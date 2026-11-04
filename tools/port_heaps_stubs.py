"""``flash.*`` stand-ins with empty bodies, generated from the OpenFL API the raw game builds against, so the game
type-checks and builds against the new (Heaps) engine.

    python tools/port_heaps_stubs.py dump            # Haxe's type dump of the OpenFL build (-xml, ~30 s)
    python tools/port_heaps_stubs.py stubs [--check] # the stand-ins, and with --check a type-check of the raw game
    python tools/port_heaps_stubs.py test [Suite...] # the engine's own classes' tests on HashLink (after stubs)

``dump`` writes ``build/port-heaps/e1/types.xml``; ``stubs`` reads it and writes ``build/port-heaps/e1/stubs``.
``stubs --build C:/abs/game.hl`` compiles the new engine's game (``--headless``: the game without a window;
``--both``: also ``headless.hl`` beside it, compiled at the same time); ``python tools/port_heaps.py game`` runs it.
``--check`` type-checks the raw game (``--no-output``) and writes the compiler's errors to
``build/port-heaps/e1/check.txt`` with a count per error kind.
"""
from __future__ import annotations

import argparse
import contextlib
import os
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
OUT = ROOT / "build" / "port-heaps" / "e1"
ENGINE = Path("C:/Coding/bh-port-engine-openfl")
GAME = Path("C:/Coding/BRAWLHALLA PROJECTS/bh-raw/bh-game/src")
RAW_GAME = GAME
OWN_SRC = ROOT / "port" / "engine-heaps" / "src"

VECTOR = [
    "@:forward(length, push, pop, join, slice, splice, indexOf, lastIndexOf, reverse, sort, copy, insertAt,",
    "\tremoveAt, iterator, shift, unshift)",
    "abstract Vector<T>(Array<T>) from Array<T> to Array<T> {",
    "\tpublic inline function new(?length:Int, ?fixed:Bool, ?array:Array<T>) this = [];",
    "\tpublic var fixed(get, set):Bool;",
    "\tinline function get_fixed():Bool return false;",
    "\tinline function set_fixed(value:Bool):Bool return value;",
    "\t@:arrayAccess inline function get(index:Int):T return this[index];",
    "\t@:arrayAccess inline function set(index:Int, value:T):T return this[index] = value;",
    "\t// OpenFL's concat takes an optional vector (``v.concat()`` copies).",
    "\tpublic inline function concat(?a:Array<T>):Vector<T> return a == null ? this.copy() : this.concat(a);",
    "\tpublic static function ofArray<T>(array:Array<T>):Vector<T> return array;",
    "}",
]

KEEP = {"Int", "Float", "Bool", "String", "Void", "Dynamic", "Array", "Null", "Class", "Enum", "Map", "UInt",
        "Iterator", "Iterable", "EReg", "Date", "Xml", "Any", "KeyValueIterator", "ArrayAccess"}


def dump() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    hxml = (ENGINE / "build.hxml").read_text(encoding="utf-8")
    hxml = re.sub(r"(?m)^--cwd .*$", f"--cwd {ENGINE.as_posix()}", hxml)
    hxml = re.sub(r"(?m)^--hl .*$", f"--hl {(OUT / 'dump.hl').as_posix()}\n-xml {(OUT / 'types.xml').as_posix()}", hxml)
    (OUT / "dump.hxml").write_text(hxml, encoding="utf-8")
    started = time.monotonic()
    run = subprocess.run([str(ENGINE / "tools" / "haxe" / "haxe.exe"), str(OUT / "dump.hxml")], capture_output=True,
                         text=True)
    print(run.stdout[-2000:] + run.stderr[-2000:])
    print(f"dump in {time.monotonic() - started:.1f} s -> {OUT / 'types.xml'}")
    return run.returncode


def load_types(path: Path) -> dict[str, ET.Element]:
    text = path.read_text(encoding="utf-8")
    text = re.sub(r' expr="[^"]*"', "", text)
    root = ET.fromstring(text)
    return {e.get("path"): e for e in root}


def flash_aliases() -> tuple[dict[str, str], list[Path]]:
    aliases: dict[str, str] = {}
    own: list[Path] = []
    base = ENGINE / "runtime"
    for path in sorted((base / "flash").rglob("*.hx")):
        text = path.read_text(encoding="utf-8")
        match = re.search(r"^typedef\s+(\w+)\s*=\s*(openfl\.[\w.]+)\s*;", text, re.M)
        flash = ".".join(path.relative_to(base).with_suffix("").parts)
        if match and not re.search(r"^(class|abstract|interface|enum)\b", text, re.M):
            aliases[match.group(2)] = flash
        else:
            own.append(path)
    return aliases, own


LITERAL = re.compile(r'^(?:"(?:[^"\\]|\\.)*"|-?(?:0x[0-9A-Fa-f]+|\d+(?:\.\d+)?(?:[eE]-?\d+)?)|true|false)$')


ARG_FIELDS = {"id": "errorID"}


def literal_text(field: ET.Element) -> str | None:
    for m in field.iter("m"):
        if m.get("n") == ":value":
            e = m.find("e")
            return (e.text or "").strip() if e is not None else ""
    return None


def literal(field: ET.Element) -> str | None:
    text = literal_text(field)
    return text if text is not None and LITERAL.match(text) else None


