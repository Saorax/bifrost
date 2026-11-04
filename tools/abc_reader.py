from __future__ import annotations

import struct
from dataclasses import dataclass, field

from apply_mods import swf_tags

QNAME, QNAME_A = 0x07, 0x0D
RTQNAME, RTQNAME_A = 0x0F, 0x10
RTQNAME_L, RTQNAME_LA = 0x11, 0x12
MULTINAME, MULTINAME_A = 0x09, 0x0E
MULTINAME_L, MULTINAME_LA = 0x1B, 0x1C
TYPENAME = 0x1D

TRAIT_KINDS = {0: "slot", 1: "method", 2: "getter", 3: "setter", 4: "class", 5: "function", 6: "const"}

NAMESPACE_KINDS = {
    0x08: "Namespace", 0x16: "PackageNamespace", 0x17: "PackageInternalNs",
    0x18: "ProtectedNamespace", 0x19: "ExplicitNamespace", 0x1A: "StaticProtectedNs",
    0x05: "PrivateNamespace",
}


class AbcError(Exception):
    pass


class _Stream:
    def __init__(self, data: bytes, pos: int = 0):
        self.data, self.pos = data, pos

    def u8(self) -> int:
        v = self.data[self.pos]
        self.pos += 1
        return v

    def u16(self) -> int:
        v = struct.unpack_from("<H", self.data, self.pos)[0]
        self.pos += 2
        return v

    def u30(self) -> int:
        result = shift = 0
        for _ in range(5):
            b = self.data[self.pos]
            self.pos += 1
            result |= (b & 0x7F) << shift
            if not b & 0x80:
                break
            shift += 7
        return result & 0xFFFFFFFF

    def d64(self) -> float:
        v = struct.unpack_from("<d", self.data, self.pos)[0]
        self.pos += 8
        return v

    def bytes(self, n: int) -> bytes:
        v = self.data[self.pos:self.pos + n]
        if len(v) != n:
            raise AbcError("unexpected end of ABC data")
        self.pos += n
        return v


@dataclass
class Multiname:
    kind: int
    name: int = 0
    ns: int = 0
    ns_set: int = 0
    type_def: int = 0
    params: list[int] = field(default_factory=list)


@dataclass
class Trait:
    name: int
    kind: int
    attrs: int
    slot_id: int = 0
    type_name: int = 0
    method: int = -1
    class_index: int = -1

    @property
    def kind_name(self) -> str:
        return TRAIT_KINDS[self.kind]


@dataclass
class Instance:
    name: int
    super_name: int
    flags: int
    protected_ns: int
    interfaces: list[int]
    iinit: int
    traits: list[Trait]


@dataclass
class ClassInfo:
    cinit: int
    traits: list[Trait]


@dataclass
class Script:
    init: int
    traits: list[Trait]


@dataclass
class Abc:
    minor: int
    major: int
    strings: list[str | None]
    namespaces: list[tuple[int, int]]
    ns_sets: list[list[int]]
    multinames: list[Multiname | None]
    method_names: list[int]
    method_count: int
    instances: list[Instance]
    classes: list[ClassInfo]
    scripts: list[Script]
    body_methods: list[int]

    def string(self, index: int) -> str | None:
        return self.strings[index] if 0 < index < len(self.strings) else None

    def ns_name(self, index: int) -> str | None:
        if index <= 0 or index >= len(self.namespaces):
            return None
        return self.string(self.namespaces[index][1])

    def ns_kind(self, index: int) -> int:
        return self.namespaces[index][0] if 0 < index < len(self.namespaces) else 0

    def is_private(self, mn_index: int) -> bool:
        mn = self.multinames[mn_index] if 0 < mn_index < len(self.multinames) else None
        return mn is not None and mn.kind in (QNAME, QNAME_A) and self.ns_kind(mn.ns) == 0x05

    def mn_name(self, index: int) -> str | None:
        mn = self.multinames[index] if 0 < index < len(self.multinames) else None
        if mn is None or mn.kind == TYPENAME:
            return None
        return self.string(mn.name)

    def qname(self, index: int) -> str | None:
        mn = self.multinames[index] if 0 < index < len(self.multinames) else None
        if mn is None:
            return None
        local = self.string(mn.name)
        if mn.kind in (QNAME, QNAME_A):
            if self.ns_kind(mn.ns) not in (0x16, 0x17):
                return local
            pkg = self.ns_name(mn.ns)
            return f"{pkg}.{local}" if pkg else local
        return local


