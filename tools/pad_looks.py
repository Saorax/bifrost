"""the input display's controller drawings (Xbox, DualShock 4, DualSense, Switch Pro) as vector layers, written to
src/platform/as3/bh/platform/PadLooks.as for PadDisplay.

    python tools/pad_looks.py [--json build/pad-looks/looks.json]

a layer: d (path data: M L C Z, absolute), fill or grad [top, bottom], stroke + lw, alpha, and optionally part (control
name) with state "off"/"on" (the "on" layers show while the control is pressed; analog triggers fade them in), knob
"L"/"R" (moves with that stick), shadow (drawn offset). canvas 400 x 340."""
import json

K = 0.5523
W = 400

def f(v):
    s = ("%.1f" % v).rstrip("0").rstrip(".")
    return "0" if s == "-0" else s

def circle(cx, cy, r):
    k = r * K
    return ("M%s %s C%s %s %s %s %s %s C%s %s %s %s %s %s C%s %s %s %s %s %s C%s %s %s %s %s %sZ" % tuple(map(f, (
        cx, cy - r, cx + k, cy - r, cx + r, cy - k, cx + r, cy,
        cx + r, cy + k, cx + k, cy + r, cx, cy + r,
        cx - k, cy + r, cx - r, cy + k, cx - r, cy,
        cx - r, cy - k, cx - k, cy - r, cx, cy - r))))

def rrect(x, y, w, h, r):
    k = r * (1 - K)
    return ("M%s %s L%s %s C%s %s %s %s %s %s L%s %s C%s %s %s %s %s %s L%s %s C%s %s %s %s %s %s L%s %s "
            "C%s %s %s %s %s %sZ" % tuple(map(f, (
                x + r, y, x + w - r, y, x + w - k, y, x + w, y + k, x + w, y + r,
                x + w, y + h - r, x + w, y + h - k, x + w - k, y + h, x + w - r, y + h,
                x + r, y + h, x + k, y + h, x, y + h - k, x, y + h - r,
                x, y + r, x, y + k, x + k, y, x + r, y))))

def poly(pts, close=True):
    return "M" + " L".join("%s %s" % (f(x), f(y)) for x, y in pts) + ("Z" if close else "")

def segs_path(start, segs, close=True):
    out = ["M%s %s" % (f(start[0]), f(start[1]))]
    for s in segs:
        if s[0] == "L":
            out.append("L%s %s" % (f(s[1]), f(s[2])))
        else:
            out.append("C" + " ".join(f(v) for v in s[1:]))
    return " ".join(out) + ("Z" if close else "")

def mirror_segs(start, segs):
    pts = [start] + [(s[-2], s[-1]) for s in segs]
    back = []
    for i in range(len(segs) - 1, -1, -1):
        s = segs[i]
        p0 = pts[i]
        if s[0] == "L":
            back.append(("L", W - p0[0], p0[1]))
        else:
            back.append(("C", W - s[3], s[4], W - s[1], s[2], W - p0[0], p0[1]))
    return segs_path(start, list(segs) + back)

def mx(d):
    toks = d.replace("Z", " Z ").replace("M", " M ").replace("L", " L ").replace("C", " C ").split()
    out = []
    xturn = True
    for t in toks:
        if t in ("M", "L", "C", "Z"):
            out.append(t)
            xturn = True
        else:
            v = float(t)
            out.append(f(W - v) if xturn else f(v))
            xturn = not xturn
    s = ""
    for t in out:
        s += t if t in ("M", "L", "C", "Z") else (" " + t if s and s[-1] not in "MLCZ" else t)
    return s

def lay(d, fill=None, line=None, lw=1, grad=None, part=None, state=None, knob=None, alpha=None):
    L = {"d": d}
    if fill is not None: L["fill"] = fill
    if grad is not None: L["grad"] = grad
    if line is not None: L["stroke"] = line; L["lw"] = lw
    if part: L["part"] = part; L["state"] = state or "off"
    if knob: L["knob"] = knob
    if alpha is not None: L["alpha"] = alpha
    return L

