"""build the sample animation mod's .anm from your own game files.

    python tools/make_sample_anim.py --anims "E:\\SteamLibrary\\steamapps\\common\\Brawlhalla\\anims"
    python tools/make_sample_anim.py                    # default: versions/<newest>/anims

writes ``build/sample-anim/Animation_BHSample.anm`` (copy it to ``mods\\sample-anim\\`` in the game folder, next to
the mod.json from ``examples/mods/sample-anim``). it holds one class, ``Animation_Hammer.swf/a__HammerAnimation`` from
your ``Animation_Hammer.anm``, with every explicit bone position of its ``Ready`` animation scaled by SCALE; a file
loaded later replaces the game's class of the same key.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools import anm

SOURCE = "Animation_Hammer.anm"
CLASS = "Animation_Hammer.swf/a__HammerAnimation"
ANIMATION = "Ready"
SCALE = 1.3


def newest_anims() -> Path:
    versions = [p for p in (ROOT / "versions").iterdir() if (p / "anims").is_dir()]
    return max(versions, key=lambda p: [int(x) if x.isdigit() else x for x in p.name.split(".")]) / "anims"


def stretch(animation: dict, scale: float) -> int:
    changed = 0
    for frame in animation["frames"]:
        for bone in frame["bones"]:
            if not bone.get("dup") and bone["pos"] != "prev":
                bone["pos"] = [anm.bits32(anm.as_float32(v) * scale) for v in bone["pos"]]
                changed += 1
    return changed


def build(source: bytes, scale: float = SCALE) -> tuple[bytes, dict]:
    data = anm.decode(source)
    cls = next((c for c in data["classes"] if c["key"] == CLASS), None)
    if cls is None:
        raise anm.AnmError(f"{CLASS} is not in {SOURCE}")
    target = next((a for a in cls["animations"] if a["name"] == ANIMATION), None)
    if target is None:
        raise anm.AnmError(f"{CLASS} has no animation {ANIMATION}")
    changed = stretch(target, scale)
    out = {"header": data["header"], "classes": [cls]}
    return anm.encode(out), {"animations": len(cls["animations"]), "frames": len(target["frames"]), "bones": changed}


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--anims", type=Path, help="the game's anims folder (default versions/<newest>/anims)")
    p.add_argument("--out", type=Path, default=ROOT / "build" / "sample-anim" / "Animation_BHSample.anm")
    p.add_argument("--scale", type=float, default=SCALE)
    args = p.parse_args(argv)
    source = (args.anims or newest_anims()) / SOURCE
    if not source.is_file():
        print(f"make_sample_anim FAILED: {source} not found", file=sys.stderr)
        return 1
    try:
        data, info = build(source.read_bytes(), args.scale)
    except anm.AnmError as e:
        print(f"make_sample_anim FAILED: {e}", file=sys.stderr)
        return 1
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(data)
    print(f"{CLASS}: {info['animations']} animations copied, {ANIMATION} changed ({info['frames']} frames, "
          f"{info['bones']} bone positions scaled by {args.scale}) -> {args.out} ({len(data)} bytes)")
    print("Copy it to <game folder>\\mods\\sample-anim\\ next to examples/mods/sample-anim/mod.json.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
