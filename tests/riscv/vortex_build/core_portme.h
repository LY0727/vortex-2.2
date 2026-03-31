/*
 * @Author: lao liuao0727@foxmail.com
 * @Date: 2026-03-23 15:12:53
 * @LastEditors: lao liuao0727@foxmail.com
 * @LastEditTime: 2026-03-23 15:19:12
 * @FilePath: /lao/vortex-2.2/tests/riscv/vortex_build/core_portme.h
 * @Description: 这是默认设置,请设置`customMade`, 打开koroFileHeader查看配置 进行设置: https://github.com/OBKoro1/koro1FileHeader/wiki/%E9%85%8D%E7%BD%AE
 */
#ifndef VORTEX_PORTME_H
#define VORTEX_PORTME_H

#include <stdint.h>
#include <stddef.h>

#define HAS_FLOAT 0
#define HAS_TIME_H 1
#define USE_CLOCK 1
#define HAS_STDIO 1
#define HAS_PRINTF 1
#define CORE_TICKS uint32_t
#define ee_u8 uint8_t
#define ee_u16 uint16_t
#define ee_u32 uint32_t
#define ee_s16 int16_t
#define ee_s32 int32_t
#define ee_ptr_int uintptr_t
#define ee_size_t size_t
#define COMPILER_FLAGS "rv32imaf-O3"

#include <vx_print.h>
#define ee_printf vx_printf

#define align_mem(x) (void *)(4 + (((ee_ptr_int)(x) - 1) & ~3))

#define MULTITHREAD 1
#define COMPILER_VERSION "GCC"
#define MEM_LOCATION "SRAM"

typedef struct CORE_PORTABLE_S
{
    ee_u8 portable_id;
} core_portable;

void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);
CORE_TICKS get_time(void);

extern ee_u32 default_num_contexts;

#endif
