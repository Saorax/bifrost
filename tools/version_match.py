from __future__ import annotations

from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re

OBF = re.compile(r"_-[A-Za-z0-9$]+")
ALGORITHM = 8


def key_parts(key: str) -> tuple[str, str, str, str] | None:
    m = re.fullmatch(r"([^/]+)/([is])/(method|getter|setter) (.+?)(?:#\d+)?\+*", key)
    return (m.group(1), m.group(2), m.group(3), m.group(4)) if m else None


def body_text(body: dict, translate=None, pattern: re.Pattern = OBF) -> str:
    lines = [str(body["sig"])] + list(body["code"] or []) + [str(body["exceptions"])]
    text = "\n".join(lines)
    if translate is None:
        return pattern.sub("§", text)
    return pattern.sub(lambda m: translate.get(m.group(0), "§"), text)


def fingerprint(body: dict, pattern: re.Pattern = OBF) -> str:
    return hashlib.sha1(body_text(body, pattern=pattern).encode("utf-8", "surrogateescape")).hexdigest()


def fresh_pattern(src: dict[str, dict], dst: dict[str, dict]) -> re.Pattern:
    real_src = {p[0] for k in src if (p := key_parts(k))}
    fresh = sorted({p[0] for k in dst if (p := key_parts(k)) and not OBF.search(p[0])} - real_src)
    if not fresh:
        return OBF
    return re.compile(OBF.pattern + r"|(?<![\w$])(?:" + "|".join(map(re.escape, fresh)) + r")(?![\w$])")


def zip_votes(a: dict, b: dict, votes: dict[str, Counter], pattern_b: re.Pattern = OBF) -> None:
    ta = [str(a["sig"])] + list(a["code"] or []) + [str(a["exceptions"])]
    tb = [str(b["sig"])] + list(b["code"] or []) + [str(b["exceptions"])]
    if len(ta) != len(tb):
        return
    for la, lb in zip(ta, tb):
        na, nb = OBF.findall(la), pattern_b.findall(lb)
        if len(na) != len(nb) or OBF.sub("§", la) != pattern_b.sub("§", lb):
            continue
        for x, y in zip(na, nb):
            votes[x][y] += 1


def resolve(votes: dict[str, Counter], min_votes: int = 2, share: float = 0.6) -> dict[str, str]:
    candidates = []
    for x, c in votes.items():
        (y, n), total = c.most_common(1)[0], sum(c.values())
        if n >= min_votes and n / total >= share:
            candidates.append((n, n / total, x, y))
    mapping, taken = {}, set()
    for n, frac, x, y in sorted(candidates, reverse=True):
        if y not in taken:
            mapping[x] = y
            taken.add(y)
    return mapping


def match(src: dict[str, dict], dst: dict[str, dict], rounds: int = 10) -> tuple[dict[str, str], dict[str, str]]:
    pat = fresh_pattern(src, dst)
    by_fp_src, by_fp_dst = defaultdict(list), defaultdict(list)
    for k, b in src.items():
        by_fp_src[fingerprint(b)].append(k)
    for k, b in dst.items():
        by_fp_dst[fingerprint(b, pat)].append(k)
    pairs = {ks[0]: by_fp_dst[fp][0] for fp, ks in by_fp_src.items() if len(ks) == 1 and len(by_fp_dst.get(fp, [])) == 1}
    mapping: dict[str, str] = {}
    for _ in range(rounds):
        votes: dict[str, Counter] = defaultdict(Counter)
        for ka, kb in pairs.items():
            zip_votes(src[ka], dst[kb], votes, pat)
            pa, pb = key_parts(ka), key_parts(kb)
            if pa and pb:
                for x, y in ((pa[0], pb[0]), (pa[3], pb[3])):
                    if OBF.fullmatch(x) and (pat.fullmatch(y) or not OBF.search(y)):
                        votes[x][y] += 2
        mapping = resolve(votes)
        targets = set(mapping.values())
        taken = set(pairs.values())
        dst_by_class = defaultdict(list)
        for kb in dst:
            p = key_parts(kb)
            if p and kb not in taken:
                dst_by_class[(p[0], p[1], p[2])].append(kb)
        added = 0
        for ka, body in src.items():
            if ka in pairs:
                continue
            p = key_parts(ka)
            if not p:
                continue
            cls = mapping.get(p[0], p[0])
            cands = dst_by_class.get((cls, p[1], p[2]), [])
            if not cands:
                continue
            want = body_text(body, mapping)
            hits = [kb for kb in cands if known_text(dst[kb], targets, pat) == want]
            if len(hits) == 1:
                pairs[ka] = hits[0]
                taken.add(hits[0])
                dst_by_class[(cls, p[1], p[2])].remove(hits[0])
                added += 1
        if not added:
            added = pair_by_opcodes(src, dst, pairs, mapping, dst_by_class)
        if not added:
            break
    votes = defaultdict(Counter)
    for ka, kb in pairs.items():
        zip_votes(src[ka], dst[kb], votes, pat)
    known = resolve(votes) | mapping
    for ka, kb in changed_pairs(src, dst, pairs, known, pat).items():
        aligned_votes(src[ka], dst[kb], votes, known, pat)
    return resolve_unanimous(votes, resolve(votes) | known), pairs


