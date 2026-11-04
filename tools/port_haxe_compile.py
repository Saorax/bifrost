from __future__ import annotations

import argparse
import contextlib
from collections import Counter
import copy
from decimal import Decimal, InvalidOperation
import hashlib
import json
import os
from pathlib import Path
import pickle
import re
import shutil
import struct
import subprocess
import time
import sys
import tempfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
HAXE = ROOT / ".tools" / "haxe" / "haxe.exe"
RUNTIME = ROOT / "port" / "runtime" / "haxe"
RUNTIME_FLASH = ROOT / "port" / "runtime" / "haxe-flash"
RUNTIME_HL = ROOT / "port" / "runtime" / "haxe-hl"
RUNTIME_PRIVATE = ROOT / "data" / "runtime"
GENERATED = ROOT / "build" / "port-haxe" / "10.11" / "src"
NATIVE_CONVERTED = ROOT / "build" / "port-haxe" / "10.11-native" / "converted"
NATIVE_GENERATED = ROOT / "build" / "port-haxe" / "10.11-native" / "src"
NATIVE_FIXES_KEY_FILE = ".native-fixes-key"
PORT_BUILD = ROOT / "build" / "port-haxe" / "10.11"
FULL_FLASH_SWF = PORT_BUILD / "BrawlhallaAir.haxe.swf"
RAW = True
BIFROST = False
BIFROST_TREE = ROOT / "build" / "bifrost" / "root"
TREE_KIND_FILE = "PORT_TREE_KIND.txt"
VERSION = "10.11"


def symbols_path() -> Path:
    return ROOT / "client" / "symbols" / f"{VERSION}.json"


def scripts_path() -> Path:
    return ROOT / "src" / "as3" / VERSION / "scripts"


def base_swf() -> Path:
    from tools import compare_methods

    if VERSION == "10.11":
        return compare_methods.base_swf()
    work = ROOT / "build" / "as3" / VERSION / "ffdec"
    aliased = work / "aliased.swf"
    return aliased if aliased.exists() else work / "renamed.swf"


def use_version(version: str) -> None:
    global VERSION, GENERATED, NATIVE_CONVERTED, NATIVE_GENERATED, PORT_BUILD, FULL_FLASH_SWF
    global FULL_FLASH_REPORT, FULL_FLASH_MARKDOWN, ORIGINAL_COMPARE_CACHE
    VERSION = version
    GENERATED = ROOT / "build" / "port-haxe" / version / "src"
    NATIVE_CONVERTED = ROOT / "build" / "port-haxe" / f"{version}-native" / "converted"
    NATIVE_GENERATED = ROOT / "build" / "port-haxe" / f"{version}-native" / "src"
    PORT_BUILD = ROOT / "build" / "port-haxe" / version
    FULL_FLASH_SWF = PORT_BUILD / "BrawlhallaAir.haxe.swf"
    FULL_FLASH_REPORT = PORT_BUILD / "method-compare.json"
    FULL_FLASH_MARKDOWN = PORT_BUILD / "method-compare.md"
    ORIGINAL_COMPARE_CACHE = PORT_BUILD / "original-compare-cache.pickle"
    as3_to_haxe.use_version(version)
FULL_FLASH_REPORT = PORT_BUILD / "method-compare.json"
FULL_FLASH_MARKDOWN = PORT_BUILD / "method-compare.md"
ORIGINAL_COMPARE_CACHE = PORT_BUILD / "original-compare-cache.pickle"
ORIGINAL_FACT_NAMES = (
    "SHADOWED", "CONSTS", "SLOT_TYPES", "CLASS_SLOT_TYPES", "CLASS_READ_SLOT_TYPES",
    "CLASS_INSTANCE_LITERAL_SLOTS",
    "ENUM_INSTANCE_CLASSES",
    "READ_SLOT_TYPES", "CTOR_PARAM_TYPES", "METHOD_PARAM_TYPES", "OWNER_METHOD_PARAM_TYPES",
    "OWNER_METHOD_FIXED_ARITIES", "METHOD_RETURNS",
    "CONSTRUCTIBLE_CLASSES", "MAP_BACKING_TYPES", "INTERFACE_METHOD_CALLS",
    "INTERFACE_METHOD_RETURNS", "PRIVATE_MEMBER_LOCALS", "PUBLIC_MEMBER_LOCALS",
    "FILE_PRIVATE_CLASS_LOCALS", "STATIC_TRAITS", "INSTANCE_TRAITS", "INERT_CLASSES",
)
GENERATED_STDLIB_DIRS = {Path("haxe")}
GENERATED_STDLIB_KEPT_DIRS = {Path("haxe") / "xml"}
GENERATED_STDLIB_FILES = {
    Path("EReg.hx"),
    Path("Type.hx"),
    Path("flash") / "Boot.hx",
    Path("flash") / "Lib.hx",
}
FULL_INCLUDE_MACRO = "include('', true, ['flash._std.*'], ['src'])"
FLASH_KEEP_MACRO = ("keep(null, ['haxe.ds.BalancedTree', 'haxe.ds.EnumValueMap', 'haxe.ds.StringMap', "
                    "'haxe.ds.IntMap', 'haxe.ds.ObjectMap'], false)")
ERROR_RE = re.compile(r"^(?P<file>.*?\.hx):(?P<line>\d+): characters? [^:]+ : (?P<message>.*)$")
PORT_CLASS_RE = re.compile(r"^class_(\d+)$")

sys.path.insert(0, str(ROOT))
from tools import as3_to_haxe


REPRESENTATIVE_AS3 = r"""package port.check {
   public class Sample {
      public function Sample() {}
      public function run(value:Object, map:Object, key:String, values:Array) : void {
         var text:String = value as String;
         var ok:Boolean = value is Array;
         delete map[key];
         delete value.token;
         if(!/^\d+$/.test(text)) {
            text = text.replace(/\r/g, "");
         }
         for each(var item:String in values) {
            text = item;
         }
         add(<HardCollision X1={1.0} Kind="solid"/>);
      }
      public function add(value:Object) : void {}
   }
}
"""


MAIN_HX = """class Main {
    static function main() {
        var sample = new port.check.Sample();
        sample.run("12", {}, "key", ["a", "b"]);
    }
}
"""


def require_haxe() -> None:
    if not HAXE.exists():
        raise FileNotFoundError(f"Missing pinned Haxe compiler: {HAXE}. Run python tools/setup_haxe.py")
    version = subprocess.check_output([str(HAXE), "--version"], text=True).strip()
    if version != "4.3.7":
        raise ValueError(f"Expected Haxe 4.3.7, found {version}")


def copy_runtime(target: Path) -> None:
    for base in (RUNTIME, RUNTIME_PRIVATE):
        for source in sorted(base.rglob("*.hx")):
            rel = source.relative_to(base)
            out = target / rel
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(source.read_text(encoding="utf-8"), encoding="utf-8", newline="\n")


def should_skip_generated_source(rel: Path) -> bool:
    if rel.parent in GENERATED_STDLIB_KEPT_DIRS:
        return False
    if rel.parts and Path(rel.parts[0]) in GENERATED_STDLIB_DIRS:
        return True
    return rel in GENERATED_STDLIB_FILES


@contextlib.contextmanager
def staged_text_cache(root: Path):
    root_key = os.path.normcase(os.path.abspath(root)) + os.sep
    cache: dict[str, str] = {}
    original_read, original_write = Path.read_text, Path.write_text

    def key_of(path: Path) -> str | None:
        key = os.path.normcase(os.path.abspath(path))
        return key if key.startswith(root_key) else None

    def read_text(self, encoding=None, errors=None, newline=None):
        key = key_of(self)
        if key is not None and newline is None and key in cache:
            return cache[key]
        return original_read(self, encoding=encoding, errors=errors, newline=newline)

    def write_text(self, data, encoding=None, errors=None, newline=None):
        written = original_write(self, data, encoding=encoding, errors=errors, newline=newline)
        key = key_of(self)
        if key is not None:
            cache[key] = data.replace("\r\n", "\n").replace("\r", "\n")
        return written

    Path.read_text, Path.write_text = read_text, write_text
    try:
        yield
    finally:
        Path.read_text, Path.write_text = original_read, original_write


def copy_filtered_generated_tree(target: Path, generated: Path | None = None) -> int:
    generated = generated or GENERATED
    if not generated.exists():
        raise FileNotFoundError(f"Missing generated Haxe tree: {generated}. Run python tools/as3_to_haxe.py convert")
    copied = 0
    for source in sorted(generated.rglob("*.hx")):
        rel = source.relative_to(generated)
        if should_skip_generated_source(rel):
            continue
        out = target / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(source.read_text(encoding="utf-8"), encoding="utf-8", newline="\n")
        copied += 1
    copy_runtime(target)
    return copied


PLAIN_FIELD_EXTERNS = True
_FLASH_PROPERTY_RE = re.compile(
    r"@:flash\.property\s+((?:@:\w+(?:\([^)]*\))?\s+)*)((?:static\s+)?)var\s+(\w+)\((get,set|get,never)\)(\s*:)")


def plain_field_extern(text: str) -> str:
    def plain(match: re.Match) -> str:
        access = "" if match.group(4) == "get,set" else "(default,null)"
        return f"{match.group(1)}{match.group(2)}var {match.group(3)}{access}{match.group(5)}"
    return _FLASH_PROPERTY_RE.sub(plain, text)


def write_plain_field_externs(target: Path) -> int:
    if not PLAIN_FIELD_EXTERNS:
        return 0
    std = HAXE.parent / "std" / "flash"
    written = 0
    for source in sorted(std.rglob("*.hx")):
        rel = source.relative_to(std.parent)
        if rel.parts[1] == "_std":
            continue
        out = target / rel
        if out.exists():
            continue
        text = source.read_text(encoding="utf-8")
        if "@:flash.property" not in text:
            continue
        plain = plain_field_extern(text)
        if plain == text:
            continue
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(plain, encoding="utf-8", newline="\n")
        written += 1
    return written


def extern_from_stub(text: str) -> str:
    out: list[str] = []
    i = 0
    match = re.search(r"^(\s*(?:@:[^\n]*\n\s*)*)(class|interface)\b", text, re.M)
    if match is None or re.search(r"\bextern\s+(class|interface)\b", text):
        return text
    out.append(text[:match.start(2)] + "extern ")
    i = match.start(2)
    open_brace = text.index("{", i)
    out.append(text[i:open_brace + 1])
    i = open_brace + 1
    depth = 1
    member: list[str] = []
    while i < len(text) and depth > 0:
        ch = text[i]
        if ch == "{" and depth == 1:
            close = i
            nested = 0
            while close < len(text):
                if text[close] == "{":
                    nested += 1
                elif text[close] == "}":
                    nested -= 1
                    if nested == 0:
                        break
                close += 1
            out.append("".join(member).rstrip() + ";")
            member = []
            i = close + 1
            continue
        if ch == ";" and depth == 1:
            decl = "".join(member)
            decl = re.sub(r"(\bvar\s+\w+(?:\([^)]*\))?\s*:[^=;]+?)\s*=.*$", r"\1", decl, flags=re.S)
            out.append(decl + ";")
            member = []
            i += 1
            continue
        if ch == "}":
            depth -= 1
            if depth == 0:
                out.append("".join(member))
                out.append("}")
                out.append(text[i + 1:])
                break
        member.append(ch)
        i += 1
    extern = "".join(out)
    properties = re.findall(r"\bvar\s+(\w+)\s*\(\s*\w+\s*,\s*\w+\s*\)\s*:", extern)
    extern = re.sub(r"\bvar\s+(\w+)\s*\(\s*\w+\s*,\s*\w+\s*\)\s*:", r"var \1:", extern)
    for name in properties:
        extern = re.sub(rf"^[ \t]*(?:(?:public|private|static|inline|override)\s+)*function\s+(?:get|set)_{name}\b"
                        rf"[^;]*;[ \t]*\n?", "", extern, flags=re.M)
    return extern


def write_flash_native_externs(target: Path) -> tuple[int, int]:
    std = HAXE.parent / "std"
    removed = externalized = 0
    for source in sorted((RUNTIME / "flash").rglob("*.hx")):
        rel = source.relative_to(RUNTIME)
        staged = target / rel
        if not staged.exists():
            continue
        if (std / rel).exists():
            extern = plain_field_extern((std / rel).read_text(encoding="utf-8"))
            stub = staged.read_text(encoding="utf-8")
            missing = [
                (name, kind) for name, kind in re.findall(r"public\s+static\s+var\s+(\w+)\s*:\s*(\w+)", stub)
                if not re.search(rf"\b(?:var|final)\s+{name}\b", extern)
            ]
            if missing:
                close = extern.rindex("}")
                added = "".join(f"\tstatic var {name}(default,never) : {kind};\n" for name, kind in missing)
                extern = extern[:close] + added + extern[close:]
            staged.write_text(extern, encoding="utf-8", newline="\n")
            removed += 1
            continue
        text = staged.read_text(encoding="utf-8")
        extern = extern_from_stub(text)
        if extern != text:
            staged.write_text(extern, encoding="utf-8", newline="\n")
            externalized += 1
    return removed, externalized


def write_representative_project(target: Path) -> None:
    copy_runtime(target)
    converted, stats = as3_to_haxe.convert_text(REPRESENTATIVE_AS3)
    if stats.unsupported:
        raise ValueError(f"Representative AS3 still has unsupported constructs after conversion: {stats.unsupported}")
    sample = target / "port" / "check" / "Sample.hx"
    sample.parent.mkdir(parents=True, exist_ok=True)
    sample.write_text(converted, encoding="utf-8", newline="\n")
    (target / "Main.hx").write_text(MAIN_HX, encoding="utf-8", newline="\n")


def representative_compile() -> None:
    require_haxe()
    with tempfile.TemporaryDirectory(prefix="bh-port-haxe-") as td:
        work = Path(td)
        write_representative_project(work)
        subprocess.check_call([
            str(HAXE),
            "--cwd", str(work),
            "--class-path", str(work),
            "--main", "Main",
            "--interp",
        ])


def haxe_error_summary(output: str) -> str:
    counts: Counter[str] = Counter()
    first: dict[str, str] = {}
    for line in output.splitlines():
        match = ERROR_RE.match(line)
        if not match:
            continue
        message = match.group("message").strip()
        counts[message] += 1
        first.setdefault(message, line)
    if not counts:
        return "Haxe errors: no parsable diagnostics"
    lines = ["Haxe error census:"]
    for message, count in counts.most_common(12):
        lines.append(f"  {count}: {message}")
        lines.append(f"     first: {first[message]}")
    return "\n".join(lines)


def load_port_haxe_aliases(version: str | None = None) -> dict[str, str]:
    aliases: dict[str, str] = {}
    symbols = ROOT / "client" / "symbols" / f"{version or VERSION}.json"
    if symbols.exists():
        data = json.loads(symbols.read_text(encoding="utf-8"))
        for block in data.get("blocks", []):
            for row in block.get("classes", []):
                renamed = row[2]
                if PORT_CLASS_RE.fullmatch(renamed):
                    aliases[f"Class_{renamed.split('_', 1)[1]}"] = renamed
    readable = ROOT / "client" / "symbols" / f"{version or VERSION}.aliases.json"
    if readable.exists():
        data = json.loads(readable.read_text(encoding="utf-8"))
        for item in data.get("aliases", []):
            alias = item.get("alias")
            renamed = item.get("renamed")
            if alias and renamed:
                aliases[alias] = renamed.rsplit(".", 1)[-1]
    if "Xml" in aliases:
        aliases["XML"] = aliases["Xml"]
    aliases["Random_bhsrc"] = "Random"
    if "Xml" in aliases:
        aliases["LegacyXml"] = aliases["Xml"]
    aliases.update({"LegacyParser": "Parser", "LegacyPrinter": "Printer",
                    "LegacyXmlParserException": "XmlParserException"})
    return aliases


COMPILED_ONLY_ALIASES = {"LegacyXml", "LegacyParser", "LegacyPrinter", "LegacyXmlParserException"}


METHOD_KEY_RE = re.compile(r"^(?P<class>.+?)/(?:(?P<init>iinit|cinit)|(?P<side>[is])/(?P<kind>method|getter|setter) (?P<name>.+))$")
SCRIPT_KEY_RE = re.compile(r"^script (?P<class>.+?)/(?:init|function|method|getter|setter)")
PORT_SURFACE_PREFIXES = ("bh.mods.", "bh.platform.", "port.runtime.", "flash.")
HAXE_SURFACE_PREFIXES = ("haxe.", "flash.Boot", "package_")
HAXE_ROOT_SURFACE = {
    "ArgumentError",
    "Date",
    "Dynamic",
    "Error",
    "JSON",
    "Reflect",
    "RegExp",
    "Std",
    "StringBuf",
    "StringTools",
    "_UInt.UInt_Impl_",
    "_Vector.Vector_Impl_",
    "_XMLList.XMLList_Impl_",
}

PACKAGE_LOCAL_QNAME_CASE_FIXES = {
    "package_1.Class_253": "package_1.class_253",
    "package_1.Class_254": "package_1.class_254",
    "package_2.Class_263": "package_2.class_263",
    "package_2.Class_264": "package_2.class_264",
    "package_3.Class_636": "package_3.class_636",
}

STRING_DEFAULT_SIGNATURE_REPAIRS = {
    "ANE_DnaManager/s/method ReportNewsAction": "string:'{}'",
    "ANE_DnaManager/s/method ReportNewsImpression": "string:'{}'",
    "ANE_DnaManager/s/method SendProgressionEvent": "string:'{}'",
    "ANE_DnaManager/s/method SendStartContextEvent": "string:'{}'",
    "ANE_DnaManager/s/method SendStopContextEvent": "string:'{}'",
    "SoundEngineExtension/s/method RegisterGameObj": "string:''",
}


def string_default_signature_replacements(original: dict[str, dict],
                                          compiled: dict[str, dict]) -> dict[str, dict]:
    replacements: dict[str, dict] = {}
    for key, default in STRING_DEFAULT_SIGNATURE_REPAIRS.items():
        orig = original.get(key)
        comp = compiled.get(key)
        if orig is None or comp is None:
            raise ValueError(f"{key}: String-default repair target is missing")
        old_sig, new_sig = orig["sig"], comp["sig"]
        if (old_sig["params"] != new_sig["params"]
                or old_sig["ret"] != new_sig["ret"]
                or old_sig["flags"] != new_sig["flags"]
                or old_sig["optional"] != [default]
                or new_sig["optional"] != ["undefined"]):
            raise ValueError(f"{key}: String-default signature is not the audited shape")
        last_local = len(old_sig["params"])
        literal = default.removeprefix("string:")
        expected = [
            f"getlocal {last_local}", "pushnull", "ifne L6", f"pushstring {literal}",
            "coerce pkg:::String", f"setlocal {last_local}",
        ]
        if comp.get("exceptions") or (comp.get("code") or [])[:6] != expected:
            raise ValueError(f"{key}: String-default body prologue is not the audited shape")
        replacements[key] = copy.deepcopy(old_sig)
    return replacements


def restorable_signature_keys(compare_methods, original: dict[str, dict],
                              compiled: dict[str, dict]) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for key, orig in original.items():
        comp = compiled.get(key)
        if comp is None or orig["sig"] == comp["sig"]:
            continue
        repaired_package_classes = set(PACKAGE_LOCAL_QNAME_CASE_FIXES.values())
        if (residual_category("signature", key) != "original game signature deltas"
                and method_key_class(key) not in repaired_package_classes):
            continue
        if len(orig["sig"]["params"]) != len(comp["sig"]["params"]):
            continue
        if orig["sig"]["flags"] != comp["sig"]["flags"]:
            continue
        erased = {"pkg:::Object", "pkg:::Function", "pkg:haxe::IMap"}
        if any(old != new and not (old in erased and new == "*")
               for old, new in zip(orig["sig"]["params"], comp["sig"]["params"])):
            continue
        old_ret, new_ret = orig["sig"]["ret"], comp["sig"]["ret"]
        if old_ret != new_ret:
            erased_return = old_ret in erased and new_ret == "*"
            untyped_void = (old_ret == "*" and new_ret == "pkg:::void"
                            and "returnvalue" not in (comp["code"] or []))
            if not (erased_return or untyped_void):
                continue
        old_optional, new_optional = orig["sig"]["optional"], comp["sig"]["optional"]
        if len(old_optional) != len(new_optional):
            continue

        def numeric(value: str) -> Decimal | None:
            kind, separator, literal = value.partition(":")
            if not separator or kind not in {"int", "uint", "double"}:
                return None
            try:
                return Decimal(literal)
            except InvalidOperation:
                return None

        if any(old != new and (numeric(old) is None or numeric(old) != numeric(new))
               for old, new in zip(old_optional, new_optional)):
            continue
        out[key] = copy.deepcopy(orig["sig"])
    return out


def _encode_u30(value: int) -> bytes:
    if value < 0 or value > 0x3FFFFFFF:
        raise ValueError(f"u30 out of range: {value}")
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        out.append(byte | (0x80 if value else 0))
        if not value:
            return bytes(out)


def _encode_u32(value: int) -> bytes:
    if value < 0 or value > 0xFFFFFFFF:
        raise ValueError(f"u32 out of range: {value}")
    out = bytearray()
    for _ in range(5):
        byte = value & 0x7F
        value >>= 7
        out.append(byte | (0x80 if value else 0))
        if not value:
            return bytes(out)
    return bytes(out)


def _ensure_optional_numeric_constants(data: bytes, signatures: list[dict], compare_methods) -> bytes:
    abc = compare_methods.Abc(data)
    wanted_ints: list[int] = []
    wanted_uints: list[int] = []
    wanted_doubles: list[float] = []
    for signature in signatures:
        for value in signature["optional"]:
            kind, separator, literal = value.partition(":")
            if not separator:
                continue
            if kind == "int":
                parsed = int(literal)
                if parsed not in abc.ints and parsed not in wanted_ints:
                    wanted_ints.append(parsed)
            elif kind == "uint":
                parsed = int(literal)
                if parsed not in abc.uints and parsed not in wanted_uints:
                    wanted_uints.append(parsed)
            elif kind == "double":
                parsed = float(literal)
                if parsed not in abc.doubles and parsed not in wanted_doubles:
                    wanted_doubles.append(parsed)
    if not (wanted_ints or wanted_uints or wanted_doubles):
        return data

    s = compare_methods.Stream(data)
    prefix = s.bytes(4)
    int_count = s.u30()
    ints = [s.s32() for _ in range(max(int_count - 1, 0))]
    uint_count = s.u30()
    uints = [s.u30() for _ in range(max(uint_count - 1, 0))]
    double_count = s.u30()
    doubles = [s.d64() for _ in range(max(double_count - 1, 0))]
    suffix = data[s.pos:]

    ints.extend(wanted_ints)
    uints.extend(wanted_uints)
    doubles.extend(wanted_doubles)
    rebuilt = bytearray(prefix)
    rebuilt += _encode_u30(len(ints) + 1)
    for value in ints:
        rebuilt += _encode_u32(value & 0xFFFFFFFF)
    rebuilt += _encode_u30(len(uints) + 1)
    for value in uints:
        rebuilt += _encode_u32(value)
    rebuilt += _encode_u30(len(doubles) + 1)
    for value in doubles:
        rebuilt += struct.pack("<d", value)
    rebuilt += suffix
    return bytes(rebuilt)


def _rewrite_abc_string_indices(data: bytes, replacements: dict[int, str], compare_methods) -> bytes:
    if not replacements:
        return data
    s = compare_methods.Stream(data)
    s.u16(), s.u16()
    for reader in (s.s32, s.u30, s.d64):
        for _ in range(max(s.u30() - 1, 0)):
            reader()
    count = s.u30()
    rebuilt = bytearray(data)
    seen: set[int] = set()
    for index in range(1, count):
        length = s.u30()
        start = s.pos
        raw = s.bytes(length)
        if index not in replacements:
            continue
        encoded = replacements[index].encode("utf-8")
        if len(encoded) != length:
            raise ValueError(f"string {index}: QName case repair changes UTF-8 width")
        rebuilt[start:start + length] = encoded
        seen.add(index)
    if seen != set(replacements):
        raise ValueError("QName case repair references a missing string-pool entry")
    return bytes(rebuilt)


def repair_package_local_qname_case_blocks(original_blocks: list[bytes], compiled_blocks: list[bytes],
                                            compare_methods,
                                            fixes: dict[str, str] | None = None) -> tuple[list[bytes], int]:
    fixes = fixes or PACKAGE_LOCAL_QNAME_CASE_FIXES
    original_names = [
        abc.class_name(index)
        for data in original_blocks
        for abc in [compare_methods.Abc(data)]
        for index in range(len(abc.instances))
    ]
    for old, new in fixes.items():
        if original_names.count(new) != 1 or old in original_names:
            raise ValueError(f"original ABC does not uniquely prove QName repair {old} -> {new}")

    by_block: dict[int, dict[int, str]] = {}
    found: set[str] = set()
    for block_index, data in enumerate(compiled_blocks):
        abc = compare_methods.Abc(data)
        class_names = [abc.class_name(index) for index in range(len(abc.instances))]
        for old, new in fixes.items():
            matches = [index for index, name in enumerate(class_names) if name == old]
            if not matches:
                continue
            if len(matches) != 1 or old in found or new in class_names:
                raise ValueError(f"compiled ABC does not uniquely identify QName repair {old} -> {new}")
            class_index = matches[0]
            multiname_index = abc.instances[class_index]["name"]
            multiname = abc.multinames[multiname_index]
            if len(multiname) != 3 or multiname[0] not in (0x07, 0x0D):
                raise ValueError(f"{old}: class name is not a QName")
            string_index = multiname[2]
            old_local, new_local = old.rsplit(".", 1)[-1], new.rsplit(".", 1)[-1]
            if (abc.string(string_index) != old_local or abc.strings.count(old_local) != 1
                    or len(old_local.encode("ascii")) != len(new_local.encode("ascii"))):
                raise ValueError(f"{old}: local-name pool entry is not a unique equal-width ASCII spelling")
            name_uses = [
                index for index, item in enumerate(abc.multinames)
                if item and ((item[0] in (0x07, 0x0D) and item[2] == string_index)
                             or (item[0] in (0x0F, 0x10, 0x09, 0x0E) and item[1] == string_index))
            ]
            if name_uses != [multiname_index]:
                raise ValueError(f"{old}: local-name pool entry has other multiname uses")
            for method in abc.methods:
                if method["body"] is None:
                    continue
                if any(op in {"pushstring", "debugfile"} and args and args[0] == string_index
                       for _offset, op, args in abc.decode(method["body"]["code"])):
                    raise ValueError(f"{old}: local-name pool entry is also used as a string literal")
            by_block.setdefault(block_index, {})[string_index] = new_local
            found.add(old)
    if found != set(fixes):
        missing = sorted(set(fixes) - found)
        raise ValueError(f"compiled ABC is missing package-local QName repairs: {missing}")

    repaired = list(compiled_blocks)
    for block_index, replacements in by_block.items():
        repaired[block_index] = _rewrite_abc_string_indices(
            repaired[block_index], replacements, compare_methods
        )
        compare_methods.Abc(repaired[block_index])
    return repaired, len(found)


def _read_abc_trait_layout(stream) -> dict:
    start = stream.pos
    name = stream.u30()
    kind_attrs = stream.u8()
    kind, attrs = kind_attrs & 0x0F, kind_attrs & 0xF0
    record = {"start": start, "name": name, "kind": kind, "attrs": attrs}
    if kind in (0, 6):
        record.update(slot=stream.u30(), type=stream.u30(), vindex=stream.u30())
        record["vkind"] = stream.u8() if record["vindex"] else 0
    elif kind in (1, 2, 3):
        record.update(disp=stream.u30(), method=stream.u30())
    elif kind == 4:
        record.update(slot=stream.u30(), cls=stream.u30())
    elif kind == 5:
        record.update(slot=stream.u30(), function=stream.u30())
    else:
        raise ValueError(f"unsupported trait kind {kind}")
    if attrs & 0x40:
        record["metadata"] = [stream.u30() for _ in range(stream.u30())]
    else:
        record["metadata"] = []
    record["end"] = stream.pos
    return record


