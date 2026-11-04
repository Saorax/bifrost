"""put the evidence-backed names into the AS3 tree and the renamed SWF.

    python tools/apply_aliases.py [--version 10.11]

``client/symbols/<ver>.aliases.json`` gives readable names to
FFDec's renamed strings (``class_42`` -> ``GameApp``, ``method_3225`` ->
``onBootFrame``). FFDec renamed at the string level, so the aliases apply at
that level too, and the rules checked by ``tools/symbol_evidence.py``
(one alias per renamed string, one renamed string per alias, no alias that is
already a string of the SWF) make it reversible:

- the FFDec export ``build/as3/export/scripts`` is copied to
  ``build/as3/export-aliased/scripts`` with every identifier token that is an
  aliased string replaced, and each aliased class's file renamed to match;
  the export itself stays as FFDec wrote it (the evidence lines point into it);
- ``build/as3/renamed.swf`` is copied to ``build/as3/aliased.swf`` with the
  same strings replaced in every ABC string pool. the later tools compare the
  compiled AS3 against it.

``tools/rename_back.py`` maps aliases, like renamed names, back to the
original names. ``tools/export_as3.py`` runs this before ``as3_fixups.py``.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools import abc_roundtrip, name_map, rename_back, symbol_evidence

IDENT = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*")


class AliasError(Exception):
    pass


def string_map(aliases: list[dict], strings: set[str] | None = None) -> dict[str, str]:
    problems = symbol_evidence.string_problems(aliases, strings)
    if problems:
        raise AliasError("; ".join(problems[:5]))
    return {e["renamed"].split(".")[-1]: e["alias"] for e in aliases}


def alias_text(text: str, mapping: dict[str, str]) -> str:
    return IDENT.sub(lambda m: mapping.get(m.group(0), m.group(0)), text)


def alias_tree(src: Path, dst: Path, mapping: dict[str, str]) -> int:
    if dst.exists():
        shutil.rmtree(dst)
    n = 0
    for path in sorted(src.rglob("*")):
        rel = path.relative_to(src)
        if path.is_dir():
            continue
        parts = list(rel.parts)
        stem, dot, ext = parts[-1].partition(".")
        parts[-1] = mapping.get(stem, stem) + dot + ext
        parts[:-1] = [mapping.get(p, p) for p in parts[:-1]]
        out = dst.joinpath(*parts)
        out.parent.mkdir(parents=True, exist_ok=True)
        if path.suffix == ".as":
            text = path.read_text(encoding="utf-8")
            new = alias_text(text, mapping)
            n += new != text
            out.write_text(new, encoding="utf-8")
        else:
            shutil.copyfile(path, out)
    return n


def alias_swf(swf: Path, out: Path, mapping: dict[str, str]) -> int:
    shutil.copyfile(swf, out)
    total, abcs = 0, {}
    for i, tag in enumerate(name_map.abc_tags(swf.read_bytes())):
        abcs[i], n = rename_back.rename_abc(tag["abc"], mapping)
        total += n
    abc_roundtrip.replace_blocks(out, abcs)
    return total


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--version", default="10.11")
    p.add_argument("--export", type=Path, default=ROOT / "build" / "as3" / "export" / "scripts")
    p.add_argument("--out-tree", type=Path, default=ROOT / "build" / "as3" / "export-aliased" / "scripts")
    p.add_argument("--renamed-swf", type=Path, default=ROOT / "build" / "as3" / "renamed.swf")
    p.add_argument("--out-swf", type=Path, default=ROOT / "build" / "as3" / "aliased.swf")
    args = p.parse_args(argv)
    path = ROOT / "client" / "symbols" / f"{args.version}.aliases.json"
    try:
        aliases = json.loads(path.read_text(encoding="utf-8"))["aliases"]
        mapping = string_map(aliases, symbol_evidence.swf_strings(args.renamed_swf))
        files = alias_tree(args.export, args.out_tree, mapping)
        strings = alias_swf(args.renamed_swf, args.out_swf, mapping)
    except AliasError as e:
        print(f"apply_aliases FAILED: {e}", file=sys.stderr)
        return 1
    print(f"{len(mapping)} aliases: {files} files and {strings} SWF strings renamed -> {args.out_tree}, {args.out_swf}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
