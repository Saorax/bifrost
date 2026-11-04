"""make a mod that replaces game sounds (the announcer's or any other) from a folder of MP3 files.

    python tools/make_sound_pack.py <folder with .mp3 files> --id my-announcer --name "My announcer"
        [--out <mods folder>] [--game <install>] [--allow-unknown]

each file replaces the sound event it is named after, in full (``VO_Announcer_InGame_Brawl_Play.mp3``) or shortened:
``_Play`` may be left off, and announcer lines may also leave off ``VO_Announcer_InGame_`` or ``VO_Announcer_Name_``
(``Brawl.mp3``, ``Player1Wins.mp3``); any case. names are checked against ``tools/sound_events.py``; an unknown name
stops with the closest known names unless ``--allow-unknown`` keeps it as written (names the game builds at run time).

writes ``<out>/<id>/mod.json`` (``"sounds"``) and ``<out>/<id>/sounds/<event>.mp3``. ``--out`` defaults to
``<game>/mods``. files that don't look like MP3 are refused.
"""

from __future__ import annotations

import argparse
import difflib
import json
from pathlib import Path
import shutil
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from make_music_pack import DEFAULT_GAME, ID, looks_like_mp3
import sound_events

PREFIXES = ("", "VO_Announcer_InGame_", "VO_Announcer_Name_")


def event_for(stem: str, known: dict[str, str]) -> str | None:
    lower = {name.lower(): name for name in known}
    for prefix in PREFIXES:
        for suffix in ("", "_Play"):
            hit = lower.get((prefix + stem + suffix).lower())
            if hit is not None:
                return hit
    return None


def closest(stem: str, known: dict[str, str]) -> list[str]:
    forms: dict[str, str] = {}
    for name in known:
        forms.setdefault(name.lower(), name)
        short = name[:-5] if name.endswith("_Play") else name
        for prefix in PREFIXES[1:]:
            if short.startswith(prefix):
                forms.setdefault(short[len(prefix):].lower(), name)
        forms.setdefault(short.lower(), name)
    hits = difflib.get_close_matches(stem.lower(), list(forms), n=6, cutoff=0.6)
    return list(dict.fromkeys(forms[h] for h in hits))[:3]


def build(folder: Path, mod_id: str, name: str, out: Path, known: dict[str, str],
          allow_unknown: bool = False) -> dict:
    if not ID.match(mod_id):
        raise ValueError(f"id {mod_id!r}: use a-z, 0-9, '.', '_' and '-' only")
    files = sorted(p for p in folder.iterdir() if p.is_file() and p.suffix.lower() == ".mp3")
    if not files:
        raise ValueError(f"no .mp3 files in {folder}")
    sounds: dict[str, str] = {}
    source: dict[str, Path] = {}
    for f in files:
        with f.open("rb") as stream:
            head = stream.read(4)
        if not looks_like_mp3(head):
            raise ValueError(f"{f.name} doesn't look like an MP3 (the game plays MP3 only)")
        event = event_for(f.stem, known)
        if event is None:
            if not allow_unknown or not sound_events.EVENT.match(f.stem):
                close = closest(f.stem, known)
                hint = f"; closest: {', '.join(close)}" if close else ""
                more = "" if allow_unknown else " (--allow-unknown keeps it)"
                raise ValueError(f"{f.name}: not a sound event of the game{hint}{more}")
            event = f.stem
        if event in source:
            raise ValueError(f"{f.name} and {source[event].name} both mean {event}")
        source[event] = f
        sounds[event] = f"sounds/{event}.mp3"
    announcer = sum(1 for e in sounds if e.startswith("VO_Announcer"))
    what = ("announcer line" if announcer == len(sounds) else "sound") + ("" if len(sounds) == 1 else "s")
    manifest = {"id": mod_id, "name": name, "version": "1.0",
                "description": f"Replaces {len(sounds)} {what} of the game while the mod is on.",
                "sounds": dict(sorted(sounds.items()))}
    target = out / mod_id
    (target / "sounds").mkdir(parents=True, exist_ok=True)
    for event, f in source.items():
        shutil.copyfile(f, target / sounds[event])
    (target / "mod.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("folder", type=Path)
    parser.add_argument("--id", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--game", type=Path, default=DEFAULT_GAME)
    parser.add_argument("--out", type=Path, help="mods folder (default: <game>/mods)")
    parser.add_argument("--version", default="10.11")
    parser.add_argument("--allow-unknown", action="store_true",
                        help="keep file names that aren't known event names (written out in full, ending in _Play/_Stop)")
    args = parser.parse_args(argv)
    out = args.out or args.game / "mods"
    try:
        known = sound_events.load(args.version)
        manifest = build(args.folder, args.id, args.name, out, known, args.allow_unknown)
    except (ValueError, FileNotFoundError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    print(f"wrote {out / args.id / 'mod.json'}: {len(manifest['sounds'])} sounds")
    return 0


if __name__ == "__main__":
    sys.exit(main())
