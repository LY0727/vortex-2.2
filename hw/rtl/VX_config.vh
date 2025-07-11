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

`ifndef VX_CONFIG_VH
`define VX_CONFIG_VH

/*===================================================
1. 宏工具函数
====================================================*/
`ifndef MIN
`define MIN(x, y)   (((x) < (y)) ? (x) : (y))
`endif

`ifndef MAX
`define MAX(x, y)   (((x) > (y)) ? (x) : (y))
`endif
// 限定x上下限： [ lo, hi ]
`ifndef CLAMP
`define CLAMP(x, lo, hi)   (((x) > (hi)) ? (hi) : (((x) < (lo)) ? (lo) : (x)))
`endif
// 避免0值
`ifndef UP
`define UP(x)   (((x) != 0) ? (x) : 1)
`endif


/*===================================================
2. 硬件架构配置 
    M F D ZICOND 四种扩展的启动和禁用
    默认系统位宽
    默认浮点数位宽，浮点数还涉及到硬件参数配置
====================================================*/
`ifndef EXT_M_DISABLE
`define EXT_M_ENABLE
`endif

`ifndef EXT_F_DISABLE
`define EXT_F_ENABLE
`endif

`ifdef XLEN_64
`ifndef FPU_DSP
`ifndef EXT_D_DISABLE
`define EXT_D_ENABLE
`endif
`endif
`endif

`ifndef EXT_ZICOND_DISABLE
`define EXT_ZICOND_ENABLE
`endif
// 默认32位
`ifndef XLEN_32
`ifndef XLEN_64
`define XLEN_32
`endif
`endif

`ifdef XLEN_64
`define XLEN 64
`endif

`ifdef XLEN_32
`define XLEN 32
`endif

`ifdef EXT_D_ENABLE
`define FLEN_64
`else
`define FLEN_32
`endif

`ifdef FLEN_64
`define FLEN 64
`endif

`ifdef FLEN_32
`define FLEN 32
`endif

`ifdef XLEN_64
`ifdef FLEN_32
    `define FPU_RV64F
`endif
`endif
/*===================================================
3. 硬件参数配置
====================================================*/
`ifndef NUM_CLUSTERS
`define NUM_CLUSTERS 1
`endif

`ifndef NUM_CORES
`define NUM_CORES 1
`endif

`ifndef NUM_WARPS
`define NUM_WARPS 4
`endif

`ifndef NUM_THREADS
`define NUM_THREADS 4
`endif
    // barrier 为什么是warps的一半；看schedule.sv
`ifndef NUM_BARRIERS
`define NUM_BARRIERS `UP(`NUM_WARPS/2)
`endif
    // spcket 为 4个cores
`ifndef SOCKET_SIZE
`define SOCKET_SIZE `MIN(4, `NUM_CORES)
`endif

`ifdef L2_ENABLE
    `define L2_ENABLED   1
`else
    `define L2_ENABLED   0
`endif

`ifdef L3_ENABLE
    `define L3_ENABLED   1
`else
    `define L3_ENABLED   0
`endif

`ifdef L1_DISABLE
    `define ICACHE_DISABLE
    `define DCACHE_DISABLE
`endif
    // 内存块大小
`ifndef MEM_BLOCK_SIZE
`define MEM_BLOCK_SIZE 64
`endif
    // 内存地址宽度
`ifndef MEM_ADDR_WIDTH
`ifdef XLEN_64
`define MEM_ADDR_WIDTH 48
`else
`define MEM_ADDR_WIDTH 32
`endif
`endif
    // L1 L2 L3 cache的行大小
`ifndef L1_LINE_SIZE
`define L1_LINE_SIZE `MEM_BLOCK_SIZE
`endif

`ifndef L2_LINE_SIZE
`define L2_LINE_SIZE `MEM_BLOCK_SIZE
`endif

`ifndef L3_LINE_SIZE
`define L3_LINE_SIZE `MEM_BLOCK_SIZE
`endif

/*===================================================
4. 地址配置，各基地址和大小
    堆栈
    起始地址
    用户地址
    IO地址
====================================================*/
`ifdef XLEN_64

`ifndef STACK_BASE_ADDR
`define STACK_BASE_ADDR 64'h1FFFF0000
`endif

`ifndef STARTUP_ADDR
`define STARTUP_ADDR    64'h080000000
`endif

`ifndef USER_BASE_ADDR
`define USER_BASE_ADDR  64'h000010000
`endif

`ifndef IO_BASE_ADDR
`define IO_BASE_ADDR    64'h000000040
`endif

`else

`ifndef STACK_BASE_ADDR
`define STACK_BASE_ADDR 32'hFFFF0000
`endif

