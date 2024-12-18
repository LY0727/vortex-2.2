## 安装

**根据readme来；**

1. 安装配置

   1. clone;  这里之后都用 release 2.2

   ```
      git clone --depth=1 --recursive https://github.com/vortexgpgpu/vortex.git
      cd vortex
   	# 建议修改一下权限；中途遇到过不少权限问题，逐个修改太麻烦。
      chmod -R 755 /vortex-2.2
   ```

   2. 检查安装gcc 11
      ./ci/install_dependencies.sh
   3. mkdir build；  使用下面那一句
      cd build
      ../configure --xlen=32 --tooldir=$HOME/tools

      ../configure --xlen=64 --tooldir=$HOME/tools
   4. 安装工具链，但是有时候网络也不太行；下载zip本地安装的话，需要理解一下脚本内容，自己写了一个压缩解压缩脚本。
      ./ci/toolchain_install.sh --all
   5. 三个额外的依赖：    注意依赖目录；ramulator需要clone release 2； clone后需要改文件夹名称，为 cvfpu;ramulator;softfloat;   或者改makefile也行
      cd ../third_party
      git clone  git@github.com:ucb-bar/berkeley-softfloat-3.git
      git clone  git@github.com:CMU-SAFARI/ramulator2.git
      git clone  git@github.com:openhwgroup/cvfpu.git
      cd ../build
   6. 添加环境变量

      source ./ci/toolchain_env.sh

      echo "source `<build-path>`/ci/toolchain_env.sh" >> ~/.bashrc
   7. 编译
      make -s
   8. **安装目录修改：**  需要对应修改的文件有：

      1. toolchain_install.sh
      2. toolchain_env.sh
      3. config.mk
2. quick demo
   blackbox.sh脚本需要看一下；这里的命令是设置了cores，和测试项；还有一些默认配置在脚本中可见。

   ./ci/blackbox.sh --cores=2 --app=vecadd

   测试过程：

   1. 从命令的输出信息来看，主要是两个部分： runtime/simx 和 tests/opencl/vecadd     仿真器和测试应用程序。 两个目录下都有makefile
   2. 配置参数、编译运行时库simx和测试应用程序、进入测试目录、设置环境变量，执行测试程序。
   3. 具体测试程序、trace、输出结果还未研究。
3. 到这一步后建议阅读 docs/ 中的仿真文档
4. 通过makefile 来理解掌握整个工程。

## 子模块仿真分析

**路径：** /mnt/ssd2/lao/vortex-2.2/build/hw/unittest/

1. makefile： 汇总调用6个子模块的makefile
2. common.mk:  verilator编译，生成波形，查看波形
3. subdir_dir下的makefile : 针对各个子模块；准备好相应的编译环境和编译选项，各种路径、编译标志和源文件列表等预备信息。**然后调用上层目录下的common.mk 进行verilator的仿真。**



## 仿真

### 验证环境（看paper）

