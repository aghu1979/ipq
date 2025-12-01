#!/bin/bash
# ==============================================================================
# OpenWrt 自定义构建脚本
#
# 功能:
#   1. 修改固件基本配置
#   2. 准备第三方软件源
#   3. 更新和安装 feeds
#
# 使用方法:
#   ./diy.sh
#
# 注意:
#   此脚本只负责准备软件源，不决定最终哪些软件包会被编译进固件
#   最终的软件包选择由 .config 文件控制
#
# 作者: Mary
# 日期：20251201
# 版本: 2.8 - 修复 feeds.conf.default 语法错误
# ==============================================================================

# 设置严格模式
set -e
set -o pipefail

# 日志函数
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

# ==============================================================================
# 基本配置
# ==============================================================================
DEFAULT_IP="192.168.111.1"
HOSTNAME="WRT"
BUILD_SIGNATURE="Built by Mary"

# ==============================================================================
# 软件源配置
# ==============================================================================

# 网络代理相关软件源
PASSWALL_PACKAGES="https://github.com/xiaorouji/openwrt-passwall-packages.git;main"
PASSWALL_LUCI="https://github.com/xiaorouji/openwrt-passwall.git;main"
PASSWALL2="https://github.com/xiaorouji/openwrt-passwall2.git;main" # 修正：feed 名应为 passwall2
OPENCLASH="https://github.com/vernesong/OpenClash.git"
HOMEPROXY="https://github.com/VIKINGYFY/homeproxy"
MOMO="https://github.com/nikkinikki-org/OpenWrt-momo;main"
NIKKI="https://github.com/nikkinikki-org/OpenWrt-nikki;main"

# 网络工具与服务
ADGUARDHOME="https://github.com/sirpdboy/luci-app-adguardhome"  # 首选sirpdboy版本
DDNS_GO="https://github.com/sirpdboy/luci-app-ddns-go"
TAILSCALE="https://github.com/asvow/luci-app-tailscale"  # 官方推荐asvow版本
VNT="https://github.com/lmq8267/luci-app-vnt"  # 官方无luci-app，使用lmq8267版本
LUCKY="https://github.com/gdy666/luci-app-lucky"  # 使用原作者版本
EASYTIER="https://github.com/EasyTier/luci-app-easytier"
GECOOSAC="https://github.com/lwb1978/openwrt-gecoosac"
WOLPLUS="https://github.com/VIKINGYFY/packages;main"

# 监控与测试工具
NETDATA="https://github.com/sirpdboy/luci-app-netdata"
NETSPEEDTEST="https://github.com/sirpdboy/luci-app-netspeedtest"

# 系统管理工具
PARTEXP="https://github.com/sirpdboy/luci-app-partexp"
TASKPLAN="https://github.com/sirpdboy/luci-app-taskplan"
QUICKFILE="https://github.com/sbwml/luci-app-quickfile"
WECHATPUSH="https://github.com/tty228/luci-app-wechatpush"
OPENAPPFILTER="https://github.com/destan19/OpenAppFilter"

# 主题与界面
ARGON="https://github.com/jerrykuku/luci-theme-argon"
AURORA="https://github.com/eamonxg/luci-theme-aurora"

# DNS 相关
MOSDNS="https://github.com/sbwml/luci-app-mosdns;v5"
OPENLIST2="https://github.com/sbwml/luci-app-openlist2"
GOLANG="https://github.com/sbwml/packages_lang_golang;25.x"

# 特殊硬件支持
ATHENA_LED="https://github.com/NONGFAH/luci-app-athena-led"

# 备用软件源
SMALL_PACKAGE="https://github.com/kenzok8/small-package"

# 特殊软件源（需要稀疏克隆）
ARIANG_REPO="https://github.com/laipeng668/packages"
FRP_REPO="https://github.com/laipeng668/packages"
FRPC_LUCI_REPO="https://github.com/laipeng668/luci"

# ==============================================================================
# 主要功能函数
# ==============================================================================

# 修改基本配置 (不依赖 feeds)
modify_basic_config() {
    log "修改基本配置 (IP、主机名、密码)..."
    
    # 修改默认 IP
    sed -i "s/192.168.1.1/$DEFAULT_IP/g" package/base-files/files/bin/config_generate || error_exit "修改默认 IP 失败"
    
    # 修改主机名
    sed -i "s/hostname='.*'/hostname='$HOSTNAME'/g" package/base-files/files/bin/config_generate || error_exit "修改主机名失败"
    
    # 修改初始登录密码为空
    log "设置初始登录密码为空..."
    local shadow_file="package/base-files/files/etc/shadow"
    if [ -f "$shadow_file" ]; then
        # 将root用户的密码字段清空
        # 格式: root:<password_field>:...
        # 修改为: root::...
        sed -i 's/^root:[^:]*:/root::/' "$shadow_file" || error_exit "修改登录密码失败"
        log "初始登录密码已设置为空"
    else
        log "警告: shadow 文件 '$shadow_file' 不存在，跳过修改登录密码。"
    fi
    
    log "基本配置 (IP、主机名、密码) 修改完成"
}

