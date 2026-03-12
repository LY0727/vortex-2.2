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

module VX_commit import VX_gpu_pkg::*, VX_trace_pkg::*; #(
    parameter `STRING INSTANCE_ID = ""
) (
    input wire              clk,
    input wire              reset,

    // inputs
    VX_commit_if.slave      commit_if [`NUM_EX_UNITS * `ISSUE_WIDTH], // 输出是每个执行单元的commit接口，commit单元需要从这些接口中仲裁出最终的commit结果

    // outputs
    VX_writeback_if.master  writeback_if  [`ISSUE_WIDTH], // commit单元的输出是每个issue的writeback接口，commit单元需要将仲裁出的commit结果发送到对应的writeback接口
    VX_commit_csr_if.master commit_csr_if,    // 更新CSR寄存器的接口，这里只设计了一个功能：instret计数器的更新，commit单元需要将每个周期提交的指令数量发送到这个接口，以便更新instret寄存器
    VX_commit_sched_if.master commit_sched_if // 将提交指令的warp id 发生到调度器接口。
);
    `UNUSED_SPARAM(INSTANCE_ID)
    localparam DATAW = `UUID_WIDTH + `NW_WIDTH + `NUM_THREADS + `PC_BITS + 1 + `NR_BITS + `NUM_THREADS * `XLEN + 1 + 1 + 1;
    localparam COMMIT_SIZEW = `CLOG2(`NUM_THREADS + 1);
    localparam COMMIT_ALL_SIZEW = COMMIT_SIZEW + `ISSUE_WIDTH - 1;

    // commit arbitration 

    VX_commit_if commit_arb_if[`ISSUE_WIDTH]();

    wire [`ISSUE_WIDTH-1:0] per_issue_commit_fire;
    wire [`ISSUE_WIDTH-1:0][`NW_WIDTH-1:0] per_issue_commit_wid;
    wire [`ISSUE_WIDTH-1:0][`NUM_THREADS-1:0] per_issue_commit_tmask;
    wire [`ISSUE_WIDTH-1:0] per_issue_commit_eop;  // simd迭代执行机制时使用。

    for (genvar i = 0; i < `ISSUE_WIDTH; ++i) begin
        // 每个执行单元的commit接口都是并行的，commit单元需要对它们进行仲裁，
        // 选出每个周期最终要提交的指令。这里使用了一个简单的轮询仲裁器，低位优先。
        wire [`NUM_EX_UNITS-1:0]            valid_in;
        wire [`NUM_EX_UNITS-1:0][DATAW-1:0] data_in;
        wire [`NUM_EX_UNITS-1:0]            ready_in;

        for (genvar j = 0; j < `NUM_EX_UNITS; ++j) begin
            assign valid_in[j] = commit_if[j * `ISSUE_WIDTH + i].valid;
            assign data_in[j]  = commit_if[j * `ISSUE_WIDTH + i].data;
            assign commit_if[j * `ISSUE_WIDTH + i].ready = ready_in[j];
        end

        `RESET_RELAY (arb_reset, reset);

        VX_stream_arb #(
            .NUM_INPUTS (`NUM_EX_UNITS),
            .DATAW      (DATAW),
            .ARBITER    ("R"),
            .OUT_BUF    (1)
        ) commit_arb (
            .clk        (clk),
            .reset      (arb_reset),
            .valid_in   (valid_in),
            .ready_in   (ready_in),
            .data_in    (data_in),
            .data_out   (commit_arb_if[i].data),
            .valid_out  (commit_arb_if[i].valid),
            .ready_out  (commit_arb_if[i].ready),
            `UNUSED_PIN (sel_out)
        );

        assign per_issue_commit_fire[i] = commit_arb_if[i].valid && commit_arb_if[i].ready;
        assign per_issue_commit_tmask[i]= {`NUM_THREADS{per_issue_commit_fire[i]}} & commit_arb_if[i].data.tmask;
        assign per_issue_commit_wid[i]  = commit_arb_if[i].data.wid;
        assign per_issue_commit_eop[i]  = commit_arb_if[i].data.eop;
    end

    // CSRs update     （这条数据路径，延迟 4 cycle）
    // 更新commit_csr_if.instret： 每个硬件threads执行提交指令的次数的总和。  可以理解，对比一个单线程CPU要提交指令的次数总和。
    // 分三步计算：
    // st1: 计算每个issue提交的指令数量，并寄存器化。 这里的指令数量是指每个issue提交的指令中有多少个线程在执行。 这个数量在commit阶段是可以直接计算出来的，因为commit接口中已经包含了每条指令的线程掩码了。
    // st2：将每个issue提交的指令数量进行累加，得到这次提交的指令总数量。 这里使用了一个树形结构的加法器，先两两相加，再将结果相加，直到得到最终的总和。
    // st3: 将st2计算出来的值寄存器化，得到最终的提交指令总数量。 这里寄存器化的目的是为了和commit指令的提交保持同步，因为commit接口是有一个周期的延迟的，所以需要寄存器化来对齐。
    wire [`ISSUE_WIDTH-1:0][COMMIT_SIZEW-1:0] commit_size, commit_size_r;
    wire [COMMIT_ALL_SIZEW-1:0] commit_size_all_r, commit_size_all_rr;
    wire commit_fire_any, commit_fire_any_r, commit_fire_any_rr;

    assign commit_fire_any = (| per_issue_commit_fire); // 是否有提交
    // st1: 计算每个issue提交的指令数量，并寄存器化。
    for (genvar i = 0; i < `ISSUE_WIDTH; ++i) begin
        wire [COMMIT_SIZEW-1:0] count;
        `POP_COUNT(count, per_issue_commit_tmask[i]);
        assign commit_size[i] = count;   // 这次提交的指令有 count 个thread在执行。
    end
    
    VX_pipe_register #(
        .DATAW  (1 + `ISSUE_WIDTH * COMMIT_SIZEW),
        .RESETW (1)
    ) commit_size_reg1 (
        .clk      (clk),
        .reset    (reset),
        .enable   (1'b1),
        .data_in  ({commit_fire_any, commit_size}),
        .data_out ({commit_fire_any_r, commit_size_r})
    );
    // st2： 将每个issue提交的指令数量进行累加，得到这次提交的指令总数量。 这里使用了一个树形结构的加法器，先两两相加，再将结果相加，直到得到最终的总和。
    VX_reduce #(
        .DATAW_IN (COMMIT_SIZEW),
        .DATAW_OUT (COMMIT_ALL_SIZEW),
        .N  (`ISSUE_WIDTH),
        .OP ("+")
    ) commit_size_reduce (
        .data_in  (commit_size_r),
        .data_out (commit_size_all_r)
    );

    VX_pipe_register #(
        .DATAW  (1 + COMMIT_ALL_SIZEW),
        .RESETW (1)
    ) commit_size_reg2 (
        .clk      (clk),
        .reset    (reset),
        .enable   (1'b1),
        .data_in  ({commit_fire_any_r, commit_size_all_r}),
        .data_out ({commit_fire_any_rr, commit_size_all_rr})
    );
    // st3: 将st2计算出来的值寄存器化，得到最终的提交指令总数量
    reg [`PERF_CTR_BITS-1:0] instret;
    always @(posedge clk) begin
       if (reset) begin
            instret <= '0;
        end else begin
            if (commit_fire_any_rr) begin
                instret <= instret + `PERF_CTR_BITS'(commit_size_all_rr);
            end
        end
    end
    assign commit_csr_if.instret = instret;  // 给到csr后，其实还要一个周期才能更新到CSR寄存器中。

    // Track committed instructions

    reg [`NUM_WARPS-1:0] committed_warps;

    always @(*) begin
        committed_warps = 0;
        for (integer i = 0; i < `ISSUE_WIDTH; ++i) begin
            if (per_issue_commit_fire[i] && per_issue_commit_eop[i]) begin
                committed_warps[per_issue_commit_wid[i]] = 1;
            end
        end
    end
    // 一拍 + arb一拍，到commit_sched_if的周期是两拍。
    VX_pipe_register #(
        .DATAW  (`NUM_WARPS),
        .RESETW (`NUM_WARPS)
    ) committed_pipe_reg (
        .clk      (clk),
        .reset    (reset),
        .enable   (1'b1),
        .data_in  (committed_warps),
        .data_out ({commit_sched_if.committed_warps})   // 将提交指令的warp id 发生到调度器接口。 这里的设计是每个周期提交了指令的warp id都会被记录下来，并在下一个周期提供给调度器使用。
    );

    // Writeback  这条数据路径，延迟 1cycle.  只有arb的一拍。

    for (genvar i = 0; i < `ISSUE_WIDTH; ++i) begin
        assign writeback_if[i].valid     = commit_arb_if[i].valid && commit_arb_if[i].data.wb;
        assign writeback_if[i].data.uuid = commit_arb_if[i].data.uuid;
        assign writeback_if[i].data.wis  = wid_to_wis(commit_arb_if[i].data.wid);
        assign writeback_if[i].data.PC   = commit_arb_if[i].data.PC;
        assign writeback_if[i].data.tmask= commit_arb_if[i].data.tmask;
        assign writeback_if[i].data.rd   = commit_arb_if[i].data.rd;
        assign writeback_if[i].data.data = commit_arb_if[i].data.data;
        assign writeback_if[i].data.sop  = commit_arb_if[i].data.sop;
        assign writeback_if[i].data.eop  = commit_arb_if[i].data.eop;
        assign commit_arb_if[i].ready = 1'b1; // writeback has no backpressure  //得益于scoreboard的设计。
    end

