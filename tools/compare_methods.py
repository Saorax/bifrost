"""compare every method body of the compiled AS3 with the original bytecode.

    python tools/compare_methods.py [--version 10.11] [--compiled build/as3/<ver>/game.swc]
                                    [--original build/as3/renamed.swf] [--markdown PATH]

both sides are parsed straight from their ABC blocks: the compiled side is the SWC's ``library.swf`` from
``tools/compile_as3.py``, or any SWF; the original side defaults to FFDec's renamed SWF from
``tools/export_as3.py``, the game with only its names changed 1:1, so its names are the ones the AS3 source uses.

methods are matched by key, not by index:

- ``pkg.Class/iinit``, ``pkg.Class/cinit``;
- ``pkg.Class/i/<kind> <name>`` and ``pkg.Class/s/<kind> <name>`` for instance
  and static traits (kind is method, getter or setter);
- ``script <first trait>/init`` and ``script <first trait>/function <name>``;
- ``<parent key>/fn<n>`` for the n-th ``newfunction`` closure in a body.

each body is normalized before comparing: names are rendered from the
constant pool (private namespaces as ``private``), branch targets become
instruction numbers, ``getlocal0``-``3``/``setlocal0``-``3`` become their
general form, and ``debug*``, ``nop``, ``label`` and ``bkpt*`` are dropped.
``max_stack``, ``local_count`` and the scope depths are compared separately;
they don't decide equality. the signature (parameter and return types,
optional defaults, need_* flags) is part of equality.

status of each original method: ``equal``, ``equivalent`` (equal after the
proven rewrites in ``EQUIVALENCES``), ``splice`` (a ``BH_SPLICE`` stub
from ``tools/as3_fixups.py``), ``signature``, ``code`` or ``missing``;
compiled methods with no original are ``extra``. each non-equal method gets a
cause: for ``code``, the first differing instruction pair with operands
collapsed, so the census groups by what the compiler did differently.
renames made by ``as3_fixups.py`` (``Random_bhsrc``) are mapped back through
``--fixups`` (default ``build/as3/<ver>/as3-fixups.json``).

writes ``build/as3/<ver>/method-compare.json``. exit 0 once the comparison
ran; ``--require-equal`` exits 1 unless every method is equal or listed in
``--exceptions``.
"""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import os
import io
import json
from pathlib import Path
import re
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(Path(__file__).resolve().parent))

from abc_reader import AbcError, _Stream, swf_abc_blocks

NS_KINDS = {0x08: "ns", 0x16: "pkg", 0x17: "internal", 0x18: "protected",
            0x19: "explicit", 0x1A: "staticprotected", 0x05: "private"}
NEED_FLAGS = 0x01 | 0x02 | 0x04 | 0x40
TRAIT_KINDS = {0: "slot", 1: "method", 2: "getter", 3: "setter", 4: "class", 5: "function", 6: "const"}

OPS: dict[int, tuple[str, tuple[str, ...]]] = {
    0x01: ("bkpt", ()), 0x02: ("nop", ()), 0x03: ("throw", ()),
    0x04: ("getsuper", ("mn",)), 0x05: ("setsuper", ("mn",)),
    0x06: ("dxns", ("str",)), 0x07: ("dxnslate", ()), 0x08: ("kill", ("reg",)),
    0x09: ("label", ()),
    0x0C: ("ifnlt", ("off",)), 0x0D: ("ifnle", ("off",)), 0x0E: ("ifngt", ("off",)),
    0x0F: ("ifnge", ("off",)), 0x10: ("jump", ("off",)), 0x11: ("iftrue", ("off",)),
    0x12: ("iffalse", ("off",)), 0x13: ("ifeq", ("off",)), 0x14: ("ifne", ("off",)),
    0x15: ("iflt", ("off",)), 0x16: ("ifle", ("off",)), 0x17: ("ifgt", ("off",)),
    0x18: ("ifge", ("off",)), 0x19: ("ifstricteq", ("off",)), 0x1A: ("ifstrictne", ("off",)),
    0x1B: ("lookupswitch", ()),
    0x1C: ("pushwith", ()), 0x1D: ("popscope", ()), 0x1E: ("nextname", ()),
    0x1F: ("hasnext", ()), 0x20: ("pushnull", ()), 0x21: ("pushundefined", ()),
    0x23: ("nextvalue", ()), 0x24: ("pushbyte", ("s8",)), 0x25: ("pushshort", ("s32",)),
    0x26: ("pushtrue", ()), 0x27: ("pushfalse", ()), 0x28: ("pushnan", ()),
    0x29: ("pop", ()), 0x2A: ("dup", ()), 0x2B: ("swap", ()),
    0x2C: ("pushstring", ("str",)), 0x2D: ("pushint", ("int",)), 0x2E: ("pushuint", ("uint",)),
    0x2F: ("pushdouble", ("dbl",)), 0x30: ("pushscope", ()), 0x31: ("pushnamespace", ("ns",)),
    0x32: ("hasnext2", ("reg", "reg")),
    0x35: ("li8", ()), 0x36: ("li16", ()), 0x37: ("li32", ()), 0x38: ("lf32", ()),
    0x39: ("lf64", ()), 0x3A: ("si8", ()), 0x3B: ("si16", ()), 0x3C: ("si32", ()),
    0x3D: ("sf32", ()), 0x3E: ("sf64", ()),
    0x40: ("newfunction", ("m",)), 0x41: ("call", ("u",)), 0x42: ("construct", ("u",)),
    0x43: ("callmethod", ("u", "u")), 0x44: ("callstatic", ("m", "u")),
    0x45: ("callsuper", ("mn", "u")), 0x46: ("callproperty", ("mn", "u")),
    0x47: ("returnvoid", ()), 0x48: ("returnvalue", ()), 0x49: ("constructsuper", ("u",)),
    0x4A: ("constructprop", ("mn", "u")), 0x4B: ("callsuperid", ()),
    0x4C: ("callproplex", ("mn", "u")), 0x4D: ("callinterface", ()),
    0x4E: ("callsupervoid", ("mn", "u")), 0x4F: ("callpropvoid", ("mn", "u")),
    0x50: ("sxi1", ()), 0x51: ("sxi8", ()), 0x52: ("sxi16", ()),
    0x53: ("applytype", ("u",)), 0x55: ("newobject", ("u",)), 0x56: ("newarray", ("u",)),
    0x57: ("newactivation", ()), 0x58: ("newclass", ("c",)), 0x59: ("getdescendants", ("mn",)),
    0x5A: ("newcatch", ("u",)), 0x5D: ("findpropstrict", ("mn",)), 0x5E: ("findproperty", ("mn",)),
    0x5F: ("finddef", ("mn",)), 0x60: ("getlex", ("mn",)), 0x61: ("setproperty", ("mn",)),
    0x62: ("getlocal", ("reg",)), 0x63: ("setlocal", ("reg",)), 0x64: ("getglobalscope", ()),
    0x65: ("getscopeobject", ("b8",)), 0x66: ("getproperty", ("mn",)),
    0x67: ("getouterscope", ("u",)), 0x68: ("initproperty", ("mn",)),
    0x6A: ("deleteproperty", ("mn",)), 0x6C: ("getslot", ("u",)), 0x6D: ("setslot", ("u",)),
    0x6E: ("getglobalslot", ("u",)), 0x6F: ("setglobalslot", ("u",)),
    0x70: ("convert_s", ()), 0x71: ("esc_xelem", ()), 0x72: ("esc_xattr", ()),
    0x73: ("convert_i", ()), 0x74: ("convert_u", ()), 0x75: ("convert_d", ()),
    0x76: ("convert_b", ()), 0x77: ("convert_o", ()), 0x78: ("checkfilter", ()),
    0x80: ("coerce", ("mn",)), 0x81: ("coerce_b", ()), 0x82: ("coerce_a", ()),
    0x83: ("coerce_i", ()), 0x84: ("coerce_d", ()), 0x85: ("coerce_s", ()),
    0x86: ("astype", ("mn",)), 0x87: ("astypelate", ()), 0x88: ("coerce_u", ()),
    0x89: ("coerce_o", ()),
    0x90: ("negate", ()), 0x91: ("increment", ()), 0x92: ("inclocal", ("reg",)),
    0x93: ("decrement", ()), 0x94: ("declocal", ("reg",)), 0x95: ("typeof", ()),
    0x96: ("not", ()), 0x97: ("bitnot", ()),
    0xA0: ("add", ()), 0xA1: ("subtract", ()), 0xA2: ("multiply", ()), 0xA3: ("divide", ()),
    0xA4: ("modulo", ()), 0xA5: ("lshift", ()), 0xA6: ("rshift", ()), 0xA7: ("urshift", ()),
    0xA8: ("bitand", ()), 0xA9: ("bitor", ()), 0xAA: ("bitxor", ()), 0xAB: ("equals", ()),
    0xAC: ("strictequals", ()), 0xAD: ("lessthan", ()), 0xAE: ("lessequals", ()),
    0xAF: ("greaterthan", ()), 0xB0: ("greaterequals", ()), 0xB1: ("instanceof", ()),
    0xB2: ("istype", ("mn",)), 0xB3: ("istypelate", ()), 0xB4: ("in", ()),
    0xC0: ("increment_i", ()), 0xC1: ("decrement_i", ()), 0xC2: ("inclocal_i", ("reg",)),
    0xC3: ("declocal_i", ("reg",)), 0xC4: ("negate_i", ()), 0xC5: ("add_i", ()),
    0xC6: ("subtract_i", ()), 0xC7: ("multiply_i", ()),
    0xD0: ("getlocal0", ()), 0xD1: ("getlocal1", ()), 0xD2: ("getlocal2", ()), 0xD3: ("getlocal3", ()),
    0xD4: ("setlocal0", ()), 0xD5: ("setlocal1", ()), 0xD6: ("setlocal2", ()), 0xD7: ("setlocal3", ()),
    0xEF: ("debug", ("b8", "str", "b8", "u")), 0xF0: ("debugline", ("u",)),
    0xF1: ("debugfile", ("str",)), 0xF2: ("bkptline", ("u",)), 0xF3: ("timestamp", ()),
}
OP_BY_NAME = {v[0]: k for k, v in OPS.items()}
DROPPED = {"debug", "debugline", "debugfile", "nop", "label", "bkpt", "bkptline", "timestamp"}


