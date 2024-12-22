ROOT_DIR := $(realpath ../../..)

TARGET ?= opaesim

XRT_SYN_DIR ?= $(VORTEX_HOME)/hw/syn/xilinx/xrt
XRT_DEVICE_INDEX ?= 0

# 指定架构 和 ABI
# 设置 起始地址
ifeq ($(XLEN),64)
VX_CFLAGS += -march=rv64imafd -mabi=lp64d
STARTUP_ADDR ?= 0x180000000
else
VX_CFLAGS += -march=rv32imaf -mabi=ilp32f
STARTUP_ADDR ?= 0x80000000
endif

# 不需要使用
LLVM_CFLAGS += --sysroot=$(RISCV_SYSROOT)
LLVM_CFLAGS += --gcc-toolchain=$(RISCV_TOOLCHAIN_PATH)
LLVM_CFLAGS += -Xclang -target-feature -Xclang +vortex
LLVM_CFLAGS += -Xclang -target-feature -Xclang +zicond
LLVM_CFLAGS += -mllvm -disable-loop-idiom-all # disable memset/memcpy loop idiom
#LLVM_CFLAGS += -mllvm -vortex-branch-divergence=0
#LLVM_CFLAGS += -mllvm -print-after-all
#LLVM_CFLAGS += -I$(RISCV_SYSROOT)/include/c++/9.2.0/$(RISCV_PREFIX)
#LLVM_CFLAGS += -I$(RISCV_SYSROOT)/include/c++/9.2.0
#LLVM_CFLAGS += -Wl,-L$(RISCV_TOOLCHAIN_PATH)/lib/gcc/$(RISCV_PREFIX)/9.2.0
#LLVM_CFLAGS += --rtlib=libgcc

# llvm-vortex 这套编译工具
VX_CC  = $(LLVM_VORTEX)/bin/clang $(LLVM_CFLAGS)
VX_CXX = $(LLVM_VORTEX)/bin/clang++ $(LLVM_CFLAGS)
VX_DP  = $(LLVM_VORTEX)/bin/llvm-objdump
VX_CP  = $(LLVM_VORTEX)/bin/llvm-objcopy

#VX_CC  = $(RISCV_TOOLCHAIN_PATH)/bin/$(RISCV_PREFIX)-gcc
#VX_CXX = $(RISCV_TOOLCHAIN_PATH)/bin/$(RISCV_PREFIX)-g++
#VX_DP  = $(RISCV_TOOLCHAIN_PATH)/bin/$(RISCV_PREFIX)-objdump
#VX_CP  = $(RISCV_TOOLCHAIN_PATH)/bin/$(RISCV_PREFIX)-objcopy

VX_CFLAGS += -O3 -mcmodel=medany -fno-rtti -fno-exceptions -nostartfiles -nostdlib -fdata-sections -ffunction-sections
VX_CFLAGS += -I$(VORTEX_KN_PATH)/include -I$(ROOT_DIR)/hw
VX_CFLAGS += -DXLEN_$(XLEN)
VX_CFLAGS += -DNDEBUG

VX_LIBS += -L$(LIBC_VORTEX)/lib -lm -lc

VX_LIBS += $(LIBCRT_VORTEX)/lib/baremetal/libclang_rt.builtins-riscv$(XLEN).a
#VX_LIBS += -lgcc

VX_LDFLAGS += -Wl,-Bstatic,--gc-sections,-T,$(VORTEX_KN_PATH)/scripts/link$(XLEN).ld,--defsym=STARTUP_ADDR=$(STARTUP_ADDR) $(ROOT_DIR)/kernel/libvortex.a $(VX_LIBS)

CXXFLAGS += -std=c++11 -Wall -Wextra -pedantic -Wfatal-errors
CXXFLAGS += -I$(VORTEX_RT_PATH)/include -I$(ROOT_DIR)/hw

LDFLAGS += -L$(ROOT_DIR)/runtime -lvortex

# Debugging
ifdef DEBUG
	CXXFLAGS += -g -O0
else
	CXXFLAGS += -O2 -DNDEBUG
endif

ifeq ($(TARGET), fpga)
	OPAE_DRV_PATHS ?= libopae-c.so
else
ifeq ($(TARGET), asesim)
	OPAE_DRV_PATHS ?= libopae-c-ase.so
else
ifeq ($(TARGET), opaesim)
	OPAE_DRV_PATHS ?= libopae-c-sim.so