def _abc_trait_body_layout(data: bytes, compare_methods) -> tuple[list[list[dict]], dict[int, dict]]:
    instance_traits, _class_traits, bodies = _abc_layout(data, compare_methods)
    return instance_traits, bodies


def _abc_layout(data: bytes, compare_methods) -> tuple[list[list[dict]], list[list[dict]], dict[int, dict]]:
    _count_pos, method_end, _records = _method_info_region(data, compare_methods)
    s = compare_methods.Stream(data)
    s.pos = method_end
    for _ in range(s.u30()):
        s.u30()
        count = s.u30()
        for _ in range(count):
            s.u30()
        for _ in range(count):
            s.u30()
    class_count = s.u30()
    instance_traits: list[list[dict]] = []
    for _ in range(class_count):
        s.u30(), s.u30()
        flags = s.u8()
        if flags & 0x08:
            s.u30()
        for _ in range(s.u30()):
            s.u30()
        s.u30()
        instance_traits.append([_read_abc_trait_layout(s) for _ in range(s.u30())])
    class_traits: list[list[dict]] = []
    for _ in range(class_count):
        s.u30()
        class_traits.append([_read_abc_trait_layout(s) for _ in range(s.u30())])
    for _ in range(s.u30()):
        s.u30()
        for _ in range(s.u30()):
            _read_abc_trait_layout(s)
    bodies: dict[int, dict] = {}
    for _ in range(s.u30()):
        method = s.u30()
        header_start = s.pos
        s.u30(), s.u30(), s.u30(), s.u30()
        code_length_start = s.pos
        code_length = s.u30()
        code_start = s.pos
        s.bytes(code_length)
        code_end = s.pos
        exception_count = s.u30()
        for _ in range(exception_count):
            s.u30(), s.u30(), s.u30(), s.u30(), s.u30()
        for _ in range(s.u30()):
            _read_abc_trait_layout(s)
        if method in bodies:
            raise ValueError(f"method {method} has duplicate bodies")
        bodies[method] = {
            "header_start": header_start,
            "code_length_start": code_length_start,
            "code_start": code_start,
            "code_end": code_end,
            "exception_count": exception_count,
        }
    if s.pos != len(data):
        raise ValueError("ABC layout scan did not consume the complete block")
    return instance_traits, class_traits, bodies


def _encode_enum_const_trait(trait: dict) -> bytes:
    return b"".join((
        _encode_u30(trait["name"]), bytes([0x06]), _encode_u30(trait["slot"]),
        _encode_u30(trait["type"]), _encode_u30(0x0B), bytes([0x0B]),
    ))


def _local_instruction_index(op: str, args: list[int]) -> int | None:
    if op == "getlocal" or op == "setlocal":
        return args[0] if len(args) == 1 else None
    match = re.fullmatch(r"(?:get|set)local([0-3])", op)
    return int(match.group(1)) if match else None


def repair_string_default_signature_blocks(
        original_blocks: list[bytes], compiled_blocks: list[bytes], compare_methods,
        original_aliases: dict[str, str] | None = None,
        compiled_aliases: dict[str, str] | None = None) -> tuple[list[bytes], int]:
    original = compare_methods.collect(original_blocks, ns_aliases=original_aliases)
    compiled = compare_methods.collect(compiled_blocks, compiled_aliases, compiled_aliases)
    compiled = align_port_haxe_methods(original, compiled)
    replacements = string_default_signature_replacements(original, compiled)

    raw_locations = _method_locations(
        compare_methods, compiled_blocks, compiled_aliases or {}, compiled_aliases or {}
    )
    locations = align_port_haxe_methods(original, raw_locations)
    body_edits: dict[int, list[tuple[int, int, bytes]]] = {}
    signature_edits: dict[int, dict[int, dict]] = {}
    for key, signature in replacements.items():
        block_index, method = locations[key]
        abc = compare_methods.Abc(compiled_blocks[block_index], compiled_aliases)
        _traits, bodies = _abc_trait_body_layout(compiled_blocks[block_index], compare_methods)
        body = abc.methods[method]["body"]
        layout = bodies.get(method)
        if body is None or layout is None or body["exceptions"] or layout["exception_count"]:
            raise ValueError(f"{key}: String-default method body is absent or has exceptions")
        decoded = abc.decode(body["code"])
        if len(decoded) < 7:
            raise ValueError(f"{key}: String-default body is truncated")
        last_local = len(signature["params"])
        expected_default = STRING_DEFAULT_SIGNATURE_REPAIRS[key]
        expected_literal = expected_default.removeprefix("string:")[1:-1]
        first_ops = [op for _offset, op, _args in decoded[:6]]
        remove_end = decoded[6][0]
        if (decoded[0][0] != 0
                or first_ops[1:5] != ["pushnull", "ifne", "pushstring", "coerce"]
                or _local_instruction_index(decoded[0][1], decoded[0][2]) != last_local
                or _local_instruction_index(decoded[5][1], decoded[5][2]) != last_local
                or decoded[2][2] != [remove_end]
                or abc.constant(decoded[3][2][0], 0x01) != f"string:{expected_literal!r}"
                or abc.mn(decoded[4][2][0], compiled_aliases) != "pkg:::String"):
            raise ValueError(f"{key}: raw String-default prologue is not the audited shape")
        for index, (_offset, op, args) in enumerate(decoded):
            if index == 2:
                continue
            if (op == "jump" or op.startswith("if")) and args and args[0] < remove_end:
                raise ValueError(f"{key}: branch enters the String-default prologue")
            if op == "lookupswitch" and any(target < remove_end for target in args):
                raise ValueError(f"{key}: switch enters the String-default prologue")
        new_code = body["code"][remove_end:]
        body_edits.setdefault(block_index, []).append((
            layout["code_length_start"], layout["code_end"], _encode_u30(len(new_code)) + new_code,
        ))
        signature_edits.setdefault(block_index, {})[method] = signature

    repaired = list(compiled_blocks)
    for block_index, edits in body_edits.items():
        previous_start = len(repaired[block_index]) + 1
        rebuilt = bytearray(repaired[block_index])
        for start, end, replacement in sorted(edits, reverse=True):
            if end > previous_start or start >= end:
                raise ValueError("String-default repair has overlapping or invalid ABC edits")
            rebuilt[start:end] = replacement
            previous_start = start
        repaired[block_index] = _rewrite_abc_signatures(
            bytes(rebuilt), signature_edits[block_index], compare_methods,
            compiled_aliases or {}, compiled_aliases or {},
        )

    verified = compare_methods.collect(repaired, compiled_aliases, compiled_aliases)
    verified = align_port_haxe_methods(original, verified)
    for key, signature in replacements.items():
        method = verified.get(key)
        if method is None or method["sig"] != signature:
            raise ValueError(f"{key}: repaired String-default signature failed validation")
        expected_prefix = compiled[key]["code"][:6]
        if (method["code"] or [])[:6] == expected_prefix:
            raise ValueError(f"{key}: repaired String-default prologue remains")
    return repaired, len(replacements)


def repair_enum_instance_trait_blocks(original_blocks: list[bytes], compiled_blocks: list[bytes],
                                      compare_methods, original_aliases: dict[str, str] | None = None,
                                      compiled_aliases: dict[str, str] | None = None,
                                      expected_count: int = 28) -> tuple[list[bytes], int]:
    targets: set[str] = set()
    for data in original_blocks:
        abc = compare_methods.Abc(data, original_aliases)
        layouts, _bodies = _abc_trait_body_layout(data, compare_methods)
        for class_index, instance in enumerate(abc.instances):
            enum_indices = [
                index for index, trait in enumerate(instance["traits"])
                if abc.mn(trait["name"], original_aliases) == "pkg:::__enum__"
            ]
            if not enum_indices:
                continue
            if len(enum_indices) != 1:
                raise ValueError(f"{abc.class_name(class_index)}: duplicate original __enum__ traits")
            trait_index = enum_indices[0]
            trait = instance["traits"][trait_index]
            raw = layouts[class_index][trait_index]
            if (trait["kind"] != 6 or raw["kind"] != 6 or raw["attrs"] != 0 or trait["slot"] != 0
                    or abc.mn(trait["type"], original_aliases) != "pkg:::Boolean"
                    or trait["value"] != (0x0B, 0x0B)):
                raise ValueError(f"{abc.class_name(class_index)}: original __enum__ is not const Boolean true")
            name = abc.class_name(class_index)
            if name in targets:
                raise ValueError(f"duplicate original enum class {name}")
            targets.add(name)
    if len(targets) != expected_count:
        raise ValueError(f"expected {expected_count} original enum instance traits, found {len(targets)}")

    edits_by_block: dict[int, list[tuple[int, int, bytes]]] = {}
    found: set[str] = set()
    for block_index, data in enumerate(compiled_blocks):
        abc = compare_methods.Abc(data, compiled_aliases)
        layouts, bodies = _abc_trait_body_layout(data, compare_methods)
        iinit_owners: dict[int, int] = {}
        for instance in abc.instances:
            iinit_owners[instance["iinit"]] = iinit_owners.get(instance["iinit"], 0) + 1
        for class_index, instance in enumerate(abc.instances):
            raw_name = abc.class_name(class_index)
            name = (compiled_aliases or {}).get(raw_name, raw_name)
            if name not in targets:
                continue
            if name in found:
                raise ValueError(f"duplicate compiled enum class {name}")
            enum_indices = [
                index for index, trait in enumerate(instance["traits"])
                if abc.mn(trait["name"], compiled_aliases) == "pkg:::__enum__"
            ]
            if len(enum_indices) != 1:
                raise ValueError(f"{name}: compiled enum class does not have one __enum__ trait")
            trait_index = enum_indices[0]
            trait = instance["traits"][trait_index]
            raw = layouts[class_index][trait_index]
            if (trait["kind"] != 0 or raw["kind"] != 0 or raw["attrs"] != 0 or trait["slot"] != 0
                    or abc.mn(trait["type"], compiled_aliases) != "pkg:::Boolean"
                    or trait["value"] != (0, 0)):
                raise ValueError(f"{name}: compiled __enum__ is not the expected empty Boolean slot")
            method = instance["iinit"]
            if iinit_owners.get(method) != 1 or method not in bodies:
                raise ValueError(f"{name}: enum initializer is missing or shared")
            body = abc.methods[method]["body"]
            if body is None or body["exceptions"] or bodies[method]["exception_count"]:
                raise ValueError(f"{name}: enum initializer has exceptions")
            decoded = abc.decode(body["code"])
            expected_ops = ["getlocal0", "pushscope", "findproperty", "pushtrue", "initproperty"]
            if ([op for _offset, op, _args in decoded[:5]] != expected_ops
                    or len(decoded) < 6
                    or decoded[2][2] != [trait["name"]]
                    or decoded[4][2] != [trait["name"]]
                    or any(
                    op == "lookupswitch" or op == "jump" or op.startswith("if")
                    for _offset, op, _args in decoded)):
                raise ValueError(f"{name}: enum initializer write is not the exact branchless Haxe prefix")
            code = body["code"]
            remove_start, remove_end = decoded[2][0], decoded[5][0]
            if remove_start != 2 or not (remove_start < remove_end <= len(code)):
                raise ValueError(f"{name}: enum initializer code is truncated")
            new_code = code[:remove_start] + code[remove_end:]
            layout = bodies[method]
            edits_by_block.setdefault(block_index, []).extend((
                (raw["start"], raw["end"], _encode_enum_const_trait(raw)),
                (layout["code_length_start"], layout["code_end"], _encode_u30(len(new_code)) + new_code),
            ))
            found.add(name)
    if found != targets:
        raise ValueError(f"compiled ABC is missing enum trait repairs: {sorted(targets - found)}")

    repaired = list(compiled_blocks)
    for block_index, edits in edits_by_block.items():
        previous_start = len(repaired[block_index]) + 1
        rebuilt = bytearray(repaired[block_index])
        for start, end, replacement in sorted(edits, reverse=True):
            if end > previous_start or start >= end:
                raise ValueError("enum trait repair has overlapping or invalid ABC edits")
            rebuilt[start:end] = replacement
            previous_start = start
        repaired[block_index] = bytes(rebuilt)
        compare_methods.Abc(repaired[block_index], compiled_aliases)

    verified: set[str] = set()
    for data in repaired:
        abc = compare_methods.Abc(data, compiled_aliases)
        for class_index, instance in enumerate(abc.instances):
            raw_name = abc.class_name(class_index)
            name = (compiled_aliases or {}).get(raw_name, raw_name)
            if name not in targets:
                continue
            traits = [trait for trait in instance["traits"]
                      if abc.mn(trait["name"], compiled_aliases) == "pkg:::__enum__"]
            if (len(traits) != 1 or traits[0]["kind"] != 6 or traits[0]["value"] != (0x0B, 0x0B)
                    or abc.mn(traits[0]["type"], compiled_aliases) != "pkg:::Boolean"):
                raise ValueError(f"{name}: repaired enum trait failed post-validation")
            if any(abc.mn(args[0], compiled_aliases) == "pkg:::__enum__"
                   for _offset, op, args in abc.decode(abc.methods[instance["iinit"]]["body"]["code"])
                   if op in {"findproperty", "findpropstrict", "initproperty", "setproperty"} and args):
                raise ValueError(f"{name}: repaired initializer still writes __enum__")
            verified.add(name)
    if verified != targets:
        raise ValueError("enum trait repair post-validation missed a target class")
    return repaired, len(verified)


ENUM_VALUE_OPS = ["getlex", "findpropstrict", "pushstring", None, "pushnull", "coerce", "constructprop", "initproperty"]
ENUM_INDEX_OPS = {"pushbyte", "pushshort", "pushint"}


def _branch_targets(decoded: list[tuple[int, str, list]]) -> set[int]:
    targets: set[int] = set()
    for _offset, op, args in decoded:
        if op == "lookupswitch":
            targets.update(args)
        elif op == "jump" or op.startswith("if"):
            targets.add(args[0])
    return targets


def repair_enum_script_init_blocks(original_blocks: list[bytes], compiled_blocks: list[bytes],
                                   compare_methods, original_aliases: dict[str, str] | None = None,
                                   compiled_aliases: dict[str, str] | None = None,
                                   expected_count: int = 28) -> tuple[list[bytes], int]:
    targets: set[str] = set()
    for data in original_blocks:
        abc = compare_methods.Abc(data, original_aliases)
        for class_index, cls in enumerate(abc.classes):
            traits = [trait for trait in cls["traits"]
                      if abc.mn(trait["name"], original_aliases) == "pkg:::__isenum"]
            if not traits:
                continue
            trait = traits[0]
            if (len(traits) != 1 or trait["kind"] != 6 or trait["value"] != (0x0B, 0x0B)
                    or abc.mn(trait["type"], original_aliases) != "pkg:::Boolean"):
                raise ValueError(f"{abc.class_name(class_index)}: original __isenum is not const Boolean true")
            targets.add(abc.class_name(class_index))
    if len(targets) != expected_count:
        raise ValueError(f"expected {expected_count} original enum classes, found {len(targets)}")

    edits_by_block: dict[int, list[tuple[int, int, bytes]]] = {}
    found: set[str] = set()
    for block_index, data in enumerate(compiled_blocks):
        abc = compare_methods.Abc(data, compiled_aliases)
        _instance_layouts, class_layouts, bodies = _abc_layout(data, compare_methods)
        decoded_bodies = {
            method: abc.decode(info["body"]["code"])
            for method, info in enumerate(abc.methods) if info["body"] is not None
        }
        script_inits = {script["init"] for script in abc.scripts}
        for class_index, cls in enumerate(abc.classes):
            raw_name = abc.class_name(class_index)
            name = (compiled_aliases or {}).get(raw_name, raw_name)
            if name not in targets:
                continue
            if name in found:
                raise ValueError(f"duplicate compiled enum class {name}")
            class_mn = abc.instances[class_index]["name"]
            by_name: dict[str, list[int]] = {}
            for trait_index, trait in enumerate(cls["traits"]):
                by_name.setdefault(abc.mn(trait["name"], compiled_aliases), []).append(trait_index)
            isenum = by_name.get("pkg:::__isenum", [])
            guard = by_name.get("pkg:::init__", [])
            if len(isenum) != 1 or len(guard) != 1:
                raise ValueError(f"{name}: compiled enum lacks one __isenum and one init__ trait")
            isenum_trait = cls["traits"][isenum[0]]
            isenum_raw = class_layouts[class_index][isenum[0]]
            guard_name = cls["traits"][guard[0]]["name"]
            if (isenum_trait["kind"] != 0 or isenum_raw["attrs"] != 0 or isenum_raw["metadata"]
                    or isenum_trait["value"] != (0, 0)
                    or abc.mn(isenum_trait["type"], compiled_aliases) != "pkg:::Boolean"):
                raise ValueError(f"{name}: compiled __isenum is not the expected empty Boolean slot")
            value_names = {
                trait["name"] for trait in cls["traits"]
                if trait["kind"] == 0 and trait["type"] == class_mn
            }

            def is_class(op_args: list) -> bool:
                return bool(op_args) and op_args[0] == class_mn

            writes = []
            for method, decoded in decoded_bodies.items():
                for index in range(len(decoded) - 2):
                    (_o0, op0, a0), (_o1, op1, _a1), (_o2, op2, a2) = decoded[index:index + 3]
                    if (op0 == "getlex" and is_class(a0) and op1 == "pushtrue" and op2 == "initproperty"
                            and a2 == [isenum_trait["name"]]):
                        writes.append((method, index))
            if len(writes) != 1 or writes[0][0] not in script_inits:
                raise ValueError(f"{name}: no single __isenum write in a script initializer")
            script_method, write_index = writes[0]
            script_decoded = decoded_bodies[script_method]
            script_body = abc.methods[script_method]["body"]
            if _branch_targets(script_decoded) or script_body["exceptions"]:
                raise ValueError(f"{name}: script initializer is not straight-line")

            guards = []
            for method, decoded in decoded_bodies.items():
                for index in range(len(decoded) - 6):
                    ops = decoded[index:index + 6]
                    if ([op for _o, op, _a in ops]
                            == ["getlex", "getproperty", "iftrue", "getlex", "pushtrue", "initproperty"]
                            and is_class(ops[0][2]) and is_class(ops[3][2])
                            and ops[1][2] == [guard_name] and ops[5][2] == [guard_name]):
                        guards.append((method, index))
            if len(guards) != 1:
                raise ValueError(f"{name}: no single init__ guard")
            boot_method, guard_index = guards[0]
            boot_decoded = decoded_bodies[boot_method]
            boot_code = abc.methods[boot_method]["body"]["code"]
            end = boot_decoded[guard_index + 2][2][0]
            start_index = guard_index + 6
            if start_index >= len(boot_decoded):
                raise ValueError(f"{name}: init__ guard has no block")
            block_start = boot_decoded[start_index][0]
            end_index = next((i for i, item in enumerate(boot_decoded) if item[0] == end), None)
            if end_index is None or end_index <= start_index or (end_index - start_index) % 8:
                raise ValueError(f"{name}: init__ guard does not end on an instruction after its block")
            stored = []
            for unit in range(start_index, end_index, 8):
                ops = boot_decoded[unit:unit + 8]
                names = [op for _o, op, _a in ops]
                if (any(expected is not None and actual != expected
                        for expected, actual in zip(ENUM_VALUE_OPS, names))
                        or names[3] not in ENUM_INDEX_OPS
                        or not is_class(ops[0][2]) or not is_class(ops[1][2]) or ops[6][2] != [class_mn, 3]
                        or abc.mn(ops[5][2][0], compiled_aliases) != "pkg:::Array"
                        or ops[7][2][0] not in value_names):
                    raise ValueError(f"{name}: guarded block is not the exact enum construction sequence")
                stored.append(ops[7][2][0])
            if len(set(stored)) != len(stored) or set(stored) != value_names:
                raise ValueError(f"{name}: guarded block does not build every enum value once")
            inside = {offset for offset in _branch_targets(boot_decoded) if block_start <= offset < end}
            boot_exceptions = abc.methods[boot_method]["body"]["exceptions"]
            if inside or any(block_start < bound < end for item in boot_exceptions for bound in item[:3]):
                raise ValueError(f"{name}: control flow enters the guarded enum block")
            block = boot_code[block_start:end]

            script_code = script_body["code"]
            write_start = script_decoded[write_index][0]
            write_end = (script_decoded[write_index + 3][0] if write_index + 3 < len(script_decoded)
                         else len(script_code))
            new_code = script_code[:write_start] + block + script_code[write_end:]
            layout = bodies[script_method]
            header = b"".join(_encode_u30(value) for value in (
                script_body["max_stack"] + 3, script_body["locals"],
                script_body["init_scope"], script_body["max_scope"],
            ))
            boot_layout = bodies[boot_method]
            edits_by_block.setdefault(block_index, []).extend((
                (isenum_raw["start"], isenum_raw["end"], _encode_enum_const_trait(isenum_raw)),
                (layout["header_start"], layout["code_end"], header + _encode_u30(len(new_code)) + new_code),
                (boot_layout["code_start"] + block_start, boot_layout["code_start"] + end,
                 b"\x02" * (end - block_start)),
            ))
            found.add(name)
    if found != targets:
        raise ValueError(f"compiled ABC is missing enum script repairs: {sorted(targets - found)}")

    repaired = list(compiled_blocks)
    for block_index, edits in edits_by_block.items():
        previous_start = len(repaired[block_index]) + 1
        rebuilt = bytearray(repaired[block_index])
        for start, end, replacement in sorted(edits, reverse=True):
            if end > previous_start or start >= end:
                raise ValueError("enum script repair has overlapping or invalid ABC edits")
            rebuilt[start:end] = replacement
            previous_start = start
        repaired[block_index] = bytes(rebuilt)

    verified: set[str] = set()
    for data in repaired:
        abc = compare_methods.Abc(data, compiled_aliases)
        script_inits = {script["init"] for script in abc.scripts}
        for class_index, cls in enumerate(abc.classes):
            raw_name = abc.class_name(class_index)
            name = (compiled_aliases or {}).get(raw_name, raw_name)
            if name not in targets:
                continue
            traits = [trait for trait in cls["traits"]
                      if abc.mn(trait["name"], compiled_aliases) == "pkg:::__isenum"]
            if len(traits) != 1 or traits[0]["kind"] != 6 or traits[0]["value"] != (0x0B, 0x0B):
                raise ValueError(f"{name}: repaired __isenum trait failed post-validation")
            class_mn = abc.instances[class_index]["name"]
            builders = [
                method for method in script_inits
                if any(op == "constructprop" and args[0] == class_mn
                       for _o, op, args in abc.decode(abc.methods[method]["body"]["code"]))
            ]
            if len(builders) != 1:
                raise ValueError(f"{name}: repaired script initializer does not build the enum values")
            verified.add(name)
    if verified != targets:
        raise ValueError("enum script repair post-validation missed a target class")
    return repaired, len(verified)


def _literal_number(abc, ops: list[tuple[int, str, list]]) -> int | None:
    if not ops or len(ops) > 2 or (len(ops) == 2 and ops[1][1] not in ("convert_i", "convert_u")):
        return None
    _offset, op, args = ops[0]
    if op == "pushbyte":
        value = args[0]
    elif op == "pushshort":
        value = args[0] - (1 << 30) if args[0] & (1 << 29) else args[0]
    elif op == "pushint":
        value = abc.ints[args[0]]
    elif op == "pushuint":
        value = abc.uints[args[0]]
    else:
        return None
    if len(ops) == 2 and ops[1][1] == "convert_u" and value < 0:
        return None
    return value


def repair_native_script_init_blocks(original_blocks: list[bytes], compiled_blocks: list[bytes],
                                     compare_methods, original_aliases: dict[str, str] | None = None,
                                     compiled_aliases: dict[str, str] | None = None,
                                     _add_constants: bool = True,
                                     ) -> tuple[list[bytes], list[str]]:
    original = compare_methods.collect(original_blocks, ns_aliases=original_aliases)
    missing_numbers: dict[int, list[str]] = {}
    original_traits: dict[str, dict[str, dict]] = {}
    for data in original_blocks:
        abc = compare_methods.Abc(data, original_aliases)
        for class_index, cls in enumerate(abc.classes):
            original_traits[abc.class_name(class_index)] = {
                abc.mn(trait["name"], original_aliases).rsplit("::", 1)[-1]: {
                    "kind": trait["kind"],
                    "string": (abc.strings[trait["value"][0]]
                               if trait.get("value") and trait["value"][1] == 0x01 else None),
                    "number": ((trait["value"][1], (abc.ints if trait["value"][1] == 0x03 else abc.uints)
                                [trait["value"][0]])
                               if trait.get("value") and trait["value"][1] in (0x03, 0x04) else None),
                    "bool": ({0x0B: True, 0x0A: False}.get(trait["value"][1])
                             if trait.get("value") else None),
                }
                for trait in cls["traits"]
            }

    u30 = _encode_u30
    candidates: list[tuple[int, str, list[tuple[int, int, bytes]]]] = []
    for block_index, data in enumerate(compiled_blocks):
        abc = compare_methods.Abc(data, compiled_aliases)
        _instance_layouts, class_layouts, bodies = _abc_layout(data, compare_methods)
        object_mn = next((index for index in range(1, len(abc.multinames))
                          if abc.mn(index, compiled_aliases) == "pkg:::Object"), None)
        for script in abc.scripts:
            method = script["init"]
            body = abc.methods[method]["body"]
            if body is None or body["exceptions"]:
                continue
            decoded = abc.decode(body["code"])
            ops = [op for _o, op, _a in decoded]
            if (ops[:9] != ["getlocal0", "pushscope", "getglobalscope", "getlex", "pushscope", "getlex",
                            "newclass", "popscope", "initproperty"]
                    or decoded[3][2] != decoded[5][2] or ops[-1] != "returnvoid"
                    or _branch_targets(decoded) or ops.count("newclass") != 1):
                continue
            class_index = decoded[6][2][0]
            raw_name = abc.class_name(class_index)
            name = (compiled_aliases or {}).get(raw_name, raw_name)
            key = f"script {name}/init"
            want = original.get(key)
            if (want is None or not want["code"]
                    or want["code"][:2] != ["getlocal 0", "pushscope"]
                    or want["code"][2] not in ("getscopeobject 0", "getglobalscope")
                    or name not in original_traits or object_mn is None):
                continue
            base = decoded[3][2][0]
            prologue = b"\xd0\x30\x65\x00"
            if want["code"][2] == "getglobalscope":
                prologue = body["code"][:decoded[8][0]]
            elif base == object_mn:
                prologue += b"\x60" + u30(base) + b"\x2a\x30\x58" + u30(class_index) + b"\x1d"
            else:
                prologue += (b"\x60" + u30(object_mn) + b"\x30\x60" + u30(base) + b"\x2a\x30\x58"
                             + u30(class_index) + b"\x1d\x1d")
            code = body["code"]
            kept = [prologue, code[decoded[8][0]:decoded[9][0]]]
            trait_edits: list[tuple[int, int, bytes]] = []
            by_name = {abc.mn(trait["name"], compiled_aliases).rsplit("::", 1)[-1]: index
                       for index, trait in enumerate(abc.classes[class_index]["traits"])}
            class_mn = abc.instances[class_index]["name"]
            index, ok = 9, True
            while index < len(decoded) - 1:
                end = next((j for j in range(index, len(decoded) - 1) if ops[j] == "initproperty"), None)
                if end is None or ops[index] != "getlex" or decoded[index][2] != [class_mn]:
                    ok = False
                    break
                value_ops = ops[index + 1:end]
                field = abc.mn(decoded[end][2][0], compiled_aliases).rsplit("::", 1)[-1]
                want_trait = original_traits[name].get(field)
                trait_index = by_name.get(field)
                layout = class_layouts[class_index][trait_index] if trait_index is not None else None
                if value_ops in (["pushnull"], ["pushnull", "coerce"]) and want_trait and want_trait["kind"] == 0:
                    pass
                elif (value_ops == ["pushstring"] and want_trait and layout and not layout["metadata"]
                        and want_trait["string"] == abc.strings[decoded[index + 1][2][0]]
                        and want_trait["kind"] in (0, 6) and layout["kind"] == 0 and not layout["vindex"]):
                    trait_edits.append((layout["start"], layout["end"], b"".join((
                        u30(layout["name"]), bytes([want_trait["kind"] | layout["attrs"]]), u30(layout["slot"]),
                        u30(layout["type"]), u30(decoded[index + 1][2][0]), b"\x01",
                    ))))
                elif (value_ops in (["pushtrue"], ["pushfalse"]) and want_trait and layout
                        and not layout["metadata"] and layout["kind"] == 0 and not layout["vindex"]
                        and want_trait["bool"] is (value_ops == ["pushtrue"]) and want_trait["kind"] in (0, 6)):
                    flag = 0x0B if want_trait["bool"] else 0x0A
                    trait_edits.append((layout["start"], layout["end"], b"".join((
                        u30(layout["name"]), bytes([want_trait["kind"] | layout["attrs"]]), u30(layout["slot"]),
                        u30(layout["type"]), u30(flag), bytes([flag]),
                    ))))
                elif (want_trait and want_trait["number"] and layout and not layout["metadata"]
                        and layout["kind"] == 0 and not layout["vindex"]
                        and (number := _literal_number(abc, decoded[index + 1:end])) is not None
                        and number == want_trait["number"][1]):
                    kinds = [want_trait["number"][0]] + ([0x04 if want_trait["number"][0] == 0x03 else 0x03]
                                                        if number >= 0 else [])
                    found = [(vkind, i) for vkind in kinds
                             for pool in [abc.ints if vkind == 0x03 else abc.uints]
                             for i in range(1, len(pool)) if pool[i] == number]
                    if not found:
                        missing_numbers.setdefault(block_index, []).append(
                            f"{'int' if want_trait['number'][0] == 0x03 else 'uint'}:{number}")
                        ok = False
                        index = end + 1
                        continue
                    vkind, vindex = found[0]
                    trait_edits.append((layout["start"], layout["end"], b"".join((
                        u30(layout["name"]), bytes([want_trait["kind"] | layout["attrs"]]), u30(layout["slot"]),
                        u30(layout["type"]), u30(vindex), bytes([vkind]),
                    ))))
                else:
                    kept.append(code[decoded[index][0]:decoded[end + 1][0]])
                index = end + 1
            if not ok:
                continue
            kept.append(b"\x47")
            new_code = b"".join(kept)
            haxe_shaped = want["code"][2] == "getglobalscope"
            if haxe_shaped and new_code == code and not trait_edits:
                continue
            layout = bodies[method]
            header = b"".join(u30(value) for value in (
                body["max_stack"] if haxe_shaped else max(body["max_stack"], 3), body["locals"], body["init_scope"],
                body["max_scope"] if haxe_shaped else max(body["max_scope"], body["init_scope"] + 3),
            ))
            candidates.append((block_index, key, [
                (layout["header_start"], layout["code_end"], header + u30(len(new_code)) + new_code),
                *trait_edits,
            ]))

    if missing_numbers and _add_constants:
        extended = [
            _ensure_optional_numeric_constants(data, [{"optional": missing_numbers[block_index]}], compare_methods)
            if block_index in missing_numbers else data
            for block_index, data in enumerate(compiled_blocks)
        ]
        return repair_native_script_init_blocks(original_blocks, extended, compare_methods, original_aliases,
                                                compiled_aliases, _add_constants=False)

    def apply(accepted: list[tuple[int, str, list[tuple[int, int, bytes]]]]) -> list[bytes]:
        out = list(compiled_blocks)
        by_block: dict[int, list[tuple[int, int, bytes]]] = {}
        for block_index, _key, edits in accepted:
            by_block.setdefault(block_index, []).extend(edits)
        for block_index, edits in by_block.items():
            rebuilt = bytearray(out[block_index])
            previous_start = len(rebuilt) + 1
            for start, end, replacement in sorted(edits, reverse=True):
                if end > previous_start or start >= end:
                    raise ValueError("native script repair has overlapping or invalid ABC edits")
                rebuilt[start:end] = replacement
                previous_start = start
            out[block_index] = bytes(rebuilt)
        return out

    trial = align_port_haxe_methods(
        original, compare_methods.collect(apply(candidates), compiled_aliases, compiled_aliases))
    accepted = [item for item in candidates if trial.get(item[1], {}).get("code") == original[item[1]]["code"]]
    repaired = apply(accepted)
    for data in repaired:
        compare_methods.Abc(data, compiled_aliases)
    return repaired, sorted(key for _b, key, _e in accepted)


