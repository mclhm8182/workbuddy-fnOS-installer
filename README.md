# workbuddy-fnOS-installer

飞牛 fnOS 上的 **WorkBuddy 第三方安装器**。

一个 fpk 包，**不包含 WorkBuddy 的任何二进制文件**。安装时才从官方地址获取官方 `.deb` 并解包为 fnOS 应用。

fpk（~42KB）──安装──> 从官方源下载 deb（~400MB）──解包──> /vol1/1000/app_workbuddy


简体中文 | [English](README_EN.md)

---

## 这是什么，不是什么

| | |
|---|---|
| ✅ 是 | 一个**安装器** —— 下载、解包、注册、启动、卸载，一条龙 |
| ✅ 是 | 约 42KB 的小包，含图标 + 脚本 + manifest |
| ❌ 不是 | WorkBuddy 程序本体 |
| ❌ 不是 | 官方发布物，与 WorkBuddy 官方无隶属关系 |
| ❌ 不是 | 重新打包的 WorkBuddy，不修改任何官方代码 |

**为什么这么设计**：把约 400MB 的官方 deb 塞进 fpk 意味着二次分发官方软件，有著作权风险。做成安装器则完全规避 —— 仓库里没有一行官方代码，运行时才去官方源取。

---

## 快速开始

### 方式一：图形界面（推荐）

1. 下载对应你 NAS 架构的 `.fpk`（`x86` 或 `arm`）
2. fnOS 网页端 → **应用中心** → 左下角**手动安装**
3. 上传 fpk，确认安装位置为「系统分区」
4. 装完后桌面出现 WorkBuddy 图标，点击访问

