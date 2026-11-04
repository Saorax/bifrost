"""the game files a release is made for, and the quick list the launcher checks at each start.

    python tools/game_files.py fingerprint DIR    # sha-256 over every .swf and .swz in the install's top folder
    python tools/game_files.py stats DIR          # "size filetime name" lines (the launcher's start check)

a file that Bifrost keeps as ``<name>.bifrost-original`` counts as that original. a release lists each file's
sha-256 (``listing``): the game's code and data (``core``: BrawlhallaAir.swf and the .swz files) must match it; another
listed file that differs (an art or sound .swf a mod or a skipped Steam update left) is only reported, since the build
never reads those. files the release doesn't list are left out.
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


_listings: dict[tuple[str, str], dict[str, str]] = {}


def listing(game: Path) -> dict[str, str]:
    listed = files(game)
    if not listed:
        raise FileNotFoundError(f"{game}: no .swf or .swz files")
    seen = (str(game.resolve()), stats(game))
    if seen not in _listings:
        with ThreadPoolExecutor(4) as pool:
            _listings[seen] = dict(zip(listed, pool.map(sha256, listed.values())))
    return dict(_listings[seen])


def fingerprint(game: Path) -> str:
    lines = "".join(f"{name}\t{digest}\n" for name, digest in listing(game).items())
    return hashlib.sha256(lines.encode("utf-8")).hexdigest()


def differences(game: Path, want: dict[str, str]) -> list[str]:
    have = {name.lower(): digest for name, digest in listing(game).items()}
    out = []
    for name, digest in want.items():
        found = have.get(name.lower())
        if found != digest:
            out.append(name if found else f"{name} (missing)")
    return out


def core(name: str) -> bool:
    name = name.lower().removesuffix(" (missing)")
    return name == "brawlhallaair.swf" or name.endswith(".swz")


def describe(names: list[str], shown: int = 5) -> str:
    more = f" and {len(names) - shown} more" if len(names) > shown else ""
    return ", ".join(names[:shown]) + more


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
