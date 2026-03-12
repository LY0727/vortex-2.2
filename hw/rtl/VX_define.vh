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

`ifndef VX_DEFINE_VH
`define VX_DEFINE_VH

`include "VX_platform.vh"
`include "VX_config.vh"
`include "VX_types.vh"

///////////////////////////////////////////////////////////////////////////////

`define NW_BITS         `CLOG2(`NUM_WARPS)
`define NW_WIDTH        `UP(`NW_BITS)

`define NT_BITS         `CLOG2(`NUM_THREADS)
`define NT_WIDTH        `UP(`NT_BITS)

`define NC_BITS         `CLOG2(`NUM_CORES)
`define NC_WIDTH        `UP(`NC_BITS)

`define NB_BITS         `CLOG2(`NUM_BARRIERS)
`define NB_WIDTH        `UP(`NB_BITS)

`define NUM_IREGS       32
`define NRI_BITS        `CLOG2(`NUM_IREGS)  // Number of integer registers, used for register file and register renaming. Does not include zero register.

`ifdef EXT_F_ENABLE
`define NUM_REGS        (2 * `NUM_IREGS)
`else
`define NUM_REGS        `NUM_IREGS
`endif

`define NR_BITS         `CLOG2(`NUM_REGS)

`define DV_STACK_SIZE   `UP(`NUM_THREADS-1)
`define DV_STACK_SIZEW  `UP(`CLOG2(`DV_STACK_SIZE))  // 因为最坏情况是全部线程分化，所以分化栈需要 `NUM_THREADS-1` 层，每层一个 bit 来表示哪个路径被 taken 了

`define PERF_CTR_BITS   44  // 性能计数器的位宽，生产版本会被替换成 1 位的占位符

`ifndef NDEBUG
`define UUID_WIDTH      44  // 用于调试的 UUID，生产版本会被替换成 1 位的占位符
`else
`define UUID_WIDTH      1
`endif

