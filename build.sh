#!/bin/sh
# build.sh — 构建 x86 与 arm 两个平台的 fpk
# SPDX-License-Identifier: MIT
#
# 第三方安装器，与 WorkBuddy 官方无隶属关系。
#
# 用法:
#   ./build.sh                      # 自动获取 fnpack 后构建
#   FNPACK=/path/to/fnpack ./build.sh
#
# 产物文件名必须与应用 ID 一致（fnwb.workbuddy），
# 否则 fnOS 报"FPK 不存在"。

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_SRC="$ROOT_DIR/apps/workbuddy-installer"
DIST="$ROOT_DIR/dist"

FNPACK_VERSION="1.2.3"
# fnOS 官方工具 CDN（与 AUR fnpack-bin 包一致的来源）
FNPACK_BASE="https://static2.fnnas.com/fnpack"
FNPACK_LOCAL="$ROOT_DIR/.fnpack/fnpack"

# fnOS platform 取值 -> (宿主平台, 下载用的架构串)
# 注意：fnpack build 无平台参数，平台由 manifest 的 platform 字段决定，
# 故双架构需分别改写 manifest 后各打包一次。
PLATFORMS="x86 arm"
HOSTARCH_darwin_arm64="darwin-arm64"
HOSTARCH_darwin_x64="darwin-amd64"
HOSTARCH_linux_x64="linux-amd64"

APP_NAME="fnwb.workbuddy"
APP_VERSION="1.2.2"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_GRN='\033[0;32m'; C_YEL='\033[0;33m'; C_BLU='\033[0;34m'; C_RST='\033[0m'
else
    C_GRN=''; C_YEL=''; C_BLU=''; C_RST=''
fi
info() { printf "${C_BLU}::${C_RST} %s\n" "$*"; }
ok()   { printf "${C_GRN}OK${C_RST} %s\n" "$*"; }
warn() { printf "${C_YEL}!!${C_RST} %s\n" "$*"; }
die()  { printf "XX %s\n" "$*" >&2; exit 1; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- 前置检查

for c in tar gzip sha256sum sed awk; do
    have_cmd "$c" || die "缺少必要命令：$c"
done

[ -d "$APP_SRC" ] || die "应用目录不存在：$APP_SRC"
[ -f "$APP_SRC/manifest" ] || die "缺少 manifest"

# ---------------------------------------------------------------- 图标

if [ "${SKIP_ICONS:-0}" != "1" ]; then
    if have_cmd python3; then
        info "生成图标"
        (cd "$ROOT_DIR" && python3 make_icons.py)
    else
        warn "未找到 python3，沿用仓库中已有图标"
    fi
fi

# ---------------------------------------------------------------- fnpack

detect_host_arch() {
    _os=$(uname -s)
    _m=$(uname -m)
    case "$_os" in
        Darwin) [ "$_m" = "arm64" ] && echo "darwin-arm64" || echo "darwin-amd64" ;;
        Linux)  [ "$_m" = "x86_64" ] && echo "linux-amd64" || echo "linux-arm64" ;;
        *)      echo "" ;;
    esac
}

get_fnpack() {
    # 优先使用显式指定
    if [ -n "${FNPACK:-}" ] && [ -x "$FNPACK" ]; then
        ok "使用 FNPACK=$FNPACK"
        FNPACK_BIN="$FNPACK"
        return 0
    fi
    # 其次使用 .fnpack/fnpack
    if [ -x "$FNPACK_LOCAL" ]; then
        ok "使用本地 fnpack：$FNPACK_LOCAL"
        FNPACK_BIN="$FNPACK_LOCAL"
        return 0
    fi
    # 再次使用 PATH 中的
    if have_cmd fnpack; then
        ok "使用系统 fnpack"
        FNPACK_BIN="$(command -v fnpack)"
        return 0
    fi
    # 最后从官方 CDN 获取
    HOSTA=$(detect_host_arch)
    [ -n "$HOSTA" ] || die "无法识别宿主平台：$(uname -s)/$(uname -m)
fnpack 官方未提供该平台版本。请在 x86_64 Linux、arm64 Linux 或 macOS 上构建。"

    local_fn="fnpack-${FNPACK_VERSION}-${HOSTA}"
    url="${FNPACK_BASE}/${local_fn}"
    info "从 fnOS 官方 CDN 获取 fnpack：$url"
    mkdir -p "$(dirname "$FNPACK_LOCAL")"

    if have_cmd curl; then
        curl -fL --connect-timeout 20 --retry2 -o "$FNPACK_LOCAL" "$url" \
            || die "下载失败：$url"
    elif have_cmd wget; then
        wget --timeout=20 --tries=2 -O "$FNPACK_LOCAL" "$url" \
            || die "下载失败：$url"
    else
        die "需要 curl 或 wget"
    fi

    chmod +x "$FNPACK_LOCAL"

    # 校验确为可执行的官方工具
    if ! "$FNPACK_LOCAL" --help >/dev/null 2>&1; then
        rm -f "$FNPACK_LOCAL"
        die "下载的文件无法执行，可能已损坏。已清理，请重试或手动放置 fnpack。"
    fi

    VER_OUT=$("$FNPACK_LOCAL" --help 2>&1 | sed -n 's/^Version[[:space:]]*//p' | head -1)
    ok "fnpack 就绪（$VER_OUT）"
    [ "$VER_OUT" = "$FNPACK_VERSION" ] || \
        warn "版本为 $VER_OUT，与期望的 $FNPACK_VERSION 不同"
    FNPACK_BIN="$FNPACK_LOCAL"
}