class Stream(_Stream):
    def s24(self) -> int:
        b = self.bytes(3)
        v = b[0] | b[1] << 8 | b[2] << 16
        return v - (1 << 24) if v & 0x800000 else v

    def s32(self) -> int:
        v = self.u30()
        return v - (1 << 32) if v & 0x80000000 else v


def _traits(s: Stream) -> list[dict]:
    traits = []
    for _ in range(s.u30()):
        t = {"name": s.u30()}
        kind_byte = s.u8()
        t["kind"], attrs = kind_byte & 0x0F, kind_byte >> 4
        if t["kind"] in (0, 6):
            t["slot"], t["type"], vindex = s.u30(), s.u30(), s.u30()
            t["value"] = (vindex, s.u8() if vindex else 0)
        elif t["kind"] == 4:
            t["slot"], t["class"] = s.u30(), s.u30()
        elif t["kind"] in (1, 2, 3, 5):
            s.u30()
            t["method"] = s.u30()
        else:
            raise AbcError(f"bad trait kind {t['kind']}")
        if attrs & 0x4:
            for _ in range(s.u30()):
                s.u30()
        traits.append(t)
    return traits


class Abc:

    def __init__(self, data: bytes, ns_aliases: dict[str, str] | None = None):
        self.ns_aliases = ns_aliases or {}
        s = Stream(data)
        s.u16(), s.u16()
        self.ints = [0] + [s.s32() for _ in range(max(s.u30() - 1, 0))]
        self.uints = [0] + [s.u30() for _ in range(max(s.u30() - 1, 0))]
        self.doubles = [float("nan")] + [s.d64() for _ in range(max(s.u30() - 1, 0))]
        self.strings: list[str | None] = [None]
        for _ in range(max(s.u30() - 1, 0)):
            self.strings.append(s.bytes(s.u30()).decode("utf-8", errors="surrogateescape"))
        self.namespaces = [(0, 0)] + [(s.u8(), s.u30()) for _ in range(max(s.u30() - 1, 0))]
        self.ns_sets = [[]] + [[s.u30() for _ in range(s.u30())] for _ in range(max(s.u30() - 1, 0))]
        self.multinames: list[tuple] = [()]
        for _ in range(max(s.u30() - 1, 0)):
            kind = s.u8()
            if kind in (0x07, 0x0D):
                self.multinames.append((kind, s.u30(), s.u30()))
            elif kind in (0x0F, 0x10):
                self.multinames.append((kind, s.u30()))
            elif kind in (0x11, 0x12):
                self.multinames.append((kind,))
            elif kind in (0x09, 0x0E):
                self.multinames.append((kind, s.u30(), s.u30()))
            elif kind in (0x1B, 0x1C):
                self.multinames.append((kind, s.u30()))
            elif kind == 0x1D:
                base = s.u30()
                self.multinames.append((kind, base, tuple(s.u30() for _ in range(s.u30()))))
            else:
                raise AbcError(f"bad multiname kind 0x{kind:02x}")
        self.methods = []
        for _ in range(s.u30()):
            count = s.u30()
            ret = s.u30()
            params = [s.u30() for _ in range(count)]
            s.u30()
            flags = s.u8()
            optional = [(s.u30(), s.u8()) for _ in range(s.u30())] if flags & 0x08 else []
            if flags & 0x80:
                for _ in range(count):
                    s.u30()
            self.methods.append({"ret": ret, "params": params, "flags": flags, "optional": optional,
                                 "body": None})
        for _ in range(s.u30()):
            s.u30()
            for _ in range(2 * s.u30()):
                s.u30()
        count = s.u30()
        self.instances = []
        for _ in range(count):
            name, sup, flags = s.u30(), s.u30(), s.u8()
            if flags & 0x08:
                s.u30()
            for _ in range(s.u30()):
                s.u30()
            self.instances.append({"name": name, "super": sup, "iinit": s.u30(), "traits": _traits(s)})
        self.classes = [{"cinit": s.u30(), "traits": _traits(s)} for _ in range(count)]
        self.scripts = [{"init": s.u30(), "traits": _traits(s)} for _ in range(s.u30())]
        for _ in range(s.u30()):
            method = s.u30()
            body = {"max_stack": s.u30(), "locals": s.u30(), "init_scope": s.u30(), "max_scope": s.u30()}
            body["code"] = s.bytes(s.u30())
            body["exceptions"] = [tuple(s.u30() for _ in range(5)) for _ in range(s.u30())]
            _traits(s)
            self.methods[method]["body"] = body
        if s.pos != len(data):
            raise AbcError(f"trailing data: parsed {s.pos} of {len(data)} bytes")

    def string(self, i: int) -> str:
        return self.strings[i] if 0 < i < len(self.strings) and self.strings[i] is not None else "*"

    def ns(self, i: int) -> str:
        if i <= 0:
            return "*"
        kind, name = self.namespaces[i]
        if kind == 0x05:
            return "private"
        uri = self.string(name) if name else ""
        if kind == 0x08:
            uri = self.ns_aliases.get(uri, uri)
        return f"{NS_KINDS.get(kind, hex(kind))}:{uri}"

    def mn(self, i: int, aliases: dict[str, str] | None = None) -> str:
        if i <= 0 or i >= len(self.multinames):
            return "*"
        m = self.multinames[i]
        kind = m[0]

        def local(n: int) -> str:
            text = self.string(n) if n else "*"
            return aliases.get(text, text) if aliases else text

        if kind in (0x07, 0x0D):
            return f"{self.ns(m[1])}::{local(m[2])}"
        if kind in (0x0F, 0x10):
            return f"rt::{local(m[1])}"
        if kind in (0x11, 0x12):
            return "rt::[]"
        if kind in (0x09, 0x0E):
            spaces = sorted({self.ns(n) for n in self.ns_sets[m[2]]})
            return "{" + ",".join(spaces) + "}::" + local(m[1])
        if kind in (0x1B, 0x1C):
            return "{" + ",".join(sorted({self.ns(n) for n in self.ns_sets[m[1]]})) + "}::[]"
        return f"{self.mn(m[1], aliases)}.<{','.join(self.mn(p, aliases) for p in m[2])}>"

    def class_name(self, index: int) -> str:
        m = self.multinames[self.instances[index]["name"]]
        pkg = self.string(self.namespaces[m[1]][1]) if self.namespaces[m[1]][1] else ""
        return f"{pkg}.{self.string(m[2])}" if pkg else self.string(m[2])

    def constant(self, index: int, kind: int) -> str:
        if kind == 0x03:
            return f"int:{self.ints[index]}"
        if kind == 0x04:
            return f"uint:{self.uints[index]}"
        if kind == 0x06:
            return f"double:{self.doubles[index]!r}"
        if kind == 0x01:
            return f"string:{self.string(index)!r}"
        fixed = {0x0A: "false", 0x0B: "true", 0x0C: "null", 0x00: "undefined"}
        return fixed[kind] if kind in fixed else f"ns:{self.ns(index)}"

    def decode(self, code: bytes) -> list[tuple[int, str, list]]:
        s, out = Stream(code), []
        while s.pos < len(code):
            at = s.pos
            op = s.u8()
            if op not in OPS:
                raise AbcError(f"unknown opcode 0x{op:02x} at {at}")
            name, kinds = OPS[op]
            if op == 0x1B:
                default = s.s24()
                cases = [s.s24() for _ in range(s.u30() + 1)]
                out.append((at, name, [at + default] + [at + c for c in cases]))
                continue
            args = []
            for kind in kinds:
                if kind == "off":
                    delta = s.s24()
                    args.append(s.pos + delta)
                elif kind == "s8":
                    v = s.u8()
                    args.append(v - 256 if v & 0x80 else v)
                elif kind == "b8":
                    args.append(s.u8())
                elif kind == "s32":
                    args.append(s.s32())
                else:
                    args.append(s.u30())
            out.append((at, name, args))
        return out