`ifndef STARTUP_ADDR
`define STARTUP_ADDR    32'h80000000
`endif

`ifndef USER_BASE_ADDR
`define USER_BASE_ADDR  32'h00010000
`endif

`ifndef IO_BASE_ADDR
`define IO_BASE_ADDR    32'h00000040
`endif

`endif


`define IO_END_ADDR     `USER_BASE_ADDR

`ifndef LMEM_LOG_SIZE
`define LMEM_LOG_SIZE   14
`endif

`ifndef LMEM_BASE_ADDR
`define LMEM_BASE_ADDR  `STACK_BASE_ADDR
`endif

`ifndef IO_COUT_ADDR
`define IO_COUT_ADDR    `IO_BASE_ADDR
`endif
`define IO_COUT_SIZE    64

`ifndef IO_MPM_ADDR
`define IO_MPM_ADDR     (`IO_COUT_ADDR + `IO_COUT_SIZE)
`endif
`define IO_MPM_SIZE     (8 * 32 * `NUM_CORES * `NUM_CLUSTERS)

`ifndef STACK_LOG2_SIZE
`define STACK_LOG2_SIZE 13
`endif
`define STACK_SIZE      (1 << `STACK_LOG2_SIZE)
    // 复位延时
`define RESET_DELAY 8
    // 访存等待超时
`ifndef STALL_TIMEOUT
`define STALL_TIMEOUT   (100000 * (1 ** (`L2_ENABLED + `L3_ENABLED)))
`endif

/*===================================================
5. DPI、FPU、SYNTHESIS、DEBUG等配置   这都是仿真需要的
    DPI_DISABLE
    FPU_FPNEW
    FPU_DSP
    FPU_DPI
    IMUL_DPI
    IDIV_DPI
    DEBUG_LEVEL
====================================================*/
`ifndef SV_DPI
`define DPI_DISABLE
`endif

`ifndef FPU_FPNEW
`ifndef FPU_DSP
`ifndef FPU_DPI
`ifndef SYNTHESIS
`ifndef DPI_DISABLE
`define FPU_DPI
`else
`define FPU_DSP
`endif
`else
`define FPU_DSP
`endif
`endif
`endif
`endif

`ifndef SYNTHESIS
`ifndef DPI_DISABLE
`define IMUL_DPI
`define IDIV_DPI
`endif
`endif

`ifndef DEBUG_LEVEL
`define DEBUG_LEVEL 3
`endif

// Pipeline Configuration /////////////////////////////////////////////////////
/*===================================================
6. 流水线配置，
    发射宽度
    ALU、FPU、LSU、SFU的配置
    指令缓冲区大小
    LSU的配置
    FPU的配置
    Icache、Dcache、L2cache、L3cache、LMEM的配置
    ISA扩展
====================================================*/
// Issue width  发射宽度是指可以同时执行的warp数,这样执行单元也要加
`ifndef ISSUE_WIDTH
`define ISSUE_WIDTH     `UP(`NUM_WARPS / 8)
`endif

// Number of ALU units   
`ifndef NUM_ALU_LANES
`define NUM_ALU_LANES   `NUM_THREADS
`endif
`ifndef NUM_ALU_BLOCKS
`define NUM_ALU_BLOCKS  `ISSUE_WIDTH
`endif

// Number of FPU units
`ifndef NUM_FPU_LANES
`define NUM_FPU_LANES   `NUM_THREADS
`endif
`ifndef NUM_FPU_BLOCKS
`define NUM_FPU_BLOCKS  `ISSUE_WIDTH
`endif

// Number of LSU units  这个为什么要等于线程数
`ifndef NUM_LSU_LANES
`define NUM_LSU_LANES   `NUM_THREADS
`endif
`ifndef NUM_LSU_BLOCKS
`define NUM_LSU_BLOCKS  1
`endif

// Number of SFU units
`ifndef NUM_SFU_LANES
`define NUM_SFU_LANES   `NUM_THREADS
`endif
`ifndef NUM_SFU_BLOCKS
`define NUM_SFU_BLOCKS  1
`endif

// Size of Instruction Buffer
`ifndef IBUF_SIZE
`define IBUF_SIZE   4
`endif

// LSU line size    line数 * 每指令字节数 * cache行大小（64words）
`ifndef LSU_LINE_SIZE
`define LSU_LINE_SIZE   `MIN(`NUM_LSU_LANES * (`XLEN / 8), `L1_LINE_SIZE)
`endif

// Size of LSU Core Request Queue
`ifndef LSUQ_IN_SIZE
`define LSUQ_IN_SIZE    (2 * (`NUM_THREADS / `NUM_LSU_LANES))
`endif

