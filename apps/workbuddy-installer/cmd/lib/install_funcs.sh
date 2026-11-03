#!/bin/sh
# install_funcs.sh — 安装期使用的函数定义
# SPDX-License-Identifier: MIT
#
# 本文件属于 workbuddy-fnOS-installer（第三方安装器），
# 与 WorkBuddy 官方无隶属关系。
#
# 这些函数由 install_init 在**顶层** source（. install_funcs.sh），
# 不能定义在 install_init 的某个分支里 —— 否则走“已是最新版本、跳过解包”
# 那条路径时函数根本不存在，调用会静默失败（command not found）。
# 历史上就因此出现过“启动脚本刷新失败”“网页界面未补齐”等现象。
#
# 依赖 common.sh 中的变量与工具函数（APP_DATA / APP_DIR / APP_PORT /
# ok / warn / info / have_cmd 等），由 install_init 先 source common.sh。


_write_fallback_scripts() {
    _dir="$1"

    # --- 定位 app 目录（含 cli/bin/codebuddy 的那一层）---
    _appdir=""
    for pat in \
        "$_dir"/root/opt/apps/* \
        "$_dir"/opt/apps/* \
        "$_dir"/root/opt/* \
        "$_dir"/opt/*; do
        [ -d "$pat" ] || continue
        if [ -x "$pat/resources/app.asar.unpacked/cli/bin/codebuddy" ]; then
            _appdir="$pat"
            break
        fi
    done

    # 兜底：全局搜索该入口文件
    if [ -z "$_appdir" ]; then
        _cli=$(find "$_dir" -type f -path '*resources/app.asar.unpacked/cli/bin/codebuddy' \
               2>/dev/null | head -1)
        [ -n "$_cli" ] && _appdir="${_cli%/resources/app.asar.unpacked/cli/bin/codebuddy}"
    fi

    if [ -z "$_appdir" ]; then
        err "未能在 $_dir 中定位 WorkBuddy CLI 入口"
        log "（期望路径 */resources/app.asar.unpacked/cli/bin/codebuddy）"
        log "解包顶层："
        log "$(ls -la "$_dir" 2>/dev/null)"
        log "opt 结构："
        log "$(ls -la "$_dir/opt" 2>/dev/null)"
        log "root 结构："
        log "$(ls -la "$_dir/root" 2>/dev/null)"
        return 1
    fi

    # Node 运行时目录（若存在则加入 PATH）
    _nodedir="$_appdir/resources/runtime/node/bin"

    info "定位到 CLI 入口：$_appdir"
    log "app 目录: $_appdir"

    if [ ! -x "$_nodedir/node" ]; then
        warn "未找到内置 Node 运行时（$_nodedir/node），将依赖系统 node"
    fi

    # --- 生成启动脚本 ---
    #
    # 逻辑与用户在 1.1 上验证可用的方案一致：
    #   HOME/TMPDIR 指向安装目录（避免污染系统家目录）
    #   PATH 加入自带 node
    #   NODE_OPTIONS 限制 V8 堆预算，配合 cgroup 防止 OOM
    #
    # 访问认证（重点）：
    #   CodeBuddy 网关**没有"首次设置密码"的流程**，它只认"用终端打印的密码登录"，
    #   或在settings.json 里设 gateway.auth。因此给用户两个选择：
    #
    #   AUTH_MODE=password -> 随机生成密码存ACCESS_PASS，入口 url 带 ?password=
    #   AUTH_MODE=none     -> 不需要密码，打开即用（默认）
    #
    #   用 AUTH_MODE 文件控制，用户可随时改并重启，无需重装：
    #       echo password > $BASE/AUTH_MODE   开启
    #       echo none     > $BASE/AUTH_MODE   关闭
    cat >"$_dir/start.sh" <<EOS
#!/bin/bash
# WorkBuddy 服务启动脚本（由第三方安装器生成，非官方文件）
# 使用官方内置 CLI 的网关模式提供服务，无需图形环境。

BASE="\$(cd "\$(dirname "\$0")" && pwd)"
APPDIR="$_appdir"

# 数据与临时目录就地放置，避免污染系统目录
export HOME="\$BASE/home"
export TMPDIR="\$BASE/tmp"
mkdir -p "\$HOME" "\$TMPDIR"

# ---------------------------------------------------------------------
# 身份认证 / 登录（重要）
#
#   WorkBuddy 网关的网页登录使用腾讯 SSO（copilot.tencent.com）扫码。
#   流程由网关主动向外轮询腾讯 SSO 完成账号绑定，因此：
#     - 不需要把网关暴露到公网，也不需要任何反向代理 / 隧道；
#     - 不依赖 CODEBUDDY_BASE_URL（该变量是模型与 Remote Control 的 API
#       地址，设置为局域网地址反而会破坏模型调用，切勿设置）。
#
#   只要 NAS 能访问外网（copilot.tencent.com、tencent.sso.copilot.tencent.com），
#   普通用户在 fnOS 门户打开 WorkBuddy 后扫码即可登录并绑定账号，
#   对话历史将随账号持久化（解决“换窗口历史丢失”问题）。
#
#   访问鉴权见下方 AUTH_MODE；写入 $BASE/AUTH_MODE=password 可启用密码。
# ---------------------------------------------------------------------
# 使用官方自带的 Node 运行时
[ -d "$_nodedir" ] && export PATH="$_nodedir:\$PATH"

# ---------------------------------------------------------------------
# 访问认证
#
#   AUTH_MODE=password  启用密码认证，密码见ACCESS_PASS 文件
#   AUTH_MODE=none      不需要密码，局域网/Tailnet 内可直接访问（默认）
#
# 需要密码时切换（重启后生效）：
#   echo password > \$BASE/AUTH_MODE
#   cat \$BASE/ACCESS_PASS
# ---------------------------------------------------------------------
AUTH_MODE="\$(cat "\$BASE/AUTH_MODE" 2>/dev/null || echo none)"

if [ "\$AUTH_MODE" = "password" ]; then
    ACCESS_PASS_FILE="\$BASE/ACCESS_PASS"
    if [ ! -s "\$ACCESS_PASS_FILE" ]; then
        head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 16 > "\$ACCESS_PASS_FILE"
        chmod 600 "\$ACCESS_PASS_FILE"
    fi
    export CODEBUDDY_GATEWAY_AUTH=password
    export CODEBUDDY_GATEWAY_PASSWORD="\$(cat "\$ACCESS_PASS_FILE")"
else
    export CODEBUDDY_GATEWAY_AUTH=none
fi

# ---------------------------------------------------------------------
# 内存预算
#
# V8 堆上限需按机器实际内存自适应：
#   2GB 机器（如飞牛 OEC）→ 768MB，避免 V8 把系统内存吃光导致 OOM
#   8GB 以上            → 1024MB
#   16GB 以上           → 1536MB
#
# Node 自身开销约在堆之外再占 100-200MB，故总占用约为堆上限的 1.3 倍。
# 取得总内存后按比例推算，可用 MEM_TOTAL_MB 覆盖。
# ---------------------------------------------------------------------
_mem_total_mb() {
    if [ -n "\${MEM_TOTAL_MB:-}" ]; then
        echo "\${MEM_TOTAL_MB}"; return
    fi
    _t=""
    # 来源1：/proc/meminfo（多数 Linux 可读；字段 \$2 为 MemTotal 的 KB 数）
    _t=\$(awk '/^MemTotal:/{printf "%d", \$2/1024}' /proc/meminfo 2>/dev/null)
    # 来源2：free -m（部分精简系统无 /proc/meminfo 时兜底）
    if [ -z "\$_t" ] && command -v free >/dev/null 2>&1; then
        _t=\$(free -m 2>/dev/null | awk '/^Mem:/{print \$2}')
    fi
    # 来源3：vmstat -s
    if [ -z "\$_t" ] && command -v vmstat >/dev/null 2>&1; then
        _t=\$(vmstat -s 2>/dev/null | awk '/total memory/{printf "%d", \$1/1024}')
    fi
    # 兜底 + 强制为正整数，避免 [ ] 整数比较报 "integer expression expected"
    case "\$_t" in ''|*[!0-9]*) _t=1536 ;; esac
    echo "\$_t"
}