`ifdef DBG_TRACE_PIPELINE
    for (genvar i = 0; i < `ISSUE_WIDTH; ++i) begin
        for (genvar j = 0; j < `NUM_EX_UNITS; ++j) begin
            always @(posedge clk) begin
                if (commit_if[j * `ISSUE_WIDTH + i].valid && commit_if[j * `ISSUE_WIDTH + i].ready) begin
                    `TRACE(1, ("%d: %s: wid=%0d, PC=0x%0h, ex=", $time, INSTANCE_ID, commit_if[j * `ISSUE_WIDTH + i].data.wid, {commit_if[j * `ISSUE_WIDTH + i].data.PC, 1'b0}));
                    trace_ex_type(1, j);
                    `TRACE(1, (", tmask=%b, wb=%0d, rd=%0d, sop=%b, eop=%b, data=", commit_if[j * `ISSUE_WIDTH + i].data.tmask, commit_if[j * `ISSUE_WIDTH + i].data.wb, commit_if[j * `ISSUE_WIDTH + i].data.rd, commit_if[j * `ISSUE_WIDTH + i].data.sop, commit_if[j * `ISSUE_WIDTH + i].data.eop));
                    `TRACE_ARRAY1D(1, "0x%0h", commit_if[j * `ISSUE_WIDTH + i].data.data, `NUM_THREADS);
                    `TRACE(1, (" (#%0d)\n", commit_if[j * `ISSUE_WIDTH + i].data.uuid));
                end
            end
        end
    end
`endif

endmodule