`define PC_BITS         (`XLEN-1)
`define OFFSET_BITS     12
`define IMM_BITS        `XLEN

`define NUM_SOCKETS     `UP(`NUM_CORES / `SOCKET_SIZE)

///////////////////////////////////////////////////////////////////////////////

`define EX_ALU          0
`define EX_LSU          1
`define EX_SFU          2
`define EX_FPU          (`EX_SFU + `EXT_F_ENABLED)   // 上面三个是固定的，FPU 的编号根据是否启用 F 扩展来决定

`define NUM_EX_UNITS    (3 + `EXT_F_ENABLED)
`define EX_BITS         `CLOG2(`NUM_EX_UNITS)   // 对执行单元编号
`define EX_WIDTH        `UP(`EX_BITS)

`define SFU_CSRS        0
`define SFU_WCTL        1

`define NUM_SFU_UNITS   (2)
`define SFU_BITS        `CLOG2(`NUM_SFU_UNITS)
`define SFU_WIDTH       `UP(`SFU_BITS)

///////////////////////////////////////////////////////////////////////////////

`define INST_LUI        7'b0110111
`define INST_AUIPC      7'b0010111
`define INST_JAL        7'b1101111
`define INST_JALR       7'b1100111
`define INST_B          7'b1100011 // branch instructions
`define INST_L          7'b0000011 // load instructions
`define INST_S          7'b0100011 // store instructions
`define INST_I          7'b0010011 // immediate instructions
`define INST_R          7'b0110011 // register instructions
`define INST_FENCE      7'b0001111 // Fence instructions
`define INST_SYS        7'b1110011 // system instructions

// RV64I instruction specific opcodes (for any W instruction)
`define INST_I_W        7'b0011011 // W type immediate instructions
`define INST_R_W        7'b0111011 // W type register instructions

`define INST_FL         7'b0000111 // float load instruction
`define INST_FS         7'b0100111 // float store  instruction
`define INST_FMADD      7'b1000011
`define INST_FMSUB      7'b1000111
`define INST_FNMSUB     7'b1001011
`define INST_FNMADD     7'b1001111
`define INST_FCI        7'b1010011 // float common instructions

// Custom extension opcodes
`define INST_EXT1       7'b0001011 // 0x0B
`define INST_EXT2       7'b0101011 // 0x2B
`define INST_EXT3       7'b1011011 // 0x5B
`define INST_EXT4       7'b1111011 // 0x7B

// Opcode extensions
`define INST_R_F7_MUL   7'b0000001
`define INST_R_F7_ZICOND 7'b0000111

///////////////////////////////////////////////////////////////////////////////

`define INST_FRM_RNE    3'b000  // round to nearest even
`define INST_FRM_RTZ    3'b001  // round to zero
`define INST_FRM_RDN    3'b010  // round to -inf
`define INST_FRM_RUP    3'b011  // round to +inf
`define INST_FRM_RMM    3'b100  // round to nearest max magnitude
`define INST_FRM_DYN    3'b111  // dynamic mode
`define INST_FRM_BITS   3

///////////////////////////////////////////////////////////////////////////////

`define INST_OP_BITS    4
`define INST_ARGS_BITS   $bits(op_args_t)
`define INST_FMT_BITS   2

///////////////////////////////////////////////////////////////////////////////

`define INST_ALU_ADD         4'b0000 // ADD: 加法 (Addition)
//`define INST_ALU_UNUSED    4'b0001
`define INST_ALU_LUI         4'b0010 // LUI: Load Upper Immediate (取立即数高位并左移12位)
`define INST_ALU_AUIPC       4'b0011 // AUIPC: Add Upper Immediate to PC (将立即数高位与PC相加)
`define INST_ALU_SLTU        4'b0100 // SLTU: Set Less Than Unsigned (无符号比较，若小于则置1)
`define INST_ALU_SLT         4'b0101 // SLT: Set Less Than (有符号比较，若小于则置1)
//`define INST_ALU_UNUSED    4'b0110
`define INST_ALU_SUB         4'b0111 // SUB: 减法 (Subtraction)
`define INST_ALU_SRL         4'b1000 // SRL: Shift Right Logical (逻辑右移，高位补0)
`define INST_ALU_SRA         4'b1001 // SRA: Shift Right Arithmetic (算术右移，高位补符号位)
`define INST_ALU_CZEQ        4'b1010 // CZEQ: Conditional Zero if Equal (条件置零Zicond扩展：若满足等于条件则置0)
`define INST_ALU_CZNE        4'b1011 // CZNE: Conditional Zero if Not Equal (条件置零Zicond扩展：若不等于则置0)
`define INST_ALU_AND         4'b1100 // AND: 按位与 (Bitwise AND)
`define INST_ALU_OR          4'b1101 // OR: 按位或 (Bitwise OR)
`define INST_ALU_XOR         4'b1110 // XOR: 按位异或 (Bitwise XOR)
`define INST_ALU_SLL         4'b1111 // SLL: Shift Left Logical (逻辑左移，低位补0)


`define ALU_TYPE_BITS        2
`define ALU_TYPE_ARITH       0
`define ALU_TYPE_BRANCH      1
`define ALU_TYPE_MULDIV      2
`define ALU_TYPE_OTHER       3

`define INST_ALU_BITS        4
`define INST_ALU_CLASS(op)   op[3:2]
`define INST_ALU_SIGNED(op)  op[0]
`define INST_ALU_IS_SUB(op)  op[1]
`define INST_ALU_IS_CZERO(op) (op[3:1] == 3'b101)

`define INST_BR_EQ           4'b0000 // BEQ (Branch if Equal): 当 rs1 == rs2 时发生跳转
`define INST_BR_NE           4'b0010 // BNE (Branch if Not Equal): 当 rs1 != rs2 时发生跳转
`define INST_BR_LTU          4'b0100 // BLTU (Branch if Less Than, Unsigned): 当 rs1 < rs2 (无符号比较) 时跳转
`define INST_BR_GEU          4'b0110 // BGEU (Branch if Greater/Equal, Unsigned): 当 rs1 >= rs2 (无符号比较) 时跳转
`define INST_BR_LT           4'b0101 // BLT (Branch if Less Than): 当 rs1 < rs2 (有符号比较) 时跳转
`define INST_BR_GE           4'b0111 // BGE (Branch if Greater/Equal): 当 rs1 >= rs2 (有符号比较) 时跳转
`define INST_BR_JAL          4'b1000 // JAL (Jump and Link): 无条件相对跳转，并将 PC+4 保存至 rd (通常作函数调用)
`define INST_BR_JALR         4'b1001 // JALR (Jump and Link Register): 无条件绝对跳转(基址+偏移)，PC+4 保存至 rd
`define INST_BR_ECALL        4'b1010 // ECALL (Environment Call): 触发环境调用异常(俗称系统调用/Syscall)，陷入特权模式
`define INST_BR_EBREAK       4'b1011 // EBREAK (Environment Breakpoint): 触发断点异常，用于Debug器挂起程序
`define INST_BR_URET         4'b1100 // URET (User mode Return): 从异常处理程序返回到 User 用户态
`define INST_BR_SRET         4'b1101 // SRET (Supervisor mode Return): 从异常处理程序返回到 Supervisor 管理态
`define INST_BR_MRET         4'b1110 // MRET (Machine mode Return): 从异常处理程序返回到 Machine 机器态
`define INST_BR_OTHER        4'b1111 // 保留作为其他控制流的 Fallback 标志
`define INST_BR_BITS         4
`define INST_BR_CLASS(op)    {1'b0, ~op[3]}
`define INST_BR_IS_NEG(op)   op[1]
`define INST_BR_IS_LESS(op)  op[2]
`define INST_BR_IS_STATIC(op) op[3]

`define INST_M_MUL           3'b000 // MUL: 乘法，返回乘积低位 (低 XLEN 位)
`define INST_M_MULHU         3'b001 // MULHU: 无符号数乘法，返回乘积高位 (高 XLEN 位)
`define INST_M_MULH          3'b010 // MULH: 有符号数乘法，返回乘积高位 (高 XLEN 位)
`define INST_M_MULHSU        3'b011 // MULHSU: 有符号与无符号数相乘，返回乘积高位 (高 XLEN 位)
`define INST_M_DIV           3'b100 // DIV: 有符号除法
`define INST_M_DIVU          3'b101 // DIVU: 无符号除法
`define INST_M_REM           3'b110 // REM: 有符号求余
`define INST_M_REMU          3'b111 // REMU: 无符号求余
`define INST_M_BITS          3
`define INST_M_SIGNED(op)    (~op[0])
`define INST_M_IS_MULX(op)   (~op[2])
`define INST_M_IS_MULH(op)   (op[1:0] != 0)
`define INST_M_SIGNED_A(op)  (op[1:0] != 1)
`define INST_M_IS_REM(op)    op[1]

`define INST_FMT_B           3'b000
`define INST_FMT_H           3'b001
`define INST_FMT_W           3'b010
`define INST_FMT_D           3'b011
`define INST_FMT_BU          3'b100
`define INST_FMT_HU          3'b101
`define INST_FMT_WU          3'b110

`define INST_LSU_LB          4'b0000 // LB: Load Byte (加载8位字节并进行符号扩展)
`define INST_LSU_LH          4'b0001 // LH: Load Halfword (加载16位半字并进行符号扩展)
`define INST_LSU_LW          4'b0010 // LW: Load Word (加载32位字并进行符号扩展)
`define INST_LSU_LD          4'b0011 // LD: new for RV64I LD (加载64位双字)
`define INST_LSU_LBU         4'b0100 // LBU: Load Byte Unsigned (加载8位字节并进行无符号扩展/零扩展)
`define INST_LSU_LHU         4'b0101 // LHU: Load Halfword Unsigned (加载16位半字并进行无符号扩展/零扩展)
`define INST_LSU_LWU         4'b0110 // LWU: new for RV64I LWU (加载32位字并进行无符号扩展/零扩展)
`define INST_LSU_SB          4'b1000 // SB: Store Byte (存储最低8位字节)
`define INST_LSU_SH          4'b1001 // SH: Store Halfword (存储最低16位半字)
`define INST_LSU_SW          4'b1010 // SW: Store Word (存储最低32位字)
`define INST_LSU_SD          4'b1011 // SD: new for RV64I SD (存储64位双字)
`define INST_LSU_FENCE       4'b1111 // FENCE: 内存屏障指令，保证访存顺序
`define INST_LSU_BITS        4
`define INST_LSU_FMT(op)     op[2:0]
`define INST_LSU_WSIZE(op)   op[1:0]
`define INST_LSU_IS_FENCE(op) (op[3:2] == 3)

`define INST_FENCE_BITS      1
`define INST_FENCE_D         1'h0
`define INST_FENCE_I         1'h1

`define INST_FPU_ADD         4'b0000 // FADD: 浮点加法
`define INST_FPU_SUB         4'b0001 // FSUB: 浮点减法
`define INST_FPU_MUL         4'b0010 // FMUL: 浮点乘法
`define INST_FPU_DIV         4'b0011 // FDIV: 浮点除法
`define INST_FPU_SQRT        4'b0100 // FSQRT: 浮点平方根
`define INST_FPU_CMP         4'b0101 // frm: LE=0, LT=1, EQ=2 (浮点比较)
`define INST_FPU_F2F         4'b0110 // FCVT.F.F: 浮点数格式转换(比如单精度与双精度转换)
`define INST_FPU_MISC        4'b0111 // frm: SGNJ=0, SGNJN=1, SGNJX=2, CLASS=3, MVXW=4, MVWX=5, FMIN=6, FMAX=7 (浮点混杂指令，符号注入/分类/极值/数据移动)
`define INST_FPU_F2I         4'b1000 // FCVT.W.S / FCVT.L.S: 浮点数转有符号整数
`define INST_FPU_F2U         4'b1001 // FCVT.WU.S / FCVT.LU.S: 浮点数转无符号整数
`define INST_FPU_I2F         4'b1010 // FCVT.S.W / FCVT.S.L: 有符号整数转浮点数
`define INST_FPU_U2F         4'b1011 // FCVT.S.WU / FCVT.S.LU: 无符号整数转浮点数
`define INST_FPU_MADD        4'b1100 // FMADD: 浮点乘加 (rs1 * rs2 + rs3)
`define INST_FPU_MSUB        4'b1101 // FMSUB: 浮点乘减 (rs1 * rs2 - rs3)
`define INST_FPU_NMSUB       4'b1110 // FNMSUB: 浮点负向乘减 (-(rs1 * rs2) + rs3)
`define INST_FPU_NMADD       4'b1111 // FNMADD: 浮点负向乘加 (-(rs1 * rs2) - rs3)
`define INST_FPU_BITS        4
`define INST_FPU_IS_CLASS(op, frm) (op == `INST_FPU_MISC && frm == 3)
`define INST_FPU_IS_MVXW(op, frm) (op == `INST_FPU_MISC && frm == 4)

`define INST_SFU_TMC         4'h0 // TMC (Thread Mask Control): 设置当前的活动线程掩码
`define INST_SFU_WSPAWN      4'h1 // WSPAWN (Warp Spawn): 启动新的 Warp
`define INST_SFU_SPLIT       4'h2 // SPLIT (Control Flow Split): 记录分化点，用于处理分支发散
`define INST_SFU_JOIN        4'h3 // JOIN (Control Flow Join): 会合点，处理分支的归一化
`define INST_SFU_BAR         4'h4 // BAR (Barrier): Warp 和 Thread 的栅栏同步机制
`define INST_SFU_PRED        4'h5 // PRED (Predicate): 设置谓词掩码
`define INST_SFU_CSRRW       4'h6 // CSRRW (CSR Read/Write): 读并写控制和状态寄存器
`define INST_SFU_CSRRS       4'h7 // CSRRS (CSR Read/Set): 读并按位置1设置控制和状态寄存器
`define INST_SFU_CSRRC       4'h8 // CSRRC (CSR Read/Clear): 读并按位清零控制和状态寄存器
`define INST_SFU_BITS        4
`define INST_SFU_CSR(f3)     (4'h6 + 4'(f3) - 4'h1)
`define INST_SFU_IS_WCTL(op) (op <= 5)
`define INST_SFU_IS_CSR(op)  (op >= 6 && op <= 8)

///////////////////////////////////////////////////////////////////////////////

`define ARB_SEL_BITS(I, O)  ((I > O) ? `CLOG2(`CDIV(I, O)) : 0)

///////////////////////////////////////////////////////////////////////////////

`define CACHE_MEM_TAG_WIDTH(mshr_size, num_banks) \
        (`CLOG2(mshr_size) + `CLOG2(num_banks))

`define CACHE_BYPASS_TAG_WIDTH(num_reqs, line_size, word_size, tag_width) \
        (`CLOG2(num_reqs) + `CLOG2(line_size / word_size) + tag_width)

`define CACHE_NC_MEM_TAG_WIDTH(mshr_size, num_banks, num_reqs, line_size, word_size, tag_width) \
        (`MAX(`CACHE_MEM_TAG_WIDTH(mshr_size, num_banks), `CACHE_BYPASS_TAG_WIDTH(num_reqs, line_size, word_size, tag_width)) + 1)

///////////////////////////////////////////////////////////////////////////////

`define CACHE_CLUSTER_CORE_ARB_TAG(tag_width, num_inputs, num_caches) \
        (tag_width + `ARB_SEL_BITS(num_inputs, `UP(num_caches)))

`define CACHE_CLUSTER_MEM_ARB_TAG(tag_width, num_caches) \
        (tag_width + `ARB_SEL_BITS(`UP(num_caches), 1))

`define CACHE_CLUSTER_MEM_TAG_WIDTH(mshr_size, num_banks, num_caches) \
        `CACHE_CLUSTER_MEM_ARB_TAG(`CACHE_MEM_TAG_WIDTH(mshr_size, num_banks), num_caches)

`define CACHE_CLUSTER_BYPASS_MEM_TAG_WIDTH(num_reqs, line_size, word_size, tag_width, num_inputs, num_caches) \
        `CACHE_CLUSTER_MEM_ARB_TAG(`CACHE_BYPASS_TAG_WIDTH(num_reqs, line_size, word_size, `CACHE_CLUSTER_CORE_ARB_TAG(tag_width, num_inputs, num_caches)), num_caches)

`define CACHE_CLUSTER_NC_MEM_TAG_WIDTH(mshr_size, num_banks, num_reqs, line_size, word_size, tag_width, num_inputs, num_caches) \
        `CACHE_CLUSTER_MEM_ARB_TAG(`CACHE_NC_MEM_TAG_WIDTH(mshr_size, num_banks, num_reqs, line_size, word_size, `CACHE_CLUSTER_CORE_ARB_TAG(tag_width, num_inputs, num_caches)), num_caches)

///////////////////////////////////////////////////////////////////////////////

`ifdef ICACHE_ENABLE
`define L1_ENABLE
`endif

`ifdef DCACHE_ENABLE
`define L1_ENABLE
`endif

`define ADDR_TYPE_FLUSH         0 // 用于标记特殊的内存请求类型，比如全局内存屏障或者指令缓存失效等不涉及具体地址的请求
`define ADDR_TYPE_IO            1 // IO 设备访问，通常映射到特定的地址范围，访问时需要特殊处理
`define ADDR_TYPE_LOCAL         2 // shoud be last since optional
`define ADDR_TYPE_WIDTH         (`ADDR_TYPE_LOCAL + `LMEM_ENABLED)

`define VX_MEM_BYTEEN_WIDTH     `L3_LINE_SIZE
`define VX_MEM_ADDR_WIDTH       (`MEM_ADDR_WIDTH - `CLOG2(`L3_LINE_SIZE))
`define VX_MEM_DATA_WIDTH       (`L3_LINE_SIZE * 8)
`define VX_MEM_TAG_WIDTH        L3_MEM_TAG_WIDTH

`define VX_DCR_ADDR_WIDTH       `VX_DCR_ADDR_BITS
`define VX_DCR_DATA_WIDTH       32

