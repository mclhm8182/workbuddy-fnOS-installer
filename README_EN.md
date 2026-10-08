# workbuddy-fnOS-installer

**Third-party installer for WorkBuddy on fnOS** (飞牛 NAS).

A single fpk package that contains **none of WorkBuddy's binary files**. At install time it fetches the official `.deb` from Tencent's official endpoint and unpacks it into an fnOS app.

```
fpk (~42 KB) ──install──> download official deb (~400 MB) ──unpack──> /vol1/1000/app_workbuddy
```

[简体中文](README.md) | English

---

## What this is, and what it isn't

| | |
|---|---|
| ✅ **Is** | An **installer** — download, unpack, register, start, uninstall |
| ✅ **Is** | A ~42 KB package containing only icons, scripts, and a manifest |
| ❌ **Is not** | WorkBuddy itself |
| ❌ **Is not** | An official release, or affiliated with WorkBuddy |
| ❌ **Is not** | A repackaged WorkBuddy — no official code is modified |

**Why it's built this way**: bundling the ~400 MB official deb inside the fpk would mean redistributing someone else's software, which carries copyright risk. Shipping an installer avoids this entirely — the repository contains **zero lines of official code**; the official package is fetched from the official source at runtime.

---

## Quick start

### Option 1: GUI (recommended)

1. Download the `.fpk` matching your NAS architecture (`x86` or `arm`)
2. In the fnOS web UI, go to **App Center** → **Manual Install** (bottom left)
3. Upload the fpk, confirm the install location is the system partition
4. A WorkBuddy icon appears on the desktop — click it

