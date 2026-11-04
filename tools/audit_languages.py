import hashlib
import json
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]


def decode(data: bytes, limit: int = 16 * 1024 * 1024) -> tuple[int, bytes, dict[str, str], int]:
    if len(data) < 4:
        raise ValueError("Truncated language header")
    stream = zlib.decompressobj()
    payload = stream.decompress(data[4:], limit + 1)
    if len(payload) > limit or stream.unconsumed_tail:
        raise ValueError("Language payload exceeds limit")
    if not stream.eof or stream.unused_data:
        raise ValueError("Incomplete or trailing language compressed data")
    if len(payload) < 4:
        raise ValueError("Truncated language count")
    count = struct.unpack_from(">i", payload)[0]
    if count < 0 or count > (len(payload) - 4) // 4:
        raise ValueError("Invalid language row count")
    offset = 4

    def utf() -> str:
        nonlocal offset
        if offset + 2 > len(payload):
            raise ValueError("Truncated language string length")
        size = struct.unpack_from(">H", payload, offset)[0]
        offset += 2
        if size > len(payload) - offset:
            raise ValueError("Truncated language string")
        value = payload[offset:offset + size].decode("utf-8-sig")
        offset += size
        return value

    rows = {}
    for _ in range(count):
        key, value = utf(), utf()
        rows[key] = value
    if offset != len(payload):
        raise ValueError("Trailing language payload data")
    return struct.unpack_from("<I", data)[0], payload, rows, count


def canonical(rows: dict[str, str]) -> bytes:
    result = bytearray()
    for key in sorted(rows):
        for value in (key, rows[key]):
            encoded = value.encode("utf-8")
            result.extend(struct.pack(">H", len(encoded)))
            result.extend(encoded)
    return bytes(result)


def audit() -> dict:
    inventory = json.loads((ROOT / "reports/10.10/inventory.json").read_text(encoding="utf-8"))
    indexed = {row["path"]: row for row in inventory["files"]}
    result = []
    for language_id in range(1, 14):
        path = f"languages/language.{language_id}.bin"
        data = (ROOT / "versions/10.10" / path).read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        if digest != indexed[path]["sha256"] or len(data) != indexed[path]["size"]:
            raise ValueError(f"Input differs from preserved inventory: {path}")
        header, payload, rows, count = decode(data)
        result.append({"id": language_id, "path": path, "sha256": digest,
                       "header": header, "payload_bytes": len(payload), "row_count": count,
                       "unique_keys": len(rows), "canonical_sha256": hashlib.sha256(canonical(rows)).hexdigest()})
    return {"schema_version": 1, "version": "10.10", "source": "X3c.k4g/o5U",
            "note": "Header is retained, not enforced by the original loader. Canonical bytes sort keys and encode big-endian UTF lengths. Strict bounds and complete-consumption checks are authored.",
            "languages": result}


if __name__ == "__main__":
    report = audit()
    (ROOT / "reports/10.10/languages-audit.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Validated {len(report['languages'])} language containers against preserved hashes")