def changed_pairs(src: dict[str, dict], dst: dict[str, dict], pairs: dict[str, str], mapping: dict[str, str],
                  pattern_b: re.Pattern = OBF) -> dict[str, str]:
    taken = set(pairs.values())
    out = {}
    for ka in src:
        p = key_parts(ka)
        if ka in pairs or not p:
            continue
        cls, member = (mapping.get(x, None if OBF.fullmatch(x) else x) for x in (p[0], p[3]))
        kb = f"{cls}/{p[1]}/{p[2]} {member}" if cls and member else None
        if kb in dst and kb not in taken:
            out[ka] = kb
    return out


MIN_ALIGNED = 3


def aligned_votes(a: dict, b: dict, votes: dict[str, Counter], known: dict[str, str],
                  pattern_b: re.Pattern = OBF) -> None:
    import difflib
    targets = set(known.values())
    ta = [str(a["sig"])] + list(a["code"] or []) + [str(a["exceptions"])]
    tb = [str(b["sig"])] + list(b["code"] or []) + [str(b["exceptions"])]
    na = [OBF.sub(lambda m: known.get(m.group(0), "§"), line) for line in ta]
    nb = [pattern_b.sub(lambda m: m.group(0) if m.group(0) in targets else "§", line) for line in tb]
    for i, j, n in difflib.SequenceMatcher(None, na, nb, autojunk=False).get_matching_blocks():
        if n < MIN_ALIGNED:
            continue
        for la, lb in zip(ta[i:i + n], tb[j:j + n]):
            for x, y in zip(OBF.findall(la), pattern_b.findall(lb)):
                if x not in known:
                    votes[x][y] += 1


MIN_OPCODES = 8


def opcode_seq(body: dict) -> tuple[str, ...]:
    return tuple(line.split(" ", 1)[0] for line in body["code"] or [])


def pair_by_opcodes(src: dict[str, dict], dst: dict[str, dict], pairs: dict[str, str], mapping: dict[str, str],
                    dst_by_class: dict[tuple, list[str]]) -> int:
    groups: dict[tuple, dict[tuple, list[str]]] = defaultdict(lambda: defaultdict(list))
    for ka, body in src.items():
        p = key_parts(ka)
        cls = mapping.get(p[0], None if OBF.fullmatch(p[0]) else p[0]) if p else None
        if ka in pairs or not cls or len(body["code"] or []) < MIN_OPCODES:
            continue
        groups[(cls, p[1], p[2])][opcode_seq(body)].append(ka)
    added = 0
    for group, by_ops in groups.items():
        cands = defaultdict(list)
        for kb in dst_by_class.get(group, []):
            cands[opcode_seq(dst[kb])].append(kb)
        for ops, kas in by_ops.items():
            if len(kas) == 1 and len(cands.get(ops, [])) == 1:
                pairs[kas[0]] = cands[ops][0]
                dst_by_class[group].remove(cands[ops][0])
                added += 1
    return added


def resolve_unanimous(votes: dict[str, Counter], mapping: dict[str, str]) -> dict[str, str]:
    claims: dict[str, set[str]] = defaultdict(set)
    for x, c in votes.items():
        for y in c:
            claims[y].add(x)
    out, taken = dict(mapping), set(mapping.values())
    for x, c in sorted(votes.items()):
        if x in out or len(c) != 1:
            continue
        y = next(iter(c))
        if y not in taken and claims[y] == {x}:
            out[x] = y
            taken.add(y)
    return out


def swf_digest(swf: Path, symbol_map: Path) -> str:
    if swf.exists():
        return hashlib.sha256(swf.read_bytes()).hexdigest()
    if symbol_map.exists():
        return json.loads(symbol_map.read_text(encoding="utf-8"))["input_sha256"]
    raise FileNotFoundError(f"{swf} (and no {symbol_map.name} to stand in for it)")


