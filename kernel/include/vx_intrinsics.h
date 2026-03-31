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

// The intrinsics implemented use RISC-V assembler pseudo-directives defined here:
// https://sourceware.org/binutils/docs/as/RISC_002dV_002dFormats.html

#ifndef __VX_INTRINSICS_H__
#define __VX_INTRINSICS_H__

#include <stddef.h>
#include <stdint.h>
#include <VX_types.h>

#if defined(__clang__)
#define __UNIFORM__   __attribute__((annotate("vortex.uniform")))
#else
#define __UNIFORM__
#endif

#ifdef __cplusplus
extern "C" {
#endif

/***************************************************
1. **文件用途**  
   该头文件主要为 Vortex 平台提供 RISC-V 自定义指令与寄存器访问的内联函数与宏定义，用于实现多线程、多 Warp 等自定义操作。

2. **CSR（控制与状态寄存器）访问宏**  
   - `csr_read` / `csr_write` / `csr_swap` / `csr_read_set` / `csr_set` / `csr_read_clear` / `csr_clear` 等宏，
   - 简化了对 RISC-V 体系结构中控制与状态寄存器的读取、写入、置位、清除等操作。
   - 通过内联汇编 `.insn` 或 `csrr/csrw` 等伪指令完成对特定寄存器的读写。

3. **线程控制与分支指令**  
   - `vx_tmc` / `vx_tmc_zero` / `vx_tmc_one` 这些内联函数可用于启用、禁用或只启用单个线程。
   - `vx_pred` / `vx_pred_n` 用于基于条件的线程掩码设置（谓词机制）。
   - `vx_wspawn` 可用于在硬件层面派生多个 Warp 并执行指定函数。

4. **分支与合并**  
   - `vx_split` / `vx_split_n`：根据谓词进行分支，返回值可用于后续控制流。
   - `vx_join`：Warp 合并操作，通常在分支结束后使用。

5. **同步与栅栏操作**  
   - `vx_barrier` 通过自定义指令实现对多 Warp 的同步。
   - `vx_fence` 则使用 RISC-V 的 `fence` 指令完成内存同步。

6. **多核/多 Warp 属性获取**  
   - `vx_thread_id` / `vx_warp_id` / `vx_core_id` / `vx_hart_id` 等函数可获取当前thread、Warp、Core、hart标识。
   - `vx_active_threads` / `vx_active_warps` / `vx_num_threads` / `vx_num_warps` / `vx_num_cores` 提供当前活跃线程/warp 数量、系统线程/warp 数量、以及核心数量等信息。

整体而言，该文件提供了对 Vortex 定义的一系列 RISC-V 自定义指令与控制寄存器的便捷接口，让上层代码可直接使用 C 语言内联函数和宏来进行底层多线程、多 Warp 管理、线程谓词控制及寄存器读写等操作。
 ****************************************************/

// RISC-V 用于自定义扩展指令编码 的四类opcode
#define RISCV_CUSTOM0   0x0B
#define RISCV_CUSTOM1   0x2B
#define RISCV_CUSTOM2   0x5B
#define RISCV_CUSTOM3   0x7B

/***************************************************
2. **CSR（控制与状态寄存器）访问宏**    
    ​​寄存器读写​​：
        csr_read/csr_write 使用csrr和csrw指令完成寄存器值的读取与写入。
    ​​位操作​​：
        csr_set/csr_clear 通过csrs/csrc指令设置或清除寄存器的特定位。
        csr_swap 使用csrrw实现原子交换操作，适用于互斥锁场景。
    ​​优化处理​​：
        根据操作数是否为立即数（__builtin_constant_p判断），自动选择更高效的指令形式。
        如果val在编译器就是一个小于32的常量数值，即可在汇编指令里使用立即数写CSR，减少开销。
        否则使用寄存器("r")传递参数，避免了编译器在寄存器和内存之间的隐式转换。
    CSR扩展：
        RISC-V 预留了12位的CSR地址空间，允许用户定义扩展CSR。
        
        csrr rd, csr：     将名为 csr 的寄存器内容读到通用寄存器 rd。
        csrw csr, rs：     将通用寄存器 rs 的内容写入名为 csr 的寄存器。
        csrs csr, rs：     对名为 csr 的寄存器进行“置位”操作（逻辑或）。
        csrc csr, rs：     对名为 csr 的寄存器进行“清零”操作（逻辑与取反）。
        csrrw rd, csr, rs：将名为 csr 的寄存器内容读到 rd，并把 rs 写入 csr。
        csrrs rd, csr, rs：将名为 csr 的寄存器内容读到 rd，并用 rs 对 csr 置位。
        csrrc rd, csr, rs：将名为 csr 的寄存器内容读到 rd，并根据 rs 清除 csr 对应位。
 ****************************************************/
 /****************************************************
  * 
  * __asm__ __volatile__ ( 
    "汇编指令模板" 
    : 输出操作数列表 (可选)
    : 输入操作数列表 (可选)
    : 破坏列表 (可选)
    );
  * 
  * 解释：
1. ({ ... })：这是 GCC 的 Statement Expression 扩展。它允许你在一个表达式（Expression）里写多条语句（Statement），并且最后一条语句的值（这里是 __r;）作为整个表达式的返回值。这使得宏可以像函数一样返回值。
2."csrr %0, %1"：汇编模板。
    csrr：RISC-V 指令，读取 CSR。
    %0, %1：占位符，对应后面的操作数。
3. : "=r" (__r) (输出部分)：
    =：表示这个操作数是只写（Write-only）的。
    r：约束（Constraint），告诉编译器“请分配一个通用寄存器（Register）给变量 __r，并把这个寄存器的名字填到 %0 的位置”。
4. : "i" (csr) (输入部分)：
    i：约束，表示 csr 必须是一个立即数（Immediate integer）。编译器会把 csr 的数值直接填到 %1 的位置。
5. : "memory" (破坏列表)：
    告诉编译器：“这段汇编可能会修改内存，请不要在汇编前后随意缓存内存变量到寄存器里，
    也不要随意调整内存读写指令的顺序”。这是一个内存屏障（Memory Barrier）。
 ****************************************************/
#define csr_read(csr) ({                        \
	size_t __r;	               		            \
	__asm__ __volatile__ ("csrr %0, %1" : "=r" (__r) : "i" (csr) : "memory"); \
	__r;							            \
})

