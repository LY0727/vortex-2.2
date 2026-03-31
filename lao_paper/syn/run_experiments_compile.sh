#!/bin/bash
###
 # @Author: lao liuao0727@foxmail.com
 # @Date: 2026-03-27 17:03:03
 # @LastEditors: lao liuao0727@foxmail.com
 # @LastEditTime: 2026-03-27 21:18:08
 # @FilePath: /vortex-2.2/syn/run_experiments.sh
 # @Description: 这是默认设置,请设置`customMade`, 打开koroFileHeader查看配置 进行设置: https://github.com/OBKoro1/koro1FileHeader/wiki/%E9%85%8D%E7%BD%AE
### 
# ==============================================================================
# DC Synthesis Automation Script for SM-Core Experiments
# ==============================================================================

# 设置基础目录
BASE_DIR=$(pwd)
EXP_DIR="$BASE_DIR/dc_experiments_compile_only"

# 创建一个执行单次 DC 综合跑流的函数
run_dc() {
    local exp_name=$1
    local w=$2
    local t=$3
    local period_ns=$4
    local freq_mhz=$5

    local out_dir="${EXP_DIR}/${exp_name}/W${w}_T${t}_${freq_mhz}M"
    
    echo "=========================================================="
    echo "▶ 启动实验: $exp_name"
    echo "▶ 参数配置: NUM_WARPS=$w, NUM_THREADS=$t"
    echo "▶ 时序约束: $freq_mhz MHz (Period = $period_ns ns)"
    echo "▶ 报告目录: $out_dir"
    echo "=========================================================="

    # 创建实验专用的输出目录和临时的综合工作目录(保持工作区整洁)
    mkdir -p "$out_dir"
    
    local work_dir="$BASE_DIR/work_temp_${w}_${t}_${freq_mhz}"
    mkdir -p "$work_dir"
    cd "$work_dir" || exit

    # 使用 dc_shell 的 -x 参数动态传递 TCL 变量到综合脚本中去
    # 这会覆盖 core_top_syn.tcl 和 core_top.sdc 中的默认值
    # 注意将报告的生成直接指向我们建立的子目录。
    dc_shell -x "set NUM_WARPS $w; set NUM_THREADS $t; set CLK_PERIOD $period_ns; set OUT_DIR \"$out_dir\"" -f ../core_top_syn_compile_only.tcl | tee "$out_dir/dc_run.log"

    # 清理并返回基础目录
    cd "$BASE_DIR" || exit
    rm -rf "$work_dir"
    
    echo "✅ 实验 $exp_name (W=$w, T=$t, F=${freq_mhz}M) 完成！"
    echo ""
}

echo "开始自动化综合实验流程..."

# ---------------------------------------------------------
# 【实验 1】 并行通道扩展评估 (Scaling Threads)
# 变量固定: NUM_WARPS = 4, Freq = 400MHz (Period = 2.50ns)
# ---------------------------------------------------------
mkdir -p "$EXP_DIR/exp1_scaling_threads"
for t in 1 2 4 8 16 32; do
    run_dc "exp1_scaling_threads" 4 $t 2.5 400
done

# ---------------------------------------------------------
# 【实验 2】 多线程上下文扩展评估 (Scaling Warps)
# 变量固定: NUM_THREADS = 4, Freq = 400MHz (Period = 2.50ns)
# 注意: W=4,T=4 会有一组合适的冗余计算，可以通过比较报告时间复用
# ---------------------------------------------------------
mkdir -p "$EXP_DIR/exp2_scaling_warps"
for w in 1 2 4 8 16 32; do
    # 可选: 如果上一组实验已经跑过 W4_T4_400M，可以跳过以节省时间。但自动化脚本为了完整性，会覆盖运行。
    run_dc "exp2_scaling_warps" $w 4 2.5 400
done

# ---------------------------------------------------------
# 【实验 3】 极限主频压榨与关键路径分析 (Critical Path Analysis)
# 变量固定: NUM_WARPS = 4, NUM_THREADS = 4
# 时钟周期约束换算:
# 300MHz -> 3.33ns, 400MHz -> 2.50ns, 500MHz -> 2.00ns, 600MHz -> 1.67ns, 700MHz -> 1.43ns
# 800MHz -> 1.25ns, 900MHz -> 1.11ns, 1000MHz -> 1.00ns, 1100MHz -> 0.91ns, 1200MHz -> 0.83ns
# ---------------------------------------------------------
mkdir -p "$EXP_DIR/exp3_critical_path"
freqs=(300 350 400 450 500 550 600 650 700 750 800)
periods=(3.33 2.85 2.50 2.22 2.00 1.81 1.67 1.54 1.43 1.33 1.25)

for i in "${!freqs[@]}"; do
    f=${freqs[$i]}
    p=${periods[$i]}
    run_dc "exp3_critical_path" 4 4 $p $f
done

echo "🎉 所有自动化实验运行完毕！"
echo "📂 所有综合报告保存在: $EXP_DIR"
