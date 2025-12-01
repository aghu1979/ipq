#!/bin/bash
# ==============================================================================
# OpenWrt/ImmortalWrt 磁盘空间扩展脚本 (自动挂载版)
#
# 功能:
#   1. 优先使用已挂载的、空间充足的目录。
#   2. 如果没有，则自动寻找并挂载未使用的磁盘分区。
#   3. 将大型构建目录软链接到目标位置。
#
# 使用方法:
#   ./scripts/extend_disk.sh [openwrt_source_directory] [options]
#
# 作者: Mary
# 日期：20251201
# 版本: 2.4 - 实现自动发现并挂载未使用磁盘
# ==============================================================================

# --- 脚本开始 ---

# 设置严格模式
set -e
set -o pipefail

# --- 默认配置 ---
DEFAULT_SOURCE_DIR="openwrt"
DEFAULT_MIN_SIZE_GB=20
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

# --- 参数解析 (省略，与之前版本相同) ---
show_help() { grep -E '^# |^#-#' "$0" | sed -e 's/^# \?//' -e 's/^#-#//'; }
parse_args() {
    # ... (此函数代码与前一版本完全相同，为简洁起见在此省略)
    # ... 请确保从上一个版本复制完整的 parse_args 函数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) show_help; exit 0 ;;
            -m|--min-size) MIN_SIZE_GB="$2"; shift 2 ;;
            -d|--dirs) DIRS_TO_LINK="$2"; shift 2 ;;
            -r|--revert) REVERT_MODE=true; shift ;;
            -f|--force) FORCE_MODE=true; shift ;;
            -*) error_exit "未知选项: $1" ;;
            *) if [ -z "$SOURCE_DIR" ]; then SOURCE_DIR="$1"; else error_exit "多余的参数: $1"; fi; shift ;;
        esac
    done
    SOURCE_DIR="${SOURCE_DIR:-$DEFAULT_SOURCE_DIR}"
    MIN_SIZE_GB="${MIN_SIZE_GB:-$DEFAULT_MIN_SIZE_GB}"
    DIRS_TO_LINK="${DIRS_TO_LINK:-$DEFAULT_DIRS_TO_LINK}"
}


# --- 恢复操作 (省略，与之前版本相同) ---
revert_links() {
    # ... (此函数代码与前一版本完全相同)
    log "进入恢复模式..."
    cd "$SOURCE_DIR" || error_exit "无法进入源码目录: $SOURCE_DIR"
    for dir in $DIRS_TO_LINK; do
        if [ -L "$dir" ]; then
            log "恢复软链接: $dir"
            local link_target=$(readlink "$dir")
            rm "$dir" || error_exit "移除软链接 $dir 失败"
            if [ -d "$link_target" ]; then mv "$link_target" "$dir" || error_exit "将 $link_target 移回 $dir 失败"
            else mkdir -p "$dir" || error_exit "创建目录 $dir 失败"; fi
        else log "目录 $dir 不是软链接，跳过"; fi
    done
    log "恢复操作完成"
}

# --- 新增：自动寻找并挂载未使用的设备 ---
find_and_mount_device() {
    local min_size_kb=$((MIN_SIZE_GB * 1024 * 1024))
    log "未找到合适的挂载点，正在尝试寻找并挂载未使用的磁盘..." >&2

    # 使用 lsblk 的 JSON 输出进行精确解析
    while read -r device; do
        local name=$(echo "$device" | jq -r '.name')
        local size_kb=$(echo "$device" | jq -r '.size' | sed 's/G//' | awk '{print int($1 * 1024 * 1024)}')
        local fstype=$(echo "$device" | jq -r '.fstype')

        # 检查是否为分区、大小是否足够、是否有文件系统
        if [[ "$name" =~ ^sd[a-z][0-9]+$ ]] && [ "$size_kb" -gt "$min_size_kb" ] && [ -n "$fstype" ]; then
            local device_path="/dev/$name"
            local mount_point="/mnt/auto-openwrt-$(date +%s)"

            log "发现合适的未挂载设备: $device_path (大小: $((size_kb / 1024 / 1024))GB, 文件系统: $fstype)" >&2
            
            log "正在创建临时挂载点: $mount_point" >&2
            sudo mkdir -p "$mount_point" || error_exit "创建挂载点 $mount_point 失败"

            log "正在挂载设备 $device_path 到 $mount_point..." >&2
            sudo mount "$device_path" "$mount_point" || error_exit "挂载 $device_path 失败"

            log "正在修改挂载点权限..." >&2
            sudo chown $(id -u):$(id -g) "$mount_point" || error_exit "修改 $mount_point 权限失败"
            
            log "成功挂载并使用 $device_path" >&2
            echo "$mount_point"
            return
        fi
    done < <(lsblk -J -o NAME,SIZE,FSTYPE,MOUNTPOINT | jq -c '.blockdevices[] | select(.type=="part")')
    
    log "未能找到任何合适的未挂载磁盘。" >&2
}