#define csr_write(csr, val)	({                  \
	size_t __v = (size_t)(val);                 \
	if (__builtin_constant_p(val) && __v < 32)  \
        __asm__ __volatile__ ("csrw %0, %1" :: "i" (csr), "i" (__v) : "memory");  \
    else                                        \
        __asm__ __volatile__ ("csrw %0, %1"	:: "i" (csr), "r" (__v) : "memory");  \
})

#define csr_swap(csr, val) ({                   \
    size_t __r;                                 \
	size_t __v = (size_t)(val);	                \
	if (__builtin_constant_p(val) && __v < 32)  \
        __asm__ __volatile__ ("csrrw %0, %1, %2" : "=r" (__r) : "i" (csr), "i" (__v) : "memory"); \
    else                                        \
        __asm__ __volatile__ ("csrrw %0, %1, %2" : "=r" (__r) : "i" (csr), "r" (__v) : "memory"); \
	__r;						                \
})

#define csr_read_set(csr, val) ({               \
	size_t __r;                                 \
	size_t __v = (size_t)(val);	                \
    if (__builtin_constant_p(val) && __v < 32)  \
	    __asm__ __volatile__ ("csrrs %0, %1, %2" : "=r" (__r) : "i" (csr), "i" (__v) : "memory"); \
    else                                        \
        __asm__ __volatile__ ("csrrs %0, %1, %2" : "=r" (__r) : "i" (csr), "r" (__v) : "memory"); \
	__r;							            \
})

#define csr_set(csr, val) ({                    \
	size_t __v = (size_t)(val);	                \
    if (__builtin_constant_p(val) && __v < 32)  \
	    __asm__ __volatile__ ("csrs %0, %1"	:: "i" (csr), "i" (__v) : "memory");  \
    else                                        \
        __asm__ __volatile__ ("csrs %0, %1"	:: "i" (csr), "r" (__v) : "memory");  \
})

#define csr_read_clear(csr, val) ({             \
	size_t __r;                                 \
	size_t __v = (size_t)(val);	                \
    if (__builtin_constant_p(val) && __v < 32)  \
	    __asm__ __volatile__ ("csrrc %0, %1, %2" : "=r" (__r) : "i" (csr), "i" (__v) : "memory"); \
    else                                        \
        __asm__ __volatile__ ("csrrc %0, %1, %2" : "=r" (__r) : "i" (csr), "r" (__v) : "memory"); \
	__r;							            \
})

#define csr_clear(csr, val)	({                  \
	size_t __v = (size_t)(val);                 \
	if (__builtin_constant_p(val) && __v < 32)  \
        __asm__ __volatile__ ("csrc %0, %1" :: "i" (csr), "i" (__v) : "memory"); \
    else                                        \
        __asm__ __volatile__ ("csrc %0, %1"	:: "i" (csr), "r" (__v) : "memory"); \
})

