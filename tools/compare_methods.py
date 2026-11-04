"""compare every method body of the compiled AS3 with the original bytecode.

    python tools/compare_methods.py [--version 10.11] [--compiled build/as3/<ver>/game.swc]
                                    [--original build/as3/renamed.swf] [--markdown PATH]

both sides are parsed straight from their ABC blocks: the compiled side is the SWC's ``library.swf`` (or any SWF),
the original defaults to FFDec's renamed SWF from ``tools/export_as3.py`` (the game with only its names changed, so a
match against it is a match against the original modulo that 1:1 map).

methods are matched by key, not by index:

- ``pkg.Class/iinit``, ``pkg.Class/cinit``;
- ``pkg.Class/i/<kind> <name>`` and ``pkg.Class/s/<kind> <name>`` for instance
  and static traits (kind is method, getter or setter);
- ``script <first trait>/init`` and ``script <first trait>/function <name>``;
- ``<parent key>/fn<n>`` for the n-th ``newfunction`` closure in a body.

bodies are normalized first: names from the constant pool (private namespaces as ``private``), branch targets as
instruction numbers, ``getlocal0``-``3``/``setlocal0``-``3`` in general form, ``debug*``, ``nop``, ``label`` and
``bkpt*`` dropped. the signature is part of equality; ``max_stack``, ``local_count`` and scope depths are not.

status per original method: ``equal``, ``equivalent`` (equal after the proven rewrites in ``EQUIVALENCES``),
``splice`` (a ``BH_SPLICE`` stub from ``tools/as3_fixups.py``), ``signature``, ``code`` or ``missing``; compiled
methods with no original are ``extra``. a ``code`` difference's cause is its first differing instruction pair with
operands collapsed. renames by ``as3_fixups.py`` are mapped back through ``--fixups``.

writes ``build/as3/<ver>/method-compare.json``; ``--require-equal`` exits 1 unless every method is equal or listed
in ``--exceptions``.
"""

from __future__ import annotations

import argparse
from collections import Counter
import io
import json
import math
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
            interfaces = [s.u30() for _ in range(s.u30())]
            self.instances.append({"name": name, "super": sup, "flags": flags, "interfaces": interfaces,
                                   "iinit": s.u30(), "traits": _traits(s)})
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

    def class_name(self, index: int, aliases: dict[str, str] | None = None) -> str:
        m = self.multinames[self.instances[index]["name"]]
        pkg = self.string(self.namespaces[m[1]][1]) if self.namespaces[m[1]][1] else ""
        local = self.string(m[2])
        local = aliases.get(local, local) if aliases else local
        return f"{pkg}.{local}" if pkg else local

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
                    parts.append(abc.class_name(a, aliases))
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


def exception_targets(exceptions: list[str]) -> set[int]:
    targets = set()
    for e in exceptions:
        labels = [int(n) for n in LABEL.findall(e)]
        if len(labels) >= 3:
            targets.add(labels[2])
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


def rule_vector_construct(lines, exceptions):
    def simple_type_arg(line: str) -> bool:
        return bool(_operand(line, "getlex") or _operand(line, "getlocal"))

    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    for i in range(len(lines) - 6):
        if (lines[i] == "getlex pkg:__AS3__.vec::Vector"
                and simple_type_arg(lines[i + 1])
                and lines[i + 2] == "applytype 1"
                and lines[i + 3] == "pushdouble 0.0"
                and lines[i + 4] == "convert_i"
                and lines[i + 5] == "pushfalse"
                and lines[i + 6] == "construct 2"
                and not targets & {i + 1, i + 2, i + 3, i + 4, i + 5, i + 6}):
            changed.update({i + 3: None, i + 4: None, i + 5: None, i + 6: "construct 0"})
    for i in range(len(lines) - 7):
        if (lines[i] == "getlex pkg:__AS3__.vec::Vector"
                and simple_type_arg(lines[i + 1])
                and lines[i + 2] == "applytype 1"
                and lines[i + 3] == "pushbyte 0"
                and lines[i + 4] == "convert_d"
                and lines[i + 5] == "convert_i"
                and lines[i + 6] == "pushfalse"
                and lines[i + 7] == "construct 2"
                and not targets & {i + 1, i + 2, i + 3, i + 4, i + 5, i + 6, i + 7}):
            changed.update({i + 3: None, i + 4: None, i + 5: None, i + 6: None, i + 7: "construct 0"})
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_null_coerce(lines, exceptions):
    def match(a, b):
        if a == "pushnull" and b == "coerce_s":
            return "pushnull", None
        t = _operand(b, "coerce") or _operand(b, "astype")
        if a == "pushnull" and t and is_type(t) and t not in VALUE_TYPES:
            return "pushnull", None
    return _pairs(lines, exceptions, match)


def rule_coerce_any(lines, exceptions):
    changed = {i: None for i, line in enumerate(lines) if line == "coerce_a"}
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_object_coerce_after_reference_cast(lines, exceptions):
    def match(a, b):
        cast = _operand(a, "astype") or _operand(a, "coerce")
        if cast and is_type(cast) and cast not in VALUE_TYPES and b == "coerce pkg:::Object":
            return a, None
    return _pairs(lines, exceptions, match)


NEGATED_BRANCH = {"iffalse": "iftrue", "iftrue": "iffalse"}
COMPARE_BRANCH = {
    ("equals", "iffalse"): "ifne",
    ("equals", "iftrue"): "ifeq",
    ("strictequals", "iffalse"): "ifstrictne",
    ("strictequals", "iftrue"): "ifstricteq",
    ("lessthan", "iffalse"): "ifnlt",
    ("lessthan", "iftrue"): "iflt",
    ("lessequals", "iffalse"): "ifnle",
    ("lessequals", "iftrue"): "ifle",
    ("greaterthan", "iffalse"): "ifngt",
    ("greaterthan", "iftrue"): "ifgt",
    ("greaterequals", "iffalse"): "ifnge",
    ("greaterequals", "iftrue"): "ifge",
}


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


NON_NAN_BRANCH_CANONICAL = {
    "ifnle": "ifgt",
    "ifnlt": "ifge",
    "ifnge": "iflt",
    "ifngt": "ifle",
}


def _non_nan_branch_inputs(lines: list[str], param_types: list[str] | None,
                           slot_context: tuple[str, str] | None) -> set[int] | None:
    max_reg = len(param_types or [])
    for line in lines:
        for match in re.finditer(r"\b(?:getlocal|setlocal|kill|inclocal|declocal|inclocal_i|declocal_i) (\d+)", line):
            max_reg = max(max_reg, int(match.group(1)))
    entry_locals = [False] * (max_reg + 1)
    for register, typ in enumerate(param_types or [], 1):
        if register < len(entry_locals):
            entry_locals[register] = typ in {"pkg:::int", "pkg:::uint"}

    State = tuple[tuple[bool, ...], tuple[bool, ...]]
    states: dict[int, State] = {0: ((), tuple(entry_locals))} if lines else {}
    work = [0] if lines else []
    invalid = False

    def pop(stack: list[bool], count: int = 1) -> list[bool]:
        nonlocal invalid
        if len(stack) < count:
            invalid = True
            stack.clear()
            return []
        values = stack[-count:]
        del stack[-count:]
        return values

    def typed_non_nan(line: str) -> bool:
        return _typed_read(line, slot_context) in {"pkg:::int", "pkg:::uint"}

    def merge(index: int, stack: list[bool], locals_: list[bool]) -> None:
        nonlocal invalid
        if index < 0 or index >= len(lines):
            return
        incoming: State = (tuple(stack), tuple(locals_))
        current = states.get(index)
        if current is None:
            states[index] = incoming
            work.append(index)
            return
        if len(current[0]) != len(incoming[0]) or len(current[1]) != len(incoming[1]):
            invalid = True
            return
        joined: State = (
            tuple(a and b for a, b in zip(current[0], incoming[0])),
            tuple(a and b for a, b in zip(current[1], incoming[1])),
        )
        if joined != current:
            states[index] = joined
            work.append(index)

    while work and not invalid:
        i = work.pop()
        stack = list(states[i][0])
        locals_ = list(states[i][1])
        line = lines[i]
        head, _, rest = line.partition(" ")

        if head == "getlocal" and rest.isdigit():
            stack.append(locals_[int(rest)] if int(rest) < len(locals_) else False)
        elif head == "setlocal" and rest.isdigit():
            values = pop(stack)
            if int(rest) < len(locals_):
                locals_[int(rest)] = values[0] if values else False
        elif head == "kill" and rest.isdigit():
            if int(rest) < len(locals_):
                locals_[int(rest)] = False
        elif head in {"inclocal_i", "declocal_i"} and rest.isdigit():
            if int(rest) < len(locals_):
                locals_[int(rest)] = True
        elif head in {"inclocal", "declocal"} and rest.isdigit():
            if int(rest) < len(locals_):
                locals_[int(rest)] = False
        elif head == "hasnext2":
            registers = [int(value) for value in rest.split() if value.isdigit()]
            if len(registers) != 2:
                invalid = True
            else:
                for register in registers:
                    if register < len(locals_):
                        locals_[register] = False
                stack.append(False)
        elif head in {"pushbyte", "pushshort", "pushint", "pushuint"}:
            stack.append(True)
        elif head == "pushdouble":
            try:
                stack.append(math.isfinite(float(rest)))
            except ValueError:
                stack.append(False)
        elif head in STACK_PUSH_OPS:
            stack.append(False)
        elif head == "getlex":
            stack.append(typed_non_nan(line))
        elif head in {"findproperty", "findpropstrict", "getglobalscope", "getscopeobject",
                      "getouterscope", "newfunction", "newactivation"}:
            stack.append(False)
        elif head == "getproperty":
            runtime_names = 2 if rest == "rt::[]" else 1 if rest.startswith("{") and rest.endswith("}::[]") else 0
            pop(stack, runtime_names + 1)
            stack.append(typed_non_nan(line))
        elif head == "dup":
            stack.append(stack[-1] if stack else False)
        elif head == "swap":
            if len(stack) < 2:
                invalid = True
            else:
                stack[-1], stack[-2] = stack[-2], stack[-1]
        elif head in {"convert_i", "convert_u", "coerce_i", "coerce_u", "negate_i",
                      "increment_i", "decrement_i", "bitnot"}:
            if stack:
                stack[-1] = True
            else:
                invalid = True
        elif head in {"convert_d", "coerce_d"}:
            if not stack:
                invalid = True
        elif head in {"add_i", "subtract_i", "multiply_i", "lshift", "rshift", "urshift",
                      "bitand", "bitor", "bitxor"}:
            pop(stack, 2)
            stack.append(True)
        elif head in {"add", "subtract", "multiply", "divide", "modulo", "equals", "strictequals",
                      "lessthan", "lessequals", "greaterthan", "greaterequals", "instanceof", "istype",
                      "istypelate", "in"}:
            pop(stack, 2)
            stack.append(False)
        elif head in {"callproperty", "callproplex", "callpropvoid", "constructprop"}:
            name, _, argc_text = rest.rpartition(" ")
            if not argc_text.isdigit():
                invalid = True
            else:
                pop(stack, int(argc_text) + 1)
                if head not in {"callpropvoid"}:
                    stack.append(head != "constructprop" and METHOD_RETURNS.get(name) in {"pkg:::int", "pkg:::uint"})
        elif head == "construct" and rest.isdigit():
            pop(stack, int(rest) + 1)
            stack.append(False)
        elif head in {"newarray", "newobject"} and rest.isdigit():
            pop(stack, int(rest) if head == "newarray" else int(rest) * 2)
            stack.append(False)
        elif head in NON_NAN_BRANCH_CANONICAL or head in {"ifgt", "ifge", "iflt", "ifle"}:
            pop(stack, 2)
        elif head in NUMERIC_BRANCHES:
            pop(stack, 2)
        elif head in {"iftrue", "iffalse", "lookupswitch", "returnvalue", "throw", "pop", "pushscope"}:
            pop(stack)
        elif head in {"jump", "returnvoid", "popscope"}:
            pass
        else:
            delta = _stack_delta(line)
            if delta is None:
                invalid = True
            elif delta < 0:
                pop(stack, -delta)
                stack = [False] * len(stack)
            elif delta > 0:
                stack.extend([False] * delta)
                stack = [False] * len(stack)
            else:
                stack = [False] * len(stack)

        targets = [int(value) for value in LABEL.findall(line)]
        if head == "jump":
            successors = targets
        elif head.startswith("if") or head == "lookupswitch":
            successors = targets + ([i + 1] if i + 1 < len(lines) else [])
        elif head in {"returnvalue", "returnvoid", "throw"}:
            successors = []
        else:
            successors = [i + 1] if i + 1 < len(lines) else []
        for successor in successors:
            merge(successor, stack, locals_)

    if invalid:
        return None
    return {
        i for i, (stack, _locals) in states.items()
        if lines[i].partition(" ")[0] in (set(NON_NAN_BRANCH_CANONICAL) | {"ifgt", "ifge", "iflt", "ifle"})
        and len(stack) >= 2 and all(stack[-2:])
    }


