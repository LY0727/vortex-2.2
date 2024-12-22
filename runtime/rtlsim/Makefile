include ../common.mk
# CURDIR 是指当前目录
DESTDIR ?= $(CURDIR)/..

SRC_DIR := $(VORTEX_HOME)/runtime/rtlsim

CXXFLAGS += -std=c++11 -Wall -Wextra -pedantic -Wfatal-errors
# 头文件路径，可以看到 sim/ hw/ runtime/  三个大子项的头文件都包含了；
# 同时也可以确认， RTL-SIM deriver 以及 仿真运行时库 与 kernel/   还是完全独立的 。
CXXFLAGS += -I$(INC_DIR) -I$(COMMON_DIR) -I$(ROOT_DIR)/hw -I$(SIM_DIR)/rtlsim -I$(COMMON_DIR) -I$(SIM_DIR)/common
CXXFLAGS += -DXLEN_$(XLEN)

# Position independent code   位置无关，适用于共享库
CXXFLAGS += -fPIC

# Add external configuration   
# 顶层对硬件的配置，ci/blackbox.sh 中做了命令行参数的解析配置；
# 也可以 自行在单独运行make时，通过 make CONFIGS="-DXXX"  来配置
CXXFLAGS += $(CONFIGS)

# Linker flags   生成共享库，启用多线程；  
# 指定库文件搜索路径，链接到 librtlsim.so；  这个库应该是 SIM/rtlsim/Makefile 生成的,
LDFLAGS += -shared -pthread
LDFLAGS += -L$(DESTDIR) -lrtlsim

SRCS := $(SRC_DIR)/vortex.cpp

# DEBUG  为1时，启用调试模式，否则启用优化模式
# 这个宏，prj中原本是设计通过  ci/blackbox.sh  一键运行仿真测试；这时候通过命令行参数 配置硬件资源、DEBUG宏
# 自己单独运行时，可以通过 make DEBUG=1 runtime/rtlsim  来启用调试模式

# DEBUG=1 make runtime/rtlsim
# Debugging
ifdef DEBUG
	CXXFLAGS += -g -O0
else
	CXXFLAGS += -O2 -DNDEBUG
endif

# 生成的共享库文件名
PROJECT := libvortex-rtlsim.so


all: $(DESTDIR)/$(PROJECT)

driver: $(DESTDIR)/librtlsim.so

# 生成 librtlsim.so；  依赖于 SIM/rtlsim/Makefile，这个库是 单纯rtl-sim 的驱动库；
# verilator 仿真逻辑。
$(DESTDIR)/librtlsim.so:
	DESTDIR=$(DESTDIR) $(MAKE) -C $(ROOT_DIR)/sim/rtlsim $(DESTDIR)/librtlsim.so

# kernel/  ->  libvortex.a
# sim/rtlsim/ -> librtlsim.so
# runtime/rtlsim/ -> libvortex-rtlsim.so   仿真运行时库 
# 理解这三个库各自的作用，对应的软硬件层级，以及他们之间的关系，是非常重要的； 
$(DESTDIR)/$(PROJECT): $(SRCS) $(DESTDIR)/librtlsim.so
	$(CXX) $(CXXFLAGS) $(SRCS) $(LDFLAGS) -o $@

clean-driver:
	DESTDIR=$(DESTDIR) $(MAKE) -C $(ROOT_DIR)/sim/rtlsim clean-lib

clean-runtime:
	rm -f $(DESTDIR)/$(PROJECT)

clean: clean-driver clean-runtime

.PHONY: all driver clean-driver clean-runtime clean