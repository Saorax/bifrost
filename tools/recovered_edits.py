"""recovered methods stored as edits of FFDec's own text, so the player's kit carries no game code.

    python tools/recovered_edits.py make --version 11.00 --ffdec DIR --out FILE    # the kit builder runs it
    python tools/recovered_edits.py apply --edits FILE --ffdec DIR --out DIR        # the kit's driver runs it

per line of each ``src/as3-recovered/<ver>/<Class>.<method>.as`` the edits hold either ``[indent, k]`` (line k of
FFDec's method) or the hand-written line; ``apply`` rebuilds the files exactly from the player's own decompile.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class EditError(Exception):
    pass


def method_text(text: str, method: str) -> str | None:
    head = re.compile(r"^[ \t]*(?:(?:public|private|protected|internal|override|static|final)\s+)*function\s+"
                      + re.escape(method) + r"\s*\(", re.M).search(text)
    if not head:
        return None
    start = text.rfind("\n", 0, head.start()) + 1
    depth = 0
    for j in range(text.index("{", head.end()), len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[start:j + 1]
    return None


def class_files(ffdec: Path) -> dict[str, Path]:
    return {p.stem: p for p in ffdec.rglob("*.as")}


def make_one(recovered: str, ffdec_method: str) -> list:
    by_text: dict[str, list[int]] = {}
    for k, line in enumerate(ffdec_method.splitlines()):
        by_text.setdefault(line.strip(), []).append(k)
    out, last = [], -1
    for line in recovered.splitlines():
        body = line.strip()
        candidates = by_text.get(body, []) if body else []
        k = next((c for c in candidates if c > last), candidates[0] if candidates else None)
        if k is None:
            out.append(line)
        else:
            out.append([line[:len(line) - len(line.lstrip())], k])
            last = k
    return out


def make(recovered_dir: Path, ffdec: Path) -> dict:
    files = class_files(ffdec)
    edits = {}
    for src in sorted(recovered_dir.glob("*.as")):
        owner, method = src.stem.split(".", 1)
        if owner not in files:
            raise EditError(f"{src.name}: no {owner}.as in {ffdec}")
        raw = method_text(files[owner].read_text(encoding="utf-8"), method)
        if raw is None:
            raise EditError(f"{src.name}: {method} not in FFDec's {owner}.as")
        recovered = src.read_text(encoding="utf-8")
        edits[src.name] = {"class": owner, "method": method, "lines": make_one(recovered.strip("\n"), raw),
                           "trailing_newline": recovered.endswith("\n"), "leading": len(recovered) - len(recovered.lstrip("\n")),
                           "crlf": b"\r\n" in src.read_bytes()}
        if encode(edits[src.name], apply_one(edits[src.name], raw)) != src.read_bytes():
            raise EditError(f"{src.name}: the edit doesn't rebuild the file")
    return edits


def apply_one(edit: dict, ffdec_method: str) -> str:
    lines = ffdec_method.splitlines()
    out = [entry if isinstance(entry, str) else entry[0] + lines[entry[1]].strip() for entry in edit["lines"]]
    return "\n" * edit.get("leading", 0) + "\n".join(out) + ("\n" if edit["trailing_newline"] else "")


def encode(edit: dict, text: str) -> bytes:
    return (text.replace("\n", "\r\n") if edit.get("crlf") else text).encode("utf-8")


def apply(edits: dict, ffdec: Path, out: Path) -> int:
    files = class_files(ffdec)
    out.mkdir(parents=True, exist_ok=True)
    for name, edit in edits.items():
        if edit["class"] not in files:
            raise EditError(f"{name}: no {edit['class']}.as in this decompile")
        raw = method_text(files[edit["class"]].read_text(encoding="utf-8"), edit["method"])
        if raw is None:
            raise EditError(f"{name}: {edit['method']} not in this decompile's {edit['class']}.as")
        (out / name).write_bytes(encode(edit, apply_one(edit, raw)))
    return len(edits)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("action", choices=("make", "apply"))
    p.add_argument("--version", default="11.00")
    p.add_argument("--ffdec", type=Path, required=True, help="FFDec's export with the aliases (its scripts folder)")
    p.add_argument("--edits", type=Path)
    p.add_argument("--out", type=Path, required=True)
    a = p.parse_args(argv)
    try:
        if a.action == "make":
            edits = make(ROOT / "src" / "as3-recovered" / a.version, a.ffdec)
            a.out.parent.mkdir(parents=True, exist_ok=True)
            a.out.write_text(json.dumps(edits, indent=1) + "\n", encoding="utf-8")
            literal = sum(1 for e in edits.values() for x in e["lines"] if isinstance(x, str))
            print(f"{len(edits)} recovered methods -> {a.out} ({literal} hand-written lines)")
        else:
            n = apply(json.loads(a.edits.read_text(encoding="utf-8")), a.ffdec, a.out)
            print(f"{n} recovered methods -> {a.out}")
        return 0
    except EditError as e:
        print(f"recovered_edits: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