def match_versions(a: str, b: str, root: Path | None = None,
                   dirs: dict[str, Path] | None = None) -> tuple[dict[str, str], dict[str, str]]:
    from tools import compare_methods
    root = root or Path(__file__).resolve().parents[1]
    dirs = dirs or {}
    swfs = [Path(dirs.get(v, root / "versions" / v)) / "BrawlhallaAir.swf" for v in (a, b)]
    digest = [swf_digest(s, root / "client" / "symbols" / f"{v}.json") for s, v in zip(swfs, (a, b))]
    cache = root / "build" / "version-match" / f"{a}_to_{b}.json"
    names = pairs = None
    if cache.exists():
        data = json.loads(cache.read_text(encoding="utf-8"))
        if data.get("sha256") == digest and data.get("algorithm") == ALGORITHM:
            names, pairs = data["names"], data["pairs"]
    if names is None:
        missing = [s for s in swfs if not s.exists()]
        if missing:
            raise FileNotFoundError(f"{missing[0]}: no cached match of these versions ({cache.name}) to use without it")
        names, pairs = match(*(compare_methods.collect(compare_methods.swf_blocks(s)) for s in swfs))
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_text(json.dumps({"sha256": digest, "algorithm": ALGORITHM, "names": names, "pairs": pairs}),
                         encoding="utf-8")
    maps = [root / "client" / "symbols" / f"{v}.json" for v in (a, b)]
    if all(m.exists() for m in maps):
        data = [json.loads(m.read_text(encoding="utf-8")) for m in maps]
        if [d.get("input_sha256") for d in data] == digest:
            names = names | match_traits(*(class_traits(d) for d in data), names)
    packets = [root / "client" / "symbols" / f"{v}.packets.json" for v in (a, b)]
    if all(m.exists() for m in packets):
        data = [json.loads(m.read_text(encoding="utf-8")) for m in packets]
        if [d.get("swf_sha256") for d in data] == digest:
            for kind in ("packets", "handlers"):
                names = apply_packets(names, match_packets(data[0].get(kind, {}), data[1].get(kind, {}), {}))
    return names, pairs


def apply_packets(names: dict[str, str], found: dict[str, str]) -> dict[str, str]:
    claimed = set(found.values())
    out = {x: y for x, y in names.items() if x in found or y not in claimed}
    out.update(found)
    return out


def match_packets(src: dict[str, int], dst: dict[str, int], names: dict[str, str]) -> dict[str, str]:
    by_number: dict[int, list[str]] = defaultdict(list)
    for name, n in dst.items():
        by_number[n].append(name)
    taken = set(names.values())
    out = {}
    for name, n in src.items():
        cands = by_number.get(n, [])
        if name not in names and OBF.fullmatch(name) and len(cands) == 1 and cands[0] not in taken:
            out[name] = cands[0]
    return out


def class_traits(symbol_map: dict) -> dict[str, list[tuple[str, str, str]]]:
    out: dict[str, list[tuple[str, str, str]]] = defaultdict(list)
    for b in symbol_map["blocks"]:
        cls = {c[0]: c[1] for c in b["classes"]}
        for m in b["members"]:
            if m[0] in ("instance", "static") and m[1] in cls:
                out[cls[m[1]]].append((m[0], m[2], m[3]))
    return out


def match_traits(src: dict[str, list[tuple]], dst: dict[str, list[tuple]], names: dict[str, str]) -> dict[str, str]:
    taken = set(names.values())
    found: dict[str, set[str]] = defaultdict(set)
    for ca, ta in src.items():
        tb = dst.get(names.get(ca, None if OBF.fullmatch(ca) else ca) or "")
        if not tb or [t[:2] for t in ta] != [t[:2] for t in tb]:
            continue
        known = [(x[2], y[2]) for x, y in zip(ta, tb) if x[2] in names or not OBF.fullmatch(x[2])]
        if not known or any(names.get(x, x) != y for x, y in known):
            continue
        for x, y in zip(ta, tb):
            if x[2] not in names and OBF.fullmatch(x[2]) and OBF.fullmatch(y[2]) and y[2] not in taken:
                found[x[2]].add(y[2])
    targets = [next(iter(v)) for v in found.values() if len(v) == 1]
    return {x: next(iter(v)) for x, v in found.items() if len(v) == 1 and targets.count(next(iter(v))) == 1}


def body_text_raw(body: dict) -> str:
    return "\n".join([str(body["sig"])] + list(body["code"] or []) + [str(body["exceptions"])])


def known_text(body: dict, known: set[str], pattern: re.Pattern = OBF) -> str:
    return pattern.sub(lambda m: m.group(0) if m.group(0) in known else "§", body_text_raw(body))