ACCENT = 0x4FE3D0

def stick(side, cx, cy, well, cap, edge, cap2, ring, wr=36):
    part = side + "S"
    return [lay(circle(cx, cy, wr), fill=well, line=edge, lw=1),
            lay(circle(cx, cy, 25), grad=cap, line=edge, lw=1.2, knob=side),
            lay(circle(cx, cy, 25), fill=ACCENT, line=edge, lw=1.2, knob=side, part=part, state="on"),
            lay(circle(cx, cy, 18), fill=cap2, line=ring, lw=1, knob=side)]

def face_button(part, cx, cy, r, base, line, glyph, gcol, on_fill, on_glyph, lw=2):
    out = [lay(circle(cx, cy, r), grad=base, line=line, lw=1.2)]
    out += [lay(g, line=gcol, lw=lw) for g in glyph]
    out.append(lay(circle(cx, cy, r), fill=on_fill, line=line, lw=1.2, part=part, state="on"))
    out += [lay(g, line=on_glyph, lw=lw, part=part, state="on") for g in glyph]
    return out

def glyph_cross(cx, cy, s):
    return [poly([(cx - s, cy - s), (cx + s, cy + s)], False), poly([(cx + s, cy - s), (cx - s, cy + s)], False)]

def glyph_circle(cx, cy, s):
    return [circle(cx, cy, s)]

def glyph_square(cx, cy, s):
    return [poly([(cx - s, cy - s), (cx + s, cy - s), (cx + s, cy + s), (cx - s, cy + s)])]

def glyph_triangle(cx, cy, s):
    return [poly([(cx, cy - s * 1.1), (cx + s * 1.05, cy + s * 0.75), (cx - s * 1.05, cy + s * 0.75)])]

def letter(ch, cx, cy, s):
    w = s * 0.75
    if ch == "A":
        return [poly([(cx - w, cy + s), (cx, cy - s), (cx + w, cy + s)], False), poly([(cx - w * 0.55, cy + s * 0.3), (cx + w * 0.55, cy + s * 0.3)], False)]
    if ch == "B":
        return [segs_path((cx - w * 0.8, cy - s), [("L", cx + w * 0.2, cy - s), ("C", cx + w * 1.0, cy - s, cx + w * 1.0, cy, cx + w * 0.2, cy),
                                                    ("L", cx - w * 0.8, cy), ("L", cx + w * 0.3, cy),
                                                    ("C", cx + w * 1.1, cy, cx + w * 1.1, cy + s, cx + w * 0.3, cy + s),
                                                    ("L", cx - w * 0.8, cy + s), ("L", cx - w * 0.8, cy - s)], False)]
    if ch == "X":
        return [poly([(cx - w * 0.9, cy - s), (cx + w * 0.9, cy + s)], False),
                poly([(cx + w * 0.9, cy - s), (cx - w * 0.9, cy + s)], False)]
    if ch == "Y":
        return [poly([(cx - w * 0.9, cy - s), (cx, cy), (cx + w * 0.9, cy - s)], False), poly([(cx, cy), (cx, cy + s)], False)]
    raise ValueError(ch)

def small_button(part, cx, cy, w, h, base, line, on=ACCENT, glyph=(), gcol=0xC8CDD4):
    out = [lay(rrect(cx - w / 2, cy - h / 2, w, h, min(w, h) / 2), fill=base, line=line, lw=1)]
    out.append(lay(rrect(cx - w / 2, cy - h / 2, w, h, min(w, h) / 2), fill=on, line=line, lw=1, part=part, state="on"))
    out += [lay(g, line=gcol, lw=1.1) for g in glyph]
    return out