_total=\$(_mem_total_mb)
if [ "\$_total" -lt 3072 ]; then
    HEAP_MB=768
elif [ "\$_total" -lt 12288 ]; then
    HEAP_MB=1024
else
    HEAP_MB=1536
fi

export NODE_OPTIONS="--max-old-space-size=\$HEAP_MB"
echo "WorkBuddy: 机器内存 \${_total}MB，V8 堆上限 \${HEAP_MB}MB"

# ---------------------------------------------------------------------
# 运行时 bundle 选择（兼容 WB 5.6.x 的新包结构）
#
#   WB 5.6.2 起，官方 deb 不再随包提供"完整桌面 bundle"
#   （resources/app.asar.unpacked/cli/dist/codebuddy.js），
#   而 CLI 入口默认仍执行 require('../dist/codebuddy')，
#   直接抛 MODULE_NOT_FOUND 崩溃 —— 表现为应用"装完就打不开"、
#   在应用中心反复启用/退出（GitHub issue #2 / #4）。
#
#   官方为此提供了 CODEBUDDY_FORCE_HEADLESS_BUNDLE 开关，指向随包提供的
#   cli/dist/codebuddy-headless.js。NAS 网关正是 headless 场景，
#   且该 bundle 体积更小（12MB vs 20MB），更适合小内存机型。
#
#   仅在"完整 bundle 不存在"时才启用；旧版本（如 5.5.6）行为保持不变。
#   若将来 headless bundle 也改名/移除，则退到 lite-wb bundle。
# ---------------------------------------------------------------------
_CLI_DIST="\$APPDIR/resources/app.asar.unpacked/cli/dist"
if [ ! -f "\$_CLI_DIST/codebuddy.js" ]; then
    if [ -f "\$_CLI_DIST/codebuddy-headless.js" ]; then
        export CODEBUDDY_FORCE_HEADLESS_BUNDLE=1
        echo "WorkBuddy: 检测到新版包结构（无完整 bundle），启用 headless bundle"
    elif [ -f "\$_CLI_DIST/codebuddy-lite-wb.mjs" ]; then
        export CODEBUDDY_FORCE_LITE_WB_BUNDLE=1
        echo "WorkBuddy: 检测到新版包结构，启用 lite-wb bundle"
    fi
