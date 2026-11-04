"""make a music mod from a folder of MP3 files.

    python tools/make_music_pack.py <folder with .mp3 files> --id my-music --name "My music" [--out <mods folder>]
        [--menu <file>] [--charselect <file>] [--maps <file>] [--victory <file>]

writes ``<out>/<id>/mod.json`` and copies the MP3s into ``<out>/<id>/music/``, one track per file. ``--menu`` and the
others name the slots the mod replaces while it is on. ``--out`` defaults to ``<game>/mods``. files that don't look like
MP3 are refused: the game plays MP3 only (AIR ``Sound``).
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import shutil
import sys

DEFAULT_GAME = Path(r"E:\SteamLibrary\steamapps\common\Brawlhalla")
SLOTS = {"menu": "DefaultUI", "charselect": "DefaultCharacterSelect", "maps": "*battle", "victory": "DefaultWinTheme"}
ID = re.compile(r"^[a-z0-9._-]+$")


def looks_like_mp3(data: bytes) -> bool:
    if data[:3] == b"ID3":
        return True
    return len(data) >= 2 and data[0] == 0xFF and (data[1] & 0xE0) == 0xE0 and (data[1] & 0x06) != 0


def track_key(name: str) -> str:
    key = re.sub(r"[^A-Za-z0-9_.-]+", "-", Path(name).stem).strip("-.")
    return key or "track"


def build(folder: Path, mod_id: str, name: str, out: Path, slots: dict[str, str]) -> dict:
    if not ID.match(mod_id):
        raise ValueError(f"id {mod_id!r}: use a-z, 0-9, '.', '_' and '-' only")
    files = sorted(p for p in folder.iterdir() if p.is_file() and p.suffix.lower() == ".mp3")
    if not files:
        raise ValueError(f"no .mp3 files in {folder}")
    tracks: dict[str, dict] = {}
    by_file: dict[str, str] = {}
    for f in files:
        with f.open("rb") as stream:
            head = stream.read(4)
        if not looks_like_mp3(head):
            raise ValueError(f"{f.name} doesn't look like an MP3 (the game plays MP3 only)")
        key = track_key(f.name)
        base, n = key, 2
        while key in tracks:
            key = f"{base}-{n}"
            n += 1
        tracks[key] = {"file": f"music/{key}.mp3", "title": f.stem}
        by_file[f.name.lower()] = key
        by_file[f.stem.lower()] = key
    replaces = {}
    for option, slot in SLOTS.items():
        pick = slots.get(option)
        if pick is None:
            continue
        key = by_file.get(pick.lower()) or by_file.get(Path(pick).name.lower())
        if key is None:
            raise ValueError(f"--{option} {pick}: not one of the MP3 files")
        replaces[slot] = key
    manifest = {"id": mod_id, "name": name, "version": "1.0",
                "description": f"Music: {len(tracks)} tracks. While this mod is on they play where it says (the Mods window's AUDIO tab lists them).",
                "music": {"tracks": tracks}}
    if replaces:
        manifest["music"]["replaces"] = replaces
    target = out / mod_id
    (target / "music").mkdir(parents=True, exist_ok=True)
    for f in files:
        shutil.copyfile(f, target / tracks[by_file[f.name.lower()]]["file"])
    (target / "mod.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("folder", type=Path)
    parser.add_argument("--id", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--game", type=Path, default=DEFAULT_GAME)
    parser.add_argument("--out", type=Path, help="mods folder (default: <game>/mods)")
    for option in SLOTS:
        parser.add_argument(f"--{option}", help="the MP3 file for this slot")
    args = parser.parse_args(argv)
    out = args.out or args.game / "mods"
    try:
        manifest = build(args.folder, args.id, args.name, out, {o: getattr(args, o) for o in SLOTS})
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    print(f"wrote {out / args.id / 'mod.json'}: {len(manifest['music']['tracks'])} tracks"
          + (f", made for {', '.join(manifest['music']['replaces'])}" if "replaces" in manifest["music"] else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
