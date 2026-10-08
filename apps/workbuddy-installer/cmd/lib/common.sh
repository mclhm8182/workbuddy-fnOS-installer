#!/bin/sh
# common.sh — 公共函数库
# SPDX-License-Identifier: MIT
#
# 本文件属于 workbuddy-fnOS-installer（第三方安装器），
# 与 WorkBuddy 官方无隶属关系。

# ---------------------------------------------------------------- 应用标识

# 应用 ID / 包名。改动这里需同步改 build.sh 与 manifest。
APP_ID="fnwb.workbuddy"
APP_TITLE="WorkBuddy"
# fnOS 要求桌面入口形如 <appName>.main
APP_LAUNCH_NAME="${APP_ID}.main"

# ---------------------------------------------------------------- 路径布局
#
# 采用"注册与程序本体分离"布局：
#   应用注册（脚本/图标/入口）→ /usr/local/apps/@appcenter/fnwb.workbuddy/  系统分区
#   程序本体（约 1.3GB）      → /vol1/1000/app_workbuddy/   存储池
#
# 理由：程序解包后约 1.3GB 且可能继续增长，系统分区不适合放这种体积。
# 这也是 fnOS 上Docker 类应用放置程序数据的通行做法。

# 应用注册目录（fnOS 应用中心安装时创建，cmd/ app/ 都在其下）
APP_DIR="/usr/local/apps/@appcenter/${APP_ID}"

# 程序本体根目录（运行期数据也放这里）
APP_DATA="${WORKBUDDY_APP_DIR:-/vol1/1000/app_workbuddy}"

# 安装期日志目录（由 fnOS 注入 TRIM_TEMP_LOGFILE 时优先用它）
LOG_FILE="${TRIM_TEMP_LOGFILE:-/tmp/workbuddy-installer.log}"

# 服务端口，与 app/ui/config 中的 port 保持一致
APP_PORT="8090"

# ---------------------------------------------------------------- 下载源
#
# 官方更新接口（腾讯自有CDN），动态返回最新版地址。
# 架构由 uname -m 映射到 platform 通道名。
# 参考：https://www.codebuddy.ai /官方文档提及 copilot.tencent.com 更新接口
UPDATE_API="https://copilot.tencent.com/v2/update?platform="

# 架构 -> 官方 platform 通道
platform_channel() {
    case "$1" in
        amd64) echo "workbuddy-linux-x64-deb" ;;
        arm64) echo "workbuddy-linux-arm64-deb" ;;
        *)     echo "" ;;
    esac
}

# ---------------------------------------------------------------- 日志输出
#
# fnOS 会收集 TRIM_TEMP_LOGFILE，日志同时写终端与文件。

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RED='\033[0;31m'; C_GRN='\033[0;32m'
    C_YEL='\033[0;33m'; C_BLU='\033[0;34m'
    C_DIM='\033[2m';    C_RST='\033[0m'
else
    C_RED=''; C_GRN=''; C_YEL=''; C_BLU=''; C_DIM=''; C_RST=''
fi

_log_file_write() {
    # 无TRIM_TEMP_LOGFILE 时退化为无文件日志，避免权限问题
    [ -n "${TRIM_TEMP_LOGFILE:-}" ] || return 0
    printf '%s\n' "$1" >>"$TRIM_TEMP_LOGFILE" 2>/dev/null || true
}

info() { _m=":: $*"; printf "${C_BLU}%s${C_RST}\n" "$_m"; _log_file_write "$_m"; }
ok()   { _m="OK $*"; printf "${C_GRN}%s${C_RST}\n" "$_m"; _log_file_write "$_m"; }
warn() { _m="!! $*"; printf "${C_YEL}%s${C_RST}\n" "$_m" >&2; _log_file_write "$_m"; }
err()  { _m="XX $*"; printf "${C_RED}%s${C_RST}\n" "$_m" >&2; _log_file_write "$_m"; }
die()  { err "$*"; exit 1; }

step() { _m="==> $*"; printf "\n${C_BLU}%s${C_RST}\n" "$_m"; _log_file_write "$_m"; }
hint() { printf "${C_DIM}    %s${C_RST}\n" "$*"; _log_file_write "    $*"; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

require_root() {
    [ "$(id -u)" -eq 0 ] || die "需要 root 权限"
}

check_deps() {
    missing=""
    for c in "$@"; do
        have_cmd "$c" || missing="$missing $c"
    done
    [ -z "$missing" ] || die "缺少必要命令：$missing"
}

# ---------------------------------------------------------------- 架构

arch_deb_suffix() {
    case "$1" in
        x86_64|amd64)  echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *)             echo "" ;;
    esac
}

detect_arch() {
    arch_deb_suffix "$(uname -m)"
}

# ---------------------------------------------------------------- 磁盘

require_space_mb() {
    need_mb="$1"; target="$2"
    vol=$(df -Pm "$target" 2>/dev/null | awk 'NR==2{print $4}')
    [ -n "$vol" ] || return 0        # 目标不存在时跳过，交给后续 mkdir 报错
    [ "$vol" -ge "$need_mb" ] || die "可用空间不足：需要 ${need_mb}MB，仅剩 ${vol}MB
请先清理空间，或用 --install-dir 指定其他卷。"
    hint "可用空间 ${vol}MB，需要 ${need_mb}MB"
}

# ---------------------------------------------------------------- 进程管理

port_owner() {
    have_cmd ss >/dev/null 2>&1 || return 1
    ss -lntp 2>/dev/null | grep ":${APP_PORT}[[:space:]]" \
        | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2
}

is_running() {
    pid=$(port_owner) || return 1
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

stop_service() {
    is_running || return 0
    pid=$(port_owner)
    [ -n "$pid" ] || return 0

    info "停止服务（PID $pid）..."
    kill -TERM "$pid" 2>/dev/null || true
    i=0
    while [ $i -lt 20 ]; do
        kill -0 "$pid" 2>/dev/null || { ok "服务已停止"; return 0; }
        sleep 1; i=$((i + 1))
    done
    warn "优雅停止超时，强制结束"
    kill -KILL "$pid" 2>/dev/null || true
    sleep 2
    ok "服务已停止"
}

start_service() {
    runner="$APP_DATA/login_runner.sh"
    [ -f "$runner" ] || runner="$APP_DATA/start.sh"
    [ -f "$runner" ] || return 1

    chmod +x "$runner" 2>/dev/null || true
    nohup /bin/sh "$runner" >/dev/null 2>&1 &

    i=0
    while [ $i -lt 40 ]; do
        if is_running; then
            ok "服务已就绪：端口 ${APP_PORT}"
            return 0
        fi
        sleep 1; i=$((i + 1))
    done
    return 1
}

# ---------------------------------------------------------------- 杂项

human_size() {
    _b="${1:-0}"
    if [ "$_b" -ge 1048576 ] 2>/dev/null; then echo "$(( _b / 1048576 ))MB"
    elif [ "$_b" -ge 1024 ] 2>/dev/null; then echo "$(( _b / 1024 ))KB"
    else echo "${_b}B"; fi
}

rand_suffix() {
    if have_cmd openssl; then openssl rand -hex 6
    else awk 'BEGIN{srand();printf "%012x", rand()*4294967295*4294967295}'; fi
}

confirm() {
    [ -n "${ASSUME_YES:-}" ] && return 0
    if [ ! -t 0 ]; then
        warn "非交互环境下无法确认，已取消"
        return 1
    fi
    printf "%s [y/N] " "$1"
    read -r ans
    case "$ans" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}