def _method_info_region(data: bytes, compare_methods) -> tuple[int, int, list[dict]]:
    s = compare_methods.Stream(data)
    s.u16(), s.u16()
    for reader in (s.s32, s.u30, s.d64):
        for _ in range(max(s.u30() - 1, 0)):
            reader()
    for _ in range(max(s.u30() - 1, 0)):
        s.bytes(s.u30())
    for _ in range(max(s.u30() - 1, 0)):
        s.u8(), s.u30()
    for _ in range(max(s.u30() - 1, 0)):
        for _ in range(s.u30()):
            s.u30()
    for _ in range(max(s.u30() - 1, 0)):
        kind = s.u8()
        if kind in (0x07, 0x0D):
            s.u30(), s.u30()
        elif kind in (0x0F, 0x10):
            s.u30()
        elif kind in (0x11, 0x12):
            pass
        elif kind in (0x09, 0x0E):
            s.u30(), s.u30()
        elif kind in (0x1B, 0x1C):
            s.u30()
        elif kind == 0x1D:
            s.u30()
            for _ in range(s.u30()):
                s.u30()
        else:
            raise ValueError(f"unsupported multiname kind 0x{kind:02x}")

    count_pos = s.pos
    count = s.u30()
    records = []
    for _ in range(count):
        param_count = s.u30()
        ret = s.u30()
        params = [s.u30() for _ in range(param_count)]
        name = s.u30()
        flags = s.u8()
        optional = [(s.u30(), s.u8()) for _ in range(s.u30())] if flags & 0x08 else []
        param_names = [s.u30() for _ in range(param_count)] if flags & 0x80 else []
        records.append({
            "ret": ret, "params": params, "name": name, "flags": flags,
            "optional": optional, "param_names": param_names,
        })
    return count_pos, s.pos, records


def _method_locations(compare_methods, blocks: list[bytes], aliases: dict[str, str],
                      ns_aliases: dict[str, str]) -> dict[str, tuple[int, int]]:
    locations: dict[str, tuple[int, int]] = {}
    for block_index, data in enumerate(blocks):
        abc = compare_methods.Abc(data, ns_aliases)
        pending = list(compare_methods.method_keys(abc, aliases).items())
        while pending:
            key, method = pending.pop()
            while key in locations:
                key += "+"
            locations[key] = (block_index, method)
            norm = compare_methods.normalize(abc, method, aliases)
            pending.extend((f"{key}/fn{n}", child) for n, child in enumerate(norm["closures"]))
    return locations


def _constant_indices(abc) -> dict[str, tuple[int, int]]:
    out: dict[str, tuple[int, int]] = {
        "undefined": (0, 0x00), "false": (0, 0x0A), "true": (0, 0x0B), "null": (0, 0x0C),
    }
    for kind, values in ((0x03, abc.ints), (0x04, abc.uints), (0x06, abc.doubles), (0x01, abc.strings)):
        for index in range(len(values)):
            out.setdefault(abc.constant(index, kind), (index, kind))
    return out


def _rewrite_abc_signatures(data: bytes, replacements: dict[int, dict], compare_methods,
                            aliases: dict[str, str], ns_aliases: dict[str, str]) -> bytes:
    if not replacements:
        return data
    data = _ensure_optional_numeric_constants(data, list(replacements.values()), compare_methods)
    abc = compare_methods.Abc(data, ns_aliases)
    type_indices: dict[str, list[int]] = {}
    for index in range(len(abc.multinames)):
        type_indices.setdefault(abc.mn(index, aliases), []).append(index)
    constants = _constant_indices(abc)
    count_pos, end_pos, records = _method_info_region(data, compare_methods)

    def type_index(name: str) -> int:
        if name == "*":
            return 0
        choices = type_indices.get(name, [])
        if not choices:
            raise ValueError(f"compiled ABC has no multiname for restored type {name}")
        return choices[0]

    for method, signature in replacements.items():
        record = records[method]
        if len(signature["params"]) != len(record["params"]):
            raise ValueError(f"method {method}: restored parameter count differs")
        if signature["flags"] != (record["flags"] & compare_methods.NEED_FLAGS):
            raise ValueError(f"method {method}: restored semantic flags differ")
        record["ret"] = type_index(signature["ret"])
        record["params"] = [type_index(name) for name in signature["params"]]
        record["optional"] = [constants[value] for value in signature["optional"]]
        if record["optional"]:
            record["flags"] |= 0x08
        else:
            record["flags"] &= ~0x08

    encoded = bytearray(_encode_u30(len(records)))
    for record in records:
        encoded += _encode_u30(len(record["params"]))
        encoded += _encode_u30(record["ret"])
        for param in record["params"]:
            encoded += _encode_u30(param)
        encoded += _encode_u30(record["name"])
        encoded.append(record["flags"])
        if record["flags"] & 0x08:
            encoded += _encode_u30(len(record["optional"]))
            for value, kind in record["optional"]:
                encoded += _encode_u30(value)
                encoded.append(kind)
        if record["flags"] & 0x80:
            for name in record["param_names"]:
                encoded += _encode_u30(name)
    return data[:count_pos] + bytes(encoded) + data[end_pos:]


def _swf_body(data: bytes) -> bytes:
    if data[:3] == b"FWS":
        return data[8:]
    if data[:3] == b"CWS":
        return zlib.decompress(data[8:])
    raise ValueError(f"SWF stage restoration supports FWS/CWS, found {data[:3]!r}")


def _swf_tags(body: bytes) -> tuple[int, list[tuple[int, bytes]]]:
    nbits = body[0] >> 3
    pos = header_end = (5 + 4 * nbits + 7) // 8 + 4
    tags: list[tuple[int, bytes]] = []
    while pos < len(body):
        header = struct.unpack_from("<H", body, pos)[0]
        pos += 2
        code, length = header >> 6, header & 0x3F
        if length == 0x3F:
            length = struct.unpack_from("<I", body, pos)[0]
            pos += 4
        tags.append((code, body[pos:pos + length]))
        pos += length
        if code == 0:
            break
    return header_end, tags


def restore_swf_stage_tags(path: Path, original: Path | None = None) -> None:
    from tools import compare_methods

    original = original or base_swf()
    data = path.read_bytes()
    body = _swf_body(data)
    original_body = _swf_body(original.read_bytes())
    original_header_end, original_tags = _swf_tags(original_body)
    header_end, tags = _swf_tags(body)
    background = next((payload for code, payload in original_tags if code == 9), None)
    limits = next((payload for code, payload in original_tags if code == 65), None)
    rebuilt = bytearray(original_body[:original_header_end])
    inserted = False
    for code, payload in tags:
        if code == 65:
            continue
        if code == 9 and background is not None:
            payload = background
        if code in (82, 72) and limits is not None and not inserted:
            rebuilt += struct.pack("<H", (65 << 6) | len(limits)) + limits
            inserted = True
        if len(payload) < 0x3F:
            rebuilt += struct.pack("<H", (code << 6) | len(payload))
        else:
            rebuilt += struct.pack("<HI", (code << 6) | 0x3F, len(payload))
        rebuilt += payload
    uncompressed = bytes(rebuilt)
    out = data[:4] + struct.pack("<I", 8 + len(uncompressed))
    out += zlib.compress(uncompressed, 9) if data[:3] == b"CWS" else uncompressed
    temporary = path.with_suffix(path.suffix + ".stage")
    temporary.write_bytes(out)
    temporary.replace(path)
    print(f"restored the original stage header, background and script limits in {path}")


def _rewrite_swf_abc_blocks(data: bytes, replacements: dict[int, bytes]) -> bytes:
    signature, version = data[:3], data[3:4]
    if signature == b"FWS":
        body = data[8:]
    elif signature == b"CWS":
        body = zlib.decompress(data[8:])
    else:
        raise ValueError(f"signature restoration supports FWS/CWS, found {signature!r}")
    nbits = body[0] >> 3
    pos = (5 + 4 * nbits + 7) // 8 + 4
    rebuilt = bytearray(body[:pos])
    abc_index = 0
    while pos < len(body):
        header = struct.unpack_from("<H", body, pos)[0]
        pos += 2
        code, length = header >> 6, header & 0x3F
        if length == 0x3F:
            length = struct.unpack_from("<I", body, pos)[0]
            pos += 4
        payload = body[pos:pos + length]
        pos += length
        if code == 82:
            end = payload.index(b"\0", 4)
            if abc_index in replacements:
                payload = payload[:end + 1] + replacements[abc_index]
            abc_index += 1
        elif code == 72:
            if abc_index in replacements:
                payload = replacements[abc_index]
            abc_index += 1
        tag_length = len(payload)
        if tag_length < 0x3F:
            rebuilt += struct.pack("<H", (code << 6) | tag_length)
        else:
            rebuilt += struct.pack("<HI", (code << 6) | 0x3F, tag_length)
        rebuilt += payload
        if code == 0:
            rebuilt += body[pos:]
            break
    uncompressed = bytes(rebuilt)
    header = signature + version + struct.pack("<I", 8 + len(uncompressed))
    return header + (uncompressed if signature == b"FWS" else zlib.compress(uncompressed, 9))


def restore_package_local_qnames(path: Path) -> int:
    from tools import compare_methods

    blocks = compare_methods.swf_blocks(path)
    repaired, count = repair_package_local_qname_case_blocks(
        compare_methods.swf_blocks(base_swf()), blocks, compare_methods
    )
    changed = {index: data for index, data in enumerate(repaired) if data != blocks[index]}
    if not changed:
        return 0
    restored = _rewrite_swf_abc_blocks(path.read_bytes(), changed)
    temporary = path.with_suffix(path.suffix + ".qnames")
    temporary.write_bytes(restored)
    temporary.replace(path)
    print(f"restored {count} package-local class QNames in {path}")
    return count


def restore_enum_instance_traits(path: Path) -> int:
    from tools import compare_methods

    symbols = symbols_path()
    ns_aliases = compare_methods.load_class_names(symbols)
    haxe_aliases = load_port_haxe_aliases()
    haxe_ns_aliases = {**ns_aliases, **haxe_aliases}
    blocks = compare_methods.swf_blocks(path)
    repaired, count = repair_enum_instance_trait_blocks(
        compare_methods.swf_blocks(base_swf()), blocks, compare_methods,
        ns_aliases, haxe_ns_aliases,
    )
    changed = {index: data for index, data in enumerate(repaired) if data != blocks[index]}
    restored = _rewrite_swf_abc_blocks(path.read_bytes(), changed)
    temporary = path.with_suffix(path.suffix + ".enums")
    temporary.write_bytes(restored)
    temporary.replace(path)
    print(f"restored {count} enum instance const traits in {path}")
    return count


def restore_enum_script_initializers(path: Path) -> int:
    from tools import compare_methods

    symbols = symbols_path()
    ns_aliases = compare_methods.load_class_names(symbols)
    haxe_aliases = load_port_haxe_aliases()
    haxe_ns_aliases = {**ns_aliases, **haxe_aliases}
    blocks = compare_methods.swf_blocks(path)
    repaired, count = repair_enum_script_init_blocks(
        compare_methods.swf_blocks(base_swf()), blocks, compare_methods,
        ns_aliases, haxe_ns_aliases,
    )
    changed = {index: data for index, data in enumerate(repaired) if data != blocks[index]}
    restored = _rewrite_swf_abc_blocks(path.read_bytes(), changed)
    temporary = path.with_suffix(path.suffix + ".enum-scripts")
    temporary.write_bytes(restored)
    temporary.replace(path)
    print(f"moved {count} enum value constructions into their script initializers in {path}")
    return count


def restore_native_script_initializers(path: Path) -> int:
    from tools import compare_methods

    symbols = symbols_path()
    ns_aliases = compare_methods.load_class_names(symbols)
    haxe_aliases = load_port_haxe_aliases()
    haxe_ns_aliases = {**ns_aliases, **haxe_aliases}
    blocks = compare_methods.swf_blocks(path)
    repaired, keys = repair_native_script_init_blocks(
        compare_methods.swf_blocks(base_swf()), blocks, compare_methods,
        ns_aliases, haxe_ns_aliases,
    )
    changed = {index: data for index, data in enumerate(repaired) if data != blocks[index]}
    restored = _rewrite_swf_abc_blocks(path.read_bytes(), changed)
    temporary = path.with_suffix(path.suffix + ".native-scripts")
    temporary.write_bytes(restored)
    temporary.replace(path)
    print(f"restored {len(keys)} ASC-compiled script initializers in {path}")
    return len(keys)


def restore_string_default_signatures(path: Path) -> int:
    from tools import compare_methods

    symbols = symbols_path()
    ns_aliases = compare_methods.load_class_names(symbols)
    haxe_aliases = load_port_haxe_aliases()
    haxe_ns_aliases = {**ns_aliases, **haxe_aliases}
    blocks = compare_methods.swf_blocks(path)
    repaired, count = repair_string_default_signature_blocks(
        compare_methods.swf_blocks(base_swf()), blocks, compare_methods,
        ns_aliases, haxe_ns_aliases,
    )
    changed = {index: data for index, data in enumerate(repaired) if data != blocks[index]}
    if not changed:
        raise ValueError("String-default signature repair changed no ABC blocks")
    restored = _rewrite_swf_abc_blocks(path.read_bytes(), changed)
    temporary = path.with_suffix(path.suffix + ".string-defaults")
    temporary.write_bytes(restored)
    temporary.replace(path)
    print(f"restored {count} String-default method signatures in {path}")
    return count


def restore_original_signatures(path: Path) -> int:
    from tools import compare_methods

    original = base_swf()
    symbols = symbols_path()
    ns_aliases = compare_methods.load_class_names(symbols)
    haxe_aliases = load_port_haxe_aliases()
    haxe_ns_aliases = {**ns_aliases, **haxe_aliases}
    original_methods, _ = load_original_comparison(compare_methods, original, symbols, ns_aliases)
    blocks = compare_methods.swf_blocks(path)
    compiled_methods = compare_methods.collect(blocks, haxe_aliases, haxe_ns_aliases)
    compiled_methods = align_port_haxe_methods(original_methods, compiled_methods)
    signatures = restorable_signature_keys(compare_methods, original_methods, compiled_methods)
    raw_locations = _method_locations(compare_methods, blocks, haxe_aliases, haxe_ns_aliases)
    locations = align_port_haxe_methods(original_methods, raw_locations)
    by_block: dict[int, dict[int, dict]] = {}
    for key, signature in signatures.items():
        block, method = locations[key]
        by_block.setdefault(block, {})[method] = signature
    changed_blocks = {
        block: _rewrite_abc_signatures(blocks[block], replacements, compare_methods,
                                       haxe_aliases, haxe_ns_aliases)
        for block, replacements in by_block.items()
    }
    restored = _rewrite_swf_abc_blocks(path.read_bytes(), changed_blocks)
    temporary = path.with_suffix(path.suffix + ".restored")
    temporary.write_bytes(restored)
    temporary.replace(path)
    print(f"restored {len(signatures)} original method signatures in {path}")
    return len(signatures)


def method_key_class(key: str) -> str | None:
    match = METHOD_KEY_RE.match(key)
    if match:
        return match.group("class")
    match = SCRIPT_KEY_RE.match(key)
    return match.group("class") if match else None


def replace_method_key_class(key: str, cls: str) -> str:
    match = METHOD_KEY_RE.match(key)
    if not match:
        return key
    return cls + key[match.end("class"):]


def align_port_haxe_methods(original: dict[str, dict], compiled: dict[str, dict]) -> dict[str, dict]:
    original_classes: dict[str, set[str]] = {}
    compiled_classes: dict[str, set[str]] = {}
    for key in original:
        if cls := method_key_class(key):
            original_classes.setdefault(cls, set()).add(key)
    for key in compiled:
        if cls := method_key_class(key):
            compiled_classes.setdefault(cls, set()).add(key)

    class_map: dict[str, str] = {}
    tail_to_original: dict[str, list[str]] = {}
    for cls in original_classes:
        if cls.startswith("FilePrivateNS:") and "." in cls:
            tail_to_original.setdefault(cls.rsplit(".", 1)[-1], []).append(cls)
    for cls in compiled_classes:
        choices = tail_to_original.get(cls, [])
        if len(choices) == 1:
            class_map[cls] = choices[0]

    out: dict[str, dict] = {}
    for key, value in compiled.items():
        mapped = key
        cls = method_key_class(mapped)
        if cls in class_map:
            mapped = replace_method_key_class(mapped, class_map[cls])

        match = METHOD_KEY_RE.match(mapped)
        if match and match.group("kind") == "method":
            prefix = f"{match.group('class')}/{match.group('side')}"
            name = match.group("name")
            if name.startswith("get_"):
                getter = f"{prefix}/getter {name[4:]}"
                if getter in original and getter not in compiled:
                    mapped = getter
            elif name.startswith("set_"):
                setter = f"{prefix}/setter {name[4:]}"
                if setter in original and setter not in compiled:
                    mapped = setter

        while mapped in out:
            mapped += "+"
        out[mapped] = value
    return out


def residual_category(status: str, key: str, cause: str = "") -> str:
    cls = method_key_class(key) or key
    if cls.startswith(PORT_SURFACE_PREFIXES):
        return "expected port/platform additions"
    if cls.startswith(HAXE_SURFACE_PREFIXES) or cls in HAXE_ROOT_SURFACE:
        return "Haxe stdlib/runtime surface mismatch"
    if status == "extra" and "." in cls and not cls.startswith(("class_", "package_")):
        return "expected port/platform additions"
    if status == "missing" and (cls.startswith("class_728") or cls.startswith("XML")):
        return "XML runtime surface mismatch"
    if status == "signature":
        return "original game signature deltas"
    if status == "code":
        if "getlex pkg::N" in cause or "getlex pkg:port.runtime::As3" in cause:
            return "Haxe helper/codegen bytecode shape"
        return "original game code-shape deltas"
    return "uncategorized residual"


def residual_focus(status: str, key: str, cause: str = "") -> str:
    cls = method_key_class(key) or key
    if cls.startswith(PORT_SURFACE_PREFIXES):
        return "expected port/platform surface"
    if cls.startswith(HAXE_SURFACE_PREFIXES) or cls in HAXE_ROOT_SURFACE:
        return "Haxe stdlib/runtime surface"
    if status == "missing" and (cls.startswith("class_728") or cls.startswith("XML")):
        return "XML runtime surface"
    if status == "signature":
        return "original game signatures"
    if status in ("missing", "extra"):
        return "method key alignment"
    if status != "code":
        return "other residual"

    if ("getlex pkg::N" in cause or "findpropstrict pkg::N" in cause
            or "getlex private::N" in cause or "pushscope | getproperty" in cause):
        return "lookup/prologue codegen"
    if (cause.startswith("operand: if") or cause == "operand: jump L"
            or cause.endswith("| jump L") or "| jump L" in cause):
        return "branch/control-flow shape"
    if "setlocal" in cause or "setproperty" in cause or "initproperty" in cause:
        return "local or property store conversion"
    if cause.startswith("callproperty ns::N") or "haxe:IMap" in cause:
        return "namespace call shape"
    if re.search(r"push(?:byte|short|int|uint|double) v", cause):
        return "numeric literal spelling"
    if "construct 0 | pushdouble v" in cause:
        return "constructor argument shape"
    if "coerce" in cause or "astype" in cause or "convert_" in cause:
        return "cast/conversion shape"
    return "unclassified game code-shape"


def add_residual_categories(report: dict, sample_limit: int = 8) -> dict:
    buckets: dict[str, dict] = {}
    focus_buckets: dict[str, dict] = {}
    for key, item in report.get("methods", {}).items():
        status = item.get("status", "")
        if status in ("equal", "equivalent", "splice"):
            continue
        category = residual_category(status, key, item.get("cause", ""))
        bucket = buckets.setdefault(category, {"count": 0, "statuses": Counter(), "samples": []})
        bucket["count"] += 1
        bucket["statuses"][status] += 1
        if len(bucket["samples"]) < sample_limit:
            bucket["samples"].append(key)

        focus = residual_focus(status, key, item.get("cause", ""))
        focus_bucket = focus_buckets.setdefault(focus, {"count": 0, "statuses": Counter(), "samples": []})
        focus_bucket["count"] += 1
        focus_bucket["statuses"][status] += 1
        if len(focus_bucket["samples"]) < sample_limit:
            focus_bucket["samples"].append(key)
    report["residual_categories"] = [
        {
            "category": name,
            "count": bucket["count"],
            "statuses": dict(bucket["statuses"].most_common()),
            "samples": bucket["samples"],
        }
        for name, bucket in sorted(buckets.items(), key=lambda item: (-item[1]["count"], item[0]))
    ]
    report["residual_focus"] = [
        {
            "focus": name,
            "count": bucket["count"],
            "statuses": dict(bucket["statuses"].most_common()),
            "samples": bucket["samples"],
        }
        for name, bucket in sorted(focus_buckets.items(), key=lambda item: (-item[1]["count"], item[0]))
    ]
    return report


def append_residual_categories(markdown: str, report: dict) -> str:
    categories = report.get("residual_categories") or []
    if not categories:
        return markdown
    lines = [markdown.rstrip(), "", "## P3 residual categories", "", "| Count | Category | Statuses | Sample |",
             "| --- | --- | --- | --- |"]
    for item in categories:
        statuses = ", ".join(f"{key} {value}" for key, value in item["statuses"].items())
        sample = item["samples"][0] if item["samples"] else ""
        lines.append(f"| {item['count']} | `{item['category']}` | {statuses} | `{sample}` |")
    focus = report.get("residual_focus") or []
    if focus:
        lines.extend(["", "## P3 residual focus", "", "| Count | Focus | Statuses | Sample |",
                      "| --- | --- | --- | --- |"])
        for item in focus:
            statuses = ", ".join(f"{key} {value}" for key, value in item["statuses"].items())
            sample = item["samples"][0] if item["samples"] else ""
            lines.append(f"| {item['count']} | `{item['focus']}` | {statuses} | `{sample}` |")
    return "\n".join(lines) + "\n"


def full_flash_args(work: Path, swf: Path, *, emit_output: bool) -> list[str]:
    args = [
        str(HAXE),
        "--cwd", str(work),
        "--class-path", "src",
        "--macro", FULL_INCLUDE_MACRO,
        "--main", "port.runtime.FlashBoot",
        "--swf", str(swf),
        "--swf-version", "32",
        "--macro", FLASH_KEEP_MACRO,
    ]
    for define in os.environ.get("PORT_HAXE_DEFINES", "").split():
        args.extend(["-D", define])
    if not emit_output:
        args.append("--no-output")
    return args


INITPROPERTY_RE = re.compile(r"^initproperty (?:\S*:)?([A-Za-z_$][\w$]*)$")


def field_init_order_table(original_methods: dict[str, dict], version: str | None = None) -> dict[str, list[str]]:
    class_alias: dict[str, str] = {}
    member_alias: dict[str, set[str]] = {}
    readable = ROOT / "client" / "symbols" / f"{version or VERSION}.aliases.json"
    if readable.exists():
        for item in json.loads(readable.read_text(encoding="utf-8")).get("aliases", []):
            renamed, alias = item.get("renamed"), item.get("alias")
            if not renamed or not alias:
                continue
            if item.get("kind") == "class":
                class_alias[renamed.rsplit(".", 1)[-1]] = alias
            elif "." in renamed:
                member_alias.setdefault(renamed.rsplit(".", 1)[-1], set()).add(alias)
    table: dict[str, list[str]] = {}
    for key, method in original_methods.items():
        if not key.endswith("/iinit"):
            continue
        cls = key[: -len("/iinit")].rsplit(".", 1)[-1]
        names = []
        for line in (method or {}).get("code") or []:
            match = INITPROPERTY_RE.match(line)
            if match:
                name = match.group(1)
                aliases = member_alias.get(name)
                names.append(next(iter(aliases)) if aliases and len(aliases) == 1 else name)
        if names:
            table[class_alias.get(cls, cls)] = names
    return table


HOISTED_PROLOGUE_KINDS = {"pushnan": "nan", "pushfalse": "false", "pushbyte 0": "int"}


