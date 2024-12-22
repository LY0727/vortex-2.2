ROOT_DIR := $(realpath ../../..)
# 设置默认仿真器；因为 tests 支持四种仿真器
TARGET ?= opaesim
# 单独设置XRT 综合工具目录;设备索引
XRT_SYN_DIR ?= $(VORTEX_HOME)/hw/syn/xilinx/xrt
XRT_DEVICE_INDEX ?= 0

# ISA子集； ABI规则； 
# 起始地址； 这里注意对应	sim/rtlsim/makefile 中带main.cpp编译时也设置了起始地址
# POCL_CC_FLAGS 为编译opencl的编译器参数 
ifeq ($(XLEN),64)
VX_CFLAGS += -march=rv64imafd -mabi=lp64d
STARTUP_ADDR ?= 0x180000000
POCL_CC_FLAGS += POCL_VORTEX_XLEN=64
else
VX_CFLAGS += -march=rv32imaf -mabi=ilp32f
STARTUP_ADDR ?= 0x80000000
POCL_CC_FLAGS += POCL_VORTEX_XLEN=32
endif

# 基于pocl 定制修改的 openCL 库
POCL_PATH ?= $(TOOLDIR)/pocl
# 基于pocl 定制修改的 llvm-vortex编译器; 完成kernel.cl的编译
LLVM_POCL ?= $(TOOLDIR)/llvm-vortex

# 依赖的C-lib      .a 静态库文件
# kernel/Makefile 中 使用riscv$(XLEN)-unknown-elf编译器，使用的是newlib的libc
# runtime/rtlsim/Makefile 中 使用的是gcc编译器，linux下的libc
# sim/rtlsim/Makefile 中 使用的是gcc编译器，linux下的libc
# tests/opencl/conv3/Makefile 中 分为两套工具：
#    1.  kernel.cl  使用的是基于pocl修改的 llvm-vortex 编译器;    
#        libc 和 libclang_rt.builtins-riscv64.a 这两个库需要搞清楚是什么库。
#    2.  main.cc 使用的是基于gnu的编译器，使用的是linux下的libc； 
#		 头文件路径添加了基于pocl的opencl库；这些头文件就是 main.cc 与 kernel.cl 之间的接口 
#		 链接选项添加了 llvm-vortex 的库路径;  
#
VX_LIBS += -L$(LIBC_VORTEX)/lib -lm -lc
VX_LIBS += $(LIBCRT_VORTEX)/lib/baremetal/libclang_rt.builtins-riscv$(XLEN).a
#VX_LIBS += -lgcc

# llvm-vortex 编译器参数
# -O3：启用最高级优化； -mcmodel=medany：启用中等模型； --sysroot=$(RISCV_SYSROOT)：指定系统根目录； --gcc-toolchain=$(RISCV_TOOLCHAIN_PATH)：指定gcc工具链；
# -fno-rtti：禁用运行时类型识别； -fno-exceptions：禁用异常； -nostartfiles：禁用启动文件； -nostdlib：禁用标准库； -fdata-sections：启用数据分段； -ffunction-sections：启用函数分段；
# 指定头文件搜索路径； -I$(ROOT_DIR)/hw：-I$(VORTEX_KN_PATH)/include：    hw/ kernel/include/ 两个目录下的头文件；
# -DXLEN_$(XLEN)：定义宏； -DNDEBUG：定义宏；
# -Xclang -target-feature -Xclang +vortex：指定目标特性； 
# -Xclang -target-feature -Xclang +zicond：指定目标特性； 
# -mllvm -disable-loop-idiom-all：禁用循环习语；
VX_CFLAGS  += -O3 -mcmodel=medany --sysroot=$(RISCV_SYSROOT) --gcc-toolchain=$(RISCV_TOOLCHAIN_PATH)
VX_CFLAGS  += -fno-rtti -fno-exceptions -nostartfiles -nostdlib -fdata-sections -ffunction-sections
VX_CFLAGS  += -I$(ROOT_DIR)/hw -I$(VORTEX_KN_PATH)/include -DXLEN_$(XLEN) -DNDEBUG
VX_CFLAGS  += -Xclang -target-feature -Xclang +vortex
VX_CFLAGS  += -Xclang -target-feature -Xclang +zicond
VX_CFLAGS  += -mllvm -disable-loop-idiom-all
#VX_CFLAGS += -mllvm -vortex-branch-divergence=0
#VX_CFLAGS += -mllvm -print-after-all