# --- 修复：智能查找挂载点 ---
find_best_mount_point() {
    # ... (此函数代码与前一版本完全相同)
    local min_size_kb=$((MIN_SIZE_GB * 1024 * 1024))
    local best_mount=""
    local best_size=0
    local fallback_mount=""
    local fallback_size=0
    log "正在扫描所有挂载点..." >&2
    while read -r filesystem blocks used available use_percent mount; do
        if [[ "$filesystem" == "Filesystem" || "$filesystem" == "tmpfs" || "$filesystem" == "devtmpfs" || "$filesystem" == "overlay" ]]; then continue; fi
        if [ -w "$mount" ] && [ "$available" -gt "$fallback_size" ]; then fallback_size="$available"; fallback_mount="$mount"; fi
        if [ "$available" -gt "$min_size_kb" ] && [ -w "$mount" ]; then
            log "发现满足条件的挂载点: $mount (可用空间: $((available / 1024 / 1024))GB)" >&2
            if [ "$available" -gt "$best_size" ]; then best_size="$available"; best_mount="$mount"; fi
        fi
    done < <(df -k | tail -n +2)
    if [ -n "$best_mount" ]; then echo "$best_mount"
    elif [ -n "$fallback_mount" ]; then
        log "警告: 未找到满足 ${MIN_SIZE_GB}GB 的挂载点。将回退到空间最大的挂载点: $fallback_mount (可用空间: $((fallback_size / 1024 / 1024))GB)" >&2
        echo "$fallback_mount"
    else echo ""; fi
}

# --- 核心逻辑 ---
extend_disk() {
    log "源码目录: $SOURCE_DIR"
    log "最小空间要求: ${MIN_SIZE_GB}GB"
    log "待处理目录: $DIRS_TO_LINK"
    echo "=================================================="
    if [ ! -d "$SOURCE_DIR" ]; then error_exit "源码目录 '$SOURCE_DIR' 不存在！"; fi
    log "扩展前主磁盘(/)空间使用情况:"; df -h /; echo "--------------------------------------------------"

    # 1. 首先尝试寻找已挂载的目录
    TARGET_MOUNT_POINT=$(find_best_mount_point)

    # 2. 如果找不到，则尝试寻找并挂载新设备
    if [ -z "$TARGET_MOUNT_POINT" ]; then
        TARGET_MOUNT_POINT=$(find_and_mount_device)
    fi

    # 3. 最终检查
    if [ -z "$TARGET_MOUNT_POINT" ]; then
        error_exit "无法找到或创建任何可用的存储空间，磁盘扩展失败。"
    else
        log "最终选择存储位置: $TARGET_MOUNT_POINT"
    fi
    
    # ... (后续的 mkdir, mv, ln 等逻辑与之前版本相同)
    if [ ! -w "$TARGET_MOUNT_POINT" ]; then error_exit "选定的位置 '$TARGET_MOUNT_POINT' 不可写，请检查权限。"; fi
    BUILD_DIR="$TARGET_MOUNT_POINT/openwrt-build-$(date +%s)"
    log "在 $TARGET_MOUNT_POINT 上创建构建目录: $BUILD_DIR"
    mkdir -p "$BUILD_DIR" || error_exit "无法创建构建目录 $BUILD_DIR，请检查权限。"
    log "移动并链接大型构建目录..."
    cd "$SOURCE_DIR" || error_exit "无法进入源码目录: $SOURCE_DIR"
    for dir in $DIRS_TO_LINK; do
        log "--- 处理目录: $dir ---"
        if [ -L "$dir" ]; then
            local current_target=$(readlink "$dir")
            if [ "$current_target" = "$BUILD_DIR/$dir" ]; then log "软链接 $dir -> $current_target 已存在且正确，跳过"; continue
            else
                if [ "$FORCE_MODE" = false ]; then error_exit "软链接 $dir 已存在但指向错误目标 ($current_target)。使用 -f 强制覆盖。"; fi
                log "强制模式：移除现有软链接 $dir"; rm "$dir";
            fi
        fi
        if [ -d "$dir" ]; then log "移动现有目录 '$dir' 到 '$BUILD_DIR/$dir'..."; mv "$dir" "$BUILD_DIR/"
        else log "目录 '$dir' 不存在，将在 '$BUILD_DIR' 中创建。"; mkdir -p "$BUILD_DIR/$dir"; fi
        log "创建软链接: $dir -> $BUILD_DIR/$dir"; ln -sf "$BUILD_DIR/$dir" .
    done
    echo "--------------------------------------------------"
    log "验证扩展结果:"; log "1. 检查软链接是否创建成功:"; ls -l . | grep -E "$(echo $DIRS_TO_LINK | tr ' ' '|')"
    echo ""; log "2. 检查扩展文件夹 '$BUILD_DIR' 的大小:"; du -shc "$BUILD_DIR"/*
    echo ""; log "3. 扩展后主磁盘(/)空间使用情况:"; df -h /; echo "--------------------------------------------------"
    log "磁盘空间扩展脚本执行完毕！"; log "构建目录位于: $BUILD_DIR"; log "请对比扩展前后的主磁盘可用空间变化。"
}

# --- 主函数 ---
main() {
    parse_args "$@"
    if [ "$REVERT_MODE" = true ]; then revert_links; else extend_disk; fi
}

# --- 脚本结束 ---
main "$@"