def dpad_cross(cx, cy, arm, half, base, line, on=ACCENT, arrows=None):
    a, h = arm, half
    out = [lay(rrect(cx - h, cy - h - a, 2 * h, 2 * (h + a), 4), grad=base, line=line, lw=1.2),
           lay(rrect(cx - h - a, cy - h, 2 * (h + a), 2 * h, 4), grad=base, line=line, lw=1.2),
           lay(rrect(cx - h + 0.6, cy - h - 2, 2 * h - 1.2, 2 * h + 4, 1), grad=base)]
    rects = {"D0": (cx - h, cy - h - a, 2 * h, a + 2), "D1": (cx - h, cy + h - 2, 2 * h, a + 2),
             "D2": (cx - h - a, cy - h, a + 2, 2 * h), "D3": (cx + h - 2, cy - h, a + 2, 2 * h)}
    for p, (x, y, w2, h2) in rects.items():
        out.append(lay(rrect(x, y, w2, h2, 3), fill=on, part=p, state="on"))
    if arrows is not None:
        s = 3.2
        tris = {"D0": [(cx, cy - h - a + 6), (cx + s, cy - h - a + 6 + s * 1.4), (cx - s, cy - h - a + 6 + s * 1.4)],
                "D1": [(cx, cy + h + a - 6), (cx + s, cy + h + a - 6 - s * 1.4), (cx - s, cy + h + a - 6 - s * 1.4)],
                "D2": [(cx - h - a + 6, cy), (cx - h - a + 6 + s * 1.4, cy - s), (cx - h - a + 6 + s * 1.4, cy + s)],
                "D3": [(cx + h + a - 6, cy), (cx + h + a - 6 - s * 1.4, cy - s), (cx + h + a - 6 - s * 1.4, cy + s)]}
        for p, t in tris.items():
            out.append(lay(poly(t), fill=arrows))
    return out

def dpad_ps(cx, cy, base, line, on, arrow, gap=9, length=26, width=19):
    out = []
    for p, ang in (("D0", 0), ("D1", 2), ("D2", 3), ("D3", 1)):
        def P(al, ac, ang=ang):
            return [(cx + ac, cy - al), (cx + al, cy + ac), (cx - ac, cy + al), (cx - al, cy - ac)][ang]
        w2 = width / 2
        pts_ = [P(gap, 0), P(gap + 6, -w2), P(gap + length - 3, -w2), P(gap + length, -w2 + 3), P(gap + length, w2 - 3),
                P(gap + length - 3, w2), P(gap + 6, w2)]
        d = poly(pts_)
        out.append(lay(d, grad=base, line=line, lw=1.2))
        out.append(lay(d, fill=on, line=line, lw=1.2, part=p, state="on"))
        t = [P(gap + length - 8, 0), P(gap + length - 14, -4), P(gap + length - 14, 4)]
        out.append(lay(poly(t), fill=arrow))
    return out

def bumper_trigger(trig, bump, tbase, bbase, line):
    out = []
    sides = (("L", trig, bump), ("R", mx(trig), mx(bump)))
    for side, tpath, _ in sides:
        out.append(lay(tpath, grad=tbase, line=line, lw=1.2))
        out.append(lay(tpath, fill=ACCENT, line=line, lw=1.2, part=side + "T", state="on"))
    for side, _, bpath in sides:
        out.append(dict(lay(bpath, grad=bbase, line=line, lw=1.2), front=True))
        out.append(dict(lay(bpath, fill=ACCENT, line=line, lw=1.2, part=side + "B", state="on"), front=True))
    return out

def in_front(look):
    layers = look["layers"]
    front = [l for l in layers if l.pop("front", False)]
    rest = [l for l in layers if l not in front]
    at = next(i for i, l in enumerate(rest) if l.get("shadow")) + 2
    look["layers"] = rest[:at] + front + rest[at:]
    return look

