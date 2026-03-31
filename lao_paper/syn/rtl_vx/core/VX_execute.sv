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

module VX_execute import VX_gpu_pkg::*; #(
    parameter `STRING INSTANCE_ID = "",
    parameter CORE_ID = 0
) (
    `SCOPE_IO_DECL

    input wire              clk,
    input wire              reset,

`ifdef PERF_ENABLE
    VX_mem_perf_if.slave    mem_perf_if,
    VX_pipeline_perf_if.slave pipeline_perf_if,
`endif

    input base_dcrs_t       base_dcrs,

    // Dcache interface
    VX_lsu_mem_if.master    lsu_mem_if [`NUM_LSU_BLOCKS],

    // dispatch interface
    VX_dispatch_if.slave    dispatch_if [`NUM_EX_UNITS * `ISSUE_WIDTH],

    // commit interface
    VX_commit_if.master     commit_if [`NUM_EX_UNITS * `ISSUE_WIDTH],

    // scheduler interfaces
    VX_sched_csr_if.slave   sched_csr_if,
    VX_branch_ctl_if.master branch_ctl_if [`NUM_ALU_BLOCKS],
    VX_warp_ctl_if.master   warp_ctl_if,

    // commit interface
    VX_commit_csr_if.slave  commit_csr_if
);

`ifdef EXT_F_ENABLE
    VX_fpu_csr_if fpu_csr_if[`NUM_FPU_BLOCKS]();
`endif

    VX_dispatch_if dispatch_if_alu [`ISSUE_WIDTH]();
    VX_commit_if   commit_if_alu   [`ISSUE_WIDTH]();
    VX_dispatch_if dispatch_if_lsu [`ISSUE_WIDTH]();
    VX_commit_if   commit_if_lsu   [`ISSUE_WIDTH]();
    VX_dispatch_if dispatch_if_sfu [`ISSUE_WIDTH]();
    VX_commit_if   commit_if_sfu   [`ISSUE_WIDTH]();
`ifdef EXT_F_ENABLE
    VX_dispatch_if dispatch_if_fpu [`ISSUE_WIDTH]();
    VX_commit_if   commit_if_fpu   [`ISSUE_WIDTH]();
`endif

    for (genvar i = 0; i < `ISSUE_WIDTH; i++) begin
        assign dispatch_if_alu[i].valid = dispatch_if[`EX_ALU * `ISSUE_WIDTH + i].valid;
        assign dispatch_if_alu[i].data  = dispatch_if[`EX_ALU * `ISSUE_WIDTH + i].data;
        assign dispatch_if[`EX_ALU * `ISSUE_WIDTH + i].ready = dispatch_if_alu[i].ready;
        assign commit_if[`EX_ALU * `ISSUE_WIDTH + i].valid = commit_if_alu[i].valid;
        assign commit_if[`EX_ALU * `ISSUE_WIDTH + i].data  = commit_if_alu[i].data;
        assign commit_if_alu[i].ready = commit_if[`EX_ALU * `ISSUE_WIDTH + i].ready;

        assign dispatch_if_lsu[i].valid = dispatch_if[`EX_LSU * `ISSUE_WIDTH + i].valid;
        assign dispatch_if_lsu[i].data  = dispatch_if[`EX_LSU * `ISSUE_WIDTH + i].data;
        assign dispatch_if[`EX_LSU * `ISSUE_WIDTH + i].ready = dispatch_if_lsu[i].ready;
        assign commit_if[`EX_LSU * `ISSUE_WIDTH + i].valid = commit_if_lsu[i].valid;
        assign commit_if[`EX_LSU * `ISSUE_WIDTH + i].data  = commit_if_lsu[i].data;
        assign commit_if_lsu[i].ready = commit_if[`EX_LSU * `ISSUE_WIDTH + i].ready;

        assign dispatch_if_sfu[i].valid = dispatch_if[`EX_SFU * `ISSUE_WIDTH + i].valid;
        assign dispatch_if_sfu[i].data  = dispatch_if[`EX_SFU * `ISSUE_WIDTH + i].data;
        assign dispatch_if[`EX_SFU * `ISSUE_WIDTH + i].ready = dispatch_if_sfu[i].ready;
        assign commit_if[`EX_SFU * `ISSUE_WIDTH + i].valid = commit_if_sfu[i].valid;
        assign commit_if[`EX_SFU * `ISSUE_WIDTH + i].data  = commit_if_sfu[i].data;
        assign commit_if_sfu[i].ready = commit_if[`EX_SFU * `ISSUE_WIDTH + i].ready;
    end

`ifdef EXT_F_ENABLE
    for (genvar i = 0; i < `ISSUE_WIDTH; i++) begin
        assign dispatch_if_fpu[i].valid = dispatch_if[`EX_FPU * `ISSUE_WIDTH + i].valid;
        assign dispatch_if_fpu[i].data  = dispatch_if[`EX_FPU * `ISSUE_WIDTH + i].data;
        assign dispatch_if[`EX_FPU * `ISSUE_WIDTH + i].ready = dispatch_if_fpu[i].ready;
        assign commit_if[`EX_FPU * `ISSUE_WIDTH + i].valid = commit_if_fpu[i].valid;
        assign commit_if[`EX_FPU * `ISSUE_WIDTH + i].data  = commit_if_fpu[i].data;
        assign commit_if_fpu[i].ready = commit_if[`EX_FPU * `ISSUE_WIDTH + i].ready;
    end
`endif

    `RESET_RELAY (alu_reset, reset);
    `RESET_RELAY (lsu_reset, reset);
    `RESET_RELAY (sfu_reset, reset);

    VX_alu_unit #(
        .INSTANCE_ID ("")
    ) alu_unit (
        .clk            (clk),
        .reset          (alu_reset),
        .dispatch_if    (dispatch_if_alu),
        .commit_if      (commit_if_alu),
        .branch_ctl_if  (branch_ctl_if)
    );

    `SCOPE_IO_SWITCH (1)

    VX_lsu_unit #(
        .INSTANCE_ID ("")
    ) lsu_unit (
        `SCOPE_IO_BIND  (0)
        .clk            (clk),
        .reset          (lsu_reset),
        .dispatch_if    (dispatch_if_lsu),
        .commit_if      (commit_if_lsu),
        .lsu_mem_if     (lsu_mem_if)
    );

`ifdef EXT_F_ENABLE
    `RESET_RELAY (fpu_reset, reset);

    VX_fpu_unit #(
        .INSTANCE_ID ("")
    ) fpu_unit (
        .clk            (clk),
        .reset          (fpu_reset),
        .dispatch_if    (dispatch_if_fpu),
        .commit_if      (commit_if_fpu),
        .fpu_csr_if     (fpu_csr_if)
    );
`endif

    VX_sfu_unit #(
        .INSTANCE_ID (""),
        .CORE_ID (CORE_ID)
    ) sfu_unit (
        .clk            (clk),
        .reset          (sfu_reset),
    `ifdef PERF_ENABLE
        .mem_perf_if    (mem_perf_if),
        .pipeline_perf_if (pipeline_perf_if),
    `endif
        .base_dcrs      (base_dcrs),
        .dispatch_if    (dispatch_if_sfu),
        .commit_if      (commit_if_sfu),
    `ifdef EXT_F_ENABLE
        .fpu_csr_if     (fpu_csr_if),
    `endif
        .commit_csr_if  (commit_csr_if),
        .sched_csr_if   (sched_csr_if),
        .warp_ctl_if    (warp_ctl_if)
    );

endmodule
