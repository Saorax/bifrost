"""import a .bmod as a new item next to the one it was made to replace.

    python tools/bmod_import.py "Hatsune Miku.bmod" [--out DIR] [--token BHMiku] [--name "Hatsune Miku"]
        [--game versions/10.11] [--tables build/tabledata] [--from Xavier]

a .bmod (the community mod format) is an uncompressed SWF with a Metadata tag holding a JSON manifest:
``swfs`` maps a game SWF (``Gfx_Viking.swf``, ``Bones_Hammer.swf``, ...) to the sprites the mod redraws in it,
and ``files`` maps DefineBinaryData IDs to loose files it replaces (map art, images). the tool that made it
replaces those sprites inside the game's own files; this importer keeps the original and adds a new item instead:

1. which item: the game draws a skin from ``file/suffix`` entries in its costumeTypes row
   (``Gfx_Viking.swf/Xavier``, ``Animation_Hammer.swf/SwapXavier``): each bone ``a_<Bone>`` is looked up as
   ``a_<Bone>_<suffix>``. the skin or weapon skin whose suffixes the most of the mod's sprite names end with is
   the one it replaces (``--from`` names it instead).
2. new names: every sprite ending in one of those suffixes is renamed: the suffixes' common part becomes the
   new token (``a_Hair_Xavier`` -> ``a_Hair_BHMiku``, ``..._SwapXavier`` -> ``..._SwapBHMiku``).
3. a SWF of its own: ``Bones_<token>.swf`` holds the mod's shapes and sprites (character IDs unchanged), an
   AS3 class per sprite and a SymbolClass. like the game's sprite classes, each extends MovieClip and sets
   ``a``, the colours the game recolours to the skin's palette, in a frame script.
4. a content mod (``bh.platform.ContentMods``): the new costumeTypes/weaponSkinTypes row is a copy of the
   original with a new name, the loader's IDs, a display name and the new suffixes in free art columns after the
   original's, so the mod's sprites come first and the original's fill in whatever the mod didn't redraw
   (the game tries a skin's art entries from the last one back). ``BoneSources`` maps every new sprite name to
   the new SWF, ``MasterFileList`` lists it, and ``"assets"`` tells the game to read ``bones/Bones_<token>.swf``
   from the mod folder.

map-art and avatar .bmods become map art picked per map and new avatars. nothing from the game is copied into
the mod except the colour lists.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCAL_RABCDASM = ROOT / ".tools" / "rabcdasm" / "bin"
EXE = ".exe" if os.name == "nt" else ""

END, SHOW_FRAME, FILE_ATTRIBUTES, SYMBOL_CLASS, METADATA, DO_ABC, BINARY_DATA = 0, 1, 69, 76, 77, 82, 87
SET_BACKGROUND = 9
NOT_COPIED = {END, SHOW_FRAME, FILE_ATTRIBUTES, SYMBOL_CLASS, METADATA, DO_ABC, BINARY_DATA, SET_BACKGROUND,
              56, 72, 41, 64, 65, 86}

COSTUME_ART = [f"GfxType.CustomArt{n}" if n > 1 else "GfxType.CustomArt" for n in range(1, 11)]
COSTUME_SWAP = [f"SwapCustomArt{n}" if n > 1 else "SwapCustomArt" for n in range(1, 6)]
WEAPON_ART = ["CustomArt", "CustomArt2", "CustomArt3"]


class ImportError_(Exception):
    pass


def read_swf(data: bytes) -> tuple[dict, list[tuple[int, bytes]]]:
    sig = data[:3]
    if sig == b"CWS":
        import zlib
        data = data[:8] + zlib.decompress(data[8:])
    elif sig != b"FWS":
        raise ImportError_(f"not a SWF (starts with {sig!r})")
    nbits = data[8] >> 3
    rect_len = (5 + 4 * nbits + 7) // 8
    rect = data[8:8 + rect_len]
    rate, count = struct.unpack_from("<HH", data, 8 + rect_len)
    pos = 8 + rect_len + 4
    tags = []
    while pos < len(data):
        code_len = struct.unpack_from("<H", data, pos)[0]
        pos += 2
        code, length = code_len >> 6, code_len & 0x3F
        if length == 0x3F:
            length = struct.unpack_from("<I", data, pos)[0]
            pos += 4
        tags.append((code, data[pos:pos + length]))
        pos += length
        if code == END:
            break
    return {"version": data[3], "rect": rect, "rate": rate, "count": count}, tags


def tag_bytes(code: int, body: bytes) -> bytes:
    if len(body) < 0x3F and code not in (20, 21, 35, 36, 90, 6):
        return struct.pack("<H", (code << 6) | len(body)) + body
    return struct.pack("<HI", (code << 6) | 0x3F, len(body)) + body


def write_swf(header: dict, tags: list[tuple[int, bytes]]) -> bytes:
    body = header["rect"] + struct.pack("<HH", header["rate"], header["count"])
    body += b"".join(tag_bytes(c, b) for c, b in tags)
    return b"FWS" + bytes([header["version"]]) + struct.pack("<I", 8 + len(body)) + body


def symbol_class(tag: bytes) -> list[tuple[int, str]]:
    n = struct.unpack_from("<H", tag, 0)[0]
    out, i = [], 2
    for _ in range(n):
        cid = struct.unpack_from("<H", tag, i)[0]
        j = tag.index(b"\0", i + 2)
        out.append((cid, tag[i + 2:j].decode("utf-8")))
        i = j + 1
    return out


def symbol_class_tag(entries: list[tuple[int, str]]) -> bytes:
    return struct.pack("<H", len(entries)) + b"".join(struct.pack("<H", c) + n.encode("utf-8") + b"\0"
                                                        for c, n in entries)


def read_bmod(path: Path) -> dict:
    header, tags = read_swf(path.read_bytes())
    meta, symbols = None, []
    for code, body in tags:
        if code == METADATA:
            text = body.decode("utf-8", "replace").rstrip("\0")
            meta, _ = json.JSONDecoder().raw_decode(text)
        elif code == SYMBOL_CLASS:
            symbols += symbol_class(body)
    if meta is None:
        raise ImportError_(f"{path.name}: no Metadata tag, so not a .bmod")
    return {"header": header, "tags": tags, "meta": meta, "symbols": symbols}


class _Bits:
    def __init__(self, data: bytes, pos: int):
        self.d, self.p, self.b = data, pos, 0

    def ub(self, n: int) -> int:
        v = 0
        for _ in range(n):
            v = (v << 1) | ((self.d[self.p] >> (7 - self.b)) & 1)
            self.b += 1
            if self.b == 8:
                self.b, self.p = 0, self.p + 1
        return v

    def sb(self, n: int) -> int:
        v = self.ub(n)
        return v - (1 << n) if n and v & (1 << (n - 1)) else v

    def align(self) -> None:
        if self.b:
            self.b, self.p = 0, self.p + 1


def _skip_rect(b: bytes, pos: int) -> int:
    r = _Bits(b, pos)
    n = r.ub(5)
    for _ in range(4):
        r.sb(n)
    r.align()
    return r.p


def _skip_matrix(b: bytes, pos: int) -> int:
    r = _Bits(b, pos)
    for _ in range(2):
        if r.ub(1):
            n = r.ub(5)
            r.sb(n)
            r.sb(n)
    n = r.ub(5)
    r.sb(n)
    r.sb(n)
    r.align()
    return r.p


def uses_new_styles(body: bytes) -> bool:
    r = _Bits(body, _style_colours(body, _skip_rect(body, 2), 1, {}))
    nf, nl = r.ub(4), r.ub(4)
    while True:
        if r.ub(1) == 0:
            flags = r.ub(5)
            if flags == 0:
                return False
            if flags & 1:
                n = r.ub(5)
                r.sb(n)
                r.sb(n)
            for bit, bits in ((2, nf), (4, nf), (8, nl)):
                if flags & bit:
                    r.ub(bits)
            if flags & 16:
                return True
        else:
            straight, n = r.ub(1), r.ub(4) + 2
            if straight:
                if r.ub(1):
                    r.sb(n)
                    r.sb(n)
                else:
                    r.ub(1)
                    r.sb(n)
            else:
                for _ in range(4):
                    r.sb(n)


def fix_shapes(tags: list[tuple[int, bytes]]) -> tuple[list[tuple[int, bytes]], int]:
    out, fixed = [], 0
    for code, body in tags:
        if code == 2:
            try:
                if uses_new_styles(body):
                    code, fixed = 22, fixed + 1
            except (IndexError, ValueError):
                pass
        out.append((code, body))
    return out, fixed


FAMILIES = {
    "Hair": ["HairLt", "Hair", "HairDk"],
    "Body1": ["Body1VL", "Body1Lt", "Body1", "Body1Dk", "Body1VD"],
    "Body2": ["Body2VL", "Body2Lt", "Body2", "Body2Dk", "Body2VD"],
    "Special": ["SpecialVL", "SpecialLt", "Special", "SpecialDk", "SpecialVD"],
    "Cloth": ["ClothVL", "ClothLt", "Cloth", "ClothDk"],
    "Weapon": ["WeaponVL", "WeaponLt", "Weapon", "WeaponDk"],
}


def levels_for(family: str, n: int) -> list[str]:
    names = FAMILIES[family]
    base, n = names.index(family), min(n, len(names))
    start = max(0, min(base - (n - 1) // 2, len(names) - n))
    return names[start:start + n]


def _fill_colours(b: bytes, pos: int, ver: int, out: dict) -> int:
    kind = b[pos]
    pos += 1
    size = 4 if ver >= 3 else 3
    if kind == 0:
        out[int.from_bytes(b[pos:pos + 3], "big")] = out.get(int.from_bytes(b[pos:pos + 3], "big"), 0) + 1
        return pos + size
    if kind in (0x10, 0x12, 0x13):
        pos = _skip_matrix(b, pos)
        n = b[pos] & 0x0F
        pos += 1
        for _ in range(n):
            c = int.from_bytes(b[pos + 1:pos + 4], "big")
            out[c] = out.get(c, 0) + 1
            pos += 1 + size
        return pos + (2 if kind == 0x13 else 0)
    if 0x40 <= kind <= 0x43:
        return _skip_matrix(b, pos + 2)
    raise ValueError(f"fill style type {kind:#x}")


def _style_colours(b: bytes, pos: int, ver: int, out: dict) -> int:
    n = b[pos]
    pos += 1
    if n == 0xFF and ver >= 2:
        n, pos = struct.unpack_from("<H", b, pos)[0], pos + 2
    for _ in range(n):
        pos = _fill_colours(b, pos, ver, out)
    return _skip_lines(b, pos, ver)


def _skip_lines(b: bytes, pos: int, ver: int) -> int:
    n = b[pos]
    pos += 1
    if n == 0xFF and ver >= 2:
        n, pos = struct.unpack_from("<H", b, pos)[0], pos + 2
    for _ in range(n):
        if ver == 4:
            join, has_fill = (b[pos + 2] >> 4) & 3, (b[pos + 2] >> 3) & 1
            pos += 4 + (2 if join == 2 else 0)
            pos = _fill_colours(b, pos, ver, {}) if has_fill else pos + 4
        else:
            pos += 2 + (4 if ver >= 3 else 3)
    return pos


def shape_colours(body: bytes, ver: int) -> dict[int, int]:
    out: dict[int, int] = {}
    pos = _skip_rect(body, 2)
    if ver == 4:
        pos = _skip_rect(body, pos) + 1
    r = _Bits(body, _style_colours(body, pos, ver, out))
    nf, nl = r.ub(4), r.ub(4)
    while True:
        if r.ub(1) == 0:
            flags = r.ub(5)
            if flags == 0:
                return out
            if flags & 1:
                n = r.ub(5)
                r.sb(n)
                r.sb(n)
            for bit, bits in ((2, nf), (4, nf), (8, nl)):
                if flags & bit:
                    r.ub(bits)
            if flags & 16:
                r.align()
                r = _Bits(body, _style_colours(body, r.p, max(ver, 2), out))
                nf, nl = r.ub(4), r.ub(4)
        else:
            straight, n = r.ub(1), r.ub(4) + 2
            if straight:
                if r.ub(1):
                    r.sb(n)
                    r.sb(n)
                else:
                    r.ub(1)
                    r.sb(n)
            else:
                for _ in range(4):
                    r.sb(n)


def _sprite_children(body: bytes) -> list[int]:
    pos, out = 4, []
    while pos + 2 <= len(body):
        cl = struct.unpack_from("<H", body, pos)[0]
        pos += 2
        code, ln = cl >> 6, cl & 0x3F
        if ln == 0x3F:
            ln, pos = struct.unpack_from("<I", body, pos)[0], pos + 4
        t = body[pos:pos + ln]
        pos += ln
        if code == 26 and t and t[0] & 0x02:
            out.append(struct.unpack_from("<H", t, 3)[0])
        elif code == 70 and len(t) > 2 and t[0] & 0x02:
            i = 4
            if t[1] & 0x08 or (t[1] & 0x10 and t[0] & 0x02):
                i = t.index(b"\0", i) + 1
            out.append(struct.unpack_from("<H", t, i)[0])
        if code == END:
            break
    return out


def symbol_colours(tags: list[tuple[int, bytes]]) -> dict[str, dict[int, int]]:
    shapes: dict[int, dict[int, int]] = {}
    sprites: dict[int, list[int]] = {}
    names: dict[int, str] = {}
    for code, body in tags:
        ver = {2: 1, 22: 2, 32: 3, 83: 4}.get(code)
        if ver:
            try:
                shapes[struct.unpack_from("<H", body, 0)[0]] = shape_colours(body, ver)
            except (IndexError, ValueError):
                pass
        elif code == 39:
            sprites[struct.unpack_from("<H", body, 0)[0]] = _sprite_children(body)
        elif code == SYMBOL_CLASS:
            names.update(dict(symbol_class(body)))

    def collect(cid: int, seen: set) -> dict[int, int]:
        if cid in shapes:
            return shapes[cid]
        total: dict[int, int] = {}
        for child in sprites.get(cid, []):
            if child not in seen:
                seen.add(child)
                for c, n in collect(child, seen).items():
                    total[c] = total.get(c, 0) + n
        return total
    return {name: collect(cid, {cid}) for cid, name in names.items()}


def _hls(c: int) -> tuple[float, float, float]:
    import colorsys
    return colorsys.rgb_to_hls((c >> 16) / 255, ((c >> 8) & 0xFF) / 255, (c & 0xFF) / 255)


def _hue_gap(a: float, b: float) -> float:
    d = abs(a - b) % 1.0
    return min(d, 1.0 - d)


def is_skin(c: int) -> bool:
    h, l, s = _hls(c)
    return h <= 50 / 360 and s >= 0.2 and 0.45 <= l <= 0.97


def skin_tones(sprite_colours: dict[str, dict[int, int]]) -> tuple[int, int] | None:
    use: dict[int, int] = {}
    for bone, colours in sprite_colours.items():
        part = bone[2:] if bone.startswith("a_") else bone
        if part.startswith(("Eyes", "Mouth", "Weapon")):
            continue
        for c, n in colours.items():
            if is_skin(c):
                use[c] = use.get(c, 0) + n
    if not use:
        return None
    light = max(use, key=lambda c: (use[c], -abs(_hls(c)[1] - 0.75)))
    dark = 0
    for shift in (16, 8, 0):
        dark |= round(((light >> shift) & 0xFF) * 0.8) << shift
    return light, dark


def build_palette(sprite_colours: dict[str, dict[int, int]]) -> tuple[dict[str, int], dict[int, list], list[str]]:
    use: dict[int, int] = {}
    hair: dict[int, int] = {}
    parts: dict[int, set] = {}
    for bone, colours in sprite_colours.items():
        part = bone[2:] if bone.startswith("a_") else bone
        if part.startswith("Weapon"):
            continue
        for c, n in colours.items():
            use[c] = use.get(c, 0) + n
            parts.setdefault(c, set()).add(part)
            if part.startswith("Hair"):
                hair[c] = hair.get(c, 0) + n
    family_of: dict[int, str] = {}
    saturated = []
    for c, n in use.items():
        h, l, s = _hls(c)
        if l < 0.1 or (l > 0.93 and s < 0.25) or is_skin(c):
            continue
        if all(p.startswith(("Eyes", "Mouth")) for p in parts[c]):
            continue
        if s < 0.15:
            family_of[c] = "Cloth"
        elif hair.get(c, 0) * 2 > n:
            family_of[c] = "Hair"
        else:
            saturated.append(c)
    groups: list[list[int]] = []
    for c in sorted(saturated, key=lambda c: -use[c]):
        h = _hls(c)[0]
        for g in groups:
            if _hue_gap(h, _hls(g[0])[0]) <= 35 / 360:
                g.append(c)
                break
        else:
            groups.append([c])
    groups.sort(key=lambda g: -sum(use[c] for c in g))
    for family, g in zip(("Body1", "Body2", "Special"), groups):
        for c in g:
            family_of[c] = family
    defines: dict[str, int] = {}
    table: dict[int, list] = {}
    notes = []
    for family in FAMILIES:
        members = [c for c, f in family_of.items() if f == family]
        if not members:
            continue
        members.sort(key=lambda c: _hls(c)[1], reverse=True)
        distinct, last = 0, None
        for c in members:
            if last is None or last - _hls(c)[1] >= 0.08:
                distinct, last = distinct + 1, _hls(c)[1]
        levels = levels_for(family, max(1, distinct))
        anchors = []
        for i, role in enumerate(levels):
            lo, hi = i * len(members) // len(levels), (i + 1) * len(members) // len(levels)
            anchor = max(members[lo:hi], key=lambda c: use[c])
            anchors.append(anchor)
            defines[role] = anchor
        for c in members:
            h, l, s = _hls(c)
            a = min(anchors, key=lambda x: abs(_hls(x)[1] - l) + 2 * _hue_gap(_hls(x)[0], h))
            ah, al, as_ = _hls(a)
            dh = (h - ah + 0.5) % 1.0 - 0.5
            table[c] = [a, round(dh, 4), round(l - al, 4), round(s - as_, 4)]
        notes.append(f"{family}: {len(members)} shades on " + ", ".join(f"{r} {a:06x}" for r, a in zip(levels, anchors)))
    left = sum(1 for c in use if c not in family_of)
    if notes or left:
        notes.append(f"left as drawn: {left} colours (outlines, whites, skin, eyes and mouths)")
    return defines, table, notes


class _BitWriter:
    def __init__(self) -> None:
        self.out, self.cur, self.n = bytearray(), 0, 0

    def ub(self, v: int, n: int) -> None:
        for i in range(n - 1, -1, -1):
            self.cur = (self.cur << 1) | ((v >> i) & 1)
            self.n += 1
            if self.n == 8:
                self.out.append(self.cur)
                self.cur, self.n = 0, 0

    def done(self) -> bytes:
        if self.n:
            self.ub(0, 8 - self.n)
        return bytes(self.out)


def _nbits(*vals: int) -> int:
    return max(1, *((v.bit_length() if v >= 0 else (~v).bit_length()) + 1 for v in vals))


def write_matrix(a: float, b: float, c: float, d: float, tx: float, ty: float) -> bytes:
    w = _BitWriter()
    sx, sy = round(a * 65536), round(d * 65536)
    w.ub(1, 1)
    n = _nbits(sx, sy)
    w.ub(n, 5)
    w.ub(sx & ((1 << n) - 1), n)
    w.ub(sy & ((1 << n) - 1), n)
    r0, r1 = round(b * 65536), round(c * 65536)
    if r0 or r1:
        w.ub(1, 1)
        n = _nbits(r0, r1)
        w.ub(n, 5)
        w.ub(r0 & ((1 << n) - 1), n)
        w.ub(r1 & ((1 << n) - 1), n)
    else:
        w.ub(0, 1)
    x, y = round(tx * 20), round(ty * 20)
    n = _nbits(x, y)
    w.ub(n, 5)
    w.ub(x & ((1 << n) - 1), n)
    w.ub(y & ((1 << n) - 1), n)
    return w.done()


def read_matrix(b: bytes, pos: int) -> tuple[float, float, float, float, float, float]:
    r = _Bits(b, pos)
    a = d = 1.0
    bb = c = 0.0
    if r.ub(1):
        n = r.ub(5)
        a, d = r.sb(n) / 65536, r.sb(n) / 65536
    if r.ub(1):
        n = r.ub(5)
        bb, c = r.sb(n) / 65536, r.sb(n) / 65536
    n = r.ub(5)
    return a, bb, c, d, r.sb(n) / 20, r.sb(n) / 20


def _rect(b: bytes, pos: int) -> tuple[float, float, float, float]:
    r = _Bits(b, pos)
    n = r.ub(5)
    x0, x1, y0, y1 = (r.sb(n) / 20 for _ in range(4))
    return x0, y0, x1, y1


def _add_box(box: tuple | None, cb: tuple, m: tuple) -> tuple:
    a, b, c, d, tx, ty = m
    for x, y in ((cb[0], cb[1]), (cb[2], cb[1]), (cb[0], cb[3]), (cb[2], cb[3])):
        px, py = a * x + c * y + tx, b * x + d * y + ty
        box = (px, py, px, py) if box is None else (min(box[0], px), min(box[1], py), max(box[2], px), max(box[3], py))
    return box


def character_bounds(tags: list[tuple[int, bytes]]) -> dict[int, tuple[float, float, float, float] | None]:
    shapes, sprites = {}, {}
    for code, body in tags:
        if code in (2, 22, 32, 83):
            shapes[struct.unpack_from("<H", body, 0)[0]] = _rect(body, 2)
        elif code == 39:
            places, pos = [], 4
            while pos + 2 <= len(body):
                cl = struct.unpack_from("<H", body, pos)[0]
                pos += 2
                kind, ln = cl >> 6, cl & 0x3F
                if ln == 0x3F:
                    ln, pos = struct.unpack_from("<I", body, pos)[0], pos + 4
                t = body[pos:pos + ln]
                pos += ln
                if kind == SHOW_FRAME or kind == END:
                    break
                if kind == 26 and t[0] & 0x02:
                    cid = struct.unpack_from("<H", t, 3)[0]
                    m = read_matrix(t, 5) if t[0] & 0x04 else (1, 0, 0, 1, 0, 0)
                    places.append((cid, m))
            sprites[struct.unpack_from("<H", body, 0)[0]] = places
    memo: dict[int, tuple | None] = {}

    def bounds(cid: int, depth: int = 0):
        if cid in memo:
            return memo[cid]
        if cid in shapes:
            memo[cid] = shapes[cid]
            return memo[cid]
        out = None
        for child, m in sprites.get(cid, []) if depth < 20 else []:
            cb = bounds(child, depth + 1)
            if cb is not None:
                out = _add_box(out, cb, m)
        memo[cid] = out
        return out
    return {cid: bounds(cid) for cid in list(shapes) + list(sprites)}


def headshot_pose(game: Path, tables: Path) -> list[tuple[str, tuple]]:
    sys.path.insert(0, str(ROOT / "tools"))
    import anm
    data = anm.decode((game / "anims" / "Animation_Player.anm").read_bytes())
    cls = next(c for c in data["classes"] if c["index"] == "a__HeadShotAnimation")
    frame = next(a for a in cls["animations"] if a["name"] == "FaceIdle")["frames"][0]
    names = re.findall(r"<Bone>([^<]*)</Bone>", (tables / "Init" / "BoneTypes.xml").read_text(encoding="utf-8"))
    pose, m, pos = [], (1.0, 0.0, 0.0, 1.0), (0.0, 0.0)
    for bone in frame["bones"]:
        if bone["transform"] != "prev":
            m = tuple(anm.as_float32(v) for v in bone["m"]) if isinstance(bone.get("m"), list) else m
        if bone["pos"] != "prev":
            pos = tuple(anm.as_float32(v) for v in bone["pos"])
        name = names[bone["id"] - 1]
        if name.endswith("R") and name[:-1] in names:
            continue
        pose.append((name, (m[0], m[1], m[2], m[3], pos[0], pos[1])))
    return pose


def rect_shape(shape_id: int, box: tuple[float, float, float, float]) -> bytes:
    x0, y0, x1, y1 = (round(v * 20) for v in box)
    w = _BitWriter()
    n = _nbits(x0, y0, x1, y1)
    w.ub(n, 5)
    for v in (x0, x1, y0, y1):
        w.ub(v & ((1 << n) - 1), n)
    bounds = w.done()
    w = _BitWriter()
    w.ub(1, 4)
    w.ub(0, 4)
    w.ub(0, 1)
    w.ub(0b00101, 5)
    n = _nbits(x0, y0)
    w.ub(n, 5)
    w.ub(x0 & ((1 << n) - 1), n)
    w.ub(y0 & ((1 << n) - 1), n)
    w.ub(1, 1)
    for dx, dy in ((x1 - x0, 0), (0, y1 - y0), (x0 - x1, 0), (0, y0 - y1)):
        d = dx or dy
        m = max(2, _nbits(d))
        w.ub(1, 1)
        w.ub(1, 1)
        w.ub(m - 2, 4)
        w.ub(0, 1)
        w.ub(0 if dx else 1, 1)
        w.ub(d & ((1 << m) - 1), m)
    w.ub(0, 6)
    return struct.pack("<H", shape_id) + bounds + bytes([1, 0, 0xFF, 0xFF, 0xFF, 0]) + w.done()


def icon_sprite(icon_id: int, parts: list[tuple[int, tuple]], bounds: dict, target: tuple,
                fit: set | None = None, fill: float = 1.0, drop: float = 0.0,
                centre: tuple[float, float] | None = None, mask_id: int | None = None) -> bytes | None:
    box = None
    for cid, m in parts:
        cb = bounds.get(cid)
        if cb is not None and not (fit and cid not in fit):
            box = _add_box(box, cb, m)
    if box is None:
        return None
    scale = fill * min((target[2] - target[0]) / max(1e-6, box[2] - box[0]),
                       (target[3] - target[1]) / max(1e-6, box[3] - box[1]))
    cx, cy = centre if centre else ((target[0] + target[2]) / 2, (target[1] + target[3]) / 2)
    ox = cx - scale * (box[0] + box[2]) / 2
    oy = cy - scale * (box[1] + box[3]) / 2 + drop * (target[3] - target[1])
    inner = b""
    first = 1
    if mask_id is not None:
        inner += tag_bytes(26, bytes([0x46]) + struct.pack("<HH", 1, mask_id) + write_matrix(1, 0, 0, 1, 0, 0) +
                           struct.pack("<H", len(parts) + 1))
        first = 2
    for depth, (cid, (a, b, c, d, tx, ty)) in enumerate(parts, first):
        m = write_matrix(a * scale, b * scale, c * scale, d * scale, tx * scale + ox, ty * scale + oy)
        inner += tag_bytes(26, bytes([0x06]) + struct.pack("<HH", depth, cid) + m)
    inner += tag_bytes(SHOW_FRAME, b"") + tag_bytes(END, b"")
    return struct.pack("<HH", icon_id, 1) + inner


def read_csv_table(tables: Path, name: str) -> tuple[list[str], list[dict]]:
    path = tables / "Game" / f"{name}.csv"
    rows = list(csv.reader(io.StringIO(path.read_text(encoding="utf-8"))))
    header = rows[1]
    return header, [dict(zip(header, r)) for r in rows[2:] if r and r[0] and r[0] != "Template"]


def suffixes(row: dict, columns: list[str]) -> dict[str, str]:
    out = {}
    for col in columns:
        value = (row.get(col) or "").strip()
        if "/" in value:
            out.setdefault(value.split(":")[-1].split("/", 1)[1], col)
    return out


def common_part(words: list[str]) -> str:
    first = min(words, key=len)
    for size in range(len(first), 0, -1):
        for start in range(len(first) - size + 1):
            part = first[start:start + size]
            if all(part in w for w in words):
                return part
    return first


def find_item(names: list[str], tables: Path, wanted: str | None = None) -> dict:
    candidates = []
    for table, art, swap in (("costumeTypes", COSTUME_ART, COSTUME_SWAP), ("weaponSkinTypes", WEAPON_ART, [])):
        header, rows = read_csv_table(tables, table)
        for row in rows:
            key = row[header[0]]
            if wanted and key != wanted:
                continue
            found = suffixes(row, art + swap)
            hits = {s: [n for n in names if n.endswith("_" + s)] for s in found}
            hits = {s: v for s, v in hits.items() if v}
            if not hits:
                continue
            score = sum(len(v) for v in hits.values())
            weapon = row.get("BaseWeapon", "")
            bonus = sum(1 for n in names if weapon and weapon in n) if table == "weaponSkinTypes" else 0
            candidates.append((score, bonus, table == "costumeTypes", table, key, row, header, hits, found))
    if not candidates:
        raise ImportError_("no skin or weapon skin uses the suffixes of this mod's sprites" +
                           (f" (--from {wanted})" if wanted else ""))
    candidates.sort(key=lambda c: (c[0], c[2], c[1]), reverse=True)
    score, _, _, table, key, row, header, hits, found = candidates[0]
    return {"table": table, "key": key, "row": row, "header": header, "hits": hits, "columns": found}


def tool(name: str, base: str | None) -> str:
    base = base or os.environ.get("RABCDASM_DIR") or (str(LOCAL_RABCDASM) if (LOCAL_RABCDASM / (name + EXE)).exists() else None)
    path = Path(base) / (name + EXE) if base else shutil.which(name)
    if not path or not Path(path).exists():
        raise ImportError_(f"RABCDAsm tool {name!r} not found (python tools/setup_rabcdasm.py, or --rabcdasm DIR)")
    return str(path)


COLOUR_RE = re.compile(r"^\s*push(?:int|uint|short|byte)\s+(-?\d+)\s*$")


def colours_in_class(text: str) -> list[int] | None:
    m = re.search(r'"frame1"\)\s*\n\s*method(.*?)end ; method', text, re.S)
    if not m:
        return None
    values, found = [], None
    for line in m.group(1).split("\n"):
        c = COLOUR_RE.match(line)
        if c:
            values.append(int(c.group(1)))
        elif line.strip().startswith("newarray"):
            count = int(line.split()[1])
            found = values[len(values) - count:] if count else []
        elif "initproperty" in line and '"a")' in line and found is not None:
            return found
    return None


def game_colours(game: Path, swf_names: list[str], rabcdasm: str | None, work: Path) -> dict[str, list[int] | None]:
    out: dict[str, list[int] | None] = {}
    for n, name in enumerate(swf_names):
        src = next((p for p in (game / name, game / "bones" / name) if p.exists()), None)
        if src is None:
            continue
        d = work / f"game{n}"
        d.mkdir()
        shutil.copy(src, d / "g.swf")
        subprocess.run([tool("abcexport", rabcdasm), "g.swf"], cwd=d, check=True, capture_output=True)
        for abc in sorted(d.glob("g-*.abc")):
            subprocess.run([tool("rabcdasm", rabcdasm), abc.name], cwd=d, check=True, capture_output=True)
            for cls in (d / abc.stem).rglob("*.class.asasm"):
                out[cls.name[:-len(".class.asasm")]] = colours_in_class(cls.read_text(encoding="utf-8", errors="replace"))
    return out


def class_asasm(name: str, colours: list[int] | None) -> str:
    frame = ""
    ctor_frame = ""
    if colours is not None:
        pushes = "".join(f"      pushint             {c}\n" for c in colours)
        frame = f"""  trait method QName(PackageInternalNs(""), "frame1")
   method
    refid "{name}/instance/frame1"
    body
     maxstack {max(2, len(colours) + 1)}
     localcount 1
     initscopedepth 10
     maxscopedepth 11
     code
      getlocal0
      pushscope

      getlocal0
{pushes}      newarray            {len(colours)}
      initproperty        QName(PackageNamespace(""), "a")

      returnvoid
     end ; code
    end ; body
   end ; method
  end ; trait
