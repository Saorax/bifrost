"""preview what content mods do to the game's data tables, without starting the game.

    python tools/preview_content_mod.py examples/mods/sample-tables [more mod folders] \
        [--tables build/tabledata]

mirrors the table rules of bh.platform.ContentMods on the tables from tools/extract_client_data.mjs and prints one
line per row in the words of Documents\\Bifrost\\bh-mods.txt; exit 1 if a manifest or row is invalid.
"""

from __future__ import annotations

import argparse
import copy
import csv
import io
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ID = re.compile(r"^[a-z0-9._-]+$")


class ModError(Exception):
    pass


def load_manifest(folder: Path) -> dict:
    path = folder / "mod.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError) as e:
        raise ModError(f"{folder.name}: {e}") from e
    for field in ("id", "name", "version"):
        if not isinstance(data.get(field), str) or not data[field]:
            raise ModError(f"{folder.name}: \"{field}\" is missing or not a string")
    if not ID.match(data["id"]):
        raise ModError(f"{folder.name}: id {data['id']!r} may only use a-z, 0-9, '.', '_' and '-'")
    files = data.get("files") or []
    if not isinstance(files, list) or not all(isinstance(f, str) and re.fullmatch(r"[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*", f)
                                              and ".." not in f for f in files):
        raise ModError(f"{folder.name}: \"files\" must be a list of plain paths inside the mod folder")
    tables = data.get("tables") or {}
    def row_ok(r) -> bool:
        return isinstance(r, str) or (isinstance(r, dict) and isinstance(r.get("add"), str)) or (
            isinstance(r, dict) and isinstance(r.get("set"), dict)
                                      and isinstance(r.get("copy", ""), str))
    if not isinstance(tables, dict) or not all(isinstance(v, list) and all(row_ok(r) for r in v)
                                               for v in tables.values()):
        raise ModError(f"{folder.name}: \"tables\" must map table names to lists of rows "
                       "(XML text, CSV lines or {\"copy\": ..., \"set\": {...}})")
    return {"id": data["id"], "requires": list(data.get("requires") or []), "tables": tables, "files": files,
            "folder": folder}


def order(mods: list[dict]) -> list[dict]:
    pending = sorted(mods, key=lambda m: m["id"])
    known = {m["id"] for m in pending}
    placed, out = set(), []
    progress = True
    while pending and progress:
        progress = False
        for i, mod in enumerate(pending):
            missing = next((r for r in mod["requires"] if r not in known), None)
            if missing:
                print(f"skipped {mod['id']}: requires {missing}, which is missing or skipped")
                known.discard(mod["id"])
                del pending[i]
                progress = True
                break
            if all(r in placed for r in mod["requires"]):
                placed.add(mod["id"])
                out.append(mod)
                del pending[i]
                progress = True
                break
    for mod in pending:
        print(f"skipped {mod['id']}: its requirements form a cycle ({', '.join(mod['requires'])})")
    return out


def key_attributes(row: ET.Element) -> list[str]:
    named = [a for a in row.attrib if a.endswith("Name")]
    return named if len(named) == 1 else sorted(row.attrib)


def key_text(row: ET.Element) -> str:
    return ",".join(row.get(a, "") for a in key_attributes(row))


def row_key(row: ET.Element) -> str:
    if not row.attrib and len(row):
        return f"{row.tag}[{row[0].tag}={(row[0].text or '').strip()}]"
    return f"{row.tag}[{key_text(row)}]"


GROUP_INDEX = {"CostumeIndex": "OwnerHero"}
NOT_IDS = {"SteamAppID", "AppID"}


def is_id_column(name: str, values: list[str]) -> bool:
    return (len(name) > 2 and name.endswith("ID") and name not in NOT_IDS and bool(values)
            and all(re.fullmatch(r"\s*-?\d+\s*", v) for v in values) and len(set(values)) == len(values))


def xml_id_tags(root: ET.Element) -> dict[str, bool]:
    values: dict[str, list[str]] = {}
    rows = [r for r in root if key_text(r) != "Template"]
    for r in rows:
        for c in r:
            if (c.text or "").strip():
                values.setdefault(c.tag, []).append(c.text.strip())
    return {t: len(v) >= 0.9 * len(rows) for t, v in values.items() if is_id_column(t, v)}


