#!/bin/bash

# ==============================================================================
# OpenWrt/ImmortalWrt 磁盘空间扩展脚本
#
# 功能:
#   通过将大型构建目录软链接到容量更大的磁盘挂载点，
#   解决 GitHub Actions 等环境中编译时磁盘空间不足的问题。
#
# 使用方法:
#   ./scripts/extend_disk.sh [openwrt_source_directory]
#   参数:
#     openwrt_source_directory: OpenWrt/ImmortalWrt 的源码目录路径。
#                               如果不提供，默认为当前目录下的 'openwrt' 文件夹。
#
# 作者: Mary
# 日期：20251201
# 版本: 1.3 - 增加对 .ccache 目录的支持，以配合编译器缓存优化。
# ==============================================================================

# --- 脚本开始 ---

# 设置严格模式：任何命令失败或管道中任一命令失败，则脚本退出
set -e
set -o pipefail

# --- 参数处理 ---
# 默认源码目录为当前目录下的 'openwrt'
SOURCE_DIR="${1:-openwrt}"

# 检查源码目录是否存在
if [ ! -d "$SOURCE_DIR" ]; then
    echo "错误: 源码目录 '$SOURCE_DIR' 不存在！"
    echo "请确保在正确的位置运行此脚本，或提供正确的源码目录路径作为参数。"
    exit 1
fi

echo ">>> 正在为源码目录 '$SOURCE_DIR' 扩展磁盘空间..."
echo "=================================================="

# --- 1. 显示扩展前的磁盘状态 ---
echo ">>> [步骤 1/4] 扩展前主磁盘(/)空间使用情况:"
df -h /
echo "--------------------------------------------------"

# --- 2. 核心逻辑：查找挂载点并移动/链接目录 ---

# 查找最佳挂载点
echo ">>> [步骤 2/4] 查找最佳挂载点并准备扩展..."
TARGET_MOUNT_POINT=$(df -h | awk '
    NR>1 && $1!="tmpfs" && $6!="/" {
        gsub(/G/, "", $4);
        gsub(/M/, "0.001", $4);
        gsub(/K/, "0.000001", $4);
        if($4 > 10) {
            print $4, $6
        }
    }
' | sort -nr | head -n 1 | awk '{print $2}')

if [ -z "$TARGET_MOUNT_POINT" ]; then
    echo "警告: 未找到合适的辅助挂载点。将回退到根目录，这可能导致空间不足。"
    TARGET_MOUNT_POINT="/"
else
    echo "找到最佳挂载点: $TARGET_MOUNT_POINT"
fi

# 准备外部构建目录
BUILD_DIR="$TARGET_MOUNT_POINT/openwrt-build"
echo "在 $TARGET_MOUNT_POINT 上创建构建目录: $BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 移动并链接大目录
echo ">>> [步骤 3/4] 移动并链接大型构建目录..."
cd "$SOURCE_DIR"
# 将 .ccache 也加入列表，因为它也可能变得很大
DIRS_TO_LINK="dl build_dir staging_dir tmp .ccache"

for dir in $DIRS_TO_LINK; do
    echo "--- 处理目录: $dir ---"
    if [ -d "$dir" ]; then
        echo "移动现有目录 '$dir' 到 '$BUILD_DIR/$dir'..."
        mv "$dir" "$BUILD_DIR/"
    else
        echo "目录 '$dir' 不存在，将在 '$BUILD_DIR' 中创建。"
        mkdir -p "$BUILD_DIR/$dir"
    fi
    echo "创建软链接: $dir -> $BUILD_DIR/$dir"
    ln -sf "$BUILD_DIR/$dir" .
done
echo "--------------------------------------------------"

# --- 3. 显示扩展后的结果 ---
echo ">>> [步骤 3/4] 验证扩展结果:"
echo "1. 检查软链接是否创建成功:"
ls -l . | grep -E 'dl|build_dir|staging_dir|tmp|.ccache'

echo ""
echo "2. 检查扩展文件夹 '$BUILD_DIR' 的大小:"
# -h: human-readable, -s: summarize, -c: display a grand total
du -shc "$BUILD_DIR"/*

echo ""
echo "3. 扩展后主磁盘(/)空间使用情况:"
df -h /
echo "--------------------------------------------------"

# --- 4. 总结 ---
echo ">>> [步骤 4/4] 磁盘空间扩展脚本执行完毕！"
echo "请对比步骤 1 和步骤 3 中主磁盘(/)的可用空间变化。"

# --- 脚本结束 ---