class Gen:
    def __init__(self, types: dict[str, ET.Element], aliases: dict[str, str]):
        self.types = types
        self.names = dict(aliases)
        self.queue = list(aliases)
        self.own: set[str] = set()

    @staticmethod
    def public_openfl(path: str) -> bool:
        return path.startswith("openfl.") and "._" not in path and not path.split(".")[-1].startswith("_")

    def flash_name(self, path: str) -> str | None:
        if path in self.names:
            return self.names[path]
        if self.public_openfl(path) and path in self.types and self.types[path].get("private") != "1":
            name = "flash." + path[len("openfl."):]
            if name in self.own and not (OWN_SRC / (name.replace(".", "/") + ".hx")).exists():
                name = path
            self.names[path] = name
            self.queue.append(path)
            return name
        return None

    def type(self, e: ET.Element | None, params: set[str]) -> str:
        if e is None:
            return "Dynamic"
        tag, path = e.tag, e.get("path", "")
        if tag == "f":
            parts = [self.type(c, params) for c in e]
            args, ret = parts[:-1], parts[-1]
            return "(" + ", ".join(args) + ") -> " + ret if args else "() -> " + ret
        if tag == "d":
            return "Dynamic"
        if tag == "a":
            return "Dynamic"
        if tag in ("c", "x", "t", "e"):
            if path in params or path.rsplit(".", 1)[-1] in params:
                return path.rsplit(".", 1)[-1]
            sub = [self.type(c, params) for c in e]
            short = path.split(".")[-1]
            if path in KEEP or short in KEEP and "." not in path:
                name = path
            elif path.startswith("haxe.") and "._" not in path:
                name = path
                module = self.types[path].get("module") if path in self.types else None
                if module and module != path:
                    name = module + "." + short
            elif path.startswith("openfl."):
                name = self.flash_name(path)
                if name is None:
                    return "Dynamic"
            elif path.startswith("flash."):
                name = path
            else:
                return "Dynamic"
            if path == "Null" and sub:
                return f"Null<{sub[0]}>"
            if sub and name not in ("Void",):
                return f"{name}<{', '.join(sub)}>"
            return name
        return "Dynamic"

    def emit(self, path: str) -> str:
        e = self.types[path]
        self.current = path
        self.event = False
        flash = self.names[path]
        pkg, _, short = flash.rpartition(".")
        params = set(filter(None, (e.get("params") or "").split(":")))
        plist = f"<{', '.join(sorted(params))}>" if params else ""
        lines = [f"package {pkg};", "", f"// E1 stand-in generated from {path}'s API (tools/port_heaps_stubs.py)."]
        if e.tag == "abstract":
            return "\n".join(lines + self.emit_abstract(e, short, params)) + "\n"
        if e.tag == "typedef":
            return "\n".join(lines + [f"typedef {short}{plist} = Dynamic;"]) + "\n"
        if e.tag == "enum":
            ctors = [c.tag for c in e if c.tag not in ("meta", "haxe_doc")]
            return "\n".join(lines + [f"enum {short} {{"] + [f"\t{c};" for c in ctors] + ["}"]) + "\n"
        is_interface = e.get("interface") == "1"
        head = ("interface " if is_interface else "class ") + short + plist
        ext = e.find("extends")
        has_super = False
        if ext is not None:
            name = self.type(ET.Element("c", path=ext.get("path")), params)
            if name != "Dynamic":
                head += " extends " + name
                has_super = True
        self.super_args = self.constructor_args(ext.get("path")) if has_super else 0
        self.event = has_super and self.is_event(path)
        self.parent_ctor = self.constructor(ext.get("path")) if has_super else None
        self.fields = self.chain_vars(path)
        self.short = short
        for imp in e.findall("implements"):
            name = self.type(ET.Element("c", path=imp.get("path")), params)
            if name != "Dynamic":
                head += " implements " + name
        lines.append(head + " {")
        for f in e:
            if f.tag in ("extends", "implements", "meta", "haxe_doc", "__constructor"):
                continue
            if f.get("public") != "1" and f.tag != "new":
                continue
            lines += self.emit_field(f, params, is_interface, has_super)
        lines.append("}")
        return "\n".join(lines) + "\n"

    def is_event(self, path: str | None) -> bool:
        while path is not None and path in self.types:
            if path == "openfl.events.Event":
                return True
            ext = self.types[path].find("extends")
            path = ext.get("path") if ext is not None else None
        return False

    def constructor(self, path: str | None) -> list[str] | None:
        while path is not None and path in self.types:
            new = self.types[path].find("new")
            if new is not None and len(new) and new[0].tag == "f":
                names = [n for n in (new[0].get("a") or "").split(":") if n]
                defaults = (new[0].get("v") or "").split(":") if new[0].get("v") is not None else []
                return [n + (f"={defaults[i]}" if i < len(defaults) and LITERAL.match(defaults[i] or "-") else "")
                        for i, n in enumerate(names)]
            ext = self.types[path].find("extends")
            path = ext.get("path") if ext is not None else None
        return None

    def chain_vars(self, path: str | None) -> set[str]:
        names: set[str] = set()
        while path is not None and path in self.types:
            e = self.types[path]
            names |= {f.tag for f in e if f.get("public") == "1" and f.get("set") != "method" and f.get("static") != "1"
                      and f.tag not in ("extends", "implements", "meta", "haxe_doc")}
            ext = e.find("extends")
            path = ext.get("path") if ext is not None else None
        return names

    def field_of(self, arg: str) -> str | None:
        if arg in self.fields:
            return arg
        if arg in ARG_FIELDS and ARG_FIELDS[arg] in self.fields:
            return ARG_FIELDS[arg]
        if arg.endswith("Value") and arg[:-5] in self.fields:
            return arg[:-5]
        return None

    def constructor_args(self, path: str | None) -> int:
        while path is not None and path in self.types:
            e = self.types[path]
            new = e.find("new")
            if new is not None and len(new) and new[0].tag == "f":
                names = new[0].get("a") or ""
                return sum(1 for n in names.split(":") if n and not n.startswith("?")) if names else 0
            ext = e.find("extends")
            path = ext.get("path") if ext is not None else None
        return 0

    def emit_field(self, f: ET.Element, params: set[str], is_interface: bool, has_super: bool) -> list[str]:
        static = "static " if f.get("static") == "1" else ""
        overrides = f.get("override") == "1" or any(m.get("n") == ":override" for m in f.iter("m"))
        kind = f[0] if len(f) else None
        fparams = set(filter(None, (f.get("params") or "").split(":")))
        allp = params | fparams
        if f.get("set") == "method" or f.tag == "new":
            if kind is None or kind.tag != "f":
                return []
            if is_interface and re.match(r"[gs]et_", f.tag):
                return []
            names = (kind.get("a") or "").split(":") if kind.get("a") else []
            types = [self.type(c, allp) for c in kind]
            ret = types[-1] if types else "Void"
            defaults = (kind.get("v") or "").split(":") if kind.get("v") is not None else []
            args = []
            for i, (name, t) in enumerate(zip(names, types[:-1])):
                opt = name.startswith("?")
                value = defaults[i] if i < len(defaults) else ""
                if opt and value and value != "null" and LITERAL.match(value):
                    args.append(name.lstrip("?") + ":" + t + " = " + value)
                else:
                    args.append(("?" if opt else "") + name.lstrip("?") + ":" + t)
            plist = f"<{', '.join(sorted(fparams))}>" if fparams else ""
            sig = f"public {static}function {f.tag}{plist}({', '.join(args)})"
            if f.tag == "new":
                if is_interface:
                    return []
                if self.event and self.parent_ctor is not None:
                    mine = {n.lstrip("?") for n in names}
                    passed = []
                    for n in self.parent_ctor:
                        bare, _, default = n.lstrip("?").partition("=")
                        passed.append(bare if bare in mine else default or ("null" if n.startswith("?") else "cast null"))
                    body = ["\t\tsuper(" + ", ".join(passed) + ");"]
                    handled = {n.lstrip("?").partition("=")[0] for n in self.parent_ctor}
                    for n in mine - handled:
                        field = self.field_of(n)
                        if field is not None:
                            body.append(f"\t\tthis.{field} = {n};")
                    return [f"\t{sig} {{"] + body + ["\t}"]
                body = (" { super(" + ", ".join(["cast null"] * self.super_args) + "); }") if has_super else " {}"
                return [f"\t{sig}{body}"]
            if not static and overrides and has_super:
                sig = "override " + sig
            if is_interface:
                return [f"\t{sig}:{ret};"]
            body = " {}" if ret == "Void" else " { return cast null; }"
            ctor = self.types[self.current].find("new") if self.event else None
            if self.event and f.tag == "clone" and not static and ctor is not None and len(ctor):
                values = []
                names_ = [n for n in (ctor[0].get("a") or "").split(":") if n]
                defaults_ = (ctor[0].get("v") or "").split(":") if ctor[0].get("v") is not None else []
                for i, n in enumerate(names_):
                    field = self.field_of(n.lstrip("?"))
                    default = defaults_[i] if i < len(defaults_) and LITERAL.match(defaults_[i] or "-") else "null"
                    values.append(field if field is not None else default)
                body = f" {{ return new {self.short}({', '.join(values)}); }}"
            elif not static and overrides and has_super:
                return []
            return [f"\t{sig}:{ret}{body}"]
        if is_interface:
            return [f"\tpublic var {f.tag}:{self.type(kind, allp)};"]
        if overrides:
            return []
        value = literal(f) if static else None
        if value is not None:
            return [f"\tpublic {static}var {f.tag}:{self.type(kind, allp)} = {value};"]
        return [f"\tpublic {static}var {f.tag}:{self.type(kind, allp)};"]

    def emit_abstract(self, e: ET.Element, short: str, params: set[str]) -> list[str]:
        impl = e.find("impl/class")
        values = []
        if impl is not None:
            for f in impl:
                if f.get("static") == "1" and any(m.get("n") == ":enum" for m in f.iter("m")) and \
                        f.get("set") != "method":
                    m = re.match(r"cast (-?\d+)$", literal_text(f) or "")
                    values.append((f.tag, int(m.group(1)) if m else None))
        if not values:
            if e.get("path") == "openfl.Vector":
                return VECTOR
            under = e.find("this")
            name = self.type(under[0], params) if under is not None and len(under) else "Dynamic"
            plist = f"<{', '.join(sorted(params))}>" if params else ""
            new = impl.find("_new") if impl is not None else None
            if name == "Dynamic" and new is not None and len(new) and new[0].tag == "f":
                names = (new[0].get("a") or "").split(":") if new[0].get("a") else []
                types = [self.type(c, params) for c in new[0]][:-1]
                args = ", ".join(("?" if n.startswith("?") else "") + n.lstrip("?") + ":" + t
                                 for n, t in zip(names, types))
                return [f"abstract {short}{plist}(Dynamic) {{", f"\tpublic inline function new({args}) this = {{}};",
                        "\t@:op(a.b) inline function read(name:String):Dynamic return Reflect.field(this, name);",
                        "\t@:op(a.b) inline function write(name:String, value:Dynamic):Dynamic {",
                        "\t\tReflect.setField(this, name, value);", "\t\treturn value;", "\t}", "}"]
            return [f"typedef {short}{plist} = {name};"]
        out = [f"enum abstract {short}(Null<Int>) {{"]
        out += [f"\tvar {v} = {i if n is None else n};" for i, (v, n) in enumerate(values)]
        names = {v for v, _ in values}
        strings = [(text, name) for text, name in enum_strings(e.get("path") or "") if name in names]
        if strings and {name for _, name in strings} == names and len(strings) == len(names):
            out = [f"enum abstract {short}(String) from String to String {{"]
            out += [f'\tvar {name} = "{text}";' for text, name in strings]
            return out + ["}"]
        if strings:
            out += ["\t@:from static function fromString(value:String):" + short + " {", "\t\treturn switch (value) {"]
            out += [f'\t\t\tcase "{text}": {name};' for text, name in strings]
            out += ["\t\t\tdefault: null;", "\t\t}", "\t}", "\t@:to function toString():String {",
                    f"\t\treturn switch (cast this : {short}) {{"]
            out += [f'\t\t\tcase {name}: "{text}";' for text, name in strings]
            out += ["\t\t\tdefault: null;", "\t\t}", "\t}", "}"]
            return out
        if values and all(n is not None for _, n in values):
            out[0] = f"enum abstract {short}(Int) from Int to Int {{"
            return out + ["}"]
        out += ["\t@:from static function fromString(value:String):" + short + " return cast 0;",
                "\t@:to function toString():String return null;", "}"]
        return out