def enforce_xml_ids(row: ET.Element, is_new: bool, id_tags: dict[str, bool], table: str, key: str, mod_id: str) -> list[str]:
    lines, have = [], set()
    for c in list(row):
        if c.tag not in id_tags:
            continue
        have.add(c.tag)
        t = (c.text or "").strip()
        if is_new and t != "@id":
            if t and not t.startswith("@id/"):
                lines.append(f"id {table}/{c.tag} {t} for {key} ignored: IDs are assigned ({mod_id})")
            c.text = "@id"
        elif not is_new:
            lines.append(f"id {table}/{c.tag} of {key} kept: a game row's ID can't change ({mod_id})")
            row.remove(c)
    if is_new:
        for t in sorted(t for t, always in id_tags.items() if always and t not in have):
            ET.SubElement(row, t).text = "@id"
    return lines


def group_value(row: ET.Element, spec: str) -> str:
    if spec.startswith("@"):
        return row.get(spec[1:], "")
    child = row.find(spec)
    return (child.text or "") if child is not None else ""


def max_field(root: ET.Element, field: str, group: str | None = None, value: str | None = None) -> int:
    values = [int(c.text) for r in root if group is None or group_value(r, group) == value
              for c in r if c.tag == field and c.text and re.fullmatch(r"\s*-?\d+\s*", c.text)]
    return max([0] + values)


def common_fields(root: ET.Element, tag: str, share: float = 0.8) -> set[str]:
    rows = [r for r in root if r.tag == tag and "Template" not in r.attrib.values()]
    counts: dict[str, int] = {}
    for r in rows:
        for name in {c.tag for c in r}:
            counts[name] = counts.get(name, 0) + 1
    return {n for n, k in counts.items() if rows and k >= share * len(rows)}


def copy_row(root: ET.Element, spec: dict, mod_id: str, table: str) -> ET.Element:
    if not spec.get("copy"):
        raise ModError(f"{mod_id} {table}: an object row needs \"copy\" in an XML table")
    source = next((r for r in root if key_text(r) == spec["copy"]), None)
    if source is None:
        raise ModError(f"{mod_id} {table}: no row {spec['copy']} to copy")
    row = copy.deepcopy(source)
    for name, value in spec["set"].items():
        if name.startswith("@"):
            row.set(name[1:], str(value))
            continue
        for old in [c for c in row if c.tag == name]:
            row.remove(old)
        ET.SubElement(row, name).text = str(value)
    return row


def set_stance(root: ET.Element, spec: dict, mod_id: str, table: str) -> str:
    label = f"{table}/{spec['stance']} stance {spec.get('index')}"
    hero = None
    for r in root:
        if r.find("HeroName") is not None:
            hero = (r.find("HeroName").text or "")
        index = r.find("RuneIndex")
        if hero != spec["stance"] or index is None or (index.text or "") != str(spec.get("index")):
            continue
        for name in spec["set"]:
            if not re.fullmatch(r"[A-Za-z]\w*", name) or name in ("HeroName", "RuneIndex"):
                return f"row skipped {mod_id} {label}: can't set {name}"
        for name, value in spec["set"].items():
            for old in r.findall(name):
                r.remove(old)
            ET.SubElement(r, name).text = str(value)
        return f"row changed {label} ({mod_id})"
    return f"row skipped {mod_id} {label}: no such stance"