def hoisted_locals_table(original_methods: dict[str, dict],
                         names: dict[str, str] | None = None) -> dict[str, dict[str, str]]:
    names = names or {}
    table: dict[str, dict[str, str]] = {}
    clashes: set[str] = set()
    for key, method in original_methods.items():
        parts = key.split("/")
        if len(parts) != 3 or not parts[2].startswith("method "):
            continue
        code = (method or {}).get("code") or []
        i = 2 if code[:2] == ["getlocal 0", "pushscope"] else 0
        if (code[i:i + 2] == ["newactivation", "dup"] and code[i + 2:i + 3]
                and code[i + 2].startswith("setlocal ") and code[i + 3:i + 4] == ["pushscope"]):
            i += 4
        registers: dict[str, str] = {}
        while i + 1 < len(code):
            if code[i] in HOISTED_PROLOGUE_KINDS and code[i + 1].startswith("setlocal "):
                registers[code[i + 1].split()[1]] = HOISTED_PROLOGUE_KINDS[code[i]]
                i += 2
            elif code[i:i + 2] == ["pushbyte 0", "convert_u"] and code[i + 2:i + 3] and code[i + 2].startswith("setlocal "):
                registers[code[i + 2].split()[1]] = "uint"
                i += 3
            elif code[i:i + 2] == ["pushnull", "coerce_a"] and code[i + 2:i + 3] and code[i + 2].startswith("setlocal "):
                registers[code[i + 2].split()[1]] = "*"
                i += 3
            elif (code[i] == "pushnull" and code[i + 1].startswith("astype ") and i + 2 < len(code)
                  and code[i + 2].startswith("setlocal ")):
                kind = "Vector" if "::Vector.<" in code[i + 1] else re.split(r"[:.]", code[i + 1])[-1]
                if re.fullmatch(r"class_\d+", kind):
                    kind = names.get(kind, kind)
                registers[code[i + 2].split()[1]] = kind
                i += 3
            else:
                break
        class_name = parts[0].rsplit('.', 1)[-1]
        method_name = parts[2].split(' ', 1)[1]
        if re.fullmatch(r"class_\d+", class_name):
            class_name = names.get(class_name, class_name)
        name = f"{class_name}/{names.get(method_name, method_name)}"
        if name in table and table[name] != registers:
            clashes.add(name)
        if registers:
            table[name] = registers
    for name in clashes:
        table.pop(name, None)
    return table


_RMW_OPS = {"add": "+", "add_i": "+", "subtract": "-", "subtract_i": "-", "multiply": "*", "multiply_i": "*",
            "divide": "/", "modulo": "%", "bitor": "|", "bitand": "&", "bitxor": "^", "lshift": "<<",
            "rshift": ">>", "urshift": ">>>", "increment": "++", "increment_i": "++", "decrement": "--",
            "decrement_i": "--"}


def _receiver_expression(code: list[str], j: int, names: dict[str, str]) -> tuple[str, int] | None:
    if j < 0:
        return None
    ins = code[j]
    if re.fullmatch(r"coerce (?:pkg|ns):[\w.$]*::[\w$.<>:]+", ins):
        return _receiver_expression(code, j - 1, names)
    if re.fullmatch(r"getlocal \d+", ins):
        return f"@{ins.split()[1]}", j
    if re.fullmatch(r"getlex pkg:::[\w$]+", ins):
        cls = ins.rsplit(":", 1)[1]
        return names.get(cls, cls), j
    if ins == "getproperty {pkg:}::[]":
        index = _receiver_expression(code, j - 1, names)
        target = _receiver_expression(code, index[1] - 1, names) if index else None
        return (f"{target[0]}[{index[0]}]", target[1]) if target else None
    read = re.fullmatch(r"getproperty pkg:::([\w$]+)", ins)
    if not read:
        return None
    field = names.get(read.group(1), read.group(1))
    if j >= 1 and code[j - 1] == f"findproperty pkg:::{read.group(1)}":
        return field, j - 1
    target = _receiver_expression(code, j - 1, names)
    return (f"{target[0]}.{field}", target[1]) if target else None


def _rmw_op(code: list[str], start: int, raw_field: str) -> str | None:
    stores = (f"setproperty pkg:::{raw_field}", f"initproperty pkg:::{raw_field}")
    for k in range(start + 2, len(code)):
        ins = code[k]
        if ins in ("returnvoid", "returnvalue") or (ins == f"getproperty pkg:::{raw_field}" and code[k - 1] == "dup"):
            return None
        if ins in stores:
            m = k - 1
            while m > start and code[m].split(" ", 1)[0] in ("convert_d", "convert_i", "convert_u", "coerce_a",
                                                             "coerce", "dup", "setlocal", "kill"):
                m -= 1
            return _RMW_OPS.get(code[m].split(" ", 1)[0])
    return None


def temp_receivers_table(original_methods: dict[str, dict],
                         names: dict[str, str] | None = None) -> dict[str, dict[str, list[list[str | None]]]]:
    names = names or {}
    table: dict[str, dict[str, list[list[str | None]]]] = {}
    clashes: set[str] = set()
    field = re.compile(r"getproperty pkg:::([\w$]+)$")
    for key, method in original_methods.items():
        parts = key.split("/")
        if len(parts) != 3 or not parts[2].startswith("method "):
            continue
        code = (method or {}).get("code") or []
        receivers: dict[str, list[list[str | None]]] = {}
        for i, line in enumerate(code):
            read = field.match(code[i + 1]) if line == "dup" and i + 1 < len(code) else None
            if not read:
                continue
            op = _rmw_op(code, i, read.group(1))
            if op is None:
                continue
            head = _receiver_expression(code, i - 1, names)
            receivers.setdefault(names.get(read.group(1), read.group(1)), []).append([head[0] if head else None, op])
        class_name = parts[0].rsplit('.', 1)[-1]
        method_name = parts[2].split(' ', 1)[1]
        if re.fullmatch(r"class_\d+", class_name):
            class_name = names.get(class_name, class_name)
        name = f"{class_name}/{names.get(method_name, method_name)}"
        if name in table and table[name] != receivers:
            clashes.add(name)
        if receivers:
            table[name] = receivers
    for name in clashes:
        table.pop(name, None)
    return table


_STACK_PUSH = {"getlocal", "getlex", "pushbyte", "pushshort", "pushint", "pushuint", "pushdouble", "pushstring",
               "pushnull", "pushtrue", "pushfalse", "pushnan", "pushundefined", "findpropstrict", "findproperty"}
_STACK_UNARY = {"coerce", "coerce_a", "coerce_s", "convert_i", "convert_u", "convert_d", "convert_b", "not",
                "negate", "negate_i", "increment", "increment_i", "decrement", "decrement_i", "bitnot", "astype"}
_STACK_BINARY = {"add", "subtract", "multiply", "divide", "modulo", "bitand", "bitor", "bitxor", "lshift", "rshift",
                 "urshift", "add_i", "subtract_i", "multiply_i"}
_FIELD_READ_RE = re.compile(r"(?:getproperty|getlex) pkg:::([\w$]+)$")
_ELEMENT_COERCE_RE = re.compile(r"coerce (?:pkg|ns):([\w.$]*)::([\w$]+)$")
_VECTOR_ELEMENT_COERCE_RE = re.compile(r"coerce pkg:__AS3__\.vec::Vector\.<pkg:::([A-Za-z_][\w$]*)>$")
MINED_ARRAY_REFERENCE_LOCALS = True
MINED_CONSTRUCTOR_REFERENCE_LOCALS = True
_REFERENCE_STORE_RE = re.compile(r"(coerce|astype) (?:pkg|ns):([\w.$]*)::([\w$]+)$")
MINED_VECTOR_REFERENCE_LOCALS = True
_VECTOR_REFERENCE_STORE_RE = re.compile(r"(coerce|astype) pkg:__AS3__\.vec::Vector\.<pkg:::([A-Za-z_][\w$]*)>$")
ELEMENT_CONTAINERS = {"Array": "arr", "StringMap": "map", "IntMap": "map"}
_MAP_RECEIVER_COERCES = {"coerce pkg:haxe.ds::IntMap", "coerce pkg:haxe.ds::StringMap", "coerce pkg:haxe::IMap"}
_MAP_SPEC_COERCES = {"coerce pkg:haxe.ds::IntMap", "coerce pkg:haxe.ds::StringMap"}


def _stack_effect(ins: str) -> tuple[int, int] | None:
    op = ins.split(" ", 1)[0]
    if op in _STACK_PUSH:
        return 0, 1
    if op in _STACK_UNARY:
        return 1, 1
    if op in _STACK_BINARY:
        return 2, 1
    if op == "getproperty":
        return (2, 1) if ins.endswith("::[]") else (1, 1)
    if op in ("callproperty", "constructprop"):
        return int(ins.rsplit(" ", 1)[1]) + 1, 1
    return None


_INT_CONSUMERS = {"add_i", "subtract_i", "multiply_i", "negate_i", "increment_i", "decrement_i", "convert_i",
                  "convert_u"}


def _consumer(code: list[str], start: int) -> str | None:
    depth = 1
    for ins in code[start + 1:]:
        op = ins.split(" ", 1)[0]
        if op == "jump":
            return "jump"
        effect = _stack_effect(ins)
        if effect is None:
            return None
        if effect[0] >= depth:
            return op
        depth += effect[1] - effect[0]
    return None


def _int_consumed(code: list[str], start: int) -> bool:
    consumer = _consumer(code, start)
    if consumer == "jump":
        return _join(code, start) != "convert_d"
    return consumer in _INT_CONSUMERS


def _join(code: list[str], start: int) -> str | None:
    for ins in code[start + 1:]:
        if ins.startswith("jump "):
            match = re.fullmatch(r"jump L(\d+)", ins)
            target = int(match.group(1)) if match else -1
            return code[target] if 0 <= target < len(code) else None
    return None


def _expression_start(code: list[str], end: int) -> int | None:
    need = 1
    for i in range(end, -1, -1):
        effect = _stack_effect(code[i])
        if effect is None:
            return None
        need += effect[0] - effect[1]
        if need == 0:
            return i
    return None


def _read_field(code: list[str], end: int) -> str | None:
    match = _FIELD_READ_RE.match(code[end])
    if match:
        return match.group(1)
    if not code[end].startswith("getlocal ") or code[end] == "getlocal 0":
        return None
    store = "setlocal " + code[end].split()[1]
    for j in range(end - 1, -1, -1):
        if code[j] == store:
            k = j - 1
            while k >= 0 and (code[k].startswith("coerce ") or code[k] == "coerce_a"):
                k -= 1
            match = _FIELD_READ_RE.match(code[k]) if k >= 0 else None
            return match.group(1) if match else None
    return None


def _own_field_read(code: list[str], end: int) -> str | None:
    match = _FIELD_READ_RE.match(code[end])
    if not match:
        return None
    if code[end].startswith("getlex "):
        return match.group(1)
    field = match.group(1)
    if end > 0 and code[end - 1] in ("getlocal 0", f"findproperty pkg:::{field}", f"findpropstrict pkg:::{field}"):
        return field
    return None


WIDE_ELEMENT_TYPES = {"Object": "EnumValue", "Array": "Array<Dynamic>",
                      "haxe.IMap": "haxe.Constraints.IMap<Dynamic, Dynamic>"}


def element_types_table(original_methods: dict[str, dict], declarations: dict[str, list[tuple[str, str]]],
                        names: dict[str, str] | None = None, ambiguous: set[str] = frozenset(),
                        parents: dict[str, str] | None = None) -> dict[str, dict]:
    names = names or {}
    seen: dict[str, Counter] = {}
    double_stores: dict[str, dict[str, list[str]]] = {}
    uint_consts: dict[str, dict[str, int]] = {}
    double_literals: dict[str, dict[str, list]] = {}
    class_seen: dict[str, Counter] = {}
    local_seen: dict[str, dict[str, Counter]] = {}
    nested_seen: dict[str, Counter] = {}
    local_nested_seen: dict[str, dict[str, Counter]] = {}
    reference_seen: dict[str, dict[str, Counter]] = {}
    spec_seen: dict[str, Counter] = {}
    class_spec_seen: dict[str, Counter] = {}
    local_spec_seen: dict[str, dict[str, Counter]] = {}
    clashes: set[str] = set()
    for key, method in original_methods.items():
        code = (method or {}).get("code") or []
        parts = key.split("/")
        method_key = None
        if len(parts) == 3 and parts[2].startswith("method "):
            class_name = parts[0].rsplit(".", 1)[-1]
            method_name = parts[2].split(" ", 1)[1]
            method_key = f"{names.get(class_name, class_name)}/{names.get(method_name, method_name)}"
        method_class = names.get(parts[0].rsplit(".", 1)[-1], parts[0].rsplit(".", 1)[-1]) if parts[0] else None
        own: dict[str, Counter] = {}
        own_spec: dict[str, Counter] = {}
        own_nested: dict[str, Counter] = {}
        for i, ins in enumerate(code):
            if ins != "getproperty pkg:::h" or i < 2:
                continue
            spec = code[i - 1].rsplit("::", 1)[-1] if code[i - 1] in _MAP_SPEC_COERCES else "-"
            receiver = i - 1
            while receiver > 0 and code[receiver] in _MAP_RECEIVER_COERCES:
                receiver -= 1
            field = _FIELD_READ_RE.match(code[receiver])
            if field:
                spec_seen.setdefault(field.group(1), Counter())[spec] += 1
                owner = None
                if code[receiver].startswith("getproperty ") and receiver > 0 and re.fullmatch(r"getlex pkg:::[\w$]+", code[receiver - 1]):
                    owner = names.get(code[receiver - 1][13:], code[receiver - 1][13:])
                elif method_class and _own_field_read(code, receiver):
                    owner = method_class
                if owner:
                    class_spec_seen.setdefault(f"{owner}/{field.group(1)}", Counter())[spec] += 1
            elif re.fullmatch(r"getlocal [1-9]\d*", code[receiver]):
                own_spec.setdefault(code[receiver].split()[1], Counter())[spec] += 1
        for i, ins in enumerate(code):
            if ins == "getproperty {pkg:}::[]":
                kind = "arr"
            elif ins in ("callproperty pkg:::getReserved 1", "callproperty pkg:::method_4935 1",
                         "callproperty ns:haxe:IMap::method_4935 1"):
                kind = "map"
            else:
                continue
            start = _expression_start(code, i - 1)
            if not start:
                continue
            receiver = start - 1
            if kind == "arr" and code[receiver] == "getproperty pkg:::h":
                kind, receiver = "map", receiver - 1
            while kind == "map" and receiver > 0 and code[receiver] in _MAP_RECEIVER_COERCES:
                receiver -= 1
            match = _ELEMENT_COERCE_RE.match(code[i + 1]) if i + 1 < len(code) else None
            if match and not match.group(1):
                element = match.group(2)
            elif match and match.group(1).startswith("flash."):
                element = f"{match.group(1)}.{match.group(2)}"
            elif match and match.group(1) == "haxe" and match.group(2) == "IMap":
                element = "haxe.IMap"
            elif i + 1 < len(code) and _VECTOR_ELEMENT_COERCE_RE.match(code[i + 1]):
                element = "Vector.<" + _VECTOR_ELEMENT_COERCE_RE.match(code[i + 1]).group(1) + ">"
            else:
                element = "!" + "".join(code[i + 1:i + 2])
            field = _read_field(code, receiver)
            if field:
                seen.setdefault(f"{kind} {field}", Counter())[element] += 1
            own_field = _own_field_read(code, receiver)
            if own_field and method_class:
                class_seen.setdefault(f"{kind} {method_class}/{own_field}", Counter())[element] += 1
            if re.fullmatch(r"getlocal [1-9]\d*", code[receiver]):
                own.setdefault(code[receiver].split()[1], Counter())[element] += 1
            if kind == "map" and element == "haxe.IMap" and i + 2 < len(code):
                nested = code[i + 2:i + 4]
                if nested[0] in _MAP_SPEC_COERCES and nested[1:] == ["getproperty pkg:::h"]:
                    spec = nested[0].rsplit("::", 1)[-1]
                else:
                    spec = "-" if nested[0] == "getproperty pkg:::h" else None
                if spec and field:
                    nested_seen.setdefault(field, Counter())[spec] += 1
                if spec and re.fullmatch(r"getlocal [1-9]\d*", code[receiver]):
                    own_nested.setdefault(code[receiver].split()[1], Counter())[spec] += 1
        if method_key and own_nested:
            if method_key in local_nested_seen and local_nested_seen[method_key] != own_nested:
                clashes.add(method_key)
            local_nested_seen[method_key] = own_nested
        if method_key and own:
            if method_key in local_seen and local_seen[method_key] != own:
                clashes.add(method_key)
            local_seen[method_key] = own
        if method_key and own_spec:
            if method_key in local_spec_seen and local_spec_seen[method_key] != own_spec:
                clashes.add(method_key)
            local_spec_seen[method_key] = own_spec
        if method_key:
            doubles: dict[str, set[str]] = {}
            ints: dict[str, set[str]] = {}
            for i, ins in enumerate(code[:-1]):
                target = re.fullmatch(r"(?:set|init)property pkg:::([\w$]+)", code[i + 1])
                if not target:
                    continue
                head, _, value = ins.partition(" ")
                if head == "pushdouble":
                    try:
                        number = float(value)
                    except ValueError:
                        continue
                    if number.is_integer() and abs(number) < 2 ** 31 and not (number == 0 and str(number)[0] == "-"):
                        doubles.setdefault(target.group(1), set()).add(str(int(number)))
                elif head in ("pushbyte", "pushshort", "pushint", "pushuint"):
                    ints.setdefault(target.group(1), set()).add(value)
            stores = {name: sorted(values - ints.get(name, set()), key=int) for name, values in doubles.items()}
            stores = {name: values for name, values in stores.items() if values}
            if stores:
                if method_key in double_stores and double_stores[method_key] != stores:
                    clashes.add(method_key)
                double_stores[method_key] = stores
            consts: Counter = Counter()
            for i, ins in enumerate(code[:-2]):
                if (ins.startswith("pushuint ") and code[i + 1] == "convert_u"
                        and re.match(r"(?:setlocal|setproperty|initproperty) ", code[i + 2])):
                    consts[ins.split(" ", 1)[1]] += 1
            if consts:
                if method_key in uint_consts and uint_consts[method_key] != dict(consts):
                    clashes.add(method_key)
                uint_consts[method_key] = dict(consts)
            values: list[float | None] = []
            doubles: list[int] = []
            uints: list[int] = []
            for i, ins in enumerate(code):
                kind, _, operand = ins.partition(" ")
                if kind not in ("pushbyte", "pushshort", "pushint", "pushuint", "pushdouble"):
                    continue
                try:
                    number = float(operand)
                except ValueError:
                    number = None
                stored = re.fullmatch(r"(?:set|init)property pkg:::([\w$]+)", code[i + 1]) if i + 1 < len(code) else None
                if (kind == "pushdouble" and number is not None and number.is_integer() and abs(number) < 2 ** 53
                        and not (number == 0 and operand.startswith("-"))
                        and (i + 1 >= len(code) or code[i + 1] not in ("convert_i", "convert_u"))
                        and not _int_consumed(code, i)
                        and not (stored and any(typ in ("int", "uint")
                                                for _cls, typ in declarations.get(stored.group(1), [])))):
                    doubles.append(len(values))
                if (kind == "pushuint" and number is not None and 0 <= number < 2 ** 31
                        and (i + 1 >= len(code) or code[i + 1] != "convert_u")
                        and _consumer(code, i) not in _STACK_BINARY):
                    uints.append(len(values))
                values.append(number)
            if doubles or uints:
                entry = {"values": values, "doubles": doubles}
                if uints:
                    entry["uints"] = uints
                if method_key in double_literals and double_literals[method_key] != entry:
                    clashes.add(method_key)
                double_literals[method_key] = entry
        stores: dict[str, Counter] = {}
        for i, ins in enumerate(code[1:], 1):
            store = re.fullmatch(r"setlocal ([1-9]\d*)", ins)
            if not store:
                continue
            previous = code[i - 1]
            typed = _REFERENCE_STORE_RE.match(previous)
            vector = _VECTOR_REFERENCE_STORE_RE.match(previous) if MINED_VECTOR_REFERENCE_LOCALS else None
            if vector:
                stores.setdefault(store.group(1), Counter())[("astype " if vector.group(1) == "astype" else "")
                                                             + f"Vector.<{vector.group(2)}>"] += 1
            elif typed and (not typed.group(2) or typed.group(2).startswith("flash.")):
                element = f"{typed.group(2)}.{typed.group(3)}" if typed.group(2) else typed.group(3)
                stores.setdefault(store.group(1), Counter())[("astype " if typed.group(1) == "astype" else "")
                                                             + element] += 1
            elif previous in ("coerce_s", "coerce_a", "coerce_i", "coerce_u", "coerce_d", "coerce_b") \
                    or previous.startswith(("convert_", "coerce ", "astype ")):
                stores.setdefault(store.group(1), Counter())["!" + previous] += 1
        reference_key = method_key
        if (MINED_CONSTRUCTOR_REFERENCE_LOCALS and reference_key is None and len(parts) == 2 and parts[1] == "iinit"
                and method_class):
            reference_key = f"{method_class}/{method_class}"
        if reference_key and stores:
            if reference_key in reference_seen and reference_seen[reference_key] != stores:
                clashes.add(reference_key)
            reference_seen[reference_key] = stores

    def single(kinds: Counter, wide: bool = False) -> str | None:
        element = next(iter(kinds)) if len(kinds) == 1 else None
        if wide and element in WIDE_ELEMENT_TYPES:
            return WIDE_ELEMENT_TYPES[element]
        vector = re.fullmatch(r"Vector\.<([A-Za-z_][\w$]*)>", element or "")
        if vector:
            inner = vector.group(1)
            inner = {"int": "Int", "uint": "UInt", "Number": "Float", "Boolean": "Bool"}.get(inner, inner)
            if inner in ambiguous or inner in ("Object", "Function", "Class", "void"):
                return None
            return f"Vector<{names.get(inner, inner)}>"
        if (not element or not re.fullmatch(r"(?:flash(?:\.[a-z]\w*)+\.)?[A-Za-z_][\w$]*", element) or element in ambiguous
                or element in ("Object", "Array", "Function")):
            return None
        return names.get(element, element)

    fields: dict[str, dict[str, str]] = {}
    maps: dict[str, str] = {}
    for key, kinds in seen.items():
        kind, field = key.split(" ", 1)
        owners = declarations.get(field) or []
        element = single(kinds, wide=True)
        if (len(owners) == 1 and ELEMENT_CONTAINERS.get(owners[0][1]) == kind and element
                and not element.startswith("haxe.Constraints.IMap")):
            fields[field] = {"class": owners[0][0], "type": owners[0][1], "element": element}
        elif owners and all(typ == "IMap" for _cls, typ in owners) and kind == "map" and element:
            maps[field] = element
    class_fields: dict[str, dict[str, str]] = {}
    for key, kinds in class_seen.items():
        kind, owner_field = key.split(" ", 1)
        owner, field = owner_field.split("/", 1)
        owners = declarations.get(field) or []
        declared = [typ for cls, typ in owners if cls == owner]
        element = single(kinds, wide=True)
        if (len(owners) > 1 and len(declared) == 1 and ELEMENT_CONTAINERS.get(declared[0]) == kind and element
                and not element.startswith("haxe.Constraints.IMap") and element not in WIDE_ELEMENT_TYPES.values()):
            class_fields[owner_field] = {"class": owner, "type": declared[0], "element": element}
    locals_: dict[str, dict[str, str]] = {}
    for method_key, registers in local_seen.items():
        if method_key in clashes:
            continue
        typed = {register: single(kinds, wide=True) for register, kinds in registers.items()}
        typed = {register: element for register, element in typed.items() if element}
        if typed:
            locals_[method_key] = typed
    references: dict[str, dict[str, str]] = {}
    for method_key, registers in reference_seen.items():
        if method_key in clashes:
            continue
        typed = {}
        for register, kinds in registers.items():
            classes = {kind.removeprefix("astype ") for kind in kinds}
            if len(classes) != 1 or not any(kind.startswith("astype ") for kind in kinds):
                continue
            element = "Object" if classes == {"Object"} and "Object" in kinds else single(Counter(classes))
            if MINED_ARRAY_REFERENCE_LOCALS and classes == {"Array"}:
                element = "Array"
            vector = re.fullmatch(r"Vector\.<([A-Za-z_][\w$]*)>", next(iter(classes))) if len(classes) == 1 else None
            if vector:
                inner = vector.group(1)
                element = (None if inner in ambiguous or inner in ("Object", "Function", "Class", "void")
                           else f"Vector.<{names.get(inner, inner)}>")
            if element and element != "String":
                typed[register] = element
        if typed:
            references[method_key] = typed
    string_locals: dict[str, list[str]] = {}
    for method_key, registers in reference_seen.items():
        if method_key in clashes:
            continue
        typed = sorted((register for register, kinds in registers.items()
                        if "astype String" in kinds and set(kinds) <= {"astype String", "String", "!coerce_s"}),
                       key=int)
        if typed:
            string_locals[method_key] = typed
    spec_fields = {}
    for field, kinds in spec_seen.items():
        owners = declarations.get(field) or []
        if len(kinds) == 1 and next(iter(kinds)) != "-" and [typ for _cls, typ in owners].count("IMap") == 1:
            spec_fields[field] = next(iter(kinds))
    spec_class_fields = {}
    for owner_field, kinds in class_spec_seen.items():
        owner, field = owner_field.split("/", 1)
        owners = declarations.get(field) or []
        if (field not in spec_fields and len(kinds) == 1 and next(iter(kinds)) != "-"
                and [typ for cls, typ in owners if cls == owner] == ["IMap"]):
            spec_class_fields[owner_field] = next(iter(kinds))
    spec_locals: dict[str, dict[str, str]] = {}
    for method_key, registers in local_spec_seen.items():
        if method_key in clashes:
            continue
        typed = {register: next(iter(kinds)) for register, kinds in registers.items()
                 if len(kinds) == 1 and next(iter(kinds)) != "-"}
        if typed:
            spec_locals[method_key] = typed
    arrays = sorted(name for name, owners in declarations.items()
                    if len(owners) == 1 and (owners[0][1] == "Array" or owners[0][1].startswith("Vector.<")))
    strings = sorted(name for name, owners in declarations.items() if len(owners) == 1 and owners[0][1] == "String")
    nested_fields = {field: next(iter(kinds)) for field, kinds in nested_seen.items()
                     if len(kinds) == 1 and next(iter(kinds)) != "-"}
    nested_locals: dict[str, dict[str, str]] = {}
    for method_key, registers in local_nested_seen.items():
        typed = {register: next(iter(kinds)) for register, kinds in registers.items()
                 if len(kinds) == 1 and next(iter(kinds)) != "-"}
        if typed and method_key not in clashes:
            nested_locals[method_key] = typed
    return {"fields": fields, "class_fields": class_fields, "locals": locals_, "maps": maps, "arrays": arrays, "strings": strings,
            "references": references, "string_locals": string_locals,
            "double_stores": {key: value for key, value in double_stores.items() if key not in clashes},
            "uint_consts": {key: value for key, value in uint_consts.items() if key not in clashes},
            "double_literals": {key: value for key, value in double_literals.items() if key not in clashes},
            "double_store_int_owners": double_store_int_owners(
                {name for key, value in double_stores.items() if key not in clashes for name in value},
                declarations, parents or {}),
            "double_store_receiver_fields": {
                name: types.pop() for name, owners in declarations.items()
                if len(types := {typ for _cls, typ in owners}) == 1
                and next(iter(types)) not in ("int", "uint", "Number", "String", "Boolean", "*", "Object", "Array")},
            "map_specs": {"fields": spec_fields, "class_fields": spec_class_fields, "locals": spec_locals},
            "nested_specs": {"fields": nested_fields, "locals": nested_locals}}


