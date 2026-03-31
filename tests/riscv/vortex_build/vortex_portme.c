#include "coremark.h"
#include <vx_print.h>
#include <vx_intrinsics.h>

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

static ee_u32 start_time_val, stop_time_val;

// Use Vortex cycle counter
void start_time(void) {
    ee_u32 cycle;
    __asm__ volatile ("csrr %0, mcycle" : "=r"(cycle));
    start_time_val = cycle;
}

void stop_time(void) {
    ee_u32 cycle;
    __asm__ volatile ("csrr %0, mcycle" : "=r"(cycle));
    stop_time_val = cycle;
}

CORE_TICKS get_time(void) {
    return (CORE_TICKS)(stop_time_val - start_time_val);
}

// Dummy for missing barebones implementations
CORE_TICKS barebones_clock() {
    ee_u32 cycle;
    __asm__ volatile ("csrr %0, mcycle" : "=r"(cycle));
    return cycle;
}

#define EE_TICKS_PER_SEC 250000000

secs_ret time_in_secs(CORE_TICKS ticks) {
    secs_ret retval = ((secs_ret)ticks) / (secs_ret)EE_TICKS_PER_SEC;
    return retval;
}

ee_u32 default_num_contexts = 1;

void portable_init(core_portable *p, int *argc, char *argv[]) {
    p->portable_id = 1;
}
void portable_fini(core_portable *p) {
    p->portable_id = 0;
}
void uart_send_char(char c) {
    vx_putchar(c);
}