/***************************************************
3. **线程控制与分支指令**  
   - `vx_tmc` / `vx_tmc_zero` / `vx_tmc_one` 这些内联函数可用于启用、禁用或只启用单个线程。
   - `vx_pred` / `vx_pred_n` 用于基于条件的线程掩码设置（谓词机制）。
   - `vx_wspawn` 可用于在硬件层面派生多个 Warp 并执行指定函数。

4. **分支与合并**  
   - `vx_split` / `vx_split_n`：根据谓词进行分支，返回值可用于后续控制流。
   - `vx_join`：Warp 合并操作，通常在分支结束后使用。

5. **同步与栅栏操作**  
   - `vx_barrier` 通过自定义指令实现对多 Warp 的同步。
   - `vx_fence` 则使用 RISC-V 的 `fence` 指令完成内存同步。

扩展指令：
insn                             opcode          func3   func7
tmc(tmc_zero、tmc_one)      RISCV_CUSTOM0 (0x0B)   0        0
wspawn                      RISCV_CUSTOM0 (0x0B)   1        0
split(split_n)              RISCV_CUSTOM0 (0x0B)   2        0
join                        RISCV_CUSTOM0 (0x0B)   3        0
barrier                     RISCV_CUSTOM0 (0x0B)   4        0 
pred(pred_n)                RISCV_CUSTOM0 (0x0B)   5        0
 ****************************************************/
 /****************************************************
  * 
  * 
  * inline void vx_barrier(int barried_id, int num_warps) {
    __asm__ volatile (".insn r %0, 4, 0, x0, %1, %2" :: "i"(RISCV_CUSTOM0), "r"(barried_id), "r"(num_warps));
}
    * 
    * 解释：

1. .insn r ...：这是 RISC-V 汇编器的伪指令，用于手动编码一条 R-type 指令。
    格式：.insn r opcode, func3, func7, rd, rs1, rs2
    %0 -> opcode (RISCV_CUSTOM0)
    4 -> func3 (Barrier 的功能码)
    0 -> func7
    x0 -> rd (不需要返回值，丢弃)
    %1 -> rs1 (barried_id)
    %2 -> rs2 (num_warps)
2. ::  ：注意这里有两个冒号连在一起，说明没有输出操作数。
3. "i"(RISCV_CUSTOM0)：输入 %0，必须是立即数。
4. "r"(barried_id)：输入 %1。编译器会把变量 barried_id 的值加载到一个寄存器（比如 a1），然后把 a1 填入汇编指令的 rs1 位置。
5. "r"(num_warps)：输入 %2。同上，分配寄存器传递参数。
 ****************************************************/
// Set thread mask
inline void vx_tmc(int thread_mask) {
    // .insn r opcode, func3, func7, rd, rs1, rs2
    // 可以看到这三条tmc 的汇编指令格式是一样的，区别在于 rs1 的值不同而已
    // tmc rs1 (将 rs1 的值设为新的线程掩码)
    __asm__ volatile (".insn r %0, 0, 0, x0, %1, x0" :: "i"(RISCV_CUSTOM0), "r"(thread_mask));
}

// disable all threads in the current warp
inline void vx_tmc_zero() {
    __asm__ volatile (".insn r %0, 0, 0, x0, x0, x0" :: "i"(RISCV_CUSTOM0));
}

// switch execution to single thread zero
inline void vx_tmc_one() {
    __asm__ volatile (
        "li a0, 1\n\t"  // Load immediate value 1 into a0 (x10) register
        ".insn r %0, 0, 0, x0, a0, x0" :: "i"(RISCV_CUSTOM0) : "a0"
    );
}
// pred 和 split 这里之所以有 pred_n 和 split_n 的版本，是为了支持正向谓词和反向谓词两种情况，满足不同的条件分支需求。 --- IGNORE ---
// 硬件上是 is_neg信号； pred执行是 rd[0]位； split执行是 rs2[0]位。 从下面的封装中也可以看到这一点。
// 硬件上需要这一个机制才能支持正向谓词和反向谓词两种情况。 
// Set thread predicate
inline void vx_pred(int condition, int thread_mask) {
    __asm__ volatile (".insn r %0, 5, 0, x0, %1, %2" :: "i"(RISCV_CUSTOM0), "r"(condition), "r"(thread_mask));
}

// Set thread not predicate
inline void vx_pred_n(int condition, int thread_mask) {
    // 这里的x1并不会常规意义的作为rd使用，而是作为一个标志位，表示取反，与vx_pred的区别就在于此。
    // 硬件上针对这条指令，会通过RD位置的译码结果来决定是使用正向谓词还是反向谓词。
    __asm__ volatile (".insn r %0, 5, 0, x1, %1, %2" :: "i"(RISCV_CUSTOM0), "r"(condition), "r"(thread_mask));
}

