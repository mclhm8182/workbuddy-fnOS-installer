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

# ---------------------------------------------------------------- web-ui 补齐
#
# 背景（2026-11 实测）：
#   WB 5.6.2 的官方 deb **不再随包提供网关的网页界面**
#   （resources/app.asar.unpacked/cli/dist/web-ui/，5.5.6 时存在，13MB/895 个文件）。
#   网关找不到该目录时会退化成一张占位页：
#     "CodeBuddy Gateway / Web UI is not built. Use the API endpoints directly..."
#   —— 即装完能连上、但网页里什么都不是（GitHub issue #6）。
#
#   官方没有单独发布 web-ui 构件，CDN 上也没有其它平台包可借，
#   而唯一带 web-ui 的官方包是 5.5.6（5.6.0 起被移除）。
#
# 做法：从 5.5.6 的官方 deb 中**只抽取 web-ui 目录**补进 5.6.x 的安装树。
#   - web-ui 是纯前端静态资源，与架构无关（实测 x64/arm64 两包内该目录
#     逐字节相同），故 x64/arm64 共用同一份 donor URL；
#   - 与 5.6.2 后端的接口兼容性已实测：SPA 调用的 67 个 /api 端点
#     在 5.5.6 自带后端与 5.6.2 后端上响应**完全一致**（SAME=67 DIFF=0）；
#   - web-ui 在 deb 的 data.tar 中排第 88 位（很靠前），故用 HTTP Range
#     只取包头约 96MB 即可抽全，比下满 429MB 少传 ~78%。
#
# donor 版本固定为 5.5.6（最后一个带 web-ui 的官方版本）。
# 该 URL 里的构建号是历史事实，不会变；官方接口只提供最新版，
# 无法通过接口回溯指定版本，故此处硬编码。
WEBUI_DONOR_VERSION="5.5.6.38337834"
WEBUI_DONOR_BUILD="5f969292"
WEBUI_DONOR_URL="https://download.codebuddy.cn/workbuddy/saas/linux-x64-deb/WorkBuddy-linux-x64-deb-${WEBUI_DONOR_VERSION}-${WEBUI_DONOR_BUILD}.deb"
# 只需 deb 前缀（实测 84MB 足够覆盖 web-ui 全部条目，取 96MB 留余量）
WEBUI_RANGE_BYTES=100663296
# 期望抽出的文件数（5.5.6 实测 895），用于校验完整性
WEBUI_EXPECT_FILES=895

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
    if have_cmd ss >/dev/null 2>&1; then
        ss -lntp 2>/dev/null | grep ":${APP_PORT}[[:space:]]" \
            | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2
    elif have_cmd netstat >/dev/null 2>&1; then
        netstat -lntp 2>/dev/null | grep ":${APP_PORT}[[:space:]]" \
            | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2
    else
        return 1
    fi
}

