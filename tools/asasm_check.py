#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

BRANCHES = {"jump", "iftrue", "iffalse", "ifeq", "ifne", "iflt", "ifle", "ifgt", "ifge",
            "ifstricteq", "ifstrictne", "ifnlt", "ifnle", "ifngt", "ifnge"}
TERMINATORS = {"returnvoid", "returnvalue", "throw", "jump", "lookupswitch"}
BINARY_IFS = BRANCHES - {"jump", "iftrue", "iffalse"}
STACK = {
    "getlex": (0, 1), "findpropstrict": (0, 1), "findproperty": (0, 1), "getscopeobject": (0, 1),
    "getglobalscope": (0, 1),
    "pushstring": (0, 1), "pushbyte": (0, 1), "pushshort": (0, 1), "pushint": (0, 1), "pushuint": (0, 1),
    "pushdouble": (0, 1), "pushnull": (0, 1), "pushundefined": (0, 1), "pushtrue": (0, 1),
    "pushfalse": (0, 1), "pushnan": (0, 1), "pushnamespace": (0, 1),
    "getlocal0": (0, 1), "getlocal1": (0, 1), "getlocal2": (0, 1), "getlocal3": (0, 1), "getlocal": (0, 1),
    "setlocal0": (1, 0), "setlocal1": (1, 0), "setlocal2": (1, 0), "setlocal3": (1, 0), "setlocal": (1, 0),
    "kill": (0, 0), "inclocal": (0, 0), "inclocal_i": (0, 0), "declocal": (0, 0), "declocal_i": (0, 0),
    "getproperty": (1, 1), "setproperty": (2, 0), "initproperty": (2, 0), "deleteproperty": (1, 1),
    "getslot": (1, 1), "setslot": (2, 0), "getsuper": (1, 1), "setsuper": (2, 0),
    "add": (2, 1), "add_i": (2, 1), "subtract": (2, 1), "subtract_i": (2, 1), "multiply": (2, 1),
    "multiply_i": (2, 1), "divide": (2, 1), "modulo": (2, 1), "equals": (2, 1), "strictequals": (2, 1),
    "lessthan": (2, 1), "lessequals": (2, 1), "greaterthan": (2, 1), "greaterequals": (2, 1),
    "istypelate": (2, 1), "astypelate": (2, 1), "instanceof": (2, 1), "in": (2, 1),
    "bitand": (2, 1), "bitor": (2, 1), "bitxor": (2, 1), "lshift": (2, 1), "rshift": (2, 1), "urshift": (2, 1),
    "not": (1, 1), "negate": (1, 1), "negate_i": (1, 1), "increment": (1, 1), "increment_i": (1, 1),
    "decrement": (1, 1), "decrement_i": (1, 1), "typeof": (1, 1), "bitnot": (1, 1),
    "convert_s": (1, 1), "convert_i": (1, 1), "convert_u": (1, 1), "convert_d": (1, 1), "convert_b": (1, 1),
    "convert_o": (1, 1), "coerce": (1, 1), "coerce_a": (1, 1), "coerce_s": (1, 1), "istype": (1, 1),
    "astype": (1, 1), "esc_xelem": (1, 1), "esc_xattr": (1, 1), "newclass": (1, 1),
    "pushscope": (1, 0), "pushwith": (1, 0), "popscope": (0, 0), "pop": (1, 0), "dup": (1, 2),
    "swap": (2, 2), "nop": (0, 0), "label": (0, 0), "debugline": (0, 0), "debugfile": (0, 0),
    "returnvoid": (0, 0), "returnvalue": (1, 0), "throw": (1, 0), "jump": (0, 0),
    "iftrue": (1, 0), "iffalse": (1, 0), "lookupswitch": (1, 0), "newactivation": (0, 1),
    "newfunction": (0, 1), "hasnext2": (0, 1), "getdescendants": (1, 1),
    "checkfilter": (1, 1), "dxns": (0, 0), "dxnslate": (1, 0), "nextname": (2, 1), "nextvalue": (2, 1), "hasnext": (2, 1),
    **{op: (2, 0) for op in BINARY_IFS},
}
ARGC_OPS = {
    "callproperty": (1, 1), "callpropvoid": (1, 0), "callproplex": (1, 1), "callsuper": (1, 1),
    "callsupervoid": (1, 0), "constructprop": (1, 1), "construct": (1, 1), "constructsuper": (1, 0),
    "call": (2, 1), "newarray": (0, 1), "applytype": (1, 1),
}
REG = re.compile(r"^(?:getlocal|setlocal|kill|inclocal|inclocal_i|declocal|declocal_i)(\d)?\s*(\d+)?")


def _runtime_name_pops(op: str) -> int:
    if "RTQNameL(" in op or "RTQNameLA(" in op:
        return 2
    if "RTQName(" in op or "RTQNameA(" in op or "MultinameL(" in op or "MultinameLA(" in op:
        return 1
    return 0


def _effect(op: str) -> tuple[int, int] | None:
    eff = _base_effect(op)
    if eff is None:
        return None
    return eff[0] + _runtime_name_pops(op), eff[1]


