"""builds Bifrost on the new engine: Bifrost's tree beside the raw game, its export, build and smoke.

    python tools/bifrost_build.py tree [--air C:/Coding/BRAWLHALLA PROJECTS/bifrost/bifrost-air] [--commit a47ba9f1]
    python tools/bifrost_build.py round | export | heaps [flags]

``tree`` writes ``build/bifrost/root``, laid out as the converter's ``--root`` reads it:

- ``src/as3/<ver>/scripts``: the raw game's AS3 (old ``// bh-platform:`` lines stripped, as ``as3_to_haxe.py --raw``
  does) with Bifrost's hooks from the hook map (``tools/bifrost_hookmap.py``); each inserted line ends with
  ``// bifrost:<id>``.
- ``src/platform/as3``: Bifrost's layer (``bh.platform``, ``bh.mods``) from the AIR project at the pinned commit
  (``bifrost/SOURCE.txt``), read with ``git archive`` (never its working tree).

the raw tree (``src/as3``) is never written; the output holds game code, so it stays in ``build/``.
"""
from __future__ import annotations

import argparse
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from tools import bifrost_hookmap

BUILD_DIR = ROOT / "build" / "bifrost"
TREE = BUILD_DIR / "root"
MARKER = "// bifrost:"


class TreeError(Exception):
    pass


def uncaught_summary(boot: str) -> list[str]:
    seen: dict[str, list] = {}
    lines = boot.splitlines()
    for i, line in enumerate(lines):
        m = re.search(r"uncaught in frame \d+: (.*?)(?: \(uncaught errors so far: \d+\))?$", line)
        if not m:
            continue
        entry = seen.setdefault(m.group(1), [0, [l.strip() for l in lines[i + 1:i + 4] if l.startswith("Called from")][:2]])
        entry[0] += 1
    total = max([int(n) for n in re.findall(r"uncaught errors so far: (\d+)", boot)] + [sum(e[0] for e in seen.values())])
    if not total:
        return []
    out = [f"{total} uncaught errors in game frames:"]
    for message, (count, stack) in sorted(seen.items(), key=lambda kv: -kv[1][0])[:5]:
        out.append(f"  {count} x {message}" + "".join(f"\n      {s}" for s in stack))
    return out


def indent_of(line: str) -> str:
    return re.match(r"\s*", line).group(0)


def apply_sites(lines: list[str], sites: list[dict]) -> list[str]:
    spans = [(s["lines"][0], s["lines"][1], s["id"]) for s in sites if s["op"] in ("replace", "wrap")]
    for s in sites:
        at = s.get("line")
        for a, b, sid in spans:
            if s["id"] != sid and ((at is not None and a < at <= b) or
                                   ("lines" in s and not (s["lines"][1] < a or s["lines"][0] > b))):
                raise TreeError(f"{s['id']} falls inside {sid}'s lines {a}-{b}")
    def rank(p: tuple[int, dict]) -> tuple:
        i, s = p
        late = s.get("where") in ("before", "end")
        return (s.get("line") or s["lines"][0], late, i if late else -i)
    out = list(lines)
    for s in sites:
        if s["op"] != "edit":
            continue
        a, b = s["lines"][0] - 1, s["lines"][1] - 1
        body = "\n".join(out[a:b])
        hits = list(re.finditer(s["find"], body))
        if len(hits) != 1:
            raise TreeError(f"{s['id']}: edit {s['find']!r} matched {len(hits)} times")
        at = a + body.count("\n", 0, hits[0].start())
        text = re.sub(s["find"], s["replace"], body)
        if text.count("\n") != body.count("\n"):
            raise TreeError(f"{s['id']}: an edit may not add lines")
        out[a:b] = text.split("\n")
        out[at] = out[at] + f" {MARKER}{s['id']}"
    order = sorted(((i, s) for i, s in enumerate(sites) if s["op"] != "edit"), key=rank, reverse=True)
    for _, s in order:
        mark = f" {MARKER}{s['id']}"
        if s["op"] == "insert":
            i = s["line"] - 1
            if s["where"] == "start":
                ind = indent_of(out[i - 1]) + "   "
            elif s["where"] == "end":
                ind = indent_of(out[i]) + "   "
            elif s["where"] == "after":
                ind = indent_of(out[i - 1])
            else:
                ind = indent_of(out[i])
            out[i:i] = [ind + code + mark for code in s["insert"]]
        elif s["op"] == "replace":
            a, b = s["lines"][0] - 1, s["lines"][1]
            ind = indent_of(out[a])
            out[a:b] = [ind + code + mark for code in s["insert"]]
        elif s["op"] == "wrap":
            a, b = s["lines"][0] - 1, s["lines"][1]
            ind = indent_of(out[a])
            body = ["   " + line if line.strip() else line for line in out[a:b]]
            out[a:b] = [f"{ind}if({s['cond']}){mark}", f"{ind}{{{mark}"] + body + [f"{ind}}}{mark}"]
        else:
            raise TreeError(f"{s['id']}: op {s['op']!r}")
    return out