// Size of LSU Memory Request Queue
`ifndef LSUQ_OUT_SIZE
`define LSUQ_OUT_SIZE   `MAX(`LSUQ_IN_SIZE, `LSU_LINE_SIZE / (`XLEN / 8))
`endif

`ifdef GBAR_ENABLE
`define GBAR_ENABLED 1
`else
`define GBAR_ENABLED 0
`endif

`ifndef LATENCY_IMUL
`ifdef VIVADO
`define LATENCY_IMUL 4
`endif
`ifdef QUARTUS
`define LATENCY_IMUL 3
`endif
`ifndef LATENCY_IMUL
`define LATENCY_IMUL 4
`endif
`endif

// Floating-Point Units ///////////////////////////////////////////////////////

// Size of FPU Request Queue
`ifndef FPUQ_SIZE
`define FPUQ_SIZE (2 * (`NUM_THREADS / `NUM_FPU_LANES))
`endif

// FNCP Latency
`ifndef LATENCY_FNCP
`define LATENCY_FNCP 2
`endif

// FMA Latency
`ifndef LATENCY_FMA
`ifdef FPU_DPI
`define LATENCY_FMA 4
`endif
`ifdef FPU_FPNEW
`define LATENCY_FMA 4
`endif
`ifdef FPU_DSP
`ifdef QUARTUS
`define LATENCY_FMA 4
`endif
`ifdef VIVADO
`define LATENCY_FMA 16
`endif
`ifndef LATENCY_FMA
`define LATENCY_FMA 4
`endif
`endif
`endif

// FDIV Latency
`ifndef LATENCY_FDIV
`ifdef FPU_DPI
`define LATENCY_FDIV 15
`endif
`ifdef FPU_FPNEW
`define LATENCY_FDIV 16
`endif
`ifdef FPU_DSP
`ifdef QUARTUS
`define LATENCY_FDIV 15
`endif
`ifdef VIVADO
`define LATENCY_FDIV 28
`endif
`ifndef LATENCY_FDIV
`define LATENCY_FDIV 16
`endif
`endif
`endif

// FSQRT Latency
`ifndef LATENCY_FSQRT
`ifdef FPU_DPI
`define LATENCY_FSQRT 10
`endif
`ifdef FPU_FPNEW
`define LATENCY_FSQRT 16
`endif
`ifdef FPU_DSP
`ifdef QUARTUS
`define LATENCY_FSQRT 10
`endif
`ifdef VIVADO
`define LATENCY_FSQRT 28
`endif
`ifndef LATENCY_FSQRT
`define LATENCY_FSQRT 16
`endif
`endif
`endif

// FCVT Latency
`ifndef LATENCY_FCVT
`define LATENCY_FCVT 5
`endif

// FMA Bandwidth ratio
`ifndef FMA_PE_RATIO
`define FMA_PE_RATIO 1
`endif

// FDIV Bandwidth ratio
`ifndef FDIV_PE_RATIO
`define FDIV_PE_RATIO 8
`endif

// FSQRT Bandwidth ratio
`ifndef FSQRT_PE_RATIO
`define FSQRT_PE_RATIO 8
`endif

// FCVT Bandwidth ratio
`ifndef FCVT_PE_RATIO
`define FCVT_PE_RATIO 8
`endif

// FNCP Bandwidth ratio
`ifndef FNCP_PE_RATIO
`define FNCP_PE_RATIO 2
`endif

// Icache Configurable Knobs //////////////////////////////////////////////////

// Cache Enable
`ifndef ICACHE_DISABLE
`define ICACHE_ENABLE
`endif
`ifdef ICACHE_ENABLE
    `define ICACHE_ENABLED 1
`else
    `define ICACHE_ENABLED 0
    `define NUM_ICACHES 0