ENUM_CASE_RE = re.compile(r'case\s+"([^"\\]*)"\s*:\s*([A-Z_][A-Z0-9_]*)\s*;')


def enum_strings(path: str) -> list[tuple[str, str]]:
    if not path.startswith("openfl."):
        return []
    source = ENGINE / "lib" / "openfl" / "src" / Path(*path.split(".")).with_suffix(".hx")
    if not source.exists():
        return []
    text = source.read_text(encoding="utf-8", errors="replace")
    start = text.find("function fromString")
    if start < 0:
        return []
    end = text.find("function toString", start)
    return ENUM_CASE_RE.findall(text[start:end if end > 0 else len(text)])


def refresh_export() -> int:
    sources = [path.stat().st_mtime for path in (ROOT / "port" / "runtime").rglob("*.hx")]
    exported = [path.stat().st_mtime for path in (ENGINE / "runtime").rglob("*.hx")]
    if not sources or (exported and max(sources) <= max(exported)):
        return 0
    print("port/runtime changed since the last export: re-exporting the engine (port_raw_export.py --no-build)")
    from tools import port_raw_export
    return port_raw_export.main(["--out", str(RAW_GAME.parent), "--openfl-engine", str(ENGINE), "--openfl-only",
                                 "--no-build"])


def runtime_stale() -> str | None:
    sources = [(path.stat().st_mtime, path) for path in (ROOT / "port" / "runtime").rglob("*.hx")]
    staged = [path.stat().st_mtime for path in (OUT / "runtime").rglob("*.hx")] if (OUT / "runtime").exists() else []
    if not sources:
        return None
    newest, path = max(sources)
    if staged and newest <= max(staged):
        return None
    return path.relative_to(ROOT).as_posix()


def stubs(check: bool, build: Path | None = None, main: str = "port.engine.HeapsMain",
          headless: Path | None = None, defines: tuple[str, ...] = (), stage_only: bool = False) -> int:
    with work_lock():
        if build is None or check or stage_only:
            return _stubs(check, build, main, headless, defines, stage_only)
        if refresh_export() != 0:
            return 1
        key = build_key(main, headless, defines)
        stamp = build.with_name(build.name + ".stamp")
        outputs = [build] + ([headless] if headless is not None else [])
        try:
            same = stamp.read_text(encoding="utf-8") == key
        except OSError:
            same = False
        if same and os.environ.get("BH_PORT_REBUILD") != "1" and all(path.exists() for path in outputs):
            print(f"{build.name}: inputs unchanged since its last build, reused (BH_PORT_REBUILD=1 rebuilds)")
            return 0
        stamp.unlink(missing_ok=True)
        code = _stubs(check, build, main, headless, defines, stage_only)
        if code == 0:
            stamp.write_text(key, encoding="utf-8")
        return code


def build_key(main: str, headless: Path | None, defines: tuple[str, ...]) -> str:
    import hashlib
    digest = hashlib.sha1(repr((main, str(headless), tuple(defines), str(GAME))).encode())
    files = [Path(__file__).resolve(), OUT / "types.xml"]
    for root in (ROOT / "port", GAME, ENGINE / "runtime", LIB_PATCHES):
        if root.exists():
            files += [path for path in root.rglob("*") if path.is_file()]
    for path in sorted(files):
        try:
            info = path.stat()
        except OSError:
            continue
        digest.update(f"{path}|{info.st_size}|{info.st_mtime_ns}\n".encode())
    return digest.hexdigest()


