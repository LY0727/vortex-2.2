// Copyright © 2019-2023
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

`include "VX_define.vh"

module VX_split_join import VX_gpu_pkg::*; #(
    parameter `STRING INSTANCE_ID = ""
) (
    input  wire                     clk,
    input  wire                     reset,
    input  wire                     valid,
    input  wire [`NW_WIDTH-1:0]     wid,
    input  split_t                  split,
    input  join_t                   sjoin,
    output wire                     join_valid,
    output wire                     join_is_dvg,
    output wire                     join_is_else,
    output wire [`NW_WIDTH-1:0]     join_wid,
    output wire [`NUM_THREADS-1:0]  join_tmask,
    output wire [`PC_BITS-1:0]      join_pc,
    input  wire [`NW_WIDTH-1:0]     stack_wid,
    output wire [`DV_STACK_SIZEW-1:0] stack_ptr
);
    `UNUSED_SPARAM (INSTANCE_ID)
    // 每个warp维护一个IPDOM栈。
    wire [(`NUM_THREADS+`PC_BITS)-1:0] ipdom_data [`NUM_WARPS-1:0];
    wire [`DV_STACK_SIZEW-1:0] ipdom_q_ptr [`NUM_WARPS-1:0];
    wire ipdom_set [`NUM_WARPS-1:0];
    // q0：汇合点 (Join / Reconvergence Point)：所有参加此次分支的线程掩码，以及汇合后的 PC 。
    //     (此处占位为 0，因为 Vortex 实现中是由汇合点的 join 指令自带继续往下走的机制)
    // q1: 另一条分支 (Else 路径)：暂时不走的分支掩码，以及它的 PC (next_pc)
    wire [(`NUM_THREADS+`PC_BITS)-1:0] ipdom_q0 = {split.then_tmask | split.else_tmask, `PC_BITS'(0)};
    wire [(`NUM_THREADS+`PC_BITS)-1:0] ipdom_q1 = {split.else_tmask, split.next_pc};
    // 因为有的join只是假动作或者说warp本身没有发散，所以需要判断。   
    // sjoin传过来的stack_ptr和当前栈顶指针比较，不相等说明此前有对应的push，发生过真发散；如果想到说明之前的split指令没有发散。
    wire sjoin_is_dvg = (sjoin.stack_ptr != ipdom_q_ptr[wid]);
    // 
    wire ipdom_push = valid && split.valid && split.is_dvg;
    wire ipdom_pop = valid && sjoin.valid && sjoin_is_dvg;

    for (genvar i = 0; i < `NUM_WARPS; ++i) begin

        `RESET_RELAY (ipdom_reset, reset);

        VX_ipdom_stack #(
            .WIDTH (`NUM_THREADS+`PC_BITS),
            .DEPTH (`DV_STACK_SIZE)
        ) ipdom_stack (
            .clk   (clk),
            .reset (ipdom_reset),
            .q0    (ipdom_q0),      // 入栈：汇合点状态    （底层），可以看到只是会合tmask，PC部分占位为0  
            .q1    (ipdom_q1),      // 入栈：Else 路径状态 （顶层），包含Else路径的tmask和PC
            .d     (ipdom_data[i]), // 出栈：当前活跃状态数据 {tmask, PC}
            .d_set (ipdom_set[i]),  // 出栈：判断当前出栈的是q0还是q1； 1就是q1，0就是q0
            .q_ptr (ipdom_q_ptr[i]),// out:  当前栈顶指针
            .push  (ipdom_push && (i == wid)),  // push和pop信号只对当前warp对应的栈有效
            .pop   (ipdom_pop && (i == wid)),   
            `UNUSED_PIN (empty),
            `UNUSED_PIN (full)
        );
    end

    VX_pipe_register #(
        .DATAW  (1 + 1 + 1 + `NW_WIDTH + `NUM_THREADS + `PC_BITS),
        .DEPTH  (1),
        .RESETW (1)
    ) pipe_reg (
        .clk      (clk),
        .reset    (reset),
        .enable   (1'b1),
        .data_in  ({valid && sjoin.valid, sjoin_is_dvg, ipdom_set[wid], wid, ipdom_data[wid]}),
        .data_out ({join_valid, join_is_dvg, join_is_else, join_wid, {join_tmask, join_pc}})
    );

    assign stack_ptr = ipdom_q_ptr[stack_wid];


endmodule


// 1.发生发散 (Split 指令)

//     push = 1。 wdata 接收到 {q1(Else数据), q0(汇合点数据)} 写入栈的深度 N 个位置。
//     指针 wr_ptr = N+1, rd_ptr = N。
//     slot_set[N] 设置为 0。（此层标记=0，表示下一次读取q1）
// 2.Then 分支走完 (遇到第一个 Join 指令)

//     发起一次 pop = 1。
//     此时当前读取的是栈顶深度 N 对应的数据。因为 d_set_n 是 slot_set[N] 等于 0，所以读出的数据 d 会拿到 d1 (也就是 Else 的状态 q1)。
//     由于此时 d_set_n == 0，指针递减 - 0，所以读写指针不减！依然停留在 N！
//     同一个时钟周期触发 slot_set[N] <= 1。标记这一层的上半部分已经被读走了。
//     结果：调度器收到了 Else的掩码和PC，开始执行Else路径。
// 3.Else 分支也走完 (遇到第二个 Join 指令)

//     发起第二次 pop = 1。
//     读取依然是栈顶深度 N。但这次 d_set_n 变成了 1（因为上次被覆盖了）。输出数据 d 拿到了 d0（也就是 重收敛汇合点的状态 q0，拥有全部存活线程的掩码）。
//     **由于此时 d_set_n == 1，指针发生真实的递减 - 1！读写指针下移退回到 N-1。**这一层的数据才被清空抹除。
//     结果：调度器成功拿回了当初由于遇到发散而暂时屏蔽掉的线程，大家合体，重新用一个统一完整的掩码往下取指令！
