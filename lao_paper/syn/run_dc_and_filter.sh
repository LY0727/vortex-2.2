#!/bin/bash
# 1. Ensure RTL source files are clean and untouched by intermediate files
mkdir -p work
cd work

# 2. Run Design Compiler inside the work directory
dc_shell -f ../core_top_syn.tcl | tee dc_run.log

# 3. Filter output for significant errors and warnings
echo ""
echo "========================================"
echo "      Summary of Errors and Warnings    "
echo "========================================"
grep -iE "error|warning" dc_run.log | grep -v "VER-274" | grep -v "VER-281" | grep -v "VER-209"

echo ""
echo "Note: Intermediate outputs (alib, .svf, default WORK_LIB, logs) are all saved inside the 'work' directory."
cd ..