get_fnpack

# ---------------------------------------------------------------- 打包

mkdir -p "$DIST"

for PLAT in $PLATFORMS; do
    WORK="$DIST/.build-${PLAT}"
    PKGNAME="${APP_NAME}_${APP_VERSION}_${PLAT}"

    info "构建 ${PKGNAME}.fpk ..."
    rm -rf "$WORK"
    mkdir -p "$WORK/${APP_NAME}"

    cp -r "$APP_SRC/." "$WORK/${APP_NAME}/"

    # 按平台改写 manifest 的 platform 字段（fnpack 依此决定产物后缀）
    sed -i.bak "s/^platform *=.*/platform = ${PLAT}/" "$WORK/${APP_NAME}/manifest"
    rm -f "$WORK/${APP_NAME}/manifest.bak"
    grep -q "^platform *= *${PLAT}$" "$WORK/${APP_NAME}/manifest" \
        || die "manifest 的 platform 字段改写失败"
    ok "manifest platform=${PLAT}"

    # fnpack build -d <应用源码目录>
    (cd "$WORK" && "$FNPACK_BIN" build -d "${APP_NAME}") \
        || die "fnpack 构建失败（平台 $PLAT）"

    # 收集产物并规范命名
    produced=""
    for f in "$WORK"/*.fpk "$WORK"/"$APP_NAME"/*.fpk; do
        [ -f "$f" ] && produced="$f"
    done
    [ -n "$produced" ] || die "未找到产物 fpk（平台 $PLAT）"

    mv "$produced" "$DIST/${PKGNAME}.fpk"
    ok "产物：dist/${PKGNAME}.fpk"
    rm -rf "$WORK"
done

# ---------------------------------------------------------------- 校验和

info "生成 SHA256SUMS"
( cd "$DIST" && sha256sum ./*.fpk 2>/dev/null | sed 's|\./||' > SHA256SUMS ) \
    || ( cd "$DIST" && sha256sum *.fpk > SHA256SUMS )
ok "dist/SHA256SUMS"

# ---------------------------------------------------------------- 产物自检
#
# fpk 格式为 tar.gz（内含 manifest / config / app.tgz / ICON*.PNG），
# 不是 zip，故用 tar 检查。

info "校验产物"
for f in "$DIST"/*.fpk; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    case "$base" in
        "${APP_NAME}_${APP_VERSION}_x86.fpk") PLAT=x86 ;;
        "${APP_NAME}_${APP_VERSION}_arm.fpk") PLAT=arm ;;
        *) warn "产物名异常：$base（应为 ${APP_NAME}_${APP_VERSION}_<plat>.fpk）"; continue ;;
    esac

    LIST=$(tar -tzf "$f" 2>/dev/null || true)
    if [ -z "$LIST" ]; then
        warn "$base 无法读取（文件可能损坏）"
        continue
    fi

    # 必需文件检查
    MISSING=""
    for must in manifest cmd/main cmd/install_init config/privilege ICON.PNG ICON_256.PNG; do
        echo "$LIST" | grep -qx "$must" || MISSING="$MISSING $must"
    done
    if [ -n "$MISSING" ]; then
        warn "$base 缺少必需文件：$MISSING"
    fi

    # platform 字段核对
    GOT_PLAT=$(tar -xzOf "$f" manifest 2>/dev/null \
        | sed -n 's/^platform[[:space:]]*=[[:space:]]*//p' | head -1 | tr -d '[:space:]')
    if [ "$GOT_PLAT" = "$PLAT" ]; then
        ok "$base  platform=$PLAT  $(ls -lh "$f" | awk '{print $5}')"
    else
        warn "$base 的 manifest platform=$GOT_PLAT，与预期 $PLAT 不符"
    fi
done

# ---------------------------------------------------------------- 汇总

printf "\n"
printf "  构建完成\n"
printf "  %s\n" "--------------------------------------------"
for f in "$DIST"/*.fpk; do
    [ -f "$f" ] || continue
    printf "  %-34s %s\n" "$(basename "$f")" "$(du -h "$f" | awk '{print $1}')"
done
printf "  %s\n" "--------------------------------------------"
printf "\n  安装：将 .fpk 拖入 fnOS 应用中心 → 手动安装\n"
printf "  架构：x86 包用于 Intel/AMD，arm 包用于 OEC 等 ARM 机型\n\n"

cat <<EOF
  合规说明：本仓库不包含 WorkBuddy 的任何二进制文件。
  fpk 内仅有安装脚本，安装时从官方地址获取官方 .deb。
  本工具与 WorkBuddy 官方无隶属关系。
EOF