def _read_traits(s: _Stream) -> list[Trait]:
    traits = []
    for _ in range(s.u30()):
        name = s.u30()
        kind_byte = s.u8()
        kind, attrs = kind_byte & 0x0F, kind_byte >> 4
        t = Trait(name, kind, attrs)
        if kind in (0, 6):
            t.slot_id, t.type_name = s.u30(), s.u30()
            vindex = s.u30()
            if vindex:
                s.u8()
        elif kind == 4:
            t.slot_id, t.class_index = s.u30(), s.u30()
        elif kind == 5:
            t.slot_id, t.method = s.u30(), s.u30()
        elif kind in (1, 2, 3):
            s.u30()
            t.method = s.u30()
        else:
            raise AbcError(f"bad trait kind {kind}")
        if attrs & 0x4:
            for _ in range(s.u30()):
                s.u30()
        traits.append(t)
    return traits


def parse_abc(data: bytes) -> Abc:
    s = _Stream(data)
    minor, major = s.u16(), s.u16()

    n = s.u30()
    for _ in range(max(n - 1, 0)):
        s.u30()
    n = s.u30()
    for _ in range(max(n - 1, 0)):
        s.u30()
    n = s.u30()
    for _ in range(max(n - 1, 0)):
        s.d64()

    strings: list[str | None] = [None]
    for _ in range(max(s.u30() - 1, 0)):
        raw = s.bytes(s.u30())
        strings.append(raw.decode("utf-8", errors="surrogateescape"))

    namespaces = [(0, 0)]
    for _ in range(max(s.u30() - 1, 0)):
        namespaces.append((s.u8(), s.u30()))

    ns_sets: list[list[int]] = [[]]
    for _ in range(max(s.u30() - 1, 0)):
        ns_sets.append([s.u30() for _ in range(s.u30())])

    multinames: list[Multiname | None] = [None]
    for _ in range(max(s.u30() - 1, 0)):
        kind = s.u8()
        if kind in (QNAME, QNAME_A):
            ns = s.u30()
            multinames.append(Multiname(kind, name=s.u30(), ns=ns))
        elif kind in (RTQNAME, RTQNAME_A):
            multinames.append(Multiname(kind, name=s.u30()))
        elif kind in (RTQNAME_L, RTQNAME_LA):
            multinames.append(Multiname(kind))
        elif kind in (MULTINAME, MULTINAME_A):
            name = s.u30()
            multinames.append(Multiname(kind, name=name, ns_set=s.u30()))
        elif kind in (MULTINAME_L, MULTINAME_LA):
            multinames.append(Multiname(kind, ns_set=s.u30()))
        elif kind == TYPENAME:
            base = s.u30()
            multinames.append(Multiname(kind, type_def=base, params=[s.u30() for _ in range(s.u30())]))
        else:
            raise AbcError(f"bad multiname kind 0x{kind:02x} at {s.pos}")

    method_names = []
    method_count = s.u30()
    for _ in range(method_count):
        param_count = s.u30()
        s.u30()
        for _ in range(param_count):
            s.u30()
        method_names.append(s.u30())
        flags = s.u8()
        if flags & 0x08:
            for _ in range(s.u30()):
                s.u30()
                s.u8()
        if flags & 0x80:
            for _ in range(param_count):
                s.u30()

    for _ in range(s.u30()):
        s.u30()
        items = s.u30()
        for _ in range(2 * items):
            s.u30()

    class_count = s.u30()
    instances = []
    for _ in range(class_count):
        name, super_name, flags = s.u30(), s.u30(), s.u8()
        protected_ns = s.u30() if flags & 0x08 else 0
        interfaces = [s.u30() for _ in range(s.u30())]
        iinit = s.u30()
        instances.append(Instance(name, super_name, flags, protected_ns, interfaces, iinit, _read_traits(s)))
    classes = []
    for _ in range(class_count):
        cinit = s.u30()
        classes.append(ClassInfo(cinit, _read_traits(s)))
    scripts = []
    for _ in range(s.u30()):
        init = s.u30()
        scripts.append(Script(init, _read_traits(s)))

    body_methods = []
    for _ in range(s.u30()):
        body_methods.append(s.u30())
        s.u30(), s.u30(), s.u30(), s.u30()
        code_length = s.u30()
        s.pos += code_length
        for _ in range(s.u30()):
            s.u30(), s.u30(), s.u30(), s.u30(), s.u30()
        _read_traits(s)
    if s.pos != len(data):
        raise AbcError(f"trailing data: parsed {s.pos} of {len(data)} bytes")

    return Abc(minor, major, strings, namespaces, ns_sets, multinames, method_names,
               method_count, instances, classes, scripts, body_methods)


def swf_abc_blocks(swf: bytes) -> list[tuple[str, bytes]]:
    blocks = []
    for code, payload in swf_tags(swf):
        if code == 82:
            end = payload.index(b"\0", 4)
            blocks.append((payload[4:end].decode("utf-8"), payload[end + 1:]))
        elif code == 72:
            blocks.append(("", payload))
    return blocks
