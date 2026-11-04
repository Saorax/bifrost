"""compile an exported AS3 tree with the pinned compiler and report every error.

    python tools/compile_as3.py --src <exported tree>/scripts [--strict]

the whole tree is compiled as one library (``compc -include-sources``) against
``airglobal.swc``, so every file is checked, not only what a document class
reaches. the game was compiled by Haxe, not from AS3, so non-strict mode is
the default; ``--strict`` reports the extra static type errors.

writes ``build/as3/<ver>/as3-compile.json`` (and ``--markdown`` for a readable
census): error totals, errors by kind, by normalized message and by file.
exits 0 only when the compile has zero errors.
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
if __package__:
    from . import setup_as3_compiler
else:
    import setup_as3_compiler

DIAGNOSTIC = re.compile(
    r"^(?P<path>.+?)\((?P<line>\d+)\): col: (?P<col>\d+) "
    r"(?P<kind>Error|Syntax error|Warning): (?P<message>.*)$"
)
NO_POSITION = re.compile(r"^(?P<kind>Error|Syntax error|Warning|command line Error): (?P<message>.*)$")


def normalize(message: str) -> str:
    message = re.sub(r"'[^']*'", "'X'", message)
    message = re.sub(r"(type|property|method|namespace|definition|variable|function)\s+[\w$.:<>*]+", r"\1 N", message)
    message = re.sub(r":\s*[\w$.]+\.$", ": N.", message)
    return re.sub(r"\baddr\w+", "addrN", message)


def parse_log(text: str, src: Path | None = None) -> list[dict]:
    diagnostics = []
    for raw in text.splitlines():
        line = raw.rstrip()
        match = DIAGNOSTIC.match(line)
        if match:
            path = Path(match["path"])
            if src is not None:
                try:
                    path = path.resolve().relative_to(src.resolve())
                except ValueError:
                    pass
            diagnostics.append({
                "file": path.as_posix(), "line": int(match["line"]), "col": int(match["col"]),
                "kind": match["kind"], "message": match["message"].strip(),
            })
            continue
        match = NO_POSITION.match(line)
        if match:
            diagnostics.append({"file": None, "line": None, "col": None,
                                "kind": match["kind"], "message": match["message"].strip()})
    return diagnostics


def summarize(diagnostics: list[dict], files: int) -> dict:
    errors = [d for d in diagnostics if d["kind"] != "Warning"]
    return {
        "source_files": files,
        "errors": len(errors),
        "warnings": len(diagnostics) - len(errors),
        "files_with_errors": len({d["file"] for d in errors}),
        "by_kind": dict(Counter(d["kind"] for d in errors).most_common()),
        "by_message": dict(Counter(normalize(d["message"]) for d in errors).most_common()),
        "by_file": dict(Counter(str(d["file"]) for d in errors).most_common()),
    }


def compile_tree(src: Path, out: Path, strict: bool, libs: list[Path], jar: Path) -> tuple[int, str]:
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        config = Path(tmp, "config.xml")
        config.write_text("<royale-config/>\n", encoding="utf-8")
        cmd = ["java", "-Xmx6g", "-jar", str(jar), f"-load-config={config}",
               f"-compiler.strict={'true' if strict else 'false'}"]
        cmd += [f"-compiler.external-library-path+={lib}" for lib in libs]
        cmd += [f"-compiler.source-path+={src}", f"-include-sources+={src}", f"-output={out}"]
        result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return result.returncode, result.stdout + result.stderr


def escape(text: str) -> str:
    return text.replace("|", "\\|")


def markdown(report: dict, top: int = 40) -> str:
    s = report["summary"]
    lines = [
        f"# AS3 compile census ({report['version']})", "",
        f"Compiler: Apache Royale {report['compiler']} `compc`, strict={str(report['strict']).lower()}, "
        f"against `{', '.join(report['libraries'])}`.", "",
        f"- Source files: {s['source_files']}",
        f"- Errors: {s['errors']} in {s['files_with_errors']} files (warnings: {s['warnings']})",
        f"- Compiler exit code: {report['exit_code']}", "",
        "The compiler stops at a file's syntax errors, so fixing them can reveal more errors in that file.", "",
        "## By kind", "", "| Kind | Count |", "| --- | --- |",
    ]
    lines += [f"| {k} | {v} |" for k, v in s["by_kind"].items()]
    lines += ["", "## By message", "", "| Count | Message (names collapsed) |", "| --- | --- |"]
    lines += [f"| {v} | {escape(k)} |" for k, v in list(s["by_message"].items())[:top]]
    lines += ["", "## By file", "", "| Count | File |", "| --- | --- |"]
    lines += [f"| {v} | `{k}` |" for k, v in list(s["by_file"].items())[:top]]
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--version", default="10.11")
    parser.add_argument("--src", type=Path, help="exported scripts folder (default src/as3/<ver>/scripts)")
    parser.add_argument("--out", type=Path, help="output SWC (default build/as3/<ver>/game.swc)")
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--lib", type=Path, action="append", default=[], help="extra external SWC")
    parser.add_argument("--report", type=Path, help="JSON report (default build/as3/<ver>/as3-compile.json)")
    parser.add_argument("--markdown", type=Path, help="also write a Markdown census here")
    parser.add_argument("--log", type=Path, help="parse an existing compiler log instead of compiling")
    args = parser.parse_args(argv)

    src = (args.src or ROOT / "src" / "as3" / args.version / "scripts").resolve()
    if not src.is_dir():
        print(f"error: source folder not found: {src}", file=sys.stderr)
        return 2
    files = sum(1 for _ in src.rglob("*.as"))
    libs = [setup_as3_compiler.AIRGLOBAL, *args.lib]
    out = (args.out or ROOT / "build" / "as3" / args.version / "game.swc").resolve()

    started = time.monotonic()
    if args.log:
        code, text = None, args.log.read_text(encoding="utf-8", errors="replace")
    else:
        jar = setup_as3_compiler.compc_jar()
        if not jar.is_file():
            print("error: compiler missing; run python tools/setup_as3_compiler.py", file=sys.stderr)
            return 2
        code, text = compile_tree(src, out, args.strict, libs, jar)
    diagnostics = parse_log(text, src)
    report = {
        "version": args.version,
        "compiler": setup_as3_compiler.VERSION,
        "strict": args.strict,
        "libraries": [lib.name for lib in libs],
        "exit_code": code,
        "seconds": round(time.monotonic() - started, 1),
        "summary": summarize(diagnostics, files),
        "diagnostics": diagnostics,
    }
    report_path = args.report or ROOT / "build" / "as3" / args.version / "as3-compile.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    if args.markdown:
        args.markdown.write_text(markdown(report), encoding="utf-8")

    s = report["summary"]
    print(f"{files} files, {s['errors']} errors in {s['files_with_errors']} files, {s['warnings']} warnings")
    for message, count in list(s["by_message"].items())[:10]:
        print(f"  {count:6d}  {message}")
    ok = s["errors"] == 0 and code in (0, None) and (args.log or out.is_file())
    print("OK" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
