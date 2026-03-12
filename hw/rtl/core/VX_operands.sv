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

// reset all GPRs in debug mode
`ifdef SIMULATION
`ifndef NDEBUG
`define GPR_RESET
`endif
`endif

module VX_operands import VX_gpu_pkg::*; #(
    parameter `STRING INSTANCE_ID = "",
    parameter NUM_BANKS = 4,
    parameter OUT_BUF   = 4 // using 2-cycle EB for area reduction
) (
    input wire              clk,
    input wire              reset,

`ifdef PERF_ENABLE
    output wire [`PERF_CTR_BITS-1:0] perf_stalls,
`endif

    VX_writeback_if.slave   writeback_if,
    VX_scoreboard_if.slave  scoreboard_if,
    VX_operands_if.master   operands_if
);
    `UNUSED_SPARAM (INSTANCE_ID)
    localparam NUM_SRC_REGS = 3;  // max number of source registers (rs1, rs2, rs3); rs3是考虑了F扩展中的FMA指令。
    localparam REQ_SEL_BITS = `CLOG2(NUM_SRC_REGS);
    localparam REQ_SEL_WIDTH = `UP(REQ_SEL_BITS);
    localparam BANK_SEL_BITS = `CLOG2(NUM_BANKS);
    localparam BANK_SEL_WIDTH = `UP(BANK_SEL_BITS);
    localparam PER_BANK_REGS = `NUM_REGS / NUM_BANKS;  // number of registers per bank
    localparam META_DATAW = ISSUE_WIS_W + `NUM_THREADS + `PC_BITS + 1 + `EX_BITS + `INST_OP_BITS + `INST_ARGS_BITS + `NR_BITS + `UUID_WIDTH;
    localparam REGS_DATAW = `XLEN * `NUM_THREADS;   // 因为所有线程执行同一指令，取通用的reg，所以直接把所有线程的相同寄存器数据放在一起。
    localparam DATAW = META_DATAW + NUM_SRC_REGS * REGS_DATAW;   // 传递到out_buf的数据宽度 = 元数据宽度 + 每个源寄存器的数据宽度 * 源寄存器数量
    localparam RAM_ADDRW = `LOG2UP(`NUM_REGS * PER_ISSUE_WARPS); // 总地址宽度 = log2（每个warp的寄存器数量 * 每个issue单元负责的warp数量）
    localparam PER_BANK_ADDRW = RAM_ADDRW - BANK_SEL_BITS;       // 每个bank的地址宽度 = 总地址宽度 - bank选择位宽度
    localparam XLEN_SIZE = `XLEN / 8;  
    localparam BYTEENW = `NUM_THREADS * XLEN_SIZE;  // REGS_DATAW的字节使能宽度

    `UNUSED_VAR (writeback_if.data.sop)
    // 1、scorebaord接口输入信号,解析出每个源寄存器的编号，并计算出对应的bank索引和bank内地址。
    wire [NUM_SRC_REGS-1:0] src_valid;
    wire [NUM_SRC_REGS-1:0] req_in_valid, req_in_ready;
    wire [NUM_SRC_REGS-1:0][PER_BANK_ADDRW-1:0] req_in_data;  // bank内的索引地址（）
    wire [NUM_SRC_REGS-1:0][BANK_SEL_WIDTH-1:0] req_bank_idx; // bank索引地址
    // 2、GPR输入输出信号
    wire [NUM_BANKS-1:0] gpr_rd_valid, gpr_rd_ready;
    wire [NUM_BANKS-1:0] gpr_rd_valid_st1, gpr_rd_valid_st2;
    wire [NUM_BANKS-1:0][PER_BANK_ADDRW-1:0] gpr_rd_addr, gpr_rd_addr_st1; // 读寄存器时的地址，已经经过xbar仲裁后的bank内地址。
    wire [NUM_BANKS-1:0][`NUM_THREADS-1:0][`XLEN-1:0] gpr_rd_data_st1, gpr_rd_data_st2;
    wire [NUM_BANKS-1:0][REQ_SEL_WIDTH-1:0] gpr_rd_req_idx, gpr_rd_req_idx_st1, gpr_rd_req_idx_st2;
    // 3、双级流水线打拍，
    // pipe1负责地址计算和bank请求的仲裁调度，
    // pipe2负责等待bank读数据返回并将数据与元数据一起传递到out_buf。
    wire pipe_valid_st1, pipe_ready_st1;
    wire pipe_valid_st2, pipe_ready_st2;
    wire [META_DATAW-1:0] pipe_data, pipe_data_st1, pipe_data_st2;
    // 4、GPR读出数据。
    reg [NUM_SRC_REGS-1:0][`NUM_THREADS-1:0][`XLEN-1:0] src_data_n;
    wire [NUM_SRC_REGS-1:0][`NUM_THREADS-1:0][`XLEN-1:0] src_data_st1, src_data_st2;
    // 5、reg数据读取完成标志
    reg [NUM_SRC_REGS-1:0] data_fetched_n;
    wire [NUM_SRC_REGS-1:0] data_fetched_st1;
    // 6、bank冲突标志
    reg has_collision_n;
    wire has_collision_st1;
    // 1、地址映射与bank寻址计算：
    //    根据scoreboard接口的数据，[操作数编号][源寄存器编号(为0说明不需要读)]
    wire [NUM_SRC_REGS-1:0][`NR_BITS-1:0] src_regs = {scoreboard_if.data.rs3,
                                                      scoreboard_if.data.rs2,
                                                      scoreboard_if.data.rs1};
    //    根据src_regs的值，计算出每个源寄存器对应的GPR地址和bank索引。  
    //    根据寄存器编号的地位分bank；根据寄存器编号的高位和wis组成地址（多warp情况）或者直接使用寄存器编号的高位作为地址（单warp情况）。
    //    可见同一个bank内：排列顺序是，多个warp的r0，在多个warp的r4，先warp编号递增，再寄存器编号递增。                                                                                                                                                      
    for (genvar i = 0; i < NUM_SRC_REGS; ++i) begin
        if (ISSUE_WIS != 0) begin
            assign req_in_data[i] = {src_regs[i][`NR_BITS-1:BANK_SEL_BITS], scoreboard_if.data.wis}; // 多warp情况，地址由寄存器编号的高位和wis组成，以支持每个issue单元负责多个warp的情况。
        end else begin
            assign req_in_data[i] = src_regs[i][`NR_BITS-1:BANK_SEL_BITS];  // 单warp情况，
        end
        if (NUM_BANKS != 1) begin
            assign req_bank_idx[i] = src_regs[i][BANK_SEL_BITS-1:0];  // 多bank情况，bank索引由寄存器编号的低位决定。
        end else begin
            assign req_bank_idx[i] = '0;
        end
    end

    for (genvar i = 0; i < NUM_SRC_REGS; ++i) begin
        assign src_valid[i] = (src_regs[i] != 0) && ~data_fetched_st1[i]; // 如果寄存器编号不为0且数据还没有fetch到位.
    end

    assign req_in_valid = {NUM_SRC_REGS{scoreboard_if.valid}} & src_valid;
    // 2、bank请求的仲裁与调度： (组合逻辑？)
    //    使用一个NUM_SRC_REGS输入、NUM_BANKS输出的交叉开关矩阵（xbar）来仲裁和调度对不同bank的请求。
    //    每个输入都是一个bank内的地址，仲裁器根据bank索引进行固定优先级仲裁，确保同一时刻只有一个请求访问同一个bank，从而避免bank冲突。
    VX_stream_xbar #(
        .NUM_INPUTS  (NUM_SRC_REGS),
        .NUM_OUTPUTS (NUM_BANKS),
        .DATAW       (PER_BANK_ADDRW),
        .ARBITER     ("P"), // use priority arbiter
        .PERF_CTR_BITS(`PERF_CTR_BITS),
        .OUT_BUF     (0) // no output buffering
    ) req_xbar (
        .clk       (clk),
        .reset     (reset),
        `UNUSED_PIN(collisions),
        .valid_in  (req_in_valid), // 3路请求的vld
        .data_in   (req_in_data),  // 3路请求的地址（已经是bank内地址了）
        .sel_in    (req_bank_idx), // 3路请求的bank索引
        .ready_in  (req_in_ready),
        .valid_out (gpr_rd_valid), // 4路bank读请求的vld
        .data_out  (gpr_rd_addr),  // 4路bank读请求的地址（bank内地址）
        .sel_out   (gpr_rd_req_idx), // 4路bank读请求的源寄存器索引（该bank 此次读哪个reg的数据）
        .ready_out (gpr_rd_ready)
    );
    // 可见是前向切割打拍逻辑
    wire pipe_in_ready = pipe_ready_st1 || ~pipe_valid_st1;

    assign gpr_rd_ready = {NUM_BANKS{pipe_in_ready}};
    // bank冲突反压scoreboard接口：当存在bank冲突时，scoreboard_if.ready为0，反之为1。
    assign scoreboard_if.ready = pipe_in_ready && ~has_collision_n;

    wire pipe_fire_st1 = pipe_valid_st1 && pipe_ready_st1; 
    wire pipe_fire_st2 = pipe_valid_st2 && pipe_ready_st2;
    // 是否存在bank冲突逻辑？  bank_idx相同且对应的src_valid都为1就说明存在bank冲突。
    always @(*) begin
        has_collision_n = 0;
        for (integer i = 0; i < NUM_SRC_REGS; ++i) begin
            for (integer j = 1; j < (NUM_SRC_REGS-i); ++j) begin
                has_collision_n |= src_valid[i]
                                && src_valid[j+i]
                                && (req_bank_idx[i] == req_bank_idx[j+i]);
            end
        end
    end
    // 数据是否已经全部fetch到位的逻辑？ 只要存在一个src_valid为1且对应的gpr_rd_valid为0，就说明数据还没有全部fetch到位。
    always @(*) begin
        data_fetched_n = data_fetched_st1;
         if (scoreboard_if.ready) begin
            data_fetched_n = '0;
        end else begin
            data_fetched_n = data_fetched_st1 | req_in_ready;
        end
    end

    assign pipe_data = {
        scoreboard_if.data.wis,
        scoreboard_if.data.tmask,
        scoreboard_if.data.PC,
        scoreboard_if.data.wb,
        scoreboard_if.data.ex_type,
        scoreboard_if.data.op_type,
        scoreboard_if.data.op_args,
        scoreboard_if.data.rd,
        scoreboard_if.data.uuid
    };
    // 第一级pipe_reg1寄存器：打拍scoreboard接口的输入信号，包括每个源寄存器的数据是否已经fetch到位的标志，以及是否存在bank冲突的标志等元数据，同时也传递bank请求的地址和索引信息到下一阶段。
    // pipe_reg1寄存器的输出信号：正式对GPR发起读请求，读出数据存放在 gpr_rd_data_st1[]中。
    // st1阶段和st2阶段之间可能要多个周期，has_collision_st1 标志这一过程。
    VX_pipe_register #(
        .DATAW  (1 + NUM_SRC_REGS + NUM_BANKS + META_DATAW + 1 + NUM_BANKS * (PER_BANK_ADDRW + REQ_SEL_WIDTH)),
        .RESETW (1 + NUM_SRC_REGS)
    ) pipe_reg1 (
        .clk      (clk),
        .reset    (reset),
        .enable   (pipe_in_ready),
        .data_in  ({scoreboard_if.valid, data_fetched_n,   gpr_rd_valid,     pipe_data,     has_collision_n,   gpr_rd_addr,     gpr_rd_req_idx}),
        .data_out ({pipe_valid_st1,      data_fetched_st1, gpr_rd_valid_st1, pipe_data_st1, has_collision_st1, gpr_rd_addr_st1, gpr_rd_req_idx_st1})
    );
    // 前向切割打拍逻辑
    assign pipe_ready_st1 = pipe_ready_st2 || ~pipe_valid_st2;
    // st2发送了清零，否则在st1阶段累计读取数据。
    assign src_data_st1 = pipe_fire_st2 ? '0 : src_data_n;
    // 也就所有数据都fetch到位了，并且没有bank冲突了，才说明第一阶段的打拍完成了，可以进入第二阶段了。
    wire pipe_valid2_st1 = pipe_valid_st1 && ~has_collision_st1;

    `RESET_RELAY (pipe2_reset, reset); // needed for pipe_reg2's wide RESETW

    VX_pipe_register #(
        .DATAW  (1 + NUM_SRC_REGS * REGS_DATAW + NUM_BANKS + NUM_BANKS * REGS_DATAW + META_DATAW + NUM_BANKS * REQ_SEL_WIDTH),
        .RESETW (1 + NUM_SRC_REGS * REGS_DATAW)
    ) pipe_reg2 (
        .clk      (clk),
        .reset    (pipe2_reset),
        .enable   (pipe_ready_st1),
        .data_in  ({pipe_valid2_st1, src_data_st1, gpr_rd_valid_st1, gpr_rd_data_st1, pipe_data_st1, gpr_rd_req_idx_st1}),
        .data_out ({pipe_valid_st2,  src_data_st2, gpr_rd_valid_st2, gpr_rd_data_st2, pipe_data_st2, gpr_rd_req_idx_st2})
    );
    // 拼装重组数据。
    always @(*) begin
        src_data_n = src_data_st2;
        for (integer b = 0; b < NUM_BANKS; ++b) begin
            // 哪个bank读出了有效数据，是为哪个源操作数读的，放到对应位置
            if (gpr_rd_valid_st2[b]) begin
                src_data_n[gpr_rd_req_idx_st2[b]] = gpr_rd_data_st2[b];
            end
        end
    end
    // st2阶段和operands_if之间的弹性缓冲区。深度为2的FIFO。
    VX_elastic_buffer #(
        .DATAW   (DATAW),
        .SIZE    (`TO_OUT_BUF_SIZE(OUT_BUF)),
        .OUT_REG (`TO_OUT_BUF_REG(OUT_BUF)),
        .LUTRAM  (1)
    ) out_buf (
        .clk       (clk),
        .reset     (reset),
        .valid_in  (pipe_valid_st2),
        .ready_in  (pipe_ready_st2),
        .data_in   ({
            pipe_data_st2,
            src_data_n[0],
            src_data_n[1],
            src_data_n[2]
        }),
        .data_out  ({
            operands_if.data.wis,
            operands_if.data.tmask,
            operands_if.data.PC,
            operands_if.data.wb,
            operands_if.data.ex_type,
            operands_if.data.op_type,
            operands_if.data.op_args,
            operands_if.data.rd,
            operands_if.data.uuid,
            operands_if.data.rs1_data,
            operands_if.data.rs2_data,
            operands_if.data.rs3_data
        }),
        .valid_out (operands_if.valid),
        .ready_out (operands_if.ready)
    );
    // 写回时的地址计算逻辑：根据writeback接口的数据，计算出需要写回的寄存器地址和bank索引。
    wire [PER_BANK_ADDRW-1:0] gpr_wr_addr;
    if (ISSUE_WIS != 0) begin
        assign gpr_wr_addr = {writeback_if.data.rd[`NR_BITS-1:BANK_SEL_BITS], writeback_if.data.wis};
    end else begin
        assign gpr_wr_addr = writeback_if.data.rd[`NR_BITS-1:BANK_SEL_BITS];
    end

    wire [BANK_SEL_WIDTH-1:0] gpr_wr_bank_idx;
    if (NUM_BANKS != 1) begin
        assign gpr_wr_bank_idx = writeback_if.data.rd[BANK_SEL_BITS-1:0];
    end else begin
        assign gpr_wr_bank_idx = '0;
    end

    `ifdef GPR_RESET
        reg wr_enabled = 0;
        always @(posedge clk) begin
            if (reset) begin
                wr_enabled <= 1;
            end
        end
    `else
        wire wr_enabled = 1;
    `endif
    // 基于dp_ram的多bank GPR设计。   （注意，同步写异步读，读数据没有周期延迟，单周期内拿到raddr出rdata）(查看源码，OUT_REG 配置为0时，读数据没有周期延迟；OUT_REG 配置为1时，读数据有一个周期的寄存器打拍延迟。)
    // 每个bank负责寄存器文件的一部分，通过地址的高位来选择bank，低位作为bank内部的地址。
    // 同时根据配置计算出写入时需要发送到GPR的地址和bank索引，并由tmask生成写使能信号。    
    for (genvar b = 0; b < NUM_BANKS; ++b) begin
        wire gpr_wr_enabled;
        if (BANK_SEL_BITS != 0) begin
            assign gpr_wr_enabled = wr_enabled
                                 && writeback_if.valid
                                 && (gpr_wr_bank_idx == BANK_SEL_BITS'(b)); // 多bank情况。
        end else begin
            assign gpr_wr_enabled = wr_enabled && writeback_if.valid;  // 单bank情况。
        end
        // 由tmask来生成写使能。
        wire [BYTEENW-1:0] wren;
        for (genvar i = 0; i < `NUM_THREADS; ++i) begin
            assign wren[i*XLEN_SIZE+:XLEN_SIZE] = {XLEN_SIZE{writeback_if.data.tmask[i]}};
        end

        VX_dp_ram #(
            .DATAW (REGS_DATAW),
            .SIZE  (PER_BANK_REGS * PER_ISSUE_WARPS), // 每个bank的寄存器数量 = 每个warp的寄存器数量 * 每个issue单元负责的warp数量
            .WRENW (BYTEENW),
         `ifdef GPR_RESET
            .RESET_RAM (1),
         `endif
            .NO_RWCHECK (1)  //不需要检测读写碰撞，scoreboard逻辑已经保证了不会出现读写同一个地址的情况。
        ) gpr_ram (
            .clk   (clk),
            .reset (reset),
            .read  (pipe_fire_st1),
            .wren  (wren),              // 只有当writeback有效且对应bank被选中时才使能写入，同时根据tmask生成字节使能信号。
            .write (gpr_wr_enabled),
            .waddr (gpr_wr_addr),
            .wdata (writeback_if.data.data),
            .raddr (gpr_rd_addr_st1[b]),
            .rdata (gpr_rd_data_st1[b])
        );
    end

`ifdef PERF_ENABLE
    reg [`PERF_CTR_BITS-1:0] collisions_r;
    always @(posedge clk) begin
        if (reset) begin
            collisions_r <= '0;
        end else begin
            collisions_r <= collisions_r + `PERF_CTR_BITS'(scoreboard_if.valid && pipe_in_ready && has_collision_n);
        end
    end
    assign perf_stalls = collisions_r;
`endif

endmodule
