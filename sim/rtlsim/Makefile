include ../common.mk

DESTDIR ?= $(CURDIR)
# rtlsim 主要源文件 就两个： processor.cpp  main.cpp
SRC_DIR = $(VORTEX_HOME)/sim/rtlsim

# 重要编译选项： 
# C++17库；启动所有警告；
CXXFLAGS += -std=c++17 -Wall -Wextra -Wfatal-errors -Wno-array-bounds
# 生成位置无关代码，适用于共享库
# 禁用对  可能未初始化变量   的编译警告 （某些情况下，变量实际上是初始化了的，编译器误认为未初始化）
CXXFLAGS += -fPIC -Wno-maybe-uninitialized

# 头文件路径
# hw/ 里面是 VX_config.h VX_types.h  硬件配置的标签符号
# sim/common/ 里面是一些工具函数; 这些是每个仿真器 都会用到的。 
# 可以想到还是verilator逻辑中为实现  对照模型  所需的工具函数
CXXFLAGS += -I$(ROOT_DIR)/hw -I$(COMMON_DIR)
# 软件浮点运算库、 ramulator内存模拟器、yaml-cpp、spdlog;  这些都是仿真器需要的第三方库
CXXFLAGS += -I$(THIRD_PARTY_DIR)/softfloat/source/include
CXXFLAGS += -I$(THIRD_PARTY_DIR)/ramulator/ext/spdlog/include
CXXFLAGS += -I$(THIRD_PARTY_DIR)/ramulator/ext/yaml-cpp/include
CXXFLAGS += -I$(THIRD_PARTY_DIR)/ramulator/src
# 定义宏
CXXFLAGS += -DXLEN_$(XLEN)

# 链接器选项， 依赖的第三方库， 软浮点是静态库， ramulator是动态库
LDFLAGS += $(THIRD_PARTY_DIR)/softfloat/build/Linux-x86_64-GCC/softfloat.a
LDFLAGS += -Wl,-rpath,$(THIRD_PARTY_DIR)/ramulator  -L$(THIRD_PARTY_DIR)/ramulator -lramulator

# control RTL debug tracing states
DBG_TRACE_FLAGS += -DDBG_TRACE_PIPELINE
DBG_TRACE_FLAGS += -DDBG_TRACE_MEM
DBG_TRACE_FLAGS += -DDBG_TRACE_CACHE
DBG_TRACE_FLAGS += -DDBG_TRACE_AFU
DBG_TRACE_FLAGS += -DDBG_TRACE_SCOPE
DBG_TRACE_FLAGS += -DDBG_TRACE_GBAR

# 定义调试标签， 以及启用VCD波形输出； 可以看到这里也是需要有 DEBUG 宏的	
DBG_FLAGS += -DDEBUG_LEVEL=$(DEBUG) -DVCD_OUTPUT $(DBG_TRACE_FLAGS)

# RTL包列表
RTL_PKGS = $(RTL_DIR)/VX_gpu_pkg.sv $(RTL_DIR)/fpu/VX_fpu_pkg.sv $(RTL_DIR)/core/VX_trace_pkg.sv

# RTL_FPU;  这里仅仅包含vortex核中的FPU部分
FPU_INCLUDE = -I$(RTL_DIR)/fpu
# 如果配置中包含FPU_FPNEW；那么就需要包含fpnew库； 这个库是pulp开源的一硬件浮点运算库
# 这里用的是 += ；增加可不是覆盖；也就是说包含了两个FPU的rtl，虽然vortex本身的FPU部分非常简单，
# 全局搜索  FPU_FPNEW ；  可以看到这个宏 是在 调用ci/blackbox.sh 是命令行参数传入的； 
# 在RTL中会适用这个宏来选择不同的FPU库；
ifneq (,$(findstring FPU_FPNEW,$(CONFIGS)))
	RTL_PKGS += $(THIRD_PARTY_DIR)/fpnew/src/fpnew_pkg.sv $(THIRD_PARTY_DIR)/fpnew/src/common_cells/src/cf_math_pkg $(THIRD_PARTY_DIR)/fpnew/src/fpu_div_sqrt_mvp/hdl/defs_div_sqrt_mvp.sv
	FPU_INCLUDE += -I$(THIRD_PARTY_DIR)/fpnew/src/common_cells/include -I$(THIRD_PARTY_DIR)/fpnew/src/common_cells/src -I$(THIRD_PARTY_DIR)/fpnew/src/fpu_div_sqrt_mvp/hdl -I$(THIRD_PARTY_DIR)/fpnew/src
endif

# vortex RTL包含路径
RTL_INCLUDE = -I$(RTL_DIR) -I$(DPI_DIR) -I$(RTL_DIR)/libs -I$(RTL_DIR)/interfaces -I$(RTL_DIR)/core -I$(RTL_DIR)/mem -I$(RTL_DIR)/cache $(FPU_INCLUDE)