![1729256422620](https://vscode-remote+ssh-002dremote-002bubuntu4053.vscode-resource.vscode-cdn.net/mnt/ssd2/lao/vortex-2.2/%E7%AC%94%E8%AE%B0/image/%E5%A4%8D%E7%8E%B0%E8%AE%B0%E5%BD%95/1729256422620.png)

1、最右侧是作者团队设计的一个周期精确的Vortex GPGPU模拟器，基于SIMX Driver驱动支持Vortex应用程序的运行。
2、从最右侧过来，左边第一个是纯Vortex GPGPU的验证环境，作者借助Verilator这个开源波形验证工具向上搭建RTLSIM驱动来支持Vortex应用程序的运行。
3、再往左边过来就是，使用AFU实现基本的数据可供给的系统，作者依旧借助Verilator这个开源工具向上搭建VLSIM驱动来支持Vortex应用程序的运行。
4、最左侧就是在FPGA平台上基于OPAE驱动来支持Vortex应用程序的运行。
![1729256422620](image/复现记录/1729256422620.png)

**需要着重弄清楚： AFU**的设计，**AFU+Processor** 这样是一个完整的可用的GPGPU组件吗？  如果要移植为 CPU + GPGPU的异构结构，需要做哪些改动？

**AFU：** 指FPGA上的加速功能单元；

**OPAE：** intel提供的一个软件框架，提供一套统一的API，用于与intel FPGA进行交互。开发者可以使用 OPAE 将自己编写的加速逻辑编译成可执行的 AFU 镜像，并将其加载到 FPGA 上运行。同时，OPAE 还支持对 AFU 的运行状态进行监控和管理，方便开发者进行调试和优化。

**XRT：** Xilinx 提供的一个高性能、低延迟的运行时环境，用于在 Xilinx 的 FPGA 设备上执行加速应用。和OPAE类似。通过XRT，开发者直接在C++或者OpenCL编程模型中进行开发就可以了，无须深入学习底层硬件细节。

这两种方案之前都没有接触过，需要理清楚；目前来看，vortex提供的intel FPGA方案 FPGA板子比较简单，流程也许会更通顺；  xilinx方案针对的板子比较特殊，但xilinx发工具平时使用更多，尽量走xilinx的平台。

### simx 仿真

### verilator -- RTLsim

## FPGA部署

### 目标：

    ZCU104开发板，部署CPU+vortex异构系统，跑通软件工具链、运行时环境。

1. vortex_axi 在FPGA上综合
2. 理清cpu--vortex数据交互流程
3. 搭建cpu--vortex异构硬件soc

   部署yolov3-tiny网络进行图片推理任务。

### 踩坑记录：

1. **添加宏定义 ：**`define VIVADO ；  应该是可以最顶层添加就ok的；但是我是在头文件、top文件、fpu几个文件中 都添加了。 后续再细究这个宏定义添加方法。
2. **添加xilinx_IP：** FPU中 fdiv、fma、fsqrt使用xilinx的ip需要添加；执行如下tcl命令：

   ```
   create_ip -name floating_point -vendor xilinx.com -library ip -version 7.1 -module_name xil_fdiv
   set_property -dict [list CONFIG.Component_Name {xil_fdiv} CONFIG.Operation_Type {Divide} CONFIG.Flow_Control {NonBlocking} CONFIG.Has_ACLKEN {true} CONFIG.C_Has_UNDERFLOW {true} CONFIG.C_Has_OVERFLOW {true} CONFIG.C_Has_INVALID_OP {true} CONFIG.C_Has_DIVIDE_BY_ZERO {true} CONFIG.A_Precision_Type {Single} CONFIG.C_A_Exponent_Width {8} CONFIG.C_A_Fraction_Width {24} CONFIG.Result_Precision_Type {Single} CONFIG.C_Result_Exponent_Width {8} CONFIG.C_Result_Fraction_Width {24} CONFIG.C_Mult_Usage {No_Usage} CONFIG.Has_RESULT_TREADY {false} CONFIG.C_Latency {28} CONFIG.C_Rate {1}] [get_ips xil_fdiv]

   create_ip -name floating_point -vendor xilinx.com -library ip -version 7.1 -module_name xil_fsqrt
   set_property -dict [list CONFIG.Component_Name {xil_fsqrt} CONFIG.Operation_Type {Square_root} CONFIG.Flow_Control {NonBlocking} CONFIG.Has_ACLKEN {true} CONFIG.C_Has_INVALID_OP {true} CONFIG.A_Precision_Type {Single} CONFIG.C_A_Exponent_Width {8} CONFIG.C_A_Fraction_Width {24} CONFIG.Result_Precision_Type {Single} CONFIG.C_Result_Exponent_Width {8} CONFIG.C_Result_Fraction_Width {24} CONFIG.C_Mult_Usage {No_Usage} CONFIG.Has_RESULT_TREADY {false} CONFIG.C_Latency {28} CONFIG.C_Rate {1}] [get_ips xil_fsqrt]

   create_ip -name floating_point -vendor xilinx.com -library ip -version 7.1 -module_name xil_fma
   set_property -dict [list CONFIG.Component_Name {xil_fma} CONFIG.Operation_Type {FMA} CONFIG.Add_Sub_Value {Add} CONFIG.Flow_Control {NonBlocking} CONFIG.Has_ACLKEN {true} CONFIG.C_Has_UNDERFLOW {true} CONFIG.C_Has_OVERFLOW {true} CONFIG.C_Has_INVALID_OP {true} CONFIG.Has_A_TUSER {false} CONFIG.A_Precision_Type {Single} CONFIG.C_A_Exponent_Width {8} CONFIG.C_A_Fraction_Width {24} CONFIG.Result_Precision_Type {Single} CONFIG.C_Result_Exponent_Width {8} CONFIG.C_Result_Fraction_Width {24} CONFIG.C_Mult_Usage {Medium_Usage} CONFIG.Has_RESULT_TREADY {false} CONFIG.C_Latency {16} CONFIG.C_Rate {1} CONFIG.A_TUSER_Width {1}] [get_ips xil_fma]

   generate_target all [get_ips]

   ```
3. **排错：**

## docs

## 系统架构梳理

DCR总线：DCR总线（Device Control Register Bus）是一种用于访问和控制**设备寄存器**的总线。DCR总线通常用于配置和管理GPU系统中的各种硬件模块，通过读写DCR寄存器来实现对硬件模块的控制和状态监测。

## RTL阅读

### .vh-5个

1. [VX_scope.vh](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html)

* **作用** ：定义与调试和信号监控相关的宏。
* **主要内容** ：
  * 定义了用于调试和信号监控的输入输出信号声明、绑定和未使用信号处理的宏。
  * 定义了用于创建信号监控开关和探针的宏。
* **包含关系** ：没有包含其他文件。

2. [VX_platform.vh](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html)

* **作用** ：定义与平台相关的宏和配置。
* **主要内容** ：
  * 包含了 [VX_scope.vh](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html) 文件。
  * 定义了用于模拟和综合的各种宏，如断言、错误处理、调试块、忽略警告等。
  * 定义了与不同综合工具（如Quartus和Vivado）相关的宏。
  * 定义了一些常用的数学和逻辑操作宏，如 `CLOG2`、`MIN`、`MAX` 等。
* **包含关系** ：包含了 [VX_scope.vh](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html) 文件。

3. [VX_types.vh](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html)

* **作用** ：定义设备配置寄存器和性能监控计数器的地址和相关常量。
* **主要内容** ：
  * 定义了设备配置寄存器（DCR）和控制状态寄存器（CSR）的地址。
  * 定义了性能监控计数器的类别和地址。
  * 定义了一些与浮点操作相关的CSR地址。
  * 定义了一些与机器信息相关的CSR地址。
* **包含关系** ：没有包含其他文件。

**4. [VX_config.vh](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html)**

* **作用** ：定义与系统配置和参数相关的宏。
* **主要内容** ：
  * 定义了各种系统配置参数，如扩展使能、地址宽度、缓存配置、内存配置等。
  * 定义了与虚拟内存配置相关的宏。
  * 定义了与流水线配置相关的宏。
  * 定义了与浮点运算单元（FPU）相关的配置宏。
  * 定义了与缓存配置相关的宏。
  * 定义了与ISA扩展相关的宏。
  * 定义了设备标识相关的宏。
* **包含关系** ：没有包含其他文件。

5. [VX_define.vh](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html)

* **作用** ：定义与指令集、操作码、寄存器和其他硬件相关的宏。
* **主要内容** ：
  * 包含了 [VX_platform.vh](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html)、`VX_config.vh` 和 [VX_types.vh](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html) 文件。
  * 定义了与指令集相关的操作码和功能码。
  * 定义了与寄存器和性能计数器相关的宏。
  * 定义了与缓存和内存相关的宏。
  * 定义了一些常用的硬件操作宏，如边沿触发器、流水线寄存器、计数器等。
* **包含关系** ：包含了 [VX_platform.vh](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html)、`VX_config.vh` 和 [VX_types.vh](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html) 文件。

**包含关系：**

* [VX_define.vh](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html) 包含了 [VX_platform.vh](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html)、`VX_config.vh` 和 [VX_types.vh](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html) 文件。
* [VX_platform.vh](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html) 包含了 [VX_scope.vh](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html) 文件。
* [VX_scope.vh](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html) 和 [VX_types.vh](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html) 没有包含其他文件。
* [VX_config.vh](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html) 没有包含其他文件。

### .sv-4个顶层

#### 1. [Vortex_axi.sv](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html)

 功能：

    顶层模块，它将Vortex GPU系统与AXI总线接口连接起来。它负责处理AXI总线的读写请求，并将这些请求转换为Vortex GPU系统内部的内存请求。

 结构：

* 包含一个 `Vortex`实例，用于处理Vortex GPU系统的内部逻辑。
* 包含一个 `VX_mem_adapter`实例，用于在不同数据宽度和地址宽度之间进行转换。   该模块**输入端**是vortex；**输出端**是
* 包含一个 `VX_axi_adapter`实例，用于将内存请求转换为AXI总线请求。

对外接口：

* 调试接口：SCOPE_IO_DECL `
* 时钟和复位信号：`clk`和 `reset`
* AXI总线接口：包括读写请求地址通道、数据通道、响应通道等。
* DCR写请求接口：`dcr_wr_valid`、`dcr_wr_addr`、`dcr_wr_data`。
* 状态信号：`busy `这个应该就是kernel函数运行时向CPU反馈的busy信号。

数据流：

1. dcr总线，host发送给vortex；写gpu设备寄存器
2. vortex本身对外是 访存总线 和 DCR总线 两种接口； 其实 访存总线 可转换为 axi 接口；自然后续也可以转换为其它接口
3. 数据：vortex(req、rsp两通道) -- mem_adapter(data、addr位宽转换) -- axi_adapter(req、rsp双通道转换为axi master接口) 。

#### 2. [Vortex.sv](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html)

功能：

    Vortex GPU系统的核心模块，负责处理内存请求、DCR写请求以及系统状态管理。

结构：

* 包含一个 `VX_cache_wrap`实例，用于L3缓存的管理。
* 包含多个 `VX_cluster`实例，用于管理多个计算集群。
* 包含一个 `VX_dcr_bus_if`实例，用于DCR总线接口。

对外接口：

* 时钟和复位信号：`clk`和[reset](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html)
* 内存请求接口：`mem_req_valid`、`mem_req_rw`、`mem_req_byteen`、`mem_req_addr`、`mem_req_data`、`mem_req_tag`、`mem_req_ready`
* 内存响应接口：`mem_rsp_valid`、`mem_rsp_data`、`mem_rsp_tag`、`mem_rsp_ready`
* DCR写请求接口：`dcr_wr_valid`、`dcr_wr_addr`、`dcr_wr_data`
* 状态信号：`busy`

#### 3. [VX_cluster.sv](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html)

功能：

    grid级，负责管理集群内的多个计算单元（sockets），并处理内存请求和DCR请求。

结构：

* 包含多个 `VX_socket`实例，用于管理多个计算单元。
* 包含一个 `VX_cache_wrap`实例，用于L2缓存的管理。
* 包含一个 `VX_dcr_bus_if`实例，用于DCR总线接口。

对外接口：

* 时钟和复位信号：`clk`和[reset](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html)
* 内存请求接口：`mem_bus_if`
* DCR总线接口：`dcr_bus_if`
* 状态信号：`busy`

#### 4. [VX_socket.sv](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html)

功能：

    block级，负责管理计算单元内的多个核心（cores），并处理内存请求和DCR请求。

结构：

* 包含多个 `VX_core`实例，用于管理多个核心。
* 包含一个 `VX_cache_cluster`实例，用于L1缓存的管理。
* 包含一个 `VX_dcr_bus_if`实例，用于DCR总线接口。

对外接口：

* 时钟和复位信号：`clk`和[reset](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html)
* 内存请求接口：`mem_bus_if`
* DCR总线接口：`dcr_bus_if`
* 状态信号：`busy`

#### 5. VX_gpu_pkg.sv

    SystemVerilog包文件，定义了Vortex GPU系统中使用的各种全局参数、类型和工具函数。在整个工程中使用，确保系统的一致性和可配置性。

1. 参数定义：  主要是 **cache单元参数** 和 **issue单元参数**

   1. cache单元参数：L2和L3缓存的大小、行大小、标签宽度
   2. issue单元参数：发射宽度、每个发射单元的warp数量
2. 类型定义：

   1. 数据结构类型
      * `tmc_t`：线程掩码类型
      * `wspawn_t`：warp生成类型
      * `split_t`：分裂类型
      * `join_t`：合并类型
      * `barrier_t`：屏障类型
      * `base_dcrs_t`：基本DCR类型
   2. 性能计数器类型：  定义了与性能计数器相关的类型，用于跟踪和记录系统的性能数据
      * `cache_perf_t`：缓存性能计数器类型
      * `mem_perf_t`：内存性能计数器类型
      * `sched_perf_t`：调度性能计数器类型
      * `issue_perf_t`：发射性能计数器类型
   3. 指令参数类型：
      * `alu_args_t`：ALU（算术逻辑单元）指令参数类型
      * `fpu_args_t`：FPU（浮点运算单元）指令参数类型
      * `lsu_args_t`：LSU（加载存储单元）指令参数类型
      * `csr_args_t`：CSR（控制状态寄存器）指令参数类型
      * `wctl_args_t`：WCTL（warp控制）指令参数类型
      * `op_args_t`：不同类型指令参数的联合体类型
3. 函数定义：  前三个函数都是issue阶段使用的；

   * `wis_to_wid`：将warp索引和发射单元索引转换为warp ID
   * `wid_to_isw`：将warp ID转换为发射单元索引
   * `wid_to_wis`：将warp ID转换为warp索引
   * `op_to_sfu_type`：根据操作类型确定SFU类型
4. DIP-C接口：   与C语言代码进行交互； 需要添加**SIMULATION**宏定义启用

   1. dip_trace :  引入DPI-C接口
   2. trace_ex_type ： 记录操作的类型
   3. trace_ex_op ： 记录操作的详细信息，操作类型、操作数、结果等

#### 调用包含关系

* [Vortex_axi.sv](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html)是最顶层模块，包含一个 `Vortex`实例。
* [Vortex.sv](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html)包含多个 `VX_cluster`实例。
* [VX_cluster.sv](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html)包含多个 `VX_socket`实例。
* [VX_socket.sv](vscode-file://vscode-app/c:/App2/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html)包含多个 `VX_core`实例。

### .sv-fpu

##### vortex-afu

### .sv-core

### .sv-mem

### .sv-cache

### .sv-libs

##### 1.VX_mem_adapter.sv

##### 2.VX_axi_adapter.sv

### .sv-interface
