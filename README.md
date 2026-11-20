# WorkBuddy 第三方 fnOS 安装器

面向飞牛 fnOS 的 **WorkBuddy 第三方安装器** —— 一个 fpk 包，**不含 WorkBuddy 任何二进制**，安装时从官方源获取官方 `.deb` 并解包为 fnOS 应用。

> [!IMPORTANT]
> 本项目是独立社区工具，与 WorkBuddy 官方无任何隶属、背书或合作关系；不包含官方二进制，安装时仅从官方公开渠道获取官方 deb，不修改、不重新打包。

简体中文 | [English](README_EN.md)

## 下载

从 [GitHub Releases](https://github.com/mclhm8182/workbuddy-fnOS-installer/releases/latest) 下载对应架构的安装包：

| 架构 | 安装包 |
| --- | --- |
| x86_64 | `fnwb.workbuddy_1.2.6_x86.fpk` |
| ARM64 / aarch64 | `fnwb.workbuddy_1.2.6_arm.fpk` |

对照 Release 的 `SHA256SUMS` 校验文件，不一致时重新下载：

```bash
sha256sum fnwb.workbuddy_1.2.6_x86.fpk
```
## 快速开始

1. 在 fnOS“应用中心”点击 **手动安装**。
2. 上传对应架构的 fpk，确认安装位置为「系统分区」。
3. 装完后桌面出现 WorkBuddy 图标，点击访问。

安装过程无需任何输入。**默认不需要密码**，点桌面图标直接进。

## 访问与登录

**默认不需要密码**（`AUTH_MODE=none`），局域网 / Tailnet 内设备直接可用。

如需密码，改 `AUTH_MODE` 并重启：

```bash
sudo sh -c 'echo password > /vol1/1000/app_workbuddy/AUTH_MODE'   # 启用
sudo cat /vol1/1000/app_workbuddy/ACCESS_PASS                    # 查看密码
sudo sh -c 'echo none > /vol1/1000/app_workbuddy/AUTH_MODE'      # 关闭
sudo pkill -f 'app_workbuddy.*codebuddy'
sudo sh -c 'cd /vol1/1000/app_workbuddy && setsid ./start.sh > run.log 2>&1 < /dev/null &'
```

> **安全提醒**：未启用密码时，局域网 / Tailnet 内任何设备都能直接使用你的 WorkBuddy（含读写文件、消耗 AI 额度）。若 NAS 暴露到不可信网络（端口转发、公网 IP），请务必启用密码。

**登录与历史**：打开后点击登录，用手机 App 扫码绑定 CodeBuddy 账号即可。绑定后对话历史随账号持久化，**跨窗口 / 设备不丢失**。该登录不依赖公网回跳，NAS 能出网即可完成。

## 工作区与端口（可自定义，且能随更新保留）

网关把**进程的工作目录**当作 workspace：网页打开时会据 workspace 建文件监听、跑 git status 与 file-changes checkpoint 扫描。若这个目录是 `/` 或包含超大目录（fnOS 的 `/fs/<uid>` 媒体库、云盘 FUSE 挂载等），扫描会同步阻塞事件循环 —— 端口仍在 LISTEN、TCP 能连上，但**页面永久无响应**。所以工作区必须是一个小而干净的目录。

### 安装时指定（推荐）

fnOS 应用中心是无人值守安装，所以用预置文件。安装前在 NAS 上放一个：

```bash
# 内容为 KEY=VALUE；下面三个位置任意一个都可识别
sudo tee /vol1/1000/app_workbuddy.install.conf >/dev/null <<'EOF'
WORKSPACE=/vol1/1000/myproject
PORT=8092
EOF
```

| 键 | 说明 |
| --- | --- |
| `WORKSPACE` | 绝对路径；必须存在或可创建。`/` 会被拒绝（会把网关卡死） |
| `PORT` | 要用的端口；被**别的**进程占用时安装会明确报错（不会偷偷改你的选择） |

也支持环境变量 `WORKBUDDY_WORKSPACE` / `WORKBUDDY_PORT`（优先级最高），以及 `WORKBUDDY_INSTALL_CONF=<路径>` 指定预置文件。

### 安装后修改

解析结果落在**程序数据目录**的 `instance.conf`：

```bash
cat /vol1/1000/app_workbuddy/instance.conf
# WORKSPACE=/vol1/1000/myproject
# PORT=8092

# 改完重启应用
sudo bash /var/apps/fnwb.workbuddy/cmd/main stop
sudo bash /var/apps/fnwb.workbuddy/cmd/main start
```

这是**升级/重装都不覆盖**的文件，所以安装时定的工作区与端口会一直继承下去 —— 换新版 fpk 只需要重装，不用重新配置。

### 端口自动检测

| 情况 | 行为 |
| --- | --- |
| 未指定端口，8090 空闲 | 用 8090 |
| 未指定端口，8090 被**本应用**占用（升级场景） | 沿用 8090 |
| 未指定端口，8090 被其它进程占用 | 自动向后找一个空闲端口（8091–8199），日志与安装结尾都会提示 |
| 指定了端口，但被别的进程占用 | **安装失败**并给出改法（不静默改动） |

`manifest` 的 `checkport` 已关闭，否则 8090 被占用时应用中心会在跑安装脚本前就拦下来。桌面入口的 `ui/config` 会按最终端口写入，点图标不会指错端口。

### 想继续用文件方式指定

也可以继续用 `WORKSPACE_DIR`（只写目录、单行）：优先级低于 `instance.conf`：

```bash
echo /vol1/1000/myproject > /vol1/1000/app_workbuddy/WORKSPACE_DIR
```


## 卸载

在应用中心直接卸载即可 —— 默认保留程序数据（`/vol1/1000/app_workbuddy`），便于重新启用。彻底清理（不可逆）：

```bash
sudo pkill -f 'app_workbuddy.*codebuddy'
sudo rm -rf /vol1/1000/app_workbuddy
```

## 故障排查

**桌面点击无反应 / 一直转圈**

```bash
ss -lntp | grep 8090                              # 端口是否在监听
sudo tail -40 /var/log/apps/fnwb.workbuddy.log     # 应用日志
sudo tail -40 /vol1/1000/app_workbuddy/run.log     # 服务运行日志
```

**“端口被占用”**：未指定端口时安装器会自动改用空口并提示实际端口；显式指定（`instance.conf` 的 `PORT`）时若被占用会安装失败并说明改法。要换端口改 `instance.conf` 后重启应用即可，无需重装。

**“系统缺少 ar”**：安装器有两条解包路径 —— 有 `ar` 时只取官方包前缀约 96MB；没有 `ar`（fnOS 精简系统默认不装 `binutils`）时自动改用 `dpkg-deb` 解完整包（多下约 330MB）。两条路径最终校验一致（895 个文件 + `index.html`）。若两条都不可用才会退化为占位页，此时 `apt-get install -y binutils` 后重装一次即可。

**下载失败**：先在电脑下载官方 deb 拷到 NAS，再设 `DEB_FILE=/tmp/wb.deb` 后于应用中心重新安装（绕过官方接口查询）。

**重启后服务没了**：fnOS 上服务靠 `setsid` 拉起而非 systemd unit，重启后重新执行上面的启动命令即可。

## 架构与体积

| | x86_64 | aarch64 |
| --- | --- | --- |
| 安装包 | `fnwb.workbuddy_1.2.6_x86.fpk` | `fnwb.workbuddy_1.2.6_arm.fpk` |
| NAS 机型 | 多数 Intel / AMD 飞牛 | 飞牛 OEC 等 ARM 机型 |
| 解包后占用 | 约 950 MB | 约 2.7 GB |

用 `uname -m` 查看架构：`x86_64` 选 x86，`aarch64` 选 arm。安装期磁盘需求约 2.6 GB（含 deb），装完自动删除 deb，稳定占用位于存储池。

### 机型自适应

- **小 `/tmp` 的 ARM 机型**：OEC 的 `/tmp` 是 977 MB tmpfs，装不下 400 MB deb，安装器把下载暂存到存储池，空间检查跟随实际安装卷。
- **小内存机型**：V8 堆上限按总内存分档（2GB→768MB，<12GB→1024MB，更大→1536MB），2GB 的 OEC 实测 RSS 约 270MB，不触发 OOM。

## 路径布局

| | 位置 | 说明 |
| --- | --- | --- |
| 应用注册 | `/usr/local/apps/@appcenter/fnwb.workbuddy/` | 系统分区 |
| 程序本体 | `/vol1/1000/app_workbuddy/` | 存储池，避免撑爆系统分区 |

`dpkg -x` 解包不注册进 dpkg 数据库，不会与官方 deb 互相破坏。若你已有手工安装的 WorkBuddy（在 `/vol1/1000/workbuddy`），本安装器不会动它，两者共存。

## 从源码构建

```bash
git clone https://github.com/mclhm8182/workbuddy-fnOS-installer
cd workbuddy-fnOS-installer
./build.sh
```

产物在 `dist/`：`fnwb.workbuddy_1.2.6_x86.fpk`、`fnwb.workbuddy_1.2.6_arm.fpk`、`SHA256SUMS`。`build.sh` 自动从 fnOS 官方 CDN 获取 fnpack 1.2.3。

## 合规与许可

- 本仓库不包含 WorkBuddy 任何二进制 / 源码 / 商标图形；安装时仅获取官方 deb，不修改不重新打包。
- 图标为自绘中性图形，未使用官方 logo。
- 脚本以 [MIT License](LICENSE) 发布。使用 WorkBuddy 需自行注册账号并遵守其服务条款。

## 致谢

fpk 打包模式参考社区项目 [DockFN](https://github.com/lviaa/dockfn)。
