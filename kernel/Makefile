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

#  gcc编译器--使用的newlib的libc;    ar创建静态库；  objdump反汇编；  objcopy目标文件转换，elf -> bin;
CC  = $(RISCV_TOOLCHAIN_PATH)/bin/$(RISCV_PREFIX)-gcc
AR  = $(RISCV_TOOLCHAIN_PATH)/bin/$(RISCV_PREFIX)-gcc-ar
DP  = $(RISCV_TOOLCHAIN_PATH)/bin/$(RISCV_PREFIX)-objdump
CP  = $(RISCV_TOOLCHAIN_PATH)/bin/$(RISCV_PREFIX)-objcopy

# 启用优化、内存模型、禁用异常、启用数据分段、函数分段
# 头文件搜索路径
# 定义宏，  -D 是编译器选项，用于定义一个预处理器宏；这里就是定义了一个宏 XLEN_64； 
# 用于代码中的条件编译，相当于 defined XLEN_64
CFLAGS += -O3 -mcmodel=medany -fno-exceptions -fdata-sections -ffunction-sections
CFLAGS += -I$(INC_DIR) -I$(ROOT_DIR)/hw
CFLAGS += -DXLEN_$(XLEN)

# 生成的库文件名  最终生成 libvortex.a (静态库文件)  libvortex.dump (反汇编文件)
PROJECT := libvortex
# 这里是真正的 kernel 运行时库的源文件；包括了启动文件， 都要看一遍
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
