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

// vx_start.S: RISC-V Vortex 内核启动代码
# 初始化环境：它负责设置栈指针、初始化全局变量、清空 BSS 段（未初始化的全局变量）。
# 多线程初始化：利用 vx_wspawn 指令激活所有硬件线程（Warps），并为每个线程初始化寄存器和 TLS（线程局部存储）。
# 跳转主函数：完成准备工作后，跳转到用户的 main 函数。

# Vortex 的启动流程是一个 “并行 -> 串行 -> 并行” 的交替过程：
  # 并行：所有 Warp 醒来，各自认领自己的栈 (sp) 和 TLS (tp)。
  # 串行：Warp 0 的 Thread 0 负责清空 BSS，初始化全局环境。
  # 进入 Main：以单线程模式进入 main()。用户在 main 里再决定何时调用 vx_spawn_kernel 来再次开启并行计算。

#include <VX_config.h>
#include <VX_types.h>
#include <newlib.h>
#include "common.h"

.section .init, "ax"
.global _start
.type   _start, @function
_start:

  # initialize per-thread registers
  # 1. 注意这里是warp0 (主warp) 的 thread0 (主线程) 执行的代码。
  # 2. 先激活所有warp(注意这里是除warp0之外的其他warp)，调用 init_regs_all 初始化每个warp的所有线程寄存器。
  # 3. 然后再激活当前warp的所有线程，调用 init_regs 初始化寄存器。(注意这里是warp0的所有线程)
  # 4. 最后切换回单线程模式，继续后续初始化工作。
  #
  csrr  t0, VX_CSR_NUM_WARPS  # get num warps ； 这里的含义是core硬件上支持多少个warp同时运行
  la    t1, init_regs_all     # 初始化函数  地址存入 t1
  .insn r RISCV_CUSTOM0, 1, 0, x0, t0, t1  # wspawn t0, t1  # 激活t0个warp，让它们从t1地址开始执行,进行初始化。
  
  li    t0, -1                              
  .insn r RISCV_CUSTOM0, 0, 0, x0, t0, x0  # tmc t0；  # tmc -1（0xFFFFFFFF）,也就是激活当前warp的所有线程
  jal   init_regs                                      # 当前warp，跳转去执行初始化寄存器函数。
  li    t0, 1
  .insn r RISCV_CUSTOM0, 0, 0, x0, t0, x0  # tmc t0    # tmc 1（0x01），单线程模式。

  # initialize TLS for all warps
  csrr  t0, VX_CSR_NUM_WARPS  # get num warps
  la    t1, init_tls_all
  .insn r RISCV_CUSTOM0, 1, 0, x0, t0, t1  # wspawn t0, t1
  li    t0, -1
  .insn r RISCV_CUSTOM0, 0, 0, x0, t0, x0  # tmc t0
  call  __init_tls                         # 初始化TLS函数，这里是调用C库函数，把 .tdata 的初始值拷贝到 tp 指向的内存
                                           # 这里会需要用到 tp 寄存器，而 tp 寄存器已经在 init_regs 中初始化好了。
  li    t0, 1
  .insn r RISCV_CUSTOM0, 0, 0, x0, t0, x0  # tmc t0

  # clear BSS segment   # 注意这里只有warp0 的 thread0 单线程执行，初始化整个全局的bss段。
  la    a0, _edata
  la    a2, _end
  sub   a2, a2, a0
  li    a1, 0
  call  memset          # 清空 BSS 段，初始化未初始化的全局变量。

  # initialize trap vector
  # la t0, trap_entry
  # csrw mtvec, t0

#ifdef HAVE_INITFINI_ARRAY
  # run global initialization functions    # 运行全局构造函数 (C++ 特性)
  call  __libc_init_array
#endif

  # call main program routine     # 终于！跳转到用户的 main 函数
  call  main

  # call exit routine             # main 返回后，调用 exit 函数，进行清理和退出操作
  tail  exit
.size _start, .-_start