`endif

// Number of Cache Units
`ifndef NUM_ICACHES
`define NUM_ICACHES `UP(`SOCKET_SIZE / 4)
`endif

// Cache Size   16KB
`ifndef ICACHE_SIZE
`define ICACHE_SIZE 16384
`endif

// Core Response Queue Size
`ifndef ICACHE_CRSQ_SIZE
`define ICACHE_CRSQ_SIZE 2
`endif

// Miss Handling Register Size
`ifndef ICACHE_MSHR_SIZE
`define ICACHE_MSHR_SIZE 16
`endif

// Memory Request Queue Size
`ifndef ICACHE_MREQ_SIZE
`define ICACHE_MREQ_SIZE 4
`endif

// Memory Response Queue Size
`ifndef ICACHE_MRSQ_SIZE
`define ICACHE_MRSQ_SIZE 0
`endif

// Number of Associative Ways
`ifndef ICACHE_NUM_WAYS
`define ICACHE_NUM_WAYS 1
`endif

// Dcache Configurable Knobs //////////////////////////////////////////////////

// Cache Enable
`ifndef DCACHE_DISABLE
`define DCACHE_ENABLE
`endif
`ifdef DCACHE_ENABLE
    `define DCACHE_ENABLED 1
`else
    `define DCACHE_ENABLED 0
    `define NUM_DCACHES 0
    `define DCACHE_NUM_BANKS 1
`endif

// Number of Cache Units   意思就是4个core共享一个cache
`ifndef NUM_DCACHES
`define NUM_DCACHES `UP(`SOCKET_SIZE / 4)
`endif

// Cache Size  16KB
`ifndef DCACHE_SIZE
`define DCACHE_SIZE 16384
`endif

// Number of Banks
`ifndef DCACHE_NUM_BANKS
`define DCACHE_NUM_BANKS `MIN(`NUM_LSU_LANES, 4)
`endif

// Core Response Queue Size
`ifndef DCACHE_CRSQ_SIZE
`define DCACHE_CRSQ_SIZE 2
`endif

// Miss Handling Register Size
`ifndef DCACHE_MSHR_SIZE
`define DCACHE_MSHR_SIZE 16
`endif

// Memory Request Queue Size
`ifndef DCACHE_MREQ_SIZE
`define DCACHE_MREQ_SIZE 4
`endif

// Memory Response Queue Size
`ifndef DCACHE_MRSQ_SIZE
`define DCACHE_MRSQ_SIZE 0
`endif

// Number of Associative Ways
`ifndef DCACHE_NUM_WAYS
`define DCACHE_NUM_WAYS 1
`endif

// Enable Cache Writeback
`ifndef DCACHE_WRITEBACK
`define DCACHE_WRITEBACK 0
`endif

// LMEM Configurable Knobs ////////////////////////////////////////////////////

`ifndef LMEM_DISABLE
`define LMEM_ENABLE
`endif

`ifdef LMEM_ENABLE
    `define LMEM_ENABLED   1
`else
    `define LMEM_ENABLED   0
    `define LMEM_NUM_BANKS 1
`endif

// Number of Banks
`ifndef LMEM_NUM_BANKS
`define LMEM_NUM_BANKS `NUM_LSU_LANES
`endif

// L2cache Configurable Knobs /////////////////////////////////////////////////