# vortex仿真器源文件
SRCS = $(COMMON_DIR)/util.cpp $(COMMON_DIR)/mem.cpp $(COMMON_DIR)/rvfloats.cpp $(COMMON_DIR)/dram_sim.cpp
SRCS += $(DPI_DIR)/util_dpi.cpp $(DPI_DIR)/float_dpi.cpp
SRCS += $(SRC_DIR)/processor.cpp

# 顶层模块 
# 如果配置中包含AXI_BUS；那么顶层模块就是Vortex_axi； 否则就是Vortex；  论文中介绍了这两种情况。
# 此前我一直仿真的都是vortex为顶层，没有AXI总线；  这里可以看到，AXI总线的支持是通过命令行参数传入的；
# 通过全局搜索，可以看到AXI_BUS是在 ci/blackbox.sh 中传入的； 在processor.cpp中，也有对AXI_BUS的条件编译；
ifdef AXI_BUS
	TOP = Vortex_axi
	CXXFLAGS += -DAXI_BUS
else
	TOP = Vortex
endif

# verilator的编译选项；
VL_FLAGS = --exe
VL_FLAGS += --language 1800-2009 --assert -Wall -Wpedantic
VL_FLAGS += -Wno-DECLFILENAME -Wno-REDEFMACRO -Wno-GENUNNAMED 
VL_FLAGS += --x-initial unique --x-assign unique
VL_FLAGS += $(SRC_DIR)/verilator.vlt
VL_FLAGS += -DSIMULATION -DSV_DPI
VL_FLAGS += -DXLEN_$(XLEN)
VL_FLAGS += $(CONFIGS)
VL_FLAGS += $(RTL_INCLUDE)
VL_FLAGS += $(RTL_PKGS)
VL_FLAGS += --cc $(TOP) --top-module $(TOP)

# 硬件资源配置参数
CXXFLAGS += $(CONFIGS)

# Enable Verilator multithreaded simulation
THREADS ?= $(shell python -c 'import multiprocessing as mp; print(mp.cpu_count())')
VL_FLAGS += -j $(THREADS)
#VL_FLAGS += --threads $(THREADS)

# 跟踪式调试风格
# Debugging
ifdef DEBUG
	VL_FLAGS += --trace --trace-structs $(DBG_FLAGS)
	CXXFLAGS += -g -O0 $(DBG_FLAGS)
else
	VL_FLAGS += -DNDEBUG
	CXXFLAGS += -O2 -DNDEBUG
endif

# Enable perf counters   
ifdef PERF
	VL_FLAGS += -DPERF_ENABLE
	CXXFLAGS += -DPERF_ENABLE
endif


PROJECT := rtlsim

all: $(DESTDIR)/$(PROJECT)

# 编译这个可执行程序的时候，编译了RTL转CPP；编译了sim下的工具函数CPP；链接了第三方依赖库；同时也编译了main.cpp; 是一个完整的可执行文件。
# 注意到同时指定了一个宏： STARTUP_ADDR=0x80000000； 这个宏在processor.cpp中有用到；
# 可执行文件 和 .so 只相差一个 main.cpp；   
$(DESTDIR)/$(PROJECT): $(SRCS) $(SRC_DIR)/main.cpp
	verilator --build $(VL_FLAGS) $^ -CFLAGS '$(CXXFLAGS) -DSTARTUP_ADDR=0x80000000' -LDFLAGS '$(LDFLAGS)' --Mdir $@.obj_dir -o $@

# 生成 librtlsim.so；可以看到编译这个共享库时，编译了RTL转CPP；编译了sim下的工具函数CPP；链接了第三方依赖库；但没有使用这个 main.cpp ； 
# 也就是说这个库是一个纯粹的驱动库；所以在testbench中，需要自己写一个main函数，来调用这个库？
# prj中可以看到 后续 runtime/rtlsim/Makefile 链接这个.so库，生成一个仿真运行时共享库：  libvortex-rtlsim.so； 到这一步依然是没有main函数的。
# 再下一步应该看到tests/opencl 和 tests/regression 两个目录下的测试用例，在测试用例中才提供main.cpp, 并链接上述共享库。
$(DESTDIR)/lib$(PROJECT).so: $(SRCS)
	verilator --build $(VL_FLAGS) $^ -CFLAGS '$(CXXFLAGS)' -LDFLAGS '-shared $(LDFLAGS)' --Mdir $@.obj_dir -o $@

clean-lib:
	rm -rf $(DESTDIR)/lib$(PROJECT).so.obj_dir
	rm -f $(DESTDIR)/lib$(PROJECT).so

clean-exe:
	rm -rf $(DESTDIR)/$(PROJECT).obj_dir
	rm -f $(DESTDIR)/$(PROJECT)

clean: clean-lib clean-exe