#!/usr/bin/env python3
"""
生成 WorkBuddy 安装器图标（64x64 与 256x256）。

设计说明（重要）：
  本图标为第三方安装器的**自绘图形**，不使用 WorkBuddy 官方商标/logo。
  造型为一只绿色底 + 白色龙虾的扁平化风格龙虾，呼应 WorkBuddy 的龙虾品牌意象，
  但线条与构造均为自行设计，属中性指涉，不构成商标使用。

技术要点：
  纯标准库手写 PNG 编码，无第三方依赖。
  采用 4x 超采样 + 盒式降采样做抗锯齿，避免小尺寸下边缘锯齿明显。

依赖：仅标准库（math / struct / zlib）。
"""
import math
import struct
import zlib
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent
APP_DIR = OUT_DIR / "apps" / "workbuddy-installer"
# UI 资源位于 app/ui/（fnpack 规范：ui 在 app 之下）
UI_IMAGES = APP_DIR / "app" / "ui" / "images"

# ---------------------------------------------------------------- 配色
BG_TOP = (74, 222, 128)     # #4ADE80  翠绿
BG_BOTTOM = (21, 128, 61)   # #15803D  深绿
FG = (255, 255, 255)        # 白色龙虾
FG_SHADE = (226, 245, 233)  # 龙虾暗部（分节线等细节）

SS = 4  # 超采样倍数


# ---------------------------------------------------------------- 几何工具

def ellipse(px, py, cx, cy, rx, ry):
    """点是否在椭圆内。"""
    if rx <= 0 or ry <= 0:
        return False
    return ((px - cx) / rx) ** 2 + ((py - cy) / ry) ** 2 <= 1.0


def rot(px, py, cx, cy, ang):
    """把点绕中心旋转 ang 弧度。"""
    dx, dy = px - cx, py - cy
    ca, sa = math.cos(ang), math.sin(ang)
    return cx + dx * ca + dy * sa, cy - dx * sa + dy * ca


def dist_seg(px, py, x1, y1, x2, y2):
    """点到线段的距离。"""
    vx, vy = x2 - x1, y2 - y1
    wx, wy = px - x1, py - y1
    L2 = vx * vx + vy * vy
    if L2 == 0:
        return math.hypot(wx, wy)
    t = max(0.0, min(1.0, (wx * vx + wy * vy) / L2))
    return math.hypot(px - (x1 + t * vx), py - (y1 + t * vy))


def capsule(px, py, x1, y1, x2, y2, w):
    """粗线段（用于触须、腿、臂）。"""
    return dist_seg(px, py, x1, y1, x2, y2) <= w


def bezier(p0, p1, p2, n=18):
    """二次贝塞尔采样成折线点列。"""
    out = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        out.append((u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
                    u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]))
    return out


def polyline_dist(px, py, pts):
    return min(dist_seg(px, py, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1])
               for i in range(len(pts) - 1))


def circle(px, py, cx, cy, r):
    return math.hypot(px - cx, py - cy) <= r


# ---------------------------------------------------------------- 龙虾造型
#
# 正面视图：头在上一、双螯高举两侧、躯干分节、尾扇在下、触须上扬。
# 所有坐标为0..1 归一化，再乘以图标尺寸。

# 躯干 + 头 + 尾
HEAD = (0.500, 0.300, 0.132, 0.112)
BODY = (0.500, 0.545, 0.158, 0.212)
TAIL_LINK = (0.500, 0.720, 0.092, 0.082)
TAIL_C = (0.500, 0.786, 0.112, 0.074)
TAIL_L = (0.406, 0.768, 0.076, 0.062)
TAIL_R = (0.594, 0.768, 0.076, 0.062)

# 双螯（椭圆 + 缺口，缺口由下方相减得到）
#缺口朝身体内侧（左螯在右下、右螯在左下），形成"张开的钳"
CLAW_L = dict(c=(0.206, 0.292), rx=0.128, ry=0.094, ang=-0.40,
              notch=(0.268, 0.348, 0.058))
CLAW_R = dict(c=(0.794, 0.292), rx=0.128, ry=0.094, ang=0.40,
              notch=(0.732, 0.348, 0.058))

# 螯臂
ARM_L = ((0.335, 0.408), (0.243, 0.318), 0.032)
ARM_R = ((0.665, 0.408), (0.757, 0.318), 0.032)

# 触须（二次贝塞尔）
ANT_L = bezier((0.470, 0.205), (0.372, 0.052), (0.252, 0.098))
ANT_R = bezier((0.530, 0.205), (0.628, 0.052), (0.748, 0.098))
ANT_W = 0.0165

# 步足
LEGS_L = [((0.345, 0.452), (0.222, 0.520)),
          ((0.338, 0.556), (0.203, 0.622)),
          ((0.344, 0.652), (0.243, 0.712))]
LEGS_R = [((0.655, 0.452), (0.778, 0.520)),
          ((0.662, 0.556), (0.797, 0.622)),
          ((0.656, 0.652), (0.757, 0.712))]
LEG_W = 0.0175


