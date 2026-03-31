#include <VX_types.h>
#include "/home/zhd/work/vortex-2.2/kernel/src/common.h"
#include <VX_config.h>

.section .init, "ax"
.global _start
.type   _start, @function
_start:
  .option push
  .option norelax
  la    gp, __global_pointer
  .option pop

  # Set up stack pointer (end of RAM)
  li    sp, 0xFFFF0000

  # clear BSS segment
  la    a0, _edata
  la    a2, _end
  sub   a2, a2, a0
  li    a1, 0
  call  memset

#ifdef HAVE_INITFINI_ARRAY
  call  __libc_init_array
#endif

  call  main

  # call exit
  tail exit
.size _start, .-_start

.section .text
.type _Exit, @function
.global _Exit
_Exit:
  li t0, IO_MPM_EXITCODE
  sw a0, 0(t0)
  fence
  .insn r RISCV_CUSTOM0, 0, 0, x0, x0, x0  # tmc x0 
1:
  j 1b
