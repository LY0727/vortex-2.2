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

module VX_schedule import VX_gpu_pkg::*; #(
    parameter `STRING INSTANCE_ID = "",
    parameter CORE_ID = 0
) (
    input wire              clk,
    input wire              reset,

`ifdef PERF_ENABLE
    output sched_perf_t     sched_perf,
`endif

    // configuration
    input base_dcrs_t       base_dcrs,        

    // inputs decode_if
    VX_warp_ctl_if.slave    warp_ctl_if,
    VX_branch_ctl_if.slave  branch_ctl_if [`NUM_ALU_BLOCKS],
    VX_decode_sched_if.slave decode_sched_if,
    VX_commit_sched_if.slave commit_sched_if,

    // outputs
    VX_schedule_if.master   schedule_if,
`ifdef GBAR_ENABLE
    VX_gbar_bus_if.master   gbar_bus_if,
`endif
    VX_sched_csr_if.master  sched_csr_if,

    // status
    output wire             busy
);
    `UNUSED_SPARAM (INSTANCE_ID)
    `UNUSED_PARAM (CORE_ID)

    reg [`NUM_WARPS-1:0] active_warps, active_warps_n; // updated when a warp is activated or disabled
    reg [`NUM_WARPS-1:0] stalled_warps, stalled_warps_n;  // set when branch/gpgpu instructions are issued

    reg [`NUM_WARPS-1:0][`NUM_THREADS-1:0] thread_masks, thread_masks_n;
    reg [`NUM_WARPS-1:0][`PC_BITS-1:0] warp_pcs, warp_pcs_n;

    wire [`NW_WIDTH-1:0]    schedule_wid;
    wire [`NUM_THREADS-1:0] schedule_tmask;
    wire [`PC_BITS-1:0]     schedule_pc;
    wire                    schedule_valid;
    wire                    schedule_ready;

    // split/join
    wire                    join_valid;
    wire                    join_is_dvg;    // join指令对应的分支是否发生了分支发散（divergence）
    wire                    join_is_else;   // join指令对应的分支是否是else分支
    wire [`NW_WIDTH-1:0]    join_wid;
    wire [`NUM_THREADS-1:0] join_tmask;
    wire [`PC_BITS-1:0]     join_pc;

    reg [`PERF_CTR_BITS-1:0] cycles;

    reg [`NUM_WARPS-1:0][`UUID_WIDTH-1:0] issued_instrs; 

    wire schedule_fire = schedule_valid && schedule_ready;
    wire schedule_if_fire = schedule_if.valid && schedule_if.ready;  

    // branch
    wire [`NUM_ALU_BLOCKS-1:0]                  branch_valid;
    wire [`NUM_ALU_BLOCKS-1:0][`NW_WIDTH-1:0]   branch_wid;
    wire [`NUM_ALU_BLOCKS-1:0]                  branch_taken;// 这个taken信号是branch指令本身的结果，
    wire [`NUM_ALU_BLOCKS-1:0][`PC_BITS-1:0]    branch_dest; // 这个dest是绝对地址，由branch unit计算得到的分支目标地址
    for (genvar i = 0; i < `NUM_ALU_BLOCKS; ++i) begin
        assign branch_valid[i] = branch_ctl_if[i].valid;
        assign branch_wid[i]   = branch_ctl_if[i].wid;
        assign branch_taken[i] = branch_ctl_if[i].taken;  
        assign branch_dest[i]  = branch_ctl_if[i].dest;   
    end

    // barriers
    reg [`NUM_BARRIERS-1:0][`NUM_WARPS-1:0] barrier_masks, barrier_masks_n; // 记录每个barrier已经到达的warp
    reg [`NUM_BARRIERS-1:0][`NW_WIDTH-1:0] barrier_ctrs, barrier_ctrs_n;    // 到达barrier的warp数量
    reg [`NUM_WARPS-1:0] barrier_stalls, barrier_stalls_n;                  // stall 控制位，为1表示对应的warp正在等待barrier
    reg [`NUM_WARPS-1:0] curr_barrier_mask_p1;