`define TO_FULL_ADDR(x)         {x, (`MEM_ADDR_WIDTH-$bits(x))'(0)}

///////////////////////////////////////////////////////////////////////////////

`define BUFFER_EX(dst, src, ena, latency) \
    VX_pipe_register #( \
        .DATAW  ($bits(dst)), \
        .RESETW ($bits(dst)), \
        .DEPTH  (latency) \
    ) __``dst``__ ( \
        .clk      (clk), \
        .reset    (reset), \
        .enable   (ena), \
        .data_in  (src), \
        .data_out (dst) \
    )

`define BUFFER(dst, src) `BUFFER_EX(dst, src, 1'b1, 1)

`define POP_COUNT_EX(out, in, model) \
    VX_popcount #( \
        .N ($bits(in)), \
        .MODEL (model) \
    ) __``out``__ ( \
        .data_in  (in), \
        .data_out (out) \
    )

`define POP_COUNT(out, in) `POP_COUNT_EX(out, in, 1)

`define ASSIGN_VX_IF(dst, src) \
    assign dst.valid = src.valid; \
    assign dst.data  = src.data; \
    assign src.ready = dst.ready

`define ASSIGN_VX_MEM_BUS_IF(dst, src) \
    assign dst.req_valid  = src.req_valid; \
    assign dst.req_data   = src.req_data; \
    assign src.req_ready  = dst.req_ready; \
    assign src.rsp_valid  = dst.rsp_valid; \
    assign src.rsp_data   = dst.rsp_data; \
    assign dst.rsp_ready  = src.rsp_ready