def apply(table: str, root: ET.Element, mods: list[dict]) -> list[str]:
    lines, next_ids, touched = [], {}, {}
    id_tags = xml_id_tags(root)
    for mod in mods:
        for text in mod["tables"].get(table, []):
            if isinstance(text, dict) and isinstance(text.get("stance"), str):
                lines.append(set_stance(root, text, mod["id"], table))
                continue
            if isinstance(text, dict) and "add" in text:
                row = ET.fromstring(text["add"])
                root.append(row)
                lines.append(f"row added {table}/{row_key(row)} ({mod['id']}, added as is)")
                continue
            if isinstance(text, dict):
                row = copy_row(root, text, mod["id"], table)
            else:
                try:
                    row = ET.fromstring(text)
                except ET.ParseError as e:
                    raise ModError(f"{mod['id']} {table}: row is not valid XML ({e})") from e
            key = row_key(row)
            keys = key_attributes(row)
            existing = None if not keys else next(
                (c for c in root if c.tag == row.tag and all(c.get(a) == row.get(a) for a in keys)), None)
            if keys:
                lines += enforce_xml_ids(row, existing is None, id_tags, table, key, mod["id"])
            for field in row:
                if (field.text or "") == "@id":
                    if field.tag not in next_ids:
                        next_ids[field.tag] = max_field(root, field.tag) + 1
                    field.text = str(next_ids[field.tag])
                    next_ids[field.tag] += 1
                    lines.append(f"id {table}/{field.tag} = {field.text} for {key} ({mod['id']})")
                elif (field.text or "").startswith("@id/"):
                    spec = field.text[4:]
                    value = group_value(row, spec)
                    k = f"{field.tag}/{spec}={value}"
                    if k not in next_ids:
                        next_ids[k] = max_field(root, field.tag, spec, value) + 1
                    field.text = str(next_ids[k])
                    next_ids[k] += 1
                    lines.append(f"id {table}/{field.tag} = {field.text} for {key} (next free for {spec} {value}, {mod['id']})")
            append_only = len(row) > 0 and all((f.text or "").startswith("+") for f in row) and not row.attrib.keys() - set(keys)
            if keys and not append_only:
                if key in touched:
                    lines.append(f"conflict row {table}/{key}: {touched[key]} is overridden by {mod['id']}")
                touched[key] = mod["id"]
            if existing is None:
                for field in row:
                    if (field.text or "").startswith("+"):
                        field.text = field.text[1:]
                missing = common_fields(root, row.tag) - {c.tag for c in row}
                if missing:
                    lines.append(f"warning {table}/{key}: most {row.tag} rows have {', '.join(sorted(missing))}, "
                                 "this one doesn't (the game's table checks throw, and one bad row stops the whole "
                                 "archive from loading)")
                root.append(row)
                lines.append(f"row added {table}/{key} ({mod['id']})")
            else:
                existing.attrib.update(row.attrib)
                for field in list(row):
                    previous = None
                    for old in [c for c in existing if c.tag == field.tag]:
                        previous = old.text or ""
                        existing.remove(old)
                    if (field.text or "").startswith("+"):
                        field.text = f"{previous},{field.text[1:]}" if previous else field.text[1:]
                    existing.append(field)
                lines.append(f"row changed {table}/{key} ({mod['id']})")
    return lines


def split_csv(line: str) -> list[str]:
    return next(csv.reader([line]), [""])


def join_csv(fields: list[str]) -> str:
    return ",".join(f'"{f.replace(chr(34), chr(34) * 2)}"' if re.search(r'[",\n\r]', f) else f for f in fields)