def add_imports(lines: list[str], imports: list[str]) -> list[str]:
    have = {l.strip() for l in lines}
    missing = [i for i in dict.fromkeys(imports) if f"import {i};" not in have]
    if not missing:
        return lines
    pkg = next(i for i, l in enumerate(lines) if l.strip().startswith("package"))
    brace = next(i for i in range(pkg, len(lines)) if "{" in lines[i])
    return lines[:brace + 1] + [f"   import {i}; {MARKER}import" for i in missing] + lines[brace + 1:]


def write_game(tree_src: Path, out: Path, sites: list[dict]) -> tuple[int, int]:
    by_file: dict[str, list[dict]] = {}
    for s in sites:
        by_file.setdefault(s["file"], []).append(s)
    if out.exists():
        shutil.rmtree(out)
    files = hooked = 0
    for src in sorted(tree_src.rglob("*.as")):
        rel = src.relative_to(tree_src)
        if rel.parts[0] == "bh":
            continue
        lines = bifrost_hookmap.raw_lines(src)
        mine = by_file.get(rel.as_posix())
        if mine:
            lines = add_imports(apply_sites(lines, mine), [i for s in mine for i in s["imports"]])
            hooked += 1
        target = out / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
        files += 1
    missing = set(by_file) - {p.relative_to(tree_src).as_posix() for p in tree_src.rglob("*.as")}
    if missing:
        raise TreeError(f"hook map names files the tree lacks: {sorted(missing)}")
    return files, hooked


def write_layer(air: Path, commit: str, out: Path) -> int:
    if VERSION != "10.11":
        src = bifrost_hookmap.ported_source(air, commit, VERSION) / "src" / "platform" / "as3"
        if out.exists():
            shutil.rmtree(out)
        shutil.copytree(src, out)
        return sum(1 for p in out.rglob("*") if p.is_file())
    data = bifrost_hookmap.air_archive(air, commit, "src/platform/as3")
    if out.exists():
        shutil.rmtree(out)
    count = 0
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        for member in tar.getmembers():
            if not member.isfile():
                continue
            rel = Path(member.name).relative_to("src/platform/as3")
            target = out / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(tar.extractfile(member).read())
            count += 1
    return count


def add_test_mods(layer: Path, mods: list[str]) -> int:
    from tools import pins, port_platform
    count = 0
    for mod in mods:
        target = layer / "bh" / "mods" / mod
        if target.exists():
            continue
        found = [d / "data" / "mods" / mod for d in (pins.LAYER_DIR, ROOT.parent / "bifrost")]
        source = next((s for s in found if s.is_dir()), None)
        if source is None:
            raise TreeError(f"test mod {mod}: not in the pinned tree, nor in {' or '.join(str(s) for s in found)}")
        if VERSION == "10.11":
            shutil.copytree(source, target)
        else:
            carry = bifrost_hookmap.porter(VERSION)
            port_platform.port_tree(source, target, lambda t: port_platform.FFDEC.sub(lambda m: carry.ffdec(m.group(0)), t))
        count += sum(1 for p in target.rglob("*") if p.is_file())
    return count


def apply_layer_sites(out: Path, sites: list[dict]) -> int:
    by_file: dict[str, list[dict]] = {}
    for s in sites:
        by_file.setdefault(s["file"], []).append(s)
    applied = len(sites)
    for rel, mine in by_file.items():
        path = out / rel
        if not path.exists() and rel.startswith("bh/mods/"):
            continue
        if not path.exists() and all(s.get("optional") for s in mine):
            applied -= len(mine)
            continue
        if not path.exists():
            raise TreeError(f"layer site file missing: {rel}")
        lines = path.read_text(encoding="utf-8").replace("\r\n", "\n").split("\n")
        for s in mine:
            hits = [i for i, line in enumerate(lines) if re.search(s["anchor"], line.strip())]
            if len(hits) != 1:
                raise TreeError(f"{s['id']}: anchor {s['anchor']!r} matched {len(hits)} lines of {rel}")
            i = hits[0]
            ind = indent_of(lines[i])
            first = s.get("mark") == "first"
            new = [ind + code + (f" {MARKER}{s['id']}" if not first or k == 0 else "") for k, code in enumerate(s["insert"])]
            at = i + 1 if s.get("where", "after") == "after" else i
            lines[at:at] = new
        lines = add_imports(lines, [i for s in mine for i in s.get("imports", [])])
        path.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    return applied


