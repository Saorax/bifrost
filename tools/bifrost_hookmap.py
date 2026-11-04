"""builds Bifrost's hook map for the port from the AIR project's ``src/platform/patches.json``.

    python tools/bifrost_hookmap.py [--air C:/Coding/BRAWLHALLA PROJECTS/bifrost/bifrost-air] [--commit a47ba9f1] [--out build/bifrost/hooks.json]
    python tools/bifrost_hookmap.py --check     # exit 1 if a site does not resolve to exactly one place

the hooks go as AS3 statements into a copy of the raw AS3 tree (the raw tree never sees one). for each AIR site the
tool finds its method in ``src/as3/<ver>/scripts``, turns a ``before``/``after`` bytecode anchor into the AS3
statement it must match once (or the site's ``occurrence``) and renders the hook with the AIR tool's semantics.
the AIR project is read only (``git show <commit>:path``); the commit is in ``bifrost/SOURCE.txt``.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from tools import pins
DEFAULT_AIR = pins.LAYER_DIR
DEFAULT_OUT = ROOT / "build" / "bifrost" / "hooks.json"
OVERRIDES = ROOT / "bifrost" / "hooks-as3.json"
TEST_OVERRIDES = ROOT / "data" / "hooks-as3.test.json"
HOOKS = "bh.platform.Hooks"


class HookMapError(Exception):
    pass


def air_tree(commit: str) -> Path | None:
    tree = os.environ.get("BIFROST_AIR_TREE")
    if not tree:
        return None
    pinned = (Path(tree) / "PIN.txt").read_text(encoding="utf-8").split()[-1]
    if not (pinned.startswith(commit) or commit.startswith(pinned)):
        raise HookMapError(f"{tree} holds AIR {pinned}, not {commit}")
    return Path(tree)


def air_show(air: Path, commit: str, path: str) -> str:
    tree = air_tree(commit)
    if tree is not None:
        return (tree / path).read_text(encoding="utf-8")
    out = subprocess.run(["git", "-C", str(air), "show", f"{commit}:{path}"], capture_output=True, check=True)
    return out.stdout.decode("utf-8")


def air_archive(air: Path, commit: str, *paths: str) -> bytes:
    tree = air_tree(commit)
    if tree is None:
        return subprocess.run(["git", "-C", str(air), "archive", "--format=tar", commit, *paths],
                              capture_output=True, check=True).stdout
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w") as tar:
        for rel in paths:
            base = tree / rel
            files = [base] if base.is_file() else sorted(p for p in base.rglob("*") if p.is_file())
            for f in files:
                tar.add(f, arcname=f.relative_to(tree).as_posix())
    return buf.getvalue()


def pinned_commit() -> str:
    return pins.pins()["commit"]


AIR_PORT = ROOT / "build" / "bifrost" / "air-port"
_PORTERS: dict[str, object] = {}


def porter(version: str):
    if version not in _PORTERS:
        from tools import port_platform, version_match
        _PORTERS[version] = port_platform.Porter(port_platform.SymbolMap("10.11"), port_platform.SymbolMap(version),
                                                 version_match.match_versions("10.11", version)[0])
    return _PORTERS[version]


def ported_source(air: Path, commit: str, version: str, out: Path | None = None) -> Path:
    from tools import port_platform, version_match
    out = out or AIR_PORT
    tool = hashlib.sha1(Path(port_platform.__file__).read_bytes()).hexdigest()
    want = {"commit": commit, "version": version, "port_platform": tool}
    stamp = out / "STAMP.json"
    if stamp.exists() and json.loads(stamp.read_text(encoding="utf-8")) == want:
        return out
    data = air_archive(air, commit, "src/platform", "src/mods")
    if out.exists():
        shutil.rmtree(out)
    pinned = out / "air"
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        for member in tar.getmembers():
            if member.isfile():
                target = pinned / member.name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(tar.extractfile(member).read())
    carry = porter(version)
    carry.missing.clear()
    port_platform.port_tree(pinned / "src" / "platform", out / "src" / "platform",
                            lambda t: port_platform.FFDEC.sub(lambda m: carry.ffdec(m.group(0)), t))
    patches = out / "src" / "platform" / "patches.json"
    text = patches.read_text(encoding="utf-8")
    patches.write_text(version_match.OBF.sub(lambda m: carry.obfuscated(m.group(0)), text), encoding="utf-8")
    port_platform.port_tree(pinned / "src" / "mods", out / "src" / "mods", lambda t: port_platform.MOD_NAME.sub(
        lambda m: carry.class_file(m) if m.group(1) else carry.obfuscated(m.group(0)), t))
    shutil.rmtree(pinned)
    lines = [f"AIR {commit} src/platform and src/mods, 10.11 -> {version} (tools/bifrost_hookmap.py ported_source).",
             f"Names translated: {len(carry.done)}; not translated: {len(carry.missing)}.", ""]
    lines += [f"not translated {k}: {v}" for k, v in sorted(carry.missing.items())]
    (out / "PORT.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    if carry.missing:
        raise HookMapError(f"{len(carry.missing)} AIR names have no match in {version}: see {out / 'PORT.txt'}")
    stamp.write_text(json.dumps(want) + "\n", encoding="utf-8")
    return out


def air_text(air: Path, commit: str, path: str) -> str:
    if VERSION == "10.11":
        return air_show(air, commit, path)
    return (ported_source(air, commit, VERSION) / path).read_text(encoding="utf-8")


def air_mod_folders(air: Path, commit: str) -> list[str]:
    if VERSION == "10.11":
        return subprocess.run(["git", "-C", str(air), "ls-tree", "--name-only", commit, "src/mods/"],
                              capture_output=True, check=True, text=True).stdout.split()
    mods = ported_source(air, commit, VERSION) / "src" / "mods"
    return sorted(f"src/mods/{p.name}" for p in mods.iterdir() if p.is_dir())


def raw_lines(path: Path) -> list[str]:
    from tools import as3_to_haxe
    text, _, _ = as3_to_haxe.strip_platform_lines(path.read_text(encoding="utf-8"), path.name)
    return text.splitlines()


def _skip_string(text: str, i: int) -> int:
    quote = text[i]
    i += 1
    while i < len(text) and text[i] != quote:
        i += 2 if text[i] == "\\" else 1
    return i + 1


def match_brace(text: str, open_at: int) -> int:
    depth = 0
    i = open_at
    while i < len(text):
        c = text[i]
        if c in "\"'":
            i = _skip_string(text, i)
            continue
        if text.startswith("//", i):
            i = text.find("\n", i)
            if i < 0:
                break
            continue
        if text.startswith("/*", i):
            i = text.find("*/", i) + 2
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise HookMapError("unbalanced braces")


class Method:

    def __init__(self, lines: list[str], key: str):
        static, kind, name = key.split("/")
        accessor = {"getter": r"get\s+", "setter": r"set\s+"}.get(kind, "")
        header = re.compile(rf"^\s*((?:\w+\s+)*)function\s+{accessor}{re.escape(name)}\s*\(")
        hits = [i for i, line in enumerate(lines)
                if (m := header.match(line)) and (("static" in m.group(1).split()) == (static == "s"))]
        if len(hits) != 1:
            raise HookMapError(f"function {key}: {len(hits)} matches")
        self.header = hits[0]
        text = "\n".join(lines)
        offset = sum(len(l) + 1 for l in lines[:self.header])
        open_at = text.find("{", offset)
        sig = text[offset:open_at]
        params = sig[sig.find("(") + 1:sig.rfind(")")]
        self.params = len([p for p in params.split(",") if p.strip() and not p.strip().startswith("...")])
        self.returns_void = bool(re.search(r"\)\s*:\s*void\s*$", sig.strip()))
        self.open = text.count("\n", 0, open_at)
        self.close = text.count("\n", 0, match_brace(text, open_at))
        self.lines = lines

    def body(self) -> range:
        return range(self.open + 1, self.close)

    def register(self, n: int) -> str:
        if n == 0:
            return "this"
        return f"param{n}" if n <= self.params else f"_loc{n}_"


VERSION = "10.11"
_FFDEC: dict[str, dict[str, str]] = {}


def ffdec_name(name: str, version: str | None = None) -> str:
    version = version or VERSION
    if version not in _FFDEC:
        seen: dict[str, set[str]] = {}
        data = json.loads((ROOT / "client" / "symbols" / f"{version}.json").read_text(encoding="utf-8"))
        for block in data["blocks"]:
            for member in block["members"]:
                seen.setdefault(member[3], set()).add(member[4])
        _FFDEC[version] = {k: next(iter(v)) for k, v in seen.items() if len(v) == 1}
    return _FFDEC[version].get(name, name)


def _names(anchor: str) -> list[str]:
    names = re.findall(r"\{\{(\w+)\}\}", anchor)
    if names:
        return names
    return [ffdec_name(n) for n in re.findall(r'"([A-Za-z_$][\w$-]*)"\\?\)', anchor)]


def as3_anchor(anchor: str, method: Method) -> tuple[str, str]:
    a = anchor.strip("^$")
    if m := re.fullmatch(r"setlocal(?:\\s\+|\s+)?(\d+)", a):
        reg = re.escape(method.register(int(m.group(1))))
        return rf"^(var\s+)?{reg}\b(\s*:[^=]*)?\s*([-+*/|&^]|<<|>>>?)?=(?!=)|^{reg}\s*(\+\+|--)", "setlocal"
    names = _names(anchor)
    if re.match(r"\(init\|set\)property|initproperty|setproperty", a) and names:
        n = re.escape(names[-1])
        return (rf"(^|[.\s(]){n}\s*([-+*/|&^]|<<|>>>?)?=(?!=)|(^|[.\s]){n}\s*(\+\+|--)"
                rf"|^(\+\+|--)\s*([\w$]+\.)*{n}\s*;", "setproperty")
    if re.match(r"callpropvoid|callproperty|constructprop", a) and names:
        return rf"(^|[^\w$]){re.escape(names[-1])}\s*\(", "call"
    if re.search(r"\\?\), \d+$", a) and names:
        return rf"(^|[^\w$]){re.escape(names[-1])}\s*\(", "call"
    if a == "returnvalue":
        return r"^return\b", "return"
    if m := re.fullmatch(r"findproperty\\s\+\.\*\"\{\{(\w+)\}\}\"\\\)", a):
        n = re.escape(m.group(1))
        return rf"(^|[^\w$.]){n}\s*(\(|([-+*/|&^]|<<|>>>?)?=(?!=))", "findproperty"
    raise HookMapError(f"no AS3 rule for anchor {anchor!r}")


def statements(method: Method) -> list[tuple[int, int, str]]:
    out = []
    i = method.open + 1
    while i < method.close:
        s = method.lines[i].strip()
        if not s or s in ("{", "}") or s.startswith("//"):
            i += 1
            continue
        j = i
        text = s
        while not text.rstrip().endswith((";", "{", "}")) and j + 1 < method.close and not re.match(
                r"^(if|else|while|for|switch|case|default|do|try|catch|finally)\b", text):
            j += 1
            text += " " + method.lines[j].strip()
        out.append((i, j, text))
        i = j + 1
    return out


def find_anchor(method: Method, regex: str, occurrence: int | None) -> tuple[int, int, int]:
    pat = re.compile(regex)
    hits = [(a, b) for a, b, text in statements(method)
            if pat.search(text) and not re.match(r"^(if|while|for|switch|else)\b", text)]
    if not hits:
        raise HookMapError(f"anchor {regex!r}: no statement")
    if occurrence is None:
        if len(hits) != 1:
            raise HookMapError(f"anchor {regex!r}: {len(hits)} statements")
        return hits[0] + (1,)
    if occurrence > len(hits):
        raise HookMapError(f"anchor {regex!r}: occurrence {occurrence} of {len(hits)}")
    return hits[occurrence - 1] + (len(hits),)


def as3_arg(arg: str, method: Method) -> str:
    if arg in ("this", "null"):
        return arg
    if re.fullmatch(r"'[A-Za-z0-9_ .-]*'", arg):
        return '"' + arg[1:-1] + '"'
    if m := re.fullmatch(r"(?:param|local)(\d+)((?:\.\w+)?)", arg):
        return method.register(int(m.group(1))) + m.group(2)
    if re.fullmatch(r"this\.\w+|[A-Za-z_]\w*\.\w+", arg):
        return arg
    raise HookMapError(f"argument {arg!r}")


def as3_code(patch: dict, method: Method) -> tuple[list[str], list[str]]:
    pid = re.sub(r"\W", "_", patch["id"])
    if "code" in patch:
        note = patch.get("note", "")
        if not note or "end_anchor" in patch:
            raise HookMapError("raw code without a plain AS3 note (needs a hand-written AS3 form)")
        imports = [HOOKS] if "Hooks." in note else []
        return [note.rstrip(";") + ";"], imports
    args = ", ".join(as3_arg(a, method) for a in patch.get("args", []))
    n = len(patch.get("args", []))
    if "call" in patch:
        m = re.fullmatch(r"([A-Za-z0-9_.]+):([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)", patch["call"])
        if not m:
            raise HookMapError(f"call {patch['call']!r}")
        imports = [f"{m.group(1)}.{m.group(2)}"]
        call = f"{m.group(2)}.{m.group(3)}({args})"
        if patch.get("returns") == "nonzero":
            return [f"var _bh_{pid}:* = {call};", f"if(_bh_{pid}) return _bh_{pid};"], imports
        if patch.get("returns") == "skip":
            return [f"if({call}) return;"], imports
        if "sets_param" in patch:
            return [f"{method.register(int(patch['sets_param']))} = {call};"], imports
        return [f"{call};"], imports
    hook = f"Hooks.{patch['hook']}"
    imports = [HOOKS]
    if patch.get("filter"):
        call = f"{hook}.filter({args})"
        if patch.get("returns") == "nonzero":
            return [f"var _bh_{pid}:* = {call};", f"if(_bh_{pid}) return _bh_{pid};"], imports
        if "sets_param" not in patch:
            raise HookMapError("a filter hook needs sets_param or returns nonzero")
        conv = patch.get("convert")
        if conv not in (None, "String", "int", "uint", "Boolean"):
            raise HookMapError(f"convert {conv!r}")
        value = f"{conv}({call})" if conv else call
        if "as" in patch:
            value = f"{value} as {patch['as']}"
        return [f"{method.register(int(patch['sets_param']))} = {value};"], imports
    suffix = str(n) if n <= 3 else ""
    if not patch.get("consumable"):
        return [f"{hook}.fire{suffix}({args});"], imports
    test = f"{hook}.fireUntilHandled{suffix}({args})"
    if "sets_local" in patch:
        return [f"if({test}) {method.register(int(patch['sets_local']))} = true;"], imports
    ret = {"true": "return true;", "false": "return false;", "void": "return;"}[patch.get("returns", "void")]
    return [f"if({test}) {ret}"], imports


def chain_end(lines: list[str], header: int) -> int:
    text = "\n".join(lines)
    at = sum(len(l) + 1 for l in lines[:header])
    while True:
        close = match_brace(text, text.index("{", at))
        end = text.count("\n", 0, close)
        nxt = end + 1
        while nxt < len(lines) and not lines[nxt].strip():
            nxt += 1
        if nxt >= len(lines) or not lines[nxt].strip().startswith("else"):
            return end
        at = sum(len(l) + 1 for l in lines[:nxt])


def resolve_override(entry: dict, over: dict, patch: dict, lines: list[str], method: Method) -> dict:
    pat = re.compile(over["anchor"])
    hits = [i for i in method.body() if pat.search(lines[i].strip())]
    occ = over.get("occurrence")
    if not hits or (occ is None and len(hits) != 1) or (occ is not None and occ > len(hits)):
        raise HookMapError(f"override anchor {over['anchor']!r}: {len(hits)} lines")
    first = hits[(occ or 1) - 1]
    op = over.get("op", "insert")
    entry.update({"op": op, "anchor": over["anchor"], "rule": "override", "matches": len(hits),
                  "why": over.get("why", "")})
    if "insert" in over:
        entry["insert"] = over["insert"]
        entry["imports"] = over.get("imports", [])
    if op == "insert":
        last = first
        for a, b, _ in statements(method):
            if a == first:
                last = b
        entry["line"] = (first if over.get("where", patch["where"]) == "before" else last + 1) + 1
        entry["statement"] = lines[first].strip()
    elif op == "replace":
        stmt = [(a, b) for a, b, _ in statements(method) if a == first]
        if not stmt:
            raise HookMapError(f"override anchor {over['anchor']!r}: not a statement")
        entry["lines"] = [first + 1, stmt[0][1] + 1]
        entry["statement"] = " ".join(l.strip() for l in lines[first:stmt[0][1] + 1])
    elif op == "wrap":
        if not lines[first].strip().startswith("if"):
            raise HookMapError(f"override anchor {over['anchor']!r}: wrap needs an if")
        entry["cond"] = over["cond"]
        entry["insert"] = []
        entry["imports"] = over.get("imports", [])
        entry["lines"] = [first + 1, chain_end(lines, first) + 1]
        entry["statement"] = lines[first].strip()
    else:
        raise HookMapError(f"override op {op!r}")
    return entry


def load_overrides(path: Path | None = None, section: str = "sites") -> dict[str, dict]:
    data: dict[str, list] = {}
    for source in [path] if path else [OVERRIDES, TEST_OVERRIDES]:
        if source.exists():
            for key, items in json.loads(source.read_text(encoding="utf-8")).items():
                data.setdefault(key, []).extend(items)
    if not data:
        return {}
    found = {o["id"]: o for o in data.get(section, [])}
    if VERSION != "10.11":
        found = {k: translate_override(o, VERSION) for k, o in found.items()}
        found.update({o["id"]: o for o in data.get(f"{section}@{VERSION}", [])})
    return found


OVERRIDE_CODE = ("anchor", "insert", "cond", "file", "function", "imports")


def translate_override(over: dict, version: str) -> dict:
    from tools import port_platform, version_match
    carry = porter(version)
    carry.missing.clear()

    def text(s: str) -> str:
        s = port_platform.FFDEC.sub(lambda m: carry.ffdec(m.group(0)), s)
        return re.sub(r"\{\{([^}]+)\}\}", lambda m: "{{" + version_match.OBF.sub(
            lambda n: carry.obfuscated(n.group(0)), m.group(1)) + "}}", s)

    out = dict(over)
    for key in OVERRIDE_CODE:
        if isinstance(out.get(key), str):
            out[key] = text(out[key])
        elif isinstance(out.get(key), list):
            out[key] = [text(v) if isinstance(v, str) else v for v in out[key]]
    if carry.missing:
        raise HookMapError(f"override {over['id']}: no {version} match for " + ", ".join(sorted(carry.missing)))
    return out


def resolve(patch: dict, tree: Path, overrides: dict[str, dict] | None = None) -> dict:
    entry = {k: patch[k] for k in ("id", "file", "function", "where") if k in patch}
    path = tree / patch["file"]
    if not path.exists():
        raise HookMapError(f"no file {patch['file']}")
    lines = raw_lines(path)
    method = Method(lines, patch["function"])
    over = (overrides or {}).get(patch["id"])
    if over is not None:
        if "insert" not in over and over.get("op") != "wrap":
            entry["insert"], entry["imports"] = as3_code(patch, method)
        return resolve_override(entry, over, patch, lines, method)
    code, imports = as3_code(patch, method)
    entry["op"] = "insert"
    entry["insert"] = code
    entry["imports"] = imports
    where = patch["where"]
    if where == "start":
        entry["line"] = method.open + 2
    elif where == "end":
        if not method.returns_void:
            raise HookMapError("'end' on a method that returns a value")
        entry["line"] = method.close + 1
    else:
        regex, rule = as3_anchor(patch["anchor"], method)
        first, last, count = find_anchor(method, regex, patch.get("occurrence"))
        offset = patch.get("offset", 0)
        entry.update({"anchor": regex, "rule": rule, "matches": count})
        if "occurrence" in patch:
            entry["occurrence"] = patch["occurrence"]
        if offset:
            entry["offset"] = offset
        entry["line"] = (first if where == "before" else last + 1) + 1
        entry["statement"] = " ".join(l.strip() for l in lines[first:last + 1])
    return entry


def build(patches: list[dict], tree: Path, overrides: dict[str, dict] | None = None) -> tuple[list[dict], list[dict]]:
    sites, failed = [], []
    for patch in patches:
        try:
            sites.append(resolve(patch, tree, overrides))
        except HookMapError as e:
            failed.append({"id": patch["id"], "file": patch["file"], "function": patch["function"],
                           "where": patch["where"], "anchor": patch.get("anchor"), "why": str(e)})
    return sites, failed


SKIP_MODS = {"smoke_probe": "AIR's smoke harness; the engine has its own smoke driver",
             "smoke_screens": "AIR's smoke harness; the engine has its own smoke driver"}


class AS3Names:

    def __init__(self, version: str | None = None):
        version = version or VERSION
        sym = ROOT / "client" / "symbols"
        data = json.loads((sym / f"{version}.json").read_text(encoding="utf-8"))
        aliases = json.loads((sym / f"{version}.aliases.json").read_text(encoding="utf-8"))["aliases"]
        self.alias = {a["original"]: a["alias"] for a in aliases}
        self.classes: dict[str, str] = {}
        self.members: dict[tuple[str, str], tuple[str, bool]] = {}
        for block in data["blocks"]:
            owners = {c[0]: c[1] for c in block["classes"]}
            for c in block["classes"]:
                self.classes[c[1]] = self.alias.get(c[1], c[2])
            for scope, owner, _kind, original, renamed, *_ in block["members"]:
                if scope in ("static", "instance") and owner in owners:
                    name = self.alias.get(f"{owners[owner]}.{original}", renamed)
                    self.members[(owners[owner], original)] = (name, scope == "static")

    def cls(self, original: str) -> str:
        if original not in self.classes:
            raise HookMapError(f"no class {original}")
        return self.classes[original]

    def member(self, cls: str, original: str) -> tuple[str, bool]:
        if (cls, original) not in self.members:
            raise HookMapError(f"no member {cls}.{original}")
        return self.members[(cls, original)]

    def expand(self, text: str) -> str:
        def one(m: re.Match) -> str:
            cls, _, member = m.group(1).partition(".")
            return self.cls(cls) + ("." + self.member(cls, member)[0] if member else "")
        return re.sub(r"\{\{(_-[\w$-]+?(?:\._-[\w$-]+)?)\}\}", one, text)


def mod_edit(after: str, insert: list[str]) -> tuple[str, str, str] | None:
    if (m := re.fullmatch(r'\^pushstring\\s\+"([\w.]+)"\$', after)) and len(insert) == 2 and insert[0] == "pop" \
            and (n := re.fullmatch(r'pushstring "([\w.]+)"', insert[1])):
        return rf'"{re.escape(m.group(1))}"', f'"{n.group(1)}"', "string"
    if after == r'^pushstring\s+"[0-9]+"$' and len(insert) == 2 and insert[1] == "add" \
            and (n := re.fullmatch(r'pushstring "([^"\\]*)"', insert[0])):
        return r'"([0-9]+)"', rf'"\1" + "{n.group(1)}"', "string append"
    if (m := re.fullmatch(r"\^push(?:uint|byte|short|int)\\s\+(\d+)\$", after)) and len(insert) == 2 \
            and insert[0] == "pop" and (n := re.fullmatch(r"push(?:uint|byte|short|int) (\d+)", insert[1])):
        return rf"(?<![\w.\"]){m.group(1)}(?![\w.\"])", n.group(1), "constant"
    if "applicationStorageDirectory" in after and insert == [
            'pushstring "Bifrost"', 'callproperty QName(PackageNamespace(""), "resolvePath"), 1']:
        return (r'\.applicationStorageDirectory\b(?!\.resolvePath\("Bifrost"\))',
                '.applicationStorageDirectory.resolvePath("Bifrost")', "storage folder")
    return None


def resolve_mod(sid: str, patch: dict, names: AS3Names, tree: Path, over: dict | None) -> dict:
    cls = Path(patch["class"]).name.split(".")[0]
    if cls not in names.classes and cls.endswith("_"):
        cls = cls[:-1]
    trait = patch["method"].removeprefix("trait:")
    name, static = names.member(cls, trait)
    file = names.cls(cls) + ".as"
    function = f"{'s' if static else 'i'}/method/{name}"
    lines = raw_lines(tree / file)
    method = Method(lines, function)
    entry = {"id": sid, "file": file, "function": function}
    if over is not None:
        over = dict(over, insert=[names.expand(c) for c in over.get("insert", [])])
        if over.get("where") == "start":
            entry.update({"op": "insert", "where": "start", "line": method.open + 2, "insert": over["insert"],
                          "imports": over.get("imports", []), "rule": "override", "why": over.get("why", "")})
            return entry
        entry["where"] = over.get("where", "after")
        return resolve_override(entry, over, {"where": entry["where"]}, lines, method)
    edit = mod_edit(patch["after"], patch["insert"] if isinstance(patch["insert"], list) else [])
    if edit is None:
        raise HookMapError(f"no AS3 form for after {patch['after']!r} (add one to bifrost/hooks-as3.json 'mods')")
    find, replace, rule = edit
    body = "\n".join(lines[method.open + 1:method.close])
    count = len(re.findall(find, body))
    if count != 1:
        raise HookMapError(f"edit {find!r}: {count} matches in {file} {function}")
    entry.update({"op": "edit", "where": "edit", "find": find, "replace": replace, "rule": rule,
                  "lines": [method.open + 2, method.close], "imports": []})
    return entry


def build_mods(air: Path, commit: str, tree: Path, overrides: dict[str, dict]) -> tuple[list[dict], list[dict]]:
    listing = air_mod_folders(air, commit)
    names = AS3Names()
    sites, failed = [], []
    for folder in listing:
        mod = Path(folder).name
        if mod in SKIP_MODS:
            continue
        data = json.loads(air_text(air, commit, f"{folder}/mod.json"))
        for i, patch in enumerate(data.get("patches", [])):
            sid = f"mod-{mod}-{i}"
            try:
                sites.append(resolve_mod(sid, patch, names, tree, overrides.get(sid)))
            except HookMapError as e:
                failed.append({"id": sid, "file": patch.get("class"), "function": patch.get("method"),
                               "where": "mod", "anchor": patch.get("after"), "why": str(e)})
    return sites, failed


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--air", type=Path, default=DEFAULT_AIR, help="the AIR project (read only)")
    p.add_argument("--commit", help="the AIR commit (default: bifrost/SOURCE.txt)")
    p.add_argument("--version", default="10.11")
    p.add_argument("--out", type=Path, default=DEFAULT_OUT)
    p.add_argument("--check", action="store_true", help="exit 1 if any site does not resolve")
    args = p.parse_args(argv)
    global VERSION
    VERSION = args.version
    commit = args.commit or pinned_commit()
    data = json.loads(air_text(args.air, commit, "src/platform/patches.json"))
    patches = data["patches"] if isinstance(data, dict) else data
    tree = ROOT / "src" / "as3" / args.version / "scripts"
    overrides = load_overrides()
    unknown = set(overrides) - {p["id"] for p in patches}
    if unknown:
        print(f"overrides for sites AIR no longer has: {', '.join(sorted(unknown))}")
    sites, failed = build(patches, tree, overrides)
    mod_sites, mod_failed = build_mods(args.air, commit, tree, load_overrides(section="mods"))
    sites, failed = sites + mod_sites, failed + mod_failed
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps({"air_commit": commit, "version": args.version, "sites": sites,
                                    "unresolved": failed}, indent=1) + "\n", encoding="utf-8", newline="\n")
    where = Counter(s["where"] for s in sites)
    print(f"{len(patches)} AIR sites at {commit}: {len(sites)} resolved "
          f"({', '.join(f'{k} {v}' for k, v in sorted(where.items()))}), {len(failed)} not -> {args.out}")
    for f in failed:
        print(f"  {f['id']} ({f['file']} {f['function']} {f['where']}): {f['why']}")
    return 1 if args.check and failed else 0


if __name__ == "__main__":
    sys.exit(main())