# 链接器参数
# -Wl,-Bstatic,--gc-sections：启用静态链接和垃圾收集。
# -T：指定链接脚本。 
# --defsym=STARTUP_ADDR=$(STARTUP_ADDR)：定义启动地址。  
# $(ROOT_DIR)/kernel/libvortex.a：    链接 Vortex 库，这个库是 kernel/Makefile 生成的。 vortex库中包含了启动文件、系统调用、打印函数、串行通信、性能计数器等。
# $(VX_LIBS)：链接 C 库。			   这里的C库是 libc 和 libclang_rt.builtins-riscv64.a ；
VX_LDFLAGS += -Wl,-Bstatic,--gc-sections,-T$(VORTEX_KN_PATH)/scripts/link$(XLEN).ld,--defsym=STARTUP_ADDR=$(STARTUP_ADDR) $(ROOT_DIR)/kernel/libvortex.a $(VX_LIBS)

# 二进制工具  
# OBJCOPY：指定目标文件转换工具。            gcc中，这个工具直接就可以完成 elf到bin
# $(VORTEX_HOME)/kernel/scripts/vxbin.py：  这里还用了一个python脚本完成转换      
VX_BINTOOL += OBJCOPY=$(LLVM_VORTEX)/bin/llvm-objcopy $(VORTEX_HOME)/kernel/scripts/vxbin.py


# 这里给出了 llvm-vortex 的编译器路径; elf转bin工具路径；  llvm-vortex 编译器参数;  llvm-vortex 链接器参数
POCL_CC_FLAGS += LLVM_PREFIX=$(LLVM_VORTEX) POCL_VORTEX_BINTOOL="$(VX_BINTOOL)" POCL_VORTEX_CFLAGS="$(VX_CFLAGS)" POCL_VORTEX_LDFLAGS="$(VX_LDFLAGS)"


#  C++编译器 参数
#  -std=c++11：使用C++11标准；
#  -Wall -Wextra -Wfatal-errors：启用所有警告，额外警告，错误警告；
#  -Wno-deprecated-declarations -Wno-unused-parameter -Wno-narrowing：忽略特定警告；
#  -pthread：启用多线程；
#  -I$(POCL_PATH)/include：指定头文件搜索路径；  这里的头文件路径是基于pocl的opencl库 
CXXFLAGS += -std=c++11 -Wall -Wextra -Wfatal-errors
CXXFLAGS += -Wno-deprecated-declarations -Wno-unused-parameter -Wno-narrowing
CXXFLAGS += -pthread
CXXFLAGS += -I$(POCL_PATH)/include

# Debugging
ifdef DEBUG
	CXXFLAGS += -g -O0
	POCL_CC_FLAGS += POCL_DEBUG=all
else
	CXXFLAGS += -O2 -DNDEBUG
endif

# 链接 llvm-vortex 的库
# -rpath,指定运行时库文件搜索路径；
LDFLAGS += -Wl,-rpath,$(LLVM_VORTEX)/lib

# 这里的驱动库 和 仿真 我们暂时不关注
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

# 生成的目标文件列表；每个源文件生成一个目标文件
OBJS := $(addsuffix .o, $(notdir $(SRCS)))

all: $(PROJECT)

# 每个源文件生成 .o 文件
# 头文件路径添加了基于pocl的opencl库；
%.cc.o: $(SRC_DIR)/%.cc
	$(CXX) $(CXXFLAGS) -c $< -o $@

%.cpp.o: $(SRC_DIR)/%.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

%.c.o: $(SRC_DIR)/%.c
	$(CC) $(CXXFLAGS) -c $< -o $@

# 生成可执行文件：  源文件只包含了 main.cpp;  其他的都是动态链接库；
# 头文件路径添加了基于pocl的opencl库； 链接选项添加了 llvm-vortex 的库路径;
# 链接了 libvortex.so;  位于 build/runtime ; 这个是由 runtime/stub/Makefile 生成的；     这个是关键！
# 链接了 libOpenCL.so;  位于pocl/lib ;  openCL的动态库，
# 
$(PROJECT): $(OBJS)
	$(CXX) $(CXXFLAGS) $(OBJS) $(LDFLAGS) -L$(ROOT_DIR)/runtime -lvortex -L$(POCL_PATH)/lib -lOpenCL -o $@

$(PROJECT).host: $(OBJS)
	$(CXX) $(CXXFLAGS) $(OBJS) $(LDFLAGS) -lOpenCL -o $@

run-gpu: $(PROJECT).host $(KERNEL_SRCS)
	./$(PROJECT).host $(OPTS)