def command_tree(args: argparse.Namespace) -> int:
    commit = args.commit or bifrost_hookmap.pinned_commit()
    data = json.loads(bifrost_hookmap.air_text(args.air, commit, "src/platform/patches.json"))
    patches = data["patches"] if isinstance(data, dict) else data
    raw = ROOT / "src" / "as3" / args.version / "scripts"
    sites, failed = bifrost_hookmap.build(patches, raw, bifrost_hookmap.load_overrides())
    mod_sites, mod_failed = bifrost_hookmap.build_mods(args.air, commit, raw, bifrost_hookmap.load_overrides(section="mods"))
    sites, failed = sites + mod_sites, failed + mod_failed
    if failed:
        for f in failed:
            print(f"  {f['id']}: {f['why']}")
        raise TreeError(f"{len(failed)} hook sites do not resolve (tools/bifrost_hookmap.py)")
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    (BUILD_DIR / "hooks.json").write_text(json.dumps({"air_commit": commit, "version": args.version, "sites": sites,
                                                "unresolved": []}, indent=1) + "\n", encoding="utf-8")
    files, hooked = write_game(raw, TREE / "src" / "as3" / args.version / "scripts", sites)
    layer = write_layer(args.air, commit, TREE / "src" / "platform" / "as3")
    layer += add_test_mods(TREE / "src" / "platform" / "as3", args.test_mods or [])
    overrides = bifrost_hookmap.load_overrides(bifrost_hookmap.OVERRIDES, section="layer")
    if args.test_mods and bifrost_hookmap.TEST_OVERRIDES.exists():
        overrides.update(bifrost_hookmap.load_overrides(bifrost_hookmap.TEST_OVERRIDES, section="layer"))
    layer_sites = apply_layer_sites(TREE / "src" / "platform" / "as3", list(overrides.values()))
    renamed = translate_layer_names(TREE / "src" / "platform" / "as3", raw, args.version)
    if renamed:
        print("layer names as the raw tree spells them: " + ", ".join(f"{a} -> {b} ({n})" for a, b, n in renamed))
    mods = write_mod_list(TREE / "src" / "platform" / "as3", args.test_mods)
    print(f"Bifrost tree at AIR {commit} -> {TREE}: {files} game files ({hooked} hooked, {len(sites)} sites), "
          f"{layer} layer files ({layer_sites} port lines), mods registered: {', '.join(mods)}")
    return 0


FFDEC_MEMBER_RE = re.compile(r"\b(?:var|method)_\d+\b")


def translate_layer_names(layer: Path, raw: Path, version: str) -> list[tuple[str, str, int]]:
    aliases = json.loads((ROOT / "client" / "symbols" / f"{version}.aliases.json").read_text(encoding="utf-8"))
    by_name: dict[str, set[str]] = {}
    for entry in aliases["aliases"]:
        renamed = entry.get("renamed", "")
        if "." in renamed and FFDEC_MEMBER_RE.fullmatch(renamed.rsplit(".", 1)[1]):
            by_name.setdefault(renamed.rsplit(".", 1)[1], set()).add(entry["alias"])
    in_raw: set[str] = set()
    for path in raw.rglob("*.as"):
        if path.relative_to(raw).parts[0] == "bh":
            continue
        in_raw.update(FFDEC_MEMBER_RE.findall(path.read_text(encoding="utf-8", errors="replace")))
    plan = {name: next(iter(found)) for name, found in by_name.items() if len(found) == 1 and name not in in_raw}
    uses: dict[str, int] = {}
    for path in layer.rglob("*.as"):
        text = path.read_text(encoding="utf-8")

        def swap(m: re.Match) -> str:
            alias = plan.get(m.group(0))
            if alias is None:
                return m.group(0)
            uses[m.group(0)] = uses.get(m.group(0), 0) + 1
            return alias

        new = FFDEC_MEMBER_RE.sub(swap, text)
        if new != text:
            path.write_text(new, encoding="utf-8", newline="")
    return [(name, plan[name], count) for name, count in sorted(uses.items())]


MODS_FILE = ROOT / "bifrost" / "mods.txt"


def write_mod_list(layer: Path, test_mods: list[str] | None = None) -> list[str]:
    mods = [line.strip() for line in MODS_FILE.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.startswith("#")]
    mods += [m for m in (test_mods or []) if m not in mods]
    classes = []
    for mod in mods:
        found = sorted(p.stem for p in (layer / "bh" / "mods" / mod).glob("*Mod.as"))
        if len(found) != 1:
            raise TreeError(f"mod {mod}: expected one *Mod.as, found {found}")
        classes.append(found[0])
    imports = "".join(f"   import bh.mods.{m}.{c};\n" for m, c in zip(mods, classes))
    calls = "".join(f"         {c}.register();\n" for c in classes)
    text = ("package bh.platform\n{\n" + imports +
            "\n   /** Generated by tools/bifrost_build.py from bifrost/mods.txt: the mods Bifrost registers. */\n"
            "   public final class ModList\n   {\n      public function ModList()\n      {\n      }\n\n"
            "      public static function registerAll() : void\n      {\n" + calls + "      }\n   }\n}\n")
    (layer / "bh" / "platform" / "ModList.as").write_text(text, encoding="utf-8", newline="\n")
    return mods


VERSION = "10.11"
RAW_SRC = ROOT / "build" / "port-haxe" / "10.11-native" / "src"
RAW_BASELINE = ROOT / "build" / "bifrost" / "raw-baseline.json"