def _stubs(check: bool, build: Path | None, main: str, headless: Path | None, defines: tuple[str, ...],
           stage_only: bool) -> int:
    if refresh_export() != 0:
        return 1
    types = load_types(OUT / "types.xml")
    aliases, own = flash_aliases()
    gen = Gen(types, aliases)
    gen.own = {".".join(p.relative_to(ENGINE / "runtime").with_suffix("").parts) for p in own}
    for path in sorted((ENGINE / "runtime").rglob("*.hx")):
        if path.relative_to(ENGINE / "runtime").parts[0] == "flash" and path not in own:
            continue
        for ref in set(re.findall(r"\bopenfl(?:\.[a-z]\w*)*\.[A-Z]\w*", path.read_text(encoding="utf-8"))):
            gen.flash_name(ref)
    copied = []
    for path in own:
        name = ".".join(path.relative_to(ENGINE / "runtime").with_suffix("").parts)
        if "lime." in path.read_text(encoding="utf-8"):
            if name in types:
                gen.names[name] = name
                gen.queue.append(name)
        else:
            copied.append(path)
    gen.names["openfl.Vector"] = "openfl.Vector"
    gen.queue.append("openfl.Vector")
    target = OUT / "stubs"
    if target.exists():
        shutil.rmtree(target)
    written = 0
    done: set[str] = set()
    while gen.queue:
        path = gen.queue.pop()
        if path in done or path not in types:
            continue
        done.add(path)
        text = gen.emit(path)
        flash = gen.names[path]
        file = target.joinpath(*flash.split(".")).with_suffix(".hx")
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(text, encoding="utf-8", newline="\n")
        written += 1
    renames = sorted(gen.names.items(), key=lambda kv: -len(kv[0]))
    taken = copy_openfl_sources(target, renames)
    print(f"{len(taken)} modules from OpenFL's own source replace their stand-ins: {', '.join(taken)}")
    overlaid = overlay_own(target)
    print(f"{overlaid} engine classes of our own from {OWN_SRC} replace their stand-ins")
    renames = sorted(gen.names.items(), key=lambda kv: -len(kv[0]))
    for path in copied:
        file = target / path.relative_to(ENGINE / "runtime")
        if (OWN_SRC / path.relative_to(ENGINE / "runtime")).exists():
            continue
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(rename(path.read_text(encoding="utf-8"), renames), encoding="utf-8", newline="\n")
    missing = sorted(set(aliases) - done)
    print(f"{written} stand-ins from {len(aliases)} runtime aliases ({len(missing)} aliases name no dumped type"
          f"{': ' + ', '.join(missing[:8]) if missing else ''}), {len(copied)} of the runtime's {len(own)} own flash classes copied -> {target}")
    if not (check or build or stage_only):
        return 0
    return type_check(target, renames, gen, build, main, headless, defines, stage_only=stage_only)


OPENFL_SOURCES = (
    "openfl.utils.ByteArray",
    "openfl.geom.Point",
    "openfl.geom.Rectangle",
    "openfl.geom.Matrix",
    "openfl.geom.ColorTransform",
    "openfl.utils.IDataInput",
    "openfl.utils.IDataOutput",
    "openfl.utils.Future",
    "openfl.geom.Vector3D",
    "openfl.geom.Matrix3D",
    "openfl.geom.Orientation3D",
    "openfl.text.TextFormat",
    "openfl.text.TextLineMetrics",
    "openfl.net.URLRequest",
    "openfl.net.URLVariables",
    "openfl.net.URLRequestHeader",
    "openfl.net.FileFilter",
    "openfl.media.SoundTransform",
    "openfl.system.LoaderContext",
    "openfl.display.GraphicsPath",
    "openfl.display.GraphicsSolidFill",
    "openfl.display.GraphicsEndFill",
    "openfl.display.GraphicsBitmapFill",
    "openfl.display.GraphicsGradientFill",
    "openfl.display.GraphicsStroke",
    "openfl.display.GraphicsTrianglePath",
    "openfl.display.Timeline",
    "openfl.display.Scene",
    "openfl.display.FrameLabel",
    "openfl.text._internal.TextFormatRange",
    "openfl.text._internal.HTMLParser",
)
OPENFL_SRC = ENGINE / "lib" / "openfl" / "src"
ENGINE_STAND_INS = frozenset(("port.runtime.DirectVectors", "port.runtime.FlashFilters", "port.runtime.NativeMain",
                              "port.runtime.RasterCache", "port.runtime.RasterRelease", "port.runtime.SlowRasters",
                              "port.runtime.TextPaths"))
LIB_PATCHES = ENGINE / "lib-patches"
_ZLIB_LEVEL = 9
OPENFL_SOURCE_PATCHES: list[tuple[str, str, str, int, str]] = [
    ("openfl.utils.ByteArray",
     r"(\t\t\tposition = __length;\r?\n\t\t\}\r?\n)(\t\t#end\r?\n\t\})",
     r"\1\t\t#else" "\n"
     "\t\tvar input = this.sub(0, __length);\n"
     "\t\tvar bytes = switch (algorithm)\n"
     "\t\t{\n"
     "\t\t\tcase CompressionAlgorithm.LZMA: throw new openfl.errors.IOError(\"LZMA is not supported by this engine\");\n"
     f"\t\t\tcase CompressionAlgorithm.DEFLATE: var z = haxe.zip.Compress.run(input, {_ZLIB_LEVEL}); z.sub(2, z.length - 6);\n"
     f"\t\t\tdefault: haxe.zip.Compress.run(input, {_ZLIB_LEVEL});\n"
     "\t\t};\n"
     "\t\t__setData(bytes);\n"
     "\t\t__length = bytes.length;\n"
     "\t\tposition = __length;\n"
     r"\2", 1,
     "``compress()`` did nothing without Lime: zlib (the game's only algorithm) and raw deflate through HashLink's own "
     "zlib (``haxe.zip``), over the logical length only (OpenFL's HL path compressed the whole allocation, see the "
     "OpenFL engine's ``HL_LIBRARY_PATCHES``)"),
    ("openfl.utils.ByteArray",
     r"(\t\t\t__length = __allocated;\r?\n\t\t\}\r?\n)(\t\t#end\r?\n\r?\n\t\tposition = 0;)",
     r"\1\t\t#else" "\n"
     "\t\tvar input = this.sub(0, __length);\n"
     "\t\tvar bytes:Bytes = switch (algorithm)\n"
     "\t\t{\n"
     "\t\t\tcase CompressionAlgorithm.LZMA: throw new openfl.errors.IOError(\"LZMA is not supported by this engine\");\n"
     "\t\t\tcase CompressionAlgorithm.DEFLATE: port.engine.Inflate.run(input, -15);\n"
     "\t\t\tdefault: port.engine.Inflate.run(input, 15);\n"
     "\t\t};\n"
     "\t\t__setData(bytes);\n"
     "\t\t__length = bytes.length;\n"
     r"\2", 1,
     "``uncompress()`` did nothing without Lime, so the game's compressed tables (``ArchiveFile`` line 193, "
     "``Class_8.method_5551``) read as garbage on the new engine (\"Invalid allocation size\" at boot frame 25)"),
    ("openfl.text.TextFormat",
     r"(\t\treturn __cacheKey = '\$font\$size\$bold\$italic';\r?\n)",
     "\t\t#if lime\n\\1\t\t#else\n\t\treturn null;\n\t\t#end\n", 1,
     "the key is for Lime's text shaping cache (``ShapeCache``), which the new engine does not have; every font, "
     "size, bold and italic set built it again from four ``Std.string`` (E9 run 25: 50 ms of the 170 ms results "
     "screen frame, ``SwfTimeline.editText``'s formats)"),
]
COMMENT_RE = re.compile(r"/\*.*?\*/|//[^\n]*", re.DOTALL)
TYPE_DECL_RE = re.compile(r"^\s*(?:@:[^\n]*\s+)*(?:(?:private|extern|final)\s+)*(?:class|interface|abstract|typedef|enum)\s+([A-Z]\w*)",
                          re.MULTILINE)


