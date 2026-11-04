"""installs Bifrost on the new engine into a Brawlhalla install folder, started by Steam's Play.

    python tools/port_steam_install.py stub                      # build the launcher (MSVC) -> build/steam-launcher
    python tools/port_steam_install.py sim --version 11.00       # a test folder: build/game-test/steam-sim-<ver>
    python tools/port_steam_install.py install --game DIR [--from C:/Coding/BRAWLHALLA PROJECTS/bifrost/bifrost-main] [--engine-dir DIR]
    python tools/port_steam_install.py move --game DIR --engine-dir DIR   # move the engine folder (and its saves)
    python tools/port_steam_install.py check --game DIR [--seconds 90]
    python tools/port_steam_install.py uninstall --game DIR [--purge]
    python tools/port_steam_install.py status --game DIR         # the marker, and the launcher's start record

``install`` puts the export's engine (``bin``, ``bin-vulkan``; ``tools/bifrost_export.py``) in ``<game>/bifrost-engine``, or in
``--engine-dir``. with the engine outside the game folder only the launcher stays there: the marker and the original
launcher's backup live in the engine folder, the launcher carries the engine folder's path at its end (``set_tail``),
and ``%LOCALAPPDATA%/Bifrost/engines.txt`` lists engine folders so an install is found after Steam replaces the launcher
and the launcher (``port/tools/steam-launcher/launcher.c``) in place of ``Brawlhalla.exe``. the game's own launcher is
kept as ``Brawlhalla.exe.bifrost-original`` and every file added is listed in ``bifrost-engine.json`` (the marker).
the game reads its files in place (content mods in ``<game>/mods``); saves go to the engine folder's ``storage``.
``uninstall`` restores the original launcher (its hash checked) and removes what the marker lists; the saves stay
unless ``--purge``. a Steam update that puts the original launcher back is noticed by the next ``install``.

never while ``Brawlhalla.exe`` or ``hl.exe`` runs from the folder. the owner's folders (the Steam install, the AIR
build's) are refused unless ``--owner-folder`` is given.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from tools import bifrost_export

LAUNCHER_SRC = ROOT / "port" / "tools" / "steam-launcher" / "launcher.c"
STUB = ROOT / "build" / "steam-launcher" / "Brawlhalla.exe"
BRIDGE_SRC = "src/platform/native/discord_bridge.cpp"
BRIDGE_EXE = "BifrostDiscord.exe"
HL_BUILD = ROOT / "build" / "port-hashlink-1.15"
HL_SRC = HL_BUILD / "src" / "src"
HL_LIB = HL_BUILD / "libhl.lib"
HL_VM = ("code.c", "jit.c", "module.c", "debugger.c", "profile.c")
VM_SRC = ROOT / "port" / "tools" / "steam-launcher" / "vm.c"
VM_DLL = STUB.parent / "bifrost-vm.dll"
UNUSED = ("mysql.hdll", "sqlite.hdll", "game-gl.hl", "sdl.hdll", "SDL2.dll")
HOSTED = ("hl.exe", "launcher.hl")
DXVK = ("d3d11.dll", "dxgi.dll")
VULKAN_EXE = "bifrost-vulkan.exe"
LOGS = "logs"
EXE = "Brawlhalla.exe"
BACKUP = "Brawlhalla.exe.bifrost-original"
ENGINE = "bifrost-engine"
MARKER = "bifrost-engine.json"
ENGINE_DIRS = ("bin", "bin-vulkan")
OWNER_FOLDERS = (Path("E:/SteamLibrary/steamapps/common/Brawlhalla"), Path("E:/Bifrost/Brawlhalla-10.11"))
VCVARS = Path("C:/Program Files/Microsoft Visual Studio/18/Community/VC/Auxiliary/Build/vcvars64.bat")


class InstallError(Exception):
    pass


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def guard(game: Path, owner_folder: bool) -> None:
    if not (game / EXE).exists():
        raise InstallError(f"{game}: no {EXE} (not a Brawlhalla install folder)")
    resolved = game.resolve()
    player = os.environ.get("BIFROST_PLAYER_INSTALL") == "1"
    if not player and any(resolved == p.resolve() for p in OWNER_FOLDERS if p.exists()):
        if not owner_folder:
            raise InstallError(f"{game} is the owner's folder: needs --owner-folder")
    running = bifrost_export.running_from(game)
    if running:
        raise InstallError(f"running from {game}: {', '.join(running)}")


def bridge_source() -> bytes:
    from tools import pins
    fields = pins.pins()
    out = subprocess.run(["git", "-C", fields["repo"], "show", f"{fields['commit']}:{BRIDGE_SRC}"],
                         capture_output=True)
    if out.returncode != 0:
        raise InstallError(f"no {BRIDGE_SRC} at the pin: {out.stderr.decode(errors='replace')}")
    return out.stdout


def prebuilt_stub() -> bool:
    global STUB, VM_DLL
    folder = os.environ.get("BIFROST_LAUNCHER_DIR")
    if not folder:
        return False
    stub, vm = Path(folder) / EXE, Path(folder) / "bifrost-vm.dll"
    if not stub.exists() or not vm.exists():
        raise InstallError(f"{folder}: no prebuilt {EXE} and bifrost-vm.dll")
    STUB, VM_DLL = stub, vm
    return True


def build_stub() -> Path:
    if prebuilt_stub():
        return STUB
    STUB.parent.mkdir(parents=True, exist_ok=True)
    bridge = STUB.parent / "discord_bridge.cpp"
    source = bridge_source()
    if not (HL_SRC / "main.c").exists() or not HL_LIB.exists():
        raise InstallError(f"no HashLink 1.15 build in {HL_LIB.parent} (python tools/port_hashlink_build.py)")
    vm = [VM_SRC] + [HL_SRC / name for name in HL_VM]
    stamp = STUB.parent / "stub.stamp"
    key = hashlib.sha256(LAUNCHER_SRC.read_bytes() + source + b"".join(p.read_bytes() for p in vm)
                         + HL_LIB.read_bytes()).hexdigest()
    if STUB.exists() and VM_DLL.exists() and stamp.exists() and stamp.read_text(encoding="ascii") == key:
        return STUB
    if not VCVARS.exists():
        raise InstallError(f"no MSVC ({VCVARS})")
    bridge.write_bytes(source)
    for old in (STUB, VM_DLL):
        old.unlink(missing_ok=True)
    vm_files = " ".join(f'"{p}"' for p in vm)
    vm_dir, exe_dir = STUB.parent / "obj-vm", STUB.parent / "obj-exe"
    vm_dir.mkdir(exist_ok=True)
    exe_dir.mkdir(exist_ok=True)
    bat = STUB.parent / "build.bat"
    bat.write_text(f'@call "{VCVARS}" >nul\r\n'
                   f'@cl /nologo /O2 /W1 /MD /LD /DUNICODE /D_UNICODE /DWIN32 /DNDEBUG /I"{HL_SRC}" {vm_files} '
                   f'/Fo"{vm_dir}\\\\" /Fe"{VM_DLL}" /link "{HL_LIB}" user32.lib ws2_32.lib || exit /b 1\r\n'
                   f'@cl /nologo /O1 /W3 /MT /EHsc /std:c++17 /DUNICODE /D_UNICODE /DBIFROST_BRIDGE_EMBEDDED '
                   f'"{LAUNCHER_SRC}" "{bridge}" /Fo"{exe_dir}\\\\" /Fe"{STUB}" /link /SUBSYSTEM:WINDOWS user32.lib '
                   f'kernel32.lib shell32.lib advapi32.lib\r\n', encoding="ascii")
    out = subprocess.run(["cmd", "/c", str(bat)], capture_output=True, text=True, cwd=STUB.parent)
    if out.returncode != 0 or not STUB.exists() or not VM_DLL.exists():
        raise InstallError(f"cl failed:\n{out.stdout}\n{out.stderr}")
    stamp.write_text(key, encoding="ascii")
    return STUB


ICON_HUE = 0.0


def recolor_icon(image: bytes, hue: float = ICON_HUE) -> bytes:
    import colorsys
    if len(image) < 40 or image[:4] == b"\x89PNG" or int.from_bytes(image[14:16], "little") != 32:
        return image
    header = int.from_bytes(image[0:4], "little")
    width = int.from_bytes(image[4:8], "little", signed=True)
    height = int.from_bytes(image[8:12], "little", signed=True) // 2
    out = bytearray(image)
    for i in range(header, header + 4 * abs(width) * abs(height), 4):
        b, g, r = out[i], out[i + 1], out[i + 2]
        if r == g == b:
            continue
        _, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        out[i + 2], out[i + 1], out[i] = (round(c * 255) for c in colorsys.hsv_to_rgb(hue, s, v))
    return bytes(out)


def copy_icon(original: Path, target: Path) -> bool:
    import ctypes
    from ctypes import wintypes
    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    k32.LoadLibraryExW.restype = wintypes.HMODULE
    k32.FindResourceW.restype = wintypes.HANDLE
    k32.FindResourceW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p]
    k32.LoadResource.restype = wintypes.HANDLE
    k32.LoadResource.argtypes = [wintypes.HMODULE, wintypes.HANDLE]
    k32.LockResource.restype = ctypes.c_void_p
    k32.LockResource.argtypes = [wintypes.HANDLE]
    k32.SizeofResource.argtypes = [wintypes.HMODULE, wintypes.HANDLE]
    k32.BeginUpdateResourceW.restype = wintypes.HANDLE
    k32.UpdateResourceW.argtypes = [wintypes.HANDLE, ctypes.c_void_p, ctypes.c_void_p, wintypes.WORD, ctypes.c_void_p,
                                    wintypes.DWORD]
    k32.EndUpdateResourceW.argtypes = [wintypes.HANDLE, wintypes.BOOL]
    k32.FreeLibrary.argtypes = [wintypes.HMODULE]
    k32.LoadLibraryExW.argtypes = [wintypes.LPCWSTR, wintypes.HANDLE, wintypes.DWORD]
    k32.BeginUpdateResourceW.argtypes = [wintypes.LPCWSTR, wintypes.BOOL]
    enum_proc = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)
    k32.EnumResourceNamesW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, enum_proc, ctypes.c_void_p]
    RT_ICON, RT_GROUP_ICON = 3, 14
    module = k32.LoadLibraryExW(str(original), None, 0x2 | 0x20)
    if not module:
        return False
    try:
        names: list = []
        callback = enum_proc(lambda h, t, name, p: names.append(name) or False)
        k32.EnumResourceNamesW(module, ctypes.c_void_p(RT_GROUP_ICON), callback, None)
        if not names:
            return False

        def data(name, kind) -> bytes | None:
            found = k32.FindResourceW(module, ctypes.c_void_p(name), ctypes.c_void_p(kind))
            if not found:
                return None
            return ctypes.string_at(k32.LockResource(k32.LoadResource(module, found)), k32.SizeofResource(module, found))

        group = data(names[0], RT_GROUP_ICON)
        if group is None or len(group) < 6:
            return False
        count = int.from_bytes(group[4:6], "little")
        images = []
        for i in range(count):
            entry = group[6 + 14 * i: 6 + 14 * (i + 1)]
            icon_id = int.from_bytes(entry[12:14], "little")
            image = data(icon_id, RT_ICON)
            if image is not None:
                images.append((icon_id, recolor_icon(image)))
    finally:
        k32.FreeLibrary(module)
    update = k32.BeginUpdateResourceW(str(target), False)
    if not update:
        return False
    for icon_id, image in images:
        buf = ctypes.create_string_buffer(image, len(image))
        k32.UpdateResourceW(update, ctypes.c_void_p(RT_ICON), ctypes.c_void_p(icon_id), 0, buf, len(image))
    buf = ctypes.create_string_buffer(group, len(group))
    k32.UpdateResourceW(update, ctypes.c_void_p(RT_GROUP_ICON), ctypes.c_void_p(1), 0, buf, len(group))
    return bool(k32.EndUpdateResourceW(update, False))


TAIL = b"BFEN"


def launcher_tail(exe: Path) -> Path | None:
    try:
        data = exe.read_bytes()
    except OSError:
        return None
    if len(data) < 9 or data[-4:] != TAIL:
        return None
    size = int.from_bytes(data[-8:-4], "little")
    if size <= 0 or size > len(data) - 8:
        return None
    try:
        return Path(data[-8 - size:-8].decode("utf-8"))
    except UnicodeDecodeError:
        return None


def set_tail(exe: Path, engine: Path | None) -> None:
    data = exe.read_bytes()
    if launcher_tail(exe) is not None:
        data = data[:-8 - int.from_bytes(data[-8:-4], "little")]
    if engine is not None:
        text = engine.resolve().as_posix().encode("utf-8")
        data += text + len(text).to_bytes(4, "little") + TAIL
    exe.write_bytes(data)


def index_file() -> Path | None:
    local = os.environ.get("LOCALAPPDATA")
    return Path(local) / "Bifrost" / "engines.txt" if local else None


def remember(engine: Path) -> None:
    index = index_file()
    if index is None:
        return
    known = [line for line in (index.read_text(encoding="utf-8").splitlines() if index.exists() else []) if line.strip()]
    entry = engine.resolve().as_posix()
    if entry not in known:
        index.parent.mkdir(parents=True, exist_ok=True)
        index.write_text("\n".join(known + [entry]) + "\n", encoding="utf-8")


def same_folder(a: Path, b: Path) -> bool:
    return os.path.normcase(str(a.resolve())) == os.path.normcase(str(b.resolve()))


def outside(game: Path, engine: Path) -> bool:
    return not same_folder(engine, game / ENGINE)


def engine_dir(game: Path) -> Path:
    tail = launcher_tail(game / EXE)
    if tail is not None:
        return tail
    legacy = game / MARKER
    if legacy.exists():
        try:
            value = json.loads(legacy.read_text(encoding="utf-8")).get("engine_dir")
        except (OSError, ValueError):
            value = None
        return Path(value) if value else game / ENGINE
    index = index_file()
    for line in (index.read_text(encoding="utf-8").splitlines() if index and index.exists() else []):
        candidate = Path(line.strip()) / MARKER
        try:
            recorded = json.loads(candidate.read_text(encoding="utf-8")).get("game") if candidate.exists() else None
        except (OSError, ValueError):
            recorded = None
        if recorded and same_folder(Path(recorded), game):
            return candidate.parent
    return game / ENGINE


def marker_path(game: Path, engine: Path | None = None) -> Path:
    engine = engine_dir(game) if engine is None else engine
    return engine / MARKER if outside(game, engine) else game / MARKER


def backup_path(game: Path, engine: Path | None = None) -> Path:
    engine = engine_dir(game) if engine is None else engine
    return engine / BACKUP if outside(game, engine) else game / BACKUP


def installed(game: Path) -> bool:
    return marker_path(game).exists() or (game / MARKER).exists()


def settle(game: Path, engine: Path) -> None:
    for name, want in ((MARKER, marker_path(game, engine)), (BACKUP, backup_path(game, engine))):
        for have in (game / name, engine / name):
            if same_folder(have, want) or not have.exists():
                continue
            if want.exists():
                have.unlink()
            else:
                want.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(have), str(want))


def read_marker(game: Path, engine: Path | None = None) -> dict:
    path = marker_path(game, engine)
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def placed(game: Path, marker: dict, engine: Path) -> None:
    if outside(game, engine):
        marker["engine_dir"] = engine.resolve().as_posix()
        added = [name for name in marker.get("added", []) if name not in (ENGINE, MARKER)]
        remember(engine)
    else:
        marker.pop("engine_dir", None)
        added = [name for name in marker.get("added", []) if name not in (ENGINE, MARKER)] + [ENGINE, MARKER]
    marker["added"] = sorted(added)
    marker["game"] = str(game.resolve())


def relaunch(game: Path, marker: dict, engine: Path) -> None:
    exe = game / EXE
    before = sha256(exe)
    if before not in (marker.get("stub_sha256"), *marker.get("stub_history", [])):
        return
    set_tail(exe, engine if outside(game, engine) else None)
    after = sha256(exe)
    if after != before:
        marker["stub_history"] = [h for h in marker.get("stub_history", []) + [before] if h][-10:]
        marker["stub_sha256"] = after
    vulkan = engine / "bin" / "vulkan"
    if vulkan.is_dir():
        shutil.copy2(exe, vulkan / VULKAN_EXE)


def move(game: Path, target: Path, owner_folder: bool = False) -> str:
    guard(game, owner_folder)
    if not installed(game):
        raise InstallError(f"{game}: not installed (no {MARKER})")
    current = engine_dir(game)
    if bifrost_export.running_from(current):
        raise InstallError("close Brawlhalla first")
    target = target.resolve()
    if same_folder(target, current):
        return f"the engine is already in {target}"
    if target.exists() and any(target.iterdir()):
        raise InstallError(f"{target} isn't empty: pick a new or empty folder")
    if current.resolve() in target.parents or target in current.resolve().parents:
        raise InstallError(f"{target} is inside {current} (or the other way round)")
    settle(game, current)
    if target.exists():
        target.rmdir()
    target.parent.mkdir(parents=True, exist_ok=True)
    if current.exists():
        shutil.move(str(current), str(target))
    else:
        target.mkdir()
    for name in (MARKER, BACKUP):
        if (game / name).exists() and outside(game, target) and not (target / name).exists():
            shutil.move(str(game / name), str(target / name))
        elif (target / name).exists() and not outside(game, target):
            shutil.move(str(target / name), str(game / name))
    marker = read_marker(game, target)
    placed(game, marker, target)
    relaunch(game, marker, target)
    marker_path(game, target).write_text(json.dumps(marker, indent=1) + "\n", encoding="utf-8")
    return f"moved the engine from {current} to {target}"


def storage_dir(folder: Path) -> Path | None:
    found = sorted((folder / "storage").glob("BhPort*")) if (folder / "storage").exists() else []
    return found[0] if found else None


def install(game: Path, source: Path, owner_folder: bool = False, engine_at: Path | None = None) -> str:
    guard(game, owner_folder)
    for name in ENGINE_DIRS[:1]:
        if not (source / name / "hl.exe").exists():
            raise InstallError(f"{source}: no {name}/hl.exe (export it with tools/bifrost_export.py)")
    stub = build_stub()
    stub_hash = sha256(stub)
    if engine_at is not None and installed(game) and not same_folder(engine_at, engine_dir(game)):
        print(move(game, engine_at, owner_folder))
    engine = engine_at.resolve() if engine_at is not None else engine_dir(game)
    engine.mkdir(parents=True, exist_ok=True)
    settle(game, engine)
    marker = read_marker(game, engine)
    backup = backup_path(game, engine)
    current = sha256(game / EXE)
    if current != stub_hash and current != marker.get("stub_sha256") and current not in marker.get("stub_history", []):
        shutil.copy2(game / EXE, backup)
        marker["original_sha256"] = current
    elif not backup.exists():
        raise InstallError(f"{game}: {EXE} is the launcher but {BACKUP} is missing (verify the game files in Steam)")
    for name in ENGINE_DIRS:
        if (engine / name).exists():
            shutil.rmtree(engine / name)
    shutil.copytree(source / "bin", engine / "bin", ignore=shutil.ignore_patterns(*UNUSED, *HOSTED))
    shutil.copy2(VM_DLL, engine / "bin" / VM_DLL.name)
    official_native = engine / "official" / "native"
    if official_native.is_dir():
        for dll in official_native.iterdir():
            shutil.copy2(dll, engine / "bin" / dll.name)
    if (source / "bin-vulkan").exists():
        (engine / "bin" / "vulkan").mkdir()
        for name in DXVK:
            if (source / "bin-vulkan" / name).exists():
                shutil.copy2(source / "bin-vulkan" / name, engine / "bin" / "vulkan" / name)
    logs = engine / LOGS
    logs.mkdir(exist_ok=True)
    for name in ("boot.txt", "boot-previous.txt", "starts.txt"):
        if (engine / name).exists():
            os.replace(engine / name, logs / name)
    saves = storage_dir(source)
    if not (engine / "storage").exists() and saves is not None:
        shutil.copytree(saves, engine / "storage" / saves.name)
    (game / BRIDGE_EXE).unlink(missing_ok=True)
    marker["added"] = sorted(set(marker.get("added", [])) - {BRIDGE_EXE})
    placed(game, marker, engine)
    new = game / (EXE + ".bifrost-new")
    shutil.copy2(stub, new)
    icon = copy_icon(backup, new)
    set_tail(new, engine if outside(game, engine) else None)
    stub_hash = sha256(new)
    if (engine / "bin" / "vulkan").is_dir():
        shutil.copy2(new, engine / "bin" / "vulkan" / VULKAN_EXE)
    os.replace(new, game / EXE)
    history = [h for h in marker.get("stub_history", []) + [marker.get("stub_sha256")] if h][-10:]
    marker.update({"stub_sha256": stub_hash, "stub_history": history, "discord_bridge": True, "icon": icon,
                   "engine_from": str(source), "installed": time.strftime("%Y-%m-%d %H:%M:%S"),
                   "version": bifrost_export_version(source)})
    marker_path(game, engine).write_text(json.dumps(marker, indent=1) + "\n", encoding="utf-8")
    where = f"; the engine, marker and original launcher in {engine}" if outside(game, engine) else ""
    return (f"installed the new engine from {source} into {game} ({', '.join(marker['added']) or EXE}){where}; "
            f"original launcher kept as {BACKUP}")


def bifrost_export_version(source: Path) -> str:
    readme = source / "README.md"
    m = re.search(r"Brawlhalla v([\d.]+)", readme.read_text(encoding="utf-8")) if readme.exists() else None
    return m.group(1) if m else "?"


def restore_launcher(game: Path, owner_folder: bool = False) -> str | None:
    guard(game, owner_folder)
    engine = engine_dir(game)
    if not marker_path(game, engine).exists() and not (game / MARKER).exists():
        return None
    settle(game, engine)
    marker = read_marker(game, engine)
    backup = backup_path(game, engine)
    current = sha256(game / EXE)
    if current == marker.get("stub_sha256"):
        return None
    older = current in marker.get("stub_history", [])
    if not older:
        shutil.copy2(game / EXE, backup)
        marker["original_sha256"] = current
    elif not backup.exists():
        raise InstallError(f"{game}: {EXE} is an older Bifrost launcher but {BACKUP} is missing (verify the game files in Steam)")
    stub = build_stub()
    new = game / (EXE + ".bifrost-new")
    shutil.copy2(stub, new)
    icon = copy_icon(backup, new)
    set_tail(new, engine if outside(game, engine) else None)
    stub_hash = sha256(new)
    vulkan = engine / "bin" / "vulkan"
    if vulkan.is_dir():
        shutil.copy2(new, vulkan / VULKAN_EXE)
    os.replace(new, game / EXE)
    history = [h for h in marker.get("stub_history", []) + [marker.get("stub_sha256")] if h][-10:]
    marker.update({"stub_sha256": stub_hash, "stub_history": history, "icon": icon})
    marker_path(game, engine).write_text(json.dumps(marker, indent=1) + "\n", encoding="utf-8")
    return f"{EXE} wasn't Bifrost's launcher any more (Steam or another program replaced it): put it back"


def uninstall(game: Path, purge: bool = False, owner_folder: bool = False) -> str:
    guard(game, owner_folder)
    if not installed(game):
        raise InstallError(f"{game}: not installed (no {MARKER})")
    engine = engine_dir(game)
    settle(game, engine)
    marker = read_marker(game, engine)
    backup = backup_path(game, engine)
    if sha256(game / EXE) == marker["stub_sha256"]:
        if not backup.exists() or sha256(backup) != marker["original_sha256"]:
            raise InstallError(f"{BACKUP} is missing or changed: verify the game files in Steam instead")
        shutil.copy2(backup, game / EXE)
    backup.unlink(missing_ok=True)
    names = marker.get("added", []) + ([] if ENGINE in marker.get("added", []) else [ENGINE])
    for name in names:
        path = engine if name == ENGINE else game / name
        if name == ENGINE and path.exists():
            for child in path.iterdir():
                if child.name in ("storage", "storage-official") and not purge:
                    continue
                shutil.rmtree(child) if child.is_dir() else child.unlink()
            if purge or not any(path.iterdir()):
                shutil.rmtree(path)
        elif path.is_file() and name != MARKER:
            path.unlink()
    marker_path(game, engine).unlink(missing_ok=True)
    (game / MARKER).unlink(missing_ok=True)
    kept = "" if purge or not (engine / "storage").exists() else f"; saves kept in {engine / 'storage'}"
    return f"uninstalled from {game}: {EXE} restored{kept}"


def check(game: Path, seconds: int) -> tuple[bool, str]:
    if any(game.resolve() == p.resolve() for p in OWNER_FOLDERS if p.exists()):
        raise InstallError(f"{game} is the owner's folder: check a test install (sim) instead")
    if bifrost_export.running_from(game):
        raise InstallError(f"something runs from {game}")
    from tools import bifrost_build
    env = dict(os.environ, BH_PORT_BROWSER="off", BH_PORT_NATIVEPROCESS_ARGS=bifrost_build.TEST_PIPE,
               SteamAppId=STEAM_APP_ID)
    for key in ("BH_PORT_APP_DIR", "BH_PORT_STORAGE_DIR", "BH_PORT_LOG"):
        env.pop(key, None)
    proc = subprocess.Popen([str(game / EXE)], cwd=game, env=env)
    try:
        proc.wait(timeout=seconds)
    except subprocess.TimeoutExpired:
        pass
    for exe in bifrost_export.running_from(game):
        subprocess.run(["powershell", "-NoProfile", "-Command",
                        f"Get-CimInstance Win32_Process | Where-Object {{ $_.ExecutablePath -eq '{exe}' }} | "
                        "ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"], capture_output=True)
    proc.wait(timeout=30)
    engine = engine_dir(game)
    log = engine / LOGS / "boot.txt"
    saves = storage_dir(engine)
    errors = saves / "Documents" / "Bifrost" / "bh-errors.txt" if saves else Path("-")
    read = lambda p: p.read_text(encoding="utf-8", errors="replace") if p.exists() else ""
    ok, report = bifrost_export.boot_verdict(read(log), read(errors))
    return ok, report + "\n" + starts(game, last=1)


STEAM_APP_ID = "291550"


def starts(game: Path, last: int = 5) -> str:
    path = engine_dir(game) / LOGS / "starts.txt"
    if not path.exists():
        boot = engine_dir(game) / LOGS / "boot.txt"
        seen = f"; boot.txt from {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(boot.stat().st_mtime))}" \
            if boot.exists() else "; no boot.txt either (not started through the launcher since the install)"
        return "starts: none recorded (no start since a launcher that records them was installed)" + seen
    lines = [ln for ln in path.read_text(encoding="utf-8", errors="replace").splitlines() if ln.strip()]
    play = [ln for ln in lines if ln.endswith(f"steam={STEAM_APP_ID}")]
    verdict = f"last start from Steam's Play: {play[-1].split(' steam=')[0]}" if play else "no start from Steam's Play"
    return "\n".join([f"starts: {len(lines)} recorded, {verdict}"] + [f"  {ln}" for ln in lines[-last:]])


def sim(version: str) -> Path:
    source = ROOT / "build" / "game-test" / ("port" if version == "10.11" else f"port-{version}")
    target = ROOT / "build" / "game-test" / f"steam-sim-{version}"
    if target.exists() and installed(target):
        raise InstallError(f"{target} has an install: uninstall it first")
    made, kept = bifrost_export.link_install(source, target)
    print(f"steam-sim: {target} ({made} linked, {kept} kept)")
    return target


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("command", choices=["stub", "sim", "install", "move", "uninstall", "check", "status"])
    p.add_argument("--game", type=Path, help="the Brawlhalla install folder")
    p.add_argument("--from", dest="source", type=Path, default=Path("C:/Coding/BRAWLHALLA PROJECTS/bifrost/bifrost-main"),
                   help="the exported Bifrost-on-Heaps folder (tools/bifrost_export.py)")
    p.add_argument("--version", default="11.00", help="sim: the test install's version")
    p.add_argument("--seconds", type=int, default=90)
    p.add_argument("--purge", action="store_true", help="uninstall: remove the saves too")
    p.add_argument("--engine-dir", type=Path, help="install, move: where the engine folder goes (default <game>/bifrost-engine)")
    p.add_argument("--owner-folder", action="store_true", help="allow the owner's folders")
    a = p.parse_args(argv)
    try:
        if a.command == "stub":
            print(f"launcher: {build_stub()} ({STUB.stat().st_size} bytes)")
            return 0
        if a.command == "sim":
            sim(a.version)
            return 0
        if a.game is None:
            raise InstallError("--game is required")
        if a.command == "install":
            print(install(a.game, a.source, a.owner_folder, a.engine_dir))
        elif a.command == "move":
            if a.engine_dir is None:
                raise InstallError("--engine-dir is required")
            print(move(a.game, a.engine_dir, a.owner_folder))
        elif a.command == "uninstall":
            print(uninstall(a.game, a.purge, a.owner_folder))
        elif a.command == "check":
            ok, report = check(a.game, a.seconds)
            print(("BOOT OK: " if ok else "BOOT FAILED: ") + report)
            return 0 if ok else 1
        else:
            marker = marker_path(a.game)
            print(marker.read_text(encoding="utf-8") if marker.exists() else f"{a.game}: not installed")
            if marker.exists():
                print(starts(a.game))
    except InstallError as e:
        print(f"port_steam_install: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