// Spawn warps
typedef void (*vx_wspawn_pfn)();
inline void vx_wspawn(int num_warps, vx_wspawn_pfn func_ptr) {
    // wspawn rs1, rs2 (激活 rs1 个 warps，让它们从 rs2 地址开始执行)
    // rs2 是函数指针,func_ptr是函数名 也就是一个地址。
    __asm__ volatile (".insn r %0, 1, 0, x0, %1, %2" :: "i"(RISCV_CUSTOM0), "r"(num_warps), "r"(func_ptr));
}

// Split on a predicate
inline int vx_split(int predicate) {
    int ret;
    // split rd, rs1 (根据谓词 rs1 分裂，返回需要跳转的掩码到 rd)
    __asm__ volatile (".insn r %1, 2, 0, %0, %2, x0" : "=r"(ret) : "i"(RISCV_CUSTOM0), "r"(predicate));
    return ret;
}

// Split on a not predicate
inline int vx_split_n(int predicate) {
    int ret;
    __asm__ volatile (".insn r %1, 2, 0, %0, %2, x1" : "=r"(ret) : "i"(RISCV_CUSTOM0), "r"(predicate));
    return ret;
}

// Join
inline void vx_join(int stack_ptr) {
    // join rs1 (合并分支)
    __asm__ volatile (".insn r %0, 3, 0, x0, %1, x0" :: "i"(RISCV_CUSTOM0), "r"(stack_ptr));
}

// Warp Barrier
inline void vx_barrier(int barried_id, int num_warps) {
    __asm__ volatile (".insn r %0, 4, 0, x0, %1, %2" :: "i"(RISCV_CUSTOM0), "r"(barried_id), "r"(num_warps));
}

/***************************************************
6. **多核/多 Warp 属性获取**       这些CSR的定义见 VX_types.vh 文件。  
   - `vx_thread_id` / `vx_warp_id` / `vx_core_id` / `vx_hart_id` 等函数可获取当前线程、Warp、Core 及硬件线程标识。
   - `vx_active_threads` / `vx_active_warps` / `vx_num_threads` / `vx_num_warps` / `vx_num_cores` 提供当前活跃线程/warp 数量、系统线程/warp 数量、以及核心数量等信息。
****************************************************/
// Return current thread identifier
inline int vx_thread_id() {
    int ret;
    __asm__ volatile ("csrr %0, %1" : "=r"(ret) : "i"(VX_CSR_THREAD_ID));
    return ret;
}

// Return current warp identifier
inline int vx_warp_id() {
    int ret;
    __asm__ volatile ("csrr %0, %1" : "=r"(ret) : "i"(VX_CSR_WARP_ID));
    return ret;
}

// Return current core identifier
inline int vx_core_id() {
    int ret;
    __asm__ volatile ("csrr %0, %1" : "=r"(ret) : "i"(VX_CSR_CORE_ID));
    return ret;
}

// Return active threads mask
inline int vx_active_threads() {
    int ret;
    __asm__ volatile ("csrr %0, %1" : "=r"(ret) : "i"(VX_CSR_ACTIVE_THREADS));
    return ret;
}

// Return active warps mask
inline int vx_active_warps() {
    int ret;
    __asm__ volatile ("csrr %0, %1" : "=r"(ret) : "i"(VX_CSR_ACTIVE_WARPS));
    return ret;
}

// Return the number of threads per warp
inline int vx_num_threads() {
    int ret;
    __asm__ volatile ("csrr %0, %1" : "=r"(ret) : "i"(VX_CSR_NUM_THREADS));
    return ret;
}

// Return the number of warps per core
inline int vx_num_warps() {
    int ret;
    __asm__ volatile ("csrr %0, %1" : "=r"(ret) : "i"(VX_CSR_NUM_WARPS));
    return ret;
}

// Return the number of cores per cluster
inline int vx_num_cores() {
    int ret;
    __asm__ volatile ("csrr %0, %1" : "=r"(ret) : "i"(VX_CSR_NUM_CORES));
    return ret;
}

// Return the hart identifier (thread id accross the processor)
inline int vx_hart_id() {
    int ret;
    __asm__ volatile ("csrr %0, %1" : "=r"(ret) : "i"(VX_CSR_MHARTID));
    return ret;
}

inline void vx_fence() {
    __asm__ volatile ("fence iorw, iorw");
}

#ifdef __cplusplus
}
#endif

#endif // __VX_INTRINSICS_H__