def copy_openfl_sources(target: Path, renames: list[tuple[str, str]]) -> list[str]:
    names = dict(renames)

    def source_of(module: str) -> Path:
        return OPENFL_SRC.joinpath(*module.split(".")).with_suffix(".hx")

    def exists(module: str) -> bool:
        path = source_of(module)
        return path.parent.is_dir() and path.name in os.listdir(path.parent)

    def provided(module: str) -> bool:
        return OWN_SRC.joinpath(*module.split(".")).with_suffix(".hx").exists()

    queue = list(OPENFL_SOURCES)
    taken: list[str] = []
    texts: dict[str, str] = {}
    while queue:
        module = queue.pop(0)
        if module in taken or provided(module):
            continue
        source = source_of(module)
        if not source.exists():
            raise FileNotFoundError(f"OpenFL source missing for {module}: {source}")
        patched_copy = LIB_PATCHES.joinpath(*module.split(".")).with_suffix(".hx")
        if patched_copy.exists():
            source = patched_copy
        text = source.read_text(encoding="utf-8")
        for patched, pattern, replacement, expected, _reason in OPENFL_SOURCE_PATCHES:
            if patched == module:
                text, n = re.subn(pattern, replacement, text)
                if n != expected:
                    raise ValueError(f"OPENFL_SOURCE_PATCHES: {module} {pattern!r} matched {n} times, not {expected}")
        texts[module] = text
        taken.append(module)
        for ref in re.findall(r"\bimport\s+(openfl(?:\.\w+)+)\s*;", text):
            if ref not in names and exists(ref):
                queue.append(ref)
        package = module.rpartition(".")[0]
        moved_package = names.get(module, module).rpartition(".")[0]
        declared = set(TYPE_DECL_RE.findall(text))
        code = COMMENT_RE.sub(" ", text)
        for short in sorted(set(re.findall(r"(?<![\w.])([A-Z]\w*)\b", code)) - declared):
            ref = f"{package}.{short}"
            if ref in names or ref in taken or provided(ref) or not exists(ref):
                continue
            names[ref] = f"{moved_package}.{short}"
            queue.append(ref)
    final = sorted(names.items(), key=lambda kv: -len(kv[0]))
    for module in taken:
        text = texts[module]
        flash = names.get(module, module)
        file = target.joinpath(*flash.split(".")).with_suffix(".hx")
        file.parent.mkdir(parents=True, exist_ok=True)
        declared_here = set(TYPE_DECL_RE.findall(text))
        for declared in declared_here:
            other = file.with_name(declared + ".hx")
            if other != file and other.exists():
                other.unlink()
        if flash == module:
            own_package = module.rpartition(".")[0]
            moved = [(name.rpartition(".")[2], target_name) for name, target_name in final
                     if name.rpartition(".")[0] == own_package and target_name != name]
            imports = [f"import {target_name};" for short, target_name in moved
                       if short not in declared_here and re.search(r"(?<![\w.])" + short + r"\b", text)]
            if imports:
                text = re.sub(r"^(package\s+[\w.]*\s*;)", lambda m: m.group(1) + "\n" + "\n".join(imports), text,
                              count=1, flags=re.M)
        header = f"// Taken from OpenFL 9.5.2's {module} (MIT; tools/port_heaps_stubs.py OPENFL_SOURCES), openfl. names renamed.\n"
        package = flash.rpartition(".")[0]
        text = re.sub(r"^package\s+[\w.]*\s*;", f"package {package};", rename(text, final), count=1, flags=re.M)
        file.write_text(header + text, encoding="utf-8", newline="\n")
    return taken


def rename(text: str, renames: list[tuple[str, str]]) -> str:
    for openfl, flash in renames:
        text = re.sub(r"\b" + re.escape(openfl) + r"\b", flash, text)
    return re.sub(r"\bimport openfl\.(\w+)\.\*;", r"import flash.\1.*;", text)


COND_RE = re.compile(r"^[ \t]*#(if|elseif|else|end)\b(.*)$", re.MULTILINE)


def openfl_only(condition: str) -> bool:
    if "||" in condition:
        return False
    terms = [term.strip(" ()") for term in condition.split("&&")]
    return "openfl" in terms


def without_openfl_only(text: str) -> str:
    out: list[str] = []
    stack: list[bool] = []
    pos = 0
    for m in COND_RE.finditer(text):
        if not any(stack):
            out.append(text[pos:m.start()])
        kind, rest = m.group(1), m.group(2).strip()
        if kind == "if":
            stack.append(openfl_only(rest))
        elif kind in ("elseif", "else") and stack:
            stack[-1] = False
        elif kind == "end" and stack:
            stack.pop()
        pos = m.end()
    if not any(stack):
        out.append(text[pos:])
    return "".join(out)


def game_hxml(driver: str, build: Path | str | None, main: str, defines: tuple[str, ...] = (), *, cwd: str, game: str,
              stubs: str, runtime: str, patched: str, libraries: dict[str, str]) -> list[str]:
    from tools import port_heaps
    hxml = [f"--cwd {cwd}", f"--class-path {game}", f"--class-path {stubs}", f"--class-path {runtime}",
            "--macro allowPackage('flash')",
            f"--macro include('', true, ['flash._std.*', 'port.runtime.FlashBoot'], ['{game}'])"]
    hxml += ["--hl check.hl", "--no-output"] if build is None else [f"--main {main}", f"--hl {Path(build).as_posix()}"]
    window = "hlsdl" if driver == "sdl" else "hldx"
    hxml += [f"-D hl-ver={port_heaps.HL_VERSION}", f"-D {window}={port_heaps.HL_VERSION}", "-D heaps=2.1.0",
             "-D format=3.7.1", "-D hlopenal=1.4.0"] + (["-D dx12"] if driver == "dx12" else [])
    hxml += [f"-D {name}" for name in defines]
    if "bifrost" in defines:
        hxml.append("-D openfl_big_endian")
    hxml += [f"--class-path {libraries[name]}" for name in ("heaps", "format", window, "hlopenal")]
    return hxml + [f"--class-path {patched}"]