`ifdef GBAR_ENABLE
    reg gbar_req_valid;
    reg [`NB_WIDTH-1:0] gbar_req_id;
    reg [`NC_WIDTH-1:0] gbar_req_size_m1;
`endif

    // wspawn
    wspawn_t wspawn;
    reg [`NW_WIDTH-1:0] wspawn_wid;  // 接收来自wspawn指令的wid，等到下一个周期真正发出wspawn信号时使用
    reg is_single_warp;              // 只有一个warp活跃时为1

    wire [`CLOG2(`NUM_WARPS+1)-1:0] active_warps_cnt;
    `POP_COUNT(active_warps_cnt, active_warps);

    always @(*) begin
        active_warps_n  = active_warps;
        stalled_warps_n = stalled_warps;
        thread_masks_n  = thread_masks;
        barrier_masks_n = barrier_masks;
        barrier_ctrs_n  = barrier_ctrs;
        barrier_stalls_n= barrier_stalls;
        warp_pcs_n      = warp_pcs;

        // wspawn handling  激活warp，设置每个warp的线程掩码和PC，解锁warp
        if (wspawn.valid && is_single_warp) begin
            active_warps_n |= wspawn.wmask;
            for (integer i = 0; i < `NUM_WARPS; ++i) begin
                if (wspawn.wmask[i]) begin
                    thread_masks_n[i][0] = 1;
                    warp_pcs_n[i] = wspawn.pc;
                end
            end
            stalled_warps_n[wspawn_wid] = 0; // unlock warp
        end

        // TMC handling   直接设置该warp的线程掩码，解锁warp
        if (warp_ctl_if.valid && warp_ctl_if.tmc.valid) begin
            active_warps_n[warp_ctl_if.wid]  = (warp_ctl_if.tmc.tmask != 0);
            thread_masks_n[warp_ctl_if.wid]  = warp_ctl_if.tmc.tmask;
            stalled_warps_n[warp_ctl_if.wid] = 0; // unlock warp
        end

        // split handling  如果发生了分支发散，则设置该warp的tmask=then_tmask; 如果没有发散，自然就不需要设置；解锁warp
        if (warp_ctl_if.valid && warp_ctl_if.split.valid) begin
            if (warp_ctl_if.split.is_dvg) begin
                thread_masks_n[warp_ctl_if.wid] = warp_ctl_if.split.then_tmask;
            end
            stalled_warps_n[warp_ctl_if.wid] = 0; // unlock warp
        end

        // join handling   
        if (join_valid) begin
            if (join_is_dvg) begin
                if (join_is_else) begin
                    warp_pcs_n[join_wid] = join_pc;
                end
                thread_masks_n[join_wid] = join_tmask;
            end
            stalled_warps_n[join_wid] = 0; // unlock warp
        end

        // barrier handling
        curr_barrier_mask_p1 = barrier_masks[warp_ctl_if.barrier.id];
        curr_barrier_mask_p1[warp_ctl_if.wid] = 1;   // 本次到达的warp，加上之前已经到达的warp，组成新的mask
        if (warp_ctl_if.valid && warp_ctl_if.barrier.valid) begin
            if (~warp_ctl_if.barrier.is_noop) begin
                if (~warp_ctl_if.barrier.is_global 
                 && (barrier_ctrs[warp_ctl_if.barrier.id] == `NW_WIDTH'(warp_ctl_if.barrier.size_m1))) begin
                    barrier_ctrs_n[warp_ctl_if.barrier.id] = '0; // reset barrier counter
                    barrier_masks_n[warp_ctl_if.barrier.id] = '0; // reset barrier mask
                    stalled_warps_n &= ~barrier_masks[warp_ctl_if.barrier.id]; // unlock warps
                    stalled_warps_n[warp_ctl_if.wid] = 0; // unlock warp
                end else begin
                    barrier_ctrs_n[warp_ctl_if.barrier.id] = barrier_ctrs[warp_ctl_if.barrier.id] + `NW_WIDTH'(1);
                    barrier_masks_n[warp_ctl_if.barrier.id] = curr_barrier_mask_p1;
                end
            end else begin
                stalled_warps_n[warp_ctl_if.wid] = 0; // unlock warp； 虽然是bar指令，但是不需要等待，直接解锁warp继续执行后续指令
            end
        end
    `ifdef GBAR_ENABLE
        if (gbar_bus_if.rsp_valid && (gbar_req_id == gbar_bus_if.rsp_id)) begin
            barrier_ctrs_n[warp_ctl_if.barrier.id] = '0; // reset barrier counter
            barrier_masks_n[gbar_bus_if.rsp_id] = '0; // reset barrier mask
            stalled_warps_n = '0; // unlock all warps
        end
    `endif

        // Branch handling    根据branch指令的结果，更新该warp的PC为分支目标地址，解锁warp
        for (integer i = 0; i < `NUM_ALU_BLOCKS; ++i) begin
            if (branch_valid[i]) begin
                if (branch_taken[i]) begin
                    warp_pcs_n[branch_wid[i]] = branch_dest[i];
                end
                stalled_warps_n[branch_wid[i]] = 0; // unlock warp
            end
        end

        // decode unlock  如果decode阶段发出的指令不是wstall指令（哪些是wstall指令：），就解锁对应的warp
        if (decode_sched_if.valid && ~decode_sched_if.is_wstall) begin
            stalled_warps_n[decode_sched_if.wid] = 0;
        end

        // CSR unlock
        if (sched_csr_if.unlock_warp) begin
            stalled_warps_n[sched_csr_if.unlock_wid] = 0;
        end

        // stall the warp until decode stage     
        if (schedule_fire) begin
            stalled_warps_n[schedule_wid] = 1;
        end

        // advance PC  // 这里应该是RISCV考虑指令长度是16/32位，所以每条指令的PC至少增加2；如果是分支指令，PC在branch handling里已经被更新了，这里就不需要再增加了
        // 可以看到，sche内调度后就马上stall， 但是PC更新应该以fetch拿到sche包为准。
        if (schedule_if_fire) begin
            warp_pcs_n[schedule_if.data.wid] = schedule_if.data.PC + `PC_BITS'(2);
        end
    end

    `UNUSED_VAR (base_dcrs)

    always @(posedge clk) begin
        if (reset) begin
            barrier_masks   <= '0;
            barrier_ctrs    <= '0;
        `ifdef GBAR_ENABLE
            gbar_req_valid  <= 0;
        `endif
            stalled_warps   <= '0;
            warp_pcs        <= '0;
            active_warps    <= '0;
            thread_masks    <= '0;
            barrier_stalls  <= '0;
            issued_instrs   <= '0;
            cycles          <= '0;
            wspawn.valid    <=  0;

            // activate first warp
            warp_pcs[0]     <= base_dcrs.startup_addr[1 +: `PC_BITS];   // 这为什么是 1 +: ?； RISCV指令特性，LSB位不需要考虑。
            active_warps[0] <= 1;
            thread_masks[0][0] <= 1;
            is_single_warp  <= 1;
        end else begin
            active_warps   <= active_warps_n;   
            stalled_warps  <= stalled_warps_n;
            thread_masks   <= thread_masks_n;
            warp_pcs       <= warp_pcs_n;
            barrier_masks  <= barrier_masks_n;
            barrier_ctrs   <= barrier_ctrs_n;
            barrier_stalls <= barrier_stalls_n;
            is_single_warp <= (active_warps_cnt == $bits(active_warps_cnt)'(1));  // 只有一个warp活跃

            // wspawn handling
            if (warp_ctl_if.valid && warp_ctl_if.wspawn.valid) begin
                wspawn.valid <= 1;
                wspawn.wmask <= warp_ctl_if.wspawn.wmask;
                wspawn.pc    <= warp_ctl_if.wspawn.pc;
                wspawn_wid   <= warp_ctl_if.wid;
            end
            if (wspawn.valid && is_single_warp) begin
                wspawn.valid <= 0;
            end

            // global barrier scheduling
        `ifdef GBAR_ENABLE
            if (warp_ctl_if.valid && warp_ctl_if.barrier.valid
             && warp_ctl_if.barrier.is_global
             && !warp_ctl_if.barrier.is_noop
             && (curr_barrier_mask_p1 == active_warps)) begin
                gbar_req_valid <= 1;
                gbar_req_id <= warp_ctl_if.barrier.id;
                gbar_req_size_m1 <= `NC_WIDTH'(warp_ctl_if.barrier.size_m1);
            end
            if (gbar_bus_if.req_valid && gbar_bus_if.req_ready) begin
                gbar_req_valid <= 0;
            end
        `endif

            if (schedule_if_fire) begin
                issued_instrs[schedule_if.data.wid] <= issued_instrs[schedule_if.data.wid] + `UUID_WIDTH'(1);
            end
            // performance counter
            if (busy) begin
                cycles <= cycles + 1;
            end
        end
    end

    // barrier handling

`ifdef GBAR_ENABLE
    assign gbar_bus_if.req_valid   = gbar_req_valid;
    assign gbar_bus_if.req_id      = gbar_req_id;
    assign gbar_bus_if.req_size_m1 = gbar_req_size_m1;
    assign gbar_bus_if.req_core_id = `NC_WIDTH'(CORE_ID % `NUM_CORES);
`endif

    // split/join handling

    `RESET_RELAY (split_join_reset, reset);

    VX_split_join #(
        .INSTANCE_ID ($sformatf("%s-splitjoin", INSTANCE_ID))
    ) split_join (
        .clk        (clk),
        .reset      (split_join_reset),
        .valid      (warp_ctl_if.valid),
        .wid        (warp_ctl_if.wid),
        .split      (warp_ctl_if.split), // split_t
        .sjoin      (warp_ctl_if.sjoin), // join_t
        .join_valid (join_valid),
        .join_is_dvg(join_is_dvg),
        .join_is_else(join_is_else),   
        .join_wid   (join_wid),
        .join_tmask (join_tmask),
        .join_pc    (join_pc),
        .stack_wid  (warp_ctl_if.dvstack_wid),
        .stack_ptr  (warp_ctl_if.dvstack_ptr)
    );

    // schedule the next ready warp
    // 活跃的未被阻塞的warps
    wire [`NUM_WARPS-1:0] ready_warps = active_warps & ~stalled_warps;
    // 前导零计数器，也就是低位优先的固定优先级仲裁。 因为只要调度有效，这个warp马上就会被stall，所以实际类似循环（但其实没有严格轮询，因为最快的情况在译码后就可以unlock，warp较多的情况下，它比还未轮询到的warp优先级更高）
    VX_lzc #(
        .N (`NUM_WARPS),
        .REVERSE (1)
    ) wid_select (
        .data_in   (ready_warps),
        .data_out  (schedule_wid),
        .valid_out (schedule_valid)
    );
    //  schedule_data  这里莫名奇妙，没有任何作用，像是遗留代码。最新仓库里面依然有？为了波形找信号嘛？
    wire [`NUM_WARPS-1:0][(`NUM_THREADS + `PC_BITS)-1:0] schedule_data;
    for (genvar i = 0; i < `NUM_WARPS; ++i) begin
        assign schedule_data[i] = {thread_masks[i], warp_pcs[i]};
    end

    assign {schedule_tmask, schedule_pc} = {
        schedule_data[schedule_wid][(`NUM_THREADS + `PC_BITS)-1:(`NUM_THREADS + `PC_BITS)-4],
        schedule_data[schedule_wid][(`NUM_THREADS + `PC_BITS)-5:0]
    };

    // 注意到 uuid信号，完全是为了方便开发调试，实际硬件不用在意。 它的生成方式是：
    // 如果定义了SV_DPI，就调用dpi_uuid_gen这个DPI函数来生成uuid；
    // 如果没有定义SV_DPI，就根据CORE_ID、schedule_wid和schedule_pc组合成一个uuid。
    // 无论哪种方式，uuid都是为了唯一标识每条指令的，方便在仿真波形中观察和调试。
`ifndef NDEBUG
    localparam GNW_WIDTH = `LOG2UP(`NUM_CLUSTERS * `NUM_CORES * `NUM_WARPS);
    reg [`UUID_WIDTH-1:0] instr_uuid;
    wire [GNW_WIDTH-1:0] g_wid = (GNW_WIDTH'(CORE_ID) << `NW_BITS) + GNW_WIDTH'(schedule_wid);
`ifdef SV_DPI
    always @(posedge clk) begin
        if (reset) begin
            instr_uuid <= `UUID_WIDTH'(dpi_uuid_gen(1, 32'd0));
        end else if (schedule_fire) begin
            instr_uuid <= `UUID_WIDTH'(dpi_uuid_gen(0, 32'(g_wid)));
        end
    end
`else
    wire [GNW_WIDTH+16-1:0] w_uuid = {g_wid, 16'(schedule_pc)};
    always @(*) begin
        instr_uuid = `UUID_WIDTH'(w_uuid);
    end
`endif
`else
    wire [`UUID_WIDTH-1:0] instr_uuid = '0;  // 在非调试模式下，uuid位宽为1，赋值为0.
