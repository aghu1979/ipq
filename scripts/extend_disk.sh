#!/bin/bash
# ==============================================================================
# OpenWrt/ImmortalWrt 磁盘空间扩展脚本 (修复版)
#
# 功能:
#   通过将大型构建目录软链接到容量更大且可写的磁盘挂载点，
#   解决 GitHub Actions 等环境中编译时磁盘空间不足的问题。
#
# 使用方法:
#   ./scripts/extend_disk.sh [openwrt_source_directory] [options]
#   参数:
#     openwrt_source_directory: OpenWrt/ImmortalWrt 的源码目录路径。
#                               如果不提供，默认为当前目录下的 'openwrt' 文件夹。
#
#   选项:
#     -m, --min-size SIZE     设置挂载点的最小可用空间 (GB), 默认: 30
#     -d, --dirs "DIR1 DIR2"  指定需要链接的目录, 默认: "dl build_dir staging_dir tmp .ccache"
#     -r, --revert            恢复操作，将软链接替换回原始目录
#     -f, --force             强制执行，覆盖已存在的链接或目录
#
# 作者: Mary
# 日期：20251201
# 版本: 2.2 - 修复日志污染变量和挂载点选择逻辑
# ==============================================================================

# --- 脚本开始 ---

# 设置严格模式
set -e
set -o pipefail

# --- 默认配置 ---
DEFAULT_SOURCE_DIR="openwrt"
DEFAULT_MIN_SIZE_GB=30
DEFAULT_DIRS_TO_LINK="dl build_dir staging_dir tmp .ccache"
REVERT_MODE=false
FORCE_MODE=false

# --- 日志函数 ---
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

# --- 帮助信息 ---
show_help() {
    grep -E '^# |^#-#' "$0" | sed -e 's/^# \?//' -e 's/^#-#//'
}

# --- 参数解析 ---
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -m|--min-size)
                MIN_SIZE_GB="$2"
                shift 2
                ;;
            -d|--dirs)
                DIRS_TO_LINK="$2"
                shift 2
                ;;
            -r|--revert)
                REVERT_MODE=true
                shift
                ;;
            -f|--force)
                FORCE_MODE=true
                shift
                ;;
            -*)
                error_exit "未知选项: $1"
                ;;
            *)
                # 第一个非选项参数作为源码目录
                if [ -z "$SOURCE_DIR" ]; then
                    SOURCE_DIR="$1"
                else
                    error_exit "多余的参数: $1"
                fi
                shift
                ;;
        esac
    done

    # 设置最终变量
    SOURCE_DIR="${SOURCE_DIR:-$DEFAULT_SOURCE_DIR}"
    MIN_SIZE_GB="${MIN_SIZE_GB:-$DEFAULT_MIN_SIZE_GB}"
    DIRS_TO_LINK="${DIRS_TO_LINK:-$DEFAULT_DIRS_TO_LINK}"
}

# --- 恢复操作 ---
revert_links() {
    log "进入恢复模式..."
    cd "$SOURCE_DIR" || error_exit "无法进入源码目录: $SOURCE_DIR"

    for dir in $DIRS_TO_LINK; do
        if [ -L "$dir" ]; then
            log "恢复软链接: $dir"
            local link_target=$(readlink "$dir")
            rm "$dir" || error_exit "移除软链接 $dir 失败"
            if [ -d "$link_target" ]; then
                mv "$link_target" "$dir" || error_exit "将 $link_target 移回 $dir 失败"
            else
                mkdir -p "$dir" || error_exit "创建目录 $dir 失败"
            fi
        else
            log "目录 $dir 不是软链接，跳过"
        fi
    done
    log "恢复操作完成"
}

# --- 修复：查找最佳且可写的挂载点 ---
find_best_writable_mount_point() {
    local min_size_kb=$((MIN_SIZE_GB * 1024 * 1024)) # 转换为 KB
    local best_mount=""
    local best_size=0

    # 修复：将进度日志重定向到 stderr，避免污染函数返回值
    log "正在扫描可用且可写的挂载点 (最小空间: ${MIN_SIZE_GB}GB)..." >&2

    # 使用 df -k 获取以KB为单位的精确大小，并逐行处理
    while read -r filesystem blocks used available use_percent mount; do
        # 跳过标题行、根目录、tmpfs 和其他特殊文件系统
        if [[ "$filesystem" == "Filesystem" || "$mount" == "/" || "$filesystem" == "tmpfs" || "$filesystem" == "devtmpfs" || "$filesystem" == "overlay" ]]; then
            continue
        fi

        # 检查空间和可写性
        if [ "$available" -gt "$min_size_kb" ] && [ -w "$mount" ]; then
            # 修复：将候选日志也重定向到 stderr
            log "发现候选挂载点: $mount (可用空间: $((available / 1024 / 1024))GB)" >&2
            if [ "$available" -gt "$best_size" ]; then
                best_size="$available"
                best_mount="$mount"
            fi
        fi
    done < <(df -k | tail -n +2) # tail -n +2 跳过 df 的标题行

    echo "$best_mount"
}