def double_store_int_owners(names: set[str], declarations: dict[str, list[tuple[str, str]]],
                            parents: dict[str, str]) -> dict[str, list[str]]:
    owners: dict[str, list[str]] = {}
    for name in sorted(names):
        roots = {cls for cls, typ in declarations.get(name, []) if typ in ("int", "uint")}
        if not roots:
            continue
        found = set(roots)
        for cls in parents:
            seen, parent = set(), cls
            while parent in parents and parent not in seen and parent not in found:
                seen.add(parent)
                parent = parents[parent]
            if parent in found:
                found.add(cls)
        owners[name] = sorted(found)
    return owners


def game_as3_files(scripts: Path) -> list[Path]:
    return sorted(p for p in scripts.rglob("*.as") if p.relative_to(scripts).parts[0] != "bh")


def as3_class_parents(scripts: Path) -> dict[str, str]:
    parents: dict[str, str] = {}
    pattern = re.compile(r"^\s*(?:(?:public|internal|final|dynamic)\s+)*class\s+([\w$]+)\s+extends\s+([\w.$]+)", re.M)
    for path in game_as3_files(scripts):
        for match in pattern.finditer(path.read_text(encoding="utf-8", errors="replace")):
            parents[match.group(1)] = match.group(2).rsplit(".", 1)[-1]
    return parents


def as3_field_declarations(scripts: Path) -> dict[str, list[tuple[str, str]]]:
    declarations: dict[str, list[tuple[str, str]]] = {}
    pattern = re.compile(r"^      (?:(?:public|private|protected|internal|static|override)\s+)+var\s+([\w$]+)\s*:\s*"
                         r"([\w.$<>*]+)", re.M)
    for path in game_as3_files(scripts):
        for match in pattern.finditer(path.read_text(encoding="utf-8", errors="replace")):
            declarations.setdefault(match.group(1), []).append((path.stem, match.group(2)))
    return declarations


def as3_method_return_declarations(scripts: Path) -> dict[str, list[tuple[str, str]]]:
    declarations: dict[str, list[tuple[str, str]]] = {}
    pattern = re.compile(r"^\s+(?:(?:public|private|protected|internal|static|override|final)\s+)*function\s+"
                         r"(?!get\s|set\s)([\w$]+)\s*\([^)]*\)\s*:\s*([\w.$<>*]+)", re.M)
    for path in game_as3_files(scripts):
        for match in pattern.finditer(path.read_text(encoding="utf-8", errors="replace")):
            declarations.setdefault(match.group(1), []).append((path.stem, match.group(2)))
    return declarations


def as3_method_parameters(scripts: Path) -> dict[str, list[tuple[str, list[str]]]]:
    declarations: dict[str, list[tuple[str, list[str]]]] = {}
    pattern = re.compile(r"^\s+((?:(?:public|private|protected|internal|static|override|final)\s+)*)function\s+"
                         r"(?!get\s|set\s)([\w$]+)\s*\(([^)]*)\)", re.M)
    for path in game_as3_files(scripts):
        for match in pattern.finditer(path.read_text(encoding="utf-8", errors="replace")):
            types = []
            for param in (p.strip() for p in match.group(3).split(",") if p.strip()):
                typed = re.match(r"[\w$]+\s*:\s*([\w.$<>*]+)", param)
                types.append(typed.group(1) if typed else "*")
            owner = ("!" if "override" in match.group(1) else "") + path.stem
            declarations.setdefault(match.group(2), []).append((owner, types))
    return declarations


def container_parameters(locals_: dict[str, dict[str, str]],
                         parameters: dict[str, list[tuple[str, list[str]]]]) -> dict[str, dict]:
    wide = set(WIDE_ELEMENT_TYPES.values())
    methods: dict[str, dict[str, str]] = {}
    for method_key, registers in locals_.items():
        class_name, _, name = method_key.partition("/")
        owners = [types for owner, types in parameters.get(name, []) if owner == class_name]
        if len(owners) != 1:
            continue
        typed = {register: element for register, element in registers.items()
                 if element not in wide and 0 < int(register) <= len(owners[0])
                 and owners[0][int(register) - 1] in ELEMENT_CONTAINERS}
        if typed:
            methods[method_key] = typed
    calls: dict[str, list[str]] = {}
    for method_key, registers in methods.items():
        name = method_key.partition("/")[2]
        positions = [register for register in sorted(registers, key=int)
                     if all(len(types) >= int(register) and types[int(register) - 1] in ELEMENT_CONTAINERS
                            for _owner, types in parameters.get(name, []))]
        if positions:
            calls[name] = sorted(set(calls.get(name, [])) | set(positions), key=int)
    methods = {method_key: kept for method_key, registers in methods.items()
               if (kept := {register: element for register, element in registers.items()
                            if register in calls.get(method_key.partition("/")[2], [])})}
    return {"methods": methods, "calls": calls}


def string_returning_methods(declarations: dict[str, list[tuple[str, str]]]) -> list[str]:
    return sorted(name for name, owners in declarations.items()
                  if owners and all(typ == "String" for _cls, typ in owners))


CONVERSION_TABLES_KEY = "conversion-tables.key"


