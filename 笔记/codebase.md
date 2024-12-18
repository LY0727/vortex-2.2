# Vortex Codebase

The directory/file layout of the Vortex codebase is as followed:

- `hw`:     
  - `rtl`: hardware rtl sources
  - *** Verilog Header ***
    `VX_define`: define instructions and opcode, etc.
      `VX_types`: define Device_Config_Regs and Control_&_Status_Rigs, also config Performance monitor
      `VX_config`: define GPU's configuration, for example: length of Regs, number of Warps and Threads, en/disable of Caches, Data width
      `VX_platform`: this file is invalid in vivado! may be enable in other verify
        `VX_scope`: may be <control scope in gpu core? why can switch scope's io?>
      `VX_cache_define`: hw/rtl/cache/VX_cache_define.vh; define Cache's Word/Bank/Line/Tag select 
    *** Vortex GPU package ***
    - `VX_gpu_pkg`: build packed struct for Vortex's core code
    
    *** Vortex GPU TOP ***
    `vortex_afu`: <maybe use AXI4 to AXI-lite bridge> to match Vortex GPU(as a AXI4 master) with AFU(as a AXI-lite slave)
      `afu_wrap`: match afu_ctrl with Vortex_axi
        `afu_ctrl`: work as a AXI-lite slave, also have dcr write req
        `scope_tap`: performance trace capture and state control
        `Vortex_axi`: work as AXI4 master, also have dcr write req and mem req/rsp
          `axi_adapter`: Vortex's AXI logic, Vortex link to AXI4 bus as a Master
          `Vortex`: top of Vortex GPU
          - `cluster`: define Vortex cluster based on socket
            - `socket`: fenerate socket based on VX_core
              - `core`
              - `cache_cluster`

    *** core micro architecture ***
      -`core_top`: the top level of core
        -`core`: core level, named "VX_core"
          -`dcr_data`: may be <the Device Control Register>
          -`lmem_unit`: local memory unit
            -`lsu_adapter`: LSU adapter, connect LSU and local memory
            -`local_mem`
          -`schedule`: Wrap (group of Threads) scheduler, can active warps
            -`split_join`: split and join 
              -`ipdom_stack`: Vortex IPDOM (realize SIMT-stack)
              -`pipe_register`
            -`lzc`
          -`fetch`: fetch instructions, then transfer to next stage
            -`dp_ram`
            -`scope_tap`
          -`decode`: decode satge, choose INST though opcode, 
          -`issue_top`: transmit unit, schedule instructions to units
            -`issue`
              -`issue_slice`
                -`scoreboard`: track in-used regs, check regs utilization
                -`operands`: store operands
                -`dispatch`: transmit instructions
                -`ibuffer`: store decoded insts
                -`trace_pkg`: may be <trace applications operate stats>
                -`scope_tap`
          -`execute`: execute stage, compute data
            -`sfu_unit`: special function unit, perform tracendental & trigonometric OPs
              -`dispatch_unit`: transmit instructions
              -`wctl_unit`: write control unit
              -`csr_unit`: csr register unit
                -`csr_data`: may be <select CSR mode>
              -`stream_arb`
                -`generic_arbiter`
              -`gather_unit`: may be <can gather data>
            -`alu_unit`
              -`dispatch_unit`
              -`alu_int`: ALU's int part
              -`alu_muldiv`: ALU mul & div part
              -`gather_unit`
            -`fpu_unit`
              -`dispatch_unit`
              -`fpu_dpi`: may be <fpu interfaces> or <fpu mode select>
              -`fpu_fpnew`: may be <a new RISC-V FP unit designed by openhwgroup>
              -`fpu_dsp`
            -`lsu_unit`
              -`dispatch_unit`
              -`lsu_slice`: a slice in the LSU
                -`mem_scheduler`
                -`scope_tap`: capture mem scope
          -`commit`: Commit unit, the last stage in the pipeline

    *** cache micro architecture ***
    -`cache`: cache subsystem
      -`cache_top`: single cache's top level, encapsulate cache as a black box
        -`cache`
          -`cache_flush`: flush total cache
            -`pending_size`
          -`stream_xbar`
            -`stream_arb`
          -`cache_bank`
            -`bank_flush`: flush cache's bank
            -`cache_tags`: cache's tag, can index cache's bank and line
            -`cache_mshr`: cache miss stage holding register
            -`cache_data`: store cache's data
              -`onehot_encoder`
              -`sp_ram`
          -`stream_arb`
      -`cache_cluster`: multi cache's top level, build a cluster based on cache
        -`cache_wrap`: build a wrap based on cache
          -`cache_bypass`: cache data bypass
          -`cache`

    *** mem micro architecture ***
    -`mem_arb`: mem subsystem arbiter
      -`mem_bus_if`: mem bus interface
      -`bits_remove`
      -`stream_switch`
      -`stream_arb`
    -`mem_switch`: memory switcher
      -`stream_switch`
      -`stream_arb`
    -`mem_perf_if`: memory performance interface, use performance counter record data
    -`gbar_unit`: may be <intel's global bus arbitration register unit>
      -`gbar_buf_if`
    -`gbar_arb`
    -`local_mem_top`
      -`local_mem`: local memory is in each thread block (thread wrap)
        -`pipe_buffer`
          -`pipe_register`
        -`stream_xbar`
        -`sp_ram`

    *** fpu micro architecture ***
    -`fpu_csr_if`: fpu csr register interface
      -`fpu_fma`: fpu's fused multiply-add inst
        -`shift_register`
        -`pe_sericalizer`: convert PE's parallel data to serial data
          -`shift_register`
          -`pipe_register`
        -`acl_fmadd`: for Altra Quartus IDE <use proprietary IP>
        -`xil_fma`: for Xilinx Vivado IDE <use proprietary IP>
      -`stream_arb`
    -`fpu_dsp`: fpu's digital signal process model
      -`fpu_div`: 
        -`shift_register`
        -`pe_sericalizer`
      -`fpu_sqrt`:
        -`pe_sericalizer`
        -`shift_register`
        -`acl_fsqrt`:
        -`xil_fsqrt`:
      -`fpu_cvt`: may be <the Centroidal Voronoi Tessellation>
        -`pe_sericalizer`
        -`fcvt_unit`: cvt unit
                      Normalization: renormalization input data
                      stage1: perform adjustments to mantissa and exponent
                      stage2: classify and process input data
                      stage3: process and assemble output data
          -`fp_classifier`: floatpoint classifier
          -`fp_rounding`: set floatpoint rounding
          -`pipe_register`
          -`lzc`
      -`fpu_ncp`: may be <the Numeric Computation Pipeline>
        -`fncp_unit`: ncp unit
                      FCLASS: classifier numbers
                      Min/Max: find float min and float max
                      Sign injection: add sign to result
          -`fp_classifier`
          -`pipe_register`
        -`pe_sericalizer`

    -`fpu_dpi`: may be <fpu mode select>
      -`shift_register`
      -`stream_arb`
    -`fpu_fpnew`: may be <a new RISC-V FP unit designed by openhwgroup>
      -`fpnew_top`
    -`fpu_pkg`: fpu struct package

    *** module interface ***
    - `interfaces`: interfaces for inter-module communication
      -`branch_ctl_if`
      -`commit_csr_if`
      -`commit_if`
      -`commit_sched_if`
      -`dcr_bus_if`
      -`decode_if`
      -`decode_sched_if`
      -`dispatch_if`
      -`execute_if`
      -`fetch_if`
      -`ibuffer_if`
      -`lsu_mem_if`
      -`operands_if`
      -`pipeline_perf_if`
      -`sched_csr_if`
      -`schedule_if`
      -`scoreboard_if`
      -`sfu_perf_if`
      -`warp_ctl_if`
      -`writeback_if`

    *** module librarys ***
    - `libs`: general-purpose RTL modules
      *** arbiter 仲裁器 ***
      -`cyclic_arbiter`: respond each request as a cycle
      -`fair_arbiter`: respond each request fairly, consider priority and history
      -`generic_arbiter`: control hardware blocks require
      -`matrix_arbiter`: dynamic respond, priority based on matrix
      -`priority_arbiter`: respond based on each request's priority
      -`rr_arbiter`: round-robin arbiter, the same as cyclic_arbiter
      *** adaptor 适配器 ***
      -`avs_adapter`: avs bus (a kind of power management bus) adapter
      -`axi_adapter`: AXI bus adapter
      -`elastic_adapter`
      -`mem_adapter`
      *** buffer 缓冲器 ***
      -`bypass_buffer`: if enable, output from buffer, else from data_in
      -`elastic_buffer`
      -`index_buffer`: index buffer, to optimize vertex data
      -`pipe_buffer`
      -`skid_buffer`: cache data to resolve data width or data rate mismatches 
      -`toggle_buffer`: synchronized data in each clock domain

      -`allocator`: allocate free slot
      -`bits_insert`: insert bits into data
      -`bits_remove`: remove bits from data, delete 1 bit based on N, S, POS
      -`divider`: <use Quaturs's lpm_divide IP core to build divider ?>
      -`dp_ram`: dual port ram
      -`fifo_queue`
      -`find_first`: ergodic and find the first valid data
      -`index_queue`
      -`lzc`: Leading Zero Count, to comput leading zero in wrap's thread
              leading zero: the number of consecutive zero (MSB --> LSB)
      -`mem_coalescer`: mem coalescer can incorporation multi mem request
      -`mem_scheduler`: memory scheduler, load data from mem and store to mem
      -`multiplier`
      -`mux`: multiplexer
      -`onehot_encoder`: encode onehot code
      -`onehot_mux`
      -`pe_serializer`: PE's serializer, can incorporation multi PE's output
      -`pending_size`: set cache size
      -`pipe_register`: pipeline register
      -`popcount`: can calculate the number of " 1 " in a binary number
      -`priority_encoder`: detect signal with hegiest priority, then encode and output
      -`reduce`
      -`reset_relay`: create reset signal
      -`scan`: <scan lowest data ?>
      -`scope_switch`: switch in different scope
      -`scope_tap`: may be <the scope of Thread Address Processor>
      -`serial_div`: serializer divider, only process 1 bit at once
      -`serial_mul`: serializer multiplexer
      -`shift_register`: data shift register
      -`sp_ram`: single port ram
      -`stream_arb`: stream arbiter, control compute tasks & streams
      -`stream_pack`: stream package
      -`stream_switch`
      -`stream_unpack`: stream unpackage
      -`stream_buffer`
      -`stream_xbar`: stream crossbar, joint input & output channel
      


  - `syn`: synthesis directory
    - `altera`: Altera synthesis scripts
    - `xilinx`: Xilinx synthesis scripts    
    - `synopsys`: Synopsys synthesis scripts
    - `modelsim`: Modelsim synthesis scripts
    - `yosys`: Yosys synthesis scripts
  - `unit_tests`: unit tests for some hardware components
- `runtime`: host runtime software APIs
  - `include`: Vortex driver public headers
  - `stub`: Vortex stub driver library
  - `opae`: software driver that uses Intel OPAE API with device targets=fpga|asesim|opaesim
  - `xrt`: software driver that uses Xilinx XRT API with device targets=hw|hw_emu|sw_emu
  - `rtlsim`: software driver that uses rtlsim simulator
  - `simx`: software driver that uses simX simulator
- `kernel`: GPU kernel software APIs
  - `include`: Vortex runtime public headers
  - `linker`: linker file for compiling kernels
  - `src`: runtime implementation
- `sim`: 
  - `opaesim`: Intel OPAE AFU RTL simulator
  - `rtlsim`: processor RTL simulator
  - `simX`: cycle approximate simulator for vortex
- `tests`: tests repository.
  - `riscv`: RISC-V conformance tests
  - `kernel`: kernel tests
  - `regression`: regression tests  
  - `opencl`: opencl benchmarks and tests
- `ci`: continuous integration scripts
- `miscs`: miscellaneous resources.
