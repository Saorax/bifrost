"""the engine's evidence aliases (the AIR project's, without the names Haxe can't take) and the game trees spelled with
them.

    python tools/engine_aliases.py sync --version 11.00.49 [--source FILE]
    python tools/engine_aliases.py tree --version 11.00.49
    python tools/engine_aliases.py recovered --version 11.00.49 --previous OLD.aliases.json

``sync`` writes ``client/symbols/<ver>.aliases.json`` from the AIR project's (``tools/pins.py``'s folder, its working
tree, or ``--source``), leaving out each class alias that names a Haxe standard type (``Std``, ``Reflect``,
``Dynamic``...: the converted game would shadow it) unless the converter renames that type
(``as3_to_haxe.STD_SHADOW_RENAMES``).

``tree`` applies them as the player's kit does (the AIR project's ``apply_aliases`` and ``as3_fixups`` at the pin, on
the AIR project's FFDec export of the same SWF): ``build/as3/<ver>/ffdec/export-aliased/scripts`` and ``aliased.swf``
(``recovered_edits`` and the method comparison read them) and the raw tree ``src/as3/<ver>/scripts``.

``recovered`` respells ``src/as3-recovered/<ver>`` from the ``--previous`` aliases to the current ones, then checks
that ``recovered_edits`` rebuilds every file byte for byte from the new export with no more hand-written lines than
before, and that the raw tree has each method's ``BH_SPLICE`` stub. nothing is written when a check fails.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

IDENT = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*")
STAMP = "export-aliased.stamp.json"
DRIVER = """import json
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from tools import apply_aliases, as3_fixups, symbol_evidence
aliases, export, renamed, out_export, out_swf, out_tree = map(Path, sys.argv[2:8])
entries = json.loads(aliases.read_text(encoding="utf-8"))["aliases"]
mapping = apply_aliases.string_map(entries, symbol_evidence.swf_strings(renamed))
files = apply_aliases.alias_tree(export, out_export, mapping)
strings = apply_aliases.alias_swf(renamed, out_swf, mapping)
report = as3_fixups.fix_tree(out_export, out_tree)
print(json.dumps({"aliases": len(mapping), "files": files, "strings": strings, "splices": len(report["splices"]),
                  "unresolved": report["unresolved_files"]}))
