"""what the last port run left behind, in one look: the run lock, port games and tools still running, uncommitted
changes, and the newest ``build/port-perf/rN`` folder's files.

    python tools/port_run_state.py [--files 12]

read only: it stops and changes nothing, except ``--note``.

    python tools/port_run_state.py --note "AIR: testing a fix in game; port: sweeps running"

``--note`` writes the time and a line on where the run stands into the lock (``keep_lock`` keeps the line when it
touches it), so the next run reads it here. the AIR project's uncommitted files, its lock and its test tools are
listed too.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "port" / ".run-lock"
AIR = ROOT.parent / "bifrost"
AIR_LOCK = AIR / "build" / ".port-run-lock"
AIR_TOOLS = re.compile(r"(autopilot\.py|air_smoke\.py|two_copy_room\.py|build_as3_game\.py|bot_ab\.py)(.*)")
PERF = ROOT / "build" / "port-perf"
PROCESS_QUERY = ("Get-CimInstance Win32_Process -Filter \"Name='hl.exe' or Name='Brawlhalla.exe' or Name='python.exe'\""
                 " | Select-Object ProcessId,Name,ExecutablePath,CommandLine,"
                 "@{n='Started';e={$_.CreationDate.ToString('s')}} | ConvertTo-Json -Compress")


_last_touch = 0.0


def keep_lock(every: float = 600.0) -> None:
    global _last_touch
    import time
    now = time.monotonic()
    if now - _last_touch < every:
        return
    _last_touch = now
    try:
        if LOCK.exists():
            LOCK.write_text(dt.datetime.now().astimezone().isoformat() + "\n" + lock_note(), encoding="utf-8")
    except OSError:
        pass


def lock_note() -> str:
    try:
        lines = LOCK.read_text(encoding="utf-8").splitlines(keepends=True)
    except OSError:
        return ""
    return "".join(lines[1:])


def write_note(note: str) -> None:
    LOCK.write_text(dt.datetime.now().astimezone().isoformat() + "\n" + note.strip() + "\n", encoding="utf-8")


def age(path: Path, now: dt.datetime) -> str:
    minutes = (now - dt.datetime.fromtimestamp(path.stat().st_mtime)).total_seconds() / 60
    return f"{minutes:.0f} min ago" if minutes < 120 else f"{minutes / 60:.1f} h ago"


def processes() -> list[dict]:
    try:
        out = subprocess.run(["powershell", "-NoProfile", "-Command", PROCESS_QUERY], capture_output=True, text=True,
                             timeout=60).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return []
    if not out:
        return []
    rows = json.loads(out)
    return rows if isinstance(rows, list) else [rows]


def describe(row: dict) -> str | None:
    name, exe, cmd = row.get("Name", ""), row.get("ExecutablePath") or "", row.get("CommandLine") or ""
    started = row.get("Started", "")
    if name.lower() != "python.exe":
        owner = "port build (a leftover if no port tool runs)" if exe.lower().startswith(str(ROOT).lower()) else \
            "NOT the port's: leave it alone"
        return f"  {name} {row.get('ProcessId')} started {started}: {exe} [{owner}]"
    tool = re.search(r"(port_\w+\.py|bifrost_\w+\.py)(.*)", cmd) or AIR_TOOLS.search(cmd)
    if not tool:
        return None
    return f"  python {row.get('ProcessId')} started {started}: {tool.group(1)}{tool.group(2)[:160]}"


def newest_perf(files: int, now: dt.datetime) -> list[str]:
    runs = [p for p in PERF.glob("r*") if p.is_dir() and re.fullmatch(r"r\d+", p.name)] if PERF.exists() else []
    if not runs:
        return ["  (no build/port-perf/rN folder)"]
    newest = max(runs, key=lambda p: int(p.name[1:]))
    entries = sorted(newest.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True)
    lines = [f"  {newest.relative_to(ROOT)} ({len(entries)} files), newest first:"]
    for p in entries[:files]:
        size = p.stat().st_size if p.is_file() else 0
        lines.append(f"    {p.name}  {size / 1e6:.1f} MB  {age(p, now)}" if size > 1e6 else f"    {p.name}  {age(p, now)}")
    return lines


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--files", type=int, default=12, help="how many of the newest perf folder's files to list")
    parser.add_argument("--note", default=None, help="write the time and this line on where the run stands into the lock")
    args = parser.parse_args(argv)
    if args.note is not None:
        write_note(args.note)
        print(f"run lock: {LOCK.read_text(encoding='utf-8').strip()}")
        return 0
    now = dt.datetime.now()
    print("run lock: " + (f"{LOCK.read_text(encoding='utf-8').strip()} (touched {age(LOCK, now)})" if LOCK.exists()
                          else "none"))
    branch = subprocess.run(["git", "branch", "--show-current"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    last = subprocess.run(["git", "log", "-1", "--format=%h %ci %s"], cwd=ROOT, capture_output=True, text=True).stdout
    print(f"branch {branch}, last commit {last.strip()[:140]}")
    status = subprocess.run(["git", "status", "--short"], cwd=ROOT, capture_output=True, text=True).stdout.splitlines()
    print(f"uncommitted: {len(status)}" + "".join(f"\n  {s}" for s in status[:20]))
    if AIR.exists():
        air = [a for a in subprocess.run(["git", "status", "--short"], cwd=AIR, capture_output=True,
                                         text=True).stdout.splitlines() if not a.startswith("??")]
        alast = subprocess.run(["git", "log", "-1", "--format=%h %ci %s"], cwd=AIR, capture_output=True,
                               text=True).stdout.strip()
        print(f"AIR: last commit {alast[:120]}; lock " + (f"touched {age(AIR_LOCK, now)}" if AIR_LOCK.exists() else
                                                          "none") + f"; uncommitted (tracked): {len(air)}" +
              "".join(f"\n  {a}" for a in air[:20]))
    running = [line for line in map(describe, (r for r in processes() if r.get("ProcessId") != os.getpid())) if line]
    print("running:" + ("".join("\n" + line for line in running) if running else " no game, no port tool"))
    print("newest perf folder:")
    print("\n".join(newest_perf(args.files, now)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
