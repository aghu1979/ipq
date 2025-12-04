# ==============================================================================
# OpenWrt 自定义构建脚本 (diyroc.sh)
#
# 功能:
#   1. 修改固件基本配置 (IP, 主机名, 登录密码)
#   2. 移除不需要的默认软件包
#   3. 准备并添加第三方软件源到 'package/' 目录
#
# 使用方法:
#   此脚本由 GitHub Actions 工作流调用。
#   ./scripts/diyroc.sh
#
# 注意:
#   - 所有自定义包都将添加到 'package/' 目录，这是 OpenWrt 的推荐做法。
#   - 最终的软件包选择由 .config 文件控制。
#
# 作者: Mary
# 日期：20251202
# 版本: 3.3 - 修复 golang 包依赖问题，避免破坏 feeds 内部结构
# ==============================================================================

# 在任何命令失败时立即退出
set -e

echo "==============================================================================="
echo "开始执行自定义构建脚本..."
echo "==============================================================================="

# --- 1. 修改固件基本配置 ---
echo "-> 1. 修改默认IP, 主机名, 固件信息和登录密码..."
sed -i 's/192.168.1.1/192.168.111.1/g' package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='WRT'/g" package/base-files/files/bin/config_generate
# 设置默认登录密码为空，确保与发布描述相符
sed -i 's/^root:[^:]*:/root::/g' package/base-files/files/etc/shadow
# 修改固件版本显示
sed -i "s#_('Firmware Version'), (L\.isObject(boardinfo\.release) ? boardinfo\.release\.description + ' / ' : '') + (luciversion || ''),# \
            _('Firmware Version'),\n \
            E('span', {}, [\n \
                (L.isObject(boardinfo.release)\n \
                ? boardinfo.release.description + ' / '\n \
                : '') + (luciversion || '') + ' / ',\n \
            E('a', {\n \
                href: 'https://github.com/laipeng668/openwrt-ci-roc/releases',\n \
                target: '_blank',\n \
                rel: 'noopener noreferrer'\n \
                }, [ 'Built by Mary $(date "+%Y-%m-%d %H:%M:%S")' ])\n \
            ]),#" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js

# --- 2. 移除默认软件包 ---
echo "-> 2. 移除不需要的默认软件包..."
# 移除 luci-app-attendedsysupgrade
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "/attendedsysupgrade/d" {} +

# 移除要替换的默认包和feeds自带的核心库
rm -rf \
    feeds/luci/applications/luci-app-wechatpush \
    feeds/luci/applications/luci-app-appfilter \
    feeds/luci/applications/luci-app-frpc \
    feeds/luci/applications/luci-app-frps \
    feeds/luci/themes/luci-theme-argon \
    feeds/packages/net/open-app-filter \
    feeds/packages/net/adguardhome \
    feeds/packages/net/ariang \
    feeds/packages/net/frp \
    # feeds/packages/lang/golang \  # <-- 从这里移除
    feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls} \
    feeds/luci/applications/luci-app-passwall \
    feeds/luci/applications/luci-app-openclash \
    feeds/packages/net/speedtest-cli

# --- 3. 准备并添加第三方软件源 ---
echo "-> 3. 准备并添加第三方软件源 (并行克隆中)..."

# Git稀疏克隆函数
function git_sparse_clone() {
  branch="$1"
  repourl="$2"
  shift 2
  repodir=$(basename "$repourl")
  echo "  -> 稀疏克隆: $repourl (分支: $branch, 目录: $@)"
  git clone --depth 1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl"
  cd "$repodir" && git sparse-checkout set "$@"
  mv -f "$@" ../package/
  cd .. && rm -rf "$repodir"
}

# --- 并行执行所有 Git 克隆操作 ---

# LuCI 主题
git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon &
git clone --depth 1 https://github.com/eamonxg/luci-theme-aurora package/luci-theme-aurora &

# PassWall & OpenClash 核心
git clone --depth 1 https://github.com/xiaorouji/openwrt-passwall-packages package/passwall-packages &
git clone --depth 1 https://github.com/xiaorouji/openwrt-passwall package/luci-app-passwall &
git clone --depth 1 https://github.com/xiaorouji/openwrt-passwall2 package/luci-app-passwall2 &
git clone --depth 1 https://github.com/vernesong/OpenClash package/luci-app-openclash &

# Mary LUCI App
git clone https://github.com/sirpdboy/luci-app-adguardhome package/luci-app-adguardhome &
git clone https://github.com/sirpdboy/luci-app-ddns-go package/luci-app-ddns-go &
git clone https://github.com/sirpdboy/luci-app-netdata package/luci-app-netdata &
git clone https://github.com/sirpdboy/luci-app-netspeedtest package/luci-app-netspeedtest &
git clone https://github.com/sirpdboy/luci-app-partexp package/luci-app-partexp &
git clone https://github.com/sirpdboy/luci-app-taskplan package/luci-app-taskplan &
git clone https://github.com/EasyTier/luci-app-easytier package/luci-app-easytier &
git clone https://github.com/VIKINGYFY/homeproxy package/homeproxy &
git clone -b v5 https://github.com/sbwml/luci-app-mosdns package/luci-app-mosdns &
git clone https://github.com/sbwml/luci-app-quickfile package/luci-app-quickfile &
git clone https://github.com/nikkinikki-org/OpenWrt-momo package/luci-app-momo &
git clone https://github.com/nikkinikki-org/OpenWrt-nikki package/luci-app-nikki &

# 其他工具和插件
git clone https://github.com/VIKINGYFY/packages package/vikingyfy-packages &
git clone https://github.com/sbwml/packages_lang_golang package/lang_golang & # <-- 修改为克隆到 package/ 目录
git clone https://github.com/sbwml/luci-app-openlist2 package/luci-app-openlist2 &
git clone https://github.com/gdy666/luci-app-lucky package/luci-app-lucky &
git clone https://github.com/tty228/luci-app-wechatpush package/luci-app-wechatpush &
git clone https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter &
git clone https://github.com/lwb1978/openwrt-gecoosac package/openwrt-gecoosac &
git clone https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led &
git clone https://github.com/asvow/luci-app-tailscale package/luci-app-tailscale &
git clone https://github.com/lmq8267/luci-app-vnt package/luci-app-vnt &
git clone https://github.com/kenzok8/small-package package/small &

# 等待所有后台克隆任务完成
echo "  -> 等待所有克隆任务完成..."
wait

# --- 4. 移动稀疏克隆的包并设置权限 ---
echo "-> 4. 处理稀疏克隆的包并设置权限..."
# 移动稀疏克隆的包
git_sparse_clone ariang https://github.com/laipeng668/packages net/ariang
git_sparse_clone frp https://github.com/laipeng668/packages net/frp
git_sparse_clone frp https://github.com/laipeng668/luci applications/luci-app-frpc applications/luci-app-frps
git_sparse_clone main https://github.com/VIKINGYFY/packages luci-app-wolplus

# 设置可执行权限
chmod +x \
    package/luci-app-athena-led/root/etc/init.d/athena_led \
    package/luci-app-athena-led/root/usr/sbin/athena-led

echo "==============================================================================="
echo "自定义构建脚本执行完成。"
echo "==============================================================================="