def _base_effect(op: str) -> tuple[int, int] | None:
    mnem = op.split()[0]
    if mnem in ARGC_OPS:
        m = re.search(r",\s*(\d+)\s*$", op) or re.search(r"\s(\d+)\s*$", op)
        argc = int(m.group(1)) if m else 0
        extra, pushes = ARGC_OPS[mnem]
        return argc + extra, pushes
    if mnem == "newobject":
        m = re.search(r"(\d+)\s*$", op)
        return 2 * int(m.group(1)), 1
    return STACK.get(mnem)
LABEL = re.compile(r"^(L\d+):$")
TRY = re.compile(r"^try from (L\d+) to (L\d+) target (L\d+)\b")


def _methods(text: str):
    name, init, maxd, maxstack, localcount = "?", 0, 0, 0, 0
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        s = lines[i].strip()
        if s.startswith("refid "):
            name = s[6:].strip('"')
        elif s.startswith("initscopedepth "):
            init = int(s.split()[1])
        elif s.startswith("maxscopedepth "):
            maxd = int(s.split()[1])
        elif s.startswith("maxstack "):
            maxstack = int(s.split()[1])
        elif s.startswith("localcount "):
            localcount = int(s.split()[1])
        elif s == "code":
            code, tries = [], []
            i += 1
            while lines[i].strip() != "end ; code":
                code.append(lines[i].strip())
                i += 1
            while not lines[i].strip().startswith("end ; body"):
                if lines[i].strip().startswith("try "):
                    tries.append(lines[i].strip())
                i += 1
            yield name, init, maxd, maxstack, localcount, code, tries
        i += 1


def check(text: str) -> list[str]:
    errors = []
    for name, init, maxd, maxstack, localcount, raw, tries in _methods(text):
        ops, labels = [], {}
        for line in raw:
            line = line.split(";", 1)[0].strip()
            if not line:
                continue
            m = LABEL.match(line)
            if m:
                labels[m.group(1)] = len(ops)
                continue
            ops.append(line)
        limit = maxd - init
        handlers = []
        for t in tries:
            m = TRY.match(t)
            if m:
                handlers.append((labels[m.group(1)], labels[m.group(2)], labels[m.group(3)]))
        state = {}
        work = []

        def reach(idx, st, frm):
            if idx >= len(ops):
                errors.append(f"{name}: falls off the end of the code after instruction {frm}")
                return
            if idx in state:
                old = state[idx]
                if old[0] != st[0]:
                    errors.append(f"{name}: instruction {idx} ({ops[idx]!r}) reached with scope depth "
                                  f"{old[0]} and {st[0]} (VerifyError #1031)")
                if old[1] != st[1]:
                    errors.append(f"{name}: instruction {idx} ({ops[idx]!r}) reached with stack depth "
                                  f"{old[1]} and {st[1]} (VerifyError #1030)")
                return
            state[idx] = st
            work.append(idx)

        reach(0, (0, 0), -1)
        for _, _, target in handlers:
            reach(target, (0, 1), -1)
        while work:
            i = work.pop()
            op = ops[i]
            mnem = op.split()[0]
            d, sd = state[i]
            m = REG.match(op)
            if m and (m.group(1) or m.group(2)):
                reg = int(m.group(1) or m.group(2))
                if reg >= localcount:
                    errors.append(f"{name}: {op!r} uses register {reg} but localcount is {localcount} "
                                  "(VerifyError #1025)")
            eff = _effect(op)
            if eff is None:
                errors.append(f"{name}: opcode {mnem!r} is not modelled by tools/asasm_check.py")
                continue
            pops, pushes = eff
            if sd < pops:
                errors.append(f"{name}: {op!r} at instruction {i} pops {pops} with stack depth {sd} "
                              "(VerifyError #1024)")
                continue
            sd = sd - pops + pushes
            if sd > maxstack:
                errors.append(f"{name}: stack depth {sd} after {op!r} (instruction {i}) exceeds maxstack "
                              f"{maxstack} (VerifyError #1023)")
            if mnem in ("pushscope", "pushwith"):
                d += 1
                if d > limit:
                    errors.append(f"{name}: scope depth {d} exceeds maxscopedepth - initscopedepth = {limit}")
            elif mnem == "popscope":
                d -= 1
                if d < 0:
                    errors.append(f"{name}: popscope on an empty scope stack at instruction {i}")
                    continue
            targets = re.findall(r"\bL\d+\b", op) if mnem in BRANCHES or mnem == "lookupswitch" else []
            for t in targets:
                if t not in labels:
                    errors.append(f"{name}: unknown label {t}")
                else:
                    reach(labels[t], (d, sd), i)
            if mnem not in TERMINATORS:
                reach(i + 1, (d, sd), i)
            for start, end, target in handlers:
                if start <= i < end:
                    reach(target, (0, 1), i)
    return errors


check_scope_depth = check


def main():
    bad = 0
    for arg in sys.argv[1:]:
        for err in check(Path(arg).read_text(encoding="utf-8")):
            print(f"{arg}: {err}")
            bad += 1
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