# 修改 Feeds 中的包 (依赖 feeds update)
modify_feeds_packages() {
    log "修改 Feeds 中的包..."
    
    # 修改 Tailscale Makefile
    if [ -n "$TAILSCALE" ]; then
        local tailscale_makefile="feeds/packages/net/tailscale/Makefile"
        if [ -f "$tailscale_makefile" ]; then
            log "修改 Tailscale Makefile..."
            sed -i '/\/etc\/init\.d\/tailscale/d;/\/etc\/config\/tailscale/d;' "$tailscale_makefile" || log "警告: 修改 Tailscale Makefile 失败，但构建可继续"
            log "Tailscale Makefile 修改完成"
        else
            log "警告: Tailscale Makefile '$tailscale_makefile' 不存在，跳过修改。"
        fi
    fi
    
    log "Feeds 包修改完成"
}

# 修改 LuCI 编译署名 (依赖 feeds update)
modify_luci_signature() {
    log "修改 LuCI 编译署名..."
    
    local luci_status_file="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
    
    if [ -f "$luci_status_file" ]; then
        sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $BUILD_SIGNATURE')/g" "$luci_status_file" || error_exit "修改编译署名失败"
        log "LuCI 编译署名修改成功"
    else
        log "警告: LuCI 状态文件 '$luci_status_file' 不存在，跳过修改编译署名。"
    fi
}

# 添加 feeds
add_feeds() {
    log "添加 feeds..."
    
    # 添加代理相关 feeds
    [ -n "$PASSWALL_PACKAGES" ] && echo "src-git passwall_packages $PASSWALL_PACKAGES" >> "feeds.conf.default"
    [ -n "$PASSWALL_LUCI" ] && echo "src-git passwall_luci $PASSWALL_LUCI" >> "feeds.conf.default"
    # 修复：使用正确的 feed 名称
    [ -n "$PASSWALL2" ] && echo "src-git passwall2 $PASSWALL2" >> "feeds.conf.default"
    [ -n "$OPENCLASH" ] && echo "src-git luci-app-openclash $OPENCLASH" >> "feeds.conf.default"
    [ -n "$MOMO" ] && echo "src-git momo $MOMO" >> "feeds.conf.default"
    [ -n "$NIKKI" ] && echo "src-git nikki $NIKKI" >> "feeds.conf.default"
    
    log "Feeds 添加完成"
}

# 克隆软件包
clone_packages() {
    log "克隆软件包..."
    
    # 网络代理相关
    [ -n "$HOMEPROXY" ] && git clone "$HOMEPROXY" package/homeproxy
    
    # 网络工具与服务
    [ -n "$ADGUARDHOME" ] && git clone "$ADGUARDHOME" package/luci-app-adguardhome
    [ -n "$DDNS_GO" ] && git clone "$DDNS_GO" package/luci-app-ddns-go"
    [ -n "$LUCKY" ] && git clone "$LUCKY" package/luci-app-lucky
    [ -n "$EASYTIER" ] && git clone "$EASYTIER" package/luci-app-easytier"
    [ -n "$GECOOSAC" ] && git clone "$GECOOSAC" package/openwrt-gecoosac"
    
    # 监控与测试工具
    [ -n "$NETDATA" ] && git clone "$NETDATA" package/luci-app-netdata"
    [ -n "$NETSPEEDTEST" ] && git clone "$NETSPEEDTEST" package/luci-app-netspeedtest"
    
    # 系统管理工具
    [ -n "$PARTEXP" ] && git clone "$PARTEXP" package/luci-app-partexp"
    [ -n "$TASKPLAN" ] && git clone "$TASKPLAN" package/luci-app-taskplan"
    [ -n "$QUICKFILE" ] && git clone "$QUICKFILE" package/luci-app-quickfile"
    [ -n "$WECHATPUSH" ] && git clone "$WECHATPUSH" package/luci-app-wechatpush"
    [ -n "$OPENAPPFILTER" ] && git clone "$OPENAPPFILTER" package/luci-app-oaf"
    
    # 主题
    [ -n "$ARGON" ] && git clone "$ARGON" feeds/luci/themes/luci-theme-argon"
    [ -n "$AURORA" ] && git clone "$AURORA" feeds/luci/themes/luci-theme-aurora"
    
    # DNS 相关
    [ -n "$MOSDNS" ] && git clone -b "${MOSDNS#*;}" "${MOSDNS%;*}" package/luci-app-mosdns
    [ -n "$OPENLIST2" ] && git clone "$OPENLIST2" package/luci-app-openlist2"
    [ -n "$GOLANG" ] && git clone -b "${GOLANG#*;}" "${GOLANG%;*}" feeds/packages/lang/golang"
    
    # 特殊硬件支持
    [ -n "$ATHENA_LED" ] && git clone "$ATHENA_LED" package/luci-app-athena-led && chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led package/luci-app-athena-led/root/usr/sbin/athena-led
    
    # 网络工具与服务（特殊处理，移除了 sed 命令）
    [ -n "$TAILSCALE" ] && git clone "$TAILSCALE" package/luci-app-tailscale
    [ -n "$VNT" ] && git clone "$VNT" package/luci-app-vnt"
    
    # 备用软件源
    [ -n "$SMALL_PACKAGE" ] && git clone "$SMALL_PACKAGE" small
    
    log "软件包克隆完成"
}