"""
        ctor_frame = """
     findpropstrict      QName(PackageNamespace(""), "addFrameScript")
     pushbyte            0
     getlocal0
     getproperty         QName(PackageInternalNs(""), "frame1")
     callpropvoid        QName(PackageNamespace(""), "addFrameScript"), 2
"""
    return f"""class
 refid "{name}"
 instance QName(PackageNamespace(""), "{name}")
  extends QName(PackageNamespace("flash.display"), "MovieClip")
  flag PROTECTEDNS
  protectedns ProtectedNamespace("{name}")
  iinit
   refid "{name}/instance/init"
   body
    maxstack 3
    localcount 1
    initscopedepth 10
    maxscopedepth 11
    code
     getlocal0
     pushscope

     getlocal0
     constructsuper      0
{ctor_frame}
     returnvoid
    end ; code
   end ; body
  end ; method
  trait slot QName(PackageNamespace(""), "a") type QName(PackageNamespace(""), "Array") end
{frame} end ; instance
 cinit
  refid "{name}/class/init"
  body
   maxstack 1
   localcount 1
   initscopedepth 9
   maxscopedepth 10
   code
    getlocal0
    pushscope

    returnvoid
   end ; code
  end ; body
 end ; method
end ; class
"""


BASES = [("", "Object"), ("flash.events", "EventDispatcher"), ("flash.display", "DisplayObject"),
         ("flash.display", "InteractiveObject"), ("flash.display", "DisplayObjectContainer"),
         ("flash.display", "Sprite"), ("flash.display", "MovieClip")]


def script_asasm(name: str) -> str:
    scopes = "".join(f'    getlex              QName(PackageNamespace("{p}"), "{c}")\n    pushscope\n\n' for p, c in BASES)
    return f"""script
 sinit
  refid "{name}/init"
  body
   maxstack 2
   localcount 1
   initscopedepth 1
   maxscopedepth 9
   code
    getlocal0
    pushscope

    getscopeobject      0
{scopes}    getlex              QName(PackageNamespace("flash.display"), "MovieClip")
    newclass            "{name}"
{("    popscope" + chr(10)) * len(BASES)}    initproperty        QName(PackageNamespace(""), "{name}")

    returnvoid
   end ; code
  end ; body
 end ; method
 trait class QName(PackageNamespace(""), "{name}") slotid 1
  #include "{name}.class.asasm"
 end ; trait
