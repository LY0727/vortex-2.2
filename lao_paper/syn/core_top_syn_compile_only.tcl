######################################################################
# 1. User Setup Variables (Modify these paths based on your CentOS VM)
######################################################################
# Define standard cell library paths
set search_path    "$search_path ../rtl_vx ../rtl_vx/interfaces ../rtl_vx/libs ../rtl_vx/fpu ../rtl_vx/core ../rtl_vx/mem ../rtl_vx/cache"

# 当没有实际库文件时，可以使用以下占位符路径，确保脚本能够运行，但请替换为实际的 .db 文件路径以获得正确的综合结果。
# set target_library "lsi_10k.db"
# set link_library   "* $target_library standard.sldb dw_foundation.sldb"

# 实际库文件路径
set link_library { * /home/lao/works/backend-example/test/lib/scc40nll_hdc50_lvt_ff_v1p21_0c_basic.db }
set target_library { /home/lao/works/backend-example/test/lib/scc40nll_hdc50_lvt_ff_v1p21_0c_basic.db }

# Allow variables to be passed externally via dc_shell -x
if {![info exists NUM_WARPS]} { set NUM_WARPS 4 }
if {![info exists NUM_THREADS]} { set NUM_THREADS 4 }
if {![info exists CLK_PERIOD]} { set CLK_PERIOD 2.5 }
if {![info exists OUT_DIR]} { set OUT_DIR "../reports" }

# Define top module
set TOP_MODULE "VX_core_top"

######################################################################
# 2. Read RTL Design
######################################################################
# Create a WORK directory for intermediate files
define_design_lib WORK -path ./WORK_LIB

# We use the generated filelist to read all the dependencies
set filelist [open "../filelist_core.f" r]
set sv_files ""
while {[gets $filelist line] >= 0} {
    set line [string trim $line]
    if {$line eq ""} continue
    if {[string match "+incdir*" $line]} {
        # Extract incdir path
        set inc_path [string range $line 8 end]
        lappend search_path $inc_path
    } else {
        lappend sv_files $line
    }
}
close $filelist

analyze -format sverilog -define "NUM_WARPS=${NUM_WARPS} NUM_THREADS=${NUM_THREADS}" $sv_files
elaborate $TOP_MODULE

current_design $TOP_MODULE
link
uniquify

######################################################################
# 3. Timing and Design Constraints
######################################################################
# Optionally read from an SDC file
source -echo -verbose ../core_top.sdc

######################################################################
# 4. Compile Design
######################################################################
# --- 在编译前明确开启关键重整权限 ---
# 1. 允许 DC 对部分层级进行拍扁 (这是 retiming 跨越模块找最优解的前提)
# 2. 也是最关键的：允许 DC 改变流水线寄存器的位置 (即 Retiming / 寄存器重新同步)
# 3. 开启基于数据通路的算术优化 (允许它对 *、+ 重新用高级树状结构组合)
# 最后执行普通编译，并加入 -inc 等参数
# set_flatten true -effort high
# set_optimize_registers true
# set_dp_smart_compile true
# compile -map_effort high -incremental_mapping

compile

######################################################################
# 5. Generate Reports
######################################################################
file mkdir $OUT_DIR
report_timing > ${OUT_DIR}/${TOP_MODULE}_timing.rpt
report_area   > ${OUT_DIR}/${TOP_MODULE}_area.rpt
report_power  > ${OUT_DIR}/${TOP_MODULE}_power.rpt
report_qor    > ${OUT_DIR}/${TOP_MODULE}_qor.rpt

######################################################################
# 6. Save Output Files
######################################################################
# Output mapped files to OUT_DIR
change_names -rules verilog -hierarchy
write -format verilog -hierarchy -output ${OUT_DIR}/${TOP_MODULE}_mapped.v
write -format ddc -hierarchy -output ${OUT_DIR}/${TOP_MODULE}_mapped.ddc
write_sdc ${OUT_DIR}/${TOP_MODULE}_mapped.sdc
write_sdf ${OUT_DIR}/${TOP_MODULE}_mapped.sdf

quit
