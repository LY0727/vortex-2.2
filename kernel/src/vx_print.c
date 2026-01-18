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

#include <vx_print.h>
#include <vx_spawn.h>
#include <vx_intrinsics.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "tinyprintf.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
	const char* format;
	va_list*    va;
	int         ret;
} printf_arg_t;

typedef struct {
	int value;
	int base;
} putint_arg_t;

typedef struct {
	float value;
	int precision;
} putfloat_arg_t;

static void __putint_cb(const putint_arg_t* arg) {
	char tmp[33];
	float value = arg->value;
	int base = arg->base;
	itoa(value, tmp, base);   // 整数转换为字符串
	for (int i = 0; i < 33; ++i) {
		int c = tmp[i];
		if (!c)
			break;
		vx_putchar(c);   // 最底层的调用汇编函数输出单个字符
	}
}

static void __putfloat_cb(const putfloat_arg_t* arg) {
	float value = arg->value;
	int precision = arg->precision;
	int ipart = (int)value;
	vx_putint(ipart, 10);
	if (precision != 0) {
		vx_putchar('.');
		float frac = value - (float)ipart;
		float fscaled = frac * pow(10, precision);
		vx_putint((int)fscaled, 10);
	}
}

static void __vprintf_cb(printf_arg_t* arg) {
	arg->ret = tiny_vprintf(arg->format, *arg->va);
}

void vx_putint(int value, int base) {
	putint_arg_t arg;
	arg.value = value;
	arg.base = base;
	vx_serial((vx_serial_cb)__putint_cb, &arg);
}

void vx_putfloat(float value, int precision) {
	putfloat_arg_t arg;
	arg.value = value;
	arg.precision = precision;
	vx_serial((vx_serial_cb)__putfloat_cb, &arg);
}

int vx_vprintf(const char* format, va_list va) {
	printf_arg_t arg;
	arg.format = format;
	arg.va = &va;
	vx_serial((vx_serial_cb)__vprintf_cb, &arg);
  return arg.ret;
}

/*
总结：一次 vx_printf 的旅程
	1.用户调用：vx_printf("Val: %d", 100);
	2.打包：参数被打包成 va_list。
	3.排队 (vx_serial)：进入临界区，Warp 内的线程开始排队。
	4.解析 (tiny_vprintf)：解析字符串，发现 %d，把 100 转成 "100"。
	5.输出 (vx_putchar)：
		1.写 'V' -> IO_COUT_ADDR + tid
		2.写 'a' -> ...
		3....
	6.硬件拦截：仿真器捕获写操作，在终端显示字符。
*/
/* 	拓展思考：  
	目前的实现：     目前的机制依赖于 Magic Address (魔法地址)：

		1. IO_COUT_ADDR (通常定义在 VX_config.h 中，比如 0xFF000000)。
		2. 在 仿真环境 (SimX/RTLSim) 中，仿真器是用 C++ 写的软件。它会监控每一条 Store 指令的地址。如果发现地址是 0xFF000000，它就拦截下来，直接调用宿主机的 std::cout。这是一种“作弊”行为，因为它不需要真实的电路逻辑。
		3. 在 真实硬件 中，CPU 发出的 Store 指令会经过总线（如 AXI Bus）。如果总线上没有挂载一个设备（Slave）去响应这个地址 0xFF000000，总线事务就会超时或报错（Bus Error），导致程序崩溃。
	
	后续要在硬件上真实实现：

	方案 A：硬件 UART 控制器 (最常用)
		1. 硬件修改：在 SoC 的总线上挂载一个 UART (串口) 控制器 IP 核。
		2. 地址映射：把这个 UART 控制器的寄存器映射到某个物理地址（比如就映射到 IO_COUT_ADDR，或者修改代码指向新地址）。
		3. 驱动修改：
			3.1 修改 vx_putchar。不再是简单地 sb a0, 0(t0) (写内存)。
			3.2 而是要先查询 UART 的 状态寄存器 (Status Register)，等待发送缓冲区为空（FIFO Not Full）。
			3.3 然后把字符写入 数据寄存器 (Data Register)。
		4. 外部连接：FPGA 的 TX 引脚连到电脑的 USB 转串口，你在电脑上用串口助手就能看到打印了。

	方案 B：共享内存 + 主机轮询 (PCIe 加速卡模式)
	如果 Vortex 是作为 GPU 插在 PCIe 插槽上的：

		硬件修改：不需要 UART。利用现有的 DRAM (显存)。
		原理：
			IO_COUT_ADDR 被映射到显存的一块保留区域（Ring Buffer / 环形缓冲区）。
			Kernel 里的 vx_putchar 负责往这个环形缓冲区里写数据，并更新写指针。
		主机驱动：
			Host CPU (x86) 端的驱动程序会不断轮询（或通过中断触发）读取这块显存区域。读到新数据后，由 Host CPU 打印到终端。
		注：Vortex 的 vx_print.S 其实已经有点这个意思了（利用 MHARTID 做偏移），但目前它依赖仿真器去“主动偷看”内存，而不是真实的 DMA 或 PCIe 传输。

	总结与建议：
		1. // hw/rtl/afu/opae/vortex_afu.sv (约 977 行)       opae的封装方案中已经实现了方案B的思路。后续可以考虑借鉴。
*/
int vx_printf(const char * format, ...) {
	int ret;
	va_list va;
	va_start(va, format);
	ret = vx_vprintf(format, va);
	va_end(va);
  return ret;
}

#ifdef __cplusplus
}
#endif