# 端口是否处于 LISTEN 状态
#
# 三级回退：ss → netstat → /proc/net/tcp。
# 精简系统可能两个命令都没有，最后直接读内核的 /proc/net/tcp
# （local_address 里端口是十六进制，状态 0A 即 LISTEN）。
port_listening() {
    _port="$1"
    if have_cmd ss >/dev/null 2>&1; then
        ss -lnt 2>/dev/null | grep -q ":${_port}[[:space:]]"
        return $?
    fi
    if have_cmd netstat >/dev/null 2>&1; then
        netstat -lnt 2>/dev/null | grep -q ":${_port}[[:space:]]"
        return $?
    fi
    _hex=$(printf '%04X' "$_port" 2>/dev/null)
    [ -n "$_hex" ] || return 1
    awk -v want=":${_hex}" '
        FNR>1 { split($2, a, ":"); if (a[2] == want && $4 == "0A") found = 1 }
        END { exit(found ? 0 : 1) }
    ' /proc/net/tcp /proc/net/tcp6 2>/dev/null
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

# ---------------------------------------------------------------- web-ui 补齐实现
#
# 判定：安装树里是否已有可用的网页界面
web_ui_present() {
    [ -f "$1/index.html" ]
}

# 从官方 5.5.6 deb 中抽取 web-ui 目录
#
# $1 = 目标 web-ui 目录（会被清空后重建）
# $2 = 工作目录（存放下载的 deb 前缀）
#
# 流程：
#   1) HTTP Range 取 deb 前缀（CDN 支持 accept-ranges: bytes）
#   2) ar 取出 data.tar.xz —— 注意：前缀文件不是完整 ar，GNU ar 会报
#      "不是有效的归档文件"，但仍会把成员数据写到 stdout，故不能靠退出码判断；
#   3) xz -dc | tar 解出 web-ui —— xz 在流被截断时报"输入意外结束"，
#      但已解出的部分完整可用，同样不能靠退出码判断；
#   4) 用文件数 + index.html 校验结果，不合格则报错退出。
extract_web_ui() {
    _dest="$1"
    _work="$2"

    # ar / xz 是解包 deb 前缀所必需
    have_cmd ar || { warn "系统缺少 ar，无法补齐网页界面"; return 1; }
    have_cmd xz || { warn "系统缺少 xz，无法补齐网页界面"; return 1; }

    _prefix="$_work/webui-donor.deb"
    _stage="$_work/webui-stage"

    rm -rf "$_stage" "$_prefix"
    mkdir -p "$_stage" || return 1

    # --- 1) 下载前缀 ---
    info "补齐网页界面：下载官方 ${WEBUI_DONOR_VERSION} 的 web-ui 资源"
    log "donor URL: $WEBUI_DONOR_URL"
    log "Range: bytes=0-$((WEBUI_RANGE_BYTES - 1))"

    if have_cmd curl; then
        curl -fL --connect-timeout 20 --retry 2 \
             -r "0-$((WEBUI_RANGE_BYTES - 1))" \
             -o "$_prefix" "$WEBUI_DONOR_URL" \
            || { warn "web-ui 资源下载失败"; return 1; }
    elif have_cmd wget; then
        # wget 用 --header 传 Range
        wget --timeout=30 --tries=2 \
             --header="Range: bytes=0-$((WEBUI_RANGE_BYTES - 1))" \
             -O "$_prefix" "$WEBUI_DONOR_URL" \
            || { warn "web-ui 资源下载失败"; return 1; }
    else
        warn "系统缺少 curl 或 wget，无法补齐网页界面"
        return 1
    fi

    [ -s "$_prefix" ] || { warn "web-ui 资源下载为空"; return 1; }
    log "已下载前缀：$(human_size "$(wc -c <"$_prefix")")"

    # --- 2) 解出 web-ui ---
    #
    # ar / xz 在流不完整时都会返回非零，但已解出的数据是好的，
    # 故这里不判断管道退出码，只看最终文件数与 index.html。
    ar p "$_prefix" data.tar.xz 2>/dev/null \
        | xz -dc 2>/dev/null \
        | tar -x -C "$_stage" --wildcards "*/cli/dist/web-ui/*" 2>/dev/null

    _found=$(find "$_stage" -type d -name web-ui 2>/dev/null | head -1)
    if [ -z "$_found" ]; then
        warn "未能从 donor 包中定位 web-ui 目录"
        return 1
    fi

    _count=$(find "$_found" -type f 2>/dev/null | wc -l | tr -d ' ')
    log "抽出的 web-ui 文件数：$_count（期望 ${WEBUI_EXPECT_FILES}）"

    if [ "$_count" -lt 100 ]; then
        warn "web-ui 文件数异常（$_count），判定为不完整"
        return 1
    fi
    if [ ! -f "$_found/index.html" ]; then
        warn "web-ui 缺少 index.html，判定为不完整"
        return 1
    fi

    # --- 3) 落到目标位置 ---
    rm -rf "$_dest"
    mkdir -p "$_dest" || return 1
    cp -a "$_found/." "$_dest/" || return 1
    chmod -R u+rwX,go+rX "$_dest" 2>/dev/null || true

    _final=$(find "$_dest" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ ! -f "$_dest/index.html" ] || [ "$_final" -lt 100 ]; then
        warn "web-ui 落地后校验失败（$_final 个文件）"
        return 1
    fi

    ok "网页界面资源就绪（$_final 个文件）"
    log "web-ui 安装位置: $_dest"

    rm -rf "$_stage" "$_prefix"
    return 0
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