def xbox():
    edge = 0x0A0B0D
    L = []
    trig = segs_path((86, 70), [("C", 84, 40, 90, 8, 110, 4), ("C", 122, 2, 128, 10, 128, 26), ("L", 130, 70)])
    bump = segs_path((58, 86), [("C", 72, 66, 104, 58, 134, 64), ("C", 140, 66, 142, 74, 140, 82),
                                ("C", 110, 74, 82, 78, 64, 94)])
    L += bumper_trigger(trig, bump, [0x34373D, 0x1E2024], [0x3A3D44, 0x222429], edge)
    shell = mirror_segs((200, 78), [("C", 170, 78, 150, 78, 132, 72), ("C", 112, 64, 82, 64, 62, 76),
                                    ("C", 48, 84, 42, 98, 38, 110), ("C", 22, 158, 4, 220, 2, 268),
                                    ("C", 0, 308, 14, 334, 40, 334), ("C", 60, 334, 74, 318, 92, 296),
                                    ("C", 108, 278, 120, 268, 142, 268), ("C", 170, 268, 190, 268, 200, 268)])
    L.append(lay(shell, fill=0x000000, alpha=0.35))
    L[-1]["shadow"] = True
    L.append(lay(shell, grad=[0x34373D, 0x17181B], line=edge, lw=1.6))
    L.append(lay(poly([(142, 80), (258, 80), (248, 128), (152, 128)]), grad=[0x2A2D33, 0x24262B], line=0x101114, lw=1))
    L.append(lay(circle(200, 104, 17), grad=[0xE8ECF2, 0xB8C0CA], line=0x101114, lw=1.2))
    L.append(lay(circle(200, 104, 11), line=0x8A939E, lw=1.5))
    L += stick("L", 98, 148, 0x0E0F11, [0x3A3D44, 0x24262B], edge, 0x1C1E22, 0x2C2F35)
    L += stick("R", 252, 212, 0x0E0F11, [0x3A3D44, 0x24262B], edge, 0x1C1E22, 0x2C2F35)
    L.append(lay(circle(148, 212, 33), fill=0x0E0F11, line=edge, lw=1))
    L += dpad_cross(148, 212, 20, 9.5, [0x3A3D44, 0x24262B], edge)
    cols = {"A": 0x6CC24A, "B": 0xE5483B, "X": 0x2F8DE4, "Y": 0xF2C230}
    for p, (dx, dy) in {"A": (0, 27), "B": (27, 0), "X": (-27, 0), "Y": (0, -27)}.items():
        L += face_button(p, 302 + dx, 148 + dy, 12.5, [0x2E3137, 0x1C1E22], edge, letter(p, 302 + dx, 148 + dy, 5.5),
                         cols[p], cols[p], 0xFFFFFF, lw=1.8)
    view = [rrect(167, 145, 6, 5, 1), rrect(171, 148, 6, 5, 1)]
    menu = [poly([(224, 146), (232, 146)], False), poly([(224, 149), (232, 149)], False), poly([(224, 152), (232, 152)], False)]
    L += small_button("BACK", 172, 149, 16, 16, 0x1A1C20, edge, glyph=view)
    L += small_button("START", 228, 149, 16, 16, 0x1A1C20, edge, glyph=menu)
    L.append(lay(rrect(193, 168, 14, 8, 4), fill=0x1A1C20, line=edge, lw=1))
    return {"layers": L, "names": {"LT": "LT", "RT": "RT", "LB": "LB", "RB": "RB"}}

