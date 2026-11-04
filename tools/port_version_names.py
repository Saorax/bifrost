from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools import port_platform, version_match

NAME = re.compile(r"\b(?:[Cc]lass|method|var|const|package|namespace)_\d+\b")
OUT = ROOT / "build" / "version-names"


def build_map(src: str, dst: str) -> tuple[dict[str, str], dict[str, str]]:
    names, _pairs = version_match.match_versions(src, dst, root=ROOT)
    porter = port_platform.Porter(port_platform.SymbolMap(src), port_platform.SymbolMap(dst), names)
    carried: dict[str, str] = {}
    for name in sorted(porter.src.to_original):
        if not NAME.fullmatch(name):
            continue
        new = porter.ffdec(name)
        if name not in porter.missing:
            carried[name] = new
    return carried, dict(porter.missing)


def load_map(src: str, dst: str) -> dict[str, str]:
    path = OUT / f"{src}_to_{dst}.json"
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))["carried"]
    carried, missing = build_map(src, dst)
    save_map(path, src, dst, carried, missing)
    return carried


def save_map(path: Path, src: str, dst: str, carried: dict[str, str], missing: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"from": src, "to": dst, "carried": carried, "missing": missing}, indent=0,
                               sort_keys=True) + "\n", encoding="utf-8")


def carry(name: str, carried: dict[str, str]) -> str | None:
    if name.startswith("Class_"):
        new = carried.get("c" + name[1:])
        return None if new is None else "C" + new[1:]
    return carried.get(name)


def translate_text(text: str, carried: dict[str, str], missing: set[str] | None = None) -> str:
    def sub(m: re.Match) -> str:
        new = carry(m.group(0), carried)
        if new is None:
            if missing is not None:
                missing.add(m.group(0))
            return m.group(0)
        return new
    return NAME.sub(sub, text)


def splice_methods(text: str) -> dict[tuple[str, str], str]:
    from tools import as3_to_haxe

    found: dict[tuple[str, str], str] = {}
    for match in as3_to_haxe.BH_SPLICE_RE.finditer(text):
        owner, method = match.group(1).rsplit(".", 1)[-1], match.group(2)
        head = text.rfind("function ", 0, match.start())
        close = as3_to_haxe.find_matching_right(text, text.index("{", head))
        found[(owner, method)] = text[text.rfind("\n", 0, head) + 1:close + 1]
    return found


def normalized(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def carry_recovered(src: str, dst: str, carried: dict[str, str]) -> tuple[list[str], list[str]]:
    def stubs(version: str) -> dict[tuple[str, str], str]:
        table: dict[tuple[str, str], str] = {}
        for path in sorted((ROOT / "src" / "as3" / version / "scripts").rglob("*.as")):
            text = path.read_text(encoding="utf-8")
            if "BH_SPLICE" in text:
                table.update(splice_methods(text))
        return table

    old, new = stubs(src), stubs(dst)
    out = ROOT / "src" / "as3-recovered" / dst
    done: list[str] = []
    changed: list[str] = []
    for path in sorted((ROOT / "src" / "as3-recovered" / src).glob("*.as")):
        owner, method = path.stem.split(".", 1)
        key = (carry(owner, carried) or owner, carry(method, carried) or method)
        stub = old.get((owner, method))
        if stub is None or key not in new or normalized(translate_text(stub, carried)) != normalized(new[key]):
            changed.append(f"{path.name} -> {key[0]}.{key[1]}: "
                           + ("no stub in " + dst if key not in new else "the method changed"))
            continue
        out.mkdir(parents=True, exist_ok=True)
        (out / f"{key[0]}.{key[1]}.as").write_text(translate_text(path.read_text(encoding="utf-8"), carried),
                                                   encoding="utf-8")
        done.append(f"{path.name} -> {key[0]}.{key[1]}.as")
    recovered = {tuple(d.split(" -> ")[1][:-3].split(".", 1)) for d in done}
    changed_keys = {tuple(c.split(" -> ")[1].split(":")[0].split(".", 1)) for c in changed}
    unrecovered_old = {(carry(o, carried) or o, carry(m, carried) or m) for o, m in old
                       if not (ROOT / "src" / "as3-recovered" / src / f"{o}.{m}.as").exists()}
    left = sorted(f"{o}.{m}" for o, m in new
                  if (o, m) not in recovered and (o, m) not in changed_keys and (o, m) not in unrecovered_old)
    return done, changed + [f"{name}: a stub new in {dst}, without a recovered method" for name in left]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("map", "scan", "recovered"))
    parser.add_argument("paths", nargs="*", type=Path)
    parser.add_argument("--from", dest="src", default="10.11")
    parser.add_argument("--to", required=True)
    args = parser.parse_args(argv)
    if args.command == "map":
        carried, missing = build_map(args.src, args.to)
        path = OUT / f"{args.src}_to_{args.to}.json"
        save_map(path, args.src, args.to, carried, missing)
        print(f"{len(carried)} names carried, {len(missing)} without a match -> {path}")
        return 0
    carried = load_map(args.src, args.to)
    if args.command == "recovered":
        done, left = carry_recovered(args.src, args.to, carried)
        for line in done:
            print(f"carried: {line}")
        for line in left:
            print(f"left: {line}")
        print(f"{len(done)} recovered methods carried to {args.to}, {len(left)} left")
        return 0
    total: dict[str, int] = {}
    for root in args.paths:
        files = [root] if root.is_file() else sorted(p for p in root.rglob("*") if p.suffix in {".py", ".hx"})
        for path in files:
            missing: set[str] = set()
            translate_text(path.read_text(encoding="utf-8"), carried, missing)
            for name in missing:
                total[name] = total.get(name, 0) + 1
            if missing:
                print(f"{path}: {len(missing)} names without a match: {' '.join(sorted(missing)[:12])}")
    print(f"{len(total)} distinct names without a match")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
