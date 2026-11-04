"""the game files a release is made for, and the quick list the launcher checks at each start.

    python tools/game_files.py fingerprint DIR    # sha-256 over every .swf and .swz in the install's top folder
    python tools/game_files.py stats DIR          # "size filetime name" lines (the launcher's start check)

a file that Bifrost keeps as ``<name>.bifrost-original`` counts as that original.
"""
from __future__ import annotations

import argparse
import hashlib
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

SUFFIXES = (".swf", ".swz")
ORIGINAL = ".bifrost-original"
FILETIME_EPOCH = 116444736000000000


def files(game: Path) -> dict[str, Path]:
    found: dict[str, Path] = {}
    for path in game.iterdir():
        if not path.is_file():
            continue
        name = path.name
        if name.lower().endswith(ORIGINAL):
            base = name[: -len(ORIGINAL)]
            if base.lower().endswith(SUFFIXES):
                found[base] = path
        elif name.lower().endswith(SUFFIXES) and name not in found:
            found[name] = path
    return dict(sorted(found.items(), key=lambda item: (item[0].lower(), item[0])))


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


_fingerprints: dict[tuple[str, str], str] = {}


def fingerprint(game: Path) -> str:
    listed = files(game)
    if not listed:
        raise FileNotFoundError(f"{game}: no .swf or .swz files")
    seen = (str(game.resolve()), stats(game))
    if seen in _fingerprints:
        return _fingerprints[seen]
    with ThreadPoolExecutor(4) as pool:
        sums = list(pool.map(sha256, listed.values()))
    lines = "".join(f"{name}\t{digest}\n" for name, digest in zip(listed, sums))
    _fingerprints[seen] = hashlib.sha256(lines.encode("utf-8")).hexdigest()
    return _fingerprints[seen]


def stats(game: Path) -> str:
    out = []
    for name, path in files(game).items():
        info = path.stat()
        out.append(f"{info.st_size} {info.st_mtime_ns // 100 + FILETIME_EPOCH} {path.name}\n")
    return "".join(out)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("what", choices=("fingerprint", "stats"))
    p.add_argument("game", type=Path)
    a = p.parse_args(argv)
    print(fingerprint(a.game) if a.what == "fingerprint" else stats(a.game), end="" if a.what == "stats" else "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