def conversion_tables_key(original: Path, symbols: Path) -> str:
    from tools import compare_methods

    here = Path(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    paths = {p for root in (ROOT, here) for p in (str(root), root.as_posix())}

    def path_free(path: Path) -> bytes:
        data = path.read_bytes()
        for p in sorted(paths, key=len, reverse=True):
            data = data.replace(p.encode("utf-8"), b"")
        return data

    digest = hashlib.sha256()
    for path in (Path(__file__), Path(as3_to_haxe.__file__), Path(compare_methods.__file__), symbols):
        digest.update(path.name.encode("utf-8") + hashlib.sha256(path_free(path)).digest())
    data = original.read_bytes()
    if data[:3] == b"CWS":
        import zlib
        data = b"FWS" + data[3:8] + zlib.decompress(data[8:])
    digest.update(hashlib.sha256(data).digest())
    scripts = scripts_path()
    for path in game_as3_files(scripts):
        digest.update(path.relative_to(scripts).as_posix().encode("utf-8") + hashlib.sha256(path.read_bytes()).digest())
    digest.update(repr((os.environ.get("PORT_NO_UNINIT_HOISTED") == "1", load_port_haxe_aliases())).encode("utf-8"))
    return digest.hexdigest()


def load_cached_conversion_tables(key: str) -> bool:
    stamp = as3_to_haxe.FIELD_INIT_ORDER_PATH.parent / CONVERSION_TABLES_KEY
    paths = (as3_to_haxe.FIELD_INIT_ORDER_PATH, as3_to_haxe.HOISTED_LOCALS_PATH, as3_to_haxe.TEMP_RECEIVERS_PATH,
             as3_to_haxe.ELEMENT_TYPES_PATH)
    if not stamp.exists() or stamp.read_text(encoding="utf-8").strip() != key or not all(p.exists() for p in paths):
        return False
    tables = [json.loads(p.read_text(encoding="utf-8")) for p in paths]
    as3_to_haxe.load_field_init_order(tables[0])
    as3_to_haxe.load_hoisted_locals(tables[1])
    as3_to_haxe.UNINIT_HOISTED_LOCALS = os.environ.get("PORT_NO_UNINIT_HOISTED") != "1"
    as3_to_haxe.load_temp_receivers(tables[2])
    as3_to_haxe.load_element_types(tables[3])
    print(f"conversion tables from the cache ({key[:12]}): {len(tables[0])} classes' store order, {len(tables[1])}"
          f" prologues, {len(tables[2])} receivers, {len(tables[3]['fields'])} element-typed fields")
    return True


def write_field_init_order() -> None:
    from tools import compare_methods

    original = base_swf()
    if not original.exists():
        return
    symbols = symbols_path()
    key = conversion_tables_key(original, symbols)
    if load_cached_conversion_tables(key):
        return
    try:
        (as3_to_haxe.FIELD_INIT_ORDER_PATH.parent / CONVERSION_TABLES_KEY).unlink(missing_ok=True)
    except PermissionError:
        pass
    ns_aliases = compare_methods.load_class_names(symbols)
    original_methods, _ = load_original_comparison(compare_methods, original, symbols, ns_aliases)
    table = field_init_order_table(original_methods)
    as3_to_haxe.FIELD_INIT_ORDER_PATH.parent.mkdir(parents=True, exist_ok=True)
    as3_to_haxe.FIELD_INIT_ORDER_PATH.write_text(json.dumps(table, indent=0, sort_keys=True) + "\n", encoding="utf-8")
    as3_to_haxe.load_field_init_order(table)
    print(f"original constructor store order: {len(table)} classes -> {as3_to_haxe.FIELD_INIT_ORDER_PATH}")
    readable: dict[str, str] = {}
    for alias, renamed in load_port_haxe_aliases().items():
        if not alias.startswith("Class_") and alias not in COMPILED_ONLY_ALIASES:
            readable.setdefault(renamed, alias)
    hoisted = hoisted_locals_table(original_methods, readable)
    as3_to_haxe.HOISTED_LOCALS_PATH.write_text(json.dumps(hoisted, indent=0, sort_keys=True) + "\n", encoding="utf-8")
    as3_to_haxe.load_hoisted_locals(hoisted)
    as3_to_haxe.UNINIT_HOISTED_LOCALS = os.environ.get("PORT_NO_UNINIT_HOISTED") != "1"
    print(f"original block-variable prologues: {len(hoisted)} methods -> {as3_to_haxe.HOISTED_LOCALS_PATH}")
    receivers = temp_receivers_table(original_methods, readable)
    as3_to_haxe.TEMP_RECEIVERS_PATH.write_text(json.dumps(receivers, indent=0, sort_keys=True) + "\n",
                                               encoding="utf-8")
    as3_to_haxe.load_temp_receivers(receivers)
    print(f"original read-modify-write receivers: {len(receivers)} methods -> {as3_to_haxe.TEMP_RECEIVERS_PATH}")
    aliases_of = Counter(renamed for alias, renamed in load_port_haxe_aliases().items()
                         if not alias.startswith("Class_") and alias not in COMPILED_ONLY_ALIASES)
    elements = element_types_table(original_methods,
                                   as3_field_declarations(scripts_path()), readable,
                                   {renamed for renamed, count in aliases_of.items() if count > 1},
                                   as3_class_parents(scripts_path()))
    elements["params"] = container_parameters(
        elements["locals"], as3_method_parameters(scripts_path()))
    elements["string_methods"] = string_returning_methods(
        as3_method_return_declarations(scripts_path()))
    as3_to_haxe.ELEMENT_TYPES_PATH.write_text(json.dumps(elements, indent=0, sort_keys=True) + "\n", encoding="utf-8")
    as3_to_haxe.load_element_types(elements)
    print(f"original container element types: {len(elements['fields'])} fields, {len(elements['locals'])} methods' "
          f"locals, {len(elements['maps'])} IMap fields -> {as3_to_haxe.ELEMENT_TYPES_PATH}")
    (as3_to_haxe.FIELD_INIT_ORDER_PATH.parent / CONVERSION_TABLES_KEY).write_text(key + "\n", encoding="utf-8")


def full_flash_compile(*, emit_output: bool = False, out: Path | None = None, mods: list[str] | None = None) -> int:
    require_haxe()
    write_field_init_order()
    convert_tree(GENERATED)
    out = out or FULL_FLASH_SWF
    if emit_output:
        out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="bh-port-full-") as td, staged_text_cache(Path(td)):
        work = Path(td)
        src = work / "src"
        build = work / "build"
        src.mkdir(parents=True)
        build.mkdir()
        copied = copy_filtered_generated_tree(src)
        guarded = apply_net_guard(src, GENERATED, flash=True)
        stored = apply_port_storage(src, GENERATED)
        if mods:
            write_mod_list(src, mods)
        for source in sorted(RUNTIME_FLASH.rglob("*.hx")):
            staged = src / source.relative_to(RUNTIME_FLASH)
            staged.parent.mkdir(parents=True, exist_ok=True)
            staged.write_text(source.read_text(encoding="utf-8"), encoding="utf-8", newline="\n")
        if "port_smoke" in os.environ.get("PORT_HAXE_DEFINES", ""):
            apply_hl_probes(src, call="port.runtime.SmokeDriver.probe")
        native_removed, native_externs = write_flash_native_externs(src)
        externs = write_plain_field_externs(src)
        swf = out if emit_output else build / "full.swf"
        result = subprocess.run(
            full_flash_args(work, swf, emit_output=emit_output),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        print(f"full Flash compile ({tree_kind()} tree) staged {copied} generated files plus runtime helpers,"
              f" {guarded} network sites behind the guard, {stored} save-data sites on the port's own storage,"
              f" and {externs} plain-field Flash externs; {native_removed} runtime stand-ins left to the std"
              f" externs, {native_externs} AIR stand-ins staged as externs")
        if result.stdout:
            print(result.stdout.rstrip())
            print(haxe_error_summary(result.stdout))
        if result.returncode == 0:
            print("full Flash Haxe compile OK")
            if emit_output:
                try:
                    restore_package_local_qnames(out)
                    restore_enum_instance_traits(out)
                    restore_enum_script_initializers(out)
                    restore_native_script_initializers(out)
                    restore_string_default_signatures(out)
                    restore_original_signatures(out)
                    restore_swf_stage_tags(out)
                except (OSError, ValueError, KeyError, IndexError) as error:
                    print(f"emitted ABC restoration failed: {error}", file=sys.stderr)
                    return 1
                print(f"output: {out}")
        return result.returncode


NET_GUARD_SITES: list[tuple[str, str, str, int, bool]] = [
    ("HttpCall.hx", r"\bnew URLLoader\(\)", "new port.runtime.net.GuardedURLLoader()", 1, False),
    ("TcpConnection.hx", r"\bnew Socket\(\)", "new port.runtime.net.GuardedSocket()", 1, False),
    ("UdpConnection.hx", r"\bnew DatagramSocket\(\)", "new port.runtime.net.GuardedDatagramSocket()", 1, False),
    ("Class_722.hx", r"\bnew NetStream\(", "new port.runtime.net.GuardedNetStream(", 1, True),
]
NET_CLASSES_RE = re.compile(
    r"\bnew (?:flash\.net\.|openfl\.net\.)?(URLLoader|URLStream|Socket|SecureSocket|XMLSocket|DatagramSocket|"
    r"NetStream|ServerSocket|LocalConnection)\(")


def apply_net_guard(target: Path, generated: Path, *, flash: bool) -> int:
    applied = 0
    for rel, pattern, replacement, expected, flash_only in NET_GUARD_SITES:
        if flash_only and not flash:
            continue
        path = target / rel
        text, found = re.subn(pattern, replacement, path.read_text(encoding="utf-8"))
        if found != expected:
            raise ValueError(f"network guard site in {rel} matched {found} times, expected {expected}")
        path.write_text(text, encoding="utf-8", newline="\n")
        applied += found
    unguarded = []
    for path in sorted(target.rglob("*.hx")):
        rel = path.relative_to(target)
        if not (generated / rel).exists() or (RUNTIME / rel).exists():
            continue
        for m in NET_CLASSES_RE.finditer(path.read_text(encoding="utf-8")):
            if not (m.group(1) == "NetStream" and not flash):
                unguarded.append(f"{rel.as_posix()}: {m.group(0)}")
    if unguarded:
        raise ValueError("unguarded network objects in the converted game: " + "; ".join(unguarded))
    return applied


def check_native_net_engine(target: Path) -> None:
    for rel, needle in ((Path("flash/net/Socket.hx"), "NetGuard.allowHost"),
                        (Path("flash/net/DatagramSocket.hx"), "NetGuard.allowHost"),
                        (Path("flash/net/URLLoader.hx"), "port.runtime.net.GuardedURLLoader"),
                        (Path("flash/net/SharedObject.hx"), "PortStorage.PREFIX"),
                        (Path("flash/filesystem/File.hx"), "PortStorage.FOLDER")):
        path = target / rel
        if not path.exists() or needle not in path.read_text(encoding="utf-8"):
            raise ValueError(f"the engine's {rel.as_posix()} lacks {needle}: the native build would be unguarded")


STORAGE_SITES: list[tuple[str, str, int]] = [
    (r"(?<![\w.])(?:flash\.filesystem\.)?File\.applicationStorageDirectory\b",
     "port.runtime.PortStorage.storageDirectory()", 9),
    (r"(?<![\w.])(?:flash\.net\.)?SharedObject\.getLocal\(", "port.runtime.PortStorage.getLocal(", 5),
    (r"(?<![\w.])(?:flash\.filesystem\.)?File\.userDirectory\b", "port.runtime.PortStorage.userDirectory()", 3),
    (r"(?<![\w.])(?:flash\.filesystem\.)?File\.documentsDirectory\b",
     "port.runtime.PortStorage.documentsDirectory()", 1),
]


def apply_port_storage(target: Path, generated: Path) -> int:
    applied = 0
    for pattern, replacement, expected in STORAGE_SITES:
        count = 0
        for path in sorted(target.rglob("*.hx")):
            rel = path.relative_to(target)
            if not (generated / rel).exists() or (RUNTIME / rel).exists():
                continue
            text, found = re.subn(pattern, replacement, path.read_text(encoding="utf-8"))
            if found:
                path.write_text(text, encoding="utf-8", newline="\n")
                count += found
        if count != expected:
            raise ValueError(f"storage site {pattern!r} matched {count} times, expected {expected}")
        applied += count
    return applied


def tree_kind() -> str:
    return "bifrost" if BIFROST else "raw" if RAW else "platform"


def use_bifrost() -> None:
    global BIFROST, RAW, NATIVE_CONVERTED, NATIVE_GENERATED
    if not (BIFROST_TREE / "src" / "as3").exists():
        raise FileNotFoundError(f"no Bifrost tree in {BIFROST_TREE}: run python tools/bifrost_build.py tree")
    BIFROST, RAW = True, False
    NATIVE_CONVERTED = BIFROST_TREE / "build" / "native-converted"
    NATIVE_GENERATED = BIFROST_TREE / "build" / "native-src"


def convert_tree(output: Path, *, native: bool = False) -> None:
    args = (["convert", "--output", str(output), "--version", VERSION] + (["--native"] if native else [])
            + (["--raw"] if RAW else []))
    if BIFROST:
        args += ["--root", str(BIFROST_TREE)]
    only = [Path(p) for p in os.environ.get("PORT_CONVERT_ONLY", "").split(os.pathsep) if p.strip()]
    if only and output.exists():
        for source in only:
            rc = as3_to_haxe.main(args + ["--file", str(source)])
            if rc:
                raise RuntimeError(f"as3_to_haxe convert {source} failed ({rc})")
        (output / as3_to_haxe.CONVERT_KEY_FILE).write_text(f"partial-{time.time_ns()}\n", encoding="utf-8")
        print(f"converted only {len(only)} files into {output}")
        return
    rc = as3_to_haxe.main(args)
    if rc:
        raise RuntimeError(f"as3_to_haxe convert failed ({rc})")
    (output / TREE_KIND_FILE).write_text(tree_kind() + "\n", encoding="utf-8")


def check_tree_kind(output: Path) -> None:
    marker = output / TREE_KIND_FILE
    found = marker.read_text(encoding="utf-8").strip() if marker.exists() else "platform (unmarked)"
    if found != tree_kind():
        raise ValueError(f"{output} holds the {found} tree, this build wants {tree_kind()}: convert again")


def write_mod_list(target: Path, mods: list[str]) -> None:
    from tools import apply_platform

    converted, stats = as3_to_haxe.convert_text(apply_platform.mod_list(mods), "bh/platform/ModList.as")
    if stats.unsupported:
        raise ValueError(f"ModList: unsupported constructs {stats.unsupported}")
    out = target / "bh" / "platform" / "ModList.hx"
    out.write_text(converted, encoding="utf-8", newline="\n")
    print(f"mods built in: {', '.join(mods)}")


def comparison_cache_key(*paths: Path) -> str:
    digest = hashlib.sha256()
    for path in paths:
        digest.update(str(path.resolve()).encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes() if path.exists() else b"<missing>")
        digest.update(b"\0")
    return digest.hexdigest()


def load_original_comparison(compare_methods, original: Path, symbols: Path,
                             ns_aliases: dict[str, str]) -> tuple[dict[str, dict], bool]:
    key = comparison_cache_key(original, symbols, Path(compare_methods.__file__))
    try:
        payload = pickle.loads(ORIGINAL_COMPARE_CACHE.read_bytes())
        if payload.get("key") == key and set(payload.get("facts", {})) == set(ORIGINAL_FACT_NAMES):
            for name in ORIGINAL_FACT_NAMES:
                target = getattr(compare_methods, name)
                target.clear()
                target.update(payload["facts"][name])
            if compare_methods._CANONICAL is not None:
                compare_methods._CANONICAL.clear()
            print(f"original comparison cache hit: {ORIGINAL_COMPARE_CACHE}")
            return payload["methods"], True
    except (OSError, EOFError, pickle.PickleError, AttributeError, ValueError, TypeError):
        pass

    original_blocks = compare_methods.swf_blocks(original)
    compare_methods.prepare(original_blocks, ns_aliases)
    methods = compare_methods.collect(original_blocks, ns_aliases=ns_aliases)
    facts = {name: getattr(compare_methods, name).copy() for name in ORIGINAL_FACT_NAMES}
    ORIGINAL_COMPARE_CACHE.parent.mkdir(parents=True, exist_ok=True)
    ORIGINAL_COMPARE_CACHE.write_bytes(pickle.dumps({"key": key, "methods": methods, "facts": facts}, protocol=5))
    print(f"original comparison cache refreshed: {ORIGINAL_COMPARE_CACHE}")
    return methods, False


def compare_existing(out: Path | None = None) -> int:
    from tools import compare_methods

    out = out or FULL_FLASH_SWF
    if not out.exists():
        print(f"missing compiled Haxe SWF {out}: run build-flash first", file=sys.stderr)
        return 2

    original = base_swf()
    if not original.exists():
        print(f"missing comparison baseline {original}: run tools/export_as3.py first", file=sys.stderr)
        return 2
    symbols = symbols_path()
    ns_aliases = compare_methods.load_class_names(symbols)
    haxe_aliases = load_port_haxe_aliases()
    haxe_ns_aliases = {**ns_aliases, **haxe_aliases}
    original_methods, _cache_hit = load_original_comparison(compare_methods, original, symbols, ns_aliases)
    haxe_methods = compare_methods.collect(compare_methods.swf_blocks(out), haxe_aliases, haxe_ns_aliases)
    haxe_methods = align_port_haxe_methods(original_methods, haxe_methods)
    report = compare_methods.compare(
        original_methods,
        haxe_methods,
    )
    report["inputs"] = {"original": str(original), "compiled": str(out), "aliases": haxe_aliases}
    add_residual_categories(report)
    FULL_FLASH_REPORT.parent.mkdir(parents=True, exist_ok=True)
    FULL_FLASH_REPORT.write_text(json.dumps(report, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    FULL_FLASH_MARKDOWN.write_text(append_residual_categories(compare_methods.markdown(report), report), encoding="utf-8")
    t = report["totals"]
    print(
        f"{t['original']} original methods, {t['compiled']} Haxe methods: "
        + ", ".join(f"{s} {t.get(s, 0)}" for s in ("equal", "equivalent", "splice", "signature", "code", "missing", "extra"))
        + f" -> {FULL_FLASH_REPORT}"
    )
    for item in report["causes"][:10]:
        print(f"  {item['count']:6d}  {item['cause']}")
    return 0


OPENFL_SRC = ROOT / ".tools" / "haxelib" / "openfl" / "9,5,2" / "src"
LIME_SRC = ROOT / ".tools" / "haxelib" / "lime" / "8,3,2" / "src"
HL_FULL_INCLUDE_MACRO = "include('', true, ['flash._std.*', 'port.runtime.FlashBoot'], ['src'])"
HL_OPENFL_OWNED = {
    Path("flash/events/Event.hx"), Path("flash/events/ErrorEvent.hx"), Path("flash/events/IOErrorEvent.hx"),
    Path("flash/events/ProgressEvent.hx"), Path("flash/events/TextEvent.hx"),
}
FLASH_REFERENCE_RE = re.compile(r"\bflash((?:\.[a-z][A-Za-z0-9_]*)+)\.([A-Z][A-Za-z0-9_]*)\b")
_OPENFL_DECL_RE = re.compile(
    r"^\s*(?:@:[^\n]*\n\s*)*(?:(?:extern|final|private)\s+)*(?:class|interface|abstract|typedef|enum\s+abstract|enum)\s+"
    r"(\w+)(<[^>{(=]*>)?", re.M)


def _type_params(declaration: str) -> tuple[str, str]:
    if not declaration:
        return "", ""
    names = [part.split(":")[0].strip() for part in declaration.strip("<>").split(",")]
    joined = "<" + ", ".join(names) + ">"
    return joined, joined


def write_openfl_flash_shims(target: Path) -> tuple[int, list[str]]:
    for rel in HL_OPENFL_OWNED:
        (target / rel).unlink(missing_ok=True)
    referenced: set[tuple[str, str]] = set()
    for source in target.rglob("*.hx"):
        for match in FLASH_REFERENCE_RE.finditer(source.read_text(encoding="utf-8")):
            referenced.add((match.group(1)[1:], match.group(2)))
    (target / "flash").mkdir(exist_ok=True)
    (target / "flash" / "Vector.hx").write_text("package flash;\n\nimport Vector as RootVector;\n\n"
                                                "typedef Vector<T> = RootVector<T>;\n",
                                                encoding="utf-8", newline="\n")
    shims = 1
    missing = []
    for package, name in sorted(referenced):
        rel = Path("flash", *package.split("."), f"{name}.hx")
        if (target / rel).exists():
            continue
        openfl_file = OPENFL_SRC / "openfl" / Path(*package.split(".")) / f"{name}.hx"
        if not openfl_file.exists():
            missing.append(f"flash.{package}.{name}")
            continue
        params = ""
        for decl in _OPENFL_DECL_RE.finditer(openfl_file.read_text(encoding="utf-8")):
            if decl.group(1) == name:
                params = decl.group(2) or ""
                break
        shim_params, args = _type_params(params)
        out = target / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(f"package flash.{package};\n\ntypedef {name}{shim_params} = openfl.{package}.{name}{args};\n",
                       encoding="utf-8", newline="\n")
        shims += 1
    return shims, missing


HL_ADAPTATIONS: list[tuple[str, str, str, int | tuple[int, int], str]] = [
    ("AGALMiniAssembler.hx", r"(?m)^(.*new Register\(.*?)\b(\d+)\.0\b(.*)$", r"\1\2\3", 9,
     "integral Float literals (restored pushdouble shape) passed to Register's UInt parameter; native UInt takes no "
     "Float, the value is the same integer"),
    ("Class_91.hx", r"_loc3_\.getData\(\)\.writeBytes\(param1,0,param1\.length\);",
     "_loc3_.blit(0,param1,0,param1.length);", 1,
     "haxe.io.Bytes.getData() is a ByteArray only on Flash; copying the ByteArray into the Bytes is a blit natively "
     "(OpenFL's ByteArray is Bytes there)"),
    ("Class_49.hx", r'untyped __global__\["parseFloat"\]\(param1\)', "Std.parseFloat(param1)", 1,
     "the game's ``Std.parseFloat`` (class_49) calls AVM2's global ``parseFloat`` (``findpropstrict parseFloat``); "
     "natively Haxe's own Std.parseFloat is the same leading-number parse (NaN when there is none)"),
    ("*", r"\+ \(untyped ([A-Za-z_$][\w$.]*)\)", r"+ Std.string(\1)", 33,
     "string concatenation operands the converter leaves untyped so Flash emits the original's plain ``add`` "
     "(``untype_string_concat_operands``); HashLink cannot add an untyped number to a String"),
    ("*", r"\(cast (Context3D(?:TextureFormat|Profile)\.[A-Z_0-9]+) : String\)", r"(\1 : String)", 19,
     "Stage3D enum constants stored as Strings (the original's ``getlex``/``coerce_s`` of Flash's String constants); "
     "OpenFL's native constants are Int-backed abstracts whose ``@:to String`` gives Flash's strings ('bgra', "
     "'standardExtended'), an unsafe cast does not ('Can't cast i32 to String' in class_582's static init)"),
    ("Class_582.hx", r'requestContext3D\("auto",cast (Class_582\.var_10802)\)',
     r'requestContext3D("auto",(\1 : flash.display3D.Context3DProfile))', 1,
     "the profile string passed back to ``Stage3D.requestContext3D`` (Flash takes a String); OpenFL's native "
     "profile is an Int-backed abstract with ``@:from String``, an unsafe cast is not ('Can't cast String to i32')"),
    ("Class_84.hx", r"createRectangleTexture\(var_7160,var_2831,cast param4,false\)",
     "createRectangleTexture(var_7160,var_2831,(param4 : flash.display3D.Context3DTextureFormat),false)", 2,
     "the texture format string (Flash's ``Context3DTextureFormat`` values are Strings) passed to "
     "``createRectangleTexture``; OpenFL's native format is an Int-backed abstract with ``@:from String``"),
    ("bh/platform/Hook.hx", r"\bhandler\.apply\(null,", "Reflect.callMethod(null,handler,", (3, 0),
     "AS3 ``Function.apply(thisArg, args)`` on a hook handler; a native Haxe closure has no ``apply`` field "
     "('Invalid field access' in Hook.filter from GameApp.onInvoke), ``Reflect.callMethod`` is the same call"),
    ("*", r"\b([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\.hasOwnProperty\(", r"port.runtime.As3.hasOwnPropertyValue(\1,", (6, 3),
     "AS3 ``Object.hasOwnProperty`` called on an untyped value (the game's Reflect.hasField, class_103; three mods); "
     "native objects have no such method ('Null access' in class_103.method_5626 from SavedData.getUint)"),
    ("*", r"(?m)^([ \t]*(?:public |private |protected )(?:static )?var [A-Za-z_]\w*:Float);", r"\1 = Math.NaN;",
     (560, 560),
     "AS3 ``Number`` fields without an initializer start as NaN (AVM2's slot default); HashLink's Float fields start "
     "at 0, so the original's NaN-guarded code runs (class_694.method_7176: ``var_1144 < 1`` is false for NaN, "
     "true for 0, and calls the never-set easing function: 'Null access' entering Training). Flash keeps NaN"),
    ("*", r"\bcast 4294967295\b(?!\.)", "cast -1", (21, 21),
     "``uint(-1)`` defaults written as ``cast 4294967295`` (a Float literal in Haxe): Flash stores the uint, HashLink "
     "converts the double to its 32-bit Int with saturation, giving -2147483648 (class_714's ``param2``: 'index "
     "-2147483648 is out of range' in class_256.method_1791 at match start). -1 has the same 32 bits"),
    ("*", r"(?<![\w.])([A-Za-z_]\w*\.graphics\.readGraphicsData\((?:true|false)?\))",
     r"(\1 : Vector<flash.display.IGraphicsData>)", (4, 4),
     "``Graphics.readGraphicsData`` returns OpenFL's own ``openfl.Vector`` natively, which the game's ``Vector`` "
     "converts only where the target is typed. ``class_176.method_6868`` keeps it in an untyped local (FFDec's "
     "``:* = null as Vector.<IGraphicsData>``), and HashLink reads OpenFL's ``length`` getter as 0 through "
     "``Dynamic``. Its colour-swap loop then never ran, and fighters kept their default colours under any scheme. "
     "Every call converts explicitly; for typed targets this is the same conversion"),
    ("*", r"\.drawGraphicsData\(([A-Za-z_]\w*)\)", r".drawGraphicsData((\1 : Vector<flash.display.IGraphicsData>))",
     (1, 1),
     "(same) the swapped result goes back to ``Graphics.drawGraphicsData``, which natively takes OpenFL's vector; from "
     "the untyped local the game's ``Vector`` failed the cast ('Can't cast port.runtime.AS3Vector to "
     "openfl._Vector.ObjectVector'). The typed argument converts through ``Vector``'s ``@:to``"),
    ("*", r"(?<![\w.])([A-Za-z_]\w*\.getVector\([A-Za-z_]\w*\.rect\))", r"(\1 : Vector<UInt>)", (3, 3),
     "(same) ``BitmapData.getVector`` (all three sites are typed already; converted explicitly like the above)"),
    ("*", r"(?<![\w.])Type\.createInstance\(", "port.runtime.As3.createInstance(", (7, 6),
     "AS3 ``new cls()`` on a class value (``construct``): natively a loaded SWF's symbol class is the runtime's "
     "``SymbolClass`` (``port.runtime.swf``), whose instance is built from the SWF's timeline, which std "
     "``Type.createInstance`` cannot do (it only allocates the HashLink type); other classes go to it unchanged"),
    ("Class_73.hx", r"public static var var_12273:Array<Dynamic>;",
     "public static var var_12273:port.runtime.SparseArray;", 1,
     "class_73's collision table, keyed by the collision colour (``method_2445(16777215, 4, ...)`` in GameApp): an "
     "AS3 Array that AVM2 keeps sparse. A Haxe Array is dense: 16.7M slots, a 191 MB block. "
     "``port.runtime.SparseArray`` is an IntMap with the Array's index reads and writes"),
    ("BootDocument.hx", r"Class_73\.var_12273 = \[\];", "Class_73.var_12273 = new port.runtime.SparseArray();", 1,
     "(same) the table's ``[]`` initializer"),
    ("Class_74.hx", r"port\.runtime\.As3\.index\(Class_73\.var_12273, param4\)", "Class_73.var_12273[param4]", 1,
     "(same) the table's one read; a key never written reads null as before (``uint(undefined)`` is 0)"),
]


HL_LIBRARY_PATCHES: list[tuple[str, str, str, int, str]] = [
    ("openfl/display/DisplayObject.hx", r"stack\[i - j - 1\]\.__dispatch\(event\);",
     "stack[i - j - 1].__dispatch(event);\n\t\t\t\t\tif (event.__isCanceled) break;", 1,
     "stopPropagation during the capture phase ends the dispatch after the current object, as in AIR: OpenFL kept "
     "capturing through the remaining ancestors (driver ``eventorder``, 2026-10-17, case 2)"),
    ("openfl/display/DisplayObject.hx", r"(\t\tevent\.eventPhase = AT_TARGET;\r?\n\r?\n\t\treturn __dispatchEvent\(event\);)",
     "\t\tif (event.__isCanceled) return !event.isDefaultPrevented();\n\\1", 1,
     "... and never reaches the target: OpenFL ran the target's listeners after a capture listener had stopped the "
     "event (case 2)"),
    ("openfl/display/Stage.hx",
     r"(var dispatchers = DisplayObject\.__broadcastEvents\.get\(event\.type\);\r?\n\r?\n\t\t\tfor \(dispatcher in dispatchers)\)",
     r"\1.copy())", 1,
     "a frame broadcast (enterFrame, exitFrame, ...) goes to the objects listening when it starts: OpenFL walked the "
     "live list, so an object that began listening during enterFrame got that frame's event too; AIR's doesn't "
     "(driver ``eventorder``, 2026-10-17)"),
    ("openfl/display/Stage.hx", r"dispatcher\.__dispatch\(event\);", "dispatcher.__dispatch(event.clone());", 2,
     "each object of a frame broadcast gets its own event, as in AIR: OpenFL passed one event object to all of "
     "them, so ``event.target`` read the first object (the stage for enterFrame) in every listener (driver "
     "``eventorder``, 2026-10-17)"),
    ("openfl/utils/ByteArray.hx", r"(#if lime\r?\n\t\t)#if js(\r?\n\t\tif \(__allocated > __length\))",
     r"\1#if (js || hl)\2", 2,
     "compress()/uncompress() trim the buffer to its length first only on JS; natively they (de)compress the whole "
     "allocation, so a ByteArray grown by writes compresses its unused capacity too (zlib's inflate happens to "
     "ignore the trailing bytes, compress does not)"),
    ("openfl/utils/ByteArray.hx", r"var int64:Int64 = FPHelper\.doubleToI64\(value\);",
     "var int64:Int64 = value != value ? Int64.make(0x7FFFFFFF, 0xE0000000) : FPHelper.doubleToI64(value);", 1,
     "``writeDouble(NaN)``: AIR writes NaN as 7FFFFFFF E0000000 (a float32 NaN widened), HashLink's NaN is x86's "
     "FFF8000000000000. The game's rollback checkpoints (``class_362``, a NaN field at byte 332) differed from AIR's "
     "in every checkpoint of a replay (P8 parity, driver ``replay``); the value is the same NaN either way"),
    ("openfl/system/ApplicationDomain.hx", r"Type\.resolveClass\(name\)",
     "port.runtime.swf.SwfSymbols.resolve(this, name)", 2,
     "``getDefinition``/``hasDefinition`` resolve only compiled Haxe classes natively; a loaded SWF's symbols "
     "(registered by the runtime's SwfLoader) resolve first, in the domain and its parents as in AVM2"),
    ("openfl/text/Font.hx", r"(public static function registerFont\(font:Dynamic\):Void\r?\n\t\{\r?\n)",
     r"\1\t\tfont = port.runtime.swf.SwfSymbols.fontOf(font);\n\t\tif (font == null) return;\n", 1,
     "a loaded SWF's font symbol (``SwfSymbols``' class value) registers its ``DefineFont3`` glyphs as a TrueType "
     "font natively (``SwfFont``); OpenFL would ``Type.createInstance`` the class, which has no Font constructor"),
    ("openfl/display3D/textures/RectangleTexture.hx", r"\t\tuploadFromTypedArray\(image\.data\);",
     "\t\tif (image.buffer.width > __width || image.buffer.height > __height)\n"
     "\t\t{\n"
     "\t\t\t// port: AIR uploads the source's top-left texture-sized region (docs/port-handfixes.md).\n"
     "\t\t\tif (image.buffer.width >= __width && image.buffer.height >= __height)\n"
     "\t\t\t{\n"
     "\t\t\t\t// port: read the region in place (GL_UNPACK_ROW_LENGTH = the source's width) instead of a copy per upload.\n"
     "\t\t\t\tvar gl = __context.gl;\n"
     "\t\t\t\tgl.pixelStorei(0x0CF2, image.buffer.width);\n"
     "\t\t\t\tuploadFromTypedArray(image.data);\n"
     "\t\t\t\tgl.pixelStorei(0x0CF2, 0);\n"
     "\t\t\t\treturn;\n"
     "\t\t\t}\n"
     "\t\t\tvar stride = image.buffer.width * 4, row = __width * 4;\n"
     "\t\t\tvar copy = row < stride ? row : stride;\n"
     "\t\t\tvar rows = __height < image.buffer.height ? __height : image.buffer.height;\n"
     "\t\t\tvar out = new lime.utils.UInt8Array(row * __height);\n"
     "\t\t\tvar src = image.data;\n"
     "\t\t\tfor (y in 0...rows) out.buffer.blit(y * row, src.buffer, src.byteOffset + y * stride, copy);\n"
     "\t\t\tuploadFromTypedArray(out);\n"
     "\t\t\treturn;\n"
     "\t\t}\n"
     "\t\tuploadFromTypedArray(image.data);", 1,
     "the game makes each animation/stage-art texture at its ``scrollRect`` size and uploads the shared atlas canvas "
     "it was drawn on (128x128/256x256, ``class_626.method_3009``); AIR takes the source's top-left texture-sized "
     "region, OpenFL handed the whole buffer to ``texImage2D`` with the texture's width, so rows sheared into "
     "stripes"),
    ("openfl/display/Graphics.hx",
     r"(private function __readGraphicsData\(graphicsData:Vector<IGraphicsData>)\):Void(\r?\n\t\{\r?\n)",
     r"\1, ?transform:Matrix):Void\2\t\tvar portStart = graphicsData.length;\n", 1,
     "``readGraphicsData(true)`` (class_176's colour swap): AIR returns every child's paths in the queried "
     "object's space, with the children's transforms applied; OpenFL read each child's commands untransformed. "
     "The graphics' own reader takes the child's concatenated matrix"),
    ("openfl/display/Graphics.hx",
     r"(\r?\n\t\tif \(path != null\)\r?\n\t\t\{\r?\n\t\t\tgraphicsData\.push\(path\);\r?\n\t\t\})(\r?\n\t\})",
     r"\1\n\t\tif (transform != null) port.runtime.swf.GraphicsDataTransform.apply(graphicsData, portStart, "
     r"transform);\2", 1,
     "(same) the paths, gradient and bitmap fill matrices read from a child are mapped by its matrix"),
    ("openfl/display/DisplayObject.hx",
     r"(private function __readGraphicsData\(graphicsData:Vector<IGraphicsData>, recurse:Bool)\):Void"
     r"(\r?\n\t\{\r?\n\t\tif \(__graphics != null\)\r?\n\t\t\{\r?\n\t\t\t)__graphics\.__readGraphicsData\(graphicsData\);",
     r"\1, ?transform:Matrix):Void\2__graphics.__readGraphicsData(graphicsData, transform);", 1,
     "(same) passes the matrix down"),
    ("openfl/display/DisplayObjectContainer.hx",
     r"(private override function __readGraphicsData\(graphicsData:Vector<IGraphicsData>, recurse:Bool)\):Void"
     r"(\r?\n\t\{\r?\n\t\t)super\.__readGraphicsData\(graphicsData, recurse\);",
     r"\1, ?transform:Matrix):Void\2super.__readGraphicsData(graphicsData, recurse, transform);", 1,
     "(same) the container's own graphics in the queried space"),
    ("openfl/display/DisplayObjectContainer.hx", r"\t\t\t\tchild\.__readGraphicsData\(graphicsData, recurse\);",
     "\t\t\t\tif (!child.visible) continue; // port: AIR leaves non-visible objects out\n"
     "\t\t\t\tvar portMatrix = child.transform.matrix;\n"
     "\t\t\t\tif (transform != null) portMatrix.concat(transform);\n"
     "\t\t\t\tchild.__readGraphicsData(graphicsData, recurse, portMatrix);", 1,
     "(same) each child is read with its matrix concatenated to its parent's; non-visible children are left out "
     "(AIR's documented behaviour)"),
    ("openfl/display/DisplayObject.hx", r"(\t@:noCompletion private var __cacheAsBitmap:Bool;)",
     r"\1\n\t@:noCompletion public var __portFields:Dynamic; // port: As3.dyn's field store"
     r"\n\t@:noCompletion public var __portTimelineNames:Dynamic; // port: the timeline's named children (SwfTimeline)", 1,
     "the fields AS3's dynamic MovieClip takes without declaring them (``As3.dyn``: the converter's dynamic clip "
     "fields, a symbol's ``a`` palette) are kept on the display object itself; a global identity map kept every "
     "such clip alive for the whole session (no measured heap difference: the game keeps those clips itself)"),
    ("openfl/display/DisplayObject.hx", r"(\t@:noCompletion private var __name:String;)",
     r"\1\n\t@:noCompletion private var __portInstance:Int; // port: the number of the default name, made on first read",
     1,
     "the default ``instanceN`` name is built when first read, with the number it got at construction "
     "(the same name as before); most objects are renamed by their placement or never read, and the eager strings "
     "were among the small blocks pinning nearly empty GC pages"),
    ("openfl/display/DisplayObject.hx", r"\t\tname = \"instance\" \+ \(\+\+__instanceCount\);",
     "\t\t__portInstance = ++__instanceCount;", 1, "(same) the number only"),
    ("openfl/display/DisplayObject.hx",
     r"(private function get_name\(\):String\r?\n\t\{\r?\n)(\t\treturn __name;)",
     r'\1\t\tif (__name == null && __portInstance != 0) __name = "instance" + __portInstance;\n\2', 1,
     "(same) the name on first read"),
    ("openfl/display/DisplayObject.hx",
     r"(private function set_name\(value:String\):String\r?\n\t\{\r?\n)(\t\treturn __name = value;)",
     r"\1\t\t__portInstance = 0;\n\2", 1, "(same) a set name replaces it"),
    ("openfl/display3D/Context3D.hx",
     r"(public function setProgramConstantsFromVector\(programType:Context3DProgramType, firstRegister:Int, )"
     r"data:Vector<Float>(, numRegisters:Int = -1\):Void\r?\n\t\{\r?\n\t\tif \(numRegisters == 0\) return;\r?\n\r?\n"
     r"\t\tif \(__state\.program != null && __state\.program\.__format == GLSL\) \{\}\r?\n\t\telse\r?\n\t\t\{\r?\n)",
     r"\1data:Dynamic\2"
     "\t\t\tif (Std.isOfType(data, port.runtime.AS3Vector))\n"
     "\t\t\t{\n"
     "\t\t\t\t// port: the game's Vector.<Number> store, read in place (OpenFL's loop below, same values)\n"
     "\t\t\t\tvar portData:port.runtime.AS3Vector = cast data;\n"
     "\t\t\t\tvar portLength = portData.getLength();\n"
     "\t\t\t\tif (numRegisters == -1) numRegisters = (portLength >> 2);\n"
     "\t\t\t\tvar portVertex = (programType == VERTEX);\n"
     "\t\t\t\tvar portDest = portVertex ? __vertexConstants : __fragmentConstants;\n"
     "\t\t\t\tvar portIndex = firstRegister * 4;\n"
     "\t\t\t\tfor (i in 0...numRegisters * 4)\n"
     "\t\t\t\t{\n"
     "\t\t\t\t\tvar portValue:Float = i < portLength ? portData.floatAt(i) : 0.0;\n"
     "\t\t\t\t\tportDest[portIndex++] = portValue;\n"
     "\t\t\t\t}\n"
     "\t\t\t\tif (__state.program != null) __state.program.__markDirty(portVertex, firstRegister, numRegisters);\n"
     "\t\t\t\treturn;\n"
     "\t\t\t}\n", 1,
     "the game's ``Vector.<Number>`` (``port.runtime.AS3Vector``) is read in place; its conversion to "
     "an OpenFL vector copied it at every call (``class_318.method_6254``: six calls per drawn quad, a third of "
     "a match's allocations by bytes, ``data/tools/port_track_summary.py``), and the collections those allocations cause "
     "are the match's frame spikes (the soak's ``--gc-off-in-matches``)"),
    ("openfl/display3D/Context3D.hx", r"(\t\t\tvar dest = isVertex \? __vertexConstants : __fragmentConstants;\r?\n"
     r"\t\t\t)var source = data;", r"\1var source:Vector<Float> = data;", 1,
     "(same) OpenFL's own path, for an OpenFL vector, keeps its type"),
    ("openfl/events/EventDispatcher.hx", r"\blistener\.callback\(event\);",
     "#if port_slow_listeners port.runtime.SlowListeners.call(listener.callback, event) #else "
     "listener.callback(event) #end;", 4,
     "diagnostic only, off by default: with ``-D port_slow_listeners`` each listener call is timed and slow ones "
     "are logged (``SlowListeners``); without it the code is OpenFL's"),
    ("openfl/display/BitmapData.hx", r"(\r?\n)(\t\t\t)__drawCairo\(source, renderer\);",
     r"\1\2var portStarted = Sys.time();\1"
     r"\2port.runtime.RasterRelease.begin();\1\2try __drawCairo(source, renderer) catch (e:haxe.Exception) {\1"
     r"\2\tport.runtime.RasterRelease.end();\1\2\tthrow e;\1\2}\1\2port.runtime.RasterRelease.end();\1"
     r"\2port.runtime.SlowRasters.drawn(source, this, portStarted, matrix, colorTransform);", 1,
     "a Cairo ``draw`` of an object off the stage keeps no raster per shape afterwards, as in AIR "
     "(``port.runtime.RasterRelease``; the game's clip caches kept every drawn shape's bitmap, ~11 MB per match). "
     "a slow draw is logged (``SlowRasters.drawn``) and every draw counted (``DrawStats``)"),
    ("openfl/display/BitmapData.hx",
     r"(#if \(\(js && html5\) \|\| lime_cairo\)\r?\n\t\t\tif \(colorTransform != null)\)",
     r"\1 && !colorTransform.__isDefault(false))", 1,
     "fidelity: with any colour transform, even the identity the game passes (``class_176.method_2658``'s "
     "``transform.colorTransform``, the Image Render Tool's composite), OpenFL's Cairo ``draw`` first drew the source "
     "unscaled and unsmoothed into a copy and then scaled that copy by the matrix: the bones were rasterised at "
     "1/1.4 of their size with nearest sampling and enlarged (dotted thin lines). An identity transform changes no "
     "colour, so the source is drawn once with its full matrix, as Flash draws it"),
    ("openfl/filters/GlowFilter.hx", r"(\r?\n)(\t\t// TODO: Support knockout, inner)",
     r"\1\t\tif (true) return port.runtime.FlashFilters.glow(bitmapData, sourceBitmapData, sourceRect, destPoint, "
     r"__color, __alpha, __blurX, __blurY, __strength, __quality, __inner, __knockout);\1\2", 1,
     "filters as AIR computes them (``port.runtime.FlashFilters``, fitted pixel for pixel to AIR's output): OpenFL's "
     "software glow used Lime's stack blur, which ignores ``strength`` and spreads wider, so the menus' crisp text "
     "outlines (blur 3, strength 10) came out blurry (owner, 2026-10-17)"),
    ("openfl/filters/DropShadowFilter.hx", r"(\r?\n)(\t\t// TODO: Support knockout, inner)",
     r"\1\t\tif (true) return port.runtime.FlashFilters.glow(bitmapData, sourceBitmapData, sourceRect, destPoint, "
     r"__color, __alpha, __blurX, __blurY, __strength, __quality, __inner, __knockout, "
     r"__distance * Math.cos(__angle * Math.PI / 180), __distance * Math.sin(__angle * Math.PI / 180), __hideObject);\1\2", 1,
     "(same) a drop shadow is the glow moved by its exact distance and angle (OpenFL truncated them to whole pixels)"),
    ("openfl/filters/GlowFilter.hx", r"__preserveObject = true;", "__preserveObject = false;", 1,
     "(same) ``FlashFilters`` composites the object itself (inner glows draw over it, knockouts remove it)"),
    ("openfl/filters/DropShadowFilter.hx", r"__preserveObject = true;", "__preserveObject = false;", 1, "(same)"),
    ("openfl/filters/BlurFilter.hx", r"(\t\t#if lime\r?\n\t\tvar time = Timer\.stamp\(\);)",
     r"\t\tif (true) return port.runtime.FlashFilters.blur(bitmapData, sourceBitmapData, sourceRect, destPoint, __blurX, "
     r"__blurY, __quality);\n\1", 1, "(same) Flash's box blur"),
    ("openfl/display/BitmapData.hx", r"var lastBitmap = filter\.__applyFilter\(bitmapData2, this, sourceRect, destPoint\);",
     "var lastBitmap = filter.__applyFilter(bitmapData2, sourceBitmapData, sourceRect, destPoint);", 1,
     "``applyFilter`` filters its source, as Flash's does (OpenFL filtered the destination)"),
    ("openfl/display/BitmapData.hx", r"bitmapData3\.copyPixels\(this, rect, destPoint\);",
     "bitmapData3.copyPixels(sourceBitmapData, sourceRect, destPoint);", 1, "(same) and keeps the source to draw over"),
    ("openfl/display/DisplayObjectRenderer.hx",
     r"__shouldCacheHardware\(displayObject, null\) == false #else true #end\)",
     "__shouldCacheHardware(displayObject, null) == false || displayObject.__filters != null #else true #end)", 1,
     "every filtered object takes the software filter path (``FlashFilters``); the GL path's shader filters are "
     "OpenFL's own blur, not Flash's"),
    ("openfl/display/DisplayObject.hx",
     r"(\t\tvar bounds = new Rectangle\(\);\r?\n\t\t__getBounds\(bounds, matrix\);)",
     r"\1\n\t\tport.runtime.Twips.snap(bounds);", 1,
     "bounds in twips as in Flash (``port.runtime.Twips``): the game lays screens out from them, and float residue "
     "flipped the Training legend select from AIR's 7 rows of 23 to 6 of 26 (owner, 2026-10-17)"),
    ("openfl/display/DisplayObject.hx", r"var width = rect\.width;",
     "port.runtime.Twips.snap(rect);\n\t\tvar width = rect.width;", 1, "(same) ``width``"),
    ("openfl/display/DisplayObject.hx", r"var height = rect\.height;",
     "port.runtime.Twips.snap(rect);\n\t\tvar height = rect.height;", 1, "(same) ``height``"),
    ("openfl/display/DisplayObject.hx", r"(\t\tmatrix\.identity\(\);\r?\n\r?\n\t\t__getBounds\(rect, matrix\);)",
     r"\1\n\t\tport.runtime.Twips.snap(rect);", 2,
     "(same) setting ``width``/``height`` scales by the twip-rounded size, as Flash does"),
    ("openfl/display/DisplayObjectContainer.hx",
     r"if \(__children\[i\]\.__hitTest\(x, y, shapeFlag, null, true, cast __children\[i\]\)\)",
     "if (__children[i].__hitTest(x, y, shapeFlag, null, mouseChildren, cast __children[i]))", 1,
     "mouse targets as in Flash: a container with ``mouseChildren = false`` is the target when any visible descendant's "
     "shape is hit, whatever the descendants' own mouse flags; OpenFL tested them as interactive objects, so a child "
     "with its mouse off (the map tiles' ``am_Holder`` picture) hid the tile from the pointer: no hover select "
     "on the map vote (owner, 2026-10-17)"),
    ("openfl/display/_internal/CairoShape.hx",
     r"(\n\t\t\t\trenderer\.applyMatrix\(renderTransform, cairo\);\r?\n)",
     r"\1\t\t\t\tport.runtime.RasterRelease.snapPaint(shape, cairo);\n", 1,
     "(same) a grid-fitted text raster painted inside ``BitmapData.draw`` at a fractional offset lands on whole pixels "
     "(``RasterRelease.snapPaint``) instead of being resampled"),
    ("openfl/display/_internal/CairoTextField.hx",
     r"(\t\tmatrix\.scale\(pixelRatio, pixelRatio\);\r?\n)",
     r"\1\t\tport.runtime.RasterRelease.snapText(textField, matrix);\n", 1,
     "fidelity: advanced antialiasing with pixel grid fit puts the text on whole device pixels, as Flash does "
     "(AIR's glyphs do not move with a fractional field position); OpenFL drew the sub-pixel remainder into the "
     "glyphs, which softened them (``RasterRelease.snapText``)"),
    ("openfl/display/_internal/CairoTextField.hx",
     r"new CairoGlyph\(position\.glyph, x \+ position\.offset\.x \+ 0\.5, y - position\.offset\.y \+ 0\.5\)",
     "new CairoGlyph(position.glyph, x + position.offset.x + port.runtime.RasterRelease.textDx, "
     "y - position.offset.y + port.runtime.RasterRelease.textDy)", 1,
     "fidelity: where glyphs sit against their layout positions (OpenFL's half pixel), fitted against AIR's with the "
     "driver's ``textdump`` (``RasterRelease.textDx``/``textDy``)"),
    ("openfl/display/_internal/CairoTextField.hx",
     r"(\t+)cairo\.showGlyphs\(glyphs\);(\r?\n\t+#end)",
     r"\1if (!port.runtime.TextPaths.show(cairo, font, size, glyphs, textEngine.antiAliasType == ADVANCED)) "
     r"cairo.showGlyphs(glyphs);\2", 1,
     "fidelity: normal-antialiased text in a SWF font is filled from its glyph outlines with the 4x4-sample "
     "rasteriser, as Flash fills it (AIR's normal text has Flash's 16 coverage levels; FreeType's hinted glyph "
     "rasters have 256 and move edges); ``TextPaths``, ``BH_PORT_TEXT_PATHS``"),
    ("openfl/text/_internal/TextEngine.hx",
     r"(\r?\n)(\t\t#if lime_switch\r?\n\t\tif \(name != null && name\.indexOf)",
     r"\1\t\tvar portFont = port.runtime.swf.SwfFonts.find(name);\n"
     r"\t\tif (portFont != null && @:privateAccess portFont.__initialize()) return portFont;\n\n\2", 1,
     "fonts embedded in loaded SWFs resolve by name as in Flash (``SwfFonts``), after the class-registered fonts and "
     "before a system font file of that name: the key hints' \"Eras Bold ITC\" drew nothing"),
    ("openfl/text/_internal/TextEngine.hx",
     r"currentTextHeight = Math\.ceil\(group\.offsetY - 2 \+ group\.ascent \+ group\.descent\);",
     "currentTextHeight = group.offsetY - 2 + group.ascent + group.descent;", 1,
     "text height as AIR's: not rounded up to whole pixels (AIR's ``textHeight`` 28.2, OpenFL's 29; the game's "
     "fit-to-box code, ``textHeight + 6.5 <= height``, then took a size smaller: the Code of Conduct titles 20 vs 21)"),
    ("openfl/text/_internal/TextEngine.hx", r"var widthValue = 0\.0, heightValue = 0, maxHeightValue = 0;",
     "var widthValue = 0.0, heightValue = 0.0, maxHeightValue = 0.0;", 1,
     "(same) line heights are not rounded up either, so lines are spaced as AIR spaces them"),
    ("openfl/text/_internal/TextEngine.hx", r"(\t\t\t)heightValue = Math\.ceil\(ascent \+ descent \+ leading\);(\r?\n\r?\n\t\t\tif \(heightValue > maxHeightValue\))",
     r"\1heightValue = ascent + descent + leading;\2", 1, "(same)"),
    ("openfl/text/_internal/TextLayout.hx",
     r"(\t\t\t\t\tlastCluster = info\.cluster;\r?\n\t\t\t\t\}\r?\n)",
     r"\1\t\t\t\tvar portExact = port.runtime.swf.SwfFonts.advances(font);\n"
     r"\t\t\t\tif (portExact != null) for (p in positions) {\n"
     r"\t\t\t\t\tvar g:Int = p.glyph;\n"
     r"\t\t\t\t\tif (g > 0 && g < portExact.length) p.advance.x = port.runtime.swf.SwfFonts.twipAdvance(portExact[g] * size) + letterSpacing;\n"
     r"\t\t\t\t}\n", 1,
     "text width as AIR's: a font made from SWF data lays out at its glyphs' exact advances "
     "(``SwfFonts.advances``); HarfBuzz's are FreeType's, hinted to whole pixels, which made text up to 8% wider "
     "than AIR's (the main menu's 10-px descriptions 264 vs 245 px), and the game's fit-to-box code then shrank titles; "
     "each advance floored to whole twips as Flash does (``SwfFonts.twipAdvance``, fitted with the driver's ``textdump``)"),
    ("openfl/display/DisplayObjectRenderer.hx",
     r"(\t+)displayObject\.__cacheBitmapData\.__drawGL\(displayObject, childRenderer\);",
     r"\1port.runtime.RasterCache.cacheBitmapDepth++;\n"
     r"\1displayObject.__cacheBitmapData.__drawGL(displayObject, childRenderer);\n"
     r"\1port.runtime.RasterCache.cacheBitmapDepth--;", 1,
     "``RasterCache`` knows when a raster is made for a ``cacheAsBitmap``/filter bitmap (the menu's roster "
     "icons, rebuilt after every match), so ``BH_PORT_RASTER_CACHE_SCOPE=cachebitmap`` can keep only those"),
    ("openfl/display3D/textures/TextureBase.hx", r"(\t@:noCompletion private var __width:Int;)",
     r"\1\n\t// port: texture counters (driver ``caches``): live textures and their bytes, all created, how many"
     r" came from BitmapData.getTexture and how many BitmapData.dispose dropped without deleting\n"
     r"\tpublic static var __portLive:Int = 0;\n\tpublic static var __portLiveBytes:Float = 0;\n"
     r"\tpublic static var __portCreated:Int = 0;\n\tpublic static var __portFromBitmap:Int = 0;\n"
     r"\tpublic static var __portDropped:Int = 0;\n"
     r"\tpublic static var __portPackedBytes:Float = 0;\n\tpublic var __portPacked:Bool = false;", 1,
     "the GL driver keeps a copy of every texture in the process (``glprobe``), so the "
     "textures the game and OpenFL hold are counted"),
    ("openfl/display3D/textures/TextureBase.hx", r"(\t\t__textureID = gl\.createTexture\(\);)",
     r"\1\n\t\t__portLive++;\n\t\t__portCreated++;", 1, "(same) a texture made"),
    ("openfl/display3D/textures/TextureBase.hx", r"(\t\tif \(__textureID != null\)\r?\n\t\t\{\r?\n)(\t\t\tgl\.deleteTexture\(__textureID\);)",
     r"\1\t\t\t__portLive--;\n\t\t\t__portLiveBytes -= __width * __height * 4.0;\n"
     r"\t\t\tif (__portPacked) __portPackedBytes -= __width * __height * 4.0;\n\2", 1, "(same) a texture deleted"),
    ("openfl/display3D/textures/RectangleTexture.hx", r"(\t\t__height = height;)",
     r"\1\n\t\tTextureBase.__portLiveBytes += width * height * 4.0;\n"
     r"\t\tif (format == 'bgraPacked4444') { __portPacked = true; TextureBase.__portPackedBytes += width * height * 4.0; }",
     1, "(same) its bytes (RGBA, one level), and those the game asked for as BGRA_PACKED (16 bits a pixel in AIR)"),
    ("openfl/display3D/textures/Texture.hx", r"(\t\t__height = height;)",
     r"\1\n\t\tTextureBase.__portLiveBytes += width * height * 4.0;", 1, "(same) its bytes (RGBA, first level)"),
    ("openfl/display/BitmapData.hx",
     r"(\t\t\t__texture = context\.createRectangleTexture\(width, height, BGRA, false\);)",
     r"\1\n\t\t\topenfl.display3D.textures.TextureBase.__portFromBitmap++;", 1,
     "(same) a display-list bitmap's texture"),
    ("openfl/display/BitmapData.hx", r"(\r?\n)(\t\t__texture = null;)",
     r"\1\t\tif (__texture != null && @:privateAccess __texture.__textureID != null)"
     r" openfl.display3D.textures.TextureBase.__portDropped++;\1\2", 1,
     "(same) ``dispose`` drops its texture without deleting it (OpenFL 9.5.2 has the delete commented out; Lime's "
     "GL object finalizer deletes it once collected). Deleting it in ``dispose`` was measured on 2026-10-16 and "
     "changed nothing (4-match soak, private bytes and GPU memory within the runs' spread: the driver pools freed "
     "texture memory), so OpenFL's behaviour stays"),
    ("openfl/display/_internal/CairoGraphics.hx",
     r"(public static function render\(graphics:Graphics, renderer:CairoRenderer\):Void\r?\n\t\{\r?\n\t\t#if lime_cairo\r?\n)",
     r"\1\t\tport.runtime.RasterRelease.note(graphics);\n", 1,
     "notes each drawing rendered during a ``BitmapData.draw`` (``RasterRelease``)"),
    ("openfl/display/_internal/CairoGraphics.hx",
     r"var bitmap = new BitmapData\(bitmapWidth, bitmapHeight, true, 0\);",
     "var bitmap = port.runtime.RasterRelease.take(bitmapWidth, bitmapHeight);", 1,
     "a new raster reuses a released one of the same size (``RasterRelease.take``; the render "
     "clears it first)"),
    ("openfl/display/_internal/CairoGraphics.hx", r"(\t\tcairo\.fillRule = EVEN_ODD;\r?\n\t\t)cairo\.antialias = SUBPIXEL;",
     r"\1cairo.antialias = port.runtime.RasterRelease.fillAntialias;", 1,
     "vector fills read their antialiasing from ``RasterRelease.fillAntialias`` (Cairo's ``FAST`` by "
     "default since 2026-10-17, as close to AIR's pixels as OpenFL's ``SUBPIXEL`` and 37% faster; "
     "``BH_PORT_CAIRO_AA=subpixel`` restores OpenFL's)"),
    ("openfl/display/_internal/CairoGraphics.hx",
     r"(\t\tcairo\.antialias = port\.runtime\.RasterRelease\.fillAntialias;)",
     r"\1\n\t\tcairo.setOperator(!stroke && graphics.__portAdditive"
     r" && port.runtime.RasterRelease.additiveFills ? ADD : OVER);", 1,
     "fidelity: a SWF shape's fills are added into its raster (Cairo ``ADD``), as Flash rasterises a shape's fills "
     "together: they partition the shape, so a pixel two fills share gets their summed coverage (full). Drawn one "
     "over the other, a pixel half covered by each got 75% alpha, a seam of the background through every edge "
     "between two colours (the Image Render Tool's PNG, the art baker's legends). Lines are drawn over as before"),
    ("openfl/display/_internal/CairoGraphics.hx",
     r"(\t\t\tvar initStrokeY = 0\.0;\r?\n\r?\n\t\t\tvar data = new DrawCommandReader\(graphics\.__commands\);\r?\n\r?\n"
     r"\t\t\tfor \(type in graphics\.__commands\.types\)\r?\n\t\t\t\{\r?\n)",
     r"\t\t\tvar portGroups = graphics.__portAdditive && port.runtime.RasterRelease.additiveFills ? graphics.__portGroups : null;\n"
     r"\t\t\tvar portIndex = 0, portNext = 1;\n\t\t\tif (portGroups != null) cairo.pushGroup();\n\1"
     r"\t\t\t\tif (portGroups != null && portNext < portGroups.length && portIndex == portGroups[portNext]) {\n"
     r"\t\t\t\t\tif (fillCommands.length > 0) endFill();\n\t\t\t\t\tif (strokeCommands.length > 0) endStroke();\n"
     r"\t\t\t\t\tcairo.popGroupToSource();\n\t\t\t\t\tcairo.setOperator(OVER);\n\t\t\t\t\tcairo.paint();\n"
     r"\t\t\t\t\tcairo.pushGroup();\n\t\t\t\t\tportNext++;\n\t\t\t\t}\n\t\t\t\tportIndex++;\n", 1,
     "fidelity: a SWF shape of several style groups (``Graphics.__portGroups``) on the screen: each group's fills "
     "are added in a Cairo group of their own and the groups painted one over the other, as ``DirectVectors`` draws "
     "them inside a ``BitmapData.draw`` (a quarter of the shapes have several groups; their fills were drawn one "
     "over the other, with seams)"),
    ("openfl/display/_internal/CairoGraphics.hx",
     r"(\t\t\tif \(strokeCommands\.length > 0\)\r?\n\t\t\t\{\r?\n\t\t\t\tendStroke\(\);\r?\n\t\t\t\}\r?\n\r?\n)"
     r"(\t\t\tdata\.destroy\(\);\r?\n\r?\n\t\t\tgraphics\.__bitmap\.image\.dirty = true;)",
     r"\1\t\t\tif (portGroups != null) {\n\t\t\t\tcairo.popGroupToSource();\n\t\t\t\tcairo.setOperator(OVER);\n"
     r"\t\t\t\tcairo.paint();\n\t\t\t}\n\n\2", 1, "(same) the last group"),
    ("openfl/display/_internal/CairoGraphics.hx", r"(\t\tcairo\.newPath\(\);\r?\n)(\t\tplayCommands\(fillCommands, false\);)",
     r"\1\t\tif (!hitTesting) port.runtime.RasterRelease.shiftFill(cairo, 1);\n\2"
     r"\n\t\tif (!hitTesting) port.runtime.RasterRelease.shiftFill(cairo, -1);", 1,
     "fidelity: vector fills move by a device-pixel offset (``RasterRelease.fillDx``, 1/8 px right with ``FAST``), "
     "where Cairo's samples fall against Flash's (fitted with ``tools/port_pixcompare.py``)"),
    ("openfl/display/_internal/CairoGraphics.hx", r"(\t\tcairo\.newPath\(\);\r?\n)(\t\tplayCommands\(strokeCommands, true\);)",
     r"\1\t\tif (!hitTesting) port.runtime.RasterRelease.shiftFill(cairo, 1);\n\2"
     r"\n\t\tif (!hitTesting) port.runtime.RasterRelease.shiftFill(cairo, -1);", 1,
     "(same) lines, drawn by the same rasteriser"),
    ("openfl/display/_internal/CairoShape.hx",
     r"(\t\tvar graphics = shape\.__graphics;\r?\n\r?\n)(\t\tif \(graphics != null\)\r?\n\t\t\{\r?\n"
     r"\t\t\tCairoGraphics\.render\(graphics, renderer\);)",
     r"\1\t\tif (graphics != null && port.runtime.DirectVectors.render(shape, renderer, alpha)) return;\n\n\2", 2,
     "fidelity: inside ``BitmapData.draw`` a drawing of fills is drawn straight into the target with its full "
     "transform, as Flash rasterises vectors (``port.runtime.DirectVectors``); OpenFL painted a scale-only raster "
     "rotated, which left the rotated bones the art baker draws with dotted, soft outlines. Both render functions "
     "(the second is OpenFL's legacy scale-9 one, not compiled here)"),
    ("openfl/display/Graphics.hx",
     r"(\t\tvar graphicsData = new Vector<IGraphicsData>\(\);\r?\n)(\t\t__owner\.__readGraphicsData\(graphicsData, recurse\);)",
     r"\1\t\tport.runtime.swf.GraphicsDataTransform.beginRead();\n\2"
     r"\n\t\tport.runtime.swf.GraphicsDataTransform.endRead(graphicsData);", 1,
     "(same) the game's colour swap (``class_176.method_6868``) reads a shape's fills, recolours them and draws them "
     "into a cleared drawing: a read of SWF shapes' fills only is remembered (``GraphicsDataTransform``)"),
    ("openfl/display/Graphics.hx",
     r"(private function __readGraphicsData\(graphicsData:Vector<IGraphicsData>, \?transform:Matrix\):Void\r?\n\t\{\r?\n"
     r"\t\tvar portStart = graphicsData\.length;\n)",
     r"\1\t\tif (!__portAdditive && __commands.types.length > 0) port.runtime.swf.GraphicsDataTransform.readAdditive = false;\n"
     r"\t\tvar portGroups:Array<Int> = __portAdditive ? (__portGroups != null ? __portGroups : [0]) : null;\n"
     r"\t\tvar portIndex = 0, portNext = 0;\n", 1,
     "(same) any drawing read that is not a SWF shape's makes the read an ordinary one; an empty one does not (the "
     "game's ``param1.graphics`` creates one on every bone clip it reads). Each style group of each shape read is "
     "noted where it starts in the result"),
    ("openfl/display/Graphics.hx",
     r"(\t\t\t\t\t\}\r?\n\t\t\t\}\r?\n\r?\n)(\t\t\tswitch \(type\)\r?\n\t\t\t\{\r?\n\t\t\t\tcase CUBIC_CURVE_TO:\r?\n"
     r"\t\t\t\t\tvar c = data\.readCubicCurveTo\(\);\r?\n\t\t\t\t\tpath\.cubicCurveTo)",
     r"\1\t\t\tif (portGroups != null && portNext < portGroups.length && portIndex == portGroups[portNext]) {\n"
     r"\t\t\t\tport.runtime.swf.GraphicsDataTransform.groupAt(graphicsData.length);\n\t\t\t\tportNext++;\n\t\t\t}\n"
     r"\t\t\tportIndex++;\n\2", 1,
     "(same) a group starts at its first command, after the path before it was flushed"),
    ("openfl/display/Graphics.hx",
     r"(public function drawGraphicsData\(graphicsData:Vector<IGraphicsData>\):Void\r?\n\t\{\r?\n)",
     r"\1\t\tvar portFresh = __commands.length == 0;\n"
     r"\t\tvar portGroupsAt = portFresh ? port.runtime.swf.GraphicsDataTransform.groupsOf(graphicsData) : null;\n"
     r"\t\tvar portData = 0;\n\t\tvar portCommandGroups:Array<Int> = [];\n", 1, "(same)"),
    ("openfl/display/Graphics.hx",
     r"(\t\tfor \(graphics in graphicsData\)\r?\n\t\t\{\r?\n)(\t\t\tswitch \(graphics\.__graphicsDataType\))",
     r"\1\t\t\tif (portGroupsAt != null && portGroupsAt.indexOf(portData) >= 0) portCommandGroups.push(__commands.types.length);\n"
     r"\t\t\tportData++;\n\2", 1,
     "(same) where each group read starts in the drawing's commands"),
    ("openfl/display/Graphics.hx",
     r"(\t\t\t\t\tdrawQuads\(quadPath\.rects, quadPath\.indices, quadPath\.transforms\);\r?\n\t\t\t\}\r?\n\t\t\}\r?\n)(\t\})",
     r"\1\t\tif (portFresh && port.runtime.swf.GraphicsDataTransform.drawsBack(graphicsData)) {\n"
     r"\t\t\t__portAdditive = true;\n\t\t\t__portGroups = portCommandGroups.length > 1 ? portCommandGroups : null;\n\t\t}\n\2",
     1,
     "(same) drawn as it was read into an empty drawing, the recoloured fills are SWF shapes' again: each group's "
     "fills are added and the groups (the bone's shapes and their style groups) painted one over the other, as "
     "``DirectVectors`` draws a shape of several groups (no seams in the recoloured legends, which AIR draws without)"),
    ("openfl/display/Graphics.hx", r"(\t@:noCompletion private var __bounds:Rectangle;)",
     r"\1\n\t// port: the commands are one SWF shape's style group, whose fills do not overlap (``SwfShape``): Cairo"
     r" adds them\n\t@:noCompletion public var __portAdditive:Bool = false;"
     r"\n\t// port: where each style group starts in the commands, for a SWF shape of several (``SwfShape``)"
     r"\n\t@:noCompletion public var __portGroups:Array<Int> = null;", 1,
     "(same) the flag ``SwfShape`` sets"),
    ("openfl/display/Graphics.hx",
     r"(\t\t__commands = sourceGraphics\.__commands\.copy\(\);)",
     r"\1\n\t\t__portAdditive = sourceGraphics.__portAdditive;\n\t\t__portGroups = sourceGraphics.__portGroups;", 1, "(same) an instance of a shape template keeps it"),
    ("openfl/display/Graphics.hx", r"(\tpublic function clear\(\):Void\r?\n\t\{\r?\n)",
     r"\1\t\t__portAdditive = false;\n\t\t__portGroups = null;\n", 1,
     "(same) other drawing in a cleared drawing is the game's"),
    ("openfl/display/_internal/CairoGraphics.hx",
     r"(\t\tif \(!graphics\.__softwareDirty \|\| graphics\.__managed\)\r?\n\t\t\{\r?\n\t\t\tCairoGraphics\.graphics = null;"
     r"\r?\n\t\t\treturn;\r?\n\t\t\}\r?\n)",
     r"\1\n\t\tif (port.runtime.RasterCache.lookup(graphics, hasScale9Grid, allowSmoothing))\n\t\t{\n"
     r"\t\t\tCairoGraphics.graphics = null;\n\t\t\treturn;\n\t\t}\n", 1,
     "a drawing that shares its template's commands shows the raster another instance made with the same "
     "key (``port.runtime.RasterCache``; the menu re-rasterised every shape after each match)"),
    ("openfl/display/_internal/CairoGraphics.hx",
     r"(\t\t\tgraphics\.__bitmap\.image\.version\+\+;\r?\n)",
     r"\1\t\t\tport.runtime.RasterCache.store(graphics, hasScale9Grid, allowSmoothing);\n", 1,
     "(same) the second raster of a key becomes shared (``RasterCache.store``)"),
    ("openfl/display/_internal/CairoShape.hx", r"graphics\.__cairo\.target", "graphics.__bitmap.getSurface()", 3,
     "(same) the software renderer paints a drawing from its raster's surface (``__bitmap.getSurface()``, the surface "
     "its Cairo context was made on) instead of the context's target: a drawing showing a shared raster has no "
     "context"),
    ("openfl/display/_internal/CairoShape.hx", r"graphics\.__cairo != null", "graphics.__bitmap != null", 1,
     "(same)"),
    ("openfl/display/BitmapData.hx", r"(\t@:noCompletion private var __textureVersion:Int;)",
     r"\1\n\t// port: a raster shared by several drawings (port.runtime.RasterCache): never pooled or disposed by them\n"
     r"\t@:noCompletion public var __portShared:Bool = false;", 1,
     "(same) marks a shared raster, so ``RasterRelease`` drops the reference instead of pooling the bitmap"),
    ("openfl/display/_internal/Context3DGraphics.hx",
     r"(#elseif lime_cairo\r?\n\t\t\t)CairoGraphics\.render\(graphics, cast renderer\.__softwareRenderer\);",
     r"\1port.runtime.SlowRasters.render(graphics, cast renderer.__softwareRenderer);", 1,
     "the GL renderer's Cairo rasters of vector drawings go through ``SlowRasters.render``, which "
     "times each and logs those over 30 ms with the drawing's display path (which art makes a long frame)"),
    ("openfl/display/_internal/DrawCommandBuffer.hx", r"(\r?\n)(\tpublic function clear\(\):Void)",
     r"\1\t// port: empties a buffer that owns its arrays, keeping their capacity\1"
     r"\tpublic function __portReset():Void\1\t{\1\t\tif (copyOnWrite)\1\t\t{\1\t\t\tclear();\1\t\t\treturn;\1\t\t}\1"
     r"\t\ttypes.resize(0);\1\t\tb.resize(0);\1\t\ti.resize(0);\1\t\tf.resize(0);\1\t\to.resize(0);\1"
     r"\t\tff.resize(0);\1\t\tii.resize(0);\1\t}\1\1\2", 1,
     "``__portReset`` empties a buffer that owns its arrays and keeps their capacity; ``clear`` "
     "points it back at the shared empty arrays, so the next write copies them and grows them again by half"),
    ("openfl/display/_internal/CairoGraphics.hx", r"\b(fillCommands|strokeCommands)\.clear\(\);",
     r"\1.__portReset();", 6,
     "(same) Cairo's two static scratch buffers (each drawing's fill and stroke commands, replayed at every Cairo "
     "render) keep their arrays from render to render: their regrowth was the largest drawing-command allocation "
     "left in a match (``replay ... track:``); nothing else holds those arrays (they are read by ``playCommands`` "
     "only, never appended to another buffer)"),
    ("openfl/utils/Endian.hx", r"abstract Endian\(Null<Int>\)", "abstract Endian(Int)", 1,
     "an ``Int``-backed enum instead of ``Null<Int>``. HashLink boxes a ``Null<Int>`` enum "
     "constant at every comparison and ``switch`` (probe: 100,000 compares allocate 1.6 MB; an ``Int`` enum none): "
     "``ByteArray``'s ``endian`` tests and Context3D's program/vertex-format tests were about half of a match "
     "frame's boxes (``port_track_summary.py --type i32``). The compiler rejects every remaining ``null`` use of "
     "the type, so the build compiling shows none is left in OpenFL, Lime or the game"),
    ("openfl/utils/Endian.hx",
     r"(@:from private static function from\w+\([^)]*\):Endian\r?\n\t\{\r?\n\t\treturn switch \(value\)\r?\n\t\t\{\r?\n"
     r"(?:\t\t\tcase[^\n]*\r?\n)*?\t\t\t)default: null;",
     r"\1default: cast -1;", 3,
     "(same) an unknown name converts to -1, which no constant equals (as the null it was); the third match is "
     "the String-backed declaration of the other targets, not compiled here"),
    ("openfl/utils/ByteArray.hx", r"private static var __defaultEndian:Endian = null;",
     "private static var __defaultEndian:Null<Endian> = null;", 1,
     "(same) the one null of ``Endian`` in OpenFL: the lazily computed default, now an explicit ``Null<Endian>``"),
    ("openfl/display/DisplayObject.hx", r"if \(__blendMode == null \|\| __blendMode == NORMAL\)",
     "if (__blendMode == null || (cast __blendMode : Int) == 10) // port: NORMAL, unboxed", 1,
     "(same) the per-object blend test of every display update (``BlendMode`` stays ``Null<Int>``: OpenFL and the "
     "game use its null); comparing the unboxed value with NORMAL's 10 allocates nothing (probe)"),
    ("openfl/display/ShaderParameter.hx", r"\bindex \+ i\b", "(index : Int) + i", 18,
     "(same) a vertex attribute's location (``index:Dynamic``, an Int natively) plus the slot: ``Dynamic + Int`` "
     "went through ``Std.__add__`` and boxed the sum at every bound shader attribute"),
    ("openfl/display3D/Context3DProgramType.hx", r"abstract Context3DProgramType\(Null<Int>\)", "abstract Context3DProgramType(Int)", 1,
     "(same)"),
    ("openfl/display3D/Context3DProgramType.hx",
     r"(@:from private static function from\w+\([^)]*\):Context3DProgramType\r?\n\t\{\r?\n\t\treturn switch \(value\)\r?\n\t\t\{\r?\n"
     r"(?:\t\t\tcase[^\n]*\r?\n)*?\t\t\t)default: null;",
     r"\1default: cast -1;", 1,
     "(same) an unknown name converts to -1, which no constant equals (as the null it was)"),
    ("openfl/display3D/Context3DProgramFormat.hx", r"abstract Context3DProgramFormat\(Null<Int>\)", "abstract Context3DProgramFormat(Int)", 1,
     "(same)"),
    ("openfl/display3D/Context3DProgramFormat.hx",
     r"(@:from private static function from\w+\([^)]*\):Context3DProgramFormat\r?\n\t\{\r?\n\t\treturn switch \(value\)\r?\n\t\t\{\r?\n"
     r"(?:\t\t\tcase[^\n]*\r?\n)*?\t\t\t)default: null;",
     r"\1default: cast -1;", 1,
     "(same) an unknown name converts to -1, which no constant equals (as the null it was)"),
    ("openfl/display3D/Context3DVertexBufferFormat.hx", r"abstract Context3DVertexBufferFormat\(Null<Int>\)", "abstract Context3DVertexBufferFormat(Int)", 1,
     "(same)"),
    ("openfl/display3D/Context3DVertexBufferFormat.hx",
     r"(@:from private static function from\w+\([^)]*\):Context3DVertexBufferFormat\r?\n\t\{\r?\n\t\treturn switch \(value\)\r?\n\t\t\{\r?\n"
     r"(?:\t\t\tcase[^\n]*\r?\n)*?\t\t\t)default: null;",
     r"\1default: cast -1;", 1,
     "(same) an unknown name converts to -1, which no constant equals (as the null it was)"),
]


def apply_hl_library_patches(target: Path) -> int:
    applied = 0
    patched: dict[str, str] = {}
    for rel, pattern, replacement, expected, _reason in HL_LIBRARY_PATCHES:
        text = patched.get(rel)
        if text is None:
            text = (OPENFL_SRC / rel).read_bytes().decode("utf-8")
        text, found = re.subn(pattern, replacement, text)
        if found != expected:
            raise ValueError(f"OpenFL patch for {rel} matched {found} times, expected {expected}")
        patched[rel] = text
        applied += found
    for rel, text in patched.items():
        out = target / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text, encoding="utf-8", newline="")
    return applied


def apply_short_dynamic_calls(target: Path, generated: Path | None = None) -> int:
    from tools import port_dyncalls
    generated = generated or NATIVE_GENERATED
    files = [path for path in sorted(target.rglob("*.hx")) if (generated / path.relative_to(target)).exists()
             and not (RUNTIME / path.relative_to(target)).exists()]
    openfl = [path.read_text(encoding="utf-8") for path in sorted(OPENFL_SRC.rglob("*.hx"))
              if "/_internal/" not in path.as_posix()]
    return port_dyncalls.apply(target, files, openfl, named_packages=("bh/",))


def apply_hl_probes(target: Path, spec: str | None = None, call: str = "port.runtime.NativeMain.probe") -> int:
    spec = spec if spec is not None else os.environ.get("PORT_HL_PROBES", "")
    if not spec:
        return 0
    probes = json.loads(Path(spec).read_text(encoding="utf-8"))
    for index, probe in enumerate(probes):
        path = target / probe["file"]
        lines = path.read_text(encoding="utf-8").split("\n")
        anchor = probe.get("after", probe.get("before"))
        found = [i for i, line in enumerate(lines) if anchor in line]
        if len(found) != 1:
            raise ValueError(f"probe {index}: anchor {anchor!r} is on {len(found)} lines of {probe['file']}")
        at = found[0] + (1 if "after" in probe else 0)
        indent = re.match(r"[ \t]*", lines[found[0]]).group(0)
        lines.insert(at, f"{indent}{call}({index}, {int(probe.get('limit', 20))}, "
                         f"() -> {probe['expr']});")
        path.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"{len(probes)} debug probes staged from {spec}")
    return len(probes)


UNARY_MINUS_RE = re.compile(r"(?:(?<=[(\[,=?:!<>&|+*/%^~])|(?<=\breturn))([ \t]*)-(?=[ \t]*[A-Za-z_(])")
OPERAND_HEAD_RE = re.compile(r"[ \t]*(?:[A-Za-z_][\w]*(?:\.[A-Za-z_]\w*)*)?")


def negation_operand_end(text: str, start: int) -> int:
    from tools import port_dyncalls
    i = OPERAND_HEAD_RE.match(text, start).end()
    if i == start or text[start:i].strip() == "":
        i = start + (len(text[start:]) - len(text[start:].lstrip(" \t")))
        if i >= len(text) or text[i] != "(":
            return start
    while i < len(text):
        if text[i] in "([":
            i = port_dyncalls.matching_paren(text, i)
        elif text[i] == "." and i + 1 < len(text) and (text[i + 1].isalpha() or text[i + 1] == "_"):
            i = OPERAND_HEAD_RE.match(text, i + 1).end()
        else:
            break
    return i


def apply_hl_negation(target: Path, generated: Path | None = None) -> int:
    generated = generated or NATIVE_GENERATED
    count = 0
    for path in sorted(target.rglob("*.hx")):
        rel = path.relative_to(target)
        if not (generated / rel).exists() or (RUNTIME / rel).exists() or (RUNTIME_HL / rel).exists():
            continue
        text = path.read_text(encoding="utf-8")
        out = []
        pos = 0
        for match in UNARY_MINUS_RE.finditer(text):
            if match.start() < pos:
                continue
            operand_start = match.end()
            end = negation_operand_end(text, operand_start)
            if end <= operand_start:
                continue
            operand = text[operand_start:end].strip()
            out.append(text[pos:match.start()] + match.group(1) + f"port.runtime.As3.neg({operand})")
            pos = end
            count += 1
        if out:
            path.write_text("".join(out) + text[pos:], encoding="utf-8", newline="\n")
    return count


MATH_ROUNDING_RE = re.compile(r"(?<![\w.])Math\.(floor|ceil|round)\(")


def apply_hl_math_rounding(target: Path, generated: Path | None = None) -> int:
    generated = generated or NATIVE_GENERATED
    count = 0
    for path in sorted(target.rglob("*.hx")):
        rel = path.relative_to(target)
        if not (generated / rel).exists() or (RUNTIME / rel).exists() or (RUNTIME_HL / rel).exists():
            continue
        text = path.read_text(encoding="utf-8")
        new, n = MATH_ROUNDING_RE.subn(r"port.runtime.As3.\1(", text)
        if n:
            path.write_text(new, encoding="utf-8", newline="\n")
            count += n
    return count


MATH_FUNCTIONS_RE = re.compile(r"(?<![\w.])Math\.(sin|cos|tan|asin|acos|atan2|atan|exp|log|pow)\(")


def apply_hl_math_functions(target: Path, generated: Path | None = None) -> int:
    generated = generated or NATIVE_GENERATED
    count = 0
    for path in sorted(target.rglob("*.hx")):
        rel = path.relative_to(target)
        if not (generated / rel).exists() or (RUNTIME / rel).exists() or (RUNTIME_HL / rel).exists():
            continue
        text = path.read_text(encoding="utf-8")
        new, n = MATH_FUNCTIONS_RE.subn(r"port.runtime.As3.\1(", text)
        if n:
            path.write_text(new, encoding="utf-8", newline="\n")
            count += n
    return count


def apply_hl_adaptations(target: Path, generated: Path | None = None) -> int:
    generated = generated or NATIVE_GENERATED
    applied = 0
    for rel, pattern, replacement, expected, _reason in HL_ADAPTATIONS:
        if isinstance(expected, tuple):
            expected = expected[1] if RAW or BIFROST else expected[0]
        if rel != "*" and expected == 0 and not (target / rel).exists():
            continue
        paths = ([path for path in sorted(target.rglob("*.hx")) if (generated / path.relative_to(target)).exists()
                  and not (RUNTIME / path.relative_to(target)).exists()]
                 if rel == "*" else [target / rel])
        count = layer = 0
        for path in paths:
            text = path.read_text(encoding="utf-8")
            text, found = re.subn(pattern, replacement, text)
            if found:
                path.write_text(text, encoding="utf-8", newline="\n")
                if BIFROST and path.relative_to(target).parts[0] == "bh":
                    layer += found
                else:
                    count += found
        if count != expected:
            site_mismatch(f"native adaptation for {rel} matched {count} times, expected {expected}: {_reason}")
        applied += count + layer
    return applied


SITE_MISMATCHES: list[str] = []


VECTOR_ELEMENT_ARG_RE = r"(\.\w+\()(port\.runtime\.As3\.index\((?:this\.)?(?:{fields}), [^()]*\))\)"


def apply_vector_element_downcasts(target: Path, generated: Path | None = None) -> int:
    generated = generated or NATIVE_GENERATED
    fields = sorted({name for name, rows in as3_field_declarations(scripts_path()).items()
                     if rows and all(re.fullmatch(r"Vector\.<class_\d+>", kind) for _cls, kind in rows)})
    if not fields:
        return 0
    pattern = re.compile(VECTOR_ELEMENT_ARG_RE.format(fields="|".join(map(re.escape, fields))))
    applied = 0
    for path in sorted(target.rglob("*.hx")):
        rel = path.relative_to(target)
        if not (generated / rel).exists() or (RUNTIME / rel).exists():
            continue
        text, found = pattern.subn(r"\1cast(\2))", path.read_text(encoding="utf-8"))
        if found:
            path.write_text(text, encoding="utf-8", newline="\n")
            applied += found
    return applied


def site_mismatch(message: str) -> None:
    if VERSION == "10.11":
        raise ValueError(message)
    SITE_MISMATCHES.append(message)
    print(f"site mismatch ({VERSION}): {message}")


GAME_TYPE_ENUM_FUNCTIONS = ("createEnum", "createEnumIndex", "enumConstructor", "enumParameters", "allEnums")
GAME_TYPE_REF_RE = re.compile(r"(?<![\w.$])Type\.(?=(?:" + "|".join(GAME_TYPE_ENUM_FUNCTIONS) + r")\()")
GAME_TYPE_REFLECTION_RE = re.compile(
    r"\n      public static function (?:getClass|getClassName|createInstance)\(.*?(?=\n      public static function )",
    re.S)


def stage_game_type(target: Path, generated: Path) -> int:
    text = (generated / "Type.hx").read_text(encoding="utf-8")
    text = re.sub(r"\bclass Type\b", "class GameType", text, count=1)
    text, removed = GAME_TYPE_REFLECTION_RE.subn("", text)
    if removed != 3:
        raise ValueError(f"game Type: expected 3 reflection functions, found {removed}")
    text = GAME_TYPE_REF_RE.sub("GameType.", text)
    text = text.replace("param1:Class<Dynamic>", "param1:Dynamic")
    text, applied = re.subn(r"\b_loc4_\.apply\(param1,param3\)", "Reflect.callMethod(param1,_loc4_,param3)", text)
    if applied != 1:
        raise ValueError(f"game Type: expected 1 Function.apply in createEnum, found {applied}")
    (target / "GameType.hx").write_text(text, encoding="utf-8", newline="\n")
    sites = 0
    for path in sorted(target.rglob("*.hx")):
        rel = path.relative_to(target)
        if rel == Path("GameType.hx") or not (generated / rel).exists() or (RUNTIME / rel).exists():
            continue
        code = path.read_text(encoding="utf-8")
        code, found = GAME_TYPE_REF_RE.subn("GameType.", code)
        if found:
            path.write_text(code, encoding="utf-8", newline="\n")
            sites += found
    return sites


GAME_DS_CLASSES = ("EnumValueMap", "BalancedTree", "TreeNode")
GAME_DS_PACKAGE = "port.gameds"


def stage_game_ds(target: Path, generated: Path) -> int:
    names = "|".join(GAME_DS_CLASSES)
    out_dir = target / Path(*GAME_DS_PACKAGE.split("."))
    out_dir.mkdir(parents=True, exist_ok=True)
    for name in GAME_DS_CLASSES:
        text = (generated / "haxe" / "ds" / f"{name}.hx").read_text(encoding="utf-8")
        text = text.replace("package haxe.ds;", f"package {GAME_DS_PACKAGE};", 1)
        text = GAME_TYPE_REF_RE.sub("GameType.", text)
        text = text.replace(" implements IMap\n", "\n")
        (out_dir / f"{name}.hx").write_text(text, encoding="utf-8", newline="\n")
    reference = re.compile(rf"\bhaxe\.ds\.({names})\b")
    generic = re.compile(rf"\b({names})<Dynamic, Dynamic>")
    count = 0
    for path in sorted(target.rglob("*.hx")):
        rel = path.relative_to(target)
        if not (generated / rel).exists() or (RUNTIME / rel).exists() or rel.parts[:2] == ("haxe", "ds"):
            continue
        code = path.read_text(encoding="utf-8")
        if not re.search(rf"\b({names})\b", code):
            continue
        code, found = reference.subn(rf"{GAME_DS_PACKAGE}.\1", code)
        code, typed = generic.subn(r"\1", code)
        if found or typed:
            path.write_text(code, encoding="utf-8", newline="\n")
            count += found + typed
    return count


def without_script_code(text: str) -> str:
    lines = text.split("\n")
    in_class = False
    for index, line in enumerate(lines):
        if re.match(r"\s+(?:final\s+)?class\s", line):
            in_class = True
        elif in_class and line and not line[0].isspace() and line[0] != "}":
            return "\n".join(lines[:index]).rstrip() + "\n"
    return text


def stage_boot_classes(src: Path, generated: Path) -> None:
    for rel in (Path("flash") / "Boot.hx", Path("flash") / "Lib.hx"):
        text = without_script_code((generated / rel).read_text(encoding="utf-8"))
        if rel.name == "Lib.hx":
            text = text.replace("package flash;\n", "package flash;\n\nimport port.runtime.As3.navigateToURL;\n", 1)
        (src / rel).parent.mkdir(parents=True, exist_ok=True)
        (src / rel).write_text(text, encoding="utf-8", newline="\n")


NATIVE_FIXES_ADDED = (Path("GameType.hx"),) + tuple(Path(*GAME_DS_PACKAGE.split("."), f"{name}.hx")
                                                     for name in GAME_DS_CLASSES)


IMAP_FIELD_RE = re.compile(r"\bvar (var_\d+):([\w.<>, ]+?)\s*[;=]")
IMAP_HAS_NEXT_RE = re.compile(r"(?<![\w.])((?:this|[A-Za-z_]\w*)(?:\.[A-Za-z_]\w*)*)\.iterator\(\)\.hasNext\(\)")


def apply_hl_imap_calls(target: Path, generated: Path | None = None) -> int:
    generated = generated or NATIVE_GENERATED
    files = []
    for path in sorted(target.rglob("*.hx")):
        rel = path.relative_to(target)
        if not (generated / rel).exists() or (RUNTIME / rel).exists() or (RUNTIME_HL / rel).exists():
            continue
        files.append(path)
    types: dict[str, set[str]] = {}
    texts = {path: path.read_text(encoding="utf-8") for path in files}
    for text in texts.values():
        for m in IMAP_FIELD_RE.finditer(text):
            types.setdefault(m.group(1), set()).add(m.group(2).strip())
    count = 0
    for path, text in list(texts.items()):
        new, n = IMAP_HAS_NEXT_RE.subn(lambda m: f"port.runtime.As3.imapHasNext({m.group(1)})", text)
        if n:
            texts[path] = new
            path.write_text(new, encoding="utf-8", newline="\n")
            count += n
    fields = sorted(name for name, kinds in types.items() if kinds == {"IMap"})
    if not fields:
        return count
    call = re.compile(r"(?<![\w.])((?:(?:this|[A-Za-z_]\w*)\.)*(?:" + "|".join(fields)
                      + r"))\.(exists|method_4935)\(")
    for path, text in texts.items():
        new, n = call.subn(lambda m: "port.runtime.As3." + ("imapExists" if m.group(2) == "exists" else "imapGet")
                           + f"({m.group(1)}, ", text)
        if n:
            path.write_text(new, encoding="utf-8", newline="\n")
            count += n
    return count


NUMBER_VECTOR_TYPES = {"Vector<Float>", "Vector<Int>", "Vector<UInt>"}


def apply_hl_vector_pushes(target: Path, generated: Path | None = None) -> int:
    generated = generated or NATIVE_GENERATED
    texts = {}
    for path in sorted(target.rglob("*.hx")):
        rel = path.relative_to(target)
        if not (generated / rel).exists() or (RUNTIME / rel).exists() or (RUNTIME_HL / rel).exists():
            continue
        texts[path] = path.read_text(encoding="utf-8")
    types: dict[str, set[str]] = {}
    for text in texts.values():
        for m in IMAP_FIELD_RE.finditer(text):
            types.setdefault(m.group(1), set()).add(m.group(2).replace(" ", ""))
    fields = sorted(name for name, kinds in types.items() if len(kinds) == 1 and kinds <= NUMBER_VECTOR_TYPES)
    if not fields:
        return 0
    call = re.compile(r"(?<![\w.])((?:(?:this|[A-Za-z_]\w*)\.)*(?:" + "|".join(fields) + r"))\.push\((?!\s*\))")
    count = 0
    for path, text in texts.items():
        new, n = call.subn(lambda m: f"port.runtime.As3.vectorPush({m.group(1)}, ", text)
        if n:
            path.write_text(new, encoding="utf-8", newline="\n")
            count += n
    return count


def native_fixes_key(converted: Path) -> str:
    digest = hashlib.sha256()
    stamp = converted / ".convert-key"
    for data in (stamp.read_bytes() if stamp.exists() else b"<no key>",
                 Path(__file__).read_bytes(), (ROOT / "tools" / "port_dyncalls.py").read_bytes(),
                 repr(RAW).encode("utf-8"),
                 "\n".join(sorted(p.relative_to(RUNTIME).as_posix() for p in RUNTIME.rglob("*.hx"))).encode("utf-8"),
                 str(OPENFL_SRC).encode("utf-8")):
        digest.update(hashlib.sha256(data).digest())
    for path in sorted(RUNTIME_HL.rglob("*.hx")):
        digest.update(path.relative_to(RUNTIME_HL).as_posix().encode("utf-8") + b"\0"
                      + hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def apply_native_fixes(converted: Path | None = None, final: Path | None = None, *, force: bool = False) -> dict | None:
    converted = converted or NATIVE_CONVERTED
    final = final or NATIVE_GENERATED
    try:
        final.resolve().relative_to(ROOT / "build")
    except ValueError:
        raise ValueError(f"refusing to replace a tree outside build/: {final}")
    key = native_fixes_key(converted)
    stamp = final / NATIVE_FIXES_KEY_FILE
    if not force and stamp.exists() and stamp.read_text(encoding="utf-8").strip() == key:
        return None
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="bh-port-fixes-") as td, staged_text_cache(Path(td)):
        src = Path(td) / "src"
        src.mkdir(parents=True)
        copy_filtered_generated_tree(src, converted)
        stage_boot_classes(src, converted)
        for source in sorted(RUNTIME_HL.rglob("*.hx")):
            staged = src / source.relative_to(RUNTIME_HL)
            staged.parent.mkdir(parents=True, exist_ok=True)
            staged.write_text(source.read_text(encoding="utf-8"), encoding="utf-8", newline="\n")
        counts = {"adaptations": apply_hl_adaptations(src, converted),
                  "negations": apply_hl_negation(src, converted),
                  "roundings": apply_hl_math_rounding(src, converted),
                  "math_functions": apply_hl_math_functions(src, converted),
                  "imap_calls": apply_hl_imap_calls(src, converted),
                  "vector_pushes": apply_hl_vector_pushes(src, converted)}
        counts["vector_downcasts"] = apply_vector_element_downcasts(src, converted)
        counts["type_sites"] = stage_game_type(src, converted) + stage_game_ds(src, converted)
        counts["short_calls"] = apply_short_dynamic_calls(src, converted)
        runtime ={p.relative_to(RUNTIME) for p in RUNTIME.rglob("*.hx")}
        runtime |= {p.relative_to(RUNTIME_HL) for p in RUNTIME_HL.rglob("*.hx")}
        boot = {Path("flash") / "Boot.hx", Path("flash") / "Lib.hx"}
        shutil.rmtree(final, ignore_errors=True)
        kept = 0
        for source in sorted(converted.rglob("*")):
            rel = source.relative_to(converted)
            if source.is_dir() or rel in runtime or rel.name == ".convert-key":
                continue
            out = final / rel
            out.parent.mkdir(parents=True, exist_ok=True)
            if source.suffix == ".hx" and (rel in boot or not should_skip_generated_source(rel)):
                out.write_text((src / rel).read_text(encoding="utf-8"), encoding="utf-8", newline="\n")
            else:
                shutil.copy2(source, out)
            kept += 1
        for rel in NATIVE_FIXES_ADDED:
            (final / rel).parent.mkdir(parents=True, exist_ok=True)
            (final / rel).write_text((src / rel).read_text(encoding="utf-8"), encoding="utf-8", newline="\n")
    counts["files"] = kept
    (final / "native-fixes.json").write_text(json.dumps(counts, indent=2) + "\n", encoding="utf-8")
    if VERSION != "10.11":
        report = PORT_BUILD / "site-mismatches.txt"
        report.parent.mkdir(parents=True, exist_ok=True)
        report.write_text("".join(line + "\n" for line in SITE_MISMATCHES), encoding="utf-8")
        print(f"{len(SITE_MISMATCHES)} native adaptation counts differ from 10.11's -> {report}")
    if not SITE_MISMATCHES or VERSION != "10.11":
        stamp.write_text(key + "\n", encoding="utf-8")
    print(f"native fixes in {time.monotonic() - started:.1f} s: {kept} game files, {counts['adaptations']} native "
          f"adaptations, {counts['negations']} negations, {counts['roundings']} Math roundings, "
          f"{counts['math_functions']} Math functions as AIR's, {counts['type_sites']} references to the game's own "
          f"Type/enum map, {counts['short_calls']} short dynamic calls padded -> {final}")
    return counts


def migrate_native_tree() -> None:
    if not NATIVE_CONVERTED.exists() and (NATIVE_GENERATED / ".convert-key").exists() \
            and not (NATIVE_GENERATED / NATIVE_FIXES_KEY_FILE).exists():
        NATIVE_GENERATED.rename(NATIVE_CONVERTED)
        print(f"moved the converted native tree to {NATIVE_CONVERTED}")


HL_MAIN = "port.runtime.NativeMain"


def hl_check_args(work: Path, hl: Path, *, emit_output: bool, main: str | None = None) -> list[str]:
    args = [
        str(HAXE),
        "--cwd", str(work),
        "--class-path", "src",
        "--class-path", str(OPENFL_SRC),
        "--class-path", str(LIME_SRC),
        "--class-path", "lib-patches",
        "-D", "openfl=9.5.2",
        "-D", "lime=8.3.2",
        "--macro", "lime._internal.macros.DefineMacro.run()",
        "--macro", "openfl.utils._internal.ExtraParamsMacro.include()",
        "--macro", "allowPackage('flash')",
        "--macro", HL_FULL_INCLUDE_MACRO,
        "--hl", str(hl),
    ]
    if main:
        args.extend(["--main", main])
    for define in os.environ.get("PORT_HAXE_DEFINES", "").split():
        args.extend(["-D", define])
    if BIFROST:
        args.extend(["-D", "bifrost"])
    if not emit_output:
        args.append("--no-output")
    return args


def hl_check(*, convert: bool = True, out: Path | None = None, main: str | None = None,
             extra: list[Path] | None = None, export: tuple[Path, Path] | None = None) -> int:
    require_haxe()
    if not OPENFL_SRC.exists() or not LIME_SRC.exists():
        raise FileNotFoundError("Missing pinned OpenFL/Lime: run python tools/setup_openfl.py")
    migrate_native_tree()
    if convert:
        write_field_init_order()
        convert_tree(NATIVE_CONVERTED, native=True)
    check_tree_kind(NATIVE_CONVERTED)
    fixes = apply_native_fixes()
    if fixes is None:
        fixes = json.loads((NATIVE_GENERATED / "native-fixes.json").read_text(encoding="utf-8"))
    with tempfile.TemporaryDirectory(prefix="bh-port-hl-") as td, staged_text_cache(Path(td)):
        started = time.monotonic()
        work = Path(td)
        src = work / "src"
        src.mkdir(parents=True)
        copied = copy_filtered_generated_tree(src, NATIVE_GENERATED)
        for rel in (Path("flash") / "Boot.hx", Path("flash") / "Lib.hx"):
            (src / rel).write_text((NATIVE_GENERATED / rel).read_text(encoding="utf-8"), encoding="utf-8",
                                   newline="\n")
        for source in sorted(RUNTIME_HL.rglob("*.hx")):
            staged = src / source.relative_to(RUNTIME_HL)
            staged.parent.mkdir(parents=True, exist_ok=True)
            staged.write_text(source.read_text(encoding="utf-8"), encoding="utf-8", newline="\n")
        for source in extra or []:
            (src / source.name).write_text(source.read_text(encoding="utf-8"), encoding="utf-8", newline="\n")
        shims, missing = write_openfl_flash_shims(src)
        adapted, short_calls = fixes["adaptations"], fixes["short_calls"]
        negations, roundings, math_functions = fixes["negations"], fixes["roundings"], fixes["math_functions"]
        guarded = stored = 0
        check_native_net_engine(src)
        type_sites = fixes["type_sites"]
        adapted += apply_hl_library_patches(work / "lib-patches")
        apply_hl_probes(src)
        if export is not None:
            game_out, engine_out = export
            for folder in (game_out / "src", engine_out / "runtime", engine_out / "lib-patches"):
                shutil.rmtree(folder, ignore_errors=True)
            game_files = engine_files = 0
            for path in sorted(src.rglob("*")):
                if path.is_dir():
                    continue
                rel = path.relative_to(src)
                converted = NATIVE_GENERATED / rel
                if converted.exists():
                    if path.read_text(encoding="utf-8") != converted.read_text(encoding="utf-8") \
                            and not os.environ.get("PORT_HL_PROBES"):
                        raise ValueError(f"staging changed the converted game file {rel.as_posix()}")
                    dest, game_files = game_out / "src" / rel, game_files + 1
                else:
                    dest, engine_files = engine_out / "runtime" / rel, engine_files + 1
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, dest)
            shutil.copytree(work / "lib-patches", engine_out / "lib-patches")
            print(f"exported {game_files} game files as converted to {game_out}; {engine_files} runtime files and"
                  f" {adapted - fixes['adaptations']} library patches to {engine_out}")
            return 0
        if out is not None:
            out.parent.mkdir(parents=True, exist_ok=True)
        staged_at = time.monotonic()
        limit = float(os.environ.get("PORT_HAXE_TIMEOUT", "300"))
        try:
            result = subprocess.run(hl_check_args(work, out or work / "check.hl", emit_output=out is not None,
                                                  main=main), text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=limit)
        except subprocess.TimeoutExpired:
            print(f"HashLink Haxe compile stopped after {limit:.0f} s (PORT_HAXE_TIMEOUT): a macro that does not "
                  "finish? A normal compile takes ~20-30 s.")
            return 1
        print(f"HashLink build times: staging {staged_at - started:.1f} s, Haxe {time.monotonic() - staged_at:.1f} s")
        print(f"HashLink check ({tree_kind()} tree) staged {copied} generated files plus runtime helpers and {shims} OpenFL aliases,"
              f" {adapted} native adaptations, {short_calls} short dynamic calls padded, {negations} negations, {roundings} Math roundings, {math_functions} Math functions as AIR's,"
              f" {guarded} network sites behind the guard, {stored} save-data sites,"
              f" {type_sites} references to the game's own Type/enum map;"
              f" Flash names with no OpenFL class or stand-in: {', '.join(missing) or 'none'}")
        if result.stdout:
            print(result.stdout.rstrip())
            print(haxe_error_summary(result.stdout))
        if result.returncode == 0:
            print("HashLink Haxe check OK" + (f"; output: {out}" if out is not None else ""))
        if out is not None:
            kept = out.parent / "staged"
            shutil.rmtree(kept, ignore_errors=True)
            shutil.copytree(src, kept)
        return result.returncode