def in_lobster(px, py):
    """点是否落在龙虾形体上（归一化坐标）。"""
    # 触须与步足先判（最细的部分）
    if polyline_dist(px, py, ANT_L) <= ANT_W or polyline_dist(px, py, ANT_R) <= ANT_W:
        return True
    for (a, b) in LEGS_L + LEGS_R:
        if capsule(px, py, a[0], a[1], b[0], b[1], LEG_W):
            return True

    # 螯臂
    if capsule(px, py, ARM_L[0][0], ARM_L[0][1], ARM_L[1][0], ARM_L[1][1], ARM_L[2]):
        return True
    if capsule(px, py, ARM_R[0][0], ARM_R[0][1], ARM_R[1][0], ARM_R[1][1], ARM_R[2]):
        return True

    # 躯干 / 头 / 尾
    for (cx, cy, rx, ry) in (HEAD, BODY, TAIL_LINK, TAIL_C, TAIL_L, TAIL_R):
        if ellipse(px, py, cx, cy, rx, ry):
            return True

    # 双螯：旋转椭圆减去缺口
    for c in (CLAW_L, CLAW_R):
        rxp, ryp = rot(px, py, c["c"][0], c["c"][1], -c["ang"])
        if ellipse(rxp, ryp, c["c"][0], c["c"][1], c["rx"], c["ry"]):
            n = c["notch"]
            if not circle(px, py, n[0], n[1], n[2]):
                return True

    return False


def in_seam(px, py):
    """躯干分节线（用暗色，让造型更有细节）。"""
    if not ellipse(px, py, BODY[0], BODY[1], BODY[2], BODY[3]):
        return False
    for y in (0.455, 0.545, 0.635):
        if abs(py - y) <= 0.011:
            return True
    return False


# ---------------------------------------------------------------- 渲染

def render(size):
    """返回 size*size 的 RGBA 矩阵（超采样抗锯齿）。"""
    big = size * SS
    # 先算超采样层的分类
    fg_hi = bytearray(big * big)
    seam_hi = bytearray(big * big)
    r = size * 0.223  # 圆角半径（像素）
    inside_bg_hi = bytearray(big * big)

    for j in range(big):
        py = (j + 0.5) / big
        for i in range(big):
            px = (i + 0.5) / big
            # 背景圆角方块（像素空间判定圆角）
            dx = min(i + 0.5, big - i - 0.5)
            dy = min(j + 0.5, big - j - 0.5)
            if dx >= r or dy >= r or math.hypot(dx - r, dy - r) <= r:
                inside_bg_hi[j * big + i] = 1
            if in_lobster(px, py):
                fg_hi[j * big + i] = 1
            elif in_seam(px, py):
                seam_hi[j * big + i] = 1

    # 盒式降采样
    out = []
    area = SS * SS
    for y in range(size):
        row = []
        for x in range(size):
            bg_n = fg_n = seam_n = 0
            for dy in range(SS):
                base = (y * SS + dy) * big + x * SS
                for dx in range(SS):
                    k = base + dx
                    if inside_bg_hi[k]:
                        bg_n += 1
                    if fg_hi[k]:
                        fg_n += 1
                    elif seam_hi[k]:
                        seam_n += 1
            if bg_n == 0:
                row.append((0, 0, 0, 0))
                continue
            a = bg_n / area          # 整体不透明度
            # 前景色与背景色混合
            t = fg_n / area           # 龙虾覆盖率
            ts = seam_n / area
            col = [0.0, 0.0, 0.0]
            for c in range(3):
                bgc = BG_TOP[c] + (BG_BOTTOM[c] - BG_TOP[c]) * (y / max(size - 1, 1))
                g = FG[c]
                s = FG_SHADE[c]
                base_c = bgc * (bg_n - fg_n - seam_n) / bg_n
                col[c] = base_c + g * fg_n / bg_n + s * seam_n / bg_n
            row.append((int(round(col[0])), int(round(col[1])),
                        int(round(col[2])), int(round(a * 255))))
        out.append(row)
    return out


def write_png(path, pixels):
    h = len(pixels)
    w = len(pixels[0])

    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for (r, g, b, a) in row:
            raw += bytes((r, g, b, a))

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def main():
    UI_IMAGES.mkdir(parents=True, exist_ok=True)

    # fnOS 桌面/任务栏会按需请求多种尺寸（实测系统自带应用提供
    # 16/24/64/128/256 及 icon_{0}.png），缺哪些就可能回落到旧缓存或默认图标。
    # 故一次性生成全套。
    sizes = (16, 24, 32, 64, 128, 256)
    cache = {}
    for size in sizes:
        cache[size] = render(size)

    for size in sizes:
        out = UI_IMAGES / f"icon_{size}.png"
        write_png(out, cache[size])
        print(f"  {out.relative_to(OUT_DIR)}  ({out.stat().st_size} B, {size}x{size})")

    # icon_{0}.png：fnOS 桌面实际请求的模板文件
    tmpl = UI_IMAGES / "icon_{0}.png"
    write_png(tmpl, cache[128])
    print(f"  {tmpl.relative_to(OUT_DIR)}  ({tmpl.stat().st_size} B, 128x128)")

    # fnpack 规范要求图标位于包根目录
    for size, name in ((64, "ICON.PNG"), (256, "ICON_256.PNG")):
        out = APP_DIR / name
        write_png(out, cache[size])
        print(f"  {out.relative_to(OUT_DIR)}  ({out.stat().st_size} B, {size}x{size})")


if __name__ == "__main__":
    main()