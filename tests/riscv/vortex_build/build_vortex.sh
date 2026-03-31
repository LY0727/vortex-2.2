#!/bin/bash
set -e

VORTEX_HOME=/mnt/ssd2/lao/vortex-2.2
TOOLDIR=/mnt/ssd2/lao/vortex-tools
COREMARK=/mnt/ssd2/lao/coremark
BUILD=/mnt/ssd2/lao/vortex-2.2/tests/riscv/vortex_build

GCC=${TOOLDIR}/riscv32-gnu-toolchain/bin/riscv32-unknown-elf-gcc
OBJCOPY=${TOOLDIR}/riscv32-gnu-toolchain/bin/riscv32-unknown-elf-objcopy
OBJDUMP=${TOOLDIR}/riscv32-gnu-toolchain/bin/riscv32-unknown-elf-objdump

LINK_SCRIPT=${VORTEX_HOME}/kernel/scripts/link32.ld
STARTUP_ADDR=0x80000000

# 1. 强制架构为 rv32im（附加 zicsr 是因为使用了 csrr 指令读取寄存器），强制 ABI 为整数调用标准 ilp32
CFLAGS="-march=rv32im_zicsr -mabi=ilp32 -O3 -mcmodel=medany"
CFLAGS+=" -fno-exceptions -nostartfiles -nostdlib"
CFLAGS+=" -fdata-sections -ffunction-sections"

# 注意：如果要在模拟器中很快跑到结束，可缩短 ITERATIONS，比如10
CFLAGS+=" -DITERATIONS=600 -DPERFORMANCE_RUN=1"
CFLAGS+=" -DHAS_FLOAT=0 -DPRINTF_DISABLE_SUPPORT_FLOAT=1"
CFLAGS+=" -DCOMPILER_FLAGS=\"-O3\""

CFLAGS+=" -I${BUILD} -I${COREMARK}"
CFLAGS+=" -I${VORTEX_HOME}/kernel/include -I${VORTEX_HOME}/hw -I${VORTEX_HOME}/build/hw"
CFLAGS+=" -Dee_printf=vx_printf"

LDFLAGS="-Wl,-Bstatic,--gc-sections"
LDFLAGS+=" -Wl,-T,${LINK_SCRIPT}"
LDFLAGS+=" -Wl,--defsym=STARTUP_ADDR=${STARTUP_ADDR}"

# 2. 忽略我们自己编译的 rv32im 与标准 libc.a 的 ilp32f 标签不匹配警告（因为我们只用到 libc 里的 memset/memcpy，这部分是普通的数学逻辑，对浮点无影响）
LDFLAGS+=" -Wl,--no-warn-mismatch"
LIBC=${TOOLDIR}/libc32

# 3. 这里不再去链接 prebuilt 的 libvortex.a 以及带浮点的 builtins，而是直接链接 libc
LIBS="-L${LIBC}/lib -lc -lm"

SRCS="${COREMARK}/core_list_join.c"
SRCS+=" ${COREMARK}/core_main.c"
SRCS+=" ${COREMARK}/core_matrix.c"
SRCS+=" ${COREMARK}/core_state.c"
SRCS+=" ${COREMARK}/core_util.c"
SRCS+=" ${BUILD}/vortex_portme.c"

# 4. 重点：直接源码级编译 Vortex 内核库（从源代码构建），确保不混入浮点相关指令
K_SRCS="${BUILD}/simple_start.S"
K_SRCS+=" ${VORTEX_HOME}/kernel/src/vx_syscalls.c"
K_SRCS+=" ${VORTEX_HOME}/kernel/src/vx_print.S"
K_SRCS+=" ${VORTEX_HOME}/kernel/src/tinyprintf.c"
K_SRCS+=" ${VORTEX_HOME}/kernel/src/vx_print.c"
K_SRCS+=" ${VORTEX_HOME}/kernel/src/vx_spawn.c"
K_SRCS+=" ${VORTEX_HOME}/kernel/src/vx_serial.S"
K_SRCS+=" ${VORTEX_HOME}/kernel/src/vx_perf.c"

echo "=== 编译 ==="
# 加入内置低级库 -lgcc 用于支持软件乘除非标准指令的一些长整数回退
${GCC} ${CFLAGS} ${SRCS} ${K_SRCS} ${LDFLAGS} ${LIBS} -o ${BUILD}/coremark_vortex.elf -lgcc

echo "=== 生成 bin ==="
${OBJCOPY} -O binary ${BUILD}/coremark_vortex.elf ${BUILD}/coremark_vortex.bin

echo "=== 反汇编 ==="
${OBJDUMP} -D ${BUILD}/coremark_vortex.elf > ${BUILD}/coremark_vortex.dump

echo "完成！"