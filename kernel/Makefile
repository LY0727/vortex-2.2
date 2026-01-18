ROOT_DIR := $(realpath ..)
include $(ROOT_DIR)/config.mk

# 关键的两个编译选项；指定RISCV架构；指定ABI规则； 可以看到差别仅仅是 是否支持double类型
ifeq ($(XLEN),64)
CFLAGS += -march=rv64imafd -mabi=lp64d
else
CFLAGS += -march=rv32imaf -mabi=ilp32f
endif
# 头文件、源文件
INC_DIR := $(VORTEX_HOME)/kernel/include
SRC_DIR := $(VORTEX_HOME)/kernel/src

# 编译kernel库 并没有使用这里 llvm的编译器;  而是使用的riscv的编译器
LLVM_CFLAGS += --sysroot=$(RISCV_SYSROOT)
LLVM_CFLAGS += --gcc-toolchain=$(RISCV_TOOLCHAIN_PATH)
LLVM_CFLAGS += -Xclang -target-feature -Xclang +vortex -mllvm -vortex-branch-divergence=0
#LLVM_CFLAGS += -I$(RISCV_SYSROOT)/include/c++/9.2.0/$(RISCV_PREFIX)
#LLVM_CFLAGS += -I$(RISCV_SYSROOT)/include/c++/9.2.0
#LLVM_CFLAGS += -Wl,-L$(RISCV_TOOLCHAIN_PATH)/lib/gcc/$(RISCV_PREFIX)/9.2.0
#LLVM_CFLAGS += --rtlib=libgcc

#CC  = $(LLVM_VORTEX)/bin/clang $(LLVM_CFLAGS)
#AR  = $(LLVM_VORTEX)/bin/llvm-ar
#DP  = $(LLVM_VORTEX)/bin/llvm-objdump
#CP  = $(LLVM_VORTEX)/bin/llvm-objcopy

#  risc-v编译工具链;    ar创建静态库；  objdump反汇编；  objcopy目标文件转换，elf -> bin;
#  扩展指令都是.insns文件里实现的，编译器只需要支持基本的riscv指令集就行了；所以这里就是标准的RISCV编译器；
CC  = $(RISCV_TOOLCHAIN_PATH)/bin/$(RISCV_PREFIX)-gcc
AR  = $(RISCV_TOOLCHAIN_PATH)/bin/$(RISCV_PREFIX)-gcc-ar
DP  = $(RISCV_TOOLCHAIN_PATH)/bin/$(RISCV_PREFIX)-objdump
CP  = $(RISCV_TOOLCHAIN_PATH)/bin/$(RISCV_PREFIX)-objcopy

# -O3: 最高级别优化。
# -mcmodel=medany (Medium-Any Memory Model): 非常重要。这告诉编译器生成的代码可以放在内存的任意位置（但在 +/- 2GB 范围内跳转）。如果没有这个选项，编译器可能会假设代码在低地址（由 medlow 模型处理），当你把代码加载到 GPU 显存的高地址时，可能会崩溃。
# -fdata-sections -ffunction-sections:  把每个函数和全局变量放在独立的段（section）里。配合链接器的 --gc-sections 选项（通常在应用层的 Makefile 里），可以自动剔除没有被调用的死代码，减小最终二进制文件的体积。
# -I : 头文件搜索路径；
# -D : 是编译器选项，用于定义一个预处理器宏；这里就是定义了一个宏 XLEN_64 or XLEN_32； 
CFLAGS += -O3 -mcmodel=medany -fno-exceptions -fdata-sections -ffunction-sections
CFLAGS += -I$(INC_DIR) -I$(ROOT_DIR)/hw
CFLAGS += -DXLEN_$(XLEN)

# 生成的库文件名  最终生成 libvortex.a (静态库文件)  libvortex.dump (反汇编文件)
PROJECT := libvortex
# 这里是真正的 kernel 内核库的源文件；包括了启动文件， 都要看一遍
SRCS = $(SRC_DIR)/vx_start.S $(SRC_DIR)/vx_syscalls.c $(SRC_DIR)/vx_print.S $(SRC_DIR)/tinyprintf.c $(SRC_DIR)/vx_print.c $(SRC_DIR)/vx_spawn.c $(SRC_DIR)/vx_serial.S $(SRC_DIR)/vx_perf.c
# 生成的目标文件列表；每个源文件生成一个目标文件
OBJS = $(addsuffix .o, $(notdir $(SRCS)))

all: $(PROJECT).a $(PROJECT).dump

# 对静态库生成反汇编文件
$(PROJECT).dump: $(PROJECT).a
	$(DP) -D $(PROJECT).a > $(PROJECT).dump

# 编译器生成 可重定向目标文件 .o
%.S.o: $(SRC_DIR)/%.S
	$(CC) $(CFLAGS) -c $< -o $@

%.c.o: $(SRC_DIR)/%.c
	$(CC) $(CFLAGS) -c $< -o $@

# ar 生成静态库
$(PROJECT).a: $(OBJS)
	$(AR) rcs $@ $^

# 自动生成依赖关系
.depend: $(SRCS)
	$(CC) $(CFLAGS) -MM $^ > .depend;

clean:
	rm -rf *.a *.o *.dump .depend