def apply_csv(table: str, text: str, mods: list[dict]) -> tuple[str, list[str]]:
    first, _, rest = text.partition("\n")
    lines = rest.split("\n")
    strip = lambda s: s[:-1] if s.endswith("\r") else s
    cell = lambda r, c: r[c] if r and c < len(r) else ""
    header = split_csv(strip(lines[0]))
    column = {n: i for i, n in enumerate(header)}
    by_key = {split_csv(strip(l))[0]: i for i, l in enumerate(lines) if i > 0 and strip(l)}
    game_rows = [c for l in lines[1:] if (c := split_csv(strip(l))) and len(c) > 1 and c[0] not in ("", "Template")]
    filled = {i: [r[i] for r in game_rows if i < len(r) and r[i]] for i in range(len(header))}
    id_cols = {i for i, n in enumerate(header) if is_id_column(n, filled[i])}
    always = {i for i in id_cols if len(filled[i]) >= 0.9 * len(game_rows)}
    out_lines, next_ids, touched = [], {}, {}

    def max_field(c: int, g: int | None = None, gv: str | None = None) -> int:
        vals = [int(cells[c]) for l in lines[1:] if (cells := split_csv(strip(l))) and c < len(cells)
                and (g is None or (g < len(cells) and cells[g] == gv)) and re.fullmatch(r"\s*-?\d+\s*", cells[c])]
        return max([0] + vals)

    def insert(line: str) -> int:
        at = len(lines)
        while at > 1 and not strip(lines[at - 1]):
            at -= 1
        lines.insert(at, line)
        return at

    for mod in mods:
        for row in mod["tables"].get(table, []):
            base = None
            if isinstance(row, dict) and "add" in row:
                insert(row["add"])
                out_lines.append(f"row added {table}: {','.join(split_csv(row['add'])[:2])} ({mod['id']})")
                continue
            if isinstance(row, str):
                fields = split_csv(row)
            else:
                if row.get("copy"):
                    if row["copy"] not in by_key:
                        out_lines.append(f"row skipped {mod['id']} {table}: no row {row['copy']} to copy")
                        continue
                    base = split_csv(strip(lines[by_key[row["copy"]]]))
                unknown = [n for n in row["set"] if n not in column]
                if unknown:
                    raise ModError(f"{mod['id']} {table}: no column {unknown[0]}")
                fields = [""] * len(header)
                for n, v in row["set"].items():
                    fields[column[n]] = str(v)
            fields = (fields + [""] * len(header))[:len(header)]
            key = fields[0] or (base[0] if base else "")
            if not key:
                raise ModError(f"{mod['id']} {table}: a row has no value in the first column ({header[0]})")
            is_new = key not in by_key
            for c in id_cols:
                effective = fields[c] or cell(base, c)
                if is_new and effective == "@none" and c not in always:
                    continue
                if is_new and not effective and c not in always:
                    continue
                if is_new and fields[c] != "@id":
                    if fields[c] and not fields[c].startswith("@id/"):
                        out_lines.append(f"id {table}/{header[c]} {fields[c]} for {key} ignored: IDs are assigned ({mod['id']})")
                    fields[c] = "@id"
                elif not is_new and fields[c]:
                    out_lines.append(f"id {table}/{header[c]} of {key} kept: a game row's ID can't change ({mod['id']})")
                    fields[c] = ""
            for col, grp in GROUP_INDEX.items():
                ci, gi = column.get(col), column.get(grp)
                if not is_new or ci is None or gi is None:
                    continue
                want = fields[ci] or cell(base, ci)
                owner = fields[gi] or cell(base, gi)
                if want.startswith("@id"):
                    continue
                taken = any(len(r) > max(ci, gi) and r[gi] == owner and r[ci] == want
                            for r in (split_csv(strip(l)) for l in lines[1:]))
                if not want or taken:
                    if want:
                        out_lines.append(f"id {table}/{col} {want} for {key} is taken for {owner}: the next free one is used ({mod['id']})")
                    fields[ci] = "@id/" + grp
            for c, v in enumerate(fields):
                if v == "@id":
                    next_ids.setdefault(c, max_field(c) + 1)
                    fields[c] = str(next_ids[c])
                    next_ids[c] += 1
                    out_lines.append(f"id {table}/{header[c]} = {fields[c]} for {key} ({mod['id']})")
                elif v.startswith("@id/"):
                    g = column.get(v[4:])
                    gv = "" if g is None else (fields[g] or cell(base, g))
                    k = (c, gv)
                    next_ids.setdefault(k, max_field(c, g, gv) + 1)
                    fields[c] = str(next_ids[k])
                    next_ids[k] += 1
                    what = "the whole table" if g is None else f"{header[g]} {gv}"
                    out_lines.append(f"id {table}/{header[c]} = {fields[c]} for {key} (next free for {what}, {mod['id']})")
            if key in touched:
                out_lines.append(f"conflict row {table}/{key}: {touched[key]} is overridden by {mod['id']}")
            touched[key] = mod["id"]
            existing = split_csv(strip(lines[by_key[key]])) if key in by_key else base
            merged = [fields[c] or cell(existing, c) for c in range(len(header))]
            merged = ["" if v == "@none" else v for v in merged]
            merged[0] = key
            if key in by_key:
                lines[by_key[key]] = join_csv(merged)
                out_lines.append(f"row changed {table}/{key} ({mod['id']})")
            else:
                by_key[key] = insert(join_csv(merged))
                copied = f" (copy of {base[0]})" if base else ""
                out_lines.append(f"row added {table}/{key}{copied} ({mod['id']})")
    return first + "\n" + "\n".join(lines), out_lines


KEEP_FIELDS = {"WeaponSet"}


def game_names(tables: Path, table_names: set[str]) -> dict[str, dict]:
    out = {}
    for table in table_names:
        found = sorted(tables.rglob(f"{table}.xml")) + sorted(tables.rglob(f"{table}.csv"))
        if len(found) != 1:
            continue
        if found[0].suffix == ".csv":
            text = found[0].read_text(encoding="utf-8").split("\n", 1)[1]
            rows = list(csv.reader(io.StringIO(text)))
            out[table] = {"kind": "csv", "field": rows[0][0], "names": {r[0] for r in rows[1:] if r and r[0]}}
        else:
            root = ET.parse(found[0]).getroot()
            keyed = [r for r in root if r.attrib]
            field = key_attributes(keyed[0])[0] if keyed and len(key_attributes(keyed[0])) == 1 else None
            out[table] = {"kind": "xml", "field": field, "names": {key_text(r) for r in keyed}}
    return out


def row_name(row, info: dict) -> str | None:
    if isinstance(row, dict) and "add" in row:
        return None
    if isinstance(row, dict):
        if info["kind"] == "xml":
            return row["set"].get("@" + info["field"], row.get("copy")) if info["field"] else None
        return row["set"].get(info["field"], row.get("copy"))
    if info["kind"] == "csv":
        return split_csv(row)[0]
    try:
        r = ET.fromstring(row)
    except ET.ParseError:
        return None
    return key_text(r) if r.attrib else None