安装过程无需任何输入。**默认构建不需要密码**，点桌面图标直接进 —— 详见[访问控制](#访问控制)。

### 关于安装过程

fpk 安装时会在 `cmd/install_init` 阶段自动完成：检测架构 → 查询官方接口 → 下载 deb → dpkg -x 解包 → 校验 → 拉起服务

全程静默。日志在 `/var/log/apps/fnwb.workbuddy.log`。

**自定义安装行为** —— 如需跳过自动下载或换源，可在安装前设置环境变量：

| 变量 | 作用 |
|---|---|
| `DEB_FILE` | 用本地 deb 安装（0 流量），如 `DEB_FILE=/tmp/wb.deb` |
| `DEB_URL` | 指定下载地址，跳过官方接口查询 |

安装器默认走**腾讯官方更新接口**动态获取最新版地址，不硬编码 URL
（官方构建号每次发版都会变）：

```
https://copilot.tencent.com/v2/update?platform=workbuddy-linux-x64-deb
https://copilot.tencent.com/v2/update?platform=workbuddy-linux-arm64-deb
```

浏览器直接打开即可看到 JSON 里的 `url` 字段，那就是下载地址。

这些是高级用法，普通用户**不需要设置** —— 直接装 fpk 即可。

---

## 访问密码

**默认不需要密码**，装完点桌面图标直接进。

需要密码时（比如局域网里有其他设备想访问），随时开启：

```bash
# 启用密码认证
sudo sh -c 'echo password > /vol1/1000/app_workbuddy/AUTH_MODE'

# 查看密码
sudo cat /vol1/1000/app_workbuddy/ACCESS_PASS

# 关闭密码
sudo sh -c 'echo none > /vol1/1000/app_workbuddy/AUTH_MODE'
```

改完重启服务生效：

```bash
sudo pkill -f 'app_workbuddy.*codebuddy'
sudo sh -c 'cd /vol1/1000/app_workbuddy && setsid ./start.sh > run.log 2>&1 < /dev/null &'
```

### 安全提醒

**不启用密码意味着局域网和 Tailnet 内的任何设备都能直接使用你的 WorkBuddy** ——
包括读写它能访问的文件、消耗你的 AI 额度。

如果你把 NAS 暴露给了不可信的网络（端口转发、公开 IP），**务必启用密码**。

fnOS 自身的登录**不能替代**这个密码 —— 桌面图标只是 iframe 容器，8090 端口本身是敞开的。

> **关于上游网关**：CodeBuddy 网关**没有"首次运行设置密码"的流程**。它只认三种方式：服务启动时打印在终端的密码、URL 参数 `?password=xxx`、或用 `gateway.auth: "none"` 关闭认证。
> 正因如此本安装器默认不启用密码、另行提供开关，而不是假装存在一个首次设密码的向导。
> 启用密码后，桌面入口会自动带上密码参数，点击即可直接进入。

## 卸载

在 fnOS 应用中心直接卸载即可。

**默认行为**：移除应用注册、桌面图标和启动入口，**保留程序数据**（`/vol1/1000/app_workbuddy`），便于日后重新启用。

**彻底清理**（不可逆），手动执行：

```bash
# 先停服务
sudo pkill -f 'app_workbuddy.*codebuddy'

# 确认路径后再删
sudo rm -rf /vol1/1000/app_workbuddy
```

删前建议确认目录路径无误 —— 该目录下含聊天记录与配置，删除后无法恢复。

> 若删除时提示 `Permission denied`，那是 fnOS 的 ACL 所致，用：
> `sudo setfacl -R -m u:fnwb.workbuddy:rwx /vol1/1000/app_workbuddy` 先放开权限再删。

---

## 故障排查

**桌面点击无反应 / 一直转圈**

```bash
# 端口是否在监听
ss -lntp | grep 8090

# 应用日志
sudo tail -40 /var/log/apps/fnwb.workbuddy.log

# 服务运行日志
sudo tail -40 /vol1/1000/app_workbuddy/run.log
```

> 注意：fnOS 安装完成后会把 `cmd/` 挪到 `/var/apps/fnwb.workbuddy/cmd/`，
> 所以 `/usr/local/apps/@appcenter/fnwb.workbuddy/cmd/main` 在装完后**不存在**，请用上面的命令。

**提示「8090 端口被占用」**

说明已有服务在用该端口。停掉它，或改端口 —— 需同步修改 `cmd/lib/common.sh` 的 `APP_PORT` 与 `manifest` 的 `service_port`。

**下载失败**

先在电脑上下载 deb，拷到 NAS，再设 `DEB_FILE` 指向它：

```bash
scp workbuddy_5.4.5_amd64.deb Tom@<NAS_IP>:/tmp/

# 然后在应用中心重新安装，或手动：
sudo env DEB_FILE=/tmp/workbuddy_5.4.5_amd64.deb \
  /usr/local/apps/@appcenter/fnwb.workbuddy/cmd/install_init
```

**重启后服务没了**

这是已知限制：fnOS 上 `systemctl daemon-reload` 会超时，服务靠 `setsid` 启动而非 systemd unit。重启后重新执行上面的启动命令即可。

---

## 架构与体积

| | x86_64 | aarch64 |
|---|---|---|
| 对应 fpk | `fnwb.workbuddy_1.2.2_x86.fpk` | `fnwb.workbuddy_1.2.2_arm.fpk` |
| NAS 型号 | 多数 Intel/AMD飞牛 | 飞牛 OEC 等 ARM 机型 |
| 解包后占用 | 约 950 MB | 约 2.7 GB |
| 验证状态 | ✅ 生产环境验证 | ✅ 生产环境验证 |

用 `uname -m` 查看自己的架构：`x86_64` 选 x86，`aarch64` 选 arm。

**安装期磁盘需求约 2.6GB**（deb 约 400MB + 解包）。装完自动删除 deb，稳定占用位于存储池而非系统分区。

### 机型自适应

安装器会根据宿主机自动适配，以下两个都是真机验证过的：

- **`/tmp` 较小的 ARM 机型** —— 飞牛 OEC 的 `/tmp` 是 977MB 的 tmpfs，装不下 400MB 的 deb。安装器因此把下载暂存到**存储池**，空间检查也跟随实际安装卷而非硬编码路径。
- **小内存机型** —— V8 堆上限按总内存自动分档（2GB 机器用 768MB，12GB 以下1024MB，更大用 1536MB）。在 2GB 的 OEC 上实测 RSS 约 270MB，不会触发 OOM。

---

## 路径布局

采用「注册与程序本体分离」：

| | 位置 | 说明 |
|---|---|---|
| 应用注册 | `/usr/local/apps/@appcenter/fnwb.workbuddy/` | 系统分区，跟随fnOS 原生惯例 |
| 程序本体 | `/vol1/1000/app_workbuddy/` | 存储池，避免撑爆系统分区 |

`dpkg -x` 解包**不注册进 dpkg 数据库**，因此不会与官方 deb 的安装/升级/卸载互相破坏。

> **若你已有手工安装的 WorkBuddy**（在 `/vol1/1000/workbuddy`），本安装器**不会动它**。
> 程序会装到 `/vol1/1000/app_workbuddy/`，两者共存。只有本安装器管理的副本会开机自启 ——
> 若你只是想继续用原来那份，直接卸载本包即可。

---

## 从源码构建

```bash
git clone https://github.com/mclhm8182/workbuddy-fnOS-installer
cd workbuddy-fnOS-installer

./build.sh
```

build.sh 会自动从 fnOS 官方 CDN 获取 fnpack 1.2.3，无需手工下载。

如需指定已有的 fnpack：

```bash
FNPACK=/path/to/fnpack ./build.sh
```

产物在 `dist/`：

```
fnwb.workbuddy_1.2.2_x86.fpk
fnwb.workbuddy_1.2.2_arm.fpk
SHA256SUMS
```

**为什么固定 fnpack 1.2.3**：不同版本打包格式有差异，CI 校验产物时以 1.2.3 为准。

---

## 合规声明

本仓库是**独立社区用户的第三方工具**，与 WorkBuddy 官方无任何隶属、背书或合作关系。

- 本仓库**不包含** WorkBuddy 的任何二进制文件、源代码或商标图形
- 安装时从 WorkBuddy 官方公开渠道获取官方 `.deb`，不修改、不重新打包
- 官方 deb 的著作权与再分发权归其权利人所有
- 本项目图标为自绘中性图形，**未使用** WorkBuddy 官方 logo 或商标
- manifest 中的 `maintainer` / `distributor` 字段指向本项目维护者，与官方无关
- 使用 WorkBuddy 需自行注册账号并遵守其服务条款

**如果你就是 WorkBuddy 官方的成员**，请不要使用本仓库 —— 直接从官方渠道获取安装包，或联系维护者删除。

## 许可

脚本部分以 [MIT License](LICENSE) 发布。WorkBuddy 本身不是本项目的一部分。

## 致谢

本项目的 fpk 打包模式参考了社区项目 [DockFN](https://github.com/lviaa/dockfn) 的做法。