# --- 核心逻辑：查找挂载点并移动/链接目录 ---
extend_disk() {
    log "源码目录: $SOURCE_DIR"
    log "最小空间要求: ${MIN_SIZE_GB}GB"
    log "待处理目录: $DIRS_TO_LINK"
    echo "=================================================="

    # 检查源码目录是否存在
    if [ ! -d "$SOURCE_DIR" ]; then
        error_exit "源码目录 '$SOURCE_DIR' 不存在！"
    fi

    # 1. 显示扩展前的磁盘状态
    log "扩展前主磁盘(/)空间使用情况:"
    df -h /
    echo "--------------------------------------------------"

    # 2. 查找最佳且可写的挂载点
    TARGET_MOUNT_POINT=$(find_best_writable_mount_point)

    if [ -z "$TARGET_MOUNT_POINT" ]; then
        log "警告: 未找到满足条件的辅助挂载点。将回退到源码目录所在磁盘，这可能导致空间不足。"
        # 回退策略：使用源码目录所在的挂载点
        TARGET_MOUNT_POINT=$(df "$SOURCE_DIR" | tail -1 | awk '{print $6}')
    else
        # 修复：增加明确的日志，显示最终选择的挂载点
        log "找到最佳挂载点: $TARGET_MOUNT_POINT"
    fi

    # 准备外部构建目录
    BUILD_DIR="$TARGET_MOUNT_POINT/openwrt-build-$(date +%s)"
    log "在 $TARGET_MOUNT_POINT 上创建构建目录: $BUILD_DIR"
    mkdir -p "$BUILD_DIR" || error_exit "无法创建构建目录 $BUILD_DIR，请检查权限。"

    # 3. 移动并链接大目录
    log "移动并链接大型构建目录..."
    cd "$SOURCE_DIR" || error_exit "无法进入源码目录: $SOURCE_DIR"

    for dir in $DIRS_TO_LINK; do
        log "--- 处理目录: $dir ---"
        
        # 幂等性检查
        if [ -L "$dir" ]; then
            local current_target=$(readlink "$dir")
            if [ "$current_target" = "$BUILD_DIR/$dir" ]; then
                log "软链接 $dir -> $current_target 已存在且正确，跳过"
                continue
            else
                if [ "$FORCE_MODE" = false ]; then
                    error_exit "软链接 $dir 已存在但指向错误目标 ($current_target)。使用 -f 强制覆盖。"
                fi
                log "强制模式：移除现有软链接 $dir"
                rm "$dir"
            fi
        fi

        if [ -d "$dir" ]; then
            log "移动现有目录 '$dir' 到 '$BUILD_DIR/$dir'..."
            mv "$dir" "$BUILD_DIR/"
        else
            log "目录 '$dir' 不存在，将在 '$BUILD_DIR' 中创建。"
            mkdir -p "$BUILD_DIR/$dir"
        fi
        
        log "创建软链接: $dir -> $BUILD_DIR/$dir"
        ln -sf "$BUILD_DIR/$dir" .
    done
    echo "--------------------------------------------------"

    # 4. 显示扩展后的结果
    log "验证扩展结果:"
    log "1. 检查软链接是否创建成功:"
    ls -l . | grep -E "$(echo $DIRS_TO_LINK | tr ' ' '|')"

    echo ""
    log "2. 检查扩展文件夹 '$BUILD_DIR' 的大小:"
    du -shc "$BUILD_DIR"/*

    echo ""
    log "3. 扩展后主磁盘(/)空间使用情况:"
    df -h /
    echo "--------------------------------------------------"

    log "磁盘空间扩展脚本执行完毕！"
    log "构建目录位于: $BUILD_DIR"
    log "请对比扩展前后的主磁盘可用空间变化。"
}

# --- 主函数 ---
main() {
    # 解析命令行参数
    parse_args "$@"

    if [ "$REVERT_MODE" = true ]; then
        revert_links
    else
        extend_disk
    fi
}

# --- 脚本结束 ---
main "$@"
