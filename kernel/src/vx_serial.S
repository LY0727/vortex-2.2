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

#include <VX_config.h>
#include <VX_types.h>

#define RISCV_CUSTOM0   0x0B

.type vx_serial, @function
.global vx_serial
vx_serial:
#if (XLEN == 64)
    addi sp, sp, -56
    sd   ra, 48(sp)
    sd   s5, 40(sp)
    sd   s4, 32(sp)
    sd   s3, 24(sp)
    sd   s2, 16(sp)
    sd   s1, 8(sp)
    sd   s0, 0(sp)
#else
    addi sp, sp, -28      // make space on stack(每个thread都有一个sp),sp向下移动28字节
    sw   ra, 24(sp)       // save return address
    sw   s5, 20(sp)       // save callee-saved registers  (上下文保存)
    sw   s4, 16(sp)
    sw   s3, 12(sp)
    sw   s2, 8(sp)
    sw   s1, 4(sp)
    sw   s0, 0(sp)
#endif
    mv   s4, a0                 # s4 <- callback（回调函数地址）
    mv   s3, a1                 # s3 <- arg     （回调函数参数）
    csrr s2, VX_CSR_NUM_THREADS # s2 <- NT      （warp内线程数）
    csrr s1, VX_CSR_THREAD_ID   # s1 <- tid     （当前线程ID）
    li	 s0, 0                  # s0 <- index   （循环计数器，从0开始）
label_loop:
    sub	 t0, s0, s1             # 1. t0 = (index - tid)
    seqz t1, t0                 # 2. 根据t0是否为0设置t1，t1=1表示相等，t1=0表示不等；
                                #    这样就实现了每次只有一个线程会执行后续的callback调用。       
    # 3. 硬件分歧控制 (Split)
    # 作用：根据条件 t1，把 Warp 里的线程分成两组：
    #      - "Taken" 组：t1=1 的线程 (即当前轮到的那个线程)
    #      - "Not Taken" 组：t1=0 的线程 (其他线程)
    #      s5 寄存器： split指令返回的，IPDOM栈的栈顶ID，用于后续的 join 指令。
    .insn r RISCV_CUSTOM0, 2, 0, s5, t1, x0  # split s5, t0

    # 4. t0 != 0 时，跳过 callback 调用
    #    split分支1：会执行 callback
    #    split分支2：直接跳到 label_join
    bnez t0, label_join
    # 5. t0=0 的线程, 调用回调函数
    mv   a0, s3                 # a0 <- arg
    jalr s4                     # callback(arg)
label_join:
    # 6. 硬件分歧控制 (Join)
    # 作用：等待所有线程到达此点，然后重新合并成一个统一的执行流。
    #      s5 寄存器保存了之前 split 时的分支状态信息。
    .insn r RISCV_CUSTOM0, 3, 0, x0, s5, x0  # join s5
    # 7. index++,循环
    addi s0, s0, 1              # index++
    blt	 s0, s2, label_loop     # loop back
#if (XLEN == 64)
    ld   ra, 48(sp)
    ld   s5, 40(sp)
    ld   s4, 32(sp)
    ld   s3, 24(sp)
    ld   s2, 16(sp)
    ld   s1, 8(sp)
    ld   s0, 0(sp)
    addi sp, sp, 56
#else
    lw   ra, 24(sp)     // 上下文恢复
    lw   s5, 20(sp)
    lw   s4, 16(sp)
    lw   s3, 12(sp)
    lw   s2, 8(sp)
    lw   s1, 4(sp)
    lw   s0, 0(sp)
    addi sp, sp, 28
#endif
    ret     // return to caller