def type_check(target: Path, renames: list[tuple[str, str]], gen: Gen, build: Path | None = None,
               main: str = "port.engine.HeapsMain", headless: Path | None = None,
               defines: tuple[str, ...] = (), stage_only: bool = False) -> int:
    work = OUT / "runtime"
    if work.exists():
        shutil.rmtree(work)
    shutil.copytree(ENGINE / "runtime", work, ignore=shutil.ignore_patterns("flash"))
    engine_files: list[str] = []
    provided = sorted((n for n in gen.names.values() if n.startswith("openfl.")), key=len, reverse=True)
    for file in work.rglob("*.hx"):
        text = file.read_text(encoding="utf-8")
        renamed = rename(text, renames)
        module = ".".join(file.relative_to(work).with_suffix("").parts)
        probe = without_openfl_only(renamed)
        for name in provided:
            probe = probe.replace(name, "")
        found = re.search(r"\b(lime|openfl)\.", probe)
        if found and module in gen.types:
            if module not in ENGINE_STAND_INS:
                line = probe[probe.rfind("\n", 0, found.start()) + 1:probe.find("\n", found.start())].strip()
                print(f"warning: {module} becomes an OpenFL-engine stand-in because of: {line[:160]}")
            gen.names[module] = module
            renamed = gen.emit(module)
            engine_files.append(module)
        if renamed != text:
            file.write_text(renamed, encoding="utf-8", newline="\n")
    if stage_only:
        return 0
    from tools import port_heaps
    driver = os.environ.get("BH_PORT_HEAPS_DRIVER", "dx")
    if "port_smoke" in defines and "bh_port_gc_marks" not in defines and port_heaps.gc_marks_available():
        defines = defines + ("bh_port_gc_marks",)
    hxml = game_hxml(driver, build, main, defines, cwd=ENGINE.as_posix(), game=GAME.as_posix(),
                     stubs=target.as_posix(), runtime=work.as_posix(), patched=HEAPS_PATCHED.as_posix(),
                     libraries={name: port_heaps.library_path(name).as_posix() for name in ("heaps", "format",
                                                                                          "hldx", "hlsdl", "hlopenal")})
    (OUT / "check.hxml").write_text("\n".join(hxml) + "\n", encoding="utf-8")
    started = time.monotonic()
    haxe = str(ENGINE / "tools" / "haxe" / "haxe.exe")
    second = None
    if headless is not None and build is not None:
        other = list(hxml)
        other[other.index(f"--main {main}")] = "--main port.engine.HeadlessMain"
        other[other.index(f"--hl {build.as_posix()}")] = f"--hl {headless.as_posix()}"
        (OUT / "check-headless.hxml").write_text("\n".join(other) + "\n", encoding="utf-8")
        second = subprocess.Popen([haxe, str(OUT / "check-headless.hxml")], stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, text=True)
    run = subprocess.run([haxe, str(OUT / "check.hxml")], capture_output=True, text=True)
    text = run.stdout + run.stderr
    if second is not None:
        other_text, _ = second.communicate()
        print(f"headless build -> {headless}: exit {second.returncode}")
        if second.returncode != 0:
            text += "\n" + other_text
            run = subprocess.CompletedProcess(run.args, run.returncode or second.returncode, run.stdout, run.stderr)
    (OUT / "check.txt").write_text(text, encoding="utf-8")
    errors = [line for line in text.splitlines() if ": " in line and re.search(r":\d+: (characters?|lines)", line)]
    kinds = Counter(re.sub(r"[\"'][^\"']*[\"']|\b[A-Z]\w*(\.\w+)*", "X", line.split(" : ", 1)[-1])[:80]
                    for line in errors)
    files = Counter(line.split(":")[0] for line in errors)
    print(f"{len(engine_files)} OpenFL-engine runtime modules as stand-ins: {', '.join(sorted(engine_files))}")
    print(f"type-check in {time.monotonic() - started:.1f} s, exit {run.returncode}: {len(errors)} error lines "
          f"(haxe stops at the first failing pass) -> {OUT / 'check.txt'}")
    for kind, n in kinds.most_common(12):
        print(f"  {n:5} {kind}")
    for file, n in files.most_common(6):
        print(f"  {n:5} in {file}")
    return run.returncode


def overlay_own(target: Path) -> int:
    overlaid = 0
    for path in sorted(OWN_SRC.rglob("*.hx")) if OWN_SRC.exists() else []:
        file = target / path.relative_to(OWN_SRC)
        file.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, file)
        overlaid += 1
    patch_heaps()
    return overlaid


