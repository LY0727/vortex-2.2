# 定义工具链前缀
RISCV_PREFIX ?= /mnt/ssd2/lao/vortex-tools/riscv32-gnu-toolchain/bin/riscv32-unknown-elf-

CC = $(RISCV_PREFIX)gcc
OBJCOPY = $(RISCV_PREFIX)objcopy

# Vortex Include 与链接器脚本
VORTEX_INC = -I../../../kernel/include -I../../../build/hw
LDFLAGS = -nostartfiles -Wl,-Bstatic,--gc-sections,-T,../../../kernel/scripts/link32.ld,--defsym=STARTUP_ADDR=0x80000000 -L../../../build/kernel -lvortex

# RV32IM 核心编译参数
# CFLAGS = -O3 -funroll-all-loops -march=rv32im_zicsr -mabi=ilp32 -mcmodel=medany -fno-exceptions -ffreestanding 
# RV32IMAF 核心编译参数
CFLAGS = -O3 -funroll-all-loops -march=rv32imaf_zicsr -mabi=ilp32f -mcmodel=medany -fno-exceptions -ffreestanding 
CFLAGS += -DITERATIONS=100 # 可以调整该数值使得跑分时间>10s即可
CFLAGS += $(VORTEX_INC)

SRCS = core_list_join.c core_main.c core_matrix.c core_state.c core_util.c core_portme.c

all: coremark.bin

# 1. 编译成 ELF
coremark.elf: $(SRCS)
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

# 2. 从 ELF 提取 BIN 文件 (也可使用 vortex 提供的 vxbin.py)
coremark.bin: coremark.elf
	$(OBJCOPY) -O binary $< $@

clean:
	rm -f *.elf *.bin