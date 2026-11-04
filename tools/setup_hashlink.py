from __future__ import annotations

import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.workspace_paths import checked_output
VERSION = "1.15.0"
URL = f"https://github.com/HaxeFoundation/hashlink/releases/download/1.15/hashlink-{VERSION}-win.zip"
SHA256 = "69f1e2af38e8e912ee7fcd6869ba4a2eb352ad1b577701aee5503d7fd775657e"
ARCHIVE_ROOT = f"hashlink-{VERSION}-win"


def main() -> None:
    archive_path = checked_output(ROOT / f".tools/hashlink-{VERSION}-win.zip", ROOT / ".tools")
    destination = checked_output(ROOT / ".tools/hashlink", ROOT / ".tools")
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    if not archive_path.exists():
        print(f"Downloading official HashLink {VERSION}", flush=True)
        with urllib.request.urlopen(URL, timeout=60) as response, archive_path.open("xb") as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
    if hashlib.sha256(archive_path.read_bytes()).hexdigest() != SHA256:
        raise ValueError(f"HashLink ZIP checksum mismatch: {archive_path}")
    files = []
    with zipfile.ZipFile(archive_path) as archive:
        for entry in archive.infolist():
            relative = PurePosixPath(entry.filename)
            if relative.is_absolute() or ".." in relative.parts or not relative.parts or relative.parts[0] != ARCHIVE_ROOT:
                raise ValueError(f"Unexpected ZIP path: {entry.filename}")
            if entry.is_dir():
                continue
            local = Path(*relative.parts[1:])
            target = checked_output(destination / local, ROOT / ".tools")
            if not target.resolve().is_relative_to(destination.resolve()):
                raise ValueError(f"ZIP path escapes tool directory: {entry.filename}")
            data = archive.read(entry)
            digest = hashlib.sha256(data).hexdigest()
            if target.exists():
                if not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest() != digest:
                    raise ValueError(f"Existing HashLink file differs from pinned bundle: {target}")
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
            files.append({"path": local.as_posix(), "size": len(data), "sha256": digest})
    vm = destination / "hl.exe"
    actual_version = subprocess.check_output([str(vm), "--version"], text=True).strip()
    if actual_version != VERSION:
        raise ValueError(f"Unexpected HashLink version: {actual_version}")
    report = {
        "schema_version": 1, "name": "HashLink", "version": VERSION,
        "purpose": "Engine port P5 target VM; runtime-service tests on a target with UDP.",
        "url": URL, "archive_sha256": SHA256,
        "hash_provenance": "SHA-256 observed from the official HTTPS release download and pinned locally; the GitHub "
                           "release lists no digest for this asset.",
        "files": files,
    }
    report_path = checked_output(ROOT / "reports/toolchain/hashlink.json", ROOT / "reports")
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"HashLink {actual_version} ready: {vm}")


if __name__ == "__main__":
    main()
