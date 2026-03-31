#!/bin/bash
# ==============================================================================
# Cleanup Script to remove large synthesis artifacts and keep ONLY .rpt files 
# ==============================================================================

# 设置清理的目标目录
TARGET_DIR="dc_experiments"

echo "========================================="
echo "🧽 开始清理 $TARGET_DIR 目录中不需要的网表文件..."
echo "========================================="

# 确保目录存在
if [ ! -d "$TARGET_DIR" ]; then
    echo "错误: 找不到目录 $TARGET_DIR"
    exit 1
fi

# 使用 find 命令查找并删除所有扩展名为 .v, .ddc, .sdc, .sdf 的文件
# -type f: 只查找普通文件
# \(: 分组匹配多个后缀
# -exec rm -v {} +: 批量删除并打印出被删除的文件名

find "$TARGET_DIR" -type f \( -name "*.v" -o -name "*.ddc" -o -name "*.sdc" -o -name "*.sdf" -o -name "*.log" \) -exec rm -v {} +

echo ""
echo "✅ 清理完成！"
echo "现在 $TARGET_DIR 下应该只剩下 .rpt 报告文件了。"
echo "您可以放心地将 dc_experiments 目录打包压缩并同步回来了！"

# (可选提示操作: 顺便打个压缩包)
# tar -czvf dc_experiments_reports.tar.gz dc_experiments/
