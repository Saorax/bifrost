"""the test server and its stand-ins from the command line.

    python tools/services.py status
    python tools/services.py start|stop|restart <service>      # server, queuebot, fillers-2v2, fillers-tournament
    python tools/services.py restart-all                       # the server, then every stand-in that was running
    python tools/services.py say <text>                        # a notice to every game (the console's say)
    python tools/services.py console <line>                    # any console command, e.g. "mods approve <key>";
                                                               # prints the server's answer
    python tools/services.py log <service> [n]

each service runs under tools/studio_run.py (output in build/studio/<service>.log); running services are found by
their command lines. --tournament N picks the tournament the tournament fillers play (default 4).
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
LOGS = ROOT / "build" / "studio"
REPORT = str(Path.home() / "Documents" / "Bifrost" / "bh-private.txt")


def services(tournament: int) -> dict[str, dict]:
    server = str((ROOT.parent / "bifrost-server"))
    return {
        "server": {"cwd": server, "args": ["-m", "bh_server"],
                   "matches": lambda c: "-m bh_server" in c and "bh_server." not in c and "-u -m bh_server" not in c},
        "queuebot": {"cwd": server, "args": [str(ROOT / "data" / "tools" / "testplayer.py"), "queue", "--playlist", "5", "--p2p", "--lag",
                                              "30", "--stay", "--rematch-after", "15", "--report-from", REPORT, "--token",
                                              os.path.join("..", "build", "queuebot-token.txt"), "--name", "Queue Bot"],
                     "matches": lambda c: "testplayer.py" in c and "Queue Bot" in c},
        "fillers-2v2": {"cwd": str(ROOT), "args": ["tools/fill_queue.py", "--playlist", "6", "--count", "3", "--accounts",
                                                   "--report-from", REPORT],
                        "matches": lambda c: "fill_queue.py" in c},
        "fillers-tournament": {"cwd": str(ROOT), "args": ["tools/fill_tournament.py", "--tournament", str(tournament),
                                                          "--report-from", REPORT],
                               "matches": lambda c: "fill_tournament.py" in c and "--tournament" in c},
    }


def processes() -> list[tuple[int, str]]:
    if os.name == "nt":
        out = subprocess.run(["powershell", "-NoProfile", "-Command",
                              "Get-CimInstance Win32_Process | ForEach-Object { \"$($_.ProcessId)`t$($_.CommandLine)\" }"],
                             capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
        rows = [line.split("\t", 1) for line in out.splitlines() if "\t" in line]
    else:
        out = subprocess.run(["ps", "-eo", "pid=,args="], capture_output=True, text=True).stdout
        rows = [line.strip().split(None, 1) for line in out.splitlines() if line.strip()]
    me = os.getpid()
    return [(int(p), c) for p, c in rows if p.strip().isdigit() and int(p) != me and c]


def find(spec: dict, procs: list[tuple[int, str]]) -> tuple[int, bool] | None:
    hits = [(pid, c) for pid, c in procs if spec["matches"](c) and "services.py" not in c]
    hits.sort(key=lambda h: "studio_run.py" not in h[1])
    return (hits[0][0], "studio_run.py" in hits[0][1]) if hits else None


def alive(pid: int) -> bool:
    if os.name == "nt":
        out = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/NH"], capture_output=True, text=True).stdout
        return str(pid) in out
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def kill(pid: int) -> None:
    if os.name == "nt":
        subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True)
    else:
        try:
            os.kill(pid, 9)
        except OSError:
            pass


def start(name: str, spec: dict) -> None:
    LOGS.mkdir(parents=True, exist_ok=True)
    log = LOGS / f"{name}.log"
    flags = (subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW) if os.name == "nt" else 0
    subprocess.Popen([sys.executable, "tools/studio_run.py", "--log", str(log), "--cwd", spec["cwd"], "--", sys.executable,
                      *spec["args"]], cwd=ROOT, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, creationflags=flags, start_new_session=os.name != "nt")
    print(f"started {name} (log {log.relative_to(ROOT)})")


def stop(name: str, spec: dict, procs: list[tuple[int, str]]) -> None:
    hit = find(spec, procs)
    if hit is None:
        return
    pid, wrapped = hit
    if wrapped:
        (LOGS / f"{name}.log.stop").write_text("", encoding="utf-8")
        for _ in range(40):
            if not alive(pid):
                break
            time.sleep(0.25)
    if alive(pid):
        kill(pid)
    if name == "server":
        time.sleep(0.5)
        if os.name == "nt":
            subprocess.run(["taskkill", "/IM", "bh-relay.exe", "/T", "/F"], capture_output=True)
    print(f"stopped {name}")


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("action", choices=["status", "start", "stop", "restart", "restart-all", "say", "console", "log"])
    p.add_argument("args", nargs="*")
    p.add_argument("--tournament", type=int, default=4)
    a = p.parse_args(argv)
    specs = services(a.tournament)
    if a.action in ("start", "stop", "restart", "log") and (not a.args or a.args[0] not in specs):
        print(f"which service? {', '.join(specs)}", file=sys.stderr)
        return 2
    procs = processes()
    if a.action == "status":
        for name, spec in specs.items():
            hit = find(spec, procs)
            print(f"{name:20} " + (f"running (pid {hit[0]}{', under studio_run' if hit[1] else ''})" if hit else "stopped"))
        return 0
    if a.action == "say":
        (LOGS / "server.log.in").open("a", encoding="utf-8").write("say " + " ".join(a.args) + "\n")
        return 0
    if a.action == "console":
        log = LOGS / "server.log"
        offset = log.stat().st_size if log.exists() else 0
        (LOGS / "server.log.in").open("a", encoding="utf-8").write(" ".join(a.args) + "\n")
        time.sleep(2)
        with log.open("rb") as f:
            f.seek(offset)
            got = [ln for ln in f.read().decode("utf-8", errors="replace").splitlines() if "packet type" not in ln]
        print("\n".join(got[-20:]))
        return 0
    if a.action == "log":
        lines = (LOGS / f"{a.args[0]}.log").read_text(encoding="utf-8", errors="replace").splitlines()
        print("\n".join(lines[-int(a.args[1] if len(a.args) > 1 else 40):]))
        return 0
    if a.action == "restart-all":
        running = [n for n, s in specs.items() if find(s, procs)]
        for name in reversed(list(specs)):
            stop(name, specs[name], procs)
        start("server", specs["server"])
        time.sleep(3)
        for name in running:
            if name != "server":
                start(name, specs[name])
        print("restarted: " + ", ".join(["server"] + [n for n in running if n != "server"]))
        return 0
    name = a.args[0]
    if a.action in ("stop", "restart"):
        stop(name, specs[name], procs)
    if a.action in ("start", "restart"):
        if a.action == "start" and find(specs[name], procs):
            print(f"{name} is already running")
            return 0
        start(name, specs[name])
    return 0


if __name__ == "__main__":
    sys.exit(main())
