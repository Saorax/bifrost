"""run one long-lived project process (the server, a stand-in) for Bifrost Studio, outliving the app.

    python tools/studio_run.py --log build/studio/server.log -- python -m bh_server

the child's output goes to the log (appended, line by line); lines appended to ``<log>.in`` are typed into its
console (the server's commands, e.g. ``say ...``); creating ``<log>.stop`` stops it the way Ctrl+C / Ctrl+Break in
its own window would (the server then tells the players it is restarting), and kills it if it is still running
after 8 seconds. ``<log>.pid`` holds this wrapper's process id while it runs. The Bifrost app (bifrost-app) tails the log and
finds this wrapper again by that file (``tools/services.py`` by its command line) when reopened.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--log", required=True, type=Path)
    parser.add_argument("--cwd", type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("no command")
    log_path: Path = args.log
    log_path.parent.mkdir(parents=True, exist_ok=True)
    inbox, stop, pid = (log_path.with_name(log_path.name + suffix) for suffix in (".in", ".stop", ".pid"))
    for stale in (inbox, stop):
        stale.unlink(missing_ok=True)
    pid.write_text(str(os.getpid()), encoding="utf-8")

    env = dict(os.environ, PYTHONUNBUFFERED="1", PYTHONIOENCODING="utf-8")
    flags = subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0
    with open(log_path, "a", encoding="utf-8", errors="replace", buffering=1) as log:
        log.write(f"--- {time.strftime('%Y-%m-%d %H:%M:%S')} started: {subprocess.list2cmdline(command)}\n")
        child = subprocess.Popen(command, cwd=args.cwd, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace",
                                 creationflags=flags, start_new_session=os.name != "nt")
        threading.Thread(target=feed_console, args=(child, inbox), daemon=True).start()
        threading.Thread(target=watch_stop, args=(child, stop, log), daemon=True).start()
        assert child.stdout is not None
        for line in child.stdout:
            log.write(line)
        code = child.wait()
        log.write(f"--- {time.strftime('%Y-%m-%d %H:%M:%S')} exited with code {code}\n")
    for leftover in (inbox, stop):
        leftover.unlink(missing_ok=True)
    try:
        if pid.read_text(encoding="utf-8").strip() == str(os.getpid()):
            pid.unlink()
    except OSError:
        pass
    return code


def feed_console(child: subprocess.Popen, inbox: Path) -> None:
    offset = 0
    while child.poll() is None:
        time.sleep(0.3)
        try:
            data = inbox.read_bytes()
        except OSError:
            continue
        if len(data) <= offset:
            continue
        text, offset = data[offset:].decode("utf-8", "replace"), len(data)
        try:
            child.stdin.write(text if text.endswith("\n") else text + "\n")
            child.stdin.flush()
        except (OSError, ValueError):
            return


def watch_stop(child: subprocess.Popen, stop: Path, log) -> None:
    while child.poll() is None:
        time.sleep(0.3)
        if not stop.exists():
            continue
        log.write(f"--- {time.strftime('%H:%M:%S')} stopping\n")
        try:
            if os.name == "nt":
                child.send_signal(signal.CTRL_BREAK_EVENT)
            else:
                os.killpg(child.pid, signal.SIGINT)
        except OSError:
            pass
        try:
            child.wait(8)
        except subprocess.TimeoutExpired:
            log.write("--- still running after 8 s: killed\n")
            kill_tree(child.pid)
        return


def kill_tree(pid: int) -> None:
    if os.name == "nt":
        subprocess.run(["taskkill", "/F", "/T", "/PID", str(pid)], capture_output=True)
    else:
        try:
            os.killpg(pid, signal.SIGKILL)
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