fi

# ---------------------------------------------------------------------
# 网页界面（web-ui）
#
#   WB 5.6.x 的官方 deb 不再随包提供 cli/dist/web-ui/，
#   网关找不到它时会退化成占位页（"Web UI is not built"），
#   表现为装完能连上 8090、但网页里只有一段 API 文档说明。
#
#   安装器会从官方 5.5.6 包中把这份静态资源补到 dist/web-ui/，
#   这里显式告知网关其位置（官方支持该环境变量），
#   双保险：即使包内目录查找顺序变化也能正确找到。
# ---------------------------------------------------------------------
if [ -f "\$_CLI_DIST/web-ui/index.html" ]; then
    export CODEBUDDY_WEB_UI_ROOT="\$_CLI_DIST/web-ui"
    echo "WorkBuddy: 网页界面资源已就绪"
fi

exec "\$APPDIR/resources/app.asar.unpacked/cli/bin/codebuddy" \\
    --serve --host 0.0.0.0 --port ${APP_PORT}
EOS
    chmod +x "$_dir/start.sh" || return 1

    # 默认不启用密码（开箱即用）；仅在尚未设置时写入，避免覆盖用户已切换的密码模式
    if [ ! -s "$_dir/AUTH_MODE" ]; then
        printf 'none\n' >"$_dir/AUTH_MODE"
    fi

    # --- 生成开机自启用的包装脚本 ---
    cat >"$_dir/login_runner.sh" <<EOS
#!/bin/sh
# WorkBuddy 自启包装脚本（由第三方安装器生成，非官方文件）
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
nohup "\$DIR/start.sh" >>"\$DIR/run.log" 2>&1 &
EOS
    chmod +x "$_dir/login_runner.sh" || return 1

    # --- 供 fnOS main start 调用的入口 ---
    ln -sf start.sh "$_dir/run.sh" 2>/dev/null || true

    log "已生成启动脚本"
    hint "CLI 入口：$_appdir"
    return 0
}


