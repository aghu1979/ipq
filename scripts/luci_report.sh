# ==============================================================================
# OpenWrt 三阶段 Luci 软件包报告生成脚本
#
# 功能:
#   1. 从三个不同阶段的 .config 文件中提取 Luci 软件包列表。
#   2. 生成一个 Markdown 表格，用于横向对比三个阶段的软件包状态。
#
# 使用方法:
#   ./scripts/luci_report.sh <初始配置> <Feeds安装后配置> <最终配置> <报告输出路径>
#
# 注意:
#   此脚本通常在 CI/CD 工作流中被调用。
#
# 作者: Mary
# 日期：20251202
# 版本: 3.1 - 修正报告阶段描述以匹配新的工作流
# ==============================================================================

#!/bin/bash

# 检查参数
if [ "$#" -ne 4 ]; then
    echo "用法: $0 <initial_config_path> <post_feeds_config_path> <final_config_path> <report_output_path>"
    exit 1
fi

INITIAL_CONFIG_PATH="$1"
POST_FEEDS_CONFIG_PATH="$2"
FINAL_CONFIG_PATH="$3"
REPORT_OUTPUT_PATH="$4"

# 检查文件是否存在
for file in "$INITIAL_CONFIG_PATH" "$POST_FEEDS_CONFIG_PATH" "$FINAL_CONFIG_PATH"; do
    if [ ! -f "$file" ]; then
        echo "错误: 配置文件 '$file' 不存在!"
        exit 1
    fi
done

# 临时文件
INITIAL_PACKAGES_FILE=$(mktemp)
POST_FEEDS_PACKAGES_FILE=$(mktemp)
FINAL_PACKAGES_FILE=$(mktemp)
ALL_PACKAGES_FILE=$(mktemp)

# 提取 luci 软件包名称 (去掉 CONFIG_PACKAGE_=y 前缀)
grep "^CONFIG_PACKAGE_luci.*=y$" "$INITIAL_CONFIG_PATH" | sed 's/^CONFIG_PACKAGE_\(.*\)=y/\1/' | sort > "$INITIAL_PACKAGES_FILE"
grep "^CONFIG_PACKAGE_luci.*=y$" "$POST_FEEDS_CONFIG_PATH" | sed 's/^CONFIG_PACKAGE_\(.*\)=y/\1/' | sort > "$POST_FEEDS_PACKAGES_FILE"
grep "^CONFIG_PACKAGE_luci.*=y$" "$FINAL_CONFIG_PATH" | sed 's/^CONFIG_PACKAGE_\(.*\)=y/\1/' | sort > "$FINAL_PACKAGES_FILE"

# 合并所有软件包并排序，用于生成表格的行
cat "$INITIAL_PACKAGES_FILE" "$POST_FEEDS_PACKAGES_FILE" "$FINAL_PACKAGES_FILE" | sort -u > "$ALL_PACKAGES_FILE"

# 生成报告
{
    echo "==============================================================================="
    echo "OpenWrt Luci 软件包变更报告 (表格版)"
    echo "生成时间: $(date)"
    echo "==============================================================================="
    echo ""
    echo "### 📊 软件包状态对比表"
    echo ""
    echo "| 软件包名称 | 1. 初始 | 2. Feeds后 | 3. 最终 |"
    echo "|:---|:---:|:---:|:---:|"

    # 遍历所有软件包，检查它们在每个阶段的状态
    while IFS= read -r pkg; do
        initial_status=" "
        post_feeds_status=" "
        final_status=" "

        if grep -q "^${pkg}$" "$INITIAL_PACKAGES_FILE"; then
            initial_status="✅"
        fi
        if grep -q "^${pkg}$" "$POST_FEEDS_PACKAGES_FILE"; then
            post_feeds_status="✅"
        fi
        if grep -q "^${pkg}$" "$FINAL_PACKAGES_FILE"; then
            final_status="✅"
        fi
        
        echo "| $pkg | $initial_status | $post_feeds_status | $final_status |"
    done < "$ALL_PACKAGES_FILE"

    echo ""
    echo "### 📈 统计信息"
    echo ""
    echo "- **初始软件包数量**: $(wc -l < "$INITIAL_PACKAGES_FILE")"
    echo "- **Feeds后软件包数量**: $(wc -l < "$POST_FEEDS_PACKAGES_FILE")"
    echo "- **最终软件包数量**: $(wc -l < "$FINAL_PACKAGES_FILE")"
    echo ""
    echo "### 📝 变更分析"
    echo ""
    echo "- **Feeds Install 新增**: $(comm -13 "$INITIAL_PACKAGES_FILE" "$POST_FEEDS_PACKAGES_FILE" | wc -l) 个 (主要是依赖包)"
    echo "- **Feeds Install 移除**: $(comm -23 "$INITIAL_PACKAGES_FILE" "$POST_FEEDS_PACKAGES_FILE" | wc -l) 个"
    echo "- **Defconfig 新增**: $(comm -13 "$POST_FEEDS_PACKAGES_FILE" "$FINAL_PACKAGES_FILE" | wc -l) 个"
    echo "- **Defconfig 移除**: $(comm -23 "$POST_FEEDS_PACKAGES_FILE" "$FINAL_PACKAGES_FILE" | wc -l) 个"

} > "$REPORT_OUTPUT_PATH"

# 清理临时文件
rm -f "$INITIAL_PACKAGES_FILE" "$POST_FEEDS_PACKAGES_FILE" "$FINAL_PACKAGES_FILE" "$ALL_PACKAGES_FILE"

echo "Luci 软件包报告已生成至: $REPORT_OUTPUT_PATH"

# 在工作流中显示报告内容
echo "---------- 报告内容预览 ----------"
cat "$REPORT_OUTPUT_PATH"
echo "----------------------------------"
