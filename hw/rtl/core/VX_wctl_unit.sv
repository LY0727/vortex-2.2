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

module VX_wctl_unit import VX_gpu_pkg::*; #(
    parameter `STRING INSTANCE_ID = "",
    parameter NUM_LANES = 1
) (
    input wire              clk,
    input wire              reset,

    // Inputs
    VX_execute_if.slave     execute_if,

    // Outputs
    VX_warp_ctl_if.master   warp_ctl_if,
    VX_commit_if.master     commit_if
);
    // 这里的前三个定义，pid等还是预留的 SIMD_WIDTH < NUM_THREADS 时，SIMD执行的设计。
    // 但目前的版本 SIMD_WIDTH = NUM_THREADS，所以这些设计暂时没有实际意义，先保留接口，后续版本再完善。
    `UNUSED_SPARAM (INSTANCE_ID)
    localparam LANE_BITS  = `CLOG2(NUM_LANES);  
    localparam PID_BITS   = `CLOG2(`NUM_THREADS / NUM_LANES);
    localparam PID_WIDTH  = `UP(PID_BITS); 
    localparam WCTL_WIDTH = $bits(tmc_t) + $bits(wspawn_t) + $bits(split_t) + $bits(join_t) + $bits(barrier_t);
    localparam DATAW = `UUID_WIDTH + `NW_WIDTH + NUM_LANES + `PC_BITS + `NR_BITS + 1 + WCTL_WIDTH + PID_WIDTH + 1 + 1 + `DV_STACK_SIZEW;

    `UNUSED_VAR (execute_if.data.rs3_data)

    tmc_t       tmc, tmc_r;
    wspawn_t    wspawn, wspawn_r;
    split_t     split, split_r;
    join_t      sjoin, sjoin_r;
    barrier_t   barrier, barrier_r;

    wire is_wspawn = (execute_if.data.op_type == `INST_SFU_WSPAWN);
    wire is_tmc    = (execute_if.data.op_type == `INST_SFU_TMC);
    wire is_pred   = (execute_if.data.op_type == `INST_SFU_PRED);
    wire is_split  = (execute_if.data.op_type == `INST_SFU_SPLIT);
    wire is_join   = (execute_if.data.op_type == `INST_SFU_JOIN);
    wire is_bar    = (execute_if.data.op_type == `INST_SFU_BAR);

    // 这里有点疑问：
    wire [`UP(LANE_BITS)-1:0] tid;
    if (LANE_BITS != 0) begin
        assign tid = execute_if.data.tid[0 +: LANE_BITS];
    end else begin
        assign tid = 0;
    end

    wire [`XLEN-1:0] rs1_data = execute_if.data.rs1_data[tid];
    wire [`XLEN-1:0] rs2_data = execute_if.data.rs2_data[tid];
    `UNUSED_VAR (rs1_data)

    // not_pred 用于表示是否对 predicate 值进行取反操作，找一下这个信号的来源和意义。
    // 这个信号的含义是不是分支条件的 大于0 / 等于0 关系？如果是的话，is_neg 就是表示分支条件的极性了。
    // execute_if.data.rs1_data  是分支指令的 predicate 寄存器值。
    wire not_pred = execute_if.data.op_args.wctl.is_neg;

    wire [NUM_LANES-1:0] taken;
    for (genvar i = 0; i < NUM_LANES; ++i) begin
        assign taken[i] = (execute_if.data.rs1_data[i][0] ^ not_pred);
    end

    // then分支和else分支的线程掩码
    reg [`NUM_THREADS-1:0] then_tmask_r, then_tmask_n;
    reg [`NUM_THREADS-1:0] else_tmask_r, else_tmask_n;
    always @(*) begin
        then_tmask_n = then_tmask_r;
        else_tmask_n = else_tmask_r;
        if (execute_if.data.sop) begin
            then_tmask_n = '0;
            else_tmask_n = '0;
        end
        then_tmask_n[execute_if.data.pid * NUM_LANES +: NUM_LANES] = taken & execute_if.data.tmask;
        else_tmask_n[execute_if.data.pid * NUM_LANES +: NUM_LANES] = ~taken & execute_if.data.tmask;
    end
    always @(posedge clk) begin
        if (execute_if.valid) begin
            then_tmask_r <= then_tmask_n;
            else_tmask_r <= else_tmask_n;
        end
    end
    wire has_then = (then_tmask_n != 0);
    wire has_else = (else_tmask_n != 0);

    // tmc / pred    可以看到pred指令的反馈和TMC指令共享同一个接口。
    // tmc指令，tmask直接来自rs1_data；是指令自带的tmask。
    // pred指令，tmask来自pred_mask，是根据分支指令的predicate寄存器值计算得到的tmask。
    wire [`NUM_THREADS-1:0] pred_mask = has_then ? then_tmask_n : rs2_data[`NUM_THREADS-1:0];
    assign tmc.valid = (is_tmc || is_pred);
    assign tmc.tmask = is_pred ? pred_mask : rs1_data[`NUM_THREADS-1:0];

    // split  
    // 关键逻辑1：线程数多的分支为 taken，线程数少的分支为ntaken。
    // 关键逻辑2：split指令的next_pc = 当前指令PC + 4；也就是直接继续执行。
    //   split.next_pc 也就是后续存入ipdom的 ntaken分支的PC执行地址。
    wire [`CLOG2(`NUM_THREADS+1)-1:0] then_tmask_cnt, else_tmask_cnt;
    `POP_COUNT(then_tmask_cnt, then_tmask_n);
    `POP_COUNT(else_tmask_cnt, else_tmask_n);
    wire then_first = (then_tmask_cnt >= else_tmask_cnt);
    wire [`NUM_THREADS-1:0] taken_tmask = then_first ? then_tmask_n : else_tmask_n;
    wire [`NUM_THREADS-1:0] ntaken_tmask = then_first ? else_tmask_n : then_tmask_n;

    assign split.valid      = is_split;
    assign split.is_dvg     = has_then && has_else;  // 是否存在分歧。
    assign split.then_tmask = taken_tmask;
    assign split.else_tmask = ntaken_tmask;
    assign split.next_pc    = execute_if.data.PC + `PC_BITS'(2); // 关键逻辑！

    assign warp_ctl_if.dvstack_wid = execute_if.data.wid;
    wire [`DV_STACK_SIZEW-1:0] dvstack_ptr;

    // join   
    // join指令的输入参数是ipdom的指针，这个参数的值是对应的split指令的返回值。
    // join指令的功能是根据这个指针找到对应的split指令，然后把那个split指令的ntaken分支的线程掩码重新激活。
    assign sjoin.valid      = is_join;
    assign sjoin.stack_ptr  = rs1_data[`DV_STACK_SIZEW-1:0];  

    // barrier
    assign barrier.valid    = is_bar;
    assign barrier.id       = rs1_data[`NB_WIDTH-1:0];
`ifdef GBAR_ENABLE
    assign barrier.is_global = rs1_data[31];
`else
    assign barrier.is_global = 1'b0;
`endif
    assign barrier.size_m1  = rs2_data[$bits(barrier.size_m1)-1:0] - $bits(barrier.size_m1)'(1);
    assign barrier.is_noop  = (rs2_data[$bits(barrier.size_m1)-1:0] == $bits(barrier.size_m1)'(1)); //该bar只有这一个warp执行，也就是没有barrier的必要了，可以直接当作nop处理。

    // wspawn // 多warp并行执行软硬件上是这样一个过程：
    // 1、系统上一定会有一个warp单线程在线； 称为 warp0。
    // 2、当要激活多个warps并行执行时，warp0执行wspawn指令，激活其他warps,并配置好。这就是硬件上的wspawn指令，也就是说其执行对象不包括自己。
    // 3、软件上，warp0会执行除了以上warps负责的其他task。
    wire [`NUM_WARPS-1:0] wspawn_wmask;
    for (genvar i = 0; i < `NUM_WARPS; ++i) begin
        assign wspawn_wmask[i] = (i < rs1_data[`NW_BITS:0]) && (i != execute_if.data.wid);
    end
    assign wspawn.valid = is_wspawn;
    assign wspawn.wmask = wspawn_wmask;  // 是不包括当前warp的其他warps的掩码。
    assign wspawn.pc    = rs2_data[1 +: `PC_BITS];

    // response  打两拍到commit。
    // 如果 SIZE = 0：纯 Wire，完全没有延迟 (Bypass)。
    // 如果 SIZE = 1 或者 OUT_BUF=1：它是一个基础的带寄存器的前向缓冲，会带来 1 拍的延迟。
    // 如果 SIZE = 2：它实际上实例化了一个两项深度的 FIFO（Skid Buffer 结构）。
                // 这种结构的设计意图是为了在解耦 Ready 握手信号（即防止后级反压堵死前级）的同时，
                // 切断数据通路的组合逻辑，它引入了 1 个 Cycle 的本征前向延迟（Forward Latency）。
                // 也就是说，在没有发生反压拥堵的情况下数据流入缓冲后，下一拍就能在其输出端读取。
    VX_elastic_buffer #(
        .DATAW (DATAW),
        .SIZE  (2)   
    ) rsp_buf (
        .clk       (clk),
        .reset     (reset),
        .valid_in  (execute_if.valid),
        .ready_in  (execute_if.ready),
        .data_in   ({execute_if.data.uuid, execute_if.data.wid, execute_if.data.tmask, execute_if.data.PC, execute_if.data.rd, execute_if.data.wb, execute_if.data.pid, execute_if.data.sop, execute_if.data.eop, {tmc, wspawn, split, sjoin, barrier}, warp_ctl_if.dvstack_ptr}),
        .data_out  ({commit_if.data.uuid, commit_if.data.wid, commit_if.data.tmask, commit_if.data.PC, commit_if.data.rd, commit_if.data.wb, commit_if.data.pid, commit_if.data.sop, commit_if.data.eop, {tmc_r, wspawn_r, split_r, sjoin_r, barrier_r}, dvstack_ptr}),
        .valid_out (commit_if.valid),
        .ready_out (commit_if.ready)
    );

    assign warp_ctl_if.valid   = commit_if.valid && commit_if.ready && commit_if.data.eop;
    assign warp_ctl_if.wid     = commit_if.data.wid;
    assign warp_ctl_if.tmc     = tmc_r;
    assign warp_ctl_if.wspawn  = wspawn_r;
    assign warp_ctl_if.split   = split_r;
    assign warp_ctl_if.sjoin   = sjoin_r;
    assign warp_ctl_if.barrier = barrier_r;

    // 就是split指令的返回值，其对应的IPDOM的entry prt。
    // split指令执行，在sched模块内的 split逻辑，实际上是IPDOM的入栈操作后才得到的，然后一路反馈到这里，最后通过commit提交。
    for (genvar i = 0; i < NUM_LANES; ++i) begin
        assign commit_if.data.data[i] = `XLEN'(dvstack_ptr);
    end

endmodule
