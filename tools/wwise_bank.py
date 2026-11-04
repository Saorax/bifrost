from __future__ import annotations

import struct
from dataclasses import dataclass, field

SOUND, ACTION, EVENT = 2, 3, 4
CONTAINERS = {5, 6, 9}


def fnv(name: str) -> int:
    h = 2166136261
    for b in name.lower().encode("utf-8"):
        h = (h * 16777619) & 0xFFFFFFFF
        h ^= b
    return h


@dataclass
class Bank:
    sections: list = field(default_factory=list)
    objects: dict = field(default_factory=dict)
    order: list = field(default_factory=list)
    media: dict = field(default_factory=dict)

    @property
    def version(self) -> int:
        return struct.unpack_from("<I", dict(self.sections)["BKHD"], 0)[0]


def read_bank(data: bytes) -> Bank:
    bank, pos = Bank(), 0
    while pos + 8 <= len(data):
        tag, size = data[pos:pos + 4].decode("latin1"), struct.unpack_from("<I", data, pos + 4)[0]
        bank.sections.append((tag, data[pos + 8:pos + 8 + size]))
        pos += 8 + size
    sec = dict(bank.sections)
    if "DIDX" in sec:
        didx, blob = sec["DIDX"], sec.get("DATA", b"")
        for i in range(len(didx) // 12):
            mid, off, size = struct.unpack_from("<III", didx, 12 * i)
            bank.media[mid] = blob[off:off + size]
    if "HIRC" in sec:
        h = sec["HIRC"]
        count, p = struct.unpack_from("<I", h, 0)[0], 4
        for _ in range(count):
            kind, size = h[p], struct.unpack_from("<I", h, p + 1)[0]
            body = h[p + 5:p + 5 + size]
            oid = struct.unpack_from("<I", body, 0)[0]
            bank.objects[oid] = (kind, body)
            bank.order.append(oid)
            p += 5 + size
    return bank


def event_actions(body: bytes) -> list[int]:
    n = body[4]
    return [struct.unpack_from("<I", body, 5 + 4 * i)[0] for i in range(n)]


def action_target(body: bytes) -> int:
    return struct.unpack_from("<I", body, 6)[0]


def sound_media(body: bytes) -> int:
    return struct.unpack_from("<I", body, 9)[0]


def children(bank: Bank, oid: int) -> list[int]:
    kind, body = bank.objects[oid]
    out = []
    for i in range(4, len(body) - 3):
        cid = struct.unpack_from("<I", body, i)[0]
        if cid != oid and cid in bank.objects and bank.objects[cid][0] in {SOUND} | CONTAINERS:
            if struct.pack("<I", oid) in bank.objects[cid][1][4:] and cid not in out:
                out.append(cid)
    return out


def leads_to(bank: Bank, oid: int, changed: set[int], seen: set | None = None) -> set[int]:
    seen = seen if seen is not None else set()
    if oid in seen or oid not in bank.objects:
        return set()
    seen.add(oid)
    kind, body = bank.objects[oid]
    if kind == SOUND:
        return {oid} if sound_media(body) in changed else set()
    if kind in CONTAINERS:
        below = set()
        for c in children(bank, oid):
            below |= leads_to(bank, c, changed, seen)
        return below | {oid} if below else set()
    return set()


def changed_media(game: Bank, mod: Bank) -> set[int]:
    return {m for m, data in mod.media.items() if m in game.media and game.media[m] != data}


def events_to_changed(game: Bank, mod: Bank) -> dict[int, set[int]]:
    changed = changed_media(game, mod)
    out = {}
    for oid, (kind, body) in game.objects.items():
        if kind != EVENT:
            continue
        path = set()
        for aid in event_actions(body):
            if aid in game.objects and game.objects[aid][0] == ACTION:
                path |= leads_to(game, action_target(game.objects[aid][1]), changed)
        if path:
            out[oid] = path
    return out


def _replace_ids(body: bytes, mapping: dict[int, int]) -> bytes:
    b = bytearray(body)
    for old, new in mapping.items():
        o, n = struct.pack("<I", old), struct.pack("<I", new)
        start = 0
        while (i := b.find(o, start)) >= 0:
            b[i:i + 4] = n
            start = i + 4
    return bytes(b)


def build(bank_name: str, pieces: list[tuple[Bank, Bank, dict[str, str]]]) -> tuple[bytes, list[str]]:
    objects: list[tuple[int, bytes]] = []
    media: dict[int, bytes] = {}
    made: list[str] = []
    header = None
    for game, mod, names in pieces:
        header = header or dict(game.sections)["BKHD"]
        paths = events_to_changed(game, mod)
        for old_name, new_name in names.items():
            eid = fnv(old_name)
            if eid not in paths:
                continue
            new_eid = fnv(new_name)
            mapping = {eid: new_eid}
            for oid in paths[eid]:
                mapping[oid] = fnv(f"{new_name}#{oid}")
            ev_body = game.objects[eid][1]
            for aid in event_actions(ev_body):
                mapping[aid] = fnv(f"{new_name}#action#{aid}")
            for oid in sorted(paths[eid], key=lambda o: game.order.index(o)):
                kind, body = game.objects[oid]
                if kind == SOUND:
                    mid = sound_media(body)
                    new_mid = fnv(f"{new_name}#media#{mid}")
                    media[new_mid] = mod.media[mid]
                    b = bytearray(_replace_ids(body, mapping))
                    struct.pack_into("<I", b, 9, new_mid)
                    struct.pack_into("<I", b, 13, len(mod.media[mid]))
                    objects.append((kind, bytes(b)))
                else:
                    objects.append((kind, _replace_ids(body, mapping)))
            for aid in event_actions(ev_body):
                if aid in game.objects:
                    objects.append((ACTION, _replace_ids(game.objects[aid][1], mapping)))
            objects.append((EVENT, _replace_ids(ev_body, mapping)))
            made.append(new_name)
    if header is None:
        raise ValueError("no banks")
    bkhd = bytearray(header)
    struct.pack_into("<I", bkhd, 4, fnv(bank_name))
    struct.pack_into("<I", bkhd, 8, 0)
    didx, blob = b"", b""
    for mid in sorted(media):
        while len(blob) % 16:
            blob += b"\0"
        didx += struct.pack("<III", mid, len(blob), len(media[mid]))
        blob += media[mid]
    hirc = struct.pack("<I", len(objects)) + b"".join(bytes([k]) + struct.pack("<I", len(b)) + b for k, b in objects)
    out = b"BKHD" + struct.pack("<I", len(bkhd)) + bytes(bkhd)
    if media:
        out += b"DIDX" + struct.pack("<I", len(didx)) + didx + b"DATA" + struct.pack("<I", len(blob)) + blob
    out += b"HIRC" + struct.pack("<I", len(hirc)) + hirc
    return out, made