HEAPS_PATCHES: dict[str, list[tuple[str, str]]] = {
    "h3d/impl/DirectXDriver.hx": [
        ("public var layouts : Map<Int, Layout>;", "public var layouts : port.engine.NativeIntMap<Layout>;"),
        ("var shaders : Map<Int,CompiledShader>;", "var shaders : port.engine.NativeIntMap<CompiledShader>;"),
        ("var depthStates : Map<Int,{", "var depthStates : port.engine.NativeIntMap<{"),
        ("var blendStates : Map<Int,BlendState>;", "var blendStates : port.engine.NativeIntMap<BlendState>;"),
        ("var rasterStates : Map<Int,RasterState>;", "var rasterStates : port.engine.NativeIntMap<RasterState>;"),
        ("var samplerStates : Map<Int,SamplerState>;", "var samplerStates : port.engine.NativeIntMap<SamplerState>;"),
        ("s.layouts = [];", "s.layouts = new port.engine.NativeIntMap();"),
        ("shaders = new Map();", "shaders = new port.engine.NativeIntMap();"),
        ("depthStates = new Map();", "depthStates = new port.engine.NativeIntMap();"),
        ("blendStates = new Map();", "blendStates = new port.engine.NativeIntMap();"),
        ("rasterStates = new Map();", "rasterStates = new port.engine.NativeIntMap();"),
        ("samplerStates = new Map();", "samplerStates = new port.engine.NativeIntMap();"),
        ("s.layouts = new Map();", "s.layouts = new port.engine.NativeIntMap();"),
        ("var tmp = dx.Driver.createTexture2d(desc);",
         "var tmp = port.engine.StagingPool.get(desc, hxd.Pixels.calcStride(1, tex.format));"),
        ("\t\ttmp.unmap(0);\n\t\ttmp.release();\n\t\treturn pixels;",
         "\t\ttmp.unmap(0);\n\t\tport.engine.StagingPool.put(tmp);\n\t\treturn pixels;"),
        ("var res = b.flags.has(UniformBuffer) ? dx.Driver.createBuffer(size, Dynamic, ConstantBuffer, CpuWrite, None, 0, null) :",
         "var res = b.flags.has(UniformBuffer) ? dx.Driver.createBuffer(size, Dynamic, ConstantBuffer, CpuWrite, None, 0, null) :"
         " b.flags.has(Dynamic) && port.engine.StagingPool.dynamicBuffers ? dx.Driver.createBuffer(size, Dynamic,"
         " b.flags.has(IndexBuffer) ? IndexBuffer : VertexBuffer, CpuWrite, None, 0, null) :"),
        ("\t\tupdateBuffer(b.vbuf, data, startVertex * b.format.strideBytes, vertexCount * b.format.strideBytes);",
         "\t\tif( b.flags.has(Dynamic) && port.engine.StagingPool.dynamicBuffers ) {\n"
         "\t\t\tport.engine.StagingPool.mapBuffer(b.vbuf, data, startVertex * b.format.strideBytes, vertexCount * b.format.strideBytes);\n"
         "\t\t\treturn;\n\t\t}\n"
         "\t\tupdateBuffer(b.vbuf, data, startVertex * b.format.strideBytes, vertexCount * b.format.strideBytes);"),
        ("\t\tupdateBuffer(b.vbuf, @:privateAccess buf.b.offset(bufPos), startVertex * b.format.strideBytes, vertexCount * b.format.strideBytes);",
         "\t\tif( b.flags.has(Dynamic) && port.engine.StagingPool.dynamicBuffers ) {\n"
         "\t\t\tport.engine.StagingPool.mapBuffer(b.vbuf, @:privateAccess buf.b.offset(bufPos), startVertex * b.format.strideBytes, vertexCount * b.format.strideBytes);\n"
         "\t\t\treturn;\n\t\t}\n"
         "\t\tupdateBuffer(b.vbuf, @:privateAccess buf.b.offset(bufPos), startVertex * b.format.strideBytes, vertexCount * b.format.strideBytes);"),
        ("\t\ttry\n\t\t\tdriver = Driver.create(window, backBufferFormat, getDriverFlags())",
         "\t\tport.engine.GpuAdapter.choose();\n\t\ttry\n\t\t\tdriver = Driver.create(window, backBufferFormat, getDriverFlags())"),
        ("\toverride function begin(frame:Int) {",
         "\t@:hlNative(\"bhsound\", \"gpu_trim\") static function portGpuTrim(d:dx.Driver.DriverInstance):Int return 0;\n\n"
         "\t@:hlNative(\"bhsound\", \"gpu_flush\") static function portGpuFlush(d:dx.Driver.DriverInstance):Int return 0;\n\n"
         "\tfunction portFlush():Int return portGpuFlush(driver);\n\n"
         "\tfunction portTrim():Int {\n"
         "\t\tvar done = portGpuTrim(driver);\n"
         "\t\tDriver.iaSetPrimitiveTopology(TriangleList); // set once at the start; ClearState undid it\n"
         "\t\tcurrentShader = null;\n\t\tcurrentIndex = null;\n\t\tcurrentDepth = null;\n\t\tcurrentLayout = null;\n"
         "\t\tfor( i in 0...16 ) {\n\t\t\tcurrentTargets[i] = null;\n\t\t\tcurrentTargetResources[i] = null;\n"
         "\t\t\tcurrentVBuffers[i] = null;\n\t\t}\n"
         "\t\tvertexShader = new PipelineState(Vertex);\n\t\tpixelShader = new PipelineState(Pixel);\n"
         "\t\tcurrentMaterialBits = -1;\n\t\tcurrentStencilMaskBits = -1;\n\t\tcurrentStencilOpBits = -1;\n"
         "\t\tcurrentColorMask = -1;\n\t\tcurrentColorMaskIndex = -1;\n"
         "\t\tcurrentDepthState = null;\n\t\tcurrentBlendState = null;\n\t\tcurrentRasterState = null;\n"
         "\t\tcurTexture = null;\n\t\thasScissor = false;\n"
         "\t\tsetRenderTarget(null);\n"
         "\t\treturn done;\n\t}\n\n"
         "\toverride function begin(frame:Int) {"),
    ],
    "hxd/System.hl.hx": [
        ("\tstatic function mainLoop() {\n", "\tstatic function mainLoop() {\n\t\tvar portEvents = haxe.Timer.stamp();\n"),
        ("\t\t// loop\n", "\t\tport.engine.LoopTimes.events += haxe.Timer.stamp() - portEvents;\n\t\t// loop\n"),
        ("\t\t\tcur.driver.present();\n",
         "\t\t\tvar portPresent = haxe.Timer.stamp();\n\t\t\tcur.driver.present();\n"
         "\t\t\tport.engine.LoopTimes.addPresent(haxe.Timer.stamp() - portPresent);\n"),
        ("\t\t\t\tmainThread.events.progress();\n",
         "\t\t\t\tvar portThread = haxe.Timer.stamp();\n\t\t\t\tmainThread.events.progress();\n"
         "\t\t\t\tport.engine.LoopTimes.threadEvents += haxe.Timer.stamp() - portThread;\n"),
    ],
    "hxd/App.hx": [
        ("\t\tsevents.checkEvents();\n",
         "\t\tvar portScene = haxe.Timer.stamp();\n\t\tsevents.checkEvents();\n"
         "\t\tport.engine.LoopTimes.sceneEvents += haxe.Timer.stamp() - portScene;\n"),
        ("\t\tengine.render(this);\n",
         "\t\tvar portRender = haxe.Timer.stamp();\n\t\tengine.render(this);\n"
         "\t\tport.engine.LoopTimes.engineRender += haxe.Timer.stamp() - portRender;\n"),
    ],
    "hxd/Pad.hx": [
        ("GameController.detect(onDetect);",
         "var portPads = haxe.Timer.stamp();\n\t\tGameController.detect(onDetect);\n"
         "\t\tport.engine.LoopTimes.pads += haxe.Timer.stamp() - portPads;"),
        ("\t\t\tp.d.update();",
         "\t\t\tvar portPad = haxe.Timer.stamp();\n\t\t\tp.d.update();\n"
         "\t\t\tport.engine.LoopTimes.pads += haxe.Timer.stamp() - portPad;"),
    ],
    "h3d/mat/Texture.hx": [
        ("\tvar bits : Int;\n", "\tvar bits : Int;\n\tvar portMemIndex : Int = -1;\n"),
    ],
    "h3d/impl/MemoryManager.hx": [
        ("\t\tif( !textures.remove(t) ) return;\n\t\tdriver.disposeTexture(t);",
         "\t\tvar i = t.portMemIndex;\n"
         "\t\tif( i < 0 || i >= textures.length || textures[i] != t ) return;\n"
         "\t\tvar last = textures.pop();\n"
         "\t\tif( last != t ) {\n\t\t\ttextures[i] = last;\n\t\t\tlast.portMemIndex = i;\n\t\t}\n"
         "\t\tt.portMemIndex = -1;\n"
         "\t\tif( t.isDepth() && Sys.getEnv(\"BH_PORT_DEPTH_DISPOSE\") != \"0\" ) driver.disposeDepthBuffer(t) "
         "else driver.disposeTexture(t);"),
        ("\t\ttextures.push(t);\n\t\ttexMemory += memSize(t);",
         "\t\tt.portMemIndex = textures.length;\n\t\ttextures.push(t);\n\t\ttexMemory += memSize(t);"),
        ("\t\ttextures.sort(sortByLRU);\n",
         "\t\ttextures.sort(sortByLRU);\n\t\tfor( i in 0...textures.length ) textures[i].portMemIndex = i;\n"),
        ("\t\tfor( t in textures.copy() )\n\t\t\tt.dispose();",
         "\t\tfor( t in textures.copy() )\n\t\t\tt.dispose();\n\t\tfor( t in textures ) t.portMemIndex = -1;"),
    ],
}


_DS4_LAYOUT = ("a:b1,b:b2,back:b13,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b12,leftshoulder:b4,leftstick:b10,"
               "lefttrigger:a3,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b11,righttrigger:a4,rightx:a2,righty:a5,"
               "start:b9,x:b0,y:b3,")
LIBRARY_PATCHES: dict[str, dict[str, list[tuple[str, str]]]] = {
    "hldx": {
        "dx/GameController.hx": [
            ('\t\t"03000000790000001100000000000000,Retrolink SNES Controller,',
             f'\t\t"030000004c050000e60c000000000000,PS5 Controller,{_DS4_LAYOUT}", // DualSense (port)\n'
             f'\t\t"030000004c050000f20d000000000000,PS5 Controller,{_DS4_LAYOUT}", // DualSense Edge (port)\n'
             '\t\t"03000000790000001100000000000000,Retrolink SNES Controller,'),
            *[(f'\t\t"030000004c050000{pid}000000000000,PS4 Controller,a:b1,b:b2,back:b8,',
               f'\t\t"030000004c050000{pid}000000000000,PS4 Controller,a:b1,b:b2,back:b13,') for pid in ("c405", "cc09", "a00b")],
        ],
    },
}


HEAPS_PATCHED = OUT / "heaps-patched"


def patch_heaps(target: Path = HEAPS_PATCHED) -> None:
    from tools import port_heaps
    heaps = port_heaps.library_path("heaps")
    for module, edits in HEAPS_PATCHES.items():
        text = (heaps / module).read_text(encoding="utf-8")
        for old, new in edits:
            if old not in text:
                raise RuntimeError(f"HEAPS_PATCHES: {module} has no {old!r} (Heaps changed?)")
            text = text.replace(old, new)
        out = target / module
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(f"// Patched copy of Heaps 2.1.0's {module} (MIT; tools/port_heaps_stubs.py HEAPS_PATCHES).\n"
                       + text, encoding="utf-8", newline="\n")
    for library, modules in LIBRARY_PATCHES.items():
        folder = port_heaps.library_path(library)
        for module, edits in modules.items():
            text = (folder / module).read_text(encoding="utf-8")
            for old, new in edits:
                if text.count(old) != 1:
                    raise RuntimeError(f"LIBRARY_PATCHES: {library} {module} has {text.count(old)} of {old!r}, not 1")
                text = text.replace(old, new)
            out = target / module
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(f"// Patched copy of {library}'s {module} (MIT; tools/port_heaps_stubs.py LIBRARY_PATCHES).\n"
                           + text, encoding="utf-8", newline="\n")
    std = ROOT / "port" / "engine-heaps" / "std"
    for source in std.rglob("*.hx"):
        out = target / source.relative_to(std)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(source.read_bytes())


