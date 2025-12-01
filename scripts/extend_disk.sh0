#!/bin/bash
# ==============================================================================
# OpenWrt/ImmortalWrt 磁盘空间扩展脚本 (优化版)
#
# 功能:
#   通过将大型构建目录软链接到容量更大的磁盘挂载点，
#   解决 GitHub Actions 等环境中编译时磁盘空间不足的问题。
#
# 使用方法:
#   ./extend_disk.sh [openwrt_source_directory] [options]
#   参数:
#     openwrt_source_directory: OpenWrt/ImmortalWrt 的源码目录路径。
#                               如果不提供，默认为当前目录下的 'openwrt' 文件夹。
#
#   选项:
#     -m, --min-size SIZE     设置挂载点的最小可用空间 (GB), 默认: 10
#     -d, --dirs "DIR1 DIR2"  指定需要链接的目录, 默认: "dl build_dir staging_dir tmp .ccache"
#     -r, --revert            恢复操作，将软链接替换回原始目录
#     -f, --force             强制执行，覆盖已存在的链接或目录
#
# 作者: Mary
# 日期：20251201
# 版本: 2.0 - 增加幂等性、可恢复性和可配置性
# ==============================================================================

# --- 脚本开始 ---

# 设置严格模式
set -e
set -o pipefail

# --- 默认配置 ---
DEFAULT_SOURCE_DIR="openwrt"
DEFAULT_MIN_SIZE_GB=10
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

    # 2. 查找最佳挂载点
    log "查找最佳挂载点..."
    TARGET_MOUNT_POINT=$(df -h | awk -v min_size="$MIN_SIZE_GB" '
    NR>1 && $1!="tmpfs" && $6!="/" {
        gsub(/G/, "", $4);
        gsub(/M/, "0.001", $4);
        gsub(/K/, "0.000001", $4);
        if($4 > min_size) {
            print $4, $6
        }
    }
' | sort -nr | head -n 1 | awk '{print $2}')

    if [ -z "$TARGET_MOUNT_POINT" ]; then
        log "警告: 未找到满足 ${MIN_SIZE_GB}GB 的辅助挂载点。将回退到根目录，这可能导致空间不足。"
        TARGET_MOUNT_POINT="/"
    else
        log "找到最佳挂载点: $TARGET_MOUNT_POINT"
    fi

    # 准备外部构建目录
    BUILD_DIR="$TARGET_MOUNT_POINT/openwrt-build-$(date +%s)"
    log "在 $TARGET_MOUNT_POINT 上创建构建目录: $BUILD_DIR"
    mkdir -p "$BUILD_DIR"

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
