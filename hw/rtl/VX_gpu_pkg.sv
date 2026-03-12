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

`ifndef VX_GPU_PKG_VH
`define VX_GPU_PKG_VH

`include "VX_define.vh"

package VX_gpu_pkg;

    typedef struct packed {
        logic                    valid;  
        logic [`NUM_THREADS-1:0] tmask;  
    } tmc_t;

    typedef struct packed {
        logic                   valid;
        logic [`NUM_WARPS-1:0]  wmask;
        logic [`PC_BITS-1:0]    pc;
    } wspawn_t;

    typedef struct packed {
        logic                    valid;
        logic                    is_dvg;     // 是不是发生了发散？(Divergence)
        logic [`NUM_THREADS-1:0] then_tmask; // 如果发生发散，走 then 路径的线程们
        logic [`NUM_THREADS-1:0] else_tmask; // 走 else 路径的线程们
        logic [`PC_BITS-1:0]     next_pc;    // else路径的PC，以便稍后回来执行
    } split_t;

    typedef struct packed {
        logic valid;
        logic [`DV_STACK_SIZEW-1:0] stack_ptr; // 分化栈指针，指向当前分化层的栈顶
    } join_t;

    typedef struct packed {
        logic                   valid;
        logic [`NB_WIDTH-1:0]   id;      // 屏障ID，用户指定的一个值，用于区分不同的屏障指令
        logic                   is_global;
    `ifdef GBAR_ENABLE
        logic [`MAX(`NW_WIDTH, `NC_WIDTH)-1:0] size_m1;
    `else
        logic [`NW_WIDTH-1:0]   size_m1; // block内屏障，对应硬件core内屏障；size就是 NUM_WARPS。
    `endif
        logic                   is_noop; // 是不是一个 noop 屏障指令？noop 屏障指令不需要真正执行屏障操作，主要用于占位和调度目的
    } barrier_t;

    typedef struct packed {
        logic [`XLEN-1:0]       startup_addr;
        logic [`XLEN-1:0]       startup_arg;  
        logic [7:0]             mpm_class;   // Multi-Program Multi-Thread class, 用于区分不同的 MPM 任务
    } base_dcrs_t;

    //////////////////////////// Perf counter types ///////////////////////////

    typedef struct packed {
        logic [`PERF_CTR_BITS-1:0] reads;
        logic [`PERF_CTR_BITS-1:0] writes;
        logic [`PERF_CTR_BITS-1:0] read_misses;
        logic [`PERF_CTR_BITS-1:0] write_misses;
        logic [`PERF_CTR_BITS-1:0] bank_stalls;
        logic [`PERF_CTR_BITS-1:0] mshr_stalls;
        logic [`PERF_CTR_BITS-1:0] mem_stalls;
        logic [`PERF_CTR_BITS-1:0] crsp_stalls;
    } cache_perf_t;

    typedef struct packed {
        logic [`PERF_CTR_BITS-1:0] reads;
        logic [`PERF_CTR_BITS-1:0] writes;
        logic [`PERF_CTR_BITS-1:0] latency;
    } mem_perf_t;

    typedef struct packed {
        logic [`PERF_CTR_BITS-1:0] idles;
        logic [`PERF_CTR_BITS-1:0] stalls;
    } sched_perf_t;

    typedef struct packed {
        logic [`PERF_CTR_BITS-1:0] ibf_stalls;
        logic [`PERF_CTR_BITS-1:0] scb_stalls;
        logic [`PERF_CTR_BITS-1:0] opd_stalls;
        logic [`NUM_EX_UNITS-1:0][`PERF_CTR_BITS-1:0] units_uses;
        logic [`NUM_SFU_UNITS-1:0][`PERF_CTR_BITS-1:0] sfu_uses;
    } issue_perf_t;

    //////////////////////// instruction arguments ////////////////////////////

    typedef struct packed {
        logic use_PC;
        logic use_imm;
        logic is_w;
        logic [`ALU_TYPE_BITS-1:0] xtype;
        logic [`IMM_BITS-1:0] imm;
    } alu_args_t;

    typedef struct packed {
        logic [($bits(alu_args_t)-`INST_FRM_BITS-`INST_FMT_BITS)-1:0] __padding; 
        logic [`INST_FRM_BITS-1:0] frm;
        logic [`INST_FMT_BITS-1:0] fmt;
    } fpu_args_t;

    typedef struct packed {
        logic [($bits(alu_args_t)-1-1-`OFFSET_BITS)-1:0] __padding;
        logic is_store;
        logic is_float;
        logic [`OFFSET_BITS-1:0] offset;
    } lsu_args_t;

    typedef struct packed {
        logic [($bits(alu_args_t)-1-`VX_CSR_ADDR_BITS-5)-1:0] __padding;
        logic use_imm;
        logic [`VX_CSR_ADDR_BITS-1:0] addr;
        logic [4:0] imm;
    } csr_args_t;

    typedef struct packed {
        logic [($bits(alu_args_t)-1)-1:0] __padding; // 填充到和其他 args 一样宽，方便后续的 union 操作
        logic is_neg;   // 
    } wctl_args_t;
    
    // union of all instruction arguments, used for easier decoding and issue logic
    typedef union packed {
        alu_args_t  alu;
        fpu_args_t  fpu;
        lsu_args_t  lsu;
        csr_args_t  csr;
        wctl_args_t wctl;
    } op_args_t;

`IGNORE_UNUSED_BEGIN

    ///////////////////////// LSU memory Parameters ///////////////////////////

    localparam LSU_WORD_SIZE        = `XLEN / 8;
    localparam LSU_ADDR_WIDTH	    = (`MEM_ADDR_WIDTH - `CLOG2(LSU_WORD_SIZE));         // 低位对齐
    localparam LSU_MEM_BATCHES      = 1;                                                 // 每个 LSU 请求中合并的内存访问数量，默认为 1，即不合并。可以根据需要调整这个值来增加请求的粒度，从而提高内存带宽利用率，但也可能增加请求的延迟。
    localparam LSU_TAG_ID_BITS      = (`CLOG2(`LSUQ_IN_SIZE) + `CLOG2(LSU_MEM_BATCHES)); // LSU tag 中的 ID bits，用于区分不同的请求。因为 LSU 内部可能会合并多个请求，所以需要考虑 batch 的情况
    localparam LSU_TAG_WIDTH        = (`UUID_WIDTH + LSU_TAG_ID_BITS);                   // LSU 请求的 tag bits 总宽度，包括 UUID 和 ID bits
    localparam LSU_NUM_REQS	        = `NUM_LSU_BLOCKS * `NUM_LSU_LANES;                  // 每个周期 LSU 最多可以发出的内存请求数量，取决于 LSU 的块数量和每块的通道数量

    ////////////////////////// Icache Parameters //////////////////////////////

    // Word size in bytes
    localparam ICACHE_WORD_SIZE	    = 4;     
    localparam ICACHE_ADDR_WIDTH	= (`MEM_ADDR_WIDTH - `CLOG2(ICACHE_WORD_SIZE));

    // Block size in bytes
    localparam ICACHE_LINE_SIZE	    = `L1_LINE_SIZE;

    // Core request tag Id bits  // warp ID
    localparam ICACHE_TAG_ID_BITS	= `NW_WIDTH;

    // Core request tag bits     // UUID仅用于开发调试阶段和溯源
    localparam ICACHE_TAG_WIDTH	    = (`UUID_WIDTH + ICACHE_TAG_ID_BITS);

    // Memory request data bits
    localparam ICACHE_MEM_DATA_WIDTH = (ICACHE_LINE_SIZE * 8);

    // Memory request tag bits
`ifdef ICACHE_ENABLE
    localparam ICACHE_MEM_TAG_WIDTH = `CACHE_CLUSTER_MEM_TAG_WIDTH(`ICACHE_MSHR_SIZE, 1, `NUM_ICACHES);
`else
    localparam ICACHE_MEM_TAG_WIDTH = `CACHE_CLUSTER_BYPASS_MEM_TAG_WIDTH(1, ICACHE_LINE_SIZE, ICACHE_WORD_SIZE, ICACHE_TAG_WIDTH, `SOCKET_SIZE, `NUM_ICACHES);
`endif

    ////////////////////////// Dcache Parameters //////////////////////////////

    // Word size in bytes  // LSU 每个通道的访存位宽，也是 Dcache 的数据位宽，因为 Dcache 直接和 LSU 对接
    localparam DCACHE_WORD_SIZE	    = `LSU_LINE_SIZE;
    localparam DCACHE_ADDR_WIDTH	= (`MEM_ADDR_WIDTH - `CLOG2(DCACHE_WORD_SIZE));

    // Block size in bytes
    localparam DCACHE_LINE_SIZE 	= `L1_LINE_SIZE;

    // Input request size
    localparam DCACHE_CHANNELS	    = `UP((`NUM_LSU_LANES * LSU_WORD_SIZE) / DCACHE_WORD_SIZE);
    localparam DCACHE_NUM_REQS	    = `NUM_LSU_BLOCKS * DCACHE_CHANNELS;

    // Core request tag Id bits
    localparam DCACHE_MERGED_REQS   = (`NUM_LSU_LANES * LSU_WORD_SIZE) / DCACHE_WORD_SIZE;
    localparam DCACHE_MEM_BATCHES   = `CDIV(DCACHE_MERGED_REQS, DCACHE_CHANNELS);
    localparam DCACHE_TAG_ID_BITS   = (`CLOG2(`LSUQ_OUT_SIZE) + `CLOG2(DCACHE_MEM_BATCHES));

    // Core request tag bits
    localparam DCACHE_TAG_WIDTH	    = (`UUID_WIDTH + DCACHE_TAG_ID_BITS);

    // Memory request data bits
    localparam DCACHE_MEM_DATA_WIDTH = (DCACHE_LINE_SIZE * 8);

    // Memory request tag bits
`ifdef DCACHE_ENABLE
    localparam DCACHE_MEM_TAG_WIDTH = `CACHE_CLUSTER_NC_MEM_TAG_WIDTH(`DCACHE_MSHR_SIZE, `DCACHE_NUM_BANKS, DCACHE_NUM_REQS, DCACHE_LINE_SIZE, DCACHE_WORD_SIZE, DCACHE_TAG_WIDTH, `SOCKET_SIZE, `NUM_DCACHES);
`else
    localparam DCACHE_MEM_TAG_WIDTH = `CACHE_CLUSTER_BYPASS_MEM_TAG_WIDTH(DCACHE_NUM_REQS, DCACHE_LINE_SIZE, DCACHE_WORD_SIZE, DCACHE_TAG_WIDTH, `SOCKET_SIZE, `NUM_DCACHES);
`endif

    /////////////////////////////// L1 Parameters /////////////////////////////

    localparam L1_MEM_TAG_WIDTH     = `MAX(ICACHE_MEM_TAG_WIDTH, DCACHE_MEM_TAG_WIDTH);
    localparam L1_MEM_ARB_TAG_WIDTH = (L1_MEM_TAG_WIDTH + `CLOG2(2));

    /////////////////////////////// L2 Parameters /////////////////////////////

    localparam ICACHE_MEM_ARB_IDX = 0;
    localparam DCACHE_MEM_ARB_IDX = ICACHE_MEM_ARB_IDX + 1;

    // Word size in bytes
    localparam L2_WORD_SIZE	        = `L1_LINE_SIZE;

    // Input request size
    localparam L2_NUM_REQS	        = `NUM_SOCKETS;

    // Core request tag bits
    localparam L2_TAG_WIDTH	        = L1_MEM_ARB_TAG_WIDTH;

    // Memory request data bits
    localparam L2_MEM_DATA_WIDTH	= (`L2_LINE_SIZE * 8);

    // Memory request tag bits
`ifdef L2_ENABLE
    localparam L2_MEM_TAG_WIDTH     = `CACHE_NC_MEM_TAG_WIDTH(`L2_MSHR_SIZE, `L2_NUM_BANKS, L2_NUM_REQS, `L2_LINE_SIZE, L2_WORD_SIZE, L2_TAG_WIDTH);
`else
    localparam L2_MEM_TAG_WIDTH     = `CACHE_BYPASS_TAG_WIDTH(L2_NUM_REQS, `L2_LINE_SIZE, L2_WORD_SIZE, L2_TAG_WIDTH);
`endif

    /////////////////////////////// L3 Parameters /////////////////////////////

    // Word size in bytes
    localparam L3_WORD_SIZE	        = `L2_LINE_SIZE;

    // Input request size
    localparam L3_NUM_REQS	        = `NUM_CLUSTERS;

    // Core request tag bits
    localparam L3_TAG_WIDTH	        = L2_MEM_TAG_WIDTH;

    // Memory request data bits
    localparam L3_MEM_DATA_WIDTH	= (`L3_LINE_SIZE * 8);

    // Memory request tag bits
`ifdef L3_ENABLE
    localparam L3_MEM_TAG_WIDTH     = `CACHE_NC_MEM_TAG_WIDTH(`L3_MSHR_SIZE, `L3_NUM_BANKS, L3_NUM_REQS, `L3_LINE_SIZE, L3_WORD_SIZE, L3_TAG_WIDTH);
`else
    localparam L3_MEM_TAG_WIDTH     = `CACHE_BYPASS_TAG_WIDTH(L3_NUM_REQS, `L3_LINE_SIZE, L3_WORD_SIZE, L3_TAG_WIDTH);
`endif

    /////////////////////////////// Issue parameters //////////////////////////

    localparam ISSUE_ISW   = `CLOG2(`ISSUE_WIDTH);    //ISSUE_WIDTH = `UP(`NUM_WARPS / 8)
    localparam ISSUE_ISW_W = `UP(ISSUE_ISW);
    localparam PER_ISSUE_WARPS = `NUM_WARPS / `ISSUE_WIDTH;   //
    localparam ISSUE_WIS   = `CLOG2(PER_ISSUE_WARPS);
    localparam ISSUE_WIS_W = `UP(ISSUE_WIS);
    // 例如：core支持16个warp，那么会配置2个issue单元，每个issue单元调度8个warp；PER_ISSUE_WARPS是8。
    // 我们需要建立warp到issue单元的映射，wid是对16个warp的编号；
    // isw是映射到那个issue单元的编号，1bit，其实就是wid的高位;  
    // wis是对一个issue单元负责的8个warp的编号，3bit，就是wid的低3位。
    // 通过isw和wis，我们就可以知道一个指令属于哪个warp，以及这个warp由哪个issue单元调度。
    function logic [`NW_WIDTH-1:0] wis_to_wid(
        input logic [ISSUE_WIS_W-1:0] wis,
        input logic [ISSUE_ISW_W-1:0] isw
    );
        if (ISSUE_WIS == 0) begin
            wis_to_wid = `NW_WIDTH'(isw);
        end else if (ISSUE_ISW == 0) begin
            wis_to_wid = `NW_WIDTH'(wis);
        end else begin
            wis_to_wid = `NW_WIDTH'({wis, isw});
        end
    endfunction

    function logic [ISSUE_ISW_W-1:0] wid_to_isw(
        input logic [`NW_WIDTH-1:0] wid
    );
        if (ISSUE_ISW != 0) begin
            wid_to_isw = wid[ISSUE_ISW_W-1:0];
        end else begin
            wid_to_isw = 0;
        end
    endfunction

    function logic [ISSUE_WIS_W-1:0] wid_to_wis(
        input logic [`NW_WIDTH-1:0] wid
    );
        if (ISSUE_WIS != 0) begin
            wid_to_wis = ISSUE_WIS_W'(wid >> ISSUE_ISW);
        end else begin
            wid_to_wis = 0;
        end
    endfunction

    ///////////////////////// Miscaellaneous functions ////////////////////////

    function logic [`SFU_WIDTH-1:0] op_to_sfu_type(
        input logic [`INST_OP_BITS-1:0] op_type
    );
        case (op_type)
        `INST_SFU_CSRRW,
        `INST_SFU_CSRRS,
        `INST_SFU_CSRRC: op_to_sfu_type = `SFU_CSRS;
        default: op_to_sfu_type = `SFU_WCTL;
        endcase
    endfunction

`IGNORE_UNUSED_END

endpackage

`endif // VX_GPU_PKG_VH
