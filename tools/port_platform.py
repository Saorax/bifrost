"""port the extension layer and the bytecode mods to another game version.

    python tools/port_platform.py --to 10.10 [--from 10.11]

``src/platform`` (hook sites, platform code, platform mods) is
written against the FFDec names of 10.11's export (``class_295.method_8123``),
and ``src/mods`` against 10.11's original obfuscated names (``_-F2e``). Neither
means anything in another build: the obfuscator reshuffles the names and FFDec
numbers its renames per SWF. each name is carried by structure:

    FFDec name (from) -> original (from) -> version_match -> original (to) -> FFDec name (to)

using ``client/symbols/<ver>.json`` for both versions and
``tools/version_match.match_versions``. real (unobfuscated) names stay.

output (generated, not committed):
- ``build/port-<to>/platform/``: a copy of ``src/platform`` with every FFDec name
  translated (and in ``patches.json`` every obfuscated name too: the bytecode
  hooks' anchors), for ``apply_platform.py`` / ``apply_platform_bytecode.py --platform``;
- ``build/port-<to>/mods/``: a copy of ``src/mods`` with every obfuscated name
  translated and each patched class file moved to its block in the target,
  for ``apply_mods.py --mods``;
- ``build/port-<to>/PORT.txt``: every name translated, and the ones that couldn't be.

exit 1 if any name can't be translated; the sources in ``src/`` are never changed.
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
from tools import version_match

FFDEC = re.compile(r"\b(?:class|method|var|const|package|namespace)_\d+\b")
MOD_NAME = re.compile(r"block-(\d+)/([^\"/]+)\.class\.asasm|(?<![\w$])_-[A-Za-z0-9$]+")
TEXT = {".as", ".json", ".asasm", ".txt", ".md", ".xml"}


class PortError(Exception):
    pass


class SymbolMap:

    def __init__(self, version: str):
        path = ROOT / "client" / "symbols" / f"{version}.json"
        if not path.exists():
            raise PortError(f"missing {path}: run tools/symbol_map.py build for {version}")
        data = json.loads(path.read_text(encoding="utf-8"))
        self.to_original: dict[str, str] = {}
        self.to_renamed: dict[str, str] = {}
        self.block: dict[str, int] = {}
        self.file: dict[str, str] = {}
        for b in data["blocks"]:
            seen: dict[str, int] = {}
            for c in sorted(b["classes"], key=lambda c: c[0]):
                self.to_original[c[2]] = c[1]
                self.to_renamed[c[1]] = c[2]
                self.block.setdefault(c[1], b["index"])
                n = seen.get(c[1].lower(), 0)
                seen[c[1].lower()] = n + 1
                self.file.setdefault(c[1], c[1] + "_" * n)
            for m in b["members"]:
                self.to_original[m[4]] = m[3]
                self.to_renamed[m[3]] = m[4]
        for kind in ("strings", "namespaces"):
            for b in data["blocks"]:
                for row in b.get(kind) or []:
                    self.to_original.setdefault(row[2], row[1])
                    self.to_renamed.setdefault(row[1], row[2])


class Porter:
    def __init__(self, src: SymbolMap, dst: SymbolMap, names: dict[str, str]):
        self.src, self.dst, self.names = src, dst, names
        self.done: dict[str, str] = {}
        self.missing: dict[str, str] = {}

    def original(self, name: str) -> str | None:
        if not version_match.OBF.fullmatch(name):
            return name
        return self.names.get(name)

    def ffdec(self, name: str) -> str:
        orig = self.src.to_original.get(name)
        if orig is None:
            return self.fail(name, "not an FFDec name of the source version")
        orig2 = self.original(orig)
        if orig2 is None:
            return self.fail(name, f"{orig} has no match in the target")
        new = self.dst.to_renamed.get(orig2)
        if new is None:
            return self.fail(name, f"{orig} -> {orig2}, which the target's symbol map lacks")
        self.done[name] = f"{new} ({orig} -> {orig2})"
        return new

    def obfuscated(self, name: str) -> str:
        new = self.names.get(name)
        if new is None:
            return self.fail(name, "no match in the target")
        self.done[name] = new
        return new

    def fail(self, name: str, why: str) -> str:
        self.missing[name] = why
        return name

    def class_file(self, m: re.Match) -> str:
        stem = m.group(2)
        name = next((c for c, f in self.src.file.items() if f == stem), stem)
        cls = self.obfuscated(name) if version_match.OBF.fullmatch(name) else name
        block = self.dst.block.get(cls)
        if block is None:
            self.fail(m.group(0), f"class {cls} isn't in the target's symbol map")
            return m.group(0)
        return f"block-{block}/{self.dst.file[cls]}.class.asasm"


def port_tree(src: Path, out: Path, rewrite) -> int:
    if out.exists():
        shutil.rmtree(out)
    shutil.copytree(src, out)
    changed = 0
    for f in sorted(out.rglob("*")):
        if f.is_file() and f.suffix in TEXT:
            text = f.read_text(encoding="utf-8")
            new = rewrite(text)
            if new != text:
                f.write_text(new, encoding="utf-8")
                changed += 1
    return changed


def port(src_ver: str, dst_ver: str, out: Path | None = None) -> tuple[Path, Porter]:
    porter = Porter(SymbolMap(src_ver), SymbolMap(dst_ver), version_match.match_versions(src_ver, dst_ver)[0])
    out = out or ROOT / "build" / f"port-{dst_ver}"
    out.mkdir(parents=True, exist_ok=True)
    n_platform = port_tree(ROOT / "src" / "platform", out / "platform",
                           lambda t: FFDEC.sub(lambda m: porter.ffdec(m.group(0)), t))
    patches = out / "platform" / "patches.json"
    if patches.exists():
        text = patches.read_text(encoding="utf-8")
        new = version_match.OBF.sub(lambda m: porter.obfuscated(m.group(0)), text)
        if new != text:
            patches.write_text(new, encoding="utf-8")

    def mods(text: str) -> str:
        return MOD_NAME.sub(lambda m: porter.class_file(m) if m.group(1) else porter.obfuscated(m.group(0)), text)

    n_mods = port_tree(ROOT / "src" / "mods", out / "mods", mods)
    lines = [f"Ported src/platform and src/mods from {src_ver} to {dst_ver} (tools/port_platform.py).",
             f"Files rewritten: platform {n_platform}, mods {n_mods}. Names translated: {len(porter.done)}; "
             f"not translated: {len(porter.missing)}.", ""]
    lines += [f"not translated {k}: {v}" for k, v in sorted(porter.missing.items())]
    lines += [f"{k} -> {v}" for k, v in sorted(porter.done.items())]
    (out / "PORT.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out, porter


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--from", dest="src", default="10.11")
    p.add_argument("--to", dest="dst", required=True)
    p.add_argument("--out", type=Path, help="output folder (default build/port-<to>)")
    args = p.parse_args(argv)
    try:
        out, porter = port(args.src, args.dst, args.out)
    except PortError as e:
        print(f"port_platform FAILED: {e}", file=sys.stderr)
        return 1
    print(f"{args.src} -> {args.dst}: {len(porter.done)} names translated, {len(porter.missing)} not -> {out}")
    for k, v in sorted(porter.missing.items()):
        print(f"  not translated {k}: {v}")
    return 1 if porter.missing else 0


if __name__ == "__main__":
    sys.exit(main())