# 确保网关的网页界面（web-ui）可用
#
# 背景（2026-11 实测）：
#   WB 5.6.2 的官方 deb **不再随包提供** cli/dist/web-ui/，
#   网关找不到它时会退化成占位页：
#     "CodeBuddy Gateway — Web UI is not built. Use the API endpoints directly"
#   表现为：装完能连上 8090，但网页里只有一段 API 文档说明，什么都点不了。
#   （用户反馈，暂无对应 issue）
#
#   5.6.0 起官方就移除了该目录，唯一仍带它的官方版本是 5.5.6。
#   故从 5.5.6 的官方包中只抽取 web-ui 静态资源补齐。
#
# 兼容性已实测：5.5.6 的 web-ui 与 5.6.2 后端完全兼容 ——
#   SPA 调用的 67 个 /api 端点在两侧响应逐条一致（SAME=67 DIFF=0）。
#
# $1 = 安装目录（$APP_DATA）
_ensure_web_ui() {
    _datadir="$1"

    # --- 定位 CLI 的 dist 目录 ---
    _cli_dist=""
    for _cand in \
        "$_datadir"/opt/WorkBuddy/resources/app.asar.unpacked/cli/dist \
        "$_datadir"/opt/apps/*/resources/app.asar.unpacked/cli/dist \
        "$_datadir"/root/opt/WorkBuddy/resources/app.asar.unpacked/cli/dist; do
        [ -d "$_cand" ] || continue
        _cli_dist="$_cand"
        break
    done
    if [ -z "$_cli_dist" ]; then
        _cli=$(find "$_datadir" -type d -path '*app.asar.unpacked/cli/dist' 2>/dev/null | head -1)
        [ -n "$_cli" ] && _cli_dist="$_cli"
    fi

    if [ -z "$_cli_dist" ]; then
        warn "未找到 CLI 资源目录，跳过网页界面补齐"
        return 1
    fi

    # 官方包自带（未来版本若恢复）→ 无需处理
    if web_ui_present "$_cli_dist/web-ui"; then
        ok "官方包已自带网页界面"
        return 0
    fi

    warn "官方包未包含网页界面（5.6.x 起被移除），正在补齐"
    _wu_work="$(dirname "$_datadir")/.workbuddy-webui-$(rand_suffix)"
    if ! mkdir -p "$_wu_work" 2>/dev/null; then
        _wu_work="/tmp/.workbuddy-webui-$(rand_suffix)"
        mkdir -p "$_wu_work" 2>/dev/null || return 1
    fi

    if extract_web_ui "$_cli_dist/web-ui" "$_wu_work"; then
        ok "网页界面已补齐"
        _rc=0
    else
        warn "网页界面补齐失败；网关仍可提供 API，但网页端会显示占位页"
        _rc=1
    fi

    rm -rf "$_wu_work" 2>/dev/null || true
    return $_rc
}


# 确保认证相关文件存在
#
# 默认 AUTH_MODE=none（无需密码，打开即用）。
# 用户可随时改为 password 以启用访问认证：
#     echo password > /vol1/1000/app_workbuddy/AUTH_MODE
#     cat /vol1/1000/app_workbuddy/ACCESS_PASS
_ensure_auth_files() {
    _dir="$1"
    # 认证模式：默认 none
    [ -f "$_dir/AUTH_MODE" ] || printf 'none\n' >"$_dir/AUTH_MODE"

    # 若已启用密码但密码文件缺失，补生成一个
    if [ "$(cat "$_dir/AUTH_MODE" 2>/dev/null || echo none)" = "password" ]; then
        if [ ! -s "$_dir/ACCESS_PASS" ]; then
            head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 16 \
                >"$_dir/ACCESS_PASS"
            chmod 600 "$_dir/ACCESS_PASS"
            info "已生成访问密码：$(cat "$_dir/ACCESS_PASS")"
        fi
    fi
    return 0
}


# 写入 fnOS 桌面入口配置
#
# 关键点：网关开启了密码认证，iframe 请求若不带凭证会返回空白页/黑屏。
# 因此 url 必须带上 ?password=<网关密码>。
#
# 路径说明（fnOS 实测）：
#   fpk 内是 app/ui/config，但 fnOS 应用中心解包 app.tgz 后，
#   ui/ 与 config/ **直接落在应用注册目录顶层**，即：
#     /usr/local/apps/@appcenter/<appid>/ui/config
#   不是一个 app/ui/ 子目录。各版本结构可能有差异，故依次探测。
_write_desktop_entry() {
    _datadir="$1"

    # 无密码模式（默认）：url 不带参数，打开即用
    if [ "$(cat "$_datadir/AUTH_MODE" 2>/dev/null || echo none)" != "password" ]; then
        _pw=""
    else
        _pw=$(cat "$_datadir/ACCESS_PASS" 2>/dev/null || echo "")
    fi

    # 候选位置：应用注册目录优先（fnOS 实际读取处），其次旧结构
    _cands="
$APP_DIR/ui/config
$APP_DIR/app/ui/config
$_datadir/app/ui/config
$_datadir/ui/config
"

    _target=""
    for c in $_cands; do
        if [ -d "$(dirname "$c")" ]; then
            _target="$c"
            break
        fi
    done

    # 都没找到时，在应用注册目录下创建 ui/（首次安装可能如此）
    if [ -z "$_target" ] && [ -d "$APP_DIR" ]; then
        mkdir -p "$APP_DIR/ui/images" 2>/dev/null || true
        if [ -d "$APP_DIR/ui" ]; then
            _target="$APP_DIR/ui/config"
        fi
    fi

    if [ -z "$_target" ]; then
        warn "未找到桌面入口配置目录，跳过"
        log "尝试过的路径：$_cands"
        log "APP_DIR=$APP_DIR是否存在：$([ -d "$APP_DIR" ] && echo yes || echo no)"
        return 1
    fi

    cat >"$_target" <<EOC
{
    ".url": {
        "${APP_ID}.main": {
            "allUsers": false,
            "control": {
                "accessPerm": "readonly"
            },
            "icon": "images/icon_{0}.png",
            "port": "${APP_PORT}",
            "protocol": "http",
            "title": "WorkBuddy",
            "type": "iframe",
            "url": "/${_pw:+?password=${_pw}}"
        }
    }
}
EOC
    log "已写入桌面入口配置：$_target"
    log "url 含网关密码，已带 control.accessPerm"
    return 0
}
