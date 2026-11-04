"""build the port's own native helpers for the HashLink build (the install's native extensions in-process).

    python tools/port_native_build.py [--out build/port-hl/run]

compiles with the local MSVC (``vcvars64.bat`` of Visual Studio, found under Program Files):

- ``Adobe AIR.dll`` from ``port/native/fre/fre_shim.c``: the FlashRuntimeExtensions functions the install's
  extensions import, over the port's own values. It must sit next to ``hl.exe`` so an extension's import of
  "Adobe AIR.dll" resolves to it. Our code only.
- ``bhsound.hdll`` from ``port/native/fre/bhsound.c`` (linked with the pinned Lime's ``libhl.lib``): loads one
  extension DLL of the user's install by full path and calls its functions (``port.runtime.services.NativeExtension``);
  with ``port/native/fre/bhmath.c``, the Math functions as AIR rounds them (msvcr120.dll, ``port.runtime.As3``), and
  ``port/native/fre/bhprobe.c``, the main thread's CPU time and page faults for the long-frame line
  (``port.engine.ThreadProbe``);
  ``port/native/fre/bhgpu.c``, DXGI's Trim of the Direct3D 11 driver's own memory (``port.engine.GpuTrim``);
  ``port/native/fre/bhjpeg.c``, JPEG encoding (stb_image_write, public domain) for ``BitmapData.encode``;
  ``port/native/fre/bhshell.c``, ShellExecute for ``File.openWithDefaultApplication`` (the opened window can come to
  the front over the game).

nothing of the game's is compiled in or copied; the extension DLL stays in the user's install.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "port" / "native" / "fre"
LIME_HL = ROOT / ".tools" / "haxelib" / "lime" / "8,3,2" / "templates" / "bin" / "hl"
DEFAULT_OUT = ROOT / "build" / "port-hl" / "run"


def find_vcvars() -> Path | None:
    for base in (Path("C:/Program Files/Microsoft Visual Studio"), Path("C:/Program Files (x86)/Microsoft Visual Studio")):
        if base.exists():
            found = sorted(base.glob("*/*/VC/Auxiliary/Build/vcvars64.bat"), reverse=True)
            if found:
                return found[0]
    return None


def build(out: Path) -> int:
    vcvars = find_vcvars()
    if vcvars is None:
        print("no Visual Studio vcvars64.bat found", file=sys.stderr)
        return 2
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        steps = [
            f'cl /nologo /O2 /LD /W3 "{SRC / "fre_shim.c"}" /Fo"{tmp}\\\\" /Fe"{out / "Adobe AIR.dll"}" '
            f'/link /IMPLIB:"{tmp}\\fre_shim.lib"',
            f'cl /nologo /O2 /LD /W3 /I"{LIME_HL / "include"}" "{SRC / "bhsound.c"}" "{SRC / "bhmath.c"}" "{SRC / "bhgpu.c"}" "{SRC / "bhprobe.c"}" "{SRC / "bhjpeg.c"}" "{SRC / "bhshell.c"}" /Fo"{tmp}\\\\" '
            f'/Fe"{out / "bhsound.hdll"}" /link "{LIME_HL / "Windows64" / "libhl.lib"}" dxguid.lib dbghelp.lib dxgi.lib shell32.lib user32.lib /IMPLIB:"{tmp}\\bhsound.lib"',
        ]
        script = Path(tmp) / "build.bat"
        script.write_text("@echo off\r\n" + f'call "{vcvars}" >nul\r\n'
                          + "".join(f"{step}\r\nif errorlevel 1 exit /b 1\r\n" for step in steps), encoding="utf-8")
        result = subprocess.run(["cmd", "/d", "/c", str(script)], capture_output=True, text=True)
        if result.returncode != 0:
            print(result.stdout + result.stderr, file=sys.stderr)
            return result.returncode
    print(f"built {out / 'Adobe AIR.dll'} and {out / 'bhsound.hdll'}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args(argv)
    return build(args.out.resolve())


if __name__ == "__main__":
    sys.exit(main())
