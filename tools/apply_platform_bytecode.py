"""insert bytecode-mode hook calls into the disassembled game SWF.

    python tools/apply_platform_bytecode.py --src build/asasm-as3/<ver> [--version 10.11]

a hook call site (``src/platform/patches.json``) with ``"mode": "bytecode"`` leaves the AS3 tree alone, so
``tools/splice_as3.py`` keeps the method's original bytecode, and this tool adds the hook call to that bytecode
after ``tools/rename_back.py``. the game's own code in that method stays exactly as shipped.

a bytecode patch gives:

- ``file``/``function`` like an AS3 patch (``i/method/<name>``, names as in the
  AS3 tree; they are mapped back to the original names with the same maps as
  ``tools/rename_back.py``);
- ``where``: ``start`` (after the method's first ``pushscope``), ``end``
  (before its last ``returnvoid``), or ``after`` with ``anchor``: a regex on
  the stripped instruction that matches exactly one line of the method (the
  call goes right after it), or ``before`` one; ``{{name}}`` in it is an
  AS3-tree name, replaced by the original; ``occurrence`` picks the n-th of
  several matches instead;
- ``hook``: the ``bh.platform.Hooks`` constant; or ``call``: a static function,
  ``"bh.platform:Palette.swap"``, called directly (a hot path), with
  ``"returns": "nonzero"``: its result is returned when it isn't 0/false/null;
  or with ``"returns": "skip"`` (a void method): the rest of the method is
  skipped when it returns true; or with ``"sets_param": n``: its result replaces parameter n (``setlocal n``)
  and the method carries on;
- ``args``: what to pass: ``this``, ``paramN`` (``getlocal0``/``getlocalN``),
  ``localN`` (local register N, e.g. an object the method made: the AS3
  tree's ``_locN_`` is register N; only after it is set),
  ``this.<field>`` (a field of the object, named as in the AS3 tree) or a
  quoted string, ``'Taunt'`` (``pushstring``: one hook for several methods);
  also ``null``, ``paramN.<field>`` / ``localN.<field>`` and
  ``Class.<field>`` (a static field of a game class, ``GameApp.mainInstance``);
- ``filter`` (with ``hook``): ``Hook.filter(args...)``; its result replaces
  parameter/local ``sets_param`` (``convert``: String/int/uint/Boolean,
  or ``as``: a class), or with ``"returns": "nonzero"`` is returned unless null;
- ``code`` (for patches that are more than a call): raw instructions,
  ``{{name}}`` an AS3-tree name, ``@x`` a label of the patch; ``end_anchor``
  (regex; ``end_occurrence``, ``end_where``: ``before``) places ``@end`` at
  the first (n-th) matching line after the insertion, for skipping a statement;
  ``maxstack`` gives the stack the code needs; ``note`` says what it does in AS3;
- ``offset``: moves an anchored insertion n lines (to the start of the
  statement the anchor is in);
- ``consumable``: call ``fireUntilHandled`` and, if it returns true, return
  ``returns`` (``true``, ``false`` or ``void``) at once. Otherwise ``fire``.
  with ``sets_local``: n instead, a true result sets local register n to true
  and the method carries on (a switch a mod can turn on).
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools import rename_back
from tools.asasm_check import check as check_asasm

PATCHES = ROOT / "src" / "platform" / "patches.json"
HOOKS = 'QName(PackageNamespace("bh.platform"), "Hooks")'


class BytecodeError(Exception):
    pass


def original_names(version: str) -> dict[str, str]:
    symbols = ROOT / "client" / "symbols" / f"{version}.json"
    back = rename_back.back_map(json.loads(symbols.read_text(encoding="utf-8")))
    aliases = symbols.with_name(f"{version}.aliases.json")
    if aliases.exists():
        back.update(rename_back.alias_back_map(json.loads(aliases.read_text(encoding="utf-8"))["aliases"], back))
    return back


def _anchor(text: str, names: dict[str, str] | None) -> re.Pattern:
    return re.compile(re.sub(r"\{\{(\w+)\}\}", lambda m: re.escape((names or {}).get(m.group(1), m.group(1))), text))


def hook_code(patch: dict, label: str, names: dict[str, str] | None = None) -> list[str]:
    if "code" in patch:
        local = {"end": "0"}

        def at(m: re.Match) -> str:
            return label + local.setdefault(m.group(1), str(len(local)))
        return [re.sub(r"@(\w+)", at,
                       re.sub(r"\{\{(\w+)\}\}", lambda m: (names or {}).get(m.group(1), m.group(1)), c))
                for c in patch["code"]]
    if "call" in patch:
        m = re.fullmatch(r"([A-Za-z0-9_.]+):([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)", patch["call"])
        if not m:
            raise BytecodeError(f"{patch['id']}: call {patch['call']!r} is not package:Class.function")
        code = [f'getlex QName(PackageNamespace("{m.group(1)}"), "{m.group(2)}")']
    else:
        code = [f"getlex {HOOKS}", f'getproperty QName(PackageNamespace(""), "{patch["hook"]}")']
    def orig(name: str) -> str:
        return (names or {}).get(name, name)

    for arg in patch.get("args", []):
        if arg == "this":
            code.append("getlocal0")
        elif arg == "null":
            code.append("pushnull")
        elif re.fullmatch(r"'[A-Za-z0-9_ .-]*'", arg):
            code.append(f'pushstring "{arg[1:-1]}"')
        elif arg.startswith("this."):
            code += ["getlocal0", f'getproperty QName(PackageNamespace(""), "{orig(arg[5:])}")']
        elif m := re.fullmatch(r"(?:param|local)(\d+)\.(\w+)", arg):
            code += [f"getlocal {m.group(1)}", f'getproperty QName(PackageNamespace(""), "{orig(m.group(2))}")']
        elif m := re.fullmatch(r"(?:param|local)(\d+)", arg):
            code.append(f"getlocal {m.group(1)}")
        elif m := re.fullmatch(r"([A-Za-z_]\w*)\.(\w+)", arg):
            code += [f'getlex QName(PackageNamespace(""), "{orig(m.group(1))}")',
                     f'getproperty QName(PackageNamespace(""), "{orig(m.group(2))}")']
        else:
            raise BytecodeError(f"{patch['id']}: argument {arg!r} is not this, null, this.<field>, paramN[.field], "
                                f"localN[.field], Class.field or 'text'")
    n = len(patch.get("args", []))
    if patch.get("filter"):
        code.append(f'callproperty QName(PackageNamespace(""), "filter"), {n}')
        if patch.get("returns") == "nonzero":
            return code + ["dup", f"iffalse {label}", "returnvalue", f"{label}:", "pop"]
        if "sets_param" not in patch:
            raise BytecodeError(f"{patch['id']}: a filter hook needs sets_param or returns nonzero")
        conv = {"String": "convert_s", "int": "convert_i", "uint": "convert_u", "Boolean": "convert_b",
                None: None}
        if patch.get("convert") not in conv:
            raise BytecodeError(f"{patch['id']}: convert {patch['convert']!r} is not String, int, uint or Boolean")
        if conv[patch.get("convert")]:
            code.append(conv[patch["convert"]])
        if "as" in patch:
            code.append(f'astype QName(PackageNamespace(""), "{patch["as"]}")')
        return code + [f"setlocal {int(patch['sets_param'])}"]
    if "call" in patch:
        name = patch["call"].rsplit(".", 1)[1]
        if patch.get("returns") == "nonzero":
            return code + [f'callproperty QName(PackageNamespace(""), "{name}"), {n}', "dup", f"iffalse {label}",
                           "returnvalue", f"{label}:", "pop"]
        if patch.get("returns") == "skip":
            return code + [f'callproperty QName(PackageNamespace(""), "{name}"), {n}', f"iffalse {label}",
                           "returnvoid", f"{label}:"]
        if "sets_param" in patch:
            return code + [f'callproperty QName(PackageNamespace(""), "{name}"), {n}',
                           f"setlocal {int(patch['sets_param'])}"]
        return code + [f'callpropvoid QName(PackageNamespace(""), "{name}"), {n}']
    suffix = str(n) if n <= 3 else ""
    if not patch.get("consumable"):
        return code + [f'callpropvoid QName(PackageNamespace(""), "fire{suffix}"), {n}']
    if "sets_local" in patch:
        return code + [f'callproperty QName(PackageNamespace(""), "fireUntilHandled{suffix}"), {n}',
                       f"iffalse {label}", "pushtrue", f"setlocal {int(patch['sets_local'])}", f"{label}:"]
    ret = {"true": ["pushtrue", "returnvalue"], "false": ["pushfalse", "returnvalue"],
           "void": ["returnvoid"]}[patch.get("returns", "void")]
    return code + [f'callproperty QName(PackageNamespace(""), "fireUntilHandled{suffix}"), {n}',
                   f"iffalse {label}"] + ret + [f"{label}:"]


def method_span(lines: list[str], name: str) -> tuple[int, int]:
    rx = re.compile(r'^trait method QName\(.*, "%s"\)' % re.escape(name))
    starts = [i for i, l in enumerate(lines) if rx.match(l.strip())]
    if len(starts) != 1:
        raise BytecodeError(f"method {name}: {len(starts)} matches")
    for i in range(starts[0], len(lines)):
        if lines[i].strip() == "end ; method":
            return starts[0], i + 1
    raise BytecodeError(f"method {name}: no end")


DUP_NS = re.compile(r', "#[0-9]+"\)')


def plain(line: str) -> str:
    return DUP_NS.sub(")", line.strip()) if '"#' in line else line.strip()


def apply_patch(path: Path, method: str, patch: dict, label: str, names: dict[str, str] | None = None) -> None:
    lines = path.read_text(encoding="utf-8", errors="surrogateescape").split("\n")
    start, end = method_span(lines, method)
    body = range(start, end)
    if patch["where"] == "start":
        hits = [i for i in body if lines[i].strip() == "pushscope"]
        if not hits:
            hits = [i for i in body if lines[i].strip() == "code"]
        if not hits:
            raise BytecodeError(f"{patch['id']}: no pushscope or code in {method}")
        at = hits[0] + 1
    elif patch["where"] == "end":
        hits = [i for i in body if lines[i].strip() == "returnvoid"]
        if not hits:
            raise BytecodeError(f"{patch['id']}: no returnvoid in {method}")
        at = hits[-1]
    elif patch["where"] in ("after", "before") and patch.get("anchor"):
        rx = _anchor(patch["anchor"], names)
        hits = [i for i in body if rx.search(plain(lines[i]))]
        if "occurrence" in patch:
            k = int(patch["occurrence"])
            if not 1 <= k <= len(hits):
                raise BytecodeError(f"{patch['id']}: anchor {patch['anchor']!r} has {len(hits)} matches in {method}, "
                                    f"not a match number {k}")
            hits = [hits[k - 1]]
        if len(hits) != 1:
            raise BytecodeError(f"{patch['id']}: anchor {patch['anchor']!r} matches {len(hits)} lines in {method}")
        at = (hits[0] + 1 if patch["where"] == "after" else hits[0]) + int(patch.get("offset", 0))
        if not start < at < end:
            raise BytecodeError(f"{patch['id']}: offset {patch.get('offset')} leaves the method {method}")
    else:
        raise BytecodeError(f"{patch['id']}: bytecode patches go at the start, the end, or after or before an anchor, "
                            f"not {patch['where']!r}")
    indent = re.match(r"\s*", lines[at - 1 if patch["where"] in ("start", "after") else at]).group(0)
    if "end_anchor" in patch:
        rx = _anchor(patch["end_anchor"], names)
        hits = [i for i in range(at, end) if rx.search(plain(lines[i]))]
        if not hits:
            raise BytecodeError(f"{patch['id']}: end_anchor {patch['end_anchor']!r} has no match after the insertion")
        k = int(patch.get("end_occurrence", 1))
        if len(hits) < k:
            raise BytecodeError(f"{patch['id']}: end_anchor {patch['end_anchor']!r} has {len(hits)} matches after "
                                f"the insertion, not a match number {k}")
        e = hits[k - 1] + (0 if patch.get("end_where") == "before" else 1)
        lines[e:e] = [f"{label}0:"]
        end += 1
    code = [f"{indent}{c}" if not c.endswith(":") else c for c in hook_code(patch, label, names)]
    inserted = [f"{indent}; bh-platform:{patch['id']}"] + code
    lines[at:at] = inserted
    end += len(inserted)
    need = int(patch.get("maxstack", len(patch.get("args", [])) + 2))
    for i in range(start, end):
        m = re.match(r"^(\s*maxstack\s+)(\d+)\s*$", lines[i])
        if m:
            if int(m.group(2)) < need:
                lines[i] = f"{m.group(1)}{need}"
            break
    text = "\n".join(lines)
    problems = check_asasm("\n".join(lines[start:end]))
    if problems:
        raise BytecodeError(f"{patch['id']}: asasm_check: {problems[:3]}")
    path.write_text(text, encoding="utf-8", errors="surrogateescape")


def class_files(src: Path, cls: str) -> list[Path]:
    out = []
    for f in sorted(src.glob(f"block-*/{cls}*.class.asasm")):
        if f.name not in (f"{cls}.class.asasm", f"{cls}_.class.asasm") and f.name.lower() != f"{cls}.class.asasm".lower():
            continue
        with f.open(encoding="utf-8", errors="surrogateescape") as fh:
            fh.readline()
            if fh.readline().strip() == f'refid "{cls}"':
                out.append(f)
    return out


def apply(src: Path, version: str) -> list[str]:
    patches = [p for p in json.loads(PATCHES.read_text(encoding="utf-8"))["patches"] if p.get("mode") == "bytecode"]
    if not patches:
        return []
    names = original_names(version)
    done = []
    for n, patch in enumerate(patches):
        cls = Path(patch["file"]).stem
        method = patch["function"].split("/")[-1]
        orig_cls, orig_method = names.get(cls, cls), names.get(method, method)
        files = class_files(src, orig_cls)
        if len(files) != 1:
            raise BytecodeError(f"{patch['id']}: {len(files)} files for class {cls} ({orig_cls})")
        try:
            apply_patch(files[0], orig_method, patch, f"L{99001 + n}", names)
        except BytecodeError as e:
            raise BytecodeError(f"{patch['id']} ({cls}.{method} -> {orig_cls}.{orig_method}): {e}; src/platform/"
                                f"patches.json names 10.11's tree (src/as3/10.11), ported to other versions") from None
        done.append(f"{patch['id']} -> {orig_cls}.{orig_method}")
    return done


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--src", type=Path, required=True, help="disassembled SWF (abc_roundtrip.py disasm)")
    p.add_argument("--version", default="10.11")
    p.add_argument("--platform", type=Path, help="extension layer with the patches.json (default src/platform)")
    args = p.parse_args(argv)
    global PATCHES
    PATCHES = args.platform / "patches.json" if args.platform else PATCHES
    try:
        done = apply(args.src, args.version)
    except BytecodeError as e:
        print(f"apply_platform_bytecode FAILED: {e}", file=sys.stderr)
        return 1
    for line in done:
        print(f"[bytecode hook] {line}")
    print(f"{len(done)} bytecode hooks inserted")
    return 0


if __name__ == "__main__":
    sys.exit(main())
