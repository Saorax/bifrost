"""summarise HashLink's allocation-tracking dump (the smoke driver's ``track dump TAG``: ``track-TAG.txt``) by site.

    python tools/port_heaps.py game --smoke waitmenu couch "wait 300" "track on 6" "wait 600" "track dump match" leave quit
    python tools/port_hl_track.py build/port-heaps/smoke/track-match.txt [--top 20] [--frames 2]
    python tools/port_hl_track.py after.txt --against before.txt     # the sites that changed most, by bytes

the dump (``hl.Profile.dump``) starts with ``N total allocs (B bytes)``, then one block per allocation type and stack:
``alloc COUNT TYPE (BYTES bytes)`` followed by tab-indented stack lines, innermost first. a site here is the type plus
the first ``--frames`` stack lines (file paths shortened to their last part), so the same place reached from several
callers counts once.
"""
from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

HEADER = re.compile(r"(\d+) total allocs \((\d+) bytes\)")
ALLOC = re.compile(r"alloc\s+(\d+) (.*) \((\d+) bytes\)")
PATH = re.compile(r"\(([^()]*[\\/])([^\\/()]+)\)")


def short(frame: str) -> str:
    return PATH.sub(lambda m: "(" + m.group(2) + ")", frame.strip())


def parse(text: str, frames: int = 2) -> tuple[int, int, dict[tuple[str, ...], list[int]]]:
    lines = text.split("\n")
    total = HEADER.match(lines[0]) if lines else None
    sites: dict[tuple[str, ...], list[int]] = defaultdict(lambda: [0, 0])
    i = 1
    while i < len(lines):
        m = ALLOC.match(lines[i])
        if not m:
            i += 1
            continue
        stack = []
        j = i + 1
        while j < len(lines) and lines[j].startswith("\t"):
            stack.append(short(lines[j]))
            j += 1
        key = (m.group(2)[:60],) + tuple(stack[:frames])
        sites[key][0] += int(m.group(3))
        sites[key][1] += int(m.group(1))
        i = j
    return (int(total.group(1)) if total else 0, int(total.group(2)) if total else 0, dict(sites))


def merge(texts: list[str]) -> str:
    count = size = 0
    body: list[str] = []
    for text in texts:
        lines = text.split("\n")
        total = HEADER.match(lines[0]) if lines else None
        if total:
            count += int(total.group(1))
            size += int(total.group(2))
            lines = lines[1:]
        body.extend(line for line in lines if line.strip())
    return f"{count} total allocs ({size} bytes)\n" + "\n".join(body) + "\n"


def describe(key: tuple[str, ...]) -> str:
    return " | ".join(key)


def top(text: str, n: int, frames: int) -> str:
    count, size, sites = parse(text, frames)
    out = [f"{count} allocations, {size / 1e6:.1f} MB"]
    for key, (b, c) in sorted(sites.items(), key=lambda kv: -kv[1][0])[:n]:
        out.append(f"{b / 1e6:7.2f} MB {c:9d}  {describe(key)}")
    return "\n".join(out)


def diff(after: str, before: str, n: int, frames: int) -> str:
    ac, asize, a = parse(after, frames)
    bc, bsize, b = parse(before, frames)
    out = [f"allocations {bc} -> {ac}, {bsize / 1e6:.1f} -> {asize / 1e6:.1f} MB"]
    keys = set(a) | set(b)
    changes = sorted(keys, key=lambda k: -abs(a.get(k, [0, 0])[0] - b.get(k, [0, 0])[0]))
    for key in changes[:n]:
        was, now = b.get(key, [0, 0])[0], a.get(key, [0, 0])[0]
        out.append(f"{(now - was) / 1e6:+7.2f} MB ({was / 1e6:.2f} -> {now / 1e6:.2f})  {describe(key)}")
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("dump")
    parser.add_argument("--against", help="an earlier dump: print the sites that changed most")
    parser.add_argument("--top", type=int, default=20)
    parser.add_argument("--frames", type=int, default=2, help="stack lines that name a site")
    args = parser.parse_args(argv)
    text = Path(args.dump).read_text(encoding="utf-8", errors="replace")
    if args.against:
        print(diff(text, Path(args.against).read_text(encoding="utf-8", errors="replace"), args.top, args.frames))
    else:
        print(top(text, args.top, args.frames))
    return 0


if __name__ == "__main__":
    sys.exit(main())