def swap_token(value: str, renames: dict[str, str]) -> str:
    if value in renames:
        return renames[value]
    if "," not in value and not value.startswith("+"):
        return value
    parts = []
    for part in value.split(","):
        core = part.strip()
        plus = core.startswith("+")
        core = core[1:] if plus else core
        parts.append(part.replace(core, renames[core]) if core in renames else part)
    return ",".join(parts)


def rename_in_row(row, renames: dict[str, str], kind: str):
    if isinstance(row, dict) and "add" in row:
        return row
    if isinstance(row, dict):
        return dict(row, set={k: (v if k in KEEP_FIELDS else swap_token(str(v), renames)) for k, v in row["set"].items()})
    if kind == "csv":
        return join_csv([swap_token(c, renames) for c in split_csv(row)])
    try:
        r = ET.fromstring(row)
    except ET.ParseError:
        return row
    for el in r.iter():
        for a, v in el.attrib.items():
            el.set(a, swap_token(v, renames))
        if el.tag not in KEEP_FIELDS and len(el) == 0 and el.text:
            el.text = swap_token(el.text, renames)
    return ET.tostring(r, encoding="unicode")


def resolve_duplicate_names(mods: list[dict], names: dict[str, dict]) -> list[str]:
    lines, added = [], {}
    for mod in mods:
        renames: dict[str, str] = {}
        for table, rows in mod["tables"].items():
            info = names.get(table)
            if not info:
                continue
            for row in rows:
                name = row_name(row, info)
                if not name or name in info["names"]:
                    continue
                if (table, name) in added and added[(table, name)] != mod["id"]:
                    new = re.sub(r"[^A-Za-z0-9_]", "_", mod["id"]) + "_" + name
                    renames[name] = new
                    lines.append(f"renamed {table}/{name} to {new} in {mod['id']}: {added[(table, name)]} added that name first")
                else:
                    added[(table, name)] = mod["id"]
        if renames:
            mod["tables"] = {t: [rename_in_row(r, renames, (names.get(t) or {}).get("kind", "xml")) for r in rows]
                             for t, rows in mod["tables"].items()}
            mod["file_renames"] = renames
            for table, rows in mod["tables"].items():
                info = names.get(table)
                for row in rows:
                    n = row_name(row, info) if info else None
                    if n and info and n not in info["names"]:
                        added.setdefault((table, n), mod["id"])
    return lines


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("mods", nargs="+", type=Path, help="mod folders (each with a mod.json)")
    p.add_argument("--tables", type=Path, default=ROOT / "build" / "tabledata",
                   help="extracted tables (tools/extract_client_data.mjs output)")
    args = p.parse_args(argv)
    try:
        mods = order([load_manifest(m) for m in args.mods])
        for line in resolve_duplicate_names(mods, game_names(args.tables, {t for m in mods for t in m["tables"]})):
            print(line)
        for table in sorted({t for m in mods for t in m["tables"]}):
            found = sorted(args.tables.rglob(f"{table}.xml")) + sorted(args.tables.rglob(f"{table}.csv"))
            if len(found) != 1:
                raise ModError(f"table {table}: {len(found)} files named {table}.xml or .csv under {args.tables}")
            if found[0].suffix == ".csv":
                _, lines = apply_csv(table, found[0].read_text(encoding="utf-8"), mods)
            else:
                lines = apply(table, ET.parse(found[0]).getroot(), mods)
            for line in lines:
                print(line)
        for mod in mods:
            for path in mod["files"]:
                try:
                    root = ET.parse(mod["folder"] / path).getroot()
                except (OSError, ET.ParseError) as e:
                    raise ModError(f"{mod['id']}: file {path}: {e}") from e
                for a, v in root.attrib.items():
                    root.set(a, swap_token(v, mod.get("file_renames", {})))
                print(f"file {mod['id']}/{path}: {root.tag} {' '.join(f'{k}={v}' for k, v in root.attrib.items())}")
                if root.tag == "LevelDesc" and root.find("Background") is None:
                    print(f"file {mod['id']}/{path}: no Background, which the game needs (the loader adds a default)")
                if root.tag == "LevelDesc" and root.find("NavNode") is None:
                    print(f"file {mod['id']}/{path}: warning: no NavNode (bot navigation); a match with bots will crash")
    except ModError as e:
        print(f"preview FAILED: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