def dualshock():
    edge = 0x0B0C10
    L = []
    trig = segs_path((58, 48), [("C", 58, 22, 66, 2, 84, 2), ("C", 100, 2, 106, 18, 108, 48)])
    bump = segs_path((52, 60), [("C", 56, 52, 70, 48, 82, 48), ("C", 96, 48, 108, 50, 112, 58), ("L", 110, 64),
                                ("C", 92, 60, 72, 60, 54, 66)])
    L += bumper_trigger(trig, bump, [0x34383F, 0x1F2227], [0x3A3E46, 0x23262C], edge)
    shell = mirror_segs((200, 60), [("L", 112, 60), ("C", 92, 58, 60, 58, 44, 64), ("C", 30, 70, 24, 84, 20, 104),
                                    ("C", 10, 160, 0, 220, 4, 262), ("C", 8, 290, 30, 300, 52, 296),
                                    ("C", 76, 292, 88, 262, 100, 236), ("C", 108, 220, 120, 214, 140, 214),
                                    ("L", 200, 214)])
    L.append(lay(shell, fill=0x000000, alpha=0.35)); L[-1]["shadow"] = True
    L.append(lay(shell, grad=[0x2C3038, 0x16181D], line=edge, lw=1.6))
    grip = segs_path((6, 236), [("C", 26, 244, 70, 246, 92, 250), ("C", 84, 274, 74, 292, 52, 296),
                               ("C", 30, 300, 8, 290, 4, 262)])
    L.append(lay(grip, fill=0x3A3E46, alpha=0.45))
    L.append(lay(mx(grip), fill=0x3A3E46, alpha=0.45))
    L.append(lay(rrect(136, 60, 128, 74, 6), grad=[0x1E2126, 0x15171B], line=0x08090B, lw=1.2))
    L.append(lay(poly([(140, 61), (260, 61)], False), line=0x3C78FF, lw=2))
    for cx in (82, 318):
        L.append(lay(circle(cx, 120, 46), fill=0x111317, line=0x2A2E35, lw=1))
    L += dpad_ps(82, 120, [0x3A3E46, 0x24272D], edge, ACCENT, 0x14161A)
    for p, (dx, dy), g, col in (("Y", (0, -28), glyph_triangle, 0x3FD6A6), ("B", (28, 0), glyph_circle, 0xFF6B6B),
                                ("X", (-28, 0), glyph_square, 0xE58AD8), ("A", (0, 28), glyph_cross, 0x7FA8E8)):
        cx, cy = 318 + dx, 120 + dy
        L += face_button(p, cx, cy, 13, [0x2A2E35, 0x1A1C21], edge, g(cx, cy, 5.5), col, col, 0xFFFFFF, lw=1.8)
    L += small_button("BACK", 118, 80, 8, 18, 0x15171B, 0x2A2E35)
    L += small_button("START", 282, 80, 8, 18, 0x15171B, 0x2A2E35)
    for i in range(5):
        L.append(lay(circle(188 + i * 6, 146, 1.6), fill=0x08090B))
    for i in range(4):
        L.append(lay(circle(191 + i * 6, 151, 1.6), fill=0x08090B))
    L += stick("L", 140, 176, 0x0D0E11, [0x34383F, 0x1F2227], edge, 0x1A1C21, 0x2A2E35)
    L += stick("R", 260, 176, 0x0D0E11, [0x34383F, 0x1F2227], edge, 0x1A1C21, 0x2A2E35)
    L.append(lay(circle(200, 180, 9), fill=0x0D0E11, line=0x2A2E35, lw=1))
    return {"layers": L, "names": {"LT": "L2", "RT": "R2", "LB": "L1", "RB": "R1"}}

