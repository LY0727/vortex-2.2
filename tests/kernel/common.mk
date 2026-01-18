ROOT_DIR := $(realpath ../../..)

# ilp32f: int、long、pointer 都是32-bit,浮点参数通过浮点寄存器传递。 
ifeq ($(XLEN),64)
CFLAGS += -march=rv64imafd -mabi=lp64d
else
CFLAGS += -march=rv32imaf -mabi=ilp32f
endif

# 未使用
LLVM_CFLAGS += --sysroot=$(RISCV_SYSROOT)
LLVM_CFLAGS += --gcc-toolchain=$(RISCV_TOOLCHAIN_PATH)
LLVM_CFLAGS += -Xclang -target-feature -Xclang +vortex -mllvm -vortex-branch-divergence=0

# LLVM这一套在这里用不上
#CC  = $(LLVM_VORTEX)/bin/clang $(LLVM_CFLAGS)
#CXX = $(LLVM_VORTEX)/bin/clang++ $(LLVM_CFLAGS)
#AR  = $(LLVM_VORTEX)/bin/llvm-ar
#DP  = $(LLVM_VORTEX)/bin/llvm-objdump
#CP  = $(LLVM_VORTEX)/bin/llvm-objcopy

# 使用GCC工具链    c、c++编译器,AR 静态库打包工具,DP 反汇编工具,CP 二进制文件转换工具 （将含有调试信息的.elf剥离成纯二进制文件.bin）
CC  = $(RISCV_TOOLCHAIN_PATH)/bin/$(RISCV_PREFIX)-gcc
CXX = $(RISCV_TOOLCHAIN_PATH)/bin/$(RISCV_PREFIX)-g++
AR  = $(RISCV_TOOLCHAIN_PATH)/bin/$(RISCV_PREFIX)-gcc-ar
DP  = $(RISCV_TOOLCHAIN_PATH)/bin/$(RISCV_PREFIX)-objdump
CP  = $(RISCV_TOOLCHAIN_PATH)/bin/$(RISCV_PREFIX)-objcopy

# 编译选项说明：
# -O3: 最高等级优化。对于 GPGPU 内核代码，性能至关重要。
# -mcmodel=medany: 关键！ Medium-Any Code Model。允许符号地址在 2GB 范围内的任意位置（绝对寻址）。如果用默认的 medlow，代码只能放在低 2GB 空间，而 GPGPU 的内存映射往往很高（如 0x80000000）。
# -fno-exceptions: 禁用 C++ 异常处理 (try-catch)。裸机环境没有 OS 负责栈展开 (stack unwinding)，这能减小二进制体积。
# -nostartfiles: 不链接标准的启动文件 (如 crt0.o)。因为我们有自己的 vx_start.S。
# -nostdlib: 不链接标准库。 
# -fdata-sections -ffunction-sections: 把每个函数和全局变量放在独立的段 (Section) 中。配合链接器的 --gc-sections，可以把没用到的死代码（Dead Code）删得干干净净。
# -DXLEN_$(XLEN) -DNDEBUG: 定义宏供代码中使用。
CFLAGS += -O3 -mcmodel=medany -fno-exceptions -nostartfiles -nostdlib -fdata-sections -ffunction-sections
CFLAGS += -I$(VORTEX_KN_PATH)/include -I$(ROOT_DIR)/hw
CFLAGS += -DXLEN_$(XLEN) -DNDEBUG

# 库文件依赖：
# 虽然用了 -nostdlib，但我们手动链接了 Vortex 预编译的 libc (Newlib) 和 libm (数学库)。
# libclang_rt.builtins: 编译器内置函数库。用于处理硬件不支持的操作（比如如果硬件不支持除法，这里会提供软除法函数）。
LIBC_LIB += -L$(LIBC_VORTEX)/lib -lm -lc
LIBC_LIB += $(LIBCRT_VORTEX)/lib/baremetal/libclang_rt.builtins-riscv$(XLEN).a

# 链接选项说明：
# -Wl,...: 告诉 gcc，逗号后面的是传给链接器 (ld) 的参数。
# -Bstatic: 强制静态链接。
# --gc-sections: 垃圾回收段。配合前面的 -ffunction-sections，把没被调用的函数直接剔除，极其适合嵌入式。
# -T link$(XLEN).ld: 核心！ 指定链接脚本。它决定了 .text 放哪，.data 放哪，栈放在哪。
# --defsym=STARTUP_ADDR=0x80000000: 定义符号 STARTUP_ADDR。这是程序的入口地址，也是模拟器加载程序的起始物理地址。
# libvortex.a: Vortex 内核运行时库（包含 vx_start.S, vx_spawn, tinyprintf 等）。
LDFLAGS += -Wl,-Bstatic,--gc-sections,-T,$(VORTEX_KN_PATH)/scripts/link$(XLEN).ld,--defsym=STARTUP_ADDR=0x80000000 $(ROOT_DIR)/kernel/libvortex.a $(LIBC_LIB)


all: $(PROJECT).elf $(PROJECT).bin $(PROJECT).dump

$(PROJECT).dump: $(PROJECT).elf
	$(DP) -D $< > $@

$(PROJECT).bin: $(PROJECT).elf
	$(CP) -O binary $< $@

$(PROJECT).elf: $(SRCS)
	$(CC) $(CFLAGS) $^ $(LDFLAGS) -o $@

run-rtlsim: $(PROJECT).bin
	$(ROOT_DIR)/sim/rtlsim/rtlsim $(PROJECT).bin

run-simx: $(PROJECT).bin
	$(ROOT_DIR)/sim/simx/simx $(PROJECT).bin

.depend: $(SRCS)
	$(CC) $(CFLAGS) -MM $^ > .depend;

clean:
	rm -rf *.elf *.bin *.dump *.log .depend
