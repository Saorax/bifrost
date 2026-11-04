"""export the game's AS3 with valid identifiers, check it against the name map, and make it compilable.

  1. FFDec `-renameInvalidIdentifiers typeNumber`: versions/<ver>/BrawlhallaAir.swf
     → build/as3/renamed.swf (build/as3/<ver>/ffdec/ for a version other than 10.11; the same for
     every build/as3 path below).
  2. FFDec `-export script` of the renamed SWF → build/as3/export/scripts/.
  3. tools/symbol_map.py: original ↔ renamed name map, client/symbols/<ver>.json. an existing map's
     renamed-SWF hash must match (--update-map accepts a new one); every class must have its `.as`
     file and no FFDec `§name§` identifier may be left.
  4. tools/apply_aliases.py, when client/symbols/<ver>.aliases.json exists: the evidence-backed names
     go into build/as3/export-aliased/scripts and build/as3/aliased.swf. --no-aliases skips it.
  5. tools/as3_fixups.py → src/as3/<ver>/scripts/, the tree tools/compile_as3.py compiles.
     --no-fixups skips it.

FFDec is the build committed at .tools/ffdec (or FFDEC_JAR / --ffdec). steps 1 and 2 are skipped when
build/as3/export.stamp.json shows they already ran on the same SWF with the same FFDec jar and settings
(--no-cache runs FFDec anyway).

usage: python tools/export_as3.py [--version 10.11] [--ffdec PATH] [--update-map] [--no-fixups] [--no-cache]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(Path(__file__).resolve().parent))

import apply_aliases
import as3_fixups
import compare_methods
import symbol_map

DEFAULT_JAR = ROOT / ".tools" / "ffdec" / "ffdec.jar"
FFDEC_LABEL = "committed .tools/ffdec"
EXPORT_CONFIG = "autoDeobfuscate=false,autoRenameIdentifiers=false,parallelSpeedUp=true,simplifyExpressions=false"
QUOTED_NAME = re.compile(r"(?<!§)§(?!§)[^§\n]+§(?!§)")


def newest_version() -> str:
    versions = [p.name for p in (ROOT / "versions").iterdir() if (p / "BrawlhallaAir.swf").is_file()]
    if not versions:
        raise SystemExit("no versions/<ver>/BrawlhallaAir.swf found")
    return max(versions, key=lambda v: [int(x) if x.isdigit() else x for x in v.split(".")])


def _files_where(scripts: Path, test) -> list[str]:
    return sorted(str(p.relative_to(scripts)).replace(os.sep, "/") for p in scripts.rglob("*.as")
                  if test(p.read_text(encoding="utf-8", errors="replace")))


def pseudo_op_files(scripts: Path) -> list[str]:
    return _files_where(scripts, lambda text: "§§" in text)


def quoted_name_files(scripts: Path) -> list[str]:
    return _files_where(scripts, QUOTED_NAME.search)


def ffdec_stamp(jar: Path, original: Path) -> dict:
    return {"original_sha256": symbol_map.sha256(original), "ffdec_sha256": symbol_map.sha256(jar),
            "rename": "typeNumber", "config": EXPORT_CONFIG}


def ffdec(jar: Path, *args: str) -> None:
    subprocess.run(["java", "-Xmx4g", "-jar", str(jar), *args], check=True)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version", default=None, help="versions/<ver> to export (default: newest)")
    ap.add_argument("--ffdec", type=Path, default=Path(os.environ.get("FFDEC_JAR", DEFAULT_JAR)))
    ap.add_argument("--update-map", action="store_true", help="accept a renamed SWF that differs from the map's")
    ap.add_argument("--no-fixups", action="store_true", help="stop after the export and map check")
    ap.add_argument("--no-aliases", action="store_true", help="keep FFDec's names in the tree to compile")
    ap.add_argument("--no-cache", action="store_true", help="run FFDec even if its last output is still current")
    args = ap.parse_args(argv)

    version = args.version or newest_version()
    original = ROOT / "versions" / version / "BrawlhallaAir.swf"
    work = compare_methods.ffdec_work(version)
    renamed = work / "renamed.swf"
    export = work / "export"
    map_path = ROOT / "client" / "symbols" / f"{version}.json"
    if not args.ffdec.is_file():
        raise SystemExit(f"FFDec jar not found: {args.ffdec} (set FFDEC_JAR or --ffdec)")

    work.mkdir(parents=True, exist_ok=True)
    stamp_path = work / "export.stamp.json"
    stamp = ffdec_stamp(args.ffdec, original)
    cached = (not args.no_cache and renamed.is_file() and (export / "scripts").is_dir() and stamp_path.is_file()
              and json.loads(stamp_path.read_text(encoding="utf-8")) == {**stamp, "renamed_sha256": symbol_map.sha256(renamed)})
    if cached:
        print(f"FFDec output is current for this SWF and FFDec ({stamp_path.name}); reusing {export}")
    else:
        stamp_path.unlink(missing_ok=True)
        ffdec(args.ffdec, "-renameInvalidIdentifiers", "typeNumber", str(original), str(renamed))
    got = symbol_map.sha256(renamed)
    if map_path.is_file() and not args.update_map:
        want = symbol_map.load(map_path)["renamed_sha256"]
        if got != want:
            raise SystemExit(f"renamed SWF {got} differs from the map's {want}; wrong FFDec? "
                             "(--update-map to rebuild the map)")

    if not cached:
        if export.exists():
            shutil.rmtree(export)
        ffdec(args.ffdec, "-config", EXPORT_CONFIG, "-export", "script", str(export), str(renamed))
        stamp_path.write_text(json.dumps({**stamp, "renamed_sha256": got}, indent=1) + "\n", encoding="utf-8")

    data = symbol_map.build_map(original, renamed, version, ffdec=FFDEC_LABEL)
    if not map_path.is_file() or args.update_map:
        symbol_map.dump(data, map_path)
    scripts = export / "scripts"
    problems = symbol_map.check_map(data, export)
    problems += [f"FFDec §name§ identifier left in {p}" for p in quoted_name_files(scripts)]
    problems += [f"{f}: not in the map: {', '.join(names[:5])}" for f, names in
                 symbol_map.unresolved_names(data, scripts).items()]
    pseudo = pseudo_op_files(scripts)
    files = sum(1 for _ in scripts.rglob("*.as"))
    print(f"exported {files} .as files to {export}; {len(pseudo)} contain §§ pseudo-ops")
    for p in problems:
        print("PROBLEM:", p)
    if problems:
        print(f"{len(problems)} problem(s)")
        return 1
    print("export OK: every class has its file, every renamed name is in the map, no §name§ identifiers")
    if args.no_fixups:
        return 0
    aliases = ROOT / "client" / "symbols" / f"{version}.aliases.json"
    aliased = work / "aliased.swf"
    if aliased.exists():
        aliased.unlink()
    if aliases.exists() and not args.no_aliases:
        tree = work / "export-aliased" / "scripts"
        code = apply_aliases.main(["--version", version, "--export", str(scripts), "--out-tree", str(tree),
                                   "--renamed-swf", str(renamed), "--out-swf", str(aliased)])
        if code:
            return code
        scripts, renamed = tree, aliased
    return as3_fixups.main(["--src", str(scripts), "--version", version, "--renamed-swf", str(renamed)])


if __name__ == "__main__":
    sys.exit(main())