run-simx: $(PROJECT) $(KERNEL_SRCS)
	LD_LIBRARY_PATH=$(POCL_PATH)/lib:$(ROOT_DIR)/runtime:$(LLVM_VORTEX)/lib:$(LD_LIBRARY_PATH) $(POCL_CC_FLAGS) VORTEX_DRIVER=simx ./$(PROJECT) $(OPTS)

# 执行可执行文件， 执行过程中进行动态链接。
# 1.  LD_LIBRARY_PATH：指定动态链接库搜索路径： pocl/lib:  build/runtime:   llvm-vortex/lib:
# 2.  POCL_CC_FLAGS：指定编译器参数；  
#		2.1  POCL_VORTEX_XLEN=64：指定ISA子集；
#		2.2  POCL_DEBUG=all：指定调试模式；
#		2.3  LLVM_PREFIX=$(LLVM_VORTEX)：指定llvm-vortex编译器路径；
#		2.4  POCL_VORTEX_BINTOOL="$(VX_BINTOOL)"：指定二进制工具；
#		2.5  POCL_VORTEX_CFLAGS="$(VX_CFLAGS)"：  指定编译器参数；
#		2.6  POCL_VORTEX_LDFLAGS="$(VX_LDFLAGS)"：指定链接器参数；  kernel/libvortex.a; libc 和 libclang_rt.builtins-riscv64.a ；
# 3.  VORTEX_DRIVER：指定驱动器类型；  这里是rtlsim；  这个宏定义在 runtime/rtlsim/vortex.cpp 中有用到；
# 4.  ./$(PROJECT) $(OPTS)：执行可执行文件，传入参数
run-rtlsim: $(PROJECT) $(KERNEL_SRCS)
	LD_LIBRARY_PATH=$(POCL_PATH)/lib:$(ROOT_DIR)/runtime:$(LLVM_VORTEX)/lib:$(LD_LIBRARY_PATH) $(POCL_CC_FLAGS) VORTEX_DRIVER=rtlsim ./$(PROJECT) $(OPTS)

run-opae: $(PROJECT) $(KERNEL_SRCS)
	SCOPE_JSON_PATH=$(ROOT_DIR)/runtime/scope.json OPAE_DRV_PATHS=$(OPAE_DRV_PATHS) LD_LIBRARY_PATH=$(POCL_PATH)/lib:$(ROOT_DIR)/runtime:$(LLVM_VORTEX)/lib:$(LD_LIBRARY_PATH) $(POCL_CC_FLAGS) VORTEX_DRIVER=opae ./$(PROJECT) $(OPTS)

run-xrt: $(PROJECT) $(KERNEL_SRCS)
ifeq ($(TARGET), hw)
	XRT_INI_PATH=$(XRT_SYN_DIR)/xrt.ini EMCONFIG_PATH=$(FPGA_BIN_DIR) XRT_DEVICE_INDEX=$(XRT_DEVICE_INDEX) XRT_XCLBIN_PATH=$(FPGA_BIN_DIR)/vortex_afu.xclbin LD_LIBRARY_PATH=$(XILINX_XRT)/lib:$(POCL_PATH)/lib:$(ROOT_DIR)/runtime:$(LLVM_VORTEX)/lib:$(LD_LIBRARY_PATH) $(POCL_CC_FLAGS) VORTEX_DRIVER=xrt ./$(PROJECT) $(OPTS)
else
	XCL_EMULATION_MODE=$(TARGET) XRT_INI_PATH=$(XRT_SYN_DIR)/xrt.ini EMCONFIG_PATH=$(FPGA_BIN_DIR) XRT_DEVICE_INDEX=$(XRT_DEVICE_INDEX) XRT_XCLBIN_PATH=$(FPGA_BIN_DIR)/vortex_afu.xclbin LD_LIBRARY_PATH=$(XILINX_XRT)/lib:$(POCL_PATH)/lib:$(ROOT_DIR)/runtime:$(LLVM_VORTEX)/lib:$(LD_LIBRARY_PATH) $(POCL_CC_FLAGS) VORTEX_DRIVER=xrt ./$(PROJECT) $(OPTS)
endif

.depend: $(SRCS)
	$(CXX) $(CXXFLAGS) -MM $^ > .depend;

clean-kernel:
	rm -rf *.dump *.ll

clean-host:
	rm -rf $(PROJECT) $(PROJECT).host *.o *.log .depend

clean: clean-kernel clean-host

# 只要不是clean目标，就会包含.depend文件
ifneq ($(MAKECMDGOALS),clean)
    -include .depend
endif