`endif
    //  这里最后硬件是：一个带有组合逻辑前馈的单极D触发器打拍器。 其实就是前向切割寄存器。
    VX_elastic_buffer #(
        .DATAW (`NUM_THREADS + `PC_BITS + `NW_WIDTH)
    ) out_buf (
        .clk       (clk),
        .reset     (reset),
        .valid_in  (schedule_valid),
        .ready_in  (schedule_ready),
        .data_in   ({schedule_tmask, schedule_pc, schedule_wid}),
        .data_out  ({schedule_if.data.tmask, schedule_if.data.PC, schedule_if.data.wid}),
        .valid_out (schedule_if.valid),
        .ready_out (schedule_if.ready)
    );

    assign schedule_if.data.uuid = instr_uuid;

    // Track pending instructions per warp
    // 这里的pending指的是已经被调度出去但还没有提交的指令。 这个计数器在schedule阶段增加，在commit阶段减少。
    reg [`NUM_WARPS-1:0] per_warp_incr;
    always @(*) begin
        per_warp_incr = 0;
        if (schedule_if_fire) begin
            per_warp_incr[schedule_if.data.wid] = 1;
        end
    end

    wire [`NUM_WARPS-1:0] pending_warp_empty;
    wire [`NUM_WARPS-1:0] pending_warp_alm_empty;   // 这里的almost empty是指只有1条pending指令了。 这个信号在调度时可以用来判断该warp是否即将没有pending指令了，从而可以优先调度它，以避免出现某些warp长时间没有机会被调度的情况。

    `RESET_RELAY_EX (pending_instr_reset, reset, `NUM_WARPS, `MAX_FANOUT);
    // 这里为每个warp维护一个计数器，记录该warp已经调度出去但还没有提交的指令数量。 
    // 调度时+1；commit提交时-1；当计数器为0时，表示该warp没有pending指令。
    for (genvar i = 0; i < `NUM_WARPS; ++i) begin

        VX_pending_size #(
            .SIZE      (4096),
            .ALM_EMPTY (1)
        ) counter (
            .clk       (clk),
            .reset     (pending_instr_reset[i]),
            .incr      (per_warp_incr[i]),
            .decr      (commit_sched_if.committed_warps[i]),
            .empty     (pending_warp_empty[i]),
            .alm_empty (pending_warp_alm_empty[i]),
            `UNUSED_PIN (full),
            `UNUSED_PIN (alm_full),
            `UNUSED_PIN (size)
        );
	end

    assign sched_csr_if.alm_empty = pending_warp_alm_empty[sched_csr_if.alm_empty_wid];

    wire no_pending_instr = (& pending_warp_empty); // 所有warp的pending计数器都为0，说明没有任何warp有pending指令了。

    `BUFFER_EX(busy, (active_warps != 0 || ~no_pending_instr), 1'b1, 1); // busy信号表示调度器是否有活跃的warp或者有pending指令，如果没有活跃的warp且没有pending指令了，就认为调度器空闲了。

    // export CSRs； 
    //  这里的CSR接口主要是为了提供一些调试和性能监控的功能，比如周期计数器、活跃warp数量、线程掩码等。 
    //  实际上，这些信息在硬件中是很容易获取的，直接通过寄存器或者组合逻辑就可以了，不需要复杂的CSR机制。
    assign sched_csr_if.cycles = cycles;    
    assign sched_csr_if.active_warps = active_warps;
    assign sched_csr_if.thread_masks = thread_masks;

   // timeout handling
    reg [31:0] timeout_ctr;
    reg timeout_enable;
    always @(posedge clk) begin
        if (reset) begin
            timeout_ctr    <= '0;
            timeout_enable <= 0;
        end else begin
            if (decode_sched_if.valid && ~decode_sched_if.is_wstall) begin
                timeout_enable <= 1;
            end
            if (timeout_enable && active_warps !=0 && active_warps == stalled_warps) begin
                timeout_ctr <= timeout_ctr + 1;
            end else if (active_warps == 0 || active_warps != stalled_warps) begin
                timeout_ctr <= '0;
            end
        end
    end
    `RUNTIME_ASSERT(timeout_ctr < `STALL_TIMEOUT, ("%t: *** %s timeout: stalled_warps=%b", $time, INSTANCE_ID, stalled_warps))

`ifdef PERF_ENABLE
    reg [`PERF_CTR_BITS-1:0] perf_sched_idles;
    reg [`PERF_CTR_BITS-1:0] perf_sched_stalls;

    wire schedule_idle = ~schedule_valid;
    wire schedule_stall = schedule_if.valid && ~schedule_if.ready;

    always @(posedge clk) begin
        if (reset) begin
            perf_sched_idles  <= '0;
            perf_sched_stalls <= '0;
        end else begin
            perf_sched_idles  <= perf_sched_idles + `PERF_CTR_BITS'(schedule_idle);
            perf_sched_stalls <= perf_sched_stalls + `PERF_CTR_BITS'(schedule_stall);
        end
    end

    assign sched_perf.idles = perf_sched_idles;
    assign sched_perf.stalls = perf_sched_stalls;
`endif

endmodule
