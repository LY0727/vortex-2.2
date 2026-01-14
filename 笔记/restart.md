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

#### **2.2.1 三大寄存器：GP, SP, TP**

在 RISC-V 的 ABI（应用程序二进制接口）约定中，有三个通用寄存器被赋予了特殊使命：

| 寄存器名     | 物理寄存器 | 全称           | 作用                                                                                                                                                                              | 谁拥有？                                                              |
| :----------- | :--------- | :------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :-------------------------------------------------------------------- |
| **gp** | `x3`     | Global Pointer | **全局指针** 。用于加速访问全局变量（`.sdata`, `.sbss`）。编译器会把常用的全局变量放在 `gp` 指向地址的 ±2KB 范围内，这样只需一条指令就能访问，不用加载 32 位长地址。 | **所有线程共享同一个值** （通常指向静态数据段的中间）。         |
| **sp** | `x2`     | Stack Pointer  | **栈指针** 。指向当前函数调用的栈顶。用于保存局部变量、函数返回地址等。                                                                                                     | **每个线程必须独享一个** 。否则线程 A 压栈会覆盖线程 B 的数据。 |
| **tp** | `x4`     | Thread Pointer | **线程指针** 。指向当前线程的 TLS（线程局部存储）区域。用于访问 `__thread` 修饰的变量。                                                                                   | **每个线程必须独享一个** 。                                     |

#### **2.2.2 Hart ID 与 独立空间**

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

* **Core**: 1 个
* **Warps** : 2 个 (Warp 0, Warp 1)
* **Threads/Warp** : 2 个 (Thread 0, Thread 1)
* **总 Hart 数** : 4 个 (Hart 0, 1, 2, 3)
  * Hart 0 = Warp 0, Thread 0
  * Hart 1 = Warp 0, Thread 1
  * Hart 2 = Warp 1, Thread 0
  * Hart 3 = Warp 1, Thread 1
* **STACK_BASE_ADDR** : 假设 `0x80000000`
* **_end** : 假设 `0x10000000`

**内存布局全景图 (2 Warps x 2 Threads)：**

```
高地址 (0xFFFFFFFF)
      |
      | ... (未使用 / IO 映射区) ...
      |
+-----+-----------------------+ <--- STACK_BASE_ADDR (0x80000000)
|     | Hart 0 Stack          | <--- Warp 0, Thread 0 的 SP 初始值
+-----+-----------------------+
|     | Hart 1 Stack          | <--- Warp 0, Thread 1 的 SP
+-----+-----------------------+
|     | Hart 2 Stack          | <--- Warp 1, Thread 0 的 SP
+-----+-----------------------+
|     | Hart 3 Stack          | <--- Warp 1, Thread 1 的 SP
+-----+-----------------------+ <--- 栈区结束 (0x80000000 - 4 * STACK_SIZE)
|
|
|           ( 堆 Heap 区域 )
|           ( 向高地址增长 )
|                  ^
|                  |
|
+-----+-----------------------+ <--- TLS 区结束 (_end + 4 * TLS_SIZE)
|     | Hart 3 TLS            | <--- Warp 1, Thread 1 的 TP 指向这里
+-----+-----------------------+
|     | Hart 2 TLS            | <--- Warp 1, Thread 0 的 TP
+-----+-----------------------+
|     | Hart 1 TLS            | <--- Warp 0, Thread 1 的 TP
+-----+-----------------------+
|     | Hart 0 TLS            | <--- Warp 0, Thread 0 的 TP 指向这里
+-----+-----------------------+ <--- _end (0x10000000)
|     | .bss (未初始化全局)   |
+-----+-----------------------+
|     | .data (已初始化全局)  | <--- gp (Global Pointer) 指向这里附近
+-----+-----------------------+
|     | .text (代码段)        |
+-----+-----------------------+ <--- STARTUP_ADDR (0x00000000)
低地址 (0x00000000)
```

## 3、TESTS/KERNEL阅读

### conform

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