`define ASSIGN_VX_MEM_BUS_IF_X(dst, src, TD, TS) \
    assign dst.req_valid = src.req_valid; \
    assign dst.req_data.rw = src.req_data.rw; \
    assign dst.req_data.byteen = src.req_data.byteen; \
    assign dst.req_data.addr = src.req_data.addr; \
    assign dst.req_data.atype = src.req_data.atype; \
    assign dst.req_data.data = src.req_data.data; \
    if (TD != TS) \
        assign dst.req_data.tag = {src.req_data.tag, {(TD-TS){1'b0}}}; \
    else \
        assign dst.req_data.tag = src.req_data.tag; \
    assign src.req_ready = dst.req_ready; \
    assign src.rsp_valid = dst.rsp_valid; \
    assign src.rsp_data.data = dst.rsp_data.data; \
    assign src.rsp_data.tag = dst.rsp_data.tag[TD-1 -: TS]; \
    assign dst.rsp_ready = src.rsp_ready

`define ASSIGN_VX_LSU_MEM_IF(dst, src) \
    assign dst.req_valid  = src.req_valid; \
    assign dst.req_data   = src.req_data; \
    assign src.req_ready  = dst.req_ready; \
    assign src.rsp_valid  = dst.rsp_valid; \
    assign src.rsp_data   = dst.rsp_data; \
    assign dst.rsp_ready  = src.rsp_ready

