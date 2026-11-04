"""give the AS3-built game SWF its original identifiers back.

    python tools/rename_back.py [--version 10.11] [--swf build/as3/<ver>/BrawlhallaAir.swf]
                                [--out build/as3/<ver>/BrawlhallaAir.original-names.swf]

rewrites each ABC block's string pool from FFDec's renamed identifiers (and the aliases) back to the original strings
in ``client/symbols/<ver>.json`` and puts the blocks into a copy of the original SWF. only the string pool changes:
the rest of a block refers to strings by index. the map must be one-to-one and no renamed name may be a genuine string
of the original (both checked every run). the output is then compared method by method with the original SWF; every
method must be ``equal`` or ``equivalent``, except those edited in ``build/as3/<ver>/splice.json``.
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
from tools import abc_roundtrip, compare_methods, name_map


class RenameError(Exception):
    pass


def back_map(symbols: dict) -> dict[str, str]:
    back: dict[str, set[str]] = {}
    for b in symbols["blocks"]:
        pairs = [(r[2], r[1]) for r in b["strings"]] + [(r[2], r[1]) for r in b["classes"]] \
            + [(r[2], r[1]) for r in b["namespaces"]] + [(r[4], r[3]) for r in b["members"]] \
            + [(r[5], r[4]) for r in b["methods"]]
        for renamed, original in pairs:
            if renamed != original:
                back.setdefault(renamed, set()).add(original)
    ambiguous = sorted(k for k, v in back.items() if len(v) > 1)
    if ambiguous:
        raise RenameError(f"renamed names with more than one original: {ambiguous[:5]}")
    return {k: next(iter(v)) for k, v in back.items()}


def alias_back_map(aliases: list[dict], back: dict[str, str]) -> dict[str, str]:
    out = {}
    for e in aliases:
        renamed = e["renamed"].split(".")[-1]
        if renamed not in back:
            raise RenameError(f"alias {e['alias']}: renamed string {renamed} has no original in the map")
        if out.setdefault(e["alias"], back[renamed]) != back[renamed]:
            raise RenameError(f"alias {e['alias']} stands for more than one original")
    clash = sorted(set(out) & set(back))
    if clash:
        raise RenameError(f"aliases that are also renamed names: {clash[:5]}")
    return out


def _u30(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def _read_u30(data: bytes, pos: int) -> tuple[int, int]:
    result, shift = 0, 0
    for _ in range(5):
        byte = data[pos]
        pos += 1
        result |= (byte & 0x7F) << shift
        if not byte & 0x80:
            break
        shift += 7
    return result & 0xFFFFFFFF, pos


def string_pool(abc: bytes) -> tuple[int, int, list[bytes]]:
    pos = 4
    count, pos = _read_u30(abc, pos)
    for _ in range(max(count - 1, 0)):
        _, pos = _read_u30(abc, pos)
    count, pos = _read_u30(abc, pos)
    for _ in range(max(count - 1, 0)):
        _, pos = _read_u30(abc, pos)
    count, pos = _read_u30(abc, pos)
    pos += 8 * max(count - 1, 0)
    start = pos
    count, pos = _read_u30(abc, pos)
    strings = []
    for _ in range(max(count - 1, 0)):
        length, pos = _read_u30(abc, pos)
        strings.append(abc[pos:pos + length])
        pos += length
    return start, pos, strings


def rename_abc(abc: bytes, back: dict[str, str]) -> tuple[bytes, int]:
    start, end, strings = string_pool(abc)
    out, n = bytearray(_u30(len(strings) + 1 if strings else 0)), 0
    for raw in strings:
        text = raw.decode("utf-8", errors="surrogateescape")
        if text in back:
            raw = back[text].encode("utf-8", errors="surrogateescape")
            n += 1
        out += _u30(len(raw)) + raw
    return abc[:start] + bytes(out) + abc[end:], n


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--version", default="10.11")
    p.add_argument("--swf", help="AS3-built SWF (default build/as3/<ver>/BrawlhallaAir.swf)")
    p.add_argument("--original", help="original SWF (default versions/<ver>/BrawlhallaAir.swf)")
    p.add_argument("--map", help="name map (default client/symbols/<ver>.json)")
    p.add_argument("--splice-report", help="splice_as3.py report (default build/as3/<ver>/splice.json)")
    p.add_argument("--out", help="output (default build/as3/<ver>/BrawlhallaAir.original-names.swf)")
    p.add_argument("--rabcdasm", default=str(abc_roundtrip.LOCAL_RABCDASM))
    args = p.parse_args(argv)
    out_dir = ROOT / "build" / "as3" / args.version
    built = Path(args.swf or out_dir / "BrawlhallaAir.swf")
    original = Path(args.original or ROOT / "versions" / args.version / "BrawlhallaAir.swf")
    symbols = Path(args.map or ROOT / "client" / "symbols" / f"{args.version}.json")
    report_path = Path(args.splice_report or out_dir / "splice.json")
    out = Path(args.out or out_dir / "BrawlhallaAir.original-names.swf")
    for path in (built, original, symbols):
        if not path.exists():
            print(f"missing {path}", file=sys.stderr)
            return 2
    try:
        back = back_map(json.loads(symbols.read_text(encoding="utf-8")))
        aliases = symbols.with_name(f"{args.version}.aliases.json")
        if aliases.exists():
            back.update(alias_back_map(json.loads(aliases.read_text(encoding="utf-8"))["aliases"], back))
        orig_blocks = [t["abc"] for t in name_map.abc_tags(original.read_bytes())]
        genuine = {s.decode("utf-8", errors="surrogateescape") for abc in orig_blocks for s in string_pool(abc)[2]}
        clash = sorted(set(back) & genuine)
        if clash:
            raise RenameError(f"renamed names that are also strings of the original: {clash[:5]}")
        built_blocks = [t["abc"] for t in name_map.abc_tags(built.read_bytes())]
        if len(built_blocks) != len(orig_blocks):
            raise RenameError(f"{built} has {len(built_blocks)} ABC blocks, the original {len(orig_blocks)}")
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(original, out)
        total, abcs = 0, {}
        for i, abc in enumerate(built_blocks):
            abcs[i], n = rename_abc(abc, back)
            total += n
        abc_roundtrip.replace_blocks(out, abcs)
    except RenameError as e:
        print(f"rename FAILED: {e}", file=sys.stderr)
        return 1

    compare_methods.prepare(orig_blocks)
    result = compare_methods.compare(compare_methods.collect(orig_blocks, cache=True),
                                     compare_methods.collect(compare_methods.swf_blocks(out)))
    edited, added = set(), set()
    if report_path.exists():
        splice_report = json.loads(report_path.read_text(encoding="utf-8"))
        edited = {re.sub(r"[A-Za-z_$][A-Za-z0-9_$]*", lambda m: back.get(m.group(0), m.group(0)), k)
                  for k in splice_report.get("edited_compiled", [])}
        added = set(splice_report.get("added_classes", []))

    def allowed(key: str, status: str) -> bool:
        head = key[len("script "):] if key.startswith("script ") else key
        return re.sub(r"(/fn\d+)+$", "", key) in edited or (status == "extra" and head.split("/", 1)[0] in added)

    bad = sorted(k for k, m in result["methods"].items() if m["status"] not in ("equal", "equivalent")
                 and not allowed(k, m["status"]))
    t = result["totals"]
    print(f"{total} strings renamed back -> {out} ({out.stat().st_size} bytes)")
    print(f"against the original SWF: {t['original']} methods: "
          + ", ".join(f"{s} {t.get(s, 0)}" for s in ("equal", "equivalent", "signature", "code", "missing", "extra")))
    for k in bad[:10]:
        print(f"  {k}: {result['methods'][k]['status']} ({result['methods'][k]['cause']})", file=sys.stderr)
    print("FAILED" if bad else "OK")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
