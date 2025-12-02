# ==============================================================================
# OpenWrt Luci 软件包报告生成脚本
#
# 功能:
#   1. 从两个 .config 文件中提取 Luci 软件包列表。
#   2. 对比两个列表，找出新增和移除的软件包。
#   3. 生成一份包含详细信息和统计数据的报告文件。
#
# 使用方法:
#   ./scripts/luci_report.sh <初始配置文件路径> <最终配置文件路径> <报告输出路径>
#
# 注意:
#   此脚本通常在 CI/CD 工作流中被调用，用于跟踪配置变更。
#   脚本依赖 grep, sort, comm 等标准 Unix 工具。
#
# 作者: Mary
# 日期：20251202
# 版本: 1.0 - 初始版本，实现基本报告功能
# ==============================================================================

#!/bin/bash

# 脚本功能：生成 Luci 软件包变更报告
# 使用方法: ./scripts/luci_report.sh <初始配置文件路径> <最终配置文件路径> <报告输出路径>

# 检查参数
if [ "$#" -ne 3 ]; then
    echo "用法: $0 <initial_config_path> <final_config_path> <report_output_path>"
    exit 1
fi

INITIAL_CONFIG_PATH="$1"
FINAL_CONFIG_PATH="$2"
REPORT_OUTPUT_PATH="$3"

# 检查文件是否存在
if [ ! -f "$INITIAL_CONFIG_PATH" ]; then
    echo "错误: 初始配置文件 '$INITIAL_CONFIG_PATH' 不存在!"
    exit 1
fi

if [ ! -f "$FINAL_CONFIG_PATH" ]; then
    echo "错误: 最终配置文件 '$FINAL_CONFIG_PATH' 不存在!"
    exit 1
fi

# 临时文件
INITIAL_PACKAGES_FILE=$(mktemp)
FINAL_PACKAGES_FILE=$(mktemp)

# 提取 luci 软件包
grep "^CONFIG_PACKAGE_luci.*=y$" "$INITIAL_CONFIG_PATH" | sort > "$INITIAL_PACKAGES_FILE"
grep "^CONFIG_PACKAGE_luci.*=y$" "$FINAL_CONFIG_PATH" | sort > "$FINAL_PACKAGES_FILE"

# 生成报告
echo "=== Luci软件包变更报告 ===" > "$REPORT_OUTPUT_PATH"
echo "生成时间: $(date)" >> "$REPORT_OUTPUT_PATH"
echo "" >> "$REPORT_OUTPUT_PATH"

# 新增的软件包
echo "### 新增的Luci软件包 ###" >> "$REPORT_OUTPUT_PATH"
comm -13 "$INITIAL_PACKAGES_FILE" "$FINAL_PACKAGES_FILE" >> "$REPORT_OUTPUT_PATH"
echo "" >> "$REPORT_OUTPUT_PATH"

# 移除的软件包
echo "### 移除的Luci软件包 ###" >> "$REPORT_OUTPUT_PATH"
comm -23 "$INITIAL_PACKAGES_FILE" "$FINAL_PACKAGES_FILE" >> "$REPORT_OUTPUT_PATH"
echo "" >> "$REPORT_OUTPUT_PATH"

# 统计信息
echo "### 统计信息 ###" >> "$REPORT_OUTPUT_PATH"
echo "初始Luci软件包数量: $(wc -l < "$INITIAL_PACKAGES_FILE")" >> "$REPORT_OUTPUT_PATH"
echo "最终Luci软件包数量: $(wc -l < "$FINAL_PACKAGES_FILE")" >> "$REPORT_OUTPUT_PATH"
echo "新增软件包数量: $(comm -13 "$INITIAL_PACKAGES_FILE" "$FINAL_PACKAGES_FILE" | wc -l)" >> "$REPORT_OUTPUT_PATH"
echo "移除软件包数量: $(comm -23 "$INITIAL_PACKAGES_FILE" "$FINAL_PACKAGES_FILE" | wc -l)" >> "$REPORT_OUTPUT_PATH"

# 清理临时文件
rm -f "$INITIAL_PACKAGES_FILE" "$FINAL_PACKAGES_FILE"

echo "Luci软件包报告已生成至: $REPORT_OUTPUT_PATH"

# 在工作流中显示报告内容
echo "---------- 报告内容预览 ----------"
cat "$REPORT_OUTPUT_PATH"
echo "----------------------------------"