def tree_hashes(folder: Path) -> dict[str, str]:
    import hashlib
    return {p.relative_to(folder).as_posix(): hashlib.sha1(p.read_bytes()).hexdigest()
            for p in sorted(folder.rglob("*.hx"))}


def last_lines(text: str, count: int) -> str:
    return "\n".join(text.rstrip().splitlines()[-count:])


EXPORT = BUILD_DIR / "export"


def command_export(args: argparse.Namespace) -> int:
    from tools import port_haxe_compile
    if args.version != port_haxe_compile.VERSION:
        port_haxe_compile.use_version(args.version)
    port_haxe_compile.use_bifrost()
    engine = BUILD_DIR / "export-engine"
    for folder in (EXPORT, engine):
        folder.mkdir(parents=True, exist_ok=True)
    return port_haxe_compile.hl_check(convert=not args.no_convert, export=(EXPORT, engine))


def failing_sources(log: str) -> list[Path]:
    found: list[Path] = []
    game = TREE / "src" / "as3" / VERSION / "scripts"
    layer = TREE / "src" / "platform" / "as3"
    for rel in dict.fromkeys(re.findall(r"(?m)^src/([\w/]+)\.hx:\d+", log)):
        for base in (layer, game):
            path = base / f"{rel}.as"
            matches = ([p for p in path.parent.glob("*.as") if p.stem.lower() == path.stem.lower()]
                       if path.parent.exists() else [])
            path = matches[0] if matches else path
            if path.exists():
                found.append(path)
                break
    return found


def command_round(args: argparse.Namespace) -> int:
    import time
    tool = [sys.executable, str(ROOT / "tools" / "port_haxe_compile.py")]
    logs = ROOT / "build" / "bifrost"
    logs.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    version = ["--version", VERSION]
    jobs = {"raw": tool + ["check-hl"] + version, "bifrost": tool + ["--bifrost", "check-hl"] + version}
    env = None
    if args.bifrost_only or args.failing:
        jobs.pop("raw")
    if args.failing:
        sources = failing_sources((logs / "round-bifrost.log").read_text(encoding="utf-8", errors="replace"))
        if not sources:
            print("no failing Bifrost files in build/bifrost/round-bifrost.log")
            return 1
        env = dict(os.environ, PORT_CONVERT_ONLY=os.pathsep.join(str(s) for s in sources))
        print(f"converting {len(sources)} failing files: {', '.join(s.stem for s in sources)}")
    def start(cmd: list[str]) -> subprocess.Popen:
        return subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                encoding="utf-8", errors="replace", env=env)

    procs: dict[str, subprocess.Popen] = {}
    head: dict[str, str] = {}
    if "raw" in jobs:
        procs["raw"] = start(jobs["raw"])
        lines = []
        for line in procs["raw"].stdout:
            lines.append(line)
            if "conversion tables from the cache" in line or "original container element types" in line:
                break
        head["raw"] = "".join(lines)
    if "bifrost" in jobs:
        procs["bifrost"] = start(jobs["bifrost"])
    outs = {name: head.get(name, "") + proc.communicate()[0] for name, proc in procs.items()}
    rc = 0
    for name, out in outs.items():
        (logs / f"round-{name}.log").write_text(out, encoding="utf-8")
        print(f"== {name} (exit {procs[name].returncode}, log build/bifrost/round-{name}.log)")
        print(last_lines(out, 3))
        rc |= procs[name].returncode if name == "raw" else 0
    if "raw" in outs:
        now = tree_hashes(RAW_SRC)
        if args.rebase or not RAW_BASELINE.exists():
            RAW_BASELINE.write_text(json.dumps(now, indent=0), encoding="utf-8")
            print(f"raw baseline saved: {len(now)} files")
        else:
            base = json.loads(RAW_BASELINE.read_text(encoding="utf-8"))
            changed = sorted(k for k in set(base) | set(now) if base.get(k) != now.get(k))
            print(f"raw native tree vs baseline: {len(changed)} of {len(now)} files differ"
                  + (": " + ", ".join(changed[:20]) if changed else " (byte-identical)"))
            rc |= 2 if changed else 0
    print(f"round in {time.monotonic() - started:.0f} s")
    return rc


HEAPS_GAME = BUILD_DIR / "heaps" / "game.hl"
HEAPS_DRIVER = BUILD_DIR / "heaps" / "game.driver.txt"
HEAPS_STORAGE = BUILD_DIR / "storage"
AIR_SMOKE = ["waitmenu", "legal", "stats menu", "training", "wait 600", "stats training", "leave", "waitmenu",
             "couch", "wait 1800", "stats match", "leave", "waitmenu", "stats done", "quit"]


FIRST_RUN = ["wait 300", "input 17", "wait 30", "input 2", "wait 30", "input 17", "wait 30", "input 2", "wait 30",
             "input 17", "wait 30", "input 21", "wait 200", "input 17", "wait 200"]


