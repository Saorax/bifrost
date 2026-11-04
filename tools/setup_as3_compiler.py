"""install the pinned AS3 compiler (Apache Royale's compc) used to compile the exported game source.

    python tools/setup_as3_compiler.py [--dest .tools/royale] [--archive FILE] [--force] [--no-self-test]

extracts royale-asjs/lib from the hash-pinned release archive; compiles against FFDec's airglobal.swc, so no AIR SDK
is needed. Java 11+ must be on PATH.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.9.12"
ARCHIVE = f"apache-royale-{VERSION}-bin-js-swf.tar.gz"
URLS = (
    f"https://archive.apache.org/dist/royale/{VERSION}/binaries/{ARCHIVE}",
    f"https://downloads.apache.org/royale/{VERSION}/binaries/{ARCHIVE}",
)
SHA512 = (
    "6014ac9dcf1a09dd19ef06bc88d6995c3f6feefb643e9afa43000475644df416"
    "9bfe72e546a4c0d7c5206c7e7414acab153ab87dd4a61dc48b68b940686b6330"
)
SHA256 = "cbb2d5306b97c84e3afb30240366994a14b63e84698621192fdd1505aae76c37"
PREFIX = f"apache-royale-{VERSION}-bin-js-swf/"
KEEP = ("royale-asjs/lib/", "LICENSE", "NOTICE")
DEFAULT_DEST = ROOT / ".tools" / "royale"
AIRGLOBAL = ROOT / ".tools" / "ffdec" / "flashlib" / "airglobal.swc"


def file_hashes(path: Path) -> tuple[str, str]:
    h512, h256 = hashlib.sha512(), hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            h512.update(chunk)
            h256.update(chunk)
    return h512.hexdigest(), h256.hexdigest()


def check_archive(path: Path) -> None:
    h512, h256 = file_hashes(path)
    if h512 != SHA512 or h256 != SHA256:
        raise ValueError(f"{path.name}: hash mismatch (sha256 {h256})")


def download(dest: Path) -> None:
    errors = []
    for url in URLS:
        try:
            print(f"downloading {url}")
            with urllib.request.urlopen(url, timeout=120) as response, dest.open("wb") as out:
                shutil.copyfileobj(response, out, 1 << 20)
            return
        except OSError as exc:
            errors.append(f"{url}: {exc}")
    raise RuntimeError("download failed:\n  " + "\n  ".join(errors))


def wanted(name: str) -> str | None:
    if not name.startswith(PREFIX):
        return None
    rel = name[len(PREFIX):]
    if any(rel == keep or (keep.endswith("/") and rel.startswith(keep)) for keep in KEEP):
        return rel
    return None


def extract(archive: Path, dest: Path) -> int:
    count = 0
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar:
            rel = wanted(member.name)
            if rel is None or not (member.isfile() or member.isdir()):
                continue
            target = (dest / rel).resolve()
            if not target.is_relative_to(dest.resolve()):
                raise ValueError(f"unsafe archive path: {member.name}")
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with tar.extractfile(member) as src, target.open("wb") as out:
                shutil.copyfileobj(src, out)
            count += 1
    return count


def compc_jar(dest: Path = DEFAULT_DEST) -> Path:
    return dest / "royale-asjs" / "lib" / "compc.jar"


def self_test(dest: Path) -> None:
    if not AIRGLOBAL.is_file():
        raise FileNotFoundError(f"missing {AIRGLOBAL}")
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp, "src", "probe")
        src.mkdir(parents=True)
        (src / "Probe.as").write_text(
            "package probe {\n"
            "  import flash.display.Sprite;\n"
            "  public class Probe extends Sprite {\n"
            "    public function Probe() { super(); trace(Math.max(1, 2)); }\n"
            "  }\n"
            "}\n",
            encoding="utf-8",
        )
        config = Path(tmp, "config.xml")
        config.write_text("<royale-config/>\n", encoding="utf-8")
        out = Path(tmp, "probe.swc")
        cmd = [
            "java", "-jar", str(compc_jar(dest)), f"-load-config={config}",
            f"-compiler.external-library-path+={AIRGLOBAL}",
            f"-compiler.source-path+={Path(tmp, 'src')}",
            "-include-classes+=probe.Probe", f"-output={out}",
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0 or not out.is_file():
            raise RuntimeError("self-test compile failed:\n" + result.stdout + result.stderr)
    print("self-test OK: compiled probe.Probe against airglobal.swc")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dest", type=Path, default=DEFAULT_DEST)
    parser.add_argument("--archive", type=Path, help="use an already downloaded archive")
    parser.add_argument("--force", action="store_true", help="reinstall even if present")
    parser.add_argument("--no-self-test", action="store_true")
    args = parser.parse_args(argv)
    dest = args.dest.resolve()

    if compc_jar(dest).is_file() and not args.force:
        print(f"already installed: {compc_jar(dest)}")
    else:
        downloads = ROOT / ".tools" / "downloads"
        archive = args.archive or downloads / ARCHIVE
        if not archive.is_file():
            downloads.mkdir(parents=True, exist_ok=True)
            partial = archive.with_suffix(".part")
            download(partial)
            check_archive(partial)
            os.replace(partial, archive)
        check_archive(archive)
        if dest.exists():
            shutil.rmtree(dest)
        count = extract(archive, dest)
        (dest / "VERSION").write_text(f"{VERSION} sha256:{SHA256}\n", encoding="utf-8")
        print(f"installed Apache Royale {VERSION} compiler: {count} files in {dest}")
    if not args.no_self_test:
        self_test(dest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
