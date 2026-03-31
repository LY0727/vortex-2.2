<!--
 * @Author: lao liuao0727@foxmail.com
 * @Date: 2026-03-31 16:57:00
 * @LastEditors: lao liuao0727@foxmail.com
 * @LastEditTime: 2026-03-31 19:33:00
 * @FilePath: /vortex-2.2/lao_paper/readme.md
 * @Description: 这是默认设置,请设置`customMade`, 打开koroFileHeader查看配置 进行设置: https://github.com/OBKoro1/koro1FileHeader/wiki/%E9%85%8D%E7%BD%AE
-->

# 说明

## lao_paper/ 目录

1. 本目录为涉及编写论文时引入的，论文编写的大概关注点和约束如下：

   ---

   具体目标：

   1.以core组件的设计为主体内容，组织撰写一篇硕士学位论文。

   2.需要绘制的各类型图表，以.drawio文件保存在“笔记/”目录下。

   补充说明：


   1. 着眼于vortex项目中的CORE硬件，注意就是单独core硬件，不涉及向上的vortex组件，在论文中不要提及vortex项目，仅仅以一个单独的“基于RISCV自定义指令扩展的GPGPU中sm-core的设计”的视角来展开论文。
   2. 关键配置一：仅仅考虑RV32IM指令，不启用F扩展。
   3. 关键配置二：不启用LMEM，不启用cache。
   4. 关键配置三：NUM_THREAD = SIMD_WIDTH，也就是PID信号无效，不需要分包执行。
   5. 关键配置四： NUM_WARPS 设置为16，ISSUE_WIDTH设置为2，主要是绘制微架构图时要体现参数化可多发射的设计 。
   6. 关键配置五：仅仅关注设计主体部分，设计DEBUG宏、SIMULATION宏、PERF_ENABLE宏的内容都忽略。

   为了确保我们的步调一致，我将这些约束转化为设计的具体表现：

   1. **匿名化与独立性** ：全程不提“Vortex”。核心视角是**“面向GPGPU的一款基于RISC-V自定义扩展的SM-Core硬件设计”**。
   2. **指令集极简（RV32IM）** ：只有 32 位整型基础（I）加整数乘除法（M）。无浮点单元（FPU）及相关发射、寄存器逻辑。
   3. **无缓存与局存（Cache/LMEM Disable）** ：内存层级极大简化，LSU 直接对接系统总线/主存接口，不用讨论 Cache 一致性、缓存行替换、LMEM 地址映射等复杂操作。
   4. **无分包执行（`NUM_THREAD = SIMD_WIDTH`）** ：Warp 内的所有 Thread 完全并行执行，不涉及对单一指令由于硬件计算通道不足而造成的软件分包（Packet化）时序逻辑，硬件可以直接满配展开。
   5. **参数化与多发射（Warp=16, Issue=）**：这是微架构图的核心特征。画图和写正文时，所有涉及资源分配的地方都要体现出 16个 Warp 的状态维护，以及支持双发射（如 Schedule 有两条发射通路，Operands 处理交叉开关时对 2 个指令的并行响应等）。
   6. **剔除冗余逻辑** ：忽略所有 Debug、Perf 计数器（如各种 MPM CSRs）、Simulation 代码，只看纯粹的电路逻辑。

   ---
2. syn/ 综合目录： 源码是早期版本，涉及到一些sv语法问题，通过几个py脚本进行了部分源码修改。

## ../tests/riscv/ 目录

1. vortex_build 目录，编译32im指令集的coremarks。  （当然后续想要复现的话，得注意下载准备好coremarks项目）
2. rv32im_coremarks 目录， 编译32im指令集的coremarks，论文5.1中使用这个.bin进行的仿真测试。
3. coremarks_32imaf 目录， 32imaf的coremarks。
