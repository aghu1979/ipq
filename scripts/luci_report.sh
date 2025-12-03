# ==============================================================================
# OpenWrt 三阶段 Luci 软件包报告生成脚本
#
# 功能:
#   1. 从三个不同阶段的 .config 文件中提取 Luci 软件包列表。
#   2. 对比这三个列表，生成多份详细的变更报告。
#   3. 报告将显示 DIY 脚本、Feeds 安装和 Defconfig 分别带来的影响。
#
# 使用方法:
#   ./scripts/luci_report.sh <初始配置> <DIY后配置> <最终配置> <报告输出路径>
#
# 注意:
#   此脚本通常在 CI/CD 工作流中被调用。
#
# 作者: Mary
# 日期：20251202
# 版本: 2.0 - 重构为三阶段报告功能
# ==============================================================================

#!/bin/bash

# 检查参数
if [ "$#" -ne 4 ]; then
    echo "用法: $0 <initial_config_path> <post_diy_config_path> <final_config_path> <report_output_path>"
    exit 1
fi

INITIAL_CONFIG_PATH="$1"
POST_DIY_CONFIG_PATH="$2"
FINAL_CONFIG_PATH="$3"
REPORT_OUTPUT_PATH="$4"

# 检查文件是否存在
for file in "$INITIAL_CONFIG_PATH" "$POST_DIY_CONFIG_PATH" "$FINAL_CONFIG_PATH"; do
    if [ ! -f "$file" ]; then
        echo "错误: 配置文件 '$file' 不存在!"
        exit 1
    fi
done

# 临时文件
INITIAL_PACKAGES_FILE=$(mktemp)
POST_DIY_PACKAGES_FILE=$(mktemp)
FINAL_PACKAGES_FILE=$(mktemp)

# 提取 luci 软件包
grep "^CONFIG_PACKAGE_luci.*=y$" "$INITIAL_CONFIG_PATH" | sort > "$INITIAL_PACKAGES_FILE"
grep "^CONFIG_PACKAGE_luci.*=y$" "$POST_DIY_CONFIG_PATH" | sort > "$POST_DIY_PACKAGES_FILE"
grep "^CONFIG_PACKAGE_luci.*=y$" "$FINAL_CONFIG_PATH" | sort > "$FINAL_PACKAGES_FILE"

# 生成报告
{
    echo "==============================================================================="
    echo "OpenWrt 三阶段 Luci 软件包变更报告"
    echo "生成时间: $(date)"
    echo "==============================================================================="
    echo ""

    echo "### 1. 初始状态 (基于 immu.config) ###"
    echo "这是用户选择的软件包列表，作为所有变更的基准。"
    cat "$INITIAL_PACKAGES_FILE"
    echo ""

    echo "### 2. 自定义后状态 (执行 diyroc.sh 后) ###"
    echo "这是执行 DIY 脚本，添加/移除软件包后的列表。"
    cat "$POST_DIY_PACKAGES_FILE"
    echo ""

    echo "### 3. 最终状态 (执行 feeds install 和 make defconfig 后) ###"
    echo "这是安装 feeds 并解析所有依赖关系后，最终用于编译的完整列表。"
    cat "$FINAL_PACKAGES_FILE"
    echo ""

    echo "==============================================================================="
    echo "变更分析"
    echo "==============================================================================="
    echo ""

    # --- 变更 1 vs 2: DIY 脚本的影响 ---
    echo ">>> 变更分析 A: DIY 脚本带来的影响 (对比 状态1 vs 状态2)"
    echo "  - 新增的软件包:"
    comm -13 "$INITIAL_PACKAGES_FILE" "$POST_DIY_PACKAGES_FILE" | sed 's/^/    /'
    echo ""
    echo "  - 移除的软件包:"
    comm -23 "$INITIAL_PACKAGES_FILE" "$POST_DIY_PACKAGES_FILE" | sed 's/^/    /'
    echo ""

    # --- 变更 2 vs 3: Feeds 和 Defconfig 的影响 ---
    echo ">>> 变更分析 B: Feeds 和 Defconfig 带来的影响 (对比 状态2 vs 状态3)"
    echo "  - 自动新增的依赖软件包:"
    comm -13 "$POST_DIY_PACKAGES_FILE" "$FINAL_PACKAGES_FILE" | sed 's/^/    /'
    echo ""
    echo "  - 因依赖冲突自动移除的软件包:"
    comm -23 "$POST_DIY_PACKAGES_FILE" "$FINAL_PACKAGES_FILE" | sed 's/^/    /'
    echo ""

    # --- 总变更 1 vs 3 ---
    echo ">>> 变更分析 C: 总体变更 (对比 初始状态 vs 最终状态)"
    echo "  - 最终新增的软件包:"
    comm -13 "$INITIAL_PACKAGES_FILE" "$FINAL_PACKAGES_FILE" | sed 's/^/    /'
    echo ""
    echo "  - 最终移除的软件包:"
    comm -23 "$INITIAL_PACKAGES_FILE" "$FINAL_PACKAGES_FILE" | sed 's/^/    /'
    echo ""

    echo "==============================================================================="
    echo "统计信息"
    echo "==============================================================================="
    echo "  - 初始软件包数量: $(wc -l < "$INITIAL_PACKAGES_FILE")"
    echo "  - DIY后软件包数量: $(wc -l < "$POST_DIY_PACKAGES_FILE")"
    echo "  - 最终软件包数量: $(wc -l < "$FINAL_PACKAGES_FILE")"
    echo ""
    echo "  - DIY脚本新增数量: $(comm -13 "$INITIAL_PACKAGES_FILE" "$POST_DIY_PACKAGES_FILE" | wc -l)"
    echo "  - DIY脚本移除数量: $(comm -23 "$INITIAL_PACKAGES_FILE" "$POST_DIY_PACKAGES_FILE" | wc -l)"
    echo "  - 自动依赖新增数量: $(comm -13 "$POST_DIY_PACKAGES_FILE" "$FINAL_PACKAGES_FILE" | wc -l)"
    echo "  - 自动依赖移除数量: $(comm -23 "$POST_DIY_PACKAGES_FILE" "$FINAL_PACKAGES_FILE" | wc -l)"

} > "$REPORT_OUTPUT_PATH"

# 清理临时文件
rm -f "$INITIAL_PACKAGES_FILE" "$POST_DIY_PACKAGES_FILE" "$FINAL_PACKAGES_FILE"

echo "三阶段 Luci 软件包报告已生成至: $REPORT_OUTPUT_PATH"

# 在工作流中显示报告内容
echo "---------- 报告内容预览 ----------"
cat "$REPORT_OUTPUT_PATH"
echo "----------------------------------"
