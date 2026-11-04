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
VERSION = "4.3.7"
URL = f"https://github.com/HaxeFoundation/haxe/releases/download/{VERSION}/haxe-{VERSION}-win64.zip"
SHA256 = "29f7acb0fb9fc66a2b9f6bd9453af3474ccb14ebd9fd0142f351d7311c4010c9"
ARCHIVE_ROOT = "haxe_20250509143529_e0b355c"


def main() -> None:
    archive_path = checked_output(ROOT / f".tools/haxe-{VERSION}-win64.zip", ROOT / ".tools")
    destination = checked_output(ROOT / ".tools/haxe", ROOT / ".tools")
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    if not archive_path.exists():
        print(f"Downloading official Haxe {VERSION} portable compiler", flush=True)
        with urllib.request.urlopen(URL, timeout=60) as response, archive_path.open("xb") as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
    if hashlib.sha256(archive_path.read_bytes()).hexdigest() != SHA256:
        raise ValueError(f"Compiler ZIP checksum mismatch: {archive_path}")
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
                    raise ValueError(f"Existing compiler file differs from pinned bundle: {target}")
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
            files.append({"path": local.as_posix(), "size": len(data), "sha256": digest})
    compiler = destination / "haxe.exe"
    actual_version = subprocess.check_output([str(compiler), "--version"], text=True).strip()
    if actual_version != VERSION:
        raise ValueError(f"Unexpected Haxe version: {actual_version}")
    report = {
        "schema_version": 1, "name": "Haxe", "version": VERSION,
        "purpose": "Pinned reconstruction compiler; original game compiler version remains unknown.",
        "url": URL, "archive_sha256": SHA256,
        "hash_provenance": "SHA-256 observed from the official HTTPS release download and pinned locally; not an upstream signed digest.",
        "files": files,
    }
    report_path = checked_output(ROOT / "reports/toolchain/haxe.json", ROOT / "reports")
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Haxe {actual_version} ready: {compiler}")


if __name__ == "__main__":
    main()
