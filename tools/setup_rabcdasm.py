"""build the pinned, patched RABCDAsm toolchain inside this workspace (Windows, Linux, macOS).

    python tools/setup_rabcdasm.py [--repin]

pinned LDC + RABCDAsm commit + tools/patches/rabcdasm-denormal-fix.patch (stock builds crash on the game's subnormal
doubles), binaries in .tools/rabcdasm/bin checked against BINARY_SHA256 (win-x64), then a subnormal round-trip
self-test; report in reports/toolchain/rabcdasm.json (rabcdasm-<rid>.json off win-x64).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import stat
import subprocess
import sys
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.workspace_paths import checked_output

TOOLS = ROOT / ".tools"
LDC_VERSION = "1.43.0"
LDC_PACKAGES = {
    "win-x64": ("windows-x64.7z", "60ae3d5e34287aa25433c7550520060a52f9f212e3d5ff6472a9067d8d17e47e"),
    "linux-x64": ("linux-x86_64.tar.xz", "35805db60f47fd1a162b2035da84d96beec37e6d1e7b1edf60498a90acfaedce"),
    "linux-arm64": ("linux-aarch64.tar.xz", "f2b24edc254d4b9944234f641de3c4b3a36d5752639ec30cb2bbe122931b2283"),
    "osx-x64": ("osx-x86_64.tar.xz", "dee787ee77363f189e71ebda8e80acebb735dc6fc190a38d1f90a016d0c01624"),
    "osx-arm64": ("osx-arm64.tar.xz", "5e332349c784d4e0b1c4622284803880f89d97ef1ef97c6b25aa4d6b094c5fed"),
}
LDC_NAME = f"ldc2-{LDC_VERSION}-windows-x64"
LDC_URL = f"https://github.com/ldc-developers/ldc/releases/download/v{LDC_VERSION}/{LDC_NAME}.7z"
LDC_SHA256 = LDC_PACKAGES["win-x64"][1]
RABCDASM_REPO = "https://github.com/CyberShadow/RABCDAsm.git"
RABCDASM_COMMIT = "8ed623a3225ec9947f75f50bc78f5d2412a0802d"
PATCH = ROOT / "tools/patches/rabcdasm-denormal-fix.patch"
DFLAGS = ["-O", "-release", "-i", "--link-internally", "-L/Brepro", "-d"]
POSIX_DFLAGS = ["-O", "-release", "-i", "-d"]
PROGRAMS = ["abcexport", "abcreplace", "rabcasm", "rabcdasm", "swfbinexport", "swfbinreplace", "swfdecompress"]
BINARY_SHA256 = {
    "abcexport": "23994ab2e3cdb85bef944a62df35df8405bffd12f60246a4456f46a52243762c",
    "abcreplace": "8a45c47dd732707baa301a4874b40a171cca8af91c1b35448b990b2f1ceb82c6",
    "rabcasm": "1ccf6ba68c956af1b6c51e293c86dc3980853fdbe2a0848e7113a8078677f8c2",
    "rabcdasm": "d59f90895c5f0736be8ac32ca97c3f5c739b79a32200f4be3913edb4df9366c8",
    "swfbinexport": "55f290c51dc5ab3425affaf38c2e62238444124f13f971f87f7149102a0c6357",
    "swfbinreplace": "fcb2c4f7e637bc05ce6d3e8c4c38f0da2cfc629336a3655361ba8954cc6850a6",
    "swfdecompress": "2c0250a84e46487afa3e2226258cfd0de8147ec1a120008ba37d344cfdec6d1c",
}


def host_rid() -> str:
    system = {"win32": "win", "darwin": "osx"}.get(sys.platform, "linux")
    machine = platform.machine().lower()
    return f"{system}-{'arm64' if machine in ('arm64', 'aarch64') else 'x64'}"


def exe(rid: str) -> str:
    return ".exe" if rid.startswith("win-") else ""


def ldc_package(rid: str) -> tuple[str, str, str]:
    if rid not in LDC_PACKAGES:
        sys.exit(f"no pinned LDC package for {rid} (have: {', '.join(LDC_PACKAGES)})")
    file, digest = LDC_PACKAGES[rid]
    name = f"ldc2-{LDC_VERSION}-{file.split('.')[0]}"
    return name, f"https://github.com/ldc-developers/ldc/releases/download/v{LDC_VERSION}/ldc2-{LDC_VERSION}-{file}", digest


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def remove_tree(path: Path) -> None:
    def make_writable(func, target, _exc):
        os.chmod(target, stat.S_IWRITE)
        func(target)
    shutil.rmtree(path, onexc=make_writable)


def run(cmd, cwd=None):
    print("+", " ".join(str(c) for c in cmd), flush=True)
    subprocess.run([str(c) for c in cmd], cwd=cwd, check=True)


def bsdtar() -> str:
    system_tar = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32/tar.exe"
    if system_tar.exists():
        return str(system_tar)
    found = shutil.which("bsdtar")
    if not found:
        sys.exit("need bsdtar (Windows System32\\tar.exe) to unpack the LDC .7z")
    return found


def install_ldc(rid: str) -> Path:
    name, url, digest = ldc_package(rid)
    archive = checked_output(TOOLS / "dl" / url.rsplit("/", 1)[1], TOOLS)
    ldc_dir = checked_output(TOOLS / name, TOOLS)
    compiler = ldc_dir / f"bin/ldc2{exe(rid)}"
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        print(f"Downloading LDC {LDC_VERSION}", flush=True)
        partial = archive.with_suffix(".part")
        with urllib.request.urlopen(url, timeout=120) as response, partial.open("wb") as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
        partial.replace(archive)
    if sha256(archive) != digest:
        raise ValueError(f"LDC archive checksum mismatch: {archive}")
    if not compiler.exists():
        if archive.name.endswith(".7z"):
            run([bsdtar(), "-xf", archive, "-C", TOOLS])
        else:
            with tarfile.open(archive, "r:xz") as tar:
                tar.extractall(TOOLS, filter="tar")
    version = subprocess.check_output([str(compiler), "--version"], text=True).splitlines()[0]
    if LDC_VERSION not in version:
        raise ValueError(f"Unexpected LDC version: {version}")
    return compiler


def fetch_source() -> Path:
    src = checked_output(TOOLS / "rabcdasm-src", TOOLS)
    if src.exists():
        remove_tree(src)
    src.mkdir(parents=True)
    run(["git", "init", "-q"], cwd=src)
    run(["git", "config", "core.autocrlf", "false"], cwd=src)
    run(["git", "fetch", "-q", "--depth", "1", RABCDASM_REPO, RABCDASM_COMMIT], cwd=src)
    run(["git", "-c", "advice.detachedHead=false", "checkout", "-q", "FETCH_HEAD"], cwd=src)
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=src, text=True).strip()
    if head != RABCDASM_COMMIT:
        raise ValueError(f"Unexpected RABCDAsm commit: {head}")
    run(["git", "apply", "--whitespace=nowarn", PATCH], cwd=src)
    return src


def build(compiler: Path, src: Path, repin: bool, rid: str) -> list[dict]:
    bin_dir = checked_output(TOOLS / "rabcdasm/bin", TOOLS)
    if bin_dir.exists():
        remove_tree(bin_dir)
    bin_dir.mkdir(parents=True)
    obj_dir = src / "obj"
    results, mismatched = [], []
    for program in PROGRAMS:
        out = bin_dir / f"{program}{exe(rid)}"
        run([compiler, *(DFLAGS if rid.startswith("win-") else POSIX_DFLAGS), f"-od={obj_dir / program}", f"-of={out}", f"{program}.d"], cwd=src)
        digest = sha256(out)
        results.append({"name": out.name, "size": out.stat().st_size, "sha256": digest})
        if rid != "win-x64":
            continue
        expected = BINARY_SHA256.get(program)
        if expected != digest:
            mismatched.append((program, expected, digest))
    if mismatched:
        for program, expected, digest in mismatched:
            print(f'    "{program}": "{digest}",  # expected {expected}')
        if not repin:
            raise ValueError("Built binaries differ from BINARY_SHA256; rerun with --repin after reviewing")
    return results


def self_test(bin_dir: Path, rid: str) -> None:
    work = checked_output(TOOLS / "rabcdasm-selftest", TOOLS)
    if work.exists():
        remove_tree(work)
    (work / "t").mkdir(parents=True)
    (work / "t/t.main.asasm").write_text(
        "program\n minorversion 16\n majorversion 46\n script\n  sinit\n   refid \"t/init\"\n   body\n"
        "    maxstack 1\n    localcount 1\n    initscopedepth 0\n    maxscopedepth 1\n    code\n"
        "     getlocal0\n     pushscope\n     pushdouble 4.9406564584124654e-324\n     pop\n"
        "     pushdouble 2.2250738585072009e-308\n     pop\n     returnvoid\n    end ; code\n"
        "   end ; body\n  end ; method\n end ; script\nend ; program\n",
        encoding="utf-8",
    )
    run([bin_dir / f"rabcasm{exe(rid)}", "t/t.main.asasm"], cwd=work)
    first = (work / "t/t.main.abc").read_bytes()
    shutil.move(work / "t", work / "u")
    (work / "u/t.main.abc").rename(work / "t.abc")
    run([bin_dir / f"rabcdasm{exe(rid)}", "t.abc"], cwd=work)
    run([bin_dir / f"rabcasm{exe(rid)}", "t/t.main.asasm"], cwd=work)
    if (work / "t/t.main.abc").read_bytes() != first:
        raise ValueError("RABCDAsm self-test: subnormal double round-trip changed the ABC")
    remove_tree(work)
    print("Self-test passed: subnormal doubles round-trip")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repin", action="store_true", help="report new binary hashes instead of failing")
    args = parser.parse_args()
    rid = host_rid()
    _, url, digest = ldc_package(rid)
    compiler = install_ldc(rid)
    src = fetch_source()
    binaries = build(compiler, src, args.repin, rid)
    self_test(TOOLS / "rabcdasm/bin", rid)
    report = {
        "schema_version": 1, "name": "RABCDAsm",
        "rid": rid, "commit": RABCDASM_COMMIT, "repository": RABCDASM_REPO,
        "patch": PATCH.relative_to(ROOT).as_posix(), "patch_sha256": sha256(PATCH),
        "compiler": {"name": "LDC", "version": LDC_VERSION, "url": url, "archive_sha256": digest,
                     "hash_provenance": "SHA-256 published as the GitHub release asset digest."},
        "flags": DFLAGS if rid.startswith("win-") else POSIX_DFLAGS, "binaries": binaries,
    }
    report_path = checked_output(ROOT / "reports/toolchain" / ("rabcdasm.json" if rid == "win-x64" else f"rabcdasm-{rid}.json"),
                                 ROOT / "reports")
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"RABCDAsm ready: {TOOLS / 'rabcdasm/bin'}")


if __name__ == "__main__":
    main()
