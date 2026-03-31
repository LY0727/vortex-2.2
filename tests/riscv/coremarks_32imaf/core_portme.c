#include "coremark.h"
#include "core_portme.h"

#define CLOCKS_PER_SEC 50000000 // 根据你的 Vortex FPGA/仿真频率修改(如 50MHz)

ee_u32 default_num_contexts = 1;

static CORE_TICKS start_time_val, stop_time_val;

// 获取当前周期数 (利用 RV32 的 mcycle 或 cycle 寄存器)
static CORE_TICKS get_cycle_count(void) {
    uint32_t cycles;
    // 使用 vortex 提供的内联汇编获取全局周期数
    __asm__ volatile ("csrr %0, cycle" : "=r" (cycles));
    return cycles;
}

void start_time(void) {
    start_time_val = get_cycle_count();
}

void stop_time(void) {
    stop_time_val = get_cycle_count();
}

CORE_TICKS get_time(void) {
    CORE_TICKS elapsed = stop_time_val - start_time_val;
    return elapsed;
}

// 对应 time_in_secs
ee_u32 time_in_secs(CORE_TICKS ticks) {
    ee_u32 retval = ticks / CLOCKS_PER_SEC;
    return retval;
}
// // 对应 time_in_secs
// secs_ret time_in_secs(CORE_TICKS ticks) {
//     secs_ret retval = ((secs_ret)ticks) / (secs_ret)CLOCKS_PER_SEC;
//     return retval;
// }

ee_u32 time_in_msecs(CORE_TICKS ticks) {
    ee_u32 retval = ticks / (CLOCKS_PER_SEC / 1000);
    return retval;
}

// 初始化，vortex_start 已经把串口和栈准备好了，这里可留空
void portable_init(core_portable *p, int *argc, char *argv[]) {}
void portable_fini(core_portable *p) {}

ee_u8 *align_mem(ee_u8 *b1) {
    ee_ptr_int *base = (ee_ptr_int *)b1;
    return (ee_u8 *)base;
}