def compare_flash(out: Path | None = None) -> int:
    out = out or FULL_FLASH_SWF
    rc = full_flash_compile(emit_output=True, out=out)
    return rc if rc != 0 else compare_existing(out)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "command",
        choices=("representative", "full-flash", "build-flash", "compare-existing", "compare-flash", "check-hl",
                 "build-hl"),
    )
    parser.add_argument("--out", type=Path, help="output SWF for build-flash/compare-existing/compare-flash; check-hl: also emit HashLink bytecode here")
    parser.add_argument("--mod", action="append", default=[],
                        help="build-flash: platform mod to register (bh/mods/<mod>), e.g. autopilot for the boot check")
    parser.add_argument("--with-platform", action="store_true",
                        help="convert the AIR build's tree (src/platform, hook lines) instead of the raw game; "
                             "needed for --mod")
    parser.add_argument("--bifrost", action="store_true",
                        help="Bifrost's tree (tools/bifrost_build.py tree) instead of the raw game, converted into "
                             "build/bifrost/root/build (the raw game's trees are not touched)")
    parser.add_argument("--smoke", action="store_true",
                        help="TEST build: compile in port.runtime.SmokeDriver (-D port_smoke), which reads "
                             "Documents\\Bifrost\\bh-port-smoke\\commands.txt; never the product")
    parser.add_argument("--no-convert", action="store_true",
                        help="check-hl/build-hl: use the existing converted tree instead of converting again")
    parser.add_argument("--low-priority", action="store_true",
                        help="run at below-normal priority (Windows; haxe and java inherit it): a compile beside a"
                             " soak or replay run leaves the game's frames alone")
    parser.add_argument("--version", default="10.11",
                        help="the game version (11.00), built in build/port-haxe/<ver> and <ver>-native")
    parser.add_argument("--engine", choices=("openfl", "heaps"), default="openfl",
                        help="check-hl: heaps type-checks the exported raw game against the new engine's flash.* "
                             "stand-ins over Heaps (tools/port_heaps_stubs.py; E1), with no OpenFL or Lime")
    args = parser.parse_args(argv)
    if args.low_priority and sys.platform == "win32":
        import ctypes
        kernel32 = ctypes.WinDLL("kernel32")
        kernel32.GetCurrentProcess.restype = ctypes.c_void_p
        kernel32.SetPriorityClass(ctypes.c_void_p(kernel32.GetCurrentProcess()), 0x4000)
    global RAW
    RAW = not args.with_platform
    if args.version != VERSION:
        use_version(args.version)
    if args.bifrost:
        if args.with_platform or args.mod:
            parser.error("--bifrost is Bifrost's own tree: not with --with-platform or --mod")
        use_bifrost()
    if args.mod and RAW:
        parser.error("--mod builds in an AIR-build platform mod: it needs --with-platform")
    if args.smoke:
        os.environ["PORT_HAXE_DEFINES"] = (os.environ.get("PORT_HAXE_DEFINES", "") + " port_smoke").strip()
    if args.engine == "heaps":
        if args.command != "check-hl":
            parser.error("--engine heaps: check-hl only (E1 type-checks; the Heaps build comes with E2+)")
        from tools import port_heaps_stubs
        return port_heaps_stubs.dump() or port_heaps_stubs.stubs(check=True)
    if args.command == "check-hl":
        return hl_check(convert=not args.no_convert, out=args.out)
    if args.command == "build-hl":
        if args.out is None:
            parser.error("build-hl needs --out <absolute path>.hl")
        return hl_check(convert=not args.no_convert, out=args.out, main=HL_MAIN)
    if args.command == "representative":
        representative_compile()
        print("representative Haxe compile OK")
        return 0
    if args.command == "full-flash":
        return full_flash_compile()
    if args.command == "build-flash":
        return full_flash_compile(emit_output=True, out=args.out, mods=args.mod)
    if args.command == "compare-existing":
        return compare_existing(args.out)
    if args.command == "compare-flash":
        return compare_flash(args.out)
    raise AssertionError(args.command)


if __name__ == "__main__":
    raise SystemExit(main())
