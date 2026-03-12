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

module VX_scoreboard import VX_gpu_pkg::*; #(
    parameter `STRING INSTANCE_ID = ""
) (
    input wire              clk,
    input wire              reset,

`ifdef PERF_ENABLE
    output reg [`PERF_CTR_BITS-1:0] perf_stalls,
    output reg [`NUM_EX_UNITS-1:0][`PERF_CTR_BITS-1:0] perf_units_uses,
    output reg [`NUM_SFU_UNITS-1:0][`PERF_CTR_BITS-1:0] perf_sfu_uses,
`endif

    VX_writeback_if.slave   writeback_if,
    VX_ibuffer_if.slave     ibuffer_if [PER_ISSUE_WARPS],
    VX_scoreboard_if.master scoreboard_if
);
    `UNUSED_SPARAM (INSTANCE_ID)
    localparam DATAW = `UUID_WIDTH + `NUM_THREADS + `PC_BITS + `EX_BITS + `INST_OP_BITS + `INST_ARGS_BITS + (`NR_BITS * 4) + 1;

    VX_ibuffer_if staging_if [PER_ISSUE_WARPS](); // 每个warp一个深度为1的前向切割的skid buffer
    reg [PER_ISSUE_WARPS-1:0] operands_ready;     // 注意参数，每一位对应一个warp，表示该warp的指令是否所有操作数都准备好了。
