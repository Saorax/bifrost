"""build the tiny Windows Discord IPC bridge used by the in-game Rich Presence mod.

the bridge has no third-party dependencies; it is compiled /MT as a windowless x64 executable and placed beside the
rebuilt SWF. non-windows builders skip it.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "src" / "platform" / "native" / "discord_bridge.cpp"


def visual_studio_root() -> Path | None:
    vswhere = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "Microsoft Visual Studio" / "Installer" / "vswhere.exe"
    if vswhere.exists():
        result = subprocess.run(
            [str(vswhere), "-latest", "-products", "*", "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath"],
            text=True,
            capture_output=True,
        )
        if result.returncode == 0 and result.stdout.strip():
            return Path(result.stdout.strip())
    roots = [Path(r"C:\Program Files\Microsoft Visual Studio"), Path(r"C:\Program Files (x86)\Microsoft Visual Studio")]
    for root in roots:
        if root.exists():
            matches = sorted(root.glob("*/*/VC/Auxiliary/Build/vcvars64.bat"), reverse=True)
            if matches:
                return matches[0].parents[4]
    return None


def stamp_of() -> str:
    return hashlib.sha1(SOURCE.read_bytes() + Path(__file__).read_bytes()).hexdigest()


def build(out: Path) -> int:
    if os.name != "nt":
        print("Discord bridge: skipped (Windows-only runtime)")
        return 0
    stamp = out.with_suffix(".stamp")
    if out.exists() and stamp.exists() and stamp.read_text(encoding="utf-8").strip() == stamp_of():
        print(f"Discord bridge: {out} up to date")
        return 0
    vs = visual_studio_root()
    if vs is None:
        print("build_discord_bridge: Visual Studio C++ x64 tools were not found", file=sys.stderr)
        return 1
    toolsets = sorted((vs / "VC" / "Tools" / "MSVC").glob("*"), reverse=True)
    sdk = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "Windows Kits" / "10"
    sdk_versions = sorted((sdk / "Include").glob("*"), reverse=True) if (sdk / "Include").exists() else []
    if not toolsets or not sdk_versions:
        print("build_discord_bridge: MSVC or the Windows SDK is incomplete", file=sys.stderr)
        return 1
    toolset, sdk_version = toolsets[0], sdk_versions[0].name
    compiler = toolset / "bin" / "Hostx64" / "x64" / "cl.exe"
    linker = toolset / "bin" / "Hostx64" / "x64" / "link.exe"
    include_dirs = [toolset / "include"] + [sdk / "Include" / sdk_version / name for name in ("ucrt", "shared", "um", "winrt")]
    library_dirs = [toolset / "lib" / "x64"] + [sdk / "Lib" / sdk_version / name / "x64" for name in ("ucrt", "um")]
    if not compiler.exists() or not linker.exists() or not all(path.exists() for path in include_dirs + library_dirs):
        print("build_discord_bridge: required x64 compiler, headers, or libraries are missing", file=sys.stderr)
        return 1
    out.parent.mkdir(parents=True, exist_ok=True)
    obj = out.with_suffix(".obj")
    for old in (out, obj, stamp):
        if old.exists():
            old.unlink()
    result = subprocess.run(
        [str(compiler), "/nologo", "/std:c++17", "/O2", "/EHsc", "/MT", "/W4", "/DUNICODE", "/D_UNICODE",
         *[f"/I{path}" for path in include_dirs], "/c", str(SOURCE), f"/Fo{obj}"],
        cwd=ROOT,
    )
    if result.returncode:
        return result.returncode
    result = subprocess.run(
        [str(linker), "/nologo", "/SUBSYSTEM:WINDOWS", "/MACHINE:X64", f"/OUT:{out}", str(obj),
         *[f"/LIBPATH:{path}" for path in library_dirs], "shell32.lib", "kernel32.lib", "advapi32.lib"],
        cwd=ROOT,
    )
    if result.returncode:
        return result.returncode
    obj.unlink(missing_ok=True)
    stamp.write_text(stamp_of(), encoding="utf-8")
    print(f"Discord bridge: {out} ({out.stat().st_size} bytes)")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "build" / "as3-modded" / "BifrostDiscord.exe")
    args = parser.parse_args(argv)
    return build(args.out.resolve())


if __name__ == "__main__":
    raise SystemExit(main())