def normalize(abc: Abc, method: int, aliases: dict[str, str] | None = None) -> dict:
    info = abc.methods[method]
    sig = {
        "params": [abc.mn(p, aliases) for p in info["params"]],
        "ret": abc.mn(info["ret"], aliases),
        "flags": info["flags"] & NEED_FLAGS,
        "optional": [abc.constant(i, k) for i, k in info["optional"]],
    }
    body = info["body"]
    if body is None:
        return {"sig": sig, "code": None, "exceptions": [], "closures": [], "meta": None}
    raw = abc.decode(body["code"])
    kept = [(at, name, args) for at, name, args in raw if name not in DROPPED]
    index_at: dict[int, int] = {}
    k = 0
    for at, name, _ in raw:
        index_at[at] = k
        if name not in DROPPED:
            k += 1
    index_at[len(body["code"])] = k

    def label(offset: int) -> str:
        if offset in index_at:
            return f"L{index_at[offset]}"
        return f"L?{offset}"

    lines, closures = [], []
    for _, name, args in kept:
        if name[:-1] in ("getlocal", "setlocal") and name[-1].isdigit():
            name, args = name[:-1], [int(name[-1])]
        kinds = OPS[OP_BY_NAME[name]][1]
        if name == "lookupswitch":
            parts = [label(a) for a in args]
        else:
            parts = []
            for kind, a in zip(kinds, args):
                if kind == "mn":
                    parts.append(abc.mn(a, aliases))
                elif kind == "str":
                    parts.append(repr(abc.string(a)))
                elif kind == "int":
                    parts.append(str(abc.ints[a]))
                elif kind == "uint":
                    parts.append(str(abc.uints[a]))
                elif kind == "dbl":
                    parts.append(repr(abc.doubles[a]))
                elif kind == "ns":
                    parts.append(abc.ns(a))
                elif kind == "off":
                    parts.append(label(a))
                elif kind == "m":
                    if name == "newfunction":
                        closures.append(a)
                        parts.append(f"fn{len(closures) - 1}")
                    else:
                        parts.append(f"method#{a}")
                elif kind == "c":
                    parts.append(abc.class_name(a))
                else:
                    parts.append(str(a))
        lines.append(" ".join([name] + parts))
    exceptions = [
        f"{label(f)}-{label(t)}->{label(target)} {abc.mn(etype, aliases)} {abc.mn(var, aliases)}"
        for f, t, target, etype, var in body["exceptions"]
    ]
    lines, exceptions = drop_unreachable(lines, exceptions)
    meta = {key: body[key] for key in ("max_stack", "locals", "init_scope", "max_scope")}
    return {"sig": sig, "code": lines, "exceptions": exceptions, "closures": closures, "meta": meta}


LABEL = re.compile(r"\bL(\d+)\b")
EXITS = ("jump", "returnvalue", "returnvoid", "throw", "lookupswitch")
EXCEPTION = re.compile(r"^L(\d+)-L(\d+)->L(\d+) (.*)$")


def drop_unreachable(lines: list[str], exceptions: list[str]) -> tuple[list[str], list[str]]:
    if any("L?" in line for line in lines) or any("L?" in e for e in exceptions):
        return lines, exceptions
    handlers = [EXCEPTION.match(e) for e in exceptions]
    if not all(handlers):
        return lines, exceptions
    todo = [0] + [int(m.group(3)) for m in handlers]
    seen: set[int] = set()
    while todo:
        i = todo.pop()
        if i in seen or i >= len(lines):
            continue
        seen.add(i)
        name = lines[i].split(" ", 1)[0]
        if name.startswith(("if", "jump", "lookupswitch")):
            todo += [int(n) for n in LABEL.findall(lines[i])]
        if name not in EXITS:
            todo.append(i + 1)
    if len(seen) == len(lines):
        return lines, exceptions
    new_index, n = {}, 0
    for i in range(len(lines) + 1):
        new_index[i] = n
        if i in seen:
            n += 1

    def relabel(text: str) -> str:
        return LABEL.sub(lambda m: f"L{new_index[int(m.group(1))]}", text)

    kept = [relabel(line) if line.split(" ", 1)[0].startswith(("if", "jump", "lookupswitch")) else line
            for i, line in enumerate(lines) if i in seen]
    return kept, [relabel(e) for e in exceptions]


