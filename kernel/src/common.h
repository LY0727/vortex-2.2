/*
 * @Author: lao liuao0727@foxmail.com
 * @Date: 2025-01-04 16:27:12
 * @LastEditors: lao liuao0727@foxmail.com
 * @LastEditTime: 2026-01-15 12:15:29
 * @FilePath: /vortex-2.2/kernel/src/common.h
 * @Description: 这是默认设置,请设置`customMade`, 打开koroFileHeader查看配置 进行设置: https://github.com/OBKoro1/koro1FileHeader/wiki/%E9%85%8D%E7%BD%AE
 */
// Copyright © 2019-2023
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#define RISCV_CUSTOM0 0x0B
// _Exit 函数，把返回值写到这里。  最原始的 host-device 接口,实现结果回传。
#define IO_MPM_EXITCODE (IO_MPM_ADDR + 8)

#ifdef XLEN_64
  #define LOAD_IMMEDIATE64(rd, imm) \
    li   t0, (imm >> 32); \
    slli t0, t0, 32; \
    li   rd, (imm & 0xffffffff); \
    or   rd, rd, t0
#else
  #define LOAD_IMMEDIATE64(rd, imm) \
    li   rd, imm
#endif
