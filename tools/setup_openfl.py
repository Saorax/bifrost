from __future__ import annotations

import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.workspace_paths import checked_output

REPO = ROOT / ".tools" / "haxelib"
LIBRARIES = {
    "openfl": ("9.5.2", "873fa3739d80cc9ac0f48d3e27cc5684bfd60331f68caf647979de6ff437d273"),
    "lime": ("8.3.2", "ab44323146dff6512458fcb03b1c32cb9c492c64f2c0e574de9d5d929b929dff"),
}


def haxelib_version_dir(version: str) -> str:
    return version.replace(".", ",")


def library_path(name: str) -> Path:
    version, _digest = LIBRARIES[name]
    return REPO / name / haxelib_version_dir(version)


def install(name: str) -> dict:
    version, digest = LIBRARIES[name]
    archive_name = f"{name}-{haxelib_version_dir(version)}.zip"
    archive_path = checked_output(ROOT / ".tools" / archive_name, ROOT / ".tools")
    url = f"https://lib.haxe.org/files/3.0/{archive_name}"
    if not archive_path.exists():
        print(f"Downloading official {name} {version}", flush=True)
        with urllib.request.urlopen(url, timeout=120) as response, archive_path.open("xb") as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
    if hashlib.sha256(archive_path.read_bytes()).hexdigest() != digest:
        raise ValueError(f"{name} archive checksum mismatch: {archive_path}")
    destination = checked_output(library_path(name), ROOT / ".tools")
    files = 0
    total = 0
    with zipfile.ZipFile(archive_path) as archive:
        for entry in archive.infolist():
            relative = PurePosixPath(entry.filename)
            if relative.is_absolute() or ".." in relative.parts or not relative.parts:
                raise ValueError(f"Unexpected ZIP path: {entry.filename}")
            if entry.is_dir():
                continue
            target = destination / Path(*relative.parts)
            if not target.resolve().is_relative_to(destination.resolve()):
                raise ValueError(f"ZIP path escapes tool directory: {entry.filename}")
            data = archive.read(entry)
            if target.exists():
                if not target.is_file() or target.read_bytes() != data:
                    raise ValueError(f"Existing {name} file differs from the pinned release: {target}")
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
            files += 1
            total += len(data)
    meta = json.loads((destination / "haxelib.json").read_text(encoding="utf-8"))
    if meta.get("version") != version:
        raise ValueError(f"Unexpected {name} version: {meta.get('version')}")
    (REPO / name / ".current").write_text(version, encoding="utf-8")
    print(f"{name} {version} ready: {destination} ({files} files)")
    return {"name": name, "version": version, "url": url, "archive_sha256": digest, "files": files, "bytes": total}


def main() -> None:
    REPO.mkdir(parents=True, exist_ok=True)
    libraries = [install(name) for name in LIBRARIES]
    hdll = library_path("lime") / "ndll" / "Windows64" / "lime.hdll"
    report = {
        "schema_version": 1,
        "purpose": "Engine port P5: the Flash API (OpenFL) and window/input/audio layer (Lime) on HashLink.",
        "hash_provenance": "SHA-256 observed from the official HTTPS lib.haxe.org download and pinned locally; "
                           "lib.haxe.org lists no digests.",
        "libraries": libraries,
        "lime_hdll_sha256": hashlib.sha256(hdll.read_bytes()).hexdigest(),
    }
    report_path = checked_output(ROOT / "reports/toolchain/openfl.json", ROOT / "reports")
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