def rule_non_nan_relational_branch(lines, exceptions, param_types=None, slot_context=None):
    if exceptions:
        return (lines, exceptions), False
    proven = _non_nan_branch_inputs(lines, param_types, slot_context)
    if proven is None:
        return (lines, exceptions), False
    changed = {}
    for i in proven:
        head, _, label = lines[i].partition(" ")
        if head in NON_NAN_BRANCH_CANONICAL:
            changed[i] = f"{NON_NAN_BRANCH_CANONICAL[head]} {label}"
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_double_not_bool_convert(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    for i in range(len(lines) - 2):
        if (lines[i:i + 3] == ["not", "not", "convert_b"]
                and not ({i + 1, i + 2} & targets)):
            changed[i] = "convert_b"
            changed[i + 1] = None
            changed[i + 2] = None
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_const_uint(lines, exceptions):
    def match(a, b):
        head, _, n = a.partition(" ")
        if head in ("pushbyte", "pushshort", "pushint") and b == "convert_u" and n.lstrip("-").isdigit() and int(n) >= 0:
            return a, None
    return _pairs(lines, exceptions, match)


def rule_integer_literal_before_convert_d(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    for i in range(len(lines) - 1):
        head, _, n = lines[i].partition(" ")
        if (head in ("pushbyte", "pushshort", "pushint") and lines[i + 1] == "convert_d" and i + 1 in targets
                and n.lstrip("-").isdigit() and abs(int(n)) < 2 ** 53):
            changed[i] = f"pushdouble {float(int(n))!r}"
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def canonical_int_atoms(lines: list[str]) -> tuple[list[str], bool]:
    out: list[str] = []
    changed = False
    for line in lines:
        head, _, value = line.partition(" ")
        if head in ("pushbyte", "pushshort", "pushint") and value.lstrip("-").isdigit():
            canonical = f"pushint {int(value)}"
        else:
            canonical = line
        changed = changed or canonical != line
        out.append(canonical)
    return out, changed


def rule_const_bool(lines, exceptions):
    def match(a, b):
        if a in ("pushtrue", "pushfalse") and b == "convert_b":
            return a, None
    return _pairs(lines, exceptions, match)


def rule_const_int(lines, exceptions):
    def match(a, b):
        head, _, n = a.partition(" ")
        if head in ("pushbyte", "pushshort", "pushint") and b == "convert_i" and n.lstrip("-").isdigit():
            return a, None
    return _pairs(lines, exceptions, match)


def rule_double_convert(lines, exceptions):
    def match(a, b):
        if a == b and (a in IDEMPOTENT or (a.startswith("coerce ") and is_type(a[7:]))):
            return a, None
    return _pairs(lines, exceptions, match)


def rule_coerce_string(lines, exceptions):
    changed = {i: "coerce_s" for i, line in enumerate(lines) if line == "coerce pkg:::String"}
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_audited_primitive_string_concat(lines, exceptions, param_types=None, slot_context=None):
    if slot_context != ("class_113", "i"):
        return (lines, exceptions), False
    primitive_regs = {
        str(register)
        for register, typ in enumerate(param_types or [], 1)
        if typ in VALUE_TYPES
    }
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    i = 0
    while i < len(lines):
        head, _, rest = lines[i].partition(" ")
        if head in {"setlocal", "kill", "inclocal", "declocal", "inclocal_i", "declocal_i"}:
            primitive_regs.discard(rest)
        if i + 6 < len(lines):
            local = lines[i + 2].partition(" ")
            region = set(range(i, i + 7))
            if (
                lines[i] == "pushstring ''"
                and lines[i + 1] == "pushstring ''"
                and local[0] == "getlocal"
                and local[2] in primitive_regs
                and lines[i + 3] == "add"
                and lines[i + 4] == "coerce_s"
                and lines[i + 5] == "add"
                and lines[i + 6] == "coerce_s"
                and not targets.intersection(region)
            ):
                changed.update({i: None, i + 5: None, i + 6: None})
                i += 7
                continue
        i += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_coerce_then_astype(lines, exceptions):
    def match(a, b):
        t = _operand(a, "coerce")
        if t and is_type(t) and t not in VALUE_TYPES and b == "astype " + t:
            return a, None
    return _pairs(lines, exceptions, match)


def rule_double_before_integer_convert(lines, exceptions):
    def match(a, b):
        if a == "convert_d" and b in ("convert_i", "convert_u"):
            return None, b
    return _pairs(lines, exceptions, match)


AUDITED_TYPED_NUMERIC_LITERAL_BOUNDARIES = {
    "class_17/i/method method_9014": (
        ("findpropstrict pkg:::var_6725",), ("setproperty pkg:::var_6725",),
    ),
    "class_269/i/method method_228": (
        ("findpropstrict pkg:::var_2789",), ("setproperty pkg:::var_2789",),
    ),
    "class_40/i/method method_2365": ((), ("convert_u", "setlocal 17")),
    "class_448/i/method method_3853": (
        ("getproperty pkg:::var_2587",), ("setproperty pkg:::x",),
    ),
    "class_511/i/method method_6250": (
        ("getproperty pkg:::var_2587",), ("setproperty pkg:::alpha",),
    ),
    "class_522/i/method OnCreateScreen": (("getlocal 1",), ("setproperty pkg:::x",)),
    "class_624/i/method method_174": (
        ("getproperty pkg:::var_2587",), ("setproperty pkg:::x",),
    ),
    "class_680/i/method method_1725": (
        (), ("convert_d", "pushnull", "callproperty pkg:::method_8905 4"),
    ),
    "class_717/s/method method_2005": (("getlocal 5",), ("setproperty pkg:::y",)),
    "class_717/s/method method_3146": (("getlocal 5",), ("setproperty pkg:::x",)),
    "class_17/i/method method_6798": (
        ("findpropstrict pkg:::var_6725",), ("setproperty pkg:::var_6725",),
    ),
    "class_289/i/method method_3834": (
        ("getlex pkg:::Math",),
        (
            "getlocal 1", "getlex pkg:::mTimeStamp", "subtract_i", "convert_u",
            "getlex pkg:::var_13885", "getlex pkg:::mTimeStamp", "subtract_i",
            "convert_u", "divide", "callproperty pkg:::min 2",
        ),
    ),
    "class_398/s/method method_5192": (
        ("getproperty {pkg:}::[]",), ("setproperty pkg:::var_6725",),
    ),
    "class_411/i/method method_1595": (
        ("getproperty pkg:::mContainer",), ("setproperty pkg:::alpha",),
    ),
    "class_462/i/method method_4579": (
        ("getproperty pkg:::var_2544",), ("setproperty pkg:::alpha",),
    ),
    "class_462/i/method method_5351": (
        ("getproperty pkg:::var_2544",), ("setproperty pkg:::alpha",),
    ),
    "class_511/i/method method_4690": (
        ("getproperty pkg:::var_2587",), ("setproperty pkg:::alpha",),
    ),
    "class_662/i/method method_2509": (
        ("iffalse L",), ("jump L", "pushdouble 0.1", "setproperty pkg:::alpha"),
    ),
    "PowerType/i/method method_8240": (
        ("returnvalue",),
        ("getlex pkg:::var_2194", "getlocal 1", "getproperty {pkg:}::[]", "bitand", "returnvalue"),
    ),
    "class_40/i/method method_4821": (("jump L",), ("convert_u", "setlocal 5")),
    "class_117/i/method method_7516": (
        ("getproperty pkg:::var_2460",), ("setproperty pkg:::y",),
    ),
    "class_612/iinit": (
        ("getproperty pkg:::var_2587",), ("setproperty pkg:::x",),
    ),
    "class_398/s/method method_6763": (
        ("convert_d",), ("callproperty pkg:::pow 2", "convert_d"),
    ),
    "class_393/i/method method_4723": (
        ("subtract",),
        ("getlocal 2", "add", "convert_d", "callpropvoid pkg:::SetPosition 2"),
    ),
    "class_598/i/method method_5744": (
        ("getlex pkg:::var_12457",),
        ("getlocal 3", "getproperty pkg:::x", "add", "convert_d"),
    ),
    "class_600/i/method method_2941": (
        ("getlex pkg:::var_12457",),
        ("getlocal 3", "getproperty pkg:::x", "add", "convert_d"),
    ),
    "class_607/i/method method_3933": (
        ("getlex pkg:::var_12457",),
        ("getlocal 3", "getproperty pkg:::x", "add", "convert_d"),
    ),
    "class_614/i/method method_4822": (
        ("getlex pkg:::var_12457",),
        ("getlocal 4", "getproperty pkg:::x", "add", "convert_d"),
    ),
    "class_61/s/method method_7049": (
        ("getstatic pkg:::var_10320",),
        ("callpropvoid ns:http://adobe.com/AS3/2006/builtin::push 1",),
    ),
    "class_61/s/method method_2074": (
        ("getstatic pkg:::var_10320",),
        ("callpropvoid ns:http://adobe.com/AS3/2006/builtin::push 1",),
    ),
    "class_61/s/method method_3492": (
        ("getstatic pkg:::var_10320",),
        ("callpropvoid ns:http://adobe.com/AS3/2006/builtin::push 1",),
    ),
}


AUDITED_MULTI_TYPED_NUMERIC_LITERALS = {
    "MessageTrigger/i/method method_1128": (
        (4, "pushdouble 240.0", "pushint 240", 4, "setproperty pkg:::var_7160"),
        (11, "pushdouble 240.0", "pushint 240", 4, "setproperty pkg:::var_2831"),
    ),
    "SpawnBot/i/method method_4910": (
        (31, "pushdouble 1000.0", "pushint 1000", 2,
         "constructprop pkg:flash.geom::Rectangle 4"),
        (32, "pushdouble 1000.0", "pushint 1000", 1,
         "constructprop pkg:flash.geom::Rectangle 4"),
    ),
    "WaveData/s/method method_6986": (
        (0, "pushuint 1023", "pushint 1023", 2, "ifeq L"),
        (11, "pushuint 1023", "pushint 1023", 1, "convert_u"),
        (14, "pushuint 1023", "pushint 1023", 2, "ifeq L"),
        (25, "pushuint 1023", "pushint 1023", 1, "convert_u"),
        (28, "pushuint 1023", "pushint 1023", 2, "ifeq L"),
        (39, "pushuint 1023", "pushint 1023", 1, "convert_u"),
    ),
    "class_117/i/method method_7898": (
        (20, "pushdouble 2.0", "pushbyte 2", 1, "callproperty pkg:::max 2"),
        (30, "pushdouble 2.0", "pushbyte 2", 1, "callproperty pkg:::max 2"),
    ),
    "class_124/i/method method_1584": (
        (50, "pushdouble 45.0", "pushbyte 45", 1, "setproperty pkg:::x"),
        (54, "pushdouble 90.0", "pushbyte 90", 4, "setproperty pkg:::y"),
    ),
}


AUDITED_MULTI_TYPED_NUMERIC_LITERALS_FOLLOWUP = {
    "class_159/i/method method_1216": (
        (39, "pushuint 1000", "pushint 1000", 3, "convert_u"),
        (41, "pushuint 250", "pushint 250", 1, "convert_u"),
    ),
    "class_250/i/method method_9030": (
        (115, "pushbyte 0", "pushdouble 0.0", 1, "convert_d"),
        (133, "pushbyte 0", "pushdouble 0.0", 1, "convert_d"),
    ),
    "class_261/i/method method_4324": (
        (19, "pushdouble 576.0", "pushint 576", 1, "setproperty pkg:::x"),
        (23, "pushdouble 384.0", "pushint 384", 1, "setproperty pkg:::y"),
    ),
    "class_280/s/method method_5357": (
        (16, "pushbyte 0", "pushdouble 0.0", 185, "constructprop pkg:::class_280 11"),
        (32, "pushbyte 0", "pushdouble 0.0", 169, "constructprop pkg:::class_280 11"),
        (67, "pushbyte 0", "pushdouble 0.0", 134, "constructprop pkg:::class_280 11"),
    ),
    "class_349/i/method method_5034": (
        (25, "pushuint 300", "pushint 300", 3, "convert_u"),
        (27, "pushuint 140", "pushint 140", 1, "convert_u"),
    ),
    "class_381/i/method method_6992": (
        (79, "pushdouble 10.0", "pushbyte 10", 1, "setproperty pkg:::x"),
        (82, "pushdouble -15.0", "pushbyte -15", 1, "setproperty pkg:::y"),
    ),
    "class_390/i/method HandleHeldInput": (
        (37, "pushdouble 3.0", "pushbyte 3", 1, "callproperty pkg:::pow 2"),
        (42, "pushdouble 4.0", "pushbyte 4", 1, "callproperty pkg:::pow 2"),
    ),
    "class_395/iinit": (
        (29, "pushdouble 1.0", "pushbyte 1", 1, "callpropvoid pkg:::beginFill 2"),
        (32, "pushdouble 0.0", "pushbyte 0", 3, "callpropvoid pkg:::drawCircle 3"),
        (33, "pushdouble 0.0", "pushbyte 0", 2, "callpropvoid pkg:::drawCircle 3"),
    ),
    "class_402/i/method method_1758": (
        (51, "pushdouble -139.0", "pushint -139", 4, "add"),
    ),
    "class_429/i/method method_8933": (
        (11, "pushdouble 120.0", "pushbyte 120", 1, "setproperty pkg:::y"),
        (24, "pushdouble 20.0", "pushbyte 20", 1, "setproperty pkg:::y"),
    ),
    "class_448/s/method method_3550": (
        (20, "pushdouble 0.0", "pushbyte 0", 1, "setproperty pkg:::redOffset"),
        (23, "pushdouble 0.0", "pushbyte 0", 1, "setproperty pkg:::greenOffset"),
        (26, "pushdouble 0.0", "pushbyte 0", 1, "setproperty pkg:::blueOffset"),
        (29, "pushdouble 1.0", "pushbyte 1", 1, "setproperty pkg:::redMultiplier"),
        (32, "pushdouble 1.0", "pushbyte 1", 1, "setproperty pkg:::greenMultiplier"),
        (35, "pushdouble 1.0", "pushbyte 1", 1, "setproperty pkg:::blueMultiplier"),
        (65, "pushdouble 0.0", "pushbyte 0", 1, "setproperty pkg:::alphaOffset"),
        (77, "pushdouble 1.0", "pushbyte 1", 1, "setproperty pkg:::alphaMultiplier"),
    ),
    "class_448/i/method method_7898": (
        (20, "pushdouble 2.0", "pushbyte 2", 1, "callproperty pkg:::max 2"),
        (30, "pushdouble 2.0", "pushbyte 2", 1, "callproperty pkg:::max 2"),
    ),
    "class_464/i/method OnTickScreen": (
        (34, "pushuint 280", "pushint 280", 3, "ifne L"),
    ),
    "class_484/i/method OnRefreshScreen": (
        (69, "pushuint 863044", "pushint 863044", 3, "callpropvoid pkg:::method_939 1"),
        (71, "pushuint 16777215", "pushint 16777215", 1, "callpropvoid pkg:::method_939 1"),
    ),
    "class_520/i/method method_6594": (
        (26, "pushbyte 0", "pushdouble 0.0", 1, "callpropvoid pkg:::method_7486 4"),
        (42, "pushbyte 0", "pushdouble 0.0", 1, "callpropvoid pkg:::method_7486 4"),
        (58, "pushbyte 0", "pushdouble 0.0", 1, "callpropvoid pkg:::method_7486 4"),
        (88, "pushbyte 0", "pushdouble 0.0", 1, "callpropvoid pkg:::method_7486 4"),
        (104, "pushbyte 0", "pushdouble 0.0", 1, "callpropvoid pkg:::method_7486 4"),
    ),
    "class_555/i/method method_2738": (
        (18, "pushuint 3000", "pushint 3000", 2, "add"),
    ),
    "class_663/i/method method_7073": (
        (18, "pushuint 16729156", "pushint 16729156", 3, "callpropvoid pkg:::method_939 1"),
        (20, "pushuint 7391699", "pushint 7391699", 1, "callpropvoid pkg:::method_939 1"),
    ),
    "class_674/i/method method_7975": (
        (4, "pushuint 3207645", "pushint 3207645", 3, "convert_u"),
        (6, "pushuint 16777215", "pushint 16777215", 1, "convert_u"),
    ),
    "class_687/s/method method_5917": (
        (17, "pushdouble 1.0", "pushbyte 1", 1, "setproperty pkg:::alphaMultiplier"),
        (41, "pushdouble 0.0", "pushbyte 0", 1, "setproperty pkg:::alphaOffset"),
    ),
    "class_694/i/method method_1999": (
        (26, "pushdouble 1.0", "pushbyte 1", 1, "setproperty pkg:::alpha"),
        (31, "pushdouble 0.0", "pushbyte 0", 1, "setproperty pkg:::alpha"),
    ),
    "class_722/s/method method_1180": (
        (46, "pushdouble 0.0", "pushbyte 0", 1, "setproperty pkg:::x"),
        (49, "pushdouble 0.0", "pushbyte 0", 1, "setproperty pkg:::y"),
        (70, "pushdouble 0.0", "pushbyte 0", 1, "setproperty pkg:::x"),
        (100, "pushdouble 0.0", "pushbyte 0", 1, "setproperty pkg:::y"),
        (114, "pushdouble 1.0", "pushbyte 1", 1, "callpropvoid pkg:::beginFill 2"),
        (118, "pushdouble 0.0", "pushbyte 0", 4, "callpropvoid pkg:::drawRect 4"),
        (119, "pushdouble 0.0", "pushbyte 0", 3, "callpropvoid pkg:::drawRect 4"),
        (120, "pushdouble 1920.0", "pushint 1920", 2, "callpropvoid pkg:::drawRect 4"),
        (121, "pushdouble 1080.0", "pushint 1080", 1, "callpropvoid pkg:::drawRect 4"),
        (187, "pushdouble 50.0", "pushbyte 50", 1, "setproperty pkg:::x"),
        (190, "pushdouble 15.0", "pushbyte 15", 1, "setproperty pkg:::y"),
    ),
    "class_722/s/method method_7776": (
        (27, "pushdouble 50.0", "pushbyte 50", 1, "setproperty pkg:::x"),
        (30, "pushdouble 15.0", "pushbyte 15", 1, "setproperty pkg:::y"),
    ),
}


def rule_audited_multi_typed_numeric_literals_followup(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    sites = AUDITED_MULTI_TYPED_NUMERIC_LITERALS_FOLLOWUP.get(key)
    if sites is None or original_exceptions or compiled_exceptions:
        return False
    if len(original) != len(compiled):
        return False
    differences = [i for i, (a, b) in enumerate(zip(original, compiled)) if a != b]
    if not differences or not set(differences) <= {site[0] for site in sites}:
        return False

    patched = list(original)
    for index, original_atom, compiled_atom, sink_offset, sink in sites:
        if index not in differences:
            continue
        sink_index = index + sink_offset
        if (original[index] != original_atom or compiled[index] != compiled_atom
                or sink_index >= len(original)):
            return False
        original_sink = original[sink_index]
        compiled_sink = compiled[sink_index]
        if sink.endswith(" L"):
            if shape(original_sink) != sink or shape(compiled_sink) != sink:
                return False
        elif original_sink != sink or compiled_sink != sink:
            return False
        if (integer_literal(original_atom) is None
                or integer_literal(original_atom) != integer_literal(compiled_atom)):
            return False
        patched[index] = compiled_atom
    return patched == compiled


def rule_audited_multi_typed_numeric_literals(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    sites = AUDITED_MULTI_TYPED_NUMERIC_LITERALS.get(key)
    if sites is None or original_exceptions or compiled_exceptions:
        return False
    if len(original) != len(compiled):
        return False
    differences = [i for i, (a, b) in enumerate(zip(original, compiled)) if a != b]
    if not differences or not set(differences) <= {site[0] for site in sites}:
        return False

    patched = list(original)
    for index, original_atom, compiled_atom, sink_offset, sink in sites:
        if index not in differences:
            continue
        sink_index = index + sink_offset
        if (original[index] != original_atom or compiled[index] != compiled_atom
                or sink_index >= len(original)):
            return False
        original_sink = original[sink_index]
        compiled_sink = compiled[sink_index]
        if sink.endswith(" L"):
            if shape(original_sink) != sink or shape(compiled_sink) != sink:
                return False
        elif original_sink != sink or compiled_sink != sink:
            return False
        if (integer_literal(original_atom) is None
                or integer_literal(original_atom) != integer_literal(compiled_atom)):
            return False
        patched[index] = compiled_atom
    return patched == compiled


def rule_audited_typed_numeric_literal_boundary(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    context = AUDITED_TYPED_NUMERIC_LITERAL_BOUNDARIES.get(key)
    if context is None or original_exceptions or compiled_exceptions:
        return False
    if len(original) != len(compiled):
        return False
    differences = [i for i, (a, b) in enumerate(zip(original, compiled)) if a != b]
    if len(differences) != 1:
        return False
    index = differences[0]
    if not original[index].startswith(("pushdouble ", "pushuint ")):
        return False
    original_value = integer_literal(original[index])
    compiled_value = integer_literal(compiled[index])
    if (original_value is None or compiled_value is None
            or original_value != compiled_value
            or not compiled[index].startswith(("pushbyte ", "pushshort ", "pushint ", "pushuint "))):
        return False

    before, after = context

    def context_matches(expected: tuple[str, ...], actual: list[str]) -> bool:
        return len(expected) == len(actual) and all(
            wanted == got or (wanted.endswith(" L") and shape(got) == wanted)
            for wanted, got in zip(expected, actual)
        )

    return (
        index >= len(before)
        and index + 1 + len(after) <= len(original)
        and context_matches(before, original[index - len(before):index])
        and context_matches(after, original[index + 1:index + 1 + len(after)])
        and context_matches(before, compiled[index - len(before):index])
        and context_matches(after, compiled[index + 1:index + 1 + len(after)])
    )


AUDITED_UINT_OBJECT_LITERAL = "class_25/i/method method_8445"


AUDITED_TERMINAL_BOOLEAN_LAYOUTS = {
    "SubScreenEventTimedEvent/i/method HandleHotkey",
    "SubScreenEventTimedEvent/i/method HandleInputForChaseReward",
    "class_528/i/method HandleHotkey",
    "class_529/i/method HandleHotkey",
}


AUDITED_SDK_CONSTANT_FOLDS = {
    "class_50/s/method method_8141": (
        ("pkg:flash.filesystem::FileMode", "pkg:::WRITE", "pushstring 'write'"),
    ),
    "class_50/s/method method_8027": (
        ("pkg:flash.filesystem::FileMode", "pkg:::APPEND", "pushstring 'append'"),
    ),
    "class_622/i/method method_7735": (
        ("pkg:flash.events::Event", "pkg:::SELECT", "pushstring 'select'"),
    ),
    "class_622/i/method method_7089": (
        ("pkg:flash.events::Event", "pkg:::SELECT", "pushstring 'select'"),
        ("pkg:flash.events::Event", "pkg:::COMPLETE", "pushstring 'complete'"),
    ),
    "flash.Boot/i/method doInitDelay": (
        ("pkg:flash.events::Event", "pkg:::ADDED_TO_STAGE", "pushstring 'addedToStage'"),
    ),
}


def rule_audited_sdk_constant_folds(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    audits = AUDITED_SDK_CONSTANT_FOLDS.get(key)
    if audits is None or original_exceptions or compiled_exceptions:
        return False
    targets = branch_targets(original, original_exceptions)
    changed: dict[int, str | None] = {}
    previous = -1
    for owner, prop, literal in audits:
        sequence = (f"getlex {owner}", f"getproperty {prop}")
        starts = [
            i for i in range(len(original) - 1)
            if tuple(original[i:i + 2]) == sequence
        ]
        if len(starts) != 1 or starts[0] <= previous:
            return False
        start = starts[0]
        if targets & {start, start + 1}:
            return False
        changed[start] = literal
        changed[start + 1] = None
        previous = start
    return _rebuild(original, original_exceptions, changed) == (
        compiled, compiled_exceptions,
    )


def rule_audited_terminal_boolean_layout(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    if (key not in AUDITED_TERMINAL_BOOLEAN_LAYOUTS or original_exceptions
            or compiled_exceptions):
        return False

    terminal = re.compile(r"^@return\[(push(?:true|false))\]$")

    def normalize(lines: list[str]) -> list[str] | None:
        if not lines:
            return None
        jump = re.fullmatch(r"jump (@return\[push(?:true|false)\])", lines[-1])
        if jump:
            return [*lines[:-1], jump.group(1)]
        if (len(lines) >= 2 and lines[-2] in {"pushtrue", "pushfalse"}
                and lines[-1] == "returnvalue"):
            tail = len(lines) - 2
            if branch_targets(lines, []) & {tail, tail + 1}:
                return None
            token = f"@return[{lines[-2]}]"
            if terminal.fullmatch(token):
                return [*lines[:-2], token]
        return None

    normalized_original = normalize(original)
    normalized_compiled = normalize(compiled)
    return (normalized_original is not None
            and normalized_compiled is not None
            and normalized_original == normalized_compiled)


AUDITED_STORETYPE_METHOD_2100_CFG = "StoreType/i/method method_2100"


def rule_audited_storetype_method_2100_cfg(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    if (key != AUDITED_STORETYPE_METHOD_2100_CFG or original_exceptions
            or compiled_exceptions or len(original) != 593 or len(compiled) not in (593, 594)
            or "L?" in "\n".join(original) or "L?" in "\n".join(compiled)):
        return False

    original_membership = (
        "getlocal 15", "getlocal 14", "getproperty pkg:::h", "in",
    )
    compiled_membership = (
        f"getlex {AS3_HELPER_QNAME}", "getlocal 14",
        "getproperty pkg:::h", "getlocal 15",
        "callproperty pkg:::hasKey 2",
    )
    original_hits = [
        i for i in range(len(original) - len(original_membership) + 1)
        if tuple(original[i:i + len(original_membership)]) == original_membership
    ]
    compiled_hits = [
        i for i in range(len(compiled) - len(compiled_membership) + 1)
        if tuple(compiled[i:i + len(compiled_membership)]) == compiled_membership
    ]
    native_hits = [
        i for i in range(len(compiled) - len(original_membership) + 1)
        if tuple(compiled[i:i + len(original_membership)]) == original_membership
    ]
    if original_hits != [25] or (compiled_hits, native_hits) not in (([25], []), ([], [25])):
        return False
    if compiled_hits:
        compiled, compiled_exceptions = _rebuild(compiled, compiled_exceptions, {
            25: "getlocal 15", 28: "in", 29: None,
        })
    if len(compiled) != len(original):
        return False

    original_dispatch = (
        "getlocal 27", "pushstring 'Bundle'", "ifeq L141",
        "getlocal 27", "pushstring 'Costume'", "ifne L283",
    )
    compiled_dispatch = (
        "getlocal 27", "pushstring 'Bundle'", "ifeq L341",
        "getlocal 27", "pushstring 'Costume'", "ifeq L341",
    )
    if (tuple(original[135:141]) != original_dispatch
            or tuple(compiled[135:141]) != compiled_dispatch
            or original[141:144] != [
                "getlex pkg:::mType", "pushstring 'Bundle'", "ifne L151",
            ]
            or original[282] != "jump L482"
            or original[283:286] != [
                "getlocal 27", "pushstring 'ColorScheme'", "ifne L292",
            ]
            or compiled[141:144] != [
                "getlocal 27", "pushstring 'ColorScheme'", "ifne L150",
            ]
            or compiled[340] != "jump L482"
            or compiled[341:344] != [
                "getlex pkg:::mType", "pushstring 'Bundle'", "ifne L351",
            ]
            or original[482] != "findpropstrict pkg:::var_575"
            or compiled[482] != "findpropstrict pkg:::var_575"
            or original.count("pushstring 'Bundle'") != 2
            or compiled.count("pushstring 'Bundle'") != 2
            or original.count("pushstring 'Costume'") != 1
            or compiled.count("pushstring 'Costume'") != 1):
        return False

    original_edges = set(branch_edges(original))
    compiled_edges = set(branch_edges(compiled))

    def closed_region(edges: set[tuple[int, int]], start: int, end: int,
                      allowed_entries: set[tuple[int, int]], join: int) -> bool:
        for source, target in edges:
            source_inside = start <= source < end
            target_inside = start <= target < end
            if target_inside and not source_inside and (source, target) not in allowed_entries:
                return False
            if source_inside and not target_inside and target != join:
                return False
        return True

    if (not closed_region(original_edges, 141, 283, {(137, 141)}, 482)
            or not closed_region(original_edges, 283, 482, {(140, 283)}, 482)
            or not closed_region(compiled_edges, 141, 341, set(), 482)
            or not closed_region(
                compiled_edges, 341, 482, {(137, 341), (140, 341)}, 482,
            )):
        return False

    order = [
        *range(0, 141),
        *range(341, 482),
        340,
        *range(141, 340),
        *range(482, len(compiled)),
    ]
    if len(order) != len(compiled) or len(set(order)) != len(compiled):
        return False
    new_index = {old: new for new, old in enumerate(order)}
    new_index[len(compiled)] = len(compiled)

    def relabel(line: str) -> str:
        try:
            return LABEL.sub(lambda match: f"L{new_index[int(match.group(1))]}", line)
        except KeyError:
            return "L?"

    normalized_compiled: list[str] = []
    for old in order:
        line = compiled[old]
        if line.split(" ", 1)[0].startswith(("if", "jump", "lookupswitch")):
            line = relabel(line)
        if "L?" in line:
            return False
        normalized_compiled.append(line)
    normalized_compiled[140] = "ifne L283"

    literal_sites = {
        113: ("pushdouble 200000.0", "pushint 200000"),
        287: ("pushdouble 70000.0", "pushint 70000"),
        486: ("pushdouble 1.0", "pushbyte 1"),
        488: ("pushdouble 0.0", "pushbyte 0"),
        512: ("pushdouble 1.0", "pushbyte 1"),
        514: ("pushdouble 0.0", "pushbyte 0"),
        534: ("pushdouble 350.0", "pushint 350"),
        559: ("pushdouble 0.0", "pushbyte 0"),
    }
    for index, (original_line, compiled_line) in literal_sites.items():
        if (original[index] != original_line
                or normalized_compiled[index] != compiled_line):
            return False
        normalized_compiled[index] = original_line
    return normalized_compiled == original


AUDITED_COSTUMETYPE_METHOD_7242_CFG = "CostumeType/s/method method_7242"


def rule_audited_costumetype_method_7242_cfg(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    if (key != AUDITED_COSTUMETYPE_METHOD_7242_CFG or original_exceptions
            or compiled_exceptions or len(original) != 484 or len(compiled) != 483
            or "L?" in "\n".join(original) or "L?" in "\n".join(compiled)):
        return False
    original_condition = (
        "pushfalse", "getlocal 7", "getproperty pkg:::var_14874", "pushnull",
        "ifeq L373", "pop", "getlocal 7", "getproperty pkg:::var_14874",
        "getlocal 6", "equals", "not", "iffalse L396",
    )
    compiled_condition = (*original_condition[:-1], "iftrue L401")
    reset = (
        "getlocal 4", "pushnull", "setproperty pkg:::var_11133",
        "getlocal 4", "pushnull", "setproperty pkg:::var_14874",
    )
    if (tuple(original[362:374]) != original_condition
            or tuple(compiled[362:374]) != compiled_condition
            or original[374] != "getlex pkg:::class_135"
            or original[394] != "callpropvoid pkg:::method_3866 1"
            or original[395] != "jump L423"
            or original[396] != "getlocal 3"
            or original[422] != "jump L430"
            or tuple(original[423:429]) != reset
            or compiled[374] != "getlocal 3"
            or compiled[400] != "jump L429"
            or compiled[401] != "getlex pkg:::class_135"
            or compiled[421] != "callpropvoid pkg:::method_3866 1"
            or tuple(compiled[422:428]) != reset):
        return False

    original_edges = set(branch_edges(original))
    compiled_edges = set(branch_edges(compiled))

    def closed_region(edges: set[tuple[int, int]], start: int, end: int,
                      allowed_entries: set[tuple[int, int]], allowed_exits: set[int]) -> bool:
        for source, target in edges:
            source_inside = start <= source < end
            target_inside = start <= target < end
            if target_inside and not source_inside and (source, target) not in allowed_entries:
                return False
            if source_inside and not target_inside and target not in allowed_exits:
                return False
        return True

    if (not closed_region(original_edges, 374, 396, set(), {423})
            or not closed_region(original_edges, 396, 423, {(373, 396)}, {430})
            or not closed_region(compiled_edges, 374, 401, set(), {429})
            or not closed_region(compiled_edges, 401, 422, {(373, 401)}, {422})):
        return False

    order: list[int | None] = [
        *range(0, 374), *range(401, 422), None,
        *range(374, 401), *range(422, len(compiled)),
    ]
    old_indices = [index for index in order if index is not None]
    if len(order) != len(original) or len(old_indices) != len(compiled) \
            or len(set(old_indices)) != len(compiled):
        return False
    new_index = {old: new for new, old in enumerate(order) if old is not None}
    new_index[len(compiled)] = len(original)

    def relabel(line: str) -> str:
        try:
            return LABEL.sub(lambda match: f"L{new_index[int(match.group(1))]}", line)
        except KeyError:
            return "L?"

    normalized: list[str] = []
    for old in order:
        if old is None:
            normalized.append("jump L423")
            continue
        line = compiled[old]
        if line.split(" ", 1)[0].startswith(("if", "jump", "lookupswitch")):
            line = relabel(line)
        if "L?" in line:
            return False
        normalized.append(line)
    normalized[373] = "iffalse L396"
    return normalized == original


def rule_audited_uint_object_literal(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str,
        raw_compiled: list[str]) -> bool:
    if (key != AUDITED_UINT_OBJECT_LITERAL or original_exceptions
            or compiled_exceptions):
        return False
    original_sequence = (
        "pushstring 'key'",
        "pushstring 'UI_BattlePass_RewardRarity_Legendary'",
        "pushstring 'color'",
        "pushuint 16750876",
        "newobject 2",
        "returnvalue",
    )
    compiled_sequence = (
        "pushstring 'key'",
        "pushstring 'UI_BattlePass_RewardRarity_Legendary'",
        "pushstring 'color'",
        "pushint 16750876",
        "newobject 2",
        "returnvalue",
    )
    raw_boundary = (
        "pushstring 'color'",
        f"getlex {AS3_HELPER_QNAME}",
        "pushint 16750876",
        "callproperty pkg:::toUInt 1",
        "convert_u",
        "newobject 2",
    )
    original_starts = [
        i for i in range(len(original) - len(original_sequence) + 1)
        if tuple(original[i:i + len(original_sequence)]) == original_sequence
    ]
    compiled_starts = [
        i for i in range(len(compiled) - len(compiled_sequence) + 1)
        if tuple(compiled[i:i + len(compiled_sequence)]) == compiled_sequence
    ]
    raw_starts = [
        i for i in range(len(raw_compiled) - len(raw_boundary) + 1)
        if tuple(raw_compiled[i:i + len(raw_boundary)]) == raw_boundary
    ]
    if (len(original_starts) != 1 or len(compiled_starts) != 1
            or len(raw_starts) != 1):
        return False
    start = compiled_starts[0]
    literal = start + 3
    if branch_targets(compiled, compiled_exceptions) & {literal}:
        return False
    rebuilt, rebuilt_exceptions = _rebuild(
        compiled, compiled_exceptions,
        {literal: "pushuint 16750876"},
    )
    return rebuilt == original and rebuilt_exceptions == original_exceptions


AUDITED_INTEGER_LOCAL_LITERAL = "class_605/i/method method_301"
AUDITED_INTEGER_LOCAL_LITERALS = {
    AUDITED_INTEGER_LOCAL_LITERAL: ("pushdouble 20.0", "convert_i", "pushbyte 20"),
    "BombsketballState/i/method method_7010": (
        "pushuint 150", "convert_u", "pushint 150",
    ),
}


def rule_audited_integer_local_literal(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    audit = AUDITED_INTEGER_LOCAL_LITERALS.get(key)
    if audit is None or original_exceptions or compiled_exceptions:
        return False
    original_atom, conversion, compiled_atom = audit
    changed: dict[int, str | None] = {}
    for i in range(len(original) - 2):
        if (original[i] == original_atom and original[i + 1] == conversion
                and original[i + 2].startswith("setlocal ")):
            if changed:
                return False
            changed = {i: compiled_atom, i + 1: None}
    if len(changed) != 2:
        return False
    return _rebuild(original, original_exceptions, changed) == (compiled, compiled_exceptions)


AUDITED_ZERO_NUMBER_CALL_BOUNDARIES = {
    "class_727/s/method method_1968": ("'Volume_Sound'", "pkg:::var_7091"),
    "class_727/s/method method_6088": ("'Volume_Music'", "pkg:::var_13292"),
}


def rule_audited_zero_number_call_boundary(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    expected = AUDITED_ZERO_NUMBER_CALL_BOUNDARIES.get(key)
    if expected is None or original_exceptions or compiled_exceptions:
        return False
    bus, fallback = expected
    changed: dict[int, str | None] = {}
    found = 0
    for i, line in enumerate(compiled):
        if line != "pushdouble 0.0" or i < 4 or i + 4 >= len(compiled):
            continue
        if (
            compiled[i - 4] == "getlex pkg:::SoundEngineExtension"
            and compiled[i - 3] == f"pushstring {bus}"
            and compiled[i - 2] == "getlocal 1"
            and shape(compiled[i - 1]) == "iffalse L"
            and shape(compiled[i + 1]) == "jump L"
            and compiled[i + 2] == f"getstatic {fallback}"
            and compiled[i + 3] == "convert_d"
            and compiled[i + 4] == "callpropvoid pkg:::SetRtpcValue 2"
        ):
            changed[i] = "pushbyte 0"
            changed[i + 3] = None
            found += 1
    if found != 1:
        return False
    return _rebuild(compiled, compiled_exceptions, changed) == (
        original, original_exceptions,
    )


AUDITED_ENUM_CLASS_ARGUMENTS = {
    "LinkUpdater/i/method method_5910": (("pkg:::class_102", "createEnumIndex"),),
    "SubScreenEventTimedEvent/i/method GetAvailableFocuses": (
        ("pkg:::class_596", "createEnumIndex"),
    ),
    "class_479/i/method method_4097": (("pkg:::class_477", "createEnumIndex"),),
    "class_479/i/method method_4553": (("pkg:::class_475", "createEnumIndex"),),
    "class_479/i/method method_4370": (("pkg:::class_475", "createEnumIndex"),),
    "class_479/i/method method_8078": (("pkg:::class_475", "allEnums"),),
    "class_479/i/method method_8190": (("pkg:::class_475", "createEnumIndex"),),
    "class_479/i/method method_3117": (("pkg:::class_475", "createEnumIndex"),),
    "class_479/i/method method_3926": (("pkg:::class_475", "createEnumIndex"),),
    "class_479/i/method method_8045": (
        ("pkg:::class_476", "allEnums"),
        ("pkg:::class_476", "createEnumIndex"),
    ),
}


AUDITED_CONTROLLER_MAP_BOUNDARIES = {
    "Controller/i/method method_4587": 2,
    "Controller/i/method method_5041": 1,
    "Controller/i/method method_5649": 2,
    "Controller/i/method method_5923": 1,
    "Controller/i/method method_6423": 1,
    "Controller/i/method method_8127": 1,
}


AUDITED_CLOSED_MAP_LOCAL_STORES = {
    "class_104/i/method method_1516": ("pkg:::var_14524", 1, 0, 0),
    "class_104/i/method method_5985": ("pkg:::var_14524", 1, 1, 1),
    "class_81/i/method method_2948": ("pkg:::var_4713", 1, 1, 0),
}


AUDITED_CLOSED_STRING_MAP_INTERFACE_BOUNDARIES = {
    "class_25/s/method method_3356": "pkg:::var_8698",
}


AUDITED_MAP_BACKING_HAS_KEY = {
    "GameStats/i/method method_636",
    "HotkeyType/i/method method_2273",
    "HotkeyType/i/method method_9071",
    "ItemType/s/method method_6094",
    "LinkUpdater/i/method method_3452",
    "StoreType/s/method method_1971",
    "StoreType/s/method method_7721",
    "StoreType/s/method method_4295",
    "WorldHotkey/i/method method_2495",
    "class_104/i/method method_5095",
    "class_11/s/method method_1479",
    "class_11/s/method method_2993",
    "class_11/s/method method_3188",
    "class_11/s/method method_4103",
    "class_11/s/method method_5238",
    "class_11/s/method method_7395",
    "class_11/s/method method_8179",
    "class_11/s/method method_8203",
    "class_11/s/method method_1418",
    "class_123/i/method method_6611",
    "class_143/i/method method_3669",
    "class_166/s/method method_6643",
    "class_233/i/method method_1482",
    "class_233/s/method method_8741",
    "class_25/s/method method_1504",
    "class_25/s/method method_3875",
    "class_21/i/method method_3341",
    "class_21/i/method method_707",
    "class_21/i/method method_892",
    "class_275/iinit",
    "class_296/i/method method_4261",
    "class_296/i/method method_7306",
    "class_322/i/method method_7953",
    "class_328/i/method method_3614",
    "class_328/i/method method_4542",
    "class_35/i/method method_2649",
    "class_40/s/method method_6059",
    "class_444/i/method method_3258",
    "class_458/i/method method_2898",
    "class_479/s/method method_1006",
    "class_479/i/method method_3464",
    "class_479/i/method method_4454",
    "class_604/i/method method_3968",
    "class_618/s/method method_1693",
    "class_618/s/method method_6638",
    "class_665/i/method method_8679",
    "class_669/i/method Update",
    "class_669/i/method method_7147",
    "class_670/s/method method_2959",
    "class_68/i/method method_4353",
    "class_680/s/method method_7221",
    "class_719/i/method method_3625",
    "class_76/s/method method_1421",
}


AUDITED_MAP_BACKING_HAS_KEY_COUNTS = {
    "HotkeyType/i/method method_2273": 2,
    "class_123/i/method method_6611": 2,
    "class_35/i/method method_2649": 2,
    "class_719/i/method method_3625": 2,
}


AUDITED_CLOSED_IMAP_LOCAL_STORES = {
    "class_104/i/method method_6856": "pkg:::var_10882",
}


AUDITED_CLASS25_NESTED_MAP_BOUNDARY = "class_25/s/method method_7496"


AUDITED_CONTROLLER_MAPPING_IMAP_JOINS = {
    "class_88/i/method method_4012",
    "class_88/i/method method_5498",
}


AUDITED_EXTENSION_CONTEXT_FACTORY_STORES = {
    "ANE_DnaManager/s/method Init": ("private::sExtensionContext", "DnaManager", "static"),
    "ANE_DnaManager/s/method WakeUp": ("private::sExtensionContext", "DnaManager", "static"),
    "ANE_EpicAir/s/method Init": ("private::sExtensionContext", "EpicAir", "static"),
    "ANE_RawData/s/method Init": ("private::sExtensionContext", "RawData", "static"),
    "DesktopExtension/i/method Init": ("pkg:::mExtensionContext", "DesktopExtension", "instance"),
    "SoundEngineExtension/s/method Init": ("private::var_1", "SoundEngineExtension", "static"),
}


AUDITED_CAST_CONVERSION_BOUNDARIES = {
    "ANE_MultiKeyboard/s/method ActivateRawKeyboard": (
        ("astype pkg:::uint", "convert_u", "setlocal 1"),
        ("astype pkg:::uint", "coerce pkg:::Object", "convert_u", "setlocal 1"),
        "compiled",
        1,
    ),
    "class_30/i/method method_1469": (
        (
            "callproperty pkg:::charCodeAt 1",
            "callpropvoid pkg:::method_4026 2",
        ),
        (
            "callproperty pkg:::charCodeAt 1", "coerce pkg:::Object",
            "callpropvoid pkg:::method_4026 2",
        ),
        "compiled",
        1,
    ),
    "class_51/s/method method_298": (
        (
            "callproperty pkg:::getData 1",
            "callproperty pkg:::method_5298 1",
        ),
        (
            "callproperty pkg:::getData 1", "coerce pkg:::Object",
            "callproperty pkg:::method_5298 1",
        ),
        "compiled",
        1,
    ),
    "class_592/s/method method_5069": (
        (
            "callproperty pkg:::charCodeAt 1", "setlocal 3",
        ),
        (
            "callproperty pkg:::charCodeAt 1", "coerce pkg:::Object",
            "setlocal 3",
        ),
        "compiled",
        1,
    ),
    "class_143/i/method method_992": (
        ("getlocal 2", "pushint 1", "bitand", "pushdouble 0.0"),
        ("getlocal 2", "pushint 1", "bitand", "convert_u", "pushdouble 0.0"),
        "compiled",
        3,
    ),
    "class_672/i/method method_5423": (
        ("add_i", "convert_u", "setproperty pkg:::var_10792"),
        ("add_i", "convert_u", "convert_i", "setproperty pkg:::var_10792"),
        "compiled",
        2,
    ),
    "class_697/i/method method_5423": (
        ("add_i", "convert_u", "setproperty pkg:::var_10792"),
        ("add_i", "convert_u", "convert_i", "setproperty pkg:::var_10792"),
        "compiled",
        2,
    ),
    "class_698/i/method method_5423": (
        ("add_i", "convert_u", "setproperty pkg:::var_10792"),
        ("add_i", "convert_u", "convert_i", "setproperty pkg:::var_10792"),
        "compiled",
        2,
    ),
    "class_199/i/method UpdateHighlighter": (
        (
            "getproperty pkg:::var_2587", "coerce pkg:flash.display::MovieClip",
            "setlocal 1",
        ),
        (
            "getproperty pkg:::var_2587", "coerce pkg:flash.display::MovieClip",
            "coerce pkg:flash.display::MovieClip", "setlocal 1",
        ),
        "compiled",
        1,
    ),
    "class_479/i/method method_7540": (
        ("getlex pkg:::Type", "getlex pkg:::class_475", "getlex pkg:::var_1253"),
        (
            "getlex pkg:::Type", "getlex pkg:::class_475", "coerce pkg:::Class",
            "getlex pkg:::var_1253",
        ),
        "compiled",
        2,
    ),
    "class_343/i/method method_6050": (
        (
            "pushint -1", "getlocal 2", "getproperty pkg:::var_8693",
            "callproperty pkg:::method_207 0", "pushdouble 60.0", "modulo",
            "convert_d", "multiply_i", "convert_i", "setlocal 7",
        ),
        (
            "pushint -1", "getlocal 2", "getproperty pkg:::var_8693",
            "callproperty pkg:::method_207 0", "pushdouble 60.0", "modulo",
            "multiply_i", "convert_i", "setlocal 7",
        ),
        "original",
        6,
    ),
    "class_335/i/method method_3286": (
        (
            "getproperty pkg:::x", "pushdouble 100.0", "add",
            "convert_d", "ifnle L14", "pushuint 1", "returnvalue",
        ),
        (
            "getproperty pkg:::x", "pushdouble 100.0", "add",
            "ifnle L13", "pushuint 1", "returnvalue",
        ),
        "original",
        3,
    ),
    "SteamAir/i/method Init": (
        (
            "getlex pkg:::mExtensionContext", "pushstring 'status'",
            "getlex pkg:::HandleStatusEvent",
            "callpropvoid pkg:::addEventListener 2",
            "getlex pkg:::mExtensionContext",
        ),
        (
            "getlex pkg:::mExtensionContext", "pushstring 'status'",
            "getlex pkg:::HandleStatusEvent", "coerce pkg:::Function",
            "callpropvoid pkg:::addEventListener 2",
            "getlex pkg:::mExtensionContext",
        ),
        "compiled",
        3,
    ),
    "class_274/i/method method_8705": (
        (
            "getlex pkg:::var_11045", "getlocal 1", "iffalse L33",
            "getlex pkg:::method_918", "coerce pkg:::Function", "jump L35",
            "getlex pkg:::method_5494", "coerce pkg:::Function",
            "callpropvoid ns:http://adobe.com/AS3/2006/builtin::sort 1",
            "findpropstrict pkg:::var_15178",
        ),
        (
            "getlex pkg:::var_11045", "getlocal 1", "iffalse L33",
            "getlex pkg:::method_918", "coerce pkg:::Function", "jump L35",
            "getlex pkg:::method_5494", "coerce pkg:::Function",
            "coerce pkg:::Function",
            "callpropvoid ns:http://adobe.com/AS3/2006/builtin::sort 1",
            "findpropstrict pkg:::var_15178",
        ),
        "compiled",
        8,
    ),
}


def rule_audited_cast_conversion_boundary(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    audit = AUDITED_CAST_CONVERSION_BOUNDARIES.get(key)
    if audit is None or original_exceptions or compiled_exceptions:
        return False
    original_sequence, compiled_sequence, changed_side, changed_offset = audit

    def starts(lines: list[str], sequence: tuple[str, ...]) -> list[int]:
        return [
            i for i in range(len(lines) - len(sequence) + 1)
            if tuple(lines[i:i + len(sequence)]) == sequence
        ]

    original_starts = starts(original, original_sequence)
    compiled_starts = starts(compiled, compiled_sequence)
    if len(original_starts) != 1 or len(compiled_starts) != 1:
        return False
    if changed_side == "original":
        normalized_original = _rebuild(
            original, [], {original_starts[0] + changed_offset: None},
        )
        normalized_compiled = (compiled, compiled_exceptions)
    else:
        normalized_original = (original, original_exceptions)
        normalized_compiled = _rebuild(
            compiled, [], {compiled_starts[0] + changed_offset: None},
        )
    return normalized_original == normalized_compiled


AUDITED_OBJECT_LOCAL_STORE_COERCIONS = {
    "class_137/s/method method_5842": 2,
    "class_171/i/method method_2704": 2,
    "class_171/i/method method_5535": 1,
    "class_171/i/method method_7100": 1,
    "class_433/i/method method_5549": 1,
}


def rule_audited_object_local_store_coercions(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    expected = AUDITED_OBJECT_LOCAL_STORE_COERCIONS.get(key)
    if expected is None or original_exceptions or compiled_exceptions:
        return False
    changed: dict[int, None] = {}
    for i, line in enumerate(original):
        if line != "coerce pkg:::Object" or i == 0 or i + 1 >= len(original):
            continue
        if (original[i - 1] == "getproperty {pkg:}::[]"
                and original[i + 1].startswith(("setlocal ", "setproperty {pkg:}::[]"))):
            changed[i] = None
    if len(changed) != expected or "coerce pkg:::Object" in compiled:
        return False
    return _rebuild(original, [], changed) == (compiled, compiled_exceptions)


AUDITED_UINT_INCREMENT_METHODS: dict[str, tuple[str, ...]] = {
    "class_104/i/method NumBots": ("4",),
    "class_104/i/method method_1872": ("4",),
    "class_104/i/method method_2491": ("5", "4"),
    "class_104/i/method method_4668": ("3", "4"),
    "class_104/i/method method_7023": ("5",),
    "class_104/i/method method_7629": ("5",),
    "class_104/i/method method_7910": ("5",),
}


def rule_audited_uint_increment(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    expected = AUDITED_UINT_INCREMENT_METHODS.get(key)
    if expected is None or original_exceptions or compiled_exceptions:
        return False

    def original_sites(lines: list[str]) -> tuple[str, ...]:
        return tuple(
            lines[i].split(" ", 1)[1]
            for i in range(len(lines) - 3)
            if lines[i].startswith("getlocal ")
            and lines[i + 1] == "increment"
            and lines[i + 2] == "convert_u"
            and lines[i + 3] == lines[i].replace("getlocal ", "setlocal ", 1)
        )

    compiled_sites = [
        i for i in range(len(compiled) - 4)
        if compiled[i].startswith("getlocal ")
        and compiled[i + 1:i + 4] == ["pushint 1", "add_i", "convert_u"]
        and compiled[i + 4] == compiled[i].replace("getlocal ", "setlocal ", 1)
    ]
    compiled_registers = tuple(compiled[i].split(" ", 1)[1] for i in compiled_sites)
    if original_sites(original) != expected or compiled_registers != expected:
        return False
    changes: dict[int, str | None] = {}
    for i in compiled_sites:
        changes[i + 1] = "increment"
        changes[i + 2] = None
    return (original, original_exceptions) == _rebuild(compiled, [], changes)


AUDITED_BOOLEAN_DOUBLE_NOT_RETURN = (
    (
        "original",
        (
            "bitand", "pushdouble 0.0", "equals",
            "not", "not", "returnvalue",
        ),
        ((3, None), (4, None)),
    ),
)


AUDITED_CLOSED_REFERENCE_SCALAR_BOUNDARIES = {
    "class_143/i/method method_5839": AUDITED_BOOLEAN_DOUBLE_NOT_RETURN,
    "class_166/i/method method_7917": AUDITED_BOOLEAN_DOUBLE_NOT_RETURN,
    "class_376/i/method method_4494": AUDITED_BOOLEAN_DOUBLE_NOT_RETURN,
    "class_400/i/method method_3042": AUDITED_BOOLEAN_DOUBLE_NOT_RETURN,
    "class_467/i/method method_3737": AUDITED_BOOLEAN_DOUBLE_NOT_RETURN,
    "class_494/i/method method_2951": AUDITED_BOOLEAN_DOUBLE_NOT_RETURN,
    "class_319/i/method method_5305": (
        (
            "compiled",
            (
                "getlex pkg:::var_3426", "pushint 1", "subtract_i",
                "convert_i", "setlocal 1", "getlocal 1",
                "setproperty pkg:::var_3426",
            ),
            ((1, "decrement_i"), (2, None)),
        ),
    ),
    "class_375/i/method HandleInput": (
        (
            "compiled",
            (
                "getlocal 4", "pushint 1", "subtract_i",
                "convert_u", "setlocal 4",
            ),
            ((1, "decrement"), (2, None)),
        ),
    ),
    "class_370/i/method method_6732": (
        (
            "original",
            (
                "getlocal 3", "pushbyte 0", "getlocal 3",
                "getproperty pkg:::length", "pushint 2", "subtract_i",
                "callproperty ns:http://adobe.com/AS3/2006/builtin::substr 2",
                "returnvalue",
            ),
            ((6, "callproperty pkg:::substr 2"),),
        ),
    ),
    "class_112/s/method method_6506": (
        (
            "original",
            (
                "getstatic pkg:::var_5048", "getlocal 2",
                "getproperty {pkg:}::[]", "coerce pkg:::class_223",
                "setlocal 3",
            ),
            ((3, None),),
        ),
        (
            "compiled",
            (
                "getlocal 4", "pushint 1", "add_i", "convert_u",
                "setlocal 4",
            ),
            ((1, "increment"), (2, None)),
        ),
    ),
    "class_529/i/method OnInitDisplay": (
        (
            "original",
            (
                "getlex pkg:::var_3519", "pushbyte 2",
                "getproperty {pkg:}::[]", "coerce pkg:::class_695",
                "setlocal 2",
            ),
            ((3, None),),
        ),
        (
            "compiled",
            (
                "getlocal 3", "pushint 1", "add_i", "convert_u",
                "setlocal 3",
            ),
            ((1, "increment"), (2, None)),
        ),
    ),
    "class_618/i/method method_7593": (
        (
            "original",
            (
                "getlex pkg:::class_279", "getproperty pkg:::var_369",
                "getlocal 2", "callproperty pkg:::method_4935 1",
                "coerce pkg:::class_279", "setlocal 3",
            ),
            ((4, None),),
        ),
        (
            "compiled",
            (
                "getlocal 3", "getproperty pkg:::var_8381", "coerce_s",
                "jump L67",
            ),
            ((2, None),),
        ),
    ),
    "class_525/i/method method_4838": (
        (
            "original",
            (
                "getlocal 6", "getlocal 5", "getproperty {pkg:}::[]",
                "coerce pkg:::class_695", "setlocal 1",
            ),
            ((3, None),),
        ),
        (
            "original",
            (
                "getlex pkg:::var_5829", "getlocal 2",
                "getproperty {pkg:}::[]", "coerce pkg:::class_695",
                "setlocal 1",
            ),
            ((3, None),),
        ),
        (
            "compiled",
            (
                "getlocal 4", "pushint 1", "add_i", "convert_u",
                "setlocal 4",
            ),
            ((1, "increment"), (2, None)),
        ),
        (
            "compiled",
            (
                "getlocal 7", "pushint 1", "add_i", "convert_u",
                "setlocal 7",
            ),
            ((1, "increment"), (2, None)),
        ),
    ),
    "class_278/i/method method_4083": (
        (
            "original",
            (
                "getlex pkg:::var_1906", "getproperty pkg:::var_10736",
                "getlocal 4", "getproperty pkg:::var_13666", "convert_i",
                "callproperty pkg:::method_4935 1", "coerce pkg:::class_123",
                "setlocal 5",
            ),
            ((6, None),),
        ),
        (
            "compiled",
            (
                "getlocal 4", "getproperty pkg:::mTimeStamp",
                "pushdouble 8000.0", "add", "convert_u",
                "getlocal 1",
            ),
            ((2, "pushint 8000"), (3, "add_i")),
        ),
    ),
    "class_579/s/method method_5587": (
        (
            "original",
            (
                "getlex pkg:::class_579", "getproperty pkg:::var_5450",
                "coerce pkg:haxe::IMap", "setlocal 3",
            ),
            ((2, None),),
        ),
    ),
    "class_579/s/method method_4716": (
        (
            "original",
            (
                "getlocal 1", "getlex pkg:haxe.ds::StringMap",
                "getproperty pkg:::reserved", "in", "iffalse L27",
                "getlocal 8", "getlocal 1", "callproperty pkg:::getReserved 1",
                "coerce pkg:haxe::IMap", "jump L31", "getlocal 8",
                "getproperty pkg:::h", "getlocal 1", "getproperty {pkg:}::[]",
                "coerce pkg:haxe::IMap", "setlocal 9",
            ),
            ((8, None), (14, None)),
        ),
        (
            "compiled",
            (
                "getlocal 1", "getlex pkg:haxe.ds::StringMap",
                "getproperty pkg:::reserved", "in", "iffalse L27",
                "getlocal 8", "getlocal 1", "callproperty pkg:::getReserved 1",
                "coerce pkg:haxe.ds::StringMap", "jump L32", "getlocal 8",
                "getproperty pkg:::h", "getlocal 1", "getproperty {pkg:}::[]",
                "coerce pkg:haxe.ds::StringMap", "setlocal 9",
            ),
            ((8, None), (14, None)),
        ),
    ),
    "class_579/s/method method_2002": (
        (
            "original",
            (
                "getlocal 8", "getlocal 2", "callproperty pkg:::getReserved 1",
                "coerce pkg:haxe::IMap", "jump L97", "getlocal 8",
                "getproperty pkg:::h", "getlocal 2", "getproperty {pkg:}::[]",
                "coerce pkg:haxe::IMap", "coerce pkg:haxe.ds::StringMap",
                "setlocal 10",
            ),
            ((3, None), (9, None), (10, None)),
        ),
        (
            "compiled",
            (
                "getlocal 8", "getlocal 2", "callproperty pkg:::getReserved 1",
                "coerce pkg:haxe.ds::StringMap", "jump L95", "getlocal 8",
                "getproperty pkg:::h", "getlocal 2", "getproperty {pkg:}::[]",
                "coerce pkg:haxe.ds::StringMap", "setlocal 10",
            ),
            ((3, None), (9, None)),
        ),
        (
            "original",
            (
                "getlocal 6", "coerce pkg:haxe.ds::StringMap", "setlocal 8",
            ),
            ((1, None),),
        ),
        (
            "original",
            (
                "getlocal 9", "getlocal 2", "callproperty pkg:::getReserved 1",
                "coerce pkg:haxe::IMap", "jump L55", "getlocal 9",
                "getproperty pkg:::h", "getlocal 2", "getproperty {pkg:}::[]",
                "coerce pkg:haxe::IMap",
            ),
            ((3, None), (9, None)),
        ),
        (
            "compiled",
            (
                "getlocal 9", "getlocal 2", "callproperty pkg:::getReserved 1",
                "coerce pkg:haxe.ds::StringMap", "jump L55", "getlocal 9",
                "getproperty pkg:::h", "getlocal 2", "getproperty {pkg:}::[]",
                "coerce pkg:haxe.ds::StringMap",
            ),
            ((3, None), (9, None)),
        ),
    ),
    "class_672/i/method method_6271": AUDITED_BOOLEAN_DOUBLE_NOT_RETURN,
}


def _duplicate_empty_string_concat(register: int):
    return (
        "compiled",
        (
            "pushstring ''", "pushstring ''", f"getlocal {register}",
            "add", "coerce_s", "add", "coerce_s",
        ),
        ((0, None), (5, None), (6, None)),
    )


AUDITED_DUPLICATE_EMPTY_STRING_CONCATS = {
    "class_406/i/method method_7032": (
        _duplicate_empty_string_concat(2),
    ),
    "StoreType/s/method method_4085": (
        _duplicate_empty_string_concat(1),
        _duplicate_empty_string_concat(2),
    ),
    "class_189/s/method method_3021": (
        _duplicate_empty_string_concat(1),
        _duplicate_empty_string_concat(2),
    ),
    "class_189/s/method method_5488": (
        _duplicate_empty_string_concat(2),
    ),
    "class_21/i/method method_4684": (
        _duplicate_empty_string_concat(1),
    ),
    "class_21/i/method method_8419": (
        _duplicate_empty_string_concat(1),
    ),
    "class_143/i/method method_8760": (
        _duplicate_empty_string_concat(2),
    ),
    "class_143/i/method method_2751": (
        _duplicate_empty_string_concat(1),
    ),
    "class_50/s/method method_6265": (
        _duplicate_empty_string_concat(1),
    ),
    "class_279/s/method method_1344": (
        _duplicate_empty_string_concat(1),
    ),
    "class_279/s/method method_3991": (
        _duplicate_empty_string_concat(1),
    ),
    "class_386/s/method method_6139": (
        _duplicate_empty_string_concat(2),
    ),
    "class_523/i/method method_889": (
        _duplicate_empty_string_concat(3),
    ),
    "class_524/i/method method_8312": (
        (
            "compiled",
            (
                "pushstring ''", "pushstring ''", "getlocal 1",
                "add", "coerce_s", "add",
            ),
            ((0, None), (4, None), (5, None)),
        ),
    ),
    "class_700/s/method method_5033": (
        _duplicate_empty_string_concat(1),
    ),
}


AUDITED_SCALAR_EXPRESSION_BOUNDARIES = {
    "class_143/i/method method_7143": (
        (
            "compiled",
            ("getlocal 3", "getlocal 5", "pushint 1", "bitor", "bitand"),
            ((1, "pushint 1"), (2, "getlocal 5")),
        ),
    ),
    "class_493/i/method method_3812": (
        (
            "compiled",
            ("pushint 300", "getlocal 3", "pushint 10", "multiply_i", "convert_u"),
            ((1, "pushint 10"), (2, "getlocal 3")),
        ),
    ),
    "class_493/i/method method_8103": (
        (
            "compiled",
            ("pushint 300", "getlocal 3", "pushint 10", "multiply_i", "convert_u"),
            ((1, "pushint 10"), (2, "getlocal 3")),
        ),
    ),
    "SpawnBot/i/method method_6307": (
        (
            "compiled",
            (
                "getlex pkg:::class_123", "getproperty pkg:::var_11606",
                "getlocal 6", "getproperty pkg:::var_1249", "bitand",
            ),
            (
                (0, "getlocal 6"), (1, "getproperty pkg:::var_1249"),
                (2, "getlex pkg:::class_123"), (3, "getproperty pkg:::var_11606"),
            ),
        ),
        (
            "compiled",
            (
                "getlex pkg:::class_123", "getproperty pkg:::var_3544",
                "getlocal 6", "getproperty pkg:::var_1249", "bitand",
            ),
            (
                (0, "getlocal 6"), (1, "getproperty pkg:::var_1249"),
                (2, "getlex pkg:::class_123"), (3, "getproperty pkg:::var_3544"),
            ),
        ),
    ),
    "class_608/iinit": (
        (
            "compiled",
            (
                "getlocal 2", "pushint 45", "multiply_i", "convert_u",
                "pushint 230", "add_i", "convert_u",
            ),
            (
                (0, "pushint 230"), (1, "getlocal 2"),
                (2, "pushint 45"), (3, "multiply_i"),
                (4, "add_i"), (5, "convert_u"), (6, None),
            ),
        ),
    ),
    "class_600/i/method OpenBattleLogOptions2": (
        (
            "original",
            ("pushint 700", "pushint 20", "subtract_i", "convert_u"),
            ((0, "pushint 680"), (1, None), (2, None), (3, None)),
        ),
        (
            "original",
            (
                "pushint 20", "getlex pkg:::var_12457",
                "callproperty pkg:::method_1833 0", "multiply_i",
            ),
            (
                (0, "getlex pkg:::var_12457"),
                (1, "callproperty pkg:::method_1833 0"),
                (2, "pushint 20"), (3, "multiply_i"),
            ),
        ),
    ),
    "class_611/s/method method_6775": (
        (
            "compiled",
            (
                "getlocal 2", "pushint 225", "multiply_i", "convert_u",
                "pushint 334", "add_i", "convert_u",
            ),
            (
                (0, "pushint 334"), (1, "pushint 225"),
                (2, "getlocal 2"), (3, "multiply_i"),
                (4, "add_i"), (5, "convert_u"), (6, None),
            ),
        ),
        (
            "compiled",
            (
                "pushint 275", "getlex pkg:::Math", "getlocal 1",
                "pushdouble 4.0", "divide", "callproperty pkg:::floor 1",
                "multiply_i", "convert_u", "pushint 250", "add_i",
                "convert_u",
            ),
            (
                (0, "pushint 250"), (1, "pushint 275"),
                (2, "getlex pkg:::Math"), (3, "getlocal 1"),
                (4, "pushdouble 4.0"), (5, "divide"),
                (6, "callproperty pkg:::floor 1"), (7, "multiply_i"),
                (8, "add_i"), (9, "convert_u"), (10, None),
            ),
        ),
    ),
    "class_697/i/method method_6097": (
        (
            "compiled",
            ("getlocal 1", "pushint 5", "multiply_i", "convert_u"),
            ((0, "pushint 5"), (1, "getlocal 1")),
        ),
        (
            "compiled",
            (
                "pushint 3684158", "pushbyte 1",
                "callpropvoid pkg:::beginFill 2",
            ),
            ((1, "pushdouble 1.0"),),
        ),
        (
            "compiled",
            (
                "pushbyte 0", "pushbyte 0", "pushint 180", "getlocal 4",
                "pushbyte 8", "pushbyte 8",
                "callpropvoid pkg:::drawRoundRect 6",
            ),
            (
                (0, "pushdouble 0.0"), (1, "pushdouble 0.0"),
                (2, "pushdouble 180.0"), (4, "pushdouble 8.0"),
                (5, "pushdouble 8.0"),
            ),
        ),
    ),
    "PowerType/i/method method_1416": (
        (
            "compiled",
            (
                "getlex pkg:::var_12468", "getlocal 1",
                "getproperty {pkg:}::[]", "convert_u", "pushint 65535",
                "bitand", "returnvalue",
            ),
            (
                (0, "pushuint 65535"), (1, "getlex pkg:::var_12468"),
                (2, "getlocal 1"), (3, "getproperty {pkg:}::[]"),
                (4, None),
            ),
        ),
    ),
    "PowerType/i/method method_6801": (
        (
            "compiled",
            (
                "getlex pkg:::var_12468", "getlocal 1",
                "getproperty {pkg:}::[]", "convert_u", "pushint -65536",
                "bitand", "pushint 16", "urshift", "returnvalue",
            ),
            (
                (0, "pushuint 4294901760"),
                (1, "getlex pkg:::var_12468"), (2, "getlocal 1"),
                (3, "getproperty {pkg:}::[]"), (4, None),
            ),
        ),
    ),
    "class_410/i/method method_3730": (
        (
            "compiled",
            (
                "getlocal 1", "pushint 1", "bitand", "pushint 340",
                "multiply_i", "convert_u", "getlocal 1", "pushint 1",
                "urshift", "convert_u", "pushint 60", "multiply_i",
                "convert_u",
            ),
            (
                (0, "pushint 340"), (1, "getlocal 1"),
                (2, "pushint 1"), (3, "bitand"),
                (6, "pushint 60"), (7, "getlocal 1"),
                (8, "pushint 1"), (9, None), (10, "urshift"),
            ),
        ),
    ),
    "class_451/i/method method_4403": (
        (
            "compiled",
            (
                "findpropstrict pkg:::method_1544",
                "getlex pkg:::var_871", "pushint 36", "multiply_i",
                "convert_u", "getlocal 2", "add_i", "convert_u",
                "callpropvoid pkg:::method_1544 1",
            ),
            ((1, "pushint 36"), (2, "getlex pkg:::var_871")),
        ),
    ),
    "class_451/i/method method_4828": (
        (
            "compiled",
            ("getlocal 3", "pushint 36", "multiply_i"),
            ((0, "pushint 36"), (1, "getlocal 3")),
        ),
    ),
    "StoreType/s/method method_4675": (
        (
            "original",
            (
                "pushint 100000", "getlocal 1", "add_i",
                "setstatic pkg:::var_6176",
            ),
            ((0, "getlocal 1"), (1, "pushint 100000")),
        ),
    ),
    "class_451/i/method method_5877": (
        (
            "compiled",
            (
                "pushstring ''", "getlocal 1", "getproperty pkg:::var_692",
                "add", "coerce_s",
            ),
            ((0, None), (3, None)),
        ),
        (
            "compiled",
            (
                "pushstring ''", "getlocal 1", "getproperty pkg:::var_202",
                "add", "coerce_s",
            ),
            ((0, None), (3, None)),
        ),
        (
            "compiled",
            (
                "pushstring ''", "getlocal 1", "getproperty pkg:::var_3217",
                "add", "coerce_s",
            ),
            ((0, None), (3, None)),
        ),
        (
            "compiled",
            (
                "pushstring ''", "getlocal 1", "getproperty pkg:::var_6905",
                "add", "coerce_s",
            ),
            ((0, None), (3, None)),
        ),
        (
            "compiled",
            (
                "getlex pkg:::var_8737", "pushstring ''", "pushstring ''",
                "getlocal 4", "getproperty pkg:::var_1076", "add",
                "coerce_s", "add", "coerce_s",
                "callpropvoid pkg:::method_4016 1",
            ),
            ((1, None), (7, None), (8, None)),
        ),
        (
            "compiled",
            (
                "getlex pkg:::var_4407", "pushstring ''", "pushstring ''",
                "getlocal 4", "getproperty pkg:::var_1076", "add",
                "coerce_s", "add", "coerce_s",
                "callpropvoid pkg:::method_4016 1",
            ),
            ((1, None), (7, None), (8, None)),
        ),
    ),
    "class_479/i/method method_6946": (
        (
            "original",
            (
                "pushint 197", "multiply_i", "pushint 1", "multiply_i",
                "pushint 13", "subtract_i",
            ),
            ((2, None), (3, None)),
        ),
    ),
    "class_313/i/method method_2119": (
        (
            "original",
            (
                "getproperty pkg:::var_11782", "getlex pkg:::var_14014",
                "getproperty {pkg:}::[]", "convert_u", "pushint 16777215",
                "bitand",
            ),
            ((3, None),),
        ),
        (
            "compiled",
            (
                "pushint 16777215", "bitand", "pushint 0", "urshift",
                "convert_i", "convert_u", "setlocal 12",
            ),
            ((4, None),),
        ),
    ),
    "class_313/i/method method_7267": (
        (
            "original",
            (
                "getproperty pkg:::var_11782", "getlex pkg:::var_14014",
                "getproperty {pkg:}::[]", "convert_u", "pushint 251658240",
                "bitand", "pushint 24", "urshift", "convert_u", "setlocal 2",
            ),
            ((3, None),),
        ),
        (
            "compiled",
            (
                "getproperty pkg:::var_11782", "getlex pkg:::var_14014",
                "getproperty {pkg:}::[]", "pushint 251658240", "bitand",
                "pushint 24", "urshift", "convert_i", "convert_u", "setlocal 2",
            ),
            ((7, None),),
        ),
    ),
    "class_40/i/method method_3327": (
        (
            "original",
            (
                "getproperty pkg:::var_12058", "add", "convert_d",
                "getlocal 3",
            ),
            ((2, None),),
        ),
        (
            "original",
            (
                "getproperty pkg:::var_13187", "add", "convert_d",
                "callpropvoid pkg:::method_6277 2",
            ),
            ((2, None),),
        ),
    ),
    "class_394/i/method Tick": (
        (
            "original",
            (
                "getlocal 2", "getproperty pkg:::x", "getlocal 2",
                "getproperty pkg:::var_10641", "getlocal 3", "multiply",
                "add", "convert_d", "setproperty pkg:::x",
            ),
            ((7, None),),
        ),
        (
            "original",
            (
                "getlocal 2", "getproperty pkg:::y", "getlocal 2",
                "getproperty pkg:::var_9512", "getlocal 3", "multiply",
                "add", "convert_d", "setproperty pkg:::y",
            ),
            ((7, None),),
        ),
    ),
    "class_104/i/method method_2156": (
        (
            "compiled",
            (
                "getlocal 3", "getproperty pkg:::var_6607",
                "pushdouble 1.0", "add", "convert_u", "setlocal 4",
            ),
            ((2, "pushint 1"), (3, "add_i")),
        ),
    ),
    "class_278/i/method method_1917": (
        (
            "compiled",
            (
                "getlocal 4", "getproperty pkg:::mTimeStamp",
                "pushdouble 60000.0", "add", "convert_u", "getlocal 1",
            ),
            ((2, "pushint 60000"), (3, "add_i")),
        ),
    ),
    "class_278/i/method method_2854": (
        (
            "compiled",
            (
                "getlocal 3", "getproperty pkg:::mTimeStamp",
                "pushdouble 4000.0", "subtract", "convert_u", "setlocal 7",
            ),
            ((2, "pushint 4000"), (3, "subtract_i")),
        ),
    ),
    "class_278/i/method method_6429": (
        (
            "compiled",
            (
                "getlocal 4", "getproperty pkg:::mTimeStamp",
                "pushdouble 14000.0", "add", "convert_u", "lessequals",
            ),
            ((2, "pushint 14000"), (3, "add_i")),
        ),
    ),
    "class_600/i/method method_7794": (
        (
            "compiled",
            (
                "getproperty {pkg:}::[]", "getproperty pkg:::timestamp",
                "pushdouble 1814400.0", "add", "convert_u",
                "getlex pkg:::var_1906",
            ),
            ((2, "pushint 1814400"), (3, "add_i")),
        ),
    ),
    "class_274/i/method method_1741": (
        (
            "original",
            (
                "getlex pkg:::class_276", "getproperty pkg:::var_230",
                "getproperty pkg:::h", "pushuint 2147483644",
                "getlocal 1", "setproperty {pkg:}::[]",
            ),
            ((3, "pushint 2147483644"),),
        ),
    ),
    "class_274/i/method method_3566": (
        (
            "original",
            (
                "getlex pkg:::class_276", "getproperty pkg:::var_230",
                "getproperty pkg:::h", "pushuint 2147483644",
                "pushnull", "setproperty {pkg:}::[]",
            ),
            ((3, "pushint 2147483644"),),
        ),
    ),
    "TrailEffect/i/method Start": (
        (
            "original",
            (
                "getlex pkg:::var_13546", "getlocal 2",
                "getproperty {pkg:}::[]", "pushuint 4294967295",
                "convert_u", "callpropvoid pkg:::method_8361 1",
            ),
            ((3, "pushbyte -1"),),
        ),
    ),
}


def _hide_function_coerce(register: int):
    return (
        "original",
        (
            f"getlocal {register}", "getproperty pkg:::var_2793",
            "getproperty pkg:::Hide", "coerce pkg:::Function",
            "callpropvoid pkg:::method_4056 5",
        ),
        ((3, None),),
    )


AUDITED_FUNCTION_COERCE_BOUNDARIES = {
    "class_666/i/method method_5378": (_hide_function_coerce(1),),
    "class_666/i/method method_8134": (_hide_function_coerce(2),),
    "class_667/i/method method_5378": (_hide_function_coerce(1),),
    "class_667/i/method method_7273": (_hide_function_coerce(1),),
    "class_667/i/method method_8134": (_hide_function_coerce(2),),
    "class_423/i/method method_859": (
        (
            "original",
            (
                "getlocal 3", "getlocal 3",
                "getproperty pkg:::GetAccentColor", "coerce pkg:::Function",
                "getlocal 1", "pushnull", "constructprop pkg:::class_427 4",
            ),
            ((3, None),),
        ),
        (
            "original",
            (
                "getlocal 7", "getlocal 4",
                "getproperty pkg:::GetAccentColor", "coerce pkg:::Function",
                "getlocal 4", "getproperty pkg:::method_3614",
                "coerce pkg:::Function", "getlocal 4",
                "getproperty pkg:::GetTabKey", "coerce pkg:::Function",
                "getlocal 4", "constructprop pkg:::class_427 5",
            ),
            ((3, None), (6, None), (9, None)),
        ),
    ),
}


def _apply_audited_pairwise_rewrites(
        lines: list[str], exceptions: list[str],
        audits: tuple[tuple[str, tuple[str, ...], tuple[tuple[int, str | None], ...]], ...],
        side: str) -> tuple[list[str], list[str]] | None:
    for audited_side, sequence, replacements in audits:
        if audited_side != side:
            continue
        starts = [
            i for i in range(len(lines) - len(sequence) + 1)
            if tuple(lines[i:i + len(sequence)]) == sequence
        ]
        if not starts:
            rewritten = dict(replacements)
            target = tuple(
                rewritten.get(offset, line) for offset, line in enumerate(sequence)
                if rewritten.get(offset, line) is not None
            )
            if target != sequence and sum(
                    1 for i in range(len(lines) - len(target) + 1)
                    if tuple(lines[i:i + len(target)]) == target) == 1:
                continue
        if len(starts) != 1:
            return None
        start = starts[0]
        lines, exceptions = _rebuild(lines, exceptions, {
            start + offset: replacement
            for offset, replacement in replacements
        })
    return lines, exceptions


def rule_audited_scalar_expression_boundaries(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    audits = AUDITED_SCALAR_EXPRESSION_BOUNDARIES.get(key)
    if audits is None or original_exceptions or compiled_exceptions:
        return False
    normalized_original = _apply_audited_pairwise_rewrites(
        original, original_exceptions, audits, "original",
    )
    normalized_compiled = _apply_audited_pairwise_rewrites(
        compiled, compiled_exceptions, audits, "compiled",
    )
    return (normalized_original is not None
            and normalized_compiled is not None
            and normalized_original == normalized_compiled)


def rule_audited_function_coerce_boundaries(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    audits = AUDITED_FUNCTION_COERCE_BOUNDARIES.get(key)
    if audits is None or original_exceptions or compiled_exceptions:
        return False
    normalized_original = _apply_audited_pairwise_rewrites(
        original, original_exceptions, audits, "original",
    )
    normalized_compiled = _apply_audited_pairwise_rewrites(
        compiled, compiled_exceptions, audits, "compiled",
    )
    return (normalized_original is not None
            and normalized_compiled is not None
            and normalized_original == normalized_compiled)


AUDITED_DUPLICATE_STATIC_RECEIVERS = {
    "class_323/s/method method_1111": (
        "pkg:::var_14809", "getlocal 3", "pkg:::var_11598", "add_i",
    ),
    "class_670/s/method method_760": (
        "pkg:::var_14877", "getlocal 0", "pkg:::var_14877", "multiply",
    ),
}


def rule_audited_duplicate_static_receivers(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    spec = AUDITED_DUPLICATE_STATIC_RECEIVERS.get(key)
    if (spec is None or original_exceptions or compiled_exceptions
            or len(original) != len(compiled) or "setlocal 0" in original
            or "setlocal 0" in compiled):
        return False
    field, rhs_receiver, rhs_field, operator = spec
    original_window = (
        "getlocal 0", "getlocal 0", f"getproperty {field}", rhs_receiver,
        f"getproperty {rhs_field}", operator, f"setproperty {field}",
    )
    compiled_window = (
        "getlocal 0", "dup", f"getproperty {field}", rhs_receiver,
        f"getproperty {rhs_field}", operator, f"setproperty {field}",
    )
    original_starts = [
        i for i in range(len(original) - len(original_window) + 1)
        if tuple(original[i:i + len(original_window)]) == original_window
    ]
    compiled_starts = [
        i for i in range(len(compiled) - len(compiled_window) + 1)
        if tuple(compiled[i:i + len(compiled_window)]) == compiled_window
    ]
    if (len(original_starts) != 1 or len(compiled_starts) != 1
            or original_starts[0] != compiled_starts[0]):
        return False
    start = original_starts[0]
    window_indices = set(range(start + 1, start + len(original_window)))
    if (branch_targets(original, original_exceptions) & window_indices
            or branch_targets(compiled, compiled_exceptions) & window_indices):
        return False
    normalized = list(compiled)
    normalized[start + 1] = "getlocal 0"
    return original == normalized


AUDITED_DUPLICATE_RMW_RECEIVERS = {
    "class_377/i/method method_8592": ((
        ("getlex pkg:::class_377",), "pkg:::var_11721",
        ("pushint 1", "getlocal 1", "lshift"), "bitor",
    ),),
    "class_574/i/method method_1013": ((
        ("getlex pkg:::var_12837",), "pkg:::var_1250",
        ("getlex pkg:::class_574", "getproperty pkg:::var_12627"), "bitor",
    ),),
    "class_81/i/method method_686": ((
        ("getlex pkg:::var_9222",), "pkg:::var_9826", ("getlocal 3",), "add_i",
    ),),
    "class_143/i/method method_8917": ((
        ("getlex pkg:::var_8999",), "pkg:::var_2458", ("pushint 64",), "bitxor",
    ),),
    "class_340/i/method method_556": ((
        ("getlex pkg:::var_1906", "getproperty pkg:::var_8999"),
        "pkg:::var_2458", ("pushint 4",), "bitor",
    ),),
    "class_512/i/method OnInitDisplay": ((
        ("getlex pkg:::var_1906", "getproperty pkg:::var_8999"),
        "pkg:::var_2458", ("pushint 4",), "bitor",
    ),),
    "class_283/i/method method_4241": ((
        ("getlex pkg:::var_1906", "getproperty pkg:::var_6237"),
        "pkg:::var_15194", ("getlocal 1",), "add_i",
    ),),
    "LinkUpdater/i/method method_3194": ((
        ("getlex pkg:::var_1906", "getproperty pkg:::var_6237"),
        "pkg:::var_5215", ("getlocal 2",), "add_i",
    ),),
    "class_295/i/method method_8123": ((
        ("getlex pkg:::var_594",), "pkg:::var_1249",
        (
            "getlex pkg:::class_123", "getproperty pkg:::var_11250",
            "getlex pkg:::class_123", "getproperty pkg:::var_3544",
            "bitor", "bitnot",
        ),
        "bitand",
    ),),
    "class_298/i/method method_6524": (
        (
            ("getlex pkg:::var_1827",), "pkg:::var_1278",
            ("getlocal 3",), "add_i",
        ),
        (
            ("getlex pkg:::var_1827",), "pkg:::var_2198",
            ("getlocal 3",), "add_i",
        ),
    ),
    'LinkUpdater/i/method method_1506': ((('getlex pkg:::var_1906', 'getproperty pkg:::var_6237'), 'pkg:::var_5215', ('getlocal 2',), 'add_i'),),
    'LinkUpdater/i/method method_331': ((('getlex pkg:::var_1906', 'getproperty pkg:::var_6237'), 'pkg:::var_2506', ('getlex pkg:::var_1906', 'getproperty pkg:::var_2703', 'getlocal 5', 'subtract_i'), 'add_i'),),
    'LinkUpdater/i/method method_537': ((('getlex pkg:::var_1906', 'getproperty pkg:::var_6237'), 'pkg:::var_2506', ('getlex pkg:::var_1906', 'getproperty pkg:::var_2703', 'getlocal 5', 'subtract_i'), 'add_i'), (('getlex pkg:::var_1906', 'getproperty pkg:::var_6237'), 'pkg:::var_3624', ('getlex pkg:::var_1906', 'getproperty pkg:::var_138', 'getlocal 5', 'subtract_i'), 'add_i'), (('getlex pkg:::var_1906', 'getproperty pkg:::var_6237'), 'pkg:::var_4778', ('getlex pkg:::var_1906', 'getproperty pkg:::var_13314', 'getlocal 5', 'subtract_i'), 'add_i')),
    'LinkUpdater/i/method method_7460': ((('getlex pkg:::var_1906',), 'pkg:::var_13969', ('getlex pkg:::class_51', 'getproperty pkg:::var_36'), 'subtract_i'),),
    'LinkUpdater/i/method method_8842': ((('getlex pkg:::var_1906', 'getproperty pkg:::var_12494'), 'pkg:::var_12839', ('pushint 16',), 'bitor'), (('getlex pkg:::var_1906', 'getproperty pkg:::var_12494'), 'pkg:::var_12839', ('pushint -17',), 'bitand')),
    'LinkUpdater/i/method method_913': ((('getlex pkg:::var_1906', 'getproperty pkg:::var_6237'), 'pkg:::var_12317', ('getlocal 3', 'getproperty pkg:::var_10618'), 'add_i'),),
    'class_255/i/method method_3606': ((('getlex pkg:::class_323',), 'pkg:::var_10470', ('getlex pkg:::var_3636',), 'subtract_i'), (('getlex pkg:::class_323',), 'pkg:::var_14809', ('getlex pkg:::var_11598',), 'subtract_i'), (('getlex pkg:::class_323',), 'pkg:::var_10470', ('getlex pkg:::var_3636',), 'add_i'), (('getlex pkg:::class_323',), 'pkg:::var_14809', ('getlex pkg:::var_11598',), 'add_i')),
    'class_274/i/method method_7616': ((('getlex pkg:::var_1906', 'getproperty pkg:::var_6237'), 'pkg:::var_15102', ('getlocal 55',), 'add_i'),),
    'class_298/i/method method_960': ((('getlex pkg:::var_1827',), 'pkg:::var_1278', ('getlocal 1', 'getproperty pkg:::var_6840'), 'add_i'), (('getlex pkg:::var_1827',), 'pkg:::var_2198', ('getlocal 1', 'getproperty pkg:::var_6840'), 'add_i')),
    'class_344/i/method method_5774': ((('getlex pkg:::var_1906', 'getproperty pkg:::var_2208'), 'pkg:::var_10783', ('pushint 1000',), 'add_i'),),
    'class_344/i/method method_594': ((('getlex pkg:::var_1906', 'getproperty pkg:::var_2208'), 'pkg:::var_10783', ('getlocal 14', 'pushint 100', 'multiply_i'), 'add_i'),),
    'class_511/i/method method_7193': ((('getlex pkg:::var_1906', 'getproperty pkg:::var_8999'), 'pkg:::var_2458', ('pushint 4',), 'bitxor'),),
    'class_512/i/method OnClearScreen': ((('getlex pkg:::var_1906', 'getproperty pkg:::var_8999'), 'pkg:::var_2458', ('pushint -5',), 'bitand'), (('getlex pkg:::var_1906', 'getproperty pkg:::var_8999'), 'pkg:::var_2458', ('pushint 4',), 'bitor')),
    'class_52/i/method method_5992': ((('getlex pkg:::var_1906', 'getproperty pkg:::var_8999'), 'pkg:::var_2458', ('pushint 4',), 'bitor'),),
    'class_52/i/method method_6324': ((('getlex pkg:::var_1906', 'getproperty pkg:::var_8999'), 'pkg:::var_2458', ('pushint 4',), 'bitxor'),),
}


def rule_audited_duplicate_rmw_receivers(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    specs = AUDITED_DUPLICATE_RMW_RECEIVERS.get(key)
    if (specs is None or original_exceptions or compiled_exceptions
            or "setlocal 0" in original or "setlocal 0" in compiled):
        return False
    normalized_original = list(original)
    normalized_exceptions = list(original_exceptions)
    for receiver, field, rhs, operator in specs:
        original_window = (
            *receiver, *receiver, f"getproperty {field}", *rhs, operator,
            f"setproperty {field}",
        )
        compiled_window = (
            *receiver, "dup", f"getproperty {field}", *rhs, operator,
            f"setproperty {field}",
        )
        original_starts = [
            i for i in range(len(normalized_original) - len(original_window) + 1)
            if tuple(normalized_original[i:i + len(original_window)]) == original_window
        ]
        compiled_starts = [
            i for i in range(len(compiled) - len(compiled_window) + 1)
            if tuple(compiled[i:i + len(compiled_window)]) == compiled_window
        ]
        if len(original_starts) != 1 or len(compiled_starts) != 1:
            return False
        original_start = original_starts[0]
        compiled_start = compiled_starts[0]
        second_receiver = original_start + len(receiver)
        if (branch_targets(normalized_original, normalized_exceptions)
                & set(range(original_start + 1, original_start + len(original_window)))):
            return False
        if (branch_targets(compiled, compiled_exceptions)
                & set(range(compiled_start + 1,
                            compiled_start + len(compiled_window)))):
            return False
        replacements = {second_receiver: "dup"}
        replacements.update({
            second_receiver + offset: None
            for offset in range(1, len(receiver))
        })
        normalized_original, normalized_exceptions = _rebuild(
            normalized_original, normalized_exceptions, replacements,
        )
    return (normalized_original == compiled
            and normalized_exceptions == compiled_exceptions)


def rule_audited_closed_reference_scalar_boundaries(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    audits = AUDITED_CLOSED_REFERENCE_SCALAR_BOUNDARIES.get(key)
    if audits is None or original_exceptions or compiled_exceptions:
        return False
    normalized_original = _apply_audited_pairwise_rewrites(
        original, original_exceptions, audits, "original",
    )
    normalized_compiled = _apply_audited_pairwise_rewrites(
        compiled, compiled_exceptions, audits, "compiled",
    )
    return (normalized_original is not None
            and normalized_compiled is not None
            and normalized_original == normalized_compiled)


def rule_audited_duplicate_empty_string_concats(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    audits = AUDITED_DUPLICATE_EMPTY_STRING_CONCATS.get(key)
    if audits is None or original_exceptions or compiled_exceptions:
        return False
    normalized_original = _apply_audited_pairwise_rewrites(
        original, original_exceptions, audits, "original",
    )
    normalized_compiled = _apply_audited_pairwise_rewrites(
        compiled, compiled_exceptions, audits, "compiled",
    )
    return (normalized_original is not None
            and normalized_compiled is not None
            and normalized_original == normalized_compiled)


AUDITED_CLASS136_INCREMENT_TEMPS = "class_193/i/method method_7204"


def rule_audited_class136_increment_temps(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    if (key != AUDITED_CLASS136_INCREMENT_TEMPS or original_exceptions
            or compiled_exceptions):
        return False

    def remove_prologue(lines: list[str], expected: int):
        if lines[:2] != ["getlocal 0", "pushscope"]:
            return None
        changed: dict[int, None] = {}
        i = 2
        while (i + 1 < len(lines) and lines[i] == "pushnull"
               and lines[i + 1].startswith("setlocal ")):
            changed[i] = None
            changed[i + 1] = None
            i += 2
        if (len(changed) != expected * 2 or i >= len(lines)
                or lines[i] != "getlex pkg:::var_13287"):
            return None
        if branch_targets(lines, []) & set(changed):
            return None
        return _rebuild(lines, [], changed)[0]

    normalized_original = remove_prologue(original, 2)
    normalized_compiled = remove_prologue(compiled, 3)
    if normalized_original is None or normalized_compiled is None:
        return False

    changed: dict[int, str | None] = {}
    targets = branch_targets(normalized_compiled, [])
    for field in ("pkg:::var_10446", "pkg:::var_10898"):
        starts: list[int] = []
        for i in range(len(normalized_compiled) - 6):
            if (normalized_compiled[i] != "coerce pkg:::class_136"
                    or not normalized_compiled[i + 1].startswith("setlocal ")):
                continue
            reg = normalized_compiled[i + 1].split(" ", 1)[1]
            if normalized_compiled[i + 2:i + 7] == [
                f"getlocal {reg}", f"getlocal {reg}",
                f"getproperty {field}", "increment", f"setproperty {field}",
            ]:
                starts.append(i)
        if len(starts) != 1:
            return False
        start = starts[0]
        removed = {start + 1, start + 2, start + 3}
        if targets & removed:
            return False
        changed[start + 1] = "dup"
        changed[start + 2] = None
        changed[start + 3] = None

    normalized_compiled = _rebuild(normalized_compiled, [], changed)[0]
    normalized_original, _ = rule_registers(normalized_original, 4)
    normalized_compiled, _ = rule_registers(normalized_compiled, 4)
    return normalized_original == normalized_compiled


AUDITED_MODULAR_UINT_ARITHMETIC = {
    "class_14/i/method PostRollback": (
        (("getlocal 2", "getproperty pkg:::mTimeStamp"),
         "subtract_i", "subtract",
         ("convert_u", "pushdouble 41.666666666666664")),
    ),
    "class_235/i/method method_7060": (
        (("subtract_i", "getproperty {pkg:}::[]"),
         "add_i", "add", ("returnvalue",)),
    ),
    "class_271/i/method method_2831": (
        (("pushbyte 0", "getproperty {pkg:}::[]"),
         "add_i", "add",
         ("setproperty pkg:::var_678", "findpropstrict pkg:::var_1269")),
    ),
    "class_281/i/method method_6522": (
        (("getlocal 6", "getproperty pkg:::var_11488"),
         "add_i", "add", ("convert_u", "getlocal 7")),
        (("getlocal 6", "getproperty pkg:::var_11488"),
         "add_i", "add", ("convert_u", "setlocal 7")),
    ),
    "class_370/i/method method_3889": (
        (("pushbyte 1", "getproperty {pkg:}::[]"),
         "add_i", "add", ("convert_u", "getlex pkg:::var_4790")),
        (("pushbyte 2", "getproperty {pkg:}::[]"),
         "add_i", "add", ("convert_u", "convert_i")),
    ),
    "class_385/i/method method_5676": (
        (("getlex pkg:::var_7257", "getproperty {pkg:}::[]"),
         "subtract_i", "subtract",
         ("setproperty pkg:::var_11462", "getlex pkg:::var_11462")),
    ),
    "class_713/i/method method_9118": (
        (("getlocal 4", "getproperty pkg:::var_692"),
         "subtract_i", "subtract", ("convert_u", "convert_i")),
        (("getlocal 4", "getproperty pkg:::var_202"),
         "subtract_i", "subtract", ("convert_u", "convert_i")),
        (("getlocal 4", "getproperty pkg:::var_3217"),
         "subtract_i", "subtract", ("convert_u", "convert_i")),
        (("getlocal 4", "getproperty pkg:::var_6905"),
         "subtract_i", "subtract", ("convert_u", "convert_i")),
    ),
    "class_81/i/method PostRollback": (
        (("getproperty pkg:::var_14247", "getproperty pkg:::var_2572"),
         "add_i", "add", ("convert_u", "getlocal 2")),
        (("getlocal 2", "getproperty pkg:::var_13001"),
         "subtract_i", "subtract", ("convert_u", "convert_i")),
        (("getproperty pkg:::var_14247", "getproperty pkg:::var_2572"),
         "add_i", "add", ("convert_u", "getlocal 2")),
        (("getlocal 2", "getproperty pkg:::var_13001"),
         "subtract_i", "subtract", ("convert_u", "convert_i")),
    ),
    "class_82/i/method method_4637": (
        (("getlocal 3", "getproperty {pkg:}::[]"),
         "add_i", "add", ("convert_u", "getlex pkg:::var_1590")),
    ),
}


def rule_audited_modular_uint_arithmetic(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    expected = AUDITED_MODULAR_UINT_ARITHMETIC.get(key)
    if (expected is None or original_exceptions or compiled_exceptions
            or len(original) != len(compiled)):
        return False
    actual = []
    for i, (left, right) in enumerate(zip(original, compiled)):
        if left == right:
            continue
        actual.append((
            tuple(original[max(0, i - 2):i]),
            left,
            right,
            tuple(original[i + 1:min(len(original), i + 3)]),
        ))
    return tuple(actual) == expected


def rule_audited_closed_string_map_interface_boundary(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    field = AUDITED_CLOSED_STRING_MAP_INTERFACE_BOUNDARIES.get(key)
    if field is None or original_exceptions or compiled_exceptions:
        return False
    common = (
        f"getstatic {field}",
        "getproperty pkg:::h",
        "getlocal 1",
        "getproperty {pkg:}::[]",
    )
    original_sequence = (
        *common,
        "coerce pkg:haxe::IMap",
        "coerce pkg:haxe.ds::StringMap",
        "setlocal 4",
    )
    compiled_sequence = (
        *common,
        "coerce pkg:haxe.ds::StringMap",
        "setlocal 4",
    )
    original_starts = [
        i for i in range(len(original) - len(original_sequence) + 1)
        if tuple(original[i:i + len(original_sequence)]) == original_sequence
    ]
    compiled_starts = [
        i for i in range(len(compiled) - len(compiled_sequence) + 1)
        if tuple(compiled[i:i + len(compiled_sequence)]) == compiled_sequence
    ]
    if len(original_starts) != 1 or len(compiled_starts) != 1:
        return False
    removed = original_starts[0] + len(common)
    return _rebuild(original, [], {removed: None}) == (compiled, compiled_exceptions)


def rule_audited_map_backing_has_key(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    if (key not in AUDITED_MAP_BACKING_HAS_KEY
            or original_exceptions or compiled_exceptions):
        return False
    changed: dict[int, str | None] = {}
    hits = 0
    for i in range(len(compiled) - 4):
        if (compiled[i] == f"getlex {AS3_HELPER_QNAME}"
                and compiled[i + 1].startswith("getlocal ")
                and compiled[i + 2] == "getproperty pkg:::h"
                and compiled[i + 3].startswith(("getlocal ", "pushstring "))
                and compiled[i + 4] == "callproperty pkg:::hasKey 2"):
            changed.update({
                i: compiled[i + 3],
                i + 3: "in",
                i + 4: None,
            })
            hits += 1
    expected_hits = AUDITED_MAP_BACKING_HAS_KEY_COUNTS.get(key, 1)
    return hits == expected_hits and _rebuild(compiled, [], changed) == (
        original, original_exceptions,
    )


def rule_audited_closed_imap_local_store(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    audited = AUDITED_CLOSED_IMAP_LOCAL_STORES.get(key)
    if audited is None or original_exceptions or compiled_exceptions:
        return False
    field = audited
    common = (
        f"getlex {field}",
        "getproperty pkg:::h",
        "getlocal 1",
        "getproperty {pkg:}::[]",
    )
    original_starts = [
        i for i in range(len(original) - len(common) - 1)
        if tuple(original[i:i + len(common)]) == common
        and original[i + len(common)] == "coerce pkg:haxe::IMap"
        and original[i + len(common) + 1].startswith("setlocal ")
    ]
    compiled_starts = [
        i for i in range(len(compiled) - len(common))
        if tuple(compiled[i:i + len(common)]) == common
        and compiled[i + len(common)].startswith("setlocal ")
    ]
    if len(original_starts) != 1 or len(compiled_starts) != 1:
        return False
    original_store = original[original_starts[0] + len(common) + 1]
    compiled_store = compiled[compiled_starts[0] + len(common)]
    if original_store != compiled_store:
        return False
    removed = original_starts[0] + len(common)
    return _rebuild(original, [], {removed: None}) == (compiled, compiled_exceptions)


def rule_audited_class25_nested_map_boundary(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    if (key != AUDITED_CLASS25_NESTED_MAP_BOUNDARY
            or original_exceptions or compiled_exceptions
            or original.count("coerce pkg:haxe::IMap") != 2
            or original.count("coerce pkg:haxe.ds::IntMap") != 1
            or "coerce pkg:haxe::IMap" in compiled
            or "coerce pkg:haxe.ds::IntMap" in compiled):
        return False
    join_starts = [
        i for i in range(len(original) - 6)
        if original[i] == "getlocal 3"
        and re.fullmatch(r"iffalse L\d+", original[i + 1])
        and original[i + 2] == "getstatic pkg:::var_12608"
        and re.fullmatch(r"jump L\d+", original[i + 3])
        and original[i + 4:i + 7] == [
            "getstatic pkg:::var_8936", "coerce pkg:haxe::IMap",
            "setlocal 5",
        ]
    ]
    read_starts = [
        i for i in range(len(original) - 7)
        if original[i:i + 8] == [
            "getlocal 5", "getproperty pkg:::h", "getlocal 4",
            "getproperty {pkg:}::[]", "coerce pkg:haxe::IMap",
            "coerce pkg:haxe.ds::IntMap", "getproperty pkg:::h",
            "getlocal 2",
        ]
    ]
    if len(join_starts) != 1 or len(read_starts) != 1:
        return False
    helper_starts = [
        i for i in range(len(compiled) - 4)
        if compiled[i:i + 5] == [
            f"getlex {AS3_HELPER_QNAME}", "getlocal 5",
            "getproperty pkg:::h", "getlocal 4",
            "callproperty pkg:::hasKey 2",
        ]
    ]
    native_starts = [
        i for i in range(len(compiled) - 3)
        if compiled[i:i + 4] == ["getlocal 4", "getlocal 5", "getproperty pkg:::h", "in"]
    ]
    if (len(helper_starts), len(native_starts)) not in ((1, 0), (0, 1)):
        return False
    removed = {
        join_starts[0] + 5: None,
        read_starts[0] + 4: None,
        read_starts[0] + 5: None,
    }
    lowered = {}
    if helper_starts:
        helper = helper_starts[0]
        lowered = {
            helper: compiled[helper + 3],
            helper + 3: "in",
            helper + 4: None,
        }
    return _rebuild(original, [], removed) == _rebuild(compiled, [], lowered)


def rule_audited_controller_mapping_imap_join(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    if (key not in AUDITED_CONTROLLER_MAPPING_IMAP_JOINS
            or original_exceptions or compiled_exceptions
            or original.count("coerce pkg:haxe::IMap") != 1
            or "coerce pkg:haxe::IMap" in compiled):
        return False
    starts: list[int] = []
    for i in range(len(original) - 6):
        if (original[i] == "getlocal 1"
                and re.fullmatch(r"iffalse L\d+", original[i + 1])
                and original[i + 2] == "getlex pkg:::var_2970"
                and re.fullmatch(r"jump L\d+", original[i + 3])
                and original[i + 4] == "getlex pkg:::var_8548"
                and original[i + 5] == "coerce pkg:haxe::IMap"
                and original[i + 6].startswith("setlocal ")):
            starts.append(i)
    if len(starts) != 1:
        return False
    removed = starts[0] + 5
    return _rebuild(original, [], {removed: None}) == (compiled, compiled_exceptions)


def rule_audited_extension_context_factory_stores(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    audit = AUDITED_EXTENSION_CONTEXT_FACTORY_STORES.get(key)
    if audit is None or original_exceptions or compiled_exceptions:
        return False
    field, extension_id, store_kind = audit
    factory = (
        "getlex pkg:flash.external::ExtensionContext",
        f"pushstring '{extension_id}'",
        "pushnull",
        "callproperty pkg:::createExtensionContext 2",
    )

    if store_kind == "static":
        store = f"setstatic {field}"

        def normalize(lines: list[str], *, expect_coerce: bool):
            changed: dict[int, str | None] = {}
            hits = 0
            width = len(factory) + 1 + int(expect_coerce)
            for i in range(len(lines) - width + 1):
                if tuple(lines[i:i + len(factory)]) != factory:
                    continue
                cursor = i + len(factory)
                if expect_coerce:
                    if lines[cursor] != "coerce pkg:flash.external::ExtensionContext":
                        continue
                    changed[cursor] = None
                    cursor += 1
                if lines[cursor] != store:
                    continue
                hits += 1
            if hits != 1:
                return None
            return _rebuild(lines, [], changed)

        normalized_original = normalize(original, expect_coerce=False)
        normalized_compiled = normalize(compiled, expect_coerce=True)
    else:
        original_sequence = (*factory, f"findpropstrict {field}", "swap", f"setproperty {field}")
        compiled_sequence = (
            f"findpropstrict {field}", *factory,
            "coerce pkg:flash.external::ExtensionContext", f"setproperty {field}",
        )

        def normalize_instance(lines: list[str], sequence: tuple[str, ...],
                               marker_index: int):
            starts = [
                i for i in range(len(lines) - len(sequence) + 1)
                if tuple(lines[i:i + len(sequence)]) == sequence
            ]
            if len(starts) != 1:
                return None
            start = starts[0]
            changed = {start + i: None for i in range(len(sequence))}
            changed[start + marker_index] = f"set-extension-context {field} '{extension_id}'"
            return _rebuild(lines, [], changed)

        normalized_original = normalize_instance(
            original, original_sequence, len(factory) - 1,
        )
        normalized_compiled = normalize_instance(
            compiled, compiled_sequence, len(factory),
        )

    return (normalized_original is not None and normalized_compiled is not None
            and normalized_original == normalized_compiled)


def rule_audited_closed_map_local_stores(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    audit = AUDITED_CLOSED_MAP_LOCAL_STORES.get(key)
    if audit is None or original_exceptions or compiled_exceptions:
        return False
    field, *expected = audit

    read_coerces: dict[int, None] = {}
    constructed_coerces: dict[int, None] = {}
    constructed_value_coerces: dict[int, None] = {}
    for i, line in enumerate(original):
        if not line.startswith("coerce ") or i == 0 or i + 1 >= len(original):
            continue
        if not original[i + 1].startswith("setlocal "):
            continue
        window = original[max(0, i - 6):i]
        field_read = any(
            window[j] == f"getlex {field}" and window[j + 1] == "getproperty pkg:::h"
            for j in range(len(window) - 1)
        )
        if (line == "coerce pkg:haxe::IMap"
                and original[i - 1] == "getproperty {pkg:}::[]" and field_read):
            read_coerces[i] = None
            continue
        if i < 4 or not original[i - 1].startswith("getlocal "):
            continue
        source = original[i - 1].partition(" ")[2]
        if original[i - 2] != f"setlocal {source}":
            continue
        if (line == "coerce pkg:haxe::IMap"
                and original[i - 3] == "constructprop pkg:haxe.ds::IntMap 0"
                and original[i - 4] == "findpropstrict pkg:haxe.ds::IntMap"):
            constructed_coerces[i] = None
        elif (line == "coerce pkg:::class_166"
                and original[i - 3] == "constructprop pkg:::class_166 0"
                and original[i - 4] == "findpropstrict pkg:::class_166"):
            constructed_value_coerces[i] = None

    if [len(read_coerces), len(constructed_coerces), len(constructed_value_coerces)] != expected:
        return False
    if any(line == "coerce pkg:haxe::IMap" for line in compiled):
        return False

    rebuilt_original = _rebuild(
        original, original_exceptions,
        {**read_coerces, **constructed_coerces, **constructed_value_coerces},
    )
    return rebuilt_original == (compiled, compiled_exceptions)


def rule_audited_controller_map_boundaries(
        original: list[str], original_exceptions: list[str],
        compiled: list[str], compiled_exceptions: list[str], key: str) -> bool:
    expected_object_coerces = AUDITED_CONTROLLER_MAP_BOUNDARIES.get(key)
    if expected_object_coerces is None or original_exceptions or compiled_exceptions:
        return False

    original_deletes: dict[int, None] = {}
    for i, line in enumerate(original):
        if line != "coerce pkg:flash.ui::GameInputControl" or i < 3 or i + 1 >= len(original):
            continue
        if (original[i - 3] == "getlex pkg:::var_3088"
                and original[i - 2].startswith("getlex pkg:::var_")
                and original[i - 1] == "callproperty pkg:::method_4935 1"
                and original[i + 1] == "pushnull"):
            original_deletes[i] = None
    if len(original_deletes) != 1:
        return False

    compiled_deletes: dict[int, None] = {}
    for i, line in enumerate(compiled):
        if line != "coerce pkg:::Object" or i == 0 or i + 2 >= len(compiled):
            continue
        if (compiled[i - 1] == "getproperty {pkg:}::[]"
                and compiled[i + 1].startswith("pushdouble ")
                and compiled[i + 2] in {"lessequals", "greaterequals"}):
            compiled_deletes[i] = None
    if len(compiled_deletes) != expected_object_coerces:
        return False

    rebuilt_original = _rebuild(original, original_exceptions, original_deletes)
    rebuilt_compiled = _rebuild(compiled, compiled_exceptions, compiled_deletes)
    return rebuilt_original == rebuilt_compiled


def rule_audited_enum_class_argument(lines: list[str], exceptions: list[str], key: str):
    expected = AUDITED_ENUM_CLASS_ARGUMENTS.get(key)
    if expected is None or exceptions:
        return (lines, exceptions), False
    found: list[tuple[str, str]] = []
    changed: dict[int, None] = {}
    for i, line in enumerate(lines):
        if line != "coerce pkg:::Class" or i < 2 or i + 1 >= len(lines):
            continue
        if lines[i - 2] != "getlex pkg:::Type" or not lines[i - 1].startswith("getlex "):
            continue
        enum_class = lines[i - 1].partition(" ")[2]
        helper = None
        if lines[i + 1] == "callproperty pkg:::allEnums 1":
            helper = "allEnums"
        elif (i + 3 < len(lines)
              and lines[i + 1].startswith("getlocal ")
              and lines[i + 2] == "pushnull"
              and lines[i + 3] == "callproperty pkg:::createEnumIndex 3"):
            helper = "createEnumIndex"
        elif (key == "class_479/i/method method_4553" and i + 4 < len(lines)
              and lines[i + 1] == "getlex pkg:::var_1253"
              and lines[i + 2] == "convert_i"
              and lines[i + 3] == "pushnull"
              and lines[i + 4] == "callproperty pkg:::createEnumIndex 3"):
            helper = "createEnumIndex"
        elif (key == "class_479/i/method method_4553" and i + 3 < len(lines)
              and lines[i + 1:i + 4] == ["getlex pkg:::var_1253", "pushnull",
                                         "callproperty pkg:::createEnumIndex 3"]):
            helper = "createEnumIndex"
        elif (key == "class_479/i/method method_4097" and i + 6 < len(lines)
              and lines[i + 1:i + 7] == [
                  "getlex pkg:::var_5056", "getlex pkg:::var_1253",
                  "getproperty {pkg:}::[]", "convert_i", "pushnull",
                  "callproperty pkg:::createEnumIndex 3",
              ]):
            helper = "createEnumIndex"
        if helper is not None:
            found.append((enum_class, helper))
            changed[i] = None
    if sorted(found) != sorted(expected):
        return (lines, exceptions), False
    return _rebuild(lines, exceptions, changed), True


def rule_dominating_reference_coerce(lines, exceptions):
    if exceptions:
        return (lines, exceptions), False
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    i = 0
    while i + 1 < len(lines):
        first = _operand(lines[i], "coerce")
        final = _operand(lines[i + 1], "coerce")
        if ((final in CONSTRUCTIBLE_CLASSES or final == "pkg:::Function")
                and first in {final, "pkg:::Object"}
                and i not in targets and i + 1 in targets):
            changed[i] = None
            i += 2
            continue
        i += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_idempotent_coerce_jump(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str] = {}
    for i in range(len(lines) - 1):
        coerce = lines[i]
        if not (coerce.startswith("coerce ") or coerce in IDEMPOTENT):
            continue
        labels = LABEL.findall(lines[i + 1]) if lines[i + 1].startswith("jump ") else []
        if len(labels) != 1 or i + 1 in targets:
            continue
        k = int(labels[0])
        if k + 1 < len(lines) and lines[k] == coerce:
            changed[i + 1] = f"jump L{k + 1}"
    if not changed:
        return (lines, exceptions), False
    out = [changed.get(i, line) for i, line in enumerate(lines)]
    targets = branch_targets(out, exceptions)
    repeats: dict[int, None] = {
        i + 1: None for i in range(len(out) - 1)
        if out[i] == out[i + 1] and i + 1 not in targets
        and (out[i].startswith("coerce ") or out[i] in IDEMPOTENT)
    }
    if repeats:
        return _rebuild(out, exceptions, repeats), True
    return (out, exceptions), True


def rule_math_nan(lines, exceptions):
    def match(a, b):
        if a == "getlex pkg:::Math" and b == "getproperty pkg:::NaN":
            return "pushnan", None
    return _pairs(lines, exceptions, match)


def rule_branch_bool(lines, exceptions):
    def match(a, b):
        if a == "convert_b" and b.startswith(("iftrue ", "iffalse ")):
            return None, b
    return _pairs(lines, exceptions, match, keep_second_target=True)


def rule_object_coerce_branch(lines, exceptions):
    def match(a, b):
        if a == "coerce pkg:::Object" and b.startswith(("iftrue ", "iffalse ")):
            return None, b
    return _pairs(lines, exceptions, match, keep_second_target=True)


def rule_constant_branch(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    i = 0
    while i + 1 < len(lines):
        if i + 1 in targets:
            i += 1
            continue
        value, branch = lines[i], lines[i + 1]
        head, _, label = branch.partition(" ")
        if value == "pushfalse" and head == "iftrue":
            changed[i], changed[i + 1] = None, None
            i += 2
            continue
        if value == "pushtrue" and head == "iffalse":
            changed[i], changed[i + 1] = None, None
            i += 2
            continue
        if ((value == "pushtrue" and head == "iftrue")
                or (value == "pushfalse" and head == "iffalse")):
            changed[i], changed[i + 1] = f"jump {label}", None
            i += 2
            continue
        i += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


INVERT_BRANCH = {
    "iffalse": "iftrue",
    "iftrue": "iffalse",
    "ifeq": "ifne",
    "ifne": "ifeq",
    "iflt": "ifnlt",
    "ifnlt": "iflt",
    "ifle": "ifnle",
    "ifnle": "ifle",
    "ifgt": "ifngt",
    "ifngt": "ifgt",
    "ifge": "ifnge",
    "ifnge": "ifge",
    "ifstricteq": "ifstrictne",
    "ifstrictne": "ifstricteq",
}


def rule_branch_jump_simplify(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    i = 0
    while i + 1 < len(lines):
        head, _, rest = lines[i].partition(" ")
        if head in INVERT_BRANCH and rest == f"L{i + 2}" and lines[i + 1].startswith("jump ") and i + 1 not in targets:
            changed[i] = INVERT_BRANCH[head] + " " + lines[i + 1].split(" ", 1)[1]
            changed[i + 1] = None
            i += 2
            continue
        i += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_jump_next(lines, exceptions):
    changed = {}
    for i, line in enumerate(lines):
        if line == f"jump L{i + 1}":
            changed[i] = None
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_jump_trampoline(lines, exceptions):
    handlers = exception_targets(exceptions)
    changed: dict[int, str] = {}

    def final_target(start: int) -> int:
        target = start
        seen: set[int] = set()
        while (0 <= target < len(lines) and target not in handlers
               and lines[target].startswith("jump ")):
            if target in seen:
                return start
            seen.add(target)
            labels = LABEL.findall(lines[target])
            if len(labels) != 1:
                return start
            target = int(labels[0])
        return target

    for i, line in enumerate(lines):
        head = line.split(" ", 1)[0]
        if not head.startswith(("if", "jump", "lookupswitch")):
            continue
        rewritten = LABEL.sub(lambda m: f"L{final_target(int(m.group(1)))}", line)
        if rewritten != line:
            changed[i] = rewritten
    if not changed:
        return (lines, exceptions), False
    threaded, threaded_exceptions = _rebuild(lines, exceptions, changed)
    return drop_unreachable(threaded, threaded_exceptions), True


SWITCH_REGION_EXITS = ("jump", "returnvalue", "returnvoid", "throw")


def _switch_tail_default_body(lines: list[str], switch: int, default: int) -> bool:
    operands = lines[switch].split(" ")[1:]
    if not all(re.fullmatch(r"L\d+", operand) for operand in operands):
        return False
    if not lines[default - 1].split(" ", 1)[0] in SWITCH_REGION_EXITS:
        return False
    if lines[-1].split(" ", 1)[0] not in ("returnvalue", "returnvoid", "throw", "jump"):
        return False
    if any(int(t) > default for t in LABEL.findall(lines[switch])[1:]):
        return False
    for i, line in enumerate(lines):
        if i == switch or not line.split(" ", 1)[0].startswith(("if", "jump", "lookupswitch")):
            continue
        labels = [int(t) for t in LABEL.findall(line)]
        if default in labels:
            return False
        if i < default and any(t > default for t in labels):
            return False
    return True


def rule_switch_case_layout(lines, exceptions):
    if exceptions:
        return (lines, exceptions), False
    for s, line in enumerate(lines):
        if not line.startswith("lookupswitch "):
            continue
        targets = [int(t) for t in LABEL.findall(line)]
        if len(targets) < 2:
            continue
        default, cases = targets[0], targets[1:]
        default_body = False
        if default == s + 1 and s + 1 < len(lines) and lines[s + 1].startswith("jump "):
            end_labels = LABEL.findall(lines[s + 1])
            if len(end_labels) != 1:
                continue
            end = int(end_labels[0])
            first = s + 2
        elif default > s + 1 and _switch_tail_default_body(lines, s, default):
            default_body = True
            first = s + 1
            end = len(lines)
        elif default > s + 1:
            end = default
            first = s + 1
        elif default == s + 1:
            default_body = True
            first = s + 1
            starts = sorted(set(cases) | {default})
            tails = set()
            for nxt in starts[1:]:
                tail = lines[nxt - 1]
                labels = LABEL.findall(tail) if tail.startswith("jump ") else []
                if labels and int(labels[0]) >= starts[-1]:
                    tails.add(int(labels[0]))
            if len(tails) > 1:
                continue
            end = tails.pop() if tails else len(lines)
        else:
            continue
        if default_body:
            starts = sorted((set(cases) | {default}) - {end})
        else:
            starts = sorted(set(cases) - {default, end})
        if not starts or starts[0] != first or end <= starts[-1] or end > len(lines):
            continue
        bounds = starts + [end]
        regions = [(bounds[i], bounds[i + 1]) for i in range(len(starts))]
        jump_end = f"jump L{end}"
        ok = True
        bodies: list[tuple[int, list[int], bool]] = []
        for index, (lo, hi) in enumerate(regions):
            body = list(range(lo, hi))
            if body and lines[body[-1]] == jump_end:
                body = body[:-1]
            last_head = lines[body[-1]].split(" ", 1)[0] if body else ""
            exits = last_head in SWITCH_REGION_EXITS
            if index < len(regions) - 1 and lines[hi - 1].split(" ", 1)[0] not in SWITCH_REGION_EXITS:
                ok = False
                break
            if default_body and lo == default:
                highest = -1
            else:
                highest = max(v for v, t in enumerate(cases) if t == lo)
            bodies.append((highest, body, exits))
        if not ok:
            continue
        bodies.sort(key=lambda item: item[0])
        layout: list[int | None] = list(range(first))
        for index, (_, body, exits) in enumerate(bodies):
            layout.extend(body)
            if not exits and index < len(bodies) - 1:
                layout.append(None)
        layout.extend(range(end, len(lines)))
        new_index = {old: new for new, old in enumerate(layout) if old is not None}
        new_index[len(lines)] = len(layout)
        for old in range(first, end):
            if old not in new_index:
                new_index[old] = new_index[end]

        def relabel(text: str) -> str:
            return LABEL.sub(lambda m: f"L{new_index[int(m.group(1))]}", text)

        out = []
        for old in layout:
            if old is None:
                out.append(f"jump L{new_index[end]}")
                continue
            text = lines[old]
            out.append(relabel(text) if text.split(" ", 1)[0].startswith(("if", "jump", "lookupswitch")) else text)
        if out != lines:
            return (out, exceptions), True
    return (lines, exceptions), False


TERMINAL_LITERAL_PUSHES = {
    "pushbyte", "pushdouble", "pushfalse", "pushint", "pushnan", "pushnull",
    "pushshort", "pushstring", "pushtrue", "pushuint", "pushundefined",
}


def rule_terminal_literal_return(lines, exceptions):
    if exceptions:
        return (lines, exceptions), False
    branch_refs: dict[int, list[int]] = {}
    for i, line in enumerate(lines):
        head = line.split(" ", 1)[0]
        if head.startswith(("if", "jump", "lookupswitch")):
            for label in LABEL.findall(line):
                branch_refs.setdefault(int(label), []).append(i)

    candidates: dict[int, tuple[str, int | None]] = {}
    for start in range(len(lines) - 1):
        producer = lines[start]
        if producer.split(" ", 1)[0] not in TERMINAL_LITERAL_PUSHES or lines[start + 1] != "returnvalue":
            continue
        if branch_refs.get(start + 1):
            continue
        predecessor: int | None = None
        if start:
            prev_head = lines[start - 1].split(" ", 1)[0]
            if prev_head not in EXITS and not prev_head.startswith("if"):
                continue
            if prev_head.startswith("if"):
                labels = LABEL.findall(lines[start - 1])
                if len(labels) != 1 or int(labels[0]) != start + 2 or prev_head not in INVERT_BRANCH:
                    continue
                predecessor = start - 1
        if not branch_refs.get(start):
            continue
        candidates[start] = (f"@return[{producer}]", predecessor)

    continuation_targets = {start + 2 for start, (_, predecessor) in candidates.items()
                            if predecessor is not None}
    for start in continuation_targets:
        candidates.pop(start, None)
    if not candidates:
        return (lines, exceptions), False

    changed: dict[int, str | None] = {}
    for start, (terminal, predecessor) in candidates.items():
        for source in branch_refs.get(start, []):
            changed[source] = re.sub(rf"\bL{start}\b", terminal, changed.get(source, lines[source]))
        if predecessor is not None:
            head = lines[predecessor].split(" ", 1)[0]
            changed[predecessor] = f"{INVERT_BRANCH[head]} {terminal}"
        changed[start] = None
        changed[start + 1] = None
    return _rebuild(lines, exceptions, changed), True


def rule_terminal_local_return(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    i = 0
    while i + 2 < len(lines):
        set_head, _, reg = lines[i].partition(" ")
        if (set_head == "setlocal" and lines[i + 1] == f"getlocal {reg}"
                and lines[i + 2] == "returnvalue"
                and not targets & {i, i + 1, i + 2}):
            changed[i] = None
            changed[i + 1] = None
            i += 3
            continue
        i += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_terminal_jump_return(lines, exceptions):
    if exceptions:
        return (lines, exceptions), False
    changed: dict[int, str] = {}
    for i, line in enumerate(lines):
        if not line.startswith("jump L"):
            continue
        labels = LABEL.findall(line)
        if len(labels) == 1 and 0 <= int(labels[0]) < len(lines) and lines[int(labels[0])] == "returnvalue":
            changed[i] = "returnvalue"
    if not changed:
        return (lines, exceptions), False
    rewritten = _rebuild(lines, exceptions, changed)
    return drop_unreachable(*rewritten), True


def rule_void_call(lines, exceptions):
    def match(a, b):
        if b != "pop":
            return None
        if a.startswith("callproperty "):
            return "callpropvoid " + a.split(" ", 1)[1], None
        if a.startswith("callsuper "):
            return "callsupervoid " + a.split(" ", 1)[1], None
        return None
    return _pairs(lines, exceptions, match)


AS3_HELPER_QNAME = "pkg:port.runtime::As3"
AS3_HELPER_CONVERSIONS = {
    "coerceString": "coerce_s",
    "toBool": "convert_b",
    "toFloat": "convert_d",
    "toInt": "convert_i",
    "toUInt": "convert_u",
}
AS3_AS_TYPE_MARKERS = {
    "pkg:_UInt::UInt_Impl_": "pkg:::uint",
}
STACK_PUSH_OPS = {
    "pushbyte", "pushdouble", "pushfalse", "pushint", "pushnan", "pushnamespace", "pushnull",
    "pushshort", "pushstring", "pushtrue", "pushuint", "pushundefined",
}


def _callproperty(line: str) -> tuple[str, int] | None:
    head, _, rest = line.partition(" ")
    if head != "callproperty":
        return None
    name, _, argc = rest.rpartition(" ")
    return (name, int(argc)) if argc.isdigit() else None


def _stack_delta(line: str) -> int | None:
    head, _, rest = line.partition(" ")
    if head in ("getlex", "findpropstrict", "findproperty", "getlocal", "getglobalscope", "getscopeobject",
                "getouterscope", "newfunction") or head in STACK_PUSH_OPS:
        return 1
    if head in ("coerce", "coerce_a", "coerce_b", "coerce_d", "coerce_i", "coerce_s", "coerce_u", "coerce_o",
                "convert_b", "convert_d", "convert_i", "convert_o", "convert_s", "convert_u", "astype",
                "astypelate", "checkfilter", "not", "negate", "negate_i", "increment", "increment_i",
                "decrement", "decrement_i", "bitnot", "swap"):
        return 0
    if head == "getproperty":
        if rest == "rt::[]":
            return -2
        if rest.startswith("{") and rest.endswith("}::[]"):
            return -1
        return 0
    if head == "setlocal":
        return -1
    if head in ("kill", "inclocal", "declocal", "inclocal_i", "declocal_i"):
        return 0
    if head in ("add", "subtract", "multiply", "divide", "modulo", "lshift", "rshift", "urshift", "bitand",
                "bitor", "bitxor", "equals", "strictequals", "lessthan", "lessequals", "greaterthan",
                "greaterequals", "instanceof", "istype", "istypelate", "in", "add_i", "subtract_i",
                "multiply_i"):
        return -1
    if head in ("dup",):
        return 1
    if head in ("pop", "pushscope"):
        return -1
    if head == "applytype" and rest.isdigit():
        return -int(rest)
    if head == "construct" and rest.isdigit():
        return -int(rest)
    if head == "call" and rest.isdigit():
        return -(int(rest) + 1)
    if head in ("newarray",) and rest.isdigit():
        return 1 - int(rest)
    if head in ("newobject",) and rest.isdigit():
        return 1 - (int(rest) * 2)
    if head in ("callproperty", "callproplex", "constructprop") and rest.rpartition(" ")[2].isdigit():
        return -int(rest.rpartition(" ")[2])
    if head in ("callpropvoid", "callsupervoid") and rest.rpartition(" ")[2].isdigit():
        return -(int(rest.rpartition(" ")[2]) + 1)
    if head in ("setproperty", "initproperty"):
        if rest == "rt::[]":
            return -4
        if rest.startswith("{") and rest.endswith("}::[]"):
            return -3
        return -2
    if head in ("returnvalue", "returnvoid", "throw") or head.startswith(("if", "jump", "lookupswitch")):
        return None
    return None


def rule_as3_helper_conversions(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    i = 0
    while i < len(lines):
        if lines[i] != f"getlex {AS3_HELPER_QNAME}" or i in changed:
            i += 1
            continue
        depth = 1
        j = i + 1
        while j < len(lines):
            if j in targets:
                break
            call = _callproperty(lines[j])
            if call is not None and call[1] == 1:
                helper = call[0].rsplit("::", 1)[-1]
                if helper in AS3_HELPER_CONVERSIONS and depth == 2:
                    changed[i] = None
                    changed[j] = AS3_HELPER_CONVERSIONS[helper]
                    i = j + 1
                    break
            delta = _stack_delta(lines[j])
            if delta is None:
                break
            depth += delta
            if depth < 1:
                break
            j += 1
        else:
            i += 1
            continue
        if i != j + 1:
            i += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def _one_label(line: str) -> int | None:
    labels = LABEL.findall(line)
    return int(labels[0]) if len(labels) == 1 else None


def _straight_line_depth(lines: list[str], start: int, end: int, depth: int,
                         blocked_targets: set[int]) -> int | None:
    for i in range(start, end):
        if i in blocked_targets:
            return None
        delta = _stack_delta(lines[i])
        if delta is None:
            return None
        depth += delta
        if depth < 1:
            return None
    return depth


def rule_as3_helper_branch_conversion(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    handlers = exception_targets(exceptions)
    changed: dict[int, str | None] = {}
    i = 0
    while i < len(lines):
        if lines[i] != f"getlex {AS3_HELPER_QNAME}" or i in targets:
            i += 1
            continue
        branch = i + 1
        while branch < len(lines):
            head = lines[branch].partition(" ")[0]
            if head in INVERT_BRANCH:
                break
            if branch in targets or _stack_delta(lines[branch]) is None:
                branch = -1
                break
            branch += 1
        if branch < 0 or branch >= len(lines):
            i += 1
            continue
        false_start = _one_label(lines[branch])
        if false_start is None or false_start <= branch + 1 or false_start > len(lines):
            i += 1
            continue
        jump_index = false_start - 1
        if jump_index <= branch or jump_index >= len(lines) or not lines[jump_index].startswith("jump "):
            i += 1
            continue
        join = _one_label(lines[jump_index])
        if join is None or join <= false_start or join >= len(lines):
            i += 1
            continue
        call = _callproperty(lines[join])
        helper = call[0].rsplit("::", 1)[-1] if call and call[1] == 1 else None
        if helper not in AS3_HELPER_CONVERSIONS:
            i += 1
            continue
        allowed_targets = {false_start, join}
        blocked = targets - allowed_targets
        if handlers & {i, branch, jump_index, join, false_start}:
            i += 1
            continue
        if branch in targets or jump_index in targets:
            i += 1
            continue
        condition_depth = _straight_line_depth(lines, i + 1, branch, 1, blocked)
        true_depth = _straight_line_depth(lines, branch + 1, jump_index, 1, blocked)
        false_depth = _straight_line_depth(lines, false_start, join, 1, blocked)
        branch_head = lines[branch].partition(" ")[0]
        expected_condition_depth = 2 if branch_head in ("iftrue", "iffalse") else 3
        if condition_depth == expected_condition_depth and true_depth == 2 and false_depth == 2:
            changed[i] = None
            changed[join] = AS3_HELPER_CONVERSIONS[helper]
            i = join + 1
            continue
        i += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def _depths_before_index(lines: list[str], start: int, end: int, depth: int,
                         blocked_targets: set[int]) -> set[int] | None:
    work = [(start, depth)]
    seen: set[tuple[int, int]] = set()
    arrivals: set[int] = set()
    while work:
        index, current = work.pop()
        if (index, current) in seen:
            continue
        seen.add((index, current))
        if len(seen) > 128:
            return None
        if index == end:
            arrivals.add(current)
            continue
        if index < start or index > end or index in blocked_targets or current < 1:
            return None
        line = lines[index]
        head = line.split(" ", 1)[0]
        labels = [int(label) for label in LABEL.findall(line)]
        if head in INVERT_BRANCH:
            next_depth = current - (1 if head in {"iftrue", "iffalse"} else 2)
            if next_depth < 1 or len(labels) != 1:
                return None
            work.append((index + 1, next_depth))
            work.append((labels[0], next_depth))
        elif head == "jump":
            if len(labels) != 1:
                return None
            work.append((labels[0], current))
        elif head == "lookupswitch":
            next_depth = current - 1
            if next_depth < 1 or not labels:
                return None
            work.extend((label, next_depth) for label in labels)
        elif head in {"returnvalue", "returnvoid", "throw"}:
            return None
        else:
            delta = _stack_delta(line)
            if delta is None:
                return None
            work.append((index + 1, current + delta))
    return arrivals


def rule_as3_helper_cfg_conversion(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    handlers = exception_targets(exceptions)
    edges = branch_edges(lines)
    receivers = [i for i, line in enumerate(lines) if line == f"getlex {AS3_HELPER_QNAME}"]
    changed: dict[int, str | None] = {}
    for call_index, line in enumerate(lines):
        call = _callproperty(line)
        helper = call[0].rsplit("::", 1)[-1] if call and call[1] == 1 else None
        if helper not in AS3_HELPER_CONVERSIONS:
            continue
        candidates: list[int] = []
        for receiver in reversed(receivers):
            if receiver >= call_index:
                continue
            if call_index - receiver > 128:
                break
            if receiver in changed or handlers & set(range(receiver, call_index + 1)):
                continue
            if any(not (receiver <= source < call_index)
                   for source, target in edges if receiver < target <= call_index):
                continue
            internal_targets = {
                target for source, target in edges
                if receiver < source < call_index and receiver < target <= call_index
            }
            blocked = targets - internal_targets - {receiver}
            if _depths_before_index(lines, receiver + 1, call_index, 1, blocked) == {2}:
                candidates.append(receiver)
        if len(candidates) == 1:
            changed[candidates[0]] = None
            changed[call_index] = AS3_HELPER_CONVERSIONS[helper]
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_as3_to_bool_branch(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    handlers = exception_targets(exceptions)
    edges = branch_edges(lines)
    changed: dict[int, str | None] = {}
    i = 0
    while i + 2 < len(lines):
        if lines[i] != f"getlex {AS3_HELPER_QNAME}" or i in targets:
            i += 1
            continue
        j = i + 1
        while j + 1 < len(lines):
            if j - i > 64:
                break
            if j in handlers:
                break
            call = _callproperty(lines[j])
            next_head = lines[j + 1].partition(" ")[0]
            if call == ("pkg:::toBool", 1) and next_head in ("iftrue", "iffalse"):
                if handlers & set(range(i, j + 2)):
                    break
                external_entry = any(src < i or src > j + 1 for src, dst in edges if i < dst <= j)
                if external_entry:
                    break
                blocked = (targets - {dst for src, dst in edges if i < src < j}) | {i}
                depths = _depths_before_index(lines, i + 1, j, 1, blocked)
                if depths == {2}:
                    changed[i] = None
                    changed[j] = None
                    i = j + 2
                    break
            if j in targets:
                break
            head = lines[j].partition(" ")[0]
            if head in {"returnvalue", "returnvoid", "throw"}:
                break
            j += 1
        i += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_as3_as_type(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    i = 0
    while i < len(lines):
        if lines[i] != f"getlex {AS3_HELPER_QNAME}" or i in changed:
            i += 1
            continue
        depth = 1
        j = i + 1
        while j + 1 < len(lines):
            if j in targets:
                break
            t = _operand(lines[j], "getlex")
            call = _callproperty(lines[j + 1]) if j + 1 not in targets else None
            if (t and is_type(t) and t not in SHADOWED and call in (("pkg:::asType", 2), ("pkg:::asTypeValue", 2)) and depth == 2):
                changed[i] = None
                changed[j] = None
                changed[j + 1] = "astype " + t
                i = j + 2
                break
            delta = _stack_delta(lines[j])
            if delta is None:
                break
            depth += delta
            if depth < 1:
                break
            j += 1
        else:
            i += 1
            continue
        if i != j + 2:
            i += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_as3_as_type_marker(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    i = 0
    while i < len(lines):
        if lines[i] != f"getlex {AS3_HELPER_QNAME}" or i in changed:
            i += 1
            continue
        depth = 1
        j = i + 1
        while j + 1 < len(lines):
            if j in targets:
                break
            marker = _operand(lines[j], "getlex")
            call = _callproperty(lines[j + 1]) if j + 1 not in targets else None
            typ = AS3_AS_TYPE_MARKERS.get(marker or "")
            if typ and call in (("pkg:::asType", 2), ("pkg:::asTypeValue", 2)) and depth == 2:
                changed[i] = None
                changed[j] = None
                changed[j + 1] = "astype " + typ
                i = j + 2
                break
            delta = _stack_delta(lines[j])
            if delta is None:
                break
            depth += delta
            if depth < 1:
                break
            j += 1
        else:
            i += 1
            continue
        if i != j + 2:
            i += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_as3_as_type_null(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    i = 0
    while i + 3 < len(lines):
        if (lines[i] == f"getlex {AS3_HELPER_QNAME}"
                and lines[i + 1] == "pushnull"
                and (lines[i + 2].startswith(PURE_PUSH) or lines[i + 2] in PURE_PUSH_BARE)
                and _callproperty(lines[i + 3]) in (("pkg:::asType", 2), ("pkg:::asTypeValue", 2))
                and not targets & {i + 1, i + 2, i + 3}):
            changed.update({i: None, i + 2: None, i + 3: None})
            i += 4
            continue
        i += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_return_convert(lines, exceptions, ret):
    def match(a, b):
        if b == "returnvalue" and ret != "*" and (CONVERT_FOR_RETURN.get(a) == ret or a == f"coerce {ret}"):
            return None, b
    return _pairs(lines, exceptions, match, keep_second_target=True)


def rule_return_astype_object_coerce(lines, exceptions, ret):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    if ret == "*":
        return (lines, exceptions), False
    for i in range(len(lines) - 2):
        if (lines[i] == f"astype {ret}" and lines[i + 1] == "coerce pkg:::Object"
                and lines[i + 2] == "returnvalue" and i + 1 not in targets):
            changed[i + 1] = None
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_const_number(lines, exceptions):
    def match(a, b):
        head, _, n = a.partition(" ")
        if b == "convert_d" and (head == "pushdouble" or a == "pushnan"):
            return a, None
        if head in ("pushbyte", "pushshort", "pushint") and b == "convert_d" and n.lstrip("-").isdigit():
            return f"pushdouble {float(int(n))!r}", None
    return _pairs(lines, exceptions, match)


def rule_const_number_fold(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    i = 0
    while i + 2 < len(lines):
        a, b, op = lines[i:i + 3]
        if (a.startswith("pushdouble ") and b.startswith("pushdouble ")
                and op in ("add", "subtract", "multiply", "divide") and not targets & {i + 1, i + 2}):
            try:
                x, y = float(a.split(" ", 1)[1]), float(b.split(" ", 1)[1])
                value = {"add": x + y, "subtract": x - y, "multiply": x * y}[op] if op != "divide" else x / y
            except (ValueError, ZeroDivisionError):
                value = None
            if value is not None and math.isfinite(value):
                changed.update({i: f"pushdouble {value!r}", i + 1: None, i + 2: None})
                i += 3
                continue
        i += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


NUMERIC_OPS = {"add", "subtract", "multiply", "divide", "modulo", "equals", "strictequals",
               "lessthan", "lessequals", "greaterthan", "greaterequals"}
NUMERIC_BRANCHES = {"ifeq", "ifne", "iflt", "ifle", "ifgt", "ifge", "ifstricteq", "ifstrictne",
                    "ifnlt", "ifnle", "ifngt", "ifnge"}
NUMBER_RESULT_OPS = {"multiply", "subtract", "divide", "modulo", "convert_d", "coerce_d", "negate"}
INT_OPS = {"add_i", "subtract_i", "multiply_i", "bitand", "bitor", "bitxor", "lshift", "rshift", "urshift"}


def integer_literal(line: str) -> int | None:
    head, _, value = line.partition(" ")
    if head in ("pushbyte", "pushshort", "pushint", "pushuint") and value.lstrip("-").isdigit():
        return int(value)
    if head == "pushdouble":
        try:
            n = float(value)
        except ValueError:
            return None
        return int(n) if n.is_integer() and -(2 ** 31) <= n <= 2 ** 31 - 1 else None
    return None


def numeric_literal_for_type(n: int, typ: str) -> str | None:
    if typ == "pkg:::Number":
        return f"pushdouble {float(n)!r}"
    if typ == "pkg:::int":
        value = n & 0xFFFFFFFF
        if value >= 0x80000000:
            value -= 0x100000000
        return f"pushint {value}"
    if typ == "pkg:::uint":
        return f"pushuint {n & 0xFFFFFFFF}"
    return None


def numeric_owner_literal_for_type(n: int, typ: str) -> str | None:
    if typ == "pkg:::uint" and 0 <= n <= 0x7FFFFFFF:
        return f"pushint {n}"
    return numeric_literal_for_type(n, typ)


def int32(n: int) -> int:
    value = n & 0xFFFFFFFF
    return value - 0x100000000 if value >= 0x80000000 else value


def rule_const_bitwise(lines, exceptions):
    hit = False
    while True:
        (lines, exceptions), changed = _const_bitwise_pass(lines, exceptions)
        if not changed:
            return (lines, exceptions), hit
        hit = True


def _const_bitwise_pass(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    i = 0
    while i < len(lines):
        if i + 1 < len(lines) and (value := integer_literal(lines[i])) is not None:
            if lines[i + 1] == "bitnot" and i + 1 not in targets:
                changed.update({i: f"pushint {int32(~int32(value))}", i + 1: None})
                i += 2
                continue
        if i + 2 >= len(lines):
            break
        left = integer_literal(lines[i])
        right = integer_literal(lines[i + 1])
        op = lines[i + 2]
        if (left is not None and right is not None and op in {"bitor", "bitand", "bitxor"}
                and not targets & {i + 1, i + 2}):
            a, b = int32(left), int32(right)
            if op == "bitor":
                result = a | b
            elif op == "bitand":
                result = a & b
            else:
                result = a ^ b
            changed.update({i: f"pushint {int32(result)}", i + 1: None, i + 2: None})
            i += 3
            continue
        i += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_public_index_namespace(lines, exceptions):
    changed: dict[int, str] = {}
    for i, line in enumerate(lines):
        head, _, rest = line.partition(" ")
        if head not in {"getproperty", "setproperty"}:
            continue
        if rest.endswith("::[]") and rest.startswith("{") and rest != "{pkg:}::[]" and "pkg:" in rest:
            changed[i] = f"{head} {{pkg:}}::[]"
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_int_op_convert(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    for i in range(len(lines) - 1):
        if lines[i] in {"convert_i", "convert_u"} and lines[i + 1] in INT_OPS and i not in targets:
            changed[i] = None
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_vector_modulo_index_convert(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    handlers = exception_targets(exceptions)
    changed: dict[int, str | None] = {}
    for i in range(3, len(lines)):
        if (lines[i - 3:i + 1] != ["convert_u", "pushdouble 128.0", "modulo", "convert_i"]
                or i in targets or i in handlers):
            continue
        direct_read = i + 1 < len(lines) and lines[i + 1] == "getproperty {pkg:}::[]"
        direct_write = (i + 2 < len(lines) and lines[i + 1].startswith("getlocal ")
                        and lines[i + 2] == "setproperty {pkg:}::[]"
                        and not targets & {i + 1, i + 2}
                        and not handlers & {i + 1, i + 2})
        if direct_read or direct_write:
            changed[i] = None
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_integral_modulo_convert(lines, exceptions, slot_context=None):
    targets = branch_targets(lines, exceptions)
    handlers = exception_targets(exceptions)
    changed: dict[int, str | None] = {}
    integer_producers = INT_OPS | {"convert_i", "convert_u", "coerce_i", "coerce_u"}
    for i in range(3, len(lines)):
        if lines[i] != "convert_i" or lines[i - 1] != "modulo":
            continue
        divisor = integer_literal(lines[i - 2])
        if divisor is None or not 0 < divisor <= 0x7FFFFFFF:
            continue
        producer = lines[i - 3]
        head = producer.partition(" ")[0]
        integral = (head in integer_producers or integer_literal(producer) is not None
                    or _typed_read(producer, slot_context) in {"pkg:::int", "pkg:::uint"})
        if (integral and not (targets | handlers) & {i - 2, i - 1, i}):
            changed[i] = None
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_numeric_literal_context(lines, exceptions, ret, slot_context=None):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    for i, line in enumerate(lines):
        n = integer_literal(line)
        next_head, _, next_rest = lines[i + 1].partition(" ") if i + 1 < len(lines) else ("", "", "")
        if n is None and next_head in INT_OPS and line.startswith("pushdouble "):
            try:
                double_value = float(line.split(" ", 1)[1])
            except ValueError:
                double_value = float("nan")
            if (double_value.is_integer()
                    and -(2 ** 31) <= double_value <= 2 ** 32 - 1):
                changed[i] = numeric_literal_for_type(int(double_value), "pkg:::int")
            continue
        if n is None:
            continue
        if next_head in NUMERIC_OPS or next_head in NUMERIC_BRANCHES:
            changed[i] = f"pushdouble {float(n)!r}"
        elif next_head in INT_OPS and -(2 ** 31) <= n <= 2 ** 31 - 1:
            changed[i] = f"pushint {n}"
        elif lines[i + 1:i + 2] == ["returnvalue"]:
            changed[i] = numeric_literal_for_type(n, ret)
        elif next_head in ("setproperty", "initproperty"):
            typ = SLOT_TYPES.get(next_rest, "")
            if (not typ and _typed_property_literal_owner(
                    lines, exceptions, i + 1, next_rest, "pkg:::Number", slot_context
            )):
                typ = "pkg:::Number"
            changed[i] = numeric_literal_for_type(n, typ)
        elif next_head == "constructprop":
            name, _, argc = next_rest.rpartition(" ")
            if argc.isdigit():
                params = CTOR_PARAM_TYPES.get(name)
                arg_index = int(argc) - 1
                if params and 0 <= arg_index < len(params):
                    changed[i] = numeric_literal_for_type(n, params[arg_index])
        elif next_head in ("callproperty", "callproplex", "callpropvoid"):
            name, _, argc = next_rest.rpartition(" ")
            if argc.isdigit() and int(argc) > 0:
                params = METHOD_PARAM_TYPES.get(name)
                arg_index = int(argc) - 1
                if params and 0 <= arg_index < len(params):
                    changed[i] = numeric_literal_for_type(n, params[arg_index])
        else:
            depth = 1
            j = i + 1
            while j < len(lines) and j not in targets:
                head, _, rest = lines[j].partition(" ")
                if head in {"multiply", "subtract", "divide", "modulo"} and depth <= 2:
                    changed[i] = numeric_literal_for_type(n, "pkg:::Number")
                    break
                if (head in NUMERIC_OPS and depth == 2
                        and lines[j - 1].split(" ", 1)[0] in NUMBER_RESULT_OPS):
                    changed[i] = numeric_literal_for_type(n, "pkg:::Number")
                    break
                if head in INT_OPS and depth <= 2:
                    changed[i] = numeric_literal_for_type(n, "pkg:::int")
                    break
                if head in {"dup", "swap", "returnvalue", "returnvoid", "throw"} or head.startswith(
                        ("if", "jump", "lookupswitch")):
                    break
                if head in ("callproperty", "callproplex", "callpropvoid"):
                    name, _, argc_text = rest.rpartition(" ")
                    if not argc_text.isdigit():
                        break
                    argc = int(argc_text)
                    if depth <= argc:
                        params = METHOD_PARAM_TYPES.get(name)
                        arg_index = argc - depth
                        if params and 0 <= arg_index < len(params):
                            changed[i] = numeric_literal_for_type(n, params[arg_index])
                        break
                    consumed = argc + 1
                    if depth <= consumed:
                        break
                    depth += -(argc + 1) if head == "callpropvoid" else -argc
                    j += 1
                    continue
                if head in ("getlex", "findpropstrict", "findproperty", "getlocal", "getglobalscope",
                            "getscopeobject", "getouterscope", "newfunction") or head in STACK_PUSH_OPS:
                    depth += 1
                elif head in ("coerce", "coerce_a", "coerce_b", "coerce_d", "coerce_i", "coerce_s",
                              "coerce_u", "coerce_o", "convert_b", "convert_d", "convert_i", "convert_o",
                              "convert_s", "convert_u", "astype", "astypelate", "checkfilter", "not",
                              "negate", "negate_i", "increment", "increment_i", "decrement", "decrement_i",
                              "bitnot", "getproperty"):
                    if depth <= 1:
                        break
                elif head in ("add", "subtract", "multiply", "divide", "modulo", "lshift", "rshift",
                              "urshift", "bitand", "bitor", "bitxor", "equals", "strictequals", "lessthan",
                              "lessequals", "greaterthan", "greaterequals", "instanceof", "istype",
                              "istypelate", "in", "add_i", "subtract_i", "multiply_i"):
                    if depth <= 2:
                        break
                    depth -= 1
                elif head in ("setlocal", "pop", "pushscope"):
                    if depth <= 1:
                        break
                    depth -= 1
                elif head in ("kill", "inclocal", "declocal", "inclocal_i", "declocal_i"):
                    pass
                elif head in ("applytype", "construct", "call", "newarray", "newobject") and rest.isdigit():
                    count = int(rest)
                    consumed = (count + 1 if head in ("applytype", "construct", "call")
                                else count if head == "newarray" else count * 2)
                    if depth <= consumed:
                        break
                    depth += 1 - consumed
                elif head == "constructprop" and rest.rpartition(" ")[2].isdigit():
                    name, _, argc_text = rest.rpartition(" ")
                    argc = int(argc_text)
                    if depth <= argc:
                        params = CTOR_PARAM_TYPES.get(name)
                        arg_index = argc - depth
                        if params and 0 <= arg_index < len(params):
                            changed[i] = numeric_literal_for_type(n, params[arg_index])
                        break
                    consumed = argc + 1
                    if depth <= consumed:
                        break
                    depth += 1 - consumed
                else:
                    break
                j += 1
    changed = {i: v for i, v in changed.items() if v is not None and lines[i] != v}
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


CALL_ARGUMENT_CONVERSIONS = {
    "coerce_s": "pkg:::String",
    "convert_d": "pkg:::Number",
    "convert_i": "pkg:::int",
    "convert_u": "pkg:::uint",
}


def rule_string_call_argument_coerce(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    for i, line in enumerate(lines):
        expected = CALL_ARGUMENT_CONVERSIONS.get(line)
        if expected is None or i in targets:
            continue
        pair = False
        if line != "coerce_s":
            pair = (line in ("convert_i", "convert_u") and i >= 2 and lines[i - 1] == "convert_d"
                    and i - 1 not in targets)
            read = lines[i - 2 if pair else i - 1] if i >= (2 if pair else 1) else ""
            previous = read.partition(" ")[0]
            plain_read = (previous in ("getlocal", "getlex", "getslot")
                          or (previous == "getproperty" and "[]" not in read))
            if not (plain_read or (line == "convert_d" and previous in ("convert_u", "convert_i"))):
                continue
        depth = 1
        j = i + 1
        while j < len(lines) and j not in targets:
            head, _, rest = lines[j].partition(" ")
            if head in {"dup", "swap", "returnvalue", "returnvoid", "throw"} or head.startswith(
                    ("if", "jump", "lookupswitch")):
                break
            if head in ("callproperty", "callproplex", "callpropvoid"):
                name, _, argc_text = rest.rpartition(" ")
                if not argc_text.isdigit():
                    break
                argc = int(argc_text)
                if depth <= argc:
                    params = METHOD_PARAM_TYPES.get(name)
                    arg_index = argc - depth
                    if params and 0 <= arg_index < len(params) and params[arg_index] == expected:
                        changed[i] = None
                        if pair:
                            changed[i - 1] = None
                    break
                consumed = argc + 1
                if depth <= consumed:
                    break
                depth += -(argc + 1) if head == "callpropvoid" else -argc
                j += 1
                continue
            if head in ("getlex", "findpropstrict", "findproperty", "getlocal", "getglobalscope",
                        "getscopeobject", "getouterscope", "newfunction") or head in STACK_PUSH_OPS:
                depth += 1
            elif lines[j] == "getproperty {pkg:}::[]":
                if depth <= 2:
                    break
                depth -= 1
            elif head in ("coerce", "coerce_a", "coerce_b", "coerce_d", "coerce_i", "coerce_s",
                          "coerce_u", "coerce_o", "convert_b", "convert_d", "convert_i", "convert_o",
                          "convert_s", "convert_u", "astype", "astypelate", "checkfilter", "not",
                          "negate", "negate_i", "increment", "increment_i", "decrement", "decrement_i",
                          "bitnot", "getproperty"):
                if depth <= 1:
                    break
            elif head in ("add", "subtract", "multiply", "divide", "modulo", "lshift", "rshift",
                          "urshift", "bitand", "bitor", "bitxor", "equals", "strictequals", "lessthan",
                          "lessequals", "greaterthan", "greaterequals", "instanceof", "istype",
                          "istypelate", "in", "add_i", "subtract_i", "multiply_i"):
                if depth <= 2:
                    break
                depth -= 1
            elif head in ("setlocal", "pop", "pushscope"):
                if depth <= 1:
                    break
                depth -= 1
            elif head in ("kill", "inclocal", "declocal", "inclocal_i", "declocal_i"):
                pass
            elif head in ("applytype", "construct", "call", "newarray", "newobject") and rest.isdigit():
                count = int(rest)
                consumed = (count + 1 if head in ("applytype", "construct", "call")
                            else count if head == "newarray" else count * 2)
                if depth <= consumed:
                    break
                depth += 1 - consumed
            elif head == "constructprop" and rest.rpartition(" ")[2].isdigit():
                name, _, argc_text = rest.rpartition(" ")
                argc = int(argc_text)
                if depth <= argc:
                    params = CTOR_PARAM_TYPES.get(name)
                    arg_index = argc - depth
                    if params and 0 <= arg_index < len(params) and params[arg_index] == expected:
                        changed[i] = None
                        if pair:
                            changed[i - 1] = None
                    break
                consumed = argc + 1
                if depth <= consumed:
                    break
                depth -= argc
            else:
                break
            j += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def _numeric_owner(typ: str | None, side: str = "i") -> tuple[str, str] | None:
    if not typ or typ in VALUE_TYPES or typ in {"*", "pkg:::void", "pkg:::String", "pkg:::Object"}:
        return None
    return typ, side


def rule_numeric_owner_call(lines, exceptions, param_types=None, slot_context=None):
    targets = branch_targets(lines, exceptions)
    base_locals: dict[str, tuple[str, str] | None] = {
        str(i + 1): _numeric_owner(typ) for i, typ in enumerate(param_types or [])
    }
    if slot_context:
        base_locals["0"] = (class_qname(slot_context[0]), slot_context[1])
    locals_ = dict(base_locals)
    stack: list[tuple[tuple[str, str] | None, int | None]] = []
    changed: dict[int, str] = {}

    def reset_flow() -> None:
        stack.clear()
        locals_.clear()

    for i, line in enumerate(lines):
        if i in targets:
            reset_flow()
        head, _, rest = line.partition(" ")
        if head == "getlocal":
            stack.append((locals_.get(rest), None))
        elif head == "setlocal":
            owner, _literal = stack.pop() if stack else (None, None)
            locals_[rest] = owner
        elif head == "kill":
            locals_.pop(rest, None)
        elif head == "getlex":
            typ = _typed_read(line, slot_context)
            owner = _numeric_owner(typ)
            if owner is None and rest in CONSTRUCTIBLE_CLASSES:
                owner = (rest, "s")
            stack.append((owner, None))
        elif head in ("findpropstrict", "findproperty", "getglobalscope", "getscopeobject", "getouterscope"):
            stack.append((None, None))
        elif head in STACK_PUSH_OPS:
            stack.append((None, i if integer_literal(line) is not None else None))
        elif head == "getproperty":
            if not stack:
                reset_flow()
                continue
            receiver = stack.pop()[0]
            typ = _typed_read(line, slot_context)
            if typ is None and slot_context and receiver == (class_qname(slot_context[0]), slot_context[1]):
                typ = CLASS_READ_SLOT_TYPES.get((*slot_context, rest))
            stack.append((_numeric_owner(typ), None))
        elif head in ("coerce", "astype"):
            if not stack:
                reset_flow()
                continue
            _owner, literal = stack.pop()
            stack.append((_numeric_owner(rest), literal))
        elif head in ("coerce_a", "coerce_b", "coerce_d", "coerce_i", "coerce_s", "coerce_u", "coerce_o",
                      "convert_b", "convert_d", "convert_i", "convert_o", "convert_s", "convert_u", "checkfilter",
                      "not", "negate", "negate_i", "increment", "increment_i", "decrement", "decrement_i", "bitnot"):
            if not stack:
                reset_flow()
        elif head in ("callproperty", "callproplex", "callpropvoid"):
            name, _, argc_text = rest.rpartition(" ")
            if not argc_text.isdigit() or len(stack) < int(argc_text) + 1:
                reset_flow()
                continue
            argc = int(argc_text)
            args = stack[-argc:] if argc else []
            receiver = stack[-argc - 1][0]
            del stack[-argc - 1:]
            declared = None
            arity_matches = False
            if receiver:
                owner_key = (*receiver, name)
                declared = OWNER_METHOD_PARAM_TYPES.get(owner_key)
                if declared is not None:
                    fixed_arity = OWNER_METHOD_FIXED_ARITIES.get(owner_key)
                    arity_matches = bool(
                        fixed_arity
                        and fixed_arity[1] == len(declared)
                        and fixed_arity[0] <= argc <= fixed_arity[1]
                    )
                else:
                    declared = NATIVE_OWNER_METHOD_PARAM_TYPES.get(owner_key)
                    arity_matches = bool(declared and len(declared) == argc)
            if arity_matches:
                for arg_index, (_owner, literal_index) in enumerate(args):
                    if literal_index is None:
                        continue
                    literal = integer_literal(lines[literal_index])
                    canonical_literal = (
                        numeric_owner_literal_for_type(literal, declared[arg_index])
                        if literal is not None else None
                    )
                    if canonical_literal and canonical_literal != lines[literal_index]:
                        changed[literal_index] = canonical_literal
            if head != "callpropvoid":
                stack.append((None, None))
        elif head == "constructprop" and rest.rpartition(" ")[2].isdigit():
            name, _, argc_text = rest.rpartition(" ")
            argc = int(argc_text)
            if len(stack) < argc + 1:
                reset_flow()
                continue
            del stack[-argc - 1:]
            stack.append((_numeric_owner(name), None))
        elif head in ("add", "subtract", "multiply", "divide", "modulo", "lshift", "rshift", "urshift",
                      "bitand", "bitor", "bitxor", "equals", "strictequals", "lessthan", "lessequals",
                      "greaterthan", "greaterequals", "instanceof", "istype", "istypelate", "in", "add_i",
                      "subtract_i", "multiply_i"):
            if len(stack) < 2:
                reset_flow()
                continue
            del stack[-2:]
            stack.append((None, None))
        elif head in ("pop", "pushscope"):
            if stack:
                stack.pop()
            else:
                reset_flow()
        elif head in ("returnvalue", "returnvoid", "throw") or head.startswith(("if", "jump", "lookupswitch")):
            reset_flow()
        else:
            reset_flow()
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


CONSTS: set[str] = set()
SLOT_TYPES: dict[str, str] = {}
READ_SLOT_TYPES: dict[str, str] = {}
CLASS_SLOT_TYPES: dict[tuple[str, str, str], str] = {}
CLASS_READ_SLOT_TYPES: dict[tuple[str, str, str], str] = {}
CLASS_INSTANCE_LITERAL_SLOTS: dict[tuple[str, str], str] = {}
ENUM_INSTANCE_CLASSES: set[str] = set()
CTOR_PARAM_TYPES: dict[str, list[str]] = {}
METHOD_PARAM_TYPES: dict[str, list[str]] = {}
OWNER_METHOD_PARAM_TYPES: dict[tuple[str, str, str], list[str]] = {}
OWNER_METHOD_FIXED_ARITIES: dict[tuple[str, str, str], tuple[int, int]] = {}
METHOD_RETURNS: dict[str, str] = {}
CONSTRUCTIBLE_CLASSES: set[str] = set()
MAP_BACKING_TYPES: dict[str, str] = {}
MAP_BACKING_CLASSES = {"pkg:haxe.ds::IntMap", "pkg:haxe.ds::StringMap", "pkg:haxe.ds::ObjectMap",
                       "pkg:haxe.ds::EnumValueMap"}
INTERFACE_METHOD_CALLS: dict[str, str] = {}
INTERFACE_METHOD_RETURNS: dict[str, str] = {}
PRIVATE_MEMBER_LOCALS: set[tuple[str, str, str]] = set()
PUBLIC_MEMBER_LOCALS: set[tuple[str, str, str]] = set()
FILE_PRIVATE_CLASS_LOCALS: set[tuple[str, str]] = set()
STRING_BUILTIN_NS = "ns:http://adobe.com/AS3/2006/builtin::"
STRING_BUILTIN_RETURNS = {
    "charCodeAt": "pkg:::Number",
    "charAt": "pkg:::String",
    "concat": "pkg:::String",
    "replace": "pkg:::String",
    "slice": "pkg:::String",
    "substr": "pkg:::String",
    "substring": "pkg:::String",
    "toLocaleLowerCase": "pkg:::String",
    "toLocaleUpperCase": "pkg:::String",
    "toLowerCase": "pkg:::String",
    "toString": "pkg:::String",
    "toUpperCase": "pkg:::String",
}
STRING_BUILTIN_NAMES = {STRING_BUILTIN_NS + name: ret for name, ret in STRING_BUILTIN_RETURNS.items()}
STRING_BUILTIN_NAMES.update({f"pkg:::{name}": ret for name, ret in STRING_BUILTIN_RETURNS.items()})

NATIVE_OWNER_METHOD_PARAM_TYPES = {
    ("pkg:::Math", "s", "pkg:::pow"): ["pkg:::Number", "pkg:::Number"],
    ("pkg:flash.geom::Point", "i", "pkg:::normalize"): ["pkg:::Number"],
    ("pkg:flash.geom::Matrix", "i", "pkg:::setTo"): ["pkg:::Number"] * 6,
    ("pkg:flash.display::Graphics", "i", "pkg:::beginFill"): ["pkg:::uint", "pkg:::Number"],
    ("pkg:flash.display::Graphics", "i", "pkg:::drawRect"): ["pkg:::Number"] * 4,
}

NATIVE_OWNER_PROPERTY_TYPES = {
    ("pkg:flash.display::MovieClip", "pkg:::alpha"): "pkg:::Number",
    ("pkg:flash.display::MovieClip", "pkg:::x"): "pkg:::Number",
    ("pkg:flash.display::MovieClip", "pkg:::y"): "pkg:::Number",
    ("pkg:flash.text::TextField", "pkg:::x"): "pkg:::Number",
}


def public_qname(name: str) -> str:
    match = re.fullmatch(r"\{pkg:([^}]*)\}::(.+)", name)
    return f"pkg:{match.group(1)}::{match.group(2)}" if match else name


def const_names(blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> set[str]:
    names = set()
    for data in blocks:
        abc = Abc(data, ns_aliases)
        for i, inst in enumerate(abc.instances):
            names.update(abc.mn(t["name"]) for t in inst["traits"] + abc.classes[i]["traits"] if t["kind"] == 6)
        for script in abc.scripts:
            names.update(abc.mn(t["name"]) for t in script["traits"] if t["kind"] == 6)
    return names


def slot_types(blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> dict[str, str]:
    types: dict[str, set[str]] = {}
    blocked: set[str] = set()
    for data in blocks:
        abc = Abc(data, ns_aliases)

        def visit(traits: list[dict]) -> None:
            for t in traits:
                name = abc.mn(t["name"], ns_aliases)
                if t["kind"] in (0, 6):
                    typ = abc.mn(t["type"], ns_aliases) if t["type"] else "*"
                    if typ != "*":
                        types.setdefault(name, set()).add(typ)
                elif t["kind"] == 3:
                    blocked.add(name)

        for i, inst in enumerate(abc.instances):
            visit(inst["traits"])
            visit(abc.classes[i]["traits"])
        for script in abc.scripts:
            visit(script["traits"])
    return {name: next(iter(found)) for name, found in types.items() if len(found) == 1 and name not in blocked}


def class_slot_types(blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> dict[tuple[str, str, str], str]:
    out: dict[tuple[str, str, str], str] = {}
    for data in blocks:
        abc = Abc(data, ns_aliases)
        for i, inst in enumerate(abc.instances):
            cls = abc.class_name(i, ns_aliases)
            for side, traits in (("i", inst["traits"]), ("s", abc.classes[i]["traits"])):
                blocked: set[str] = set()
                found: dict[str, set[str]] = {}
                for t in traits:
                    name = abc.mn(t["name"], ns_aliases)
                    if t["kind"] in (0, 6):
                        typ = abc.mn(t["type"], ns_aliases) if t["type"] else "*"
                        if typ != "*":
                            found.setdefault(name, set()).add(typ)
                    elif t["kind"] == 3:
                        blocked.add(name)
                for name, types in found.items():
                    if len(types) == 1 and name not in blocked:
                        out[(cls, side, name)] = next(iter(types))
    return out


def class_read_slot_types(blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> dict[tuple[str, str, str], str]:
    out: dict[tuple[str, str, str], str] = {}
    for data in blocks:
        abc = Abc(data, ns_aliases)
        for i, inst in enumerate(abc.instances):
            cls = abc.class_name(i, ns_aliases)
            for side, traits in (("i", inst["traits"]), ("s", abc.classes[i]["traits"])):
                blocked: set[str] = set()
                found: dict[str, set[str]] = {}
                for t in traits:
                    name = abc.mn(t["name"], ns_aliases)
                    if t["kind"] in (0, 6):
                        typ = abc.mn(t["type"], ns_aliases) if t["type"] else "*"
                        if typ != "*":
                            found.setdefault(name, set()).add(typ)
                    else:
                        blocked.add(name)
                for name, types in found.items():
                    if len(types) == 1 and name not in blocked:
                        out[(cls, side, name)] = next(iter(types))
    return out


def class_instance_literal_slots(blocks: list[bytes],
                                 ns_aliases: dict[str, str] | None = None
                                 ) -> dict[tuple[str, str], str]:
    out: dict[tuple[str, str], str] = {}
    for data in blocks:
        abc = Abc(data, ns_aliases)
        for i, inst in enumerate(abc.instances):
            cls = abc.class_name(i, ns_aliases)
            grouped: dict[str, list[dict]] = {}
            for trait in inst["traits"]:
                grouped.setdefault(abc.mn(trait["name"], ns_aliases), []).append(trait)
            for name, traits in grouped.items():
                if len(traits) != 1 or traits[0]["kind"] != 0 or not traits[0]["type"]:
                    continue
                typ = abc.mn(traits[0]["type"], ns_aliases)
                if typ != "*":
                    out[(cls, name)] = typ
    return out


def enum_instance_classes(blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> set[str]:
    out = set()
    for data in blocks:
        abc = Abc(data, ns_aliases)
        for i, inst in enumerate(abc.instances):
            matches = [
                trait for trait in inst["traits"]
                if abc.mn(trait["name"], ns_aliases) == "pkg:::__enum__"
            ]
            if (len(matches) == 1 and matches[0]["kind"] == 6
                    and abc.mn(matches[0]["type"], ns_aliases) == "pkg:::Boolean"
                    and matches[0]["value"] == (0x0B, 0x0B)):
                out.add(abc.class_name(i, ns_aliases))
    return out


def read_slot_types(blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> dict[str, str]:
    types: dict[str, set[str]] = {}
    blocked: set[str] = set()
    for data in blocks:
        abc = Abc(data, ns_aliases)

        def visit(traits: list[dict]) -> None:
            for t in traits:
                name = abc.mn(t["name"], ns_aliases)
                if t["kind"] in (0, 6):
                    typ = abc.mn(t["type"], ns_aliases) if t["type"] else "*"
                    if typ != "*":
                        types.setdefault(name, set()).add(typ)
                else:
                    blocked.add(name)

        for i, inst in enumerate(abc.instances):
            visit(inst["traits"])
            visit(abc.classes[i]["traits"])
        for script in abc.scripts:
            visit(script["traits"])
    return {name: next(iter(found)) for name, found in types.items() if len(found) == 1 and name not in blocked}


def constructor_param_types(blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for data in blocks:
        abc = Abc(data, ns_aliases)
        for inst in abc.instances:
            name = abc.mn(inst["name"])
            method = abc.methods[inst["iinit"]]
            out[name] = [abc.mn(param, ns_aliases) for param in method["params"]]
    return out


def method_param_types(blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> dict[str, list[str]]:
    found: dict[str, set[tuple[str, ...]]] = {}
    for data in blocks:
        abc = Abc(data, ns_aliases)

        def visit(traits: list[dict]) -> None:
            for trait in traits:
                if trait["kind"] not in (1, 5):
                    continue
                params = tuple(abc.mn(param, ns_aliases) for param in abc.methods[trait["method"]]["params"])
                found.setdefault(abc.mn(trait["name"]), set()).add(params)

        for i, inst in enumerate(abc.instances):
            visit(inst["traits"])
            visit(abc.classes[i]["traits"])
        for script in abc.scripts:
            visit(script["traits"])
    return {name: list(next(iter(params))) for name, params in found.items() if len(params) == 1}


def owner_method_param_types(blocks: list[bytes],
                             ns_aliases: dict[str, str] | None = None
                             ) -> dict[tuple[str, str, str], list[str]]:
    found: dict[tuple[str, str, str], set[tuple[str, ...]]] = {}
    for data in blocks:
        abc = Abc(data, ns_aliases)
        for i, inst in enumerate(abc.instances):
            owner = abc.mn(inst["name"], ns_aliases)
            for side, traits in (("i", inst["traits"]), ("s", abc.classes[i]["traits"])):
                for trait in traits:
                    if trait["kind"] != 1:
                        continue
                    method = abc.methods[trait["method"]]
                    key = (owner, side, abc.mn(trait["name"], ns_aliases))
                    params = tuple(abc.mn(param, ns_aliases) for param in method["params"])
                    found.setdefault(key, set()).add(params)
    return {key: list(next(iter(params))) for key, params in found.items() if len(params) == 1}


def owner_method_fixed_arities(blocks: list[bytes],
                               ns_aliases: dict[str, str] | None = None
                               ) -> dict[tuple[str, str, str], tuple[int, int]]:
    found: dict[tuple[str, str, str], list[tuple[int, int, bool]]] = {}
    for data in blocks:
        abc = Abc(data, ns_aliases)
        for i, inst in enumerate(abc.instances):
            owner = abc.mn(inst["name"], ns_aliases)
            for side, traits in (("i", inst["traits"]), ("s", abc.classes[i]["traits"])):
                for trait in traits:
                    if trait["kind"] != 1:
                        continue
                    method = abc.methods[trait["method"]]
                    key = (owner, side, abc.mn(trait["name"], ns_aliases))
                    param_count = len(method["params"])
                    optional_count = len(method["optional"])
                    found.setdefault(key, []).append(
                        (param_count - optional_count, param_count, bool(method["flags"] & 0x04))
                    )
    return {
        key: (arities[0][0], arities[0][1])
        for key, arities in found.items()
        if len(arities) == 1 and not arities[0][2]
    }


def method_return_types(blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> dict[str, str]:
    found: dict[str, set[str]] = {}
    for data in blocks:
        abc = Abc(data, ns_aliases)

        def visit(traits: list[dict]) -> None:
            for trait in traits:
                if trait["kind"] not in (1, 2, 3, 5):
                    continue
                found.setdefault(abc.mn(trait["name"]), set()).add(abc.mn(abc.methods[trait["method"]]["ret"]))

        for i, inst in enumerate(abc.instances):
            visit(inst["traits"])
            visit(abc.classes[i]["traits"])
        for script in abc.scripts:
            visit(script["traits"])
    return {name: next(iter(types)) for name, types in found.items() if len(types) == 1}


def class_names(blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> set[str]:
    out = set()
    for data in blocks:
        abc = Abc(data, ns_aliases)
        out.update(abc.mn(inst["name"]) for inst in abc.instances)
    return out


def file_private_class_locals(blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> set[tuple[str, str]]:
    out = set()
    for data in blocks:
        abc = Abc(data, ns_aliases)
        for i in range(len(abc.instances)):
            name = abc.class_name(i)
            if name.startswith("FilePrivateNS:") and "." in name:
                owner, local = name[len("FilePrivateNS:"):].rsplit(".", 1)
                out.add((owner, local))
    return out


def _constructed_map_type(lines: list[str], index: int) -> str | None:
    if index < 0:
        return None
    head, _, rest = lines[index].partition(" ")
    if head == "constructprop" and rest.rsplit(" ", 1)[0] in MAP_BACKING_CLASSES and rest.endswith(" 0"):
        return rest.rsplit(" ", 1)[0]
    if head == "coerce" and rest == "pkg:haxe::IMap" and index > 0:
        return _constructed_map_type(lines, index - 1)
    return None


AUDITED_MAP_BACKING_COPIES = {
    ("pkg:::var_6944", "pkg:::var_9960"),
}


def map_backing_types_from_codes(codes: list[list[str]]) -> dict[str, str]:
    writes: dict[str, list[tuple[str, str]]] = {}
    blocked: set[str] = set()
    for lines in codes:
        local_maps: dict[str, str] = {}
        for i, line in enumerate(lines):
            head, _, rest = line.partition(" ")
            if head == "setlocal":
                map_type = _constructed_map_type(lines, i - 1)
                if map_type:
                    local_maps[rest] = map_type
                else:
                    local_maps.pop(rest, None)
            elif head in {"kill", "inclocal", "declocal", "inclocal_i", "declocal_i"}:
                local_maps.pop(rest, None)
            elif head in ("setproperty", "initproperty") and is_qname(rest):
                previous = lines[i - 1] if i > 0 else ""
                null_type = (_operand(previous, "coerce") or _operand(previous, "astype"))
                if (previous == "pushnull"
                        or (null_type and null_type not in VALUE_TYPES and null_type != "*"
                            and i > 1 and lines[i - 2] == "pushnull")):
                    continue
                map_type = _constructed_map_type(lines, i - 1)
                if not map_type and previous.startswith("getlocal "):
                    map_type = local_maps.get(previous.split(" ", 1)[1])
                if map_type:
                    writes.setdefault(rest, []).append(("type", map_type))
                    continue
                read_head, _, source = previous.partition(" ")
                if (read_head in {"getlex", "getproperty"} and is_qname(source)
                        and (rest, source) in AUDITED_MAP_BACKING_COPIES):
                    writes.setdefault(rest, []).append(("copy", source))
                    continue
                blocked.add(rest)

    resolved: dict[str, str] = {}
    changed = True
    while changed:
        changed = False
        for name, values in writes.items():
            if name in blocked or name in resolved:
                continue
            types = {value if kind == "type" else resolved.get(value)
                     for kind, value in values}
            if None in types:
                continue
            if len(types) == 1:
                resolved[name] = next(iter(types))
                changed = True
    return resolved


def map_backing_types(blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> dict[str, str]:
    codes: list[list[str]] = []
    for data in blocks:
        abc = Abc(data, ns_aliases)
        for method in range(len(abc.methods)):
            codes.append(normalize(abc, method, None)["code"] or [])
    return map_backing_types_from_codes(codes)


def interface_method_facts(blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> tuple[dict[str, str], dict[str, str]]:
    interface_methods: dict[str, dict[str, str]] = {}
    implementers: dict[str, list[set[str]]] = {}
    for data in blocks:
        abc = Abc(data, ns_aliases)
        for i, inst in enumerate(abc.instances):
            cls = public_qname(abc.mn(inst["name"]))
            methods = {abc.mn(t["name"]) for t in inst["traits"] if t["kind"] in (1, 2, 3)}
            if inst.get("flags", 0) & 0x04:
                for t in inst["traits"]:
                    name = abc.mn(t["name"])
                    if t["kind"] in (1, 2, 3) and name.startswith("ns:"):
                        interface_methods.setdefault(cls, {})[name] = abc.mn(abc.methods[t["method"]]["ret"])
            for iface in inst.get("interfaces", []):
                implementers.setdefault(public_qname(abc.mn(iface)), []).append(methods)

    calls: dict[str, str] = {}
    returns: dict[str, str] = {}
    for iface, names in interface_methods.items():
        impls = implementers.get(iface, [])
        if not impls:
            continue
        for name, ret in names.items():
            local = name.rsplit("::", 1)[-1]
            public = f"pkg:::{local}"
            if all(public in methods for methods in impls):
                calls[name] = public
                returns[name] = ret
    return calls, returns


def private_member_locals(blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> tuple[set[tuple[str, str, str]], set[tuple[str, str, str]]]:
    private: set[tuple[str, str, str]] = set()
    public: set[tuple[str, str, str]] = set()
    for data in blocks:
        abc = Abc(data, ns_aliases)
        for i, inst in enumerate(abc.instances):
            cls = abc.class_name(i)
            for side, traits in (("i", inst["traits"]), ("s", abc.classes[i]["traits"])):
                for trait in traits:
                    name = abc.mn(trait["name"])
                    if "::" not in name:
                        continue
                    ns, local = name.rsplit("::", 1)
                    if ns == "private":
                        private.add((cls, side, local))
                    elif ns == "pkg:":
                        public.add((cls, side, local))
    return private, public


def interface_method_calls(blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> dict[str, str]:
    return interface_method_facts(blocks, ns_aliases)[0]


def rule_init_set(lines, exceptions):
    changed = {i: "setproperty " + line.split(" ", 1)[1] for i, line in enumerate(lines)
               if line.startswith("initproperty ") and is_qname(line.split(" ", 1)[1])
               and line.split(" ", 1)[1] not in CONSTS}
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_as3_index(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    i = 0
    while i < len(lines):
        if lines[i] != f"getlex {AS3_HELPER_QNAME}" or i in changed:
            i += 1
            continue
        depth = 1
        j = i + 1
        while j < len(lines):
            if j in targets:
                break
            call = _callproperty(lines[j])
            if call in (("pkg:::index", 2), ("pkg:::indexValue", 2)) and depth == 3:
                changed[i] = None
                changed[j] = "getproperty {pkg:}::[]"
                i = j + 1
                break
            delta = _stack_delta(lines[j])
            if delta is None:
                break
            depth += delta
            if depth < 1:
                break
            j += 1
        else:
            i += 1
            continue
        if i != j + 1:
            i += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_as3_set_index(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    i = 0
    while i < len(lines):
        if lines[i] != f"getlex {AS3_HELPER_QNAME}" or i in changed:
            i += 1
            continue
        depth = 1
        j = i + 1
        while j < len(lines):
            if j in targets:
                break
            head, _, rest = lines[j].partition(" ")
            name, _, argc = rest.rpartition(" ")
            if (head == "callpropvoid" and name in ("pkg:::setIndex", "pkg:::setIndexValue")
                    and argc == "3" and depth == 4):
                changed[i] = None
                changed[j] = "setproperty {pkg:}::[]"
                i = j + 1
                break
            delta = _stack_delta(lines[j])
            if delta is None:
                break
            depth += delta
            if depth < 1:
                break
            j += 1
        else:
            i += 1
            continue
        if i != j + 1:
            i += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_as3_has_key_stringmap(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    i = 0
    while i + 4 < len(lines):
        key = lines[i + 3]
        if (lines[i] == f"getlex {AS3_HELPER_QNAME}"
                and lines[i + 1] == "getlex pkg:haxe.ds::StringMap"
                and lines[i + 2] == "getproperty pkg:::reserved"
                and _callproperty(lines[i + 4]) == ("pkg:::hasKey", 2)
                and (key.startswith(PURE_PUSH) or key in PURE_PUSH_BARE)
                and not targets & {i + 1, i + 2, i + 3, i + 4}):
            changed.update({i: key, i + 3: "in", i + 4: None})
            i += 5
            continue
        i += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


IMAP_METHODS = {"method_65", "remove", "keys", "method_4935", "exists"}


def rule_haxe_imap_namespace(lines, exceptions):
    changed: dict[int, str] = {}
    for i, line in enumerate(lines):
        head, _, rest = line.partition(" ")
        if head not in ("callproperty", "callpropvoid"):
            continue
        name, _, argc = rest.rpartition(" ")
        if not name.startswith("ns:haxe:IMap::"):
            continue
        local = name.rsplit("::", 1)[-1]
        if local in IMAP_METHODS:
            changed[i] = f"{head} pkg:::{local} {argc}"
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_interface_namespace_call(lines, exceptions):
    changed: dict[int, str] = {}
    for i, line in enumerate(lines):
        head, _, rest = line.partition(" ")
        if head not in ("callproperty", "callproplex", "callpropvoid"):
            continue
        name, _, argc = rest.rpartition(" ")
        public = INTERFACE_METHOD_CALLS.get(name)
        if public:
            changed[i] = f"{head} {public} {argc}"
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_interface_call_return_convert(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    for i in range(len(lines) - 1):
        head, _, rest = lines[i].partition(" ")
        if head not in ("callproperty", "callproplex") or i + 1 in targets:
            continue
        name, _, _argc = rest.rpartition(" ")
        ret = INTERFACE_METHOD_RETURNS.get(name)
        if ret and conversion_type(lines[i + 1]) == ret:
            changed[i + 1] = None
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_method_call_return_convert(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    for i in range(len(lines) - 1):
        head, _, rest = lines[i].partition(" ")
        if head not in ("callproperty", "callproplex") or i + 1 in targets:
            continue
        name, _, _argc = rest.rpartition(" ")
        ret = METHOD_RETURNS.get(name)
        if not ret or ret == "*":
            continue
        conv = conversion_type(lines[i + 1])
        if conv == ret or (ret not in VALUE_TYPES and lines[i + 1] == "coerce pkg:::Object"):
            changed[i + 1] = None
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_nullable_call_branch_coerce(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    handlers = exception_targets(exceptions)
    changed: dict[int, str | None] = {}
    incoming: dict[int, list[int]] = {}
    for index, text in enumerate(lines):
        if text.split(" ", 1)[0].startswith(("if", "jump", "lookupswitch")):
            for label in LABEL.findall(text):
                incoming.setdefault(int(label), []).append(index)

    for join, line in enumerate(lines):
        typ = _operand(line, "coerce")
        if not typ or typ in VALUE_TYPES or join < 5 or join in handlers:
            continue
        call = _callproperty(lines[join - 1])
        if not call or METHOD_RETURNS.get(call[0]) != typ:
            continue
        join_incoming = incoming.get(join, [])
        jumps = [source for source in join_incoming if lines[source] == f"jump L{join}"]
        if len(jumps) != 1 or join_incoming != jumps:
            continue
        jump = jumps[0]
        branch = jump - 2
        call_start = jump + 1
        if (branch < 0 or lines[jump - 1] != "pushnull"
                or not lines[branch].startswith("if")
                or _one_label(lines[branch]) != call_start
                or incoming.get(call_start, []) != [branch]
                or handlers & set(range(branch, join + 1))):
            continue
        if targets & set(range(call_start + 1, join)):
            continue
        depth = 0
        safe = True
        for index in range(call_start, join):
            head = lines[index].split(" ", 1)[0]
            if head.startswith(("if", "jump", "lookupswitch")) or head in {"throw", "returnvalue", "returnvoid"}:
                safe = False
                break
            delta = _stack_delta(lines[index])
            if delta is None:
                safe = False
                break
            depth += delta
            if depth < 1:
                safe = False
                break
        if safe and depth == 1:
            changed[join] = None
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_private_member_namespace(lines, exceptions, slot_context=None):
    if not slot_context:
        return (lines, exceptions), False
    cls, side = slot_context
    changed: dict[int, str] = {}
    for i, line in enumerate(lines):
        head, _, rest = line.partition(" ")
        if rest.startswith("private::"):
            local = rest.split(" ", 1)[0].rsplit("::", 1)[-1]
            if ((cls, side, local) in PRIVATE_MEMBER_LOCALS
                    and (cls, side, local) not in PUBLIC_MEMBER_LOCALS):
                changed[i] = line.replace(f"private::{local}", f"pkg:::{local}", 1)
            elif head in {"findpropstrict", "findproperty", "getlex", "constructprop",
                          "constructsuper", "coerce", "astype", "callproperty",
                          "callproplex", "callpropvoid"} and (cls, local) in FILE_PRIVATE_CLASS_LOCALS:
                changed[i] = line.replace(f"private::{local}", f"pkg:::{local}", 1)
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def _typed_read(line: str, slot_context: tuple[str, str] | None = None) -> str | None:
    head, _, name = line.partition(" ")
    if head == "getproperty":
        return SLOT_TYPES.get(name)
    if head == "getlex":
        typ = READ_SLOT_TYPES.get(name)
        if typ is None and slot_context:
            typ = CLASS_READ_SLOT_TYPES.get((*slot_context, name))
        return typ
    return None


def _converted_stack_type(line: str) -> str | None:
    if line == "convert_s" or line == "coerce_s":
        return "pkg:::String"
    if line == "convert_d" or line == "coerce_d":
        return "pkg:::Number"
    if line == "convert_i" or line == "coerce_i":
        return "pkg:::int"
    if line == "convert_u" or line == "coerce_u":
        return "pkg:::uint"
    if line == "convert_b" or line == "coerce_b":
        return "pkg:::Boolean"
    typ = _operand(line, "coerce") or _operand(line, "astype")
    return typ if typ and is_type(typ) else None


def _string_param_locals(param_types=None) -> dict[str, tuple[str, bool]]:
    return {
        str(i + 1): (typ, False)
        for i, typ in enumerate(param_types or [])
        if typ == "pkg:::String"
    }


def _std_string_expr_type(lines: list[str], param_types=None,
                          slot_context: tuple[str, str] | None = None,
                          local_facts: dict[str, tuple[str | None, bool]] | None = None
                          ) -> tuple[str | None, bool] | None:
    locals_: dict[str, tuple[str | None, bool]] = _string_param_locals(param_types)
    if local_facts:
        locals_.update(local_facts)
    stack: list[tuple[str | None, bool]] = []
    for line in lines:
        head, _, rest = line.partition(" ")
        if head == "getlocal":
            stack.append(locals_.get(rest, (None, False)))
        elif line == "pushnull":
            stack.append(("null", False))
        elif line.startswith("pushstring "):
            stack.append(("pkg:::String", True))
        elif head in STACK_PUSH_OPS:
            stack.append((None, line not in {"pushnull", "pushundefined"}))
        elif head == "getlex":
            stack.append((_typed_read(line, slot_context), False))
        elif head == "getproperty":
            if not stack:
                return None
            stack.pop()
            stack.append((_typed_read(line, slot_context), False))
        elif head in ("coerce_s", "convert_s"):
            if not stack:
                return None
            typ, nonnull = stack.pop()
            stack.append(("pkg:::String", head == "convert_s" or (typ == "pkg:::String" and nonnull)))
        elif head == "coerce":
            if not stack:
                return None
            typ = rest if is_type(rest) else None
            _old_typ, nonnull = stack.pop()
            stack.append((typ, nonnull and typ == _old_typ))
        elif head == "callproperty":
            call = _callproperty(line)
            if call is None or len(stack) < call[1] + 1:
                return None
            name, argc = call
            args = [stack.pop() for _ in range(argc)]
            receiver_type, _receiver_nonnull = stack.pop()
            ret = STRING_BUILTIN_NAMES.get(name)
            if ret == "pkg:::String" and receiver_type == "pkg:::String":
                stack.append(("pkg:::String", True))
            elif ret:
                stack.append((ret, True))
            else:
                stack.append((None, False))
        else:
            return None
    return stack[0] if len(stack) == 1 else None


def rule_std_string_known_string(lines, exceptions, param_types=None, slot_context=None):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    param_locals = _string_param_locals(param_types)
    locals_: dict[str, tuple[str | None, bool]] = dict(param_locals)
    stack: list[tuple[str | None, bool]] = []

    def clear_flow_facts() -> None:
        stack.clear()
        locals_.clear()
        locals_.update(param_locals)

    def push_unknown(delta: int) -> None:
        if delta > 0:
            stack.extend([(None, False)] * delta)
        elif delta < 0:
            if len(stack) >= -delta:
                del stack[delta:]
            else:
                stack.clear()

    def apply_fact(line: str) -> None:
        head, _, rest = line.partition(" ")
        if head == "getlocal":
            stack.append(locals_.get(rest, (None, False)))
        elif line == "pushnull":
            stack.append(("null", False))
        elif line.startswith("pushstring "):
            stack.append(("pkg:::String", True))
        elif head in STACK_PUSH_OPS:
            stack.append((None, line not in {"pushnull", "pushundefined"}))
        elif head == "getlex":
            stack.append((_typed_read(line, slot_context), False))
        elif head == "getproperty":
            if stack:
                stack.pop()
                stack.append((_typed_read(line, slot_context), False))
            else:
                stack.clear()
        elif head in ("coerce_s", "convert_s"):
            if stack:
                typ, nonnull = stack.pop()
                stack.append(("pkg:::String", head == "convert_s" or (typ == "pkg:::String" and nonnull)))
            else:
                stack.clear()
        elif head == "coerce":
            if stack:
                typ = rest if is_type(rest) else None
                old_typ, nonnull = stack.pop()
                stack.append((typ, nonnull and typ == old_typ))
            else:
                stack.clear()
        elif head == "dup":
            stack.append(stack[-1] if stack else (None, False))
        elif head == "swap":
            if len(stack) >= 2:
                stack[-1], stack[-2] = stack[-2], stack[-1]
            else:
                stack.clear()
        elif head == "setlocal":
            locals_[rest] = stack.pop() if stack else (None, False)
        elif head == "kill":
            locals_.pop(rest, None)
        elif head == "callproperty":
            call = _callproperty(line)
            if call is None or len(stack) < call[1] + 1:
                stack.clear()
                return
            name, argc = call
            for _ in range(argc):
                stack.pop()
            receiver_type, _receiver_nonnull = stack.pop()
            ret = STRING_BUILTIN_NAMES.get(name)
            if ret == "pkg:::String" and receiver_type == "pkg:::String":
                stack.append(("pkg:::String", True))
            elif ret:
                stack.append((ret, True))
            else:
                stack.append((None, False))
        elif head == "callpropvoid":
            call = _callproperty(line)
            if call is None or len(stack) < call[1] + 1:
                stack.clear()
                return
            del stack[-(call[1] + 1):]
        else:
            delta = _stack_delta(line)
            if delta is None:
                stack.clear()
            else:
                push_unknown(delta)

    def only_expected_guard_targets(start: int, true_target: int, end_target: int) -> bool:
        guarded = set(range(start + 1, start + 8))
        for src, line in enumerate(lines):
            head = line.split(" ", 1)[0]
            if not head.startswith(("if", "jump", "lookupswitch")):
                continue
            for text in LABEL.findall(line):
                target = int(text)
                if target not in guarded:
                    continue
                if src == start + 2 and target == true_target:
                    continue
                return False
        for exc in exceptions:
            for text in LABEL.findall(exc):
                if int(text) in guarded:
                    return False
        return lines[start + 4] == f"jump L{end_target}"

    def inline_std_string_local(start: int) -> str | None:
        if start + 7 >= len(lines):
            return None
        head, _, reg = lines[start].partition(" ")
        if head != "getlocal" or locals_.get(reg) != ("pkg:::String", True):
            return None
        if (lines[start + 1] != "pushnull"
                or lines[start + 2] != f"ifne L{start + 5}"
                or lines[start + 3] != "pushstring 'null'"
                or lines[start + 5] != "pushstring ''"
                or lines[start + 6] != f"getlocal {reg}"
                or lines[start + 7] != "add"):
            return None
        if not only_expected_guard_targets(start, start + 5, start + 9):
            return None
        return reg

    i = 0
    while i < len(lines):
        if i in targets:
            clear_flow_facts()
        head = lines[i].partition(" ")[0]
        if head.startswith("if") or head in {"jump", "lookupswitch", "throw", "returnvalue", "returnvoid"}:
            apply_fact(lines[i])
            clear_flow_facts()
            i += 1
            continue
        inline_reg = inline_std_string_local(i)
        if inline_reg is not None:
            for j in range(i + 1, i + 8):
                changed[j] = None
            apply_fact(lines[i])
            i += 8
            continue
        if lines[i] != "getlex pkg:::Std" or i in targets:
            apply_fact(lines[i])
            i += 1
            continue
        depth = 1
        j = i + 1
        while j < len(lines):
            if j in targets:
                break
            call = _callproperty(lines[j])
            if call == ("pkg:::string", 1) and depth == 2:
                fact = _std_string_expr_type(lines[i + 1:j], param_types, slot_context, locals_)
                if fact == ("pkg:::String", True):
                    changed[i] = None
                    changed[j] = None
                    break
            delta = _stack_delta(lines[j])
            if delta is None:
                break
            depth += delta
            if depth < 1:
                break
            j += 1
        else:
            pass
        apply_fact(lines[i])
        i += 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_string_builtin_namespace_call(lines, exceptions, param_types=None, slot_context=None):
    targets = branch_targets(lines, exceptions)
    params = param_types or []
    locals_: dict[str, str] = {
        str(i + 1): typ for i, typ in enumerate(params) if typ == "pkg:::String"
    }
    stack: list[str | None] = []
    changed: dict[int, str] = {}

    def pop() -> str | None:
        return stack.pop() if stack else None

    for i, line in enumerate(lines):
        head, _, rest = line.partition(" ")
        if head == "getlocal":
            stack.append(locals_.get(rest))
        elif head == "setlocal":
            locals_[rest] = pop()
        elif head in {"kill", "inclocal", "declocal", "inclocal_i", "declocal_i"}:
            locals_.pop(rest, None)
        elif head in ("getlex", "findpropstrict", "findproperty", "getglobalscope", "getscopeobject",
                      "getouterscope", "newfunction") or head in STACK_PUSH_OPS:
            stack.append("pkg:::String" if head == "pushstring" else _typed_read(line, slot_context))
        elif head == "getproperty":
            if stack:
                stack[-1] = _typed_read(line, slot_context)
        elif head in ("coerce", "coerce_s", "coerce_d", "coerce_i", "coerce_u", "coerce_b", "astype",
                      "convert_s", "convert_d", "convert_i", "convert_u", "convert_b"):
            if stack:
                stack[-1] = _converted_stack_type(line)
        elif head == "dup":
            stack.append(stack[-1] if stack else None)
        elif head == "swap":
            if len(stack) >= 2:
                stack[-1], stack[-2] = stack[-2], stack[-1]
            else:
                stack.clear()
        elif head in ("callproperty", "callproplex", "callpropvoid"):
            name, _, argc_text = rest.rpartition(" ")
            argc = int(argc_text) if argc_text.isdigit() else -1
            receiver_index = len(stack) - argc - 1
            receiver = stack[receiver_index] if argc >= 0 and receiver_index >= 0 else None
            local = name[len(STRING_BUILTIN_NS):] if name.startswith(STRING_BUILTIN_NS) else None
            if (local in STRING_BUILTIN_RETURNS and receiver == "pkg:::String" and i not in targets):
                changed[i] = f"{head} pkg:::{local} {argc}"
                name = f"pkg:::{local}"
            if argc >= 0 and len(stack) >= argc + 1:
                del stack[-(argc + 1):]
                if head != "callpropvoid":
                    stack.append(STRING_BUILTIN_RETURNS.get(name.rsplit("::", 1)[-1]))
            else:
                stack.clear()
        else:
            delta = _stack_delta(line)
            if delta is None:
                stack.clear()
            elif delta > 0:
                stack.extend([None] * delta)
            elif delta < 0:
                if len(stack) >= -delta:
                    del stack[delta:]
                else:
                    stack.clear()
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_builtin_call_object_coerce(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    for i in range(len(lines) - 2):
        head, _, rest = lines[i].partition(" ")
        if head not in ("callproperty", "callproplex"):
            continue
        name, _, argc = rest.rpartition(" ")
        if (name == "pkg:::charCodeAt" and argc == "1" and lines[i + 1] == "coerce pkg:::Object"
                and lines[i + 2] in {"convert_i", "convert_u", "convert_d"} and i + 1 not in targets):
            changed[i + 1] = None
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_object_coerce_integral_convert(lines, exceptions):
    def match(a, b):
        if a == "coerce pkg:::Object" and (b in ("convert_i", "convert_u", "convert_b", "bitnot")
                                           or b in INT_OPS):
            return None, b
    return _pairs(lines, exceptions, match, keep_second_target=True)


def rule_dup_setlocal(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str] = {}
    for i in range(len(lines) - 1):
        if lines[i] == "dup" and lines[i + 1].startswith("setlocal ") and i + 1 not in targets:
            reg = lines[i + 1].split(" ", 1)[1]
            changed[i] = f"setlocal {reg}"
            changed[i + 1] = f"getlocal {reg}"
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def conversion_type(line: str) -> str | None:
    if line in CONVERT_FOR_RETURN:
        return CONVERT_FOR_RETURN[line]
    if line == "coerce_s":
        return "pkg:::String"
    typ = _operand(line, "coerce")
    return typ if typ and is_type(typ) else None


def _scoped_setproperty_object(lines: list[str], exceptions: list[str], set_index: int, name: str) -> bool:
    targets = branch_targets(lines, exceptions)
    for j in range(max(0, set_index - 40), set_index):
        if lines[j] not in {f"findpropstrict {name}", f"findproperty {name}", "getlocal 0"}:
            continue
        if targets & set(range(j + 1, set_index)):
            continue
        depth = 0
        ok = True
        for k in range(j, set_index):
            delta = _stack_delta(lines[k])
            if delta is None:
                ok = False
                break
            depth += delta
            if k < set_index - 1 and depth < 1:
                ok = False
                break
        if ok and depth == 2:
            return True
    if exceptions or set_index < 2:
        return False
    conversion_index = set_index - 1
    edges = branch_edges(lines)
    for j in range(max(0, set_index - 128), conversion_index):
        if lines[j] not in {f"findpropstrict {name}", f"findproperty {name}", "getlocal 0"}:
            continue
        start = j + 1
        if any((source < start or source >= conversion_index)
               for source, target in edges if start <= target <= conversion_index):
            continue
        internal_targets = {
            target for source, target in edges
            if start <= source < conversion_index and start <= target <= conversion_index
        }
        blocked = branch_targets(lines, exceptions) - internal_targets - {conversion_index}
        if _depths_before_index(lines, start, conversion_index, 1, blocked) == {2}:
            return True
    return False


def _class_key_from_qname(qname: str) -> str | None:
    match = re.fullmatch(r"pkg:([^:]*)::(.+)", qname)
    if not match:
        return None
    package, local = match.groups()
    return f"{package}.{local}" if package else local


def _typed_property_store_owner(lines: list[str], exceptions: list[str], set_index: int,
                                name: str, typ: str,
                                slot_context: tuple[str, str] | None) -> bool:
    if not slot_context or exceptions or set_index < 2:
        return False
    conversion_index = set_index - 1
    targets = branch_targets(lines, exceptions)
    edges = branch_edges(lines)
    for start in range(max(0, set_index - 128), conversion_index):
        if start in targets or not lines[start].startswith("getlex "):
            continue
        owner_type = _typed_read(lines[start], slot_context)
        cursor = start + 1
        while owner_type and cursor < conversion_index and lines[cursor].startswith("getproperty "):
            owner_class = _class_key_from_qname(owner_type)
            if owner_class is None:
                break
            property_name = lines[cursor].split(" ", 1)[1]
            owner_type = CLASS_READ_SLOT_TYPES.get((owner_class, "i", property_name))
            cursor += 1
        if NATIVE_OWNER_PROPERTY_TYPES.get((owner_type, name)) != typ:
            continue
        if any((source < cursor or source >= conversion_index)
               for source, target in edges if cursor <= target <= conversion_index):
            continue
        internal_targets = {
            target for source, target in edges
            if cursor <= source < conversion_index and cursor <= target <= conversion_index
        }
        blocked = targets - internal_targets - {conversion_index}
        if _depths_before_index(lines, cursor, conversion_index, 1, blocked) == {2}:
            return True
    return False


def _typed_property_literal_owner(lines: list[str], exceptions: list[str], set_index: int,
                                  name: str, typ: str,
                                  slot_context: tuple[str, str] | None) -> bool:
    if not slot_context or exceptions or set_index < 2:
        return False
    literal_index = set_index - 1
    targets = branch_targets(lines, exceptions)
    for start in range(max(0, literal_index - 128), literal_index):
        if start in targets or not lines[start].startswith("getlex "):
            continue
        owner_type = _typed_read(lines[start], slot_context)
        cursor = start + 1
        while owner_type and cursor < literal_index and lines[cursor].startswith("getproperty "):
            owner_class = _class_key_from_qname(owner_type)
            if owner_class is None:
                break
            property_name = lines[cursor].split(" ", 1)[1]
            owner_type = CLASS_READ_SLOT_TYPES.get((owner_class, "i", property_name))
            cursor += 1
        if (cursor == literal_index
                and NATIVE_OWNER_PROPERTY_TYPES.get((owner_type, name)) == typ
                and not targets.intersection(range(start + 1, set_index + 1))):
            return True
    return False


def rule_typed_property_assignment_convert(lines, exceptions, slot_context=None):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    for i in range(1, len(lines)):
        head, _, name = lines[i].partition(" ")
        if head not in ("setproperty", "initproperty") or not is_qname(name):
            continue
        typ = conversion_type(lines[i - 1])
        if not typ:
            continue
        if SLOT_TYPES.get(name) == typ:
            changed[i - 1] = None
            continue
        if (slot_context and CLASS_SLOT_TYPES.get((*slot_context, name)) == typ
                and _scoped_setproperty_object(lines, exceptions, i, name)):
            changed[i - 1] = None
            continue
        if _typed_property_store_owner(lines, exceptions, i, name, typ, slot_context):
            changed[i - 1] = None
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_typed_property_read_cast(lines, exceptions, slot_context=None):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    for i in range(1, len(lines) - 1):
        typ = _operand(lines[i], "astype")
        prev_head, _, name = lines[i - 1].partition(" ")
        if (typ and typ not in VALUE_TYPES and prev_head == "getproperty" and is_qname(name)
                and SLOT_TYPES.get(name) == typ and lines[i + 1] == f"coerce {typ}" and i not in targets):
            changed[i] = None
        if (typ and typ not in VALUE_TYPES and prev_head == "getlex" and is_qname(name)
                and lines[i + 1] == f"coerce {typ}" and i not in targets):
            slot_type = READ_SLOT_TYPES.get(name)
            if slot_type is None and slot_context:
                slot_type = CLASS_READ_SLOT_TYPES.get((*slot_context, name))
            if slot_type == typ:
                changed[i] = None
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_typed_property_read_coerce(lines, exceptions, slot_context=None):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    for i in range(1, len(lines)):
        if i in targets:
            continue
        typ = _operand(lines[i], "coerce")
        if not typ or typ in VALUE_TYPES:
            continue
        prev = lines[i - 1]
        if prev.startswith("getproperty "):
            name = prev.split(" ", 1)[1]
            slot_type = SLOT_TYPES.get(name)
            if slot_type and slot_type not in VALUE_TYPES and (slot_type == typ or typ == "pkg:::Object"):
                changed[i] = None
        elif prev.startswith("getlex "):
            name = prev.split(" ", 1)[1]
            slot_type = READ_SLOT_TYPES.get(name)
            if slot_type is None and slot_context:
                slot_type = CLASS_READ_SLOT_TYPES.get((*slot_context, name))
            if slot_type and slot_type not in VALUE_TYPES and (slot_type == typ or typ == "pkg:::Object"):
                changed[i] = None
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def _constructed_vector_type(lines: list[str], index: int) -> str | None:
    if index < 3 or not lines[index].startswith("construct "):
        return None
    if (lines[index - 3] == "getlex pkg:__AS3__.vec::Vector"
            and lines[index - 2].startswith("getlex ")
            and lines[index - 1] == "applytype 1"):
        typ = lines[index - 2].split(" ", 1)[1]
        if is_type(typ):
            return f"pkg:__AS3__.vec::Vector.<{typ}>"
    return None


def rule_constructed_value_coerce(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    for i in range(1, len(lines)):
        typ = _operand(lines[i], "coerce")
        if not typ or typ in VALUE_TYPES or i in targets:
            continue
        prev = lines[i - 1]
        if prev.startswith("constructprop "):
            name, _, argc = prev.split(" ", 1)[1].rpartition(" ")
            if argc.isdigit() and name == typ and name not in SHADOWED and (
                    name in CONSTRUCTIBLE_CLASSES or name.startswith("pkg:flash.")):
                changed[i] = None
            elif typ == "pkg:haxe::IMap" and name in MAP_BACKING_CLASSES:
                changed[i] = None
        elif _constructed_vector_type(lines, i - 1) == typ:
            changed[i] = None
        elif typ == "pkg:::Function" and prev.startswith("newfunction "):
            changed[i] = None
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


VECTOR_COERCE_RE = re.compile(r"^coerce pkg:__AS3__\.vec::Vector\.<(.+)>$")


def vector_element_type_from_read(line: str, slot_context: tuple[str, str] | None = None) -> str | None:
    if line.startswith("getproperty "):
        typ = SLOT_TYPES.get(line.split(" ", 1)[1])
    elif line.startswith("getlex "):
        name = line.split(" ", 1)[1]
        typ = READ_SLOT_TYPES.get(name)
        if typ is None and slot_context:
            typ = CLASS_READ_SLOT_TYPES.get((*slot_context, name))
    else:
        typ = None
    if not typ:
        return None
    match = VECTOR_COERCE_RE.match("coerce " + typ)
    return match.group(1) if match else None


def map_backing_type_from_read(line: str) -> str | None:
    if line.startswith(("getproperty ", "getlex ")):
        return MAP_BACKING_TYPES.get(line.split(" ", 1)[1])
    return None


def branch_edges(lines: list[str]) -> list[tuple[int, int]]:
    edges = []
    for i, line in enumerate(lines):
        if line.split(" ", 1)[0].startswith(("if", "jump", "lookupswitch")):
            edges.extend((i, int(n)) for n in LABEL.findall(line))
    return edges


def local_fact_reaches(edges: list[tuple[int, int]], targets: set[int], assigned: int, read: int) -> bool:
    edge_targets = {dst for _, dst in edges}
    if any(src < assigned < dst <= read for src, dst in edges):
        return False
    return not any(assigned < t <= read for t in targets if t not in edge_targets)


def rule_vector_index_coerce(lines, exceptions, slot_context=None, param_types=None):
    targets = branch_targets(lines, exceptions)
    edges = branch_edges(lines)
    local_types: dict[str, tuple[str, int]] = {}
    for register, param_type in enumerate(param_types or [], 1):
        if VECTOR_COERCE_RE.match("coerce " + param_type):
            local_types[str(register)] = (param_type, -1)
    stack: list[str | None] = []
    changed: dict[int, str | None] = {}

    def pop() -> str | None:
        return stack.pop() if stack else None

    def vector_element(typ: str | None) -> str | None:
        match = VECTOR_COERCE_RE.match("coerce " + typ) if typ else None
        return match.group(1) if match else None

    for i, line in enumerate(lines):
        if i in targets:
            stack.clear()
        head, _, rest = line.partition(" ")
        if head == "getlocal":
            known = local_types.get(rest)
            if known and local_fact_reaches(edges, targets, known[1], i):
                stack.append(known[0])
            else:
                stack.append(None)
        elif head == "setlocal":
            typ = pop()
            if typ is None and i > 0 and VECTOR_COERCE_RE.match(lines[i - 1]):
                typ = lines[i - 1].split(" ", 1)[1]
            if typ is not None:
                local_types[rest] = (typ, i)
            else:
                local_types.pop(rest, None)
        elif head in {"kill", "inclocal", "declocal", "inclocal_i", "declocal_i"}:
            local_types.pop(rest, None)
        elif head == "getlex":
            stack.append(_typed_read(line, slot_context))
        elif head in {"findpropstrict", "findproperty", "getglobalscope", "getscopeobject",
                      "getouterscope", "newfunction"}:
            stack.append(None)
        elif head in STACK_PUSH_OPS:
            stack.append("pkg:::String" if head == "pushstring" else None)
        elif head == "getproperty":
            if rest == "{pkg:}::[]":
                pop()
                owner = pop()
                stack.append(vector_element(owner))
            else:
                owner = pop()
                typ = _typed_read(line, slot_context)
                if typ is None and owner:
                    owner_class = _class_key_from_qname(owner)
                    if owner_class:
                        typ = CLASS_READ_SLOT_TYPES.get((owner_class, "i", rest))
                stack.append(typ)
        elif head in {"coerce", "astype"}:
            if (head == "coerce" and i > 0 and lines[i - 1] == "getproperty {pkg:}::[]" and stack
                    and stack[-1] == rest and i not in targets and i - 1 not in targets):
                changed[i] = None
            if stack:
                stack[-1] = rest if is_type(rest) else None
        elif head in {"coerce_s", "convert_s", "convert_d", "convert_i", "convert_u", "convert_b"}:
            typ = conversion_type(line)
            if (i > 0 and lines[i - 1] == "getproperty {pkg:}::[]" and stack
                    and stack[-1] == typ and i not in targets and i - 1 not in targets):
                changed[i] = None
            if stack:
                stack[-1] = typ
        elif head in {"coerce_a", "coerce_b", "coerce_d", "coerce_i", "coerce_u", "coerce_o",
                      "convert_o", "checkfilter", "not", "negate", "negate_i", "increment",
                      "increment_i", "decrement", "decrement_i", "bitnot"}:
            if stack:
                stack[-1] = None
        elif head in {"add", "subtract", "multiply", "divide", "modulo", "lshift", "rshift",
                      "urshift", "bitand", "bitor", "bitxor", "equals", "strictequals", "lessthan",
                      "lessequals", "greaterthan", "greaterequals", "instanceof", "istype", "istypelate",
                      "in", "add_i", "subtract_i", "multiply_i"}:
            if len(stack) < 2:
                stack.clear()
            else:
                del stack[-2:]
                stack.append(None)
        elif head in {"callproperty", "callproplex", "callpropvoid"}:
            call = _callproperty(line)
            if call is None or len(stack) < call[1] + 1:
                stack.clear()
            else:
                name, argc = call
                del stack[-(argc + 1):]
                if head != "callpropvoid":
                    stack.append(METHOD_RETURNS.get(name))
        elif head == "dup" or head == "swap":
            stack.clear()
        else:
            stack.clear()
        if head.startswith(("if", "jump", "lookupswitch")) or head in {"returnvalue", "returnvoid", "throw"}:
            stack.clear()
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_typed_local_read_cast(lines, exceptions, param_types=None):
    targets = branch_targets(lines, exceptions)
    edges = branch_edges(lines)
    local_vectors: dict[str, tuple[str, int]] = {}
    local_types: dict[str, tuple[str, int]] = {
        str(register): (typ, -1)
        for register, typ in enumerate(param_types or [], 1)
        if typ not in VALUE_TYPES and typ != "*"
    }
    changed: dict[int, str | None] = {}

    def remember_type(reg: str, typ: str, index: int) -> None:
        if typ not in VALUE_TYPES:
            local_types[reg] = (typ, index)
        else:
            local_types.pop(reg, None)

    for i, line in enumerate(lines):
        head, _, rest = line.partition(" ")
        if head == "setlocal":
            previous = VECTOR_COERCE_RE.match(lines[i - 1]) if i > 0 else None
            if previous:
                local_vectors[rest] = (previous.group(1), i)
            elif i > 0 and (element_type := vector_element_type_from_read(lines[i - 1])):
                local_vectors[rest] = (element_type, i)
            else:
                local_vectors.pop(rest, None)

            assigned_type = conversion_type(lines[i - 1]) if i > 0 else None
            if assigned_type:
                remember_type(rest, assigned_type, i)
            elif i >= 3 and lines[i - 1] == "getproperty {pkg:}::[]" and lines[i - 3].startswith("getlocal "):
                source_reg = lines[i - 3].split(" ", 1)[1]
                known_vector = local_vectors.get(source_reg)
                if (known_vector and local_fact_reaches(edges, targets, known_vector[1], i)
                        and i - 2 not in targets and i - 1 not in targets):
                    remember_type(rest, known_vector[0], i)
                else:
                    local_types.pop(rest, None)
            else:
                local_types.pop(rest, None)
        elif head in {"kill", "inclocal", "declocal", "inclocal_i", "declocal_i"}:
            local_vectors.pop(rest, None)
            local_types.pop(rest, None)

        if (i + 2 < len(lines) and line.startswith("getlocal ") and lines[i + 1].startswith("astype ")
                and lines[i + 2] == "coerce " + lines[i + 1].split(" ", 1)[1] and i + 1 not in targets):
            reg = line.split(" ", 1)[1]
            typ = lines[i + 1].split(" ", 1)[1]
            known_type = local_types.get(reg)
            if known_type and known_type[0] == typ and local_fact_reaches(edges, targets, known_type[1], i + 1):
                changed[i + 1] = None
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


_UINT_STORE_CONSTANT_RE = re.compile(r"^push(?:byte|short|int|uint) (\d+)$")


def rule_uint_register_increment(lines, exceptions, param_types=None):
    params = list(param_types or [])
    sites = [
        i for i in range(len(lines) - 4)
        if lines[i].startswith("getlocal ")
        and lines[i + 1] == "pushint 1" and lines[i + 2] in ("add_i", "subtract_i") and lines[i + 3] == "convert_u"
        and lines[i + 4] == lines[i].replace("getlocal ", "setlocal ", 1)
    ]
    if not sites:
        return (lines, exceptions), False
    targets = branch_targets(lines, exceptions)
    proved: dict[str, bool] = {}

    def uint_register(reg: str) -> bool:
        if reg in proved:
            return proved[reg]
        ok = reg.isdigit() and reg != "0"
        index = int(reg) if ok else 0
        if ok and index <= len(params):
            ok = params[index - 1] == "pkg:::uint"
        first_use = None
        for i, line in enumerate(lines):
            if not ok:
                break
            head, _, rest = line.partition(" ")
            if head == "setlocal" and rest == reg:
                first_use = first_use or "set"
                previous = lines[i - 1] if i > 0 else ""
                ok = previous == "convert_u" or bool(_UINT_STORE_CONSTANT_RE.match(previous))
            elif head == "getlocal" and rest == reg:
                first_use = first_use or "get"
            elif (head in ("inclocal", "inclocal_i", "declocal", "declocal_i", "kill", "hasnext2")
                  and reg in rest.replace(",", " ").split()):
                ok = False
        if ok and index > len(params):
            ok = first_use == "set"
        proved[reg] = ok
        return ok

    changed: dict[int, str | None] = {}
    for i in sites:
        if i + 2 in targets or i + 1 in targets:
            continue
        if uint_register(lines[i].split(" ", 1)[1]):
            changed[i + 1] = "increment" if lines[i + 2] == "add_i" else "decrement"
            changed[i + 2] = None
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


_POSTFIX_PURE_PUSH_RE = re.compile(
    r"^(?:getlocal \d+|getlex \S+|findpropstrict \S+|findproperty \S+|getscopeobject \d+"
    r"|push(?:byte|short|int|uint|double|string) .+|pushtrue|pushfalse|pushnull|pushnan|pushundefined)$")


def rule_postfix_index_order(lines, exceptions, param_types=None):
    if exceptions:
        return (lines, exceptions), False
    params = list(param_types or [])
    sites = [
        i for i in range(1, len(lines) - 7)
        if lines[i].startswith("getlocal ") and lines[i + 1] == "dup" and lines[i + 2] == "convert_u"
        and lines[i + 3].startswith("setlocal ") and lines[i + 4] in ("increment", "decrement")
        and lines[i + 5] == "convert_u" and lines[i + 6] == lines[i].replace("getlocal ", "setlocal ", 1)
        and lines[i + 7] == lines[i + 3].replace("setlocal ", "getlocal ", 1)
        and lines[i + 3] != lines[i + 6]
    ]
    if not sites:
        return (lines, exceptions), False
    targets = branch_targets(lines, exceptions)

    def uint_register(reg: str) -> bool:
        if not reg.isdigit() or reg == "0":
            return False
        if int(reg) <= len(params):
            return params[int(reg) - 1] == "pkg:::uint"
        first_use = next((line.partition(" ")[0] for line in lines
                          if line in (f"getlocal {reg}", f"setlocal {reg}")), None)
        if first_use != "setlocal":
            return False
        for k, line in enumerate(lines):
            head, _, rest = line.partition(" ")
            if head == "setlocal" and rest == reg:
                previous = lines[k - 1] if k > 0 else ""
                if previous != "convert_u" and not _UINT_STORE_CONSTANT_RE.match(previous):
                    return False
            elif (head in ("inclocal", "inclocal_i", "declocal", "declocal_i", "kill", "hasnext2")
                  and reg in rest.replace(",", " ").split()):
                return False
        return True

    out = list(lines)
    moved: list[tuple[int, int]] = []
    for i in reversed(sites):
        index_reg = lines[i].split(" ", 1)[1]
        temp_reg = lines[i + 3].split(" ", 1)[1]
        j = i
        while j > 0:
            line = lines[j - 1]
            if _POSTFIX_PURE_PUSH_RE.match(line):
                reg = line.split(" ", 1)[1] if line.startswith("getlocal ") else None
                if reg in (index_reg, temp_reg):
                    break
            elif not (line.startswith("getproperty ") and "[]" not in line):
                break
            j -= 1
        while j < i:
            depth, ok = 0, True
            for line in lines[j:i]:
                depth += 0 if line.startswith("getproperty ") else 1
                if line.startswith("getproperty ") and depth == 0:
                    ok = False
                    break
            if ok:
                break
            j += 1
        if j == i or targets & set(range(j + 1, i + 8)) or not uint_register(index_reg):
            continue
        if any(start < i + 8 and j < end for start, end in moved):
            continue
        op = "add_i" if lines[i + 4] == "increment" else "subtract_i"
        block = [f"getlocal {index_reg}", "convert_u", f"setlocal {temp_reg}", f"getlocal {temp_reg}",
                 "pushint 1", op, "convert_u", f"setlocal {index_reg}"]
        out[j:i + 8] = block + lines[j:i] + [f"getlocal {temp_reg}"]
        moved.append((j, i + 8))
    if not moved:
        return (lines, exceptions), False
    starts = sorted(moved)

    def new_index(old: int) -> int:
        return old + sum(1 for start, end in starts if old >= end)

    def relabel(text: str) -> str:
        return LABEL.sub(lambda m: f"L{new_index(int(m.group(1)))}", text)

    out = [relabel(line) if line.split(" ", 1)[0].startswith(("if", "jump", "lookupswitch")) else line
           for line in out]
    return (out, exceptions), True


def rule_typed_local_read_coerce(lines, exceptions, param_types=None):
    targets = branch_targets(lines, exceptions)
    edges = branch_edges(lines)
    local_vectors: dict[str, tuple[str, int]] = {}
    local_types: dict[str, tuple[str, int]] = {
        str(register): (typ, -1)
        for register, typ in enumerate(param_types or [], 1)
        if typ not in VALUE_TYPES and typ != "*"
    }
    changed: dict[int, str | None] = {}

    def remember_type(reg: str, typ: str, index: int) -> None:
        if typ not in VALUE_TYPES:
            local_types[reg] = (typ, index)
        else:
            local_types.pop(reg, None)

    for i, line in enumerate(lines):
        head, _, rest = line.partition(" ")
        if head == "setlocal":
            previous = VECTOR_COERCE_RE.match(lines[i - 1]) if i > 0 else None
            if previous:
                local_vectors[rest] = (previous.group(1), i)
            elif i > 0 and (element_type := vector_element_type_from_read(lines[i - 1])):
                local_vectors[rest] = (element_type, i)
            else:
                local_vectors.pop(rest, None)

            assigned_type = conversion_type(lines[i - 1]) if i > 0 else None
            if assigned_type:
                remember_type(rest, assigned_type, i)
            elif i >= 3 and lines[i - 1] == "getproperty {pkg:}::[]" and lines[i - 3].startswith("getlocal "):
                source_reg = lines[i - 3].split(" ", 1)[1]
                known_vector = local_vectors.get(source_reg)
                if (known_vector and local_fact_reaches(edges, targets, known_vector[1], i)
                        and i - 2 not in targets and i - 1 not in targets):
                    remember_type(rest, known_vector[0], i)
                else:
                    local_types.pop(rest, None)
            else:
                local_types.pop(rest, None)
        elif head in {"kill", "inclocal", "declocal", "inclocal_i", "declocal_i"}:
            local_vectors.pop(rest, None)
            local_types.pop(rest, None)

        if i + 1 < len(lines) and line.startswith("getlocal ") and i + 1 not in targets:
            typ = _operand(lines[i + 1], "coerce")
            if typ and typ not in VALUE_TYPES:
                reg = line.split(" ", 1)[1]
                known_type = local_types.get(reg)
                if (known_type and local_fact_reaches(edges, targets, known_type[1], i + 1)
                        and (known_type[0] == typ or typ == "pkg:::Object")):
                    changed[i + 1] = None
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_map_backing_read_coerce(lines, exceptions):
    targets = branch_targets(lines, exceptions)
    edges = branch_edges(lines)
    local_maps: dict[str, tuple[str, int]] = {}
    changed: dict[int, str | None] = {}

    def remember_map(reg: str, typ: str, index: int) -> None:
        if typ in MAP_BACKING_CLASSES:
            local_maps[reg] = (typ, index)
        else:
            local_maps.pop(reg, None)

    for i, line in enumerate(lines):
        head, _, rest = line.partition(" ")
        if head == "setlocal":
            map_type = _constructed_map_type(lines, i - 1)
            if map_type:
                remember_map(rest, map_type, i)
            elif i > 0 and (map_type := map_backing_type_from_read(lines[i - 1])):
                remember_map(rest, map_type, i)
            else:
                local_maps.pop(rest, None)
        elif head in {"kill", "inclocal", "declocal", "inclocal_i", "declocal_i"}:
            local_maps.pop(rest, None)

        if line.startswith("coerce ") and i not in targets:
            typ = line.split(" ", 1)[1]
            prev = lines[i - 1] if i > 0 else ""
            if typ in MAP_BACKING_CLASSES and map_backing_type_from_read(prev) == typ:
                changed[i] = None

        if (i + 1 < len(lines) and line.startswith("coerce ") and lines[i + 1] == "getproperty pkg:::h"
                and i not in targets and i + 1 not in targets):
            typ = line.split(" ", 1)[1]
            if typ not in MAP_BACKING_CLASSES:
                continue
            prev = lines[i - 1] if i > 0 else ""
            if map_backing_type_from_read(prev) == typ:
                changed[i] = None
            elif prev.startswith("getlocal "):
                reg = prev.split(" ", 1)[1]
                known = local_maps.get(reg)
                if known and known[0] == typ and local_fact_reaches(edges, targets, known[1], i):
                    changed[i] = None
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
    ("vector-construct", rule_vector_construct),
    ("null-coerce", rule_null_coerce),
    ("coerce-any", rule_coerce_any),
    ("object-coerce", rule_object_coerce_after_reference_cast),
    ("not-branch", rule_not_branch),
    ("double-not-bool-convert", rule_double_not_bool_convert),
    ("compare-branch", rule_compare_branch),
    ("non-nan-relational-branch", rule_non_nan_relational_branch),
    ("const-uint", rule_const_uint),
    ("const-bool", rule_const_bool),
    ("const-int", rule_const_int),
    ("integer-literal-before-convert-d", rule_integer_literal_before_convert_d),
    ("const-number", rule_const_number),
    ("const-bitwise", rule_const_bitwise),
    ("const-number-fold", rule_const_number_fold),
    ("public-index-namespace", rule_public_index_namespace),
    ("int-op-convert", rule_int_op_convert),
    ("numeric-literal-context", rule_numeric_literal_context),
    ("vector-modulo-index-convert", rule_vector_modulo_index_convert),
    ("integral-modulo-convert", rule_integral_modulo_convert),
    ("string-call-argument-coerce", rule_string_call_argument_coerce),
    ("numeric-owner-call", rule_numeric_owner_call),
    ("math-nan", rule_math_nan),
    ("init-set", rule_init_set),
    ("swap-push", rule_swap_push),
    ("coerce-string", rule_coerce_string),
    ("audited-primitive-string-concat", rule_audited_primitive_string_concat),
    ("coerce-then-astype", rule_coerce_then_astype),
    ("double-convert", rule_double_convert),
    ("dominating-reference-coerce", rule_dominating_reference_coerce),
    ("typed-property-convert", rule_typed_property_assignment_convert),
    ("typed-property-read-cast", rule_typed_property_read_cast),
    ("typed-property-read-coerce", rule_typed_property_read_coerce),
    ("constructed-value-coerce", rule_constructed_value_coerce),
    ("vector-index-coerce", rule_vector_index_coerce),
    ("typed-local-read-cast", rule_typed_local_read_cast),
    ("typed-local-read-coerce", rule_typed_local_read_coerce),
    ("postfix-index-order", rule_postfix_index_order),
    ("uint-register-increment", rule_uint_register_increment),
    ("map-backing-read-coerce", rule_map_backing_read_coerce),
    ("as3-helper-conversions", rule_as3_helper_conversions),
    ("as3-helper-branch-conversion", rule_as3_helper_branch_conversion),
    ("as3-to-bool-branch", rule_as3_to_bool_branch),
    ("as3-helper-cfg-conversion", rule_as3_helper_cfg_conversion),
    ("as3-as-type-marker", rule_as3_as_type_marker),
    ("as3-as-type", rule_as3_as_type),
    ("as3-as-type-null", rule_as3_as_type_null),
    ("as3-has-key-stringmap", rule_as3_has_key_stringmap),
    ("haxe-imap-namespace", rule_haxe_imap_namespace),
    ("method-call-return-convert", rule_method_call_return_convert),
    ("nullable-call-branch-coerce", rule_nullable_call_branch_coerce),
    ("interface-call-return-convert", rule_interface_call_return_convert),
    ("interface-namespace-call", rule_interface_namespace_call),
    ("private-member-namespace", rule_private_member_namespace),
    ("string-builtin-namespace-call", rule_string_builtin_namespace_call),
    ("builtin-call-object-coerce", rule_builtin_call_object_coerce),
    ("object-coerce-integral-convert", rule_object_coerce_integral_convert),
    ("std-string-known-string", rule_std_string_known_string),
    ("as3-index", rule_as3_index),
    ("as3-set-index", rule_as3_set_index),
    ("dup-setlocal", rule_dup_setlocal),
    ("branch-bool", rule_branch_bool),
    ("object-coerce-branch", rule_object_coerce_branch),
    ("constant-branch", rule_constant_branch),
    ("branch-jump-simplify", rule_branch_jump_simplify),
    ("jump-next", rule_jump_next),
    ("jump-trampoline", rule_jump_trampoline),
    ("switch-case-layout", rule_switch_case_layout),
    ("terminal-literal-return", rule_terminal_literal_return),
    ("terminal-local-return", rule_terminal_local_return),
    ("terminal-jump-return", rule_terminal_jump_return),
    ("void-call", rule_void_call),
    ("return-astype-object-coerce", rule_return_astype_object_coerce),
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
INSTANCE_TRAITS: set[str] = set()
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


def instance_traits(blocks: list[bytes], ns_aliases: dict[str, str] | None = None) -> set[str]:
    out = set()
    for data in blocks:
        abc = Abc(data, ns_aliases)
        for inst in abc.instances:
            out.update(abc.mn(t["name"]) for t in inst["traits"])
    return out


def static_method_class(key: str) -> str | None:
    if "/s/" not in key or key.startswith("script ") or "/fn" in key.split("/s/", 1)[1]:
        return None
    return key.split("/s/", 1)[0]


def method_slot_context(key: str) -> tuple[str, str] | None:
    if key.startswith("script ") or "/fn" in key:
        return None
    if key.endswith("/iinit"):
        return key[:-6], "i"
    if key.endswith("/cinit"):
        return key[:-6], "s"
    if "/i/" in key:
        return key.split("/i/", 1)[0], "i"
    if "/s/" in key:
        return key.split("/s/", 1)[0], "s"
    return None


def static_trait_qname(cls: str, qname: str) -> str | None:
    statics = STATIC_TRAITS.get(cls)
    if not statics or not is_qname(qname):
        return None
    if qname in statics:
        return qname
    local = qname.rsplit("::", 1)[-1]
    matches = [name for name in statics if name.rsplit("::", 1)[-1] == local]
    return matches[0] if len(matches) == 1 else None


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
            if (static_trait_qname(cls, name) is not None) if is_qname(name) else (local in static_locals):
                return (lines, exceptions), False
    return _rebuild(lines, exceptions, {0: None, 1: None}), True


def rule_instance_prologue(lines, exceptions, slot_context):
    if slot_context is None or slot_context[1] != "i" or lines[:2] != ["getlocal 0", "pushscope"]:
        return (lines, exceptions), False
    if "setlocal 0" in lines or 1 in branch_targets(lines, exceptions):
        return (lines, exceptions), False
    for line in lines[2:]:
        head, _, operand = line.partition(" ")
        if head in SCOPE_OPS:
            return (lines, exceptions), False
        if head in LOOKUPS:
            name = operand.split(" ")[0]
            if not is_qname(name) or name in INSTANCE_TRAITS:
                return (lines, exceptions), False
    return _rebuild(lines, exceptions, {0: None, 1: None}), True


def _static_property_object(lines: list[str], exceptions: list[str], set_index: int) -> int | None:
    targets = branch_targets(lines, exceptions)
    for j in range(max(0, set_index - 40), set_index):
        if lines[j] != "getlocal 0":
            continue
        if targets & set(range(j + 1, set_index)):
            continue
        depth = 0
        ok = True
        for k in range(j, set_index):
            delta = _stack_delta(lines[k])
            if delta is None:
                ok = False
                break
            depth += delta
            if k < set_index - 1 and depth < 1:
                ok = False
                break
        if ok and depth == 2:
            return j
    return None


def _static_scope_property_object(lines: list[str], exceptions: list[str], set_index: int,
                                  declared: str, cls: str) -> int | None:
    targets = branch_targets(lines, exceptions)
    for j in range(max(0, set_index - 40), set_index):
        if not lines[j].startswith("findpropstrict "):
            continue
        if static_trait_qname(cls, lines[j].split(" ", 1)[1]) != declared:
            continue
        if targets & set(range(j, set_index)):
            continue
        depth = 0
        ok = True
        for k in range(j, set_index):
            delta = _stack_delta(lines[k])
            if delta is None:
                ok = False
                break
            depth += delta
            if k < set_index - 1 and depth < 1:
                ok = False
                break
        if ok and depth == 2:
            return j
    return None


def rule_static_member_access(lines, exceptions, cls):
    if cls is None or cls not in STATIC_TRAITS or "setlocal 0" in lines:
        return (lines, exceptions), False
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str | None] = {}
    if lines[:2] == ["getlocal 0", "pushscope"] and 1 not in targets:
        for i, line in enumerate(lines[2:], start=2):
            if line.startswith("getlex "):
                q = line.split(" ", 1)[1]
                declared = static_trait_qname(cls, q)
                if declared is not None:
                    changed[i] = "getstatic " + declared
    i = 0
    while i + 1 < len(lines):
        a, b = lines[i], lines[i + 1]
        if a == "getlocal 0" and b.startswith("getproperty ") and i + 1 not in targets:
            q = b.split(" ", 1)[1]
            declared = static_trait_qname(cls, q)
            if declared is not None:
                changed[i], changed[i + 1] = "getstatic " + declared, None
                i += 2
                continue
        i += 1
    i = 0
    while i + 2 < len(lines):
        a, b, c = lines[i], lines[i + 1], lines[i + 2]
        if (a.startswith("findpropstrict ") and b == "swap" and c.startswith("setproperty ")
                and not targets & {i + 1, i + 2}):
            found = static_trait_qname(cls, a.split(" ", 1)[1])
            written = static_trait_qname(cls, c.split(" ", 1)[1])
            if found is not None and found == written:
                changed[i], changed[i + 1], changed[i + 2] = None, None, "setstatic " + found
                i += 3
                continue
        i += 1
    for i, line in enumerate(lines):
        if not line.startswith("setproperty ") or i in targets:
            continue
        declared = static_trait_qname(cls, line.split(" ", 1)[1])
        if declared is None:
            continue
        obj = _static_scope_property_object(lines, exceptions, i, declared, cls)
        if obj is not None:
            changed[obj] = None
            changed[i] = "setstatic " + declared
            continue
        obj = _static_property_object(lines, exceptions, i)
        if obj is not None:
            changed[obj] = None
            changed[i] = "setstatic " + declared
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


INSTANCE_LITERAL_HEADS = {
    "pushbyte", "pushshort", "pushint", "pushuint", "pushdouble", "pushstring",
    "pushnull", "pushundefined", "pushtrue", "pushfalse", "pushnan",
}


def _literal_slot_safe(line: str, typ: str) -> bool:
    head = line.partition(" ")[0]
    if head not in INSTANCE_LITERAL_HEADS:
        return False
    if typ == "pkg:::Object":
        return head != "pushundefined"
    if typ == "pkg:::String":
        return head in {"pushstring", "pushnull"}
    if typ == "pkg:::Boolean":
        return head in {"pushtrue", "pushfalse"}
    if typ in {"pkg:::int", "pkg:::uint", "pkg:::Number"}:
        return head in {"pushbyte", "pushshort", "pushint", "pushuint", "pushdouble", "pushnan"}
    return head == "pushnull" and typ not in VALUE_TYPES and typ != "pkg:::void"


def rule_instance_literal_order(lines, exceptions, initializer_class=None):
    if initializer_class is None or lines[:2] != ["getlocal 0", "pushscope"] or "setlocal 0" in lines:
        return (lines, exceptions), False
    if any(line.partition(" ")[0] in SCOPE_OPS for line in lines[2:]):
        return (lines, exceptions), False
    targets = branch_targets(lines, exceptions)
    changed: dict[int, str] = {}

    def slot_type(name: str) -> str | None:
        typ = CLASS_INSTANCE_LITERAL_SLOTS.get((initializer_class, name))
        if typ is not None:
            return typ
        local = name.rsplit("::", 1)[-1]
        private = f"private::{local}"
        if (name == f"pkg:::{local}" and (initializer_class, "i", local) in PRIVATE_MEMBER_LOCALS
                and (initializer_class, "i", local) not in PUBLIC_MEMBER_LOCALS):
            return CLASS_INSTANCE_LITERAL_SLOTS.get((initializer_class, private))
        return None

    i = 2
    while i + 2 < len(lines):
        start = i
        records: list[tuple[str, tuple[str, str, str]]] = []
        names: set[str] = set()
        while i + 2 < len(lines):
            find, literal, store = lines[i:i + 3]
            if not find.startswith("findpropstrict ") or not store.startswith("setproperty "):
                break
            name = find.split(" ", 1)[1]
            if store.split(" ", 1)[1] != name or name in names or targets & {i, i + 1, i + 2}:
                break
            typ = slot_type(name)
            if typ is None or not _literal_slot_safe(literal, typ):
                break
            records.append((name, (find, literal, store)))
            names.add(name)
            i += 3
        if len(records) >= 2:
            ordered = sorted(records, key=lambda record: record[0])
            if ordered != records:
                flattened = [line for _name, triple in ordered for line in triple]
                changed.update({start + offset: line for offset, line in enumerate(flattened)})
        i = i if i > start else i + 1
    return (_rebuild(lines, exceptions, changed) if changed else (lines, exceptions)), bool(changed)


def rule_enum_instance_init(lines, exceptions, initializer_class=None):
    if (initializer_class not in ENUM_INSTANCE_CLASSES or exceptions
            or lines[:2] != ["getlocal 0", "pushscope"]):
        return (lines, exceptions), False
    enum_write = ["findpropstrict pkg:::__enum__", "pushtrue", "initproperty pkg:::__enum__"]
    if lines[2:5] != enum_write or branch_targets(lines, exceptions) & {2, 3, 4}:
        return (lines, exceptions), False
    return _rebuild(lines, exceptions, {2: None, 3: None, 4: None}), True


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
              fixed: int | None = None, static_class: str | None = None,
              slot_context: tuple[str, str] | None = None,
              param_types: list[str] | None = None,
              initializer_class: str | None = None) -> tuple[list[str], list[str], set[str]]:
    applied = set()
    (lines, exceptions), hit = rule_static_self(lines, exceptions, static_class)
    if hit:
        applied.add("static-self")
    (lines, exceptions), hit = rule_static_prologue(lines, exceptions, static_class)
    if hit:
        applied.add("static-prologue")
    for _ in range(8):
        before = lines
        for name, rule in EQUIVALENCES:
            if rule == rule_typed_property_assignment_convert:
                (lines, exceptions), hit = rule(lines, exceptions, slot_context)
            elif rule in (rule_typed_property_read_cast, rule_typed_property_read_coerce):
                (lines, exceptions), hit = rule(lines, exceptions, slot_context)
            elif rule in (rule_typed_local_read_cast, rule_typed_local_read_coerce, rule_uint_register_increment,
                          rule_postfix_index_order):
                (lines, exceptions), hit = rule(lines, exceptions, param_types)
            elif rule == rule_vector_index_coerce:
                (lines, exceptions), hit = rule(lines, exceptions, slot_context, param_types)
            elif rule == rule_private_member_namespace:
                (lines, exceptions), hit = rule(lines, exceptions, slot_context)
            elif rule == rule_string_builtin_namespace_call:
                (lines, exceptions), hit = rule(lines, exceptions, param_types, slot_context)
            elif rule == rule_std_string_known_string:
                (lines, exceptions), hit = rule(lines, exceptions, param_types, slot_context)
            elif rule == rule_numeric_owner_call:
                (lines, exceptions), hit = rule(lines, exceptions, param_types, slot_context)
            elif rule == rule_non_nan_relational_branch:
                (lines, exceptions), hit = rule(lines, exceptions, param_types, slot_context)
            elif rule == rule_integral_modulo_convert:
                (lines, exceptions), hit = rule(lines, exceptions, slot_context)
            elif rule == rule_audited_primitive_string_concat:
                (lines, exceptions), hit = rule(lines, exceptions, param_types, slot_context)
            elif rule == rule_numeric_literal_context:
                (lines, exceptions), hit = rule(lines, exceptions, ret, slot_context)
            elif rule in (rule_return_convert, rule_return_astype_object_coerce):
                (lines, exceptions), hit = rule(lines, exceptions, ret)
            else:
                (lines, exceptions), hit = rule(lines, exceptions)
            if hit:
                applied.add(name)
        if lines == before:
            break
    (lines, exceptions), hit = rule_enum_instance_init(lines, exceptions, initializer_class)
    if hit:
        applied.add("enum-instance-init")
    (lines, exceptions), hit = rule_instance_literal_order(lines, exceptions, initializer_class)
    if hit:
        applied.add("instance-literal-order")
    (lines, exceptions), hit = rule_instance_prologue(lines, exceptions, slot_context)
    if hit:
        applied.add("instance-prologue")
    if fixed is not None:
        lines, hit = rule_registers(lines, fixed)
        if hit:
            applied.add("registers")
    return lines, exceptions, applied


def canonical_static_member_reads(lines: list[str], exceptions: list[str], cls: str | None):
    (lines, exceptions), hit_member = rule_static_member_access(lines, exceptions, cls)
    (lines, exceptions), hit_prologue = rule_static_prologue(lines, exceptions, cls)
    rules = set()
    if hit_member:
        rules.add("static-member-access")
    if hit_prologue:
        rules.add("static-prologue")
    return lines, exceptions, rules


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
        cls = abc.class_name(i, aliases)
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
            head = abc.class_name(named[0]["class"], aliases)
        add(f"script {head}/init", script["init"])
        for t in script["traits"]:
            if t["kind"] in (1, 2, 3, 5):
                add(f"script {head}/{TRAIT_KINDS[t['kind']]} {trait_name(t)}", t["method"])
    return keys


def collect(blocks: list[bytes], aliases: dict[str, str] | None = None,
            ns_aliases: dict[str, str] | None = None) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for data in blocks:
        abc = Abc(data, ns_aliases)
        pending = list(method_keys(abc, aliases).items())
        while pending:
            key, method = pending.pop()
            while key in out:
                key += "+"
            norm = normalize(abc, method, aliases)
            out[key] = norm
            pending.extend((f"{key}/fn{n}", m) for n, m in enumerate(norm["closures"]))
    return out


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
    SLOT_TYPES.clear()
    SLOT_TYPES.update(slot_types(original_blocks, ns_aliases))
    CLASS_SLOT_TYPES.clear()
    CLASS_SLOT_TYPES.update(class_slot_types(original_blocks, ns_aliases))
    CLASS_READ_SLOT_TYPES.clear()
    CLASS_READ_SLOT_TYPES.update(class_read_slot_types(original_blocks, ns_aliases))
    CLASS_INSTANCE_LITERAL_SLOTS.clear()
    CLASS_INSTANCE_LITERAL_SLOTS.update(class_instance_literal_slots(original_blocks, ns_aliases))
    ENUM_INSTANCE_CLASSES.clear()
    ENUM_INSTANCE_CLASSES.update(enum_instance_classes(original_blocks, ns_aliases))
    READ_SLOT_TYPES.clear()
    READ_SLOT_TYPES.update(read_slot_types(original_blocks, ns_aliases))
    CTOR_PARAM_TYPES.clear()
    CTOR_PARAM_TYPES.update(constructor_param_types(original_blocks, ns_aliases))
    METHOD_PARAM_TYPES.clear()
    METHOD_PARAM_TYPES.update(method_param_types(original_blocks, ns_aliases))
    OWNER_METHOD_PARAM_TYPES.clear()
    OWNER_METHOD_PARAM_TYPES.update(owner_method_param_types(original_blocks, ns_aliases))
    OWNER_METHOD_FIXED_ARITIES.clear()
    OWNER_METHOD_FIXED_ARITIES.update(owner_method_fixed_arities(original_blocks, ns_aliases))
    METHOD_RETURNS.clear()
    METHOD_RETURNS.update(method_return_types(original_blocks, ns_aliases))
    CONSTRUCTIBLE_CLASSES.clear()
    CONSTRUCTIBLE_CLASSES.update(class_names(original_blocks, ns_aliases))
    MAP_BACKING_TYPES.clear()
    MAP_BACKING_TYPES.update(map_backing_types(original_blocks, ns_aliases))
    INTERFACE_METHOD_CALLS.clear()
    INTERFACE_METHOD_RETURNS.clear()
    interface_calls, interface_returns = interface_method_facts(original_blocks, ns_aliases)
    INTERFACE_METHOD_CALLS.update(interface_calls)
    INTERFACE_METHOD_RETURNS.update(interface_returns)
    PRIVATE_MEMBER_LOCALS.clear()
    PUBLIC_MEMBER_LOCALS.clear()
    private_members, public_members = private_member_locals(original_blocks, ns_aliases)
    PRIVATE_MEMBER_LOCALS.update(private_members)
    PUBLIC_MEMBER_LOCALS.update(public_members)
    FILE_PRIVATE_CLASS_LOCALS.clear()
    FILE_PRIVATE_CLASS_LOCALS.update(file_private_class_locals(original_blocks, ns_aliases))
    for _owner, local in FILE_PRIVATE_CLASS_LOCALS:
        private = f"private::{local}"
        if private in CTOR_PARAM_TYPES:
            CTOR_PARAM_TYPES.setdefault(f"pkg:::{local}", CTOR_PARAM_TYPES[private])
    STATIC_TRAITS.clear()
    STATIC_TRAITS.update(static_traits(original_blocks, ns_aliases))
    INSTANCE_TRAITS.clear()
    INSTANCE_TRAITS.update(instance_traits(original_blocks, ns_aliases))
    INERT_CLASSES.clear()
    INERT_CLASSES.update(inert_classes(original_blocks, ns_aliases))
    if _CANONICAL is not None:
        _CANONICAL.clear()


_CANONICAL: dict[tuple[int, str | None], tuple[dict, tuple[list[str], list[str], set[str]]]] | None = None


def enable_canonical_cache() -> None:
    global _CANONICAL
    _CANONICAL = {}


def canonical_original(orig: dict, cls: str | None,
                       slot_context: tuple[str, str] | None = None,
                       initializer_class: str | None = None) -> tuple[list[str], list[str], set[str]]:
    hit = _CANONICAL.get((id(orig), cls, slot_context, initializer_class)) if _CANONICAL is not None else None
    if hit is not None and hit[0] is orig:
        return hit[1]
    result = canonical(orig["code"] or [], orig["exceptions"], orig["sig"]["ret"],
                       fixed_registers(orig["sig"]), cls, slot_context, orig["sig"]["params"], initializer_class)
    if _CANONICAL is not None:
        _CANONICAL[(id(orig), cls, slot_context, initializer_class)] = (orig, result)
    return result


def compare_one(orig: dict, comp: dict, key: str = "") -> tuple[str, str]:
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
    if rule_audited_sdk_constant_folds(
            code_o, orig["exceptions"], code_c, comp["exceptions"], key):
        return "equivalent", "sdk-constant-fold"
    cls = static_method_class(key)
    slot_context = method_slot_context(key)
    initializer_class = key[:-6] if key.endswith("/iinit") else None
    code_o, exc_o, rules_o = canonical_original(orig, cls, slot_context, initializer_class)
    code_c, exc_c, rules_c = canonical(code_c, comp["exceptions"], comp["sig"]["ret"],
                                       fixed_registers(comp["sig"]), cls, slot_context, comp["sig"]["params"],
                                       initializer_class)
    if code_o == code_c and exc_o == exc_c:
        return "equivalent", " + ".join(sorted(rules_o | rules_c))
    if rule_audited_duplicate_static_receivers(
            code_o, exc_o, code_c, exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | {"duplicate-static-receiver"}))
    static_o, static_exc_o, static_rules_o = canonical_static_member_reads(code_o, exc_o, cls)
    static_c, static_exc_c, static_rules_c = canonical_static_member_reads(code_c, exc_c, cls)
    if (static_rules_o or static_rules_c) and static_o == static_c and static_exc_o == static_exc_c:
        return "equivalent", " + ".join(sorted(rules_o | rules_c | static_rules_o | static_rules_c))
    if rule_audited_storetype_method_2100_cfg(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"storetype-bundle-costume-cfg"}))
    if rule_audited_costumetype_method_7242_cfg(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"costumetype-upgrade-validation-cfg"}))
    if rule_audited_duplicate_rmw_receivers(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"duplicate-rmw-receiver"}))
    (integer_o, integer_exc_o), integer_hit_o = rule_double_before_integer_convert(static_o, static_exc_o)
    (integer_c, integer_exc_c), integer_hit_c = rule_double_before_integer_convert(static_c, static_exc_c)
    if ((integer_hit_o or integer_hit_c) and integer_o == integer_c
            and integer_exc_o == integer_exc_c):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c | {"double-before-integer-convert"}))
    if rule_audited_typed_numeric_literal_boundary(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"typed-numeric-literal-boundary"}))
    if rule_audited_uint_object_literal(
            static_o, static_exc_o, static_c, static_exc_c, key,
            comp["code"] or []):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"uint-object-literal"}))
    if rule_audited_terminal_boolean_layout(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"terminal-boolean-layout"}))
    if rule_audited_multi_typed_numeric_literals(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"multi-typed-numeric-literals"}))
    if rule_audited_multi_typed_numeric_literals_followup(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"multi-typed-numeric-literals-followup"}))
    if rule_audited_integer_local_literal(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"integer-local-literal"}))
    if rule_audited_zero_number_call_boundary(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"zero-number-call-boundary"}))
    (enum_o, enum_exc_o), enum_hit_o = rule_audited_enum_class_argument(
        static_o, static_exc_o, key,
    )
    (enum_c, enum_exc_c), enum_hit_c = rule_audited_enum_class_argument(
        static_c, static_exc_c, key,
    )
    if ((enum_hit_o or enum_hit_c) and enum_o == enum_c
            and enum_exc_o == enum_exc_c):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"enum-class-argument"}))
    if rule_audited_controller_map_boundaries(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"controller-map-boundaries"}))
    if rule_audited_closed_map_local_stores(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"closed-map-local-stores"}))
    if rule_audited_closed_string_map_interface_boundary(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"closed-string-map-interface-boundary"}))
    if rule_audited_map_backing_has_key(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"map-backing-has-key"}))
    if rule_audited_closed_imap_local_store(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"closed-imap-local-store"}))
    if rule_audited_class25_nested_map_boundary(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"class25-nested-map-boundary"}))
    if rule_audited_controller_mapping_imap_join(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"controller-mapping-imap-join"}))
    if rule_audited_extension_context_factory_stores(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"extension-context-factory-store"}))
    if rule_audited_cast_conversion_boundary(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"cast-conversion-boundary"}))
    if rule_audited_object_local_store_coercions(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"object-local-store-coercion"}))
    if rule_audited_uint_increment(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"uint-increment"}))
    if rule_audited_modular_uint_arithmetic(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"modular-uint-arithmetic"}))
    if rule_audited_closed_reference_scalar_boundaries(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"closed-reference-scalar-boundaries"}))
    if rule_audited_function_coerce_boundaries(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"function-coerce-boundaries"}))
    if rule_audited_scalar_expression_boundaries(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"scalar-expression-boundaries"}))
    if rule_audited_class136_increment_temps(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"class136-increment-temps"}))
    if rule_audited_duplicate_empty_string_concats(
            static_o, static_exc_o, static_c, static_exc_c, key):
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c
            | {"duplicate-empty-string-concat"}))
    (jump_o, jump_exc_o), jump_hit_o = rule_idempotent_coerce_jump(static_o, static_exc_o)
    (jump_c, jump_exc_c), jump_hit_c = rule_idempotent_coerce_jump(static_c, static_exc_c)
    if (jump_hit_o or jump_hit_c) and jump_o == jump_c and jump_exc_o == jump_exc_c:
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c | {"idempotent-coerce-jump"}))
    int_o, int_hit_o = canonical_int_atoms(static_o)
    int_c, int_hit_c = canonical_int_atoms(static_c)
    if (int_hit_o or int_hit_c) and int_o == int_c and static_exc_o == static_exc_c:
        return "equivalent", " + ".join(sorted(
            rules_o | rules_c | static_rules_o | static_rules_c | {"same-int-atom"}))
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
    return {
        "totals": {"original": len(original), "compiled": len(compiled), **dict(sorted(statuses.items()))},
        "equal_with_stack_meta_diff": sum(1 for m in methods.values() if "meta" in m),
        "causes": [{"cause": c, "count": n} for c, n in causes.most_common()],
        "equivalence_rules": dict(rules.most_common()),
        "prologue_left": dict(Counter(m["prologue"] for m in methods.values() if "prologue" in m).most_common()),
        "methods": dict(sorted(methods.items())),
    }


def base_swf() -> Path:
    aliased = ROOT / "build" / "as3" / "aliased.swf"
    return aliased if aliased.exists() else ROOT / "build" / "as3" / "renamed.swf"


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
    original_path = args.original or base_swf()
    for path in (compiled_path, original_path):
        if not path.exists():
            print(f"missing {path}: run tools/export_as3.py and data/tools/compile_as3.py first", file=sys.stderr)
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