# 稀疏克隆特殊软件包
sparse_clone_special_packages() {
    log "稀疏克隆特殊软件包..."
    
    # 稀疏克隆函数
    git_sparse_clone() {
        local branch="$1"
        local repourl="$2"
        shift 2
        local repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
        
        log "稀疏克隆 $repourl (分支: $branch, 目录: $@)"
        
        git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl" || error_exit "稀疏克隆 $repourl 失败"
        
        cd "$repodir" && git sparse-checkout set $@ || error_exit "设置稀疏检出目录失败"
        mv -f $@ ../package || error_exit "移动目录失败"
        cd .. && rm -rf "$repodir" || error_exit "删除临时目录失败"
        
        log "稀疏克隆 $repourl 完成"
    }
    
    # 稀疏克隆 ariang
    if [ -n "$ARIANG_REPO" ]; then
        git_sparse_clone "ariang" "$ARIANG_REPO" "net/ariang"
    fi
    
    # 稀疏克隆 frp 和相关 luci 应用
    if [ -n "$FRP_REPO" ]; then
        git_sparse_clone "frp" "$FRP_REPO" "net/frp"
        # 修复：确保目标目录存在
        mkdir -p feeds/packages/net
        mv -f package/frp feeds/packages/net/frp || error_exit "移动 frp 包失败"
        
        if [ -n "$FRPC_LUCI_REPO" ]; then
            git_sparse_clone "frp" "$FRPC_LUCI_REPO" "applications/luci-app-frpc" "applications/luci-app-frps"
            # 修复：确保目标目录存在
            mkdir -p feeds/luci/applications
            mv -f package/luci-app-frpc feeds/luci/applications/luci-app-frpc || error_exit "移动 luci-app-frpc 包失败"
            mv -f package/luci-app-frps feeds/luci/applications/luci-app-frps || error_exit "移动 luci-app-frps 包失败"
        fi
    fi
    
    # 稀疏克隆 wolplus
    if [ -n "$WOLPLUS" ]; then
        git_sparse_clone "${WOLPLUS#*;}" "${WOLPLUS%;*}" "luci-app-wolplus"
    fi
    
    log "稀疏克隆完成"
}

# 移除冲突的默认包 (依赖 feeds update)
remove_conflicting_packages() {
    log "移除冲突的默认包..."
    
    # 移除 luci-app-attendedsysupgrade
    sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile" 2>/dev/null) || log "警告: 移除 luci-app-attendedsysupgrade 失败，可能文件不存在。"
    
    # 移除要替换的包
    local packages=(
        "feeds/luci/applications/luci-app-wechatpush"
        "feeds/luci/applications/luci-app-appfilter"
        "feeds/luci/applications/luci-app-frpc"
        "feeds/luci/applications/luci-app-frps"
        "feeds/luci/themes/luci-theme-argon"
        "feeds/packages/net/open-app-filter"
        "feeds/packages/net/adguardhome"
        "feeds/packages/net/ariang"
        "feeds/packages/net/frp"
        "feeds/packages/lang/golang"
    )
    
    for package in "${packages[@]}"; do
        if [ -d "$package" ]; then
            log "移除 $package"
            rm -rf "$package" || error_exit "移除 $package 失败"
        fi
    done
    
    log "冲突包移除完成"
}

# 更新 feeds
update_feeds() {
    # --- 新增：验证 feeds.conf.default ---
    log "验证 feeds.conf.default 内容..."
    if [ -f "feeds.conf.default" ]; then
        log "--- feeds.conf.default 文件内容如下 ---"
        cat -n feeds.conf.default
        log "--- 内容验证结束 ---"
    else
        log "警告: feeds.conf.default 文件不存在。"
    fi

    log "更新 feeds..."
    ./scripts/feeds update -a || error_exit "Feeds 更新失败"
    ./scripts/feeds install -a || error_exit "Feeds 安装失败"
    log "Feeds 更新完成"
}

# 主函数
main() {
    log "开始 OpenWrt 自定义构建..."
    
    # 1. 修改基本配置 (不依赖 feeds)
    modify_basic_config
    
    # 2. 添加 feeds
    add_feeds
    
    # 3. 克隆软件包
    clone_packages
    
    # 4. 稀疏克隆特殊软件包
    sparse_clone_special_packages
    
    # 5. 更新 feeds
    update_feeds
    
    # 6. 移除冲突的默认包 (必须在 feeds update 之后)
    remove_conflicting_packages
    
    # 7. 修改 Feeds 中的包 (必须在 feeds update 之后)
    modify_feeds_packages
    
    # 8. 修改 LuCI 编译署名 (必须在 feeds update 之后)
    modify_luci_signature
    
    log "OpenWrt 自定义构建完成"
    log "注意: 最终编译的软件包由 .config 文件控制"
}

# 执行主函数
main