def test(names: list[str] | None = None) -> int:
    from tools import port_heaps
    tests = sorted((ROOT / "data" / "engine-heaps-tests").glob("*Test.hx"))
    tests.append(ROOT / "data" / "port-tests" / "RuntimeServicesTest.hx")
    if names:
        tests = [t for t in tests if t.stem in names or t.stem[:-4] in names]
    stale = runtime_stale()
    if stale:
        print(f"port/runtime is newer than the suites' copy ({stale}): staging the stand-ins and the runtime again")
        started = time.monotonic()
        if stubs(check=False, stage_only=True) != 0:
            return 1
        print(f"staged in {time.monotonic() - started:.1f} s")
    if (OUT / "stubs").exists():
        overlay_own(OUT / "stubs")
    failed = 0
    for path in tests:
        out = OUT / f"{path.stem}.hl"
        args = [str(ENGINE / "tools" / "haxe" / "haxe.exe"), "--class-path", str(path.parent), "--class-path",
                str(OUT / "stubs"), "--class-path", str(ROOT / "port" / "engine-heaps" / "std"),
                "--macro", "allowPackage('flash')", "--main", path.stem, "--hl", str(out),
                "-D", "heaps"]
        source = path.read_text(encoding="utf-8")
        args += ["-D", f"hl-ver={port_heaps.HL_VERSION}", "-D", "heaps=2.1.0", "-D", "format=3.7.1",
                 "-D", "openfl_big_endian"]
        for name in ("heaps", "format"):
            args[5:5] = ["--class-path", str(port_heaps.library_path(name))]
        if "@bhRawGame" in source:
            args[5:5] = ["--class-path", str(GAME)]
        if (OUT / "runtime").exists():
            args[5:5] = ["--class-path", str(OUT / "runtime")]
        build = subprocess.run(args, capture_output=True, text=True)
        if build.returncode != 0:
            print(f"{path.stem}: compile failed\n{(build.stdout + build.stderr)[-3000:]}")
            failed += 1
            continue
        extra = [str(OUT / f"{path.stem}-work")] if path.stem == "RuntimeServicesTest" else []
        if extra:
            shutil.rmtree(extra[0], ignore_errors=True)
        run = subprocess.run([str(port_heaps.HASHLINK / "hl.exe"), str(out)] + extra, capture_output=True, text=True,
                             env=dict(os.environ, BH_PORT_TESTS_DIR=str(path.parent)),
                             timeout=60)
        print(f"{path.stem}: {(run.stdout + run.stderr).strip()[-2000:]}")
        failed += run.returncode != 0
        if extra and port_heaps.game_libhl() != port_heaps.HASHLINK / "libhl.dll":
            suite_hl = suite_hashlink()
            shutil.rmtree(extra[0], ignore_errors=True)
            run = subprocess.run([str(suite_hl / "hl.exe"), str(out)] + extra, capture_output=True, text=True,
                                 env=dict(os.environ, BH_PORT_TESTS_DIR=str(path.parent)), timeout=60)
            print(f"{path.stem} on the game's libhl: {(run.stdout + run.stderr).strip()[-2000:]}")
            failed += run.returncode != 0
    return 1 if failed else 0


def suite_hashlink() -> Path:
    from tools import port_heaps
    folder = port_heaps.BUILD / "run-suite"
    folder.mkdir(parents=True, exist_ok=True)
    for source in [*port_heaps.HASHLINK.iterdir(), port_heaps.game_libhl()]:
        if source.suffix.lower() not in (".exe", ".dll", ".hdll") or source == port_heaps.HASHLINK / "libhl.dll":
            continue
        target = folder / source.name
        if not target.exists() or target.stat().st_size != source.stat().st_size \
                or target.stat().st_mtime < source.stat().st_mtime:
            shutil.copy2(source, target)
    return folder


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=("dump", "stubs", "test"))
    parser.add_argument("suites", nargs="*", help="test: only these suites (BitmapData or BitmapDataTest)")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--build", type=Path, help="stubs: compile the Heaps engine's game.hl here (absolute path)")
    parser.add_argument("--headless", action="store_true",
                        help="stubs --build: the game without a window (port.engine.HeadlessMain; diagnostics)")
    parser.add_argument("--both", action="store_true",
                        help="stubs --build DIR/game.hl: also DIR/headless.hl, compiled at the same time")
    parser.add_argument("--define", action="append", default=[],
                        help="stubs --build: a Haxe define for the game (port_smoke: the TEST build's smoke driver)")
    parser.add_argument("--game", type=Path,
                        help=f"the converted game's folder (default {GAME}; Bifrost's export with --define bifrost)")
    parser.add_argument("--openfl-engine", type=Path,
                        help=f"the OpenFL engine export the stand-ins come from (default {ENGINE})")
    args = parser.parse_args(argv)
    with work_lock():
        return run_command(args)


def _pid_alive(pid: int) -> bool:
    if sys.platform != "win32":
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False
    out = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/NH"], capture_output=True, text=True).stdout
    return str(pid) in out


_LOCK_DEPTH = 0


@contextlib.contextmanager
def work_lock(timeout: float = 1200):
    global _LOCK_DEPTH
    if _LOCK_DEPTH:
        _LOCK_DEPTH += 1
        try:
            yield
        finally:
            _LOCK_DEPTH -= 1
        return
    OUT.mkdir(parents=True, exist_ok=True)
    lock = OUT / ".busy"
    waited = False
    end = time.monotonic() + timeout
    while True:
        try:
            fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(fd, str(os.getpid()).encode())
            os.close(fd)
            break
        except FileExistsError:
            try:
                holder = int(lock.read_text().strip() or 0)
            except (OSError, ValueError):
                holder = 0
            if holder and not _pid_alive(holder):
                lock.unlink(missing_ok=True)
                continue
            if time.monotonic() > end:
                raise SystemExit(f"{lock} is held by pid {holder} for over {timeout:.0f} s")
            if not waited:
                print(f"port_heaps_stubs: waiting for pid {holder} (another stubs/test run)", flush=True)
                waited = True
            time.sleep(2)
    _LOCK_DEPTH = 1
    try:
        yield
    finally:
        _LOCK_DEPTH = 0
        lock.unlink(missing_ok=True)


def run_command(args: argparse.Namespace) -> int:
    global GAME, ENGINE, OPENFL_SRC, LIB_PATCHES
    if args.game:
        GAME = args.game.resolve()
    if args.openfl_engine:
        ENGINE = args.openfl_engine.resolve()
        OPENFL_SRC = ENGINE / "lib" / "openfl" / "src"
        LIB_PATCHES = ENGINE / "lib-patches"
    if args.command == "dump":
        return dump()
    if args.command == "test":
        return test(args.suites)
    build = args.build.resolve() if args.build else None
    return stubs(args.check, build, "port.engine.HeadlessMain" if args.headless else "port.engine.HeapsMain",
                 build.parent / "headless.hl" if args.both and build and not args.headless else None,
                 tuple(args.define))


if __name__ == "__main__":
    sys.exit(main())