def is_qname(operand: str) -> bool:
    return bool(operand) and not operand.startswith(("{", "rt::")) and "::" in operand and ".<" not in operand


def branch_targets(lines: list[str], exceptions: list[str]) -> set[int]:
    targets = set()
    for line in lines:
        if line.split(" ", 1)[0].startswith(("if", "jump", "lookupswitch")):
            targets.update(int(n) for n in LABEL.findall(line))
    for e in exceptions:
        targets.update(int(n) for n in LABEL.findall(e))
    return targets


def _rebuild(lines: list[str], exceptions: list[str], new_lines: dict[int, str | None]):
    new_index, n = {}, 0
    for i in range(len(lines) + 1):
        new_index[i] = n
        if i < len(lines) and new_lines.get(i, lines[i]) is not None:
            n += 1

    def relabel(text: str) -> str:
        return LABEL.sub(lambda m: f"L{new_index[int(m.group(1))]}", text)

    out = []
    for i, line in enumerate(lines):
        line = new_lines.get(i, line)
        if line is None:
            continue
        out.append(relabel(line) if line.split(" ", 1)[0].startswith(("if", "jump", "lookupswitch")) else line)
    return out, [relabel(e) for e in exceptions]


def rule_lookup_strict(lines, exceptions):
    changed = {i: "findpropstrict " + line.split(" ", 1)[1] for i, line in enumerate(lines)
               if line.startswith("findproperty ") and is_qname(line.split(" ", 1)[1])}
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_getlex(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    i = 0
    while i + 1 < len(lines):
        a, b = lines[i], lines[i + 1]
        if a.startswith("findpropstrict ") and b.startswith("getproperty ") and i + 1 not in targets:
            q = a.split(" ", 1)[1]
            if is_qname(q) and b.split(" ", 1)[1] == q:
                changed[i], changed[i + 1] = "getlex " + q, None
                i += 2
                continue
        i += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


VALUE_TYPES = {"pkg:::int", "pkg:::uint", "pkg:::Number", "pkg:::Boolean"}
CONVERT_FOR_RETURN = {"convert_d": "pkg:::Number", "convert_b": "pkg:::Boolean",
                      "convert_i": "pkg:::int", "convert_u": "pkg:::uint", "coerce_s": "pkg:::String"}
IDEMPOTENT = ("convert_b", "convert_d", "convert_i", "convert_u", "convert_s", "coerce_s", "coerce_a")


def _pairs(lines, exceptions, match, keep_second_target=False):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    i = 0
    while i + 1 < len(lines):
        out = match(lines[i], lines[i + 1])
        if out is not None and (i + 1 not in targets or keep_second_target):
            changed[i], changed[i + 1] = out
            i += 2
            continue
        i += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def _operand(line: str, op: str) -> str | None:
    head, _, rest = line.partition(" ")
    return rest if head == op else None


SHADOWED: set[str] = set()


def shadowed_names(blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> set[str]:
    classes, traits = set(), set()
    for data in blocks:
        abc = Abc(data, ns_aliases)
        for i, inst in enumerate(abc.instances):
            classes.add(abc.mn(inst["name"]))
            traits.update(abc.mn(t["name"]) for t in inst["traits"] + abc.classes[i]["traits"])
        for script in abc.scripts:
            traits.update(abc.mn(t["name"]) for t in script["traits"] if t["kind"] != 4)
    return classes & traits


def rule_astypelate(lines, exceptions):
    def match(a, b):
        t = _operand(a, "getlex")
        if t and is_qname(t) and t not in SHADOWED and b == "astypelate":
            return "astype " + t, None
    return _pairs(lines, exceptions, match)


def is_type(operand: str) -> bool:
    return is_qname(operand) or (bool(operand) and ".<" in operand and not operand.startswith(("{", "rt::")))


def rule_vector_astype(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    for i in range(len(lines) - 3):
        v, t = _operand(lines[i], "getlex"), _operand(lines[i + 1], "getlex")
        if (v == "pkg:__AS3__.vec::Vector" and t and is_qname(t) and t not in SHADOWED and lines[i + 2] == "applytype 1"
                and lines[i + 3] == "astypelate" and not targets & {i + 1, i + 2, i + 3} and i not in changed):
            changed.update({i: f"astype {v}.<{t}>", i + 1: None, i + 2: None, i + 3: None})
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_null_coerce(lines, exceptions):
    def match(a, b):
        t = _operand(b, "coerce")
        if a == "pushnull" and t and is_type(t) and t not in VALUE_TYPES:
            return "pushnull", None
    return _pairs(lines, exceptions, match)


NEGATED_BRANCH = {"iffalse": "iftrue", "iftrue": "iffalse"}
COMPARE_BRANCH = {("equals", "iffalse"): "ifne", ("equals", "iftrue"): "ifeq",
                  ("strictequals", "iffalse"): "ifstrictne", ("strictequals", "iftrue"): "ifstricteq"}


def rule_not_branch(lines, exceptions):
    def match(a, b):
        head, _, label = b.partition(" ")
        if a == "convert_b" and b == "not":
            return None, b
        if a == "not" and head in NEGATED_BRANCH:
            return f"{NEGATED_BRANCH[head]} {label}", None
    return _pairs(lines, exceptions, match)


def rule_compare_branch(lines, exceptions):
    def match(a, b):
        head, _, label = b.partition(" ")
        if (a, head) in COMPARE_BRANCH:
            return f"{COMPARE_BRANCH[a, head]} {label}", None
    return _pairs(lines, exceptions, match)


def rule_const_uint(lines, exceptions):
    def match(a, b):
        head, _, n = a.partition(" ")
        if head in ("pushbyte", "pushshort") and b == "convert_u" and n.lstrip("-").isdigit() and int(n) >= 0:
            return a, None
    return _pairs(lines, exceptions, match)


def rule_double_convert(lines, exceptions):
    def match(a, b):
        if a == b and (a in IDEMPOTENT or (a.startswith("coerce ") and is_qname(a[7:]))):
            return a, None
    return _pairs(lines, exceptions, match)


def rule_coerce_string(lines, exceptions):
    changed = {i: "coerce_s" for i, line in enumerate(lines) if line == "coerce pkg:::String"}
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_branch_bool(lines, exceptions):
    def match(a, b):
        if a == "convert_b" and b.startswith(("iftrue ", "iffalse ")):
            return None, b
    return _pairs(lines, exceptions, match, keep_second_target=True)


def rule_return_convert(lines, exceptions, ret):
    def match(a, b):
        if b == "returnvalue" and ret != "*" and (CONVERT_FOR_RETURN.get(a) == ret or a == f"coerce {ret}"):
            return None, b
    return _pairs(lines, exceptions, match, keep_second_target=True)


def rule_const_number(lines, exceptions):
    def match(a, b):
        head, _, n = a.partition(" ")
        if head in ("pushbyte", "pushshort", "pushint") and b == "convert_d" and n.lstrip("-").isdigit():
            return f"pushdouble {float(int(n))!r}", None
    return _pairs(lines, exceptions, match)


CONSTS: set[str] = set()


def const_names(blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> set[str]:
    names = set()
    for data in blocks:
        abc = Abc(data, ns_aliases)
        for i, inst in enumerate(abc.instances):
            names.update(abc.mn(t["name"]) for t in inst["traits"] + abc.classes[i]["traits"] if t["kind"] == 6)
        for script in abc.scripts:
            names.update(abc.mn(t["name"]) for t in script["traits"] if t["kind"] == 6)
    return names


def rule_init_set(lines, exceptions):
    changed = {i: "setproperty " + line.split(" ", 1)[1] for i, line in enumerate(lines)
               if line.startswith("initproperty ") and is_qname(line.split(" ", 1)[1])
               and line.split(" ", 1)[1] not in CONSTS}
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


PURE_PUSH = ("getlocal ", "pushbyte ", "pushshort ", "pushint ", "pushuint ", "pushdouble ", "pushstring ")
PURE_PUSH_BARE = ("pushnull", "pushundefined", "pushtrue", "pushfalse", "pushnan")


def rule_swap_push(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    i = 0
    while i + 2 < len(lines):
        p, f = lines[i], lines[i + 1]
        if ((p.startswith(PURE_PUSH) or p in PURE_PUSH_BARE) and f.startswith("findpropstrict ")
                and is_qname(f.split(" ", 1)[1]) and lines[i + 2] == "swap" and not targets & {i + 1, i + 2}):
            changed.update({i: f, i + 1: p, i + 2: None})
            i += 3
            continue
        i += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


EQUIVALENCES = [
    ("lookup-strict", rule_lookup_strict),
    ("getlex", rule_getlex),
    ("astypelate", rule_astypelate),
    ("vector-astype", rule_vector_astype),
    ("null-coerce", rule_null_coerce),
    ("not-branch", rule_not_branch),
    ("compare-branch", rule_compare_branch),
    ("const-uint", rule_const_uint),
    ("const-number", rule_const_number),
    ("init-set", rule_init_set),
    ("swap-push", rule_swap_push),
    ("coerce-string", rule_coerce_string),
    ("double-convert", rule_double_convert),
    ("branch-bool", rule_branch_bool),
    ("return-convert", rule_return_convert),
]


REGISTER_OPS = ("getlocal", "setlocal", "kill", "inclocal", "declocal", "inclocal_i", "declocal_i")


def fixed_registers(sig: dict) -> int:
    return 1 + len(sig["params"]) + (1 if sig["flags"] & (0x01 | 0x04) else 0)


def rule_registers(lines, fixed):
    names: dict[int, int] = {}
    out, hit = [], False
    for line in lines:
        head, _, rest = line.partition(" ")
        if head in REGISTER_OPS or head == "hasnext2":
            regs = [int(r) for r in rest.split()]
            new = [r if r < fixed else names.setdefault(r, fixed + len(names)) for r in regs]
            hit = hit or new != regs
            line = " ".join([head, *map(str, new)])
        out.append(line)
    return out, hit


STATIC_TRAITS: dict[str, set[str]] = {}
CLASS_OBJECT_TRAITS = {"prototype", "length", "constructor", "hasOwnProperty", "isPrototypeOf",
                       "propertyIsEnumerable", "setPropertyIsEnumerable", "toString", "toLocaleString", "valueOf"}
LOOKUPS = ("findpropstrict", "findproperty", "getlex")
SCOPE_OPS = ("pushscope", "pushwith", "popscope", "getscopeobject", "getouterscope", "newfunction", "newclass",
             "newcatch", "newactivation", "dxns", "dxnslate")


def static_traits(blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> dict[str, set[str]]:
    out: dict[str, set[str]] = {}
    for data in blocks:
        abc = Abc(data, ns_aliases)
        for i in range(len(abc.instances)):
            out.setdefault(abc.class_name(i), set()).update(abc.mn(t["name"]) for t in abc.classes[i]["traits"])
    return out


def static_method_class(key: str) -> str | None:
    if "/s/" not in key or key.startswith("script ") or "/fn" in key.split("/s/", 1)[1]:
        return None
    return key.split("/s/", 1)[0]


def rule_static_prologue(lines, exceptions, cls):
    if cls is None or cls not in STATIC_TRAITS or lines[:2] != ["getlocal 0", "pushscope"]:
        return (lines, exceptions), False
    if 1 in branch_targets(lines, exceptions):
        return (lines, exceptions), False
    statics = STATIC_TRAITS[cls]
    static_locals = {name.rsplit("::", 1)[-1] for name in statics}
    for line in lines[2:]:
        head, _, operand = line.partition(" ")
        if head in SCOPE_OPS:
            return (lines, exceptions), False
        if head in LOOKUPS:
            name = operand.split(" ")[0]
            local = name.rsplit("::", 1)[-1]
            if name.startswith("rt::") or local in CLASS_OBJECT_TRAITS:
                return (lines, exceptions), False
            if (name in statics) if is_qname(name) else (local in static_locals):
                return (lines, exceptions), False
    return _rebuild(lines, exceptions, {0: None, 1: None}), True


INERT_CLASSES: set[str] = set()


def class_qname(cls: str) -> str:
    pkg, _, local = cls.rpartition(".")
    return f"pkg:{pkg}::{local}"


def cinit_is_inert(lines: list[str], statics: set[str], slots: set[str]) -> bool:
    static_locals = {n.rsplit("::", 1)[-1] for n in statics}
    stack: list[str] = []
    scoped = False
    for line in lines:
        head, _, rest = line.partition(" ")
        args = rest.split(" ") if rest else []
        try:
            if head == "returnvoid":
                return True
            if head == "getlocal" and args == ["0"]:
                stack.append("C")
            elif head == "pushscope":
                scoped = scoped or stack.pop() == "C"
            elif head in ("findproperty", "findpropstrict"):
                stack.append("C" if scoped and args[0].rsplit("::", 1)[-1] in static_locals else "v")
            elif head in ("getlex", "pushstring", "pushnull", "pushbyte", "pushint", "pushtrue", "pushfalse"):
                stack.append("v")
            elif head == "swap":
                stack[-1], stack[-2] = stack[-2], stack[-1]
            elif head == "initproperty" and is_qname(args[0]):
                value, obj = stack.pop(), stack.pop()
                if value == "C" or (obj == "C" and args[0] not in slots):
                    return False
            elif head in ("constructprop", "construct"):
                n = int(args[-1])
                taken = [stack.pop() for _ in range(n + 1)]
                if "C" in taken:
                    return False
                stack.append("v")
            else:
                return False
        except IndexError:
            return False
    return False


def inert_classes(blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> set[str]:
    out = set()
    for data in blocks:
        abc = Abc(data, ns_aliases)
        for i in range(len(abc.instances)):
            traits = abc.classes[i]["traits"]
            statics = {abc.mn(t["name"]) for t in traits}
            slots = {abc.mn(t["name"]) for t in traits if t["kind"] in (0, 6)}
            if cinit_is_inert(normalize(abc, abc.classes[i]["cinit"], None)["code"] or [], statics, slots):
                out.add(abc.class_name(i))
    return out


def rule_static_self(lines, exceptions, cls):
    if cls is None or cls not in INERT_CLASSES:
        return (lines, exceptions), False
    q = class_qname(cls)
    if q in SHADOWED or "setlocal 0" in lines:
        return (lines, exceptions), False
    changed = {i: "getlocal 0" for i, line in enumerate(lines) if line == f"getlex {q}"}
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def prologue_reason(key: str, orig_code: list[str], comp_code: list[str]) -> str | None:
    head = ["getlocal 0", "pushscope"]
    if comp_code[:2] != head or orig_code[:2] == head:
        return None
    cls = static_method_class(key)
    if cls is None:
        return "not a static method: instance, closure or script code, where this is not the class object"
    (lines, _), dropped = rule_static_prologue(comp_code, [], cls)
    if dropped:
        return "prologue proven harmless; the method differs later"
    for line in comp_code[2:]:
        if line.partition(" ")[0] in SCOPE_OPS:
            return "uses another scope operation"
    return "a lookup could be answered by the class object (static trait or class-object trait)"


def canonical(lines: list[str], exceptions: list[str], ret: str = "*",
              fixed: int | None = None, static_class: str | None = None) -> tuple[list[str], list[str], set[str]]:
    applied = set()
    (lines, exceptions), hit = rule_static_prologue(lines, exceptions, static_class)
    if hit:
        applied.add("static-prologue")
    (lines, exceptions), hit = rule_static_self(lines, exceptions, static_class)
    if hit:
        applied.add("static-self")
    for _ in range(8):
        before = lines
        for name, rule in EQUIVALENCES:
            if rule is rule_return_convert:
                (lines, exceptions), hit = rule(lines, exceptions, ret)
            else:
                (lines, exceptions), hit = rule(lines, exceptions)
            if hit:
                applied.add(name)
        if lines == before:
            break
    if fixed is not None:
        lines, hit = rule_registers(lines, fixed)
        if hit:
            applied.add("registers")
    return lines, exceptions, applied


def method_keys(abc: Abc, aliases: dict[str, str] | None = None) -> dict[str, int]:
    keys: dict[str, int] = {}

    def add(key: str, method: int) -> None:
        n, base = 1, key
        while key in keys:
            n += 1
            key = f"{base}#{n}"
        keys[key] = method

    def trait_name(t: dict) -> str:
        m = abc.multinames[t["name"]]
        local = abc.string(m[2]) if m and m[0] in (0x07, 0x0D) else abc.mn(t["name"])
        local = aliases.get(local, local) if aliases else local
        ns = abc.ns(m[1]) if m and m[0] in (0x07, 0x0D) else ""
        return f"{local}" if ns.startswith(("pkg:", "private", "protected", "staticprotected", "internal")) \
            else f"{ns}::{local}"

    for i, inst in enumerate(abc.instances):
        cls = abc.class_name(i)
        add(f"{cls}/iinit", inst["iinit"])
        add(f"{cls}/cinit", abc.classes[i]["cinit"])
        for side, traits in (("i", inst["traits"]), ("s", abc.classes[i]["traits"])):
            for t in traits:
                if t["kind"] in (1, 2, 3):
                    add(f"{cls}/{side}/{TRAIT_KINDS[t['kind']]} {trait_name(t)}", t["method"])
    for script in abc.scripts:
        named = [t for t in script["traits"]]
        head = trait_name(named[0]) if named else "?"
        if named and named[0]["kind"] == 4:
            head = abc.class_name(named[0]["class"])
        add(f"script {head}/init", script["init"])
        for t in script["traits"]:
            if t["kind"] in (1, 2, 3, 5):
                add(f"script {head}/{TRAIT_KINDS[t['kind']]} {trait_name(t)}", t["method"])
    return keys


def collect(blocks: list[bytes], aliases: dict[str, str] | None = None,
            ns_aliases: dict[str, str] | None = None, cache: bool = False) -> dict[str, dict]:
    out: dict[str, dict] = {}
    tag = _collect_tag(aliases, ns_aliases) if cache and not os.environ.get("BH_NO_COLLECT_CACHE") else None
    for data in blocks:
        pairs = _block_cached(data, aliases, ns_aliases, tag) if tag else None
        if pairs is not None and not any(k in out for k, _ in pairs):
            out.update(pairs)
            continue
        abc = Abc(data, ns_aliases)
        pre = _normalize_all(data, len(abc.methods), aliases, ns_aliases)
        pending = list(method_keys(abc, aliases).items())
        while pending:
            key, method = pending.pop()
            while key in out:
                key += "+"
            norm = pre.pop(method, None) if pre else None
            if norm is None:
                norm = normalize(abc, method, aliases)
            out[key] = norm
            pending.extend((f"{key}/fn{n}", m) for n, m in enumerate(norm["closures"]))
    return out


_PARALLEL_MIN = 4000
_WORKERS = 6
_WORKER_ABC: tuple | None = None


def _normalize_slice(data: bytes, aliases: dict[str, str] | None, ns_aliases: dict[str, str] | None,
                     methods: range) -> dict[int, dict]:
    global _WORKER_ABC
    if _WORKER_ABC is None or _WORKER_ABC[0] != hashlib.sha1(data).digest():
        _WORKER_ABC = (hashlib.sha1(data).digest(), Abc(data, ns_aliases))
    abc = _WORKER_ABC[1]
    return {m: normalize(abc, m, aliases) for m in methods}


def _normalize_all(data: bytes, count: int, aliases: dict[str, str] | None,
                   ns_aliases: dict[str, str] | None) -> dict[int, dict] | None:
    if count < _PARALLEL_MIN or os.environ.get("BH_NO_PARALLEL_COLLECT"):
        return None
    from concurrent.futures import ProcessPoolExecutor
    workers = min(_WORKERS, os.cpu_count() or 1)
    if workers < 2:
        return None
    step = -(-count // workers)
    out: dict[int, dict] = {}
    try:
        with ProcessPoolExecutor(workers) as pool:
            for part in pool.map(_normalize_slice, [data] * workers, [aliases] * workers, [ns_aliases] * workers,
                                 [range(i, min(i + step, count)) for i in range(0, count, step)]):
                out.update(part)
    except (OSError, RuntimeError, AbcError):
        return None
    return out


_COLLECT_DIR = (Path(__file__).resolve().parents[1] / "build" / "cache" /
                f"collect-{hashlib.sha1(Path(__file__).read_bytes()).hexdigest()[:12]}")
_COLLECT_DAYS = 5
_COLLECT_SWEPT = False


def _collect_tag(aliases: dict[str, str] | None, ns_aliases: dict[str, str] | None) -> str:
    return hashlib.sha1(repr((sorted(aliases.items()) if aliases else None,
                              sorted(ns_aliases.items()) if ns_aliases else None)).encode(
        "utf-8", "surrogateescape")).hexdigest()[:16]


def _sweep_collect_cache() -> None:
    import shutil
    import time
    global _COLLECT_SWEPT
    _COLLECT_SWEPT = True
    _COLLECT_DIR.mkdir(parents=True, exist_ok=True)
    root = _COLLECT_DIR.parent
    for old in root.glob("collect-*"):
        if old != _COLLECT_DIR and old.is_dir():
            shutil.rmtree(old, ignore_errors=True)
    stamp = _COLLECT_DIR / ".swept"
    now = time.time()
    if stamp.exists() and now - stamp.stat().st_mtime < 86400:
        return
    for f in _COLLECT_DIR.glob("*.pickle"):
        try:
            if now - f.stat().st_mtime > _COLLECT_DAYS * 86400:
                f.unlink()
        except OSError:
            pass
    stamp.touch()


def _block_cached(data: bytes, aliases: dict[str, str] | None, ns_aliases: dict[str, str] | None,
                  tag: str) -> list[tuple[str, dict]]:
    import pickle
    if not _COLLECT_SWEPT:
        try:
            _sweep_collect_cache()
        except OSError:
            pass
    path = _COLLECT_DIR / f"{hashlib.sha1(data).hexdigest()}-{tag}.pickle"
    try:
        pairs = pickle.loads(path.read_bytes())
        os.utime(path)
        return pairs
    except (OSError, pickle.UnpicklingError, EOFError):
        pass
    one = collect([data], aliases, ns_aliases)
    pairs = list(one.items())
    try:
        tmp = path.with_suffix(f".tmp{os.getpid()}")
        tmp.write_bytes(pickle.dumps(pairs, protocol=pickle.HIGHEST_PROTOCOL))
        os.replace(tmp, path)
    except OSError:
        pass
    return pairs


def shape(line: str) -> str:
    name, _, rest = line.partition(" ")
    if not rest:
        return name
    if name in ("getlocal", "setlocal", "kill", "inclocal", "declocal", "inclocal_i", "declocal_i"):
        return f"{name} r"
    if name.startswith(("push",)) and name not in ("pushnamespace",):
        return f"{name} v"
    if name.startswith(("if", "jump", "lookupswitch")):
        return f"{name} L"
    rest = re.sub(r"\{[^}]*\}::\S+", "{set}::N", rest)
    rest = re.sub(r"\b(pkg|internal|protected|staticprotected|explicit|ns|private|rt)(:\S*?)?::\S+", r"\1::N", rest)
    rest = re.sub(r"'.*'", "'S'", rest)
    return f"{name} {rest}"[:60]


def prepare(original_blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> None:
    SHADOWED.clear()
    SHADOWED.update(shadowed_names(original_blocks, ns_aliases))
    CONSTS.clear()
    CONSTS.update(const_names(original_blocks, ns_aliases))
    STATIC_TRAITS.clear()
    STATIC_TRAITS.update(static_traits(original_blocks, ns_aliases))
    INERT_CLASSES.clear()
    INERT_CLASSES.update(inert_classes(original_blocks, ns_aliases))
    if _CANONICAL is not None:
        _CANONICAL.clear()


_CANONICAL: dict[tuple[int, str | None], tuple[dict, tuple[list[str], list[str], set[str]]]] | None = None


def enable_canonical_cache() -> None:
    global _CANONICAL
    _CANONICAL = {}


def canonical_original(orig: dict, cls: str | None) -> tuple[list[str], list[str], set[str]]:
    hit = _CANONICAL.get((id(orig), cls)) if _CANONICAL is not None else None
    if hit is not None and hit[0] is orig:
        return hit[1]
    result = canonical(orig["code"] or [], orig["exceptions"], orig["sig"]["ret"], fixed_registers(orig["sig"]), cls)
    if _CANONICAL is not None:
        _CANONICAL[(id(orig), cls)] = (orig, result)
    return result


_MEMO: dict[str, list[str]] | None = None
_MEMO_DIRTY = False
_MEMO_PATH = (Path(__file__).resolve().parents[1] / "build" / "cache" /
              f"compare-{hashlib.sha1(Path(__file__).read_bytes()).hexdigest()[:12]}.json")


def _memo() -> dict[str, list[str]]:
    global _MEMO
    if _MEMO is None:
        _MEMO = {}
        if not os.environ.get("BH_NO_COMPARE_CACHE") and _MEMO_PATH.exists():
            try:
                _MEMO = json.loads(_MEMO_PATH.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                _MEMO = {}
    return _MEMO


def save_memo() -> None:
    global _MEMO_DIRTY
    if _MEMO_DIRTY and _MEMO is not None and not os.environ.get("BH_NO_COMPARE_CACHE"):
        _MEMO_PATH.parent.mkdir(parents=True, exist_ok=True)
        tmp = _MEMO_PATH.with_suffix(f".tmp{os.getpid()}")
        tmp.write_text(json.dumps(_MEMO), encoding="utf-8")
        os.replace(tmp, _MEMO_PATH)
        _MEMO_DIRTY = False


_CONTEXT: tuple[tuple[int, ...], str] | None = None


def _context(force: bool = False) -> str:
    global _CONTEXT
    sizes = (len(SHADOWED), len(CONSTS), len(STATIC_TRAITS), len(INERT_CLASSES))
    if force or _CONTEXT is None or _CONTEXT[0] != sizes:
        parts = [sorted(SHADOWED), sorted(CONSTS), sorted((k, sorted(v)) for k, v in STATIC_TRAITS.items()),
                 sorted(INERT_CLASSES)]
        _CONTEXT = (sizes, hashlib.sha1(repr(parts).encode("utf-8", "surrogateescape")).hexdigest())
    return _CONTEXT[1]


def rules_changed() -> None:
    _context(force=True)
    if _CANONICAL is not None:
        _CANONICAL.clear()


def compare_one(orig: dict, comp: dict, key: str = "") -> tuple[str, str]:
    code_o = orig["code"] or []
    code_c = comp["code"] or []
    if code_o == code_c and orig["exceptions"] == comp["exceptions"] and orig["sig"] == comp["sig"]:
        return "equal", ""
    digest = hashlib.sha1(repr((code_o, orig["exceptions"], orig["sig"], code_c, comp["exceptions"], comp["sig"],
                                static_method_class(key), _context())).encode("utf-8", "surrogateescape")).hexdigest()
    memo = _memo()
    hit = memo.get(digest)
    if hit is not None:
        return hit[0], hit[1]
    result = _compare_one(orig, comp, key)
    global _MEMO_DIRTY
    memo[digest] = list(result)
    _MEMO_DIRTY = True
    return result


def _compare_one(orig: dict, comp: dict, key: str = "") -> tuple[str, str]:
    code_c = comp["code"] or []
    if any(line.startswith("pushstring 'BH_SPLICE") for line in code_c):
        return "splice", "BH_SPLICE stub"
    if orig["sig"] != comp["sig"]:
        for field in ("params", "ret", "flags", "optional"):
            if orig["sig"][field] != comp["sig"][field]:
                return "signature", f"signature {field}"
    code_o = orig["code"] or []
    if code_o == code_c and orig["exceptions"] == comp["exceptions"]:
        return "equal", ""
    cls = static_method_class(key)
    code_o, exc_o, rules_o = canonical_original(orig, cls)
    code_c, exc_c, rules_c = canonical(code_c, comp["exceptions"], comp["sig"]["ret"], fixed_registers(comp["sig"]), cls)
    if code_o == code_c and exc_o == exc_c:
        return "equivalent", " + ".join(sorted(rules_o | rules_c))
    for a, b in zip(code_o, code_c):
        if a != b:
            sa, sb = shape(a), shape(b)
            if sa == sb:
                return "code", f"operand: {sa}"
            return "code", f"{sa} | {sb}"
    if len(code_o) != len(code_c):
        return "code", "length: " + ("original longer" if len(code_o) > len(code_c) else "compiled longer")
    return "code", "exceptions"


def compare(original: dict[str, dict], compiled: dict[str, dict], dropped: set[str] = frozenset()) -> dict:
    _context(force=True)
    methods = {}
    for key, orig in original.items():
        if key in dropped and (key not in compiled or compare_one(orig, compiled[key], key)[0] != "equal"):
            methods[key] = {"status": "splice", "cause": "script init dropped by as3_fixups.py"}
            continue
        if key not in compiled:
            methods[key] = {"status": "missing", "cause": "no compiled method with this key"}
            continue
        if any(line.startswith("pushstring 'BH_SPLICE") for line in compiled[key]["code"] or []):
            methods[key] = {"status": "splice", "cause": "BH_SPLICE stub"}
            continue
        status, cause = compare_one(orig, compiled[key], key)
        entry = {"status": status, "cause": cause}
        if status == "equal" and orig["meta"] != compiled[key]["meta"]:
            entry["meta"] = {"original": orig["meta"], "compiled": compiled[key]["meta"]}
        if status == "code":
            entry["lines"] = [len(orig["code"] or []), len(compiled[key]["code"] or [])]
            reason = prologue_reason(key, orig["code"] or [], compiled[key]["code"] or [])
            if reason:
                entry["prologue"] = reason
        methods[key] = entry
    for key, entry in methods.items():
        parent = key
        while entry["status"] == "missing" and re.search(r"/fn\d+$", parent):
            parent = re.sub(r"/fn\d+$", "", parent)
            if methods.get(parent, {}).get("status") == "splice":
                entry.update(status="splice", cause=f"closure of BH_SPLICE stub {parent}")
    for key in compiled:
        if key not in original:
            methods[key] = {"status": "extra", "cause": "no original method with this key"}
    statuses = Counter(m["status"] for m in methods.values())
    causes = Counter(f"{m['status']}: {m['cause']}" for m in methods.values()
                     if m["status"] not in ("equal", "equivalent"))
    rules = Counter(r for m in methods.values() if m["status"] == "equivalent" for r in m["cause"].split(" + "))
    save_memo()
    return {
        "totals": {"original": len(original), "compiled": len(compiled), **dict(sorted(statuses.items()))},
        "equal_with_stack_meta_diff": sum(1 for m in methods.values() if "meta" in m),
        "causes": [{"cause": c, "count": n} for c, n in causes.most_common()],
        "equivalence_rules": dict(rules.most_common()),
        "prologue_left": dict(Counter(m["prologue"] for m in methods.values() if "prologue" in m).most_common()),
        "methods": dict(sorted(methods.items())),
    }


FFDEC_BASE_VERSION = "10.11"


def ffdec_work(version: str | None = None) -> Path:
    work = ROOT / "build" / "as3"
    return work if version in (None, FFDEC_BASE_VERSION) else work / version / "ffdec"


def base_swf(version: str | None = None) -> Path:
    work = ffdec_work(version)
    aliased = work / "aliased.swf"
    return aliased if aliased.exists() else work / "renamed.swf"


def swf_blocks(path: Path) -> list[bytes]:
    data = path.read_bytes()
    if data[:2] == b"PK":
        with zipfile.ZipFile(io.BytesIO(data)) as swc:
            data = swc.read("library.swf")
    return [abc for _, abc in swf_abc_blocks(data)]


def load_class_names(path: Path | None) -> dict[str, str]:
    if path is None or not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    names = {}
    for block in data.get("blocks", []):
        for row in block.get("classes", []):
            if row[1] != row[2]:
                names[row[1]] = row[2]
    return names


def load_dropped(path: Path | None) -> set[str]:
    if path is None or not path.exists():
        return set()
    report = json.loads(path.read_text(encoding="utf-8"))
    return {f"script {item['class']}/init" for item in report.get("splices", [])
            if item.get("method") == "<script init>"}


def load_aliases(path: Path | None) -> dict[str, str]:
    if path is None or not path.exists():
        return {}
    report = json.loads(path.read_text(encoding="utf-8"))
    aliases = {}
    for item in report.get("renames", []):
        new, old = item.get("source_name"), item.get("member")
        if new and old:
            aliases[new] = old
    return aliases


def markdown(report: dict, top: int = 40) -> str:
    t = report["totals"]
    lines = [
        "# AS3 vs original: per-method comparison", "",
        f"Original methods: {t['original']}; compiled: {t['compiled']}.", "",
        "| Status | Methods |", "| --- | --- |",
    ]
    for status in ("equal", "equivalent", "splice", "signature", "code", "missing", "extra"):
        lines.append(f"| {status} | {t.get(status, 0)} |")
    lines += ["", f"Equal methods whose max_stack/locals/scope depth differ: {report['equal_with_stack_meta_diff']}.", "",
              f"## Top {top} causes", "", "| Count | Cause |", "| --- | --- |"]
    for item in report["causes"][:top]:
        cause = item["cause"].replace("|", "\\|")
        lines.append(f"| {item['count']} | `{cause}` |")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--version", default="10.11")
    parser.add_argument("--compiled", type=Path, help="SWC or SWF (default build/as3/<ver>/game.swc)")
    parser.add_argument("--original", type=Path, help="SWF (default build/as3/aliased.swf, else build/as3/renamed.swf)")
    parser.add_argument("--fixups", type=Path, help="as3_fixups.py report (default build/as3/<ver>/as3-fixups.json)")
    parser.add_argument("--map", type=Path, help="structural name map (default client/symbols/<ver>.json)")
    parser.add_argument("--report", type=Path, help="JSON output (default build/as3/<ver>/method-compare.json)")
    parser.add_argument("--markdown", type=Path)
    parser.add_argument("--exceptions", type=Path, help="JSON list of method keys allowed to differ")
    parser.add_argument("--require-equal", action="store_true")
    args = parser.parse_args(argv)

    out_dir = ROOT / "build" / "as3" / args.version
    compiled_path = args.compiled or out_dir / "game.swc"
    original_path = args.original or base_swf(args.version)
    for path in (compiled_path, original_path):
        if not path.exists():
            print(f"missing {path}: run tools/export_as3.py and tools/compile_as3.py first", file=sys.stderr)
            return 2
    fixups = args.fixups or out_dir / "as3-fixups.json"
    aliases = load_aliases(fixups)
    ns_aliases = load_class_names(args.map or ROOT / "client" / "symbols" / f"{args.version}.json")
    original_blocks = swf_blocks(original_path)
    prepare(original_blocks, ns_aliases)
    original = collect(original_blocks, ns_aliases=ns_aliases)
    compiled = collect(swf_blocks(compiled_path), aliases, ns_aliases)
    report = compare(original, compiled, load_dropped(fixups))
    report["inputs"] = {"original": str(original_path), "compiled": str(compiled_path), "aliases": aliases}
    path = args.report or out_dir / "method-compare.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    if args.markdown:
        args.markdown.write_text(markdown(report), encoding="utf-8")
    t = report["totals"]
    print(f"{t['original']} original methods, {t['compiled']} compiled: "
          + ", ".join(f"{s} {t.get(s, 0)}" for s in ("equal", "equivalent", "splice", "signature", "code", "missing", "extra"))
          + f" -> {path}")
    for item in report["causes"][:10]:
        print(f"  {item['count']:6d}  {item['cause']}")
    if args.require_equal:
        allowed = set(json.loads(args.exceptions.read_text(encoding="utf-8"))) if args.exceptions else set()
        bad = [k for k, m in report["methods"].items()
               if m["status"] not in ("equal", "equivalent") and k not in allowed]
        if bad:
            print(f"{len(bad)} methods differ and are not listed as exceptions", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
