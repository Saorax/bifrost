"""records which engine sources an export was made from, so a release can refuse an old export.

``tools/bifrost_export.py`` writes ``engine-source.json`` into the folder it exports; ``tools/player_kit.py`` compares it
with the sources as they are now. the hash covers file contents, so committing doesn't change it.
"""
from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path

STAMP = "engine-source.json"
EXPORT_TOOLS = ("bifrost_export.py", "port_heaps.py", "port_heaps_stubs.py", "port_raw_export.py")


def source_files(root: Path) -> list[Path]:
    out = subprocess.run(["git", "-C", str(root), "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "port"],
                         capture_output=True)
    if out.returncode != 0:
        raise OSError(f"git ls-files in {root}: {out.stderr.decode(errors='replace').strip()}")
    files = [root / name for name in out.stdout.decode("utf-8").split("\0") if name]
    files += [root / "tools" / name for name in EXPORT_TOOLS]
    return sorted(path for path in files if path.is_file())


def source_hash(root: Path) -> str:
    digest = hashlib.sha256()
    for path in source_files(root):
        digest.update(path.relative_to(root).as_posix().encode() + b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


def write(out: Path, root: Path, version: str) -> None:
    (out / STAMP).write_text(json.dumps({"source": source_hash(root), "version": version}) + "\n", encoding="utf-8")


def stale(engine: Path, root: Path, version: str) -> str | None:
    stamp = engine / STAMP
    if not stamp.exists():
        return f"no {STAMP}: the export is older than this check"
    data = json.loads(stamp.read_text(encoding="utf-8"))
    if data.get("version") != version:
        return f"exported for game version {data.get('version')}, not {version}"
    if data.get("source") != source_hash(root):
        return "the engine sources changed after this export"
    return None