def dualsense():
    edge = 0x8A919B
    L = []
    trig = segs_path((60, 62), [("C", 58, 34, 66, 10, 86, 8), ("C", 104, 8, 110, 26, 110, 58)])
    bump = segs_path((44, 72), [("C", 54, 62, 80, 58, 112, 62), ("L", 114, 70), ("C", 84, 66, 60, 68, 46, 78)])
    L += bumper_trigger(trig, bump, [0x2C2E33, 0x18191C], [0xF4F5F7, 0xD8DCE2], 0x2A2C30)
    shell = mirror_segs((200, 54), [("C", 150, 54, 90, 60, 44, 70), ("C", 34, 72, 30, 80, 26, 90),
                                    ("C", 10, 140, 0, 200, 2, 250), ("C", 4, 290, 18, 312, 42, 314),
                                    ("C", 52, 315, 58, 306, 64, 296), ("C", 76, 268, 90, 238, 106, 228),
                                    ("C", 118, 222, 130, 222, 150, 222), ("L", 200, 222)])
    L.append(lay(shell, fill=0x000000, alpha=0.35)); L[-1]["shadow"] = True
    L.append(lay(shell, grad=[0xFDFDFE, 0xE2E5EA], line=edge, lw=1.6))
    core = mirror_segs((200, 132), [("L", 132, 132), ("C", 118, 150, 100, 176, 86, 206), ("C", 70, 240, 56, 280, 44, 314),
                                    ("C", 52, 316, 58, 306, 64, 296), ("C", 76, 268, 90, 238, 106, 228),
                                    ("C", 118, 222, 130, 222, 150, 222), ("L", 200, 222)])
    L.append(lay(core, grad=[0x232428, 0x141518], line=0x0A0A0C, lw=1.2))
    pad = segs_path((122, 58), [("C", 150, 54, 250, 54, 278, 58), ("C", 284, 59, 284, 64, 283, 70),
                                ("L", 272, 124), ("C", 268, 138, 258, 142, 244, 142), ("L", 156, 142),
                                ("C", 142, 142, 132, 138, 128, 124), ("L", 117, 70), ("C", 116, 64, 116, 59, 122, 58)])
    L.append(lay(segs_path((114, 64), [("L", 125, 126), ("C", 129, 142, 142, 146, 156, 146), ("L", 244, 146),
                                       ("C", 258, 146, 271, 142, 275, 126), ("L", 286, 64)], False), line=0x2B4BFF, lw=3))
    L.append(lay(pad, grad=[0xFFFFFF, 0xEEF0F3], line=edge, lw=1.2))
    L += small_button("BACK", 104, 76, 6, 13, 0xF4F5F7, edge)
    L += small_button("START", 296, 76, 6, 13, 0xF4F5F7, edge)
    L += dpad_ps(74, 130, [0xFFFFFF, 0xE6E9ED], edge, ACCENT, 0xA0A7B0, gap=8, length=25, width=18)
    gl = 0x9AA1AA
    for p, (dx, dy), g in (("Y", (0, -27), glyph_triangle), ("B", (27, 0), glyph_circle),
                           ("X", (-27, 0), glyph_square), ("A", (0, 27), glyph_cross)):
        cx, cy = 326 + dx, 130 + dy
        L += face_button(p, cx, cy, 12.5, [0xFFFFFF, 0xE6E9ED], edge, g(cx, cy, 5.2), gl, ACCENT, 0xFFFFFF, lw=1.6)
    for i in range(5):
        L.append(lay(circle(188 + i * 6, 152, 1.6), fill=0x050506))
    for i in range(4):
        L.append(lay(circle(191 + i * 6, 157, 1.6), fill=0x050506))
    L += stick("L", 136, 182, 0x08090A, [0x34363B, 0x1C1D21], 0x050506, 0x1A1B1E, 0x2C2E33, wr=31)
    L += stick("R", 264, 182, 0x08090A, [0x34363B, 0x1C1D21], 0x050506, 0x1A1B1E, 0x2C2E33, wr=31)
    L.append(lay(circle(200, 186, 8), fill=0x0D0E10, line=0x3A3C42, lw=1))
    L.append(lay(rrect(190, 202, 20, 6, 3), fill=0x2A2C30, line=0x0A0A0C, lw=1))
    return {"layers": L, "names": {"LT": "L2", "RT": "R2", "LB": "L1", "RB": "R1"}}