//=========================================================================================
`ifdef PERF_ENABLE
    reg [PER_ISSUE_WARPS-1:0][`NUM_EX_UNITS-1:0] perf_inuse_units_per_cycle;
    wire [`NUM_EX_UNITS-1:0] perf_units_per_cycle, perf_units_per_cycle_r;

    reg [PER_ISSUE_WARPS-1:0][`NUM_SFU_UNITS-1:0] perf_inuse_sfu_per_cycle;
    wire [`NUM_SFU_UNITS-1:0] perf_sfu_per_cycle, perf_sfu_per_cycle_r;

    VX_reduce #(
        .DATAW_IN (`NUM_EX_UNITS),
        .N  (PER_ISSUE_WARPS),
        .OP ("|")
    ) perf_units_reduce (
        .data_in  (perf_inuse_units_per_cycle),
        .data_out (perf_units_per_cycle)
    );

    VX_reduce #(
        .DATAW_IN (`NUM_SFU_UNITS),
        .N  (PER_ISSUE_WARPS),
        .OP ("|")
    ) perf_sfu_reduce (
        .data_in  (perf_inuse_sfu_per_cycle),
        .data_out (perf_sfu_per_cycle)
    );

    `BUFFER_EX(perf_units_per_cycle_r, perf_units_per_cycle, 1'b1, `CDIV(PER_ISSUE_WARPS, `MAX_FANOUT));
    `BUFFER_EX(perf_sfu_per_cycle_r, perf_sfu_per_cycle, 1'b1, `CDIV(PER_ISSUE_WARPS, `MAX_FANOUT));

    wire [PER_ISSUE_WARPS-1:0] stg_valid_in;
    for (genvar w = 0; w < PER_ISSUE_WARPS; ++w) begin
        assign stg_valid_in[w] = staging_if[w].valid;
    end

    wire perf_stall_per_cycle = (|stg_valid_in) && ~(|(stg_valid_in & operands_ready));

    always @(posedge clk) begin
        if (reset) begin
            perf_stalls <= '0;
        end else begin
            perf_stalls <= perf_stalls + `PERF_CTR_BITS'(perf_stall_per_cycle);
        end
    end

    for (genvar i = 0; i < `NUM_EX_UNITS; ++i) begin
        always @(posedge clk) begin
            if (reset) begin
                perf_units_uses[i] <= '0;
            end else begin
                perf_units_uses[i] <= perf_units_uses[i] + `PERF_CTR_BITS'(perf_units_per_cycle_r[i]);
            end
        end
    end

    for (genvar i = 0; i < `NUM_SFU_UNITS; ++i) begin
        always @(posedge clk) begin
            if (reset) begin
                perf_sfu_uses[i] <= '0;
            end else begin
                perf_sfu_uses[i] <= perf_sfu_uses[i] + `PERF_CTR_BITS'(perf_sfu_per_cycle_r[i]);
            end
        end
    end
`endif
//=======================================================================================
    // 前向切割的skid buffer;  ibuffer发出到scoreboard的指令先进入这个buffer，scoreboard再从这个buffer取指令进行打分和发出。这样做的好处是：
    // 1. 可以减少scoreboard的critical path，因为scoreboard不需要直接和ibuffer对接，ibuffer的输出可以先进入这个buffer，scoreboard从这个buffer取指令，这样scoreboard的ready信号就不需要直接反馈给ibuffer，可以有更多的时间来计算ready信号。
    // 2. 可以避免scoreboard和ibuffer之间的combinational loop，因为scoreboard的ready信号不直接反馈给ibuffer，而是通过这个buffer来隔离。scoreboard的ready信号只需要反馈给这个buffer，而这个buffer的ready信号再反馈给ibuffer，这样就避免了scoreboard和ibuffer之间的直接反馈，减少了combinational loop的风险。
    for (genvar w = 0; w < PER_ISSUE_WARPS; ++w) begin
        VX_elastic_buffer #(
            .DATAW (DATAW),
            .SIZE  (1)
        ) stanging_buf (
            .clk      (clk),
            .reset    (reset),
            .valid_in (ibuffer_if[w].valid),
            .data_in  (ibuffer_if[w].data),
            .ready_in (ibuffer_if[w].ready),
            .valid_out(staging_if[w].valid),
            .data_out (staging_if[w].data),
            .ready_out(staging_if[w].ready)
        );
    end
    // 核心的scoreboard逻辑：跟踪每个warp正在使用的寄存器，判断每条指令的操作数是否准备好，以及更新寄存器的使用状态。
    // 每个warp一个独立的寄存器使用跟踪，这样可以并行地处理多个warp的指令，减少scoreboard的critical path。
    // 每个warp跟踪一个32位的inuse_regs，表示32个寄存器是否正在被使用中。当一条指令进入staging_if时，根据指令的rd、rs1、rs2、rs3查询inuse_regs，判断操作数是否准备好，并更新operands_busy。当一条指令完成写回时，根据writeback_if的数据更新inuse_regs，释放对应的寄存器。
    for (genvar w = 0; w < PER_ISSUE_WARPS; ++w) begin
        reg [`NUM_REGS-1:0] inuse_regs;  // 追踪每个寄存器是否正在被使用中，整数32，浮点32。

        reg [3:0] operands_busy, operands_busy_n;  // 追踪当前指令的4个操作数（rd、rs1、rs2、rs3）是否正在被使用中。

        wire ibuffer_fire = ibuffer_if[w].valid && ibuffer_if[w].ready; // 这是ibuffer送指令到暂存区

        wire staging_fire = staging_if[w].valid && staging_if[w].ready; // 这是暂存区的指令被scoreboard发出去了

        wire writeback_fire = writeback_if.valid
                           && (writeback_if.data.wis == ISSUE_WIS_W'(w))
                           && writeback_if.data.eop;     // eop信号是预备了SIMD迭代执行的逻辑，但目前没用。

    `ifdef PERF_ENABLE
        reg [`NUM_REGS-1:0][`EX_WIDTH-1:0] inuse_units;
        reg [`NUM_REGS-1:0][`SFU_WIDTH-1:0] inuse_sfu;

        always @(*) begin
            perf_inuse_units_per_cycle[w] = '0;
            perf_inuse_sfu_per_cycle[w] = '0;
            if (staging_if[w].valid) begin
                if (operands_busy[0]) begin
                    perf_inuse_units_per_cycle[w][inuse_units[staging_if[w].data.rd]] = 1;
                    if (inuse_units[staging_if[w].data.rd] == `EX_SFU) begin
                        perf_inuse_sfu_per_cycle[w][inuse_sfu[staging_if[w].data.rd]] = 1;
                    end
                end
                if (operands_busy[1]) begin
                    perf_inuse_units_per_cycle[w][inuse_units[staging_if[w].data.rs1]] = 1;
                    if (inuse_units[staging_if[w].data.rs1] == `EX_SFU) begin
                        perf_inuse_sfu_per_cycle[w][inuse_sfu[staging_if[w].data.rs1]] = 1;
                    end
                end
                if (operands_busy[2]) begin
                    perf_inuse_units_per_cycle[w][inuse_units[staging_if[w].data.rs2]] = 1;
                    if (inuse_units[staging_if[w].data.rs2] == `EX_SFU) begin
                        perf_inuse_sfu_per_cycle[w][inuse_sfu[staging_if[w].data.rs2]] = 1;
                    end
                end
                if (operands_busy[3]) begin
                    perf_inuse_units_per_cycle[w][inuse_units[staging_if[w].data.rs3]] = 1;
                    if (inuse_units[staging_if[w].data.rs3] == `EX_SFU) begin
                        perf_inuse_sfu_per_cycle[w][inuse_sfu[staging_if[w].data.rs3]] = 1;
                    end
                end
            end
        end
    `endif
        // 当前指令操作数就绪情况更新逻辑。 
        // 1. ibuffer发出新指令：operands_busy_n 更新为该指令的操作数寄存器的 inuse_regs 状态。
        // 2. writeback发出指令完成信号 && ibuffer发出新指令:  写回的RD寄存器的 inuse_regs 状态更新到 operands_busy_n 中对应的操作数位上，前提是写回的寄存器和当前指令的操作数寄存器匹配。
        // 3. writeback发出指令完成信号 && 没有ibuffer发出新指令:  写回的RD寄存器的 inuse_regs 状态更新到 operands_busy_n 中对应的操作数位上，前提是写回的寄存器和当前暂存区指令的操作数寄存器匹配。
        // 4. staging_if发出指令 && 该指令需要写回寄存器:  将暂存区指令的RD寄存器标记为正在使用中，前提是暂存区指令的RD寄存器和当前指令的操作数寄存器匹配。
        always @(*) begin
            operands_busy_n = operands_busy;
            if (ibuffer_fire) begin
                operands_busy_n = {
                    inuse_regs[ibuffer_if[w].data.rs3],
                    inuse_regs[ibuffer_if[w].data.rs2],
                    inuse_regs[ibuffer_if[w].data.rs1],
                    inuse_regs[ibuffer_if[w].data.rd]
                };
            end
            if (writeback_fire) begin
                if (ibuffer_fire) begin
                    if (writeback_if.data.rd == ibuffer_if[w].data.rd) begin
                        operands_busy_n[0] = 0;
                    end
                    if (writeback_if.data.rd == ibuffer_if[w].data.rs1) begin
                        operands_busy_n[1] = 0;
                    end
                    if (writeback_if.data.rd == ibuffer_if[w].data.rs2) begin
                        operands_busy_n[2] = 0;
                    end
                    if (writeback_if.data.rd == ibuffer_if[w].data.rs3) begin
                        operands_busy_n[3] = 0;
                    end
                end else begin
                    if (writeback_if.data.rd == staging_if[w].data.rd) begin
                        operands_busy_n[0] = 0;
                    end
                    if (writeback_if.data.rd == staging_if[w].data.rs1) begin
                        operands_busy_n[1] = 0;
                    end
                    if (writeback_if.data.rd == staging_if[w].data.rs2) begin
                        operands_busy_n[2] = 0;
                    end
                    if (writeback_if.data.rd == staging_if[w].data.rs3) begin
                        operands_busy_n[3] = 0;
                    end
                end
            end
            if (staging_fire && staging_if[w].data.wb) begin
                if (staging_if[w].data.rd == ibuffer_if[w].data.rd) begin
                    operands_busy_n[0] = 1;
                end
                if (staging_if[w].data.rd == ibuffer_if[w].data.rs1) begin
                    operands_busy_n[1] = 1;
                end
                if (staging_if[w].data.rd == ibuffer_if[w].data.rs2) begin
                    operands_busy_n[2] = 1;
                end
                if (staging_if[w].data.rd == ibuffer_if[w].data.rs3) begin
                    operands_busy_n[3] = 1;
                end
            end
        end
        // 寄存器状态更新逻辑
        always @(posedge clk) begin
            if (reset) begin
                inuse_regs <= '0;
            end else begin
                // 后面的流水线算完并写回数据了，对应寄存器解除占用状态。
                if (writeback_fire) begin
                    inuse_regs[writeback_if.data.rd] <= 0;
                end
                // 当这条暂存区的指令被发射出去了，并且它确实要写回寄存器(wb==1)，就把目的寄存器标记为"忙碌"！
                if (staging_fire && staging_if[w].data.wb) begin
                    inuse_regs[staging_if[w].data.rd] <= 1;
                end
            end
            operands_busy <= operands_busy_n;
            operands_ready[w] <= ~(| operands_busy_n);
        `ifdef PERF_ENABLE
            if (staging_fire && staging_if[w].data.wb) begin
                inuse_units[staging_if[w].data.rd] <= staging_if[w].data.ex_type;
                if (staging_if[w].data.ex_type == `EX_SFU) begin
                    inuse_sfu[staging_if[w].data.rd] <= op_to_sfu_type(staging_if[w].data.op_type);
                end
            end
        `endif
        end
//============================================================================================
    `ifdef SIMULATION
        reg [31:0] timeout_ctr;

        always @(posedge clk) begin
            if (reset) begin
                timeout_ctr <= '0;
            end else begin
                if (staging_if[w].valid && ~staging_if[w].ready) begin
                `ifdef DBG_TRACE_PIPELINE
                    `TRACE(3, ("%d: *** %s-stall: wid=%0d, PC=0x%0h, tmask=%b, cycles=%0d, inuse=%b (#%0d)\n",
                        $time, INSTANCE_ID, w, {staging_if[w].data.PC, 1'b0}, staging_if[w].data.tmask, timeout_ctr,
                        operands_busy, staging_if[w].data.uuid));
                `endif
                    timeout_ctr <= timeout_ctr + 1;
                end else if (ibuffer_fire) begin
                    timeout_ctr <= '0;
                end
            end
        end

        `RUNTIME_ASSERT((timeout_ctr < `STALL_TIMEOUT),
                        ("%t: *** %s timeout: wid=%0d, PC=0x%0h, tmask=%b, cycles=%0d, inuse=%b (#%0d)",
                            $time, INSTANCE_ID, w, {staging_if[w].data.PC, 1'b0}, staging_if[w].data.tmask, timeout_ctr,
                            operands_busy, staging_if[w].data.uuid));

        `RUNTIME_ASSERT(~writeback_fire || inuse_regs[writeback_if.data.rd] != 0,
            ("%t: *** %s invalid writeback register: wid=%0d, PC=0x%0h, tmask=%b, rd=%0d (#%0d)",
                $time, INSTANCE_ID, w, {writeback_if.data.PC, 1'b0}, writeback_if.data.tmask, writeback_if.data.rd, writeback_if.data.uuid));
    `endif
//============================================================================================
    end

    wire [PER_ISSUE_WARPS-1:0] arb_valid_in;
    wire [PER_ISSUE_WARPS-1:0][DATAW-1:0] arb_data_in;
    wire [PER_ISSUE_WARPS-1:0] arb_ready_in;

    for (genvar w = 0; w < PER_ISSUE_WARPS; ++w) begin
        assign arb_valid_in[w] = staging_if[w].valid && operands_ready[w];  // 暂存区有数据 && 操作数都已有效
        assign arb_data_in[w] = staging_if[w].data;
        assign staging_if[w].ready = arb_ready_in[w] && operands_ready[w];  // 仲裁器准备好了接受 && 操作数都已有效
    end

    `RESET_RELAY (arb_reset, reset);

    VX_stream_arb #(
        .NUM_INPUTS (PER_ISSUE_WARPS),
        .DATAW      (DATAW),
        .ARBITER    ("F"),  // 公平仲裁，轮流给每个warp发射指令，避免某个warp长期得不到调度。
        .LUTRAM     (1),
        .OUT_BUF    (4) // using 2-cycle EB for area reduction
    ) out_arb (
        .clk      (clk),
        .reset    (arb_reset),
        .valid_in (arb_valid_in),
        .ready_in (arb_ready_in),
        .data_in  (arb_data_in),
        .data_out ({
            scoreboard_if.data.uuid,
            scoreboard_if.data.tmask,
            scoreboard_if.data.PC,
            scoreboard_if.data.ex_type,
            scoreboard_if.data.op_type,
            scoreboard_if.data.op_args,
            scoreboard_if.data.wb,
            scoreboard_if.data.rd,
            scoreboard_if.data.rs1,
            scoreboard_if.data.rs2,
            scoreboard_if.data.rs3
        }),
        .valid_out (scoreboard_if.valid),
        .ready_out (scoreboard_if.ready),
        .sel_out   (scoreboard_if.data.wis)
    );

endmodule
