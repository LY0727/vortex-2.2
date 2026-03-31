/*
 * @Author: lao liuao0727@foxmail.com
 * @Date: 2026-03-23 14:23:52
 * @LastEditors: lao liuao0727@foxmail.com
 * @LastEditTime: 2026-03-23 15:08:51
 * @FilePath: /lao/vortex-2.2/tests/riscv/coremarks/core_portme.h
 * @Description: 这是默认设置,请设置`customMade`, 打开koroFileHeader查看配置 进行设置: https://github.com/OBKoro1/koro1FileHeader/wiki/%E9%85%8D%E7%BD%AE
 */
#ifndef CORE_PORTME_H
#define CORE_PORTME_H

#include <stdint.h>
#include <stddef.h>
#include "vx_print.h" // 引用 vortex 的打印头文件
#include "vx_intrinsics.h"

// 1. 设置数据类型
// #define HAS_FLOAT 0 // 因为和是否编译f指令集相关放在下面定义
#define HAS_TIME_H 0
#define USE_CLOCK 0 // 不使用标准库的 clock()
#define HAS_STDIO 0
#define HAS_PRINTF 0
#define CORE_TICKS uint32_t

// 2. 将 printf 映射到 vortex 的 vx_printf
#define ee_printf vx_printf

// 3. 各种数据类型的配置
typedef int16_t ee_s16;
typedef uint16_t ee_u16;
typedef int32_t ee_s32;
typedef double ee_f32;
typedef uint8_t ee_u8;
typedef uint32_t ee_u32;
typedef int32_t ee_ptr_int;
typedef size_t ee_size_t;

// // rv32im_zicsr 和 rv32imaf_zicsr 都支持整数和控制状态寄存器指令，后者还支持单精度浮点指令
// #define COMPILER_FLAGS "-O3 -funroll-all-loops -march=rv32im_zicsr -mabi=ilp32"
// #define HAS_FLOAT 0
#define COMPILER_FLAGS "-O3 -funroll-all-loops -march=rv32imaf_zicsr -mabi=ilp32f"
#define HAS_FLOAT 0  // 如果你想让他测量包含浮点的开销，设置为1


#define COMPILER_VERSION "GCC"
#define MULTITHREAD 1

#ifndef MEM_LOCATION
#define MEM_LOCATION "SRAM"
#endif

typedef struct CORE_PORTABLE_S
{
    ee_u8 portable_id;
} core_portable;

// 初始化和定时器接口声明
void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);
CORE_TICKS get_time(void);
ee_u8 *align_mem(ee_u8 *b1);

extern ee_u32 default_num_contexts;

#endif