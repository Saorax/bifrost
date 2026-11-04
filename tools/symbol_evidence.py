"""check the evidence-backed names (aliases) for a game version.

    python tools/symbol_evidence.py check [--version 10.11]
    python tools/symbol_evidence.py line FILE TEXT      # where TEXT occurs in the export (for writing evidence)

``client/symbols/<ver>.aliases.json`` gives readable names to
obfuscated classes and members, one entry per name:

    {"renamed": "class_42.method_3225", "original": "_-X._-Y", "alias": "onBootFrame",
     "kind": "method", "subsystem": "boot", "confidence": "high",
     "basis": "why this name",
     "evidence": [{"path": "class_42.as", "line": 333,
                   "contains": "addEventListener(Event.ENTER_FRAME,class_42.method_3225)"}]}

``renamed`` is the FFDec name the AS3 export uses (``class_N`` or
``class_N.member``), ``original`` the name in the game's own bytecode; both
come from the structural map ``client/symbols/<ver>.json``. Evidence lines
point into the FFDec export (``build/as3/export/scripts``), which the
committed FFDec reproduces exactly.

``check`` verifies, for every entry:
- ``renamed`` exists in the map (the class, or a member of that class) and its
  original name is ``original``;
- every evidence file exists and its ``line`` contains ``contains``;
- ``alias`` is a valid AS3 identifier; class aliases are unique and not the
  name of another class; member aliases are unique within their class and
  not the name of another member of it;
- ``kind``, ``subsystem`` and ``confidence`` have known values and ``basis`` is set.
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
IDENT = re.compile(r"^[A-Za-z_$][A-Za-z0-9_$]*$")
KEYWORDS = {"as", "break", "case", "catch", "class", "const", "continue", "default", "delete", "do", "else",
            "extends", "false", "finally", "for", "function", "if", "implements", "import", "in", "instanceof",
            "interface", "internal", "is", "native", "new", "null", "package", "private", "protected", "public",
            "return", "super", "switch", "this", "throw", "to", "true", "try", "typeof", "use", "var", "void",
            "while", "with", "each", "get", "set", "namespace", "include", "dynamic", "final", "override", "static"}
KINDS = {"class", "method", "field", "getter", "setter", "const"}
SUBSYSTEMS = {"boot", "screens", "match", "input", "assets", "net", "other"}
CONFIDENCE = {"high", "medium"}


def load_map(path: Path) -> tuple[dict[str, str], dict[str, dict[str, str]]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    classes: dict[str, str] = {}
    members: dict[str, dict[str, str]] = {}
    for block in data["blocks"]:
        by_index = {}
        for row in block["classes"]:
            index, original, renamed = row[0], row[1], row[2]
            classes[renamed] = original
            by_index[index] = renamed
            members.setdefault(renamed, {})
        for row in block["members"]:
            owner, original, renamed = row[1], row[3], row[4]
            if owner in by_index:
                members[by_index[owner]][renamed] = original
    return classes, members


def check(aliases: list[dict], classes: dict[str, str], members: dict[str, dict[str, str]],
          export: Path, strings: set[str] | None = None) -> list[str]:
    problems: list[str] = string_problems(aliases, strings)
    class_aliases: dict[str, str] = {}
    member_aliases: dict[tuple[str, str], str] = {}
    lines_cache: dict[str, list[str]] = {}
    for entry in aliases:
        where = entry.get("renamed", "?")
        for field in ("renamed", "original", "alias", "kind", "subsystem", "confidence", "basis", "evidence"):
            if not entry.get(field):
                problems.append(f"{where}: missing {field}")
        if entry.get("kind") not in KINDS:
            problems.append(f"{where}: unknown kind {entry.get('kind')!r}")
        if entry.get("subsystem") not in SUBSYSTEMS:
            problems.append(f"{where}: unknown subsystem {entry.get('subsystem')!r}")
        if entry.get("confidence") not in CONFIDENCE:
            problems.append(f"{where}: unknown confidence {entry.get('confidence')!r}")
        alias = entry.get("alias", "")
        if not IDENT.match(alias) or alias in KEYWORDS:
            problems.append(f"{where}: alias {alias!r} is not a valid identifier")
        cls, _, member = where.partition(".")
        if cls not in classes:
            problems.append(f"{where}: no class {cls} in the map")
            continue
        if not member:
            if entry.get("kind") != "class":
                problems.append(f"{where}: a class entry needs kind 'class'")
            if classes[cls] != entry.get("original"):
                problems.append(f"{where}: original is {classes[cls]!r}, not {entry.get('original')!r}")
            if alias in class_aliases and class_aliases[alias] != cls:
                problems.append(f"{where}: alias {alias} is also given to {class_aliases[alias]}")
            if alias in classes and alias != cls:
                problems.append(f"{where}: alias {alias} is the name of another class")
            class_aliases[alias] = cls
        else:
            names = members.get(cls, {})
            if member not in names:
                problems.append(f"{where}: no member {member} of {cls} in the map")
                continue
            expected = f"{classes[cls]}.{names[member]}"
            if entry.get("original") != expected:
                problems.append(f"{where}: original is {expected!r}, not {entry.get('original')!r}")
            key = (cls, alias)
            if key in member_aliases and member_aliases[key] != member:
                problems.append(f"{where}: alias {alias} is also given to {cls}.{member_aliases[key]}")
            if (alias in names or alias in names.values()) and alias != member:
                problems.append(f"{where}: alias {alias} is the name of another member of {cls}")
            member_aliases[key] = member
        for ev in entry.get("evidence") or []:
            path = export / ev.get("path", "")
            if ev.get("path") not in lines_cache:
                lines_cache[ev.get("path")] = path.read_text(encoding="utf-8").split("\n") if path.is_file() else []
            lines = lines_cache[ev.get("path")]
            line = ev.get("line", 0)
            if not lines:
                problems.append(f"{where}: evidence file {ev.get('path')} not in the export")
            elif not (1 <= line <= len(lines)) or ev.get("contains", "\0") not in lines[line - 1]:
                problems.append(f"{where}: {ev.get('path')}:{line} does not contain {ev.get('contains')!r}")
    return problems


def string_problems(aliases: list[dict], strings: set[str] | None) -> list[str]:
    problems, by_string, by_alias = [], {}, {}
    for e in aliases:
        string, alias = e.get("renamed", "").split(".")[-1], e.get("alias", "")
        if by_string.setdefault(string, alias) != alias:
            problems.append(f"{e.get('renamed')}: {string} already has the alias {by_string[string]}, not {alias}")
        if by_alias.setdefault(alias, string) != string:
            problems.append(f"{e.get('renamed')}: alias {alias} already stands for {by_alias[alias]}")
        if strings is not None and alias in strings:
            problems.append(f"{e.get('renamed')}: alias {alias} is already a string of the SWF")
    return problems


def swf_strings(path: Path) -> set[str]:
    sys.path.insert(0, str(ROOT))
    from tools import name_map, rename_back
    return {s.decode("utf-8", errors="surrogateescape") for t in name_map.abc_tags(path.read_bytes())
            for s in rename_back.string_pool(t["abc"])[2]}


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("command", choices=["check", "line"])
    p.add_argument("args", nargs="*")
    p.add_argument("--version", default="10.11")
    p.add_argument("--export", type=Path, default=ROOT / "build" / "as3" / "export" / "scripts")
    a = p.parse_args(argv)
    if a.command == "line":
        file, text = a.args
        for n, line in enumerate((a.export / file).read_text(encoding="utf-8").split("\n"), 1):
            if text in line:
                print(f"{file}:{n}: {line.strip()}")
        return 0
    if not a.export.is_dir():
        print(f"missing {a.export}: run tools/export_as3.py first", file=sys.stderr)
        return 2
    classes, members = load_map(ROOT / "client" / "symbols" / f"{a.version}.json")
    path = ROOT / "data" / "symbols" / f"{a.version}.aliases.json"
    if not path.exists():
        print(f"missing {path}: the full aliases (with their evidence) are kept there", file=sys.stderr)
        return 2
    aliases = json.loads(path.read_text(encoding="utf-8"))["aliases"]
    renamed_swf = ROOT / "build" / "as3" / "renamed.swf"
    problems = check(aliases, classes, members, a.export, swf_strings(renamed_swf) if renamed_swf.exists() else None)
    for line in problems:
        print(line, file=sys.stderr)
    by = Counter(e.get("subsystem") for e in aliases)
    print(f"{len(aliases)} aliases (" + ", ".join(f"{k} {v}" for k, v in sorted(by.items())) + "): "
          + ("FAILED" if problems else "OK"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