endif
endif
endif

all: $(PROJECT) kernel.vxbin kernel.dump

kernel.dump: kernel.elf
	$(VX_DP) -D $< > $@

# 3. kernel.vxbin
kernel.vxbin: kernel.elf
	OBJCOPY=$(VX_CP) $(VORTEX_HOME)/kernel/scripts/vxbin.py $< $@

# 2. llvm-vortex 编译器   kernel.elf
# 源文件  ： kernel.cpp   
# 编译器  ： clang++  编译器
# 编译标志： 优化级别、模型、无rtti、无异常、无启动文件、无标准库、单独的 数据段 和 函数段
# 头文件  ：  runtime/include  build/hw
# 链接标志：  静态链接、收集未使用的段、指定链接脚本、指定起始地址； 
# 链接库  ：  kernel/libvortex.a  libc64/lib -lm -lc，libclang_rt.builtins-riscv64.a
kernel.elf: $(VX_SRCS)
	$(VX_CXX) $(VX_CFLAGS) $^ $(VX_LDFLAGS) -o kernel.elf

# 1. g++ 编译器   vecaddx 可执行程序
# 源文件：  main.cpp
# 头文件：	runtime/include    build/hw
# 链接库：  libvortex.so                       
# regression 和 opencl 两类测试生成可执行文件时都是链接的 libvortex.so ； 
# 经过全局搜索可以发现，runtime/rtlsim/   编译生成的 libvortex-rtlsim.so 确实时没看到使用啊
$(PROJECT): $(SRCS)
	$(CXX) $(CXXFLAGS) $^ $(LDFLAGS) -o $@

run-simx: $(PROJECT) kernel.vxbin
	LD_LIBRARY_PATH=$(ROOT_DIR)/runtime:$(LD_LIBRARY_PATH) VORTEX_DRIVER=simx ./$(PROJECT) $(OPTS)

# 4. 设置环境变量 运行
# 运行时库路径： build/runtime      感觉似乎仅仅只是使用这个 libvortex.so  
# 驱动程序：    rtlsim
run-rtlsim: $(PROJECT) kernel.vxbin
	LD_LIBRARY_PATH=$(ROOT_DIR)/runtime:$(LD_LIBRARY_PATH) VORTEX_DRIVER=rtlsim ./$(PROJECT) $(OPTS)

run-opae: $(PROJECT) kernel.vxbin
	SCOPE_JSON_PATH=$(ROOT_DIR)/runtime/scope.json OPAE_DRV_PATHS=$(OPAE_DRV_PATHS) LD_LIBRARY_PATH=$(ROOT_DIR)/runtime:$(LD_LIBRARY_PATH) VORTEX_DRIVER=opae ./$(PROJECT) $(OPTS)

run-xrt: $(PROJECT) kernel.vxbin

ifeq ($(TARGET), hw)
	XRT_INI_PATH=$(XRT_SYN_DIR)/xrt.ini EMCONFIG_PATH=$(FPGA_BIN_DIR) XRT_DEVICE_INDEX=$(XRT_DEVICE_INDEX) XRT_XCLBIN_PATH=$(FPGA_BIN_DIR)/vortex_afu.xclbin LD_LIBRARY_PATH=$(XILINX_XRT)/lib:$(ROOT_DIR)/runtime:$(LD_LIBRARY_PATH) VORTEX_DRIVER=xrt ./$(PROJECT) $(OPTS)
else
	XCL_EMULATION_MODE=$(TARGET) XRT_INI_PATH=$(XRT_SYN_DIR)/xrt.ini EMCONFIG_PATH=$(FPGA_BIN_DIR) XRT_DEVICE_INDEX=$(XRT_DEVICE_INDEX) XRT_XCLBIN_PATH=$(FPGA_BIN_DIR)/vortex_afu.xclbin LD_LIBRARY_PATH=$(XILINX_XRT)/lib:$(ROOT_DIR)/runtime:$(LD_LIBRARY_PATH) VORTEX_DRIVER=xrt ./$(PROJECT) $(OPTS)
endif

.depend: $(SRCS)
	$(CXX) $(CXXFLAGS) -MM $^ > .depend;

clean-kernel:
	rm -rf *.elf *.vxbin *.dump

clean-host:
	rm -rf $(PROJECT) *.o *.log .depend

clean: clean-kernel clean-host

ifneq ($(MAKECMDGOALS),clean)
    -include .depend
endif
