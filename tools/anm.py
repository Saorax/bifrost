"""read and write the game's animation files (``.anm``), losslessly.

    python tools/anm.py roundtrip versions/10.11/anims/*.anm      # decode, encode, compare every file
    python tools/anm.py json Animation_Viking.anm out.json          # the decoded form, as JSON
    python tools/anm.py build in.json Animation_New.anm             # JSON back to an .anm

format (little-endian), after the reader in bh-swz (``.tools/bh-swz/dist/anm-reader``) and the game's decoder:

- file: u32 header, then a zlib stream holding the payload;
- payload: repeated ``bool 1, str key, class``, ended by ``bool 0``;
- class: str index, str filename, u32 animation count, animations;
- animation: str name, u32 frame count, u32 loopStart, recoveryStart, freeStart,
  previewFrame, baseStart, u32 data count, data (u32 each), u32 frame bytes
  (the size of the frames that follow), frames;
- frame: i16 id, bool + 2×f64 fire socket, bool + 2×f64 platform position,
  i16 bone count, bones;
- bone: bool "same as the previous frame's bone" (then bool "same frame too",
  else i8 frame), or a full bone: i16 id, bool opaque, bool "transform as the
  previous bone", else flags (bool; then bool identity, else symmetric) and
  f32 scaleX, rotateSkew0 (and rotateSkew1, scaleY unless symmetric),
  bool "position as the previous bone" else f32 x, y, bool + i8 frame, u8
  opacity unless opaque; str: u16 length and UTF-8 bytes.

the decoded form keeps every encoding choice (which shortcut a bone used, the
raw bits of each float), so ``encode(decode(x)) == x`` byte for byte. the zlib
wrapper is recompressed, so only the payload is compared.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import struct
import sys
import zlib


class AnmError(Exception):
    pass


class Reader:
    def __init__(self, data: bytes):
        self.b = memoryview(data)
        self.o = 0

    def take(self, fmt: str):
        v = struct.unpack_from(fmt, self.b, self.o)
        self.o += struct.calcsize(fmt)
        return v[0] if len(v) == 1 else v

    def raw(self, n: int) -> bytes:
        v = bytes(self.b[self.o:self.o + n])
        if len(v) != n:
            raise AnmError(f"truncated at byte {self.o}")
        self.o += n
        return v

    def string(self) -> str:
        return self.raw(self.take("<H")).decode("utf-8", "surrogateescape")


class Writer:
    def __init__(self):
        self.parts: list[bytes] = []

    def put(self, fmt: str, *v) -> None:
        self.parts.append(struct.pack(fmt, *v))

    def string(self, s: str) -> None:
        b = s.encode("utf-8", "surrogateescape")
        self.put("<H", len(b))
        self.parts.append(b)

    def bytes(self) -> bytes:
        return b"".join(self.parts)


def f32(r: Reader) -> int:
    return r.take("<I")


def f64(r: Reader) -> int:
    return r.take("<Q")


def as_float32(bits: int) -> float:
    return struct.unpack("<f", struct.pack("<I", bits))[0]


def bits32(value: float) -> int:
    return struct.unpack("<I", struct.pack("<f", value))[0]


def read_bone(r: Reader) -> dict:
    if r.take("<?"):
        same_frame = r.take("<?")
        return {"dup": True, "frame": None if same_frame else r.take("<b")}
    bone = {"id": r.take("<h")}
    opaque = r.take("<?")
    if r.take("<?"):
        bone["transform"] = "prev"
    else:
        flags = r.take("<?")
        kind = ("identity" if r.take("<?") else "symmetric") if flags else "full"
        bone["transform"] = kind
        if kind != "identity":
            bone["m"] = [f32(r), f32(r)] + ([] if kind == "symmetric" else [f32(r), f32(r)])
    bone["pos"] = "prev" if r.take("<?") else [f32(r), f32(r)]
    bone["frame"] = r.take("<b") if r.take("<?") else None
    bone["opacity"] = None if opaque else r.take("<B")
    return bone


def write_bone(w: Writer, bone: dict) -> None:
    if bone.get("dup"):
        w.put("<?", True)
        w.put("<?", bone["frame"] is None)
        if bone["frame"] is not None:
            w.put("<b", bone["frame"])
        return
    w.put("<?", False)
    w.put("<h", bone["id"])
    w.put("<?", bone["opacity"] is None)
    t = bone["transform"]
    w.put("<?", t == "prev")
    if t != "prev":
        w.put("<?", t != "full")
        if t != "full":
            w.put("<?", t == "identity")
        if t != "identity":
            for v in bone["m"]:
                w.put("<I", v)
    w.put("<?", bone["pos"] == "prev")
    if bone["pos"] != "prev":
        w.put("<II", *bone["pos"])
    w.put("<?", bone["frame"] is not None)
    if bone["frame"] is not None:
        w.put("<b", bone["frame"])
    if bone["opacity"] is not None:
        w.put("<B", bone["opacity"])


def read_frame(r: Reader) -> dict:
    frame = {"id": r.take("<h")}
    frame["fire"] = [f64(r), f64(r)] if r.take("<?") else None
    frame["platform"] = [f64(r), f64(r)] if r.take("<?") else None
    frame["bones"] = [read_bone(r) for _ in range(r.take("<h"))]
    return frame


def write_frame(w: Writer, frame: dict) -> None:
    w.put("<h", frame["id"])
    for key in ("fire", "platform"):
        w.put("<?", frame[key] is not None)
        if frame[key] is not None:
            w.put("<QQ", *frame[key])
    w.put("<h", len(frame["bones"]))
    for bone in frame["bones"]:
        write_bone(w, bone)


def read_animation(r: Reader) -> dict:
    name = r.string()
    count = r.take("<I")
    a = {"name": name}
    for k in ("loopStart", "recoveryStart", "freeStart", "previewFrame", "baseStart"):
        a[k] = r.take("<I")
    a["data"] = [r.take("<I") for _ in range(r.take("<I"))]
    size = r.take("<I")
    start = r.o
    a["frames"] = [read_frame(r) for _ in range(count)]
    if r.o - start != size:
        raise AnmError(f"animation {name}: frame bytes field says {size}, frames took {r.o - start}")
    return a


def write_animation(w: Writer, a: dict) -> None:
    w.string(a["name"])
    w.put("<I", len(a["frames"]))
    for k in ("loopStart", "recoveryStart", "freeStart", "previewFrame", "baseStart"):
        w.put("<I", a[k])
    w.put("<I", len(a["data"]))
    for v in a["data"]:
        w.put("<I", v)
    frames = Writer()
    for f in a["frames"]:
        write_frame(frames, f)
    body = frames.bytes()
    w.put("<I", len(body))
    w.parts.append(body)


def decode_payload(payload: bytes) -> list[dict]:
    r = Reader(payload)
    classes = []
    while r.take("<?"):
        key = r.string()
        index, filename = r.string(), r.string()
        classes.append({"key": key, "index": index, "filename": filename,
                        "animations": [read_animation(r) for _ in range(r.take("<I"))]})
    if r.o != len(payload):
        raise AnmError(f"{len(payload) - r.o} bytes left after the last class")
    return classes


def encode_payload(classes: list[dict]) -> bytes:
    w = Writer()
    for c in classes:
        w.put("<?", True)
        w.string(c["key"])
        w.string(c["index"])
        w.string(c["filename"])
        w.put("<I", len(c["animations"]))
        for a in c["animations"]:
            write_animation(w, a)
    w.put("<?", False)
    return w.bytes()


def decode(data: bytes) -> dict:
    if len(data) < 4:
        raise AnmError("shorter than the header")
    return {"header": struct.unpack_from("<I", data)[0], "classes": decode_payload(zlib.decompress(data[4:]))}


def encode(anm: dict, level: int = 9) -> bytes:
    return struct.pack("<I", anm["header"]) + zlib.compress(encode_payload(anm["classes"]), level)


def roundtrip(path: Path) -> tuple[bool, str]:
    data = path.read_bytes()
    payload = zlib.decompress(data[4:])
    anm = {"header": struct.unpack_from("<I", data)[0], "classes": decode_payload(payload)}
    again = encode(anm)
    same_payload = zlib.decompress(again[4:]) == payload and again[:4] == data[:4]
    redecoded = decode(again) == anm
    n_anim = sum(len(c["animations"]) for c in anm["classes"])
    n_frames = sum(len(a["frames"]) for c in anm["classes"] for a in c["animations"])
    return same_payload and redecoded, (f"{len(anm['classes'])} classes, {n_anim} animations, {n_frames} frames, "
                                        f"payload {len(payload)} bytes")


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    rt = sub.add_parser("roundtrip", help="decode and encode each file, compare the payloads")
    rt.add_argument("files", nargs="+", type=Path)
    js = sub.add_parser("json", help="write the decoded form as JSON")
    js.add_argument("anm", type=Path)
    js.add_argument("out", type=Path)
    bd = sub.add_parser("build", help="encode a JSON decoded form into an .anm")
    bd.add_argument("json", type=Path)
    bd.add_argument("out", type=Path)
    args = p.parse_args(argv)
    if args.cmd == "roundtrip":
        bad = 0
        for f in args.files:
            try:
                ok, info = roundtrip(f)
            except (AnmError, zlib.error, struct.error) as e:
                ok, info = False, f"error: {e}"
            bad += not ok
            print(f"{'ok  ' if ok else 'FAIL'} {f.name}: {info}")
        print(f"{len(args.files) - bad}/{len(args.files)} files round-trip byte for byte (payload)")
        return 1 if bad else 0
    if args.cmd == "json":
        args.out.write_text(json.dumps(decode(args.anm.read_bytes()), separators=(",", ":")), encoding="utf-8")
        return 0
    args.out.write_bytes(encode(json.loads(args.json.read_text(encoding="utf-8"))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
