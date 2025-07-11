include ../common.mk

DESTDIR ?= $(CURDIR)

SRC_DIR = $(VORTEX_HOME)/sim/simx

# 
CXXFLAGS += -std=c++17 -Wall -Wextra -Wfatal-errors
CXXFLAGS += -fPIC -Wno-maybe-uninitialized

# 头文件搜索路径
CXXFLAGS += -I$(SRC_DIR) -I$(COMMON_DIR) -I$(ROOT_DIR)/hw
CXXFLAGS += -I$(THIRD_PARTY_DIR)/softfloat/source/include
CXXFLAGS += -I$(THIRD_PARTY_DIR)/ramulator/ext/spdlog/include
CXXFLAGS += -I$(THIRD_PARTY_DIR)/ramulator/ext/yaml-cpp/include
CXXFLAGS += -I$(THIRD_PARTY_DIR)/ramulator/src

CXXFLAGS += -DXLEN_$(XLEN)
CXXFLAGS += $(CONFIGS)

# 链接选项 两个第三方依赖库
LDFLAGS += $(THIRD_PARTY_DIR)/softfloat/build/Linux-x86_64-GCC/softfloat.a
LDFLAGS += -Wl,-rpath,$(THIRD_PARTY_DIR)/ramulator -L$(THIRD_PARTY_DIR)/ramulator -lramulator

# 源文件列表
# 一些公共的工具类、内存类、浮点数类、dram模拟器类
# 一些模拟器的类、核心类、执行类、功能单元类、缓存模拟器类、内存模拟器类、本地内存类、内存合并器类、dcrs类、类型类
SRCS = $(COMMON_DIR)/util.cpp $(COMMON_DIR)/mem.cpp $(COMMON_DIR)/rvfloats.cpp $(COMMON_DIR)/dram_sim.cpp
SRCS += $(SRC_DIR)/processor.cpp $(SRC_DIR)/cluster.cpp $(SRC_DIR)/socket.cpp $(SRC_DIR)/core.cpp $(SRC_DIR)/emulator.cpp $(SRC_DIR)/decode.cpp $(SRC_DIR)/execute.cpp $(SRC_DIR)/func_unit.cpp $(SRC_DIR)/cache_sim.cpp $(SRC_DIR)/mem_sim.cpp $(SRC_DIR)/local_mem.cpp $(SRC_DIR)/mem_coalescer.cpp $(SRC_DIR)/dcrs.cpp $(SRC_DIR)/types.cpp

# Debugging
ifdef DEBUG
	CXXFLAGS += -g -O0 -DDEBUG_LEVEL=$(DEBUG)
	#CXXFLAGS += -g -O0 -DDEBUG_LEVEL=$(DEBUG) -fsanitize=address -fno-omit-frame-pointer
else
	CXXFLAGS += -O2 -DNDEBUG
endif

# Enable perf counters
ifdef PERF
	VL_FLAGS += -DPERF_ENABLE
	CXXFLAGS += -DPERF_ENABLE
endif

PROJECT := simx

all: $(DESTDIR)/$(PROJECT)

$(DESTDIR)/$(PROJECT): $(SRCS) $(SRC_DIR)/main.cpp
	$(CXX) $(CXXFLAGS) -DSTARTUP_ADDR=0x80000000 $^ $(LDFLAGS) -o $@

$(DESTDIR)/lib$(PROJECT).so: $(SRCS)
	$(CXX) $(CXXFLAGS) $^ -shared $(LDFLAGS) -o $@

.depend: $(SRCS)
	$(CXX) $(CXXFLAGS) -MM $^ > .depend;

clean-lib:
	rm -f $(DESTDIR)/lib$(PROJECT).so

clean-exe:
	rm -f $(DESTDIR)/$(PROJECT)

clean: clean-lib clean-exe
