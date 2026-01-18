# 0、目标1

收缩战线，聚焦 /hw 、/kernel 、 /tests/kernel ； 打通vortex单独硬件即可。

*[deepwiki](https://deepwiki.com/vortexgpgpu/vortex/5.4-testing-framework)*

**硬件参数考虑：**

## 1、HW阅读

## 1.1 CORE阅读

### 1.1.1 概述

### 1.1.2 核心控制模块

## 2、KERNEL阅读

### 2.1、vx_intrinsics.h

**功能：**

1. CSR读写宏：			CSR寄存器的读写操作，操作指令，封装为读写宏。
2. vortex自定义只读CSR：针对vortex的自定义的只读CSR寄存器，封装多个读函数。
3. vortex的自定义指令：    .insn伪指令定义。

**扩展指令：**

| insn                   | opcode               | func3 | func7 |
| ---------------------- | -------------------- | ----- | ----- |
| tmc(tmc_zero、tmc_one) | RISCV_CUSTOM0 (0x0B) | 0     | 0     |
| wspawn                 | RISCV_CUSTOM0 (0x0B) | 1     | 0     |
| split(split_n)         | RISCV_CUSTOM0 (0x0B) | 2     | 0     |
| join                   | RISCV_CUSTOM0 (0x0B) | 3     | 0     |
| barrier                | RISCV_CUSTOM0 (0x0B) | 4     | 0     |
| pred(pred_n)           | RISCV_CUSTOM0 (0x0B) | 5     | 0     |

**GCC内联汇编：**

__ asm __ __ volatile __ (

    "汇编指令模板"

    : 输出操作数列表 (可选)

    : 输入操作数列表 (可选)

    : 破坏列表 (可选)

);

| 元素     | 含义         | 示例                                |
| -------- | ------------ | ----------------------------------- |
| %0, %1   | 操作数占位符 | 对应输出/输入列表中的第 0, 1 个变量 |
| "=r"     | 输出约束     | = 表示写，r 表示使用通用寄存器      |
| "r"      | 输入约束     | 变量值在寄存器中                    |
| "i"      | 输入约束     | 变量值是立即数（常数）              |
| x0, x1   | 物理寄存器名 | RISC-V 的 Zero 寄存器和 RA 寄存器   |
| .insn    | 汇编伪指令   | 用于生成无法直接写出的机器码        |
| volatile | 关键字       | 禁止编译器优化/删除这段汇编         |
| memory   | 破坏列表     | 内存屏障，防止指令重排              |

### 2.2、vx_start.s 阅读

#### 2.2.1 三大寄存器：GP, SP, TP

在 RISC-V 的 ABI（应用程序二进制接口）约定中，有三个通用寄存器被赋予了特殊使命：

| 寄存器名     | 物理寄存器 | 全称           | 作用                                                                                                                                                                              | 谁拥有？                                                              |
| :----------- | :--------- | :------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :-------------------------------------------------------------------- |
| **gp** | `x3`     | Global Pointer | **全局指针** 。用于加速访问全局变量（`.sdata`, `.sbss`）。编译器会把常用的全局变量放在 `gp` 指向地址的 ±2KB 范围内，这样只需一条指令就能访问，不用加载 32 位长地址。 | **所有线程共享同一个值** （通常指向静态数据段的中间）。         |
| **sp** | `x2`     | Stack Pointer  | **栈指针** 。指向当前函数调用的栈顶。用于保存局部变量、函数返回地址等。                                                                                                     | **每个线程必须独享一个** 。否则线程 A 压栈会覆盖线程 B 的数据。 |
| **tp** | `x4`     | Thread Pointer | **线程指针** 。指向当前线程的 TLS（线程局部存储）区域。用于访问 `__thread` 修饰的变量。                                                                                   | **每个线程必须独享一个** 。                                     |

#### 2.2.2 Hart ID 与 独立空间

* **Hart ID (Hardware Thread ID)** ：
* 在 Vortex 中，`hart_id` 是一个全局唯一的编号，标识了整个处理器中的某一个具体线程。
* 计算公式：`hart_id = (core_id * num_warps * num_threads) + (warp_id * num_threads) + thread_id`。
* 简单理解：如果你有 2 个 Warp，每个 Warp 4 个 Thread，那么：
  * Warp 0 的线程 ID 是 0, 1, 2, 3
  * Warp 1 的线程 ID 是 4, 5, 6, 7
  * 总共有 8 个 Hart。
* **独立性** ：是的，为了并行运行， **每个 Hart 必须有自己独立的栈 (Stack) 和 TLS (Thread Local Storage)** 。

#### 2.2.3 内存图谱举例

**配置参数：**

**Cores:** 2 (Core 0, Core 1)
**Warps per Core:** 2 (Warp 0, Warp 1)
**Threads per Warp:** 4 (Thread 0, 1, 2, 3)
**Total Warps:** 2×2=4
**Total Threads (Harts):** 4×4=16
**全局 Hart ID:** 0 到 15
**STACK_BASE_ADDR** = 0xFFFF0000 (32-bit默认)
**STACK_SIZE** = 8KB (1 << 13)
**LMEM_SIZE** = 16KB (1 << 14)
**TLS_SIZE** =  假设 64 Bytes (取决于应用代码)
**STARTUP_ADDR** = 0x80000000

**内存布局全景图 (2cores x 2 Warps x 4 Threads)：**

```
 物理地址 (Physical Addr)     内容 (Content)                   说明 (Description)
========================================================================================
 0xFFFFFFFF
     ...
 0xFFFF4000  +------------------------------+  <-- LMEM 结束 (STACK_BASE + 16KB)
             |      Local Memory (LMEM)     |	   LMEM是core内部私有SRAM组件，每个core看到这个地址都是
             |   (Core Shared / OpenCL)     |      去访问自己内部的SRAM，而不是外部内存。
 0xFFFF0000  +------------------------------+  <-- STACK_BASE_ADDR / LMEM_BASE_ADDR
             |    Stack for Hart 0 (No.0)   |      Thread 0 (C0, W0, T0) 的栈底
             |   (Grows DOWN towards 0)     |
 0xFFFEE000  +------------------------------+  <-- 0xFFFF0000 - 8KB
             |    Stack for Hart 1 (No.1)   |      Thread 1 (C0, W0, T1) 的栈
             +------------------------------+
             |             ...              |
             +------------------------------+
             |    Stack for Hart 15 (No.15) |      Thread 15 (C1, W1, T3) 的栈
 0xFFFD0000  +------------------------------+  <-- 栈区总边界 (0xFFFF0000 - 16*8KB)
             |                              |
             |        Free Space            |   
             |                              |
     ...     +------------------------------+
             |      Heap (Potential)        |      传统的 sbrk 通常从 _end 开始分配
             |  (Risk: Collision with TLS)  |      注意：裸机如果没有内存管理器，
             |                              |      Heap 和 TLS 会撞车！但是vortex不支持sbrk
             +------------------------------+  <-- _end + (16 * TLS_SIZE)
             |    TLS Copy for Hart 15      |
             +------------------------------+
             |             ...              |      运行时由 vx_start.S 动态拷贝
             +------------------------------+      每个副本大小 = __tbss_size
             |    TLS Copy for Hart 0       |
 0x8xxxxxxx  +------------------------------+  <-- _end (BSS End) / tp_base
             |      .bss (Zero Init)        |
             +------------------------------+
             |      .tdata (Template)       |      __thread 变量的初始值母版
             +------------------------------+
             |      .data (Initialized)     |
             +------------------------------+
             |      .rodata (Read Only)     |
             +------------------------------+
 0x80000000  |      .text (Code)            |  <-- STARTUP_ADDR (程序入口)
             +------------------------------+
     ...
     ...   
 0x0000xxxx  +------------------------------+
             |      User Base Area          |      传统上可能用于加载某些特殊的 OS 级数据
             |                              |      或者作为保护区，防止 NULL 指针越界太多
 0x00010000  +------------------------------+  <-- USER_BASE_ADDR (保留)
             |      User Base Area          |      传统上可能用于加载某些特殊的 OS 级数据
             |                              |      或者作为保护区，防止 NULL 指针越界太多
 0x0000xxxx  +------------------------------+
     ...
	     +------------------------------+
             |   IO: Performance Counters   |      性能计数器回写区 (Write-Only from Dev)
             |   (Hardware -> Host)         |      Core 跑完后把 CSR 的值 Dump 到这里
             |                              |      供 Host 读取。256B per core。
 0x00000080  +------------------------------+  <-- IO_MPM_ADDR (IO_COUT + 64)
             |   IO: Console Output         |      字符输出设备 (Write-Only)
             |        (Printf)              |      往这里写字符，模拟器会在终端打印出来
 0x00000040  +------------------------------+  <-- IO_COUT_ADDR / IO_BASE_ADDR
 	     |      NULL / Loopback         |      空地址，访问通常触发异常
  0x00000000 +------------------------------+  <-- 大小 IO_COUT_SIZE = 64
```

### 2.3 vx_spawn.c 阅读

#### 2.3.1 核心数据结构

  两个核心结构体，用于在主线程（Master Warp）和子线程（Slave Warps）之间传递参数。
  A. wspawn_groups_args_t (用于 Group 调度)
    当 block_dim > 1 时（即有线程组协作需求），使用这个结构体。
    成员解释：
      callback: 要执行的内核函数指针。
      arg:           传递给内核函数的参数指针。
      group_offset:    当前 Core 负责的第一个 Group 的全局索引偏移。
      warp_batches:    每个 Warp 需要执行多少批次的 Group。
      remaining_warps: 额外需要处理的 Warps 数量（用于处理不能整除的情况）。
      warps_per_group: 每个 Group 需要多少个 Warp。
      groups_per_core: 每个 Core 同时处理多少个 Group。
      remaining_mask: 用于最后一个 Warp 的线程掩码（如果 Group Size 不是 Warp Size 的整数倍）。
  B. wspawn_threads_args_t (用于 Task 调度)
    当 block_dim = 1 时（即每个任务独立），使用这个结构体。
    成员解释：
      callback: 要执行的内核函数指针。
      arg:           传递给内核函数的参数指针。
      all_tasks_offset: 当前 Core 负责的第一个任务的全局索引偏移。
      remain_tasks_offset: 当前 Core 负责的剩余任务的起始索引偏移（用于处理不能整除的情况）。
      warp_batches:    每个 Warp 需要执行多少批次的任务。
      remaining_warps: 额外需要处理的 Warps 数量（用于处理不能整除的情况）。

#### 2.3.2 关键函数

| 函数名                     | 作用                                                                 | 谁调用它？                           |
| -------------------------- | -------------------------------------------------------------------- | ------------------------------------ |
| vx_spawn_threads           | 总入口。计算资源，填充参数结构体，启动子 Warp。                      | Host 端调用 vx_spawn_kernel 后触发。 |
| process_thread_groups_stub | Group 调度的包装器。负责设置线程掩码 (tmc)，然后调用实际干活的函数。 | vx_wspawn 唤醒的子 Warp。            |
| process_thread_groups      | Group 调度的工人。计算 blockIdx，执行用户 Kernel。                   | process_thread_groups_stub 调用。    |
| process_threads_stub       | Task 调度的包装器。激活所有线程 (tmc -1)，然后调用工人。             | vx_wspawn 唤醒的子 Warp。            |
| process_threads            | Task 调度的工人。计算 blockIdx (其实就是 Task ID)，执行用户 Kernel。 | process_threads_stub 调用。          |

### 2.4 vx_perf.c、DCR、CSR部分

VX_types.vh 可以看到vortex项目所有的DCR和CSR定义：

**DCR:** DCR是设备寄存器，后续AFU控制器进行封装，挂AXI-lite 进行配置即可。这里就三点： main程序起始地址、main(argc,argv)参数地址、 MPM配置。

**CSR：** CSR是core内CSR空间，注意这和内存空间是两回事；vortex的CSR有三部分：

1. RISCV标准CSR：
2. vortex自定义CSR：
3. RISCV标准CSR但vortex定制使用：
   1. 性能计数器：RISCV推荐0xb00~0xb1f，vortex从core 和 mem 视觉设计了两套profile，后续自己也可以考虑其他需求服用这个空间统计其它数据。
   2. MSCRATCH、VX_CSR_MHARTID； 这两个要搞清楚。

**vx_perf.c：** core执行完成后调用，读出性能计数器的值进行统计分析。

### 2.5 总结：

**关键组件：**

1. vx_start.s ： 初始化GP、SP、TP。
2. vx_syscalls： vortex使用定制的libc库，桩函数实际只实现了_write，用于后续的vx_printf()。
3. vx_printf.c / .s ：一个简化的printf工具，硬件机制上使用的MMIO映射字符输出设备。
4. vx_spawn.c :  核心机制，SIMT模型的软件实现基础。软件层的grid、block、task(thread) 到硬件层的core、warp、thread 如何映射，如何激活调度硬件运行kernel。
5. vx_serial.s ：并发控制的关键，当有些代码只能一个一个线程串行执行时，使用该函数来串行化。

**静态库输出：  libvortex.a**

1. **标准riscv编译工具链：** 因为这里的程序都是标准的RISCV c/s 程序，所以也是标准的RISCV编译工具链，（自定义的扩展指令都是通过汇编宏或直接写.insn机器码插入的；link文件在标准link文件的基础上有稍许改动。）
2. **输入输出：**

## 3、TESTS/KERNEL阅读

### 3.1 conform

**总结与观察:**

1. 分层验证：测试从最底层的内存（Test 1, 2），上升到线程控制（Test 3, 4），再到复杂的 Warp 调度（Test 5, 6, 10），最后是运行时高级特性（Test 7, 8, 11）。
2. noinline 的使用：几乎所有 helper 函数都加了 __attribute__((noinline))。这是为了防止编译器过度优化，因为这些测试往往依赖特定的指令序列或函数调用边界来触发硬件行为（例如 test_local_memory 中的 RAW 测试）。
3. 核心难点：test_divergence (分歧) 和 test_barrier (栅栏) 是最容易暴露 SIMT 架构硬件 Bug 的两个测试点。如果硬件的分支堆栈（IPDOM）或者 Warp 计分板逻辑有误，这两个测试必挂。

| #            | 测试函数名             | 测试对象                          | 测试逻辑描述                                                                                                           | 核心验证的硬件/模块                                                                                    |
| :----------- | :--------------------- | :-------------------------------- | :--------------------------------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------- |
| **1**  | `test_global_memory` | **全局内存 (DRAM)**         | 所有线程向 Global memory 写入 `65 + index`，并立即回读检查。                                                         | **LSU (Load Store Unit)**`<br>`Cache 系统 (L1/L2/L3), AXI 总线接口                             |
| **2**  | `test_local_memory`  | **本地/共享内存 (SM/LMEM)** | 使用 `volatile` 指针访问 `LMEM_BASE_ADDR`。执行 `Store (写) -> Load (读) -> Store (回写)` 序列，验证数据一致性。 | **LSU** `<br>`L1 Bank 仲裁器, RAW 冒险检测, 旁路逻辑 (Forwarding)                              |
| **3**  | `test_tmc`           | **线程掩码控制 (TMC)**      | 仅激活前 8 个线程 (`vx_tmc`)，写入缓冲区的不同位置，验证只有活跃线程执行了写操作。                                   | **CSR unit** `<br>`根据 `thread mask` 寄存器暂停/恢复线程的能力                              |
| **4**  | `test_pred`          | **谓词执行 (Predication)**  | 使用 `vx_pred` 指令。仅让 TID=0 的线程执行写操作，其他线程跳过。                                                     | **ALU / Scheduler** `<br>`指令级条件执行 (不涉及跳转)，验证指令的 mask 位是否生效              |
| **5**  | `test_divergence`    | **控制流分歧 (Divergence)** | 构造嵌套的 `if-else` 分支结构（线程 ID < 2, < 1 等）。使用 `vx_split` 和 `vx_join` 处理不同路径。                | **Scheduler (IPDOM Stack)**`<br>`验证硬件是否能正确拆分 Warp 的执行路径并在汇合点重新同步      |
| **6**  | `test_wsapwn`        | **Warp 激活 (Wspawn)**      | 使用 `vx_wspawn` 激活多个 Warp (线程束)。主线程只负责启动，子 Warp 执行写入操作并自行休眠。                          | **Scheduler (Warp Table)**`<br>`多 Warp 调度逻辑, `wspawn` 指令解码                          |
| **7**  | `test_spawn_tasks`   | **运行时任务分发 (Tasks)**  | 使用高级 API `vx_spawn_threads` 分发工作项。通过回调函数 `st_kernel` 传递参数。                                    | **Kernel Runtime (Software)**`<br>`验证内核运行时库对任务队列和参数传递的管理                  |
| **8**  | `test_serial`        | **串行化执行 (Serial)**     | 调用 `vx_serial`，强制并行的线程串行执行一个函数块。                                                                 | **Kernel Runtime / Synchronization** `<br>`验证临界区保护和锁机制                              |
| **9**  | `test_tmask`         | **动态掩码与循环**          | 在 `goto` 循环中动态改变活跃线程掩码 (`vx_tmc`)，并使用 `vx_active_threads` 检查当前状态是否符合预期。           | **Scheduler / CSR** `<br>`复杂控制流下的线程状态查询与切换准确性                               |
| **10** | `test_barrier`       | **Warp 级栅栏 (Barrier)**   | 制造不同时长的延迟（让不同 Warp 跑不同次数的循环），然后调用 `vx_barrier` 等待所有 Warp 到齐。                       | **Scheduler (Barrier logic)**`<br>`验证同步机制，确保“快” Warp 会等待“慢” Warp             |
| **11** | `test_tls`           | **线程局部存储 (TLS)**      | 定义 `__thread int tls_var`。让不同 Warp 写入该变量，验证它们是否互不干扰。                                          | **Compiler / Register File** `<br>`验证 `tp` (Thread Pointer) 寄存器设置及从该基址的偏移访问 |

#### 3.2 makefile解析

**总结：**

1. 一个测试程序 = 纯粹的C++逻辑 (-nostdlib) + 物理地址约束 (medany, 0x80000000) + Vortex内核运行时 (libvortex.a)。
2. kernel/  目录提供了 libvortex.a；  tests/kernel/conform/ 提供了一个vortex裸机的测试程序，且编译链接后得到了.bin。
3. 下一步需要理解仿真器逻辑。

**从编译选项了解一些概念：**

1. `-mcmodel=medany` (关键点) :
   含义 : Medium-Any Memory Model。
   为什么一定要用它？ : 默认的 RISC-V 编译模型 (`medlow`) 假设所有的全局符号都在 ±2GB**±2GB** 地址范围内（通常对应虚拟地址 `0x00000000` 附近）。但 Vortex 的物理内存空间是从 `0x80000000` 开始的。如果你不用 `medany`，编译器生成的跳转指令可能会跳不到那么远的地方，导致链接错误或运行崩溃。
2. `-fno-exceptions & -nostdlib`:
   含义: 禁用 C++ 异常，不使用标准库。
   原因: 异常处理 (try-catch) 需要庞大的运行时栈展开（Stack Unwinding）支持，这在裸机上不仅极其消耗资源，而且在这个阶段根本没有做支持。我们只想要最纯粹的代码指令。
3. `-nostartfiles`:
   原因: 我们不要 GCC 自带的 crt0.o (C Runtime Startup)。因为那种启动文件是给 Linux 进程用的，它会去找 libc.so。我们要用的是自己在 vx_start.S 里手写的那个 _start。

**从链接库选项了解一些概念：**

1. -lc -lm: 这里链接的是 Newlib。这是嵌入式领域最常用的 C 标准库实现，它非常轻量。vortex 预编译了一份 Newlib，这里的 -L 就是指向那里。
2. `libclang_rt.builtins...`: 这是编译器的“保底库”。
   场景: 假设你写了一个 64位除法，但你的硬件只支持 32位。编译器发现没有硬件指令可用，就会自动生成一个函数调用 __divdi3。这个库里就包含了这些函数的软件实现（Software Emulation）。

**从链接选项了解一些概念：**

1. `-T link$(XLEN).ld` :
   指定了 链接脚本 (Linker Script) 。
   编译器只管生成指令，链接器才管这些指令放在内存的哪个位置。这个脚本决定了 `.text` 段、`.data` 段、`Stack` 和 `Heap` 在 `0x80000000` 这个地址空间里怎么排排坐。
2. `--defsym=STARTUP_ADDR=0x80000000` :
   这里定义了一个符号 [STARTUP_ADDR]
   如果你去翻一下 [link32.ld]，你会发现第一行代码就是 [. = STARTUP_ADDR;]
   这意味着： 整个程序的物理起始地址被“钉”在了 `0x80000000` 。这是一切的起点。
3. `$(ROOT_DIR)/kernel/libvortex.a` :
   链接我们刚刚分析完的 Kernel 库。所有的系统调用实现、启动代码都在这里面。

## 4、SIM/RTLSIM

### 4.1 总结

### 4.2 源码阅读