No input is required during installation. **The default build requires no password** — see [Access control](#access-control).

### What happens during install

At the `cmd/install_init` stage the installer automatically:

```
detect architecture → query official endpoint → download deb → dpkg -x unpack → verify → start service
```

Fully silent. Logs land in `/var/log/apps/fnwb.workbuddy.log`.

**Customizing the install** — environment variables you can set beforehand:

| Variable | Effect |
|---|---|
| `DEB_FILE` | Install from a local deb (zero network), e.g. `DEB_FILE=/tmp/wb.deb` |
| `DEB_URL` | Use a specific download URL, skipping the official endpoint query |

By default the installer queries **Tencent's official update endpoint** to resolve the latest download URL at runtime — it never hardcodes URLs, because the official build hash changes with every release:

```
https://copilot.tencent.com/v2/update?platform=workbuddy-linux-x64-deb
https://copilot.tencent.com/v2/update?platform=workbuddy-linux-arm64-deb
```

Open either URL in a browser and the `url` field in the JSON response is the direct download link.

These are advanced knobs — **most users never need to set anything**, just install the fpk.

---

## Access control

**No password is required by default** — click the desktop icon and you're in.

To enable a password (e.g. if other devices on your LAN should need one):

```bash
# Enable password authentication
sudo sh -c 'echo password > /vol1/1000/app_workbuddy/AUTH_MODE'

# Read the generated password
sudo cat /vol1/1000/app_workbuddy/ACCESS_PASS

# Disable it again
sudo sh -c 'echo none > /vol1/1000/app_workbuddy/AUTH_MODE'
```

Restart the service for the change to take effect:

```bash
sudo pkill -f 'app_workbuddy.*codebuddy'
sudo sh -c 'cd /vol1/1000/app_workbuddy && setsid ./start.sh > run.log 2>&1 < /dev/null &'
```

### Security notes

**Without a password, any device on your LAN or Tailnet can use your WorkBuddy directly** — including reading and writing files it can access, and consuming your AI quota.

If your NAS is reachable from an untrusted network (port forwarding, public IP), **enable the password.**

fnOS's own login **does not replace** this password — the desktop icon is just an iframe container; port 8090 itself is open.

> **Note on the upstream gateway**: CodeBuddy's gateway has no "set a password on first run" flow. It either uses a password printed at service start, accepts `?password=xxx` as a URL parameter, or is disabled via `gateway.auth: "none"`. That's why this installer defaults to no password and offers a switch, rather than pretending a first-run password wizard exists.

---

## Uninstalling

Just uninstall from the fnOS App Center.

**Default behaviour**: removes the app registration, desktop icon, and startup entry point, but **keeps program data** (`/vol1/1000/app_workbuddy`) so you can re-enable it later.

**Full cleanup** (irreversible) — remove the data directory manually:

```bash
# Stop the service first
sudo pkill -f 'app_workbuddy.*codebuddy'

# Double-check the path, then remove
sudo rm -rf /vol1/1000/app_workbuddy
```

Confirm the path before running — that directory holds chat history and configuration, and deletion cannot be undone.

---

## Troubleshooting

**Desktop icon does nothing / spins forever**

```bash
# Is the service running? (exit 0 = running, exit 3 = not running)
ss -lntp | grep 8090

# Application log
sudo tail -40 /var/log/apps/fnwb.workbuddy.log

# Service runtime log
sudo tail -40 /vol1/1000/app_workbuddy/run.log
```

**"Port 8090 is already in use"**

Another instance is already using the port. Stop it, or change the port — in that case update `APP_PORT` in `cmd/lib/common.sh` and `service_port` in `manifest` together.

**Download failed**

Download the deb on your computer, copy it to the NAS, and point `DEB_FILE` at it:

```bash
scp workbuddy_5.4.5_amd64.deb Tom@<NAS_IP>:/tmp/

# then reinstall from the App Center, or run directly:
sudo env DEB_FILE=/tmp/workbuddy_5.4.5_amd64.deb \
  /usr/local/apps/@appcenter/fnwb.workbuddy/cmd/install_init
```

**Service doesn't survive a reboot**

This is a known limitation: `systemctl daemon-reload` times out on fnOS, so the service is started via `setsid` rather than a systemd unit. Re-run the start command above after a reboot, or ask us to add a unit file.

---

## Architectures and sizing

| | x86_64 | aarch64 |
|---|---|---|
| Package | `fnwb.workbuddy_1.2.2_x86.fpk` | `fnwb.workbuddy_1.2.2_arm.fpk` |
| NAS models | Most Intel/AMD fnOS devices | ARM models such as the fnOS OEC |
| Unpacked size | ~950 MB | ~2.7 GB |
| Verified | ✅ in production | ✅ in production |

Check your architecture with `uname -m`: `x86_64` → x86 package, `aarch64` → arm package.

**Disk needed during install: ~2.6 GB** (deb ~400 MB + unpacked files). The deb is deleted afterwards; steady-state usage sits in the storage pool, not the system partition.

### Machine-specific adaptations

The installer adapts to the host automatically. Two examples verified on real hardware:

- **ARM devices with a small `/tmp`** — on the fnOS OEC, `/tmp` is a 977 MB tmpfs, too small for a 400 MB deb. The installer therefore stages the download on the **storage pool**, and runs its space check against the actual install volume rather than a hardcoded path.
- **Low-memory machines** — the V8 heap limit scales with total RAM (768 MB on a 2 GB device, 1024 MB below 12 GB, 1536 MB above). On the 2 GB OEC this keeps WorkBuddy at ~270 MB RSS instead of risking an OOM.

---

## Path layout

Registration and program body are kept separate:

| | Location | Notes |
|---|---|---|
| App registration | `/usr/local/apps/@appcenter/fnwb.workbuddy/` | System partition, follows fnOS convention (~70 KB) |
| Program body | `/vol1/1000/app_workbuddy/` | Storage pool, keeps the system partition small |

`dpkg -x` unpacking **does not register in the dpkg database**, so it cannot conflict with the official deb's own install / upgrade / uninstall.

> **If you already have a manually installed WorkBuddy** (in `/vol1/1000/workbuddy`), this installer **leaves it untouched** — the program goes to `/vol1/1000/app_workbuddy/` and the two coexist. If you're happy with the old copy, just uninstall this package.

---

## Building from source

```bash
git clone https://github.com/mclhm8182/workbuddy-fnOS-installer
cd workbuddy-fnOS-installer

./build.sh
```

`build.sh` automatically fetches fnpack 1.2.3 from fnOS's official CDN — no manual download needed.

To use an existing fnpack:

```bash
FNPACK=/path/to/fnpack ./build.sh
```

Artifacts land in `dist/`:

```
fnwb.workbuddy_1.2.2_x86.fpk
fnwb.workbuddy_1.2.2_arm.fpk
SHA256SUMS
```

**Why fnpack is pinned to 1.2.3**: output formats differ between versions, and CI validates artifacts against 1.2.3.

---

## Compliance statement

This repository is an **independent community tool**. It is not affiliated with, endorsed by, or connected to WorkBuddy's official team.

- This repository contains **none** of WorkBuddy's binary files, source code, or trademark graphics
- At install time it fetches the official `.deb` from WorkBuddy's public channels, unmodified and un-repackaged
- Copyright and redistribution rights for the official deb belong to its respective rights holder
- The icons here are original neutral artwork; **no official WorkBuddy logo or trademark is used**
- The `maintainer` / `distributor` fields in the manifest point to this project's maintainers, not to the official vendor
- Using WorkBuddy requires registering your own account and agreeing to its terms of service

**If you are a member of the WorkBuddy official team**, please do not use this repository — obtain the installer from official channels, or contact the maintainer to have it removed.

## License

The scripts are released under the [MIT License](LICENSE). WorkBuddy itself is not part of this project.

## Acknowledgements

The fpk packaging approach in this project follows the pattern established by the community project [DockFN](https://github.com/lviaa/dockfn).