/********************************
  * Function: _Exit
  * Description: 退出内核，执行性能数据的转储，并通过特定的 I/O 地址传递退出代码。
  * Parameters:
  *   - a0: 退出代码
  * Returns: None
  * Notes:
  *   - 调用 vx_perf_dump 函数以转储性能数据。
  *   - 将退出代码存储到 IO_MPM_EXITCODE 指定的内存地址。
  *   - 使用自定义指令 tmc x0 来触发退出操作。
 *********************************/
.section .text
.type _Exit, @function
.global _Exit
_Exit:
  call vx_perf_dump          # 转储性能数据，vx_perf.c 中定义的函数。
  li t0, IO_MPM_EXITCODE     # 定义在 VX_config.h 中的退出代码地址
  sw a0, 0(t0)
  fence
  .insn r RISCV_CUSTOM0, 0, 0, x0, x0, x0  # tmc x0

/********************************
  * Function: init_regs
  * Description: 初始化每个线程的寄存器，包括全局指针（gp）、栈指针（sp）和线程指针（tp）。
  * Parameters: None
  * Returns: None
  * Notes:
  *   - 全局指针（gp）设置为链接脚本中定义的 __global_pointer 符号地址。
  *   - 栈指针（sp）根据硬件线程 ID（hart_id）计算，确保每个线程有独立的栈空间。
  *   - 线程指针（tp）设置为 BSS 段结束后的地址加上 hart_id 乘以 TLS 大小，确保每个线程有独立的 TLS 副本。  __tbss_size 也是链接脚本中定义的符号，表示 TLS 数据块的大小。

  关键点：
    内存布局：Vortex 的内存模型中，栈空间是预先划分好的。每个硬件线程（Hart）都有自己的一块栈，互不干扰。
    TLS：tp 寄存器指向当前线程的私有数据区。C 语言里的 __thread int x; 就是通过 tp 寄存器加偏移量来访问的。
*********************************/
.section .text
.type init_regs, @function
.local init_regs
init_regs:
  # set global pointer register    # 每个thread，都需要全局指针
  .option push
  .option norelax
  la    gp, __global_pointer               # link脚本中定义的全局指针符号
  .option pop

  # set stack pointer register     # 每个thread，都需要独立栈空间
  # sp = STACK_BASE_ADDR - (hart_id * STACK_SIZE)
  LOAD_IMMEDIATE64(sp, STACK_BASE_ADDR)    # 设置栈基地址 ; config.h 中定义的。
  csrr  t0, VX_CSR_MHARTID                 # get hart id ; type.h 中定义的。
  sll   t1, t0, STACK_LOG2_SIZE            # hart_id * STACK_SIZE ;  STACK_LOG2_SIZE 是 STACK_SIZE 的对数值,在 config.h 中定义的。
  sub   sp, sp, t1                         # 栈向下增长，每个线程有独立栈空间。

  # set thread pointer register    # 每个thread，都需要独立TLS空间
  # use address space after BSS region
  # tp = _end + (hart_id * TLS_SIZE)
  la    t1, __tbss_size                    # TLS 数据块的大小; （由你的程序中声明了多少 __thread 变量，链接阶段自动计算出来）
  mul   t0, t0, t1                         # 偏移量
  la    tp, _end                           # TLS 区域通常放在 BSS 后面
  add   tp, tp, t0                         # 每个线程有独立的 TLS 副本
  ret

.section .text
.type init_regs_all, @function
.local init_regs_all
init_regs_all:
  li    t0, -1
  .insn r RISCV_CUSTOM0, 0, 0, x0, t0, x0  # tmc t0
  jal   init_regs
  .insn r RISCV_CUSTOM0, 0, 0, x0, x0, x0  # tmc x0  # 线程全杀死，休眠。硬件层面挂起。
  ret

.section .text
.type init_tls_all, @function
.local init_tls_all
init_tls_all:
  li    t0, -1
  .insn r RISCV_CUSTOM0, 0, 0, x0, t0, x0  # tmc t0
  call  __init_tls
  .insn r RISCV_CUSTOM0, 0, 0, x0, x0, x0  # tmc x0  # 线程全杀死，休眠。
  ret

.section .data
	.global __dso_handle
	.weak __dso_handle
__dso_handle:
	.long	0
