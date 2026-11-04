"""list the game's sound event names (for sound packs).

    python tools/sound_events.py [filter, e.g. Announcer_InGame] [--where] [--out names.json]
        [--version 10.11] [--scripts src/as3/10.11/scripts] [--tables build/tabledata]

every sound the game plays is a Wwise event posted by name; a mod's ``"sounds"`` replaces events by these names. they
come from the game code (string literals ending in ``_Play``/``_Stop``, plus the built
``VO_Announcer_InGame_Player<n>Wins_Play``) and the extracted data tables (``build/tabledata``: XML elements and CSV
columns named ``...Sound...``, XML also ``...Event``, holding full event names). names the game completes at run time
aren't listed.

prints the names sorted (``--out``: ``{"version", "events": {name: where}}`` as JSON; ``where`` is one place the name
comes from, the code first, e.g. ``code:class_525`` or ``table:HeroTypes.NameSoundEvent``).
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
EVENT = re.compile(r"^[A-Za-z0-9_]+_(?:Play|Stop)$")
LITERAL = re.compile(r'"([A-Za-z0-9_]+_(?:Play|Stop))"')
BUILT = [("VO_Announcer_InGame_Player", "Wins_Play", [str(n) for n in range(1, 5)], "class_525 (player number)")]
TAILS = {tail for _, tail, _, _ in BUILT}


def from_code(scripts: Path) -> dict[str, set[str]]:
    found: dict[str, set[str]] = {}
    for path in sorted(scripts.rglob("*.as")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for name in LITERAL.findall(text):
            if name not in TAILS:
                found.setdefault(name, set()).add(f"code:{path.stem}")
        for head, tail, parts, where in BUILT:
            if f'"{head}"' in text and f'"{tail}"' in text:
                for part in parts:
                    found.setdefault(head + part + tail, set()).add(f"code:{where}")
    return found


def _add(found: dict[str, set[str]], value: str | None, where: str) -> None:
    for item in (value or "").split(","):
        item = item.strip()
        if EVENT.match(item):
            found.setdefault(item, set()).add(where)


def from_tables(tables: Path) -> dict[str, set[str]]:
    found: dict[str, set[str]] = {}
    for path in sorted(tables.rglob("*.xml")):
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError:
            continue
        for el in root.iter():
            if "Sound" in el.tag or el.tag.endswith("Event"):
                _add(found, el.text, f"table:{path.stem}.{el.tag}")
    for path in sorted(tables.rglob("*.csv")):
        with path.open(encoding="utf-8", errors="replace", newline="") as f:
            rows = list(csv.reader(f))
        header = next((r for r in rows[:3] if len(r) > 1), None)
        if header is None:
            continue
        start = rows.index(header) + 1
        columns = [i for i, name in enumerate(header) if "Sound" in name]
        for row in rows[start:]:
            for i in columns:
                if i < len(row):
                    _add(found, row[i], f"table:{path.stem}.{header[i]}")
    return found


def collect(scripts: Path, tables: Path | None) -> dict[str, str]:
    merged = from_code(scripts)
    if tables is not None:
        for name, where in from_tables(tables).items():
            merged.setdefault(name, set()).update(where)
    return {name: sorted(merged[name])[0] for name in sorted(merged)}


def load(version: str = "10.11", scripts: Path | None = None, tables: Path | None = None) -> dict[str, str]:
    scripts = scripts or ROOT / "src" / "as3" / version / "scripts"
    if not scripts.is_dir():
        raise FileNotFoundError(f"no game scripts at {scripts}")
    tables = tables or ROOT / "build" / "tabledata"
    return collect(scripts, tables if tables.is_dir() else None)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("filter", nargs="?", default="",
                        help="only names containing this (any case), e.g. Announcer or Announcer_InGame")
    parser.add_argument("--version", default="10.11")
    parser.add_argument("--scripts", type=Path)
    parser.add_argument("--tables", type=Path)
    parser.add_argument("--where", action="store_true", help="also print where each name comes from")
    parser.add_argument("--out", type=Path, help="write {version, events: {name: where}} as JSON instead")
    args = parser.parse_args(argv)
    try:
        events = load(args.version, args.scripts, args.tables)
    except FileNotFoundError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    if not any(w.startswith("table:") for w in events.values()):
        print("note: no tables found (build/tabledata); listing the code's names only", file=sys.stderr)
    events = {n: w for n, w in events.items() if args.filter.lower() in n.lower()}
    if args.out:
        args.out.write_text(json.dumps({"version": args.version, "events": events}, indent=0) + "\n", encoding="utf-8")
        print(f"wrote {args.out}: {len(events)} events")
        return 0
    for name, where in events.items():
        print(f"{name}  ({where})" if args.where else name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
