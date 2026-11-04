"""write the map editor's element schema from the game's own map layouts.

    python tools/map_editor_schema.py [--tables build/tabledata] [--out tools/map-editor/schema.js]

per element name of every ``LevelDesc_*.xml`` the SWZ extractor wrote: how often it occurs, its attributes (most used
first), the elements it holds and its parents, whether it holds text, and the most common short value per attribute;
plus the ``LevelTypes`` fields the game's parser accepts (type, how many maps set each, most common value) and the
``LevelSetTypes`` names. only names and counts are written; no map is copied.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def parse(path: Path) -> ET.Element | None:
    raw = path.read_text(encoding="utf-8", errors="replace")
    for text in (raw, re.sub(r"&(?![a-z]+;|#)", "&amp;", raw)):
        try:
            return ET.fromstring(text)
        except ET.ParseError:
            continue
    return None


LEVEL_FIELDS = [
    ("DisplayName", "text"), ("TeamColorOrder", "text"), ("AvoidTeamColor", "text"), ("FileName", "text"),
    ("AssetName", "text"), ("CrateColorA", "int"), ("CrateColorB", "int"), ("LeftKill", "int"), ("RightKill", "int"),
    ("TopKill", "int"), ("BottomKill", "int"), ("LevelID", "int"), ("BGMusic", "text"), ("StreamerBGMusic", "text"),
    ("StartFrame", "int"), ("MidgroundTint", "int"), ("MidgroundOffset", "int"), ("MidgroundFraction", "number"),
    ("MinNumOnlineGamesBeforeRandom", "int"), ("BotTint", "int"), ("BotOffset", "int"), ("BotFraction", "number"),
    ("AIStrictRecover", "bool"), ("IsClimbMap", "bool"), ("ShowPlatsDuringMove", "bool"),
    ("ShowLavaLevelDuringMove", "bool"), ("NegateOverlaps", "bool"), ("AllowItemSpawnOverlap", "bool"),
    ("ThumbnailPNGFile", "text"), ("FixedCamera", "bool"), ("FixedWidth", "bool"), ("FixedWidthYOffset", "number"),
    ("HardLeftKill", "bool"), ("HardRightKill", "bool"), ("ShadowTint", "number"), ("AIPanicLine", "number"),
    ("AIGroundLine", "number"), ("SoftTopKill", "bool"), ("ColorExclusionList", "text"), ("BulletWaves", "text"),
]
LEVEL_ATTRIBUTES = [("DevOnly", "bool"), ("TestLevel", "bool")]


def level_settings(tables: Path) -> dict:
    found = sorted(tables.rglob("LevelTypes.xml"))
    rows = [r for r in ET.parse(found[0]).getroot()] if found else []
    used, values = Counter(), defaultdict(Counter)
    for r in rows:
        for a, v in r.attrib.items():
            used[a] += 1
            values[a][v] += 1
        for c in r:
            used[c.tag] += 1
            v = (c.text or "").strip()
            if len(v) <= 24 and re.fullmatch(r"-?\d+(\.\d+)?|0x[0-9A-Fa-f]+|true|false|TRUE|FALSE|True|False", v):
                values[c.tag][v] += 1
    field = lambda name, kind: [name, kind, used[name], values[name].most_common(1)[0][0] if values[name] else ""]
    sets = sorted(tables.rglob("LevelSetTypes.xml"))
    names = [r.get("LevelSetName") for r in ET.parse(sets[0]).getroot() if r.get("LevelSetName")] if sets else []
    return {"rows": len(rows), "fields": [field(n, k) for n, k in LEVEL_FIELDS],
            "attributes": [field(n, k) for n, k in LEVEL_ATTRIBUTES], "sets": names}


def build(tables: Path) -> dict:
    count, attrs, kids, parents, texts = Counter(), defaultdict(Counter), defaultdict(Counter), defaultdict(Counter), Counter()
    values: dict[tuple[str, str], Counter] = defaultdict(Counter)
    files = sorted(tables.rglob("LevelDesc_*.xml"))
    maps = 0

    def walk(e: ET.Element, parent: str | None) -> None:
        count[e.tag] += 1
        if parent:
            parents[e.tag][parent] += 1
        for a, v in e.attrib.items():
            attrs[e.tag][a] += 1
            if len(v) <= 24 and re.fullmatch(r"-?\d+(\.\d+)?|true|false|[A-Za-z]+", v):
                values[(e.tag, a)][v] += 1
        for c in e:
            kids[e.tag][c.tag] += 1
            walk(c, e.tag)
        if len(e) == 0 and (e.text or "").strip():
            texts[e.tag] += 1

    for f in files:
        root = parse(f)
        if root is not None and root.tag == "LevelDesc":
            maps += 1
            walk(root, None)
    elements = {}
    for tag, n in count.most_common():
        elements[tag] = {
            "count": n,
            "attributes": [[a, k] for a, k in attrs[tag].most_common()],
            "children": [c for c, _ in kids[tag].most_common()],
            "parents": [p for p, _ in parents[tag].most_common()],
            "text": texts[tag] > 0,
            "example": {a: values[(tag, a)].most_common(1)[0][0] for a in attrs[tag] if values[(tag, a)]},
        }
    return {"maps": maps, "elements": elements, "level": level_settings(tables)}


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--tables", type=Path, default=ROOT / "build" / "tabledata")
    p.add_argument("--out", type=Path, default=ROOT / "tools" / "map-editor" / "schema.js")
    args = p.parse_args(argv)
    schema = build(args.tables)
    if not schema["maps"]:
        print(f"map_editor_schema FAILED: no LevelDesc files under {args.tables}", file=sys.stderr)
        return 1
    args.out.write_text("// Generated by tools/map_editor_schema.py from the game's LevelDesc files: element and attribute\n"
                        "// names with counts only, and the map settings the game's LevelTypes parser accepts. Don't edit by hand.\n"
                        "window.MAP_SCHEMA = " + json.dumps(schema, indent=1) + ";\n", encoding="utf-8")
    print(f"{schema['maps']} maps, {len(schema['elements'])} element types, {len(schema['level']['fields'])} map settings, "
          f"{len(schema['level']['sets'])} map sets -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
