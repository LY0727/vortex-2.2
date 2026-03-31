/*
 * @Author: lao liuao0727@foxmail.com
 * @Date: 2026-03-30 22:41:05
 * @LastEditors: lao liuao0727@foxmail.com
 * @LastEditTime: 2026-03-30 22:41:32
 * @FilePath: /vortex-2.2/笔记/paper_code_2-1.h
 * @Description: 这是默认设置,请设置`customMade`, 打开koroFileHeader查看配置 进行设置: https://github.com/OBKoro1/koro1FileHeader/wiki/%E9%85%8D%E7%BD%AE
 */
/*
 * @Author: lao liuao0727@foxmail.com
 * @Date: 2026-03-30 22:41:05
 * @LastEditors: lao liuao0727@foxmail.com
 * @LastEditTime: 2026-03-30 22:41:10
 * @FilePath: /vortex-2.2/笔记/paper_code_2-1.h
 * @Description: 这是默认设置,请设置`customMade`, 打开koroFileHeader查看配置 进行设置: https://github.com/OBKoro1/koro1FileHeader/wiki/%E9%85%8D%E7%BD%AE
 */

// 伪码示例：利用内联汇编将参数寄存器正确地绑定到 R-type 字段中
// Spawn warps
typedef void (*vx_wspawn_pfn)();
inline void vx_wspawn(int num_warps, vx_wspawn_pfn func_ptr) {
    __asm__ volatile (".insn r %0, 1, 0, x0, %1, %2" :: 
                      "i"(RISCV_CUSTOM0), "r"(num_warps), "r"(func_ptr));
}
// Set thread mask
inline void vx_tmc(int thread_mask) {
    __asm__ volatile (".insn r %0, 0, 0, x0, %1, x0" ::
                      "i"(RISCV_CUSTOM0), "r"(thread_mask));
}
// Set thread predicate
inline void vx_pred(int condition, int thread_mask) {
    __asm__ volatile (".insn r %0, 5, 0, x0, %1, %2" :: 
                      "i"(RISCV_CUSTOM0), "r"(condition), "r"(thread_mask));
}
// Split on a predicate
inline int vx_split(int predicate) {
    int ret;
    __asm__ volatile (".insn r %1, 2, 0, %0, %2, x0" : "=r"(ret) : 
                      "i"(RISCV_CUSTOM0), "r"(predicate));
    return ret;
}
// Join
inline void vx_join(int stack_ptr) {
    __asm__ volatile (".insn r %0, 3, 0, x0, %1, x0" :: 
                      "i"(RISCV_CUSTOM0), "r"(stack_ptr));
}
// Warp Barrier
inline void vx_barrier(int barried_id, int num_warps) {
    __asm__ volatile (".insn r %0, 4, 0, x0, %1, %2" :: 
                      "i"(RISCV_CUSTOM0), "r"(barried_id), "r"(num_warps));
}