end ; script
"""


def build_abc(classes: dict[str, list[int] | None], rabcdasm: str | None, work: Path) -> bytes:
    d = work / "abc"
    d.mkdir()
    for name, colours in classes.items():
        (d / f"{name}.class.asasm").write_text(class_asasm(name, colours), encoding="utf-8")
        (d / f"{name}.script.asasm").write_text(script_asasm(name), encoding="utf-8")
    includes = "".join(f' #include "{n}.script.asasm"\n' for n in classes)
    (d / "main.asasm").write_text(f"#version 4\nprogram\n minorversion 16\n majorversion 46\n\n{includes}end ; program\n",
                                  encoding="utf-8")
    subprocess.run([tool("rabcasm", rabcdasm), "main.asasm"], cwd=d, check=True, capture_output=True)
    return (d / "main.abc").read_bytes()


def check_recolouring(swf_path: Path, classes: dict, make_swf, game: Path) -> tuple[bytes, list[str]]:
    import sprite_check
    swf = swf_path.read_bytes()
    names = [n for code, body in read_swf(swf)[1] if code == SYMBOL_CLASS for _, n in symbol_class(body)]
    dropped, start = [], 0
    while start < len(names):
        status, lines = sprite_check.check(swf_path, game, 600, start=start)
        if status == "ok":
            break
        started = [l[len("class "):] for l in lines if l.startswith("class ")]
        if not started:
            raise ImportError_("tools/sprite_check.py didn't start: " + (lines[-1] if lines else "no log"))
        bad = started[-1]
        dropped.append(bad)
        classes[bad] = None
        swf = make_swf()
        swf_path.write_bytes(swf)
        start = names.index(bad) + 1
    return swf, dropped


def token_for(name: str) -> str:
    words = re.findall(r"[A-Za-z0-9]+", name)
    return "BH" + "".join(w[:1].upper() + w[1:] for w in words)[:40]


def _mod_id(token: str) -> str:
    return re.sub(r"[^a-z0-9._-]+", "-", ("bmod-" + token[2:]).lower()).strip("-")


def _mod_swf(mod: dict, art: list, classes: dict[str, list[int] | None], symbols: bytes, rabcdasm: str | None) -> bytes:
    with tempfile.TemporaryDirectory() as tmp:
        abc = build_abc(classes, rabcdasm, Path(tmp))
    tags = [(FILE_ATTRIBUTES, struct.pack("<I", 0x08)), (SET_BACKGROUND, bytes([255, 255, 255]))] + art
    tags += [(DO_ABC, struct.pack("<I", 1) + bytes(1) + abc), (SYMBOL_CLASS, symbols), (SHOW_FRAME, b""), (END, b"")]
    return write_swf(dict(mod["header"], version=max(15, mod["header"]["version"]), count=1), tags)


def _binary_data(mod: dict) -> dict[int, bytes]:
    return {struct.unpack_from("<H", b, 0)[0]: b[6:] for c, b in mod["tags"] if c == BINARY_DATA}


def import_bmod(path: Path, out: Path, game: Path, tables: Path, token: str | None = None,
                display: str | None = None, wanted: str | None = None, rabcdasm: str | None = None,
                palette: bool = True, check: bool = False, hands: str = "bare", sounds: Path | None = None) -> dict:
    mod = read_bmod(path)
    meta = mod["meta"]
    swfs = meta.get("swfs") or {}
    names = sorted({n for spec in swfs.values() for n in spec.get("sprites", [])})
    report = []
    files = meta.get("files") or {}
    if any(n.startswith("a_AvatarIcon_") for n in names) or (not names and any(
            f.startswith(("a_AvatarIcon_", "a_Flag")) for f in files.values())):
        return import_avatars(path, mod, out, game, tables, rabcdasm)
    if not names and files:
        return import_map_art(path, mod, out, tables)
    if not names:
        raise ImportError_(f"{path.name} redraws no sprites; only skin and weapon skin .bmods can be imported so far")
    item = find_item(names, tables, wanted)
    hits = item["hits"]
    matched = sum(len(v) for v in hits.values())
    if not wanted and matched * 2 < len(names):
        raise ImportError_(f"only {matched} of its {len(names)} sprites are named after one item "
                           f"({item['table']}/{item['key']}), so it doesn't look like a skin or weapon skin; "
                           "--from names the item to import it as anyway")
    core = common_part(list(hits))
    token = token or token_for(meta.get("name") or path.stem)
    display = display or meta.get("name") or path.stem
    new_suffix = {s: s.replace(core, token) for s in hits}
    rename = {}
    for s, sprites in hits.items():
        for n in sprites:
            rename.setdefault(n, n[:-len(s)] + new_suffix[s])
    body_suffix = next((s for s in hits if not s.startswith("Swap")), None)
    body_new = new_suffix[body_suffix] if body_suffix is not None else None
    roster_pose = roster_gem = None
    if item["table"] == "costumeTypes":
        for n in names:
            if n.startswith("a_Roster_Pose_"):
                rename[n] = f"a_Roster_Pose_{token}" + ("M" if n.endswith("M") else "")
                roster_pose = f"a_Roster_Pose_{token}"
            elif n.startswith("a_Roster_Gem_"):
                rename[n] = roster_gem = f"a_Roster_Gem_{token}"
    if item["table"] == "costumeTypes" and body_new:
        for n in names:
            if n not in rename and "_Swap" not in n:
                rename[n] = f"{n}_{body_new}"
    skipped = [n for n in names if n not in rename]
    by_id = {name: cid for cid, name in mod["symbols"]}
    missing = [n for n in rename if n not in by_id]
    for n in missing:
        rename.pop(n)
    with tempfile.TemporaryDirectory() as tmp:
        colours = game_colours(game, list(swfs), rabcdasm, Path(tmp))
    row = item["row"]
    defines = {}
    for levels in FAMILIES.values():
        for role in levels:
            try:
                defines[role] = int((row.get(role + "_Define") or "").strip(), 16)
            except ValueError:
                pass
    new_defines, palette_table, hand_colours = {}, {}, {}
    animation_aliases: dict[str, str] = {}
    crossover_name = None
    weapon_rows: list[dict] = []
    weapon_strings: dict[str, str] = {}
    mod_symbols = symbol_colours(mod["tags"]) if palette else {}
    if palette:
        body = {}
        for old in rename:
            if colours.get(old) is not None and old in mod_symbols:
                suffix = next(s for s in hits if old.endswith("_" + s))
                body[old[:-len(suffix) - 1]] = mod_symbols[old]
        if body:
            new_defines, palette_table, notes = build_palette(body)
            report += ["palette " + note for note in notes]
        skin = skin_tones(body)
        if skin and item["table"] == "costumeTypes":
            hand_colours = {"HandsLt_Swap": skin[0], "HandsDk_Swap": skin[1], "HandsSkinLt_Swap": skin[0],
                            "HandsSkinDk_Swap": skin[1]}
            report.append(f"hands in the skin tone {skin[0]:06x} / {skin[1]:06x}")

    def colour_list(old: str) -> list[int] | None:
        if not palette or colours.get(old) is None:
            return None
        return sorted({palette_table[c][0] for c in mod_symbols.get(old, {}) if c in palette_table})
    classes = {rename[n]: colour_list(n) for n in sorted(rename)}
    swf_name = f"Bones_{token}.swf"
    art, fixed = fix_shapes([(c, b) for c, b in mod["tags"] if c not in NOT_COPIED])
    if fixed:
        report.append(f"{fixed} shapes declare styles mid-shape as DefineShape; made DefineShape2 (the SWF format "
                      "allows new styles only there)")
    symbol_list = [(by_id[old], new) for old, new in sorted(rename.items())]
    icon_name = None
    if item["table"] == "costumeTypes":
        try:
            pose = headshot_pose(game, tables) if body_suffix else []
        except (OSError, StopIteration, KeyError, IndexError):
            pose = []
        parts = []
        for bone, m in pose:
            old = f"{bone}_{body_suffix}"
            if old in rename and old in by_id:
                parts.append((by_id[old], m))
        original_icon = (row.get("CostumeIcon") or "").strip()
        target = None
        icons = game / "UI_Icons.swf"
        if original_icon and icons.exists():
            icon_tags = read_swf(icons.read_bytes())[1]
            ids = {n: cid for c, b in icon_tags if c == SYMBOL_CLASS for cid, n in symbol_class(b)}
            if original_icon in ids:
                target = character_bounds(icon_tags).get(ids[original_icon])
        if parts:
            icon_id = max(struct.unpack_from("<H", b, 0)[0] for c, b in art if c in (2, 22, 32, 83, 39, 6, 20, 21, 35, 36, 90)) + 1
            jaw = by_id.get(f"a_Jaw_{body_suffix}")
            face = {jaw} if jaw in {cid for cid, _ in parts} else None
            art_bounds = character_bounds(art)
            sprite = icon_sprite(icon_id, parts, art_bounds, target or (-40.0, -40.0, 40.0, 40.0), face,
                                 fill=0.95, drop=0.0, centre=(0.0, 0.0))
            if sprite:
                icon_name = f"a_SkinIcon_{token}"
                art.append((39, sprite))
                symbol_list.append((icon_id, icon_name))
                classes[icon_name] = None
                report.append(f"skin icon {icon_name}: {len(parts)} head parts in the head-shot pose")
    symbols = symbol_class_tag(symbol_list)

    def make_swf() -> bytes:
        return _mod_swf(mod, art, classes, symbols, rabcdasm)

    mod_id = _mod_id(token)
    folder = out / mod_id
    (folder / "bones").mkdir(parents=True, exist_ok=True)
    swf_path = folder / "bones" / swf_name
    swf = make_swf()
    swf_path.write_bytes(swf)
    if check and any(v is not None for v in classes.values()):
        swf, dropped = check_recolouring(swf_path, classes, make_swf, game)
        if dropped:
            report.append(f"the game's recolouring breaks the Flash runtime on {len(dropped)} sprites "
                          f"(tools/sprite_check.py); drawn in the mod's own colours: " + ", ".join(dropped))
        else:
            report.append("every recoloured sprite passed tools/sprite_check.py")

    header = item["header"]
    key_col = header[0]
    art_cols = COSTUME_ART + COSTUME_SWAP if item["table"] == "costumeTypes" else WEAPON_ART
    used = {c for c in art_cols if (row.get(c) or "").strip()}
    string_key = f"{token}_DisplayName"
    new_key = token if item["table"] == "costumeTypes" else (row.get("BaseWeapon") or "") + token
    sets = {key_col: new_key, "DisplayNameKey": string_key}
    sets[("CostumeID" if item["table"] == "costumeTypes" else "WeaponSkinID")] = "@id"
    for role, colour in sorted(new_defines.items()):
        if role + "_Define" in header:
            sets[role + "_Define"] = f"0x{colour:06X}"
    for column, colour in hand_colours.items():
        if column in header:
            sets[column] = f"0x{colour:06X}"
    weapon_set = (row.get("WeaponSet") or "").strip() if item["table"] == "costumeTypes" else ""
    if weapon_set and body_suffix and any(n.startswith("a_Weapon") and n in rename for n in names):
        w_header, w_rows = read_csv_table(tables, "weaponSkinTypes")
        for w in w_rows:
            base = (w.get("BaseWeapon") or "").strip()
            if w[w_header[0]] != base + weapon_set:
                continue
            w_sets = {w_header[0]: base + token, "WeaponSkinID": "@id",
                      "DisplayNameKey": f"{token}_{base}_DisplayName"}
            for col in WEAPON_ART:
                value = (w.get(col) or "").strip()
                if value.endswith("/" + body_suffix):
                    w_sets[col] = value[:-len(body_suffix)] + new_suffix[body_suffix]
            weapon_rows.append({"copy": w[w_header[0]], "set": w_sets})
            weapon_strings[f"{token}_{base}_DisplayName"] = f"{display} {base}"
        if weapon_rows:
            sets["WeaponSet"] = token
            report.append("weapons: " + ", ".join(r["set"][w_header[0]] + " (copy of " + r["copy"] + ")" for r in weapon_rows))
    if item["table"] == "costumeTypes" and hands == "bare" and not any("Hand" in n for n in names):
        for col in COSTUME_ART:
            if (row.get(col) or "").startswith("Gfx_Hands.swf/") and row[col] != "Gfx_Hands.swf/Bare":
                sets[col] = "Gfx_Hands.swf/Bare"
                report.append(f"bare hands (Gfx_Hands.swf/Bare instead of {row[col]}): the mod draws none")
    if item["table"] == "costumeTypes":
        sets["CostumeIndex"] = "@id/OwnerHero"
        if icon_name:
            sets["CostumeIcon"] = icon_name
        if roster_pose:
            sets["IsCrossover"] = "TRUE"
            sets["RosterOrderID"] = "@id"
            if roster_gem:
                sets["CrossoverGem"], sets["CrossoverGemFileName"] = roster_gem, "UI_Roster"
            else:
                for column in ("CrossoverGem", "CrossoverGemFileName"):
                    if column in header and (row.get(column) or "").strip():
                        sets[column] = "@none"
            sets["ReplacementPortrait"], sets["ReplacementPortraitFileName"] = roster_pose, "UI_Icons"
            if (row.get("ParentCrossover") or "").strip():
                sets["ParentCrossover"] = "@none"
            crossover_name = f"Generated|CostumeType_{token}_DisplayNameWRTCrossover"
            report.append(f"a crossover with the mod's roster portrait {roster_pose}")
        else:
            if "ReplacementHeroName" in header:
                sets["ReplacementHeroName"] = display
            if (row.get("IsCrossover") or "").strip().lower() == "true":
                sets["IsCrossover"] = "FALSE"
                for column in ("CrossoverGem", "CrossoverGemFileName", "ReplacementPortrait",
                               "ReplacementPortraitFileName", "ParentCrossover", "RosterOrderID"):
                    if column in header and (row.get(column) or "").strip():
                        sets[column] = "@none"
                report.append(f"a normal skin named {display} (not a crossover like {item['key']})")
        if (row.get("OverrideSelectAnims") or "").strip().lower() == "true":
            animation_aliases[token] = item["key"]
            report.append(f"character select plays {item['key']}'s animations (Idle{item['key']}, Selected{item['key']})")
    else:
        sets["DbID"] = "@id"
    for s, col in item["columns"].items():
        if s not in new_suffix:
            continue
        value = row[col].replace("/" + s, "/" + new_suffix[s])
        group = COSTUME_SWAP if col in COSTUME_SWAP else (COSTUME_ART if col in COSTUME_ART else WEAPON_ART)
        free = [c for c in reversed(group) if c not in used and c in header]
        if free and group.index(free[0]) > group.index(col):
            sets[free[0]] = value
            used.add(free[0])
        else:
            sets[col] = value
            report.append(f"no free art column after {col}: parts the mod doesn't redraw won't show the original's")
    size_kb = max(1, (len(swf) + 1023) // 1024)
    power_rows: list = []
    sound_banks: list = []
    if item["table"] == "costumeTypes":
        ps_path = tables / "Game" / "PowerSwapTypes.xml"
        ps_text = ps_path.read_text(encoding="utf-8") if ps_path.exists() else ""
        own_rows = [r for r in re.findall(r"<PowerSwapType [^>]*>.*?</PowerSwapType>", ps_text, re.S)
                    if f'OwnerCostume="{item["key"]}"' in r.split(">", 1)[0]]
        wanted = set()
        for col in ("NameSoundEvent", "OnSelectedSoundEvent"):
            if (row.get(col) or "").strip():
                wanted.add(row[col].strip().rpartition(":")[2])
        for r in own_rows:
            wanted.update(v.rpartition(":")[2] for v in re.findall(r"<(?:Cast|Hit)SoundEvent>([^<]+)<", r))
        new_events = {old: (old.replace(core, token) if core in old else f"{token}_{old}") for old in wanted}
        event_map: dict[str, str] = {}
        bank_root = sounds
        if bank_root is None:
            found = [b for b in path.parent.rglob("*.bnk") if "pc" in [part.lower() for part in b.parts]]
            if found:
                parts = [part.lower() for part in found[0].parts]
                bank_root = Path(*found[0].parts[:len(parts) - parts[::-1].index("pc")])
        if bank_root is not None and new_events:
            import wwise_bank
            defaults_csv = tables / "Engine" / "DefaultSoundBanks.csv"
            defaults = {line.split(",")[0].strip().replace("\\", "/").lower()
                        for line in (defaults_csv.read_text(encoding="utf-8").splitlines()[2:] if defaults_csv.exists() else [])}
            common, legend = [], []
            for mod_bank in sorted(bank_root.rglob("*.bnk")):
                rel = mod_bank.relative_to(bank_root)
                game_bank = game / "audio" / "pc" / rel
                if game_bank.exists():
                    piece = (wwise_bank.read_bank(game_bank.read_bytes()), wwise_bank.read_bank(mod_bank.read_bytes()),
                             new_events)
                    (common if rel.as_posix().lower() in defaults else legend).append(piece)
            made_all = []
            for pieces, name in ((common, f"{token}_Common"), (legend, token)):
                if not pieces:
                    continue
                bank_bytes, made = wwise_bank.build(name, pieces)
                if not made:
                    continue
                (folder / "audio").mkdir(parents=True, exist_ok=True)
                (folder / "audio" / f"{name}.bnk").write_bytes(bank_bytes)
                if pieces is common:
                    sound_banks.append(f"audio/{name}.bnk")
                elif weapon_rows:
                    for w in weapon_rows:
                        w["set"]["SoundBank"] = f"@mod:audio/{name}"
                else:
                    sound_banks.append(f"audio/{name}.bnk")
                    report.append(f"no weapon skins to load audio/{name}.bnk with: loaded at start-up, before the "
                                  "legend's bank, its sounds may skip the game's volume")
                made_all += made
                report.append(f"sounds: {len(made)} events in audio/{name}.bnk (" + ", ".join(sorted(made)[:3]) +
                              (", ..." if len(made) > 3 else "") + ")")
            event_map = {old: new for old, new in new_events.items() if new in made_all}

        def swap_event(value: str) -> str:
            prefix, sep, bare = value.rpartition(":")
            return prefix + sep + event_map[bare] if bare in event_map else value
        for col in ("NameSoundEvent", "OnSelectedSoundEvent"):
            value = (row.get(col) or "").strip()
            if value and swap_event(value) != value:
                sets[col] = swap_event(value)
        effect_names: set[str] = set()
        for sfx in game.glob("SFX_*.swf"):
            try:
                effect_names |= {n for c, b in read_swf(sfx.read_bytes())[1] if c == SYMBOL_CLASS for _, n in symbol_class(b)}
            except (OSError, ImportError_, struct.error):
                pass
        swap_suffixes = [s for s in hits if s.startswith("Swap")] or list(hits)

        def effect(name: str) -> str:
            if name in rename:
                return rename[name]
            for suffix in swap_suffixes:
                if name.endswith("_" + suffix) and name in effect_names and name[:-len(suffix) - 1] in effect_names:
                    return name[:-len(suffix) - 1]
            return name
        art_entries = [v for col, v in sets.items() if col in COSTUME_ART + COSTUME_SWAP and "/" in v
                       and v.rsplit("/", 1)[1] in new_suffix.values()]
        power_csv = tables / "Game" / "powerTypes.csv"
        p_rows = list(csv.reader(io.StringIO(power_csv.read_text(encoding="utf-8"))))[1:] if power_csv.exists() else []
        p_header = p_rows[0] if p_rows else []
        hero = (row.get("OwnerHero") or "").strip()
        base_gfx: dict[str, dict[str, dict[str, str]]] = {}
        for pr in p_rows[1:]:
            d = dict(zip(p_header, pr))
            name = d.get("PowerName", "")
            if not hero or not name.endswith(hero):
                continue
            kinds = {k: {col.split(".", 1)[1]: v for col, v in d.items() if col.startswith(k + "Gfx.") and v.strip()}
                     for k in ("Cast", "Fire", "Hit")}
            if any(g.get("AnimClass") for g in kinds.values()):
                base_gfx[name] = kinds
        own_by_power = {re.search(r"<TargetPower>([^<]*)<", r).group(1): r for r in own_rows if "<TargetPower>" in r}

        def gfx_xml(kind: str, inner: str | None, base: dict[str, str]) -> str:
            if inner is None or not inner.strip():
                if not base.get("AnimClass"):
                    return f"<{kind}Gfx/>"
                inner = "".join(f"<{k}>{v}</{k}>" for k, v in base.items())
            inner = re.sub(r"<AnimClass>([^<]*)</AnimClass>", lambda m: f"<AnimClass>{effect(m.group(1))}</AnimClass>", inner)
            if "<AnimClass>" in inner:
                taken = len(re.findall(r"<CustomArt\d*>", inner))
                inner += "".join(f"<CustomArt{taken + i + 1}>{v}</CustomArt{taken + i + 1}>" for i, v in enumerate(art_entries))
            return f"<{kind}Gfx>{inner}</{kind}Gfx>"
        for power in sorted(set(own_by_power) | set(base_gfx)):
            own = own_by_power.get(power, f'<PowerSwapType OwnerCostume="{item["key"]}"><TargetPower>{power}</TargetPower>'
                                          f'<CastGfx/><FireGfx/><HitGfx/></PowerSwapType>')
            r2 = own.replace(f'OwnerCostume="{item["key"]}"', f'OwnerCostume="{new_key}"', 1)
            r2 = re.sub(r"<(CastSoundEvent|HitSoundEvent)>([^<]*)</(?:CastSoundEvent|HitSoundEvent)>",
                        lambda m: f"<{m.group(1)}>{swap_event(m.group(2))}</{m.group(1)}>", r2)
            for kind in ("Cast", "Fire", "Hit"):
                m = re.search(rf"<{kind}Gfx/>|<{kind}Gfx>(.*?)</{kind}Gfx>", r2, re.S)
                new_gfx = gfx_xml(kind, m.group(1) if m else None, base_gfx.get(power, {}).get(kind, {}))
                r2 = r2[:m.start()] + new_gfx + r2[m.end():] if m else r2.replace("</PowerSwapType>", new_gfx + "</PowerSwapType>")
            power_rows.append({"add": r2})
        if power_rows:
            report.append(f"powers: {len(power_rows)} PowerSwapTypes rows ({len(own_rows)} copied from {item['key']}'s), "
                          "their effects drawn with the new skin's art")
    bones = "".join(f"<Bone>{n}</Bone>" for n in sorted(rename.values()))
    manifest = {
        "id": mod_id,
        "name": display,
        "version": str(meta.get("version") or "1.0"),
        "description": (f"Imported from {path.name} ({meta.get('author') or 'unknown author'}) by tools/bmod_import.py: "
                        f"a new {'skin' if item['table'] == 'costumeTypes' else 'weapon skin'} made from "
                        f"{item['table']}/{item['key']} with the mod's art; the original is unchanged."),
        "strings": {"English": dict({string_key: display}, **weapon_strings,
                                    **({crossover_name: f"{display} (Crossover)"} if crossover_name else {}))},
        "assets": {f"bones/{swf_name}": f"bones/{swf_name}"},
        "palette": {"costume": new_key, "colours": {f"{c:06x}": [f"{v[0]:06x}"] + v[1:] for c, v in
                                                    sorted(palette_table.items())}} if palette_table else None,
        "tables": {
            item["table"]: [{"copy": item["key"], "set": sets}],
            **({"weaponSkinTypes": weapon_rows} if weapon_rows else {}),
            **({"PowerSwapTypes": power_rows} if power_rows else {}),
            "MasterFileList": [f'<File Stage="Game" ExcludedPlatforms="" Size="{size_kb}" Name="bones/{swf_name}" Load="" />'],
            "BoneSources": [f'<Original name="{token}"><Target name="{swf_name}">{bones}</Target></Original>'],
        },
    }
    if manifest["palette"] is None:
        del manifest["palette"]
    if animation_aliases:
        manifest["animationAliases"] = animation_aliases
    if sound_banks:
        manifest["soundBanks"] = sound_banks
    manifest["author"] = meta.get("author") or ""
    write_preview(mod, folder, manifest)
    (folder / "mod.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    uncoloured = [n for n in sorted(rename) if n not in colours]
    return {"folder": folder, "item": f"{item['table']}/{item['key']}", "new": f"{item['table']}/{new_key}",
            "sprites": len(rename), "skipped": skipped + missing, "uncoloured": uncoloured, "report": report,
            "swf": len(swf), "suffixes": new_suffix}


def write_preview(mod: dict, folder: Path, manifest: dict) -> None:
    previews = mod["meta"].get("previewsIds") or {}
    data = _binary_data(mod)
    for key, ext in sorted(previews.items(), key=lambda kv: int(kv[0])):
        if int(key) in data and ext in ("png", "jpg", "jpeg"):
            name = f"preview.{ext}"
            (folder / name).write_bytes(data[int(key)])
            manifest["preview"] = name
            return


def mod_files(mod: dict) -> list[tuple[int, str, bytes]]:
    data = _binary_data(mod)
    return [(int(k), name, data[int(k)]) for k, name in sorted((mod["meta"].get("files") or {}).items(),
                                                                 key=lambda kv: int(kv[0])) if int(k) in data]


def clean_text(text: str) -> str:
    text = re.sub(r"<el>\s*", "- ", text or "")
    text = re.sub(r"</el>", "\n", text)
    text = re.sub(r"<[^>]+>", "", text)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def level_art(tables: Path) -> tuple[dict[str, set[str]], dict[str, str], dict[str, set[str]]]:
    refs: dict[str, set[str]] = {}
    for f in sorted((tables / "Dynamic").glob("LevelDesc_*.xml")):
        text = f.read_text(encoding="utf-8", errors="replace")
        root = re.search(r"<LevelDesc\b[^>]*>", text)
        if not root:
            continue
        level = re.search(r'\bLevelName="([^"]*)"', root.group(0))
        folder = re.search(r'\bAssetDir="([^"]*)"', root.group(0))
        if not level:
            continue
        base = "mapArt/" + (folder.group(1) + "/" if folder and folder.group(1) else "")
        for tag, name in re.findall(r'<(\w+)\b[^>]*?\bAssetName="([^"]*)"', text):
            if not name or name.startswith(".png"):
                continue
            path = ("mapArt/Backgrounds/" + name if tag == "Background" else
                    "mapArt/" + name[3:] if name.startswith("../") else base + name)
            refs.setdefault(path, set()).add(level.group(1))
    names: dict[str, str] = {}
    thumbs: dict[str, set[str]] = {}
    lt = tables / "Init" / "LevelTypes.xml"
    if lt.exists():
        for m in re.finditer(r'<LevelType\b([^>]*)>(.*?)</LevelType>', lt.read_text(encoding="utf-8"), re.S):
            attrs, body = m.group(1), m.group(2)
            level = re.search(r'LevelName="([^"]*)"', attrs)
            if not level or 'DevOnly="true"' in attrs or 'TestLevel="true"' in attrs:
                continue
            shown = re.search(r"<DisplayName>([^<]*)</DisplayName>", body)
            names[level.group(1)] = shown.group(1) if shown else level.group(1)
            thumb = re.search(r"<ThumbnailPNGFile>([^<]*)</ThumbnailPNGFile>", body)
            if thumb and thumb.group(1).strip():
                path = "images/thumbnails/" + thumb.group(1).strip()
                thumbs.setdefault(path, set()).add(level.group(1))
                refs.setdefault(path, set()).add(level.group(1))
    return refs, names, thumbs


MAP_TYPES = [("1v1", ("Standard1v1", "Ranked1v1")), ("2v2", ("Standard2v2", "Ranked2v2", "Unranked2v2")),
             ("FFA", ("StandardFFA", "AltFFA")), ("Big", ("StandardBig", "Standard3v3")),
             ("Game modes", ("GameModeAll", "BrawlballSmall", "BrawlballBig", "SoccerAll", "HordeAll", "CTF3v3",
                             "Showdown", "VolleyBattle", "ClimbAll", "BuddyAll", "RingAll"))]


def map_types(tables: Path) -> dict[str, list[str]]:
    sets: dict[str, set[str]] = {}
    f = tables / "Game" / "LevelSetTypes.xml"
    if f.exists():
        for m in re.finditer(r'<LevelSetType LevelSetName="([^"]*)"[^>]*>(.*?)</LevelSetType>', f.read_text(encoding="utf-8"), re.S):
            levels = re.search(r"<LevelTypes>([^<]*)</LevelTypes>", m.group(2))
            for level in (levels.group(1).split(",") if levels else []):
                sets.setdefault(level.strip(), set()).add(m.group(1))
    out = {}
    for level, names in sets.items():
        kinds = [kind for kind, members in MAP_TYPES if names & set(members)]
        out[level] = kinds or ["Other"]
    return out


def import_map_art(path: Path, mod: dict, out: Path, tables: Path) -> dict:
    meta = mod["meta"]
    refs, names, thumbs = level_art(tables)
    by_name: dict[str, list[str]] = {}
    for ref in refs:
        by_name.setdefault(ref.rsplit("/", 1)[1].lower(), []).append(ref)
    files = mod_files(mod)
    found: list[list[str]] = [by_name.get(name.lower(), []) for _, name, _ in files]

    def folder(ref: str) -> str:
        return ref.rsplit("/", 1)[0]
    placed: list[str | None] = [c[0] if len(c) == 1 else None for c in found]
    report = []
    for i, cands in enumerate(found):
        if len(cands) < 2:
            continue
        near = [folder(placed[j]) for j in sorted(range(len(files)), key=lambda j: abs(j - i))
                if j != i and placed[j] and folder(placed[j]).startswith("mapArt/")
                and not folder(placed[j]).endswith("Backgrounds")]
        pick = next((c for d in near for c in cands if folder(c) == d), None)
        if pick is None:
            pick = sorted(cands)[0]
            report.append(f"{files[i][1]} could be {', '.join(sorted(cands))}: took {pick}")
        placed[i] = pick
    mod_id = _mod_id(token_for(meta.get("name") or path.stem))
    target = out / mod_id
    if target.exists():
        shutil.rmtree(target)
    primary: dict[str, bytes] = {}
    variants: dict[str, list[tuple[int, bytes]]] = {}
    unused = []
    for (fid, name, data), ref in zip(files, placed):
        if ref is None:
            unused.append(name)
            continue
        if ref in primary:
            if primary[ref] == data:
                continue
            variants.setdefault(ref, []).append((fid, primary[ref]))
        primary[ref] = data
    if not primary:
        raise ImportError_(f"none of its {len(files)} files is art a map reads")
    for ref, data in primary.items():
        (target / ref).parent.mkdir(parents=True, exist_ok=True)
        (target / ref).write_bytes(data)
    variant_files: dict[str, list[str]] = {}
    for ref, items in variants.items():
        for fid, data in items:
            local = f"variants/{fid}_{ref.rsplit('/', 1)[1]}"
            (target / local).parent.mkdir(parents=True, exist_ok=True)
            (target / local).write_bytes(data)
            variant_files.setdefault(ref, []).append(local)
    own: dict[str, set[str]] = {}
    for ref, levels in refs.items():
        if ref.startswith("mapArt/"):
            for lvl in levels:
                own.setdefault(lvl, set()).add(ref)
    maps = {}
    kinds = map_types(tables)
    for lvl in sorted({lvl for ref in primary for lvl in refs[ref]}):
        mine = own.get(lvl, set())
        has = mine & set(primary)
        background = any(r.startswith("mapArt/Backgrounds/") for r in has)
        if lvl in names and (background or (mine and len(has) * 2 >= len(mine))):
            maps[lvl] = names[lvl]
    manifest = {
        "id": mod_id,
        "name": meta.get("name") or path.stem,
        "version": str(meta.get("version") or "1.0"),
        "author": meta.get("author") or "",
        "description": (clean_text(meta.get("description", "")) + "\n\n" if meta.get("description") else "") +
                       f"Imported from {path.name} by tools/bmod_import.py: art for {len(maps)} maps, picked per map in "
                       "the Mods screen; the game's own art is unchanged.",
        "mapArt": {
            "files": sorted(primary),
            "maps": dict(sorted(maps.items())),
            "thumbnails": {p: sorted(lv for lv in thumbs[p] if lv in maps) for p in sorted(primary) if p in thumbs},
            "mapTypes": {lv: kinds.get(lv, ["Other"]) for lv in sorted(maps)},
        },
    }
    if variant_files:
        manifest["mapArt"]["variants"] = dict(sorted(variant_files.items()))
    write_preview(mod, target, manifest)
    (target / "mod.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if unused:
        report.append(f"left out ({len(unused)}, no map reads them): " + ", ".join(unused[:12]) +
                      (" ..." if len(unused) > 12 else ""))
    if variant_files:
        report.append(f"{sum(len(v) for v in variant_files.values())} variants of files given twice: " +
                      ", ".join(variant_files))
    return {"folder": target, "kind": "map art", "files": len(primary), "maps": maps, "report": report}


def language_strings(game: Path, number: int = 1) -> dict[str, str]:
    if str(ROOT) not in sys.path:
        sys.path.insert(0, str(ROOT))
    from tools.audit_languages import decode
    f = game / "languages" / f"language.{number}.bin"
    return decode(f.read_bytes())[2] if f.exists() else {}


def _norm(text: str) -> str:
    return re.sub(r"[^a-z0-9]", "", text.lower())


def import_avatars(path: Path, mod: dict, out: Path, game: Path, tables: Path, rabcdasm: str | None) -> dict:
    meta = mod["meta"]
    _, a_rows = read_csv_table(tables, "avatarTypes")
    raw = list(csv.reader(io.StringIO((tables / "Game" / "spriteData.csv").read_text(encoding="utf-8"))))
    s_header = raw[1]
    s_rows = [dict(zip(s_header, r)) for r in raw[2:] if len(r) >= 3]
    by_icon = {r["IconName"]: r for r in a_rows if r.get("IconName")}
    by_flag: dict[str, dict] = {}
    for r in a_rows:
        by_flag.setdefault(r.get("FlagArt") or "", r)
    sprite_rows: dict[str, list[dict]] = {}
    file_set: dict[str, tuple[str, str]] = {}
    for r in s_rows:
        sprite_rows.setdefault(r["SetName"], []).append(r)
        file_set[r["File"].rsplit("/", 1)[-1].lower()] = (r["SetName"], r["BoneName"])
    touched: dict[str, dict] = {}

    def entry(row: dict) -> dict:
        return touched.setdefault(row["AvatarName"], {"row": row, "icon_sprite": None, "icon_png": None, "flags": {}})
    sprites = [n for spec in (meta.get("swfs") or {}).values() for n in spec.get("sprites", [])]
    for n in sprites:
        if n in by_icon:
            entry(by_icon[n])["icon_sprite"] = n
    unused = [n for n in sprites if n not in by_icon]
    for fid, name, data in mod_files(mod):
        stem = name.rsplit(".", 1)[0]
        if stem in by_icon:
            entry(by_icon[stem])["icon_png"] = (name, data)
        elif name.lower() in file_set and file_set[name.lower()][0] in by_flag:
            set_name, bone = file_set[name.lower()]
            entry(by_flag[set_name])["flags"][bone] = (name, data)
        else:
            unused.append(name)
    if not touched:
        raise ImportError_("it redraws no avatar")
    strings = language_strings(game)
    labels: dict[str, str] = {}
    for line in clean_text(meta.get("description", "")).splitlines():
        m = re.match(r"\s*(.+?)\s*=\s*(.+?)(?:\s+Avatar)?\s*$", line)
        if not m:
            continue
        wanted = _norm(m.group(2))
        for name, t in touched.items():
            row = t["row"]
            keys = {_norm(name), _norm(strings.get(row.get("DisplayNameKey") or "", "")),
                    _norm((row.get("IconName") or "").replace("a_AvatarIcon_", ""))}
            if wanted in keys:
                labels[name] = m.group(1)
    mod_name = meta.get("name") or path.stem
    prefix = token_for(mod_name)
    mod_id = _mod_id(prefix)
    target = out / mod_id
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True)
    rows, sprite_adds, assets, english, report = [], [], {}, {}, []
    rename: dict[str, str] = {}
    png_icons = {r["BoneName"]: r for r in sprite_rows.get("", [])}

    def write(local: str, data: bytes) -> None:
        (target / local).parent.mkdir(parents=True, exist_ok=True)
        (target / local).write_bytes(data)
    for name, t in sorted(touched.items()):
        row = t["row"]
        shown = strings.get(row.get("DisplayNameKey") or "", name)
        label = labels.get(name) or f"{shown} ({mod_name.rstrip('!')})"
        token = token_for(label if name in labels else f"{name} {mod_name}")
        icon = f"a_AvatarIcon_{token}"
        sets = {"AvatarName": token, "AvatarID": "@id", "DisplayNameKey": f"{token}_DisplayName", "IconName": icon,
                "FlagArt": token}
        if (row.get("SpriteFilePath") or "").strip():
            sets["SpriteFilePath"] = "@none"
        english[f"{token}_DisplayName"] = label
        if t["icon_sprite"]:
            rename[t["icon_sprite"]] = icon
        elif t["icon_png"] or row.get("IconName") in png_icons:
            orig = png_icons.get(row.get("IconName"))
            game_path = orig["File"] if orig else ""
            if t["icon_png"]:
                game_path = f"sprites/AutoGenerated/Sprites_Avatars/{icon}.png"
                write(f"sprites/{icon}.png", t["icon_png"][1])
                assets[game_path] = f"sprites/{icon}.png"
            dims = [orig[c] for c in s_header[3:]] if orig else ["128", "128", "1", "1"]
            sprite_adds.append({"add": ",".join(["", icon, game_path] + dims)})
        else:
            sets["IconName"] = row["IconName"]
            report.append(f"{token}: the mod has no icon for it, so it shows {name}'s")
        for orig in sprite_rows.get(row.get("FlagArt") or "", []):
            bone = orig["BoneName"]
            file_path = orig["File"]
            if bone in t["flags"]:
                file_path = f"sprites/AutoGenerated/Sprites_Emote/{bone}_{token}.png"
                write(f"sprites/{bone}_{token}.png", t["flags"][bone][1])
                assets[file_path] = f"sprites/{bone}_{token}.png"
            sprite_adds.append({"add": ",".join([token, bone, file_path] + [orig[c] for c in s_header[3:]])})
        rows.append({"copy": name, "set": sets})
        report.append(f"{token} \"{label}\": copy of {name}" +
                      (" with the mod's icon" if t["icon_sprite"] or t["icon_png"] else "") +
                      (f", {len(t['flags'])} flag pictures" if t["flags"] else ""))
    manifest = {
        "id": mod_id,
        "name": mod_name,
        "version": str(meta.get("version") or "1.0"),
        "author": meta.get("author") or "",
        "description": f"Imported from {path.name} by tools/bmod_import.py: {len(rows)} new avatars next to the ones "
                       "the mod redrew; the originals are unchanged.",
        "strings": {"English": english},
        "assets": assets,
        "tables": {"avatarTypes": rows, **({"spriteData": sprite_adds} if sprite_adds else {})},
    }
    if rename:
        by_id = {n: cid for cid, n in mod["symbols"]}
        art, _ = fix_shapes([(c, b) for c, b in mod["tags"] if c not in NOT_COPIED])
        symbols = symbol_class_tag([(by_id[o], n) for o, n in sorted(rename.items()) if o in by_id])
        swf = _mod_swf(mod, art, {n: None for n in rename.values()}, symbols, rabcdasm)
        swf_name = f"UI_{prefix}.swf"
        write(swf_name, swf)
        assets[swf_name] = swf_name
        manifest["tables"]["MasterFileList"] = [
            f'<File Stage="Required" ExcludedPlatforms="" Size="{max(1, len(swf) // 1024)}" Name="{swf_name}" Load="" />']
    write_preview(mod, target, manifest)
    (target / "mod.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if unused:
        report.append(f"left out ({len(unused)}, not an avatar's icon or flag): " + ", ".join(unused[:12]))
    return {"folder": target, "kind": "avatars", "avatars": [r["set"]["AvatarName"] for r in rows], "report": report}


def default_tables() -> Path:
    for p in (ROOT / "build" / "tabledata", ROOT / "build" / "tabledata-test"):
        if (p / "Game" / "costumeTypes.csv").exists():
            return p
    return ROOT / "build" / "tabledata"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("bmod", type=Path, nargs="+")
    p.add_argument("--out", type=Path, default=ROOT / "build" / "bmods", help="where the mod folders go")
    p.add_argument("--game", type=Path, default=ROOT / "versions" / "10.11", help="the game install (its SWFs)")
    p.add_argument("--tables", type=Path, default=None, help="tables from tools/extract_client_data.mjs")
    p.add_argument("--token", help="the new item's name in the game data (default: BH + the mod's name)")
    p.add_argument("--name", help="the new item's display name (default: the mod's name)")
    p.add_argument("--from", dest="wanted", help="the skin or weapon skin it replaces (default: from its sprite names)")
    p.add_argument("--rabcdasm", help="directory containing the RABCDAsm executables")
    p.add_argument("--sounds", type=Path, help="the folder holding the mod's banks as audio/pc/... (default: a pc folder "
                   "of .bnk files next to the .bmod)")
    p.add_argument("--hands", choices=["bare", "original"], default="bare",
                   help="hands when the mod draws none: bare (skin only, in the mod's skin tone) or the original's")
    p.add_argument("--check", action="store_true",
                   help="run tools/sprite_check.py on the game's runtime and keep colours only where recolouring is safe")
    p.add_argument("--no-colours", action="store_true",
                   help="no palette colours: the sprites are drawn as the mod has them, never recoloured")
    args = p.parse_args(argv)
    tables = args.tables or default_tables()
    status = 0
    for path in args.bmod:
        try:
            r = import_bmod(path, args.out, args.game, tables, args.token if len(args.bmod) == 1 else None,
                            args.name if len(args.bmod) == 1 else None, args.wanted, args.rabcdasm,
                            not args.no_colours, args.check, args.hands,
                            args.sounds / "audio" / "pc" if args.sounds and (args.sounds / "audio" / "pc").exists()
                            else args.sounds)
        except (ImportError_, OSError, subprocess.CalledProcessError) as e:
            print(f"{path.name}: not imported: {e}")
            status = 1
            continue
        if r.get("kind") == "map art":
            print(f"{path.name}: map art, {r['files']} files for {len(r['maps'])} maps "
                  f"({', '.join(sorted(set(r['maps'].values()))[:10])}{' ...' if len(set(r['maps'].values())) > 10 else ''}); "
                  f"{r['folder']}")
            for line in r["report"]:
                print("  " + line)
            continue
        if r.get("kind") == "avatars":
            print(f"{path.name}: {len(r['avatars'])} new avatars; {r['folder']}")
            for line in r["report"]:
                print("  " + line)
            continue
        print(f"{path.name}: {r['new']} (a copy of {r['item']}) with {r['sprites']} sprites, "
              f"suffixes {', '.join(f'{a} -> {b}' for a, b in r['suffixes'].items())}; {r['folder']}")
        if r["skipped"]:
            print(f"  left out ({len(r['skipped'])}, not named after the item, so shared by everyone): " +
                  ", ".join(r["skipped"][:12]) + (" ..." if len(r["skipped"]) > 12 else ""))
        if r["uncoloured"]:
            print(f"  not in the game's SWFs, so no palette colours ({len(r['uncoloured'])}, drawn as the mod has them): " +
                  ", ".join(r["uncoloured"][:8]) + (" ..." if len(r["uncoloured"]) > 8 else ""))
        for line in r["report"]:
            print("  " + line)
    return status


if __name__ == "__main__":
    sys.exit(main())
