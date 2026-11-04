from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass, field
import hashlib
from pathlib import Path
import json
import re
import shutil
import sys


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "build" / "port-haxe" / "10.11" / "src"
VERSION = "10.11"
DEOBFUSCATED_CLASSES = ""

TYPE_MAP = {
    "Array": "Array<Dynamic>",
    "Boolean": "Bool",
    "Class": "Class<Dynamic>",
    "Dictionary": "Dynamic",
    "Function": "Dynamic",
    "int": "Int",
    "Number": "Float",
    "Object": "Dynamic",
    "Xml": "Xml",
    "void": "Void",
    "uint": "UInt",
}

TYPE_RE = re.compile(r"(?<!\.)\b(Array(?!\s*<)|Boolean|Class|Dictionary|Function|Number|Object|Xml|int|void|uint)\b")
ARRAY_CLASS_COMPARE_RE = re.compile(r"[=!]==?\s*Array\b(?![\w<.])|(?<![\w.])Array\s*[=!]==?")
ARRAY_CLASS_MARKER = "AS3ArrayClassValue"
PACKAGE_RE = re.compile(r"\A\s*package(?:\s+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*))?\s*\{", re.MULTILINE)
CLASS_RE = re.compile(r"\b(?:public\s+)?(?:(?:dynamic|final)\s+)*(?:class|interface)\s+([A-Za-z_]\w*)")
IMPORT_RE = re.compile(r"^(\s*)import\s+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*(?:\.\*)?)\s*;", re.MULTILINE)
CONSTRUCTOR_RE = re.compile(r"\bfunction\s+{name}\s*\(")
FUNCTION_RETURN_RE = re.compile(r"\)\s*:\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?|\*)")
VECTOR_CTOR_RE = re.compile(r"\bnew\s+Vector<([^>]+)>\s*\(")
VECTOR_CAST_RE = re.compile(r"\bVector<([^>]+)>\s*\(")
FOR_EACH_RE = re.compile(r"\bfor\s+each\s*\(\s*(?:var\s+)?([A-Za-z_]\w*)(?:\s*:\s*[^)\s]+)?\s+in\s+")
FOR_IN_VAR_RE = re.compile(r"\bfor\s*\(\s*var\s+([A-Za-z_]\w*)\s*:\s*([^)\s]+?)\s+in\s+")
FOR_IN_DYNAMIC_KEY_MARK = "__as3DynamicKey"
FOR_IN_TEXT_KEY_TYPES = {"String", "int", "uint", "Number", "Boolean", "Int", "UInt", "Float", "Bool"}
GETTER_SETTER_RE = re.compile(r"\bfunction\s+(get|set)\s+([A-Za-z_]\w*)\s*\(")
QUOTED_OBJECT_KEY_RE = re.compile(r"(?<=[{,])\s*['\"][A-Za-z_]\w*['\"]\s*:")
STAR_TYPE_RE = re.compile(r"(:\s*)\*(?=\s*[,)=;{])")
OBFUSCATED_CLASS_RE = re.compile(r"\bclass_(\d+)\b")
REGEX_LITERAL_RE = re.compile(
    r"(?P<prefix>(?:^|[=(:,?;\[\{!&|]\s*|\breturn\s+))/"
    r"(?P<body>(?:\\/|\\.|[^/\n\\])*)/"
    r"(?P<flags>[A-Za-z]*)",
    re.MULTILINE,
)
XML_LITERAL_RE = re.compile(r"<(?P<tag>[A-Za-z_][A-Za-z0-9_:-]*)(?P<attrs>[^<>]*)/>")
XML_ATTR_RE = re.compile(r"([A-Za-z_][A-Za-z0-9_:-]*)\s*=\s*(?:\{([^{}]+)\}|(__AS3_NONCODE_\d+__))")
AS3_HELPER = "port.runtime.As3"
STRING_ARG_CALL = f"{AS3_HELPER}.stringArg"
STRING_ARG_MACRO = True
AS3_CAST_CALL_TYPES = {
    "Bitmap",
    "DisplayObject",
    "DisplayObjectContainer",
    "Error",
    "File",
    "MovieClip",
    "Sprite",
    "TextField",
    "Xml",
}
PACKAGE_FUNCTIONS = {
    "flash.net.navigateToURL": "navigateToURL",
    "flash.utils.clearInterval": "clearInterval",
    "flash.utils.describeType": "describeType",
    "flash.utils.encodeURIComponent": "encodeURIComponent",
    "flash.utils.getDefinitionByName": "getDefinitionByName",
    "flash.utils.getQualifiedClassName": "getQualifiedClassName",
    "flash.utils.getTimer": "getTimer",
    "flash.utils.parseInt": "parseInt",
    "flash.utils.setInterval": "setInterval",
    "flash.utils.setTimeout": "setTimeout",
}
LEGACY_HAXE_INTERNAL_IMPORTS = {
    "haxe.IMap": "port.runtime.LegacyIMap as IMap",
    "haxe.ds._IntMap.IntMapKeysIterator": "haxe.ds.IntMapKeysIterator",
    "haxe.ds._IntMap.IntMapValuesIterator": "haxe.ds.IntMapValuesIterator",
    "haxe.ds._StringMap.StringMapKeysIterator": "haxe.ds._StringMap.StringMapKeysIterator",
    "haxe.ds._StringMap.StringMapValuesIterator": "haxe.ds._StringMap.StringMapValuesIterator",
    "haxe.ds._ObjectMap.NativePropertyIterator": "haxe.ds.NativePropertyIterator",
    "haxe.ds._ObjectMap.NativeValueIterator": "haxe.ds.NativeValueIterator",
}


@dataclass
class ConvertStats:
    files: int = 0
    unsupported: Counter[str] = field(default_factory=Counter)

    def add(self, other: "ConvertStats") -> None:
        self.files += other.files
        self.unsupported.update(other.unsupported)


RAW = False
PLATFORM_MARKER_RE = re.compile(r"//\s*bh-platform:[A-Za-z0-9_.-]+\s*$")
PLATFORM_IMPORT_RE = re.compile(r"^\s*import\s+bh\.(?:platform|mods)\.([\w.]+)\s*;\s*$")


@dataclass
class RawStats:
    files: int = 0
    marked_lines: int = 0
    imports: int = 0


RAW_STATS = RawStats()


def strip_platform_lines(text: str, name: str = "<text>") -> tuple[str, int, int]:
    kept: list[str] = []
    marked = 0
    imported: list[str] = []
    for line in text.split("\n"):
        if PLATFORM_MARKER_RE.search(line):
            marked += 1
            continue
        m = PLATFORM_IMPORT_RE.match(line)
        if m:
            imported.append(m.group(1).rsplit(".", 1)[-1])
            continue
        kept.append(line)
    if not marked and not imported:
        return text, 0, 0
    out = "\n".join(kept)
    code = "".join(span for is_code, span in split_code(out) if is_code)
    left = sorted({n for n in imported if re.search(rf"(?<![\w$.]){re.escape(n)}\b", code)})
    if left or re.search(r"\bbh\.(?:platform|mods)\b", code):
        raise ValueError(f"{name}: raw conversion leaves platform references ({', '.join(left) or 'bh.*'})"
                         " after removing the marked lines")
    return out, marked, len(imported)


def source_roots(root: Path, version: str) -> list[Path]:
    if RAW:
        return [root / "src" / "as3" / version / "scripts"]
    return [
        root / "src" / "as3" / version / "scripts",
        root / "src" / "platform" / "as3",
    ]


def iter_as_files(root: Path, version: str) -> list[Path]:
    paths: list[Path] = []
    for source in source_roots(root, version):
        if source.exists():
            found = sorted(source.rglob("*.as"))
            if RAW:
                found = [p for p in found if p.relative_to(source).parts[0] != "bh"]
            paths.extend(found)
    return paths


def split_code(text: str) -> list[tuple[bool, str]]:
    spans: list[tuple[bool, str]] = []
    start = 0
    i = 0
    n = len(text)
    in_string: str | None = None
    in_line_comment = False
    in_block_comment = False
    code_start = 0

    def emit_code(end: int) -> None:
        nonlocal code_start
        if end > code_start:
            spans.append((True, text[code_start:end]))

    def emit_noncode(end: int) -> None:
        nonlocal start, code_start
        if end > start:
            spans.append((False, text[start:end]))
        code_start = end

    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_string:
            if ch == "\\" and i + 1 < n:
                i += 2
                continue
            if ch == in_string:
                in_string = None
                i += 1
                emit_noncode(i)
                continue
            i += 1
            continue
        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
                i += 1
                emit_noncode(i)
                continue
            i += 1
            continue
        if in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 2
                emit_noncode(i)
                continue
            i += 1
            continue
        if ch in ("'", '"'):
            emit_code(i)
            start = i
            in_string = ch
            i += 1
            continue
        if ch == "/" and nxt == "/":
            emit_code(i)
            start = i
            in_line_comment = True
            i += 2
            continue
        if ch == "/" and nxt == "*":
            emit_code(i)
            start = i
            in_block_comment = True
            i += 2
            continue
        if ch == "/" and is_regex_start(text, i):
            emit_code(i)
            start = i
            i = skip_regex_literal(text, i)
            emit_noncode(i)
            continue
        i += 1
    if in_string or in_line_comment or in_block_comment:
        emit_noncode(n)
    else:
        emit_code(n)
    return [(is_code, span) for is_code, span in spans if span]


def is_regex_start(text: str, index: int) -> bool:
    j = index - 1
    while j >= 0 and text[j].isspace():
        j -= 1
    return j < 0 or text[j] in "=(:,?;[{!&|"


def skip_regex_literal(text: str, index: int) -> int:
    i = index + 1
    in_class = False
    while i < len(text):
        ch = text[i]
        if ch == "\\" and i + 1 < len(text):
            i += 2
            continue
        if ch == "[":
            in_class = True
            i += 1
            continue
        if ch == "]":
            in_class = False
            i += 1
            continue
        if ch == "/" and not in_class:
            i += 1
            while i < len(text) and text[i].isalpha():
                i += 1
            return i
        if ch == "\n":
            return i
        i += 1
    return i


def transform_code(text: str, fn) -> str:
    return "".join(fn(span) if is_code else span for is_code, span in split_code(text))


def protect_noncode(text: str, prefix: str = "__AS3_NONCODE_") -> tuple[str, list[str]]:
    protected: list[str] = []
    parts: list[str] = []
    for is_code, span in split_code(text):
        if is_code:
            parts.append(span)
        else:
            marker = f"{prefix}{len(protected)}__"
            protected.append(span)
            parts.append(marker)
    return "".join(parts), protected


def restore_noncode(text: str, protected: list[str], prefix: str = "__AS3_NONCODE_") -> str:
    for index, span in enumerate(protected):
        text = text.replace(f"{prefix}{index}__", span)
    return text


def unwrap_package(text: str) -> tuple[str, str]:
    match = PACKAGE_RE.match(text)
    if not match:
        return "", text
    open_index = text.find("{", match.start())
    close_index = find_outer_close(text, open_index)
    if close_index < 0:
        return match.group(1) or "", text[match.end():]
    package_name = match.group(1) or ""
    inner = text[open_index + 1:close_index]
    tail = text[close_index + 1:]
    tail_imports = re.findall(r"^\s*import\s+[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*(?:\.\*)?\s*;\s*$", tail, flags=re.MULTILINE)
    tail = re.sub(r"^\s*import\s+[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*(?:\.\*)?\s*;\s*$", "", tail, flags=re.MULTILINE)
    pieces = [*tail_imports, inner.strip("\n"), tail.strip("\n")]
    return package_name, "\n".join(piece for piece in pieces if piece).strip("\n") + "\n"


def find_outer_close(text: str, open_index: int) -> int:
    depth = 0
    in_string: str | None = None
    in_line_comment = False
    in_block_comment = False
    i = open_index
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if in_string:
            if ch == "\\" and i + 1 < len(text):
                i += 2
                continue
            if ch == in_string:
                in_string = None
            i += 1
            continue
        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
            i += 1
            continue
        if in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 2
                continue
            i += 1
            continue
        if ch in ("'", '"'):
            in_string = ch
            i += 1
            continue
        if ch == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue
        if ch == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue
        if ch == "/":
            k = i - 1
            while k >= 0 and text[k] in " \t\r\n":
                k -= 1
            if k < 0 or text[k] in "(,=:[!&|?{};+-*%<>~^" or text[max(0, k - 5):k + 1] == "return":
                end = regex_literal_end(text, i)
                if end > i:
                    i = end
                    continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def regex_literal_end(text: str, start: int) -> int:
    i = start + 1
    in_class = False
    while i < len(text) and text[i] != "\n":
        ch = text[i]
        if ch == "\\":
            i += 2
            continue
        if ch == "[":
            in_class = True
        elif ch == "]":
            in_class = False
        elif ch == "/" and not in_class:
            i += 1
            while i < len(text) and text[i].isalpha():
                i += 1
            return i
        i += 1
    return -1


def haxe_type(match: re.Match[str]) -> str:
    return TYPE_MAP[match.group(0)]


AUDITED_PSEUDO_TYPED_VECTOR_LOCALS = {
    ("class_637", "method_6511", "_loc3_", "Vector.<String>"),
}

AUDITED_PSEUDO_TYPED_REFERENCE_LOCALS: dict[tuple[str, str], tuple[tuple[str, str], ...]] = {
    ("CompanionType", "method_8827"): (("_loc6_", "Xml"),),
    ("LevelType", "method_8827"): (("_loc3_", "Xml"),),
    ("ScoringType", "method_8827"): (("_loc6_", "Xml"),),
    ("StoreEventType", "method_8827"): (("_loc6_", "Xml"),),
    ("class_116", "method_8827"): (("_loc3_", "Xml"),),
    ("class_118", "method_8827"): (("_loc6_", "Xml"),),
    ("class_119", "method_8827"): (("_loc6_", "Xml"),),
    ("class_12", "method_8827"): (("_loc3_", "Xml"),),
    ("class_120", "method_7242"): (("_loc3_", "class_95"),),
    ("class_266", "method_684"): (("_loc8_", "GfxType"),),
    ("CTFState", "method_4418"): (("_loc2_", "class_123"),),
    ("CTFState", "method_8808"): (("_loc2_", "class_123"), ("_loc3_", "class_123"),),
    ("EntitlementType", "method_7995"): (("_loc2_", "class_574"), ("_loc7_", "HeroType"), ("_loc10_", "class_725"),),
    ("GameCore", "method_390"): (("_loc10_", "class_5"),),
    ("GameCore", "method_5765"): (("_loc4_", "ByteArray"),),
    ("GameCore", "method_6021"): (("_loc3_", "class_87"), ("_loc4_", "class_314"),),
    ("GameCore", "method_7922"): (("_loc12_", "class_634"),),
    ("LinkUpdater", "method_2602"): (("_loc13_", "class_123"), ("_loc14_", "class_295"),),
    ("LinkUpdater", "method_289"): (("_loc12_", "class_123"), ("_loc13_", "class_368"),),
    ("LinkUpdater", "method_2976"): (("_loc13_", "class_123"), ("_loc14_", "class_295"),),
    ("LinkUpdater", "method_4130"): (("_loc15_", "class_107"),),
    ("LinkUpdater", "method_4221"): (("_loc6_", "class_189"), ("_loc7_", "class_189"),),
    ("LinkUpdater", "method_4479"): (("_loc7_", "HeroType"),),
    ("LinkUpdater", "method_6328"): (("_loc13_", "class_123"), ("_loc14_", "class_295"),),
    ("ScreenBase", "method_1280"): (("_loc13_", "class_669"),),
    ("ScreenBase", "method_1792"): (("_loc5_", "class_87"), ("_loc7_", "class_314"), ("_loc8_", "class_230"),),
    ("ScreenBase", "method_900"): (("_loc2_", "PaperDoll"),),
    ("ScreenMatchPreviewRanked1v1", "method_3237"): (("_loc8_", "class_564"),),
    ("ScreenPopUpLegal", "method_3913"): (("_loc5_", "TextFormat"),),
    ("StoreType", "method_6727"): (("_loc6_", "class_95"),),
    ("class_104", "method_2344"): (("_loc15_", "CostumeType"), ("_loc16_", "class_76"),),
    ("class_104", "method_3772"): (("_loc8_", "CostumeType"),),
    ("class_104", "method_5629"): (("_loc11_", "CostumeType"), ("_loc12_", "HeroType"), ("_loc18_", "CostumeType"),),
    ("class_104", "method_7007"): (("_loc11_", "HeroType"),),
    ("class_114", "method_7698"): (("_loc12_", "class_650"), ("_loc14_", "class_574"), ("_loc15_", "class_629"),),
    ("class_123", "method_736"): (("_loc5_", "PowerType"),),
    ("class_169", "method_6047"): (("_loc8_", "class_725"),),
    ("class_182", "method_677"): (("_loc8_", "class_182"),),
    ("class_235", "method_4275"): (("_loc7_", "PowerType"),),
    ("class_25", "method_6308"): (("_loc1_", "class_629"),),
    ("class_266", "method_8605"): (("_loc7_", "class_650"),),
    ("class_268", "method_1321"): (("_loc5_", "class_16"),),
    ("class_278", "method_8450"): (("_loc10_", "class_123"), ("_loc11_", "class_123"),),
    ("class_295", "method_5584"): (("_loc7_", "class_224"),),
    ("class_304", "method_4446"): (("_loc2_", "GfxType"), ("_loc5_", "GfxType"),),
    ("class_310", "method_3817"): (("_loc4_", "class_87"),),
    ("class_313", "method_4603"): (("_loc4_", "class_123"),),
    ("class_317", "method_49"): (("_loc5_", "class_37"),),
    ("class_320", "method_3543"): (("_loc3_", "class_294"),),
    ("class_328", "method_6308"): (("_loc1_", "class_629"),),
    ("class_344", "method_8301"): (("_loc6_", "class_123"),),
    ("class_345", "method_2896"): (("_loc5_", "Hazard"), ("_loc6_", "LevelSound"), ("_loc7_", "class_246"),),
    ("class_349", "method_4185"): (("_loc9_", "class_123"),),
    ("class_349", "method_448"): (("_loc5_", "class_123"), ("_loc6_", "class_123"), ("_loc9_", "Volume"),),
    ("class_363", "method_865"): (("_loc7_", "Point"),),
    ("class_367", "method_685"): (("_loc6_", "Matrix"), ("_loc7_", "ColorTransform"),),
    ("class_382", "method_7607"): (("_loc7_", "CostumeType"), ("_loc9_", "class_302"),),
    ("class_39", "method_7901"): (("_loc17_", "PowerType"),),
    ("class_402", "method_4508"): (("_loc4_", "class_403"),),
    ("class_404", "UpdateHighlighter"): (("_loc1_", "DisplayObject"),),
    ("class_405", "method_2827"): (("_loc9_", "StoreType"),),
    ("class_409", "UpdateHighlighter"): (("_loc1_", "MovieClip"),),
    ("class_40", "method_1360"): (("_loc5_", "PowerType"), ("_loc6_", "PowerType"),),
    ("class_40", "method_7574"): (("_loc10_", "SpawnBot"),),
    ("class_410", "OnDestroyScreen"): (("_loc3_", "class_668"),),
    ("class_410", "method_224"): (("_loc2_", "class_314"),),
    ("class_410", "method_6178"): (("_loc2_", "class_314"), ("_loc3_", "class_87"),),
    ("class_410", "method_7585"): (("_loc5_", "class_314"),),
    ("class_411", "OnDestroyScreen"): (("_loc3_", "class_668"),),
    ("class_444", "method_4050"): (("_loc4_", "class_445"),),
    ("class_448", "method_102"): (("_loc12_", "HeroType"), ("_loc13_", "CostumeType"),),
    ("class_451", "method_1178"): (("_loc3_", "class_190"), ("_loc4_", "class_190"),),
    ("class_454", "method_2060"): (("_loc4_", "ItemType"),),
    ("class_462", "method_501"): (("_loc3_", "StoreType"), ("_loc8_", "EntitlementType"),),
    ("class_480", "method_8839"): (("_loc4_", "EntitlementType"),),
    ("class_51", "method_3645"): (("_loc13_", "SpawnBot"),),
    ("class_525", "method_6844"): (("_loc6_", "class_368"),),
    ("class_526", "method_2913"): (("_loc5_", "CostumeType"),),
    ("class_526", "method_5381"): (("_loc36_", "CostumeType"),),
    ("class_526", "method_7275"): (("_loc4_", "class_107"),),
    ("class_528", "method_6520"): (("_loc4_", "class_567"),),
    ("class_535", "OnRefreshScreen"): (("_loc8_", "class_536"),),
    ("class_535", "method_4508"): (("_loc4_", "class_536"),),
    ("class_538", "method_1159"): (("_loc3_", "StoreType"),),
    ("class_544", "OnRefreshScreen"): (("_loc5_", "class_109"), ("_loc9_", "HeroType"), ("_loc10_", "CostumeType"), ("_loc13_", "class_76"),),
    ("class_545", "method_819"): (("_loc5_", "class_676"),),
    ("class_590", "method_4018"): (("_loc10_", "CompanionType"), ("_loc13_", "class_120"), ("_loc14_", "class_650"), ("_loc20_", "class_574"), ("_loc21_", "class_629"),),
    ("class_590", "method_8056"): (("_loc10_", "class_574"),),
    ("class_594", "method_4013"): (("_loc6_", "class_316"),),
    ("class_595", "method_1899"): (("_loc5_", "class_120"),),
    ("class_598", "OnRefreshScreen"): (("_loc6_", "class_62"),),
    ("class_5", "method_5925"): (("_loc5_", "GfxType"),),
    ("class_5", "method_6391"): (("_loc2_", "PowerType"),),
    ("class_601", "method_2650"): (("_loc10_", "MovieClip"), ("_loc12_", "CostumeType"),),
    ("class_618", "method_2267"): (("_loc13_", "class_629"),),
    ("class_618", "method_3062"): (("_loc2_", "class_629"),),
    ("class_618", "method_3373"): (("_loc11_", "class_650"),),
    ("class_618", "method_5002"): (("_loc6_", "class_120"),),
    ("class_618", "method_5301"): (("_loc11_", "class_559"),),
    ("class_618", "method_5566"): (("_loc12_", "class_302"),),
    ("class_618", "method_7628"): (("_loc11_", "class_120"),),
    ("class_618", "method_778"): (("_loc11_", "class_297"),),
    ("class_618", "method_8980"): (("_loc7_", "class_629"),),
    ("class_622", "UpdateHighlighter"): (("_loc2_", "MovieClip"),),
    ("class_626", "ShowAndHideAsymBones3D"): (("_loc26_", "class_36"),),
    ("class_627", "method_5518"): (("_loc5_", "Sprite"),),
    ("class_628", "method_7010"): (("_loc20_", "Point"), ("_loc21_", "Point"),),
    ("class_660", "method_7317"): (("_loc5_", "class_424"),),
    ("class_660", "method_8081"): (("_loc5_", "class_424"),),
    ("class_666", "method_2811"): (("_loc6_", "class_725"),),
    ("class_666", "method_408"): (("_loc2_", "class_725"),),
    ("class_670", "method_4011"): (("_loc2_", "DragEvent"),),
    ("class_670", "method_6938"): (("_loc3_", "DragEvent"),),
    ("class_672", "UpdateHighlighter"): (("_loc2_", "MovieClip"),),
    ("class_687", "method_1024"): (("_loc3_", "class_95"), ("_loc6_", "class_92"),),
    ("class_707", "method_2565"): (("_loc2_", "MovieClip"),),
    ("class_719", "method_1730"): (("_loc5_", "class_302"),),
    ("class_719", "method_6840"): (("_loc2_", "StoreType"), ("_loc3_", "EntitlementType"),),
    ("class_719", "method_7099"): (("_loc5_", "class_57"),),
    ("class_719", "method_7353"): (("_loc4_", "class_192"),),
    ("class_719", "method_8017"): (("_loc4_", "StoreType"), ("_loc5_", "class_56"),),
    ("class_719", "method_851"): (("_loc4_", "class_57"),),
    ("class_726", "method_4771"): (("_loc6_", "class_123"),),
    ("class_726", "method_6268"): (("_loc3_", "class_123"),),
    ("class_726", "method_6277"): (("_loc5_", "class_123"),),
    ("class_73", "method_7818"): (("_loc6_", "class_72"),),
    ("class_76", "method_6314"): (("_loc9_", "class_76"),),
    ("class_81", "method_2253"): (("_loc10_", "class_629"), ("_loc12_", "class_629"),),
    ("class_81", "method_5849"): (("_loc4_", "ItemType"),),
    ("class_83", "method_6208"): (("_loc2_", "SpawnBot"),),
    ("class_85", "method_4191"): (("_loc3_", "class_95"),),
    ("class_121", "method_7242"): (("_loc6_", "class_95"),),
    ("class_163", "method_8827"): (("_loc3_", "Xml"),),
    ("class_16", "method_7242"): (("_loc3_", "class_95"),),
    ("class_181", "method_8827"): (("_loc3_", "Xml"),),
    ("class_182", "method_8827"): (("_loc3_", "Xml"),),
    ("class_186", "method_8827"): (("_loc6_", "Xml"),),
    ("class_210", "method_7242"): (("_loc6_", "class_95"),),
    ("class_245", "method_1926"): (("_loc8_", "Volume"),),
    ("class_245", "method_4562"): (("_loc7_", "Volume"),),
    ("class_228", "method_8827"): (("_loc6_", "Xml"),),
    ("class_234", "method_8827"): (("_loc3_", "Xml"),),
    ("class_243", "method_8827"): (("_loc6_", "Xml"),),
    ("class_248", "method_8827"): (("_loc6_", "Xml"),),
    ("class_27", "method_8827"): (("_loc6_", "Xml"),),
    ("class_279", "method_7242"): (("_loc3_", "class_95"),),
    ("class_306", "method_8827"): (("_loc6_", "Xml"),),
    ("class_356", "method_8827"): (("_loc3_", "Xml"),),
    ("class_38", "method_8827"): (("_loc3_", "Xml"),),
    ("class_564", "method_8827"): (("_loc3_", "Xml"),),
    ("class_567", "method_8827"): (("_loc3_", "Xml"),),
    ("class_568", "method_8827"): (("_loc6_", "Xml"),),
    ("class_574", "method_8827"): (("_loc6_", "Xml"),),
    ("class_581", "method_7242"): (("_loc6_", "class_95"),),
    ("class_585", "method_8827"): (("_loc3_", "Xml"),),
    ("class_629", "method_8827"): (("_loc6_", "Xml"),),
    ("class_639", "method_8827"): (("_loc6_", "Xml"),),
    ("class_640", "method_8827"): (("_loc3_", "Xml"),),
    ("class_650", "method_8827"): (("_loc6_", "Xml"),),
    ("class_717", "method_8827"): (("_loc3_", "Xml"),),
    ("ItemType", "method_7242"): (("_loc6_", "class_95"),),
    ("class_193", "method_47"): (("_loc4_", "Array"),),
    ("class_193", "method_2567"): (("_loc4_", "Array"),),
    ("PowerType", "method_5429"): (("_loc1_", "PowerType"), ("_loc2_", "PowerType")),
    ("class_182", "method_1998"): (("_loc5_", "Vector.<class_182>"),),
    ("class_511", "method_6981"): (("_loc6_", "Point"),),
    ("class_321", "method_237"): (("_loc4_", "class_301"),),
    ("class_310", "method_8008"): (("_loc2_", "class_309"),),
    ("class_104", "method_6585"): (("_loc6_", "class_333"),),
    ("class_683", "Tick"): (("_loc9_", "class_224"),),
    ("ItemType", "method_7970"): (("_loc4_", "CustomArt"),),
    ("class_116", "method_3340"): (("_loc5_", "class_116"),),
    ("class_123", "method_5297"): (("_loc1_", "class_116"),),
    ("class_123", "method_4398"): (("_loc3_", "RollbackEvent"),),
    ("LinkUpdater", "method_2780"): (("_loc2_", "class_365"),),
    ("class_112", "method_5916"): (("_loc6_", "class_223"),),
    ("class_112", "method_2454"): (("_loc6_", "class_223"),),
    ("class_579", "method_1024"): (
        ("_loc3_", "class_95"),
        ("_loc6_", "SpriteData"),
        ("_loc8_", "class_92"),
    ),
    ("class_193", "method_7204"): (
        ("_loc5_", "class_136"),
        ("_loc7_", "Array"),
    ),
    ("class_618", "method_7115"): (("_loc11_", "class_574"),),
    ("class_719", "method_5901"): (("_loc7_", "class_107"),),
    ("class_719", "method_7286"): (("_loc9_", "Vector.<class_107>"),),
    ("VolleyBattleState", "method_7677"): (("_loc2_", "Volume"),),
    ("VolleyBattleState", "method_8433"): (("_loc2_", "Volume"),),
    ("CTFState", "method_1945"): (("_loc2_", "Volume"),),
    ("CTFState", "method_3593"): (("_loc2_", "Volume"),),
    ("class_313", "method_1612"): (("_loc5_", "Volume"),),
    ("class_313", "method_335"): (("_loc4_", "Volume"),),
    ("class_313", "method_3593"): (("_loc5_", "Volume"),),
    ("class_157", "method_4457"): (("_loc9_", "class_245"),),
    ("SubScreenEventTimedEvent", "GetAvailableFocuses"): (("_loc5_", "class_596"),),
    ("class_325", "method_7088"): (
        ("_loc7_", "class_148"),
        ("_loc8_", "class_123"),
    ),
    ("class_344", "method_6903"): (("_loc7_", "Volume"),),
    ("class_146", "method_6509"): (("_loc5_", "class_123"),),
    ("class_344", "method_5727"): (("_loc5_", "class_123"),),
    ("class_394", "Tick"): (("_loc5_", "class_395"),),
    ("class_457", "method_5937"): (("_loc4_", "String"),),
    ("class_418", "method_2099"): (("_loc2_", "String"),),
    ("class_604", "method_5669"): (("_loc4_", "String"),),
    ("class_200", "method_5325"): (("_loc3_", "class_142"),),
    ("class_200", "method_5327"): (("_loc3_", "class_142"),),
    ("class_200", "OnRefreshScreen"): (("_loc3_", "class_142"),),
    ("class_479", "OnTickScreen"): (("_loc9_", "class_480"),),
    ("class_479", "OnClearScreen"): (("_loc5_", "class_480"),),
    ("class_479", "method_4748"): (("_loc2_", "class_480"),),
    ("class_479", "method_4927"): (("_loc2_", "class_480"),),
    ("UdpConnection", "method_4048"): (("_loc5_", "NetPacket"),),
    ("UdpConnection", "method_5534"): (("_loc5_", "NetPacket"),),
    ("UdpConnection", "method_4146"): (("_loc4_", "NetPacket"),),
    ("UdpConnection", "method_514"): (("_loc6_", "NetPacket"),),
    ("class_622", "OnDestroyScreen"): (("_loc3_", "class_138"),),
    ("class_250", "method_1442"): (
        ("_loc13_", "Vector.<class_280>"),
        ("_loc15_", "Xml"),
    ),
    ("class_281", "method_4374"): (("_loc10_", "NavNode"),),
    ("class_579", "GetSwappedBone2D"): (("_loc6_", "Bitmap"),),
    ("class_579", "method_4088"): (
        ("_loc3_", "Bitmap"),
        ("_loc4_", "Bitmap"),
        ("_loc8_", "Vector.<Bitmap>"),
    ),
    ("class_579", "method_5587"): (("_loc4_", "Vector.<Bitmap>"),),
    ("class_579", "method_4716"): (
        ("_loc9_", "CustomArt"),
        ("_loc10_", "String"),
        ("_loc11_", "SpriteData"),
    ),
    ("class_579", "method_2002"): (("_loc5_", "String"),),
    ("class_579", "Reset"): (
        ("_loc3_", "String"),
        ("_loc5_", "SpriteData"),
    ),
    ("UiClip", "method_1864"): (
        ("_loc2_", "String"),
        ("_loc3_", "FrameLabel"),
    ),
    ("UiClip", "method_3716"): (("_loc2_", "DisplayObject"),),
    ("ControllerMappingType", "method_6672"): (
        ("_loc8_", "Array"),
        ("_loc9_", "Array"),
    ),
    ("ControllerMappingType", "method_8682"): (
        ("_loc8_", "Array"),
        ("_loc9_", "Array"),
    ),
    ("ControllerMappingType", "method_5498"): (("_loc5_", "Array"),),
    ("ScreenLevelSelect", "method_3752"): (("_loc4_", "Vector.<class_107>"),),
    ("class_243", "method_4478"): (("_loc5_", "Vector.<class_243>"),),
    ("class_493", "method_7984"): (("_loc7_", "class_107"),),
    ("class_493", "method_1197"): (("_loc2_", "class_107"),),
    ("class_73", "method_5030"): (("_loc4_", "Vector.<class_72>"),),
    ("class_73", "method_6884"): (("_loc4_", "Vector.<class_72>"),),
    ("class_554", "method_8432"): (("_loc3_", "ScreenBase"),),
    ("class_45", "Destroy"): (("_loc2_", "class_46"),),
    ("StoreType", "method_620"): (("_loc3_", "HeroType"),),
    ("class_444", "method_4864"): (("_loc5_", "Vector.<uint>"),),
    ("class_501", "method_6381"): (("_loc1_", "MovieClip"),),
    ("class_510", "method_6381"): (("_loc1_", "MovieClip"),),
    ("class_538", "method_543"): (("_loc1_", "StoreType"),),
    ("class_222", "method_1994"): (("_loc2_", "class_217"),),
    ("class_112", "method_3249"): (("_loc6_", "class_223"),),
    ("class_355", "method_5605"): (("_loc6_", "class_123"),),
    ("class_339", "method_7207"): (("_loc2_", "class_123"),),
    ("class_278", "method_3682"): (("_loc5_", "class_123"),),
    ("class_719", "method_8460"): (("_loc4_", "class_56"),),
    ("class_458", "method_3828"): (("_loc5_", "GlowFilter"),),
    ("class_666", "method_490"): (("_loc3_", "class_526"),),
    ("class_698", "method_1813"): (("_loc3_", "class_525"),),
    ("class_719", "method_2876"): (("_loc2_", "NetPacket"),),
    ("class_415", "method_8430"): (
        ("_loc4_", "MovieClip"),
        ("_loc7_", "String"),
    ),
    ("class_317", "method_4029"): (
        ("_loc2_", "class_172"),
        ("_loc4_", "class_84"),
        ("_loc5_", "class_84"),
    ),
    ("class_375", "HandleInput"): (("_loc3_", "class_376"),),
    ("class_601", "Reset"): (("_loc4_", "MovieClip"),),
    ("GameCore", "method_6207"): (("_loc2_", "class_298"),),
    ("class_44", "method_7010"): (("_loc15_", "class_123"),),
    ("class_199", "method_619"): (("_loc4_", "DisplayObject"),),
    ("class_200", "UpdateHighlighter"): (("_loc1_", "DisplayObject"),),
    ("class_201", "UpdateHighlighter"): (("_loc1_", "DisplayObject"),),
    ("class_687", "method_4088"): (("_loc4_", "Bitmap"),),
    ("class_50", "method_2212"): (("_loc3_", "FrameLabel"),),
    ("class_64", "method_4152"): (("_loc7_", "class_66"),),
    ("LinkUpdater", "method_2593"): (("_loc18_", "class_293"),),
    ("StoreType", "method_7558"): (("_loc3_", "class_588"),),
    ("StoreType", "method_2100"): (
        ("_loc22_", "CostumeType"),
        ("_loc23_", "HeroType"),
        ("_loc27_", "Vector.<uint>"),
    ),
    ("WorldHotkey", "Destroy"): (("_loc4_", "MovieClip"),),
    ("SubScreenEventTimedEvent", "GetDefaultFocus"): (("_loc4_", "class_596"),),
    ("class_281", "method_8787"): (("_loc3_", "NavNode"),),
    ("ScreenBase", "method_8649"): (("_loc3_", "ScreenBase"),),
    ("class_245", "method_2305"): (("_loc3_", "class_246"),),
    ("class_358", "method_8869"): (("_loc3_", "class_19"),),
    ("ClientManager", "method_1939"): (("_loc3_", "class_639"),),
    ("LinkUpdater", "method_5121"): (("_loc3_", "class_576"),),
    ("class_330", "method_8856"): (("_loc8_", "class_21"),),
    ("PaperDoll", "method_7915"): (("_loc5_", "GfxType"),),
    ("class_697", "method_2222"): (("_loc3_", "MovieClip"),),
    ("class_388", "method_8145"): (("_loc3_", "MovieClip"),),
    ("class_423", "method_8162"): (("_loc3_", "SubScreenStaticEvent"),),
    ("class_345", "method_9057"): (("_loc4_", "Hazard"),),
    ("class_406", "method_2623"): (("_loc3_", "String"),),
    ("class_634", "method_2944"): (
        ("_loc1_", "DisplayObject"),
        ("_loc2_", "Bitmap"),
    ),
    ("class_259", "method_5156"): (
        ("_loc3_", "MovieClip"),
        ("_loc4_", "MovieClip"),
        ("_loc5_", "MovieClip"),
    ),
    ("class_74", "method_5356"): (("_loc9_", "DisplayObject"),),
    ("CostumeType", "method_7242"): (
        ("_loc3_", "Vector.<CostumeType>"),
        ("_loc4_", "CostumeType"),
        ("_loc6_", "class_95"),
        ("_loc9_", "CostumeType"),
        ("_loc10_", "CostumeType"),
    ),
}


MINED_PSEUDO_TYPED_REFERENCE_LOCALS = True
MINED_PSEUDO_TYPED_SKIPS: set[tuple[str, str, str]] = {
    ("GameCore", "method_7719", "_loc13_"),
    ("GameCore", "method_7719", "_loc14_"),
    ("class_180", "method_7635", "_loc7_"),
    ("class_638", "method_8827", "_loc5_"),
    ("class_725", "method_8668", "_loc19_"),
    ("class_725", "method_8668", "_loc21_"),
    ("CostumeType", "method_5047", "_loc19_"),
    ("CostumeType", "method_5047", "_loc21_"),
    ("class_104", "method_4034", "_loc9_"),
    ("class_529", "OnInitDisplay", "_loc4_"),
    ("class_529", "OnInitDisplay", "_loc5_"),
    ("class_512", "method_4679", "_loc14_"),
    ("class_512", "method_4679", "_loc15_"),
    ("class_389", "method_8799", "_loc8_"),
    ("class_74", "method_8965", "_loc15_"),
    ("class_668", "class_668", "_loc8_"),
}


MINED_QUALIFIED_REFERENCE_LOCALS = True


def mined_reference_matches(mined: str | None, declared: str) -> bool:
    if not mined:
        return False
    return mined == declared or (MINED_QUALIFIED_REFERENCE_LOCALS and "." in mined
                                 and "." not in declared and mined.rsplit(".", 1)[1] == declared)


def promote_mined_pseudo_typed_reference_locals(span: str) -> str:
    references = (load_element_types() or {}).get("references") or {}
    if not MINED_PSEUDO_TYPED_REFERENCE_LOCALS or not references:
        return span
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    out: list[str] = []
    i = 0
    for match in re.finditer(r"\bfunction\s+([A-Za-z_]\w*)\s*\(", span):
        if match.start() < i:
            continue
        close_paren = find_matching_right(span, span.find("(", match.start()))
        body_open = span.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(span, body_open) if body_open >= 0 else -1
        if body_close < 0 or ";" in span[close_paren:body_open]:
            continue
        registers = references.get(f"{class_name}/{match.group(1)}") or {}
        body = span[body_open:body_close]
        if registers:
            promoted: dict[str, str] = {}

            def promote(m: re.Match[str]) -> str:
                if (mined_reference_matches(registers.get(m.group(1)), m.group(2))
                        and (class_name or "", match.group(1), f"_loc{m.group(1)}_") not in MINED_PSEUDO_TYPED_SKIPS):
                    if m.group(2) == "Object":
                        if object_member_use(body, f"_loc{m.group(1)}_"):
                            return m.group(0)
                        return f"var _loc{m.group(1)}_:{AS3_HELPER}.As3Object = null;"
                    promoted[f"_loc{m.group(1)}_"] = m.group(2)
                    return f"var _loc{m.group(1)}_:{m.group(2)} = null;"
                return m.group(0)

            body = re.sub(r"\bvar\s+_loc(\d+)_\s*:\s*\*\s*=\s*null\s+as\s+([A-Za-z_]\w*|Vector\.<[A-Za-z_]\w*>)\s*;",
                          promote, body)
            body = re.sub(
                rf"\bvar\s+_loc(\d+)_\s*:\s*Object{re.escape(HOISTED_MARK)};",
                lambda m: f"var _loc{m.group(1)}_:{AS3_HELPER}.As3Object{HOISTED_MARK};"
                if registers.get(m.group(1)) == "Object" and not object_member_use(body, f"_loc{m.group(1)}_")
                and (class_name or "", match.group(1), f"_loc{m.group(1)}_") not in MINED_PSEUDO_TYPED_SKIPS
                else m.group(0),
                body)
            body = cast_promoted_local_downcasts(body, promoted)
        out.append(span[i:body_open] + body)
        i = body_close
    out.append(span[i:])
    return "".join(out)


def object_member_use(body: str, local: str) -> bool:
    return re.search(rf"(?<![\w.]){re.escape(local)}\s*[.\[]", body) is not None


def cast_promoted_local_downcasts(body: str, promoted: dict[str, str]) -> str:
    if not promoted:
        return body
    declared = dict(re.findall(r"\bvar\s+(_loc\d+_)\s*:\s*([\w.]+)", body))

    def store(m: re.Match[str]) -> str:
        target, value = promoted[m.group(2)], m.group(3)
        source = declared.get(value)
        tested = re.search(rf"(?<![\w.]){re.escape(value)}\s+is\s+{re.escape(target)}\b", body)
        if (source and source not in ("Dynamic", "*", target)) or tested:
            return f"{m.group(1)}{m.group(2)} = cast {value};"
        return m.group(0)

    names = "|".join(re.escape(name) for name in promoted)
    return re.sub(rf"(^[ \t]*)({names})\s*=\s*(_loc\d+_(?:\.[A-Za-z_]\w*)*)\s*;", store, body, flags=re.M)


def restore_audited_pseudo_typed_reference_locals(span: str) -> str:
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return "".join(out)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        body_open = span.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(span, body_open) if body_open >= 0 else -1
        if body_close < 0:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        body = span[body_open + 1:body_close]
        for local, type_name in AUDITED_PSEUDO_TYPED_REFERENCE_LOCALS.get(
            (class_name or "", match.group(1)), ()
        ):
            body = body.replace(
                f"var {local}:* = null as {type_name};",
                f"var {local}:{type_name} = null;",
            )
        out.append(span[i:body_open + 1])
        out.append(body)
        out.append("}")
        i = body_close + 1


def restore_audited_native_date_construction(span: str) -> str:
    class_match = CLASS_RE.search(span)
    if not class_match or class_match.group(1) != "class_641":
        return span
    signature = re.search(r"\bfunction\s+method_6948\s*\([^)]*\)\s*:\s*UInt\s*\{", span)
    if not signature:
        return span
    body_open = span.find("{", signature.start())
    body_close = find_matching_right(span, body_open)
    if body_close < 0:
        return span
    body = span[body_open + 1:body_close]
    expected = "var _loc2_:Dynamic = new Date();"
    if body.count(expected) != 1 or body.count("new Date()") != 1:
        return span
    body = body.replace(expected, "var _loc2_:Dynamic = port.runtime.As3.newDate();")
    return span[:body_open + 1] + body + span[body_close:]


def restore_audited_bombsketball_relational_branch(span: str) -> str:
    class_match = CLASS_RE.search(span)
    if not class_match or class_match.group(1) != "BombsketballState":
        return span
    signature = re.search(r"\bfunction\s+method_7010\s*\([^)]*\)\s*:\s*Class(?:<Dynamic>)?\s*\{", span)
    if not signature:
        return span
    body_open = span.find("{", signature.start())
    body_close = find_matching_right(span, body_open)
    if body_close < 0:
        return span
    body = span[body_open + 1:body_close]
    expression = "_loc24_.var_10228.method_113(_loc24_.var_13590)"
    original = f"if({expression} <= 2800)"
    replacement = f"if(!({expression} > 2800))"
    if body.count(original) != 1 or body.count(expression) != 1:
        return span
    body = body.replace(original, replacement)
    return span[:body_open + 1] + body + span[body_close:]


AUDITED_RELATIONAL_BRANCH_REWRITES: dict[
    tuple[str, str], tuple[tuple[str, str, int], ...]
] = {
    ("class_235", "method_7552"): ((
        "if(var_4583[_loc2_] <= param1)",
        "if(!(var_4583[_loc2_] > param1))",
        1,
    ),),
    ("class_189", "method_5563"): ((
        "if(param1 < class_189.var_2469[_loc4_])",
        "if(!(param1 >= class_189.var_2469[_loc4_]))",
        1,
    ),),
    ("class_81", "method_3163"): ((
        "if(_loc3_.method_6881(var_13518,_loc4_.var_14247.var_3888) <= 12100)",
        "if(!(_loc3_.method_6881(var_13518,_loc4_.var_14247.var_3888) > 12100))",
        1,
    ),),
    ("class_5", "method_4521"): ((
        "if(_loc6_.method_6881(var_13518) <= 22500)",
        "if(!(_loc6_.method_6881(var_13518) > 22500))",
        1,
    ),),
    ("class_651", "method_7010"): ((
        "if(_loc4_.var_10228.method_113(_loc4_.var_13590) <= 50 + var_790.var_11702.var_14639)",
        "if(!(_loc4_.var_10228.method_113(_loc4_.var_13590) > 50 + var_790.var_11702.var_14639))",
        1,
    ),),
    ("MovingPlatform", "method_641"): ((
        "if(_loc8_ >= param1.var_1211)",
        "if(!(_loc8_ < param1.var_1211))",
        1,
    ),),
    ("class_41", "method_7010"): ((
        "if(_loc13_.var_10228.method_113(_loc13_.var_13590) <= var_790.var_11702.var_14639 + 300)",
        "if(!(_loc13_.var_10228.method_113(_loc13_.var_13590) > var_790.var_11702.var_14639 + 300))",
        1,
    ),),
    ("class_555", "method_8269"): ((
        "if(class_555.var_12013[param1] < 0)",
        "if(!(class_555.var_12013[param1] >= 0))",
        1,
    ),),
    ("Companion", "method_7770"): ((
        "if(_loc6_ <= Math.abs(_loc7_))",
        "if(!(_loc6_ > Math.abs(_loc7_)))",
        1,
    ),),
    ("class_71", "method_833"): ((
        "if(_loc8_.var_10228.method_113(_loc8_.var_4461) < 0)",
        "if(!(_loc8_.var_10228.method_113(_loc8_.var_4461) >= 0))",
        2,
    ),),
}


AUDITED_NATIVE_ERROR_MESSAGE_REWRITES: dict[
    tuple[str, str], tuple[tuple[str, str, int], ...]
] = {
    ("GameCore", "method_2673"): ((
        "_loc2_ = param1.message;",
        "_loc2_ = (cast param1:flash.errors.Error).message;",
        1,
    ),),
}


def restore_audited_relational_branches(span: str) -> str:
    return apply_audited_method_rewrites(span, AUDITED_RELATIONAL_BRANCH_REWRITES)


def restore_audited_native_error_messages(span: str) -> str:
    return apply_audited_method_rewrites(span, AUDITED_NATIVE_ERROR_MESSAGE_REWRITES)


def apply_audited_method_rewrites(
        span: str, table: dict[tuple[str, str], tuple[tuple[str, str, int], ...]]) -> str:
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return "".join(out)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        body_open = span.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(span, body_open) if body_open >= 0 else -1
        if body_close < 0:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        body = span[body_open + 1:body_close]
        for needle, replacement, expected in table.get(
                (class_name or "", match.group(1)), ()):
            needle = audited_needle(body, needle, expected)
            if replacement.startswith(needle) and body.count(replacement) == expected:
                continue
            if body.count(needle) == expected:
                body = body.replace(needle, replacement)
        out.append(span[i:body_open + 1])
        out.append(body)
        out.append("}")
        i = body_close + 1


def audited_needle(body: str, needle: str, expected: int) -> str:
    if body.count(needle) == expected:
        return needle
    respelled = needle.replace("Std.string(", f"{STRING_ARG_CALL}(")
    if respelled != needle and body.count(respelled) == expected:
        return respelled
    dropped = drop_string_literal_wrappers(needle)
    if dropped != needle and body.count(dropped) != expected:
        respelled = dropped.replace("Std.string(", f"{STRING_ARG_CALL}(")
        if body.count(respelled) == expected:
            return respelled
    return dropped


def drop_string_literal_wrappers(text: str) -> str:
    out: list[str] = []
    i = 0
    while (start := text.find("Std.string(", i)) >= 0:
        open_index = start + len("Std.string")
        close_index = find_matching_right(text, open_index)
        if close_index < 0:
            break
        inner = text[open_index + 1:close_index]
        literal = re.fullmatch(r"\s*(?:\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*')\s*", inner)
        out.append(text[i:start])
        if literal or is_string_led_concatenation(inner):
            out.append(drop_string_literal_wrappers(inner))
        else:
            out.append(text[start:open_index + 1] + drop_string_literal_wrappers(inner) + ")")
        i = close_index + 1
    out.append(text[i:])
    return "".join(out)


def remove_audited_unused_number_local(span: str) -> str:
    class_match = CLASS_RE.search(span)
    if not class_match or class_match.group(1) != "class_389":
        return span
    signature = re.search(r"\bfunction\s+method_8359\s*\([^)]*\)\s*:\s*void\s*\{", span)
    if not signature:
        return span
    body_open = span.find("{", signature.start())
    body_close = find_matching_right(span, body_open)
    if body_close < 0:
        return span
    body = span[body_open + 1:body_close]
    declaration = "var _loc3_:Number = NaN;"
    if body.count(declaration) != 1 or body.count("_loc3_") != 1:
        return span
    body = body.replace(declaration, "")
    return span[:body_open + 1] + body + span[body_close:]


RESTORE_CATCH_VARIABLES = True
_CATCH_STORE_RE = re.compile(
    r"catch\((?P<e>_loc_e_\d*):(?P<type>[\w.]+)\)(?P<ws>\s*\{[ \t]*\n)[ \t]*(?P<loc>_loc\d+_) = (?P=e);[ \t]*\n")


def restore_catch_variables(text: str) -> str:
    if not RESTORE_CATCH_VARIABLES:
        return text
    out = text
    starts = [m.start() for m in re.finditer(r"\bfunction ", out)]
    for start, end in reversed(list(zip(starts, starts[1:] + [len(out)]))):
        span = out[start:end]
        done: set[str] = set()
        while True:
            span, bound = _bind_catch_copies(span, done)
            if bound is None:
                break
            done.add(bound)
        out = out[:start] + span + out[end:]
    return out


def _bind_catch_copies(span: str, done: set[str]) -> tuple[str, str | None]:
    groups: dict[str, list[re.Match[str]]] = {}
    for match in _CATCH_STORE_RE.finditer(span):
        groups.setdefault(match.group("loc"), []).append(match)
    for loc, matches in sorted(groups.items(), key=lambda item: -item[1][0].start()):
        if loc in done:
            continue
        kinds = {match.group("type") for match in matches}
        if len(kinds) != 1:
            continue
        kind = kinds.pop()
        regions = []
        for match in matches:
            open_brace = span.find("{", match.end("type"))
            close_brace = find_matching_right(span, open_brace)
            if close_brace < 0 or re.search(rf"\b{match.group('e')}\b", span[match.end():close_brace]):
                regions = []
                break
            regions.append((match.start(), close_brace))
        if not regions:
            continue
        decl = re.compile(rf"(?m)^[ \t]*var {loc}:\* = null as {re.escape(kind)};[ \t]*\n")
        decls = list(decl.finditer(span, 0, matches[0].start()))
        outside = "".join(span[a:b] for a, b in zip([0] + [r[1] for r in regions],
                                                    [r[0] for r in regions] + [len(span)]))
        if len(decls) != 1 or len(re.findall(rf"\b{loc}\b", outside)) != 1:
            continue
        for match in reversed(matches):
            span = span[:match.start()] + f"catch({loc}:{kind}){match.group('ws')}" + span[match.end():]
        span = span[:decls[0].start()] + span[decls[0].end():]
        return span, loc
    return span, None


_CATCH_HEAD_RE = re.compile(r"catch\((?P<e>_loc_e_\d*):(?P<type>[\w.*]+)\)")


def restore_unused_catch_variables(text: str) -> str:
    if not RESTORE_CATCH_VARIABLES:
        return text
    out = text
    starts = [m.start() for m in re.finditer(r"\bfunction\s+[A-Za-z_]\w*\s*\(", out)]
    for start, end in reversed(list(zip(starts, starts[1:] + [len(out)]))):
        span = out[start:end]
        heads = []
        for match in _CATCH_HEAD_RE.finditer(span):
            open_brace = span.find("{", match.end())
            close_brace = find_matching_right(span, open_brace) if open_brace >= 0 else -1
            if close_brace < 0 or span[match.end():open_brace].strip():
                heads = []
                break
            if not re.search(rf"\b{match.group('e')}\b", span[open_brace:close_brace]):
                heads.append(match)
        if len(heads) != 1 or len(_CATCH_HEAD_RE.findall(span)) != 1:
            continue
        head = heads[0]
        kind = head.group("type")
        value = r"null" if kind == "*" else rf"null as {re.escape(kind)}"
        decls = [d for d in re.finditer(rf"(?m)^[ \t]*var (?P<loc>_loc\d+_):\* = {value};[ \t]*\n", span)
                 if len(re.findall(rf"\b{d.group('loc')}\b", span)) == 1]
        if len(decls) != 1 or decls[0].start() > head.start():
            continue
        decl = decls[0]
        span = (span[:decl.start()] + span[decl.end():head.start()]
                + f"catch({decl.group('loc')}:{kind})" + span[head.end():])
        out = out[:start] + span + out[end:]
    return out


RESTORE_STATIC_INCREMENTS = True
STATIC_TEMP_DECL_RE = re.compile(r"(?m)^[ \t]*var (?P<tmp>_temp_\d+):\* = (?P<cls>class_\d+|[A-Z]\w*);[ \t]*\n")


def restore_static_increments(text: str) -> str:
    if not RESTORE_STATIC_INCREMENTS:
        return text
    def inline(match: re.Match[str]) -> str:
        return f"({'++' if match.group('op') == '+' else '--'}{match.group('cls')}.{match.group('f')})"

    out = text
    for tmp in sorted(set(re.findall(r"\((_temp_\d+) = (?:class_\d+|[A-Z]\w*),", text))):
        t = re.escape(tmp)
        out = re.sub(
            rf"\({t} = (?P<cls>class_\d+|[A-Z]\w*),\s*{t}\.(?P<f>\w+) = u?int\({t}\.(?P=f) (?P<op>[+-]) 1\)\)",
            inline, out)
        for decl in reversed(list(re.finditer(rf"(?m)^[ \t]*var {t}:\*;[ \t]*\n", out))):
            end = out.find("function ", decl.end())
            end = len(out) if end < 0 else end
            if not re.search(rf"\b{t}\b", out[decl.end():end]):
                out = out[:decl.start()] + out[decl.end():]
    for decl in reversed(list(STATIC_TEMP_DECL_RE.finditer(out))):
        tmp, cls = decl.group("tmp"), decl.group("cls")
        start = out.rfind("function ", 0, decl.start())
        end = out.find("function ", decl.end())
        end = len(out) if end < 0 else end
        if start < 0:
            continue
        scope = out[start:end]
        t = re.escape(tmp)

        def prefix(match: re.Match[str]) -> str:
            before = match.string[:match.start()].rstrip()
            if not before or before[-1] not in "=(,[":
                return match.group(0)
            return f"{'++' if match.group('op') == '+' else '--'}{cls}.{match.group('f')}"

        scope = re.sub(rf"\b{t}\.(?P<f>\w+) = u?int\({t}\.(?P=f) (?P<op>[+-]) 1\)", prefix, scope)
        post_re = re.compile(
            rf"(?m)^(?P<indent>[ \t]*){t}\.(?P<f>\w+) = \((?P<loc>_loc\d+_) = u?int\({t}\.(?P=f)\)\) \+ 1;[ \t]*\n"
            rf"[ \t]*(?P<lhs>[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*) = (?P=loc);")
        for match in list(post_re.finditer(scope)):
            loc = match.group("loc")
            rest = scope.replace(match.group(0), "", 1)
            uses = re.findall(rf"\b{loc}\b", rest)
            decls = re.findall(rf"(?m)^[ \t]*var {loc}:\w+;[ \t]*\n", rest)
            if match.group("lhs") == loc or len(uses) != len(decls):
                continue
            replacement = f"{match.group('indent')}{match.group('lhs')} = {cls}.{match.group('f')}++;"
            scope = scope.replace(match.group(0), replacement, 1)
            for item in decls:
                scope = scope.replace(item, "", 1)
        body = scope.replace(decl.group(0), "", 1)
        uses = re.findall(rf"\b{t}\b(\.\w+ = (?!=))?", body)
        if uses and all(uses):
            body = re.sub(rf"\b{t}\.(?=\w+ = (?!=))", f"{cls}.", body)
            uses = []
        out = out[:start] + (body if not uses else scope) + out[end:]
    return out


UNWRAP_BOOL_STRING_CONCATS = True


def unwrap_bool_string_concats(text: str) -> str:
    if not UNWRAP_BOOL_STRING_CONCATS:
        return text
    span, protected = protect_noncode(text)
    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return restore_noncode("".join(out), protected)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        body_open = span.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(span, body_open) if body_open >= 0 else -1
        if body_close < 0 or ";" in span[close_paren:body_open]:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        out.append(span[i:body_open + 1])
        body = span[body_open + 1:body_close]
        if not re.search(r"\bfunction\b", body):
            bools = (set(re.findall(r"([A-Za-z_$][\w$]*)\s*:\s*Boolean\b", span[paren:close_paren]))
                     | set(re.findall(r"\bvar\s+([A-Za-z_$][\w$]*)\s*:\s*Boolean\b", body)))
            def unwrap(m: re.Match) -> str:
                literal, empty, name = protected[int(m.group(2))], protected[int(m.group(3))], m.group(4)
                if name in bools and literal.startswith('"') and empty == '""':
                    return m.group(1) + name
                return m.group(0)
            body = re.sub(r"(__AS3_NONCODE_(\d+)__\s*\+\s*)\(__AS3_NONCODE_(\d+)__\s*\+\s*([A-Za-z_$][\w$]*)\)",
                          unwrap, body)
        out.append(body)
        i = body_close


INLINE_POSTFIX_INDEX_TEMPS = True
_NAME_CHAIN = r"[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*"
POSTFIX_INDEX_TEMP_RE = re.compile(
    r"(?m)^((?:[ \t]*var _temp_\d+:\*\s*=\s*[^;\n]+;\n)+)"
    r"([ \t]*([A-Za-z_$][\w$]*) = \(([A-Za-z_$][\w$]*) = \3\) [+-] 1;\n)"
    rf"([ \t]*(?:{_NAME_CHAIN}\s*=\s*)?)([^\n]*)")
_PURE_TEMP_VALUE_RE = re.compile(
    rf"^(?:{_NAME_CHAIN}|\"[^\"\\\n]*\"|-?\d+(?:\.\d+)?|true|false|null)$")


def inline_postfix_index_temps(text: str) -> str:
    if not INLINE_POSTFIX_INDEX_TEMPS:
        return text

    def body_pass(body: str) -> str:
        def replace(m: re.Match) -> str:
            decls = re.findall(r"var (_temp_\d+):\*\s*=\s*([^;\n]+);", m.group(1))
            index_local, temp_local, rest = m.group(3), m.group(4), m.group(6)
            for temp, value in decls:
                value = value.strip()
                names = set(re.findall(r"[A-Za-z_$][\w$]*", re.sub(r"\"[^\"]*\"", "", value)))
                if (not _PURE_TEMP_VALUE_RE.match(value) or index_local in names or temp_local in names
                        or "_temp_" in value):
                    return m.group(0)
                if len(re.findall(rf"(?<![\w$]){re.escape(temp)}(?![\w$])", body)) != 2:
                    return m.group(0)
            temps = [temp for temp, _value in decls]
            values = {temp: value.strip() for temp, value in decls}
            if len(temps) == 1 and rest.startswith(f"{temps[0]}[{temp_local}]"):
                return f"{m.group(2)}{m.group(5)}{values[temps[0]]}{rest[len(temps[0]):]}"
            callee = re.match(rf"({_NAME_CHAIN})\(", rest)
            if callee and not callee.group(1).startswith("_temp_"):
                if {index_local, temp_local} & set(callee.group(1).split(".")):
                    return m.group(0)
                head, args = callee.group(0), temps
            else:
                receiver = re.match(rf"({temps[0]})\.[A-Za-z_$][\w$]*\(", rest)
                if not receiver:
                    return m.group(0)
                head, args = values[temps[0]] + receiver.group(0)[len(temps[0]):], temps[1:]
            prefix = callee.group(0) if callee and head == callee.group(0) else receiver.group(0)
            expected = prefix + "".join(f"{temp}," for temp in args) + temp_local
            if not re.match(re.escape(expected) + r"[,)]", rest):
                return m.group(0)
            inlined = head + "".join(f"{values[temp]}," for temp in args) + temp_local
            return f"{m.group(2)}{m.group(5)}{inlined}{rest[len(expected):]}"
        return POSTFIX_INDEX_TEMP_RE.sub(replace, body)

    span, protected = protect_noncode(text)
    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return restore_noncode("".join(out), protected)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        body_open = span.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(span, body_open) if body_open >= 0 else -1
        if body_close < 0 or ";" in span[close_paren:body_open]:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        out.append(span[i:body_open + 1])
        body = span[body_open + 1:body_close]
        if not re.search(r"\bfunction\b", body):
            body = body_pass(body)
        out.append(body)
        i = body_close


INLINE_CALL_SPILL_TEMPS = True
CALL_SPILL_TEMP_RE = re.compile(
    r"(?m)^((?:[ \t]*var _temp_\d+:\*\s*=\s*[^;\n]+;\n)+)"
    rf"([ \t]*(?:[A-Za-z_$][\w$]*\s*=\s*)?)(_temp_\d+)\.([A-Za-z_$][\w$]*)\(([^\n]*)")

COMPOUND_SPILL_TEMP_RE = re.compile(
    r"(?m)^([ \t]*)var (_temp_\d+):\*\s*=\s*([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)+);\n[ \t]*\2"
    r"(\.[A-Za-z_$][\w$]*\s*(?:[-+*/%|&^]|<<|>>>?)=(?!=)[^\n]*)$")


def inline_call_spill_temps(text: str) -> str:
    if not INLINE_CALL_SPILL_TEMPS:
        return text

    def body_pass(body: str) -> str:
        def replace(m: re.Match) -> str:
            decls = [(temp, value.strip()) for temp, value in
                     re.findall(r"var (_temp_\d+):\*\s*=\s*([^;\n]+);", m.group(1))]
            if decls[0][0] != m.group(3):
                return m.group(0)
            for temp, value in decls:
                if "_temp_" in value:
                    return m.group(0)
                if len(re.findall(rf"(?<![\w$]){re.escape(temp)}(?![\w$])", body)) != 2:
                    return m.group(0)
            if not _PURE_TEMP_VALUE_RE.match(decls[0][1]):
                decls[0] = (decls[0][0], f"({decls[0][1]})")
            expected = ",".join(temp for temp, _value in decls[1:])
            args = m.group(5)
            if expected and not re.match(re.escape(expected) + r"[,)]", args):
                return m.group(0)
            inlined = ",".join(value for _temp, value in decls[1:])
            return f"{m.group(2)}{decls[0][1]}.{m.group(4)}({inlined}{args[len(expected):]}"
        def compound(m: re.Match) -> str:
            if len(re.findall(rf"(?<![\w$]){m.group(2)}(?![\w$])", body)) != 2:
                return m.group(0)
            return f"{m.group(1)}{m.group(3)}{m.group(4)}"
        body = COMPOUND_SPILL_TEMP_RE.sub(compound, body)
        return CALL_SPILL_TEMP_RE.sub(replace, body)

    span, protected = protect_noncode(text)
    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return restore_noncode("".join(out), protected)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        body_open = span.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(span, body_open) if body_open >= 0 else -1
        if body_close < 0 or ";" in span[close_paren:body_open]:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        out.append(span[i:body_open + 1])
        body = span[body_open + 1:body_close]
        if not re.search(r"\bfunction\b", body):
            body = body_pass(body)
        out.append(body)
        i = body_close


SINK_CHAIN_TEMP_LOCALS = True
CHAIN_ASSIGN_RE = re.compile(
    r"^[ \t]*[A-Za-z_][\w]*(?:\.[A-Za-z_]\w*)+\s*=\s*[A-Za-z_][\w]*(?:\.[A-Za-z_]\w*)+\s*=(?!=)[^;\n]*;[ \t]*\n",
    re.M,
)
CHAIN_TEMP_DECL_RE = re.compile(r"[ \t]*var\s+_loc(?P<reg>\d+)_\s*:\s*Number\s*(?:=\s*NaN\s*)?;[ \t]*\n")
STATIC_INCREMENT_STATEMENT_RE = re.compile(
    r"^[ \t]*+(?!\+\+|--)[^\n]*(?<![\w$.])(?:\+\+|--)(?:[A-Z]\w*|class_\d+)\.[A-Za-z_$][\w$]*[^\n]*;[ \t]*\n",
    re.M,
)
STATIC_INCREMENT_TEMP_DECL_RE = re.compile(r"[ \t]*var\s+_loc(?P<reg>\d+)_\s*:\s*uint\s*(?:=\s*0\s*)?;[ \t]*\n")
TEMP_REGISTER_KINDS = (
    (CHAIN_TEMP_DECL_RE, CHAIN_ASSIGN_RE),
    (STATIC_INCREMENT_TEMP_DECL_RE, STATIC_INCREMENT_STATEMENT_RE),
)


def sink_chain_temp_locals(text: str) -> str:
    span, protected = protect_noncode(text)
    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return restore_noncode("".join(out), protected)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        body_open = span.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(span, body_open) if body_open >= 0 else -1
        if body_close < 0 or ";" in span[close_paren:body_open]:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        out.append(span[i:body_open + 1])
        body = span[body_open + 1:body_close]
        if not re.search(r"\bfunction\b", body):
            body = _sink_chain_temp_body(body)
        out.append(body)
        i = body_close


def _brace_blocks(body: str) -> list[tuple[int, int]]:
    pairs: list[tuple[int, int]] = []
    stack: list[int] = []
    for index, ch in enumerate(body):
        if ch == "{":
            stack.append(index)
        elif ch == "}" and stack:
            pairs.append((stack.pop(), index))
    return sorted(pairs)


def _statement_block(body: str, open_index: int) -> bool:
    head = body[:open_index].rstrip()
    if re.search(r"\b(?:else|try|finally|do)$", head):
        return True
    if not head.endswith(")"):
        return False
    left = find_matching_left(head, len(head) - 1)
    return left >= 0 and re.search(r"\b(?:if|catch|while|for)\s*$", head[:left]) is not None


def _sink_chain_temp_body(body: str) -> str:
    for decl_re, statement_re in TEMP_REGISTER_KINDS:
        sunk = _sink_temp_register_body(body, decl_re, statement_re)
        if sunk != body:
            return sunk
    return body


def _sink_temp_register_body(body: str, decl_re: re.Pattern[str], statement_re: re.Pattern[str]) -> str:
    pos = 1 if body.startswith("\n") else 0
    decls: list[tuple[int, re.Match[str]]] = []
    while True:
        other = LEADING_VAR_RE.match(body, pos)
        if not other:
            break
        reg = re.match(r"[ \t]*var\s+_loc(\d+)_\s*:", other.group(0))
        if not reg:
            return body
        decls.append((int(reg.group(1)), other))
        pos = other.end()
    temps = [(reg, m) for reg, m in decls
             if decl_re.fullmatch(m.group(0)) and len(re.findall(rf"\b_loc{reg}_\b", body)) == 1]
    if len(temps) != 1:
        return body
    temp, temp_decl = temps[0]
    chain = statement_re.search(body, pos)
    if not chain:
        return body
    for found in re.finditer(r"\bvar\s+_loc(\d+)_\b", body[pos:]):
        reg = int(found.group(1))
        if (reg < temp) != (pos + found.start() < chain.start()):
            return body
    blocks = _brace_blocks(body)

    def innermost(start: int, end: int) -> tuple[int, int]:
        inside = [(o, c) for o, c in blocks if o < start and end <= c]
        return inside[-1] if inside else (-1, len(body))

    chain_block = innermost(chain.start(), chain.end())
    if chain_block[0] >= 0 and not _statement_block(body, chain_block[0]):
        return body
    inserts: list[tuple[int, int, str]] = []
    for reg, m in decls:
        if reg <= temp:
            continue
        refs = [ref.start() for ref in re.finditer(rf"\b_loc{reg}_\b", body) if not m.start() <= ref.start() < m.end()]
        if not refs or refs[0] < chain.end():
            return body
        block = innermost(refs[0], refs[-1] + 1)
        if block == chain_block:
            at = chain.end()
            indent = re.match(r"[ \t]*", chain.group(0)).group(0)
        elif block[0] > chain.end() and _statement_block(body, block[0]):
            line_end = body.find("\n", block[0])
            if line_end < 0 or body[block[0] + 1:line_end].strip():
                return body
            at = line_end + 1
            first_line = re.match(r"[ \t]*", body[at:]).group(0)
            indent = first_line
        else:
            return body
        inserts.append((at, reg, indent + m.group(0).lstrip(" \t")))
    if [at for at, _reg, _text in inserts] != sorted(at for at, _reg, _text in inserts):
        return body
    removed = {temp_decl.start()} | {m.start() for reg, m in decls if reg > temp}
    cuts = sorted([(m.start(), m.end(), "") for _reg, m in decls if m.start() in removed]
                  + [(at, at, text) for at, _reg, text in inserts])
    result = []
    last = 0
    for start, end, text in cuts:
        result.append(body[last:start])
        result.append(text)
        last = end
    result.append(body[last:])
    return "".join(result)


SINK_HOISTED_LOCALS = False
HOISTED_LOCAL_RE = re.compile(
    r"[ \t]*var\s+(?P<name>_loc\d+_)\s*:\s*(?:\*\s*=\s*null\s+as\s+(?P<ref>[A-Za-z_][\w.]*(?:\.<[^;\n=]+>)?)"
    r"|(?P<prim>Number(?=\s*=\s*NaN\b)|Boolean(?=\s*=\s*false\b)|u?int(?=\s*=\s*0\b))"
    r"\s*=\s*(?P<default>NaN|false|0))\s*;[ \t]*\n",
)
LEADING_VAR_RE = re.compile(r"[ \t]*var\s+[^;\n]*;[ \t]*\n")


SINK_HOISTED_SKIPS = {
    ('GameCore', 'method_7719', '_loc14_'),
    ('LocalizedText', 'method_939', '_loc3_'),
    ('LocalizedText', 'method_939', '_loc4_'),
    ('class_167', 'method_4967', '_loc8_'),
    ('class_167', 'method_4967', '_loc9_'),
    ('class_167', 'method_7806', '_loc17_'),
    ('class_167', 'method_7806', '_loc24_'),
    ('class_176', 'method_6868', '_loc21_'),
    ('class_176', 'method_6868', '_loc22_'),
    ('class_176', 'method_6868', '_loc24_'),
    ('class_176', 'method_8959', '_loc7_'),
    ('class_176', 'method_8959', '_loc8_'),
    ('class_176', 'method_8959', '_loc9_'),
    ('class_180', 'method_7635', '_loc7_'),
    ('class_389', 'method_8799', '_loc8_'),
    ('class_512', 'method_4679', '_loc14_'),
    ('class_512', 'method_4679', '_loc15_'),
    ('class_512', 'method_4679', '_loc16_'),
    ('class_638', 'method_8827', '_loc5_'),
    ('class_668', 'class_668', '_loc8_'),
    ('class_714', 'method_939', '_loc4_'),
    ('class_714', 'method_939', '_loc5_'),
    ('class_74', 'method_8965', '_loc15_'),
    ('class_74', 'method_8965', '_loc20_'),
    ('class_74', 'method_8965', '_loc21_'),
    ('class_81', 'method_2712', '_loc11_'),
    ('class_81', 'method_2712', '_loc9_'),
    ('class_81', 'method_8716', '_loc18_'),
    ('class_81', 'method_8716', '_loc26_'),
}


SINK_HOISTED_DEFAULTS = {
    ('class_274', 'method_7616', '_loc29_'),
}


def _enclosing_block(span: str, index: int) -> int:
    depth = 0
    i = index - 1
    while i >= 0:
        ch = span[i]
        if ch == "}":
            depth += 1
        elif ch == "{":
            if depth == 0:
                return i
            depth -= 1
        i -= 1
    return -1


def sink_hoisted_locals(text: str) -> str:
    span, protected = protect_noncode(text)
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return restore_noncode("".join(out), protected)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        body_open = span.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(span, body_open) if body_open >= 0 else -1
        if body_close < 0 or ";" in span[close_paren:body_open]:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        out.append(span[i:body_open + 1])
        skips = {local for cls, method, local in SINK_HOISTED_SKIPS
                 if cls == class_name and method == match.group(1)}
        defaults = {local for cls, method, local in SINK_HOISTED_DEFAULTS
                    if cls == class_name and method == match.group(1)}
        out.append(_sink_hoisted_body(span[body_open + 1:body_close], skips, defaults))
        i = body_close


def _hoisted_segments(body: str, decl: re.Match[str]):
    name = decl.group("name")
    word = rf"(?<![\w$.]){re.escape(name)}(?![\w$])"
    refs = [m.start() for m in re.finditer(word, body) if m.start() >= decl.end()]
    if not refs:
        return None
    segments = []
    scope_end = -1
    nested = False
    for ref in refs:
        if ref < scope_end:
            continue
        line_start = body.rfind("\n", 0, ref) + 1
        line_end = body.find("\n", ref)
        if line_end < 0:
            return None
        line = body[line_start:line_end]
        block = _enclosing_block(body, ref)
        block_close = find_matching_right(body, block) if block >= 0 else len(body)
        if block_close < 0:
            return None
        head = body[:block].rstrip() if block >= 0 else ""
        catch = re.match(rf"^[ \t]*{re.escape(name)}\s*=\s*(_loc_e\d*_)\s*;[ \t]*$", line)
        catch_head = re.search(r"\bcatch\s*\(\s*(_loc_e\d*_)\s*:\s*([^)\s]+)\s*\)$", head)
        if catch and catch_head and catch_head.group(1) == catch.group(1):
            caught = catch.group(1)
            if (decl.group("ref") is None or catch_head.group(2) != decl.group("ref")
                    or re.search(rf"(?<![\w$]){caught}(?![\w$])", body[line_end:block_close])
                    or body[block + 1:line_start].strip()):
                return None
            segments.append(("catch", line_start, line_end, (catch_head.start(1), catch_head.end(1))))
        else:
            assign = re.match(rf"^([ \t]*){re.escape(name)}\s*=(?!=)\s*(.+);[ \t]*$", line)
            if not assign or re.search(word, assign.group(2)) or re.search(r"\bswitch\s*\([^{}]*\)$", head):
                return None
            segments.append(("assign", line_start, line_end, (assign.group(1), assign.group(2))))
        nested = nested or block >= 0
        scope_end = block_close
    return segments if nested else None


def _sink_hoisted_body(body: str, skips: set[str] = frozenset(), defaults: set[str] = frozenset()) -> str:
    if re.search(r"\bfunction\b", body):
        return body
    pos = 1 if body.startswith("\n") else 0
    decls = []
    while True:
        match = HOISTED_LOCAL_RE.match(body, pos)
        if match:
            decls.append(match)
            pos = match.end()
            continue
        other = LEADING_VAR_RE.match(body, pos)
        if not other:
            break
        pos = other.end()
    edits: list[tuple[int, int, int, str]] = []
    for decl in decls:
        name = decl.group("name")
        type_name = decl.group("ref") or decl.group("prim")
        segments = None if name in skips else _hoisted_segments(body, decl)
        if segments is None:
            declaration = None if name in skips else _common_block_declaration(body, decl, name in defaults)
            if declaration is None:
                if decl.group("ref") is None and name not in skips:
                    continue
                return body
            edits.append((declaration[0], declaration[0], len(edits),
                          f"{declaration[1]}var {name}:{type_name}{declaration[2]};\n"))
        else:
            for kind, line_start, line_end, extra in segments:
                if kind == "catch":
                    edits.append((extra[0], extra[1], len(edits), name))
                    edits.append((line_start, line_end + 1, len(edits), ""))
                else:
                    edits.append((line_start, line_start, len(edits), f"{extra[0]}var {name}:{type_name};\n"))
        edits.append((decl.start(), decl.end(), len(edits), ""))
    for start, end, _order, replacement in sorted(edits, reverse=True):
        body = body[:start] + replacement + body[end:]
    return body


def _common_block_declaration(body: str, decl: re.Match[str],
                              keep_default: bool = False) -> tuple[int, str, str] | None:
    name = decl.group("name")
    refs = [m.start() for m in re.finditer(rf"(?<![\w$.]){re.escape(name)}(?![\w$])", body)
            if m.start() >= decl.end()]
    if not refs:
        return None
    first_line_start = body.rfind("\n", 0, refs[0]) + 1
    first_line_end = body.find("\n", refs[0])
    first = re.match(rf"^[ \t]*{re.escape(name)}\s*=(?!=)\s*(.+);[ \t]*$",
                     body[first_line_start:first_line_end if first_line_end >= 0 else len(body)])
    if not first or re.search(rf"(?<![\w$.]){re.escape(name)}(?![\w$])", first.group(1)):
        return None
    block = _enclosing_block(body, refs[0])
    while block >= 0:
        close = find_matching_right(body, block)
        if close < 0:
            return None
        if close > refs[-1]:
            break
        block = _enclosing_block(body, block)
    if block < 0 or re.search(r"\bswitch\s*\([^{}]*\)$", body[:block].rstrip()):
        return None
    depth = 0
    statement = None
    line_start = body.find("\n", block) + 1
    i = block + 1
    while i < refs[0]:
        ch = body[i]
        if ch == "\n":
            line_start = i + 1
            if depth == 0:
                stripped = body[line_start:body.find("\n", line_start)].strip()
                if stripped and not stripped.startswith(("{", "}", "else", "catch", "finally")):
                    statement = line_start
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        i += 1
    if statement is None:
        return None
    line = body[statement:body.find("\n", statement)]
    if line.strip().startswith("while") and body[:statement].rstrip().endswith("}"):
        return None
    initializer = f" = {decl.group('default') or 'null'}" if keep_default else ""
    return statement, re.match(r"[ \t]*", line).group(0), initializer


def promote_pseudo_typed_null_as_locals(span: str) -> str:

    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    method_ranges: list[tuple[int, int, str]] = []
    for function_match in re.finditer(r"\bfunction\s+([A-Za-z_]\w*)\s*\(", span):
        paren = span.find("(", function_match.start())
        close_paren = find_matching_right(span, paren)
        if close_paren < 0:
            continue
        body_open = span.find("{", close_paren)
        if body_open < 0:
            continue
        body_close = find_matching_right(span, body_open)
        if body_close >= 0:
            method_ranges.append((body_open, body_close, function_match.group(1)))

    def repl(match: re.Match[str]) -> str:
        raw_type = match.group("type").strip()
        root = raw_type.split(".<", 1)[0].rsplit(".", 1)[-1]
        local = match.group("name")
        method = next((name for start, end, name in method_ranges if start < match.start() < end), None)
        exact_vector = (class_name, method, local, raw_type) in AUDITED_PSEUDO_TYPED_VECTOR_LOCALS
        if root not in {"IMap", "IntMap", "StringMap"} and not exact_vector:
            return match.group(0)
        type_name = convert_vector_type_syntax(raw_type)
        return f"{match.group('prefix')}{type_name} = null;"

    return re.sub(
        r"(?P<prefix>\bvar\s+(?P<name>[A-Za-z_]\w*)\s*:\s*)\*\s*=\s*null\s+as\s+"
        r"(?P<type>[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?(?:\.<[^;\n=]+>)?)\s*;",
        repl,
        span,
    )


def convert_types(text: str) -> str:
    def one(span: str) -> str:
        span = promote_pseudo_typed_null_as_locals(span)
        span = STAR_TYPE_RE.sub(r"\1Dynamic", span)
        span = convert_vector_type_syntax(span)
        span = ARRAY_CLASS_COMPARE_RE.sub(lambda m: m.group(0).replace("Array", ARRAY_CLASS_MARKER), span)
        span = TYPE_RE.sub(haxe_type, span)
        span = span.replace(ARRAY_CLASS_MARKER, "Array")
        span = re.sub(r"(:\s*)StringMap\b(?!\s*<)", r"\1StringMap<Dynamic>", span)
        span = re.sub(r"\basType\(([^,\n]+),\s*IMap\s*\)", r"asType(\1, \"IMap\")", span)
        span = re.sub(r"\bArray<Dynamic>\.([A-Z_]+)\b", lambda m: f"{AS3_HELPER}.ARRAY_{m.group(1)}", span)
        return span

    return transform_code(text, one)


def convert_type_text(text: str) -> str:
    if text == "*":
        return "Dynamic"
    text = convert_vector_type_syntax(text)
    return TYPE_RE.sub(haxe_type, text)


def convert_vector_type_syntax(span: str) -> str:
    out: list[str] = []
    i = 0
    marker = "Vector.<"
    while True:
        start = span.find(marker, i)
        if start < 0:
            out.append(span[i:])
            return "".join(out)
        out.append(span[i:start])
        type_start = start + len(marker)
        type_end = find_generic_type_end(span, type_start)
        if type_end < 0:
            out.append(span[start:])
            return "".join(out)
        inner = span[type_start:type_end].strip()
        out.append(f"Vector<{convert_type_text(inner)}>")
        i = type_end + 1


def find_generic_type_end(span: str, type_start: int) -> int:
    depth = 1
    i = type_start
    while i < len(span):
        ch = span[i]
        if ch == "<":
            depth += 1
        elif ch == ">":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def convert_member_syntax(
    text: str,
    class_name: str | None,
    class_extends: bool = False,
    class_names: set[str] | None = None,
) -> str:
    text = convert_for_each_loops(text)
    property_setters = {
        match.group(1)
        for is_code, span in split_code(text)
        if is_code
        for match in re.finditer(r"\bfunction\s+set\s+([A-Za-z_]\w*)\s*\(", span)
    }

    def one(span: str) -> str:
        span = re.sub(r"\b(public|private|protected|internal)\s+(?=(?:dynamic\s+)?(?:final\s+)?(?:class|interface)\b)", "", span)
        span = re.sub(r"\b(dynamic|final)\s+(?=(?:class|interface)\b)", "", span)
        span = re.sub(r"\bfinal\s+(?=(?:public|private|protected|internal|override)\s+function\b)", "", span)
        span = re.sub(r"\b(public|private|protected|internal|override)\s+final\s+(?=function\b)", r"\1 ", span)
        span = re.sub(r"\bprotected\s+", "public ", span)
        span = re.sub(r"\binternal\s+", "public ", span)
        span = re.sub(r"\bconst\b", "final", span)
        for name in sorted(class_names or ({class_name} if class_name else set()), key=len, reverse=True):
            span = re.sub(rf"\bfunction\s+{re.escape(name)}\s*\(", "function new(", span)
        if not class_extends:
            span = re.sub(r"^\s*super\s*\(\s*\);\s*$\n?", "", span, flags=re.MULTILINE)
        span = FOR_IN_VAR_RE.sub(
            lambda m: f"for ({m.group(1)}{'' if m.group(2) in FOR_IN_TEXT_KEY_TYPES else FOR_IN_DYNAMIC_KEY_MARK} in ",
            span)
        span = add_getter_properties(span, property_setters)
        span = add_interface_getter_properties(span)
        span = GETTER_SETTER_RE.sub(lambda m: f"function {m.group(1)}_{m.group(2)}(", span)
        span = re.sub(r"\bfunction\s+([A-Za-z_]\w*)\s*\(", r"function \1(", span)
        span = re.sub(r"\)\s+:\s+", "):", span)
        span = re.sub(r"\.\.\.\s+([A-Za-z_]\w*)", r"...\1:Dynamic", span)
        span = span.replace("!==", "!=").replace("===", "==")
        span = VECTOR_CTOR_RE.sub(lambda m: f"new Vector<{m.group(1).strip()}>(", span)
        span = vector_casts(span)
        span = convert_dynamic_new(span)
        return span

    return transform_code(text, one)


def add_getter_properties(span: str, setters: set[str] | None = None) -> str:
    setters = setters or {
        match.group(1)
        for match in re.finditer(r"\bfunction\s+set\s+([A-Za-z_]\w*)\s*\(", span)
    }
    def repl(match: re.Match[str]) -> str:
        indent = match.group("indent")
        mods = match.group("mods")
        if "override" in mods.split():
            return match.group(0)
        name = match.group("name")
        type_name = match.group("type").strip()
        accessor = "get, set" if name in setters else "get, never"
        return f"{indent}{mods}var {name}({accessor}):{type_name};\n{match.group(0)}"

    return re.sub(
        r"(?P<indent>^[ \t]*)(?P<mods>(?:(?:public|private|static|override)\s+)*)function\s+get\s+"
        r"(?P<name>[A-Za-z_]\w*)\s*\(\s*\)\s*:\s*(?P<type>[^{\n]+?)\s*\{",
        repl,
        span,
        flags=re.MULTILINE,
    )


def add_interface_getter_properties(span: str) -> str:
    def repl(match: re.Match[str]) -> str:
        indent = match.group("indent")
        name = match.group("name")
        type_name = match.group("type").strip()
        return f"{indent}var {name}(get, never):{type_name};\n{match.group(0)}"

    return re.sub(
        r"(?P<indent>^[ \t]*)function\s+get\s+(?P<name>[A-Za-z_]\w*)\s*\(\s*\)\s*:\s*(?P<type>[^;\n]+?)\s*;",
        repl,
        span,
        flags=re.MULTILINE,
    )


def convert_property_setter_returns(span: str) -> str:
    out: list[str] = []
    i = 0
    pattern = re.compile(
        r"function\s+set_([A-Za-z_]\w*)\s*\(\s*([A-Za-z_]\w*)\s*:\s*([^)]+?)\s*\)\s*:\s*Void\s*\{"
    )
    while True:
        match = pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return "".join(out)
        open_brace = span.find("{", match.start())
        close_brace = find_matching_right(span, open_brace)
        if close_brace < 0:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        value_name = match.group(2)
        value_type = match.group(3).strip()
        out.append(span[i:match.start()])
        out.append(
            span[match.start():match.end()]
            .replace(":Void", f":{value_type}", 1)
        )
        body = span[match.end():close_brace]
        body = re.sub(r"\breturn\s*;", f"return {value_name};", body)
        indent = line_indent(span, close_brace)
        if re.search(r"\breturn\b", body):
            out.append(body)
        else:
            out.append(body.rstrip())
            out.append(f"\n{indent}   return {value_name};\n{indent}")
        out.append("}")
        i = close_brace + 1


SELF_ASSIGNMENT_CASTS = True


def remove_self_assignments(text: str) -> str:
    def one(span: str) -> str:
        if SELF_ASSIGNMENT_CASTS:
            span = re.sub(r"^([ \t]*)(_loc\d+_|param\d+)\s*=\s*\2\s*;", r"\1\2 = cast \2;", span, flags=re.MULTILINE)
        return re.sub(
            r"^[ \t]*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*=\s*\1\s*;\s*\n?",
            "",
            span,
            flags=re.MULTILINE,
        )

    return transform_code(text, one)


def move_instance_field_initializers(text: str, class_name: str | None) -> str:
    if not class_name:
        return text
    class_match = re.search(rf"\bclass\s+{re.escape(class_name)}\b[^\{{]*\{{", text)
    if not class_match:
        return text
    class_open = text.find("{", class_match.start())
    class_close = find_matching_right(text, class_open)
    if class_close < 0:
        return text
    body = text[class_open + 1:class_close]
    field_re = re.compile(
        r"(?P<indent>^[ \t]*)(?P<prefix>(?:public|private|protected|internal)\s+var\s+)"
        r"(?P<name>[A-Za-z_]\w*)\s*:\s*(?P<type>[^=;\n]+?)\s*=\s*(?P<expr>[^;\n]+);",
        re.MULTILINE,
    )
    moved: list[tuple[str, str]] = []

    def field_repl(match: re.Match[str]) -> str:
        expr = match.group("expr").strip()
        if not instance_initializer_needs_constructor(expr):
            return match.group(0)
        moved.append((match.group("name"), expr))
        return f"{match.group('indent')}{match.group('prefix')}{match.group('name')}:{match.group('type').strip()};"

    body = field_re.sub(field_repl, body)
    order = original_field_init_order(class_name)
    literal_moves: dict[str, tuple[str, str]] = {}
    ctor_match = re.search(r"\bfunction\s+new\s*\([^)]*\)\s*\{", body)
    if order and ctor_match:
        ctor_text = body[ctor_match.end():find_matching_right(body, body.find("{", ctor_match.start()))]

        def literal_repl(match: re.Match[str]) -> str:
            name = match.group("name")
            if any(name == moved_name for moved_name, _ in moved):
                return match.group(0)
            before = field_init_predecessor(order, name)
            if before is None or not (
                any(before == moved_name for moved_name, _ in moved)
                or field_init_anchor(ctor_text, before) is not None
            ):
                return match.group(0)
            moved.append((name, match.group("expr").strip()))
            declaration = f"{match.group('indent')}{match.group('prefix')}{name}:{match.group('type').strip()};"
            literal_moves[name] = (declaration, match.group(0))
            return declaration

        while True:
            count = len(moved)
            body = field_re.sub(literal_repl, body)
            if len(moved) == count:
                break
        ctor_match = re.search(r"\bfunction\s+new\s*\([^)]*\)\s*\{", body)
    if not moved:
        return text
    if ctor_match:
        ctor_open = body.find("{", ctor_match.start())
        indent = line_indent(body, ctor_open) + "   "
        leading = moved
        if order:
            ctor_close = find_matching_right(body, ctor_open)
            ctor_body, leading = place_field_initializers(body[ctor_open + 1:ctor_close], moved, order, indent)
            body = body[:ctor_open + 1] + ctor_body + body[ctor_close:]
            for item in [item for item in leading if item[0] in literal_moves]:
                declaration, original = literal_moves[item[0]]
                head = body[:ctor_open]
                if head.count(declaration) == 1:
                    body = head.replace(declaration, original) + body[ctor_open:]
                    ctor_open += len(original) - len(declaration)
                    leading.remove(item)
        assignments = "".join(f"\n{indent}{name} = {expr};" for name, expr in leading)
        body = body[:ctor_open + 1] + assignments + body[ctor_open + 1:]
    else:
        indent = line_indent(text, class_open) + "   "
        assignments = "".join(f"\n{indent}   {name} = {expr};" for name, expr in moved)
        body = f"\n{indent}public function new()\n{indent}{{{assignments}\n{indent}}}\n" + body
    return text[:class_open + 1] + body + text[class_close:]


ORDER_FIELD_INITIALIZERS = True
_FIELD_INITIALIZER_LINE_RE = re.compile(
    r"(?m)^[ \t]*(?:public|private|protected|internal)\s+var\s+([A-Za-z_]\w*)\s*:[^=;\n]+=[^;\n]+;[ \t]*$")


def order_field_initializers(text: str, class_name: str | None) -> str:
    order = original_field_init_order(class_name)
    if not ORDER_FIELD_INITIALIZERS or not order or not class_name:
        return text
    class_match = re.search(rf"\bclass\s+{re.escape(class_name)}\b[^\{{]*\{{", text)
    if not class_match:
        return text
    class_open = text.find("{", class_match.start())
    class_close = find_matching_right(text, class_open)
    if class_close < 0:
        return text
    body = text[class_open + 1:class_close]
    once = {name for name in order if order.count(name) == 1}
    lines = [m for m in _FIELD_INITIALIZER_LINE_RE.finditer(body) if m.group(1) in once]
    names = [m.group(1) for m in lines]
    if len(lines) < 2 or len(set(names)) != len(names):
        return text
    wanted = sorted(names, key=order.index, reverse=True)
    if wanted == names:
        return text
    by_name = {m.group(1): m.group(0).strip() for m in lines}
    out: list[str] = []
    last = 0
    for m, name in zip(lines, wanted):
        indent = re.match(r"[ \t]*", m.group(0)).group(0)
        out.append(body[last:m.start()] + indent + by_name[name])
        last = m.end()
    out.append(body[last:])
    return text[:class_open + 1] + "".join(out) + text[class_close:]


FIELD_INIT_ORDER_PATH = ROOT / "build" / "port-haxe" / "10.11" / "field-init-order.json"
HOISTED_LOCALS_PATH = ROOT / "build" / "port-haxe" / "10.11" / "hoisted-locals.json"
_HOISTED_LOCALS: dict[str, dict[str, str]] | None = None


TEMP_RECEIVERS_PATH = ROOT / "build" / "port-haxe" / "10.11" / "temp-receivers.json"
_TEMP_RECEIVERS: dict[str, dict[str, list[str | None]]] | None = None
RESTORE_TEMP_RECEIVERS = True


def load_temp_receivers(table: dict | None = None) -> dict[str, dict[str, list[str | None]]]:
    global _TEMP_RECEIVERS
    if table is not None:
        _TEMP_RECEIVERS = table
    elif _TEMP_RECEIVERS is None:
        try:
            _TEMP_RECEIVERS = json.loads(TEMP_RECEIVERS_PATH.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            _TEMP_RECEIVERS = {}
    return _TEMP_RECEIVERS


_RMW_SITE_RE = re.compile(
    r"(?<![\w$.\]])(\+\+|--)?((?:[A-Za-z_$][\w$]*)(?:\.[A-Za-z_$][\w$]*|\[[\w$.]*\])*)\.([A-Za-z_$][\w$]*)"
    r"\s*(?:(\+\+|--)|(>>>|<<|>>|[-+*/%|&^])=(?!=))")


def _register_names(signature: str) -> dict[str, str]:
    params = [part.strip() for part in signature.split(",") if part.strip()]
    names = {"0": "this"}
    for number, param in enumerate(params, 1):
        rest = re.match(r"\.\.\.\s*([A-Za-z_$][\w$]*)", param)
        names[str(number)] = rest.group(1) if rest else re.match(r"[A-Za-z_$][\w$]*", param).group(0)
    return names


def _restore_method_temp_receivers(body: str, receivers: dict, signature: str) -> str:
    registers = _register_names(signature)

    def plain(receiver: str) -> str:
        return re.sub(r"^this[.]", "", receiver)

    def resolve(head: str | None) -> str | None:
        if head is None:
            return None
        def local(m: re.Match) -> str:
            return registers.get(m.group(1), f"_loc{m.group(1)}_")
        named = re.sub(r"@(\d+)", local, head)
        for loc in re.findall(r"\b_loc\d+_\b", named):
            if not re.search(rf"\b{loc}\b", body):
                return None
        return named

    orphans = {name for name in set(re.findall(r"\b_temp_\d+\b", body))
               if not re.search(rf"\b{name}\s*=(?!=)|\bvar\s+{name}\b", body)}
    if not orphans:
        return body
    sites: dict[str, list[tuple[str, str]]] = {}
    for site in _RMW_SITE_RE.finditer(body):
        op = site.group(1) or site.group(4) or site.group(5)
        sites.setdefault(site.group(3), []).append((site.group(2), op))
    assigned: dict[str, str] = {}
    conflicts: set[str] = set()
    for field, found in sites.items():
        original = receivers.get(field) or []
        original = [entry if isinstance(entry, list) else [entry, None] for entry in original]
        if not any(receiver in orphans for receiver, _op in found):
            continue
        heads = [resolve(head) for head, _op in original]
        if len(set(heads)) == 1 and heads[0] is not None:
            for receiver, _op in found:
                if receiver in orphans:
                    assigned[receiver] = heads[0]
            continue
        if len(found) != len(original):
            continue
        if any(op != expected for (_receiver, op), (_head, expected) in zip(found, original)):
            continue
        if any(receiver not in orphans and head is not None and plain(receiver) != plain(head)
               for (receiver, _op), head in zip(found, heads)):
            continue
        for (receiver, _op), head in zip(found, heads):
            if receiver in orphans and head is not None:
                if assigned.get(receiver, head) != head:
                    conflicts.add(receiver)
                assigned[receiver] = head
    for name in sorted(orphans):
        uses = set(re.findall(rf"\b{name}\b(?:\.([A-Za-z_$][\w$]*))?", body))
        if name not in assigned or name in conflicts or len(uses) != 1 or "" in uses:
            continue
        if "[" in assigned[name]:
            statement = re.compile(rf"(?m)^([ \t]*){name}\.")
            if len(re.findall(rf"\b{name}\b", body)) == 1 and statement.search(body):
                body = statement.sub(lambda m: f"{m.group(1)}{name} = {assigned[name]};\n{m.group(0)}", body)
            continue
        body = re.sub(rf"\b{name}\b", assigned[name], body)
    return body


def restore_temp_receivers(text: str) -> str:
    table = load_temp_receivers()
    if not RESTORE_TEMP_RECEIVERS or not table:
        return text
    span, protected = protect_noncode(text)
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return restore_noncode("".join(out), protected)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        body_open = span.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(span, body_open) if body_open >= 0 else -1
        if body_close < 0 or ";" in span[close_paren:body_open]:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        out.append(span[i:body_open + 1])
        body = span[body_open + 1:body_close]
        receivers = table.get(f"{class_name}/{match.group(1)}") or {}
        if receivers and "_temp_" in body and not re.search(r"\bfunction\b", body):
            body = _restore_method_temp_receivers(body, receivers, span[paren + 1:close_paren])
        out.append(body)
        i = body_close


def load_hoisted_locals(table: dict[str, dict[str, str]] | None = None) -> dict[str, dict[str, str]]:
    global _HOISTED_LOCALS
    if table is not None:
        _HOISTED_LOCALS = table
    elif _HOISTED_LOCALS is None:
        try:
            _HOISTED_LOCALS = json.loads(HOISTED_LOCALS_PATH.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            _HOISTED_LOCALS = {}
    return _HOISTED_LOCALS


ELEMENT_TYPES_PATH = ROOT / "build" / "port-haxe" / "10.11" / "element-types.json"
_ELEMENT_TYPES: dict[str, dict[str, str]] | None = None


def load_element_types(table: dict[str, dict[str, str]] | None = None) -> dict[str, dict[str, str]]:
    global _ELEMENT_TYPES
    if table is not None:
        _ELEMENT_TYPES = table
    elif _ELEMENT_TYPES is None:
        try:
            _ELEMENT_TYPES = json.loads(ELEMENT_TYPES_PATH.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            _ELEMENT_TYPES = {}
    return _ELEMENT_TYPES


ELEMENT_TYPED_CONTAINERS = True
IMAP_ELEMENT = "haxe.Constraints.IMap<Dynamic, Dynamic>"
WIDE_ELEMENTS = {"EnumValue", "Array<Dynamic>", IMAP_ELEMENT}
ELEMENT_TYPE_SKIPS = {
    ("StoreType", "method_7344", "13"),
    ("HotkeyType", "method_1041", "21"),
}
PARAM_ELEMENT_SKIPS: dict[tuple[str, str], tuple[str, ...]] = {}


def _cast_container_stores(span: str, target: str) -> str:
    out: list[str] = []
    i = 0
    for match in re.finditer(rf"(?<![\w$.]){target}(?:\s*:\s*[\w.<>, ]+?)?\s*=(?![=>])\s*", span):
        if match.start() < i:
            continue
        value = match.end()
        depth = 0
        end = value
        while end < len(span):
            ch = span[end]
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                if depth == 0:
                    break
                depth -= 1
            elif ch in ";," and depth == 0:
                break
            end += 1
        expression = span[value:end].strip()
        if (end >= len(span) or span[end] != ";" or not expression or expression == "null"
                or expression.startswith(("new ", "[", "cast ", "cast(", f"{AS3_HELPER}.index(",
                                          f"{AS3_HELPER}.hasKey(StringMap.reserved,"))):
            continue
        out.append(span[i:value] + f"cast ({span[value:end].rstrip()})")
        i = value + len(span[value:end].rstrip())
    out.append(span[i:])
    return "".join(out)


def restore_container_element_types(text: str, class_name: str | None) -> str:
    table = load_element_types()
    if not ELEMENT_TYPED_CONTAINERS or not table:
        return text
    fields = table.get("fields") or {}
    own = {name: entry for name, entry in fields.items() if entry["class"] == class_name}
    class_fields = {key.split("/", 1)[1]: entry for key, entry in (table.get("class_fields") or {}).items()
                    if entry["class"] == class_name}
    own.update(class_fields)

    def declaration(match: re.Match[str]) -> str:
        entry = own.get(match.group("name"))
        if not entry or entry["type"] != match.group("kind"):
            return match.group(0)
        return f"{match.group('head')}{match.group('kind')}<{entry['element']}>"

    text = re.sub(r"(?m)^(?P<head>      (?:(?:public|private|protected|internal|static|override)\s+)+var\s+"
                  r"(?P<name>[\w$]+)\s*:\s*)(?P<kind>Array|StringMap|IntMap)<Dynamic>", declaration, text)

    methods = (table.get("locals") or {}) if class_name else {}
    params_table = (table.get("params") or {}) if class_name else {}
    out: list[str] = []
    i = 0
    for match in re.finditer(r"\bfunction\s+([A-Za-z_]\w*)\s*\(", text):
        if match.start() < i:
            continue
        close_paren = find_matching_right(text, text.find("(", match.start()))
        body_open = text.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(text, body_open) if body_open >= 0 else -1
        if body_close < 0 or ";" in text[close_paren:body_open]:
            continue
        body = text[body_open:body_close]
        registers = {register: element for register, element
                     in (methods.get(f"{class_name}/{match.group(1)}") or {}).items()
                     if element not in WIDE_ELEMENTS and not element.startswith("Vector<")}
        skipped = {f"_loc{register}_" for cls, method, register in ELEMENT_TYPE_SKIPS
                   if cls == class_name and method == match.group(1)}
        for local in skipped:
            registers.pop(local[4:-1], None)
        head = text[i:body_open]
        params = {register: element for register, element
                  in ((params_table.get("methods") or {}).get(f"{class_name}/{match.group(1)}") or {}).items()
                  if register not in PARAM_ELEMENT_SKIPS.get((class_name, match.group(1)), ())}
        if params:
            params_open = text.find("(", match.start())
            head = (text[i:params_open]
                    + re.sub(r"(?P<head>\bparam(?P<reg>\d+)\s*:\s*)(?P<kind>Array|StringMap|IntMap)<Dynamic>(?![\w<])",
                             lambda m: (f"{m.group('head')}{m.group('kind')}<{params[m.group('reg')]}>"
                                        if m.group("reg") in params else m.group(0)),
                             text[params_open:close_paren])
                    + text[close_paren:body_open])
        if registers and not re.search(r"\bfunction\b", body):
            body = re.sub(r"(?P<head>\bvar\s+_loc(?P<reg>\d+)_\s*:\s*)(?P<kind>Array|StringMap|IntMap)<Dynamic>(?![\w<])",
                          lambda m: (f"{m.group('head')}{m.group('kind')}<{registers[m.group('reg')]}>"
                                     if m.group("reg") in registers else m.group(0)), body)

        def local_copy(copy: re.Match[str]) -> str:
            entry = fields.get(copy.group("field"))
            if not entry and not copy.group("receiver"):
                entry = class_fields.get(copy.group("field"))
            if (not entry or entry["type"] != copy.group("kind") or copy.group("local") in skipped
                    or re.search(rf"(?<![\w$.]){copy.group('local')}\s*=(?![=>])", body)):
                return copy.group(0)
            return f"{copy.group('head')}{copy.group('kind')}<{entry['element']}>{copy.group('tail')}"

        body = re.sub(r"(?P<head>\bvar\s+(?P<local>_loc\d+_)\s*:\s*)(?P<kind>Array|StringMap|IntMap)<Dynamic>"
                      r"(?P<tail>\s*=\s*(?P<receiver>(?:[A-Za-z_][\w$]*\.)*)(?P<field>[\w$]+)\s*;)", local_copy, body)
        out.append(head + body)
        i = body_close
    out.append(text[i:])
    return "".join(out)


def restore_double_literal_stores(text: str, class_name: str | None) -> str:
    table = load_element_types()
    methods = (table.get("double_stores") or {}) if table and class_name else {}
    int_owners = (table.get("double_store_int_owners") or {}) if methods else {}
    receiver_fields = (table.get("double_store_receiver_fields") or {}) if methods else {}
    if not methods:
        return text
    out: list[str] = []
    i = 0
    for match in re.finditer(r"\bfunction\s+([A-Za-z_]\w*)\s*\(", text):
        stores = methods.get(f"{class_name}/{match.group(1)}")
        if match.start() < i or not stores:
            continue
        close_paren = find_matching_right(text, text.find("(", match.start()))
        body_open = text.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(text, body_open) if body_open >= 0 else -1
        if body_close < 0 or ";" in text[close_paren:body_open]:
            continue
        body = text[body_open:body_close]
        if re.search(r"\bfunction\b", body):
            continue
        params = text[text.find("(", match.start()) + 1:close_paren]

        def receiver_type(start: int, body: str = body, params: str = params) -> str | None:
            if start == 0 or body[start - 1] != ".":
                return class_name
            receiver = re.search(r"([A-Za-z_][\w$]*)$", body[:start - 1])
            if not receiver:
                return None
            if receiver.group(1) == "this":
                return class_name
            chained = receiver.start() > 0 and body[receiver.start() - 1] == "."
            declared = None if chained else (
                re.search(rf"\bvar\s+{re.escape(receiver.group(1))}\s*:\s*([\w.$]+)", body)
                or re.search(rf"(?<![\w$]){re.escape(receiver.group(1))}\s*:\s*([\w.$]+)", params))
            typ = declared.group(1) if declared else receiver_fields.get(receiver.group(1))
            if not typ:
                return None
            typ = typ.rsplit(".", 1)[-1]
            return "class_" + typ[6:] if typ.startswith("Class_") else typ

        for name, values in stores.items():
            blocked = set(int_owners.get(name, ()))
            for value in values:
                def spell(m: re.Match, name: str = name, value: str = value, blocked: set = blocked) -> str:
                    if blocked and receiver_type(m.start()) in blocked | {None}:
                        return m.group(0)
                    return f"{name}{m.group(1)}{value}.0"
                body = re.sub(rf"(?<![\w$]){re.escape(name)}(\s*=(?![=>])\s*){re.escape(value)}(?=\s*;)",
                              spell, body)
        out.append(text[i:body_open] + body)
        i = body_close
    out.append(text[i:])
    return "".join(out)


_NUMERIC_LITERAL_RE = re.compile(
    r"(?<![\w$.])(-?)(0x[0-9a-fA-F]+|\d+\.\d*(?:[eE][+-]?\d+)?|\d+(?:[eE][+-]?\d+)?)(?![\w$.])")
_UNARY_MINUS_BEFORE_RE = re.compile(r"(?:[=(,?:\[+\-*/%<>!&|^{;]|\breturn|\bcase)\s*$")


def numeric_literal_tokens(body: str) -> list[tuple[float, int, int]]:
    text = body
    out = []
    for match in _NUMERIC_LITERAL_RE.finditer(text):
        digits = match.group(2)
        value = float(int(digits, 16)) if digits.lower().startswith("0x") else float(digits)
        if match.group(1) and _UNARY_MINUS_BEFORE_RE.search(text[:match.start()]):
            value = -value
        out.append((value, match.start(2), match.end(2)))
    return out


POSITIONAL_DOUBLE_LITERALS = True


def restore_double_literals(text: str, class_name: str | None) -> str:
    table = load_element_types()
    methods = (table.get("double_literals") or {}) if table and class_name and POSITIONAL_DOUBLE_LITERALS else {}
    if not methods:
        return text
    out: list[str] = []
    i = 0
    for match in re.finditer(r"\bfunction\s+([A-Za-z_]\w*)\s*\(", text):
        entry = methods.get(f"{class_name}/{match.group(1)}")
        if match.start() < i or not entry:
            continue
        close_paren = find_matching_right(text, text.find("(", match.start()))
        body_open = text.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(text, body_open) if body_open >= 0 else -1
        if body_close < 0 or ";" in text[close_paren:body_open]:
            continue
        body = text[body_open:body_close]
        if re.search(r"\bfunction\b", body[1:]):
            continue
        body, protected = protect_noncode(body)
        tokens = numeric_literal_tokens(body)
        if [value for value, _start, _end in tokens] != entry["values"]:
            continue
        uints = set(entry.get("uints", ()))
        for index in sorted(set(entry["doubles"]) | uints, reverse=True):
            value, start, end = tokens[index]
            digits = body[start:end]
            if index in uints:
                if "." not in digits and "e" not in digits.lower() or digits.lower().startswith("0x"):
                    body = f"{body[:start]}{UINT_MARKER}{int(value)}{body[end:]}"
                continue
            if "." in digits or "e" in digits.lower() and not digits.lower().startswith("0x"):
                continue
            spelled = str(int(digits, 16)) if digits.lower().startswith("0x") else digits
            body = f"{body[:start]}{spelled}.0{body[end:]}"
        out.append(text[i:body_open] + restore_noncode(body, protected))
        i = body_close
    out.append(text[i:])
    return "".join(out)


UINT_MARKER = "000"
_UINT_MARKER_RE = re.compile(rf"(?:{re.escape(AS3_HELPER)}\.toUInt\({UINT_MARKER}(\d+)\)|(?<![\w.]){UINT_MARKER}(\d+)(?![\w.]))")


def restore_uint_literal_markers(text: str) -> str:
    if UINT_MARKER not in text:
        return text
    code, protected = protect_noncode(text)
    code = _UINT_MARKER_RE.sub(lambda m: f"{AS3_HELPER}.uintConst({int(m.group(1) or m.group(2))})", code)
    return restore_noncode(code, protected)


def restore_uint_constant_stores(text: str, class_name: str | None) -> str:
    table = load_element_types()
    methods = (table.get("uint_consts") or {}) if table and class_name else {}
    if not methods:
        return text
    out: list[str] = []
    i = 0
    for match in re.finditer(r"\bfunction\s+([A-Za-z_]\w*)\s*\(", text):
        consts = methods.get(f"{class_name}/{match.group(1)}")
        if match.start() < i or not consts:
            continue
        close_paren = find_matching_right(text, text.find("(", match.start()))
        body_open = text.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(text, body_open) if body_open >= 0 else -1
        if body_close < 0 or ";" in text[close_paren:body_open]:
            continue
        body = text[body_open:body_close]
        if re.search(r"\bfunction\b", body):
            continue
        for value, count in consts.items():
            store = re.compile(rf"(?<![=!<>+\-*/%&|^])(=\s*)(?:{re.escape(AS3_HELPER)}\.toUInt\({re.escape(value)}\)"
                               rf"|{re.escape(value)})(?=\s*;)")
            if len(store.findall(body)) == count:
                body = store.sub(lambda m, value=value: f"{m.group(1)}{AS3_HELPER}.uintConst({value})", body)
        out.append(text[i:body_open] + body)
        i = body_close
    out.append(text[i:])
    return "".join(out)


def cast_container_element_stores(text: str, class_name: str | None = None) -> str:
    table = load_element_types()
    if not ELEMENT_TYPED_CONTAINERS or not table:
        return text
    fields = table.get("fields") or {}
    span, protected = protect_noncode(text)
    typed_local = re.compile(r"\bvar\s+(_loc\d+_)\s*:\s*(?:Array|StringMap|IntMap)<(?!Dynamic>)")
    out: list[str] = []
    i = 0
    for match in re.finditer(r"\bfunction\s+[A-Za-z_]\w*\s*\(", span):
        if match.start() < i:
            continue
        close_paren = find_matching_right(span, span.find("(", match.start()))
        body_open = span.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(span, body_open) if body_open >= 0 else -1
        if body_close < 0 or ";" in span[close_paren:body_open]:
            continue
        body = span[body_open:body_close]
        for local in sorted(set(typed_local.findall(body))):
            body = _cast_container_stores(body, local)
        out.append(span[i:body_open] + body)
        i = body_close
    out.append(span[i:])
    span = "".join(out)
    for name in sorted(fields):
        if name in span:
            span = _cast_container_stores(span, rf"(?:[A-Za-z_][\w$]*\.)*{re.escape(name)}")
    for key, entry in sorted((table.get("class_fields") or {}).items()):
        name = key.split("/", 1)[1]
        if entry["class"] == class_name and name in span:
            span = _cast_container_stores(span, rf"(?:this\.)?{re.escape(name)}")
    span = _cast_container_arguments(span, (table.get("params") or {}).get("calls") or {})
    return restore_noncode(span, protected)


def _cast_container_arguments(span: str, calls: dict[str, list[str]]) -> str:
    if not calls:
        return span
    pattern = re.compile(r"(?<![\w$])(" + "|".join(re.escape(name) for name in sorted(calls)) + r")\(")
    out: list[str] = []
    i = 0
    for match in pattern.finditer(span):
        if match.start() < i or re.search(r"\bfunction\s+$", span[max(0, match.start() - 20):match.start()]):
            continue
        open_paren = match.end() - 1
        close_paren = find_matching_right(span, open_paren)
        if close_paren < 0:
            continue
        args = split_top_level_commas(span[open_paren + 1:close_paren])
        changed = False
        for register in calls[match.group(1)]:
            index = int(register) - 1
            if index >= len(args):
                continue
            value = args[index].strip()
            if not value or value == "null" or value.startswith(("new ", "[", "cast ", "cast(")):
                continue
            lead = args[index][:len(args[index]) - len(args[index].lstrip())]
            args[index] = f"{lead}cast ({value})"
            changed = True
        if changed:
            out.append(span[i:open_paren + 1] + ",".join(args))
            i = close_paren
    out.append(span[i:])
    return "".join(out)


UNINIT_HOISTED_LOCALS = True
HOISTED_MARK = "/*hoisted*/"
UNINIT_DECL_RE = re.compile(
    r"(?P<head>[ \t]*var\s+_loc(?P<reg>\d+)_\s*:\s*)(?:\*\s*=\s*null\s+as\s+(?P<ref>[A-Za-z_][\w.]*(?:\.<[^;\n=]+>)?)"
    r"|(?P<typed>\*|[A-Za-z_][\w.]*(?:\.<[^;\n=]+>)?)\s*=\s*(?P<value>null|NaN|false|0))\s*;"
)
UNINIT_HOISTED_SKIPS = {
    ('class_79', 'method_7724', '_loc14_'),
    ('class_423', 'method_8162', '_loc3_'),
    ('class_715', 'Initialize', '_loc7_'),
    ('class_74', 'method_8965', '_loc6_'),
    ('class_123', 'method_2080', '_loc7_'),
    ('class_666', 'method_1299', '_loc10_'),
    ('class_666', 'method_490', '_loc3_'),
    ('class_698', 'method_1813', '_loc3_'),
    ('CostumeType', 'method_7242', '_loc3_'),
    ('class_182', 'method_1998', '_loc5_'),
    ('class_525', 'method_4838', '_loc5_'),
    ('class_529', 'OnInitDisplay', '_loc5_'),
    ('ControllerMappingType', 'method_8682', '_loc8_'),
}
UNINIT_PRIMITIVES = {("Number", "NaN"): "nan", ("Boolean", "false"): "false", ("int", "0"): "int",
                     ("uint", "0"): "uint"}


def uninitialize_hoisted_locals(text: str) -> str:
    table = load_hoisted_locals()
    if not table:
        return text
    span, protected = protect_noncode(text)
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return restore_noncode("".join(out), protected)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        body_open = span.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(span, body_open) if body_open >= 0 else -1
        if body_close < 0 or ";" in span[close_paren:body_open]:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        out.append(span[i:body_open + 1])
        body = span[body_open + 1:body_close]
        registers = table.get(f"{class_name}/{match.group(1)}") or {}
        skipped = {local[4:-1] for cls, method, local in SINK_HOISTED_SKIPS | UNINIT_HOISTED_SKIPS
                   if cls == class_name and method == match.group(1)}
        if registers and not re.search(r"\bfunction\b", body):
            body = _uninitialize_hoisted_body(body, registers, span[paren + 1:close_paren], skipped,
                                              (class_name, match.group(1)) not in RESCOPE_HOISTED_SKIPS)
        out.append(body)
        i = body_close


def _uninitialize_hoisted_body(body: str, registers: dict[str, str], params: str = "",
                               skipped: set[str] = frozenset(), rescope: bool = True) -> str:
    original = body
    pos = 1 if body.startswith("\n") else 0
    edits: list[tuple[int, int, str]] = []
    moves: list[tuple[int, str]] = []
    while True:
        other = LEADING_VAR_RE.match(body, pos)
        if not other:
            break
        reg = re.match(r"[ \t]*var\s+_loc(\d+)_\s*:", other.group(0))
        kind = registers.get(reg.group(1)) if reg else None
        if kind is not None and reg.group(1) in skipped:
            return original
        decl = UNINIT_DECL_RE.match(body, pos)
        if kind is not None and not (decl and decl.end() <= other.end()):
            return original
        if kind is not None:
            if decl.group("ref"):
                type_name = decl.group("ref")
                ok = type_name.split(".<", 1)[0].rsplit(".", 1)[-1] == kind
            else:
                type_name = decl.group("typed")
                value = decl.group("value")
                ok = (UNINIT_PRIMITIVES.get((type_name, value)) == kind if value != "null"
                      else type_name.split(".<", 1)[0].rsplit(".", 1)[-1] == kind)
            if ok and decl.group("ref") and _stores_other_typed_local(body, f"_loc{decl.group('reg')}_",
                                                                     type_name, params):
                ok = False
            if ok and _maybe_read_unstored(body, f"_loc{decl.group('reg')}_", decl.end()):
                ok = False
            if ok and _first_use_at_top_level(body, f"_loc{decl.group('reg')}_", decl.end()):
                if RESCOPE_HOISTED_LOCALS and rescope:
                    rescoped = _rescope_hoisted_body(original, registers, int(decl.group("reg")), params, skipped)
                    if rescoped is not None:
                        return rescoped
                if ELSE_WRAP_HOISTED_LOCALS and rescope:
                    wrapped = _else_wrap_hoisted_body(original, registers, params, skipped)
                    if wrapped is not None:
                        return wrapped
                ok = False
            if ok:
                mark = HOISTED_MARK if decl.group("ref") or (decl.group("value") == "null" and kind != "*") else ""
                targets = _try_block_declarations(body, decl) if TRY_SCOPE_HOISTED_LOCALS else None
                if targets:
                    for at, indent in targets:
                        moves.append((at, f"{indent}var _loc{decl.group('reg')}_:{type_name}{mark};\n"))
                    line_end = body.find("\n", decl.end())
                    edits.append((decl.start(), line_end + 1 if line_end >= 0 else decl.end(), ""))
                else:
                    edits.append((decl.start(), decl.end(), f"{decl.group('head')}{type_name}{mark};"))
            elif kind not in ("uint", "*"):
                return original
        pos = other.end()
    for start, replacement in sorted(moves, key=lambda move: move[0], reverse=True):
        body = body[:start] + replacement + body[start:]
    for start, end, replacement in reversed(edits):
        body = body[:start] + replacement + body[end:]
    return body


TRY_SCOPE_HOISTED_LOCALS = True
_TRY_HEAD_RE = re.compile(r"(?:^|\n)[ \t]*(?:try|catch\s*\([^()\n]*\))$")


class _NamedAt:

    def __init__(self, name: str, end: int) -> None:
        self._name, self._end = name, end

    def group(self, key: str) -> str | None:
        return self._name if key == "name" else None

    def end(self) -> int:
        return self._end


def _try_block_declarations(body: str, decl: re.Match[str]) -> list[tuple[int, str]] | None:
    name = f"_loc{decl.group('reg')}_"
    refs = [m.start() for m in re.finditer(rf"(?<![\w$.]){name}(?![\w$])", body) if m.start() >= decl.end()]
    if not refs:
        return None
    groups: list[int] = []
    for ref in refs:
        block = _enclosing_block(body, ref)
        while block >= 0 and not _TRY_HEAD_RE.search(body[:block].rstrip()):
            block = _enclosing_block(body, block)
        if block < 0:
            return None
        if groups and groups[-1] == block:
            continue
        if block in groups:
            return None
        groups.append(block)
    declarations = []
    for block in groups:
        close = find_matching_right(body, block)
        if close < 0:
            return None
        declaration = _common_block_declaration(body[block:close + 1], _NamedAt(name, 0))
        if declaration is None:
            return None
        declarations.append((block + declaration[0], declaration[1]))
    return declarations


def _maybe_read_unstored(body: str, name: str, start: int) -> bool:
    word = rf"(?<![\w$.]){re.escape(name)}(?![\w$])"
    refs = [m.start() for m in re.finditer(word, body) if m.start() >= start]
    if not refs:
        return False

    def stores_first(index: int) -> bool:
        line_start = body.rfind("\n", 0, index) + 1
        line_end = body.find("\n", index)
        line = body[line_start:line_end if line_end >= 0 else len(body)]
        store = re.match(rf"^[ \t]*{re.escape(name)}\s*=(?!=)\s*(.+);[ \t]*$", line)
        return bool(store) and not re.search(word, store.group(1))

    if not stores_first(refs[0]):
        return True
    block = _enclosing_block(body, refs[0])
    while block >= 0:
        close = find_matching_right(body, block)
        if close < 0:
            return True
        if refs[-1] > close:
            head = body[:block].rstrip().rsplit("\n", 1)[-1]
            if not re.search(r"^\s*if\s*\(.*\)\s*$", head):
                return _maybe_read_unstored(body, name, close + 1)
            after = re.match(r"\s*else\s*\{", body[close + 1:])
            if not after:
                return _maybe_read_unstored(body, name, close + 1)
            else_open = close + after.end()
            else_close = find_matching_right(body, else_open)
            if else_close < 0:
                return True
            first_else = next((r for r in refs if r > else_open), None)
            if first_else is None or first_else > else_close:
                return _maybe_read_unstored(body, name, else_close + 1)
            if _enclosing_block(body, first_else) != else_open or not stores_first(first_else):
                return _maybe_read_unstored(body, name, else_open + 1)
            close = else_close
            if refs[-1] <= close:
                return False
        block = _enclosing_block(body, block)
    return False


def _first_use_at_top_level(body: str, name: str, start: int) -> bool:
    first = re.search(rf"(?<![\w$.]){re.escape(name)}(?![\w$])", body[start:])
    return bool(first) and _enclosing_block(body, start + first.start()) < 0


RESCOPE_HOISTED_LOCALS = True
RESCOPE_HOISTED_SKIPS = {
    ('class_104', 'method_4034'),
    ('class_526', 'method_5381'),
    ('class_713', 'method_4023'),
}
ELSE_WRAP_HOISTED_LOCALS = True
_ENDS_RETURN_RE = re.compile(r"^[ \t]*(?:return|throw)\b[^\n]*;[ \t]*$")


def _else_wrap_hoisted_body(body: str, registers: dict[str, str], params: str = "",
                            skipped: set[str] = frozenset()) -> str | None:
    pos = 1 if body.startswith("\n") else 0
    unlisted: list[str] = []
    while True:
        other = LEADING_VAR_RE.match(body, pos)
        if not other:
            break
        reg = re.match(r"[ \t]*var\s+_loc(\d+)_\s*:", other.group(0))
        if reg and reg.group(1) not in registers:
            unlisted.append(f"_loc{reg.group(1)}_")
        pos = other.end()
    first_uses = [first.start() + pos for name in unlisted
                  if (first := re.search(rf"(?<![\w$.]){name}(?![\w$])", body[pos:]))]
    candidates: list[int] = []
    for match in re.finditer(r"^[ \t]*if\s*\(", body[pos:], re.M):
        index = pos + match.start()
        if _enclosing_block(body, index + len(match.group(0))) >= 0:
            continue
        line_end = body.find("\n", index)
        brace = re.match(r"[^\n]*\n[ \t]*\{", body[index:])
        if line_end < 0 or not brace:
            continue
        open_index = index + brace.end() - 1
        close = find_matching_right(body, open_index)
        if close < 0 or re.match(r"\s*else\b", body[close + 1:]):
            continue
        inner = body[open_index + 1:close].rstrip()
        last = inner.rsplit("\n", 1)[-1]
        if not _ENDS_RETURN_RE.match(last) or _enclosing_block(body, open_index + 1 + len(inner) - 1) != open_index:
            continue
        candidates.append(close)
    for close in reversed(candidates):
        rest = body[close + 1:]
        if not rest.strip() or any(use > close for use in first_uses):
            continue
        if any(_enclosing_block(rest, m.start()) < 0 for m in re.finditer(r"^[ \t]*var\b", rest, re.M)):
            continue
        indent = re.match(r"[ \t]*", body[body.rfind("\n", 0, close) + 1:]).group(0)
        tail = rest.rstrip()
        trailing = rest[len(tail):]
        lines = [("   " + line if line.strip() else line) for line in tail.lstrip("\n").split("\n")]
        wrapped = (body[:close + 1] + f"\n{indent}else\n{indent}{{\n" + "\n".join(lines)
                   + f"\n{indent}}}" + trailing)
        result = _uninitialize_hoisted_body(wrapped, registers, params, skipped, rescope=False)
        if result != wrapped:
            return result
    return None


_HEADER_RE = re.compile(r"^[ \t]*(?:if|else|while|for|switch|try|catch|finally|with)\b")
_CHAIN_RE = re.compile(r"\s*(?:else\b[^\n{]*|catch\s*\([^\n]*\)|finally)\s*\{")


def _rescope_hoisted_body(body: str, registers: dict[str, str], first: int, params: str = "",
                          skipped: set[str] = frozenset()) -> str | None:
    if re.search(r"^[ \t]*do[ \t]*$", body, re.M):
        return None
    pos = 1 if body.startswith("\n") else 0
    moved: dict[str, str] = {}
    kept_kinds: list[str] = []
    cut: list[tuple[int, int]] = []
    while True:
        other = LEADING_VAR_RE.match(body, pos)
        if not other:
            break
        reg = re.match(r"[ \t]*var\s+_loc(\d+)_\s*:", other.group(0))
        if reg and int(reg.group(1)) >= first:
            decl = UNINIT_DECL_RE.match(body, pos)
            if not decl or decl.end() > other.end() or reg.group(1) in skipped:
                return None
            moved[f"_loc{reg.group(1)}_"] = decl.group("ref") or decl.group("typed")
            cut.append((other.start(), other.end()))
        elif reg and reg.group(1) in registers:
            kept_kinds.append(registers[reg.group(1)])
        pos = other.end()
    text = body
    for start, end in reversed(cut):
        text = text[:start] + text[end:]
    start = pos - sum(end - begin for begin, end in cut)

    def line_of(index: int) -> tuple[int, int]:
        line_end = text.find("\n", index)
        return text.rfind("\n", 0, index) + 1, line_end if line_end >= 0 else len(text)

    def is_store(name: str, index: int) -> bool:
        line_start, line_end = line_of(index)
        store = re.match(rf"^[ \t]*{re.escape(name)}\s*=(?!=)\s*(.+);[ \t]*$", text[line_start:line_end])
        return (bool(store) and line_start + len(store.group(0)) - len(store.group(0).lstrip()) == index
                and not re.search(rf"(?<![\w$.]){re.escape(name)}(?![\w$])", store.group(1)))

    def plain_block(brace: int) -> bool:
        line_start, line_end = line_of(brace)
        if text[line_start:line_end].strip() != "{":
            return False
        header = text[:line_start].rstrip().rsplit("\n", 1)[-1]
        return not re.match(r"\s*switch\b", header)

    def statement_end(index: int) -> int:
        outer = None
        block = _enclosing_block(text, index)
        while block >= 0:
            outer = block
            block = _enclosing_block(text, block)
        if outer is None:
            line_start, line_end = line_of(index)
            if not _HEADER_RE.match(text[line_start:line_end]):
                return line_end
            brace = re.match(r"\s*\{", text[line_end:])
            if not brace:
                return -1
            outer = line_end + brace.end() - 1
        close = find_matching_right(text, outer)
        while close >= 0:
            chain = _CHAIN_RE.match(text, close + 1)
            if not chain:
                return close + 1
            close = find_matching_right(text, chain.end() - 1)
        return -1

    segments: dict[str, list[tuple[int, int | None]]] = {}
    for name in moved:
        uses = [m.start() for m in re.finditer(rf"(?<![\w$.]){re.escape(name)}(?![\w$])", text)
                if m.start() >= start]
        if not uses:
            return None
        found: list[tuple[int, int | None]] = []
        i = 0
        while i < len(uses):
            use = uses[i]
            if not is_store(name, use):
                return None
            block = _enclosing_block(text, use)
            if block >= 0:
                if not plain_block(block) or (i and uses[i - 1] > block):
                    return None
                close = find_matching_right(text, block)
                while i < len(uses) and uses[i] < close:
                    i += 1
                found.append((use, None))
                continue
            end = statement_end(use)
            i += 1
            while i < len(uses):
                if uses[i] >= end and is_store(name, uses[i]):
                    break
                if uses[i] >= end:
                    end = statement_end(uses[i])
                if end < 0:
                    return None
                i += 1
            found.append((use, end))
        if any(end is None for _, end in found) != (name[4:-1] in registers):
            return None
        segments[name] = found
    groups: list[list[int]] = []
    for begin, end in sorted((line_of(use)[0], end) for found in segments.values()
                             for use, end in found if end is not None):
        if groups and begin < groups[-1][1]:
            groups[-1][1] = max(groups[-1][1], end)
        else:
            groups.append([begin, end])
    for found in segments.values():
        for (use, end), (next_use, _) in zip(found, found[1:]):
            if end is not None and any(b <= use < e and next_use < e for b, e in groups):
                return None
    edits: list[tuple[int, int, int, str]] = []
    for begin, end in groups:
        indent = re.match(r"[ \t]*", text[begin:]).group(0)
        edits.append((begin, 0, begin, f"{indent}{{\x01\n"))
        edits.append((end, 0, end, f"\n{indent}}}\x02"))
    for name, found in segments.items():
        for use, _ in found:
            assign = re.compile(rf"{re.escape(name)}\s*=").match(text, use)
            edits.append((use, 1, assign.end(), f"var {name}:{moved[name]} ="))
    for begin, _, end, replacement in sorted(edits, reverse=True):
        text = text[:begin] + replacement + text[end:]
    lines = text.split("\n")
    inside = False
    for index, line in enumerate(lines):
        if line.endswith("\x01"):
            lines[index] = line[:-1]
            inside = True
        elif inside:
            if line.endswith("\x02"):
                lines[index] = line[:-1]
                inside = False
            elif line.strip():
                lines[index] = "   " + line
    text = "\n".join(lines)
    rest = {reg: kind for reg, kind in registers.items() if int(reg) < first}
    result = _uninitialize_hoisted_body(text, rest, params, skipped, rescope=False)
    if result == text and any(kind not in ("uint", "*") for kind in kept_kinds):
        return None
    return result


def _stores_other_typed_local(body: str, name: str, type_name: str, params: str) -> bool:
    for match in re.finditer(rf"(?<![\w$.]){re.escape(name)}\s*=(?!=)\s*(_loc\d+_|param\d+)\s*;", body):
        source = match.group(1)
        typed = re.search(rf"\bvar\s+{source}\s*:\s*(?:\*\s*=\s*null\s+as\s+)?([^=;\s]+)", body)
        typed = typed or re.search(rf"(?<![\w$]){source}\s*:\s*([^,)=\s]+)", params)
        if not typed or typed.group(1) != type_name:
            return True
    return False


_FIELD_INIT_ORDER: dict[str, list[str]] | None = None


def load_field_init_order(order: dict[str, list[str]] | None = None) -> dict[str, list[str]]:
    global _FIELD_INIT_ORDER
    if order is not None:
        _FIELD_INIT_ORDER = order
    elif _FIELD_INIT_ORDER is None:
        try:
            _FIELD_INIT_ORDER = json.loads(FIELD_INIT_ORDER_PATH.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            _FIELD_INIT_ORDER = {}
    return _FIELD_INIT_ORDER


def original_field_init_order(class_name: str | None) -> list[str]:
    if not class_name:
        return []
    table = load_field_init_order()
    if class_name in table:
        return table[class_name]
    match = re.fullmatch(r"Class_(\d+)", class_name)
    return table.get(f"class_{match.group(1)}", []) if match else []


CHAINED_FIELD_INITIALIZERS = True


def field_init_predecessor(order: list[str], name: str, expr: str = "") -> str | None:
    if order.count(name) != 1:
        return None
    index = order.index(name)
    chain = []
    rest = expr
    while CHAINED_FIELD_INITIALIZERS:
        link = re.match(r"(?:[A-Za-z_]\w*\()*([A-Za-z_]\w*) = (?!=)", rest)
        if not link:
            break
        chain.append(link.group(1))
        rest = rest[link.end():]
    if chain:
        if order[max(0, index - len(chain)):index] != chain[::-1]:
            return None
        index -= len(chain)
    if index == 0 or order.count(order[index - 1]) != 1:
        return None
    return order[index - 1]


FIELD_INIT_RECEIVER_ANCHORS = True


def field_init_anchor(ctor_body: str, name: str, indent: str | None = None) -> re.Match[str] | None:
    lead = re.escape(indent) if indent is not None else r"[ \t]+"
    receiver = r"(?:[A-Za-z_]\w*\.)*" if FIELD_INIT_RECEIVER_ANCHORS else ""
    stores = list(re.finditer(rf"(?m)^{lead}{receiver}{re.escape(name)} = [^\n]*;[ \t]*$", ctor_body))
    if indent is not None:
        stores = [m for m in stores if not ctor_body[m.start() + len(indent)].isspace()]
    return stores[0] if len(stores) == 1 else None


def field_init_is_first(order: list[str], name: str, expr: str) -> bool:
    if order.count(name) != 1:
        return False
    chain = len(re.findall(r"(?:^|[(=] ?)([A-Za-z_]\w*) = (?!=)", expr))
    return order.index(name) == chain and field_init_predecessor(order, name, expr) is None


def place_field_initializers(ctor_body: str, moved: list[tuple[str, str]], order: list[str],
                             default_indent: str | None = None):
    first = re.search(r"(?m)^([ \t]+)\S", ctor_body)
    if not first and default_indent is None:
        return ctor_body, moved
    indent = first.group(1) if first else default_indent
    pending = list(moved)
    leading: list[tuple[str, str]] = []
    if CHAINED_FIELD_INITIALIZERS and not re.search(r"\bsuper\s*\(", ctor_body):
        for item in list(pending):
            if field_init_is_first(order, *item):
                ctor_body = f"\n{indent}{item[0]} = {item[1]};" + ctor_body
                pending.remove(item)
                break
    progress = True
    while pending and progress:
        progress = False
        for item in list(pending):
            name, expr = item
            before = field_init_predecessor(order, name, expr)
            if before is None:
                continue
            store = field_init_anchor(ctor_body, before, indent)
            if store is None:
                continue
            ctor_body = ctor_body[:store.end()] + f"\n{indent}{name} = {expr};" + ctor_body[store.end():]
            pending.remove(item)
            progress = True
    for item in moved:
        if item in pending:
            leading.append(item)
    return ctor_body, leading


def add_default_constructor(text: str, class_name: str | None, class_extends: bool = False) -> str:
    if not class_name:
        return text
    class_match = re.search(rf"\bclass\s+{re.escape(class_name)}\b[^\{{]*\{{", text)
    if not class_match:
        return text
    class_open = text.find("{", class_match.start())
    class_close = find_matching_right(text, class_open)
    if class_close < 0:
        return text
    body = text[class_open + 1:class_close]
    if re.search(r"\bfunction\s+new\s*\(", body):
        return text
    indent = line_indent(text, class_open) + "   "
    super_call = "\n" + indent + "   super();" if class_extends else ""
    ctor = f"\n{indent}public function new()\n{indent}{{{super_call}\n{indent}}}\n"
    return text[:class_open + 1] + ctor + body + text[class_close:]


def add_known_interface_dynamic_members(text: str, class_name: str | None) -> str:
    if class_name not in {"class_122", "Class_122"} or "interface Class_122" not in text or "mHeldByPower" in text:
        return text
    class_match = re.search(r"\binterface\s+Class_122\b[^\{]*\{", text)
    if not class_match:
        return text
    class_open = text.find("{", class_match.start())
    indent = line_indent(text, class_open) + "   "
    return text[:class_open + 1] + f"\n{indent}var mHeldByPower:Class_5;\n" + text[class_open + 1:]


def normalize_primitive_null_defaults(text: str) -> str:
    def one(span: str) -> str:
        span = re.sub(r"(:\s*(?:UInt|Int|Float)\s*=\s*)null\b", r"\g<1>0", span)
        span = re.sub(r"(:\s*Bool\s*=\s*)null\b", r"\g<1>false", span)
        return span

    return transform_code(text, one)


NONCONSTANT_DEFAULT_RE = re.compile(
    r"^(?P<lead>\s*)(?P<name>[A-Za-z_]\w*)\s*:\s*(?P<type>Float|Int|UInt|String|Bool)\s*=\s*"
    r"(?P<value>Math\.NaN|" + re.escape(AS3_HELPER) + r"\.[A-Z_]+_VALUE|(?:[A-Z]\w*\.)?[A-Z][A-Z0-9_]+)\s*$")


def coerce_float_math_int_initializers(text: str) -> str:
    out: list[str] = []
    pos = 0
    for match in re.finditer(r"\bvar\s+[A-Za-z_]\w*\s*:\s*(?P<type>U?Int)\s*=\s*(?P<call>Math\.(?:abs|pow|sqrt)\s*\()",
                             text):
        open_index = match.end() - 1
        close = find_matching_right(text, open_index)
        if close < 0 or not re.match(r"\s*;", text[close + 1:]) or match.start() < pos:
            continue
        helper = "toUInt" if match.group("type") == "UInt" else "toInt"
        out.append(text[pos:match.start("call")])
        out.append(f"{AS3_HELPER}.{helper}({text[match.start('call'):close + 1]})")
        pos = close + 1
    out.append(text[pos:])
    return "".join(out)


def convert_nonconstant_parameter_defaults(text: str) -> str:
    out: list[str] = []
    pos = 0
    for match in re.finditer(r"\bfunction\s+[A-Za-z_]\w*\s*(?:<[^>()]*>)?\s*\(", text):
        if match.start() < pos:
            continue
        open_index = match.end() - 1
        close_index = find_matching_right(text, open_index)
        if close_index < 0:
            continue
        params = split_top_level_commas(text[open_index + 1:close_index])
        fixes: list[tuple[str, str]] = []
        for index, param in enumerate(params):
            found = NONCONSTANT_DEFAULT_RE.match(param)
            if found:
                fixes.append((found.group("name"), found.group("value")))
                params[index] = f"{found.group('lead')}?{found.group('name')}:{found.group('type')}"
        if not fixes:
            continue
        brace = re.compile(r"\s*(?::[^{;]*)?\{").match(text, close_index + 1)
        if not brace:
            continue
        indent = re.search(r"([ \t]*)[^\n]*\Z", text[:match.start()]).group(1)
        prologue = "".join(f"\n{indent}   if ({name} == null) {name} = {value};" for name, value in fixes)
        out.append(text[pos:open_index + 1])
        out.append(",".join(params))
        out.append(text[close_index:brace.end()])
        out.append(prologue)
        pos = brace.end()
    out.append(text[pos:])
    return "".join(out)


def initialize_reference_locals(text: str) -> str:
    primitive = {"Bool", "Int", "UInt", "Float", "Void", "Dynamic"}

    def repl(match: re.Match[str]) -> str:
        type_name = match.group("type").strip()
        root = type_name.split("<", 1)[0].rsplit(".", 1)[-1]
        if root in primitive:
            return match.group(0)
        name = re.escape(match.group("name"))
        if SINK_HOISTED_LOCALS and re.match(rf"[ \t]*\n[ \t]*{name}\s*=(?!=)",
                                            match.string[match.end():match.end() + 200]):
            return match.group(0)
        return f"{match.group('indent')}var {match.group('name')}:{type_name} = null;"

    return re.sub(
        r"(?m)^(?P<indent>[ \t]+)var\s+(?P<name>[A-Za-z_]\w*)\s*:\s*(?P<type>[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?(?:<[^;\n=]+>)?)\s*;",
        repl,
        text,
    )


QUALIFIED_INITIALIZERS_STAY = True


def instance_initializer_needs_constructor(expr: str) -> bool:
    if "this" in expr:
        return True
    member = r"(?<![\w.])(?:var|m)[A-Za-z0-9_]*\b" if QUALIFIED_INITIALIZERS_STAY else r"\b(?:var|m)[A-Za-z0-9_]*\b"
    if re.search(member, expr):
        return True
    if re.search(r"=\s*", expr):
        return True
    return False


HAXE_ONLY_KEYWORDS = ("cast", "untyped", "inline", "macro", "using", "extern", "enum", "abstract", "operator", "typedef",
                      "overload")


def normalize_reserved_identifiers(text: str) -> str:
    declared = [name for name in HAXE_ONLY_KEYWORDS
                if re.search(rf"\bvar\s+{name}\s*:|(?:\bfunction\b[^)]*?[(,]|\bcatch\s*\()\s*{name}\s*:", text)]

    def one(span: str) -> str:
        for name in declared:
            span = re.sub(rf"(?<!\.)\b{name}\b(?!\s*\()", f"{name}_", span)
        span = re.sub(r"\bfinal\b", "final_", span)
        span = re.sub(r"\bfinal_\s+(?=[A-Za-z_]\w*\s*:)", "final ", span)
        span = re.sub(r"(?<!\.)\bport\b(?!\s*\.\s*runtime\b)", "port_", span)
        span = re.sub(r"\bPrivateServer\.port\b", "PrivateServer.port_", span)
        return span

    text = re.sub(r'([{,]\s*)"final"(\s*:)', r'\1"final_"\2', text)
    return transform_code(text, one)


def split_multi_var_declarations(text: str) -> str:
    def one(span: str) -> str:
        return "".join(split_multi_var_line(line) for line in span.splitlines(keepends=True))

    return transform_code(text, one)


def split_multi_var_line(line: str) -> str:
    newline = "\n" if line.endswith("\n") else ""
    bare = line[:-1] if newline else line
    match = re.match(r"^(\s*(?:(?:public|private|static|override)\s+)*var\s+)(.+);(\s*)$", bare)
    if not match or "," not in match.group(2):
        return line
    prefix = match.group(1)
    parts = split_top_level_commas(match.group(2))
    if len(parts) < 2:
        return line
    declarations: list[tuple[str, str, str]] = []
    current_type = ""
    for part in parts:
        item = re.match(r"\s*([A-Za-z_]\w*)\s*(?::\s*([^=]+?))?\s*=\s*(.+)\s*$", part)
        if not item:
            return line
        name = item.group(1)
        type_name = (item.group(2) or current_type).strip()
        value = item.group(3).strip()
        if not type_name:
            return line
        current_type = type_name
        declarations.append((name, type_name, value))
    indent = re.match(r"^(\s*)", prefix).group(1)
    suffix = match.group(3)
    lines = [f"{prefix}{name}:{type_name} = {value};" for name, type_name, value in declarations]
    return ("\n" + indent).join(lines) + suffix + newline


def split_top_level_commas(text: str) -> list[str]:
    parts: list[str] = []
    start = 0
    depth = 0
    i = 0
    in_string: str | None = None
    while i < len(text):
        ch = text[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == in_string:
                in_string = None
            i += 1
            continue
        if ch in ("'", '"'):
            in_string = ch
            i += 1
            continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth = max(0, depth - 1)
        elif ch == "," and depth == 0:
            parts.append(text[start:i])
            start = i + 1
        i += 1
    parts.append(text[start:])
    return parts


def split_top_level_operator(text: str, operator: str) -> list[str]:
    parts: list[str] = []
    start = 0
    depth = 0
    i = 0
    in_string: str | None = None
    while i < len(text):
        ch = text[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == in_string:
                in_string = None
            i += 1
            continue
        if ch in ("'", '"'):
            in_string = ch
            i += 1
            continue
        if ch in "([{":
            depth += 1
            i += 1
            continue
        if ch in ")]}":
            depth = max(0, depth - 1)
            i += 1
            continue
        if depth == 0 and text.startswith(operator, i):
            parts.append(text[start:i])
            i += len(operator)
            start = i
            continue
        i += 1
    parts.append(text[start:])
    return parts


TYPED_FOR_EACH_TYPES = {"File", "XML"}


def convert_for_each_loops(span: str) -> str:
    protected_span, protected = protect_noncode(span)
    span = protected_span
    out: list[str] = []
    i = 0
    while True:
        match = re.search(r"\bfor\s+each\s*\(", span[i:])
        if not match:
            out.append(span[i:])
            return restore_noncode("".join(out), protected)
        start = i + match.start()
        paren = span.find("(", start)
        close = find_matching_right(span, paren)
        if close < 0:
            out.append(span[i:start + len("for each")])
            i = start + len("for each")
            continue
        header = span[paren + 1:close]
        parsed = parse_for_each_header(header)
        out.append(span[i:start])
        if parsed is None:
            out.append(span[start:close + 1])
        else:
            name, target = parsed
            declared = re.match(r"(?:var\s+)?\w+\s*:\s*([A-Za-z_][\w.]*)\s*$", header[:header.find(" in ")].strip())
            hoisted = _for_each_var_used_after(span, close, name) if header.lstrip().startswith("var ") else None
            if hoisted is not None:
                typed = re.search(r":\s*(.+?)\s*$", header[:header.find(" in ")])
                type_name = "Dynamic" if typed is None or typed.group(1) == "*" else typed.group(1)
                indent = line_indent(span, start)
                out.append(f"var {name}:{type_name};\n{indent}for (__each_{name} in {AS3_HELPER}.values({target}))")
                out.append(span[close + 1:hoisted + 1])
                out.append(f"\n{indent}   {name} = __each_{name};")
                i = hoisted + 1
                continue
            body_open = skip_space_right(span, close + 1)
            untyped = declared is None or declared.group(1) in {"Object", "Dynamic"}
            if declared and not untyped:
                out.append(f"for ({name} in ({AS3_HELPER}.values({target}) : Iterator<{declared.group(1)}>))")
            elif untyped and body_open < len(span) and span[body_open] == "{":
                indent = line_indent(span, start)
                store = f"var {name}:Dynamic = "
                out.append(f"for (__each_{name} in {AS3_HELPER}.values({target}))")
                out.append(span[close + 1:body_open + 1])
                out.append(f"\n{indent}   {store}__each_{name};")
                i = body_open + 1
                continue
            else:
                out.append(f"for ({name} in {AS3_HELPER}.values({target}))")
        i = close + 1


FUNCTION_START_RE = re.compile(r"\bfunction\s+(?:get\s+|set\s+)?[A-Za-z_]\w*\s*\(")


def _for_each_var_used_after(span: str, close: int, name: str) -> int | None:
    body_open = skip_space_right(span, close + 1)
    if body_open >= len(span) or span[body_open] != "{":
        return None
    body_close = find_matching_right(span, body_open)
    if body_close < 0:
        return None
    rest = span[body_close + 1:]
    next_function = FUNCTION_START_RE.search(rest)
    if next_function:
        rest = rest[:next_function.start()]
    use = re.search(rf"(?<![\w.$]){re.escape(name)}\b", rest)
    if use is None or re.search(r"\bvar\s+$", rest[:use.start()]):
        return None
    return body_open


def parse_for_each_header(header: str) -> tuple[str, str] | None:
    depth = 0
    in_at = -1
    for index in range(len(header)):
        ch = header[index]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth = max(0, depth - 1)
        elif depth == 0 and header.startswith(" in ", index):
            in_at = index
            break
    if in_at < 0:
        return None
    left = header[:in_at].strip()
    target = header[in_at + 4:].strip()
    left_match = re.match(r"(?:var\s+)?([A-Za-z_]\w*)(?:\s*:\s*.+)?$", left, flags=re.DOTALL)
    if not left_match or not target:
        return None
    return left_match.group(1), target


def convert_c_style_for_loops(text: str) -> str:
    span, protected = protect_noncode(text)
    out: list[str] = []
    i = 0
    while True:
        match = re.search(r"\bfor\s*\(", span[i:])
        if not match:
            out.append(span[i:])
            return restore_noncode("".join(out), protected)
        start = i + match.start()
        paren = span.find("(", start)
        close_paren = find_matching_right(span, paren)
        if close_paren < 0:
            out.append(span[i:start + 3])
            i = start + 3
            continue
        header = span[paren + 1:close_paren]
        parts = [part.strip() for part in header.split(";")]
        if len(parts) != 3:
            out.append(span[i:close_paren + 1])
            i = close_paren + 1
            continue
        body_open = skip_space_right(span, close_paren + 1)
        if body_open >= len(span) or span[body_open] != "{":
            out.append(span[i:close_paren + 1])
            i = close_paren + 1
            continue
        body_close = find_matching_right(span, body_open)
        if body_close < 0:
            out.append(span[i:close_paren + 1])
            i = close_paren + 1
            continue
        init, condition, increment = parts
        body = convert_c_style_for_loops(span[body_open + 1:body_close])
        indent = line_indent(span, start)
        inner_indent = indent + "   "
        loop_indent = indent + "      "
        if increment:
            body = _insert_for_increment_before_continues(body, increment, loop_indent)
        hoisted_init = ""
        init_line = f"{inner_indent}{init};\n" if init else ""
        var_init = re.match(r"var\s+([A-Za-z_]\w*)\s*:\s*([^=]+?)\s*=\s*(.+)$", init)
        if var_init and re.search(rf"\bfor\s*\(\s*{re.escape(var_init.group(1))}\s*=", span[body_close + 1:]):
            hoisted_init = f"{indent}var {var_init.group(1)}:{var_init.group(2).strip()};\n"
            init_line = f"{inner_indent}{var_init.group(1)} = {var_init.group(3).strip()};\n"
        elif re.match(r"[A-Za-z_]\w*\s*=", init):
            init_name = init.split("=", 1)[0].strip()
            init_line = f"{inner_indent}var {init_name}:Dynamic;\n{inner_indent}{init};\n"
        increment_line = f"{loop_indent}{increment};\n" if increment else ""
        replacement = (
            f"{hoisted_init}"
            "{\n"
            f"{init_line}"
            f"{inner_indent}while({condition})\n"
            f"{inner_indent}{{"
            f"{body}"
            f"\n{increment_line}"
            f"{inner_indent}}}\n"
            f"{indent}}}"
        )
        out.append(span[i:start])
        out.append(replacement)
        i = body_close + 1


def _insert_for_increment_before_continues(body: str, increment: str, loop_indent: str) -> str:
    out: list[str] = []
    last = 0
    for use in re.finditer(r"\bcontinue\s*;", body):
        own = True
        depth = 0
        for pos in range(use.start() - 1, -1, -1):
            if body[pos] == "}":
                depth += 1
            elif body[pos] == "{":
                if depth:
                    depth -= 1
                    continue
                head = body[body.rfind("\n", 0, body.rfind("\n", 0, pos)) + 1:pos]
                if _block_keyword(body, pos) in SWITCH_LOOP_KEYWORDS or re.search(r"\bfunction\b", head):
                    own = False
                    break
        if own:
            out.append(body[last:use.start()])
            out.append(f"{increment};\n{loop_indent}continue;")
            last = use.end()
    out.append(body[last:])
    return "".join(out)


def line_indent(span: str, index: int) -> str:
    line_start = span.rfind("\n", 0, index) + 1
    indent = []
    while line_start < len(span) and span[line_start] in (" ", "\t"):
        indent.append(span[line_start])
        line_start += 1
    return "".join(indent)


def restore_literal_comparisons(span: str) -> str:
    span = re.sub(rf"(==|!=)\s+{re.escape(AS3_HELPER)}\.toBool\(\"([^\"]*)\"\)", r'\1 "\2"', span)
    span = re.sub(rf"(==|!=)\s+{re.escape(AS3_HELPER)}\.toBool\(\'([^\']*)\'\)", r"\1 '\2'", span)
    span = re.sub(
        rf"((?:==|!=|<=|>=|<|>)\s*){re.escape(AS3_HELPER)}\.toBool\(([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?)\)",
        r"\1\2",
        span,
    )
    span = re.sub(
        rf"!{re.escape(AS3_HELPER)}\.logicalOr\({re.escape(AS3_HELPER)}\.hasKey\(([^,\n]+),\s*([^,\n)]+)\),\s*!\({re.escape(AS3_HELPER)}\.hasKey\(([^,\n]+)\),\s*([^\n)]+)\)\)",
        rf"!({AS3_HELPER}.hasKey(\1, \2)) || !({AS3_HELPER}.hasKey(\3, \4))",
        span,
    )
    return span


AUDITED_FUNCTION_VECTOR_FIELDS: dict[str, tuple[tuple[str, str], ...]] = {
    "class_135": (("var_13379", "method_4638"), ("var_10004", "method_4559")),
    "ArchiveLoader": (("var_14576", "method_6703"),),
    "class_697": (("var_11827", "Initialize"), ("var_7499", "Initialize")),
}


def restore_audited_function_vector_types(span: str) -> str:
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    owned_fields = AUDITED_FUNCTION_VECTOR_FIELDS.get(class_name or "")
    if not owned_fields:
        return span

    pairs: list[tuple[str, str]] = []
    method_bodies: dict[str, str] = {}
    for _field, method in owned_fields:
        if method in method_bodies:
            continue
        match = re.search(rf"\bfunction\s+{re.escape(method)}\s*\(", span)
        if match is None:
            return span
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        body_open = span.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(span, body_open) if body_open >= 0 else -1
        if body_close < 0:
            return span
        method_bodies[method] = span[body_open + 1:body_close]

    for field, method in owned_fields:
        declaration = f"var {field}:Vector.<Function>;"
        assignment = f"{field} = new Vector.<Function>();"
        if (span.count(declaration) != 1 or span.count(assignment) != 1
                or method_bodies[method].count(assignment) != 1):
            return span
        pairs.extend((
            (declaration, f"var {field}:Vector.<AS3Function>;"),
            (assignment, f"{field} = new Vector.<AS3Function>();"),
        ))
    for needle, replacement in pairs:
        span = span.replace(needle, replacement)
    return span


def restore_known_string_array_literal_comparisons(span: str) -> str:
    initializer = re.compile(
        r"\bpublic\s+static\s+var\s+var_6566\s*:\s*Array<Dynamic>\s*=\s*\[\s*"
        r'"Idle"\s*,\s*"Selected"\s*,\s*"Emote"\s*,\s*"Attack"\s*,\s*"Movement"\s*'
        r"\]\s*;"
    )
    key_declaration = re.compile(r"\bpublic\s+var\s+var_2196\s*:\s*UInt\s*;")
    if len(initializer.findall(span)) != 1 or len(key_declaration.findall(span)) != 1:
        return span
    comparison = re.compile(
        rf"{re.escape(AS3_HELPER)}\.index\(((?P<owner>class_454|Class_454))\.var_6566,\s*"
        rf"var_2196\)(?P<operator>\s*==\s*)(?P<literal>\"(?:Emote|Attack|Movement)\")"
    )
    return comparison.sub(
        lambda match: (f"(cast {match.group('owner')}.var_6566[var_2196] : String)"
                       f"{match.group('operator')}{match.group('literal')}"),
        span,
    )


AUDITED_MATH_FLOOR_NUMBER_INITIALIZERS: dict[tuple[str, str], str] = {
    ("class_494", "method_6480"): "class_727.var_7091",
    ("class_494", "method_2263"): "class_727.var_13292",
    ("class_540", "method_6480"): "class_727.var_7091",
    ("class_540", "method_2263"): "class_727.var_13292",
}


AUDITED_MATH_FLOOR_NUMBER_USES: dict[
    tuple[str, str], tuple[tuple[str, str], ...]
] = {
    ("class_50", "method_2015"): (
        (
            "var _loc10_:Float = param1 / 60 - Math.floor(param1 / 60);",
            "var _loc10_:Float = param1 / 60 - Math.ffloor(param1 / 60);",
        ),
    ),
    ("class_706", "method_6386"): (
        (
            "var _loc4_:Float = var_12422 + (var_8279.var_13462 + var_8279.var_5525) * "
            "Math.floor(_loc2_ / var_8279.var_9733);",
            "var _loc4_:Float = var_12422 + (var_8279.var_13462 + var_8279.var_5525) * "
            "Math.ffloor(_loc2_ / var_8279.var_9733);",
        ),
    ),
    ("class_706", "method_6799"): (
        (
            "var _loc5_:Float = var_12422 + (var_8279.var_13462 + var_8279.var_5525) * "
            "Math.floor(_loc3_ / var_8279.var_9733);",
            "var _loc5_:Float = var_12422 + (var_8279.var_13462 + var_8279.var_5525) * "
            "Math.ffloor(_loc3_ / var_8279.var_9733);",
        ),
    ),
    ("class_706", "method_5337"): (
        (
            "(var_8279.var_13462 + var_8279.var_5525) * "
            "Math.floor(_loc7_ / var_8279.var_9733)",
            "(var_8279.var_13462 + var_8279.var_5525) * "
            "Math.ffloor(_loc7_ / var_8279.var_9733)",
        ),
    ),
}


AUDITED_EXPRESSION_REWRITES: dict[
    tuple[str, str], tuple[tuple[str, str, int], ...]
] = {
    ("SoccerState", "method_7010"): (
        ("_loc14_ = _loc19_ <= _loc20_.var_10228.method_113(_loc20_.var_10836) + _loc12_;",
         "_loc14_ = !(_loc19_ > _loc20_.var_10228.method_113(_loc20_.var_10836) + _loc12_);", 1),
    ),
    ("VolleyBattleState", "method_7010"): (
        ("_loc14_ = _loc20_ <= _loc21_.var_10228.method_113(_loc21_.var_10836) + _loc12_;",
         "_loc14_ = !(_loc20_ > _loc21_.var_10228.method_113(_loc21_.var_10836) + _loc12_);", 1),
    ),
    ("VolleyballState", "method_7010"): (
        ("_loc13_ = _loc17_ <= _loc10_.var_10228.method_113(_loc10_.var_10836) + 160;",
         "_loc13_ = !(_loc17_ > _loc10_.var_10228.method_113(_loc10_.var_10836) + 160);", 1),
    ),
    ("class_454", "method_4451"): (
        (
            "method_610(var_3041.method_4935(Class_453.ColorType));",
            ("method_610((cast var_3041.method_4935("
             "Class_453.ColorType) : Class_674));"),
            1,
        ),
    ),
    ("class_454", "method_4503"): (
        (
            "method_610(var_3041.method_4935(Class_453.Bot));",
            ("method_610((cast var_3041.method_4935("
             "Class_453.Bot) : Class_674));"),
            1,
        ),
    ),
    ("class_454", "method_5497"): (
        (
            "method_610(var_3041.method_4935(Class_453.Taunt));",
            ("method_610((cast var_3041.method_4935("
             "Class_453.Taunt) : Class_674));"),
            1,
        ),
    ),
    ("class_454", "method_6018"): (
        (
            "method_610(var_3041.method_4935(Class_453.Legend));",
            ("method_610((cast var_3041.method_4935("
             "Class_453.Legend) : Class_674));"),
            1,
        ),
    ),
    ("class_434", "method_6746"): (
        (
            ("var_3041.method_4935(Class_431.Game_Variation)."
             "method_1352(_loc3_,_loc4_,true);"),
            ("(cast var_3041.method_4935(Class_431.Game_Variation) : Class_674)."
             "method_1352(_loc3_,_loc4_,true);"),
            1,
        ),
    ),
    ("class_434", "method_3453"): (
        (
            ("var_3041.method_4935(Class_431.Game_ScoringType)."
             "method_1352(_loc4_,_loc5_);"),
            ("(cast var_3041.method_4935(Class_431.Game_ScoringType) : Class_674)."
             "method_1352(_loc4_,_loc5_);"),
            1,
        ),
    ),
    ("class_666", "method_1576"): (
        (
            (f"PaperDoll.method_180(var_1313,{AS3_HELPER}.index("
             "Class_120.var_14403, param1),false);"),
            (f"PaperDoll.method_180(var_1313,(cast {AS3_HELPER}.index("
             "Class_120.var_14403, param1) : Class_120),false);"),
            1,
        ),
    ),
    ("class_554", "OnInitDisplay"): (
        (
            f"{AS3_HELPER}.index(var_4328, var_3450).Display();",
            (f"(cast {AS3_HELPER}.index(var_4328, var_3450) : "
             "ScreenBase).Display();"),
            1,
        ),
        (
            'Std.string("Header" + Class_49.method_5298(var_3450))',
            '"Header" + Class_49.method_5298(var_3450)',
            1,
        ),
    ),
    ("class_625", "OnRefreshScreen"): (
        (
            "Std.string(owner.var_10500)",
            f"{AS3_HELPER}.coerceUIntString(owner.var_10500)",
            1,
        ),
        (
            ("Std.string(Class_50.method_4979(port.runtime.As3.toInt("
             "port.runtime.As3.toUInt(owner.var_13846 - owner.var_5583)),"
             "false,10) + \" / \" + Class_50.method_4979("
             "port.runtime.As3.toInt(port.runtime.As3.toUInt("
             "owner.var_7677 - owner.var_5583)),false,10) + \" XP\")"),
            ("Class_50.method_4979(port.runtime.As3.toInt("
             "port.runtime.As3.toUInt(owner.var_13846 - owner.var_5583)),"
             "false,10) + \" / \" + Class_50.method_4979("
             "port.runtime.As3.toInt(port.runtime.As3.toUInt("
             "owner.var_7677 - owner.var_5583)),false,10) + \" XP\""),
            1,
        ),
    ),
    ("GameCore", "method_8678"): (
        (
            "Std.string(Context3DTextureFormat.BGRA_PACKED)",
            "(cast Context3DTextureFormat.BGRA_PACKED : String)",
            1,
        ),
    ),
    ("class_194", "method_4689"): (
        (
            f"if(({AS3_HELPER}.isType(param1, Class_123)))",
            "if(Std.isOfType(param1, Class_123))",
            1,
        ),
        (
            f"return {AS3_HELPER}.asType(param1, Class_123);",
            "return cast param1;",
            1,
        ),
    ),
    ("class_370", "method_6732"): (
        (
            f"return {AS3_HELPER}.stringSubstr(_loc3_, 0,_loc3_.length - 2);",
            "return _loc3_.substr(0,_loc3_.length - 2);",
            1,
        ),
    ),
    ("class_21", "method_4533"): (
        (
            f"{AS3_HELPER}.valueIndexOf(GameApp.var_7247, var_6800)",
            "GameApp.var_7247.indexOf(var_6800)",
            1,
        ),
    ),
    ("class_375", "method_4093"): (
        (
            (f"var_10593 = {AS3_HELPER}.logicalOr({AS3_HELPER}.logicalOr(var_12421 == 0, "
             "var_6921), Class_687.var_11971 == 0);"),
            ("var_10593 = var_12421 == 0 || var_6921 || "
             "Class_687.var_11971 == 0;"),
            1,
        ),
    ),
    ("ScreenManager", "method_2726"): (
        (
            ("ScreenManager.var_3184.var_3507 = "
             f"{AS3_HELPER}.logicalOr(ScreenManager.var_3184.var_3507, param1);"),
            ("ScreenManager.var_3184.var_3507 = "
             "ScreenManager.var_3184.var_3507 || param1;"),
            1,
        ),
    ),
    ("class_377", "method_3476"): (
        (
            'return " " + ("" + param1.var_5566);',
            'return " " + param1.var_5566;',
            1,
        ),
    ),
    ("class_415", "method_8430"): (
        (
            f"_loc4_ = {AS3_HELPER}.index(var_1366, _loc3_).var_219.parent;",
            (f"_loc4_ = cast({AS3_HELPER}.index(var_1366, "
             "_loc3_).var_219.parent);"),
            1,
        ),
        (
            f'{AS3_HELPER}.valueIndexOf(_loc7_, "a_Eyes")',
            '_loc7_.indexOf("a_Eyes")',
            1,
        ),
        (
            f'{AS3_HELPER}.valueIndexOf(_loc7_, "a_Mouth")',
            '_loc7_.indexOf("a_Mouth")',
            1,
        ),
        (
            (f"{AS3_HELPER}.index(var_1366, _loc3_).var_12837."
             "var_6514.remove(_loc7_);"),
            (f"(cast {AS3_HELPER}.index(var_1366, _loc3_).var_12837."
             "var_6514 : StringMap<Dynamic>).remove(_loc7_);"),
            1,
        ),
    ),
    ("class_317", "method_4029"): (
        (
            (f"_loc2_.var_11420 = {AS3_HELPER}.numeric('-', "
             "_loc2_.var_11420, _loc5_.GetSize());"),
            "_loc2_.var_11420 -= _loc5_.GetSize();",
            1,
        ),
    ),
    ("class_458", "method_3828"): (
        (
            f"{AS3_HELPER}.isType(_loc4_, GlowFilter)",
            "Std.isOfType(_loc4_, GlowFilter)",
            1,
        ),
        (
            "_loc5_ = _loc4_;",
            "_loc5_ = cast(_loc4_);",
            1,
        ),
    ),
    ("class_666", "method_490"): (
        (
            f"{AS3_HELPER}.isType(var_6263, class_526)",
            "Std.isOfType(var_6263, class_526)",
            1,
        ),
    ),
    ("class_698", "method_1813"): (
        (
            f"{AS3_HELPER}.isType(var_6263, class_525)",
            "Std.isOfType(var_6263, class_525)",
            1,
        ),
    ),
    ("class_278", "method_3682"): (
        (
            f'{AS3_HELPER}.compare(param2, "!=", 0)',
            "param2 != 0",
            1,
        ),
    ),
    ("class_726", "method_5695"): (
        (
            f"{AS3_HELPER}.isType(param2, class_123)",
            "Std.isOfType(param2, class_123)",
            1,
        ),
    ),
    ("class_353", "method_46"): (
        (
            f"{AS3_HELPER}.isType(param3, class_123)",
            "Std.isOfType(param3, class_123)",
            1,
        ),
    ),
    ("class_155", "method_4030"): (
        (
            f"{AS3_HELPER}.isType(param1, class_123)",
            "Std.isOfType(param1, class_123)",
            1,
        ),
    ),
    ("class_697", "method_1305"): (
        (
            f"{AS3_HELPER}.isType(param2, class_526)",
            "Std.isOfType(param2, class_526)",
            1,
        ),
    ),
    ("class_457", "OnClearScreen"): (
        (
            f"{AS3_HELPER}.isType(var_12672, TextField)",
            "Std.isOfType(var_12672, TextField)",
            1,
        ),
    ),
    ("ArchiveFile", "method_6183"): (
        (
            f"{AS3_HELPER}.isType(_loc1_, Bitmap)",
            "Std.isOfType(_loc1_, Bitmap)",
            1,
        ),
    ),
    ("class_634", "method_2944"): (
        (
            f"{AS3_HELPER}.isType(_loc1_, Bitmap)",
            "Std.isOfType(_loc1_, Bitmap)",
            1,
        ),
    ),
    ("class_259", "method_5156"): (
        (
            f"{AS3_HELPER}.isType(param1, MovieClip)",
            "Std.isOfType(param1, MovieClip)",
            1,
        ),
    ),
    ("class_74", "method_5356"): (
        (
            f"{AS3_HELPER}.isType(_loc9_, Shape)",
            "Std.isOfType(_loc9_, Shape)",
            1,
        ),
        (
            f"{AS3_HELPER}.isType(_loc9_, Sprite)",
            "Std.isOfType(_loc9_, Sprite)",
            1,
        ),
        (
            "Class_74.method_8965(_loc9_,param1,param2,param3,param4);",
            "Class_74.method_8965(cast _loc9_,param1,param2,param3,param4);",
            1,
        ),
        (
            "Class_74.method_5356(_loc9_,param2,param3,param4);",
            "Class_74.method_5356(cast _loc9_,param2,param3,param4);",
            1,
        ),
    ),
    ("class_112", "method_3249"): (
        (
            f"{AS3_HELPER}.isType(param1, ControllerEvent)",
            "Std.isOfType(param1, ControllerEvent)",
            1,
        ),
    ),
    ("class_417", "method_7408"): (
        (
            'method_1467(Std.string("Lose"),8)',
            'method_1467("Lose",8)',
            1,
        ),
        (
            ("var_3685.method_1467(Std.string(\"Notch\" + "
             "Class_49.method_5298(port.runtime.As3.toUInt(param1 - 1))))"),
            ("var_3685.method_1467(\"Notch\" + "
             "Class_49.method_5298(port.runtime.As3.toUInt(param1 - 1)))"),
            1,
        ),
    ),
    ("class_708", "method_1722"): (
        ("var_14255.method_1467(Std.string(param1))", "var_14255.method_1467(param1)", 1),
    ),
    ("class_455", "method_1728"): (
        ("var_5923.method_4016(Std.string(param1))", "var_5923.method_4016(param1)", 1),
    ),
    ("class_418", "method_3968"): (
        ("var_2112.method_4016(Std.string(param1))", "var_2112.method_4016(param1)", 1),
    ),
    ("class_690", "method_650"): (
        ("var_279.method_6032(Std.string(param1))", "var_279.method_6032(param1)", 1),
    ),
    ("class_329", "method_4765"): (
        ("Std.string(param1)", "param1", 1),
        ("Std.string(param2)", "param2", 1),
        ("Std.string(param3)", "param3", 1),
    ),
    ("class_706", "method_8028"): (
        ("Std.string(param1)", "param1", 1),
        ("Std.string(param2)", "param2", 1),
        ("Std.string(param3)", "param3", 1),
    ),
    ("class_329", "method_2746"): (
        ("Std.string(param1)", "param1", 2),
        ("Std.string(param2)", "param2", 2),
        ("Std.string(param3)", "param3", 2),
    ),
    ("class_329", "method_2238"): (
        ("Std.string(param1)", "param1", 1),
        ("Std.string(param2)", "param2", 1),
    ),
    ("class_527", "method_2827"): (
        ("Std.string(param1)", "param1", 2),
    ),
    ("class_690", "method_2565"): (
        ("var_6308.method_1467(Std.string(param1))", "var_6308.method_1467(param1)", 1),
    ),
    ("class_690", "method_3882"): (
        ("var_14490.method_4016(Std.string(param1))", "var_14490.method_4016(param1)", 1),
    ),
    ("class_664", "method_7868"): (
        ("Std.string(param1.mBaseWeapon1)", "param1.mBaseWeapon1", 1),
        ("Std.string(param1.mBaseWeapon2)", "param1.mBaseWeapon2", 1),
    ),
    ("class_199", "method_7694"): (
        ("Std.string(owner.var_12909.mName)", "owner.var_12909.mName", 1),
    ),
    ("class_460", "method_2827"): (
        ("Std.string(param1)", "param1", 1),
        ("Std.string(param4)", "param4", 1),
        ("Std.string(param5)", "param5", 1),
    ),
    ("class_329", "method_5372"): (
        ("Std.string(param2)", "param2", 2),
    ),
    ("class_533", "method_6366"): (
        ("var_2986.method_1467(Std.string(param1),8)", "var_2986.method_1467(param1,8)", 1),
    ),
    ("class_60", "method_3580"): (
        ("var_5408.method_6032(Std.string(param2))", "var_5408.method_6032(param2)", 1),
    ),
    ("class_700", "method_1703"): (
        ("var_3563.method_6032(Std.string(_loc2_))", "var_3563.method_6032(_loc2_)", 1),
    ),
    ("class_390", "UpdateHighlighter"): (
        ("Std.string(_loc3_.mType.var_9717)", "_loc3_.mType.var_9717", 1),
    ),
    ("class_385", "method_6386"): (
        ("_loc1_.method_1467(Std.string(method_7316()))", "_loc1_.method_1467(method_7316())", 1),
    ),
    ("class_674", "method_5114"): (
        ("var_3046.method_4016(Std.string(var_1544))", "var_3046.method_4016(var_1544)", 1),
    ),
    ("class_480", "method_7328"): (
        ("Std.string(var_4464.var_6638)", "var_4464.var_6638", 1),
    ),
    ("class_515", "method_5683"): (
        (
            "var_7965.method_4016(Std.string(var_3899.var_6925))",
            f"var_7965.method_4016({AS3_HELPER}.coerceUIntString(var_3899.var_6925))",
            1,
        ),
    ),
    ("SubScreenEventTimedEvent", "RefreshColorProgress"): (
        (
            'mColorSchemeCounter.method_4016(Std.string("" + _loc2_ + " / " + "45"))',
            'mColorSchemeCounter.method_4016("" + _loc2_ + " / " + "45")',
            1,
        ),
    ),
    ("class_329", "method_4067"): (
        ("var_541.method_1467(Std.string(var_3479),8)", "var_541.method_1467(var_3479,8)", 1),
    ),
    ("class_524", "method_8312"): (
        (
            'Class_714.method_8170(var_10540,Std.string("" + param1),Localization.var_12101)',
            'Class_714.method_8170(var_10540,"" + param1,Localization.var_12101)',
            1,
        ),
    ),
    ("class_439", "method_68"): (
        (
            f'{AS3_HELPER}.stringReplace(_loc2_, param1," <font color=\\"#397FC7\\"><u><a href=\\"$1\\">$1</a></u></font> ")',
            '_loc2_.replace(param1," <font color=\\"#397FC7\\"><u><a href=\\"$1\\">$1</a></u></font> ")',
            1,
        ),
    ),
    ("class_482", "method_68"): (
        (
            f'{AS3_HELPER}.stringReplace(_loc2_, param1," <font color=\\"#397FC7\\"><u><a href=\\"$1\\">$1</a></u></font> ")',
            '_loc2_.replace(param1," <font color=\\"#397FC7\\"><u><a href=\\"$1\\">$1</a></u></font> ")',
            1,
        ),
    ),
    ("ScreenPopUpLegal", "method_68"): (
        (
            f'{AS3_HELPER}.stringReplace(_loc2_, param1," <u><a href=\\"$1\\">$1</a></u> ")',
            '_loc2_.replace(param1," <u><a href=\\"$1\\">$1</a></u> ")',
            1,
        ),
    ),
    ("class_593", "method_8983"): (
        (
            f"{AS3_HELPER}.stringReplace(class_593.var_15390, param1,param2)",
            "class_593.var_15390.replace(param1,param2)",
            1,
        ),
    ),
    ("class_457", "method_5958"): (
        (
            f'{AS3_HELPER}.stringReplace(_loc7_, _loc4_,"")',
            '_loc7_.replace(_loc4_,"")',
            1,
        ),
    ),
    ("class_406", "method_5255"): (
        (
            f'{AS3_HELPER}.stringReplace(_loc2_, param1,"$1")',
            '_loc2_.replace(param1,"$1")',
            1,
        ),
        (
            f'{AS3_HELPER}.stringReplace(_loc2_, param1,"$1$1")',
            '_loc2_.replace(param1,"$1$1")',
            1,
        ),
    ),
    ("class_418", "method_2099"): (
        (
            f'{AS3_HELPER}.stringReplace(_loc5_, _loc2_," ")',
            '_loc5_.replace(_loc2_," ")',
            1,
        ),
        (
            f'{AS3_HELPER}.stringReplace(_loc6_, _loc2_,"")',
            '_loc6_.replace(_loc2_,"")',
            1,
        ),
        (
            f'{AS3_HELPER}.valueIndexOf(_loc2_, " ")',
            '_loc2_.indexOf(" ")',
            1,
        ),
        (
            f"{AS3_HELPER}.stringSubstr(_loc2_, 1)",
            "_loc2_.substr(1)",
            1,
        ),
        (
            f"{AS3_HELPER}.stringSubstr(_loc2_, 0,_loc2_.length - 1)",
            "_loc2_.substr(0,_loc2_.length - 1)",
            1,
        ),
    ),
    ("class_604", "method_5669"): (
        (
            f'{AS3_HELPER}.stringReplace(_loc7_, _loc4_," ")',
            '_loc7_.replace(_loc4_," ")',
            1,
        ),
        (
            f'{AS3_HELPER}.stringReplace(_loc8_, _loc4_,"")',
            '_loc8_.replace(_loc4_,"")',
            1,
        ),
        (
            f'{AS3_HELPER}.valueIndexOf(_loc4_, " ")',
            '_loc4_.indexOf(" ")',
            1,
        ),
        (
            f"{AS3_HELPER}.stringSubstr(_loc4_, 1)",
            "_loc4_.substr(1)",
            1,
        ),
        (
            f"{AS3_HELPER}.stringSubstr(_loc4_, 0,_loc4_.length - 1)",
            "_loc4_.substr(0,_loc4_.length - 1)",
            1,
        ),
    ),
    ("class_592", "method_2169"): (
        (
            f"{AS3_HELPER}.stringSubstr(param1, 0,_loc2_ - _loc3_)",
            "param1.substr(0,_loc2_ - _loc3_)",
            1,
        ),
    ),
    ("class_700", "method_5033"): (
        (
            'param2.method_4016(Std.string("" + param1))',
            'param2.method_4016("" + param1)',
            1,
        ),
    ),
    ("class_403", "method_2003"): (
        (
            "Class_714.method_8170(var_5918,Std.string(Class_50.method_4979(param2,false,10)),Localization.FONT_16_SLIMBOLD)",
            "Class_714.method_8170(var_5918,Class_50.method_4979(param2,false,10),Localization.FONT_16_SLIMBOLD)",
            1,
        ),
    ),
    ("SubScreenEventTimedEvent", "OnRefreshScreen"): (
        (
            "mOwnedTickets.method_4016(Std.string(Class_50.method_4979(owner.method_3669(),false,10)))",
            "mOwnedTickets.method_4016(Class_50.method_4979(owner.method_3669(),false,10))",
            1,
        ),
    ),
    ("ScreenBase", "method_1053"): (
        ("var_2459.method_1467(Std.string(param1))", "var_2459.method_1467(param1)", 1),
    ),
    ("PaperDoll", "method_1467"): (
        (
            "var_5070.method_1467(Std.string(param1),param2,param3,param4)",
            "var_5070.method_1467(param1,param2,param3,param4)",
            1,
        ),
    ),
    ("class_479", "method_968"): (
        (
            "param1.method_1467(Std.string(param2.var_12788),8)",
            "param1.method_1467(param2.var_12788,8)",
            1,
        ),
    ),
    ("class_663", "method_6445"): (
        (
            "var_5653.method_1467(Std.string(var_235))",
            f"var_5653.method_1467({AS3_HELPER}.coerceUIntString(var_235))",
            1,
        ),
    ),
    ("class_618", "method_2311"): (
        (
            "var_338.method_1467(Std.string(var_13270))",
            f"var_338.method_1467({AS3_HELPER}.coerceUIntString(var_13270))",
            1,
        ),
    ),
    ("class_672", "method_7982"): (
        ("var_10940.method_6032(Std.string(param1))", "var_10940.method_6032(param1)", 1),
    ),
    ("ScreenLevelSelect", "method_1941"): (
        ("_loc2_.method_1467(Std.string(_loc4_))", "_loc2_.method_1467(_loc4_)", 1),
    ),
    ("class_376", "method_8135"): (
        ("var_12712.method_6032(Std.string(param2))", "var_12712.method_6032(param2)", 1),
    ),
    ("class_416", "method_2827"): (
        (
            ('Class_714.method_9120(Class_51.method_2013(panelClip,"am_DialogText"),'
             'Std.string(param1))'),
            'Class_714.method_9120(Class_51.method_2013(panelClip,"am_DialogText"),param1)',
            1,
        ),
    ),
    ("class_440", "method_6837"): (
        ("var_10490.method_4016(Std.string(param2))", "var_10490.method_4016(param2)", 1),
    ),
    ("class_458", "method_8115"): (
        ("Class_714.method_9120(var_4747,Std.string(param1))", "Class_714.method_9120(var_4747,param1)", 1),
    ),
    ("class_532", "method_8120"): (
        ("Class_714.method_9120(var_7892,Std.string(param1))", "Class_714.method_9120(var_7892,param1)", 1),
    ),
    ("class_534", "method_4299"): (
        ("var_13426.method_1467(Std.string(_loc2_),true,true)", "var_13426.method_1467(_loc2_,true,true)", 1),
    ),
    ("class_552", "method_4052"): (
        ("_loc9_.method_1467(Std.string(param4))", "_loc9_.method_1467(param4)", 1),
    ),
    ("class_552", "method_430"): (
        ("_loc8_.method_1467(Std.string(param3))", "_loc8_.method_1467(param3)", 1),
    ),
    ("class_557", "method_1588"): (
        (
            ('Class_714.method_9120(Class_51.method_2013(var_9360.clip,"am_Header"),'
             'Std.string(param1))'),
            'Class_714.method_9120(Class_51.method_2013(var_9360.clip,"am_Header"),param1)',
            1,
        ),
    ),
    ("class_624", "method_4491"): (
        ("var_4961.method_1467(Std.string(param1))", "var_4961.method_1467(param1)", 1),
    ),
    ("class_624", "method_9064"): (
        ("var_541.method_1467(Std.string(_loc2_),8)", "var_541.method_1467(_loc2_,8)", 1),
    ),
    ("class_663", "method_6272"): (
        (f"param1.x = {AS3_HELPER}.numeric('-', param1.x, param1.width / 2)",
         "param1.x -= param1.width / 2", 1),
        (f"param1.y = {AS3_HELPER}.numeric('-', param1.y, param1.height / 2)",
         "param1.y -= param1.height / 2", 1),
    ),
    ("class_689", "method_2847"): (
        (f"_loc5_.x = {AS3_HELPER}.numeric('-', _loc5_.x, param2.width * _loc5_.scaleX * 0.5)",
         "_loc5_.x -= param2.width * _loc5_.scaleX * 0.5", 1),
        (f"_loc5_.y = {AS3_HELPER}.numeric('-', _loc5_.y, param2.height * _loc5_.scaleY * 0.5)",
         "_loc5_.y -= param2.height * _loc5_.scaleY * 0.5", 1),
    ),
    ("class_689", "method_7916"): (
        (f"_loc6_.x = {AS3_HELPER}.numeric('-', _loc6_.x, _loc6_.bitmapData.width * _loc6_.scaleX * 0.5)",
         "_loc6_.x -= _loc6_.bitmapData.width * _loc6_.scaleX * 0.5", 1),
        (f"_loc6_.y = {AS3_HELPER}.numeric('-', _loc6_.y, _loc6_.bitmapData.height * _loc6_.scaleY * 0.5)",
         "_loc6_.y -= _loc6_.bitmapData.height * _loc6_.scaleY * 0.5", 1),
    ),
    ("class_703", "method_1354"): (
        (f"var_1002 = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('-', var_1002, _loc1_))",
         "var_1002 -= _loc1_", 1),
        (f"var_2492 = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('-', var_2492, _loc1_))",
         "var_2492 -= _loc1_", 1),
    ),
    ("class_697", "method_4875"): (
        ("Class_714.method_9120(_loc5_,Std.string(param2))", "Class_714.method_9120(_loc5_,param2)", 1),
    ),
    ("class_714", "method_7662"): (
        (
            "Class_714.method_9120(param1,Std.string(param2),false,param5)",
            "Class_714.method_9120(param1,param2,false,param5)",
            1,
        ),
    ),
    ("class_714", "method_8993"): (
        (
            "Class_714.method_8170(param1,Std.string(param2),param3)",
            "Class_714.method_8170(param1,param2,param3)",
            1,
        ),
    ),
    ("class_139", "method_2160"): (
        (
            f"_loc2_ = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('*', _loc2_, _loc3_.scaleX));",
            "_loc2_ *= _loc3_.scaleX;",
            1,
        ),
    ),
    ("class_139", "method_7294"): (
        (
            f"_loc2_ = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('*', _loc2_, _loc3_.scaleY));",
            "_loc2_ *= _loc3_.scaleY;",
            1,
        ),
    ),
    ("class_171", "method_5535"): (
        (
            f"var_11420 = {AS3_HELPER}.toInt({AS3_HELPER}.numeric('-', var_11420, "
            f"{AS3_HELPER}.toInt(_loc2_.GetSize())));",
            f"var_11420 -= {AS3_HELPER}.toInt(_loc2_.GetSize());",
            1,
        ),
    ),
    ("class_171", "method_2704"): (
        (
            f"var_11420 = {AS3_HELPER}.toInt({AS3_HELPER}.numeric('-', var_11420, "
            f"{AS3_HELPER}.toInt(_loc4_.GetSize())));",
            f"var_11420 -= {AS3_HELPER}.toInt(_loc4_.GetSize());",
            1,
        ),
    ),
    ("class_731", "method_1789"): (
        (
            f"var _loc2_:String = {AS3_HELPER}.coerceString(method_1824(param1));",
            "var _loc2_:String = method_1824(param1);",
            1,
        ),
    ),
    ("class_96", "method_1789"): (
        (
            f"var _loc2_:String = {AS3_HELPER}.coerceString(method_1824(param1));",
            "var _loc2_:String = method_1824(param1);",
            1,
        ),
    ),
    ("class_457", "method_7324"): (
        (
            f"var _loc3_:String = {AS3_HELPER}.coerceString(Class_51.method_298());",
            "var _loc3_:String = Class_51.method_298();",
            1,
        ),
    ),
    ("ControllerMappingType", "method_7203"): (
        (
            f"{AS3_HELPER}.setIndex(var_2970.h, param2, param3);",
            f"{AS3_HELPER}.setIndex((cast var_2970 : IntMap<Dynamic>).h, param2, param3);",
            1,
        ),
        (
            f"{AS3_HELPER}.setIndex(var_8548.h, param2, param3);",
            f"{AS3_HELPER}.setIndex((cast var_8548 : IntMap<Dynamic>).h, param2, param3);",
            1,
        ),
    ),
    ("ControllerMappingType", "method_5841"): (
        (
            f"return {AS3_HELPER}.index(var_2970.h, param2);",
            (f"return (cast {AS3_HELPER}.index((cast var_2970 : "
             "IntMap<Dynamic>).h, param2) : Array<Dynamic>);"),
            1,
        ),
        (
            f"return {AS3_HELPER}.index(var_8548.h, param2);",
            (f"return (cast {AS3_HELPER}.index((cast var_8548 : "
             "IntMap<Dynamic>).h, param2) : Array<Dynamic>);"),
            1,
        ),
    ),
    ("ControllerMappingType", "method_6672"): (
        (
            f"_loc8_ = {AS3_HELPER}.index(param1.h, _loc7_);",
            (f"_loc8_ = (cast {AS3_HELPER}.index("
             "param1.h, _loc7_) : Array<Dynamic>);"),
            1,
        ),
    ),
    ("ControllerMappingType", "method_8682"): (
        (
            f"_loc8_ = {AS3_HELPER}.index(param1.var_8548.h, _loc7_);",
            (f"_loc8_ = (cast {AS3_HELPER}.index((cast param1.var_8548 : "
             "IntMap<Dynamic>).h, _loc7_) : Array<Dynamic>);"),
            1,
        ),
        (
            f"_loc9_ = {AS3_HELPER}.index(param2.var_8548.h, _loc7_);",
            (f"_loc9_ = (cast {AS3_HELPER}.index((cast param2.var_8548 : "
             "IntMap<Dynamic>).h, _loc7_) : Array<Dynamic>);"),
            1,
        ),
    ),
    ("ControllerMappingType", "method_4012"): (
        (
            f"if({AS3_HELPER}.index(_loc3_.h, _loc8_) != null)",
            f"if((cast {AS3_HELPER}.index(_loc3_.h, _loc8_) : Array<Dynamic>) != null)",
            1,
        ),
        (
            (f"_loc9_ = {AS3_HELPER}.toInt({AS3_HELPER}.valueIndexOf("
             f"{AS3_HELPER}.index(_loc3_.h, _loc8_), param2));"),
            (f"_loc9_ = {AS3_HELPER}.toInt((cast {AS3_HELPER}.index("
             "_loc3_.h, _loc8_) : Array<Dynamic>).indexOf(param2));"),
            1,
        ),
        (
            (f"_loc9_ < {AS3_HELPER}.toInt({AS3_HELPER}.index("
             "_loc3_.h, _loc8_).length)"),
            (f"_loc9_ < {AS3_HELPER}.toInt((cast {AS3_HELPER}.index("
             "_loc3_.h, _loc8_) : Array<Dynamic>).length)"),
            1,
        ),
        (
            (f"{AS3_HELPER}.arraySplice({AS3_HELPER}.index("
             "_loc3_.h, _loc8_), _loc9_,1);"),
            (f"(cast {AS3_HELPER}.index(_loc3_.h, _loc8_) : "
             "Array<Dynamic>).splice(_loc9_,1);"),
            1,
        ),
    ),
    ("ControllerMappingType", "method_5498"): (
        (
            f"if({AS3_HELPER}.index(_loc4_.h, param2) == null)",
            f"if((cast {AS3_HELPER}.index(_loc4_.h, param2) : Array<Dynamic>) == null)",
            1,
        ),
        (
            f"{AS3_HELPER}.index(_loc4_.h, param2).push(param3);",
            (f"(cast {AS3_HELPER}.index(_loc4_.h, param2) : "
             "Array<Dynamic>).push(param3);"),
            1,
        ),
    ),
    ("class_417", "method_4234"): (
        (
            f"var_1144 = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('+', var_1144, "
            "owner.var_2172 * 1000 / 24 / 600));",
            "var_1144 += owner.var_2172 * 1000 / 24 / 600;",
            1,
        ),
    ),
    ("ItemSpawn", "method_3131"): (
        (
            f"_loc2_ = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('+', _loc2_, _loc3_));",
            "_loc2_ += _loc3_;",
            1,
        ),
        (
            (f"param1 = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('-', param1, "
             "_loc2_ * Class_51.var_12355));"),
            "param1 -= _loc2_ * Class_51.var_12355;",
            1,
        ),
    ),
    ("SubScreenEventTimedEvent", "GetEventDailyMissionAtIndex"): (
        (
            (f"param1 = {AS3_HELPER}.toUInt({AS3_HELPER}.numeric('+', param1, "
             f"{AS3_HELPER}.toUInt(mEventDailiesPageIndex * 4)));"),
            f"param1 += {AS3_HELPER}.toUInt(mEventDailiesPageIndex * 4);",
            1,
        ),
    ),
    ("StoreType", "method_2100"): (
        (
            (f"var_575 = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('+', var_575, "
             "((_loc10_) ? 1 : 0) * Class_50.method_9093(10000,0,param6)));"),
            "var_575 += ((_loc10_) ? 1 : 0) * Class_50.method_9093(10000,0,param6);",
            1,
        ),
        (
            (f"var_575 = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('+', var_575, "
             "_loc11_ * Class_50.method_9093(1000,0,param6)));"),
            "var_575 += _loc11_ * Class_50.method_9093(1000,0,param6);",
            1,
        ),
        (
            (f"var_575 = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('+', var_575, "
             "((_loc12_) ? 1 : 0) * Class_50.method_9093(10000,100,param6)));"),
            "var_575 += ((_loc12_) ? 1 : 0) * Class_50.method_9093(10000,100,param6);",
            1,
        ),
        *tuple(
            (
                f"var_575 = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('+', var_575, {rhs}));",
                f"var_575 += {rhs};",
                1,
            )
            for rhs in (
                "20 * var_12418",
                "(var_11307) ? 350 : 0",
                "(_loc13_) ? 0 : 0",
                "285 * _loc15_",
                "(_loc14_) ? 0 : 0",
                "280 * _loc17_",
                "285 * _loc16_",
                "(_loc18_) ? 0 : 0",
                "_loc7_",
            )
        ),
    ),
    ("class_577", "method_8895"): (
        (
            f"var_10616 = {AS3_HELPER}.toInt({AS3_HELPER}.numeric('+', var_10616, param1));",
            "var_10616 += param1;",
            1,
        ),
    ),
    ("GameCore", "method_3044"): (
        (
            f"var_7121 = {AS3_HELPER}.toInt({AS3_HELPER}.numeric('%', var_7121, 4));",
            "var_7121 %= 4;",
            1,
        ),
    ),
    ("GameCore", "method_1170"): (
        (
            f"_loc3_ = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('-', _loc3_, param2.y));",
            "_loc3_ -= param2.y;",
            1,
        ),
    ),
    ("GameCore", "method_1454"): (
        (
            f"_loc3_ = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('-', _loc3_, param2.x));",
            "_loc3_ -= param2.x;",
            1,
        ),
    ),
    ("class_609", "method_5303"): (
        (
            f"var_8917 = {AS3_HELPER}.toUInt({AS3_HELPER}.numeric('%', var_8917, 12));",
            "var_8917 %= 12;",
            1,
        ),
    ),
    ("class_614", "method_5303"): (
        (
            f"var_8917 = {AS3_HELPER}.toUInt({AS3_HELPER}.numeric('%', var_8917, 4));",
            "var_8917 %= 4;",
            1,
        ),
    ),
    ("class_555", "method_8665"): (
        (
            f"var_13036 = {AS3_HELPER}.toUInt({AS3_HELPER}.numeric('+', var_13036, param1));",
            "var_13036 += param1;",
            1,
        ),
    ),
    ("MovingPlatform", "method_814"): (
        (
            f"{AS3_HELPER}.toUInt({AS3_HELPER}.toInt((Math.floor(_loc2_ + 1e-7))) % "
            f"{AS3_HELPER}.toInt(var_13334.length))",
            f"{AS3_HELPER}.toUInt({AS3_HELPER}.toInt((Math.floor(_loc2_ + 1e-7)))) % "
            f"{AS3_HELPER}.toInt(var_13334.length)",
            1,
        ),
    ),
    ("class_394", "Tick"): (
        (
            f"_loc5_.alpha = {AS3_HELPER}.numeric('-', _loc5_.alpha, _loc5_.var_4538 * _loc1_);",
            "_loc5_.alpha -= _loc5_.var_4538 * _loc1_;",
            1,
        ),
    ),
    ("class_49", "parseFloat"): (
        (
            "return parseFloat(param1);",
            'return untyped __global__["parseFloat"](param1);',
            1,
        ),
    ),
    ("class_411", "method_3730"): (
        ("param1 * 31", "param1 * 31.0", 1),
    ),
    ("class_406", "method_4835"): (
        ("Std.string(param1)", "param1", 1),
    ),
    ("class_406", "method_5061"): (
        ('Std.string(param1 + "<br/>")', 'param1 + "<br/>"', 1),
    ),
    ("class_406", "method_8544"): (
        ('Std.string(param1 + "<br/>")', 'param1 + "<br/>"', 1),
    ),
    ("class_406", "method_7032"): (
        (
            'Std.string("<font color=\\\'#" + "DDDDDD" + "\\\'>")',
            '"<font color=\\\'#" + "DDDDDD" + "\\\'>"',
            1,
        ),
        (
            ("Std.string(Class_50.method_765(port.runtime.As3.index("
             'var_14473, 0)) + " is typing...")'),
            ("Class_50.method_765(port.runtime.As3.index("
             'var_14473, 0)) + " is typing..."'),
            1,
        ),
        (
            'Std.string("" + _loc2_ + " people typing...")',
            '"" + _loc2_ + " people typing..."',
            1,
        ),
        (
            'Std.string("</font>" + "<br/>")',
            '"</font>" + "<br/>"',
            1,
        ),
    ),
    ("class_451", "method_5877"): (
        ("Std.string(var_484.mBaseWeapon1)", "var_484.mBaseWeapon1", 1),
        ("Std.string(var_484.mBaseWeapon2)", "var_484.mBaseWeapon2", 1),
        (
            'Std.string("" + _loc4_.var_1076)',
            '"" + _loc4_.var_1076',
            2,
        ),
    ),
    ("class_507", "method_1319"): (
        ("Std.string(var_13881.var_4421)", "var_13881.var_4421", 1),
    ),
    ("class_507", "method_5984"): (
        ("Std.string(var_13881.mBaseWeapon1)", "var_13881.mBaseWeapon1", 1),
        ("Std.string(var_13881.mBaseWeapon2)", "var_13881.mBaseWeapon2", 1),
    ),
    ("class_434", "HandleInput"): (
        (
            f"{AS3_HELPER}.toBool(super.HandleInput(param1))",
            "super.HandleInput(param1)",
            1,
        ),
    ),
    ("class_479", "method_5588"): (
        (
            f"{AS3_HELPER}.toBool(super.method_5588())",
            "super.method_5588()",
            1,
        ),
    ),
    ("class_622", "PageRight"): (
        (
            f"{AS3_HELPER}.toBool(super.PageRight(param1,param2))",
            "super.PageRight(param1,param2)",
            1,
        ),
    ),
    ("class_622", "PageLeft"): (
        (
            f"{AS3_HELPER}.toBool(super.PageLeft(param1,param2))",
            "super.PageLeft(param1,param2)",
            1,
        ),
    ),
    ("class_511", "method_4279"): (
        (
            "Std.string(Class_511.method_2784(param2,false))",
            "Class_511.method_2784(param2,false)",
            1,
        ),
    ),
    ("class_533", "method_4819"): (
        (
            'Std.string(" " + Class_49.method_5298(owner.var_10500))',
            '" " + Class_49.method_5298(owner.var_10500)',
            1,
        ),
    ),
    ("class_393", "method_421"): (
        (
            'Std.string(" " + Class_49.method_5298(owner.var_12029.var_14921))',
            '" " + Class_49.method_5298(owner.var_12029.var_14921)',
            1,
        ),
    ),
    ("class_393", "method_7394"): (
        (
            ("var _loc1_:DisplayObjectContainer = cast((ScreenManager.var_8129.panelClip != null ? "
             "ScreenManager.var_8129.var_12792 : null));"),
            ("var _loc1_:DisplayObjectContainer = ScreenManager.var_8129.panelClip != null ? "
             "(cast ScreenManager.var_8129.var_12792 : DisplayObjectContainer) : "
             "(cast null : DisplayObjectContainer);"),
            1,
        ),
    ),
    ("class_393", "method_7459"): (
        (
            ("var _loc1_:DisplayObjectContainer = cast((ScreenManager.var_4095.panelClip != null ? "
             "ScreenManager.var_4095.var_12792 : null));"),
            ("var _loc1_:DisplayObjectContainer = ScreenManager.var_4095.panelClip != null ? "
             "(cast ScreenManager.var_4095.var_12792 : DisplayObjectContainer) : "
             "(cast null : DisplayObjectContainer);"),
            1,
        ),
    ),
    ("class_434", "method_1382"): (
        ('Std.string(" " + "15")', '" " + "15"', 1),
    ),
    ("class_386", "method_6139"): (
        ('Std.string("" + param2)', '"" + param2', 1),
    ),
    ("class_25", "method_8445"): (
        ('"color":16750876', f'"color":{AS3_HELPER}.toUInt(16750876)', 1),
    ),
    ("class_598", "method_6775"): (
        (
            f"{AS3_HELPER}.toInt(param1 % 2 == 0 ? 349 : {AS3_HELPER}.toInt(827))",
            f"{AS3_HELPER}.toInt(param1 % 2 == 0 ? 349.0 : {AS3_HELPER}.toInt(827.0))",
            1,
        ),
    ),
    ("class_320", "method_4885"): (
        (
            (f"if({AS3_HELPER}.index(var_13290, param1) != null && "
             f"{AS3_HELPER}.index(var_13290, param1) != \"\")"),
            (f"if((cast {AS3_HELPER}.index(var_13290, param1) : String) != null && "
             f"(cast {AS3_HELPER}.index(var_13290, param1) : String) != \"\")"),
            1,
        ),
    ),
    ("class_680", "method_1055"): (
        (
            (f"return method_8905(param1.var_13723.method_4935(param2),param1.clipLibrary,"
             f"{AS3_HELPER}.toFloat(param1.var_11561 != null && "
             f"{AS3_HELPER}.toBool(param1.var_11561.exists(param2)) ? "
             "param1.var_11561.method_4935(param2):0),null);"),
            (f"return method_8905((cast param1.var_13723.method_4935(param2) : String),"
             f"param1.clipLibrary,{AS3_HELPER}.toFloat(param1.var_11561 != null && "
             f"{AS3_HELPER}.toBool(param1.var_11561.exists(param2)) ? "
             "param1.var_11561.method_4935(param2):0.0),null);"),
            1,
        ),
    ),
    ("class_582", "method_8238"): (
        (
            "Std.string(Context3DTextureFormat.BGRA_PACKED)",
            "(cast Context3DTextureFormat.BGRA_PACKED : String)",
            1,
        ),
    ),
    ("class_579", "method_4088"): (
        (
            "Std.string(Context3DTextureFormat.BGRA_PACKED)",
            "(cast Context3DTextureFormat.BGRA_PACKED : String)",
            1,
        ),
    ),
    ("class_579", "method_4736"): (
        (
            "Std.string(Context3DTextureFormat.BGRA_PACKED)",
            "(cast Context3DTextureFormat.BGRA_PACKED : String)",
            1,
        ),
    ),
    ("UiClip", "method_1467"): (
        (
            f"{AS3_HELPER}.toFloat(param2 & 2) != 0",
            "(param2 & 2) != 0",
            1,
        ),
    ),
    ("UiClip", "method_3716"): (
        (
            f"_loc1_ = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('*', _loc1_, "
            "Class_687.var_15040));",
            "_loc1_ *= Class_687.var_15040;",
            1,
        ),
        (
            f"_loc1_ = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('*', _loc1_, "
            "_loc2_.scaleX));",
            "_loc1_ *= _loc2_.scaleX;",
            1,
        ),
    ),
    ("UiClip", "method_6266"): (
        (
            f"var_5718 = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('-', var_5718, "
            "Class_687.var_1459));",
            "var_5718 -= Class_687.var_1459;",
            1,
        ),
        (
            f"var_5718 = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('+', var_5718, "
            "Class_687.var_1459));",
            "var_5718 += Class_687.var_1459;",
            1,
        ),
    ),
    ("UiClip", "method_6891"): (
        (
            f"var_6327 = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('-', var_6327, "
            "Class_687.var_1459 * var_13195));",
            "var_6327 -= Class_687.var_1459 * var_13195;",
            1,
        ),
        (
            f"var_6327 = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('+', var_6327, "
            "Class_687.var_1459 * var_13195));",
            "var_6327 += Class_687.var_1459 * var_13195;",
            1,
        ),
    ),
    ("class_664", "method_7191"): (
        (
            "Std.string(Class_49.method_5298(var_6716))",
            "Class_49.method_5298(var_6716)",
            1,
        ),
    ),
    ("class_718", "method_7966"): (
        (
            f"{AS3_HELPER}.valueToString(var_8024)",
            "var_8024.toString()",
            1,
        ),
    ),
    ("class_672", "method_7011"): (
        (
            ("_loc3_.drawRect(11.5,2.5,var_7160 - 5,"
             "port.runtime.As3.toUInt(port.runtime.As3.toUInt(_loc2_ * 20) + 50) - 5);"),
            ("_loc3_.drawRect(11.5,2.5,var_7160 - 5,"
             "port.runtime.As3.toUInt(port.runtime.As3.toUInt(_loc2_ * 20) + 50) - 5.0);"),
            1,
        ),
    ),
    ("class_219", "method_4302"): (
        (
            ("var_11751 = (var_12647 - 1) / var_12647 * "
             "var_11751 + param1 * 1 / var_12647;"),
            ("var_11751 = (var_12647 - 1.0) / var_12647 * "
             "var_11751 + param1 * 1.0 / var_12647;"),
            1,
        ),
    ),
    ("StoreType", "method_4675"): (
        (
            f"{AS3_HELPER}.toUInt(100000 + param1)",
            "100000 + param1",
            1,
        ),
    ),
    ("class_454", "method_3940"): (
        (
            ("Std.string(\" \" + class_256.method_1351("
             f"{AS3_HELPER}.index(class_454.var_7633.h, var_5078)))"),
            ("\" \" + class_256.method_1351((cast "
             f"{AS3_HELPER}.index((cast class_454.var_7633 : "
             "IntMap<Dynamic>).h, var_5078) : String))"),
            1,
        ),
    ),
    ("class_479", "method_4097"): (
        (
            ("Type.createEnumIndex(untyped class_477,port.runtime.As3.toInt("
             "port.runtime.As3.index(var_5056, var_1253)),null)"),
            ("(cast Type.createEnumIndex(untyped class_477,port.runtime.As3.toInt("
             "port.runtime.As3.index(var_5056, var_1253)),null) : class_477)"),
            1,
        ),
    ),
    ("class_174", "method_2999"): (
        (
            "new GlowFilter(0,1,4,4,10)",
            "new GlowFilter(0,1.0,4,4,10)",
            1,
        ),
        (
            f"{AS3_HELPER}.setIndex(class_174.var_11873, 0, 0)",
            f"{AS3_HELPER}.setIndex(class_174.var_11873, 0, 0.0)",
            1,
        ),
    ),
    ("class_622", "method_1668"): (
        (
            "Std.string(param1.method_4885(param3))",
            "param1.method_4885(param3)",
            1,
        ),
    ),
    ("class_622", "method_4634"): (
        (
            "Std.string(param1.method_4885(param3))",
            "param1.method_4885(param3)",
            1,
        ),
    ),
    ("LinkUpdater", "method_643"): (
        (
            ("var _loc7_:Class_189 = cast(((_loc6_) ? "
             "owner.var_10088.method_4935(Class_189.method_5098(_loc3_,_loc4_,_loc2_)):"
             "owner.var_11393.method_4935(\"e\" + (\"\" + _loc2_) + "
             "(\"u\" + (\"\" + _loc3_)))));"),
            ("var _loc7_:Class_189 = ((_loc6_) ? (cast "
             "owner.var_10088.method_4935(Class_189.method_5098(_loc3_,_loc4_,_loc2_)) "
             ": Class_189) : (cast owner.var_11393.method_4935(\"e\" + "
             "(\"\" + _loc2_) + (\"u\" + (\"\" + _loc3_))) : Class_189));"),
            1,
        ),
        (
            ("var _loc7_:Class_189 = cast(((_loc6_) ? "
             "(cast owner.var_10088.method_4935(Class_189.method_5098(_loc3_,_loc4_,_loc2_)) : Class_189):"
             "owner.var_11393.method_4935(\"e\" + (\"\" + _loc2_) + "
             "(\"u\" + (\"\" + _loc3_)))));"),
            ("var _loc7_:Class_189 = ((_loc6_) ? (cast "
             "owner.var_10088.method_4935(Class_189.method_5098(_loc3_,_loc4_,_loc2_)) "
             ": Class_189) : (cast owner.var_11393.method_4935(\"e\" + "
             "(\"\" + _loc2_) + (\"u\" + (\"\" + _loc3_))) : Class_189));"),
            1,
        ),
    ),
    ("LinkUpdater", "method_1306"): (
        (
            ("var _loc8_:Class_189 = cast(((_loc5_) ? "
             "owner.var_10088.method_4935(Class_189.method_5098(_loc2_,_loc6_,_loc3_)):"
             "owner.var_11393.method_4935(\"e\" + (\"\" + _loc3_) + "
             "(\"u\" + (\"\" + _loc2_)))));"),
            ("var _loc8_:Class_189 = ((_loc5_) ? (cast "
             "owner.var_10088.method_4935(Class_189.method_5098(_loc2_,_loc6_,_loc3_)) "
             ": Class_189) : (cast owner.var_11393.method_4935(\"e\" + "
             "(\"\" + _loc3_) + (\"u\" + (\"\" + _loc2_))) : Class_189));"),
            1,
        ),
        (
            ("var _loc8_:Class_189 = cast(((_loc5_) ? "
             "(cast owner.var_10088.method_4935(Class_189.method_5098(_loc2_,_loc6_,_loc3_)) : Class_189):"
             "owner.var_11393.method_4935(\"e\" + (\"\" + _loc3_) + "
             "(\"u\" + (\"\" + _loc2_)))));"),
            ("var _loc8_:Class_189 = ((_loc5_) ? (cast "
             "owner.var_10088.method_4935(Class_189.method_5098(_loc2_,_loc6_,_loc3_)) "
             ": Class_189) : (cast owner.var_11393.method_4935(\"e\" + "
             "(\"\" + _loc3_) + (\"u\" + (\"\" + _loc2_))) : Class_189));"),
            1,
        ),
    ),
    ("GameStats", "method_2798"): (
        (
            f"var_14337 = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('+', var_14337, param1));",
            "var_14337 += param1;",
            1,
        ),
    ),
    ("GameStats", "method_1021"): (
        (
            f"var_7376 = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('+', var_7376, param1));",
            "var_7376 += param1;",
            1,
        ),
    ),
    ("GameStats", "method_7271"): (
        (
            f"var_10481 = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('+', var_10481, param1));",
            "var_10481 += param1;",
            1,
        ),
    ),
    ("GameStats", "method_974"): (
        (
            f"var_409 = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('+', var_409, param1));",
            "var_409 += param1;",
            1,
        ),
    ),
    ("class_114", "method_2162"): (
        (
            "Std.string(Class_49.method_5298(var_8329.method_1392(_loc3_)))",
            "Class_49.method_5298(var_8329.method_1392(_loc3_))",
            1,
        ),
    ),
    ("class_135", "method_8373"): (
        (
            'Std.string(Class_135.method_4976(_loc4_) + "\\n")',
            'Class_135.method_4976(_loc4_) + "\\n"',
            1,
        ),
    ),
    ("class_29", "method_54"): (
        (
            (f"Std.string(param1 + Class_592.method_190({AS3_HELPER}.toUInt("
             f"{AS3_HELPER}.index(var_3813, _loc6_))))"),
            (f"param1 + Class_592.method_190({AS3_HELPER}.toUInt("
             f"{AS3_HELPER}.index(var_3813, _loc6_)))"),
            1,
        ),
    ),
    ("class_544", "OnInitDisplay"): (
        (
            "var_12580.method_4016(Std.string(Class_50.method_4979(_loc5_,false,10)))",
            "var_12580.method_4016(Class_50.method_4979(_loc5_,false,10))",
            1,
        ),
    ),
    ("class_682", "method_5712"): (
        (
            "var_11533.method_1467(Std.string(var_6263.owner.var_5488.var_1140.var_4015))",
            "var_11533.method_1467(var_6263.owner.var_5488.var_1140.var_4015)",
            1,
        ),
    ),
    ("class_700", "method_3260"): (
        (
            ('param2.method_1467(Std.string("Notch" + '
             'Class_49.method_5298(Class_189.method_1542(param1))),8)'),
            ('param2.method_1467("Notch" + '
             'Class_49.method_5298(Class_189.method_1542(param1)),8)'),
            1,
        ),
    ),
    ("class_429", "method_8874"): (
        (
            f"param1 = {AS3_HELPER}.toUInt({AS3_HELPER}.numeric('-', param1, Class_429.var_1687));",
            "param1 -= Class_429.var_1687;",
            1,
        ),
    ),
    ("class_51", "method_4694"): (
        (
            f"param1 = {AS3_HELPER}.toUInt({AS3_HELPER}.numeric('-', param1, 100));",
            "param1 -= 100;",
            1,
        ),
    ),
    ("class_703", "method_6016"): (
        (
            f"var_1002 = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('-', var_1002, method_1838()));",
            "var_1002 -= method_1838();",
            1,
        ),
    ),
    ("class_626", "IsNodeMirrored2D"): (
        (
            (f"_loc2_ = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('*', _loc2_, "
             "param1.scaleX * param1.scaleY));"),
            "_loc2_ *= param1.scaleX * param1.scaleY;",
            1,
        ),
    ),
    ("class_626", "IsNodeMirrored3D"): (
        (
            (f"_loc2_ = {AS3_HELPER}.toFloat({AS3_HELPER}.numeric('*', _loc2_, "
             "param1.scaleX * param1.scaleY));"),
            "_loc2_ *= param1.scaleX * param1.scaleY;",
            1,
        ),
    ),
    ("class_15", "method_6616"): (
        (
            (f"var_1374 = {AS3_HELPER}.toUInt({AS3_HELPER}.numeric('-', var_1374, "
             f"{AS3_HELPER}.toInt(500)));"),
            "var_1374 -= 500;",
            1,
        ),
    ),
    ("class_50", "method_1503"): (
        (
            (f"param1 = {AS3_HELPER}.toInt({AS3_HELPER}.numeric('-', param1, "
             "param1 >> 1 & 0x55555555));"),
            "param1 -= param1 >> 1 & 0x55555555;",
            1,
        ),
    ),
    ("class_172", "method_5535"): (
        (
            (f"var_11420 = {AS3_HELPER}.toInt({AS3_HELPER}.numeric('-', var_11420, "
             "_loc2_.GetSize()));"),
            "var_11420 -= _loc2_.GetSize();",
            1,
        ),
    ),
    ("class_173", "method_5535"): (
        (
            (f"var_11420 = {AS3_HELPER}.toInt({AS3_HELPER}.numeric('-', var_11420, "
             "_loc2_.GetSize()));"),
            "var_11420 -= _loc2_.GetSize();",
            1,
        ),
    ),
    ("class_114", "method_644"): (
        (
            (f"param1.SessionBoxesOpened = var_7372 = "
             f"{AS3_HELPER}.toUInt(var_7372 + 1);"),
            "param1.SessionBoxesOpened = ++var_7372;",
            1,
        ),
    ),
}


def restore_audited_expression_semantics(span: str, *, late_only: bool = False) -> str:
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return "".join(out)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        if close_paren < 0:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        body_open = skip_space_right(span, close_paren + 1)
        while body_open < len(span) and span[body_open] != "{":
            body_open += 1
        if body_open >= len(span):
            out.append(span[i:close_paren + 1])
            i = close_paren + 1
            continue
        body_close = find_matching_right(span, body_open)
        if body_close < 0:
            out.append(span[i:body_open + 1])
            i = body_open + 1
            continue

        body = span[body_open + 1:body_close]
        lookup_class = class_name or ""
        if lookup_class.startswith("Class_"):
            lookup_class = "class_" + lookup_class[6:]
        method_key = (lookup_class, match.group(1))
        rewrites = AUDITED_EXPRESSION_REWRITES.get(method_key, ())
        late_methods = {
            ("class_454", "method_4451"),
            ("class_454", "method_4503"),
            ("class_454", "method_5497"),
            ("class_454", "method_6018"),
            ("class_434", "method_6746"),
            ("class_434", "method_3453"),
            ("class_666", "method_1576"),
            ("class_554", "OnInitDisplay"),
            ("class_625", "OnRefreshScreen"),
            ("GameCore", "method_8678"),
            ("class_194", "method_4689"),
            ("class_370", "method_6732"),
            ("class_21", "method_4533"),
            ("class_375", "method_4093"),
            ("ScreenManager", "method_2726"),
            ("class_377", "method_3476"),
            ("class_278", "method_3682"),
            ("class_139", "method_2160"),
            ("class_139", "method_7294"),
            ("class_171", "method_5535"),
            ("class_171", "method_2704"),
            ("class_457", "method_7324"),
            ("ControllerMappingType", "method_4012"),
            ("class_417", "method_4234"),
            ("class_417", "method_7408"),
            ("class_577", "method_8895"),
            ("GameCore", "method_3044"),
            ("GameCore", "method_1170"),
            ("GameCore", "method_1454"),
            ("class_609", "method_5303"),
            ("class_614", "method_5303"),
            ("class_555", "method_8665"),
            ("MovingPlatform", "method_814"),
            ("class_394", "Tick"),
            ("class_406", "method_5061"),
            ("class_406", "method_7032"),
            ("class_406", "method_8544"),
            ("class_451", "method_5877"),
            ("class_507", "method_1319"),
            ("class_507", "method_5984"),
            ("class_329", "method_4765"),
            ("class_706", "method_8028"),
            ("class_329", "method_2746"),
            ("class_329", "method_2238"),
            ("class_527", "method_2827"),
            ("class_690", "method_2565"),
            ("class_690", "method_3882"),
            ("class_664", "method_7868"),
            ("class_199", "method_7694"),
            ("class_460", "method_2827"),
            ("class_329", "method_5372"),
            ("class_533", "method_6366"),
            ("class_60", "method_3580"),
            ("class_700", "method_1703"),
            ("class_390", "UpdateHighlighter"),
            ("class_385", "method_6386"),
            ("class_674", "method_5114"),
            ("class_480", "method_7328"),
            ("class_515", "method_5683"),
            ("SubScreenEventTimedEvent", "RefreshColorProgress"),
            ("class_329", "method_4067"),
            ("class_524", "method_8312"),
            ("class_700", "method_5033"),
            ("class_403", "method_2003"),
            ("SubScreenEventTimedEvent", "OnRefreshScreen"),
            ("ScreenBase", "method_1053"),
            ("PaperDoll", "method_1467"),
            ("class_479", "method_968"),
            ("class_663", "method_6445"),
            ("class_618", "method_2311"),
            ("class_434", "HandleInput"),
            ("class_479", "method_5588"),
            ("class_622", "PageRight"),
            ("class_622", "PageLeft"),
            ("class_511", "method_4279"),
            ("class_533", "method_4819"),
            ("class_393", "method_421"),
            ("class_434", "method_1382"),
            ("class_386", "method_6139"),
            ("class_25", "method_8445"),
            ("class_598", "method_6775"),
            ("class_320", "method_4885"),
            ("class_680", "method_1055"),
            ("class_579", "method_4088"),
            ("class_579", "method_4736"),
            ("class_582", "method_8238"),
            ("class_664", "method_7191"),
            ("class_718", "method_7966"),
            ("class_416", "method_2827"),
            ("class_458", "method_8115"),
            ("class_532", "method_8120"),
            ("class_557", "method_1588"),
            ("class_697", "method_4875"),
            ("class_714", "method_7662"),
            ("class_714", "method_8993"),
            ("UiClip", "method_1467"),
            ("UiClip", "method_3716"),
            ("UiClip", "method_6266"),
            ("UiClip", "method_6891"),
            ("LinkUpdater", "method_643"),
            ("LinkUpdater", "method_1306"),
            ("GameStats", "method_2798"),
            ("GameStats", "method_1021"),
            ("GameStats", "method_7271"),
            ("GameStats", "method_974"),
            ("class_114", "method_2162"),
            ("class_135", "method_8373"),
            ("class_29", "method_54"),
            ("class_544", "OnInitDisplay"),
            ("class_682", "method_5712"),
            ("class_700", "method_3260"),
            ("class_429", "method_8874"),
            ("class_51", "method_4694"),
            ("class_703", "method_6016"),
            ("class_626", "IsNodeMirrored2D"),
            ("class_626", "IsNodeMirrored3D"),
            ("class_15", "method_6616"),
            ("class_50", "method_1503"),
            ("class_172", "method_5535"),
            ("class_173", "method_5535"),
            ("class_114", "method_644"),
            ("class_624", "method_9064"),
            ("class_663", "method_6272"),
            ("class_689", "method_2847"),
            ("class_689", "method_7916"),
            ("class_703", "method_1354"),
            ("class_74", "method_5356"),
            ("ItemSpawn", "method_3131"),
            ("SubScreenEventTimedEvent", "GetEventDailyMissionAtIndex"),
            ("StoreType", "method_2100"),
        }
        if late_only and method_key not in late_methods:
            rewrites = ()
        for needle, replacement, expected in rewrites:
            needle = audited_needle(body, needle, expected)
            if replacement.startswith(needle) and body.count(replacement) == expected:
                continue
            if body.count(needle) == expected:
                body = body.replace(needle, replacement)
        out.append(span[i:body_open + 1])
        out.append(body)
        out.append("}")
        i = body_close + 1


STATIC_LITERAL_STRING_INIT_RE = re.compile(
    r"(?m)^(?P<head>[ \t]*(?:(?:public|private)\s+)?static\s+var\s+[A-Za-z_]\w*:String\s*=\s*)"
    + re.escape(AS3_HELPER)
    + r"\.coerceString\((?P<literal>\"(?:[^\"\\\n]|\\.)*\")\);"
)
STATIC_LITERAL_UINT_INIT_RE = re.compile(
    r"(?m)^(?P<head>[ \t]*(?:(?:public|private)\s+)?static\s+var\s+[A-Za-z_]\w*:UInt\s*=\s*)"
    + re.escape(AS3_HELPER)
    + r"\.toUInt\((?P<literal>-?\d+)\);"
)
STATIC_CAST_UINT_INIT_RE = re.compile(
    r"(?m)^(?P<head>[ \t]*(?:(?:public|private)\s+)?static\s+var\s+[A-Za-z_]\w*:UInt\s*=\s*)"
    r"cast\s+(?P<literal>\d+);"
)


def _static_uint_literal(match: re.Match[str]) -> str:
    value = int(match.group("literal"))
    if -0x80000000 <= value <= 0x7FFFFFFF:
        spelled = str(value)
    elif 0x80000000 <= value <= 0xFFFFFFFF:
        spelled = f"0x{value:08X}"
    else:
        return match.group(0)
    return f"{match.group('head')}{spelled};"


def restore_audited_static_string_literals(span: str) -> str:
    span = STATIC_LITERAL_STRING_INIT_RE.sub(lambda m: f"{m.group('head')}{m.group('literal')};", span)
    span = STATIC_LITERAL_UINT_INIT_RE.sub(_static_uint_literal, span)
    return STATIC_CAST_UINT_INIT_RE.sub(_static_uint_literal, span)


AUDITED_REMOVE_CHILDREN_RECEIVERS: dict[tuple[str, str], tuple[str, ...]] = {
    ("class_680", "new"): ("mContainer",),
    ("class_680", "method_5324"): ("mContainer",),
    ("class_669", "method_2444"): ("mContainer",),
    ("class_664", "Shutdown"): ('class_51.method_3081(var_2089.clip,"am_Holder")',),
    ("class_597", "method_5342"): ("mIconHolder.clip",),
    ("class_556", "method_4399"): ("var_8042",),
    ("class_556", "Clear"): ("var_8042",),
    ("class_526", "method_2555"): ("var_12893",),
    ("class_329", "Clear"): ("var_4349.clip", "var_954.clip", "var_14255.clip"),
    ("PaperDoll", "method_7511"): ("var_219",),
    ("class_669", "new"): ("mContainer",),
    ("class_680", "method_8905"): ("mContainer",),
    ("class_660", "method_3789"): ("var_12966",),
    ("class_597", "method_3789"): ("mIconHolder.clip",),
    ("class_329", "method_366"): ("var_14255.clip",),
    ("class_665", "method_817"): ("port.runtime.As3.index(var_2542, _loc25_).clip",
                                  "port.runtime.As3.index(var_820, _loc25_).clip"),
}

AUDITED_DISPLAY_OBJECT_CALL_ARGUMENTS: dict[tuple[str, str], tuple[str, ...]] = {
    ("class_511", "method_5767"): (
        "var_2114.clip",
        "var_657.clip",
        "var_12383.clip",
        "var_6805.clip",
    ),
}

AUDITED_DISPLAY_OBJECT_ASSIGNMENTS = {
    ("class_511", "method_1148"),
    ("class_511", "method_5767"),
}


def restore_audited_remove_children_receiver_coercions(span: str) -> str:
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return "".join(out)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        if close_paren < 0:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        body_open = skip_space_right(span, close_paren + 1)
        while body_open < len(span) and span[body_open] != "{":
            body_open += 1
        if body_open >= len(span):
            out.append(span[i:close_paren + 1])
            i = close_paren + 1
            continue
        body_close = find_matching_right(span, body_open)
        if body_close < 0:
            out.append(span[i:body_open + 1])
            i = body_open + 1
            continue

        body = span[body_open + 1:body_close]
        for receiver in AUDITED_REMOVE_CHILDREN_RECEIVERS.get(
            (class_name or "", match.group(1)), ()
        ):
            call = f"{receiver}.removeChildren()"
            body = body.replace(
                call,
                f"(cast {receiver} : flash.display.DisplayObjectContainer).removeChildren()",
            )
        out.append(span[i:body_open + 1])
        out.append(body)
        out.append("}")
        i = body_close + 1


def restore_audited_display_object_boundaries(span: str) -> str:
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return "".join(out)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        if close_paren < 0:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        body_open = skip_space_right(span, close_paren + 1)
        while body_open < len(span) and span[body_open] != "{":
            body_open += 1
        if body_open >= len(span):
            out.append(span[i:close_paren + 1])
            i = close_paren + 1
            continue
        body_close = find_matching_right(span, body_open)
        if body_close < 0:
            out.append(span[i:body_open + 1])
            i = body_open + 1
            continue

        body = span[body_open + 1:body_close]
        method_key = (class_name or "", match.group(1))
        if method_key in AUDITED_DISPLAY_OBJECT_ASSIGNMENTS:
            body = body.replace(
                "_loc1_ = owner.main.stage.focus;",
                "_loc1_ = (cast owner.main.stage.focus : flash.display.DisplayObject);",
            )
        for receiver in AUDITED_DISPLAY_OBJECT_CALL_ARGUMENTS.get(method_key, ()):
            body = body.replace(
                f"method_8418({receiver},_loc1_)",
                f"method_8418((cast {receiver} : flash.display.DisplayObject),_loc1_)",
            )
        out.append(span[i:body_open + 1])
        out.append(body)
        out.append("}")
        i = body_close + 1


def restore_audited_math_floor_number_initializers(span: str) -> str:
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return "".join(out)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        if close_paren < 0:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        body_open = skip_space_right(span, close_paren + 1)
        while body_open < len(span) and span[body_open] != "{":
            body_open += 1
        if body_open >= len(span):
            out.append(span[i:close_paren + 1])
            i = close_paren + 1
            continue
        body_close = find_matching_right(span, body_open)
        if body_close < 0:
            out.append(span[i:body_open + 1])
            i = body_open + 1
            continue

        body = span[body_open + 1:body_close]
        expression = AUDITED_MATH_FLOOR_NUMBER_INITIALIZERS.get(
            (class_name or "", match.group(1))
        )
        if expression:
            statement = f"var _loc2_:Float = Math.floor({expression});"
            body = body.replace(statement, f"var _loc2_:Float = Math.ffloor({expression});")
        for needle, replacement in AUDITED_MATH_FLOOR_NUMBER_USES.get(
            (class_name or "", match.group(1)), ()
        ):
            if body.count(needle) == 1:
                body = body.replace(needle, replacement)
        out.append(span[i:body_open + 1])
        out.append(body)
        out.append("}")
        i = body_close + 1


AUDITED_TYPED_ARRAY_READS: dict[tuple[str, str], dict[tuple[str, str], str]] = {
    ("class_317", "method_4029"): {
        ("_loc2_.mCache", "_loc3_"): "class_84",
    },
    ("LinkUpdater", "method_1881"): {
        ("var_6983", "_loc2_"): "class_365",
    },
    ("LinkUpdater", "method_2780"): {
        ("var_6983", "0"): "class_365",
    },
    ("LinkUpdater", "method_2869"): {
        ("var_6983", "_loc4_"): "class_365",
    },
    ("LinkUpdater", "method_7072"): {
        ("var_6983", "_loc4_"): "class_365",
    },
    ("HeroType", "method_2069"): {
        ("HeroType.var_1273", "param1"): "HeroType",
        ("CostumeType.var_12721", "param2"): "CostumeType",
    },
    ("HeroType", "method_7706"): {
        ("HeroType.var_1273", "param1"): "HeroType",
        ("CostumeType.var_12721", "param2"): "CostumeType",
    },
    ("CostumeType", "method_8621"): {
        ("CostumeType.var_12721", "param1"): "CostumeType",
        ("CostumeType.var_12721", "param2"): "CostumeType",
    },
    ("ScreenMatchPreviewRanked1v1", "method_2827"): {
        ("LevelType.var_3683", "param1.var_11528"): "LevelType",
    },
    ("ScreenMatchPreviewRanked2v2", "method_2827"): {
        ("LevelType.var_3683", "param1.var_11528"): "LevelType",
    },
    ("class_682", "method_210"): {
        ("var_8042.clip.currentLabels", "param1"): "FrameLabel",
    },
    ("class_356", "method_4434"): {
        ("HeroType.var_1273", "param1"): "HeroType",
    },
    ("class_356", "method_3826"): {
        ("HeroType.var_1273", "param2"): "HeroType",
    },
    ("class_451", "method_5877"): {
        ("HeroType.var_1273", "var_484.var_12172"): "HeroType",
    },
    ("class_507", "method_4848"): {
        ("HeroType.var_1273", "var_13881.var_12172"): "HeroType",
    },
    ("class_120", "method_389"): {
        ("class_120.var_14403", "param1"): "class_120",
    },
    ("class_16", "method_5269"): {
        ("class_16.var_3275", "param2"): "class_16",
    },
    ("class_624", "method_3204"): {
        ("class_16.var_3275", "_loc2_.var_9656"): "class_16",
    },
    ("class_123", "method_4398"): {
        ("var_6578", "_loc2_"): "RollbackEvent",
    },
    ("class_622", "method_1724"): {
        ("var_3676", "var_4505"): "class_138",
    },
    ("class_635", "method_2"): {
        ("var_14954", "_loc3_"): "class_636",
    },
    ("class_719", "method_1125"): {
        ("class_629.var_6772", "param1"): "class_629",
    },
    ("class_719", "method_1526"): {
        ("class_650.var_7660", "param1"): "class_650",
    },
    ("class_719", "method_3911"): {
        ("class_297.var_11158", "param1"): "class_297",
    },
    ("class_719", "method_7374"): {
        ("class_574.var_14155", "param1"): "class_574",
    },
    ("class_719", "method_7941"): {
        ("class_574.var_14155", "param1.var_7685"): "class_574",
    },
    ("class_574", "method_858"): {
        ("class_574.var_14155", "_loc4_"): "class_574",
    },
    ("class_719", "method_9002"): {
        ("class_629.var_6772", "param1"): "class_629",
    },
    ("class_554", "method_29"): {
        ("var_4328", "param1"): "ScreenBase",
    },
    ("class_393", "HandleInput"): {
        ("var_7705", "var_3094"): "ScreenBase",
    },
    ("ControllerMappingType", "method_6672"): {
        ("_loc8_", "_loc12_"): "String",
    },
    ("ControllerMappingType", "method_8682"): {
        ("_loc8_", "_loc15_"): "String",
        ("_loc9_", "_loc15_"): "String",
    },
    ("class_112", "method_3249"): {
        ("class_112.var_5048", "_loc5_"): "class_223",
    },
    ("class_411", "method_5720"): {
        ("var_13829", "var_7405"): "class_668",
    },
    ("StoreType", "method_5060"): {
        ("var_15347", "0"): "class_588",
        ("var_15347", "1"): "class_588",
    },
    ("StoreType", "method_662"): {
        ("var_15347", "0"): "class_588",
        ("var_15347", "1"): "class_588",
    },
    ("class_112", "method_3435"): {
        ("class_112.var_5048", "_loc6_"): "class_223",
    },
    ("class_112", "method_6107"): {
        ("class_112.var_5048", "_loc7_"): "class_223",
    },
    ("class_112", "method_3287"): {
        ("class_112.var_3036", "_loc6_"): "class_223",
    },
    ("class_112", "method_2430"): {
        ("class_112.var_5048", "param1"): "class_223",
        ("class_112.var_5048", "param2"): "class_223",
    },
    ("class_112", "method_1883"): {
        ("class_112.var_5048", "_loc4_"): "class_223",
    },
    ("class_112", "method_8647"): {
        ("class_112.var_5048", "_loc2_"): "class_223",
    },
    ("class_112", "method_3868"): {
        ("class_112.var_5048", "_loc2_"): "class_223",
    },
    ("class_112", "method_5780"): {
        ("class_112.var_5048", "_loc4_"): "class_223",
    },
    ("class_112", "method_5916"): {
        ("class_112.var_5048", "_loc5_"): "class_223",
    },
    ("class_112", "method_2454"): {
        ("class_112.var_5048", "_loc5_"): "class_223",
    },
    ("class_112", "method_3935"): {
        ("class_112.var_15307", "0"): "class_314",
    },
    ("class_112", "method_5667"): {
        ("class_112.var_9206", "0"): "class_87",
    },
    ("class_123", "method_2937"): {
        ("class_116.var_14634", "var_3997"): "class_116",
    },
    ("class_123", "method_3463"): {
        ("class_116.var_14634", "var_3997"): "class_116",
    },
    ("class_123", "method_8497"): {
        ("class_116.var_14634", "var_3997"): "class_116",
    },
    ("class_423", "method_8113"): {
        ("var_14542", "param2"): "class_427",
    },
    ("class_441", "method_8113"): {
        ("var_14542", "param2"): "class_443",
    },
    ("class_230", "method_5452"): {
        ("var_5449", "param2"): "class_229",
    },
    ("class_230", "method_6698"): {
        ("var_5449", "param1"): "class_229",
    },
    ("class_230", "method_6967"): {
        ("var_5449", "param2"): "class_229",
    },
    ("class_230", "method_9020"): {
        ("var_5449", "_loc3_"): "class_229",
    },
    ("ScreenBase", "method_4900"): {
        ("var_7705", "param1"): "ScreenBase",
    },
    ("ScreenBase", "method_2920"): {
        ("var_7705", "param1"): "ScreenBase",
    },
    ("ScreenBase", "method_6363"): {
        ("var_7705", "param1"): "ScreenBase",
    },
    ("class_301", "method_1549"): {
        ("class_301.var_11302", "param1"): "class_301",
    },
    ("class_321", "method_237"): {
        ("class_301.var_11302", "param2"): "class_301",
    },
    ("class_525", "method_3948"): {
        ("class_76.var_12696", "_loc2_"): "class_76",
    },
    ("class_448", "method_1828"): {
        ("var_13244", "param1.var_11355"): "UiClip",
    },
    ("class_58", "RemoveUser"): {
        ("var_5950", "param1"): "class_570",
    },
    ("class_666", "method_8212"): {
        ("HeroType.var_1273", "_loc2_.var_13881.var_12172"): "HeroType",
    },
    ("class_666", "method_7820"): {
        ("HeroType.var_1273", "_loc3_.var_12172"): "HeroType",
    },
    ("class_667", "method_1576"): {
        ("class_120.var_14403", "param1"): "class_120",
    },
    ("class_664", "method_1258"): {
        ("HeroType.var_1273", "param1.var_12172"): "HeroType",
    },
    ("class_719", "method_7366"): {
        ("class_302.var_2300", "_loc1_"): "class_302",
    },
    ("class_624", "method_9064"): {
        ("param1.var_15347", "0"): "class_588",
        ("param1.var_15347", "1"): "class_588",
    },
    ("class_199", "method_5175"): {
        ("class_64.var_1636", "0"): "String",
        ("class_64.var_1636", "1"): "String",
        ("class_64.var_1636", "2"): "String",
        ("class_64.var_1636", "3"): "String",
        ("class_64.var_1636", "4"): "String",
    },
    ("class_609", "method_5175"): {
        ("class_64.var_1636", "0"): "String",
        ("class_64.var_1636", "1"): "String",
        ("class_64.var_1636", "2"): "String",
        ("class_64.var_1636", "3"): "String",
        ("class_64.var_1636", "4"): "String",
    },
    ("class_118", "method_858"): {
        ("class_118.var_13975", "_loc4_"): "class_118",
    },
    ("class_123", "method_9070"): {
        ("var_6578", "_loc5_"): "RollbackEvent",
    },
    ("class_123", "method_7315"): {
        ("var_12027", "_loc4_"): "GfxType",
    },
    ("class_123", "method_8551"): {
        ("HeroType.var_1273", "param1"): "HeroType",
    },
    ("class_123", "method_5880"): {
        ("var_6578", "_loc4_"): "RollbackEvent",
    },
    ("class_123", "method_8710"): {
        ("HeroType.var_1273", "_loc5_.var_11835 & 0xFFFF"): "HeroType",
    },
    ("class_123", "method_5879"): {
        ("CostumeType.var_12721", "_loc5_.var_14823"): "CostumeType",
    },
    ("class_123", "method_4649"): {
        ("HeroType.var_1273", "_loc5_.var_11835 & 0xFFFF"): "HeroType",
        ("class_725.var_4514", "class_725.method_6605(_loc5_.var_15258,true)"): "class_725",
        ("class_725.var_4514", "class_725.method_6605(_loc5_.var_15258,false)"): "class_725",
        ("CostumeType.var_12721", "_loc5_.var_14823"): "CostumeType",
    },
    ("class_295", "method_6960"): {
        ("var_11813", "_loc2_"): "class_224",
        ("var_11813", "_loc3_"): "class_224",
    },
    ("class_104", "method_6585"): {
        ("HeroType.var_1273", "_loc11_"): "HeroType",
    },
    ("class_410", "method_6914"): {
        ("class_112.var_15307", "param1"): "class_314",
    },
    ("class_58", "method_5246"): {
        ("var_5950", "_loc3_"): "class_570",
    },
    ("class_719", "method_6606"): {
        ("HeroType.var_1273", "_loc2_"): "HeroType",
    },
    ("class_719", "method_5901"): {
        ("class_16.var_3275", "param1"): "class_16",
    },
    ("class_719", "method_7286"): {
        ("class_302.var_2300", "param1"): "class_302",
    },
    ("class_193", "method_7204"): {
        (f"{AS3_HELPER}.index(var_13287, param1)", "param2"): "class_136",
        ("_loc6_", "param2"): "class_136",
        ("_loc7_", "param2"): "class_136",
    },
}


AUDITED_COERCED_STRING_ARRAY_READS: dict[tuple[str, str], set[tuple[str, str]]] = {
    ("class_328", "method_2194"): {("_loc3_", "1")},
    ("class_448", "method_7442"): {("class_725.var_7827", "_loc4_")},
    ("class_406", "method_8285"): {("class_406.var_2143", "_loc5_")},
    ("class_502", "OnCreateScreen"): {("var_12117", "_loc3_")},
}


AUDITED_ARRAY_BOUNDARY_READS: dict[
    tuple[str, str], tuple[tuple[str, str, int], ...]
] = {
    ("GameCore", "method_8653"): (
        (f"{AS3_HELPER}.index(var_106, param2)", "var_106[param2]", 2),
    ),
    ("GameCore", "method_2035"): (
        (f"{AS3_HELPER}.index(var_12482, param2)", "var_12482[param2]", 2),
    ),
    ("GameCore", "method_4789"): (
        (f"{AS3_HELPER}.index(var_12482, param2)", "var_12482[param2]", 4),
    ),
    ("class_193", "method_47"): (
        (f"{AS3_HELPER}.index(var_13287, _loc2_)", "var_13287[_loc2_]", 2),
    ),
    ("class_193", "method_2567"): (
        (f"{AS3_HELPER}.index(var_11061, _loc2_)", "var_11061[_loc2_]", 2),
    ),
    ("class_61", "method_1643"): (
        ("param1.files", "param1.files", 2),
    ),
    ("GameCore", "method_4708"): (
        (f"{AS3_HELPER}.index(var_9966, param1)", "var_9966[param1]", 6),
        (f"{AS3_HELPER}.index(var_106, param1)", "var_106[param1]", 6),
    ),
    ("class_193", "method_7204"): (
        (f"{AS3_HELPER}.index(var_13287, param1)", "var_13287[param1]", 6),
    ),
    ("class_583", "method_5948"): (
        (
            f"{AS3_HELPER}.index(class_583.var_9177, param1)",
            (f"(cast {AS3_HELPER}.index(class_583.var_9177, param1) : "
             "Array<Dynamic>)"),
            1,
        ),
    ),
}


AUDITED_TYPED_MAP_READS: dict[tuple[str, str], dict[str, str]] = {
    ("CostumeType", "method_5801"): {
        "_loc13_.getReserved(_loc11_)": "String",
        f"{AS3_HELPER}.index(_loc13_.h, _loc11_)": "String",
    },
    ("class_600", "method_7276"): {
        f"{AS3_HELPER}.index(var_9667, _loc2_).name": "String",
    },
    ("class_605", "method_7276"): {
        f"{AS3_HELPER}.index(var_9667, _loc2_).name": "String",
    },
    ("class_226", "method_8370"): {
        "class_228.var_4959.method_4935(_loc1_.var_10956)": "class_228",
    },
    ("class_226", "method_5471"): {
        "class_228.var_4959.method_4935(_loc2_.var_10956)": "class_228",
    },
    ("class_353", "method_4921"): {
        ("_loc2_.owner.var_10736.method_4935("
         f"{AS3_HELPER}.toInt(_loc2_.owner.var_2208.var_1712.var_7634.var_3239))"): "class_123",
    },
    ("class_568", "method_3720"): {
        "class_564.var_15330.method_4935(param1)": "class_564",
    },
    ("class_624", "method_1056"): {
        "class_574.var_95.method_4935(param1.var_13076)": "class_574",
    },
    ("class_624", "method_6540"): {
        "CompanionType.var_7648.method_4935(param1.var_13076)": "CompanionType",
    },
    ("class_278", "method_4886"): {
        "owner.var_10736.method_4935(param3)": "class_123",
    },
    ("class_242", "method_2224"): {
        f"{AS3_HELPER}.index(class_242.var_4368.h, param1)": "class_241",
    },
    ("class_358", "method_8158"): {
        f"{AS3_HELPER}.index(var_3103.h, _loc2_)": "class_19",
    },
    ("CompanionType", "method_858"): {
        f"{AS3_HELPER}.index(CompanionType.var_9851.h, _loc4_)": "CompanionType",
    },
    ("class_202", "method_5926"): {
        f"{AS3_HELPER}.index(class_202.var_1371.h, param1)": "String",
    },
    ("class_310", "method_8008"): {
        f"{AS3_HELPER}.index(var_14320.h, param1)": "class_309",
    },
    ("class_551", "method_6563"): {
        'StoreType.var_765.method_4935("Costume" + "|" + param1.mCostumeName)': "StoreType",
        'StoreType.var_2774.method_4935("Costume" + "|" + param1.mCostumeName)': "StoreType",
    },
    ("class_104", "method_6585"): {
        ("HeroType.var_2158.method_4935(HeroType.method_5610("
         f"{AS3_HELPER}.index(HeroType.var_1273, _loc11_),_loc10_ == 0 ? null : "
         f"{AS3_HELPER}.index(CostumeType.var_12721, _loc10_)))"): "class_333",
    },
    ("class_104", "method_6856"): {
        f"{AS3_HELPER}.index(var_10855.h, param1)": "Array<Dynamic>",
    },
    ("class_358", "method_3722"): {
        f"{AS3_HELPER}.index(var_3103.h, _loc4_)": "class_19",
    },
    ("class_467", "method_6837"): {
        "CutsceneType.var_1735.method_4935(param1.var_3322)": "CutsceneType",
    },
    ("class_168", "method_7130"): {
        "class_316.var_2189.method_4935(_loc4_)": "class_316",
    },
    ("class_168", "method_3751"): {
        "class_316.var_2189.method_4935(_loc4_)": "class_316",
    },
    ("class_250", "method_1524"): {
        f"{AS3_HELPER}.index(var_14194, _loc6_)": "Sprite3D",
    },
    ("class_479", "OnTickScreen"): {
        f"{AS3_HELPER}.index(var_2212, _loc7_)": "class_480",
    },
    ("class_579", "method_4736"): {
        f"{AS3_HELPER}.index(class_579.var_9685, _loc5_)": "class_32",
    },
    ("class_579", "GetSwappedBone2D"): {
        f"{AS3_HELPER}.index(class_579.sCreatedBmps2D, _loc5_)": "Bitmap",
    },
    ("class_579", "Reset"): {
        f"{AS3_HELPER}.index(class_579.var_9685, _loc5_)": "class_32",
    },
}


AUDITED_TYPED_MAP_REWRITES: dict[tuple[str, str], dict[str, str]] = {
    ("Controller", "method_8392"): {
        "_loc2_.getReserved(param1)":
            "(cast _loc2_.getReserved(param1) : GameInputControl)",
        f"{AS3_HELPER}.index(_loc2_.h, param1)":
            f"(cast {AS3_HELPER}.index(_loc2_.h, param1) : GameInputControl)",
    },
    ("class_120", "method_1140"): {
        "_loc2_.getReserved(param1)":
            "(cast _loc2_.getReserved(param1) : class_120)",
        f"{AS3_HELPER}.index(_loc2_.h, param1)":
            f"(cast {AS3_HELPER}.index(_loc2_.h, param1) : class_120)",
    },
    ("StoreType", "method_2667"): {
        "_loc6_.getReserved(_loc4_)":
            "(cast _loc6_.getReserved(_loc4_) : StoreType)",
        f"{AS3_HELPER}.index(_loc6_.h, _loc4_)":
            f"(cast {AS3_HELPER}.index(_loc6_.h, _loc4_) : StoreType)",
    },
    ("class_4", "method_2755"): {
        "_loc2_.getReserved(param1)":
            "(cast _loc2_.getReserved(param1) : class_276)",
    },
    ("class_578", "method_309"): {
        "_loc2_.getReserved(param1)":
            "(cast _loc2_.getReserved(param1) : class_578)",
    },
    ("class_8", "method_9003"): {
        "_loc3_.getReserved(param1)":
            "(cast _loc3_.getReserved(param1) : class_11)",
    },
    ("class_719", "method_2876"): {
        f"{AS3_HELPER}.index(class_279.var_369.h, param1)":
            (f"(cast {AS3_HELPER}.index((cast class_279.var_369 : "
             "IntMap<Dynamic>).h, param1) : class_279)"),
    },
    ("class_250", "method_8661"): {
        "_loc3_.getReserved(_loc2_)":
            "(cast _loc3_.getReserved(_loc2_) : Xml)",
        f"{AS3_HELPER}.index(_loc3_.h, _loc2_)":
            f"(cast {AS3_HELPER}.index(_loc3_.h, _loc2_) : Xml)",
    },
    ("LinkUpdater", "method_1881"): {
        "var_6983.pop()": "(cast var_6983.pop() : class_365)",
    },
    ("class_11", "method_454"): {
        "_loc2_.getReserved(param1)":
            "(cast _loc2_.getReserved(param1) : class_36)",
    },
    ("class_11", "method_4759"): {
        "_loc2_.getReserved(param1)":
            "(cast _loc2_.getReserved(param1) : class_36)",
    },
    ("class_27", "method_2715"): {
        f"{AS3_HELPER}.index(var_8939.h, param1)":
            f"{AS3_HELPER}.index((cast var_8939 : IntMap<Dynamic>).h, param1)",
    },
    ("class_165", "method_1982"): {
        f"{AS3_HELPER}.index(owner.var_14641.var_3698, _loc3_)":
            (f"(cast {AS3_HELPER}.index((cast owner.var_14641.var_3698 : ObjectMap<Dynamic, Dynamic>), _loc3_)"
             " : Hazard)"),
    },
    ("class_433", "method_4612"): {
        "var_3041.method_4935(param1)":
            "(cast (cast var_3041 : EnumValueMap<Dynamic, Dynamic>).method_4935(param1) : class_674)",
    },
    ("class_433", "method_5993"): {
        "var_3041.method_4935(param1)":
            "(cast (cast var_3041 : EnumValueMap<Dynamic, Dynamic>).method_4935(param1) : class_674)",
    },
    ("class_525", "method_162"): {
        f"{AS3_HELPER}.index(var_2896.h, param1)":
            f"{AS3_HELPER}.index((cast var_2896 : IntMap<Dynamic>).h, param1)",
    },
    ("class_434", "method_2988"): {
        "var_3041.method_4935(class_431.Lobby_Description)":
            ("(cast (cast var_3041 : EnumValueMap<Dynamic, Dynamic>).method_4935("
             "class_431.Lobby_Description) : class_674)"),
    },
    ("class_719", "method_1392"): {
        f"{AS3_HELPER}.index(class_120.var_488.h, param1)":
            (f"(cast {AS3_HELPER}.index((cast class_120.var_488 : IntMap<Dynamic>).h, param1)"
             " : class_120)"),
    },
    ("class_123", "method_1030"): {
        "cast((param2 != 0 ? owner.var_10736.method_4935(param2):null))":
            "(param2 != 0 ? (cast owner.var_10736.method_4935(param2) : class_123) : null)",
    },
    ("class_148", "method_3827"): {
        (f"cast((var_12199 != null ? owner.var_10736.method_4935({AS3_HELPER}.toInt("
         f"{AS3_HELPER}.toUInt({AS3_HELPER}.index(var_12199, param1)))):null))"):
            (f"(var_12199 != null ? (cast owner.var_10736.method_4935({AS3_HELPER}.toInt("
             f"{AS3_HELPER}.toUInt({AS3_HELPER}.index(var_12199, param1)))) : class_123) : null)"),
    },
    ("class_148", "method_7703"): {
        (f"cast((var_12199 != null ? owner.var_10736.method_4935({AS3_HELPER}.toInt("
         f"{AS3_HELPER}.toUInt({AS3_HELPER}.index(var_12199, param1.var_11355)))):null))"):
            (f"(var_12199 != null ? (cast owner.var_10736.method_4935({AS3_HELPER}.toInt("
             f"{AS3_HELPER}.toUInt({AS3_HELPER}.index(var_12199, param1.var_11355)))) : class_123) : null)"),
    },
    ("class_148", "method_4525"): {
        (f"cast((var_12199 != null ? owner.var_10736.method_4935({AS3_HELPER}.toInt("
         f"{AS3_HELPER}.toUInt({AS3_HELPER}.index(var_12199, param1.var_11355)))):null))"):
            (f"(var_12199 != null ? (cast owner.var_10736.method_4935({AS3_HELPER}.toInt("
             f"{AS3_HELPER}.toUInt({AS3_HELPER}.index(var_12199, param1.var_11355)))) : class_123) : null)"),
    },
    ("class_148", "method_2545"): {
        (f"cast((var_12199 != null ? owner.var_10736.method_4935({AS3_HELPER}.toInt("
         f"{AS3_HELPER}.toUInt({AS3_HELPER}.index(var_12199, param2.var_11355)))):null))"):
            (f"(var_12199 != null ? (cast owner.var_10736.method_4935({AS3_HELPER}.toInt("
             f"{AS3_HELPER}.toUInt({AS3_HELPER}.index(var_12199, param2.var_11355)))) : class_123) : null)"),
    },
    ("LinkUpdater", "method_5910"): {
        (f"cast((_loc2_ != 0 ? {AS3_HELPER}.index(class_301.var_11302, _loc2_) : null))"):
            (f"(_loc2_ != 0 ? (cast {AS3_HELPER}.index(class_301.var_11302, _loc2_) : "
             "class_301) : null)"),
        (f"cast((_loc3_ != 0 ? {AS3_HELPER}.index(class_108.var_9591, _loc3_) : null))"):
            (f"(_loc3_ != 0 ? (cast {AS3_HELPER}.index(class_108.var_9591, _loc3_) : "
             "class_108) : null)"),
    },
    ("class_338", "method_4252"): {
        (f"cast((_loc2_.var_12199 != null ? _loc2_.owner.var_10736.method_4935({AS3_HELPER}.toInt("
         f"{AS3_HELPER}.toUInt({AS3_HELPER}.index(_loc2_.var_12199, param1.var_11355)))):null))"):
            (f"(_loc2_.var_12199 != null ? (cast _loc2_.owner.var_10736.method_4935({AS3_HELPER}.toInt("
             f"{AS3_HELPER}.toUInt({AS3_HELPER}.index(_loc2_.var_12199, param1.var_11355)))) : class_123) : null)"),
    },
    ("class_325", "method_7088"): {
        (f"cast((_loc5_.var_12199 != null ? _loc5_.owner.var_10736.method_4935({AS3_HELPER}.toInt("
         f"{AS3_HELPER}.toUInt({AS3_HELPER}.index(_loc5_.var_12199, param1.var_11355)))):null))"):
            (f"(_loc5_.var_12199 != null ? (cast _loc5_.owner.var_10736.method_4935({AS3_HELPER}.toInt("
             f"{AS3_HELPER}.toUInt({AS3_HELPER}.index(_loc5_.var_12199, param1.var_11355)))) : class_123) : null)"),
        (f"cast(_loc7_.var_12199 != null ? _loc7_.owner.var_10736.method_4935({AS3_HELPER}.toInt("
         f"{AS3_HELPER}.toUInt({AS3_HELPER}.index(_loc7_.var_12199, param2.var_11355)))):null)"):
            (f"(_loc7_.var_12199 != null ? (cast _loc7_.owner.var_10736.method_4935({AS3_HELPER}.toInt("
             f"{AS3_HELPER}.toUInt({AS3_HELPER}.index(_loc7_.var_12199, param2.var_11355)))) : class_123) : null)"),
    },
    ("class_433", "method_5279"): {
        "cast((var_12939 & 2) != 0 ? var_15131.method_4935(param1):null)":
            ("((var_12939 & 2) != 0 ? (cast (cast var_15131 : "
             "EnumValueMap<Dynamic, Dynamic>).method_4935(param1) : class_674) : null)"),
        "var_12155.method_4935(param1)":
            ("(cast (cast var_12155 : EnumValueMap<Dynamic, Dynamic>).method_4935(param1) : "
             "Vector<class_674>)"),
        (f"{AS3_HELPER}.index((cast (cast var_12155 : EnumValueMap<Dynamic, Dynamic>).method_4935("
         "param1) : Vector<class_674>), _loc4_)"):
            ("(cast (cast var_12155 : EnumValueMap<Dynamic, Dynamic>).method_4935(param1) : "
             "Vector<class_674>)[_loc4_]"),
    },
    ("ScreenBase", "method_1806"): {
        f"{AS3_HELPER}.valueIndexOf(var_14539, {AS3_HELPER}.index(var_8754, param1))":
            (f"{AS3_HELPER}.valueIndexOf(var_14539, "
             f"(cast {AS3_HELPER}.index(var_8754, param1) : UiClip))"),
    },
    ("UiClip", "method_1467"): {
        (f"cast(({AS3_HELPER}.hasKey(StringMap.reserved, param1) ? "
         f"_loc3_.getReserved(param1):{AS3_HELPER}.index(_loc3_.h, param1)))"):
            (f"({AS3_HELPER}.hasKey(StringMap.reserved, param1) ? "
             f"(cast _loc3_.getReserved(param1) : class_696):"
             f"(cast {AS3_HELPER}.index(_loc3_.h, param1) : class_696))"),
    },
    ("UiClip", "method_6101"): {
        (f"cast(({AS3_HELPER}.hasKey(StringMap.reserved, param1) ? "
         f"_loc4_.getReserved(param1):{AS3_HELPER}.index(_loc4_.h, param1)))"):
            (f"({AS3_HELPER}.hasKey(StringMap.reserved, param1) ? "
             f"(cast _loc4_.getReserved(param1) : class_696):"
             f"(cast {AS3_HELPER}.index(_loc4_.h, param1) : class_696))"),
    },
    ("class_579", "method_5587"): {
        f"{AS3_HELPER}.index(class_579.var_5450, param1)":
            (f"(cast {AS3_HELPER}.index((cast class_579.var_5450 : "
             "ObjectMap<Dynamic, Dynamic>), param1) : Vector<Bitmap>)"),
        f"{AS3_HELPER}.setIndex(_loc3_, param1, _loc4_)":
            (f"{AS3_HELPER}.setIndex((cast _loc3_ : "
             "ObjectMap<Dynamic, Dynamic>), param1, _loc4_)"),
    },
    ("class_579", "method_4716"): {
        "_loc4_.getReserved(param1)":
            "(cast _loc4_.getReserved(param1) : StringMap<Dynamic>)",
        f"{AS3_HELPER}.index(_loc4_.h, param1)":
            f"(cast {AS3_HELPER}.index(_loc4_.h, param1) : StringMap<Dynamic>)",
        "_loc5_.getReserved(_loc10_)":
            "(cast _loc5_.getReserved(_loc10_) : SpriteData)",
        f"{AS3_HELPER}.index(_loc5_.h, _loc10_)":
            f"(cast {AS3_HELPER}.index(_loc5_.h, _loc10_) : SpriteData)",
        '_loc5_.getReserved("")':
            '(cast _loc5_.getReserved("") : SpriteData)',
        f'{AS3_HELPER}.index(_loc5_.h, "")':
             f'(cast {AS3_HELPER}.index(_loc5_.h, "") : SpriteData)',
    },
    ("class_579", "method_2002"): {
        "var _loc7_:IMap = null;":
            "var _loc7_:StringMap<Dynamic> = null;",
        "var _loc8_:IMap = null;":
            "var _loc8_:StringMap<Dynamic> = null;",
        "_loc6_.getReserved(param2)":
            "(cast _loc6_.getReserved(param2) : StringMap<Dynamic>)",
        f"{AS3_HELPER}.index(_loc6_.h, param2)":
            f"(cast {AS3_HELPER}.index(_loc6_.h, param2) : StringMap<Dynamic>)",
        "_loc9_.getReserved(param2)":
            "(cast _loc9_.getReserved(param2) : StringMap<Dynamic>)",
        f"{AS3_HELPER}.index(_loc9_.h, param2)":
            f"(cast {AS3_HELPER}.index(_loc9_.h, param2) : StringMap<Dynamic>)",
    },
    ("class_579", "Reset"): {
        "_loc7_.getReserved(_loc3_)":
            "(cast _loc7_.getReserved(_loc3_) : class_84)",
        f"{AS3_HELPER}.index(_loc7_.h, _loc3_)":
            f"(cast {AS3_HELPER}.index(_loc7_.h, _loc3_) : class_84)",
    },
    ("class_200", "method_619"): {
        **{
            f"{AS3_HELPER}.index(class_200.var_1636.h, {key})":
                (f"(cast {AS3_HELPER}.index((cast class_200.var_1636 : "
                 f"IntMap<Dynamic>).h, {key}) : String)")
            for key in (0, 1, 2, 3, 4)
        },
    },
    ("class_199", "method_5175"): {
        f"{AS3_HELPER}.index(owner.var_13870.h, _loc4_)":
            f"(cast {AS3_HELPER}.index(owner.var_13870.h, _loc4_) : class_142)",
    },
    ("class_609", "method_5175"): {
        f"{AS3_HELPER}.index(owner.var_13870.h, _loc4_)":
            f"(cast {AS3_HELPER}.index(owner.var_13870.h, _loc4_) : class_142)",
    },
}


def restore_audited_typed_array_read_body(
        body: str, allowed: dict[tuple[str, str], str],
        coerced_strings: set[tuple[str, str]]) -> str:
    needle = f"{AS3_HELPER}.index("
    out: list[str] = []
    i = 0
    while True:
        start = body.find(needle, i)
        if start < 0:
            out.append(body[i:])
            return "".join(out)
        open_index = start + len(needle) - 1
        close_index = find_matching_right(body, open_index)
        if close_index < 0:
            out.append(body[i:start + len(needle)])
            i = start + len(needle)
            continue
        args = split_top_level_commas(body[open_index + 1:close_index])
        target = args[0].strip() if len(args) == 2 else ""
        key = args[1].strip() if len(args) == 2 else ""
        out.append(body[i:start])
        if (target, key) in coerced_strings:
            out.append(f"{AS3_HELPER}.coerceString({target}[{key}])")
        elif typ := allowed.get((target, key)):
            out.append(f"(cast {target}[{key}] : {typ})")
        else:
            out.append(body[start:close_index + 1])
        i = close_index + 1


def restore_audited_typed_array_reads(span: str) -> str:
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return "".join(out)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        if close_paren < 0:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        body_open = skip_space_right(span, close_paren + 1)
        while body_open < len(span) and span[body_open] != "{":
            body_open += 1
        if body_open >= len(span):
            out.append(span[i:close_paren + 1])
            i = close_paren + 1
            continue
        body_close = find_matching_right(span, body_open)
        if body_close < 0:
            out.append(span[i:body_open + 1])
            i = body_open + 1
            continue
        allowed = AUDITED_TYPED_ARRAY_READS.get((class_name or "", match.group(1)), {})
        coerced_strings = AUDITED_COERCED_STRING_ARRAY_READS.get(
            (class_name or "", match.group(1)), set()
        )
        body = span[body_open + 1:body_close]
        out.append(span[i:body_open + 1])
        out.append(
            restore_audited_typed_array_read_body(body, allowed, coerced_strings)
            if allowed or coerced_strings else body
        )
        out.append("}")
        i = body_close + 1


def restore_audited_array_boundaries(span: str) -> str:
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return "".join(out)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        body_open = skip_space_right(span, close_paren + 1) if close_paren >= 0 else -1
        while 0 <= body_open < len(span) and span[body_open] != "{":
            body_open += 1
        body_close = (
            find_matching_right(span, body_open)
            if 0 <= body_open < len(span)
            else -1
        )
        if body_close < 0:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        body = span[body_open + 1:body_close]
        for needle, expression, expected_count in AUDITED_ARRAY_BOUNDARY_READS.get(
            (class_name or "", match.group(1)), ()
        ):
            if body.count(needle) == expected_count:
                body = body.replace(needle, f"(cast {expression} : Array<Dynamic>)")
        out.append(span[i:body_open + 1])
        out.append(body)
        out.append("}")
        i = body_close + 1


def restore_audited_typed_map_reads(span: str) -> str:
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return "".join(out)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        if close_paren < 0:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        body_open = skip_space_right(span, close_paren + 1)
        while body_open < len(span) and span[body_open] != "{":
            body_open += 1
        if body_open >= len(span):
            out.append(span[i:close_paren + 1])
            i = close_paren + 1
            continue
        body_close = find_matching_right(span, body_open)
        if body_close < 0:
            out.append(span[i:body_open + 1])
            i = body_open + 1
            continue

        body = span[body_open + 1:body_close]
        for expression, replacement in AUDITED_TYPED_MAP_REWRITES.get(
                (class_name or "", match.group(1)), {}).items():
            body = body.replace(expression, replacement)
        allowed = AUDITED_TYPED_MAP_READS.get((class_name or "", match.group(1)), {})
        for expression, typ in allowed.items():
            body = body.replace(expression, f"(cast {expression} : {typ})")
        out.append(span[i:body_open + 1])
        out.append(body)
        out.append("}")
        i = body_close + 1


TYPED_IMAP_READS = True
TYPED_MAP_H_READS = True
TYPED_IMAP_READ_SKIPS = {
    ("Controller", name) for name in
    ("method_4587", "method_5041", "method_5649", "method_5923", "method_6423", "method_8127")
} | {
    ("class_25", "method_7496"), ("class_81", "method_2948"),
}
_IMAP_READ_RE = re.compile(
    rf"(?<![\w$.])(?:(?P<helper>{re.escape(AS3_HELPER)}\.index\()(?P<hrecv>(?:[A-Za-z_][\w$]*\.)*[A-Za-z_][\w$]*)\.h\s*,"
    r"|(?P<recv>(?:[A-Za-z_][\w$]*\.)*[A-Za-z_][\w$]*)\.(?:getReserved|method_4935)\()")


def _copied_map_element(body: str, local: str, at: int, maps: dict[str, str]) -> str | None:
    stores = list(re.finditer(rf"(?<![\w$.]){local}\s*=(?![=>])\s*(?:cast\s*\(\s*)?((?:[A-Za-z_][\w$]*\.)*([A-Za-z_][\w$]*))\s*\)?\s*;",
                              body[:at]))
    other = list(re.finditer(rf"(?<![\w$.]){local}\s*=(?![=>])", body[:at]))
    if not stores or not other or other[-1].start() != stores[-1].start():
        return None
    opened: list[int] = []
    for offset, ch in enumerate(body[stores[-1].end():at], stores[-1].end()):
        if ch == "{":
            opened.append(offset)
        elif ch == "}":
            if not opened:
                return None
            opened.pop()
    if opened:
        block_end = find_matching_right(body, opened[0])
        if block_end < 0 or re.search(rf"(?<![\w$.]){local}\s*=(?![=>])", body[at:block_end]):
            return None
    return maps.get(stores[-1].group(2))


def restore_typed_imap_reads(span: str, class_name: str | None) -> str:
    table = load_element_types()
    if not TYPED_IMAP_READS or not table:
        return span
    maps = table.get("maps") or {}
    methods = (table.get("locals") or {}) if class_name else {}
    nested_fields = (table.get("nested_specs") or {}).get("fields") or {}
    nested_locals = ((table.get("nested_specs") or {}).get("locals") or {}) if class_name else {}
    map_fields = {name: entry["element"] for name, entry in (table.get("fields") or {}).items()
                  if entry.get("type") in ("StringMap", "IntMap")}
    if not maps and not methods and not map_fields:
        return span
    text, protected = protect_noncode(span)
    out: list[str] = []
    i = 0
    for match in re.finditer(r"\bfunction\s+([A-Za-z_]\w*)\s*\(", text):
        if match.start() < i:
            continue
        close_paren = find_matching_right(text, text.find("(", match.start()))
        body_open = text.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(text, body_open) if body_open >= 0 else -1
        if body_close < 0 or ";" in text[close_paren:body_open]:
            continue
        body = text[body_open:body_close]
        if (class_name, match.group(1)) in TYPED_IMAP_READ_SKIPS:
            out.append(text[i:body_close])
            i = body_close
            continue
        registers = dict(methods.get(f"{class_name}/{match.group(1)}") or {})
        for cls, method, register in ELEMENT_TYPE_SKIPS:
            if cls == class_name and method == match.group(1):
                registers.pop(register, None)
        locals_: dict[str, str] = {}
        if registers and not re.search(r"\bfunction\b", body[1:]):
            signature = text[match.end():close_paren]
            for register, element in registers.items():
                if re.search(rf"\bvar\s+_loc{register}_\s*:\s*(?:IMap|Dynamic)\b", body):
                    locals_[f"_loc{register}_"] = element
                elif element.startswith("Vector<") and re.search(
                        rf"\bvar\s+_loc{register}_\s*:\s*(?:StringMap|IntMap)<Dynamic>", body):
                    locals_[f"_loc{register}_"] = element
                elif re.search(rf"\bparam{register}\s*:\s*(?:IMap|Dynamic)\b", signature):
                    locals_[f"param{register}"] = element
        typed_h = dict(map_fields) if TYPED_MAP_H_READS else {}
        if TYPED_MAP_H_READS:
            typed_h.update(re.findall(r"\bvar\s+(_loc\d+_)\s*:\s*(?:StringMap|IntMap)<(?!Dynamic>)([\w.]+(?:<Dynamic>)?)>", body))
        nested_registers = nested_locals.get(f"{class_name}/{match.group(1)}") or {}
        nested_by_receiver = {name: nested_registers[name[4:-1] if name.startswith("_loc") else name[5:]]
                              for name in locals_
                              if (name[4:-1] if name.startswith("_loc") else name[5:]) in nested_registers}
        sites: list[tuple[int, int, str, str | None]] = []
        for read in _IMAP_READ_RE.finditer(body):
            receiver = read.group("hrecv") or read.group("recv")
            name = receiver.rsplit(".", 1)[-1]
            element = locals_.get(receiver) if receiver in locals_ else (
                maps.get(name) if not name.startswith(("_loc", "param")) else None)
            nested = nested_by_receiver.get(receiver) if receiver in locals_ else (
                nested_fields.get(name) if not name.startswith(("_loc", "param")) else None)
            if not element:
                element = typed_h.get(receiver) if receiver.startswith("_loc") else typed_h.get(name)
            if not element and receiver.startswith("_loc"):
                element = _copied_map_element(body, receiver, read.start(), maps)
            if not element or re.search(r"\(cast\s*$", body[:read.start()]):
                continue
            sites.append((read.start(), read.end("helper") - 1 if read.group("helper") else read.end() - 1, element,
                          nested))
        for start, open_paren, element, nested in sorted(sites, reverse=True):
            end = find_matching_right(body, open_paren)
            if end < 0:
                continue
            loose = element in ("EnumValue", IMAP_ELEMENT) or element.startswith("Vector<") or (
                element in WIDE_ELEMENTS and re.search(r"(?:(?<![=!<>])=|\?|\):)\s*$", body[:start]))
            cast = (f"((cast {body[start:end + 1]} : {element}) : Dynamic)" if loose
                    else f"(cast {body[start:end + 1]} : {element})")
            if element == IMAP_ELEMENT and nested in ("IntMap", "StringMap") and re.match(r"\.h\b", body[end + 1:]):
                cast = f"{AS3_HELPER}.{'intMap' if nested == 'IntMap' else 'stringMap'}({cast})"
            body = f"{body[:start]}{cast}{body[end + 1:]}"
        out.append(text[i:body_open] + body)
        i = body_close
    out.append(text[i:])
    return restore_noncode("".join(out), protected)


IMAP_LOCAL_STORES = True
_IMAP_LOCAL_DECL_RE = re.compile(r"\bvar\s+(_loc\d+_)\s*:\s*IMap(?=__AS3_NONCODE_|\W)")
IMAP_LOCAL_STORE_SKIPS = {
    ("class_104", "method_1516"), ("class_104", "method_5985"), ("class_104", "method_6856"),
    ("class_81", "method_2948"), ("class_25", "method_7496"),
}
_TYPED_CAST_RE = re.compile(r"\(cast\b[^;]*?:\s*[A-Za-z_][\w.]*(?:<[^;()]*>)?\s*\)")


def restore_imap_local_stores(span: str, class_name: str | None = None) -> str:
    if not IMAP_LOCAL_STORES:
        return span
    text, protected = protect_noncode(span)
    out: list[str] = []
    i = 0
    for match in re.finditer(r"\bfunction\s+([A-Za-z_]\w*)\s*\(", text):
        if match.start() < i:
            continue
        close_paren = find_matching_right(text, text.find("(", match.start()))
        body_open = text.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(text, body_open) if body_open >= 0 else -1
        if body_close < 0 or ";" in text[close_paren:body_open]:
            continue
        body = text[body_open:body_close]
        names = set(_IMAP_LOCAL_DECL_RE.findall(body))
        if (not names or re.search(r"\bfunction\b", body[1:])
                or (class_name, match.group(1)) in IMAP_LOCAL_STORE_SKIPS):
            continue
        sites: list[tuple[int, int]] = []
        store_re = re.compile(
            rf"(?:(?<=[;{{}}])|(?<=\n))(?P<lead>\s*(?:var\s+)?(?P<name>{'|'.join(map(re.escape, sorted(names)))})"
            rf"(?:\s*:\s*IMap)?\s*=(?!=)\s*)")
        for store in store_re.finditer(body):
            start = store.end()
            depth = 0
            end = start
            while end < len(body):
                ch = body[end]
                if ch in "([{":
                    depth += 1
                elif ch in ")]}":
                    if depth == 0:
                        break
                    depth -= 1
                elif ch == ";" and depth == 0:
                    break
                end += 1
            if end >= len(body) or body[end] != ";":
                continue
            value = body[start:end].strip()
            if not value or value == "null" or _TYPED_CAST_RE.search(value):
                continue
            sites.append((start, end))
        for start, end in sorted(sites, reverse=True):
            value = body[start:end].strip()
            body = f"{body[:start]}(cast ({value}) : {IMAP_ELEMENT}){body[end:]}"
        out.append(text[i:body_open] + body)
        i = body_close
    out.append(text[i:])
    return restore_noncode("".join(out), protected)


UINT_PRE_INCREMENTS = True
_UINT_PRE_INCREMENT_RE = re.compile(
    rf"(?P<head>[(,]\s*)(?P<name>[A-Za-z_]\w*) = {re.escape(AS3_HELPER)}\.toUInt\((?P=name) (?P<op>[+-]) 1\)(?=\s*[,)])")


def restore_uint_pre_increments(span: str) -> str:
    if not UINT_PRE_INCREMENTS:
        return span
    return _UINT_PRE_INCREMENT_RE.sub(
        lambda m: f"{m.group('head')}{'++' if m.group('op') == '+' else '--'}{m.group('name')}", span)


WIDE_ARRAY_READS = True
_WIDE_ARRAY_READ_RE = re.compile(
    rf"(?<![\w$.]){re.escape(AS3_HELPER)}\.index\(\s*(?P<recv>(?:this\.|[A-Za-z_][\w$]*\.)*[A-Za-z_][\w$]*)\s*,")


def restore_wide_array_reads(span: str, class_name: str | None) -> str:
    table = load_element_types()
    if not WIDE_ARRAY_READS or not table or not class_name:
        return span
    methods = table.get("locals") or {}
    fields = {name: entry["element"] for name, entry in (table.get("fields") or {}).items()
              if entry.get("type") == "Array" and entry.get("element") in ("EnumValue", "Array<Dynamic>")}
    text, protected = protect_noncode(span)
    out: list[str] = []
    i = 0
    for match in re.finditer(r"\bfunction\s+([A-Za-z_]\w*)\s*\(", text):
        if match.start() < i:
            continue
        close_paren = find_matching_right(text, text.find("(", match.start()))
        body_open = text.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(text, body_open) if body_open >= 0 else -1
        if body_close < 0 or ";" in text[close_paren:body_open]:
            continue
        body = text[body_open:body_close]
        if re.search(r"\bfunction\b", body[1:]):
            continue
        skipped = {register for cls, method, register in ELEMENT_TYPE_SKIPS
                   if cls == class_name and method == match.group(1)}
        signature = text[match.end():close_paren]
        locals_: dict[str, str] = {}
        for register, element in (methods.get(f"{class_name}/{match.group(1)}") or {}).items():
            if element not in ("EnumValue", "Array<Dynamic>") or register in skipped:
                continue
            if re.search(rf"\bvar\s+_loc{register}_\s*:\s*Array<Dynamic>", body):
                locals_[f"_loc{register}_"] = element
            elif re.search(rf"\bparam{register}\s*:\s*Array<Dynamic>", signature):
                locals_[f"param{register}"] = element
        sites: list[tuple[int, int, str]] = []
        for read in _WIDE_ARRAY_READ_RE.finditer(body):
            receiver = read.group("recv")
            name = receiver.rsplit(".", 1)[-1]
            element = locals_.get(receiver) if receiver.startswith(("_loc", "param")) else (
                fields.get(name) if not name.startswith("param") else None)
            if not element or re.search(r"\(cast\s*$", body[:read.start()]):
                continue
            sites.append((read.start(), body.find("(", read.start()), element))
        for start, open_paren, element in sorted(sites, reverse=True):
            end = find_matching_right(body, open_paren)
            if end < 0:
                continue
            body = f"{body[:start]}((cast {body[start:end + 1]} : {element}) : Dynamic){body[end + 1:]}"
        out.append(text[i:body_open] + body)
        i = body_close
    out.append(text[i:])
    return restore_noncode("".join(out), protected)


MAP_SPEC_RECEIVER_CASTS = True
_MAP_H_RECEIVER_RE = re.compile(r"(?<![\w$.])((?:[A-Za-z_][\w$]*\.)*([A-Za-z_][\w$]*))\.h\b(?![\w$]|\s*(?:\(|=[^=]))")


def restore_map_spec_receiver_casts(span: str, class_name: str | None) -> str:
    table = load_element_types()
    specs = (table or {}).get("map_specs") or {}
    if not MAP_SPEC_RECEIVER_CASTS or not specs:
        return span
    fields = specs.get("fields") or {}
    class_spec_fields = specs.get("class_fields") or {}
    methods = (specs.get("locals") or {}) if class_name else {}
    text, protected = protect_noncode(span)
    out: list[str] = []
    i = 0
    for match in re.finditer(r"\bfunction\s+([A-Za-z_]\w*)\s*\(", text):
        if match.start() < i:
            continue
        close_paren = find_matching_right(text, text.find("(", match.start()))
        body_open = text.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(text, body_open) if body_open >= 0 else -1
        if body_close < 0 or ";" in text[close_paren:body_open]:
            continue
        params = text[match.end():close_paren]
        body = text[body_open:body_close]
        registers = methods.get(f"{class_name}/{match.group(1)}") or {}
        if re.search(r"\bfunction\b", body[1:]):
            registers = {}

        def spec_of(receiver: str, name: str) -> str | None:
            if re.fullmatch(r"param(\d+)", receiver):
                declared = re.search(rf"(?<![\w$]){receiver}\s*:\s*(?:IMap|Dynamic)\b", params)
                return registers.get(receiver[5:]) if declared else None
            if re.fullmatch(r"_loc\d+_", receiver):
                if not re.search(rf"\bvar\s+{receiver}\s*:\s*(?:IMap|Dynamic)\b", body):
                    return None
                kinds = set()
                for store in re.finditer(rf"(?<![\w$.]){receiver}\s*(?::\s*\w+\s*)?=(?!=)\s*([^;]*);", body):
                    value = store.group(1).strip()
                    value = re.sub(rf"^\(cast \((.*)\) : {re.escape(IMAP_ELEMENT)}\)$", r"\1", value)
                    value = re.sub(r"^cast\s*\(\s*(.*)\)$", r"\1", value)
                    if value == "null":
                        continue
                    if value == "new IntMap()":
                        kinds.add("IntMap" if registers.get(receiver[4:-1]) == "IntMap" else None)
                    elif re.fullmatch(r"(?:[A-Za-z_][\w$]*\.)*([A-Za-z_][\w$]*)", value):
                        kinds.add(fields.get(value.rsplit(".", 1)[-1]))
                    else:
                        kinds.add(None)
                return kinds.pop() if len(kinds) == 1 else None
            owner = receiver.rsplit(".", 1)[0] if "." in receiver else class_name
            if owner == "this":
                owner = class_name
            owner = re.sub(r"^Class_(\d+)$", r"class_\1", owner or "")
            return fields.get(name) or class_spec_fields.get(f"{owner}/{name}")

        sites = []
        for read in _MAP_H_RECEIVER_RE.finditer(body):
            spec = spec_of(read.group(1), read.group(2))
            if spec in ("IntMap", "StringMap") and not re.search(r"\(cast\s*$", body[:read.start()]):
                sites.append((read.start(1), read.end(1), spec))
        for start, end, spec in reversed(sites):
            helper = "intMap" if spec == "IntMap" else "stringMap"
            body = f"{body[:start]}{AS3_HELPER}.{helper}({body[start:end]}){body[end:]}"
        out.append(text[i:body_open] + body)
        i = body_close
    out.append(text[i:])
    return restore_noncode("".join(out), protected)


NATIVE_IS_TYPE_CHECKS = True
_IS_TYPE_RE = re.compile(rf"(?<![\w$.]){re.escape(AS3_HELPER)}\.isType\(")
_HELPER_IS_TYPES = {"Int", "UInt", "Float", "Bool", "Dynamic", "Class", "Function", "Object"}


def convert_native_is_type_checks(span: str) -> str:
    if not NATIVE_IS_TYPE_CHECKS:
        return span
    text, protected = protect_noncode(span)
    out: list[str] = []
    i = 0
    for match in _IS_TYPE_RE.finditer(text):
        if match.start() < i:
            continue
        close = find_matching_right(text, match.end() - 1)
        if close < 0:
            continue
        args = text[match.end():close]
        depth = 0
        comma = -1
        for j, ch in enumerate(args):
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
            elif ch == "," and depth == 0:
                comma = j
        if comma < 0:
            continue
        value, type_name = args[:comma], args[comma + 1:].strip()
        literal = re.fullmatch(r"__AS3_NONCODE_(\d+)__", type_name)
        if literal and protected[int(literal.group(1))] in ('"Array<Dynamic>"', '"Array"'):
            type_name = "Array"
        if (not re.fullmatch(r"(?:[A-Za-z_][\w$]*\.)*[A-Za-z_][\w$]*", type_name)
                or type_name.rsplit(".", 1)[-1] in _HELPER_IS_TYPES):
            continue
        out.append(text[i:match.start()] + f"Std.isOfType({value}, {type_name})")
        i = close + 1
    out.append(text[i:])
    return restore_noncode("".join(out), protected)


_RAWDATA_STORE_RE = re.compile(r"^([ \t]*)([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*)\.rawData\s*=\s*([^;=\n]+);",
                               re.M)


def convert_native_rawdata_stores(span: str) -> str:
    if ELEMENT_TYPED_CONTAINERS:
        return span
    text, protected = protect_noncode(span)
    text = _RAWDATA_STORE_RE.sub(rf"\1{AS3_HELPER}.setRawData(\2, \3);", text)
    return restore_noncode(text, protected)


_DYNAMIC_TEMP_DECL_RE = re.compile(
    r"(?m)^([ \t]*var (_temp_\d+)):Dynamic(\s*=\s*(?:this|[A-Za-z_$][\w$]*)(?:\.[A-Za-z_$][\w$]*)*;)")


def type_native_receiver_temps(span: str) -> str:
    if ELEMENT_TYPED_CONTAINERS:
        return span
    text, protected = protect_noncode(span)

    def typed(m: re.Match[str]) -> str:
        if m.group(3).lstrip(" \t=").startswith("__AS3_NONCODE_") or re.search(rf"\b{m.group(2)}\s*=(?!=)", text):
            return m.group(0)
        return m.group(1) + m.group(3)

    text = _DYNAMIC_TEMP_DECL_RE.sub(typed, text)
    return restore_noncode(text, protected)


NATIVE_ARRAY_SPLICES = True
_ARRAY_SPLICE_RE = re.compile(rf"(?<![\w$.]){re.escape(AS3_HELPER)}\.arraySplice\(")


def convert_native_array_splices(span: str) -> str:
    if not NATIVE_ARRAY_SPLICES:
        return span
    arrays = set((load_element_types() or {}).get("arrays") or ())
    text, protected = protect_noncode(span)
    arrays |= set(re.findall(r"\bvar\s+([\w$]+)\s*:\s*(?:flash\.)?(?:Array|Vector)<", text))
    out: list[str] = []
    i = 0
    for match in re.finditer(r"\bfunction\s+[A-Za-z_]\w*\s*\(", text):
        if match.start() < i:
            continue
        close_paren = find_matching_right(text, text.find("(", match.start()))
        body_open = text.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(text, body_open) if body_open >= 0 else -1
        if body_close < 0 or ";" in text[close_paren:body_open]:
            continue
        head = text[match.start():body_open]
        body = text[body_open:body_close]
        sites: list[tuple[int, int, str]] = []
        for call in _ARRAY_SPLICE_RE.finditer(body):
            end = find_matching_right(body, call.end() - 1)
            args = split_top_level_commas(body[call.end():end]) if end >= 0 else []
            if len(args) != 3:
                continue
            receiver = args[0].strip()
            if not re.fullmatch(r"(?:[A-Za-z_][\w$]*\.)*[A-Za-z_][\w$]*", receiver):
                continue
            if re.fullmatch(r"_loc\d+_|param\d+", receiver):
                typed = re.search(rf"(?<![\w$]){receiver}\s*:\s*(?:flash\.)?(?:Array|Vector)<", head + body)
            else:
                typed = receiver.rsplit(".", 1)[-1] in arrays
            if typed:
                sites.append((call.start(), end, f"{receiver}.splice({args[1].strip()},{args[2].strip()})"))
        for start, end, replacement in sorted(sites, reverse=True):
            body = body[:start] + replacement + body[end + 1:]
        out.append(text[i:body_open] + body)
        i = body_close
    out.append(text[i:])
    return restore_noncode("".join(out), protected)


def _known_ring_vector_key(key: str) -> bool:
    if "var_10867[param1]" not in key or re.search(r"%\s*128\s*$", key) is None:
        return False
    remaining = key
    for token in (
        f"{AS3_HELPER}.toUInt", "GameApp.var_13575", "var_10867", "param1", "mOffset1", "mOffset2",
    ):
        remaining = remaining.replace(token, "")
    return re.fullmatch(r"[\s\[\]()+%0-9]*", remaining) is not None


def _restore_known_ring_vector_call(span: str, helper: str) -> tuple[str, bool]:
    needle = f"{AS3_HELPER}.{helper}("
    search_end = len(span)
    while True:
        start = span.rfind(needle, 0, search_end)
        if start < 0:
            return span, False
        open_index = start + len(needle) - 1
        close_index = find_matching_right(span, open_index)
        if close_index < 0:
            search_end = start
            continue
        args = split_top_level_commas(span[open_index + 1:close_index])
        if helper == "index" and len(args) == 2 and args[0].strip() == "var_906":
            key = args[1].strip()
            if _known_ring_vector_key(key):
                return span[:start] + f"var_906[{key}]" + span[close_index + 1:], True
        elif helper == "setIndex" and len(args) == 3 and args[0].strip() == "var_906":
            key, value = args[1].strip(), args[2].strip()
            if _known_ring_vector_key(key) and value == "param2":
                return span[:start] + f"var_906[{key}] = param2" + span[close_index + 1:], True
        search_end = start


def restore_known_ring_vector_accesses(span: str) -> str:
    declaration = re.search(
        r"\bclass\s+(?:class|Class)_(129|130|131|132|133)\s+extends\s+(?:class|Class)_128\b",
        span,
    )
    if declaration is None:
        return span
    span = span.replace(f"{AS3_HELPER}.index(var_10867, param1)", "var_10867[param1]")
    for helper in ("setIndex", "index"):
        while True:
            span, changed = _restore_known_ring_vector_call(span, helper)
            if not changed:
                break
    return span


def convert_expressions(text: str) -> str:
    protected_text, protected = protect_noncode(text)
    protected = [
        REGEX_LITERAL_RE.sub(lambda m: f"{m.group('prefix')}{AS3_HELPER}.re("
                             f"{python_string_literal(m.group('body').replace(chr(92) + chr(34), chr(34)))}, "
                             f"{python_string_literal(m.group('flags'))})", span)
        if span.startswith("/") and not span.startswith(("//", "/*")) else span
        for span in protected
    ]
    protected_text = fix_as3_multiplicative_modulo_precedence(protected_text)
    protected_text = fix_as3_bitwise_precedence(protected_text)
    protected_text = re.sub(r"\bundefined\b", "null", protected_text)
    protected_text = re.sub(r"(?<![\.\w])NaN\b", "Math.NaN", protected_text)
    protected_text = re.sub(r"(?<![\.\w])Infinity\b", "Math.POSITIVE_INFINITY", protected_text)
    protected_text = re.sub(r"(?<![\.\w])isNaN\s*\(", "Math.isNaN(", protected_text)
    protected_text = re.sub(r"\bInt\.MAX_VALUE\b", f"{AS3_HELPER}.INT_MAX_VALUE", protected_text)
    protected_text = re.sub(r"\bUInt\.MAX_VALUE\b", f"{AS3_HELPER}.UINT_MAX_VALUE", protected_text)
    protected_text = re.sub(r"\bFloat\.MAX_VALUE\b", f"{AS3_HELPER}.FLOAT_MAX_VALUE", protected_text)
    protected_text = re.sub(r"\b(U?Int|Float)\.MIN_VALUE\b",
                            lambda m: f"{AS3_HELPER}.{m.group(1).upper()}_MIN_VALUE", protected_text)
    protected_text = convert_parenthesized_new(protected_text)
    protected_text = convert_xml_literals(protected_text)
    protected_text = convert_as_is_operators(protected_text)
    protected_text = convert_regex_literals(protected_text)
    protected_text = convert_regex_splits(protected_text, protected)
    protected_text = convert_delete_operators(protected_text)
    protected_text = convert_layer_idioms(protected_text)
    protected_text = force_mixed_array_literals(protected_text)
    protected_text = convert_object_literal_index(protected_text)
    protected_text = convert_e4x_attributes(protected_text)
    protected_text = convert_reserved_property_access(protected_text)
    protected_text = convert_typeof_operators(protected_text)
    protected_text = convert_coercion_calls(protected_text)
    protected_text = convert_wide_bitwise_literals(protected_text)
    protected_text = convert_mathmax_compound_position(protected_text)
    protected_text = stringify_concat_ternary_numbers(protected_text)
    own = CLASS_RE.search(protected_text)
    protected_text = coerce_layer_int_arguments(protected_text, own.group(1) if own else None)
    protected_text = coerce_string_parameter_arguments(protected_text)
    protected_text = convert_comma_expressions(protected_text)
    protected_text = convert_for_in_loops(protected_text)
    protected_text = convert_in_operators(protected_text)
    protected_text = convert_index_assignments(protected_text)
    protected_text = convert_length_assignments(protected_text)
    protected_text = convert_index_reads(protected_text)
    protected_text = convert_numeric_dynamic_operations(protected_text)
    protected_text = convert_dynamic_field_access(protected_text)
    protected_text = convert_as3_string_methods(protected_text)
    protected_text = convert_as3_number_methods(protected_text)
    protected_text = convert_as3_array_methods(protected_text)
    protected_text = convert_remove_child_calls(protected_text)
    protected_text = convert_error_name_reads(protected_text)
    protected_text = convert_flash_constants(protected_text)
    protected_text = convert_numeric_not_expressions(protected_text)
    protected_text = convert_comparison_chain_booleans(protected_text)
    protected_text = convert_logical_value_expressions(protected_text)
    protected_text = convert_parenthesized_logical_values(protected_text)
    protected_text = convert_logical_boolean_assignments(protected_text)
    protected_text = fix_logical_bitwise_zero_comparisons(protected_text)
    protected_text = convert_ternary_truthiness(protected_text)
    protected_text = convert_truthy_conditions(protected_text)
    protected_text = convert_logical_operand_truthiness(protected_text)
    protected_text = fix_logical_bitwise_zero_comparisons(protected_text)
    protected_text = convert_typed_var_initializers(protected_text)
    protected_text = convert_reference_typed_initializers(protected_text)
    protected_text = convert_flash_abstract_compatibility(protected_text)
    protected_text = convert_known_argument_coercions(protected_text)
    protected_text = convert_call_argument_logical_or(protected_text)
    protected_text = convert_coercion_logical_or(protected_text)
    protected_text = fix_numeric_comparison_or_guard(protected_text)
    protected_text = fix_casted_index_as_type(protected_text)
    protected_text = fix_numeric_value_property_coercion(protected_text)
    protected_text = fix_malformed_logical_or_bool_call(protected_text)
    protected_text = convert_known_screen_assignment_casts(protected_text)
    protected_text = fix_type_frontier_value_shapes(protected_text)
    protected_text = fix_malformed_if_not_bitwise_comparison(protected_text)
    protected_text = fix_boolean_numeric_comparisons(protected_text)
    protected_text = fix_logical_bitwise_operand_truthiness(protected_text)
    protected_text = fix_boolean_numeric_comparisons(protected_text)
    protected_text = fix_logical_null_comparisons(protected_text)
    protected_text = convert_negated_logical_values(protected_text)
    protected_text = convert_unused_rest_callbacks(protected_text)
    protected_text = restore_literal_comparisons(protected_text)
    protected_text = re.sub(r"=\(=\s*null\)", "== null", protected_text)
    protected_text = re.sub(r"\bif\(\((?P<cond>[^;\n?]+\|\|[^;\n?]+== null)\s*\?", r"if((\g<cond>) ?", protected_text)
    protected_text = re.sub(r"=\(=\s*port\.runtime\.As3\.toBool\(([^)]+)\)\s*\?", r"== \1 ?", protected_text)
    protected_text = re.sub(r"=\(=\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*\?", r"== \1 ?", protected_text)
    protected_text = re.sub(r"=\(=\s*(-?\d+)\s*\?", r"== \1 ?", protected_text)
    protected_text = re.sub(
        r"(testCommunity)\(port\.runtime\.As3\.index\(c\.args,\s*0\)\)\s*==\s*\"get\"\s*\?\s*(port\.runtime\.As3\.toInt\(port\.runtime\.As3\.index\(c\.args,\s*1\)\))\s*:\s*(-?\d+)",
        '\\1(port.runtime.As3.index(c.args, 0) == "get" ? \\2:\\3)',
        protected_text,
    )
    return restore_noncode(protected_text, protected)


NEGATED_LOGICAL_RE = re.compile(r"!\s*(\(\s*)?" + re.escape(AS3_HELPER) + r"\.logical(?:Or|And)\(")


def convert_negated_logical_values(span: str) -> str:
    out: list[str] = []
    at = 0
    for m in NEGATED_LOGICAL_RE.finditer(span):
        if m.start() < at:
            continue
        call_open = m.end() - 1
        call_close = _matching_bracket(span, call_open)
        if call_close < 0:
            continue
        if m.group(1):
            paren = m.start(1)
            close = _matching_bracket(span, paren)
            if close < 0 or span[call_close + 1:close].strip():
                continue
            inner = span[paren + 1:close].strip()
        else:
            close = call_close
            inner = span[m.start() + 1:close + 1].strip()
        out.append(span[at:m.start()])
        out.append(f"!{AS3_HELPER}.toBool({convert_negated_logical_values(inner)})")
        at = close + 1
    out.append(span[at:])
    return "".join(out)


UNUSED_REST_RE = re.compile(r"\bfunction\s*\((?P<params>[^()]*?)(?P<sep>,\s*)?\.\.\.(?P<name>\w+)(?::[\w<>]+)?\)"
                            r"(?P<ret>\s*:\s*[\w<>]+)?\s*\{")


def convert_unused_rest_callbacks(span: str) -> str:
    out: list[str] = []
    at = 0
    for m in UNUSED_REST_RE.finditer(span):
        if m.start() < at:
            continue
        body_open = m.end() - 1
        body_close = _matching_bracket(span, body_open)
        if body_close < 0 or re.search(rf"\b{re.escape(m.group('name'))}\b", span[body_open:body_close]):
            continue
        params = m.group("params").strip()
        extra = ", ".join(f"?__rest{i}:Dynamic" for i in range(1, 4))
        out.append(span[at:m.start()])
        out.append(f"function({params + ', ' if params else ''}{extra}){m.group('ret') or ''} {{")
        at = m.end()
    out.append(span[at:])
    return "".join(out)


def fix_as3_multiplicative_modulo_precedence(span: str) -> str:
    atom = r"(?:[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*|-?\d+(?:\.\d+)?)"
    chain = rf"(?P<chain>{atom}(?:\s*[*/]\s*{atom})+)\s*%"
    return re.sub(chain, lambda match: f"({match.group('chain')}) %", span)


_BITWISE_LEVELS = (("|",), ("^",), ("&",), ("==", "!=", "===", "!=="), ("<", ">", "<=", ">="))
_BITWISE_BOUNDARY_OPS = {"=", "+=", "-=", "*=", "/=", "%=", "|=", "&=", "^=", "<<=", ">>=", ">>>=", "&&", "||",
                         "&&=", "||="}


def _bitwise_operator_at(text: str, i: int) -> str | None:
    for op in (">>>=", "===", "!==", ">>>", "<<=", ">>=", "&&=", "||=", "==", "!=", "<=", ">=", "&&", "||", "|=",
               "&=", "^=", "+=", "-=", "*=", "/=", "%=", "<<", ">>", "|", "&", "^", "<", ">", "="):
        if text.startswith(op, i):
            return op
    return None


def _regroup_bitwise_segment(parts: list[str], ops: list[str]) -> str:
    def build(lo: int, hi: int, level: int) -> tuple[str, int | None]:
        if lo == hi:
            return parts[lo], None
        for lv in range(level, len(_BITWISE_LEVELS)):
            cuts = [k for k in range(lo, hi) if ops[k] in _BITWISE_LEVELS[lv]]
            if not cuts:
                continue
            pieces = []
            start = lo
            for k in cuts + [hi]:
                text, inner = build(start, k, lv + 1)
                if inner is not None and not (start == lo and inner <= 2):
                    lead = len(text) - len(text.lstrip())
                    trail = len(text) - len(text.rstrip())
                    text = text[:lead] + "(" + text.strip() + ")" + text[len(text) - trail:]
                pieces.append(text)
                start = k + 1
            out = pieces[0]
            for k, piece in zip(cuts, pieces[1:]):
                out += ops[k] + piece
            return out, lv
        raise AssertionError("every operator belongs to a level")

    return build(0, len(parts) - 1, 0)[0]


def fix_as3_bitwise_precedence(span: str) -> str:
    out: list[str] = []
    seg_parts: list[str] = []
    seg_ops: list[str] = []
    current: list[str] = []

    def flush() -> None:
        seg_parts.append("".join(current))
        current.clear()
        kinds = {op for op in seg_ops if op in ("|", "^", "&")}
        compares = any(op not in ("|", "^", "&") for op in seg_ops)
        whole = seg_parts[0] + "".join(op + part for op, part in zip(seg_ops, seg_parts[1:]))
        if (len(kinds) >= 2 or (kinds and compares)) and "\\" not in whole and ".<" not in whole:
            out.append(_regroup_bitwise_segment(seg_parts, seg_ops))
        else:
            out.append(whole)
        seg_parts.clear()
        seg_ops.clear()

    i = 0
    while i < len(span):
        ch = span[i]
        if ch in "([{":
            close = _matching_bracket(span, i)
            if close < 0:
                current.append(span[i:])
                break
            current.append(ch + fix_as3_bitwise_precedence(span[i + 1:close]) + span[close])
            i = close + 1
            continue
        if ch in ",;?:\n":
            flush()
            out.append(ch)
            i += 1
            continue
        keyword = re.match(r"(?:return|throw|case|else|do)\b", span[i:i + 7]) if (
            ch.isalpha() and (i == 0 or not (span[i - 1].isalnum() or span[i - 1] in "_$."))) else None
        if keyword:
            flush()
            out.append(keyword.group(0))
            i += len(keyword.group(0))
            continue
        op = _bitwise_operator_at(span, i)
        if op in ("<<", ">>", ">>>"):
            current.append(op)
            i += len(op)
        elif op in _BITWISE_BOUNDARY_OPS:
            flush()
            out.append(op)
            i += len(op)
        elif op is not None:
            seg_parts.append("".join(current))
            current.clear()
            seg_ops.append(op)
            i += len(op)
        else:
            current.append(ch)
            i += 1
    flush()
    return "".join(out)


def _matching_bracket(span: str, open_index: int) -> int:
    pairs = {"(": ")", "[": "]", "{": "}"}
    stack = [pairs[span[open_index]]]
    i = open_index + 1
    while i < len(span):
        ch = span[i]
        if ch in pairs:
            stack.append(pairs[ch])
        elif ch in ")]}":
            if ch != stack[-1]:
                return -1
            stack.pop()
            if not stack:
                return i
        i += 1
    return -1


def convert_package_function_imports(text: str) -> str:
    used: set[str] = set()

    def import_repl(match: re.Match[str]) -> str:
        path = match.group(2)
        if path not in PACKAGE_FUNCTIONS:
            return match.group(0)
        used.add(PACKAGE_FUNCTIONS[path])
        return ""

    text = IMPORT_RE.sub(import_repl, text)
    if not used:
        return text

    def one(span: str) -> str:
        for name in sorted(used, key=len, reverse=True):
            span = re.sub(rf"(?<![\.\w])(?<!function\s){re.escape(name)}\s*\(", f"{AS3_HELPER}.{name}(", span)
        return span

    return transform_code(text, one)


def convert_package_function_calls(text: str) -> str:
    names = sorted(set(PACKAGE_FUNCTIONS.values()), key=len, reverse=True)
    qualified = sorted(PACKAGE_FUNCTIONS.items(), key=lambda item: len(item[0]), reverse=True)

    def one(span: str) -> str:
        for path, name in qualified:
            span = re.sub(rf"(?<![\.\w]){re.escape(path)}\s*\(", f"{AS3_HELPER}.{name}(", span)
        for name in names:
            span = re.sub(rf"(?<![\.\w])(?<!function\s){re.escape(name)}\s*\(", f"{AS3_HELPER}.{name}(", span)
        return span

    return transform_code(text, one)


def qualify_big_window_members(text: str, parent_name: str | None) -> str:
    if parent_name not in {"BigWindow", "SettingsWindow", "PostMatchStatsWindow", "LobbySettingsScreen"}:
        return text

    def one(span: str) -> str:
        if parent_name in {"BigWindow", "SettingsWindow", "PostMatchStatsWindow"}:
            for name in ("HEIGHT", "HALF", "LEFT", "TOP"):
                span = re.sub(rf"(?<![\w.]){name}\b", f"bh.platform.BigWindow.{name}", span)
        if parent_name in {"SettingsWindow", "LobbySettingsScreen"}:
            for name in ("iconSelected", "kindOf", "labelOf", "localized", "optionName", "rowHeight", "textOf", "valueOf"):
                span = re.sub(rf"(?<![\w.]){name}\s*\(", f"bh.platform.SettingsWindow.{name}(", span)
        return span

    return transform_code(text, one)


def normalize_legacy_haxe_internal_imports(text: str) -> str:
    def repl(match: re.Match[str]) -> str:
        path = match.group(2)
        return f"{match.group(1)}import {LEGACY_HAXE_INTERNAL_IMPORTS.get(path, path)};"

    return IMPORT_RE.sub(repl, text)


E4X_TYPE_RE = re.compile(r"(?<![\w.])(?:XML|XMLList)\b")


def import_e4x_types(text: str) -> str:
    if not any(is_code and E4X_TYPE_RE.search(span) for is_code, span in split_code(text)):
        return text
    start = len(text) - len(text.lstrip("\n"))
    return f"{text[:start]}   import port.runtime.E4X;\n{text[start:]}"


def normalize_haxe_type_names(text: str) -> str:
    return transform_code(text, lambda span: OBFUSCATED_CLASS_RE.sub(r"Class_\1", span))


STD_SHADOW_RENAMES = {"Xml": "LegacyXml"}
STD_SHADOW_XML_PACKAGE_RENAMES = {
    "Parser": "LegacyParser",
    "Printer": "LegacyPrinter",
    "XmlParserException": "LegacyXmlParserException",
}
STD_SHADOW_TYPE_RE = re.compile(r"(?<![\w.$])Xml(?![\w$])")
STD_SHADOW_QUALIFIED_RE = re.compile(r"\bhaxe\.xml\.(Parser|Printer|XmlParserException)(?![\w$])")
STD_SHADOW_BARE_RE = re.compile(r"(?<![\w.$])(Parser|Printer|XmlParserException)(?![\w$])")


def rename_std_shadowing_types(text: str, package_name: str | None) -> str:
    bare = package_name == "haxe.xml" or STD_SHADOW_QUALIFIED_RE.search(text) is not None

    def one(span: str) -> str:
        span = STD_SHADOW_TYPE_RE.sub(STD_SHADOW_RENAMES["Xml"], span)
        span = STD_SHADOW_QUALIFIED_RE.sub(lambda m: f"haxe.xml.{STD_SHADOW_XML_PACKAGE_RENAMES[m.group(1)]}", span)
        if bare:
            span = STD_SHADOW_BARE_RE.sub(lambda m: STD_SHADOW_XML_PACKAGE_RENAMES[m.group(1)], span)
        return span

    return transform_code(text, one)


def std_shadow_output_stem(rel: Path) -> str:
    if rel.parent == Path(".") and rel.stem in STD_SHADOW_RENAMES:
        return STD_SHADOW_RENAMES[rel.stem]
    if rel.parent == Path("haxe") / "xml" and rel.stem in STD_SHADOW_XML_PACKAGE_RENAMES:
        return STD_SHADOW_XML_PACKAGE_RENAMES[rel.stem]
    return rel.stem


def vector_casts(span: str) -> str:
    out: list[str] = []
    i = 0
    marker = "Vector<"
    while True:
        start = span.find(marker, i)
        if start < 0:
            out.append(span[i:])
            return "".join(out)
        out.append(span[i:start])
        type_start = start + len(marker)
        type_end = find_generic_type_end(span, type_start)
        if type_end < 0:
            out.append(span[start:])
            return "".join(out)
        call_start = skip_space_right(span, type_end + 1)
        if call_start >= len(span) or span[call_start] != "(":
            out.append(span[start:call_start])
            i = call_start
            continue
        prefix = span[max(0, start - 4):start]
        if prefix == "new ":
            out.append(span[start:call_start + 1])
            i = call_start + 1
            continue
        element = span[type_start:type_end].strip()
        call_close = find_matching_right(span, call_start)
        if element in ("UInt", "Float") and call_close > 0:
            inner = vector_casts(span[call_start + 1:call_close])
            out.append(f"Vector.ofArray(({inner} : Array<{element}>))")
            i = call_close + 1
            continue
        out.append("Vector.ofArray(")
        i = call_start + 1


def convert_dynamic_new(span: str) -> str:
    return re.sub(
        r"\bnew\s+((?!class_\d+\b)[a-z_]\w*)\s*\(\s*\)",
        lambda m: f"{AS3_HELPER}.newInstance({m.group(1)})",
        span,
    )


def convert_parenthesized_new(span: str) -> str:
    out: list[str] = []
    i = 0
    for match in re.finditer(r"\bnew\s*\(", span):
        if match.start() < i:
            continue
        class_open = match.end() - 1
        class_close = find_matching_right(span, class_open)
        if class_close < 0:
            continue
        j = class_close + 1
        while j < len(span) and span[j] in " \t":
            j += 1
        args_close = find_matching_right(span, j) if j < len(span) and span[j] == "(" else -1
        if args_close < 0:
            continue
        cls = convert_parenthesized_new(span[class_open + 1:class_close].strip())
        args = convert_parenthesized_new(span[j + 1:args_close].strip())
        out.append(span[i:match.start()])
        out.append(f"{AS3_HELPER}.createInstance({cls}, [{args}])")
        i = args_close + 1
    out.append(span[i:])
    return "".join(out)


def convert_as_is_operators(span: str) -> str:
    for operator, helper in (("as", "asType"), ("is", "isType")):
        span = convert_binary_type_operator(span, operator, helper)
    return span


def convert_binary_type_operator(span: str, operator: str, helper: str) -> str:
    i = 0
    while True:
        match = re.search(rf"\s+{operator}\s+", span[i:])
        if not match:
            return span
        op_start = i + match.start()
        op_end = i + match.end()
        if not is_word_operator(span, op_start, op_end, operator):
            i = op_end
            continue
        expr_start = find_expression_start(span, op_start)
        type_end = find_type_end(span, op_end)
        if expr_start < 0 or type_end <= op_end:
            i = op_end
            continue
        expression = span[expr_start:op_start].strip()
        type_name = span[op_end:type_end].strip()
        if not expression or not type_name:
            i = op_end
            continue
        replacement = f"{AS3_HELPER}.{helper}({expression}, {haxe_type_value(type_name)})"
        span = span[:expr_start] + replacement + span[type_end:]
        i = expr_start + len(replacement)


def is_word_operator(span: str, op_start: int, op_end: int, operator: str) -> bool:
    word_start = span.find(operator, op_start, op_end)
    before = span[word_start - 1] if word_start > 0 else ""
    after = span[word_start + len(operator)] if word_start + len(operator) < len(span) else ""
    return not (is_identifier_char(before) or is_identifier_char(after))


def is_identifier_char(ch: str) -> bool:
    return ch.isalnum() or ch in "_$"


def find_expression_start(span: str, op_start: int) -> int:
    i = skip_space_left(span, op_start - 1)
    if i < 0:
        return -1
    start = parse_atom_left(span, i)
    if start < 0:
        return -1
    while True:
        j = skip_space_left(span, start - 1)
        if j < 0:
            return start
        if span[j] == ".":
            lhs = parse_atom_left(span, skip_space_left(span, j - 1))
            if lhs < 0:
                return start
            start = lhs
            continue
        if span[j] in ("!", "~") and (j == 0 or not is_identifier_char(span[j - 1])):
            start = j
            continue
        return start


def parse_atom_left(span: str, end: int) -> int:
    if end < 0:
        return -1
    if span[end] in (")", "]"):
        start = find_matching_left(span, end)
        if start < 0:
            return -1
        j = skip_space_left(span, start - 1)
        if j >= 0 and span[j] in (")", "]"):
            lhs = parse_atom_left(span, j)
            if lhs >= 0:
                return lhs
        while j >= 0 and (is_identifier_char(span[j]) or span[j] == "."):
            j -= 1
        start = j + 1
        if start <= end and span[start] == ".":
            lhs = parse_atom_left(span, skip_space_left(span, start - 1))
            if lhs >= 0:
                return lhs
            while start < end and span[start] == ".":
                start += 1
        return start
    i = end
    while i >= 0 and (is_identifier_char(span[i]) or span[i] == "."):
        i -= 1
    start = i + 1
    if start <= end and span[start] == ".":
        lhs = parse_atom_left(span, skip_space_left(span, start - 1))
        if lhs >= 0:
            return lhs
        while start < end and span[start] == ".":
            start += 1
    return start if start <= end else -1


def find_matching_left(span: str, close_index: int) -> int:
    close_ch = span[close_index]
    open_ch = "(" if close_ch == ")" else "["
    depth = 0
    i = close_index
    while i >= 0:
        ch = span[i]
        if ch == close_ch:
            depth += 1
        elif ch == open_ch:
            depth -= 1
            if depth == 0:
                return i
        i -= 1
    return -1


def skip_space_left(span: str, index: int) -> int:
    while index >= 0 and span[index].isspace():
        index -= 1
    return index


def find_type_end(span: str, index: int) -> int:
    i = index
    depth = 0
    while i < len(span):
        ch = span[i]
        if ch == "<":
            depth += 1
        elif ch == ">":
            if depth == 0:
                break
            depth -= 1
        elif depth == 0 and not (is_identifier_char(ch) or ch in ".*"):
            break
        i += 1
    return i


def convert_in_operators(span: str) -> str:
    i = 0
    while True:
        match = re.search(r"\s+in\s+", span[i:])
        if not match:
            return span
        op_start = i + match.start()
        op_end = i + match.end()
        if not is_word_operator(span, op_start, op_end, "in"):
            i = op_end
            continue
        expr_start = find_expression_start(span, op_start)
        target_end = find_expression_end(span, op_end)
        if expr_start < 0 or target_end <= op_end:
            i = op_end
            continue
        if is_for_header_before(span, expr_start):
            i = op_end
            continue
        key = span[expr_start:op_start].strip()
        target = span[op_end:target_end].strip()
        replacement = f"{AS3_HELPER}.hasKey({target}, {key})"
        span = span[:expr_start] + replacement + span[target_end:]
        i = expr_start + len(replacement)


def is_for_header_before(span: str, expr_start: int) -> bool:
    j = skip_space_left(span, expr_start - 1)
    if j < 0 or span[j] != "(":
        return False
    word_end = skip_space_left(span, j - 1) + 1
    word_start = word_end - 1
    while word_start >= 0 and is_identifier_char(span[word_start]):
        word_start -= 1
    return span[word_start + 1:word_end] == "for"


def find_expression_end(span: str, index: int) -> int:
    i = skip_space_right(span, index)
    if i >= len(span):
        return i
    end = parse_atom_right(span, i)
    return end if end >= 0 else i


def parse_atom_right(span: str, start: int) -> int:
    if start >= len(span):
        return -1
    if span[start] in ("(", "["):
        close = find_matching_right(span, start)
        if close < 0:
            return -1
        return close + 1
    if span[start].isdigit():
        i = start + 1
        while i < len(span) and (span[i].isdigit() or span[i] == "."):
            i += 1
        return i
    i = start
    while i < len(span) and (is_identifier_char(span[i]) or span[i] == "."):
        i += 1
    while i < len(span) and span[i] == "[":
        close = find_matching_right(span, i)
        if close < 0:
            break
        i = close + 1
    return i if i > start else -1


def find_matching_right(span: str, open_index: int) -> int:
    open_ch = span[open_index]
    close_ch = {"(": ")", "[": "]", "{": "}"}.get(open_ch)
    if close_ch is None:
        return -1
    depth = 0
    i = open_index
    while i < len(span):
        ch = span[i]
        if ch == open_ch:
            depth += 1
        elif ch == close_ch:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def skip_space_right(span: str, index: int) -> int:
    while index < len(span) and span[index].isspace():
        index += 1
    return index


def convert_try_finally(text: str) -> str:
    span, protected = protect_noncode(text)
    out: list[str] = []
    i = 0
    while True:
        match = re.search(r"\btry\b", span[i:])
        if not match:
            out.append(span[i:])
            return restore_noncode("".join(out), protected)
        start = i + match.start()
        block_open = skip_space_right(span, start + len("try"))
        if block_open >= len(span) or span[block_open] != "{":
            out.append(span[i:start + len("try")])
            i = start + len("try")
            continue
        try_close = find_matching_right(span, block_open)
        if try_close < 0:
            out.append(span[i:start + len("try")])
            i = start + len("try")
            continue
        after_try = skip_space_right(span, try_close + 1)
        catch_start = after_try
        catch_end = after_try
        while span.startswith("catch", catch_end):
            catch_paren = skip_space_right(span, catch_end + len("catch"))
            if catch_paren >= len(span) or span[catch_paren] != "(":
                break
            catch_paren_end = find_matching_right(span, catch_paren)
            if catch_paren_end < 0:
                break
            catch_block_open = skip_space_right(span, catch_paren_end + 1)
            if catch_block_open >= len(span) or span[catch_block_open] != "{":
                break
            catch_block_end = find_matching_right(span, catch_block_open)
            if catch_block_end < 0:
                break
            catch_end = skip_space_right(span, catch_block_end + 1)
        finally_start = catch_end
        if not span.startswith("finally", finally_start):
            out.append(span[i:start + len("try")])
            i = start + len("try")
            continue
        finally_open = skip_space_right(span, finally_start + len("finally"))
        if finally_open >= len(span) or span[finally_open] != "{":
            out.append(span[i:start + len("try")])
            i = start + len("try")
            continue
        finally_close = find_matching_right(span, finally_open)
        if finally_close < 0:
            out.append(span[i:start + len("try")])
            i = start + len("try")
            continue

        try_body = span[block_open + 1:try_close]
        catches = span[catch_start:catch_end]
        cleanup = span[finally_open + 1:finally_close]
        if catches and re.search(r"\breturn\b", try_body + catches):
            body = f"try\n{{{try_body}\n}}{catches}"
            replacement = f"return {AS3_HELPER}.finallyValue(function():Dynamic {{{body}\n}}, function():Void {{{cleanup}\n}});"
        elif catches:
            body = f"try\n{{{try_body}\n}}{catches}"
            replacement = f"{AS3_HELPER}.finallyRun(function():Void {{{body}\n}}, function():Void {{{cleanup}\n}});"
        elif re.search(r"\breturn\b", try_body):
            replacement = f"return {AS3_HELPER}.finallyValue(function():Dynamic {{{try_body}\n}}, function():Void {{{cleanup}\n}});"
        else:
            replacement = f"{AS3_HELPER}.finallyRun(function():Void {{{try_body}\n}}, function():Void {{{cleanup}\n}});"
        out.append(span[i:start])
        out.append(replacement)
        i = finally_close + 1


LOOP_HEAD_RE = re.compile(r"\b(?:while|for|do)\b")
SIMPLE_RETURN_RE = re.compile(
    r"return(?:[ \t]+(?:[A-Za-z_]\w*|-?\d+(?:\.\d+)?|true|false|null|__AS3_NONCODE_\d+__))?[ \t]*;"
)


def labeled_breaks_across_loops(span: str) -> list[tuple[str, int, int, int]]:
    found: list[tuple[str, int, int, int]] = []
    for match in re.finditer(r"(?m)^[ \t]*(loop\d+):\s*\n[ \t]*switch\s*\(", span):
        label = match.group(1)
        block_open = span.find("{", match.end())
        block_close = find_matching_right(span, block_open)
        if block_open < 0 or block_close < 0:
            continue
        for use in re.finditer(rf"\bbreak\s+{label}\s*;", span[block_open:block_close]):
            use_start = block_open + use.start()
            depth_loops = 0
            index = use_start
            while True:
                opener = find_enclosing_open_brace(span, index, block_open)
                if opener <= block_open:
                    break
                head = span[span.rfind("\n", 0, span.rfind("\n", 0, opener)) + 1:opener]
                if LOOP_HEAD_RE.search(head):
                    depth_loops += 1
                index = opener
            if depth_loops:
                found.append((label, use_start, block_open + use.end(), block_close))
    return found


def find_enclosing_open_brace(span: str, index: int, floor: int) -> int:
    depth = 0
    for pos in range(index - 1, floor - 1, -1):
        char = span[pos]
        if char == "}":
            depth += 1
        elif char == "{":
            if depth == 0:
                return pos
            depth -= 1
    return floor


def lower_switch_label_exits_across_loops(text: str) -> str:
    span, protected = protect_noncode(text)
    for _, use_start, use_end, block_close in reversed(labeled_breaks_across_loops(span)):
        follow = SIMPLE_RETURN_RE.match(span, skip_space_right(span, block_close + 1))
        if follow:
            span = span[:use_start] + follow.group(0) + span[use_end:]
    return restore_noncode(span, protected)


def convert_labeled_breaks(text: str) -> str:
    def one(span: str) -> str:
        span = re.sub(r"^(\s*)loop\d+:\s*\n", "", span, flags=re.MULTILINE)
        span = re.sub(r"\bbreak\s+loop\d+\s*;", "break;", span)
        span = re.sub(r"\bcontinue\s+loop\d+\s*;", "continue;", span)
        return span

    return transform_code(text, one)


def wrap_switch_statements(text: str) -> str:
    span, protected = protect_noncode(text)
    return restore_noncode(_wrap_switches(span, [0]), protected)


def _wrap_switches(span: str, counter: list[int]) -> str:
    out: list[str] = []
    i = 0
    while True:
        match = re.search(r"\bswitch\s*\(", span[i:])
        if not match:
            out.append(span[i:])
            return "".join(out)
        start = i + match.start()
        paren = span.find("(", start)
        close_paren = find_matching_right(span, paren)
        if close_paren < 0:
            out.append(span[i:start + len("switch")])
            i = start + len("switch")
            continue
        block_open = skip_space_right(span, close_paren + 1)
        if block_open >= len(span) or span[block_open] != "{":
            out.append(span[i:close_paren + 1])
            i = close_paren + 1
            continue
        block_close = find_matching_right(span, block_open)
        if block_close < 0:
            out.append(span[i:block_open + 1])
            i = block_open + 1
            continue
        indent = line_indent(span, start)
        inner = _wrap_switches(span[block_open + 1:block_close], counter)
        switch_src = span[start:block_open + 1] + inner + "}"
        out.append(span[i:start])
        out.append(_shim_switch(switch_src, block_open - start, indent, counter))
        i = block_close + 1


SWITCH_LOOP_KEYWORDS = {"while", "for", "do", "each"}


def _block_keyword(span: str, opener: int) -> str:
    j = skip_space_left(span, opener - 1)
    if j >= 0 and span[j] == ")":
        left = find_matching_left(span, j)
        if left < 0:
            return ""
        j = skip_space_left(span, left - 1)
    end = j + 1
    while j >= 0 and (span[j].isalnum() or span[j] == "_"):
        j -= 1
    return span[j + 1:end]


def switch_direct_jumps(switch_src: str, block_open: int, keyword: str) -> list[tuple[int, int]]:
    found: list[tuple[int, int]] = []
    block_close = len(switch_src) - 1
    for use in re.finditer(rf"\b{keyword}\s*;", switch_src[block_open + 1:block_close]):
        pos = block_open + 1 + use.start()
        index = pos
        direct = True
        while True:
            opener = find_enclosing_open_brace(switch_src, index, block_open)
            if opener <= block_open:
                break
            if _block_keyword(switch_src, opener) in SWITCH_LOOP_KEYWORDS:
                direct = False
                break
            index = opener
        if direct:
            found.append((pos, block_open + 1 + use.end()))
    return found


def _shim_switch(switch_src: str, block_open: int, indent: str, counter: list[int]) -> str:
    if switch_direct_jumps(switch_src, block_open, "break"):
        stripped = strip_terminal_case_breaks(switch_src)
        if not switch_direct_jumps(stripped, block_open, "break"):
            switch_src = stripped
    if not switch_direct_jumps(switch_src, block_open, "break"):
        return switch_src
    continues = switch_direct_jumps(switch_src, block_open, "continue")
    flag = ""
    if continues:
        counter[0] += 1
        flag = f"_switchContinue{counter[0]}"
        for use_start, use_end in reversed(continues):
            switch_src = switch_src[:use_start] + f"{{ {flag} = true; break; }}" + switch_src[use_end:]
    shim = f"while(true)\n{indent}{{\n{indent}   {switch_src}\n{indent}   break;\n{indent}}}"
    if not flag:
        return shim
    return (f"var {flag}:Bool = false;\n{indent}{shim}\n"
            f"{indent}if({flag})\n{indent}{{\n{indent}   continue;\n{indent}}}")


SWITCH_CASE_LABEL_RE = re.compile(r"(?m)^[ \t]*(?:case\b[^\n]*?|default[ \t]*):[ \t]*$")


def switch_case_bodies(switch_src: str) -> list[tuple[int, int]] | None:
    block_open = switch_src.find("{", switch_src.find(")"))
    block_close = find_matching_right(switch_src, block_open)
    if block_open < 0 or block_close < 0:
        return None
    labels: list[tuple[int, int]] = []
    depth = 0
    index = block_open + 1
    while index < block_close:
        char = switch_src[index]
        if char in "{([":
            depth += 1
        elif char in "})]":
            depth -= 1
        elif depth == 0 and (index == 0 or switch_src[index - 1] == "\n"):
            match = SWITCH_CASE_LABEL_RE.match(switch_src, index, block_close)
            if match:
                labels.append((match.start(), match.end()))
                index = match.end()
                continue
        index += 1
    if not labels or switch_src[block_open + 1:labels[0][0]].strip():
        return None
    ends = [start for start, _ in labels[1:]] + [block_close]
    return [(label_end, end) for (_, label_end), end in zip(labels, ends)]


def strip_terminal_case_breaks(switch_src: str) -> str:
    bodies = switch_case_bodies(switch_src)
    if not bodies:
        return switch_src
    out: list[str] = []
    last = 0
    for start, end in bodies:
        body = switch_src[start:end]
        match = re.search(r"\n[ \t]*break[ \t]*;[ \t]*(?=\s*$)", body)
        if match:
            out.append(switch_src[last:start + match.start()])
            last = start + match.end()
    out.append(switch_src[last:])
    return "".join(out)


def switch_fallthrough_cases(text: str) -> list[str]:
    span, _ = protect_noncode(text)
    found: list[str] = []
    for match in re.finditer(r"\bswitch\s*\(", span):
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        if close_paren < 0:
            continue
        block_open = skip_space_right(span, close_paren + 1)
        if block_open >= len(span) or span[block_open] != "{":
            continue
        block_close = find_matching_right(span, block_open)
        if block_close < 0:
            continue
        switch_src = span[match.start():block_close + 1]
        bodies = switch_case_bodies(switch_src)
        if not bodies:
            continue
        for start, end in bodies[:-1]:
            body = switch_src[start:end].strip()
            if not body:
                continue
            if re.search(r"(?:^|[;{}\s])(?:break|continue)(?:[ \t]+\w+)?[ \t]*;$", body):
                continue
            if re.search(r"(?:^|[;{}\s])(?:return|throw)\b[^;]*;$", body):
                continue
            label = switch_src[:start].rstrip().rsplit("\n", 1)[-1].strip()
            found.append(label)
    return found


def collapse_empty_integer_case_groups(text: str) -> str:
    span, protected = protect_noncode(text)
    label = r"(?:-?(?:0|[1-9][0-9]*)|__AS3_NONCODE_[0-9]+__)"
    pattern = re.compile(
        rf"(?m)^(?P<indent>[ \t]*)case[ \t]+(?P<first>{label})[ \t]*:"
        rf"(?P<tail>(?:(?:[ \t]*\r?\n)+(?P=indent)case[ \t]+{label}[ \t]*:)+)"
    )

    def is_literal(item: str) -> bool:
        marker = re.fullmatch(r"__AS3_NONCODE_([0-9]+)__", item)
        return marker is None or protected[int(marker.group(1))][:1] in {'"', "'"}

    def grouped(match: re.Match[str]) -> str:
        labels = re.findall(rf"\bcase[ \t]+({label})[ \t]*:", match.group(0))
        if not all(is_literal(item) for item in labels):
            return match.group(0)
        return f"{match.group('indent')}case {', '.join(labels)}:"

    BREAK = "\x00\n"
    span = re.sub(r"__AS3_NONCODE_([0-9]+)__",
                  lambda m: m.group(0) + BREAK if protected[int(m.group(1))].endswith("\n") else m.group(0), span)
    return restore_noncode(pattern.sub(grouped, span).replace(BREAK, ""), protected)


def haxe_type_value(type_name: str) -> str:
    if type_name in {"IMap"}:
        return python_string_literal(type_name)
    if "<" in type_name or ">" in type_name:
        return python_string_literal(type_name)
    return type_name


def convert_regex_literals(span: str) -> str:
    def one(match: re.Match[str]) -> str:
        body = match.group("body").replace('\\"', '"')
        literal = python_string_literal(body)
        flags = python_string_literal(match.group("flags"))
        return f"{match.group('prefix')}{AS3_HELPER}.re({literal}, {flags})"

    return REGEX_LITERAL_RE.sub(one, span)


def convert_regex_splits(span: str, protected: list[str] | None = None) -> str:
    regex_markers = {f"__AS3_NONCODE_{i}__" for i, s in enumerate(protected or ()) if s.startswith(f"{AS3_HELPER}.re(")}
    pos = len(span)
    while True:
        dot = span.rfind(".split(", 0, pos)
        if dot < 0:
            return span
        pos = dot
        arg = span[dot + len(".split("):]
        if not (arg.startswith(f"{AS3_HELPER}.re(")
                or any(arg.lstrip().startswith(marker) and arg.lstrip()[len(marker):].lstrip().startswith(")")
                       for marker in regex_markers)):
            continue
        start = find_expression_start(span, dot)
        while 0 <= start < dot and span[start] in "!~":
            start += 1
        open_index = dot + len(".split")
        close_index = find_matching_right(span, open_index)
        if start < 0 or close_index < 0:
            continue
        receiver = span[start:dot].strip()
        args = span[open_index + 1:close_index]
        span = f"{span[:start]}{AS3_HELPER}.splitRe({receiver}, {args}){span[close_index + 1:]}"
        pos = start


def convert_coercion_calls(span: str) -> str:
    span = re.sub(r"\bnew\s+String\s*\(", "Std.string(", span)
    span = re.sub(r"\bnew\s+Int\s*\(", f"{AS3_HELPER}.toInt(", span)
    span = re.sub(r"\bnew\s+UInt\s*\(", f"{AS3_HELPER}.toUInt(", span)
    span = re.sub(r"\bnew\s+Float\s*\(", f"{AS3_HELPER}.toFloat(", span)
    span = re.sub(r"\bnew\s+Bool\s*\(", f"{AS3_HELPER}.toBool(", span)
    span = re.sub(r"\bString\s*\(", "Std.string(", span)
    span = re.sub(r"\bnew\s+Std\.string\s*\(", "Std.string(", span)
    span = re.sub(r"\bnew\s+port\.runtime\.As3\.asObject\s*\([^)]*\)", "{}", span)
    span = re.sub(r"\bInt\s*\(", f"{AS3_HELPER}.toInt(", span)
    span = re.sub(r"\bUInt\s*\(", f"{AS3_HELPER}.toUInt(", span)
    span = re.sub(r"\bFloat\s*\(", f"{AS3_HELPER}.toFloat(", span)
    span = re.sub(r"\bBool\s*\(", f"{AS3_HELPER}.toBool(", span)
    span = re.sub(r"(?<!new\s)\bXML\s*\(", "new XML(", span)
    span = re.sub(r"\bDynamic\s*\(", f"{AS3_HELPER}.asObject(", span)
    span = re.sub(r"\bnew\s+port\.runtime\.As3\.asObject\s*\([^)]*\)", "{}", span)
    span = re.sub(r"(?<![\w.])(?<!function )trace\s*\(", f"{AS3_HELPER}.nativeTrace(", span)
    span = re.sub(r"\bMath\.min\s*\(", f"{AS3_HELPER}.mathMin(", span)
    span = re.sub(r"\bMath\.max\s*\(", f"{AS3_HELPER}.mathMax(", span)
    span = specialize_binary_math_calls(span)
    span = convert_class_cast_calls(span)
    return span


def specialize_binary_math_calls(span: str) -> str:
    for name in ("mathMin", "mathMax"):
        needle = f"{AS3_HELPER}.{name}("
        search_end = len(span)
        while True:
            start = span.rfind(needle, 0, search_end)
            if start < 0:
                break
            open_index = start + len(needle) - 1
            close_index = find_matching_right(span, open_index)
            if close_index >= 0:
                args = split_top_level_commas(span[open_index + 1:close_index])
                if len(args) == 2:
                    replacement = f"{AS3_HELPER}.{name}2({span[open_index + 1:close_index]})"
                    span = span[:start] + replacement + span[close_index + 1:]
            search_end = start
    return span


def convert_class_cast_calls(span: str) -> str:
    for name in sorted(AS3_CAST_CALL_TYPES, key=len, reverse=True):
        span = re.sub(
            rf"(?<!new\s)(?<![\w.]){re.escape(name)}\s*\(((?:[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\([^()\n;]*\)|[^()\n;])+)\)",
            lambda m, type_name=name: f"{AS3_HELPER}.asType({m.group(1).strip()}, {type_name})",
            span,
        )
    span = re.sub(
        r"(?<!new\s)(?<!function\s)(?<![\w.])([Cc]lass_\d+)\s*\(((?:[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\([^()\n;:]*\)|[^()\n;,:])+)\)",
        lambda m: f"{AS3_HELPER}.asType({m.group(2).strip()}, {m.group(1)})",
        span,
    )
    imported = (set(re.findall(r"(?m)^\s*import\s+[\w.]+\.([A-Z]\w*)\s*;", span))
                | set(re.findall(r"(?:\b(?:var|const)\s+\w+|[(,]\s*\w+|\))\s*:\s*([A-Z]\w*)\b(?![.<])", span))
                | set(re.findall(r"(?<![\w.])([A-Z]\w*)\.[a-z_]\w*", span))) - CAST_CALL_EXCLUDED
    imported |= set(TREE_CLASS_NAMES.split()) - CAST_CALL_EXCLUDED
    imported -= set(re.findall(r"\bfunction\s+(?:get\s+|set\s+)?([A-Z]\w*)", span))
    if imported:
        names = "|".join(sorted(map(re.escape, imported), key=len, reverse=True))
        span = re.sub(
            rf"(?<!new\s)(?<!function\s)(?<![\w.])({names})\s*\(((?:[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\([^()\n;:]*\)"
            rf"|[^()\n;,:])+)\)",
            lambda m: f"{AS3_HELPER}.asType({m.group(2).strip()}, {m.group(1)})",
            span,
        )
    return span


CAST_CALL_EXCLUDED = {"String", "Number", "Boolean", "Object", "Array", "XML", "XMLList", "Vector", "Date", "Class",
                      "Std", "Math", "Reflect", "Type", "StringTools", "Lambda"}


def convert_flash_constants(span: str) -> str:
    span = re.sub(r'\bendian\s*=\s*"littleEndian"', "endian = flash.utils.Endian.LITTLE_ENDIAN", span)
    span = re.sub(r'\bendian\s*=\s*"bigEndian"', "endian = flash.utils.Endian.BIG_ENDIAN", span)
    span = re.sub(
        r"([A-Za-z_]\w*)\.b\.writeBytes\(([^;\n]+)\)",
        lambda m: f"{m.group(1)}.getData().writeBytes({m.group(2)})",
        span,
    )
    return span


def convert_comma_expressions(span: str) -> str:
    out: list[str] = []
    i = 0
    while i < len(span):
        if span[i] != "(":
            out.append(span[i])
            i += 1
            continue
        close = find_matching_right(span, i)
        if close < 0:
            out.append(span[i])
            i += 1
            continue
        inner = span[i + 1:close]
        parts = split_top_level_commas(inner)
        if len(parts) == 2 and all(is_comma_assignment_part(part) for part in parts):
            out.append(f"({comma_helper_expression(parts)})")
        elif len(parts) >= 3 and all(is_comma_assignment_part(part) for part in parts[:-1]) and is_condition_parenthesis(span, i):
            out.append(f"({comma_helper_expression(parts)})")
        else:
            out.append("(")
            out.append(convert_comma_expressions(inner))
            out.append(")")
        i = close + 1
    return "".join(out)


def comma_helper_expression(parts: list[str]) -> str:
    expression = parts[-1].strip()
    for part in reversed(parts[:-1]):
        expression = f"{AS3_HELPER}.comma({part.strip()}, {expression})"
    return expression


def is_condition_parenthesis(span: str, open_index: int) -> bool:
    i = skip_space_left(span, open_index - 1)
    end = i + 1
    while i >= 0 and is_identifier_char(span[i]):
        i -= 1
    word = span[i + 1:end]
    return word in {"if", "while"}


def is_call_parenthesis(span: str, open_index: int) -> bool:
    previous = skip_space_left(span, open_index - 1)
    if previous >= 0 and is_identifier_char(span[previous]):
        end = previous + 1
        start = previous
        while start >= 0 and is_identifier_char(span[start]):
            start -= 1
        if span[start + 1:end] in {"return", "if", "while", "switch", "for"}:
            return False
    return previous >= 0 and (is_identifier_char(span[previous]) or span[previous] in ")]")


def is_comma_assignment_part(part: str) -> bool:
    match = re.search(r"(?<![!<>=])=(?!=)", part)
    if not match:
        return False
    lhs = part[:match.start()]
    return ":" not in lhs


def convert_regex_string_replace(span: str) -> str:
    protected_text, protected = protect_noncode(span)
    protected_text = re.sub(
        rf"([A-Za-z_]\w*)\.replace\(({re.escape(AS3_HELPER)}\.re\([^\n)]*?\))\s*,\s*([^\n)]*?)\)",
        lambda m: f"{AS3_HELPER}.replace({m.group(1)}, {m.group(2)}, {m.group(3).strip()})",
        protected_text,
    )
    return restore_noncode(protected_text, protected)


def convert_for_in_loops(span: str) -> str:
    out: list[str] = []
    i = 0
    while True:
        match = re.search(r"\bfor\s*\(", span[i:])
        if not match:
            out.append(span[i:])
            return "".join(out)
        start = i + match.start()
        paren = span.find("(", start)
        close = find_matching_right(span, paren)
        if close < 0:
            out.append(span[i:start + 3])
            i = start + 3
            continue
        header = span[paren + 1:close]
        in_match = re.match(r"\s*([A-Za-z_]\w*)\s+in\s+(.+)\s*$", header, flags=re.DOTALL)
        out.append(span[i:start])
        if in_match and not in_match.group(2).strip().lstrip("(").startswith(AS3_HELPER + ".values("):
            name, target = in_match.group(1), in_match.group(2).strip()
            body_open = skip_space_right(span, close + 1)
            if not name.endswith(FOR_IN_DYNAMIC_KEY_MARK):
                out.append(f"for({name} in {AS3_HELPER}.keys({target}))")
            elif body_open < len(span) and span[body_open] == "{":
                name = name[:-len(FOR_IN_DYNAMIC_KEY_MARK)]
                out.append(f"for(__key_{name} in {AS3_HELPER}.dynamicKeys({target}))")
                out.append(span[close + 1:body_open + 1])
                out.append(f"\n{line_indent(span, start)}   var {name}:Dynamic = __key_{name};")
                i = body_open + 1
                continue
            else:
                out.append(f"for({name[:-len(FOR_IN_DYNAMIC_KEY_MARK)]} in {AS3_HELPER}.dynamicKeys({target}))")
        else:
            out.append(span[start:close + 1].replace(FOR_IN_DYNAMIC_KEY_MARK + " in ", " in "))
        i = close + 1


CHAINED_INDEX_STORE_RE = re.compile(
    r"(?m)^(?P<indent>[ \t]*)(?P<a>[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\[[^\]\n=]+\])\s*=(?!=)\s*"
    r"(?P<b>[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\[[^\]\n=]+\])\s*=(?!=)\s*(?P<value>[^;\n]+);[ \t]*$")


def convert_index_assignments(span: str) -> str:
    span = CHAINED_INDEX_STORE_RE.sub(
        lambda m: f"{m.group('indent')}{m.group('b')} = {m.group('value')};\n"
                  f"{m.group('indent')}{m.group('a')} = {m.group('b')};", span)
    span = re.sub(
        r"(?P<op>\+\+|--)\s*(?P<target>[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*\[\s*(?P<key>[^\]\n]+?)\s*\];",
        lambda m: (
            f"{AS3_HELPER}.setIndex({m.group('target')}, {m.group('key').strip()}, "
            f"{AS3_HELPER}.numeric('{ '+' if m.group('op') == '++' else '-' }', "
            f"{AS3_HELPER}.index({m.group('target')}, {m.group('key').strip()}), 1));"
        ),
        span,
    )
    span = re.sub(
        r"\b([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*\[\s*([^\]\n]+?)\s*\]\s*\[\s*([^\]\n]+?)\s*\](\+\+|--)",
        lambda m: (
            f"{AS3_HELPER}.setIndex({AS3_HELPER}.index({m.group(1)}, {m.group(2).strip()}), {m.group(3).strip()}, "
            f"{AS3_HELPER}.index({AS3_HELPER}.index({m.group(1)}, {m.group(2).strip()}), {m.group(3).strip()}) "
            f"{'+' if m.group(4) == '++' else '-'} 1)"
        ),
        span,
    )
    span = re.sub(
        r"\b([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*\[\s*([^\]\n]+?)\s*\](\+\+|--)",
        lambda m: (
            f"{AS3_HELPER}.setIndex({m.group(1)}, {m.group(2).strip()}, "
            f"{AS3_HELPER}.index({m.group(1)}, {m.group(2).strip()}) {'+' if m.group(3) == '++' else '-'} 1)"
        ),
        span,
    )
    compound_ops = {
        "|=": "|",
        "&=": "&",
        "^=": "^",
        "+=": "+",
        "-=": "-",
        "*=": "*",
        "/=": "/",
        "%=": "%",
    }
    compound_re = re.compile(
        r"\b([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*\[\s*([^\]\n]+?)\s*\]\s*(\|=|&=|\^=|\+=|-=|\*=|/=|%=)\s*([^;\n]+);"
    )
    nested_compound_re = re.compile(
        r"\b([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*\[\s*([^\]\n]+?)\s*\]\s*\[\s*([^\]\n]+?)\s*\]\s*"
        r"(\|=|&=|\^=|\+=|-=|\*=|/=|%=)\s*([^;\n]+);"
    )

    def compound_repl(match: re.Match[str]) -> str:
        target = match.group(1)
        key = match.group(2).strip()
        op = compound_ops[match.group(3)]
        value = match.group(4).strip()
        current = f"{AS3_HELPER}.index({target}, {key})"
        return f"{AS3_HELPER}.setIndex({target}, {key}, {current} {op} {value});"

    def nested_compound_repl(match: re.Match[str]) -> str:
        target = f"{AS3_HELPER}.index({match.group(1)}, {match.group(2).strip()})"
        key = match.group(3).strip()
        op = compound_ops[match.group(4)]
        value = match.group(5).strip()
        current = f"{AS3_HELPER}.index({target}, {key})"
        return f"{AS3_HELPER}.setIndex({target}, {key}, {current} {op} {value});"

    span = nested_compound_re.sub(nested_compound_repl, span)
    span = compound_re.sub(compound_repl, span)
    span = re.sub(
        r"\b(?P<base>[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*\[\s*(?P<key>[^\]\n]+?)\s*\]"
        r"(?P<rest>(?:\s*\.[A-Za-z_]\w*\s*\[\s*[^\]\n]+?\s*\])+)\s*=(?!=)\s*(?P<value>[^;\n]+);",
        chained_index_assignment,
        span,
    )
    span = re.sub(
        r"(?<![\w.])([A-Za-z_]\w*)\s*\[\s*([^\]\n]+?)\s*\]\s*\[\s*([^\]\n]+?)\s*\]\s*\[\s*([^\]\n]+?)\s*\]\s*=(?!=)\s*([^;\n]+);",
        lambda m: (
            f"{AS3_HELPER}.setIndex("
            f"{AS3_HELPER}.index({AS3_HELPER}.index({m.group(1)}, {m.group(2).strip()}), {m.group(3).strip()}), "
            f"{m.group(4).strip()}, {m.group(5).strip()});"
        ),
        span,
    )
    span = re.sub(
        r"(?<![\w.])([A-Za-z_]\w*)\s*\[\s*([^\]\n]+?)\s*\]\s*\[\s*([^\]\n]+?)\s*\]\s*=(?!=)\s*([^;\n]+);",
        lambda m: f"{AS3_HELPER}.setIndex({AS3_HELPER}.index({m.group(1)}, {m.group(2).strip()}), {m.group(3).strip()}, {m.group(4).strip()});",
        span,
    )
    out: list[str] = []
    i = 0
    last_end = 0
    while i < len(span):
        bracket = span.find("[", i)
        if bracket < 0:
            out.append(span[i:])
            return "".join(out)
        target_start = parse_atom_left(span, skip_space_left(span, bracket - 1))
        close = find_matching_right(span, bracket)
        if target_start < 0 or close < 0:
            out.append(span[i:bracket + 1])
            i = bracket + 1
            continue
        after = skip_space_right(span, close + 1)
        if after >= len(span) or span[after] != "=" or (after + 1 < len(span) and span[after + 1] == "="):
            out.append(span[i:close + 1])
            i = close + 1
            continue
        semi = statement_semicolon(span, after + 1)
        if semi < 0:
            out.append(span[i:bracket + 1])
            i = bracket + 1
            continue
        target = span[target_start:bracket].strip()
        key = span[bracket + 1:close].strip()
        value = span[after + 1:semi].strip()
        if target_start < i:
            if target_start < last_end:
                out.append(span[i:bracket + 1])
                i = bracket + 1
                continue
            copied = "".join(out)
            out = [copied[:len(copied) - (i - target_start)]]
        else:
            out.append(span[i:target_start])
        out.append(f"{AS3_HELPER}.setIndex({target}, {key}, {value});")
        i = semi + 1
        last_end = i
    return "".join(out)


def statement_semicolon(span: str, start: int) -> int:
    depth = 0
    for k in range(start, len(span)):
        ch = span[k]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth < 0:
                return span.find(";", start)
        elif ch == ";" and depth == 0:
            return k
    return span.find(";", start)


def convert_length_assignments(span: str) -> str:
    return re.sub(
        r"(?P<indent>^[ \t]*)(?P<target>[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\.length\s*=\s*(?P<value>[^;\n]+);",
        lambda m: f"{m.group('indent')}{AS3_HELPER}.setLength({m.group('target')}, {m.group('value').strip()});",
        span,
        flags=re.MULTILINE,
    )


def chained_index_assignment(match: re.Match[str]) -> str:
    target = f"{AS3_HELPER}.index({match.group('base')}, {match.group('key').strip()})"
    pieces = re.findall(r"\.\s*([A-Za-z_]\w*)\s*\[\s*([^\]\n]+?)\s*\]", match.group("rest"))
    if not pieces:
        return match.group(0)
    for field, key in pieces[:-1]:
        target = f"{AS3_HELPER}.index({target}.{field}, {key.strip()})"
    field, key = pieces[-1]
    return f"{AS3_HELPER}.setIndex({target}.{field}, {key.strip()}, {match.group('value').strip()});"


def convert_index_reads(span: str) -> str:
    marker_prefix = "__AS3_INDEX_NONCODE_"
    protected_span, protected = protect_noncode(span, marker_prefix)
    span = protected_span
    keywords = {"return", "throw", "new"}
    for _ in range(4):
        replacements: list[tuple[int, int, str]] = []
        i = 0
        while True:
            bracket = span.find("[", i)
            if bracket < 0:
                break
            target_start = parse_atom_left(span, skip_space_left(span, bracket - 1))
            close = find_matching_right(span, bracket)
            if target_start < 0 or close < 0:
                i = bracket + 1
                continue
            after = skip_space_right(span, close + 1)
            if after < len(span) and span[after] == "=" and not (after + 1 < len(span) and span[after + 1] == "="):
                i = close + 1
                continue
            target = span[target_start:bracket].strip()
            lead = re.match(r"\s*(?:return|throw)\s+(?=\[)", span[target_start:bracket])
            if lead:
                target_start += lead.end()
                target = span[target_start:bracket].strip()
            if target in keywords or target.startswith(AS3_HELPER + ".index("):
                i = close + 1
                continue
            marker = re.fullmatch(re.escape(marker_prefix) + r"(\d+)__", target)
            if (marker and protected[int(marker.group(1))].lstrip().startswith(("//", "/*"))
                    or re.fullmatch(r"(?:__AS3_NONCODE_\d+__)+", target)):
                i = bracket + 1
                continue
            key = span[bracket + 1:close].strip()
            replacements.append((target_start, close + 1, f"{AS3_HELPER}.index({target}, {key})"))
            i = close + 1
        if not replacements:
            return restore_noncode(span, protected, marker_prefix)
        changed = False
        blocked: list[tuple[int, int]] = []
        for start, end, replacement in sorted(replacements, reverse=True):
            if any(not (end <= used_start or start >= used_end) for used_start, used_end in blocked):
                continue
            span = span[:start] + replacement + span[end:]
            blocked.append((start, start + len(replacement)))
            changed = True
        if not changed:
            return restore_noncode(span, protected, marker_prefix)
    return restore_noncode(span, protected, marker_prefix)


def convert_dynamic_field_access(span: str) -> str:
    dynamic_fields = {"add", "always"}
    for field in sorted(dynamic_fields):
        span = re.sub(
            rf"\b([A-Za-z_]\w*)\.{field}\s*=\s*([^;\n]+);",
            lambda m, name=field: f'{AS3_HELPER}.setField({m.group(1)}, "{name}", {m.group(2).strip()});',
            span,
        )
        span = re.sub(
            rf"\b([A-Za-z_]\w*)\.{field}\s*\[([^\]\n]+)\]",
            lambda m, name=field: f'{AS3_HELPER}.index({AS3_HELPER}.field({m.group(1)}, "{name}"), {m.group(2).strip()})',
            span,
        )
        span = re.sub(
            rf"\b([A-Za-z_]\w*)\.{field}\b(?!\s*\()",
            lambda m, name=field: f'{AS3_HELPER}.field({m.group(1)}, "{name}")',
            span,
        )
    return span


def convert_numeric_dynamic_operations(span: str) -> str:
    span = convert_compound_assignment_call_args(span)
    span = re.sub(
        rf"\b([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*-=\s*([^;\n]+);",
        lambda m: f"{m.group(1)} = {AS3_HELPER}.numeric('-', {m.group(1)}, {m.group(2).strip()});",
        span,
    )
    return wrap_index_numeric_operations(span)


def convert_compound_assignment_call_args(span: str) -> str:
    compound_ops = {
        "+=": "+",
        "-=": "-",
        "*=": "*",
        "/=": "/",
        "%=": "%",
    }

    def repl(match: re.Match[str]) -> str:
        name = match.group("name")
        op = compound_ops[match.group("op")]
        value = match.group("value").strip()
        return (
            f"{match.group('indent')}{name} = {AS3_HELPER}.numeric('{op}', {name}, {value});\n"
            f"{match.group('indent')}{match.group('callee')}({match.group('prefix')}{name},{match.group('rest')});"
        )

    return re.sub(
        r"(?P<indent>^[ \t]*)(?P<callee>[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\((?P<prefix>\s*)"
        r"(?P<name>[A-Za-z_]\w*)\s*(?P<op>\+=|-=|\*=|/=|%=)\s*(?P<value>[^,\n]+),(?P<rest>[^;\n]*?)\);",
        repl,
        span,
        flags=re.MULTILINE,
    )


def wrap_index_numeric_operations(span: str) -> str:
    out: list[str] = []
    i = 0
    needle = f"{AS3_HELPER}.index("
    while i < len(span):
        start = span.find(needle, i)
        if start < 0:
            out.append(span[i:])
            return "".join(out)
        open_index = start + len(needle) - 1
        close_index = find_matching_right(span, open_index)
        if close_index < 0:
            out.append(span[i:start + len(needle)])
            i = start + len(needle)
            continue
        op_index = skip_space_right(span, close_index + 1)
        if op_index >= len(span) or span[op_index] not in "+-*/%":
            out.append(span[i:close_index + 1])
            i = close_index + 1
            continue
        if op_index + 1 < len(span) and span[op_index + 1] == span[op_index]:
            out.append(span[i:close_index + 1])
            i = close_index + 1
            continue
        right_start = skip_space_right(span, op_index + 1)
        right_end = find_numeric_rhs_end(span, right_start, span[op_index])
        right = span[right_start:right_end].strip()
        if not right:
            out.append(span[i:close_index + 1])
            i = close_index + 1
            continue
        if span[op_index] == "+" and not re.fullmatch(r"\d+(?:\.\d+)?", right):
            out.append(span[i:close_index + 1])
            i = close_index + 1
            continue
        out.append(span[i:start])
        out.append(f"{AS3_HELPER}.numeric('{span[op_index]}', {span[start:close_index + 1]}, {right})")
        i = right_end


def find_numeric_rhs_end(span: str, start: int, op: str = "") -> int:
    stops = "+-*/%<>=!&|^?" if op in ("*", "/", "%") else "+-<>=!&|^?"
    depth = 0
    i = start
    operand = False
    while i < len(span):
        ch = span[i]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            if depth == 0:
                return i
            depth -= 1
            operand = True
        elif depth == 0 and ch in ",;:\n":
            return i
        elif depth == 0 and op and operand and ch in stops:
            return i
        elif depth == 0 and not ch.isspace():
            operand = ch not in "+-*/%<>=!&|^?~"
        i += 1
    return i


def convert_as3_string_methods(span: str) -> str:
    methods = {
        "indexOf": "valueIndexOf",
        "match": "stringMatch",
        "replace": "stringReplace",
        "search": "stringSearch",
        "slice": "stringSlice",
        "substr": "stringSubstr",
    }
    i = 0
    while i < len(span):
        found: tuple[int, str] | None = None
        for method in methods:
            match = re.search(rf"\.{method}\s*\(", span[i:])
            if match is None:
                continue
            absolute = i + match.start()
            if found is None or absolute < found[0]:
                found = (absolute, method)
        if found is None:
            return span
        dot, method = found
        call_open = span.find("(", dot)
        call_close = find_matching_right(span, call_open)
        expr_start = find_expression_start(span, dot)
        if call_open < 0 or call_close < 0 or expr_start < 0:
            i = dot + 1
            continue
        if span[max(0, expr_start - 4):expr_start] == "new ":
            expr_start -= 4
        target = span[expr_start:dot].strip()
        if target.startswith("return "):
            expr_start += len("return ")
            target = target[len("return "):].strip()
        args = span[call_open + 1:call_close].strip()
        helper = methods[method]
        arg_tail = f", {args}" if args else ""
        replacement = f"{AS3_HELPER}.{helper}({target}{arg_tail})"
        span = span[:expr_start] + replacement + span[call_close + 1:]
        i = expr_start
    return span


INDEXABLE_TYPE_PATTERN = r"(?:String|Array<[\w.]+>|Vector<[^>]+>)"


TYPED_FIELD_CHAIN_INDEX_OF = True


def _indexable_fields() -> set[str]:
    table = load_element_types() or {}
    return set(table.get("arrays") or ()) | set(table.get("strings") or ())


def _flat_postfix_chain(expr: str) -> str:
    flat = expr
    while True:
        reduced = re.sub(r"\([^()\[\]]*\)|\[[^()\[\]]*\]", "", flat)
        if reduced == flat:
            return flat
        flat = reduced


def _postfix_chain(expr: str) -> bool:
    return re.fullmatch(r"[\w$.]+", _flat_postfix_chain(expr.strip())) is not None


DECLARED_ARRAY_SLICES = True
_SLICE_TARGET_RE = re.compile(r"^(?:[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*|\[[\w$.]+\])*\.)?([A-Za-z_$][\w$]*)$")


def restore_declared_array_slices(span: str) -> str:
    if not DECLARED_ARRAY_SLICES:
        return span
    arrays = set((load_element_types() or {}).get("arrays") or ())
    if not arrays:
        return span
    needle = f"{AS3_HELPER}.stringSlice("
    out: list[str] = []
    i = 0
    while True:
        start = span.find(needle, i)
        if start < 0:
            out.append(span[i:])
            return "".join(out)
        open_index = start + len(needle) - 1
        close_index = find_matching_right(span, open_index)
        out.append(span[i:start])
        if close_index < 0:
            out.append(needle)
            i = start + len(needle)
            continue
        args = [arg.strip() for arg in split_top_level_commas(span[open_index + 1:close_index])]
        target = _SLICE_TARGET_RE.match(_flat_postfix_chain(args[0])) if args and _postfix_chain(args[0]) else None
        if (target and len(args) >= 2 and target.group(1) in arrays
                and not target.group(1).startswith(("_loc", "param"))):
            out.append(f"{args[0]}.slice({', '.join(args[1:])})")
        else:
            out.append(span[start:close_index + 1])
        i = close_index + 1


def restore_typed_index_of_body(body: str, types: dict[str, str], class_name: str | None) -> str:
    needle = f"{AS3_HELPER}.valueIndexOf("
    out: list[str] = []
    i = 0
    while True:
        start = body.find(needle, i)
        if start < 0:
            out.append(body[i:])
            return "".join(out)
        open_index = start + len(needle) - 1
        close_index = find_matching_right(body, open_index)
        if close_index < 0:
            out.append(body[i:start + len(needle)])
            i = start + len(needle)
            continue
        args = split_top_level_commas(body[open_index + 1:close_index])
        target = args[0].strip() if args else ""
        pieces = target.split(".")
        local = pieces[-1]
        qualified_current_class = len(pieces) == 2 and pieces[0] == class_name
        simple_target = len(pieces) == 1 or (len(pieces) == 2 and pieces[0] == "this") or qualified_current_class
        out.append(body[i:start])
        declared = (TYPED_FIELD_CHAIN_INDEX_OF and len(pieces) > 1 and not local.startswith(("_loc", "param"))
                    and local in _indexable_fields())
        if (len(args) in (2, 3) and (simple_target or declared)
                and all(re.fullmatch(r"[A-Za-z_]\w*", piece) for piece in pieces)
                and (types.get(local) or declared)):
            out.append(f"{target}.indexOf({', '.join(arg.strip() for arg in args[1:])})")
        else:
            out.append(body[start:close_index + 1])
        i = close_index + 1


def restore_typed_index_of_calls(span: str) -> str:
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    visible_types: dict[str, str] = {}
    function_spans = nested_function_spans(span)
    field_pattern = re.compile(
        rf"^[ \t]*(?:public|private|protected|internal)?\s*(?:static\s+)?var\s+"
        rf"([A-Za-z_]\w*)\s*:\s*({INDEXABLE_TYPE_PATTERN})(?=\s|[=,;)]|/\*|$)",
        re.MULTILINE,
    )
    for match in field_pattern.finditer(span):
        if not any(start <= match.start() < end for start, end in function_spans):
            visible_types[match.group(1)] = match.group(2)

    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+[A-Za-z_]\w*\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return "".join(out)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        if close_paren < 0:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        body_open = skip_space_right(span, close_paren + 1)
        while body_open < len(span) and span[body_open] != "{":
            body_open += 1
        if body_open >= len(span):
            out.append(span[i:close_paren + 1])
            i = close_paren + 1
            continue
        body_close = find_matching_right(span, body_open)
        if body_close < 0:
            out.append(span[i:body_open + 1])
            i = body_open + 1
            continue

        body = span[body_open + 1:body_close]
        types = dict(visible_types)
        for param in split_top_level_commas(span[paren + 1:close_paren]):
            typed = re.match(rf"\s*([A-Za-z_]\w*)\s*:\s*({INDEXABLE_TYPE_PATTERN})(?=\s|[=,;)]|/\*|$)", param)
            if typed:
                types[typed.group(1)] = typed.group(2)
        for typed in re.finditer(
            rf"\bvar\s+([A-Za-z_]\w*)\s*:\s*({INDEXABLE_TYPE_PATTERN})(?=\s|[=,;)]|/\*|$)",
            body,
        ):
            types[typed.group(1)] = typed.group(2)

        out.append(span[i:body_open + 1])
        out.append(restore_typed_index_of_body(body, types, class_name))
        out.append("}")
        i = body_close + 1


AUDITED_TYPED_VECTOR_READS: dict[tuple[str, str], set[str]] = {
    ("class_64", "method_1010"): {"var_6931"},
    ("class_135", "method_4976"): {"var_8674", "var_10741"},
    ("class_598", "method_619"): {"var_1636"},
    ("class_600", "method_619"): {"var_1636"},
    ("class_605", "method_619"): {"var_1636"},
    ("class_605", "method_5759"): {"var_1636"},
    ("class_607", "method_619"): {"var_1636"},
    ("class_614", "method_619"): {"var_1636"},
    ("class_618", "method_5377"): {"var_13320"},
    ("class_637", "method_6511"): {"_loc3_"},
    ("class_691", "method_3149"): {"var_15010"},
    ("class_555", "method_8269"): {"var_12013"},
}

AUDITED_EXACT_VECTOR_READS: dict[tuple[str, str], set[tuple[str, str]]] = {
    ("class_6", "method_2183"): {
        ("param1.var_982", "_loc4_"),
        ("param1.var_14733", "_loc4_"),
    },
    ("itemtype", "method_6546"): {("param1.var_13621", "1")},
    ("class_266", "method_3047"): {("_loc5_", "_loc7_")},
    ("class_486", "method_184"): {("buttons", "_loc3_")},
    ("class_487", "method_184"): {("buttons", "_loc3_")},
    ("class_490", "method_184"): {("buttons", "_loc3_")},
    ("class_725", "method_8811"): {("_loc3_", "_loc4_")},
    ("class_719", "method_8460"): {("_loc3_", "_loc2_")},
    ("class_313", "method_5084"): {("var_2757.var_11782", "var_14014")},
    ("class_313", "method_2407"): {("var_2757.var_11782", "var_14014")},
    ("class_444", "method_2363"): {
        ("var_13237", "var_9670"),
        (f"{AS3_HELPER}.index(var_13237, var_9670).var_1147", "var_3843"),
    },
    ("subscreeneventtimedevent", "GetNextFocus"): {
        ("_loc2_", f"{AS3_HELPER}.toBool(param1) ? _loc3_ - 1 : _loc3_ + 1"),
    },
    ("traileffect", "method_274"): {
        ("_loc3_", "_loc7_"),
    },
    ("class_493", "method_8951"): {
        ("owner.var_6244.var_1751", "_loc2_"),
    },
    ("class_637", "method_6511"): {
        ("_loc2_.var_13621", "1"),
    },
    ("class_385", "method_6377"): {
        ("var_12427", "var_7257"),
    },
    ("class_355", "method_5605"): {
        ("_loc5_", "_loc4_"),
    },
    ("class_319", "method_5305"): {
        ("var_1931", f"var_3426 = {AS3_HELPER}.toInt(var_3426 - 1)"),
    },
    ("class_513", "method_6749"): {
        ("var_4818.var_15010", "param1"),
    },
    ("class_513", "method_6916"): {
        ("var_4818.var_15010", "param2"),
    },
    ("class_513", "method_1359"): {
        ("var_4818.var_15010", "param2"),
    },
    ("class_513", "method_639"): {
        ("var_4818.var_15010", "param2"),
    },
    ("class_513", "method_2615"): {
        ("var_4818.var_15010", "param2"),
    },
    ("class_513", "method_3123"): {
        ("var_4818.var_15010", "param2"),
    },
    ("class_513", "method_4721"): {
        ("var_4818.var_15010", "param2"),
    },
    ("class_513", "method_6204"): {
        ("var_4818.var_15010", "param2"),
    },
    ("class_513", "method_5292"): {
        ("var_4818.var_15010", "param2"),
    },
    ("class_513", "method_4436"): {
        ("var_4818.var_15010", "param2"),
    },
    ("class_513", "method_7335"): {
        ("var_4818.var_15010", "param2"),
    },
    ("class_513", "method_7877"): {
        ("var_4818.var_15010", "param2"),
    },
    ("class_622", "method_1668"): {
        ("var_4178", "param2"),
    },
    ("class_622", "method_4634"): {
        ("var_11692", "param2"),
        ("var_4178", "param2"),
    },
    ("class_467", "method_6837"): {
        ("param1.var_9485", "0"),
    },
    ("class_672", "method_6271"): {
        ("var_11444", "param1"),
    },
    ("class_548", "method_4093"): {
        ("var_40", "_loc3_"),
    },
    ("class_579", "method_4716"): {
        ("param2", f"{AS3_HELPER}.toInt(param2.length) - _loc8_ - 1"),
    },
    ("class_579", "Reset"): {
        ("_loc2_", "_loc1_"),
    },
}


def restore_typed_vector_index_read_body(body: str, types: dict[str, str],
                                         class_name: str | None,
                                         audited_fields: set[str],
                                         exact_reads: set[tuple[str, str]]) -> str:
    needle = f"{AS3_HELPER}.index("
    out: list[str] = []
    i = 0
    while True:
        start = body.find(needle, i)
        if start < 0:
            out.append(body[i:])
            return "".join(out)
        open_index = start + len(needle) - 1
        close_index = find_matching_right(body, open_index)
        if close_index < 0:
            out.append(body[i:start + len(needle)])
            i = start + len(needle)
            continue
        args = split_top_level_commas(body[open_index + 1:close_index])
        target = args[0].strip() if args else ""
        key = args[1].strip() if len(args) == 2 else ""
        pieces = target.split(".")
        local = pieces[-1]
        qualified_current_class = len(pieces) == 2 and pieces[0] == class_name
        simple_target = len(pieces) == 1 or (len(pieces) == 2 and pieces[0] == "this") or qualified_current_class
        simple_key = (re.fullmatch(r"-?\d+", key) is not None
                      or (re.fullmatch(r"[A-Za-z_]\w*", key) is not None
                          and types.get(key) in {"Int", "UInt"}))
        out.append(body[i:start])
        audited_target = local in audited_fields
        exact_read = (target, key) in exact_reads
        if exact_read:
            target = restore_typed_vector_index_read_body(
                target, types, class_name, audited_fields, exact_reads
            )
            out.append(f"{target}[{key}]")
        elif (audited_target and len(args) == 2 and simple_target and simple_key
                and all(re.fullmatch(r"[A-Za-z_]\w*", piece) for piece in pieces)
                and types.get(local, "").startswith("Vector<")):
            out.append(f"{target}[{key}]")
        else:
            out.append(body[start:close_index + 1])
        i = close_index + 1


def restore_typed_vector_index_reads(span: str) -> str:
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    type_pattern = r"(?:Vector<[^>]+>|Int|UInt)"
    visible_types: dict[str, str] = {}
    function_spans = nested_function_spans(span)
    for match in re.finditer(
        rf"^[ \t]*(?:public|private|protected|internal)?\s*(?:static\s+)?var\s+"
        rf"([A-Za-z_]\w*)\s*:\s*({type_pattern})(?=\s|[=,;)]|$)",
        span,
        re.MULTILINE,
    ):
        if not any(start <= match.start() < end for start, end in function_spans):
            visible_types[match.group(1)] = match.group(2)

    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return "".join(out)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        if close_paren < 0:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        body_open = skip_space_right(span, close_paren + 1)
        while body_open < len(span) and span[body_open] != "{":
            body_open += 1
        if body_open >= len(span):
            out.append(span[i:close_paren + 1])
            i = close_paren + 1
            continue
        body_close = find_matching_right(span, body_open)
        if body_close < 0:
            out.append(span[i:body_open + 1])
            i = body_open + 1
            continue

        body = span[body_open + 1:body_close]
        audited_fields = AUDITED_TYPED_VECTOR_READS.get(
            ((class_name or "").lower(), match.group(1)), set()
        )
        exact_reads = AUDITED_EXACT_VECTOR_READS.get(
            ((class_name or "").lower(), match.group(1)), set()
        )
        types = dict(visible_types)
        for param in split_top_level_commas(span[paren + 1:close_paren]):
            typed = re.match(rf"\s*([A-Za-z_]\w*)\s*:\s*({type_pattern})(?=\s|[=,;)]|$)", param)
            if typed:
                types[typed.group(1)] = typed.group(2)
        for typed in re.finditer(
            rf"\bvar\s+([A-Za-z_]\w*)\s*:\s*({type_pattern})(?=\s|[=,;)]|$)", body
        ):
            types[typed.group(1)] = typed.group(2)

        out.append(span[i:body_open + 1])
        out.append(restore_typed_vector_index_read_body(
            body, types, class_name, audited_fields, exact_reads
        ))
        out.append("}")
        i = body_close + 1


def restore_typed_vector_sort_body(body: str, types: dict[str, str],
                                   class_name: str | None) -> str:
    needle = f"{AS3_HELPER}.arraySort("
    lines: list[str] = []
    for line in body.splitlines(keepends=True):
        start = line.find(needle)
        if start < 0 or start != len(line) - len(line.lstrip()):
            lines.append(line)
            continue
        open_index = start + len(needle) - 1
        close_index = find_matching_right(line, open_index)
        if close_index < 0 or line[close_index + 1:].strip() != ";":
            lines.append(line)
            continue
        args = split_top_level_commas(line[open_index + 1:close_index])
        if len(args) != 2 or not args[1].strip():
            lines.append(line)
            continue
        target = args[0].strip()
        pieces = target.split(".")
        local = pieces[-1]
        qualified_current_class = len(pieces) == 2 and pieces[0] == class_name
        simple_target = len(pieces) == 1 or (len(pieces) == 2 and pieces[0] == "this") or qualified_current_class
        if (simple_target and all(re.fullmatch(r"[A-Za-z_]\w*", piece) for piece in pieces)
                and types.get(local, "").startswith("Vector<")):
            ending = "\n" if line.endswith("\n") else ""
            lines.append(f"{line[:start]}{target}.sort({args[1].strip()});{ending}")
        else:
            lines.append(line)
    return "".join(lines)


def restore_typed_vector_sorts(span: str) -> str:
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    type_pattern = r"Vector<[^>]+>"
    visible_types: dict[str, str] = {}
    function_spans = nested_function_spans(span)
    for match in re.finditer(
        rf"^[ \t]*(?:public|private|protected|internal)?\s*(?:static\s+)?var\s+"
        rf"([A-Za-z_]\w*)\s*:\s*({type_pattern})(?=\s|[=,;)]|$)",
        span,
        re.MULTILINE,
    ):
        if not any(start <= match.start() < end for start, end in function_spans):
            visible_types[match.group(1)] = match.group(2)

    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+[A-Za-z_]\w*\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return "".join(out)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        if close_paren < 0:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        body_open = skip_space_right(span, close_paren + 1)
        while body_open < len(span) and span[body_open] != "{":
            body_open += 1
        if body_open >= len(span):
            out.append(span[i:close_paren + 1])
            i = close_paren + 1
            continue
        body_close = find_matching_right(span, body_open)
        if body_close < 0:
            out.append(span[i:body_open + 1])
            i = body_open + 1
            continue

        body = span[body_open + 1:body_close]
        types = dict(visible_types)
        for param in split_top_level_commas(span[paren + 1:close_paren]):
            typed = re.match(rf"\s*([A-Za-z_]\w*)\s*:\s*({type_pattern})(?=\s|[=,;)]|$)", param)
            if typed:
                types[typed.group(1)] = typed.group(2)
        for typed in re.finditer(
            rf"\bvar\s+([A-Za-z_]\w*)\s*:\s*({type_pattern})(?=\s|[=,;)]|$)", body
        ):
            types[typed.group(1)] = typed.group(2)

        out.append(span[i:body_open + 1])
        out.append(restore_typed_vector_sort_body(body, types, class_name))
        out.append("}")
        i = body_close + 1


def restore_typed_array_index_write_body(body: str, types: dict[str, str],
                                         class_name: str | None) -> str:
    needle = f"{AS3_HELPER}.setIndex("
    lines: list[str] = []
    for line in body.splitlines(keepends=True):
        stripped = line.strip()
        start = line.find(needle)
        if start < 0 or start != len(line) - len(line.lstrip()):
            lines.append(line)
            continue
        open_index = start + len(needle) - 1
        close_index = find_matching_right(line, open_index)
        if close_index < 0 or line[close_index + 1:].strip() != ";":
            lines.append(line)
            continue
        args = split_top_level_commas(line[open_index + 1:close_index])
        if len(args) != 3:
            lines.append(line)
            continue
        target, key, value = (arg.strip() for arg in args)
        pieces = target.split(".")
        local = pieces[-1]
        qualified_current_class = len(pieces) == 2 and pieces[0] == class_name
        simple_target = len(pieces) == 1 or (len(pieces) == 2 and pieces[0] == "this") or qualified_current_class
        simple_key = (re.fullmatch(r"-?\d+", key) is not None
                      or (re.fullmatch(r"[A-Za-z_]\w*", key) is not None and types.get(key) in {"Int", "UInt"}))
        if (simple_target and all(re.fullmatch(r"[A-Za-z_]\w*", piece) for piece in pieces)
                and types.get(local) == "Array<Dynamic>" and simple_key):
            ending = "\n" if line.endswith("\n") else ""
            lines.append(f"{line[:start]}{target}[{key}] = {value};{ending}")
        else:
            lines.append(line)
    return "".join(lines)


def restore_typed_array_index_writes(span: str) -> str:
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    type_pattern = r"(?:Array<Dynamic>|Int|UInt)"
    visible_types: dict[str, str] = {}
    function_spans = nested_function_spans(span)
    for match in re.finditer(
        rf"^[ \t]*(?:public|private|protected|internal)?\s*(?:static\s+)?var\s+"
        rf"([A-Za-z_]\w*)\s*:\s*({type_pattern})(?=\s|[=,;)]|$)",
        span,
        re.MULTILINE,
    ):
        if not any(start <= match.start() < end for start, end in function_spans):
            visible_types[match.group(1)] = match.group(2)

    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+[A-Za-z_]\w*\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return "".join(out)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        if close_paren < 0:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        body_open = skip_space_right(span, close_paren + 1)
        while body_open < len(span) and span[body_open] != "{":
            body_open += 1
        if body_open >= len(span):
            out.append(span[i:close_paren + 1])
            i = close_paren + 1
            continue
        body_close = find_matching_right(span, body_open)
        if body_close < 0:
            out.append(span[i:body_open + 1])
            i = body_open + 1
            continue

        body = span[body_open + 1:body_close]
        types = dict(visible_types)
        for param in split_top_level_commas(span[paren + 1:close_paren]):
            typed = re.match(rf"\s*([A-Za-z_]\w*)\s*:\s*({type_pattern})(?=\s|[=,;)]|$)", param)
            if typed:
                types[typed.group(1)] = typed.group(2)
        for typed in re.finditer(
            rf"\bvar\s+([A-Za-z_]\w*)\s*:\s*({type_pattern})(?=\s|[=,;)]|$)", body
        ):
            types[typed.group(1)] = typed.group(2)

        out.append(span[i:body_open + 1])
        out.append(restore_typed_array_index_write_body(body, types, class_name))
        out.append("}")
        i = body_close + 1


def convert_as3_number_methods(span: str) -> str:
    methods = {
        "toFixed": "numberToFixed",
        "toString": "valueToString",
    }
    i = 0
    while i < len(span):
        found: tuple[int, str] | None = None
        for method in methods:
            match = re.search(rf"\.{method}\s*\(", span[i:])
            if match is None:
                continue
            absolute = i + match.start()
            if found is None or absolute < found[0]:
                found = (absolute, method)
        if found is None:
            return span
        dot, method = found
        call_open = span.find("(", dot)
        call_close = find_matching_right(span, call_open)
        expr_start = find_expression_start(span, dot)
        if call_open < 0 or call_close < 0 or expr_start < 0:
            i = dot + 1
            continue
        if span[max(0, expr_start - 4):expr_start] == "new ":
            expr_start -= 4
        target = span[expr_start:dot].strip()
        if target.startswith("return "):
            expr_start += len("return ")
            target = target[len("return "):].strip()
        args = span[call_open + 1:call_close].strip()
        helper = methods[method]
        arg_tail = f", {args}" if args else ""
        replacement = f"{AS3_HELPER}.{helper}({target}{arg_tail})"
        span = span[:expr_start] + replacement + span[call_close + 1:]
        i = expr_start
    return span


def convert_as3_array_methods(span: str) -> str:
    methods = {
        "concat": "arrayConcat",
        "filter": "arrayFilter",
        "map": "arrayMap",
        "push": "arrayPush",
        "sort": "arraySort",
        "sortOn": "arraySortOn",
        "splice": "arraySplice",
    }
    i = 0
    while i < len(span):
        found: tuple[int, str] | None = None
        for method in methods:
            match = re.search(rf"\.{method}\s*\(", span[i:])
            if match is None:
                continue
            absolute = i + match.start()
            if found is None or absolute < found[0]:
                found = (absolute, method)
        if found is None:
            return span
        dot, method = found
        if dot >= len(AS3_HELPER) and span[dot - len(AS3_HELPER):dot] == AS3_HELPER:
            i = dot + 1
            continue
        call_open = span.find("(", dot)
        call_close = find_matching_right(span, call_open)
        expr_start = find_expression_start(span, dot)
        if call_open < 0 or call_close < 0 or expr_start < 0:
            i = dot + 1
            continue
        target = span[expr_start:dot].strip()
        args = span[call_open + 1:call_close].strip()
        if method in {"filter", "map"} and not args.startswith("function"):
            i = dot + 1
            continue
        if method == "push" and len(split_top_level_commas(args)) < 2:
            i = dot + 1
            continue
        helper = methods[method]
        arg_tail = f", {args}" if args else ""
        replacement = f"{AS3_HELPER}.{helper}({target}{arg_tail})"
        concat_args = split_top_level_commas(args) if method == "concat" else []
        if len(concat_args) > 1:
            replacement = target
            for arg in concat_args:
                replacement = f"{AS3_HELPER}.{helper}({replacement}, {arg.strip()})"
        span = span[:expr_start] + replacement + span[call_close + 1:]
        i = expr_start
    return span


AUDITED_NATIVE_VECTOR_SPLICES: dict[tuple[str, str], tuple[tuple[str, str, int], ...]] = {
    ("class_259", "method_7513"): (
        (
            f"{AS3_HELPER}.arraySplice(var_2531, _loc3_,1)",
            "var_2531.splice(_loc3_,1)",
            1,
        ),
    ),
    ("class_238", "method_3565"): (
        (
            (f"{AS3_HELPER}.arraySplice(var_15057, "
             f"{AS3_HELPER}.toInt({AS3_HELPER}.valueIndexOf(var_15057, param1)),1)"),
            f"var_15057.splice({AS3_HELPER}.toInt(var_15057.indexOf(param1)),1)",
            1,
        ),
    ),
    ("class_238", "method_3569"): (
        (
            (f"{AS3_HELPER}.arraySplice(var_10394, "
             f"{AS3_HELPER}.toInt({AS3_HELPER}.valueIndexOf(var_10394, param1)),1)"),
            f"var_10394.splice({AS3_HELPER}.toInt(var_10394.indexOf(param1)),1)",
            1,
        ),
    ),
    ("ScreenManager", "removeActiveScreen"): (
        (
            f"{AS3_HELPER}.arraySplice(ScreenManager.activeScreens, _loc2_,1)",
            "ScreenManager.activeScreens.splice(_loc2_,1)",
            1,
        ),
    ),
    ("class_512", "method_1483"): (
        (
            f"{AS3_HELPER}.arraySplice(var_11295, 0,{AS3_HELPER}.toInt(var_11295.length))",
            f"var_11295.splice(0,{AS3_HELPER}.toInt(var_11295.length))",
            1,
        ),
    ),
    ("class_680", "Destroy"): (
        (
            f"{AS3_HELPER}.arraySplice(class_680.var_3778, _loc1_,1)",
            "class_680.var_3778.splice(_loc1_,1)",
            1,
        ),
    ),
    ("class_691", "method_2408"): (
        (
            f"{AS3_HELPER}.arraySplice(var_15010, param1,1)",
            "var_15010.splice(param1,1)",
            1,
        ),
        (
            f"{AS3_HELPER}.arraySplice(var_13892, param1,1)",
            "var_13892.splice(param1,1)",
            1,
        ),
    ),
    ("class_703", "method_5849"): (
        (
            f"{AS3_HELPER}.arraySplice(var_7957, _loc2_,1)",
            "var_7957.splice(_loc2_,1)",
            1,
        ),
    ),
    ("class_250", "method_1524"): (
        (
            f"{AS3_HELPER}.arraySplice(var_7391, _loc5_,1)",
            "var_7391.splice(_loc5_,1)",
            1,
        ),
    ),
    ("class_15", "method_3570"): (
        (
            f"{AS3_HELPER}.arraySplice(var_10704, 0,{AS3_HELPER}.toInt(var_10704.length))",
            f"var_10704.splice(0,{AS3_HELPER}.toInt(var_10704.length))",
            1,
        ),
        (
            f"{AS3_HELPER}.arraySplice(var_12195, 0,{AS3_HELPER}.toInt(var_12195.length))",
            f"var_12195.splice(0,{AS3_HELPER}.toInt(var_12195.length))",
            1,
        ),
        (
            f"{AS3_HELPER}.arraySplice(var_6549, 0,{AS3_HELPER}.toInt(var_6549.length))",
            f"var_6549.splice(0,{AS3_HELPER}.toInt(var_6549.length))",
            1,
        ),
        (
            f"{AS3_HELPER}.arraySplice(var_3086, 0,{AS3_HELPER}.toInt(var_3086.length))",
            f"var_3086.splice(0,{AS3_HELPER}.toInt(var_3086.length))",
            1,
        ),
    ),
}


AUDITED_NATIVE_ARRAY_SPLICES: dict[tuple[str, str], tuple[tuple[str, str, int], ...]] = {
    ("class_112", "method_5096"): (
        (
            f"{AS3_HELPER}.arraySplice(class_112.var_3036, _loc6_,1)",
            "class_112.var_3036.splice(_loc6_,1)",
            1,
        ),
    ),
    ("class_29", "Clear"): (
        (
            f"{AS3_HELPER}.arraySplice(var_3813, 0,_loc1_)",
            "var_3813.splice(0,_loc1_)",
            1,
        ),
    ),
    ("class_123", "method_4398"): (
        (
            f"{AS3_HELPER}.arraySplice(var_6578, _loc2_,1)",
            "var_6578.splice(_loc2_,1)",
            1,
        ),
    ),
    ("class_622", "method_1724"): (
        (
            f"{AS3_HELPER}.arraySplice(var_3676, var_4505,1)",
            "var_3676.splice(var_4505,1)",
            1,
        ),
    ),
    ("class_112", "method_5916"): (
        (
            (f"{AS3_HELPER}.arraySplice(class_112.var_9206, "
             f"{AS3_HELPER}.valueIndexOf(class_112.var_9206, param1),1)"),
            "class_112.var_9206.splice(class_112.var_9206.indexOf(param1),1)",
            1,
        ),
    ),
    ("class_112", "method_2454"): (
        (
            (f"{AS3_HELPER}.arraySplice(class_112.var_15307, "
             f"{AS3_HELPER}.valueIndexOf(class_112.var_15307, param1),1)"),
            "class_112.var_15307.splice(class_112.var_15307.indexOf(param1),1)",
            1,
        ),
    ),
    ("class_422", "method_3045"): (
        (
            f"{AS3_HELPER}.arraySplice(var_7705, 0,{AS3_HELPER}.toInt(var_7705.length))",
            f"var_7705.splice(0,{AS3_HELPER}.toInt(var_7705.length))",
            1,
        ),
    ),
}


AUDITED_NATIVE_CONTAINER_CALLS: dict[tuple[str, str], tuple[tuple[str, str, int], ...]] = {
    ("CostumeType", "method_5801"): (
        (
            f"{AS3_HELPER}.arrayConcat(_loc5_.var_11472, param2.var_11472)",
            "_loc5_.var_11472.concat(param2.var_11472)",
            1,
        ),
        (
            f"{AS3_HELPER}.arrayConcat(_loc5_.var_2277, param2.var_2277)",
            "_loc5_.var_2277.concat(param2.var_2277)",
            1,
        ),
    ),
    ("StoreType", "method_4171"): (
        (
            f"{AS3_HELPER}.arraySort(StoreType.var_7848, function",
            "StoreType.var_7848.sort(function",
            1,
        ),
    ),
    ("class_112", "method_8030"): (
        (
            f"{AS3_HELPER}.arraySort(class_112.var_3036, class_112.method_3791)",
            "class_112.var_3036.sort(class_112.method_3791)",
            1,
        ),
    ),
    ("class_347", "method_2569"): (
        (
            (f"{AS3_HELPER}.toInt({AS3_HELPER}.valueIndexOf("
             "var_12157.var_8288, param1.var_11891))"),
            "var_12157.var_8288.indexOf(param1.var_11891)",
            1,
        ),
    ),
    ("class_7", "method_6908"): (
        (
            f"{AS3_HELPER}.toInt({AS3_HELPER}.valueIndexOf(var_982, _loc2_))",
            "var_982.indexOf(_loc2_)",
            1,
        ),
    ),
    ("class_347", "method_3"): (
        (
            (f"{AS3_HELPER}.toInt({AS3_HELPER}.valueIndexOf("
             "var_12157.var_8288, param2.var_4472.var_11891))"),
            "var_12157.var_8288.indexOf(param2.var_4472.var_11891)",
            1,
        ),
    ),
    ("ScoringType", "method_2727"): (
        (
            (f"{AS3_HELPER}.toInt({AS3_HELPER}.valueIndexOf("
             "param1.var_10958, param2))"),
            "param1.var_10958.indexOf(param2)",
            1,
        ),
    ),
    ("class_114", "method_644"): (
        (
            (f"{AS3_HELPER}.toInt({AS3_HELPER}.valueIndexOf("
             "param2.var_5802, param3.mCostumeName))"),
            "param2.var_5802.indexOf(param3.mCostumeName)",
            1,
        ),
    ),
    ("CostumeType", "method_4330"): (
        (
            (f"{AS3_HELPER}.toInt({AS3_HELPER}.valueIndexOf("
             "var_7289.var_10527.var_6349, param1))"),
            "var_7289.var_10527.var_6349.indexOf(param1)",
            1,
        ),
    ),
    ("class_444", "method_4864"): (
        (
            f"{AS3_HELPER}.toUInt({AS3_HELPER}.index(_loc5_, _loc4_))",
            "_loc5_[_loc4_]",
            1,
        ),
    ),
    ("class_719", "method_8460"): (
        (
            (f"{AS3_HELPER}.toInt({AS3_HELPER}.valueIndexOf("
             "_loc4_.var_5802, param1.var_14499))"),
            "_loc4_.var_5802.indexOf(param1.var_14499)",
            1,
        ),
    ),
    ("StoreType", "method_7201"): (
        (
            (f"{AS3_HELPER}.toInt({AS3_HELPER}.valueIndexOf("
             "HeroType.var_1558, HeroType.method_6400(var_14499)))"),
            "HeroType.var_1558.indexOf(HeroType.method_6400(var_14499))",
            1,
        ),
    ),
}


AUDITED_NATIVE_VECTOR_SLICES: dict[tuple[str, str], tuple[tuple[str, str, int], ...]] = {
    ("class_281", "method_4374"): (
        (
            f"{AS3_HELPER}.stringSlice(param3)",
            "param3.slice()",
            1,
        ),
    ),
    ("class_448", "OnTickScreen"): (
        (
            f"{AS3_HELPER}.stringSlice(owner.var_2208.var_11949)",
            "owner.var_2208.var_11949.slice()",
            1,
        ),
    ),
    ("GfxType", "method_8144"): (
        (
            f"{AS3_HELPER}.stringSlice(var_2277)",
            "var_2277.slice()",
            1,
        ),
        (
            f"{AS3_HELPER}.stringSlice(var_11472)",
            "var_11472.slice()",
            1,
        ),
    ),
    ("PaperDoll", "method_7826"): (
        (
            f"{AS3_HELPER}.stringSlice(var_12837.var_2277)",
            "var_12837.var_2277.slice()",
            1,
        ),
    ),
}


def restore_audited_native_vector_methods(span: str) -> str:
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    lookup_class = class_name or ""
    if lookup_class.startswith("Class_"):
        lookup_class = "class_" + lookup_class[6:]

    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return "".join(out)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        body_open = span.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(span, body_open) if body_open >= 0 else -1
        if body_close < 0:
            out.append(span[i:match.end()])
            i = match.end()
            continue

        body = span[body_open + 1:body_close]
        for needle, replacement, expected in AUDITED_NATIVE_VECTOR_SPLICES.get(
            (lookup_class, match.group(1)), ()
        ):
            if body.count(needle) == expected:
                body = body.replace(needle, replacement)
        for needle, replacement, expected in AUDITED_NATIVE_ARRAY_SPLICES.get(
            (lookup_class, match.group(1)), ()
        ):
            if body.count(needle) == expected:
                body = body.replace(needle, replacement)
        for needle, replacement, expected in AUDITED_NATIVE_CONTAINER_CALLS.get(
            (lookup_class, match.group(1)), ()
        ):
            if body.count(needle) == expected:
                body = body.replace(needle, replacement)
        for needle, replacement, expected in AUDITED_NATIVE_VECTOR_SLICES.get(
            (lookup_class, match.group(1)), ()
        ):
            if body.count(needle) == expected:
                body = body.replace(needle, replacement)
        out.append(span[i:body_open + 1])
        out.append(body)
        out.append("}")
        i = body_close + 1


def convert_remove_child_calls(span: str) -> str:
    return re.sub(
        r"\b([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+)\.removeChild\s*\(([^;\n]+?)\)",
        lambda m: f"{AS3_HELPER}.removeChild({m.group(1)}, {m.group(2).strip()})",
        span,
    )


def convert_error_name_reads(span: str) -> str:
    span = re.sub(
        rf"({re.escape(AS3_HELPER)}\.asType\([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*,\s*Error\s*\))\.name\b",
        lambda m: f"{AS3_HELPER}.errorName({m.group(1)})",
        span,
    )
    span = re.sub(r"\berror\.name\b", f"{AS3_HELPER}.errorName(error)", span)
    return span


def convert_logical_value_expressions(span: str) -> str:
    span = convert_dynamic_return_logical_or(span)
    span = re.sub(
        r"([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*\|\|=\s*([^;\n]+);",
        lambda m: f"{m.group(1)} = {AS3_HELPER}.logicalOr({m.group(1)}, {m.group(2).strip()});",
        span,
    )
    span = convert_assignment_logical_or(span)
    span = re.sub(
        r"(?P<prefix>\bvar\s+[A-Za-z_]\w*\s*:\s*(?:Dynamic|Array<Dynamic>|String)\s*=\s*)(?P<expr>[^;\n]*\|\|[^;\n]*);",
        lambda m: f"{m.group('prefix')}{logical_or_value(m.group('expr').strip())};",
        span,
    )
    span = convert_object_literal_logical_or(span)
    span = convert_call_argument_default_or(span)
    span = convert_string_wrapper_logical_or(span)
    span = convert_helper_call_logical_or(span)
    return convert_coercion_logical_or(span)


STRING_WRAPPER_RE = re.compile(rf"(?<![\w.]){re.escape(AS3_HELPER)}\.(?:coerceString|stringParam|stringArg)\s*\(")


def convert_string_wrapper_logical_or(span: str) -> str:
    for call in reversed(list(STRING_WRAPPER_RE.finditer(span))):
        close = find_matching_right(span, call.end() - 1)
        if close < 0:
            continue
        inner = span[call.end():close]
        if "||" not in inner or AS3_HELPER + ".logicalOr" in inner or len(split_top_level_commas(inner)) != 1:
            continue
        parts = split_top_level_operator(inner.strip(), "||")
        if len(parts) < 2 or any(is_boolean_value_expression(part) and not is_parenthesized_ternary(part) for part in parts):
            continue
        span = span[:call.end()] + logical_or_expression(parts) + span[close:]
    return span


def is_parenthesized_ternary(part: str) -> bool:
    stripped = part.strip()
    if not stripped.startswith("(") or find_matching_right(stripped, 0) != len(stripped) - 1:
        return False
    return len(split_top_level_operator(stripped[1:-1], "?")) > 1


DYNAMIC_RETURN_FUNCTION_RE = re.compile(r"\bfunction\s+[A-Za-z_]\w*\s*\([^()]*\)\s*:\s*Dynamic\s*\{")
RETURN_RE = re.compile(r"(?<![\w.$])return\s+")


def convert_dynamic_return_logical_or(span: str) -> str:
    out, pos = [], 0
    for fn in DYNAMIC_RETURN_FUNCTION_RE.finditer(span):
        if fn.start() < pos:
            continue
        open_at = fn.end() - 1
        depth, close = 0, None
        for i in range(open_at, len(span)):
            if span[i] == "{":
                depth += 1
            elif span[i] == "}":
                depth -= 1
                if depth == 0:
                    close = i
                    break
        if close is None:
            continue
        body = span[open_at:close]
        new_body, at = [], 0
        for ret in RETURN_RE.finditer(body):
            if ret.start() < at:
                continue
            end, d = ret.end(), 0
            while end < len(body):
                ch = body[end]
                if ch in "([{":
                    d += 1
                elif ch in ")]}":
                    d -= 1
                elif ch in "\"'":
                    q = ch
                    end += 1
                    while end < len(body) and body[end] != q:
                        end += 2 if body[end] == "\\" else 1
                elif ch == ";" and d == 0:
                    break
                if d < 0:
                    break
                end += 1
            if end >= len(body) or body[end] != ";":
                continue
            expr = body[ret.end():end]
            parts = split_top_level_operator(expr.strip(), "||")
            if len(parts) < 2 or "?" in expr or "&&" in expr:
                continue
            new_body.append(body[at:ret.end()] + logical_or_expression([" ".join(p.split()) for p in parts]))
            at = end
        new_body.append(body[at:])
        out.append(span[pos:open_at] + "".join(new_body))
        pos = close
    out.append(span[pos:])
    return "".join(out)


def convert_assignment_logical_or(span: str) -> str:
    def repl(match: re.Match[str]) -> str:
        expr = match.group("expr").strip()
        parts = split_top_level_operator(expr, "||")
        if len(parts) < 2:
            return match.group(0)
        if "?" in expr and ":" in expr:
            return match.group(0)
        if all(is_boolean_value_expression(part) for part in parts):
            return match.group(0)
        return f"{match.group('prefix')}{logical_or_expression(parts)};"

    span = re.sub(
        r"(?P<prefix>(?<![=!<>])=(?!=)\s*)(?P<expr>[^;\n]*\|\|[^;\n]*);",
        repl,
        span,
    )
    return re.sub(
        r"(?P<prefix>\bvar\s+[A-Za-z_]\w*\s*:\s*[A-Z]\w*\s*=\s*)(?P<expr>[^;\n]*\|\|[ \t]*\n[^;]*);",
        repl,
        span,
    )


NUMERIC_BRANCH_RE = re.compile(r"(?:" + re.escape(AS3_HELPER) + r"\.(?:round|toInt|toUInt|toFloat|numeric|ceil|floor)\(|"
                               r"Math\.|-?\d)")


def stringify_concat_ternary_numbers(span: str) -> str:
    i = 0
    while True:
        at = span.find("(", i)
        if at < 0:
            return span
        i = at + 1
        close = find_matching_right(span, at)
        if close < 0:
            continue
        before, after = span[:at].rstrip(), span[close + 1:].lstrip()
        if not (before.endswith("+") or after.startswith("+")) or re.search(r"[\w\])]$", before):
            continue
        parts = split_top_level_conditional(span[at + 1:close])
        if parts is None:
            continue
        cond, yes, no = parts
        placeholder = re.compile(r"\s*__AS3_NONCODE_\d+__\s*$")

        def numeric(branch: str) -> bool:
            branch = branch.strip()
            if re.fullmatch(r"-?\d+(?:\.\d+)?", branch):
                return True
            found = NUMERIC_BRANCH_RE.match(branch)
            if not found or not branch.endswith(")"):
                return False
            return find_matching_right(branch, branch.find("(")) == len(branch) - 1

        def wrap(branch: str) -> bool:
            branch = branch.strip()
            if not branch or placeholder.match(branch) or branch.startswith("Std.string(") or \
                    not re.match(r"[A-Za-z_$]", branch):
                return False
            depth = 0
            for ch in branch:
                if ch in "([{":
                    depth += 1
                elif ch in ")]}":
                    depth -= 1
                elif depth == 0 and not (ch.isalnum() or ch in "_$."):
                    return False
            return depth == 0

        if placeholder.match(no) and (numeric(yes) or wrap(yes)):
            yes = f" Std.string({yes.strip()}) "
        elif placeholder.match(yes) and (numeric(no) or wrap(no)):
            no = f" Std.string({no.strip()})"
        else:
            continue
        inner = f"{cond.rstrip()} ?{yes}:{no}"
        span = span[:at + 1] + inner + span[close:]


def convert_call_argument_default_or(span: str) -> str:
    out: list[str] = []
    pos = 0
    for match in re.finditer(r"\|\|\s*(?:\[\]|\{\}|__AS3_NONCODE_\d+__)(?=\s*[,)])", span):
        if match.start() < pos:
            continue
        depth, left = 0, match.start() - 1
        while left >= 0:
            ch = span[left]
            if ch in ")]}":
                depth += 1
            elif ch in "([{":
                if depth == 0:
                    break
                depth -= 1
            elif ch in ",;\n" and depth == 0:
                break
            left -= 1
        if left < 0 or span[left] not in "(,":
            continue
        if span[left] == "(" and not re.search(r"[\w)\]]\s*$", span[:left]):
            continue
        if span[left] == "," and not re.search(r"[\w)\]]\s*\([^()]*$", span[:left]) and "(" not in span[:left][-200:]:
            continue
        start = left + 1
        end = match.end()
        arg = span[start:end]
        parts = split_top_level_operator(arg.strip(), "||")
        if len(parts) < 2 or AS3_HELPER + ".logicalOr" in arg or arg.count("||") != len(parts) - 1 or start < pos:
            continue
        lead = arg[:len(arg) - len(arg.lstrip())]
        out.append(span[pos:start])
        out.append(lead + logical_or_expression(parts))
        pos = end
    out.append(span[pos:])
    return "".join(out)


OBJECT_LITERAL_KEY_RE = re.compile(r"[{,]\s*(?:\"[^\"]+\"|'[^']+'|[A-Za-z_]\w*)\s*:\s*")


def convert_object_literal_logical_or(span: str) -> str:
    out: list[str] = []
    pos = 0
    for prefix in OBJECT_LITERAL_KEY_RE.finditer(span):
        if prefix.start() < pos:
            continue
        end = prefix.end()
        depth = 0
        while end < len(span):
            ch = span[end]
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                if depth == 0:
                    break
                depth -= 1
            elif ch == "\n" or (ch == "," and depth == 0):
                break
            end += 1
        if depth != 0 or "||" not in span[prefix.end():end]:
            continue
        parts = split_top_level_operator(span[prefix.end():end].strip(), "||")
        if len(parts) < 2:
            continue
        out.append(span[pos:prefix.end()])
        out.append(logical_or_expression(parts))
        pos = end
    out.append(span[pos:])
    return "".join(out)


def is_boolean_value_expression(part: str) -> bool:
    stripped = part.strip()
    return bool(re.search(r"(?:==|!=|<=|>=|<|>)", stripped) or stripped.startswith("!") or stripped in {"true", "false"})


def convert_helper_call_logical_or(span: str) -> str:
    out: list[str] = []
    i = 0
    needle = AS3_HELPER + "."
    while i < len(span):
        start = span.find(needle, i)
        if start < 0:
            out.append(span[i:])
            return "".join(out)
        name_start = start + len(needle)
        name_end = name_start
        while name_end < len(span) and is_identifier_char(span[name_end]):
            name_end += 1
        method = span[name_start:name_end]
        if method in {"logicalOr", "logicalAnd", "toBool", "index"}:
            out.append(span[i:name_end])
            i = name_end
            continue
        open_index = skip_space_right(span, name_end)
        if open_index >= len(span) or span[open_index] != "(":
            out.append(span[i:name_end])
            i = name_end
            continue
        close_index = find_matching_right(span, open_index)
        if close_index < 0:
            out.append(span[i:name_end])
            i = name_end
            continue
        previous = skip_space_left(span, start - 1)
        before_previous = skip_space_left(span, previous - 1) if previous >= 0 else -1
        if previous >= 0 and (span[previous] == "!" or (span[previous] == "(" and before_previous >= 0 and span[before_previous] == "!")):
            out.append(span[i:close_index + 1])
            i = close_index + 1
            continue
        if previous >= 0 and span[previous] in "=!<>":
            out.append(span[i:close_index + 1])
            i = close_index + 1
            continue
        op = skip_space_right(span, close_index + 1)
        if op + 1 >= len(span) or span[op:op + 2] != "||":
            out.append(span[i:close_index + 1])
            i = close_index + 1
            continue
        right_start = skip_space_right(span, op + 2)
        right_end = find_logical_rhs_end(span, right_start)
        right = span[right_start:right_end].strip()
        if not right:
            out.append(span[i:close_index + 1])
            i = close_index + 1
            continue
        if is_boolean_value_expression(span[start:close_index + 1]) or is_boolean_value_expression(right):
            out.append(span[i:close_index + 1])
            i = close_index + 1
            continue
        right_parts = split_top_level_operator(right, "||")
        if len(right_parts) > 1:
            right = logical_or_expression(right_parts)
        out.append(span[i:start])
        out.append(f"{AS3_HELPER}.logicalOr({span[start:close_index + 1]}, {right})")
        i = right_end


def convert_parenthesized_helper_logical_or(span: str) -> str:
    def repl(match: re.Match[str]) -> str:
        previous = skip_space_left(span, match.start() - 1)
        if previous >= 0 and span[previous] == "!":
            return match.group(0)
        right = match.group(2).strip()
        if is_boolean_value_expression(match.group(1)) or is_boolean_value_expression(right):
            return match.group(0)
        return f"{AS3_HELPER}.logicalOr({match.group(1)}, {right})"

    return re.sub(
        rf"(?<![\w.])\(({re.escape(AS3_HELPER)}\.[A-Za-z_]\w*\([^;\n]+?\))\)\s*\|\|\s*([^,)}}\n]+)",
        repl,
        span,
    )


def convert_coercion_logical_or(span: str) -> str:
    callees = (f"{AS3_HELPER}.toInt", f"{AS3_HELPER}.toUInt", f"{AS3_HELPER}.toFloat")
    out: list[str] = []
    i = 0
    while i < len(span):
        found: tuple[int, str] | None = None
        for callee in callees:
            at = span.find(callee + "(", i)
            if at >= 0 and (found is None or at < found[0]):
                found = (at, callee)
        if found is None:
            out.append(span[i:])
            return "".join(out)
        start, callee = found
        open_index = start + len(callee)
        close_index = find_matching_right(span, open_index)
        if close_index < 0:
            out.append(span[i:start + len(callee)])
            i = start + len(callee)
            continue
        previous = skip_space_left(span, start - 1)
        if previous >= 0 and span[previous] in "=!<>":
            out.append(span[i:start])
            out.append(f"{callee}({convert_coercion_logical_or(span[open_index + 1:close_index])})")
            i = close_index + 1
            continue
        inner = span[open_index + 1:close_index]
        op = skip_space_right(span, close_index + 1)
        if op + 1 >= len(span) or span[op:op + 2] != "||":
            out.append(span[i:start])
            out.append(f"{callee}({convert_coercion_logical_or(inner)})")
            i = close_index + 1
            continue
        right_start = skip_space_right(span, op + 2)
        right_end = find_logical_rhs_end(span, right_start)
        right = span[right_start:right_end].strip()
        if not right:
            out.append(span[i:close_index + 1])
            i = close_index + 1
            continue
        out.append(span[i:start])
        out.append(f"{AS3_HELPER}.logicalOr({span[start:close_index + 1]}, {right})")
        i = right_end
    return "".join(out)


def fix_logical_bitwise_zero_comparisons(span: str) -> str:
    bitwise_op = r"(?<![&|])(?:&|\|)(?![&|])"
    pattern = re.compile(
        rf"(?P<neg>!?)\(\((?P<left>[^;\n]*?)\s*&&\s*"
        rf"\((?P<bit>[^;\n]*?{bitwise_op}[^;\n]*?)\)\)\s*"
        rf"(?P<op>[!=]=)\s*0\)"
    )

    def repl(match: re.Match[str]) -> str:
        if not re.search(r"\)\)\s*[!=]=\s*0\)$", match.group(0)):
            return match.group(0)
        if re.search(bitwise_op, match.group("left")):
            return match.group(0)
        base = f"({match.group('left').strip()} && ({match.group('bit').strip()}) != 0)"
        invert = (match.group("op") == "==") ^ bool(match.group("neg"))
        return f"!{base}" if invert else base

    previous = None
    while previous != span:
        previous = span
        span = pattern.sub(repl, span)
    return span


def fix_numeric_comparison_or_guard(span: str) -> str:
    index_call = rf"{re.escape(AS3_HELPER)}\.index\([^)]+\)"
    to_int_call = rf"{re.escape(AS3_HELPER)}\.toInt\([^)]+\)"
    patterns = [
        re.compile(
            rf"(?P<left>[A-Za-z_]\w*)\s*\+\s*"
            rf"\({re.escape(AS3_HELPER)}\.logicalOr\(1\s*>=\s*(?P<len>{to_int_call}),\s*(?P<idx>{index_call})\)\)\s*==\s*null"
        ),
        re.compile(
            rf"(?P<left>[A-Za-z_]\w*)\s*\+\s*"
            rf"\(1\s*>=\s*{re.escape(AS3_HELPER)}\.logicalOr\((?P<len>{to_int_call}),\s*(?P<idx>{index_call})\)\)\s*==\s*null"
        ),
    ]
    previous = None
    while previous != span:
        previous = span
        for pattern in patterns:
            span = pattern.sub(
                lambda m: f"{m.group('left')} + 1 >= {m.group('len')} || {m.group('idx')} == null",
                span,
            )
    return span


def fix_casted_index_as_type(span: str) -> str:
    needle = f"{AS3_HELPER}.asType("
    out: list[str] = []
    i = 0
    while True:
        start = span.find(needle, i)
        if start < 0:
            out.append(span[i:])
            return "".join(out)
        open_index = start + len(f"{AS3_HELPER}.asType")
        close_index = find_matching_right(span, open_index)
        if close_index < 0:
            out.append(span[i:start + len(needle)])
            i = start + len(needle)
            continue
        inner = span[open_index + 1:close_index]
        as_args = split_top_level_commas(inner)
        index_prefix = f"{AS3_HELPER}.index("
        if len(as_args) == 1 and as_args[0].strip().startswith(index_prefix):
            index_call = as_args[0].strip()
            index_open = index_call.find("(")
            index_close = find_matching_right(index_call, index_open)
            if index_close == len(index_call) - 1:
                index_args = split_top_level_commas(index_call[index_open + 1:index_close])
                if len(index_args) == 3 and re.match(r"^[A-Z][A-Za-z0-9_]*$", index_args[2].strip()):
                    out.append(span[i:start])
                    out.append(
                        f"{AS3_HELPER}.asType({AS3_HELPER}.index({index_args[0].strip()}, {index_args[1].strip()}), {index_args[2].strip()})"
                    )
                    i = close_index + 1
                    continue
        out.append(span[i:close_index + 1])
        i = close_index + 1


def fix_numeric_value_property_coercion(span: str) -> str:
    needle = f"{AS3_HELPER}.toFloat("
    out: list[str] = []
    i = 0
    while True:
        start = span.find(needle, i)
        if start < 0:
            out.append(span[i:])
            return "".join(out)
        open_index = start + len(f"{AS3_HELPER}.toFloat")
        close_index = find_matching_right(span, open_index)
        if close_index < 0 or not span.startswith(".value", close_index + 1):
            out.append(span[i:start + len(needle)])
            i = start + len(needle)
            continue
        inner = span[open_index + 1:close_index].strip()
        out.append(span[i:start])
        out.append(f"{AS3_HELPER}.toFloat(({inner}).value)")
        i = close_index + len(".value") + 1


def fix_malformed_logical_or_bool_call(span: str) -> str:
    pattern = re.compile(
        rf"{re.escape(AS3_HELPER)}\.toBool\("
        rf"{re.escape(AS3_HELPER)}\.logicalOr\((?P<left>[A-Za-z_]\w*)\)\s*&&\s*(?P<cmp>[^,\n;]+),\s*(?P<right>[^)\n;]+)\)"
    )
    return pattern.sub(
        lambda m: f"(({AS3_HELPER}.toBool({m.group('left')}) && {m.group('cmp').strip()}) || {AS3_HELPER}.toBool({m.group('right').strip()}))",
        span,
    )


def convert_known_screen_assignment_casts(span: str) -> str:
    replacements = {
        "var_8863 = param1;": "var_8863 = cast param1;",
        "var_6263 = param1;": "var_6263 = cast param1;",
    }
    for old, new in replacements.items():
        span = span.replace(old, new)
    return span


def convert_uint_returns(span: str) -> str:
    out: list[str] = []
    i = 0
    pattern = re.compile(r"\bfunction\s+[A-Za-z_]\w*\s*\([^)]*\)\s*:\s*UInt\s*\{")
    while True:
        match = pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return "".join(out)
        body_open = span.find("{", match.start())
        body_close = find_matching_right(span, body_open)
        if body_open < 0 or body_close < 0:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        body = span[body_open + 1:body_close]
        body = re.sub(
            rf"return\s+(-?{re.escape(AS3_HELPER)}\.index\([^;\n]+\));",
            lambda m: f"return {AS3_HELPER}.toUInt({m.group(1)});",
            body,
        )
        out.append(span[i:body_open + 1])
        out.append(body)
        out.append("}")
        i = body_close + 1


_DYNAMIC_INT_FUNCTION = re.compile(r"\bfunction\s*\(\s*([A-Za-z_]\w*\s*:\s*Dynamic(?:\s*,\s*[A-Za-z_]\w*\s*:\s*Dynamic)*)\s*\)\s*:\s*Int\s*\{")
_FIELD = r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+"
_FIELD_ARITHMETIC_RETURN = re.compile(rf"return\s+({_FIELD}\s*[-+*]\s*{_FIELD})\s*;")


def convert_dynamic_comparator_returns(span: str) -> str:
    out: list[str] = []
    i = 0
    while True:
        match = _DYNAMIC_INT_FUNCTION.search(span, i)
        if not match:
            out.append(span[i:])
            return "".join(out)
        body_open = span.find("{", match.end() - 1)
        body_close = find_matching_right(span, body_open)
        if body_close < 0:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        body = _FIELD_ARITHMETIC_RETURN.sub(lambda m: f"return {AS3_HELPER}.toInt({m.group(1)});",
                                            span[body_open + 1:body_close])
        out.append(span[i:body_open + 1])
        out.append(body)
        out.append("}")
        i = body_close + 1


def fix_type_frontier_value_shapes(span: str) -> str:
    span = span.replace(
        "if(by.best == null || c.hits > by.best.hits || c.hits == by.best.hits && c.damage > by.best.damage)",
        f'if(by.best == null || {AS3_HELPER}.compare(c.hits, ">", by.best.hits) || c.hits == by.best.hits && {AS3_HELPER}.compare(c.damage, ">", by.best.damage))',
    )
    span = span.replace(
        "pl.attacks.length > 0 ?",
        f"{AS3_HELPER}.toInt(pl.attacks.length) > 0 ?",
    )
    span = span.replace(
        "var _loc23_:Bool = (_loc12_.var_9222 != null ? _loc12_.var_9222.var_13464 : param2.var_10228.method_113(param2.var_10836)) <= param3.var_10228.method_113(param3.var_10836);",
        f"var _loc23_:Bool = _loc12_.var_9222 != null ? {AS3_HELPER}.toBool(_loc12_.var_9222.var_13464) : param2.var_10228.method_113(param2.var_10836) <= param3.var_10228.method_113(param3.var_10836);",
    )
    span = span.replace(
        "var_14893.var_11297 = _loc3_.var_10477 % 12;",
        f"var_14893.var_11297 = {AS3_HELPER}.toInt(_loc3_.var_10477 % 12);",
    )
    span = span.replace(
        "_loc42_.length != _loc15_.numRegister",
        f'{AS3_HELPER}.compare(_loc42_.length, "!=", _loc15_.numRegister)',
    )
    for name in ("param1", "param2", "param3", "param4"):
        span = span.replace(
            f"{name} != 0 &&",
            f'{AS3_HELPER}.compare({name}, "!=", 0) &&',
        )
    span = span.replace(
        "(_loc17_.var_11835 & 0xFFFF) == param1",
        f'{AS3_HELPER}.compare((_loc17_.var_11835 & 0xFFFF), "==", param1)',
    )
    span = span.replace(
        "(port.runtime.As3.index(param3.var_12798, _loc8_).var_11835 & 0xFFFF) == param1.var_13881.var_12172",
        f'{AS3_HELPER}.compare((port.runtime.As3.index(param3.var_12798, _loc8_).var_11835 & 0xFFFF), "==", param1.var_13881.var_12172)',
    )
    span = span.replace(
        "_loc17_.var_14823 == param2",
        f'{AS3_HELPER}.compare(_loc17_.var_14823, "==", param2)',
    )
    for obj in ("_loc18_", "_loc19_"):
        for name in ("param3", "param4"):
            span = span.replace(
                f"{obj}.var_11095 == {name}",
                f'{AS3_HELPER}.compare({obj}.var_11095, "==", {name})',
            )
    span = span.replace(
        "var_5913 % 10 >= var_6558.var_8279.var_3377",
        f'{AS3_HELPER}.compare(var_5913 % 10, ">=", var_6558.var_8279.var_3377)',
    )
    span = span.replace(
        "var_5913 % 10 < var_6558.var_8279.var_3377",
        f'{AS3_HELPER}.compare(var_5913 % 10, "<", var_6558.var_8279.var_3377)',
    )
    span = span.replace(
        f"{AS3_HELPER}.toUInt({AS3_HELPER}.index({AS3_HELPER}.index(var_9966, param1), param2)) + {AS3_HELPER}.mathMax2(50,{AS3_HELPER}.toFloat({AS3_HELPER}.index({AS3_HELPER}.index(var_106, param1), param2))) > _loc3_",
        f'{AS3_HELPER}.compare({AS3_HELPER}.toUInt({AS3_HELPER}.index({AS3_HELPER}.index(var_9966, param1), param2)) + {AS3_HELPER}.mathMax2(50,{AS3_HELPER}.toFloat({AS3_HELPER}.index({AS3_HELPER}.index(var_106, param1), param2))), ">", _loc3_)',
    )
    span = span.replace(
        "back.var_960 != extra",
        f'{AS3_HELPER}.compare(back.var_960, "!=", extra)',
    )
    span = span.replace(
        "v < NAMES.length",
        f'{AS3_HELPER}.compare(v, "<", NAMES.length)',
    )
    span = span.replace(
        "c.mID == controllerID",
        f'{AS3_HELPER}.compare(c.mID, "==", controllerID)',
    )
    span = span.replace(
        "taken.length >= MAX_STEPS",
        f'{AS3_HELPER}.compare(taken.length, ">=", MAX_STEPS)',
    )
    span = span.replace(
        "at >= steps.length",
        f'{AS3_HELPER}.compare(at, ">=", steps.length)',
    )
    span = span.replace(
        "n > MAX_FILES",
        f'{AS3_HELPER}.compare(n, ">", MAX_FILES)',
    )
    span = span.replace(
        "n > PART_SIZE",
        f'{AS3_HELPER}.compare(n, ">", PART_SIZE)',
    )
    span = span.replace(
        "m > MAX_MODS",
        f'{AS3_HELPER}.compare(m, ">", MAX_MODS)',
    )
    span = span.replace(
        "(_loc11_ != null ? _loc11_.var_14656 : (_loc12_ != null ? _loc12_.var_12098 : 0)) == param1",
        f'{AS3_HELPER}.compare((_loc11_ != null ? _loc11_.var_14656 : (_loc12_ != null ? _loc12_.var_12098 : 0)), "==", param1)',
    )
    span = span.replace(
        "_loc11_.var_14656 == param1",
        f'{AS3_HELPER}.compare(_loc11_.var_14656, "==", param1)',
    )
    span = span.replace(
        "_loc12_.var_12098 == param1",
        f'{AS3_HELPER}.compare(_loc12_.var_12098, "==", param1)',
    )
    return span


def fix_logical_and_value_comparison_grouping(span: str) -> str:
    fixed: list[str] = []
    for line in span.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if "&&" not in stripped:
            fixed.append(line)
            continue
        index = 0
        while index < len(stripped):
            if stripped[index] != "(":
                index += 1
                continue
            close = find_matching_right(stripped, index)
            if close < 0:
                break
            inner = stripped[index + 1:close]
            if len(split_top_level_operator(inner, "&&")) < 2 or "?" in inner:
                index += 1
                continue
            after = stripped[close + 1:]
            before = stripped[:index]
            remove = bool(re.match(r"\s*(?:==|!=)\s*(?:null|0\b|[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)", after))
            remove = remove or bool(re.search(r"(?:==|!=)\s*$", before))
            if remove:
                stripped = before + inner + after
                index = max(0, index - 1)
                continue
            index += 1
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_logical_and_numeric_tail(span: str) -> str:
    fixed: list[str] = []
    helper_prefixes = tuple(f"{AS3_HELPER}.to{name}" for name in ("Int", "UInt", "Float"))
    for line in span.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if "&&" not in stripped or f"{AS3_HELPER}.to" not in stripped:
            fixed.append(line)
            continue
        index = 0
        while True:
            match = re.search(r"&&\s*port\.runtime\.As3\.to(?:Int|UInt|Float)\(", stripped[index:])
            if not match:
                break
            start = index + match.start()
            call_start = index + match.start() + match.group(0).find(f"{AS3_HELPER}.to")
            open_index = stripped.find("(", call_start)
            close = find_matching_right(stripped, open_index)
            if close < 0:
                break
            call = stripped[call_start:close + 1]
            if not call.startswith(helper_prefixes):
                index = close + 1
                continue
            next_index = skip_space_right(stripped, close + 1)
            if next_index < len(stripped) and stripped[next_index:next_index + 2] in {"==", "!=", "<=", ">=", "&&", "||"}:
                index = close + 1
                continue
            if next_index < len(stripped) and stripped[next_index] in "<>":
                index = close + 1
                continue
            if next_index < len(stripped) and stripped[next_index] in "+-*/%":
                index = close + 1
                continue
            stripped = stripped[:close + 1] + " != 0" + stripped[close + 1:]
            index = close + len(" != 0") + 1
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_bool_relational_comparison_grouping(span: str) -> str:
    fixed: list[str] = []
    for line in span.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if "== (" not in stripped and "!= (" not in stripped:
            fixed.append(line)
            continue
        index = 0
        while index < len(stripped):
            match = re.search(r"(==|!=)\s*\(", stripped[index:])
            if not match:
                break
            open_index = index + match.end() - 1
            left_close = find_matching_right(stripped, open_index)
            if left_close < 0:
                break
            op_index = skip_space_right(stripped, left_close + 1)
            rel_op = None
            for candidate in ("<=", ">=", "<", ">"):
                if stripped.startswith(candidate, op_index):
                    rel_op = candidate
                    break
            if rel_op is None:
                index = left_close + 1
                continue
            right_open = skip_space_right(stripped, op_index + len(rel_op))
            if right_open >= len(stripped) or stripped[right_open] != "(":
                index = left_close + 1
                continue
            right_close = find_matching_right(stripped, right_open)
            if right_close < 0:
                break
            left = stripped[open_index + 1:left_close]
            right = stripped[right_open + 1:right_close]
            replacement = f"({left} {rel_op} {right})"
            stripped = stripped[:open_index] + replacement + stripped[right_close + 1:]
            index = open_index + len(replacement)
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_malformed_if_not_bitwise_comparison(span: str) -> str:
    out: list[str] = []
    i = 0
    for match in re.finditer(r"\bif!\(", span):
        if match.start() < i:
            continue
        open_index = match.end() - 1
        close = find_matching_right(span, open_index)
        if close < 0:
            continue
        inner = span[open_index + 1:close]
        if "\n" in inner or not re.search(r"&&\s*\([^;\n]*(?<![&|])[&|](?![&|])[^;\n]*\)\s*!=\s*0\s*$", inner):
            continue
        out.append(span[i:match.start()])
        out.append(f"if(!({inner}))")
        i = close + 1
    out.append(span[i:])
    return "".join(out)


def fix_boolean_numeric_comparisons(span: str) -> str:
    fixed: list[str] = []
    for line in span.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        index = 0
        while index < len(stripped):
            match = re.search(r"(==|!=)\s*0\b", stripped[index:])
            if not match:
                break
            op_start = index + match.start()
            op = match.group(1)
            left_end = skip_space_left(stripped, op_start - 1)
            left_start = parse_atom_left(stripped, left_end)
            if left_start < 0:
                index = op_start + len(op)
                continue
            left = stripped[left_start:left_end + 1]
            inner = strip_wrapping_parens(left)
            if "&&" not in inner and "||" not in inner:
                index = op_start + len(op)
                continue
            replacement = f"!({inner})" if op == "==" else f"({inner})"
            compare_end = index + match.end()
            stripped = stripped[:left_start] + replacement + stripped[compare_end:]
            index = left_start + len(replacement)
        fixed.append(stripped + ending)
    return "".join(fixed)


def _top_level_numeric_bitwise(expr: str) -> bool:
    inner = expr[1:-1]
    depth = 0
    top_bitwise = False
    i = 0
    while i < len(inner):
        ch = inner[i]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif depth == 0:
            if inner[i:i + 2] in ("&&", "||", "==", "!=", "<=", ">=") or ch in "<>?!":
                return False
            if ch in "&|^":
                top_bitwise = True
        i += 1
    return top_bitwise


def fix_logical_bitwise_operand_truthiness(span: str) -> str:
    fixed: list[str] = []
    for line in span.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        index = 0
        while index < len(stripped):
            at = stripped.find("&&", index)
            if at < 0:
                break
            expr_start = skip_space_right(stripped, at + 2)
            if expr_start >= len(stripped) or stripped[expr_start] != "(":
                index = at + 2
                continue
            expr_end = find_matching_right(stripped, expr_start)
            if expr_end < 0:
                break
            expr = stripped[expr_start:expr_end + 1]
            after = skip_space_right(stripped, expr_end + 1)
            if stripped.startswith(("==", "!=", "<", ">"), after):
                index = expr_end + 1
                continue
            if _top_level_numeric_bitwise(expr):
                stripped = stripped[:expr_end + 1] + " != 0" + stripped[expr_end + 1:]
                index = expr_end + len(" != 0") + 1
            else:
                index = expr_end + 1
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_logical_null_comparisons(span: str) -> str:
    fixed: list[str] = []
    for line in span.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        index = 0
        while index < len(stripped):
            match = re.search(r"(==|!=)\s*null\b", stripped[index:])
            if not match:
                break
            op_start = index + match.start()
            op = match.group(1)
            left_end = skip_space_left(stripped, op_start - 1)
            left_start = parse_atom_left(stripped, left_end)
            if left_start < 0:
                index = op_start + len(op)
                continue
            left = strip_wrapping_parens(stripped[left_start:left_end + 1])
            parts = split_top_level_operator(left, "||")
            if len(parts) < 2:
                index = op_start + len(op)
                continue
            last = parts[-1].strip()
            call = AS3_HELPER + ".toBool("
            if not last.startswith(call) or not last.endswith(")"):
                index = op_start + len(op)
                continue
            open_index = last.find("(")
            close_index = find_matching_right(last, open_index)
            if close_index != len(last) - 1:
                index = op_start + len(op)
                continue
            value = last[open_index + 1:close_index].strip()
            replacement = "(" + " || ".join([p.strip() for p in parts[:-1]] + [f"{value} {op} null"]) + ")"
            compare_end = index + match.end()
            stripped = stripped[:left_start] + replacement + stripped[compare_end:]
            index = left_start + len(replacement)
        fixed.append(stripped + ending)
    return "".join(fixed)


def strip_wrapping_parens(expr: str) -> str:
    expr = expr.strip()
    while expr.startswith("(") and expr.endswith(")"):
        close = find_matching_right(expr, 0)
        if close != len(expr) - 1:
            break
        expr = expr[1:-1].strip()
    return expr


def find_logical_rhs_end(span: str, start: int) -> int:
    depth = 0
    i = start
    while i < len(span):
        ch = span[i]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            if depth == 0:
                return i
            depth -= 1
        elif depth == 0 and ch in ",;\n?":
            return i
        i += 1
    return i


def split_ternary_skipping_strings(text: str) -> tuple[str, str, str] | None:
    depth, question, colon, quote, pos = 0, -1, -1, "", 0
    while pos < len(text):
        ch = text[pos]
        if quote:
            if ch == "\\":
                pos += 1
            elif ch == quote:
                quote = ""
        elif ch in "\"'":
            quote = ch
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif depth == 0 and ch == "?":
            if question >= 0:
                return None
            question = pos
        elif depth == 0 and ch == ":" and question >= 0:
            if colon >= 0:
                return None
            colon = pos
        pos += 1
    if question < 0 or colon < 0:
        return None
    return text[:question], text[question + 1:colon], text[colon + 1:]


def logical_or_value(expr: str) -> str:
    branches = split_ternary_skipping_strings(expr)
    if branches is not None:
        cond, yes, no = branches
        cond = cond.strip()
        if len(split_top_level_operator(cond, "||")) > 1:
            cond = f"({cond})"
        return f"{cond} ? {logical_or_value(yes.strip())} : {logical_or_value(no.strip())}"
    parts = split_top_level_operator(expr, "||")
    return logical_or_expression(parts) if len(parts) > 1 else expr


def logical_or_expression(parts: list[str]) -> str:
    expression = parts[0].strip()
    for part in parts[1:]:
        expression = f"{AS3_HELPER}.logicalOr({expression}, {part.strip()})"
    return expression


def convert_numeric_not_expressions(span: str) -> str:
    return re.sub(
        r"!\s*\(([^()\n]*(?:[%+\-*/]|(?<![&|])(?:&|\|)(?![&|]))[^()\n]*)\)",
        lambda m: f"!{AS3_HELPER}.toBool({m.group(1).strip()})",
        span,
    )


def _has_top_level_ternary(text: str) -> bool:
    depth = 0
    for ch in text:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == "?" and depth == 0:
            return True
    return False


def convert_parenthesized_logical_values(span: str) -> str:
    out: list[str] = []
    i = 0
    while i < len(span):
        if span[i] != "(":
            out.append(span[i])
            i += 1
            continue
        close = find_matching_right(span, i)
        if close < 0:
            out.append(span[i])
            i += 1
            continue
        inner = span[i + 1:close]
        parts = split_top_level_operator(inner, "||")
        if (len(parts) >= 2 and not _has_top_level_ternary(inner) and not is_condition_parenthesis(span, i)
                and not is_call_parenthesis(span, i) and not is_negated_parenthesis(span, i)):
            out.append(f"({logical_or_expression(parts)})")
        else:
            out.append("(")
            out.append(convert_parenthesized_logical_values(inner))
            out.append(")")
        i = close + 1
    return "".join(out)


def is_negated_parenthesis(span: str, open_index: int) -> bool:
    previous = skip_space_left(span, open_index - 1)
    return previous >= 0 and span[previous] == "!"


def convert_typed_var_initializers(span: str) -> str:
    def wrap(match: re.Match[str]) -> str:
        name = match.group("name")
        type_name = match.group("type")
        expr = convert_coercion_logical_or(match.group("expr").strip())
        if "function" in expr:
            return match.group(0)
        helper = {
            "Int": "toInt",
            "UInt": "toUInt",
            "Float": "toFloat",
            "Bool": "toBool",
        }.get(type_name)
        if helper is None or expr.startswith(f"{AS3_HELPER}.{helper}("):
            return match.group(0)
        if type_name == "Bool" and (
            expr in {"true", "false"}
            or re.search(r"(?:==|!=|<=|>=|<|>)", expr)
            or "&&" in expr
            or "||" in expr
            or expr.startswith("!")
            or ".test(" in expr
        ):
            return match.group(0)
        if type_name == "Float":
            if f"{AS3_HELPER}.logicalOr(" not in expr:
                return match.group(0)
        elif type_name in {"Int", "UInt"}:
            simple_numeric = re.fullmatch(r"-?\d+", expr) or re.fullmatch(r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*", expr)
            needs_numeric_coercion = (
                "/" in expr
                or "?" in expr
                or (not simple_numeric and re.search(r"[+\-*%]", expr))
                or f"{AS3_HELPER}.index(" in expr
                or f"{AS3_HELPER}.logicalOr(" in expr
                or f"{AS3_HELPER}.mathMin(" in expr
                or f"{AS3_HELPER}.mathMax(" in expr
                or f"{AS3_HELPER}.mathMin2(" in expr
                or f"{AS3_HELPER}.mathMax2(" in expr
                or (re.search(r"[+\-*%]", expr) and "." in expr)
                or (type_name == "UInt" and re.fullmatch(r"\d+", expr) and int(expr) > 2147483647)
            )
            if not needs_numeric_coercion:
                return match.group(0)
        return f"var {name}:{type_name} = {AS3_HELPER}.{helper}({expr});"

    return re.sub(
        r"\bvar\s+(?P<name>[A-Za-z_]\w*)\s*:\s*(?P<type>Int|UInt|Float|Bool)\s*=\s*(?P<expr>[^;\n]+);",
        wrap,
        span,
    )


def convert_reference_typed_initializers(span: str) -> str:
    cast_types = AS3_CAST_CALL_TYPES | {"BitmapData", "LoaderInfo"}

    def wrap(match: re.Match[str]) -> str:
        name = match.group("name")
        type_name = match.group("type")
        expr = match.group("expr").strip()
        if (
            expr == "null"
            or expr.startswith("new ")
            or expr.startswith("cast ")
            or expr.startswith("cast(")
            or expr.startswith(f"{AS3_HELPER}.asType(")
            or not should_cast_reference_type(type_name, cast_types)
        ):
            return match.group(0)
        if "?" in expr and ":" in expr:
            if reference_typed_ternary_has_matching_call_arms(expr):
                return match.group(0)
            expr = f"({expr})"
        return f"var {name}:{type_name} = cast({expr});"

    span = re.sub(
        r"\bvar\s+(?P<name>[A-Za-z_]\w*)\s*:\s*(?P<type>(?:[A-Z][A-Za-z_0-9]*|class_\d+))\s*=\s*(?P<expr>[^;\n]+);",
        wrap,
        span,
    )
    span = convert_reference_typed_assignments_scoped(span, cast_types)
    return convert_class_typed_assignments(span)


def reference_typed_ternary_has_matching_call_arms(expr: str) -> bool:
    question = split_top_level_operator(expr, "?")
    if len(question) != 2:
        return False
    arms = split_top_level_operator(question[1], ":")
    if len(arms) != 2:
        return False
    left, right = (ternary_arm_callee(arm.strip()) for arm in arms)
    return left is not None and left == right


def ternary_arm_callee(expr: str) -> str | None:
    open_index = expr.find("(")
    if open_index < 0:
        return None
    close_index = find_matching_right(expr, open_index)
    if close_index != len(expr) - 1:
        return None
    callee = expr[:open_index].strip()
    return callee if re.fullmatch(r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*", callee) else None


def convert_reference_typed_assignments_scoped(span: str, cast_types: set[str]) -> str:
    out: list[str] = []
    i = 0
    while True:
        match = re.search(r"\bfunction\s+[A-Za-z_]\w*\s*\(", span[i:])
        if not match:
            out.append(span[i:])
            return "".join(out)
        start = i + match.start()
        body_open = span.find("{", start)
        if body_open < 0:
            out.append(span[i:])
            return "".join(out)
        body_close = find_matching_right(span, body_open)
        if body_close < 0:
            out.append(span[i:body_open + 1])
            i = body_open + 1
            continue
        body = span[body_open + 1:body_close]
        out.append(span[i:body_open + 1])
        out.append(convert_reference_typed_assignments_in_body(body, cast_types))
        out.append("}")
        i = body_close + 1


def convert_reference_typed_assignments_in_body(body: str, cast_types: set[str]) -> str:
    types = {
        match.group("name"): match.group("type")
        for match in re.finditer(
            r"\bvar\s+(?P<name>[A-Za-z_]\w*)\s*:\s*(?P<type>(?:[A-Z][A-Za-z_0-9]*|class_\d+))\b",
            body,
        )
        if should_cast_reference_type(match.group("type"), cast_types)
    }
    if not types:
        return body

    def repl(match: re.Match[str]) -> str:
        name = match.group("name")
        type_name = types.get(name)
        expr = match.group("expr").strip()
        if (
            type_name is None
            or expr == "null"
            or expr.startswith("new ")
            or expr.startswith("cast ")
            or expr.startswith("cast(")
            or expr.startswith(f"{AS3_HELPER}.asType(")
        ):
            return match.group(0)
        return f"{match.group('indent')}{name} = cast({expr});"

    return re.sub(
        r"(?P<indent>^[ \t]*)(?P<name>[A-Za-z_]\w*)\s*=\s*(?P<expr>[^;\n]+);",
        repl,
        body,
        flags=re.MULTILINE,
    )


def convert_class_typed_assignments(span: str) -> str:
    out: list[str] = []
    i = 0
    while True:
        match = re.search(r"\bfunction\s+[A-Za-z_]\w*\s*\(", span[i:])
        if not match:
            out.append(span[i:])
            return "".join(out)
        start = i + match.start()
        body_open = span.find("{", start)
        if body_open < 0:
            out.append(span[i:])
            return "".join(out)
        body_close = find_matching_right(span, body_open)
        if body_close < 0:
            out.append(span[i:body_open + 1])
            i = body_open + 1
            continue
        body = span[body_open + 1:body_close]
        out.append(span[i:body_open + 1])
        out.append(convert_class_typed_assignments_in_body(body))
        out.append("}")
        i = body_close + 1


def convert_class_typed_assignments_in_body(body: str) -> str:
    types = {
        match.group("name"): match.group("type")
        for match in re.finditer(
            r"\bvar\s+(?P<name>[A-Za-z_]\w*)\s*:\s*(?P<type>(?:Class|class)_\d+"
            + "".join(f"|{re.escape(name)}" for name in DEOBFUSCATED_CLASSES.split()) + r")\b",
            body,
        )
    }
    if not types:
        return body

    def repl(match: re.Match[str]) -> str:
        name = match.group("name")
        expr = match.group("expr").strip()
        type_name = types.get(name)
        if (type_name is None or expr == "null" or expr.startswith("cast ") or expr.startswith("cast(")
                or expr.startswith(f"{AS3_HELPER}.asType(")):
            return match.group(0)
        return f"{match.group('indent')}{name} = cast({expr});"

    return re.sub(
        r"(?P<indent>^[ \t]*)(?P<name>[A-Za-z_]\w*)\s*=\s*(?P<expr>[^;\n]+);",
        repl,
        body,
        flags=re.MULTILINE,
    )


def should_cast_reference_type(type_name: str, cast_types: set[str]) -> bool:
    return (
        type_name in cast_types
        or type_name in {"IMap", "IntMap", "StringMap"}
        or type_name.startswith("Class_")
        or type_name.startswith("class_")
        or type_name.endswith("Event")
        or type_name.endswith("Type")
        or type_name.endswith("Data")
        or type_name.endswith("Object")
        or type_name.endswith("Sprite")
        or type_name.endswith("Screen")
    )


def convert_reference_typed_assignment(span: str, match: re.Match[str], cast_types: set[str]) -> str:
    name = match.group("name")
    type_match = re.search(rf"\bvar\s+{re.escape(name)}\s*:\s*((?:[A-Z][A-Za-z_0-9]*|class_\d+))\b", span[:match.start()])
    if not type_match:
        return match.group(0)
    type_name = type_match.group(1)
    expr = match.group("expr").strip()
    if (
        not should_cast_reference_type(type_name, cast_types)
        or expr == "null"
        or expr.startswith("new ")
        or expr.startswith("cast ")
        or expr.startswith("cast(")
        or expr.startswith(f"{AS3_HELPER}.asType(")
    ):
        return match.group(0)
    return f"{match.group('indent')}{name} = cast({expr});"


def convert_default_logical_or_calls(span: str) -> str:
    callees = ("Std.string", STRING_ARG_CALL, f"{AS3_HELPER}.toInt", f"{AS3_HELPER}.toUInt", f"{AS3_HELPER}.toFloat", f"{AS3_HELPER}.values")
    out: list[str] = []
    i = 0
    while i < len(span):
        found: tuple[int, str] | None = None
        for callee in callees:
            at = span.find(callee + "(", i)
            if at >= 0 and (found is None or at < found[0]):
                found = (at, callee)
        if found is None:
            out.append(span[i:])
            return "".join(out)
        start, callee = found
        open_index = start + len(callee)
        close_index = find_matching_right(span, open_index)
        if close_index < 0:
            out.append(span[i:start + len(callee)])
            i = start + len(callee)
            continue
        inner = span[open_index + 1:close_index]
        parts = split_top_level_operator(inner, "||")
        out.append(span[i:start])
        if len(parts) == 2:
            out.append(f"{callee}({AS3_HELPER}.logicalOr({parts[0].strip()}, {parts[1].strip()}))")
        else:
            out.append(f"{callee}({convert_default_logical_or_calls(inner)})")
        i = close_index + 1
    return "".join(out)


def convert_call_argument_logical_or(span: str) -> str:
    out: list[str] = []
    i = 0
    while i < len(span):
        open_index = span.find("(", i)
        if open_index < 0:
            out.append(span[i:])
            return "".join(out)
        close_index = find_matching_right(span, open_index)
        if close_index < 0:
            out.append(span[i:open_index + 1])
            i = open_index + 1
            continue
        name_end = skip_space_left(span, open_index - 1) + 1
        name_start = name_end - 1
        while name_start >= 0 and (is_identifier_char(span[name_start]) or span[name_start] == "."):
            name_start -= 1
        callee = span[name_start + 1:name_end]
        if callee in {"if", "while", "switch", "for", "catch", "function"}:
            out.append(span[i:close_index + 1])
            i = close_index + 1
            continue
        args = span[open_index + 1:close_index]
        parts = split_top_level_commas(args)
        converted: list[str] = []
        changed = False
        for part in parts:
            stripped = part.strip()
            or_parts = split_top_level_operator(stripped, "||")
            if len(or_parts) > 1 and not any(is_boolean_value_expression(piece) for piece in or_parts):
                converted.append(logical_or_value(stripped))
                changed = True
            else:
                converted.append(part)
        out.append(span[i:open_index + 1])
        out.append(",".join(converted) if changed else args)
        out.append(")")
        i = close_index + 1
    return "".join(out)


def convert_known_argument_coercions(span: str) -> str:
    span = re.sub(
        r"(?<!function )(?P<prefix>\.?)method_4897\s*\(([^,\n]+),\s*([^,\n]+),\s*([^)]+)\)",
        lambda m: f"{m.group('prefix')}method_4897({m.group(2).strip()}, {AS3_HELPER}.toInt({m.group(3).strip()}), {m.group(4).strip()})",
        span,
    )
    span = convert_method_4623_args(span)
    span = convert_single_string_arg_methods(span)
    span = convert_class_714_string_args(span)
    span = convert_display_object_args(span)
    span = re.sub(
        r"\.method_1467\s*\(([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?)\)",
        lambda m: f".method_1467({string_arg(m.group(1))})",
        span,
    )
    span = re.sub(r"\bType\.allEnums\s*\(\s*((?:Class|class)_\d+)\s*\)", r"Type.allEnums(untyped \1)", span)
    span = re.sub(r"\bType\.createEnum\s*\(\s*((?:Class|class)_\d+)\s*,", r"Type.createEnum(untyped \1,", span)
    span = re.sub(r"\bType\.createEnumIndex\s*\(\s*((?:Class|class)_\d+)\s*,", r"Type.createEnumIndex(untyped \1,", span)
    span = convert_named_call_args(span, "Type.enumConstructor", {0: cast_arg})
    span = convert_string_returns(span)
    span = convert_string_typed_initializers(span)
    return span


def cast_arg(value: str) -> str:
    value = value.strip()
    return value if value.startswith("cast ") else f"cast {value}"


def string_arg(value: str) -> str:
    value = value.strip()
    if value == "null" or value.startswith(('"', "'", "Std.string(", f"{STRING_ARG_CALL}(")):
        return value
    if re.fullmatch(r"__AS3_NONCODE_\d+__", value):
        return value
    parts = split_top_level_operator(value, "||")
    if len(parts) > 1:
        value = logical_or_expression(parts)
    elif is_string_led_concatenation(value):
        return value
    elif is_declared_string_expression(value):
        return value
    return f"{STRING_ARG_CALL}({value})" if STRING_ARG_MACRO else f"Std.string({value})"


DECLARED_STRING_ARGUMENTS = True
_CHAIN_LINK_RE = re.compile(r"\s*(?:\.\s*([A-Za-z_]\w*)|(\()|(\[))")


def is_declared_string_expression(value: str) -> bool:
    if not DECLARED_STRING_ARGUMENTS:
        return False
    table = load_element_types() or {}
    match = re.match(r"[A-Za-z_]\w*", value)
    if not match:
        return False
    last, last_call, i = match.group(0), False, match.end()
    while i < len(value):
        link = _CHAIN_LINK_RE.match(value, i)
        if not link:
            return False
        if link.group(1):
            last, last_call, i = link.group(1), False, link.end()
            continue
        close_index = find_matching_right(value, link.end() - 1)
        if close_index < 0:
            return False
        if link.group(2):
            last = last if not last_call else ""
            last_call = True
        else:
            last, last_call = "", False
        i = close_index + 1
    if last_call:
        return last in set(table.get("string_methods") or ())
    return bool(last) and not last.startswith(("_loc", "param")) and last in set(table.get("strings") or ())


def is_string_led_concatenation(value: str) -> bool:
    terms = split_top_level_operator(value, "+")
    literal = r"\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'|__AS3_NONCODE_\d+__"
    if len(terms) < 2 or not re.fullmatch(literal, terms[0].strip()):
        return False
    return all(len(split_top_level_operator(value, op)) == 1 for op in ("?", "||", "&&", "==", "!=", "<", ">"))


def convert_single_string_arg_methods(span: str) -> str:
    for method in ("method_823", "method_1467", "method_4016", "method_6032"):
        span = convert_named_call_args(span, "." + method, {0: string_arg})
    return span


def convert_class_714_string_args(span: str) -> str:
    for method in ("Class_714.method_9120", "Class_714.method_8170", "class_714.method_9120", "class_714.method_8170"):
        span = convert_named_call_args(span, method, {1: string_arg})
    return span


def convert_named_call_args(span: str, callee: str, converters: dict[int, object]) -> str:
    out: list[str] = []
    i = 0
    needle = callee + "("
    while True:
        start = span.find(needle, i)
        if start < 0:
            out.append(span[i:])
            return "".join(out)
        open_index = start + len(callee)
        close_index = find_matching_right(span, open_index)
        if close_index < 0:
            out.append(span[i:start + len(needle)])
            i = start + len(needle)
            continue
        args = split_top_level_commas(span[open_index + 1:close_index])
        changed = False
        next_args: list[str] = []
        for index, arg in enumerate(args):
            converter = converters.get(index)
            if converter is None:
                next_args.append(arg)
                continue
            converted = converter(arg.strip())
            next_args.append(converted)
            changed = changed or converted != arg
        out.append(span[i:open_index + 1])
        out.append(",".join(next_args) if changed else span[open_index + 1:close_index])
        out.append(")")
        i = close_index + 1


def convert_display_object_args(span: str) -> str:
    for method in ("Class_16.method_3885", "class_16.method_3885"):
        span = convert_named_call_args(span, method, {2: cast_arg})
    for method in (".method_3079", ".method_1104"):
        span = convert_named_call_args(span, method, {0: cast_arg})
    span = convert_named_call_args(span, "UiKit.text", {1: string_arg})
    return span


def convert_method_4623_args(span: str) -> str:
    out: list[str] = []
    i = 0
    needle = ".method_4623("
    while True:
        start = span.find(needle, i)
        if start < 0:
            out.append(span[i:])
            return "".join(out)
        open_index = start + len(".method_4623")
        close_index = find_matching_right(span, open_index)
        if close_index < 0:
            out.append(span[i:start + len(needle)])
            i = start + len(needle)
            continue
        args = split_top_level_commas(span[open_index + 1:close_index])
        out.append(span[i:start])
        if len(args) == 3:
            out.append(f".method_4623({string_arg(args[0])}, {string_arg(args[1])}, {string_arg(args[2])})")
        else:
            out.append(span[start:close_index + 1])
        i = close_index + 1


def convert_string_returns(span: str) -> str:
    out: list[str] = []
    i = 0
    visible_types = collect_visible_value_types(span)
    pattern = re.compile(r"\bfunction\s+[A-Za-z_]\w*\s*\([^)]*\)\s*:\s*String\s*\{")
    while True:
        match = pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return "".join(out)
        body_open = span.find("{", match.start())
        body_close = find_matching_right(span, body_open)
        if body_close < 0:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        body = span[body_open + 1:body_close]
        params_open = span.find("(", match.start())
        params_close = find_matching_right(span, params_open)
        types = {
            **visible_types,
            **function_value_types(span[params_open + 1:params_close], body),
        }

        def string_return(return_match: re.Match[str]) -> str:
            value = return_match.group(1)
            local = value.removeprefix("this.")
            if types.get(local) == "String":
                return return_match.group(0)
            return f"return {AS3_HELPER}.coerceString({value});"

        body = re.sub(
            r"\breturn\s+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?)\s*;",
            string_return,
            body,
        )
        out.append(span[i:body_open + 1])
        out.append(body)
        out.append("}")
        i = body_close + 1


def convert_string_typed_initializers(span: str) -> str:
    def initializer(match: re.Match[str]) -> str:
        value = match.group(2).strip()
        if value.startswith(('"', "'", "Std.string(", f"{STRING_ARG_CALL}(", "null")):
            return match.group(0)
        if re.fullmatch(rf"{re.escape(AS3_HELPER)}\.asType\(.*?,\s*String\)", value):
            return match.group(0)
        return f"var {match.group(1)}:String = {AS3_HELPER}.coerceString({value});"

    return re.sub(
        r"\bvar\s+([A-Za-z_]\w*)\s*:\s*String\s*=\s*([^;\n]+);",
        initializer,
        span,
    )


def convert_function_scoped_typed_assignments(span: str) -> str:
    out: list[str] = []
    i = 0
    visible_types = collect_visible_value_types(span)
    while True:
        match = re.search(r"\bfunction\s+[A-Za-z_]\w*\s*\(", span[i:])
        if not match:
            out.append(span[i:])
            return "".join(out)
        start = i + match.start()
        paren = span.find("(", start)
        close_paren = find_matching_right(span, paren)
        if close_paren < 0:
            out.append(span[i:start + len("function")])
            i = start + len("function")
            continue
        body_open = skip_space_right(span, close_paren + 1)
        while body_open < len(span) and span[body_open] != "{":
            body_open += 1
        if body_open >= len(span):
            out.append(span[i:close_paren + 1])
            i = close_paren + 1
            continue
        body_close = find_matching_right(span, body_open)
        if body_close < 0:
            out.append(span[i:body_open + 1])
            i = body_open + 1
            continue

        header = span[start:body_open + 1]
        body = span[body_open + 1:body_close]
        types = {**visible_types, **function_value_types(span[paren + 1:close_paren], body)}
        out.append(span[i:body_open + 1])
        out.append(apply_function_typed_assignments(body, types, visible_types))
        out.append("}")
        i = body_close + 1


def statically_boolean_expression(expr: str, types: dict[str, str],
                                  bool_methods: set[str]) -> bool:
    expr = strip_wrapping_parens(expr)
    if expr in {"true", "false"} or expr.startswith("!"):
        return True
    if re.fullmatch(rf"{re.escape(AS3_HELPER)}\.(?:toBool|isType|hasKey)\(.*\)", expr):
        return True
    simple = expr.removeprefix("this.")
    if re.fullmatch(r"[A-Za-z_]\w*", simple):
        return types.get(simple) == "Bool"
    call = re.fullmatch(r"(?:this\.)?([A-Za-z_]\w*)\s*\(.*\)", expr)
    if call and call.group(1) in bool_methods:
        return True
    for operator in ("||", "&&"):
        parts = split_top_level_operator(expr, operator)
        if len(parts) > 1:
            return all(statically_boolean_expression(part, types, bool_methods) for part in parts)
    for operator in ("==", "!=", "<=", ">=", "<", ">"):
        if len(split_top_level_operator(expr, operator)) > 1:
            return True
    return False


def remove_boolean_branch_helpers_from_body(body: str, types: dict[str, str],
                                            bool_methods: set[str]) -> str:
    marker_prefix = "__AS3_BOOL_BRANCH_NONCODE_"
    body, protected = protect_noncode(body, marker_prefix)
    needle = AS3_HELPER + ".toBool("
    replacements: list[tuple[int, int, str]] = []
    i = 0
    while True:
        start = body.find(needle, i)
        if start < 0:
            break
        open_index = start + len(AS3_HELPER + ".toBool")
        close_index = find_matching_right(body, open_index)
        if close_index < 0:
            break
        end = close_index + 1
        after = skip_space_right(body, end)
        branch_context = is_inside_condition(body, start, end) or (
            after < len(body) and body[after] == "?"
        )
        expr = body[open_index + 1:close_index]
        if branch_context and statically_boolean_expression(expr, types, bool_methods):
            replacements.append((start, end, f"({expr})"))
        i = end
    for start, end, replacement in reversed(replacements):
        body = body[:start] + replacement + body[end:]
    return restore_noncode(body, protected, marker_prefix)


def remove_redundant_boolean_branch_helpers(span: str) -> str:
    visible_types = collect_visible_value_types(span)
    bool_methods = {
        match.group(1)
        for match in re.finditer(
            r"\bfunction\s+([A-Za-z_]\w*)\s*\([^)]*\)\s*:\s*Bool\b",
            span,
        )
    }
    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+[A-Za-z_]\w*\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return "".join(out)
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        if close_paren < 0:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        body_open = skip_space_right(span, close_paren + 1)
        while body_open < len(span) and span[body_open] != "{":
            body_open += 1
        body_close = find_matching_right(span, body_open) if body_open < len(span) else -1
        if body_close < 0:
            out.append(span[i:close_paren + 1])
            i = close_paren + 1
            continue
        body = span[body_open + 1:body_close]
        types = {**visible_types, **function_value_types(span[paren + 1:close_paren], body)}
        out.append(span[i:body_open + 1])
        out.append(remove_boolean_branch_helpers_from_body(body, types, bool_methods))
        out.append("}")
        i = body_close + 1


def collect_visible_value_types(span: str) -> dict[str, str]:
    types: dict[str, str] = {}
    function_spans = nested_function_spans(span)
    for match in re.finditer(
        r"^[ \t]*(?:public|private|protected|internal)?\s*(?:static\s+)?var\s+([A-Za-z_]\w*)\s*:\s*(Int|UInt|Float|Bool|String)\b",
        span,
        re.MULTILINE,
    ):
        if any(start <= match.start() < end for start, end in function_spans):
            continue
        types[match.group(1)] = match.group(2)
    return types


def function_value_types(params: str, body: str) -> dict[str, str]:
    types: dict[str, str] = {}
    for param in split_top_level_commas(params):
        match = re.match(r"\s*([A-Za-z_]\w*)\s*:\s*(Int|UInt|Float|Bool|String)\b", param)
        if match:
            types[match.group(1)] = match.group(2)
    for match in re.finditer(r"\bvar\s+([A-Za-z_]\w*)\s*:\s*(Int|UInt|Float|Bool|String)\b", body):
        types[match.group(1)] = match.group(2)
    return types


def typed_ternary_arm_matches(expr: str, type_name: str, types: dict[str, str]) -> bool:
    expr = strip_wrapping_parens(expr)
    question = split_top_level_operator(expr, "?")
    if len(question) == 2:
        arms = split_top_level_operator(question[1], ":")
        return len(arms) == 2 and all(typed_ternary_arm_matches(arm, type_name, types) for arm in arms)
    source = expr.removeprefix("this.")
    if re.fullmatch(r"[A-Za-z_]\w*", source) and types.get(source) == type_name:
        return True
    helper = {
        "Int": "toInt",
        "UInt": "toUInt",
        "Float": "toFloat",
        "Bool": "toBool",
        "String": "coerceString",
    }[type_name]
    if expr.startswith(f"{AS3_HELPER}.{helper}("):
        return True
    if type_name in {"Int", "UInt", "Float"} and re.fullmatch(r"\d+(?:\.\d+)?", expr):
        return True
    if type_name == "Bool" and expr in {"true", "false"}:
        return True
    return type_name == "String" and (expr.startswith(('"', "'")) or expr == "null")


def typed_field_ternary_can_cast(expr: str, type_name: str, types: dict[str, str]) -> bool:
    expr = strip_wrapping_parens(expr)
    question = split_top_level_operator(expr, "?")
    if len(question) != 2:
        return False
    arms = split_top_level_operator(question[1], ":")
    return len(arms) == 2 and all(typed_ternary_arm_matches(arm, type_name, types) for arm in arms)


LITERAL_TERNARY_FLOATS = True


def literal_ternary(expr: str) -> bool:
    if not LITERAL_TERNARY_FLOATS:
        return False
    expr = strip_wrapping_parens(expr)
    question = split_top_level_operator(expr, "?")
    if len(question) != 2 or question[0].count("(") != question[0].count(")"):
        return False
    arms = split_top_level_operator(question[1], ":")
    return len(arms) == 2 and all(
        literal_ternary(arm) or re.fullmatch(r"-?\d+(?:\.\d+)?", strip_wrapping_parens(arm).strip())
        for arm in arms)


def uint_literal_ternary(expr: str) -> bool:
    if not LITERAL_TERNARY_FLOATS:
        return False
    expr = strip_wrapping_parens(expr)
    question = split_top_level_operator(expr, "?")
    if len(question) != 2 or question[0].count("(") != question[0].count(")"):
        return False
    arms = [strip_wrapping_parens(arm).strip() for arm in split_top_level_operator(question[1], ":")]
    literal = [bool(re.fullmatch(r"\d+", arm)) for arm in arms]
    return (len(arms) == 2 and any(literal)
            and all(lit or (arm.startswith(f"{AS3_HELPER}.toUInt(")
                            and find_matching_right(arm, len(f"{AS3_HELPER}.toUInt")) == len(arm) - 1)
                    for arm, lit in zip(arms, literal)))


def _cut_inside_block(expr: str) -> bool:
    return expr.count("{") != expr.count("}") or expr.count("(") != expr.count(")")


def apply_function_typed_assignments(body: str, types: dict[str, str],
                                     field_types: dict[str, str] | None = None) -> str:
    if not types:
        return body
    field_types = field_types or {}
    protected_body, protected = protect_noncode(body)

    def compound(match: re.Match[str]) -> str:
        name = match.group("name")
        type_name = types.get(name)
        if type_name is None or _cut_inside_block(match.group("expr")):
            return match.group(0)
        op = match.group("op")
        expr = match.group("expr").strip()
        if type_name == "String" and op == "+=":
            return f"{match.group('indent')}{name} += {string_arg(expr)};"
        if type_name not in {"Int", "UInt", "Float"}:
            return match.group(0)
        if type_name == "Int" and op in {"+=", "-=", "*=", "|=", "&=", "^="} and re.fullmatch(r"-?\d+", expr):
            return match.group(0)
        helper = {"Int": "toInt", "UInt": "toUInt", "Float": "toFloat"}[type_name]
        if op in {"|=", "&=", "^="}:
            right = f"{AS3_HELPER}.toUInt({expr})" if type_name == "UInt" and is_large_integer_literal(expr) else f"({expr})"
            value = f"{name} {op[0]} {right}"
        else:
            value = f"{AS3_HELPER}.numeric('{op[0]}', {name}, {expr})"
        return f"{match.group('indent')}{name} = {AS3_HELPER}.{helper}({value});"

    def assign(match: re.Match[str]) -> str:
        name = match.group("name")
        type_name = types.get(name)
        if type_name is None or _cut_inside_block(match.group("expr")):
            return match.group(0)
        expr = match.group("expr").strip()
        if (field_types.get(name) == type_name
                and typed_field_ternary_can_cast(expr, type_name, types)):
            if type_name == "UInt" and uint_literal_ternary(expr):
                return match.group(0)
            return f"{match.group('indent')}{name} = cast ({expr});"
        if expr.startswith((f"{AS3_HELPER}.to", "Std.string(", f"{STRING_ARG_CALL}(", "cast ", "new ")):
            return match.group(0)
        if type_name == "String":
            if expr.startswith(('"', "'", "null")):
                return match.group(0)
            source = expr.removeprefix("this.")
            if re.fullmatch(r"[A-Za-z_]\w*", source) and types.get(source) == "String":
                return match.group(0)
            string_call = re.fullmatch(
                r"(?P<receiver>(?:this\.)?[A-Za-z_]\w*)\."
                r"(?:toLowerCase|toUpperCase|substring|substr|slice|charAt|concat|replace|toString)\s*\(.*\)",
                expr,
            )
            if string_call:
                receiver = string_call.group("receiver").removeprefix("this.")
                if types.get(receiver) == "String":
                    return match.group(0)
            if re.fullmatch(rf"{re.escape(AS3_HELPER)}\.asType\(.*?,\s*String\)", expr):
                return match.group(0)
            return f"{match.group('indent')}{name} = {AS3_HELPER}.coerceString({expr});"
        if type_name == "Bool":
            if (
                expr in {"true", "false"}
                or expr.startswith("!")
                or re.search(r"(?:==|!=|<=|>=|<|>)", expr)
                or "&&" in expr
                or "||" in expr
            ):
                return match.group(0)
            return f"{match.group('indent')}{name} = {AS3_HELPER}.toBool({expr});"
        helper = {"Int": "toInt", "UInt": "toUInt", "Float": "toFloat"}[type_name]
        if re.fullmatch(r"-?\d+(?:\.\d+)?", expr) and type_name != "UInt":
            return match.group(0)
        if type_name == "Float" and literal_ternary(expr):
            return match.group(0)
        return f"{match.group('indent')}{name} = {AS3_HELPER}.{helper}({expr});"

    protected_body = re.sub(
        r"(?P<indent>^[ \t]*)(?P<name>[A-Za-z_]\w*)\s*(?P<op>\+=|-=|\*=|/=|%=|\|=|&=|\^=)\s*(?P<expr>[^;\n]+);",
        compound,
        protected_body,
        flags=re.MULTILINE,
    )
    protected_body = re.sub(
        r"(?P<indent>^[ \t]*)(?P<name>[A-Za-z_]\w*)\s*=(?!=)\s*(?P<expr>[^;\n]+);",
        assign,
        protected_body,
        flags=re.MULTILINE,
    )
    return restore_noncode(protected_body, protected)


TYPE_TESTED_DOWNCAST_RE = re.compile(
    r"(?P<head>=\s*)cast\(\((?P<cond>[^?;\n]*\b(?:Std\.isOfType|port\.runtime\.As3\.isType)\((?P<x>[\w.]+), (?P<c>[A-Za-z_][\w.]*)\)[^?;\n]*?) \? "
    r"(?P=x) : null\)\)(?P<tail>\s*;)")


def convert_type_tested_downcasts(span: str) -> str:
    def rewrite(m: re.Match[str]) -> str:
        cond = m.group("cond")
        if cond.count("(") != cond.count(")"):
            return m.group(0)
        return f"{m.group('head')}{cond} ? (cast {m.group('x')} : {m.group('c')}) : null{m.group('tail')}"

    if not TYPE_TESTED_DOWNCASTS:
        return span
    return convert_typed_null_conditionals(TYPE_TESTED_DOWNCAST_RE.sub(rewrite, span))


TYPED_NULL_CONDITIONAL_RE = re.compile(r"\bvar\s+(?P<name>_loc\d+_)\s*:\s*(?P<type>[A-Z][\w.]*)\s*=\s*cast\(\(")


def convert_typed_null_conditionals(span: str) -> str:
    out: list[str] = []
    i = 0
    for match in TYPED_NULL_CONDITIONAL_RE.finditer(span):
        if match.start() < i:
            continue
        outer = match.end() - 2
        close = find_matching_right(span, outer)
        if close < 0 or span[close - 1] != ")" or span[close + 1:close + 2] != ";":
            continue
        inner = span[outer + 2:close - 1]
        if find_matching_right(span, outer + 1) != close - 1:
            continue
        parts = split_top_level_conditional(inner)
        if not parts or parts[2].strip() != "null" or "\n" in inner:
            continue
        cond, value = parts[0].rstrip(), parts[1].strip()
        out.append(span[i:match.start()])
        out.append(f"var {match.group('name')}:{match.group('type')} = {cond} ? "
                   f"(cast {value} : {match.group('type')}) : null")
        i = close + 1
    out.append(span[i:])
    return "".join(out)


def split_top_level_conditional(text: str) -> tuple[str, str, str] | None:
    depth, question, colon = 0, -1, -1
    for pos, ch in enumerate(text):
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif depth == 0 and ch == "?":
            if question >= 0:
                return None
            question = pos
        elif depth == 0 and ch == ":" and question >= 0:
            if colon >= 0:
                return None
            colon = pos
        elif ch in "\"'":
            return None
    if question < 0 or colon < 0:
        return None
    return text[:question], text[question + 1:colon], text[colon + 1:]


TYPE_TESTED_DOWNCASTS = True


MINED_STRING_LOCALS = True
MINED_STRING_LOCAL_SKIPS: set[tuple[str, str, str]] = {
    ("CostumeType", "method_5047", "_loc14_"),
}


def convert_pseudo_string_local_assignments(span: str) -> str:
    out: list[str] = []
    i = 0
    pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    marker = re.compile(
        rf"\bvar\s+([A-Za-z_]\w*)\s*:\s*Dynamic\s*=\s*{re.escape(AS3_HELPER)}\.asType\(null,\s*String\)\s*;"
    )
    string_locals = ((load_element_types() or {}).get("string_locals") or {}) if MINED_STRING_LOCALS else {}
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    if class_name and class_name.startswith("Class_"):
        class_name = "class_" + class_name[6:]
    while True:
        match = pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return "".join(out)
        body_open = span.find("{", match.end())
        body_close = find_matching_right(span, body_open) if body_open >= 0 else -1
        if body_close < 0:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        body = span[body_open + 1:body_close]
        names = {found.group(1) for found in marker.finditer(body)}
        proved = {f"_loc{register}_" for register in string_locals.get(f"{class_name}/{match.group(1)}", ())}
        proved -= {local for cls, method, local in MINED_STRING_LOCAL_SKIPS if (cls, method) == (class_name, match.group(1))}
        if proved & names:
            body = marker.sub(lambda found: f"var {found.group(1)}:String = null;"
                              if found.group(1) in proved else found.group(0), body)
        protected, strings = protect_noncode(body)
        for name in names:
            assign = re.compile(
                rf"(?P<indent>^[ \t]*){re.escape(name)}\s*=(?!=)\s*(?P<expr>[^;\n]+);",
                re.MULTILINE,
            )
            protected = assign.sub(
                lambda found: found.group(0)
                if found.group("expr").strip().startswith(f"{AS3_HELPER}.coerceString(")
                else f"{found.group('indent')}{name} = {AS3_HELPER}.coerceString({found.group('expr').strip()});",
                protected,
            )
        out.append(span[i:body_open + 1])
        out.append(restore_noncode(protected, strings))
        out.append("}")
        i = body_close + 1


def is_large_integer_literal(expr: str) -> bool:
    return bool(re.fullmatch(r"\d+", expr.strip()) and int(expr.strip()) > 2147483647)


def convert_logical_boolean_assignments(span: str) -> str:
    def one(match: re.Match[str]) -> str:
        prefix = match.group("prefix")
        expr = match.group("expr").strip()
        if "&&" not in expr or "?" in expr:
            return match.group(0)
        parts = re.split(r"(\s*&&\s*)", expr)
        changed = False
        converted: list[str] = []
        for index, part in enumerate(parts):
            if (index % 2 == 1 or part.count("(") != part.count(")")
                    or not _single_comparison_operands(part.replace("&&", ""))):
                converted.append(part)
                continue
            next_part = truthy_value_for_boolean_logic(part)
            changed = changed or next_part != part
            converted.append(next_part)
        if not changed:
            return match.group(0)
        return f"{prefix}{''.join(converted)};"

    return re.sub(r"(?<![!<>=])(?P<prefix>=\s*)(?P<expr>[^;\n]*&&[^;\n]*);", one, span)


def _single_comparison_operands(text: str) -> bool:
    depth = 0
    for i, ch in enumerate(text):
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth < 0:
                return False
        elif depth == 0 and text[i:i + 2] in ("||", "&&"):
            return False
    return True


def convert_comparison_chain_booleans(span: str) -> str:
    operand = r"(?:[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\([^;\n]*?\)|[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*|-?\d+(?:\.\d+)?)"
    comparison = rf"{operand}\s*(?:[<>]=?|==|!=)\s*{operand}"

    def grouped(build):
        return lambda m: build(m) if _single_comparison_operands(m.group(0)) else m.group(0)

    span = re.sub(
        rf"({comparison})\s*!=\s*({comparison})",
        grouped(lambda m: f"({m.group(1).strip()}) != ({m.group(2).strip()})"),
        span,
    )
    span = re.sub(
        rf"({comparison})\s*==\s*({comparison})",
        grouped(lambda m: f"({m.group(1).strip()}) == ({m.group(2).strip()})"),
        span,
    )
    relational = rf"{operand}\s*(?:[<>]=?)\s*{operand}"
    span = re.sub(
        rf"({operand})\s*(==|!=)\s*({relational})",
        grouped(lambda m: f"{m.group(1).strip()} {m.group(2)} ({m.group(3).strip()})"),
        span,
    )
    span = re.sub(
        rf"({relational})\s*(==|!=)\s*({operand})",
        grouped(lambda m: f"({m.group(1).strip()}) {m.group(2)} {m.group(3).strip()}"),
        span,
    )
    span = re.sub(r"\(\s*(if|while)\s*\(", r"\1((", span)
    span = fix_ternary_comparison_grouping(span)
    span = fix_unmatched_logical_and_ternary_grouping(span)
    span = fix_logical_and_ternary_result_comparison(span)
    span = parenthesize_simple_chained_ternaries(span)
    return span


def parenthesize_simple_chained_ternaries(span: str) -> str:
    value = r"(?:[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*|port\.runtime\.As3\.index\([^;\n]+?\))"
    literal = r"(?:-?\d+|\"[^\"\n]*\"|'[^'\n]*')"
    pattern = re.compile(
        rf"(?P<left>{value})\s*(?P<op>==|!=)\s*(?P<a>{literal})\s*\?\s*(?P<ta>{literal})\s*:\s*"
        rf"(?P=left)\s*(?P=op)\s*(?P<b>{literal})\s*\?\s*(?P<tb>{literal})\s*:\s*"
        rf"(?P=left)\s*(?P=op)\s*(?P<c>{literal})\s*\?\s*(?P<tc>{literal})\s*:\s*(?P<tf>{literal})"
    )

    def repl(match: re.Match[str]) -> str:
        left = match.group("left")
        op = match.group("op")
        return (
            f"{left} {op} {match.group('a')} ? {match.group('ta')} : "
            f"({left} {op} {match.group('b')} ? {match.group('tb')} : "
            f"({left} {op} {match.group('c')} ? {match.group('tc')} : {match.group('tf')}))"
        )

    return pattern.sub(repl, span)


def _parens_balanced(text: str) -> bool:
    return text.count("(") <= text.count(")")


def _balanced_top_level_ternary(text: str) -> bool:
    if text.count("(") != text.count(")"):
        return False
    depth = 0
    for ch in text:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        elif ch == "?" and depth == 0:
            return True
    return False


def fix_ternary_comparison_grouping(span: str) -> str:
    fixed: list[str] = []
    for line in span.splitlines(keepends=True):
        if "?" in line and ":" in line:
            line = re.sub(r"(\?\s*[^:\n]+?\))\)\s*([!=]=)\s*([^:\n]+?)\s*:", r"\1 \2 \3 :", line)
            line = re.sub(
                r"((?<![=!<>+\-*/%|&^])=(?!=)\s*)\((?![^?\n]*\|\|[^?\n]*\)\s*&&)([^?\n]+?\?)",
                lambda m: m.group(0) if find_matching_right(line, m.end(1)) >= 0 else m.group(1) + m.group(2),
                line,
            )
            line = re.sub(
                r"((?<![=!<>+\-*/%|&^])=(?!=)\s*)"
                r"((?:[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*|-?\d+(?:\.\d+)?)\s*[<>]=?\s*"
                r"(?:[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*|-?\d+(?:\.\d+)?)\)\s*[!=]=\s*[^?\n]+?\?)",
                r"\1(\2",
                line,
            )
            line = re.sub(
                r"((?<![=!<>+\-*/%|&^])=(?!=)\s*)([^;\n]*\?[^;\n]*:[^;\n]*\))\s*(==|!=|<=|>=|<|>)(?!\s*0\b)",
                lambda m: f"{m.group(1)}({m.group(2)}) {m.group(3)}"
                if _parens_balanced(m.group(2)) and not (
                    _balanced_top_level_ternary(m.group(2))
                    and re.search(r"\?[^:]*(?:==|!=)[^:]*:", m.group(2))) else m.group(0),
                line,
            )
            line = re.sub(r"((?<![=!<>+\-*/%|&^])=(?!=)\s*)([^;\n]*\?[^;\n]*:[^;\n]*\))\s*\+",
                          lambda m: f"{m.group(1)}({m.group(2)}) +"
                          if _parens_balanced(m.group(2)) and not _balanced_top_level_ternary(m.group(2))
                          else m.group(0),
                          line)
            def stray_third(mm: re.Match, line: str = line) -> bool:
                start = line.rfind(";", 0, mm.start()) + 1
                opener = find_matching_left(line[start:mm.start() + 3], mm.start() + 2 - start)
                return opener <= 0 or not re.match(r"[\w\]]", line[start + opener - 1])

            line = re.sub(r"\)\)\)\s*(==|!=|<=|>=|<|>)",
                          lambda mm: f")) {mm.group(1)}" if stray_third(mm) else mm.group(0), line)
        fixed.append(line)
    return "".join(fixed)


def fix_unmatched_logical_and_ternary_grouping(span: str) -> str:
    fixed: list[str] = []
    for line in span.splitlines(keepends=True):
        if "&&" not in line or "?" not in line:
            fixed.append(line)
            continue
        question = line.find("?")
        search_end = question
        while True:
            match = list(re.finditer(r"&&\s*\(", line[:search_end]))
            if not match:
                break
            paren = match[-1].end() - 1
            close = find_matching_right(line, paren)
            if close >= 0:
                break
            line = line[:paren] + line[paren + 1:]
            question -= 1
            search_end = paren
        fixed.append(line)
    return "".join(fixed)


def fix_logical_and_ternary_result_comparison(span: str) -> str:
    fixed: list[str] = []
    for line in span.splitlines(keepends=True):
        if ("&&" not in line or "?" not in line or not re.search(r"\)\s*[!=]=", line)
                or paren_balance_outside_strings(line) >= 0):
            fixed.append(line)
            continue
        question = line.find("?")
        question_depth = paren_depth_at(line, question)
        and_match = list(re.finditer(r"&&\s*", line[:question]))
        if not and_match:
            fixed.append(line)
            continue
        start = and_match[-1].end()
        if start < len(line) and line[start] == "(":
            fixed.append(line)
            continue
        colon = find_token_at_depth(line, ":", question + 1, question_depth)
        if colon < 0:
            fixed.append(line)
            continue
        close = find_token_at_depth(line, ")", colon + 1, question_depth)
        if close < 0 or not re.match(r"\s*[!=]=", line[close + 1:]):
            fixed.append(line)
            continue
        fixed.append(line[:start] + "(" + line[start:])
    return "".join(fixed)


def paren_depth_at(text: str, position: int) -> int:
    depth = 0
    in_string: str | None = None
    i = 0
    while i < min(position, len(text)):
        ch = text[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == in_string:
                in_string = None
            i += 1
            continue
        if ch in ("'", '"'):
            in_string = ch
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth = max(0, depth - 1)
        i += 1
    return depth


def find_token_at_depth(text: str, token: str, start: int, target_depth: int) -> int:
    depth = paren_depth_at(text, start)
    in_string: str | None = None
    i = start
    while i < len(text):
        ch = text[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == in_string:
                in_string = None
            i += 1
            continue
        if ch in ("'", '"'):
            in_string = ch
            i += 1
            continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            if token == ch and depth == target_depth:
                return i
            depth = max(0, depth - 1)
            i += 1
            continue
        elif depth == target_depth and text.startswith(token, i):
            return i
        i += 1
    return -1


def convert_flash_abstract_compatibility(span: str) -> str:
    literal = r"(?:\"[A-Za-z_]+\"|__AS3_NONCODE_\d+__)"
    span = re.sub(
        r"(:\s*UInt\s*=\s*)(\d{10,})",
        lambda m: f"{m.group(1)}cast {m.group(2)}",
        span,
    )
    span = re.sub(
        rf"\bnew\s+Bitmap\s*\(([^;\n]*?),\s*({literal})\s*,",
        lambda m: f"new Bitmap({m.group(1)}, cast {m.group(2)},",
        span,
    )
    span = re.sub(
        rf"\.align\s*=\s*({literal})",
        lambda m: f".align = cast {m.group(1)}",
        span,
    )
    span = re.sub(
        r"\.blendMode\s*=\s*([^;\n]+);",
        lambda m: f".blendMode = cast {m.group(1).strip()};",
        span,
    )
    span = re.sub(
        rf"([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\.blendMode\s*(!=|==)\s*({literal})",
        lambda m: f"Std.string({m.group(1)}.blendMode) {m.group(2)} {m.group(3)}",
        span,
    )
    span = re.sub(
        r"\.filters\s*=\s*([^;\n]+);",
        lambda m: f".filters = cast {m.group(1).strip()};",
        span,
    )
    span = re.sub(
        r"\b(new\s+(?:Class_84|class_84)\s*\([^;\n]*?,\s*)(Context3DTextureFormat\.[A-Z_]+)(\s*\))",
        lambda m: f"{m.group(1)}(cast {m.group(2)} : String){m.group(3)}",
        span,
    )
    span = re.sub(
        r"(\.Replace\s*\([^;\n]*?,\s*)(Context3DTextureFormat\.[A-Z_]+)(\s*\))",
        lambda m: f"{m.group(1)}(cast {m.group(2)} : String){m.group(3)}",
        span,
    )
    span = re.sub(
        r"(createRectangleTexture\s*\([^;\n]*?,\s*)([A-Za-z_]\w*)(\s*,\s*false\s*\))",
        lambda m: f"{m.group(1)}cast {m.group(2)}{m.group(3)}",
        span,
    )
    span = re.sub(
        r"\bnew\s+KeyboardEvent\s*\(((?:[^(),;\n]+,){5}\s*)([^,);\n]+)",
        lambda m: f"new KeyboardEvent({m.group(1)}cast {m.group(2).strip()}",
        span,
    )
    span = re.sub(
        r"([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\.nativeWindow\b",
        lambda m: f"{AS3_HELPER}.nativeWindow({m.group(1)})",
        span,
    )
    span = re.sub(
        r"(==|!=)\s*(Context3DProfile\.[A-Z_]+)",
        lambda m: f"{m.group(1)} (cast {m.group(2)} : String)",
        span,
    )
    span = re.sub(
        r"(requestContext3D\s*\([^,\n]+,\s*)([^);\n]+)(\))",
        lambda m: f"{m.group(1)}cast {m.group(2).strip()}{m.group(3)}",
        span,
    )
    span = re.sub(
        r"=\s*(Context3DProfile\.[A-Z_]+)\s*;",
        lambda m: f"= (cast {m.group(1)} : String);",
        span,
    )
    return span


def truthy_value_for_boolean_logic(part: str) -> str:
    stripped = part.strip()
    if not stripped or stripped.startswith(AS3_HELPER + ".toBool("):
        return part
    if re.search(r"(?:==|!=|<=|>=|<|>)", stripped):
        return part
    if stripped in {"true", "false"}:
        return part
    if (
        stripped.startswith(AS3_HELPER + ".index(")
        or stripped.startswith(AS3_HELPER + ".logicalOr(")
        or re.search(r"(?<![&|])(?:&|\|)(?![&|])", stripped)
        or re.fullmatch(r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*(?:\([^()]*\))?", stripped)
    ):
        prefix = part[: len(part) - len(part.lstrip())]
        suffix = part[len(part.rstrip()):]
        return f"{prefix}{AS3_HELPER}.toBool({stripped}){suffix}"
    return part


def is_inside_condition(span: str, start: int, end: int) -> bool:
    i = start
    while True:
        open_index = span.rfind("(", 0, i)
        if open_index < 0:
            return False
        close_index = find_matching_right(span, open_index)
        if close_index >= end:
            word_end = skip_space_left(span, open_index - 1) + 1
            word_start = word_end - 1
            while word_start >= 0 and is_identifier_char(span[word_start]):
                word_start -= 1
            return span[word_start + 1:word_end] in {"if", "while"}
        i = open_index


def convert_ternary_truthiness(span: str) -> str:
    marker_prefix = "__AS3_TERNARY_NONCODE_"
    protected_span, protected = protect_noncode(span, marker_prefix)
    span = protected_span
    replacements: list[tuple[int, int, str]] = []
    for question in find_ternary_questions(span):
        start = find_ternary_condition_start(span, question)
        if start < 0:
            continue
        condition = span[start:question].strip()
        if not condition or (is_boolean_value_expression(condition) and "&&" not in condition and "||" not in condition):
            continue
        if re.search(r"[;{}]", condition):
            continue
        converted = convert_truthy_expression(condition)
        if converted != condition:
            prefix = span[start:question][: len(span[start:question]) - len(span[start:question].lstrip())]
            suffix = span[start:question][len(span[start:question].rstrip()):]
            replacements.append((start, question, f"{prefix}{converted}{suffix}"))
    for start, end, replacement in reversed(replacements):
        span = span[:start] + replacement + span[end:]
    span = re.sub(
        rf"((?:==|!=)\s*){re.escape(AS3_HELPER)}\.toBool\((['\"][^'\"]*['\"])\)",
        r"\1\2",
        span,
    )
    span = re.sub(
        rf"=\(=\s*{re.escape(AS3_HELPER)}\.toBool\((['\"][^'\"]*['\"])\)\s*\?",
        r"== \1 ?",
        span,
    )
    span = convert_ternary_branch_logical_or(span)
    span = re.sub(
        rf"=\(=\s*{re.escape(AS3_HELPER)}\.toBool\((['\"][^'\"]*['\"])\)\s*\?",
        r"== \1 ?",
        span,
    )
    return restore_noncode(span, protected, marker_prefix)


def find_ternary_questions(span: str) -> list[int]:
    questions: list[int] = []
    depth = 0
    i = 0
    while i < len(span):
        ch = span[i]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth = max(0, depth - 1)
        elif ch == "?":
            questions.append(i)
        i += 1
    return questions


def find_ternary_condition_start(span: str, question: int) -> int:
    depth = 0
    i = question - 1
    while i >= 0:
        ch = span[i]
        if ch in ")]}":
            depth += 1
        elif ch in "([{":
            if depth == 0:
                return i + 1
            depth -= 1
        elif depth == 0 and ch == "=" and (
            (i > 0 and span[i - 1] in "!<>=") or (i + 1 < len(span) and span[i + 1] == "=")
        ):
            i -= 1
            continue
        elif depth == 0 and ch in "=,;:\n":
            return i + 1
        elif depth == 0 and span[max(0, i - 5):i + 1] == "return":
            before = i - 6
            after = i + 1
            if (before < 0 or not is_identifier_char(span[before])) and (after >= len(span) or not is_identifier_char(span[after])):
                return after
        i -= 1
    return 0


def convert_ternary_branch_logical_or(span: str) -> str:
    def repl(match: re.Match[str]) -> str:
        parts = split_top_level_operator(match.group("expr").strip(), "||")
        if len(parts) < 2:
            return match.group(0)
        return f"? {logical_or_expression(parts)} :"

    return re.sub(r"\?\s*(?P<expr>[^?:;\n]*\|\|[^:;\n]*)\s*:", repl, span)


def convert_truthy_conditions(span: str) -> str:
    keywords = ("if", "while")
    i = 0
    while i < len(span):
        next_match: re.Match[str] | None = None
        for keyword in keywords:
            match = re.search(rf"\b{keyword}\s*\(", span[i:])
            if match and (next_match is None or match.start() < next_match.start()):
                next_match = match
        if next_match is None:
            return span
        start = i + next_match.start()
        paren = span.find("(", start)
        close = find_matching_right(span, paren)
        if close < 0:
            i = paren + 1
            continue
        condition = span[paren + 1:close].strip()
        converted = convert_truthy_expression(condition)
        span = span[:paren + 1] + converted + span[close:]
        i = paren + 1 + len(converted)
    return span


def convert_truthy_expression(condition: str) -> str:
    condition = convert_logical_or_calls_in_boolean(condition)
    condition = re.sub(
        r"!\s*\(([^()\n]*(?<![&|])(?:&|\|)(?![&|])[^()\n]*)\)",
        rf"!{AS3_HELPER}.toBool(\1)",
        condition,
    )
    condition = re.sub(
        r"!\s*\(([^()\n]*(?:[%+\-*/]|\|\||&&)[^()\n]*)\)",
        rf"!{AS3_HELPER}.toBool(\1)",
        condition,
    )
    condition = re.sub(r"!\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\b(?!\s*[\w.(])", rf"!{AS3_HELPER}.toBool(\1)", condition)
    parts = re.split(r"(\s*(?:&&|\|\|)\s*)", condition)
    if len(parts) > 1:
        return "".join(convert_truthy_part(part) if index % 2 == 0 else part for index, part in enumerate(parts))
    return convert_truthy_part(condition)


def convert_logical_or_calls_in_boolean(condition: str) -> str:
    needle = AS3_HELPER + ".logicalOr("
    out: list[str] = []
    i = 0
    while i < len(condition):
        start = condition.find(needle, i)
        if start < 0:
            out.append(condition[i:])
            return "".join(out)
        open_index = start + len(AS3_HELPER + ".logicalOr")
        close_index = find_matching_right(condition, open_index)
        if close_index < 0:
            out.append(condition[i:start + len(needle)])
            i = start + len(needle)
            continue
        previous = skip_space_left(condition, start - 1)
        if previous >= 0 and condition[previous] in "=!<>+-*/%":
            out.append(condition[i:close_index + 1])
            i = close_index + 1
            continue
        before_previous = skip_space_left(condition, previous - 1) if previous >= 0 else -1
        if previous >= 0 and condition[previous] == "(" and before_previous >= 0 and condition[before_previous] in "=!<>+-*/%":
            out.append(condition[i:close_index + 1])
            i = close_index + 1
            continue
        after = skip_space_right(condition, close_index + 1)
        if condition.startswith(("==", "!="), after) or _value_argument_position(condition, start):
            out.append(condition[i:close_index + 1])
            i = close_index + 1
            continue
        args = split_top_level_commas(condition[open_index + 1:close_index])
        if len(args) != 2:
            out.append(condition[i:close_index + 1])
            i = close_index + 1
            continue
        left = boolean_condition_value(args[0])
        right = boolean_condition_value(args[1])
        out.append(condition[i:start])
        out.append(f"({left} || {right})")
        i = close_index + 1
    return "".join(out)


def _value_argument_position(condition: str, start: int) -> bool:
    depth = 0
    i = start - 1
    while i >= 0:
        ch = condition[i]
        if ch in ")]}":
            depth += 1
        elif ch in "([{":
            if depth == 0:
                if ch != "(":
                    return True
                before = skip_space_left(condition, i - 1)
                if before < 0 or not (is_identifier_char(condition[before]) or condition[before] in ")]"):
                    return False
                word = re.search(r"[\w.]*$", condition[:before + 1]).group(0)
                return not word.endswith(".toBool") and word not in {"if", "while", "return"}
            depth -= 1
        i -= 1
    return False


def boolean_condition_value(expr: str) -> str:
    expr = convert_logical_or_calls_in_boolean(expr.strip())
    if (
        not expr
        or expr.startswith(AS3_HELPER + ".toBool(")
        or expr.startswith("!")
        or expr in {"true", "false"}
        or "&&" in expr
        or "||" in expr
        or re.search(r"(?:==|!=|<=|>=|<|>)", expr)
    ):
        return expr
    return f"{AS3_HELPER}.toBool({expr})"


def convert_logical_operand_truthiness(span: str) -> str:
    pattern = re.compile(rf"(?<![\w.])([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*&&")

    def repl(match: re.Match[str]) -> str:
        token = match.group(1)
        if token in {"true", "false"}:
            return match.group(0)
        if token.startswith(AS3_HELPER + ".toBool"):
            return match.group(0)
        previous = skip_space_left(span, match.start(1) - 1)
        if previous >= 0 and span[previous] in "=!<>+-*/%":
            return match.group(0)
        return f"{AS3_HELPER}.toBool({token}) &&"

    return pattern.sub(repl, span)


def convert_truthy_part(part: str) -> str:
    stripped = part.strip()
    if not stripped or stripped.startswith(AS3_HELPER + ".toBool(") or stripped.startswith("!"):
        return part
    if re.search(r"(?:==|!=|<=|>=|<|>)", stripped):
        return part
    if re.search(r"\s[+\-*/%]\s", stripped):
        return part
    if stripped in {"true", "false"} or stripped.startswith(AS3_HELPER + ".hasKey("):
        return part
    if (
        stripped.startswith(AS3_HELPER + ".index(")
        or stripped.startswith(AS3_HELPER + ".logicalOr(")
        or re.search(r"(?<![&|])(?:&|\|)(?![&|])", stripped)
        or re.fullmatch(r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*(?:\([^()]*\))?", stripped)
    ):
        prefix = part[: len(part) - len(part.lstrip())]
        suffix = part[len(part.rstrip()):]
        return f"{prefix}{AS3_HELPER}.toBool({stripped}){suffix}"
    return part


def convert_xml_literals(span: str) -> str:
    def one(match: re.Match[str]) -> str:
        attrs: list[str] = []
        for attr in XML_ATTR_RE.finditer(match.group("attrs")):
            name = attr.group(1)
            value = attr.group(2) if attr.group(2) is not None else attr.group(3)
            attrs.append(f'"{name}", {value.strip()}')
        fields = ", ".join(attrs)
        return f'{AS3_HELPER}.xmlNode("{match.group("tag")}", ([{fields}] : Array<Dynamic>))'

    return XML_LITERAL_RE.sub(one, span)


XML_MEMBERS = {
    "addNamespace", "appendChild", "attribute", "attributes", "child", "childIndex", "children", "comments",
    "contains", "copy", "descendants", "elements", "hasComplexContent", "hasOwnProperty", "hasSimpleContent",
    "inScopeNamespaces", "insertChildAfter", "insertChildBefore", "length", "localName", "name", "namespace",
    "namespaceDeclarations", "nodeKind", "normalize", "parent", "prependChild", "processingInstructions",
    "propertyIsEnumerable", "removeNamespace", "replace", "setChildren", "setLocalName", "setName", "setNamespace",
    "text", "toJSON", "toString", "toXMLString", "valueOf",
}
XML_TYPED_DECL_RE = re.compile(
    r"(?:\bvar\s+(?P<var>[A-Za-z_]\w*)\s*:\s*XML\b(?!List)"
    r"|[(,]\s*(?P<param>[A-Za-z_]\w*)\s*:\s*XML\b(?!List)"
    r"|\bfor\s*\(\s*(?P<loop>[A-Za-z_]\w*)\s+in\s+\(.*:\s*Iterator<XML>\)\))")


def convert_e4x_typed_children(span: str) -> str:
    edits: list[tuple[int, int, str]] = []
    for decl in XML_TYPED_DECL_RE.finditer(span):
        name = decl.group("var") or decl.group("param") or decl.group("loop")
        if decl.group("param"):
            body = span.find("{", decl.end())
        else:
            body = decl.end()
        depth, start = 0, decl.start()
        while start > 0:
            start -= 1
            if span[start] == "}":
                depth += 1
            elif span[start] == "{":
                if depth == 0:
                    break
                depth -= 1
        end = find_matching_right(span, start) if span[start] == "{" else len(span)
        if decl.group("param") and body >= 0:
            end = find_matching_right(span, body)
        if body < 0 or end < 0:
            continue
        child = re.compile(rf"(?<![\w.]){re.escape(name)}\.(?P<child>[A-Za-z_]\w*)\b(?!\s*\()(?!\s*=[^=])")
        for use in child.finditer(span, body, end):
            if use.group("child") not in XML_MEMBERS:
                edits.append((use.start(), use.end(), f'{AS3_HELPER}.xmlChild({name}, "{use.group("child")}")'))
    for start, end, text in sorted(set(edits), reverse=True):
        span = span[:start] + text + span[end:]
    return span


def force_mixed_array_literals(span: str) -> str:
    placeholder = re.compile(r"\s*__AS3_NONCODE_\d+__\s*$")
    edits: list[tuple[int, int]] = []
    for at in [m.start() for m in re.finditer(r"\[", span)]:
        before = span[:at].rstrip()
        if re.search(r"[\w)\]]\s*$", span[:at]):
            continue
        close = find_matching_right(span, at)
        if close < 0:
            continue
        items = [x for x in split_top_level_commas(span[at + 1:close]) if x.strip()]
        if len(items) > 1 and all(x.strip().startswith("{") for x in items):
            edits.append((at, close))
            continue
        if not before.endswith(("(", ",", "[")):
            continue
        strings = [x for x in items if placeholder.match(x)]
        others = [x for x in items if not placeholder.match(x) and x.strip() != "null"
                  and re.fullmatch(r"-?\d+(?:\.\d+)?|[A-Za-z_][\w.]*", x.strip())]
        reads = [x for x in items if re.fullmatch(r"[A-Za-z_]\w*(?:\[[^\[\]]+\])+", x.strip())]
        typed = [x for x in items if x not in reads and x.strip() != "null"
                 and re.fullmatch(r"[A-Za-z_][\w.]*", x.strip())]
        if (strings and others) or (reads and typed):
            edits.append((at, close))
    edits = [e for e in edits if not any(o != e and e[0] < o[0] and o[1] < e[1] for o in edits)]
    for at, close in sorted(edits, reverse=True):
        span = f"{span[:at]}({span[at:close + 1]} : Array<Dynamic>){span[close + 1:]}"
    return span


def convert_layer_idioms(span: str) -> str:
    helper = AS3_HELPER
    i = 0
    while True:
        found = re.compile(r"\bMath\.(?P<which>max|min)\.apply\s*\(\s*null\s*,").search(span, i)
        if not found:
            break
        close = find_matching_right(span, span.find("(", found.start()))
        if close < 0:
            i = found.end()
            continue
        values = span[found.end():close].strip()
        replacement = f"{helper}.mathApply({'true' if found.group('which') == 'max' else 'false'}, {values})"
        span = span[:found.start()] + replacement + span[close + 1:]
        i = found.start() + len(replacement)
    span = re.sub(r"\bnew\s+Array\s*(?:<Dynamic>)?\s*\((?!\s*\))", f"{helper}.newArray(", span)
    span = re.sub(r"\b(describeType\s*\([^()\n]*\))\.factory\.(variable|accessor|method|constant)\b",
                  lambda m: f'{helper}.xmlChild({helper}.xmlChild({m.group(1)}, "factory"), "{m.group(2)}")', span)
    return span


def convert_wide_bitwise_literals(span: str) -> str:
    def repl(match: re.Match[str]) -> str:
        value = int(match.group("num"))
        if not 0x80000000 <= value <= 0xFFFFFFFF:
            return match.group(0)
        return match.group(0).replace(match.group("num"), f"0x{value:08X}")

    span = re.sub(r"(?<![\w.])(?P<num>\d{10})(?![\w.])(?=\s*(?:\^|\||&(?!&)|<<|>>))", repl, span)
    span = re.sub(r"(?:\^|(?<!\|)\|(?!\|)|(?<!&)&(?!&)|<<|>>>?)\s*(?P<num>\d{10})(?![\w.])", repl, span)
    uint_params: dict[str, set[int]] = {}
    for decl in re.finditer(r"\bfunction\s+([A-Za-z_]\w*)\s*\(([^()]*)\)", span):
        positions = {i for i, p in enumerate(split_top_level_commas(decl.group(2))) if re.search(r":\s*UInt\b", p)}
        if positions:
            uint_params[decl.group(1)] = positions
    for name, positions in uint_params.items():
        for call in reversed(list(re.finditer(rf"(?<![\w.]){re.escape(name)}\s*\(", span))):
            if span[max(0, call.start() - 9):call.start()].rstrip().endswith("function"):
                continue
            close = find_matching_right(span, call.end() - 1)
            if close < 0:
                continue
            args = split_top_level_commas(span[call.end():close])
            changed = False
            for i in positions:
                if i < len(args) and re.fullmatch(r"\s*\d{10}\s*", args[i]):
                    new = re.sub(r"(?P<num>\d{10})", repl, args[i])
                    changed |= new != args[i]
                    args[i] = new
            if changed:
                span = span[:call.end()] + ",".join(args) + span[close:]
    return span


def convert_mathmax_compound_position(span: str) -> str:
    return re.sub(
        r"(\.position\s*[+-]=\s*)(?P<rhs>[^;\n]*" + re.escape(AS3_HELPER) + r"\.math(?:Max|Min)2?\([^;\n]*);",
        lambda m: f"{m.group(1)}{AS3_HELPER}.toInt({m.group('rhs').strip()});",
        span,
    )


def convert_object_literal_index(span: str) -> str:
    i = 0
    while True:
        at = span.find("}[", i)
        if at < 0:
            return span
        i = at + 2
        depth, left = 0, at
        while left >= 0:
            depth += {"}": 1, "{": -1}.get(span[left], 0)
            if depth == 0:
                break
            left -= 1
        if left < 0:
            continue
        before = span[:left].rstrip()
        if not (before.endswith(("(", "?", ":", "=", ",")) or re.search(r"\breturn$", before)):
            continue
        close = find_matching_right(span, at + 1)
        if close < 0:
            continue
        literal, key = span[left:at + 1], span[at + 2:close]
        span = f"{span[:left]}{AS3_HELPER}.index({literal}, {key.strip()}){span[close + 1:]}"
        i = left


def convert_e4x_attributes(span: str) -> str:
    target = r"([A-Za-z_]\w*(?:\[[^\]\n]+?\]|\([^()\n]*\))?)"
    span = re.sub(
        target + r"\s*\.\s*@\s*\[\s*([^\]\n]+?)\s*\]\s*=(?!=)\s*([^;\n]+)",
        lambda m: f"{AS3_HELPER}.setXmlAttribute({m.group(1)}, {m.group(2).strip()}, {m.group(3).strip()})",
        span,
    )
    span = re.sub(
        target + r"\s*\.\s*@\s*([A-Za-z_]\w*)\s*=(?!=)\s*([^;\n]+)",
        lambda m: f'{AS3_HELPER}.setXmlAttribute({m.group(1)}, "{m.group(2)}", {m.group(3).strip()})',
        span,
    )
    span = re.sub(
        target + r"\s*\.\s*@\s*\[\s*([^\]\n]+?)\s*\]",
        lambda m: f"{AS3_HELPER}.xmlAttribute({m.group(1)}, {m.group(2).strip()})",
        span,
    )
    span = re.sub(
        target + r"\s*\.\s*@\s*([A-Za-z_]\w*)",
        lambda m: f'{AS3_HELPER}.xmlAttribute({m.group(1)}, "{m.group(2)}")',
        span,
    )
    span = re.sub(
        r"(?<![\w.])([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\.\.(?!\.)([A-Za-z_]\w*)\b(?!\s*\()",
        lambda m: f'{AS3_HELPER}.xmlDescendants({m.group(1)}, "{m.group(2)}")',
        span,
    )
    span = re.sub(
        r"\b([A-Za-z_]\w*)\.(variable|accessor)\b",
        lambda m: f'{AS3_HELPER}.xmlChild({m.group(1)}, "{m.group(2)}")',
        span,
    )
    span = convert_e4x_typed_children(span)
    helper = re.escape(AS3_HELPER)
    span = re.sub(
        rf"({helper}\.xmlChild\([^()\n]*\))\s*\+\s*({helper}\.xmlChild\([^()\n]*\))",
        lambda m: f"{AS3_HELPER}.xmlConcat({m.group(1)}, {m.group(2)})",
        span,
    )
    return span


def convert_typeof_operators(span: str) -> str:
    i = 0
    while True:
        match = re.search(r"\btypeof\s+", span[i:])
        if not match:
            return span
        start = i + match.start()
        expr_start = i + match.end()
        expr_end = find_expression_end(span, expr_start)
        if expr_end <= expr_start:
            i = expr_start
            continue
        expression = span[expr_start:expr_end].strip()
        replacement = f"{AS3_HELPER}.typeOf({expression})"
        span = span[:start] + replacement + span[expr_end:]
        i = start + len(replacement)


def convert_reserved_property_access(span: str) -> str:
    part = r"[A-Za-z_]\w*(?:\[[^\[\]\n]+\])?"
    target = rf"(?<![\w.])({part}(?:\.(?!cast\b){part})*)"
    return re.sub(
        target + r"\s*\.\s*(cast)\b",
        lambda m: f'Reflect.field({m.group(1)}, "{m.group(2)}")',
        span,
    )


def python_string_literal(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def convert_delete_operators(span: str) -> str:
    span = re.sub(
        r"\bdelete\s+([A-Za-z_]\w*)\s*\.\s*@\s*\[\s*([^\]\n]+?)\s*\]",
        lambda m: f"{AS3_HELPER}.deleteXmlAttribute({m.group(1)}, {m.group(2).strip()})",
        span,
    )
    span = re.sub(
        r"\bdelete\s+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*|\([^;\n]*?\))*)\s*\[\s*([^\]\n]+?)\s*\]",
        lambda m: f"{AS3_HELPER}.deleteField({m.group(1)}, {m.group(2).strip()})",
        span,
    )
    span = re.sub(
        r"\bdelete\s+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\.([A-Za-z_]\w*)",
        lambda m: f'{AS3_HELPER}.deleteField({m.group(1)}, "{m.group(2)}")',
        span,
    )
    return span


def declare_temp_locals(text: str) -> str:
    out: list[str] = []
    i = 0
    while True:
        match = re.search(r"\bfunction\b", text[i:])
        if not match:
            out.append(text[i:])
            return "".join(out)
        start = i + match.start()
        body_open = text.find("{", start)
        if body_open < 0:
            out.append(text[i:])
            return "".join(out)
        body_close = find_matching_right(text, body_open)
        if body_close < 0:
            out.append(text[i:body_open + 1])
            i = body_open + 1
            continue
        body = text[body_open + 1:body_close]
        temps = sorted(
            set(re.findall(r"\b_temp_\d+\b", body)),
            key=lambda name: int(name.rsplit("_", 1)[1]),
        )
        missing = [name for name in temps if not re.search(rf"\bvar\s+{re.escape(name)}\b", body)]
        out.append(text[i:body_open + 1])
        if missing:
            indent = line_indent(text, body_open) + "   "
            declarations = "".join(f"\n{indent}var {name}:Dynamic = null;" for name in missing)
            out.append(declarations)
        out.append(body)
        out.append("}")
        i = body_close + 1


def hoist_block_scoped_vars(text: str) -> str:
    out: list[str] = []
    i = 0
    while True:
        match = re.search(r"\bfunction\b", text[i:])
        if not match:
            out.append(text[i:])
            return "".join(out)
        start = i + match.start()
        body_open = text.find("{", start)
        if body_open < 0:
            out.append(text[i:])
            return "".join(out)
        body_close = find_matching_right(text, body_open)
        if body_close < 0:
            out.append(text[i:body_open + 1])
            i = body_open + 1
            continue
        out.append(text[i:body_open + 1])
        body = text[body_open + 1:body_close]
        converted = hoist_vars_in_function_body(body, line_indent(text, body_open) + "   ")
        out.append(converted)
        out.append("}")
        i = body_close + 1


def split_recursive_function_vars(text: str) -> str:
    def one(span: str) -> str:
        return re.sub(
            r"(?P<indent>^[ \t]*)var\s+(?P<name>[A-Za-z_]\w*)\s*:\s*(?P<type>[^=;\n]+?)\s*=\s*function\b",
            lambda m: f"{m.group('indent')}var {m.group('name')}:{m.group('type').strip()};\n{m.group('indent')}{m.group('name')} = function",
            span,
            flags=re.MULTILINE,
        )

    return transform_code(text, one)


def hoist_vars_in_function_body(body: str, indent: str) -> str:
    spans = nested_function_spans(body)
    declared: dict[str, str] = {}
    top_level_declared = {
        match.group("name")
        for match in re.finditer(
            r"(?P<indent>^[ \t]*)var\s+(?P<name>[A-Za-z_]\w*)\s*:\s*[^=;\n]+?(?:\s*=\s*[^;\n]+)?;",
            body,
            re.MULTILINE,
        )
        if brace_depth_at(body, match.start(), spans) == 0
    }
    replacements: list[tuple[int, int, str]] = []
    var_re = re.compile(
        r"(?P<indent>^[ \t]*)var\s+(?P<name>[A-Za-z_]\w*)\s*:\s*(?P<type>[^=;\n]+?)"
        r"(?:\s*=\s*(?P<expr>[^;\n]+))?;",
        re.MULTILINE,
    )
    for match in var_re.finditer(body):
        if any(start <= match.start() < end for start, end in spans):
            continue
        depth = brace_depth_at(body, match.start(), spans)
        name = match.group("name")
        block_end = containing_block_end(body, match.start(), spans)
        if (
            depth <= 0
            or name in declared
            or name in top_level_declared
            or block_end < 0
            or not _referenced_before_redeclaration(body[block_end + 1:], name)
        ):
            continue
        declared[name] = match.group("type").strip()
        expr = match.group("expr")
        replacement = "" if expr is None else f"{match.group('indent')}{name} = {expr.strip()};"
        replacements.append((match.start(), match.end(), replacement))
    if not declared:
        return body
    converted = body
    for start, end, replacement in sorted(replacements, reverse=True):
        converted = converted[:start] + replacement + converted[end:]
    declarations = "".join(f"\n{indent}var {name}:{type_name};" for name, type_name in declared.items())
    return declarations + converted


def _referenced_before_redeclaration(rest: str, name: str) -> bool:
    reference = re.search(rf"\b{re.escape(name)}\b", rest)
    if reference is None:
        return False
    scoped = SINK_HOISTED_LOCALS or (RESCOPE_HOISTED_LOCALS and re.fullmatch(r"_loc\d+_", name))
    return not (scoped and re.search(r"\bvar\s+$", rest[:reference.start()]))


CATCH_DEFAULT_RETURNS = True


def _terminal_catch_close(body: str) -> int:
    stripped = body.rstrip()
    close = len(stripped) - 1
    if close < 0 or stripped[close] != "}":
        return -1
    open_brace = _enclosing_block(stripped, close)
    if open_brace < 0 or _enclosing_block(stripped, open_brace) >= 0:
        return -1
    head = stripped[:open_brace].rstrip()
    catch = re.search(r"\bcatch\s*\([^()\n]*\)$", head)
    if not catch:
        return -1
    try_close = len(head[:catch.start()].rstrip()) - 1
    if try_close < 0 or head[try_close] != "}":
        return -1
    try_open = _enclosing_block(stripped, try_close)
    if try_open < 0 or not re.search(r"(?:^|\n)[ \t]*try$", stripped[:try_open].rstrip()):
        return -1
    if needs_default_return(stripped[try_open + 1:try_close]) or not needs_default_return(
            stripped[open_brace + 1:close]):
        return -1
    return close


def add_missing_return_defaults(text: str) -> str:
    out: list[str] = []
    i = 0
    pattern = re.compile(
        r"\bfunction\s+[A-Za-z_]\w*\s*\([^)]*\)\s*:\s*"
        r"([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?(?:<[^>{}\n]+>)?)\s*\{"
    )
    while True:
        match = pattern.search(text, i)
        if not match:
            out.append(text[i:])
            return "".join(out)
        body_open = text.find("{", match.start())
        body_close = find_matching_right(text, body_open)
        if body_open < 0 or body_close < 0:
            out.append(text[i:match.end()])
            i = match.end()
            continue
        return_type = match.group(1).strip()
        out.append(text[i:body_close])
        body = text[body_open + 1:body_close]
        if return_type != "Void" and needs_default_return(body):
            close_indent = line_indent(text, body_close)
            catch_close = _terminal_catch_close(body) if CATCH_DEFAULT_RETURNS else -1
            if catch_close >= 0:
                out[-1] = out[-1][:-len(body)]
                at = catch_close
                inner = line_indent(body, at)
                body = (body[:at].rstrip(" \t") + f"{inner}   return {default_return_for_type(return_type)};\n"
                        + f"{inner}" + body[at:])
                out.append(body)
            else:
                out.append(f"\n{close_indent}   return {default_return_for_type(return_type)};\n{close_indent}")
        out.append("}")
        i = body_close + 1


def convert_bare_returns_in_value_functions(text: str) -> str:
    out: list[str] = []
    i = 0
    pattern = re.compile(
        r"\bfunction\s+[A-Za-z_]\w*\s*\([^)]*\)\s*:\s*"
        r"(?P<type>[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?(?:<[^>{}\n]+>)?)\s*\{"
    )
    while True:
        match = pattern.search(text, i)
        if not match:
            out.append(text[i:])
            return "".join(out)
        body_open = text.find("{", match.start())
        body_close = find_matching_right(text, body_open)
        if body_open < 0 or body_close < 0:
            out.append(text[i:match.end()])
            i = match.end()
            continue
        return_type = match.group("type").strip()
        body = text[body_open + 1:body_close]
        if return_type != "Void":
            body = keep_terminal_switch_void_default(body, return_type)
            body = re.sub(r"(?<!untyped )\breturn\s*;", f"return {default_return_for_type(return_type)};", body)
        out.append(text[i:body_open + 1])
        out.append(body)
        out.append("}")
        i = body_close + 1


def keep_terminal_switch_void_default(body: str, return_type: str) -> str:
    span, protected = protect_noncode(body)
    end = len(span.rstrip())
    if end == 0 or span[end - 1] != "}":
        return body
    close = end - 1
    depth = 0
    open_index = -1
    for k in range(close, -1, -1):
        if span[k] == "}":
            depth += 1
        elif span[k] == "{":
            depth -= 1
            if depth == 0:
                open_index = k
                break
    if open_index < 0:
        return body
    head = span[:open_index].rstrip()
    if not head.endswith(")"):
        return body
    paren = find_matching_left(span, len(head) - 1)
    if paren < 0 or not re.search(r"(?:^|[;{}\s])switch\s*$", span[:paren]):
        return body
    default = re.search(r"\bdefault\s*:\s*return\s*;\s*$", span[open_index + 1:close])
    if not default:
        return body
    default_at = open_index + 1 + default.start()
    indent = line_indent(span, re.search(r"switch\s*$", span[:paren]).start())
    tail = (
        f"\n{indent}#if flash untyped return; #else return {default_return_for_type(return_type)}; #end"
    )
    trailing = default.group(0)[len(default.group(0).rstrip()):]
    span = span[:default_at] + "default:" + trailing + "}" + tail + span[end:]
    return restore_noncode(span, protected)


def convert_void_return_nulls(text: str) -> str:
    out: list[str] = []
    i = 0
    pattern = re.compile(
        r"\bfunction(?:\s+[A-Za-z_]\w*)?\s*\([^)]*\)\s*:\s*Void\s*\{"
    )
    while True:
        match = pattern.search(text, i)
        if not match:
            out.append(text[i:])
            return "".join(out)
        body_open = text.find("{", match.start())
        body_close = find_matching_right(text, body_open)
        if body_open < 0 or body_close < 0:
            out.append(text[i:match.end()])
            i = match.end()
            continue
        body = text[body_open + 1:body_close]
        body = re.sub(r"\breturn\s+null\s*;", "return;", body)
        out.append(text[i:body_open + 1])
        out.append(body)
        out.append("}")
        i = body_close + 1


def convert_is_guarded_returns(text: str) -> str:
    def repl(match: re.Match[str]) -> str:
        name = match.group("name")
        type_name = match.group("type")
        indent = match.group("indent")
        return (
            f"if(port.runtime.As3.toBool(port.runtime.As3.isType({name}, {type_name})))\n"
            f"{indent}{{\n"
            f"{indent}   return port.runtime.As3.asType({name}, {type_name});\n"
            f"{indent}}}"
        )

    return re.sub(
        r"if\s*\(\s*port\.runtime\.As3\.toBool\s*\(\s*port\.runtime\.As3\.isType\((?P<name>[A-Za-z_]\w*),\s*(?P<type>[A-Za-z_]\w*)\)\s*\)\s*\)\s*"
        r"\{\s*\n"
        r"(?P<return_indent>[ \t]*)return\s+(?P=name)\s*;\s*\n"
        r"(?P<indent>[ \t]*)\}",
        repl,
        text,
    )


def needs_default_return(body: str) -> bool:
    stripped = re.sub(r"(?:\s|//[^\n]*(?:\n|$)|/\*.*?\*/)+$", "", body, flags=re.DOTALL)
    return not bool(re.search(r"(?:return|throw)(?:\s+[^;]*)?;(?:\s*#end)?\s*$", stripped))


def fill_bare_typed_returns(text: str) -> str:
    if "return;" not in text:
        return text
    bodies: list[tuple[int, int, str]] = []
    for header in re.finditer(r"\bfunction\b[^{;]*?\)\s*:\s*(?P<type>[A-Za-z_][\w.]*(?:<[^{;]*>)?)\s*\{", text):
        close = find_matching_right(text, header.end() - 1)
        if close > 0:
            bodies.append((header.end() - 1, close, header.group("type")))
    edits: list[tuple[int, str]] = []
    for ret in re.finditer(r"(?<!untyped )\breturn\s*;", text):
        owners = [b for b in bodies if b[0] < ret.start() < b[1]]
        if not owners:
            continue
        owner_type = min(owners, key=lambda b: b[1] - b[0])[2]
        untyped = [m for m in re.finditer(r"\bfunction\b[^{;:]*?\)\s*\{", text) if m.end() - 1 < ret.start()
                   and find_matching_right(text, m.end() - 1) > ret.start()
                   and m.end() - 1 > min(owners, key=lambda b: b[1] - b[0])[0]]
        if owner_type != "Void" and not untyped:
            edits.append((ret.start(), f"return {default_return_for_type(owner_type)};", ret.end()))
    for start, replacement, end in sorted(edits, reverse=True):
        text = text[:start] + replacement + text[end:]
    return text


def default_return_for_type(return_type: str) -> str:
    if return_type == "Bool":
        return "false"
    if return_type in {"Int", "UInt"}:
        return "0"
    if return_type == "Float":
        return "Math.NaN"
    return "null"


def containing_block_end(text: str, index: int, skip_spans: list[tuple[int, int]]) -> int:
    stack: list[int] = []
    i = 0
    span_index = 0
    while i < len(text) and i < index:
        if span_index < len(skip_spans) and i == skip_spans[span_index][0]:
            i = skip_spans[span_index][1]
            span_index += 1
            continue
        if text[i] == "{":
            stack.append(i)
        elif text[i] == "}" and stack:
            stack.pop()
        i += 1
    if not stack:
        return -1
    return find_matching_right(text, stack[-1])


def nested_function_spans(body: str) -> list[tuple[int, int]]:
    spans: list[tuple[int, int]] = []
    i = 0
    while True:
        match = re.search(r"\bfunction\b", body[i:])
        if not match:
            return spans
        start = i + match.start()
        body_open = body.find("{", start)
        if body_open < 0:
            return spans
        body_close = find_matching_right(body, body_open)
        if body_close < 0:
            return spans
        spans.append((start, body_close + 1))
        i = body_close + 1


def brace_depth_at(text: str, index: int, skip_spans: list[tuple[int, int]]) -> int:
    depth = 0
    i = 0
    span_index = 0
    while i < index:
        if span_index < len(skip_spans) and i == skip_spans[span_index][0]:
            i = skip_spans[span_index][1]
            span_index += 1
            continue
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth = max(0, depth - 1)
        i += 1
    return depth


def collect_unsupported(text: str) -> Counter[str]:
    code = "".join(span if is_code else "" for is_code, span in split_code(text))
    code = re.sub(r"^\s*import\s+[^;\n]+\s+as\s+\w+\s*;\s*$", "", code, flags=re.MULTILINE)
    unsupported = Counter()
    checks = {
        "pseudo_ops": r"§§",
        "for_each": r"\bfor\s+each\b",
        "getter_setter": r"\bfunction\s+(?:get|set)\s+",
        "namespace": r"\bnamespace\b",
        "xml_literal": r"(?<![\w.])<[A-Za-z_][A-Za-z0-9_:-]*(?:\s|>|/>)",
        "as_operator": r"\s+as\s+",
        "is_operator": r"\s+is\s+",
        "delete_operator": r"\bdelete\s+",
        "regex_literal": REGEX_LITERAL_RE,
        "quoted_object_keys": QUOTED_OBJECT_KEY_RE,
        "e4x_attribute": r"\.\s*@",
        "typeof_operator": r"\btypeof\s+",
        "labeled_break": r"\b(?:break|continue)\s+loop\d+\s*;",
        "label": r"^\s*loop\d+:\s*$",
        "with_statement": r"\bwith\s*\(",
    }
    for name, pattern in checks.items():
        if isinstance(pattern, str):
            unsupported[name] += len(re.findall(pattern, code))
        else:
            unsupported[name] += len(pattern.findall(code))
    return +unsupported


BOOT_INIT_STUB = 'throw new Error("BH_SPLICE BootDocument.init");'


def recover_boot_document_init(text: str) -> str:
    if BOOT_INIT_STUB not in text or "class BootDocument" not in text:
        return text
    stub = text.index(BOOT_INIT_STUB)
    head = text.rfind("override public function init()", 0, stub)
    open_brace = text.index("{", head)
    close = find_matching_right(text, open_brace)
    if head < 0 or close < 0:
        raise ValueError("BootDocument.init: method not found")
    lines = []
    for line in text[stub:close].splitlines()[2:]:
        stripped = line.strip()
        if not stripped.startswith("//"):
            continue
        lines.append(stripped[2:].strip())
    first_init = next(i for i, line in enumerate(lines) if re.match(r"if\(!\w+\.init__\)", line))
    locals_ = []
    for line in lines[:first_init]:
        if not re.match(r"var _loc\d+_:", line):
            break
        locals_.append(line)
    body = lines[first_init:]
    if body and body[-1] == "GameApp.main();":
        body = body[:-1]
    out: list[str] = []
    pushed: str | None = None
    for line in body:
        push = re.fullmatch(r"§§push\(([\w.]+)\);", line)
        pop = re.fullmatch(r"§§pop\(\)\.(\w+) = (.+);", line)
        if push:
            if pushed is not None:
                raise ValueError("BootDocument.init: nested §§push")
            pushed = push.group(1)
            continue
        if pop:
            if pushed is None:
                raise ValueError("BootDocument.init: §§pop without §§push")
            out.append(f"{pushed}.{pop.group(1)} = {pop.group(2)};")
            pushed = None
            continue
        if "§§" in line:
            raise ValueError(f"BootDocument.init: unexpected pseudo-op {line!r}")
        out.append(line)
    if pushed is not None:
        raise ValueError("BootDocument.init: unbalanced §§push")
    marked: list[str] = []
    for index, line in enumerate(out):
        marked.append(line)
        guard = re.fullmatch(r"if\(!(\w+)\.init__\)", out[index - 1]) if index > 0 else None
        if guard and line == "{":
            marked.append(f'port.runtime.FlashBoot.initStage = "{guard.group(1)}";')
    out = marked
    indent = "         "
    method = ("public static function staticInit() : void" + chr(10) + "      {" + chr(10)
              + "".join(indent + line + chr(10) for line in locals_ + out) + "      }")
    return text[:head] + method + text[close + 1:]


RECOVERED_METHODS_DIR = Path(__file__).resolve().parents[1] / "src" / "as3-recovered" / "10.11"
BH_SPLICE_RE = re.compile(r'throw new Error\("BH_SPLICE ([\w.]+)\.(\w+)"\);')


def apply_recovered_methods(text: str, directory: Path | None = None) -> str:
    directory = directory or RECOVERED_METHODS_DIR
    for match in list(BH_SPLICE_RE.finditer(text))[::-1]:
        owner, method = match.group(1).rsplit(".", 1)[-1], match.group(2)
        source = directory / f"{owner}.{method}.as"
        if not source.exists():
            continue
        head = text.rfind("function ", 0, match.start())
        line_start = text.rfind("\n", 0, head) + 1
        open_brace = text.index("{", head)
        close = find_matching_right(text, open_brace)
        if head < 0 or close < 0 or close < match.end():
            raise ValueError(f"{owner}.{method}: stub method not found")
        recovered = source.read_text(encoding="utf-8").strip("\n")
        text = text[:line_start] + recovered + text[close + 1:]
    return text


NATIVE_DICTIONARY_MARK = "As3NativeDictionaryMark__"


_MOVIECLIP_API: set[str] | None = None
MEMBER_FUNCTION_RE = re.compile(r"^\s*(?:(?:public|private|override|static|inline|final|dynamic)\s+)*function\s+\w+\s*\(",
                                re.M)
_FLASH_EXTERN_MEMBER_RE = re.compile(r"\b(?:var|function)\s+(?:get_|set_)?(\w+)")


def movieclip_api() -> set[str]:
    global _MOVIECLIP_API
    if _MOVIECLIP_API is None:
        std = ROOT / ".tools" / "haxe" / "std" / "flash"
        names: set[str] = set()
        for rel in ("display/MovieClip.hx", "display/Sprite.hx", "display/DisplayObjectContainer.hx",
                    "display/InteractiveObject.hx", "display/DisplayObject.hx", "events/EventDispatcher.hx"):
            names.update(_FLASH_EXTERN_MEMBER_RE.findall((std / rel).read_text(encoding="utf-8")))
        names.update({"hasOwnProperty", "isPrototypeOf", "propertyIsEnumerable", "setPropertyIsEnumerable",
                      "toString", "toLocaleString", "valueOf", "constructor"})
        _MOVIECLIP_API = names
    return _MOVIECLIP_API


def convert_dynamic_clip_fields(body: str) -> str:
    if "MovieClip" not in body:
        return body
    code, protected = protect_noncode(body)
    api = movieclip_api()
    starts = [m.start() for m in MEMBER_FUNCTION_RE.finditer(code)] + [len(code)]
    out = [code[:starts[0]]]
    for start, end in zip(starts, starts[1:]):
        region = code[start:end]
        names = set(re.findall(r"\b(\w+)\s*:\s*(?:flash\.display\.)?MovieClip\b(?!\s*[<.])", region))
        if names:
            pattern = re.compile(r"(?<![\w.$])(" + "|".join(sorted(map(re.escape, names))) + r")\.([A-Za-z_]\w*)\b")
            region = pattern.sub(
                lambda m: m.group(0) if m.group(2) in api else f"{AS3_HELPER}.dyn({m.group(1)}).{m.group(2)}", region)
        out.append(region)
    return restore_noncode("".join(out), protected)


def convert_text(text: str, source_name: str = "<memory>") -> tuple[str, ConvertStats]:
    package_name, body = unwrap_package(text)
    body = re.sub(r"\bnew\s+Dictionary\s*\(", f"new {NATIVE_DICTIONARY_MARK}(", body)
    body = recover_boot_document_init(body)
    body = apply_recovered_methods(body)
    first_class = CLASS_RE.search(body)
    body = restore_double_literals(body, first_class.group(1) if first_class else None)
    body = restore_static_increments(body)
    body = restore_catch_variables(body)
    body = restore_unused_catch_variables(body)
    body = restore_temp_receivers(body)
    body = inline_postfix_index_temps(body)
    body = inline_call_spill_temps(body)
    body = unwrap_bool_string_concats(body)
    if SINK_HOISTED_LOCALS:
        body = sink_hoisted_locals(body)
    if UNINIT_HOISTED_LOCALS:
        body = uninitialize_hoisted_locals(body)
    if SINK_CHAIN_TEMP_LOCALS:
        body = sink_chain_temp_locals(body)
    body = restore_audited_pseudo_typed_reference_locals(body)
    body = promote_mined_pseudo_typed_reference_locals(body)
    body = restore_audited_bombsketball_relational_branch(body)
    body = restore_audited_relational_branches(body)
    body = restore_audited_native_error_messages(body)
    body = remove_audited_unused_number_local(body)
    class_match = CLASS_RE.search(body)
    class_name = class_match.group(1) if class_match else None
    class_names = {match.group(1) for match in CLASS_RE.finditer(body)}
    class_extends = bool(class_name and re.search(rf"\bclass\s+{re.escape(class_name)}\s+extends\b", body))
    parent_match = re.search(r"\bclass\s+[A-Za-z_]\w*\s+extends\s+([A-Za-z_]\w*)", body)
    parent_name = parent_match.group(1) if parent_match else None

    body = restore_audited_function_vector_types(body)
    body = convert_types(body)
    body = restore_container_element_types(body, class_name)
    body = restore_double_literal_stores(body, class_name)
    body = normalize_primitive_null_defaults(body)
    body = convert_member_syntax(body, class_name, class_extends, class_names)
    body = convert_property_setter_returns(body)
    body = move_instance_field_initializers(body, class_name)
    body = order_field_initializers(body, class_name)
    body = normalize_reserved_identifiers(body)
    body = split_multi_var_declarations(body)
    body = convert_c_style_for_loops(body)
    body = convert_try_finally(body)
    body = lower_switch_label_exits_across_loops(body)
    body = convert_labeled_breaks(body)
    body = remove_self_assignments(body)
    body = collapse_empty_integer_case_groups(body)
    body = wrap_switch_statements(body)
    body = convert_expressions(body)
    body = restore_audited_native_date_construction(body)
    body = restore_audited_native_vector_methods(body)
    body = restore_audited_expression_semantics(body)
    body = restore_audited_remove_children_receiver_coercions(body)
    body = restore_audited_display_object_boundaries(body)
    body = restore_audited_math_floor_number_initializers(body)
    body = restore_known_string_array_literal_comparisons(body)
    body = restore_audited_typed_array_reads(body)
    body = restore_audited_array_boundaries(body)
    body = restore_audited_typed_map_reads(body)
    body = restore_typed_imap_reads(body, class_name)
    body = restore_imap_local_stores(body, class_name)
    body = restore_wide_array_reads(body, class_name)
    body = restore_uint_pre_increments(body)
    body = restore_known_ring_vector_accesses(body)
    body = restore_typed_index_of_calls(body)
    body = restore_declared_array_slices(body)
    body = restore_typed_vector_index_reads(body)
    body = restore_typed_vector_sorts(body)
    body = restore_typed_array_index_writes(body)
    body = normalize_primitive_null_defaults(body)
    body = convert_nonconstant_parameter_defaults(body)
    body = coerce_float_math_int_initializers(body)
    body = re.sub(rf"{re.escape(AS3_HELPER)}\.isType\(([^(),]+), UInt\)", rf"{AS3_HELPER}.isUInt(\1)", body)
    helper = re.escape(AS3_HELPER)
    body = re.sub(rf"(?:Std\.isOfType|{helper}\.isType)\(([^(),]+), ByteArray\)", rf"{AS3_HELPER}.isByteArray(\1)", body)
    body = re.sub(rf"{helper}\.asType\(([^(),]+), ByteArray\)", rf"{AS3_HELPER}.asByteArray(\1)", body)
    body = initialize_reference_locals(body)
    body = convert_flash_constants(body)
    body = convert_default_logical_or_calls(body)
    body = restore_literal_comparisons(body)
    body = convert_regex_string_replace(body)
    body = convert_package_function_imports(body)
    body = convert_package_function_calls(body)
    body = qualify_big_window_members(body, parent_name)
    body = normalize_legacy_haxe_internal_imports(body)
    body = import_e4x_types(body)
    body = normalize_haxe_type_names(body)
    body = declare_temp_locals(body)
    body = split_recursive_function_vars(body)
    body = hoist_block_scoped_vars(body)
    body = initialize_reference_locals(body)
    body = convert_function_scoped_typed_assignments(body)
    protected_body, protected_parts = protect_noncode(body)
    body = restore_noncode(convert_string_wrapper_logical_or(protected_body), protected_parts)
    body = convert_is_guarded_returns(body)
    body = convert_bare_returns_in_value_functions(body)
    body = convert_void_return_nulls(body)
    body = fill_bare_typed_returns(body)
    body = add_missing_return_defaults(body)
    body = add_default_constructor(body, class_name, class_extends)
    body = add_known_interface_dynamic_members(body, class_name)
    body = fix_autopilot_test_community_ternary(body)
    body = parenthesize_simple_chained_ternaries(body)
    body = fix_chained_ternary_concat_closers(body)
    body = fix_multiline_push_continuations(body)
    body = fix_multiline_false_branch_ternary_concat(body)
    body = fix_set_index_trailing_arithmetic(body)
    body = fix_nested_string_ternary_returns(body)
    body = fix_std_string_false_branch_concat(body)
    body = fix_unclosed_std_string_ternaries(body)
    body = fix_logical_or_ternary_helpers(body)
    body = fix_bitwise_ternary_concat_condition(body)
    body = fix_multiline_ternary_string_continuation(body)
    body = fix_numeric_sum_string_concat(body)
    body = fix_nested_call_concat_closer(body)
    body = fix_unclosed_multiline_assignment_concat(body)
    body = fix_unclosed_multiline_call_concat(body)
    body = fix_ternary_bitwise_branches(body)
    body = fix_ternary_bitwise_comparison_grouping(body)
    body = fix_bitwise_ternary_chain_grouping(body)
    body = fix_extra_ternary_call_closer(body)
    body = fix_extra_ternary_argument_closer(body)
    body = fix_extra_set_index_closer(body)
    body = fix_extra_assignment_closer(body)
    body = fix_extra_ternary_argument_closer(body)
    body = fix_extra_ternary_field_assignment_closer(body)
    body = fix_extra_return_ternary_closer(body)
    body = fix_return_ternary_concat_closer(body)
    body = fix_ternary_field_access_grouping(body)
    body = fix_ternary_boolean_tail_grouping(body)
    body = fix_condition_logical_or_grouping(body)
    body = fix_numeric_ternary_arithmetic_grouping(body)
    body = fix_numeric_cast_ternary_branch_grouping(body)
    body = fix_numeric_cast_shift_grouping(body)
    body = fix_numeric_cast_division_ternary_grouping(body)
    body = fix_numeric_cast_shift_division_grouping(body)
    body = fix_reference_ternary_cast_grouping(body)
    body = fix_malformed_equality_ternaries(body)
    body = fix_regex_exec_assignment_grouping(body)
    body = fix_unclosed_var_ternary_initializer(body)
    body = fix_unclosed_multiline_var_ternary_initializer(body)
    body = fix_unclosed_multiline_return_grouping(body)
    body = fix_extra_assignment_closer(body)
    body = fix_numeric_cast_modulo(body)
    body = fix_unclosed_numeric_casts(body)
    body = fix_extra_ternary_call_closer(body)
    body = fix_extra_ternary_field_assignment_closer(body)
    body = fix_numeric_comparison_or_guard(body)
    body = fix_casted_index_as_type(body)
    body = fix_numeric_value_property_coercion(body)
    body = fix_malformed_logical_or_bool_call(body)
    body = convert_known_screen_assignment_casts(body)
    body = convert_uint_returns(body)
    body = convert_dynamic_comparator_returns(body)
    body = fix_type_frontier_value_shapes(body)
    body = fix_logical_and_value_comparison_grouping(body)
    body = fix_logical_and_numeric_tail(body)
    body = fix_bool_relational_comparison_grouping(body)
    body = fix_malformed_if_not_bitwise_comparison(body)
    body = fix_boolean_numeric_comparisons(body)
    body = fix_logical_bitwise_operand_truthiness(body)
    body = fix_boolean_numeric_comparisons(body)
    body = fix_logical_null_comparisons(body)
    body = re.sub(r"=\(=\s*null\)", "== null", body)
    body = re.sub(r"\bif\(\((?P<cond>[^;\n?]+\|\|[^;\n?]+== null)\s*\?", r"if((\g<cond>) ?", body)
    body = remove_redundant_boolean_branch_helpers(body)
    body = convert_pseudo_string_local_assignments(body)
    body = convert_type_tested_downcasts(body)
    body = restore_audited_expression_semantics(body, late_only=True)
    body = restore_audited_static_string_literals(body)
    body = convert_empty_vector_constructors(body)
    body = body.replace(f"{AS3_HELPER}.coerceString(null)", "null")
    body = IMPORT_RE.sub(lambda m: f"{m.group(1)}import {m.group(2)};", body)
    if RAW_STRING_THROWS:
        body = RAW_STRING_THROW_RE.sub(r"\g<head>throw (cast (\g<value>) : port.runtime.RawString);", body)
    if NATIVE_FROM_CHAR_CODE:
        body = NATIVE_FROM_CHAR_CODE_RE.sub("port.runtime.NativeString.fromCharCode(", body)
    if UINT_STRING_CONCATS:
        body = convert_uint_string_concats(body)
    if UNTYPED_STRING_CONCAT_OPERANDS:
        body = untype_string_concat_operands(body)
    if UINT_CLAMP_TERNARY_ARMS:
        body = restore_uint_clamp_ternary_arms(body)
    body = convert_native_is_type_checks(body)
    body = convert_native_array_splices(body)
    body = convert_native_rawdata_stores(body)
    body = type_native_receiver_temps(body)
    body = cast_container_element_stores(body, class_name)
    body = body.strip("\n")
    body = body.replace(HOISTED_MARK, "")
    body = restore_map_spec_receiver_casts(body, class_name)
    body = restore_uint_constant_stores(body, class_name)
    body = restore_uint_literal_markers(body)
    body = body.replace(NATIVE_DICTIONARY_MARK, "flash.utils.Dictionary")
    body = convert_dynamic_clip_fields(body)
    body = rename_std_shadowing_types(body, package_name)

    header = f"package {package_name};" if package_name else "package;"
    converted = f"{header}\n\n{body}\n"
    stats = ConvertStats(files=1, unsupported=collect_unsupported(converted))
    fallthrough = len(switch_fallthrough_cases(text))
    crossing = len(labeled_breaks_across_loops(protect_noncode(lower_switch_label_exits_across_loops(text))[0]))
    if crossing:
        stats.unsupported["labeled_break_across_loop"] += crossing
    if fallthrough:
        stats.unsupported["switch_fallthrough"] += fallthrough
    return converted, stats


UNTYPED_STRING_CONCAT_OPERANDS = True
_CONCAT_OPERAND_RE = re.compile(r"[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*")


def _single_concat_operand(text: str, start: int) -> int:
    m = _CONCAT_OPERAND_RE.match(text, start)
    if not m:
        return -1
    end = m.end()
    while end < len(text) and text[end] in "([":
        close = find_matching_right(text, end)
        if close < 0:
            return -1
        end = close + 1
        more = re.match(r"(?:\.[A-Za-z_$][\w$]*)+", text[end:])
        if more:
            end += more.end()
    return end


def untype_string_concat_operands(text: str) -> str:
    span, protected = protect_noncode(text)
    empty = {f"__AS3_NONCODE_{index}__" for index, literal in enumerate(protected) if literal == '""'}
    strings = {f"__AS3_NONCODE_{index}__" for index, literal in enumerate(protected) if literal.startswith('"')}
    out: list[str] = []
    i = 0
    for m in re.finditer(r"(\(\s*(__AS3_NONCODE_\d+__)\s*\+\s*)|((__AS3_NONCODE_\d+__)\s*\+\s*)", span):
        if m.start() < i:
            continue
        if m.group(1):
            if m.group(2) not in empty:
                continue
            start = m.end()
            end = _single_concat_operand(span, start)
            if end < 0 or span[end:end + 1] != ")":
                continue
        else:
            if m.group(4) not in strings:
                continue
            start = m.end()
            if not span.startswith(f"{AS3_HELPER}.index(", start):
                continue
            end = _single_concat_operand(span, start)
            if end < 0 or re.match(r"\s*(?:[*/%]|\.\w)", span[end:]):
                continue
        operand = span[start:end]
        if operand.startswith(("Std.string(", "untyped", f"{AS3_HELPER}.coerceString(", "__AS3_NONCODE_")) or operand in (
                "null", "true", "false", "this"):
            continue
        out.append(span[i:start])
        out.append(f"(untyped {operand})")
        i = end
    out.append(span[i:])
    return restore_noncode("".join(out), protected)


UINT_CLAMP_TERNARY_ARMS = True
UINT_CLAMP_TERNARY_RE = re.compile(
    r"\((?P<x>[A-Za-z_]\w*) (?P<op>[<>]=?) (?P<n>\d+) \? (?P=n) : (?P=x)\)(?=\s*[-+*])")


def restore_uint_clamp_ternary_arms(text: str) -> str:
    uints = load_uint_members()

    def repl(match: re.Match[str]) -> str:
        x = match.group("x")
        if x not in uints:
            return match.group(0)
        return f"({x} {match.group('op')} {match.group('n')} ? {match.group('n')} : (untyped {x}))"

    return UINT_CLAMP_TERNARY_RE.sub(repl, text)


RAW_STRING_THROWS = True
RAW_STRING_THROW_RE = re.compile(
    r'^(?P<head>[ \t]*)throw\s+(?P<value>"(?:[^"\\\n]|\\.)*"\s*\+[^;\n]*);(?=[ \t]*$)', re.M)


NATIVE_FROM_CHAR_CODE = True
NATIVE_FROM_CHAR_CODE_RE = re.compile(r"(?<![\w.])String\.fromCharCode\(")


UINT_STRING_CONCATS = True
UINT_STRING_CONCAT_RE = re.compile(
    r'(?<![\w$."])\x03\s*\+\s*(?P<x>(?:_loc\d+_|param\d+)(?:\.(?P<field>[A-Za-z_]\w*))?)(?![\w$.(\[])')
UINT_STRING_CONCAT_SKIPS = {('Class_451', 'method_5877'), ('class_451', 'method_5877')}
_UINT_MEMBERS: set[str] | None = None


def load_uint_members(names: set[str] | None = None) -> set[str]:
    global _UINT_MEMBERS
    if names is not None:
        _UINT_MEMBERS = set(names)
    if _UINT_MEMBERS is None:
        types: dict[str, set[str]] = {}
        scripts = ROOT / "src" / "as3" / VERSION / "scripts"
        for path in sorted(p for p in scripts.rglob("*.as") if p.relative_to(scripts).parts[0] != "bh"):
            for match in re.finditer(r"\bvar\s+(?!_loc\d+_)([A-Za-z_]\w*)\s*:\s*([\w.<>*]+)",
                                     path.read_text(encoding="utf-8")):
                types.setdefault(match.group(1), set()).add(match.group(2))
        _UINT_MEMBERS = {name for name, kinds in types.items() if kinds == {"uint"}}
    return _UINT_MEMBERS


def convert_uint_string_concats(text: str) -> str:
    span, protected = protect_noncode(text)
    for index, literal in enumerate(protected):
        if literal == '""':
            span = re.sub(rf"__AS3_NONCODE_{index}__(?!\d)", "\x03", span)
    class_match = CLASS_RE.search(span)
    class_name = class_match.group(1) if class_match else None
    out: list[str] = []
    i = 0
    function_pattern = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    while True:
        match = function_pattern.search(span, i)
        if not match:
            out.append(span[i:])
            return restore_noncode("".join(out), protected).replace("\x03", '""')
        paren = span.find("(", match.start())
        close_paren = find_matching_right(span, paren)
        body_open = span.find("{", close_paren) if close_paren >= 0 else -1
        body_close = find_matching_right(span, body_open) if body_open >= 0 else -1
        if body_close < 0 or ";" in span[close_paren:body_open]:
            out.append(span[i:match.end()])
            i = match.end()
            continue
        body = span[body_open:body_close]
        if "\x03" in body and (class_name, match.group(1)) not in UINT_STRING_CONCAT_SKIPS:
            uint_names = set(re.findall(r"\b(param\d+)\s*:\s*UInt\b", span[paren:close_paren]))
            uint_names |= set(re.findall(r"\bvar\s+(_loc\d+_)\s*:\s*UInt\b", body))

            def replace(m: re.Match[str]) -> str:
                if body[:m.start()].rstrip().endswith("+"):
                    return m.group(0)
                if m.group("field"):
                    ok = m.group("field") in load_uint_members()
                else:
                    ok = m.group("x") in uint_names
                return f"Std.string({m.group('x')})" if ok else m.group(0)

            body = UINT_STRING_CONCAT_RE.sub(replace, body)
        out.append(span[i:body_open])
        out.append(body)
        i = body_close


EMPTY_VECTOR_NEW_RE = re.compile(r"(?<![\w.])new\s+Vector<")
EMPTY_CALL_RE = re.compile(r"\s*\(\s*\)")


def convert_empty_vector_constructors(text: str) -> str:
    out: list[str] = []
    i = 0
    for match in EMPTY_VECTOR_NEW_RE.finditer(text):
        if match.start() < i:
            continue
        type_start = match.end()
        type_end = find_generic_type_end(text, type_start)
        if type_end < 0:
            continue
        element = text[type_start:type_end]
        call = EMPTY_CALL_RE.match(text, type_end + 1)
        if not call:
            open_index = type_end + 1
            if open_index >= len(text) or text[open_index] != "(":
                continue
            close_index = find_matching_right(text, open_index)
            if close_index < 0:
                continue
            args = [convert_empty_vector_constructors(arg.strip())
                    for arg in split_top_level_commas(text[open_index + 1:close_index])]
            if len(args) not in (1, 2) or not all(args):
                continue
            length = f"{AS3_HELPER}.vectorLength({args[0]})"
            factory = f"sized({length})" if len(args) == 1 else f"sizedFixed({length}, {args[1]})"
            out.append(text[i:match.start()])
            out.append(f"(Vector.{factory} : Vector<{element}>)")
            i = close_index + 1
            continue
        out.append(text[i:match.start()])
        out.append(f"(Vector.create() : Vector<{element}>)")
        i = call.end()
    out.append(text[i:])
    return "".join(out)


def fix_autopilot_test_community_ternary(text: str) -> str:
    text = re.sub(
        r"testCommunity\(port\.runtime\.As3\.index\(c\.args,\s*0\)\)\s*==\s*\"get\"\s*\?\s*(port\.runtime\.As3\.toInt\(port\.runtime\.As3\.index\(c\.args,\s*1\)\))\s*:\s*(-?\d+)",
        'testCommunity((port.runtime.As3.index(c.args, 0) == "get" ? \\1 : \\2))',
        text,
    )
    text = text.replace(" : -1)))));", " : -1))));")
    return text


def statement_paren_balances(lines: list[str]) -> list[int]:
    out = [0] * len(lines)
    start = 0
    balance = 0
    for i, line in enumerate(lines):
        stripped = line.rstrip("\r\n")
        balance += paren_balance_outside_strings(stripped)
        if stripped.rstrip().endswith((";", "{", "}")) or i == len(lines) - 1:
            for j in range(start, i + 1):
                out[j] = balance
            start, balance = i + 1, 0
    return out


def fix_multiline_push_continuations(text: str) -> str:
    fixed: list[str] = []
    lines = text.splitlines(keepends=True)
    balances = statement_paren_balances(lines)
    for index, line in enumerate(lines):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        match = re.search(r"\)\s*\+\s*$", stripped)
        if "out.push(" in stripped and match and paren_balance_outside_strings(stripped[: match.end() - 1]) == 0:
            stripped = stripped[: match.start()] + stripped[match.start() + 1:]
        if balances[index] < 0:
            stripped = fix_early_call_close_before_concat(stripped)
        if stripped.rstrip().endswith("+") and balances[index] < 0:
            stripped = fix_open_concat_early_close(stripped)
        if balances[index] < 0:
            stripped = fix_parenthesized_ternary_continuation(stripped)
        stripped = fix_std_string_ternary_concat(stripped)
        stripped = fix_assignment_ternary_concat(stripped)
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_open_concat_early_close(line: str) -> str:
    balance = paren_balance_outside_strings(line)
    if "out.push(" in line or not line.rstrip().endswith("+") or balance < 0:
        return line
    pos = 0
    while True:
        match = re.search(r"\)\)\s*\+", line[pos:])
        if not match:
            return line
        start = pos + match.start()
        candidate = line[:start] + line[start + 1:]
        if paren_balance_outside_strings(candidate) == balance + 1:
            return candidate
        pos = start + 2


def fix_parenthesized_ternary_continuation(line: str) -> str:
    if "?" not in line or not line.lstrip().startswith("("):
        return line
    balance = paren_balance_outside_strings(line)
    if balance >= 0:
        return line
    pos = 0
    while True:
        match = re.search(r"\)\)\s*\+", line[pos:])
        if not match:
            return line
        start = pos + match.start()
        candidate = line[:start] + line[start + 1:]
        if paren_balance_outside_strings(candidate) > balance:
            return candidate
        pos = start + 2


def fix_assignment_ternary_concat(line: str) -> str:
    if "?" not in line or "=" not in line:
        return line
    fixed = re.sub(
        r"(=\s*)\(([^;\n]*\?[^;\n]+\([^;\n]*\?[^:\n]+:[^)\n]+\))\)\s*\+\s*([^:\n]+)\s*:",
        r"\1\2 + \3 :",
        line,
    )
    if fixed != line:
        return fixed
    if paren_balance_outside_strings(line) >= 0:
        return line
    fixed = line.replace(': "refused: ")) +', ': "refused: ") +')
    if fixed != line:
        return fixed
    return re.sub(r"(=\s*\([^;\n]*\?[^:\n]+:[^)\n]+)\)\s*\+\s*([^;\n]+);", r"\1 + \2;", line)


def fix_std_string_ternary_concat(line: str) -> str:
    if (("Std.string(" not in line and f"{STRING_ARG_CALL}(" not in line) or "?" not in line
            or paren_balance_outside_strings(line) >= 0):
        return line
    return re.sub(rf"((?:Std\.string|{re.escape(STRING_ARG_CALL)})\([^;\n]*\?[^:\n]+:[^)\n]+)\)\s*\+\s*([^;\n]+)\);",
                  r"\1 + \2);", line)


def fix_chained_ternary_concat_closers(text: str) -> str:
    text = text.replace(': "in")))) + " legend"', ': "in"))) + " legend"')
    return text.replace(': "in")))) + " legend "', ': "in"))) + " legend "')


def _statement_paren_balance(lines: list[str], at: int) -> int:
    start = at
    while start > 0 and not lines[start - 1].rstrip().endswith((";", "{", "}")):
        start -= 1
    end = at
    while end < len(lines) - 1 and not lines[end].rstrip().endswith(";"):
        end += 1
    return sum(paren_balance_outside_strings(lines[k]) for k in range(start, end + 1))


def fix_multiline_false_branch_ternary_concat(text: str) -> str:
    fixed: list[str] = []
    previous_stripped = ""
    all_lines = text.splitlines()
    for index, line in enumerate(text.splitlines(keepends=True)):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if (
            previous_stripped.rstrip().endswith("+")
            and "?" in previous_stripped
            and ":" in previous_stripped
            and stripped.lstrip().startswith("(")
            and "?" in stripped
            and re.search(r'\)\s*\+\s*$', stripped)
            and not re.search(r'\)\)\s*\+\s*$', stripped)
            and _statement_paren_balance(all_lines, index) > 0
        ):
            stripped = re.sub(r"\)\s*\+\s*$", ")) +", stripped)
        fixed.append(stripped + ending)
        previous_stripped = stripped
    return "".join(fixed)


def fix_set_index_trailing_arithmetic(text: str) -> str:
    fixed: list[str] = []
    call = f"{AS3_HELPER}.setIndex("
    trailing = re.compile(r"\s*([+\-*/])\s*([^;\n]+)\);$")
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        start = stripped.find(call)
        if start < 0:
            fixed.append(line)
            continue
        open_paren = start + len(call) - 1
        close = find_matching_right(stripped, open_paren)
        if close < 0:
            fixed.append(line)
            continue
        match = trailing.match(stripped[close + 1:])
        if not match:
            fixed.append(line)
            continue
        fixed.append(stripped[:close] + f" {match.group(1)} {match.group(2).strip()});" + ending)
    return "".join(fixed)


def fix_nested_string_ternary_returns(text: str) -> str:
    pattern = re.compile(
        r"(\?\s*[^:\n]+:\s*)\(([^;\n]+?!=\s*null\s*\?\s*Std\.string\([^;\n]+?\))\s*:\s*([^;\n]+)\);"
    )
    text = pattern.sub(r"\1((\2 : \3);", text)
    fixed: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if (
            "return " in stripped
            and "?" in stripped
            and ":" in stripped
            and "((" in stripped
            and stripped.rstrip().endswith(";")
            and paren_balance_outside_strings(stripped) == 1
        ):
            stripped = stripped.rstrip()[:-1] + ");"
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_std_string_false_branch_concat(text: str) -> str:
    fixed: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        callee = next((name for name in ("Std.string", STRING_ARG_CALL) if f"{name}((" in stripped), "Std.string")
        start = stripped.find(f"{callee}((")
        if (start >= 0 and "?" in stripped and ":" in stripped
                and paren_balance_outside_strings(stripped) != 0):
            function_open = start + len(callee)
            inner_open = function_open + 1
            close = find_matching_right(stripped, inner_open)
            if close > inner_open:
                inner = stripped[inner_open + 1:close]
                trailing = stripped[close + 1:].strip()
                if "?" in inner and ":" in inner and trailing.startswith("+") and trailing.endswith(");"):
                    tail = trailing[:-2].strip()
                    stripped = stripped[:inner_open] + inner + " " + tail + ");"
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_malformed_equality_ternaries(text: str) -> str:
    value = rf"(?:{re.escape(AS3_HELPER)}\.index\([^)]+\)|[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)"
    text = re.sub(
        rf"(?P<lhs>{value})\s*=\(=\s*(?P<rhs>null|true|false|\"[^\"\n]*\"|'[^'\n]*'|-?\d+(?:\.\d+)?)\s*(?P<tail>\|\|)",
        r"\g<lhs> == \g<rhs> \g<tail>",
        text,
    )
    text = re.sub(
        rf"(?P<prefix>\bif\([^;\n]*?)=\(=\s*(?P<expr>\([^;\n]*\?[^;\n]*:[^;\n]*\))",
        r"\g<prefix>== \g<expr>",
        text,
    )
    text = re.sub(r"=\(=\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*\?", r"== \1 ?", text)
    text = re.sub(r"=\(=\s*(-?\d+(?:\.\d+)?)\s*\?", r"== \1 ?", text)
    return text


def fix_regex_exec_assignment_grouping(text: str) -> str:
    helper = re.escape(f"{AS3_HELPER}.re")
    fixed: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if (
            re.search(rf"(?<![=!<>])=\s*\({helper}\(", stripped)
            and ".exec(" in stripped
            and stripped.rstrip().endswith(";")
            and paren_balance_outside_strings(stripped) == 1
        ):
            stripped = re.sub(r"(?<![=!<>])=\s*\(", "= ", stripped, count=1)
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_unclosed_var_ternary_initializer(text: str) -> str:
    fixed: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if (
            re.match(
                r"\s*(?:var\s+[A-Za-z_]\w*\s*:\s*[A-Za-z_]\w*(?:<[^;\n]+>)?|"
                r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*=\s*\(",
                stripped,
            )
            and "?" in stripped
            and ":" in stripped
            and stripped.rstrip().endswith(";")
            and paren_balance_outside_strings(stripped) == 1
        ):
            stripped = stripped.rstrip()[:-1] + ");"
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_unclosed_multiline_var_ternary_initializer(text: str) -> str:
    lines = text.splitlines(keepends=True)
    fixed: list[str] = []
    statement: list[int] = []
    balance = 0
    for line in lines:
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        fixed.append(stripped + ending)
        if not statement:
            if not re.search(r"\bvar\s+[A-Za-z_]\w*\s*:\s*[A-Za-z_]\w*(?:<[^;\n]+>)?\s*=\s*\(", stripped):
                continue
            balance = 0
        statement.append(len(fixed) - 1)
        balance += paren_balance_outside_strings(stripped)
        if stripped.rstrip().endswith(";"):
            statement_text = "".join(fixed[i] for i in statement)
            if len(statement) > 1 and balance == 1 and "?" in statement_text and ":" in statement_text:
                last = fixed[statement[-1]]
                last_stripped = last.rstrip("\r\n")
                last_ending = last[len(last_stripped):]
                fixed[statement[-1]] = last_stripped[:-1] + ");" + last_ending
            statement = []
            balance = 0
    return "".join(fixed)


def fix_unclosed_multiline_return_grouping(text: str) -> str:
    lines = text.splitlines(keepends=True)
    fixed: list[str] = []
    statement: list[int] = []
    balance = 0
    for line in lines:
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        fixed.append(stripped + ending)
        if not statement:
            if not re.search(r"\breturn\s+\(", stripped):
                continue
            balance = 0
        statement.append(len(fixed) - 1)
        balance += paren_balance_outside_strings(stripped)
        if stripped.rstrip().endswith(";"):
            statement_text = "".join(fixed[i] for i in statement)
            if len(statement) > 1 and balance == 1 and ("?" in statement_text or "new " in statement_text):
                last = fixed[statement[-1]]
                last_stripped = last.rstrip("\r\n")
                last_ending = last[len(last_stripped):]
                fixed[statement[-1]] = last_stripped[:-1] + ");" + last_ending
            statement = []
            balance = 0
    return "".join(fixed)


def fix_unclosed_std_string_ternaries(text: str) -> str:
    fixed: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if (
            "Std.string((" in stripped
            and "?" in stripped
            and stripped.rstrip().endswith(";")
            and paren_balance_outside_strings(stripped) == 1
        ):
            stripped = stripped.rstrip()[:-1] + ");"
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_logical_or_ternary_helpers(text: str) -> str:
    call = f"{AS3_HELPER}.logicalOr("
    out: list[str] = []
    i = 0
    while True:
        start = text.find(call, i)
        if start < 0:
            out.append(text[i:])
            return "".join(out)
        open_paren = start + len(call) - 1
        close = find_matching_right(text, open_paren)
        if close < 0:
            out.append(text[i:])
            return "".join(out)
        inner = text[open_paren + 1:close]
        comma = find_top_level_token(inner, ",")
        question = find_top_level_token(inner, "?", comma + 1 if comma >= 0 else 0)
        colon = find_top_level_token(inner, ":", question + 1 if question >= 0 else 0)
        out.append(text[i:start])
        if comma >= 0 and question >= 0 and colon >= 0:
            left = inner[:comma].strip()
            condition = inner[comma + 1:question].strip()
            true_value = inner[question + 1:colon].strip()
            false_value = inner[colon + 1:].strip()
            if start > 0 and text[start - 1] == "(":
                out.append(f"({left} || {condition}) ? {true_value} : {false_value})")
            else:
                out.append(f"(({left} || {condition}) ? {true_value} : {false_value})")
        else:
            out.append(text[start:close + 1])
        i = close + 1


def fix_bitwise_ternary_concat_condition(text: str) -> str:
    bitwise_op = r"(?<![&|])(?:[&|^])(?![&|])"
    fixed: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if (
            "?" in stripped
            and f"{AS3_HELPER}.asType" not in stripped
            and re.search(rf"\s{bitwise_op}\s*[^)\n]+\)\s*[!=]=", stripped)
            and paren_balance_outside_strings(stripped) == -1
        ):
            stripped = re.sub(
                rf"(?P<prefix>(?<![=!<>])=\s*)"
                rf"(?P<expr>[^=;\n]*?\s{bitwise_op}\s*(?:\([^?\n]+\)|[^)\n]+))\)\s*"
                rf"(?P<op>[!=]=)\s*0(?P<tail>\s*(?:(?:&&|\|\|)[^?\n]+)?)\s*\?",
                lambda m: f"{m.group('prefix')}({m.group('expr')}) {m.group('op')} 0{m.group('tail').rstrip()} ?",
                stripped,
            )
            stripped = re.sub(
                rf"(?P<prefix>(?<![=!<>])=\s*)(?P<expr>[^=;\n]*?\s{bitwise_op}\s*[^)\n]+)\)\s*(?P<op>[!=]=)\s*0(?P<tail>\s*(?:(?:&&|\|\|)[^?\n]+)?)\s*\?",
                lambda m: f"{m.group('prefix')}({m.group('expr')}) {m.group('op')} 0{m.group('tail').rstrip()} ?",
                stripped,
            )
        if (
            "?" in stripped
            and re.search(r"=\s*\(\([^;\n]*\s[&|^]\s[^;\n]*[!=]=\s*0", stripped)
            and paren_balance_outside_strings(stripped) == 1
        ):
            stripped = re.sub(r"(?<![=!<>])=(?!=)\s*\(\(", "= (", stripped, count=1)
        if "?" in stripped and "arrayConcat(" in stripped:
            stripped = re.sub(
                rf"{re.escape(AS3_HELPER)}\.arrayConcat\(([^);\n]+);",
                rf"{AS3_HELPER}.arrayConcat(\1);",
                stripped,
            )
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_multiline_ternary_string_continuation(text: str) -> str:
    lines = text.splitlines(keepends=True)
    fixed: list[str] = []
    for index, line in enumerate(lines):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        next_stripped = lines[index + 1].lstrip() if index + 1 < len(lines) else ""
        if (
            stripped.lstrip().startswith("(")
            and "?" in stripped
            and re.search(r"\)\)\s*\+\s*$", stripped)
            and paren_balance_outside_strings(stripped) < 0
            and (next_stripped.startswith('"') or next_stripped.startswith("'"))
        ):
            stripped = re.sub(r"\)\s*\+\s*$", " +", stripped)
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_numeric_sum_string_concat(text: str) -> str:
    numeric = rf"{re.escape(AS3_HELPER)}\.to(?:Int|UInt|Float)\([^()\n]+\)"
    pattern = re.compile(rf"(\({numeric}\s*\+\s*{numeric})\s*\+\s*(\"[^\n\"]*\")")
    previous = None
    while previous != text:
        previous = text
        text = pattern.sub(r"\1) + \2", text)
    return text


def fix_nested_call_concat_closer(text: str) -> str:
    pattern = re.compile(r"(\bescape)\(([^+\n]+?\([^()\n]*\))\s*\+\s*([\"']</[\"'])")
    previous = None
    while previous != text:
        previous = text
        text = pattern.sub(r"\1(\2) + \3", text)
    return text


def fix_unclosed_multiline_assignment_concat(text: str) -> str:
    lines = text.splitlines(keepends=True)
    fixed: list[str] = []
    statement: list[int] = []
    balance = 0
    for line in lines:
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        fixed.append(stripped + ending)
        if not statement:
            if not re.search(r"=\s*\([^;\n]*\+", stripped):
                continue
            balance = 0
        statement.append(len(fixed) - 1)
        balance += paren_balance_outside_strings(stripped)
        if stripped.rstrip().endswith(";"):
            statement_text = "".join(fixed[i] for i in statement)
            if (
                len(statement) > 1
                and balance == 1
                and ("?" in statement_text or f"{AS3_HELPER}.logicalOr(" in statement_text)
                and "+" in statement_text
            ):
                last = fixed[statement[-1]]
                last_stripped = last.rstrip("\r\n")
                last_ending = last[len(last_stripped):]
                fixed[statement[-1]] = last_stripped[:-1] + ");" + last_ending
            statement = []
            balance = 0
    return "".join(fixed)


STRING_LITERAL_TEXT_RE = re.compile(r'"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'')


def fix_unclosed_multiline_call_concat(text: str) -> str:
    lines = text.splitlines(keepends=True)
    fixed: list[str] = []
    statement: list[int] = []
    balance = 0
    for line in lines:
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        fixed.append(stripped + ending)
        if not statement:
            candidate = re.search(r"\b[\w.]+\([^;\n]*\+", stripped)
            if not candidate or ("=" in stripped[:candidate.start()]):
                continue
            balance = 0
        statement.append(len(fixed) - 1)
        balance += paren_balance_outside_strings(stripped)
        code = STRING_LITERAL_TEXT_RE.sub('""', stripped)
        if re.search(r"\bfunction\s*\(", code):
            statement = []
            balance = 0
            continue
        if stripped.rstrip().endswith(";"):
            statement_text = STRING_LITERAL_TEXT_RE.sub('""', "".join(fixed[i] for i in statement))
            if (
                len(statement) > 1
                and balance == 1
                and ("?" in statement_text or f"{AS3_HELPER}.logicalOr(" in statement_text)
                and "+" in statement_text
            ):
                last = fixed[statement[-1]]
                last_stripped = last.rstrip("\r\n")
                last_ending = last[len(last_stripped):]
                fixed[statement[-1]] = last_stripped[:-1] + ");" + last_ending
            statement = []
            balance = 0
    return "".join(fixed)


def fix_ternary_bitwise_branches(text: str) -> str:
    simple = r"[A-Za-z_][\w.]*|0x[0-9A-Fa-f]+|\d+"
    pattern = re.compile(rf"\?\s*({simple})\s*([|&^])\s*({simple})\s*:")
    previous = None
    while previous != text:
        previous = text
        text = pattern.sub(r"? (\1 \2 \3) :", text)
    return text


def fix_ternary_bitwise_comparison_grouping(text: str) -> str:
    fixed: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if (
            "?" in stripped
            and ":" in stripped
            and re.search(r"\)\s*&\s*[^;\n]+\)\s*!=\s*0\s*;", stripped)
            and paren_balance_outside_strings(stripped) == -1
        ):
            stripped = re.sub(r"(?<![=!<>+\-*/%|&^])=(?!=)\s*\(", "= ((", stripped, count=1)
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_bitwise_ternary_chain_grouping(text: str) -> str:
    fixed: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if "?" in stripped and " | " in stripped:
            stripped = re.sub(
                r"(?P<prefix>(?<![=!<>])=\s*)(?P<expr>(?!\()[^;\n|]*\?[^:\n|]+:\s*[^)\n|]+)\)\s*\|",
                r"\g<prefix>(\g<expr>) |",
                stripped,
            )
            stripped = re.sub(
                r"(?P<expr>\|\s*\([^;\n]*\?[^;\n]*:[^);\n]+);$",
                r"\g<expr>);",
                stripped,
            )
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_extra_ternary_call_closer(text: str) -> str:
    fixed: list[str] = []
    open_parens = 0
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        question = stripped.find("?")
        prefix = stripped[:question] if question >= 0 else ""
        continuation = open_parens > 0
        open_parens = max(0, open_parens + paren_balance_outside_strings(stripped))
        if stripped.rstrip().endswith((";", "{", "}")):
            open_parens = 0
        if (
            not continuation
            and question >= 0
            and not stripped.lstrip().startswith("(")
            and re.match(r"\s*(?:return\s+)?[\w.]+\(", prefix)
            and stripped.rstrip().endswith("));")
            and paren_balance_outside_strings(stripped) == -1
        ):
            stripped = stripped.rstrip()[:-2] + ";"
        elif (
            ".method_4623(" in stripped
            and "?" in stripped
            and ":" in stripped
            and stripped.rstrip().endswith("));")
            and paren_balance_outside_strings(stripped) == -1
        ):
            stripped = stripped.rstrip()[:-2] + ";"
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_extra_set_index_closer(text: str) -> str:
    fixed: list[str] = []
    call = f"{AS3_HELPER}.setIndex("
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if call in stripped and stripped.rstrip().endswith("));") and paren_balance_outside_strings(stripped) == -1:
            stripped = stripped.rstrip()[:-2] + ";"
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_extra_assignment_closer(text: str) -> str:
    fixed: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if (
            re.match(r"\s*(?:var\s+)?[\w.]+(?:\s*:\s*[\w.<>]+)?(?:\[[^\]]+\])?\s*=(?!=)", stripped)
            and not re.search(rf"{re.escape(AS3_HELPER)}\.to(?:Int|UInt|Float)\([^;\n]+\)\s*%", stripped)
            and stripped.rstrip().endswith(");")
            and paren_balance_outside_strings(stripped) == -1
        ):
            stripped = stripped.rstrip()[:-2] + ";"
        elif (
            re.match(r"\s*(?:var\s+)?[\w.]+(?:\s*:\s*[\w.<>]+)?(?:\[[^\]]+\])?\s*=(?!=)", stripped)
            and "?" in stripped
            and ":" in stripped
            and not re.search(rf"{re.escape(AS3_HELPER)}\.to(?:Int|UInt|Float)\([^;\n]+\)\s*%", stripped)
            and re.search(r"\)\)(\s*[+\-*/]\s*[^;\n]+;)$", stripped)
            and paren_balance_outside_strings(stripped) == -1
        ):
            stripped = re.sub(r"\)\)(\s*[+\-*/]\s*[^;\n]+;)$", r")\1", stripped)
        elif (
            re.match(rf"\s*[\w.]+\s*\+=\s*(?:Std\.string|{re.escape(STRING_ARG_CALL)})\(", stripped)
            and "?" in stripped
            and stripped.rstrip().endswith("));")
            and paren_balance_outside_strings(stripped) == -1
        ):
            stripped = stripped.rstrip()[:-2] + ";"
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_extra_ternary_argument_closer(text: str) -> str:
    fixed: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if (
            "?" in stripped
            and ":" in stripped
            and re.search(r"\)\),\s*[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\s*;$", stripped)
        ):
            stripped = re.sub(r"\)\),(\s*[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*;$", r"),\1);", stripped)
        elif (
            fixed
            and "?" in fixed[-1]
            and ":" in fixed[-1]
            and re.search(r"\)\),\s*[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\s*;$", stripped)
        ):
            stripped = re.sub(r"\)\),(\s*[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*;$", r"),\1);", stripped)
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_extra_ternary_field_assignment_closer(text: str) -> str:
    fixed: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if (
            "?" in stripped
            and ":" in stripped
            and re.search(r"\)\.[A-Za-z_]\w*\s*=\s*(?:true|false|null|-?\d+)\);\s*$", stripped)
            and paren_balance_outside_strings(stripped) == -1
        ):
            stripped = stripped.rstrip()[:-2] + ";"
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_extra_return_ternary_closer(text: str) -> str:
    fixed: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if (
            re.match(r"\s*return\b", stripped)
            and "?" in stripped
            and stripped.rstrip().endswith("));")
            and paren_balance_outside_strings(stripped) == -1
        ):
            stripped = stripped.rstrip()[:-2] + ";"
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_return_ternary_concat_closer(text: str) -> str:
    fixed: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if re.match(r"\s*return\b", stripped) and "?" in stripped and ")) +" in stripped and paren_balance_outside_strings(stripped) == -1:
            stripped = stripped.replace(")) +", ") +", 1)
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_ternary_field_access_grouping(text: str) -> str:
    has_key_pattern = re.compile(
        r"(?P<prefix>(?<![=!<>])=(?!=)\s*|return\s+)"
        rf"(?P<expr>(?!\(){re.escape(AS3_HELPER)}\.hasKey\([^;\n]*\?[^;\n]*:[^;\n]*\))"
        r"(?P<field>\.[A-Za-z_]\w*)"
    )
    general_pattern = re.compile(
        r"(?P<prefix>(?<![=!<>])=(?!=)\s*|return\s+)"
        rf"(?P<expr>(?!\()(?!\s*{re.escape(AS3_HELPER)}\.index\()[^;\n]*\?[^;\n]*:[^;\n]*\))"
        r"(?P<field>\.[A-Za-z_]\w*)"
    )
    fixed: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if "?" in stripped and ":" in stripped and ")." in stripped and paren_balance_outside_strings(stripped) < 0:
            for pattern in (has_key_pattern, general_pattern):
                stripped = _insert_grouping_outside_strings(pattern, stripped)
        fixed.append(stripped + ending)
    return "".join(fixed)


def _mask_strings(line: str) -> str:
    return STRING_LITERAL_TEXT_RE.sub(lambda m: m.group(0)[0] + "x" * (len(m.group(0)) - 2) + m.group(0)[-1], line)


def _insert_grouping_outside_strings(pattern: re.Pattern[str], line: str) -> str:
    masked = _mask_strings(line)
    inserts = [m.end("prefix") for m in pattern.finditer(masked)]
    for at in reversed(inserts):
        line = line[:at] + "(" + line[at:]
    return line


def fix_numeric_ternary_arithmetic_grouping(text: str) -> str:
    numeric_prefix = (
        r"(?P<prefix>(?:\bvar\s+[A-Za-z_]\w*\s*:\s*(?:Float|Int|UInt)\s*|"
        r"(?<![=!<>])\b_loc\d+_\s*)=\s*)"
    )
    fixed: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if "?" in stripped and ":" in stripped:
            stripped = re.sub(
                numeric_prefix + r"\((?P<expr>[^;\n]*\?[^;\n]*:[^;\n]*?)\)\)\s*(?P<op>[+\-*/])",
                lambda m: f"{m.group('prefix')}({m.group('expr')}) {m.group('op')}"
                if m.group("expr").count("(") == m.group("expr").count(")") else m.group(0),
                stripped,
            )
            stripped = re.sub(
                numeric_prefix + r"(?P<expr>(?!\()[^;\n]*\?[^;\n]*:[^;\n]*\))\s*(?P<op>[+\-*/])",
                r"\g<prefix>(\g<expr> \g<op>",
                stripped,
            )
            stripped = re.sub(r"=\(\s+\(", "= (", stripped)
            stripped = re.sub(
                rf"({re.escape(AS3_HELPER)}\.math(?:Min|Max)\([^);\n]*);",
                r"\1);",
                stripped,
            )
            if re.search(numeric_prefix, stripped) and stripped.rstrip().endswith(";") and paren_balance_outside_strings(stripped) == 1:
                stripped = stripped.rstrip()[:-1] + ");"
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_numeric_cast_ternary_branch_grouping(text: str) -> str:
    fixed: list[str] = []
    cast_names = ("toInt", "toUInt", "toFloat")
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if "?" not in stripped or ":" not in stripped:
            fixed.append(line)
            continue
        for cast_name in cast_names:
            helper = re.escape(f"{AS3_HELPER}.{cast_name}")
            stripped = re.sub(
                rf"(?P<outer>{helper}\((?P<inner>{helper}\([^;\n?:]+?\))\))\s*"
                rf"(?P<op>[+\-])\s*(?P<rhs>[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?)\):",
                lambda m, cast_name=cast_name: (
                    f"{AS3_HELPER}.{cast_name}({m.group('inner')} "
                    f"{m.group('op')} {m.group('rhs')}):"
                ),
                stripped,
            )
        balance = paren_balance_outside_strings(stripped)
        if f"{AS3_HELPER}.to" in stripped and stripped.rstrip().endswith(";") and 0 < balance <= 2:
            stripped = stripped.rstrip()[:-1] + (")" * balance) + ";"
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_numeric_cast_division_ternary_grouping(text: str) -> str:
    helper = rf"{re.escape(AS3_HELPER)}\.to(?:Int|UInt|Float)"
    pattern = re.compile(
        rf"(?P<cast>{helper}\([^;\n]+?\))\)\s*/\s*\((?P<divisor>[^;\n]*\?[^;\n]*:[^;\n]*);"
    )
    fixed: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if "?" in stripped and ":" in stripped and ") / (" in stripped:
            stripped = pattern.sub(r"\g<cast> / (\g<divisor>);", stripped)
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_numeric_cast_shift_grouping(text: str) -> str:
    helper = rf"{re.escape(AS3_HELPER)}\.to(?:Int|UInt|Float)"
    pattern = re.compile(
        rf"(?P<cast>{helper})\((?P<expr>[^;\n]*\?[^;\n]*:[^;\n]*?)\)\)\s*"
        rf"(?P<shift>>>>|>>|<<)\s*(?P<bits>[^)\n]+)\)"
    )
    fixed: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if f"{AS3_HELPER}.to" in stripped and "?" in stripped and ":" in stripped and re.search(r"\)\)\s*(?:>>>|>>|<<)", stripped):
            stripped = pattern.sub(
                lambda m: (
                    f"{m.group('cast')}({m.group('expr')}) {m.group('shift')} "
                    f"{m.group('bits').strip()})"
                ),
                stripped,
            )
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_numeric_cast_shift_division_grouping(text: str) -> str:
    helper = rf"{re.escape(AS3_HELPER)}\.to(?:Int|UInt|Float)"
    pattern = re.compile(
        rf"(?P<cast>{helper})\(\((?P<expr>[^()\n]+)\)\)\s*(?P<shift>>>>|>>|<<)\s*"
        rf"(?P<bits>[^)\n]+)\)\)\s*/"
    )
    fixed: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if f"{AS3_HELPER}.to" in stripped and ")) /" in stripped and re.search(r">>>|>>|<<", stripped):
            stripped = pattern.sub(
                lambda m: (
                    f"{m.group('cast')}(({m.group('expr')}) {m.group('shift')} "
                    f"{m.group('bits').strip()})) /"
                ),
                stripped,
            )
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_ternary_boolean_tail_grouping(text: str) -> str:
    fixed: list[str] = []
    pattern = re.compile(
        r"(?P<prefix>(?<![=!<>])=\s*)"
        r"(?P<expr>(?!\()[^;\n]*\?[^;\n]*:[^;\n]*\))\s*"
        r"(?P<op>&&|\|\|)"
    )
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if "?" in stripped and ":" in stripped and re.search(r"\)\s*(?:&&|\|\|)", stripped):
            stripped = pattern.sub(r"\g<prefix>(\g<expr> \g<op>", stripped)
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_condition_logical_or_grouping(text: str) -> str:
    pattern = re.compile(
        rf"(?P<prefix>\bif\([^;\n]*&&\s*)"
        rf"(?P<expr>[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\s*(?:==|!=)\s*null\s*\|\|\s*"
        rf"{re.escape(AS3_HELPER)}\.toBool\()"
    )
    fixed: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if "if(" in stripped and "||" in stripped and f"{AS3_HELPER}.toBool(" in stripped and paren_balance_outside_strings(stripped) == -1:
            stripped = pattern.sub(r"\g<prefix>(\g<expr>", stripped, count=1)
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_reference_ternary_cast_grouping(text: str) -> str:
    helper = re.escape(f"{AS3_HELPER}.asType")
    text = re.sub(
        rf"(?P<prefix>\bvar\s+[A-Za-z_]\w*\s*:\s*(?P<type>[A-Za-z_]\w*)\s*=\s*)"
        rf"\({helper}\((?P<expr>[^;\n]*\?[^;\n]*:[^;\n]*?)\),\s*(?P=type)\);",
        lambda m: f"{m.group('prefix')}{AS3_HELPER}.asType({m.group('expr')}, {m.group('type')});",
        text,
    )
    return re.sub(
        rf"(?P<prefix>\bvar\s+[A-Za-z_]\w*\s*:\s*(?P<type>[A-Za-z_]\w*)\s*=\s*)"
        rf"{helper}\((?P<expr>[^;\n]*\?[^;\n]*:[^;\n]*?)\),\s*(?P=type);",
        lambda m: f"{m.group('prefix')}{AS3_HELPER}.asType({m.group('expr')}, {m.group('type')});",
        text,
    )


def find_top_level_token(text: str, token: str, start: int = 0) -> int:
    depth = 0
    i = start
    in_string: str | None = None
    while i < len(text):
        ch = text[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == in_string:
                in_string = None
            i += 1
            continue
        if ch in ("'", '"'):
            in_string = ch
            i += 1
            continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth = max(0, depth - 1)
        elif depth == 0 and text.startswith(token, i):
            return i
        i += 1
    return -1


def _cast_closes_before_argument_comma(line: str, open_index: int, end: int) -> bool:
    close = find_matching_right(line, open_index)
    return 0 <= close < end - 1 and line[close + 1:end].lstrip().startswith(",")


def fix_numeric_cast_modulo(text: str) -> str:
    pattern = re.compile(rf"{re.escape(AS3_HELPER)}\.toInt\(([^;\n]+)\)\s*%\s*([^;\n]+)\);")
    out: list[str] = []
    for line in text.splitlines(keepends=True):
        out.append(pattern.sub(
            lambda m: m.group(0)
            if m.group(1).count("(") == m.group(1).count(")") and paren_balance_outside_strings(line) == 0
            or _cast_closes_before_argument_comma(line, m.start(1) - 1, m.end(1))
            else f"{AS3_HELPER}.toInt(({m.group(1)}) % {m.group(2)});",
            line,
        ))
    return "".join(out)


def fix_unclosed_numeric_casts(text: str) -> str:
    fixed: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):]
        if (
            f"{AS3_HELPER}.toInt((" in stripped
            and stripped.rstrip().endswith(";")
            and paren_balance_outside_strings(stripped) == 1
        ):
            stripped = stripped.rstrip()[:-1] + ");"
        fixed.append(stripped + ending)
    return "".join(fixed)


def fix_early_call_close_before_concat(line: str) -> str:
    stripped = line.lstrip()
    if (
        "?" not in line
        or stripped.startswith("(")
        or stripped.startswith('"')
        or stripped.startswith("'")
        or stripped.startswith("port.")
        or paren_balance_outside_strings(line) >= 0
    ):
        return line
    pos = 0
    while True:
        match = re.search(r"\)\s*\+\s*(?=(?:['\"]|[A-Za-z_]\w*\s*\())", line[pos:])
        if not match:
            return line
        start = pos + match.start()
        end = pos + match.end()
        candidate = line[:start] + line[start + 1:]
        if (
            paren_balance_outside_strings(line[: start + 1]) <= 0
            and paren_balance_outside_strings(candidate) == 0
            and (");" in line[end:] or "]" in line[end:])
        ):
            line = candidate
            pos = max(0, start - 1)
            continue
        pos = end


def paren_balance_outside_strings(line: str) -> int:
    balance = 0
    quote = ""
    escaped = False
    for ch in line:
        if quote:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == quote:
                quote = ""
            continue
        if ch in {"'", '"'}:
            quote = ch
        elif ch == "(":
            balance += 1
        elif ch == ")":
            balance -= 1
    return balance


def output_path_for(source: Path, root: Path, version: str, output: Path) -> Path:
    game_root = root / "src" / "as3" / version / "scripts"
    platform_root = root / "src" / "platform" / "as3"
    if source.is_relative_to(game_root):
        rel = source.relative_to(game_root)
    elif source.is_relative_to(platform_root):
        rel = source.relative_to(platform_root)
    else:
        rel = source.name
    stem = std_shadow_output_stem(Path(rel))
    if stem != Path(rel).stem:
        rel = Path(rel).with_name(stem + Path(rel).suffix)
    if OBFUSCATED_CLASS_RE.fullmatch(stem):
        rel = rel.with_name(OBFUSCATED_CLASS_RE.sub(r"Class_\1", stem) + rel.suffix)
    return output / rel.with_suffix(".hx")


FILE_CACHE_DIR = ROOT / "build" / "port-haxe" / "convert-file-cache"
FILE_CACHE_KEY = ""
TREE_CLASS_NAMES = ""
TREE_INT_PARAMS = ""


def layer_int_params(root: Path) -> str:
    layer = root / "src" / "platform" / "as3"
    entries: list[str] = []
    if not layer.exists():
        return ""
    for path in sorted(layer.rglob("*.as")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for fn in re.finditer(r"\bstatic\s+function\s+([A-Za-z_]\w*)\s*\(([^()]*)\)", text):
            positions = [str(i) for i, p in enumerate(split_top_level_commas(fn.group(2)))
                         if re.search(r":\s*u?int\b", p)]
            if positions:
                entries.append(f"{path.stem}.{fn.group(1)}:{','.join(positions)}")
    return " ".join(entries)


def coerce_layer_int_arguments(span: str, own_class: str | None = None) -> str:
    if not TREE_INT_PARAMS:
        return span
    table = {}
    bare = set()
    for entry in TREE_INT_PARAMS.split():
        name, positions = entry.rsplit(":", 1)
        table[name] = {int(p) for p in positions.split(",")}
        if own_class and name.startswith(own_class + "."):
            table[name[len(own_class) + 1:]] = table[name]
            bare.add(name[len(own_class) + 1:])
    for name, positions in table.items():
        for call in reversed(list(re.finditer(rf"(?<![\w.])(?<!function ){re.escape(name)}\s*\(", span))):
            close = find_matching_right(span, call.end() - 1)
            if close < 0:
                continue
            args = split_top_level_commas(span[call.end():close])
            changed = False
            for i in positions:
                if i >= len(args):
                    continue
                arg = args[i].strip()
                if not arg or re.fullmatch(r"-?\d+|0x[0-9A-Fa-f]+", arg) or arg.startswith(
                        (f"{AS3_HELPER}.toInt(", f"{AS3_HELPER}.toUInt(", "int(", "uint(")) and \
                        find_matching_right(arg, arg.index("(")) == len(arg) - 1:
                    continue
                if name in bare and not re.search(r"(?<![/*])/(?![/*])|\bMath\.", arg):
                    continue
                lead = args[i][:len(args[i]) - len(args[i].lstrip())]
                if "?" in arg and not (arg.startswith("(") and find_matching_right(arg, 0) == len(arg) - 1):
                    arg = f"({arg})"
                args[i] = f"{lead}{AS3_HELPER}.toInt({arg})"
                changed = True
            if changed:
                span = span[:call.end()] + ",".join(args) + span[close:]
    return span


TREE_STRING_PARAMS = ""


def tree_string_params(sources) -> str:
    found: dict[str, str] = {}
    for path in sorted(Path(p) for p in sources):
        text = path.read_text(encoding="utf-8", errors="replace")
        for fn in re.finditer(r"\bstatic\s+function\s+([A-Za-z_]\w*)\s*\(([^()]*)\)", text):
            positions = ",".join(str(i) for i, p in enumerate(split_top_level_commas(fn.group(2)))
                                 if re.search(r":\s*String\b", p))
            if not positions:
                continue
            name = f"{path.stem}.{fn.group(1)}"
            found[name] = positions if found.get(name, positions) == positions else ""
    return " ".join(f"{name}:{positions}" for name, positions in sorted(found.items()) if positions)


def coerce_string_parameter_arguments(span: str) -> str:
    if not TREE_STRING_PARAMS:
        return span
    for entry in TREE_STRING_PARAMS.split():
        name, positions = entry.rsplit(":", 1)
        owner, method = name.rsplit(".", 1)
        wanted = {int(p) for p in positions.split(",")}
        spellings = {owner, OBFUSCATED_CLASS_RE.sub(r"Class_\1", owner)} if OBFUSCATED_CLASS_RE.fullmatch(owner) else {owner}
        for spelling in spellings:
            needle = f"{spelling}.{method}"
            if needle not in span:
                continue
            for call in reversed(list(re.finditer(rf"(?<![\w.]){re.escape(needle)}\s*\(", span))):
                close = find_matching_right(span, call.end() - 1)
                if close < 0:
                    continue
                args = split_top_level_commas(span[call.end():close])
                changed = False
                for i in wanted:
                    if i >= len(args):
                        continue
                    arg = args[i].strip()
                    if (not arg or arg == "null" or arg.startswith(('"', "'", f"{AS3_HELPER}.stringParam(",
                                                                     f"{AS3_HELPER}.coerceString("))
                            or re.fullmatch(r"__AS3_NONCODE_\d+__", arg) or is_string_led_concatenation(arg)):
                        continue
                    lead = args[i][:len(args[i]) - len(args[i].lstrip())]
                    trail = args[i][len(args[i].rstrip()):]
                    args[i] = f"{lead}{AS3_HELPER}.stringParam({arg}){trail}"
                    changed = True
                if changed:
                    span = span[:call.end()] + ",".join(args) + span[close:]
            if 0 not in wanted:
                continue
            for ref in reversed(list(re.finditer(
                    rf"(\.(?:map|filter|forEach|some|every)\s*\(\s*){re.escape(needle)}(\s*\))", span))):
                wrapper = f"function(v:Dynamic):Dynamic return {needle}({AS3_HELPER}.stringParam(v))"
                span = span[:ref.start()] + ref.group(1) + wrapper + ref.group(2) + span[ref.end():]
    return span


def file_cache_key() -> str:
    digest = hashlib.sha256()
    digest.update(Path(__file__).read_bytes())
    for table in (FIELD_INIT_ORDER_PATH, HOISTED_LOCALS_PATH, TEMP_RECEIVERS_PATH, ELEMENT_TYPES_PATH):
        digest.update(table.read_bytes() if table.exists() else b"<missing>")
    digest.update(repr(sorted((k, v) for k, v in _convert_state().items() if k != "FILE_CACHE_KEY")).encode("utf-8"))
    if RECOVERED_METHODS_DIR.exists():
        for path in sorted(RECOVERED_METHODS_DIR.rglob("*")):
            if path.is_file():
                digest.update(path.as_posix().encode("utf-8") + path.read_bytes())
    for path in iter_as_files(ROOT, VERSION):
        stat = path.stat()
        digest.update(f"{path.as_posix()}|{stat.st_size}|{stat.st_mtime_ns}".encode("utf-8"))
    return digest.hexdigest()


def convert_file(source: Path, root: Path, version: str, output: Path) -> ConvertStats:
    text = rename_shadowing_private_fields(source, source.read_text(encoding="utf-8", errors="replace"))
    text = qualify_inherited_statics(source, text)
    text = hoist_block_vars_used_after(source, text)
    cached = None
    if FILE_CACHE_KEY:
        import pickle
        key = hashlib.sha256((FILE_CACHE_KEY + "|" + source.as_posix() + "|").encode("utf-8")
                             + text.encode("utf-8")).hexdigest()
        cached = FILE_CACHE_DIR / key[:2] / f"{key}.pickle"
        if cached.exists():
            try:
                converted, stats, raw = pickle.loads(cached.read_bytes())
            except Exception:
                converted = None
            if converted is not None:
                RAW_STATS.files += raw[0]
                RAW_STATS.marked_lines += raw[1]
                RAW_STATS.imports += raw[2]
                target = output_path_for(source, root, version, output)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(converted, encoding="utf-8", newline="\n")
                return stats
    before = (RAW_STATS.files, RAW_STATS.marked_lines, RAW_STATS.imports)
    stats = _convert_file_text(source, text, root, version, output)
    if cached is not None:
        import pickle
        target = output_path_for(source, root, version, output)
        raw = (RAW_STATS.files - before[0], RAW_STATS.marked_lines - before[1], RAW_STATS.imports - before[2])
        cached.parent.mkdir(parents=True, exist_ok=True)
        cached.write_bytes(pickle.dumps((target.read_text(encoding="utf-8"), stats, raw)))
    return stats


AS3_FIELD_RE = re.compile(r"(?m)^\s*(?:override\s+)?(?P<access>private|protected|public|internal)\s+(?:static\s+)?"
                          r"(?:var|const)\s+(?P<name>[A-Za-z_]\w*)")


def _as3_class_file(source: Path, text: str, name: str) -> Path | None:
    package = re.search(r"\bpackage\s+([\w.]*)", text)
    depth = len(package.group(1).split(".")) if package and package.group(1) else 0
    base = source.parent
    for _ in range(depth):
        base = base.parent
    imported = re.search(rf"\bimport\s+([\w.]+)\.{re.escape(name)}\s*;", text)
    candidate = (base.joinpath(*imported.group(1).split("."), f"{name}.as") if imported
                 else source.parent / f"{name}.as")
    return candidate if candidate.exists() else None


AS3_UNSET_VALUES = {"Number": "NaN", "int": "0", "uint": "0", "Boolean": "false"}


def hoist_block_vars_used_after(source: Path, text: str) -> str:
    if "/platform/" not in source.as_posix():
        return text
    code, protected = protect_noncode(text)
    edits: list[tuple[int, int, str]] = []
    for header in re.finditer(r"\bfunction\s+(?:get\s+|set\s+)?[A-Za-z_]\w*\s*\([^)]*\)\s*(?::\s*[\w.*<>]+)?\s*\{",
                              code):
        body_open = header.end() - 1
        body_close = find_matching_right(code, body_open)
        if body_close < 0:
            continue
        body = code[body_open:body_close + 1]
        literals = [(m.start(), find_matching_right(body, body.find("{", m.end())))
                    for m in re.finditer(r"\bfunction\s*\([^)]*\)\s*(?::\s*[\w.*<>]+)?\s*(?=\{)", body)]
        hoisted: dict[str, str] = {}
        for decl in re.finditer(r"\bvar\s+([A-Za-z_]\w*)\s*:\s*([\w.*]+(?:\.<[^>]*>)?)", body):
            if re.search(r"\bfor\s*(?:each\s*)?\(\s*$", body[:decl.start()]):
                continue
            if any(start < decl.start() < end for start, end in literals):
                continue
            depth, block_start = 0, -1
            for i in range(decl.start() - 1, 0, -1):
                if body[i] == "}":
                    depth += 1
                elif body[i] == "{":
                    if depth == 0:
                        block_start = i
                        break
                    depth -= 1
            if block_start <= 0:
                continue
            block_end = find_matching_right(body, block_start)
            name = decl.group(1)
            if block_end > 0 and re.search(rf"(?<![\w.]){re.escape(name)}\b", body[block_end:]):
                hoisted.setdefault(name, decl.group(2))
        if not hoisted:
            continue
        for decl in re.finditer(r"\bvar\s+([A-Za-z_]\w*)\s*:\s*[\w.*]+(?:\.<[^>]*>)?(\s*=)?", body):
            if any(start < decl.start() < end for start, end in literals):
                continue
            if decl.group(1) in hoisted:
                replacement = decl.group(1) + (decl.group(2) or "")
                if not decl.group(2):
                    semi = body.find(";", decl.end())
                    edits.append((body_open + decl.start(), body_open + semi + 1, ""))
                    continue
                edits.append((body_open + decl.start(), body_open + decl.end(), replacement))
        indent = re.search(r"([ \t]*)[^\n]*\Z", code[:header.start()]).group(1)
        top = "".join(f"\n{indent}   var {n}:{t} = {AS3_UNSET_VALUES.get(t, 'null')};" for n, t in hoisted.items())
        edits.append((body_open + 1, body_open + 1, top))
    for start, end, replacement in sorted(edits, key=lambda e: (e[0], e[1]), reverse=True):
        code = code[:start] + replacement + code[end:]
    return restore_noncode(code, protected)


def qualify_inherited_statics(source: Path, text: str) -> str:
    own = re.search(r"\bclass\s+(?P<name>[A-Za-z_]\w*)\s+extends\s+(?P<base>[A-Za-z_]\w*)", text)
    if own is None or "/platform/" not in source.as_posix():
        return text
    declared = {m.group("name") for m in AS3_FIELD_RE.finditer(text)}
    declared |= set(re.findall(r"\bfunction\s+(?:get\s+|set\s+)?([A-Za-z_]\w*)", text))
    declared |= set(re.findall(r"\bvar\s+([A-Za-z_]\w*)", text))
    declared |= set(re.findall(r"[(,]\s*([A-Za-z_]\w*)\s*:", text))
    statics: dict[str, str] = {}
    path, base_text, base = source, text, own.group("base")
    for _ in range(8):
        path = _as3_class_file(path, base_text, base)
        if path is None or "/platform/" not in path.as_posix():
            break
        base_text = path.read_text(encoding="utf-8", errors="replace")
        package = re.search(r"\bpackage\s+([\w.]+)", base_text)
        qualified = f"{package.group(1)}.{base}" if package else base
        for m in re.finditer(r"\bstatic\s+(?:const|var|function)\s+([A-Za-z_]\w*)", base_text):
            statics.setdefault(m.group(1), qualified)
        parent = re.search(rf"\bclass\s+{re.escape(base)}\s+extends\s+([A-Za-z_]\w*)", base_text)
        if parent is None:
            break
        base = parent.group(1)
    names = {n: b for n, b in statics.items() if n not in declared}
    if not names:
        return text
    code, protected = protect_noncode(text)
    pattern = re.compile(rf"(?<![\w.$])({'|'.join(sorted(map(re.escape, names), key=len, reverse=True))})\b(?!\s*:)")
    code = pattern.sub(lambda m: f"{names[m.group(1)]}.{m.group(1)}", code)
    return restore_noncode(code, protected)


_SUBCLASS_SCAN: dict[str, dict[str, set[str]]] = {}


def _subclass_members(folder: Path, cls: str) -> set[str]:
    root = next((p for p in (folder, *folder.parents) if p.name == "as3"), folder)
    key = str(root)
    if key not in _SUBCLASS_SCAN:
        table: dict[str, set[str]] = {}
        for path in root.rglob("*.as"):
            text = path.read_text(encoding="utf-8", errors="replace")
            found = re.search(r"\bclass\s+[A-Za-z_]\w*\s+extends\s+([A-Za-z_]\w*)", text)
            if found:
                members = {m.group("name") for m in AS3_FIELD_RE.finditer(text)}
                members |= set(re.findall(r"\bfunction\s+(?:get\s+|set\s+)?([A-Za-z_]\w*)", text))
                table.setdefault(found.group(1), set()).update(members)
        _SUBCLASS_SCAN[key] = table
    return _SUBCLASS_SCAN[key].get(cls, set())


def rename_shadowing_private_fields(source: Path, text: str) -> str:
    own = re.search(r"\bclass\s+(?P<name>[A-Za-z_]\w*)(?:\s+extends\s+(?P<base>[A-Za-z_]\w*))?", text)
    if own is None or "/platform/" not in source.as_posix():
        return text
    inherited: set[str] = set()
    path, base_text, base = source, text, own.group("base")
    for _ in range(8 if base else 0):
        path = _as3_class_file(path, base_text, base)
        if path is None:
            break
        base_text = path.read_text(encoding="utf-8", errors="replace")
        inherited |= {m.group("name") for m in AS3_FIELD_RE.finditer(base_text)}
        parent = re.search(rf"\bclass\s+{re.escape(base)}\s+extends\s+([A-Za-z_]\w*)", base_text)
        if parent is None:
            break
        base = parent.group(1)
    privates = {m.group("name") for m in AS3_FIELD_RE.finditer(text) if m.group("access") == "private"}
    names = (privates & inherited) | (privates & _subclass_members(source.parent, own.group("name")))
    if not names:
        return text
    cls = own.group("name")
    code, protected = protect_noncode(text)
    typed_locals = set(re.findall(rf"\b([A-Za-z_]\w*)\s*:\s*{re.escape(cls)}\b", code)) | {"this"}
    receivers = "|".join(sorted(map(re.escape, typed_locals)))
    for name in sorted(names):
        renamed = f"{name}_{cls}"
        def repl(m: re.Match[str], renamed: str = renamed) -> str:
            if not m.group(1) and re.match(r"\s*:", code[m.end():]) and re.search(r"[{,]\s*$", code[:m.start()]) \
                    and not re.search(r"\bfunction\s+\w*\s*\([^)]*$", code[max(0, m.start() - 300):m.start()]):
                return m.group(0)
            return f"{m.group(1) or ''}{renamed}"

        code = re.sub(rf"(?<![\w.])((?:{receivers})\s*\.\s*)?{re.escape(name)}\b", repl, code)
    return restore_noncode(code, protected)


def _convert_file_text(source: Path, text: str, root: Path, version: str, output: Path) -> ConvertStats:
    if RAW:
        text, marked, imports = strip_platform_lines(text, source.as_posix())
        if marked or imports:
            RAW_STATS.files += 1
            RAW_STATS.marked_lines += marked
            RAW_STATS.imports += imports
    converted, stats = convert_text(text, source.as_posix())
    target = output_path_for(source, root, version, output)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(converted, encoding="utf-8", newline="\n")
    return stats


def copy_runtime_sources(root: Path, output: Path) -> list[Path]:
    runtime = ROOT / "port" / "runtime" / "haxe"
    copied: list[Path] = []
    if not runtime.exists():
        return copied
    for source in sorted(runtime.rglob("*.hx")):
        rel = source.relative_to(runtime)
        target = output / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(source.read_text(encoding="utf-8"), encoding="utf-8", newline="\n")
        copied.append(target)
    return copied


def render_summary(stats: ConvertStats) -> str:
    lines = [f"{stats.files} files converted"]
    if stats.unsupported:
        lines.append("unsupported constructs:")
        for name, count in stats.unsupported.most_common():
            lines.append(f"  {name}: {count}")
    else:
        lines.append("unsupported constructs: none found")
    return "\n".join(lines)


CONVERT_KEY_FILE = ".convert-key"


def convert_cache_key(sources: list[Path]) -> str:
    digest = hashlib.sha256()

    def add(label: str, data: bytes) -> None:
        digest.update(label.encode("utf-8") + b"\0" + hashlib.sha256(data).digest())

    add("converter", Path(__file__).read_bytes())
    for table in (FIELD_INIT_ORDER_PATH, HOISTED_LOCALS_PATH, TEMP_RECEIVERS_PATH, ELEMENT_TYPES_PATH):
        add(table.name, table.read_bytes() if table.exists() else b"<missing>")
    add("flags", repr((RAW, ELEMENT_TYPED_CONTAINERS, UNINIT_HOISTED_LOCALS)).encode("utf-8"))
    if RECOVERED_METHODS_DIR.exists():
        for path in sorted(RECOVERED_METHODS_DIR.rglob("*")):
            if path.is_file():
                add(path.relative_to(RECOVERED_METHODS_DIR).as_posix(), path.read_bytes())
    for path in sources:
        add(path.as_posix(), path.read_bytes())
    return digest.hexdigest()


CONVERT_WORKERS_ENV = "PORT_CONVERT_WORKERS"


def convert_workers(files: int) -> int:
    import os
    wanted = os.environ.get(CONVERT_WORKERS_ENV, "")
    count = int(wanted) if wanted.isdigit() else min(12, max(1, (os.cpu_count() or 2) - 2))
    return 1 if files < 50 else max(1, count)


def _convert_state() -> dict:
    return {name: value for name, value in globals().items()
            if not name.startswith("__") and isinstance(value, (bool, int, float, str, type(None)))}


def _convert_worker_init(state: dict) -> None:
    globals().update(state)
    if VERSION != "10.11":
        use_version(VERSION)


def version_build_dir(version: str) -> Path:
    return ROOT / "build" / "port-haxe" / version


def use_version(version: str) -> None:
    global VERSION, FIELD_INIT_ORDER_PATH, HOISTED_LOCALS_PATH, TEMP_RECEIVERS_PATH, ELEMENT_TYPES_PATH
    global RECOVERED_METHODS_DIR, _HOISTED_LOCALS, _TEMP_RECEIVERS, _ELEMENT_TYPES, _FIELD_INIT_ORDER, _UINT_MEMBERS
    tables = version_build_dir(version)
    paths = (tables / "field-init-order.json", tables / "hoisted-locals.json", tables / "temp-receivers.json",
             tables / "element-types.json")
    if version != VERSION:
        _HOISTED_LOCALS = _TEMP_RECEIVERS = _ELEMENT_TYPES = _FIELD_INIT_ORDER = _UINT_MEMBERS = None
    VERSION = version
    FIELD_INIT_ORDER_PATH, HOISTED_LOCALS_PATH, TEMP_RECEIVERS_PATH, ELEMENT_TYPES_PATH = paths
    global DEOBFUSCATED_CLASSES
    DEOBFUSCATED_CLASSES = ""
    names = ROOT / "build" / "version-names" / f"10.11_to_{version}.json"
    if version != "10.11" and names.exists():
        carried = json.loads(names.read_text(encoding="utf-8"))["carried"]
        DEOBFUSCATED_CLASSES = " ".join(sorted(
            new for old, new in carried.items() if old.startswith("class_") and not re.fullmatch(r"class_\d+", new)))
    RECOVERED_METHODS_DIR = ROOT / "src" / "as3-recovered" / version


def _convert_one(job: tuple[str, str, str, str]) -> tuple[ConvertStats, tuple[int, int, int]]:
    source, root, version, output = job
    before = (RAW_STATS.files, RAW_STATS.marked_lines, RAW_STATS.imports)
    stats = convert_file(Path(source), Path(root), version, Path(output))
    return stats, (RAW_STATS.files - before[0], RAW_STATS.marked_lines - before[1], RAW_STATS.imports - before[2])


def convert_parallel(sources: list, root: Path, version: str, output: Path, workers: int,
                     stats: ConvertStats) -> None:
    from concurrent.futures import ProcessPoolExecutor
    jobs = [(str(source), str(root), version, str(output)) for source in sources]
    with ProcessPoolExecutor(max_workers=workers, initializer=_convert_worker_init,
                             initargs=(_convert_state(),)) as pool:
        for file_stats, raw in pool.map(_convert_one, jobs, chunksize=8):
            stats.add(file_stats)
            RAW_STATS.files += raw[0]
            RAW_STATS.marked_lines += raw[1]
            RAW_STATS.imports += raw[2]


def command_convert(args: argparse.Namespace) -> int:
    root = args.root.resolve()
    output = args.output if args.output.is_absolute() else root / args.output
    key = None
    if not args.file and not args.no_cache:
        key = convert_cache_key(iter_as_files(root, args.version))
        stamp = output / CONVERT_KEY_FILE
        if stamp.exists() and stamp.read_text(encoding="utf-8").strip() == key:
            copied = copy_runtime_sources(root, output)
            print(f"conversion cache hit ({key[:12]}): {output} is current; {len(copied)} runtime helpers copied")
            return 0
    if not args.file and output.exists():
        try:
            output.relative_to(root / "build")
        except ValueError:
            raise ValueError(f"refusing to clear output outside build/: {output}")
        shutil.rmtree(output)
    stats = ConvertStats()
    sources = [args.file] if args.file else iter_as_files(root, args.version)
    global FILE_CACHE_KEY, TREE_CLASS_NAMES
    TREE_CLASS_NAMES = " ".join(sorted({Path(source).stem for source in iter_as_files(root, args.version)
                                        if Path(source).stem[:1].isupper()}))
    global TREE_INT_PARAMS
    TREE_INT_PARAMS = layer_int_params(root)
    global TREE_STRING_PARAMS
    TREE_STRING_PARAMS = tree_string_params(iter_as_files(root, args.version))
    FILE_CACHE_KEY = "" if args.file or args.no_cache else file_cache_key()
    workers = convert_workers(len(sources))
    if workers > 1:
        convert_parallel(sources, root, args.version, output, workers, stats)
    else:
        for source in sources:
            stats.add(convert_file(Path(source), root, args.version, output))
    copied = copy_runtime_sources(root, output)
    if key is not None:
        (output / CONVERT_KEY_FILE).write_text(key + "\n", encoding="utf-8")
    print(render_summary(stats))
    if RAW:
        print(f"raw game: {RAW_STATS.marked_lines} marked platform lines and {RAW_STATS.imports} platform imports"
              f" removed from {RAW_STATS.files} files; no src/platform, no bh/ tree")
    if copied:
        print(f"runtime helpers: {len(copied)} files")
    print(f"output: {output.relative_to(root) if output.is_relative_to(root) else output}")
    return 0


def command_summary(args: argparse.Namespace) -> int:
    root = args.root.resolve()
    stats = ConvertStats()
    for source in iter_as_files(root, args.version):
        text = source.read_text(encoding="utf-8", errors="replace")
        _, file_stats = convert_text(text, source.as_posix())
        stats.add(file_stats)
    print(render_summary(stats))
    return 0


def command_check(args: argparse.Namespace) -> int:
    root = args.root.resolve()
    paths = iter_as_files(root, args.version)
    if not paths:
        print(f"no AS3 files found for {args.version}", file=sys.stderr)
        return 1
    stats = ConvertStats()
    for source in paths:
        text = source.read_text(encoding="utf-8", errors="replace")
        converted, file_stats = convert_text(text, source.as_posix())
        stats.add(file_stats)
        if not converted.startswith("package"):
            print(f"{source}: converted file does not start with a Haxe package declaration", file=sys.stderr)
            return 1
    print(render_summary(stats))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("convert", "summary", "check"))
    parser.add_argument("--version", default="10.11")
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--file", type=Path, help="convert only one AS3 file")
    parser.add_argument("--native", action="store_true",
                        help="native-target tree: containers keep the AS3 source's ``Array<Dynamic>`` (no element "
                             "types restored for Flash bytecode parity; on HashLink ``Array<T>`` and "
                             "``Array<Dynamic>`` are different runtime objects)")
    parser.add_argument("--no-cache", action="store_true",
                        help="convert even when the output's conversion key matches (see convert_cache_key)")
    parser.add_argument("--raw", action="store_true",
                        help="the base raw game: no src/platform, no bh/ tree, the AIR build's marked hook lines and "
                             "platform imports removed (the engine port's tree, owner 2026-10-15)")
    args = parser.parse_args(argv)
    global ELEMENT_TYPED_CONTAINERS, RAW, RAW_STATS
    if args.version != VERSION:
        use_version(args.version)
    ELEMENT_TYPED_CONTAINERS = not args.native
    RAW = args.raw
    RAW_STATS = RawStats()
    if args.command == "convert":
        return command_convert(args)
    if args.command == "summary":
        return command_summary(args)
    return command_check(args)


if __name__ == "__main__":
    raise SystemExit(main())