"""


class AliasError(Exception):
    pass


def alias_file(version: str) -> Path:
    return ROOT / "client" / "symbols" / f"{version}.aliases.json"


def ffdec_dir(version: str) -> Path:
    return ROOT / "build" / "as3" / version / "ffdec"


def haxe_std_types() -> set[str]:
    std = ROOT / ".tools" / "haxe" / "std"
    if not (std / "StdTypes.hx").exists():
        raise AliasError(f"no Haxe standard library at {std}")
    names = {p.stem for p in std.glob("*.hx")}
    names |= set(re.findall(r"\b(?:abstract|typedef|interface|class|enum)\s+([A-Z]\w*)",
                            (std / "StdTypes.hx").read_text(encoding="utf-8")))
    return names


def renamed_by_converter() -> set[str]:
    from tools import as3_to_haxe
    return set(as3_to_haxe.STD_SHADOW_RENAMES)


def unsafe(entry: dict, std: set[str], renamed: set[str]) -> bool:
    return entry.get("kind") == "class" and entry["alias"] in std and entry["alias"] not in renamed


def engine_set(entries: list[dict]) -> tuple[list[dict], list[dict]]:
    std, renamed = haxe_std_types(), renamed_by_converter()
    return [e for e in entries if not unsafe(e, std, renamed)], [e for e in entries if unsafe(e, std, renamed)]


def string_map(entries: list[dict]) -> dict[str, str]:
    return {e["renamed"].split(".")[-1]: e["alias"] for e in entries}


def respell_map(previous: list[dict], current: list[dict]) -> dict[str, str]:
    old, new = string_map(previous), string_map(current)
    out = {}
    for name in set(old) | set(new):
        a, b = old.get(name, name), new.get(name, name)
        if a != b:
            out[a] = b
    return out


def respell(text: str, mapping: dict[str, str]) -> str:
    return IDENT.sub(lambda m: mapping.get(m.group(0), m.group(0)), text)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command_sync(version: str, source: Path | None) -> int:
    from tools import pins
    source = source or Path(pins.pins()["repo"]) / "client" / "symbols" / f"{version}.aliases.json"
    data = json.loads(source.read_text(encoding="utf-8"))
    kept, dropped = engine_set(data["aliases"])
    data["aliases"] = kept
    alias_file(version).write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{len(kept)} of {len(kept) + len(dropped)} aliases from {source} -> {alias_file(version)}")
    for e in dropped:
        print(f"  left out {e['renamed']} -> {e['alias']}: a Haxe standard type")
    return 0


def air_tools(dest: Path) -> tuple[Path, str]:
    from tools import pins, player_kit
    repo, commit = Path(pins.pins()["repo"]), pins.pins()["commit"]
    files = {}
    for entry in ("tools/apply_aliases.py", "tools/as3_fixups.py"):
        files.update(player_kit.air_tool_closure(repo, commit, entry))
    for rel, data in files.items():
        (dest / rel).parent.mkdir(parents=True, exist_ok=True)
        (dest / rel).write_bytes(data)
    (dest / "tools" / "__init__.py").touch()
    (dest / "run_aliases.py").write_text(DRIVER, encoding="utf-8")
    return repo, commit


def command_tree(version: str) -> int:
    work = ffdec_dir(version)
    renamed = work / "renamed.swf"
    with tempfile.TemporaryDirectory() as tmp:
        air = Path(tmp)
        repo, commit = air_tools(air)
        export = repo / "build" / "as3" / version / "ffdec" / "export" / "scripts"
        stamp = repo / "build" / "as3" / version / "ffdec" / "export.stamp.json"
        if not export.is_dir() or not stamp.exists():
            raise AliasError(f"no FFDec export at {export} (the AIR project's tools/export_as3.py --version {version})")
        if not renamed.exists():
            shutil.copy2(stamp.parent / "renamed.swf", renamed)
        if json.loads(stamp.read_text(encoding="utf-8")).get("renamed_sha256") != sha256(renamed):
            raise AliasError(f"{export} is not FFDec's export of {renamed}")
        tree = ROOT / "src" / "as3" / version / "scripts"
        fresh = tree.with_name("scripts.new")
        out = subprocess.run([sys.executable, "-I", str(air / "run_aliases.py"), str(air), str(alias_file(version)),
                              str(export), str(renamed), str(work / "export-aliased" / "scripts"),
                              str(work / "aliased.swf"), str(fresh)], capture_output=True, text=True)
        if out.returncode != 0:
            raise AliasError(f"AIR's apply_aliases/as3_fixups at {commit}: {out.stderr.strip()[-2000:]}")
    result = json.loads(out.stdout.strip().splitlines()[-1])
    if result["unresolved"]:
        shutil.rmtree(fresh, ignore_errors=True)
        raise AliasError("unresolved pseudo-ops in " + ", ".join(result["unresolved"]))
    if tree.exists():
        shutil.rmtree(tree)
    fresh.rename(tree)
    (work / STAMP).write_text(json.dumps({"aliases_sha256": sha256(alias_file(version)), "air_commit": commit},
                                         indent=1) + "\n", encoding="utf-8")
    print(f"{result['aliases']} aliases at AIR {commit}: {result['files']} files and {result['strings']} SWF strings "
          f"respelled -> {work / 'export-aliased'}, {work / 'aliased.swf'}; {result['splices']} splices -> {tree}")
    return 0


def export_current(version: str) -> Path:
    stamp = ffdec_dir(version) / STAMP
    if not stamp.exists() or json.loads(stamp.read_text(encoding="utf-8"))["aliases_sha256"] != sha256(alias_file(version)):
        raise AliasError(f"{ffdec_dir(version) / 'export-aliased'} is not spelled with {alias_file(version).name}: "
                         f"python tools/engine_aliases.py tree --version {version}")
    return ffdec_dir(version) / "export-aliased" / "scripts"


def literal_lines(edits: dict) -> int:
    return sum(1 for e in edits.values() for x in e["lines"] if isinstance(x, str))


def ffdec_export(version: str) -> Path:
    from tools import pins
    return Path(pins.pins()["repo"]) / "build" / "as3" / version / "ffdec" / "export" / "scripts"


def alias_export(export: Path, mapping: dict[str, str], out: Path) -> None:
    for path in export.rglob("*.as"):
        parts = [mapping.get(p, p) for p in path.relative_to(export).parts]
        parts[-1] = mapping.get(path.stem, path.stem) + ".as"
        target = out.joinpath(*parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(respell(path.read_bytes().decode("utf-8"), mapping).encode("utf-8"))


def command_recovered(version: str, previous: Path) -> int:
    from tools import port_version_names, recovered_edits
    old_entries = json.loads(previous.read_text(encoding="utf-8"))["aliases"]
    new_entries = json.loads(alias_file(version).read_text(encoding="utf-8"))["aliases"]
    mapping = respell_map(old_entries, new_entries)
    export = export_current(version)
    src = ROOT / "src" / "as3-recovered" / version
    stubs: set[tuple[str, str]] = set()
    for path in (ROOT / "src" / "as3" / version / "scripts").rglob("*.as"):
        text = path.read_text(encoding="utf-8")
        if "BH_SPLICE" in text:
            stubs.update(port_version_names.splice_methods(text))
    with tempfile.TemporaryDirectory() as tmp:
        old_export, fresh, rebuilt = Path(tmp) / "old-export", Path(tmp) / "new", Path(tmp) / "rebuilt"
        alias_export(ffdec_export(version), string_map(old_entries), old_export)
        try:
            before = literal_lines(recovered_edits.make(src, old_export))
        except recovered_edits.EditError as e:
            raise AliasError(f"the recovered methods aren't spelled with {previous}: {e}")
        fresh.mkdir()
        names = {}
        for path in sorted(src.glob("*.as")):
            owner, method = path.stem.split(".", 1)
            name = f"{mapping.get(owner, owner)}.{mapping.get(method, method)}.as"
            (fresh / name).write_bytes(respell(path.read_bytes().decode("utf-8"), mapping).encode("utf-8"))
            names[path.name] = name
        try:
            edits = recovered_edits.make(fresh, export)
        except recovered_edits.EditError as e:
            raise AliasError(f"recovered methods in the new names: {e}")
        recovered_edits.apply(edits, export, rebuilt)
        for name in names.values():
            if (rebuilt / name).read_bytes() != (fresh / name).read_bytes():
                raise AliasError(f"{name}: recovered_edits.apply doesn't rebuild it")
            if tuple(name[:-3].split(".", 1)) not in stubs:
                raise AliasError(f"{name}: no BH_SPLICE stub for it in src/as3/{version}/scripts")
        if literal_lines(edits) > before:
            raise AliasError(f"{literal_lines(edits)} hand-written lines in the new names, {before} before")
        for path in src.glob("*.as"):
            path.unlink()
        for name in names.values():
            shutil.copy2(fresh / name, src / name)
    for old, new in names.items():
        print(f"{old} -> {new}" if old != new else f"{old}: respelled in place")
    print(f"{len(names)} recovered methods in {src}; recovered_edits rebuilds each byte for byte from {export} "
          f"({literal_lines(edits)} hand-written lines, {before} before)")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("command", choices=("sync", "tree", "recovered"))
    p.add_argument("--version", required=True)
    p.add_argument("--source", type=Path, help="sync: the AIR project's aliases file")
    p.add_argument("--previous", type=Path, help="recovered: the aliases the files are spelled with now")
    a = p.parse_args(argv)
    try:
        if a.command == "sync":
            return command_sync(a.version, a.source)
        if a.command == "tree":
            return command_tree(a.version)
        if a.previous is None:
            p.error("recovered needs --previous")
        return command_recovered(a.version, a.previous)
    except AliasError as e:
        print(f"engine_aliases: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
