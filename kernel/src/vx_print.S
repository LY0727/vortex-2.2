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
#include "common.h"

/*
核心原理 (MMIO)：

    CPU 并没有专门的“打印指令”。
    Vortex 硬件设计了一个特殊的内存地址 IO_COUT_ADDR。
    当 CPU 往这个地址写数据时，内存控制器会拦截这个写操作，把数据转发给仿真器 (SimX/RTLSim)。
    仿真器收到数据后，就会在你的终端上打印出这个字符。
    多线程隔离：每个线程都有自己的一小块地盘（IO_COUT_ADDR + tid），这样硬件就能知道是哪个线程在说话，从而在打印时加上前缀（比如 [Thread 0] Hello）。
*/
.type vx_putchar, @function
.global vx_putchar
vx_putchar:
    # 1. 获取当前线程的全局 ID (Hart ID)
    csrr t0, VX_CSR_MHARTID
    
    # 2. 计算输出缓冲区偏移量
    # IO_COUT_SIZE 是每个线程独享的输出缓冲区大小（防止多线程输出打架）
    # 这里用掩码操作 (IO_COUT_SIZE-1) 确保 ID 不会越界，虽然通常 HartID 就在范围内。
    andi t0, t0, %lo(IO_COUT_SIZE-1)
    
    # 3. 获取输出缓冲区的基地址 (IO_COUT_ADDR)
    li t1, IO_COUT_ADDR
    
    # 4. 计算最终写入地址 = 基地址 + 线程偏移
    add t0, t0, t1
    
    # 5. Store Byte (sb): 把参数 a0 (即要打印的字符) 写入到这个内存地址
    sb a0, 0(t0)
    
    ret