def past_first_run(commands: list[str]) -> list[str]:
    if commands and commands[0] == "waitmenu":
        return [commands[0], *FIRST_RUN, *commands[1:]]
    return [*FIRST_RUN, *commands]


def smoke_commands(extra: list[str] | None) -> list[str]:
    at = AIR_SMOKE.index("legal") + 1
    return AIR_SMOKE[:at] + list(extra or []) + AIR_SMOKE[at:]


def summarize_smoke(driver_log: str, errors_log: str, run_log: str) -> tuple[list[str], bool]:
    lines = [line for line in driver_log.splitlines()
             if re.match(r"^\S+ \S+ (ok |error |legal:|callstatic |FAIL)", line)]
    counts = [int(n) for n in re.findall(r"uncaught errors so far: (\d+)", run_log)]
    uncaught = max(counts + [run_log.count("uncaught in frame")])
    failures = [line for line in errors_log.splitlines()
                if re.search(r"handler failed|not set:|draw: |couldn't|could not apply", line)]
    in_play = len(re.findall(r"stats (?:training|match): .*gameState 6\b", driver_log))
    ok = (bool(lines) and not any(" error " in line or " FAIL" in line for line in lines)
          and in_play == 2 and uncaught == 0 and not failures)
    out = [line[20:200] for line in lines]
    out.append(f"uncaught errors: {uncaught}; Training and match in play: {in_play} of 2; "
               f"Bifrost failures: {len(failures)}")
    out += ["  " + f[:200] for f in failures[:10]]
    return out, ok


def command_heaps(args: argparse.Namespace) -> int:
    import time
    started = time.monotonic()
    if args.no_build:
        if not HEAPS_GAME.exists():
            print(f"bifrost heaps: --no-build: no {HEAPS_GAME}")
            return 1
        mods_dir = install_example_mods(args.air, args.commit or source_commit(), args.library_mods) \
            if args.content_mods or args.library_mods else None
        try:
            return run_air_smoke(args, started, mods_dir)
        finally:
            if mods_dir is not None:
                shutil.rmtree(mods_dir, ignore_errors=True)
    if not args.no_export:
        stale = tree_stale(args.version, args.commit or source_commit())
        if stale:
            print(f"bifrost heaps: the Bifrost tree is stale ({stale}); making it first")
            if subprocess.run([sys.executable, str(Path(__file__)), "tree", "--version", args.version,
                               *(["--commit", args.commit] if args.commit else []),
                               *(["--test-mods", *args.test_mods] if args.test_mods else [])], cwd=ROOT).returncode != 0:
                print("bifrost heaps: the Bifrost tree failed")
                return 1
        if subprocess.run([sys.executable, str(Path(__file__)), "export", "--version", args.version],
                          cwd=ROOT).returncode != 0:
            print("bifrost heaps: the Bifrost export failed")
            return 1
    built = time.monotonic()
    driver = args.driver or os.environ.get("BH_PORT_HEAPS_DRIVER", "dx")
    HEAPS_DRIVER.unlink(missing_ok=True)
    if subprocess.run([sys.executable, str(ROOT / "tools" / "port_heaps_stubs.py"), "stubs", "--build", str(HEAPS_GAME),
                       "--game", str(EXPORT / "src"), "--define", "bifrost", "--define", "port_smoke"],
                      cwd=ROOT, env={**os.environ, "BH_PORT_HEAPS_DRIVER": driver}).returncode != 0:
        print("bifrost heaps: the Heaps build failed (build/port-heaps/e1/check.txt)")
        return 1
    HEAPS_DRIVER.write_text(driver + "\n", encoding="utf-8")
    print(f"bifrost heaps: export {built - started:.0f} s, Heaps build {time.monotonic() - built:.0f} s -> {HEAPS_GAME}")
    if args.no_smoke:
        return 0
    mods_dir = None
    if args.content_mods or args.library_mods:
        mods_dir = install_example_mods(args.air, args.commit or source_commit(), args.library_mods)
    try:
        return run_air_smoke(args, started, mods_dir)
    finally:
        if mods_dir is not None:
            shutil.rmtree(mods_dir, ignore_errors=True)


