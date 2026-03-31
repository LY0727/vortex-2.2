/*
 * @Author: lao liuao0727@foxmail.com
 * @Date: 2026-03-30 22:41:12
 * @LastEditors: lao liuao0727@foxmail.com
 * @LastEditTime: 2026-03-31 16:52:57
 * @FilePath: /vortex-2.2/笔记/paper_code_2-2.c
 * @Description: 这是默认设置,请设置`customMade`, 打开koroFileHeader查看配置 进行设置: https://github.com/OBKoro1/koro1FileHeader/wiki/%E9%85%8D%E7%BD%AE
 */
// 1、标准C语言编程范式：
if (cond) {
    // THEN 路径计算
} else {
    // ELSE 路径计算
}

// 2、SIMT硬件下编程范式：
int sp = split(cond);     // 评估分支条件，返回栈指针
if (cond) {
    // THEN 路径指令
} else {
    // ELSE 路径指令
}
join(sp);                 // 利用栈指针sp进行路径重聚



// 1、标准C语言编程范式：
while (cond) {
    // 循环体计算
}

// 2、基于split-join的编程范式：
int sp;
l_loop:
    sp = split(cond);
    if (cond) {
        // {循环体计算,内部可能再次改变 cond 的值}
        goto l_loop;
    }
    join(sp);

// 3、基于pred-tmc的编程范式：
int orig_tmask = active_threads(); // 1.保存进入循环前的活跃线程掩码状态
l_loop:
    pred(cond， orig_tmask);       // 2.结合条件更新掩码
    if (active_threads() != 0) {   // 3.还有线程满足条件，则全Warp继续循环
        // {循环体计算}
        goto l_loop;               // 4.跳转回循环开头重新计算预测
    }
    tmc(orig_tmask);               // 5.循环结束，恢复初始线程掩码，确保收敛