`define BUFFER_DCR_BUS_IF(dst, src, enable) \
    if (enable) begin \
        reg [(1 + `VX_DCR_ADDR_WIDTH + `VX_DCR_DATA_WIDTH)-1:0] __dst; \
        always @(posedge clk) begin \
            __dst <= {src.write_valid, src.write_addr, src.write_data}; \
        end \
        assign {dst.write_valid, dst.write_addr, dst.write_data} = __dst; \
    end else begin \
        assign {dst.write_valid, dst.write_addr, dst.write_data} = {src.write_valid, src.write_addr, src.write_data}; \
    end

`define PERF_COUNTER_ADD(dst, src, field, width, count, reg_enable) \
    if (count > 1) begin \
        wire [count-1:0][width-1:0] __reduce_add_i_field; \
        wire [width-1:0] __reduce_add_o_field; \
        for (genvar __i = 0; __i < count; ++__i) begin \
            assign __reduce_add_i_field[__i] = src[__i].``field; \
        end \
        VX_reduce #(.DATAW_IN(width), .N(count), .OP("+")) __reduce_add_field ( \
            __reduce_add_i_field, \
            __reduce_add_o_field \
        ); \
        if (reg_enable) begin \
            reg [width-1:0] __reduce_add_r_field; \
            always @(posedge clk) begin \
                if (reset) begin \
                    __reduce_add_r_field <= '0; \
                end else begin \
                    __reduce_add_r_field <= __reduce_add_o_field; \
                end \
            end \
            assign dst.``field = __reduce_add_r_field; \
        end else begin \
            assign dst.``field = __reduce_add_o_field; \
        end \
    end else begin \
        assign dst.``field = src[0].``field; \
    end

`define ASSIGN_BLOCKED_WID(dst, src, block_idx, block_size) \
    if (block_size != 1) begin \
        if (block_size != `NUM_WARPS) begin \
            assign dst = {src[`NW_WIDTH-1:`CLOG2(block_size)], `CLOG2(block_size)'(block_idx)}; \
        end else begin \
            assign dst = `NW_WIDTH'(block_idx); \
        end \
    end else begin \
        assign dst = src; \
    end

`endif // VX_DEFINE_VH
