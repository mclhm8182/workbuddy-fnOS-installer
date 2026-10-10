# WorkBuddy 第三方 fnOS 安装器

面向飞牛 fnOS 的 **WorkBuddy 第三方安装器** —— 一个 fpk 包，**不含 WorkBuddy 任何二进制**，安装时从官方源获取官方 `.deb` 并解包为 fnOS 应用。

> [!IMPORTANT]
> 本项目是独立社区工具，与 WorkBuddy 官方无任何隶属、背书或合作关系；不包含官方二进制，安装时仅从官方公开渠道获取官方 deb，不修改、不重新打包。

简体中文 | [English](README_EN.md)

## 下载

从 [GitHub Releases](https://github.com/mclhm8182/workbuddy-fnOS-installer/releases/latest) 下载对应架构的安装包：

| 架构 | 安装包 |
| --- | --- |
| x86_64 | `fnwb.workbuddy_1.2.4_x86.fpk` |
| ARM64 / aarch64 | `fnwb.workbuddy_1.2.4_arm.fpk` |

对照 Release 的 `SHA256SUMS` 校验文件，不一致时重新下载：

```bash
sha256sum fnwb.workbuddy_1.2.4_x86.fpk
```

应用详情显示 `v1.2`，应用内显示完整版本 `v1.2.4`。

## 更新说明（1.2.4，相对 1.2.2）

- **可直接覆盖安装旧版本（1.2.0 / 1.2.2 / 1.2.3），无需卸载。** 安装器会记录自身版本，升级时若仅安装器版本变化、WorkBuddy 本体未变，也会自动刷新启动脚本。
- 修复启动脚本：移除 1.2.3 误注入的 `CODEBUDDY_BASE_URL`（该变量是模型与 API 地址，设成局域网地址会让模型调用失效），恢复为干净默认配置。
- 一并包含 1.2.3 的内存自适应、小内存机型防 OOM 修复。
- **注意事项**：网页登录走腾讯 SSO 扫码，**不需要公网 IP / 隧道**；若扫码后一直转圈，先查 NAS 能否访问 `copilot.tencent.com` 与 `tencent.sso.copilot.tencent.com`（出网被限才会失败）。

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

**“8090 端口被占用”**：停掉占用进程，或改 `cmd/lib/common.sh` 的 `APP_PORT` 与 `manifest` 的 `service_port`。

**下载失败**：先在电脑下载官方 deb 拷到 NAS，再设 `DEB_FILE=/tmp/wb.deb` 后于应用中心重新安装（绕过官方接口查询）。

**重启后服务没了**：fnOS 上服务靠 `setsid` 拉起而非 systemd unit，重启后重新执行上面的启动命令即可。

## 架构与体积

| | x86_64 | aarch64 |
| --- | --- | --- |
| 安装包 | `fnwb.workbuddy_1.2.4_x86.fpk` | `fnwb.workbuddy_1.2.4_arm.fpk` |
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

产物在 `dist/`：`fnwb.workbuddy_1.2.4_x86.fpk`、`fnwb.workbuddy_1.2.4_arm.fpk`、`SHA256SUMS`。`build.sh` 自动从 fnOS 官方 CDN 获取 fnpack 1.2.3。

## 合规与许可

- 本仓库不包含 WorkBuddy 任何二进制 / 源码 / 商标图形；安装时仅获取官方 deb，不修改不重新打包。
- 图标为自绘中性图形，未使用官方 logo。
- 脚本以 [MIT License](LICENSE) 发布。使用 WorkBuddy 需自行注册账号并遵守其服务条款。

## 致谢

fpk 打包模式参考社区项目 [DockFN](https://github.com/lviaa/dockfn)。