def switch():
    edge = 0x0C0D10
    L = []
    trig = segs_path((80, 66), [("C", 80, 40, 88, 14, 108, 12), ("C", 122, 12, 128, 24, 128, 62)])
    bump = segs_path((54, 88), [("C", 66, 70, 100, 62, 134, 68), ("L", 138, 80), ("C", 108, 74, 80, 78, 60, 96)])
    L += bumper_trigger(trig, bump, [0x34373D, 0x1E2024], [0x3A3D44, 0x222429], edge)
    shell = mirror_segs((200, 80), [("C", 170, 74, 150, 68, 128, 68), ("C", 100, 68, 76, 70, 58, 82),
                                    ("C", 40, 94, 34, 112, 30, 130), ("C", 18, 180, 8, 232, 12, 276),
                                    ("C", 16, 310, 34, 330, 58, 328), ("C", 78, 326, 86, 306, 96, 284),
                                    ("C", 108, 262, 124, 252, 148, 250), ("L", 200, 250)])
    L.append(lay(shell, fill=0x000000, alpha=0.35)); L[-1]["shadow"] = True
    L.append(lay(shell, grad=[0x3A3D43, 0x1B1C20], line=edge, lw=1.6))
    L.append(lay(segs_path((34, 200), [("C", 50, 196, 80, 196, 100, 214)], False), line=0x2A2C31, lw=1.4))
    L.append(lay(segs_path((366, 200), [("C", 350, 196, 320, 196, 300, 214)], False), line=0x2A2C31, lw=1.4))
    L += stick("L", 100, 140, 0x101114, [0x3A3D44, 0x24262B], edge, 0x1C1E22, 0x2C2F35)
    L += stick("R", 250, 206, 0x101114, [0x3A3D44, 0x24262B], edge, 0x1C1E22, 0x2C2F35)
    L += dpad_cross(150, 206, 19, 9, [0x3A3D44, 0x24262B], edge, arrows=0x15161A)
    for p, (dx, dy), ch in (("A", (0, 26), "B"), ("B", (26, 0), "A"), ("X", (-26, 0), "Y"), ("Y", (0, -26), "X")):
        cx, cy = 300 + dx, 140 + dy
        L += face_button(p, cx, cy, 12, [0x2E3137, 0x1C1E22], edge, letter(ch, cx, cy, 5), 0xE6E9EE, ACCENT, 0x0B3A36,
                         lw=1.7)
    L += small_button("BACK", 160, 112, 12, 12, 0x1A1C20, edge, glyph=[poly([(156, 112), (164, 112)], False)])
    L += small_button("START", 240, 112, 12, 12, 0x1A1C20, edge,
                      glyph=[poly([(236, 112), (244, 112)], False), poly([(240, 108), (240, 116)], False)])
    L.append(lay(rrect(176, 140, 12, 12, 2), fill=0x1A1C20, line=edge, lw=1))
    L.append(lay(circle(182, 146, 3.5), line=0x4A4E56, lw=1))
    L.append(lay(circle(222, 146, 8), fill=0x1A1C20, line=0x8A8FA0, lw=1.4))
    return {"layers": L, "names": {"LT": "ZL", "RT": "ZR", "LB": "L", "RB": "R"}}

LOOKS = {"xbox": in_front(xbox()), "dualshock": in_front(dualshock()), "dualsense": in_front(dualsense()),
         "switch": in_front(switch())}

def as3_value(v):
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return "0x%06X" % v if v > 255 else str(v)
    if isinstance(v, float):
        return f(v)
    if isinstance(v, list):
        return "[" + ",".join(as3_value(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ",".join("%s:%s" % (json.dumps(k), as3_value(x)) for k, x in v.items()) + "}"
    raise TypeError(v)

HEADER = """package bh.platform
{
   /**
    * The input display's controller drawings (PadDisplay), generated by tools/pad_looks.py: do not edit by hand. Each
    * look is the controller's layers on a 400 x 340 canvas, back to front: "d" path data (M, L, C, Z), "fill" or "grad"
    * [top, bottom], "stroke"/"lw", "alpha"; "part" + "state" ("on" layers show while that control is pressed, faded in
    * with an analog trigger's pull), "knob" ("L"/"R": moves with that stick), "shadow" (drawn offset, under the shell).
    * Drawn by hand after front photos and layout drawings of each controller (proportions only, no art copied).
    */
   public final class PadLooks
   {
      public static const LOOKS:Object = {
"""

FOOTER = """};
   }
}
"""

if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--json", help="also write the looks as JSON")
    ap.add_argument("--out", default="src/platform/as3/bh/platform/PadLooks.as")
    a = ap.parse_args()
    if a.json:
        json.dump(LOOKS, open(a.json, "w"))
    body = []
    for name, look in LOOKS.items():
        body.append('         "%s":{"names":%s,"layers":[\n%s]}' % (
            name, as3_value(look["names"]), ",\n".join("            " + as3_value(l) for l in look["layers"])))
    open(a.out, "w", newline="\n").write(HEADER + ",\n".join(body) + FOOTER)