def tree_stale(version: str, commit: str) -> str | None:
    try:
        made = json.loads((BUILD_DIR / "hooks.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return "no tree yet"
    had = str(made.get("air_commit", ""))
    if not had or not (had.startswith(commit) or commit.startswith(had)):
        return f"made at AIR {had or '?'}, pinned {commit}"
    if made.get("version") != version:
        return f"made for {made.get('version')}, building {version}"
    return None


def source_commit() -> str:
    from tools import pins
    return pins.pins()["commit"]


def install_example_mods(air: Path, commit: str, library: list[str] | None = None) -> Path:
    from tools import port_heaps
    mods = port_heaps.GAME_TEST / "mods"
    marker = BUILD_DIR / "example-mods-installed.txt"
    tail = lambda p: Path(p).parts[-4:]
    if mods.exists() and marker.exists() and tail(marker.read_text(encoding="utf-8").strip()) == tail(mods):
        shutil.rmtree(mods)
    if mods.exists():
        raise TreeError(f"{mods} exists: refusing to mix the example mods with it")
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.write_text(str(mods), encoding="utf-8")
    data = bifrost_hookmap.air_archive(air, commit, "examples/mods")
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        for member in tar.getmembers():
            if not member.isfile():
                continue
            rel = Path(member.name).relative_to("examples/mods")
            if len(rel.parts) < 2:
                continue
            target = mods / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(tar.extractfile(member).read())
    print(f"bifrost heaps: {len([p for p in mods.iterdir() if p.is_dir()])} example content mods from AIR {commit} -> {mods}")
    try:
        for name in library or []:
            install_library_mod(mods, name)
    except Exception:
        shutil.rmtree(mods, ignore_errors=True)
        raise
    return mods


def install_library_mod(mods: Path, name: str) -> None:
    library = BUILD_DIR / "server" / "data" / "mods"
    entries = [p for p in library.glob("*.json")
               if json.loads(p.read_text(encoding="utf-8")).get("name") == name] if library.exists() else []
    if not entries:
        raise TreeError(f"no mod named {name!r} in {library} (python data/tools/bifrost_server.py snapshot)")
    sys.path.insert(0, str(BUILD_DIR / "server"))
    try:
        from bh_server import modshare
    finally:
        sys.path.pop(0)
    files = modshare.unpack(entries[0].with_suffix(".bhmp").read_bytes())
    mod_id = json.loads(files["mod.json"]).get("id") or entries[0].stem
    for rel, data in files.items():
        target = mods / mod_id / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    print(f"bifrost heaps: library mod {name} ({len(files)} files) -> {mods / mod_id}")


BRIDGE = "BifrostDiscord.exe"
BRIDGE_BUILDS = ("build/as3-modded/BifrostDiscord.exe", "build/game-b/BifrostDiscord.exe",
                 "build/patch/applied/BifrostDiscord.exe")
TEST_PIPE = r"\\?\pipe\bh-bifrost-discord-ipc-"


def bridge_source(air: Path) -> Path | None:
    found = [air / rel for rel in BRIDGE_BUILDS if (air / rel).exists()]
    return max(found, key=lambda f: f.stat().st_mtime) if found else None


def install_bridge(air: Path, game: Path) -> Path | None:
    source = bridge_source(air)
    if source is None:
        return None
    target = game / BRIDGE
    shutil.copy2(source, target)
    return target


def run_air_smoke(args: argparse.Namespace, started: float, mods_dir: Path | None) -> int:
    from tools import port_heaps
    air = getattr(args, "air", None)
    bridge = install_bridge(air, port_heaps.GAME_TEST) if air is not None else None
    saved = {k: os.environ.get(k) for k in ("BH_PORT_NATIVEPROCESS_ARGS", "BH_PORT_BROWSER")}
    if getattr(args, "real_discord", False):
        os.environ.pop("BH_PORT_NATIVEPROCESS_ARGS", None)
        os.environ["BH_PORT_BROWSER"] = ""
    else:
        os.environ.setdefault("BH_PORT_NATIVEPROCESS_ARGS", TEST_PIPE)
    try:
        return launch_air_smoke(args, started, mods_dir)
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        if bridge is not None:
            try:
                bridge.unlink()
            except OSError:
                pass


OFFICIAL = ("brawlhalla", "bmgstudios", "bluemammoth", "ubi.com", "ubisoft", "brawltools", "steampowered",
            "steamcommunity", "epicgames", "deltadna", "playfab")


def endpoint_refused(endpoint: str) -> str | None:
    host, _, port = endpoint.rpartition(":")
    if not host or not port.isdigit() or not 0 < int(port) < 65536:
        return "expected HOST:PORT"
    if any(o in host.lower() for o in OFFICIAL):
        return "an official service: never contacted"
    return None


def endpoint_config(config: Path, host: str, port: int) -> dict:
    try:
        cfg = json.loads(config.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        cfg = {}
    if not isinstance(cfg, dict):
        cfg = {}
    tokens = cfg.get("tokens") if isinstance(cfg.get("tokens"), dict) else {}
    saved = tokens.get(f"{host}:{port}")
    cfg.pop("token", None)
    cfg.pop("account", None)
    cfg.update(host=host, port=port)
    if isinstance(saved, dict) and saved.get("token"):
        cfg["token"] = saved["token"]
        if saved.get("account"):
            cfg["account"] = saved["account"]
    return cfg


def launch_air_smoke(args: argparse.Namespace, started: float, mods_dir: Path | None) -> int:
    import contextlib
    import time
    from tools import port_heaps
    others = port_heaps.running_other_games()
    if others:
        print("bifrost heaps: another game is running, nothing launched (one game at a time): " + "; ".join(others))
        return 1
    if not getattr(args, "keep_save", False) and not getattr(args, "real_discord", False):
        shutil.rmtree(HEAPS_STORAGE, ignore_errors=True)
    for replay in getattr(args, "replays", None) or []:
        folder = HEAPS_STORAGE / "BhPort" / "User" / "BrawlhallaReplays"
        folder.mkdir(parents=True, exist_ok=True)
        shutil.copy2(replay, folder / Path(replay).name)
    if getattr(args, "server", False):
        from data.tools import bifrost_server
        config = HEAPS_STORAGE / "BhPort" / "Documents" / "Bifrost" / "bh-server.json"
        config.parent.mkdir(parents=True, exist_ok=True)
        token = bifrost_server.account(args.account) if args.account else None
        config.write_text(bifrost_server.endpoint_json(token), encoding="utf-8")
        twin = bifrost_server.SERVER / "data" / "tls" / "ca-engine.pem"
        kept = config.parent / "tls" / "127.0.0.1.pem"
        if twin.exists() and bifrost_server.tls_on():
            kept.parent.mkdir(exist_ok=True)
            shutil.copy2(twin, kept)
        else:
            kept.unlink(missing_ok=True)
        if not bifrost_server.listening():
            print("bifrost heaps: --server: the test server is not running (python data/tools/bifrost_server.py start)")
            return 1
    if getattr(args, "endpoint", None):
        why = endpoint_refused(args.endpoint)
        if why:
            print(f"bifrost heaps: --endpoint {args.endpoint}: {why}")
            return 1
        host, port = args.endpoint.rsplit(":", 1)
        config = HEAPS_STORAGE / "BhPort" / "Documents" / "Bifrost" / "bh-server.json"
        config.parent.mkdir(parents=True, exist_ok=True)
        config.write_text(json.dumps(endpoint_config(config, host, int(port))), encoding="utf-8")
    if getattr(args, "autopilot", None):
        mod_list = EXPORT / "src" / "bh" / "platform" / "ModList.hx"
        if not mod_list.exists() or "AutopilotMod" not in mod_list.read_text(encoding="utf-8"):
            print("bifrost heaps: --autopilot needs a test build: python tools/bifrost_build.py tree --test-mods autopilot, "
                  "then bifrost_build.py heaps (the last export registers no autopilot)")
            return 1
        folder = HEAPS_STORAGE / "BhPort" / "Documents" / "Bifrost" / "bh-autopilot"
        folder.mkdir(parents=True, exist_ok=True)
        commands = past_first_run(args.autopilot) if getattr(args, "past_first_run", False) else args.autopilot
        (folder / "commands.txt").write_text("".join(c + "\n" for c in commands), encoding="utf-8")
    if args.trace_errors:
        os.environ["BH_PORT_TRACE_ERRORS"] = "1"
    capture = io.StringIO()
    with contextlib.redirect_stdout(capture):
        port_heaps.main(["game", "--hl", str(HEAPS_GAME), "--no-build", "--seconds", str(getattr(args, "seconds", 240)),
                         "--storage", str(HEAPS_STORAGE), "--smoke",
                         *(args.commands if getattr(args, "commands", None) else smoke_commands(args.extra))])
    run_log = capture.getvalue()
    (BUILD_DIR / "smoke-heaps.log").write_text(run_log, encoding="utf-8")
    driver = port_heaps.BUILD / "smoke" / "log.txt"
    driver_log = driver.read_text(encoding="utf-8", errors="replace") if driver.exists() else ""
    (BUILD_DIR / "smoke-driver.txt").write_text(driver_log, encoding="utf-8")
    errors = HEAPS_STORAGE / "BhPort" / "Documents" / "Bifrost" / "bh-errors.txt"
    errors_log = errors.read_text(encoding="utf-8", errors="replace") if errors.exists() else ""
    boot = port_heaps.BUILD / "boot.txt"
    boot_log = boot.read_text(encoding="utf-8", errors="replace") if boot.exists() else run_log
    lines, ok = summarize_smoke(driver_log, errors_log, boot_log)
    print("\n".join(lines))
    print("\n".join(uncaught_summary(boot_log)))
    if mods_dir is not None:
        report = HEAPS_STORAGE / "BhPort" / "Documents" / "Bifrost" / "bh-mods.txt"
        text = report.read_text(encoding="utf-8", errors="replace") if report.exists() else "(no bh-mods.txt)"
        (BUILD_DIR / "content-mods-report.txt").write_text(text, encoding="utf-8")
        print("content mods report (build/bifrost/content-mods-report.txt):\n" + text[:3000])
    print(f"bifrost heaps: AIR's smoke {'PASSED' if ok else 'FAILED'} in {time.monotonic() - started:.0f} s "
          f"(logs build/bifrost/smoke-heaps.log, smoke-driver.txt; Bifrost's own under build/bifrost/storage)")
    return 0 if ok else 1


def unstaged_problem(version: str) -> str | None:
    if version != "10.11" or os.environ.get("BH_BIFROST_ANY_VERSION") == "1":
        return None
    if not (ROOT / "build" / "bifrost-11.00" / "hooks.json").exists():
        return None
    return ("this builds 10.11's game, and the 11.00 one exists: run it staged, python tools/port_version_build.py "
            "run --version 11.00 -- bifrost_build.py ... (BH_BIFROST_ANY_VERSION=1 to build 10.11 anyway)")


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("command", choices=("tree", "round", "export", "heaps"))
    p.add_argument("--no-export", action="store_true", help="heaps: build the last export")
    p.add_argument("--no-build", action="store_true", help="heaps: run the last build (no export, no build)")
    p.add_argument("--no-smoke", action="store_true", help="heaps: build only")
    p.add_argument("--driver", choices=("dx", "dx12", "sdl"), default=None,
                   help="heaps: the renderer to build (BH_PORT_HEAPS_DRIVER: dx = Direct3D 11, dx12, sdl = OpenGL); "
                        "written to build/bifrost/heaps/game.driver.txt, which bifrost_sweep prints")
    p.add_argument("--trace-errors", action="store_true", help="heaps: caught errors' throw sites in Bifrost's logs")
    p.add_argument("--server", action="store_true",
                   help="heaps: the build signs in to data/tools/bifrost_server.py's throwaway server (127.0.0.1:7930)")
    p.add_argument("--test-mods", nargs="+", default=None, metavar="MOD",
                   help="tree: also register these AIR test mods (e.g. autopilot): a test build, never a release")
    p.add_argument("--autopilot", nargs="+", default=None, metavar="CMD",
                   help="heaps: the autopilot's first commands (Documents/Bifrost/bh-autopilot/commands.txt; needs a "
                        "tree made with --test-mods autopilot)")
    p.add_argument("--replays", nargs="+", default=None, metavar="FILE",
                   help="heaps: copy these replay files into the fresh save's BrawlhallaReplays first")
    p.add_argument("--past-first-run", action="store_true",
                   help="heaps --autopilot: first clear the fresh save's Code of Conduct and patch notes (FIRST_RUN)")
    p.add_argument("--commands", nargs="+", default=None, metavar="CMD",
                   help="heaps: these smoke driver commands instead of AIR's smoke sequence")
    p.add_argument("--seconds", type=int, default=240, help="heaps: the game's time limit")
    p.add_argument("--keep-save", action="store_true",
                   help="heaps: keep the last run's storage folder (the same save after a relaunch: rejoin)")
    p.add_argument("--account", help="heaps --server: sign in as this test account (bifrost_server.py account)")
    p.add_argument("--endpoint", metavar="HOST:PORT",
                   help="heaps: the build's bh-server.json points at this Bifrost server (the owner's own; with "
                        "--real-discord, Options > SERVERS > SIGN IN opens Discord in the browser)")
    p.add_argument("--extra", nargs="+", default=None, metavar="CMD",
                   help="heaps: smoke driver commands after the Legal check (e.g. \"callstatic Class.open\")")
    p.add_argument("--library-mods", nargs="+", default=None, metavar="NAME",
                   help="heaps: these mods from the test server copy's library too (by name, e.g. 'Hatsune Miku')")
    p.add_argument("--content-mods", action="store_true",
                   help="heaps: AIR's example content mods in the test install's mods folder for the smoke")
    p.add_argument("--real-discord", action="store_true",
                   help="heaps: the Discord bridge talks to the Discord running on this PC (the owner's Rich Presence "
                        "check); without it every launch gives the bridge the test pipe (data/tools/bifrost_discordpipe.py)")
    p.add_argument("--no-convert", action="store_true", help="export: reuse the converted Bifrost tree")
    p.add_argument("--rebase", action="store_true", help="round: save the raw game's native tree as the baseline")
    p.add_argument("--bifrost-only", action="store_true", help="round: only the Bifrost tree's check")
    p.add_argument("--failing", action="store_true",
                   help="round: convert only the files the last Bifrost check failed in, then check Bifrost")
    p.add_argument("--air", type=Path, default=bifrost_hookmap.DEFAULT_AIR, help="the AIR project (read only)")
    p.add_argument("--commit", help="the AIR commit (default: bifrost/SOURCE.txt)")
    p.add_argument("--version", default="10.11")
    args = p.parse_args(argv)
    if unstaged_problem(args.version):
        print(f"bifrost_build: {unstaged_problem(args.version)}", file=sys.stderr)
        return 2
    global VERSION, RAW_SRC
    VERSION = bifrost_hookmap.VERSION = args.version
    RAW_SRC = ROOT / "build" / "port-haxe" / f"{args.version}-native" / "src"
    if args.command == "round":
        return command_round(args)
    if args.command == "export":
        return command_export(args)
    if args.command == "heaps":
        return command_heaps(args)
    try:
        return command_tree(args)
    except (TreeError, bifrost_hookmap.HookMapError) as e:
        print(f"bifrost_build: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
