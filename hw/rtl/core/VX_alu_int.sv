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

module VX_alu_int #(
    parameter `STRING INSTANCE_ID = "",
    parameter BLOCK_IDX = 0,
    parameter NUM_LANES = 1
) (
    input wire              clk,
    input wire              reset,

    // Inputs
    VX_execute_if.slave     execute_if,

    // Outputs
    VX_commit_if.master     commit_if,    // execute_if 的结果会被前向切割寄存器打一拍后送到 commit_if
    VX_branch_ctl_if.master branch_ctl_if // execute -> commit -> branch_ctl_if，需要两拍才会到schedule。
);

    `UNUSED_SPARAM (INSTANCE_ID)
    localparam LANE_BITS      = `CLOG2(NUM_LANES);
    localparam LANE_WIDTH     = `UP(LANE_BITS);
    localparam PID_BITS       = `CLOG2(`NUM_THREADS / NUM_LANES);
    localparam PID_WIDTH      = `UP(PID_BITS);
    localparam SHIFT_IMM_BITS = `CLOG2(`XLEN);

    `UNUSED_VAR (execute_if.data.rs3_data)
    // 多lane 并行执行
    wire [NUM_LANES-1:0][`XLEN-1:0] add_result;     // ADD, LUI, AUIPC result
    wire [NUM_LANES-1:0][`XLEN:0]   sub_result;     // +1 bit for branch compare; SUB result
    reg  [NUM_LANES-1:0][`XLEN-1:0] shr_zic_result; // shift and CZERO result
    reg  [NUM_LANES-1:0][`XLEN-1:0] msc_result;     // AND, OR, XOR, SLL result

    wire [NUM_LANES-1:0][`XLEN-1:0] add_result_w;   
    wire [NUM_LANES-1:0][`XLEN-1:0] sub_result_w;
    wire [NUM_LANES-1:0][`XLEN-1:0] shr_result_w;
    reg  [NUM_LANES-1:0][`XLEN-1:0] msc_result_w;

    reg [NUM_LANES-1:0][`XLEN-1:0] alu_result;
    wire [NUM_LANES-1:0][`XLEN-1:0] alu_result_r;

`ifdef XLEN_64
    wire is_alu_w = execute_if.data.op_args.alu.is_w;
`else
    wire is_alu_w = 0;
`endif

    wire [`INST_ALU_BITS-1:0] alu_op = `INST_ALU_BITS'(execute_if.data.op_type);
    wire [`INST_BR_BITS-1:0]   br_op = `INST_BR_BITS'(execute_if.data.op_type);
    wire                    is_br_op = (execute_if.data.op_args.alu.xtype == `ALU_TYPE_BRANCH);
    wire                   is_sub_op = `INST_ALU_IS_SUB(alu_op);
    wire                   is_signed = `INST_ALU_SIGNED(alu_op);
    wire [1:0]              op_class = is_br_op ? `INST_BR_CLASS(alu_op) : `INST_ALU_CLASS(alu_op);
    // 使用rs1和rs2作为ALU输入，还是使用PC和立即数，取决于指令类型和具体指令的要求
    wire [NUM_LANES-1:0][`XLEN-1:0] alu_in1 = execute_if.data.rs1_data;
    wire [NUM_LANES-1:0][`XLEN-1:0] alu_in2 = execute_if.data.rs2_data;

    wire [NUM_LANES-1:0][`XLEN-1:0] alu_in1_PC  = execute_if.data.op_args.alu.use_PC ? {NUM_LANES{execute_if.data.PC, 1'd0}} : alu_in1;
    wire [NUM_LANES-1:0][`XLEN-1:0] alu_in2_imm = execute_if.data.op_args.alu.use_imm ? {NUM_LANES{`SEXT(`XLEN, execute_if.data.op_args.alu.imm)}} : alu_in2;
    wire [NUM_LANES-1:0][`XLEN-1:0] alu_in2_br  = (execute_if.data.op_args.alu.use_imm && ~is_br_op) ? {NUM_LANES{`SEXT(`XLEN, execute_if.data.op_args.alu.imm)}} : alu_in2;
    // 加法和减法的实现，考虑了是否使用PC和立即数，以及是否有符号扩展
    for (genvar i = 0; i < NUM_LANES; ++i) begin
        assign add_result[i] = alu_in1_PC[i] + alu_in2_imm[i];
        assign add_result_w[i] = `XLEN'($signed(alu_in1[i][31:0] + alu_in2_imm[i][31:0]));
    end

    for (genvar i = 0; i < NUM_LANES; ++i) begin
        wire [`XLEN:0] sub_in1 = {is_signed & alu_in1[i][`XLEN-1], alu_in1[i]};
        wire [`XLEN:0] sub_in2 = {is_signed & alu_in2_br[i][`XLEN-1], alu_in2_br[i]};
        assign sub_result[i] = sub_in1 - sub_in2;
        assign sub_result_w[i] = `XLEN'($signed(alu_in1[i][31:0] - alu_in2_imm[i][31:0]));
    end
    // 逻辑右移和算术右移的实现，考虑了是否有符号扩展，以及CZERO指令的特殊处理
    for (genvar i = 0; i < NUM_LANES; ++i) begin
        wire [`XLEN:0] shr_in1 = {is_signed && alu_in1[i][`XLEN-1], alu_in1[i]};
        always @(*) begin
            case (alu_op[1:0])
            `ifdef EXT_ZICOND_ENABLE
                2'b10, 2'b11: begin // CZERO
                    shr_zic_result[i] = alu_in1[i] & {`XLEN{alu_op[0] ^ (| alu_in2[i])}};
                end
            `endif
                default: begin // SRL, SRA, SRLI, SRAI
                    shr_zic_result[i] = `XLEN'($signed(shr_in1) >>> alu_in2_imm[i][SHIFT_IMM_BITS-1:0]);
                end
            endcase
        end
        wire [32:0] shr_in1_w = {is_signed && alu_in1[i][31], alu_in1[i][31:0]};
        wire [31:0] shr_res_w = 32'($signed(shr_in1_w) >>> alu_in2_imm[i][4:0]);
        assign shr_result_w[i] = `XLEN'($signed(shr_res_w));
    end
    // 逻辑运算和移位的实现，使用了case语句根据具体的操作类型选择对应的计算结果
    for (genvar i = 0; i < NUM_LANES; ++i) begin
        always @(*) begin
            case (alu_op[1:0])
                2'b00: msc_result[i] = alu_in1[i] & alu_in2_imm[i]; // AND
                2'b01: msc_result[i] = alu_in1[i] | alu_in2_imm[i]; // OR
                2'b10: msc_result[i] = alu_in1[i] ^ alu_in2_imm[i]; // XOR
                2'b11: msc_result[i] = alu_in1[i] << alu_in2_imm[i][SHIFT_IMM_BITS-1:0]; // SLL
            endcase
        end
        assign msc_result_w[i] = `XLEN'($signed(alu_in1[i][31:0] << alu_in2_imm[i][4:0])); // SLLW
    end
    // 最终的ALU结果选择，根据指令类型和操作类型从不同的计算结果中选择正确的结果输出
    for (genvar i = 0; i < NUM_LANES; ++i) begin
        wire [`XLEN-1:0] slt_br_result = `XLEN'({is_br_op && ~(| sub_result[i][`XLEN-1:0]), sub_result[i][`XLEN]});
        wire [`XLEN-1:0] sub_slt_br_result = (is_sub_op && ~is_br_op) ? sub_result[i][`XLEN-1:0] : slt_br_result;
        always @(*) begin
            case ({is_alu_w, op_class})
                3'b000: alu_result[i] = add_result[i];      // ADD, LUI, AUIPC
                3'b001: alu_result[i] = sub_slt_br_result;  // SUB, SLTU, SLTI, BR*
                3'b010: alu_result[i] = shr_zic_result[i];  // SRL, SRA, SRLI, SRAI, CZERO*
                3'b011: alu_result[i] = msc_result[i];      // AND, OR, XOR, SLL, SLLI
                3'b100: alu_result[i] = add_result_w[i];    // ADDIW, ADDW
                3'b101: alu_result[i] = sub_result_w[i];    // SUBW
                3'b110: alu_result[i] = shr_result_w[i];    // SRLW, SRAW, SRLIW, SRAIW
                3'b111: alu_result[i] = msc_result_w[i];    // SLLW
            endcase
        end
    end

    // branch

    wire [`PC_BITS-1:0] PC_r;  // 32bits
    wire [`INST_BR_BITS-1:0] br_op_r;           // 分支指令的具体类型，如BEQ、BNE、BLT等
    wire [`PC_BITS-1:0] cbr_dest, cbr_dest_r;   // 条件分支的目标地址
    wire [LANE_WIDTH-1:0] tid, tid_r;           // 线程ID，表示当前执行的指令属于哪个线程
    wire is_br_op_r;                            // 是否是分支指令
    // 对于分支指令，ALU计算出的结果中包含了分支目标地址的信息。
    // 分支指令，每个thread都会执行，直接复用了lane 0 的部分结果位来存储条件分支的目标地址，以节省寄存器资源。
    assign cbr_dest = add_result[0][1 +: `PC_BITS];

    if (LANE_BITS != 0) begin
        assign tid = execute_if.data.tid[0 +: LANE_BITS];
    end else begin
        assign tid = 0;
    end
    // 一拍的前向切割寄存器。
    VX_elastic_buffer #(
        .DATAW (`UUID_WIDTH + `NW_WIDTH + NUM_LANES + `NR_BITS + 1 + PID_WIDTH + 1 + 1 + (NUM_LANES * `XLEN) + `PC_BITS + `PC_BITS + 1 + `INST_BR_BITS + LANE_WIDTH)
    ) rsp_buf (
        .clk      (clk),
        .reset    (reset),
        .valid_in (execute_if.valid),
        .ready_in (execute_if.ready),
        .data_in  ({execute_if.data.uuid, execute_if.data.wid, execute_if.data.tmask, execute_if.data.rd, execute_if.data.wb, execute_if.data.pid, execute_if.data.sop, execute_if.data.eop, alu_result, execute_if.data.PC, cbr_dest, is_br_op, br_op, tid}),
        .data_out ({commit_if.data.uuid, commit_if.data.wid, commit_if.data.tmask, commit_if.data.rd, commit_if.data.wb, commit_if.data.pid, commit_if.data.sop, commit_if.data.eop, alu_result_r, PC_r, cbr_dest_r, is_br_op_r, br_op_r, tid_r}),
        .valid_out (commit_if.valid),
        .ready_out (commit_if.ready)
    );

    `UNUSED_VAR (br_op_r)
    wire is_br_neg  = `INST_BR_IS_NEG(br_op_r);      // 是否是反向分支指令，如BNE、BGE等
    wire is_br_less = `INST_BR_IS_LESS(br_op_r);     // 是否是比较大小的分支指令，如BLT、BGE等（与BEQ、BNE等比较相等的分支指令相对应）
    wire is_br_static = `INST_BR_IS_STATIC(br_op_r); // 是否是静态分支指令，如JAL、JALR等

    wire [`XLEN-1:0] br_result = alu_result_r[tid_r];// 分支指令的结果，通常是通过比较rs1和rs2的差值来判断分支条件是否满足。对于比较大小的分支指令，结果的最高位（符号位）表示rs1和rs2的大小关系；对于比较相等的分支指令，结果的所有位都为0表示rs1和rs2相等。
    wire is_less  = br_result[0];                    // 小于 则为1，否则为0。   对于比较大小的分支指令，is_equal通常不用于判断分支条件，而是通过is_less来判断rs1和rs2的大小关系。
    wire is_equal = br_result[1];                    // 等于则为0，否则为1。     对于比较相等的分支指令，如果rs1和rs2相等，则sub_result为0，此时is_equal为1；如果rs1和rs2不相等，则sub_result不为0，此时is_equal为0。
    // 1、是分支指令
    // 2、eop有效，即分支指令结果的前递一定是warp的所有thread都计算完成；
    // 3、commit_if_fire：因为前面的计算都是组合逻辑，到这一拍reg才是缓冲后的结果。
    wire br_enable = is_br_op_r && commit_if.valid && commit_if.ready && commit_if.data.eop;// 本次分支是否有效，允许触发分支逻辑。
    wire br_taken = ((is_br_less ? is_less : is_equal) ^ is_br_neg) | is_br_static;         //分支是否发射跳转
    wire [`PC_BITS-1:0] br_dest = is_br_static ? br_result[1 +: `PC_BITS] : cbr_dest_r;     // 分支目标地址，对于条件分支指令，目标地址来自ALU计算的结果；对于静态分支指令，目标地址直接来自ALU计算的结果的特定位（通常是加法结果中的某些位）。
    wire [`NW_WIDTH-1:0] br_wid;
    `ASSIGN_BLOCKED_WID (br_wid, commit_if.data.wid, BLOCK_IDX, `NUM_ALU_BLOCKS)
    // 前向切割寄存器，打一拍。
    VX_pipe_register #(
        .DATAW (1 + `NW_WIDTH + 1 + `PC_BITS)
    ) branch_reg (
        .clk      (clk),
        .reset    (reset),
        .enable   (1'b1),
        .data_in  ({br_enable,           br_wid,            br_taken,            br_dest}),
        .data_out ({branch_ctl_if.valid, branch_ctl_if.wid, branch_ctl_if.taken, branch_ctl_if.dest})
    );
    // 如果是 JAL / JALR（附带需要存返回地址 PC + 4 的分支返回指令），
    // 其他指令则附带ALU计算结果（如加法结果、逻辑运算结果等）。
    for (genvar i = 0; i < NUM_LANES; ++i) begin
        assign commit_if.data.data[i] = (is_br_op_r && is_br_static) ? {(PC_r + `PC_BITS'(2)), 1'd0} : alu_result_r[i];
    end

    assign commit_if.data.PC = PC_r;

`ifdef DBG_TRACE_PIPELINE
    always @(posedge clk) begin
        if (br_enable) begin
            `TRACE(1, ("%d: %s-branch: wid=%0d, PC=0x%0h, taken=%b, dest=0x%0h (#%0d)\n",
                $time, INSTANCE_ID, br_wid, {commit_if.data.PC, 1'b0}, br_taken, {br_dest, 1'b0}, commit_if.data.uuid));
        end
    end
`endif

endmodule