// Cache Size
`ifndef L2_CACHE_SIZE
`ifdef ALTERA_S10
`define L2_CACHE_SIZE 2097152
`else
`define L2_CACHE_SIZE 1048576
`endif
`endif

// Number of Banks
`ifndef L2_NUM_BANKS
`define L2_NUM_BANKS `MIN(4, `NUM_SOCKETS)
`endif

// Core Response Queue Size
`ifndef L2_CRSQ_SIZE
`define L2_CRSQ_SIZE 2
`endif

// Miss Handling Register Size
`ifndef L2_MSHR_SIZE
`define L2_MSHR_SIZE 16
`endif

// Memory Request Queue Size
`ifndef L2_MREQ_SIZE
`define L2_MREQ_SIZE 4
`endif

// Memory Response Queue Size
`ifndef L2_MRSQ_SIZE
`define L2_MRSQ_SIZE 0
`endif

// Number of Associative Ways
`ifndef L2_NUM_WAYS
`define L2_NUM_WAYS 2
`endif

// Enable Cache Writeback
`ifndef L2_WRITEBACK
`define L2_WRITEBACK 0
`endif

// L3cache Configurable Knobs /////////////////////////////////////////////////

// Cache Size
`ifndef L3_CACHE_SIZE
`ifdef ALTERA_S10
`define L3_CACHE_SIZE 2097152
`else
`define L3_CACHE_SIZE 1048576
`endif
`endif

// Number of Banks
`ifndef L3_NUM_BANKS
`define L3_NUM_BANKS `MIN(4, `NUM_CLUSTERS)
`endif

// Core Response Queue Size
`ifndef L3_CRSQ_SIZE
`define L3_CRSQ_SIZE 2
`endif

// Miss Handling Register Size
`ifndef L3_MSHR_SIZE
`define L3_MSHR_SIZE 16
`endif

// Memory Request Queue Size
`ifndef L3_MREQ_SIZE
`define L3_MREQ_SIZE 4
`endif

// Memory Response Queue Size
`ifndef L3_MRSQ_SIZE
`define L3_MRSQ_SIZE 0
`endif

// Number of Associative Ways
`ifndef L3_NUM_WAYS
`define L3_NUM_WAYS 4
`endif

// Enable Cache Writeback
`ifndef L3_WRITEBACK
`define L3_WRITEBACK 0
`endif

// ISA Extensions /////////////////////////////////////////////////////////////

`ifdef EXT_A_ENABLE
    `define EXT_A_ENABLED   1
`else
    `define EXT_A_ENABLED   0
`endif

`ifdef EXT_C_ENABLE
    `define EXT_C_ENABLED   1
`else
    `define EXT_C_ENABLED   0
`endif

`ifdef EXT_D_ENABLE
    `define EXT_D_ENABLED   1
`else
    `define EXT_D_ENABLED   0
`endif

`ifdef EXT_F_ENABLE
    `define EXT_F_ENABLED   1
`else
    `define EXT_F_ENABLED   0
`endif

`ifdef EXT_M_ENABLE
    `define EXT_M_ENABLED   1
`else
    `define EXT_M_ENABLED   0
`endif

`ifdef EXT_ZICOND_ENABLE
    `define EXT_ZICOND_ENABLED 1
`else
    `define EXT_ZICOND_ENABLED 0
`endif
// 给运行时使用的
`define ISA_STD_A           0
`define ISA_STD_C           2
`define ISA_STD_D           3
`define ISA_STD_E           4
`define ISA_STD_F           5
`define ISA_STD_H           7
`define ISA_STD_I           8
`define ISA_STD_N           13
`define ISA_STD_Q           16
`define ISA_STD_S           18
`define ISA_STD_U           20

`define ISA_EXT_ICACHE      0
`define ISA_EXT_DCACHE      1
`define ISA_EXT_L2CACHE     2
`define ISA_EXT_L3CACHE     3
`define ISA_EXT_LMEM        4
`define ISA_EXT_ZICOND      5

// MISA寄存器是RISCV架构中，用于指示处理器支持的指令集扩展 和 功能扩展 情况 的寄存器。
`define MISA_EXT  (`ICACHE_ENABLED  << `ISA_EXT_ICACHE) \
                | (`DCACHE_ENABLED  << `ISA_EXT_DCACHE) \
                | (`L2_ENABLED      << `ISA_EXT_L2CACHE) \
                | (`L3_ENABLED      << `ISA_EXT_L3CACHE) \
                | (`LMEM_ENABLED    << `ISA_EXT_LMEM) \
                | (`EXT_ZICOND_ENABLED << `ISA_EXT_ZICOND)

`define MISA_STD  (`EXT_A_ENABLED <<  0) /* A - Atomic Instructions extension */ \
                | (0 <<  1) /* B - Tentatively reserved for Bit operations extension */ \
                | (`EXT_C_ENABLED <<  2) /* C - Compressed extension */ \
                | (`EXT_D_ENABLED <<  3) /* D - Double precsision floating-point extension */ \
                | (0 <<  4) /* E - RV32E base ISA */ \
                | (`EXT_F_ENABLED << 5) /* F - Single precsision floating-point extension */ \
                | (0 <<  6) /* G - Additional standard extensions present */ \
                | (0 <<  7) /* H - Hypervisor mode implemented */ \
                | (1 <<  8) /* I - RV32I/64I/128I base ISA */ \
                | (0 <<  9) /* J - Reserved */ \
                | (0 << 10) /* K - Reserved */ \
                | (0 << 11) /* L - Tentatively reserved for Bit operations extension */ \
                | (`EXT_M_ENABLED << 12) /* M - Integer Multiply/Divide extension */ \
                | (0 << 13) /* N - User level interrupts supported */ \
                | (0 << 14) /* O - Reserved */ \
                | (0 << 15) /* P - Tentatively reserved for Packed-SIMD extension */ \
                | (0 << 16) /* Q - Quad-precision floating-point extension */ \
                | (0 << 17) /* R - Reserved */ \
                | (0 << 18) /* S - Supervisor mode implemented */ \
                | (0 << 19) /* T - Tentatively reserved for Transactional Memory extension */ \
                | (1 << 20) /* U - User mode implemented */ \
                | (0 << 21) /* V - Tentatively reserved for Vector extension */ \
                | (0 << 22) /* W - Reserved */ \
                | (1 << 23) /* X - Non-standard extensions present */ \
                | (0 << 24) /* Y - Reserved */ \
                | (0 << 25) /* Z - Reserved */

// Device identification //////////////////////////////////////////////////////

`define VENDOR_ID           0
`define ARCHITECTURE_ID     0
`define IMPLEMENTATION_ID   0

`endif // VX_CONFIG_VH
