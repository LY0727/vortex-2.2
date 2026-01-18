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

#include <sys/stat.h>
#include <newlib.h>
#include <unistd.h>
#include <vx_intrinsics.h>
#include <vx_print.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

int _close(int file) { return -1; }

int _fstat(int file, struct stat *st) { return -1; }

int _isatty(int file) { return 0; }

int _lseek(int file, int ptr, int dir) { return 0; }

int _open(const char *name, int flags, int mode) { return -1; }

int _read(int file, char *ptr, int len) { return -1; }

/*************************************************************
  * sbrk 实现说明
  *
  * 背景：newlib C 库使用 _sbrk 系统调用来实现动态内存分配 (malloc)。
  *      _sbrk 函数负责调整程序的数据段末尾，以分配或释放内存。
  * 需求：在嵌入式系统或特殊架构（如 Vortex）中，通常需要自定义 _sbrk 的行为以适应特定的内存管理需求。
  * 实现：这里的 _sbrk 实现直接触发了一个 ebreak 异常，表示当前不支持动态内存分配。 
          因为在GPU架构下，通常也不鼓励动态分配内存，而是HOST端统一管理内存分配。
  *************************************************************/

caddr_t _sbrk(int incr) {
  __asm__ __volatile__("ebreak");
  return 0;
}
/*************************************************************
  * _write 实现说明
  *
  * 背景：newlib C 库使用 _write 系统调用来实现 标准输出功能 (printf)。
  *      _write 函数负责将数据写入指定的文件描述符（通常是标准输出）。
  * 需求：在嵌入式系统或特殊架构（如 Vortex）中，通常需要自定义 _write 的行为以适应特定的输出设备。
  * 实现：这里的 _write 实现将数据逐字节发送到 Vortex 的字符输出函数 vx_putchar。
          注意这里的实现忽略了 file 参数，假设所有输出都发送到同一个输出设备（通常是 UART 或控制台）。
  * 注意：vx_putchar 函数定义在 vx_print 模块中，负责实际的字符输出。
  *************************************************************/
int _write(int file, char *ptr, int len) {
  int i;
  for (i = 0; i < len; ++i) {
    vx_putchar(*ptr++);
  }
  return len;
}

int _kill(int pid, int sig) { return -1; }

int _getpid() {
  return vx_hart_id();
}
/*************************************************************
  * TLS 初始化说明
  *
  * 背景：线程局部存储 (TLS) 允许每个线程拥有自己的数据副本。
  *      在多线程环境中，TLS 用于存储线程特有的数据，确保线程之间的数据隔离。
  * 需求：在支持多线程的系统中，必须正确初始化 TLS 以确保每个线程的数据独立性。 
  * 实现：__init_tls 函数负责初始化 TLS data段和 BSS 段。
          它从链接器提供的符号获取 TLS 数据的起始位置和大小，
          并使用 memcpy 和 memset 分别初始化数据段和 BSS 段。
  *************************************************************/

void __init_tls(void) {
  // These magic symbols are provided by the linker. 链接脚本中提供的符号。
  extern char __tdata_start[];
  extern char __tbss_offset[];
  extern char __tdata_size[];
  extern char __tbss_size[];

  // TLS memory initialization
  // 1. 获取当前线程的tp指针。 把 C 变量绑定到了物理寄存器 tp 上。这是 GCC 的扩展语法。
  register char *__thread_self __asm__ ("tp");
  // 2. 初始化 TLS data 段（拷贝）和 BSS 段（清零）。
  memcpy(__thread_self, __tdata_start, (size_t)__tdata_size);
  memset(__thread_self + (size_t)__tbss_offset, 0, (size_t)__tbss_size);
}

#ifdef HAVE_INITFINI_ARRAY

// These magic symbols are provided by the linker.
extern void (*__preinit_array_start []) (void) __attribute__((weak));
extern void (*__preinit_array_end []) (void) __attribute__((weak));
extern void (*__init_array_start []) (void) __attribute__((weak));
extern void (*__init_array_end []) (void) __attribute__((weak));

#ifdef HAVE_INIT_FINI
extern void _init (void);
#endif

// Iterate over all the init routines.
void __libc_init_array (void) {
  size_t count;
  size_t i;

  count = __preinit_array_end - __preinit_array_start;
  for (i = 0; i < count; i++)
    __preinit_array_start[i] ();

#ifdef HAVE_INIT_FINI
  _init ();
#endif

  count = __init_array_end - __init_array_start;
  for (i = 0; i < count; i++)
    __init_array_start[i] ();
}
#endif

#ifdef HAVE_INITFINI_ARRAY
extern void (*__fini_array_start []) (void) __attribute__((weak));
extern void (*__fini_array_end []) (void) __attribute__((weak));

#ifdef HAVE_INIT_FINI
extern void _fini (void);
#endif

/* Run all the cleanup routines.  */
void __libc_fini_array (void) {
  size_t count;
  size_t i;

  count = __fini_array_end - __fini_array_start;
  for (i = count; i > 0; i--)
    __fini_array_start[i-1] ();

#ifdef HAVE_INIT_FINI
  _fini ();
#endif
}
#endif

// This function will be called by LIBC at program exit.
// Since this platform only support statically linked programs,
// it is not required to support LIBC's exit functions registration via atexit().
void __funcs_on_exit (void) {
#ifdef HAVE_INITFINI_ARRAY
  __libc_fini_array();
#endif
}

#ifdef __cplusplus
}
#endif


/*
3. Vortex Kernel 的实现情况分析
让我们回到 vx_syscalls.c，看看 Vortex 实现了什么，放弃了什么。

A. 已实现 (Implemented)
  _write
    实现：循环调用 vx_putchar。
    原因：这是最基本的需求。没有它，程序无法输出任何调试信息，无法打印 "Hello World"。
  _getpid
    实现：返回 vx_hart_id()。
    原因：Vortex 是多线程架构，用 Hart ID 来模拟 Process ID 是非常合理的映射，方便调试时区分是谁在打印日志。
  _exit (在 vx_start.S 中实现)
    实现：转储性能数据并终止执行。
    原因：程序跑完了必须有个结束的地方。
B. 未实现 / 哑实现 (Stubbed out)
  _sbrk (实现为崩溃 ebreak)
    状态：不支持。
    原因：
    硬件限制：GPU/加速器通常没有复杂的内存管理单元（MMU）来处理堆的动态增长。
    编程模型：在 SIMT 编程（如 CUDA/OpenCL）中，Kernel 内部通常禁止 malloc。内存应该由 Host 端分配好，通过指针传进来。在 Kernel 里 malloc 会导致严重的内存碎片和线程安全问题（成千上万个线程同时抢堆锁）。
  文件系统相关 (_open, _close, _read, _lseek, _fstat)
    状态：返回错误 (-1) 或 0。
    原因：Vortex 是一个计算核心，不是操作系统。它没有挂载磁盘，也没有文件系统驱动。它只能通过 _write 向 Host 的控制台吐字符，无法读写文件。
  进程控制相关 (_kill)
    状态：返回错误。
    原因：Vortex 是裸机运行环境，没有操作系统内核来管理信号（Signal）和进程间通信。

4. 总结
Vortex 的 vx_syscalls.c 是一个最小化的实现，
只保留了：
能说话 (_write)：为了调试。
知道自己是谁 (_getpid)：为了多线程调试。

它砍掉了：
动态内存 (_sbrk)：为了性能和简化模型。
文件系统：因为硬件不支持。

*/