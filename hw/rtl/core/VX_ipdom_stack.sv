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

`include "VX_platform.vh"

module VX_ipdom_stack #(
    parameter WIDTH   = 1,
    parameter DEPTH   = 1,
    parameter OUT_REG = 0,
    parameter ADDRW   = `LOG2UP(DEPTH)
) (
    input  wire             clk,
    input  wire             reset,
    input  wire [WIDTH-1:0] q0,
    input  wire [WIDTH-1:0] q1,
    output wire [WIDTH-1:0] d,     // 读出的{tmask, PC}数据
    output wire             d_set, // 0、1表示当前读出的数据是q0还是q1
    output wire [ADDRW-1:0] q_ptr, // 栈顶指针。
    input  wire             push,
    input  wire             pop,
    output wire             empty,
    output wire             full
);
    reg slot_set [DEPTH-1:0];

    reg [ADDRW-1:0] rd_ptr, wr_ptr;

    reg empty_r, full_r;

    wire [WIDTH-1:0] d0, d1;

    wire d_set_n = slot_set[rd_ptr];

    always @(posedge clk) begin
        if (reset) begin
            rd_ptr  <= '0;
            wr_ptr  <= '0;
            empty_r <= 1;
            full_r  <= 0;
        end else begin
            `ASSERT(~push || ~full, ("runtime error: writing to a full stack!"));
            `ASSERT(~pop || ~empty, ("runtime error: reading an empty stack!"));
            `ASSERT(~push || ~pop,  ("runtime error: push and pop in same cycle not supported!"));
            if (push) begin
                rd_ptr  <= wr_ptr;
                wr_ptr  <= wr_ptr + ADDRW'(1);
                empty_r <= 0;
                full_r  <= (ADDRW'(DEPTH-1) == wr_ptr);
            end else if (pop) begin
                // 注意！只有当 d_set_n == 1 时（也就是这层里第二个数据q0也被读过了），写/读指针才会递减 (-1)。
                wr_ptr  <= wr_ptr - ADDRW'(d_set_n);
                rd_ptr  <= rd_ptr - ADDRW'(d_set_n);
                empty_r <= (rd_ptr == 0) && (d_set_n == 1);
                full_r  <= 0;
            end
        end
    end
    // 实际数据
    VX_dp_ram #(
        .DATAW   (WIDTH * 2),
        .SIZE    (DEPTH),
        .OUT_REG (OUT_REG ? 1 : 0),
        .LUTRAM  (OUT_REG ? 0 : 1)
    ) store (
        .clk   (clk),
        .reset (reset),
        .read  (1'b1),
        .write (push),
        .wren  (1'b1),
        .waddr (wr_ptr),
        .wdata ({q1, q0}),  // 一起入栈。q1是else路径状态，q0是汇合点状态。
        .raddr (rd_ptr),
        .rdata ({d1, d0})   // 栈顶的输出配置为一直读出状态。
    );
    // split - join的形式，一个if-else 逻辑就是插入一条split和两条join指令（分别对应else路径和汇合点）。
    always @(posedge clk) begin
        if (push) begin
            slot_set[wr_ptr] <= 0;  // push时入栈，标记为0。表示 q0,q1都还没有被读过。
        end else if (pop) begin
            slot_set[rd_ptr] <= 1;  // 首次pop会先读取q1(else路径状态);并标记改为1，这样下次POP时就会读取q1(汇合点状态)，并且指针才会真正递减。
        end
    end

    wire d_set_r;

    VX_pipe_register #(
        .DATAW (1),
        .DEPTH (OUT_REG)
    ) pipe_reg (
        .clk      (clk),
        .reset    (reset),
        .enable   (1'b1),
        .data_in  (d_set_n),
        .data_out (d_set_r)
    );

    assign d     = d_set_r ? d0 : d1; 
    assign d_set = ~d_set_r;  
    assign q_ptr = wr_ptr;    // 注意！这里输出的是写指针，因为外部需要和这个指针比较来判断当前join指令对应的汇合点是否是当前栈顶。
    assign empty = empty_r;
    assign full  = full_r;

/*
    时序分析一下：
    1.t0周期内：push信号有效
    2.t1上升沿: {q1,q0}入栈，slot_set标记为0;读写指针加1,写指针指向空栈顶，读指针指向数据顶； dp_ram输出端{d1,d0}；
      此时d_set_n是0，但是d_set_r还是上周期的值。
    3.t2上升沿：d_set_r 更新为 0； d 输出d1(else路径状态)，d_set输出1,指示当前输出端口上是d1;
    4.t3周期内：pop信号有效
    5.t4上升沿：第一次pop；slot_set标记为1; 但是指针不改变; 因为d_set_r还是0，输出端口也都还未变，即第一次pop，端口上是d1(else路径状态).
    6.t5上升沿：d_set_r更新为1; 端口上输出d0(汇合点状态);   
    7.t6周期内：pop信号有效
    8.t7上升沿：第二次pop；

    这个时序关系其实还是有点绕的。
*/
endmodule
