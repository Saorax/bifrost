"""where Bifrost's layer and server come from: the ``main`` branch checked out next to this folder as ``bifrost`` and
the server as ``bifrost-server`` (or BIFROST_LAYER / BIFROST_SERVER), each at its current commit (or
BIFROST_LAYER_COMMIT / BIFROST_SERVER_COMMIT).

    python tools/pins.py        # prints them
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAYER_DIR = Path(os.environ.get("BIFROST_LAYER") or ROOT.parent / "bifrost")
SERVER_DIR = Path(os.environ.get("BIFROST_SERVER") or ROOT.parent / "bifrost-server")
LAYER_BRANCH = os.environ.get("BIFROST_LAYER_BRANCH") or "main"


def head(repo: Path, ref: str) -> str:
    out = subprocess.run(["git", "-C", str(repo), "rev-parse", "--short=8", ref], capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else ref


def pins() -> dict[str, str]:
    return {"repo": str(LAYER_DIR), "branch": LAYER_BRANCH,
            "commit": os.environ.get("BIFROST_LAYER_COMMIT") or head(LAYER_DIR, LAYER_BRANCH),
            "server-repo": str(SERVER_DIR),
            "server-commit": os.environ.get("BIFROST_SERVER_COMMIT") or head(SERVER_DIR, "HEAD")}


if __name__ == "__main__":
    for key, value in pins().items():
        print(f"{key}: {value}")
    sys.exit(0)
