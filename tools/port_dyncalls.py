from __future__ import annotations

import re
from pathlib import Path

INDEX_CALL = "port.runtime.As3.index("
ASOBJECT_CALL = "port.runtime.As3.asObject("
FUNCTION_RE = re.compile(r"\bfunction\s+(\w+)\s*(?:<[^>]*>)?\s*\(")
PROPERTY_RE = re.compile(r"\bvar\s+(\w+)\s*\(\s*(\w+)\s*,\s*(\w+)\s*\)")
MEMBER_RE = re.compile(r"\.([A-Za-z_]\w*)")
ASSIGN_RE = re.compile(r"\s*=(?!=)")
DYNAMIC_LOCAL_RE = re.compile(r"\bvar\s+(_loc\d+_|_temp_\d+)\s*:\s*Dynamic\b")
ANY_DYNAMIC_LOCAL_RE = re.compile(r"\bvar\s+([A-Za-z_]\w*)\s*:\s*Dynamic\b")
DYNAMIC_FIELD_RE = re.compile(r"\b(?:private|public|protected)\s+(?:static\s+)?var\s+([A-Za-z_]\w*)\s*:\s*Dynamic\b")
DECLARED_RE = re.compile(r"\bvar\s+([A-Za-z_]\w*)\b")
PARAM_NAME_RE = re.compile(r"(?:^|[(,])\s*\??([A-Za-z_]\w*)\s*[:=,)]")
DYNAMIC_PARAM_RE = re.compile(r"(?:^|[(,])\s*\??([A-Za-z_]\w*)\s*:\s*Dynamic\b")
ANY_FUNCTION_RE = re.compile(r"\bfunction\b\s*(?:\w+)?\s*(?:<[^>]*>)?\s*\(")
RETURN_TYPE_RE = re.compile(r"\s*(?::\s*[\w.<>, ]+)?\s*")
COMPOUND_RE = re.compile(r"\s*(?:[-+*/%&|^]|<<|>>>?)=|\s*(?:\+\+|--)")

BUILTIN_ARITY = {
    "slice": 2, "indexOf": 2, "lastIndexOf": 2, "substr": 2, "substring": 2, "join": 1,
    "filter": 2, "map": 2, "forEach": 2, "some": 2, "every": 2,
    "gotoAndStop": 2, "gotoAndPlay": 2, "removeChildren": 2,
    "addEventListener": 5, "removeEventListener": 3, "hitTestPoint": 3, "startDrag": 2, "setTextFormat": 3,
    "beginFill": 2, "lineStyle": 8, "drawRoundRect": 6, "beginGradientFill": 8, "lineGradientStyle": 8,
    "beginBitmapFill": 4,
    "getCachedSamples": 2,
}


def _skip_string(text: str, i: int) -> int:
    quote = text[i]
    i += 1
    while i < len(text) and text[i] != quote:
        i += 2 if text[i] == "\\" else 1
    return i + 1


def matching_paren(text: str, open_at: int) -> int:
    depth = 0
    i = open_at
    while i < len(text):
        c = text[i]
        if c in "\"'":
            i = _skip_string(text, i)
            continue
        if c == "/" and text.startswith("//", i):
            end = text.find("\n", i)
            i = len(text) if end < 0 else end
            continue
        if c == "/" and text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = len(text) if end < 0 else end + 2
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError(f"unbalanced bracket at {open_at}")


def split_args(inner: str) -> list[str]:
    if not inner.strip():
        return []
    args, depth, start, i = [], 0, 0, 0
    while i < len(inner):
        c = inner[i]
        if c in "\"'":
            i = _skip_string(inner, i)
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            args.append(inner[start:i])
            start = i + 1
        i += 1
    args.append(inner[start:])
    return args


def expression_end(text: str, i: int) -> int:
    depth = 0
    while i < len(text):
        c = text[i]
        if c in "\"'":
            i = _skip_string(text, i)
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                return i
            depth -= 1
        elif c in ";," and depth == 0:
            return i
        i += 1
    return i


def method_arity(sources: list[str]) -> dict[str, int]:
    arity = Arity(BUILTIN_ARITY)
    for text in sources:
        for match in FUNCTION_RE.finditer(text):
            open_at = match.end() - 1
            try:
                close = matching_paren(text, open_at)
            except ValueError:
                continue
            count = len(split_args(text[open_at + 1:close - 1]))
            name = match.group(1)
            if count > arity.get(name, -1):
                arity[name] = count
    return arity


def accessor_properties(sources: list[str]) -> set[str]:
    names = set()
    for text in sources:
        for match in PROPERTY_RE.finditer(text):
            if "get" in match.group(2, 3) or "set" in match.group(2, 3):
                names.add(match.group(1))
    return names


HL_MAX_ARGS = 9


def too_many_args(passed: int, declared: int) -> bool:
    return max(passed, declared) + 1 > HL_MAX_ARGS


class Arity(dict):

    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.owners: dict[str, str] = {}


def method_owners(texts: dict[Path, str], target: Path) -> dict[str, str]:
    found: dict[str, set[str]] = {}
    for path, text in texts.items():
        module = ".".join(path.relative_to(target).with_suffix("").parts)
        for match in FUNCTION_RE.finditer(text):
            found.setdefault(match.group(1), set()).add(module)
    return {name: next(iter(mods)) for name, mods in found.items() if len(mods) == 1}


class Counts:
    def __init__(self) -> None:
        self.calls = 0
        self.typed = 0
        self.reads = 0
        self.writes = 0
        self.compound = 0
        self.catches = 0
        self.untyped = 0

    def total(self) -> int:
        return self.calls + self.reads + self.writes + self.typed


def rewrite(text: str, arity: dict[str, int], props: set[str] | None = None,
            counts: Counts | None = None, named: bool = False,
            expandos: frozenset[str] = frozenset()) -> tuple[str, int]:
    props = props or set()
    counts = counts or Counts()
    before = counts.total()
    for receiver in (INDEX_CALL, ASOBJECT_CALL) if named else (INDEX_CALL,):
        pos = len(text)
        while True:
            start = text.rfind(receiver, 0, pos)
            if start < 0:
                break
            pos = start
            end = matching_paren(text, start + len(receiver) - 1)
            text = _rewrite_chain(text, start, end, arity, props, counts, expandos)
    text = _rewrite_dynamic_locals(text, arity, props, counts, named, expandos)
    text = _rewrite_event_targets(text, arity, props, counts, expandos)
    if named:
        text = _rewrite_dynamic_returns(text, arity, props, counts, expandos)
    return text, counts.total() - before


DYNAMIC_RETURN_RE = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\([^)]*\)\s*:\s*Dynamic\b")


def _rewrite_dynamic_returns(text: str, arity: dict[str, int], props: set[str], counts: Counts,
                             expandos: frozenset[str] = frozenset()) -> str:
    names = set(DYNAMIC_RETURN_RE.findall(text))
    if not names:
        return text
    call = re.compile(r"(?<![\w.$])(?:" + "|".join(sorted(names)) + r")\(")
    mask = code_mask(text)
    for found in reversed(list(call.finditer(mask))):
        try:
            end = matching_paren(text, found.end() - 1)
        except ValueError:
            continue
        if re.match(r"\.[A-Za-z_]", text[end:end + 2]):
            text = _rewrite_chain(text, found.start(), end, arity, props, counts, expandos)
    return text


EVENT_TARGET_RE = re.compile(r"(?<![\w.$])[A-Za-z_]\w*\.(?:currentTarget|target)(?=\.[A-Za-z_])")


def _rewrite_event_targets(text: str, arity: dict[str, int], props: set[str], counts: Counts,
                           expandos: frozenset[str] = frozenset()) -> str:
    mask = code_mask(text)
    for found in reversed(list(EVENT_TARGET_RE.finditer(mask))):
        text = _rewrite_chain(text, found.start(), found.end(), arity, props, counts, expandos)
    return text


def _rewrite_dynamic_locals(text: str, arity: dict[str, int], props: set[str], counts: Counts,
                            named: bool = False, expandos: frozenset[str] = frozenset()) -> str:
    spans = []
    for match in (ANY_FUNCTION_RE if named else FUNCTION_RE).finditer(text):
        try:
            close = matching_paren(text, match.end() - 1)
        except ValueError:
            continue
        open_at = text.find("{", close)
        if open_at < 0 or not RETURN_TYPE_RE.fullmatch(text, close, open_at):
            continue
        try:
            spans.append([open_at, matching_paren(text, open_at), text[match.end() - 1:close]])
        except ValueError:
            continue
    spans.sort(key=lambda s: s[0], reverse=True)
    fields = set(DYNAMIC_FIELD_RE.findall(text)) if named else set()
    for index, (body_start, body_end, params) in enumerate(spans):
        body = text[body_start:body_end]
        if named:
            names = set(ANY_DYNAMIC_LOCAL_RE.findall(body)) | set(DYNAMIC_PARAM_RE.findall(params))
            shadowed = set(DECLARED_RE.findall(body)) | set(PARAM_NAME_RE.findall(params))
            names |= fields - (shadowed - names)
        else:
            names = set(DYNAMIC_LOCAL_RE.findall(body))
        if named:
            body = _rewrite_negations(body, names, counts)
        if not names:
            if named:
                delta = len(body) - (body_end - body_start)
                if delta:
                    for outer in spans[index + 1:]:
                        if outer[0] < body_start and outer[1] >= body_end:
                            outer[1] += delta
                text = text[:body_start] + body + text[body_end:]
            continue
        local = re.compile(r"(?<![\w.$])(" + "|".join(sorted(names)) + r")(?=\.[A-Za-z_])")
        mask = code_mask(body) if named else body
        pos = len(body)
        while True:
            found = None
            for m in local.finditer(mask, 0, pos):
                found = m
            if found is None:
                break
            pos = found.start()
            if body[:found.start()].rstrip().endswith(("++", "--")):
                counts.compound += 1
                continue
            body = _rewrite_chain(body, found.start(), found.end(), arity, props, counts, expandos)
        if named:
            body = _rewrite_local_calls(body, names, counts)
        delta = len(body) - (body_end - body_start)
        if delta:
            for outer in spans[index + 1:]:
                if outer[0] < body_start and outer[1] >= body_end:
                    outer[1] += delta
        text = text[:body_start] + body + text[body_end:]
    return text


def code_mask(text: str) -> str:
    out = list(text)
    i = 0
    while i < len(text):
        c = text[i]
        if c in "\"'":
            end = min(_skip_string(text, i), len(text))
            for k in range(i + 1, end - 1):
                out[k] = " "
            i = end
        elif text.startswith("//", i):
            end = text.find("\n", i)
            end = len(text) if end < 0 else end
            for k in range(i, end):
                out[k] = " "
            i = end
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            end = len(text) if end < 0 else end + 2
            for k in range(i, end):
                if out[k] != "\n":
                    out[k] = " "
            i = end
        else:
            i += 1
    return "".join(out)


CHAIN_HEAD_RE = re.compile(r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*")


def _chain_end(text: str, start: int) -> int:
    m = CHAIN_HEAD_RE.match(text, start)
    if not m:
        return start
    i = m.end()
    while i < len(text):
        if text[i] in "([":
            i = matching_paren(text, i)
        elif text[i] == "." and i + 1 < len(text) and (text[i + 1].isalpha() or text[i + 1] == "_"):
            i = CHAIN_HEAD_RE.match(text, i + 1).end()
        else:
            break
    return i


UNTYPED_READ = r"port\.runtime\.As3\.(?:index|field|getProp|callMember)\("


def _rewrite_negations(body: str, names: set[str], counts: Counts) -> str:
    heads = UNTYPED_READ + (r"|(?:" + "|".join(sorted(names)) + r")\b" if names else "")
    neg = re.compile(r"!(?!=)[ \t]*(?=" + heads + r")")
    mask = code_mask(body)
    pos = len(body)
    while True:
        found = None
        for m in neg.finditer(mask, 0, pos):
            found = m
        if found is None:
            return body
        pos = found.start()
        start = found.end()
        end = _chain_end(body, start)
        if end <= start:
            continue
        body = body[:start] + f"port.runtime.As3.toBool({body[start:end]})" + body[end:]
        counts.reads += 1


def _rewrite_local_calls(body: str, names: set[str], counts: Counts) -> str:
    call = re.compile(r"(?<![\w.$])(" + "|".join(sorted(names)) + r")\s*\(")
    mask = code_mask(body)
    pos = len(body)
    while True:
        found = None
        for m in call.finditer(mask, 0, pos):
            found = m
        if found is None:
            return body
        pos = found.start()
        before = body[:found.start()].rstrip()
        if before.endswith("function") or before.endswith("new"):
            continue
        close = matching_paren(body, found.end() - 1)
        args = split_args(body[found.end():close - 1])
        body = (body[:found.start()] + f"Reflect.callMethod(null, {found.group(1)}, "
                f"[{','.join(a.strip() for a in args)}])" + body[close:])
        counts.calls += 1


def _rewrite_chain(text: str, start: int, end: int, arity: dict[str, int], props: set[str], counts: Counts,
                   expandos: frozenset[str] = frozenset()) -> str:
    cur = text[start:end]
    changed = False
    i = end
    while True:
        m = MEMBER_RE.match(text, i)
        if not m:
            break
        name, j = m.group(1), m.end()
        if j < len(text) and text[j] == "(":
            close = matching_paren(text, j)
            args = split_args(text[j + 1:close - 1])
            owner = getattr(arity, "owners", {}).get(name)
            if owner is not None and too_many_args(len(args), arity.get(name, 0)):
                cur = f"(cast {cur} : {owner}).{name}{text[j:close]}"
                counts.typed += 1
                changed = True
            elif len(args) < arity.get(name, 0):
                cur = (f'port.runtime.As3.callMember({cur}, "{name}", '
                       f'[{",".join(a.strip() for a in args)}])')
                counts.calls += 1
                changed = True
            else:
                cur = f"{cur}.{name}{text[j:close]}"
            i = close
            continue
        if name in props and COMPOUND_RE.match(text, j):
            counts.compound += 1
            cur += f".{name}"
            i = j
            break
        assign = ASSIGN_RE.match(text, j)
        if assign:
            if name in props:
                rhs_end = expression_end(text, assign.end())
                rhs = text[assign.end():rhs_end].strip()
                cur = f'port.runtime.As3.setProp({cur}, "{name}", {rhs})'
                counts.writes += 1
                changed = True
                i = rhs_end
            else:
                cur += f".{name}"
                i = j
            break
        if name in props or name in expandos:
            cur = f'port.runtime.As3.getProp({cur}, "{name}")'
            counts.reads += 1
            changed = True
        else:
            cur += f".{name}"
        i = j
    if changed:
        text = text[:start] + cur + text[i:]
    return text


CATCH_ERROR_RE = re.compile(r"\bcatch\s*\(\s*([A-Za-z_]\w*)\s*:\s*Error\s*\)(\s*)\{")


def catch_vm_errors(text: str) -> tuple[str, int]:
    count = 0

    def repl(m: re.Match) -> str:
        nonlocal count
        count += 1
        name = m.group(1)
        return (f"catch({name}__thrown:Dynamic){m.group(2)}{{ "
                f"var {name}:Error = port.runtime.As3.catchError({name}__thrown);")

    return CATCH_ERROR_RE.sub(repl, text), count


UNTYPED_CONCAT_RE = re.compile(r"\+\s*\(untyped ")


def untyped_concat_operands(text: str) -> tuple[str, int]:
    count = 0
    mask = code_mask(text)
    pos = len(text)
    while True:
        found = None
        for m in UNTYPED_CONCAT_RE.finditer(mask, 0, pos):
            found = m
        if found is None:
            return text, count
        pos = found.start()
        open_at = found.end() - len("(untyped ")
        close = matching_paren(text, open_at)
        inner = text[found.end():close - 1]
        text = text[:open_at] + f"({inner} : Dynamic)" + text[close:]
        count += 1


DYN_CALL = "port.runtime.As3.dyn("


def expando_names(texts: list[str]) -> frozenset[str]:
    names: set[str] = set()
    for text in texts:
        pos = 0
        while True:
            start = text.find(DYN_CALL, pos)
            if start < 0:
                break
            end = matching_paren(text, start + len(DYN_CALL) - 1)
            m = MEMBER_RE.match(text, end)
            if m and ASSIGN_RE.match(text, m.end()):
                names.add(m.group(1))
            pos = end
    return frozenset(names)


PLUS_PAREN_RE = re.compile(r"(?<![+\w])\+\s*\(")


def _top_level_ternary(mask: str) -> bool:
    depth = 0
    for c in mask:
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "?" and depth == 0:
            return True
    return False


def dynamic_ternary_operands(text: str) -> tuple[str, int]:
    count = 0
    mask = code_mask(text)
    pos = len(text)
    while True:
        found = None
        for m in PLUS_PAREN_RE.finditer(mask, 0, pos):
            found = m
        if found is None:
            return text, count
        pos = found.start()
        open_at = found.end() - 1
        close = matching_paren(text, open_at)
        inner = text[open_at + 1:close - 1]
        inner_mask = mask[open_at + 1:close - 1]
        if (_top_level_ternary(inner_mask) and "port.runtime.As3." in inner_mask
                and not inner.rstrip().endswith(": Dynamic")):
            text = text[:open_at] + f"(({inner}) : Dynamic)" + text[close:]
            mask = code_mask(text)
            count += 1


REST_LITERAL_RE = re.compile(r"\bfunction\s*\(([^()]*?)\.\.\.\s*([A-Za-z_]\w*)\s*:\s*Dynamic\s*\)\s*:\s*([\w.<>]+)\s*(?=\{)")
REST_FIXED_RE = re.compile(r"^\s*\??([A-Za-z_]\w*)\s*:\s*([^=]+?)\s*(?:=\s*(.+?))?\s*$", re.S)


def vararg_literals(text: str) -> tuple[str, int]:
    count = 0
    pos = len(text)
    while True:
        found = None
        for m in REST_LITERAL_RE.finditer(text, 0, pos):
            found = m
        if found is None:
            break
        pos = found.start()
        fixed = [REST_FIXED_RE.match(p) for p in split_args(found.group(1).strip().rstrip(","))]
        if any(f is None for f in fixed):
            continue
        body_end = matching_paren(text, found.end())
        body = text[found.end():body_end]
        name, ret = found.group(2), found.group(3)
        if fixed:
            reads = "".join(f"var {f.group(1)}:{f.group(2)} = "
                            + (f"{name}.length > {i} ? {name}[{i}] : {f.group(3)}; " if f.group(3) else f"{name}[{i}]; ")
                            for i, f in enumerate(fixed))
            body = "{ " + reads + f"{name} = {name}.slice({len(fixed)}); " + body + " }"
        if ret == "Void":
            inner = f"(function():Void {body})(); return null; }})"
        else:
            inner = f"return (function():{ret} {body})(); }})"
        text = (text[:found.start()] + f"Reflect.makeVarArgs(function({name}:Array<Dynamic>):Dynamic {{ " + inner
                + text[body_end:])
        count += 1
    return text, count


LOOSE_RHS_RE = re.compile(r"\s*(==|!=)\s*(-?\d+(?:\.\d+)?|[A-Za-z_][\w.]*)(?![\w.(\[])")
LOOSE_AFTER_RE = re.compile(r"\s*(?:[);,:?}\]]|&&|\|\|)")


def loose_index_equality(text: str) -> tuple[str, int]:
    mask = code_mask(text)
    edits = []
    i = 0
    while True:
        at = mask.find(INDEX_CALL, i)
        if at < 0:
            break
        i = at + 1
        try:
            close = matching_paren(text, at + len(INDEX_CALL) - 1)
        except ValueError:
            continue
        m = LOOSE_RHS_RE.match(mask, close)
        if not m or m.group(2) == "null" or not LOOSE_AFTER_RE.match(mask, m.end()):
            continue
        before = mask[:at].rstrip()
        if not (before.endswith(("(", ",", "&&", "||", "?", ":", "return"))
                or (before.endswith("=") and not before.endswith(("==", "!=", "<=", ">=")))):
            continue
        edits.append((at, close, m))
    for at, close, m in reversed(edits):
        call = f"port.runtime.As3.looseEquals({text[at:close]}, {m.group(2)})"
        text = text[:at] + (call if m.group(1) == "==" else "!" + call) + text[m.end():]
    return text, len(edits)


def indexed_calls(text: str) -> tuple[str, int]:
    count = 0
    while True:
        mask = code_mask(text)
        found = None
        i = 0
        while True:
            at = mask.find(INDEX_CALL, i)
            if at < 0:
                break
            i = at + 1
            try:
                close = matching_paren(text, at + len(INDEX_CALL) - 1)
            except ValueError:
                continue
            if mask[close:close + 1] == "(":
                found = (at, close)
        if found is None:
            return text, count
        at, close = found
        args_end = matching_paren(text, close)
        parts = split_args(text[at + len(INDEX_CALL):close - 1])
        if len(parts) != 2:
            return text, count
        args = text[close + 1:args_end - 1]
        text = (text[:at] + f"port.runtime.As3.callIndexed({parts[0].strip()}, {parts[1].strip()}, [{args}])"
                + text[args_end:])
        count += 1


def apply(target: Path, files: list[Path], library_sources: list[str] | None = None,
          counts: Counts | None = None, named_packages: tuple[str, ...] = ()) -> int:
    counts = counts or Counts()
    texts = {path: path.read_text(encoding="utf-8") for path in files}
    arity = method_arity(list(texts.values()))
    arity.owners = method_owners(texts, target)
    props = accessor_properties(list(texts.values()) + list(library_sources or []))
    expandos = expando_names([t for path, t in texts.items()
                              if any(path.relative_to(target).as_posix().startswith(p) for p in named_packages)])
    jobs = []
    for path, text in texts.items():
        relative = path.relative_to(target).as_posix()
        named = any(relative.startswith(package) for package in named_packages)
        if not named and INDEX_CALL not in text and DYNAMIC_LOCAL_RE.search(text) is None and "(untyped " not in text:
            continue
        jobs.append((str(path), text, named))
    workers = rewrite_workers(len(jobs))
    if workers > 1:
        from concurrent.futures import ProcessPoolExecutor
        with ProcessPoolExecutor(max_workers=workers, initializer=_worker_tables, initargs=(arity, props, expandos)) as pool:
            results = list(pool.map(_rewrite_job, jobs, chunksize=8))
    else:
        _worker_tables(arity, props, expandos)
        results = [_rewrite_job(job) for job in jobs]
    for (path, _, _), (new, count, delta) in zip(jobs, results):
        for name, value in delta.items():
            setattr(counts, name, getattr(counts, name) + value)
        if count:
            Path(path).write_text(new, encoding="utf-8", newline="\n")
    return counts.total()


WORKERS_ENV = "PORT_DYNCALLS_WORKERS"
_TABLES: tuple = ()


def rewrite_workers(files: int) -> int:
    import os
    wanted = os.environ.get(WORKERS_ENV, "")
    count = int(wanted) if wanted.isdigit() else min(12, max(1, (os.cpu_count() or 2) - 2))
    return 1 if files < 50 else max(1, count)


def _worker_tables(arity, props, expandos) -> None:
    global _TABLES
    _TABLES = (arity, props, expandos)


def _rewrite_job(job: tuple[str, str, bool]) -> tuple[str, int, dict[str, int]]:
    _, text, named = job
    arity, props, expandos = _TABLES
    counts = Counts()
    new, count = rewrite(text, arity, props, counts, named, expandos if named else frozenset())
    new, untyped = untyped_concat_operands(new)
    counts.untyped += untyped
    count += untyped
    if named:
        new, catches = catch_vm_errors(new)
        new, literals = vararg_literals(new)
        new, ternaries = dynamic_ternary_operands(new)
        new, equalities = loose_index_equality(new)
        new, indexed = indexed_calls(new)
        counts.catches += catches
        count += catches + literals + ternaries + equalities + indexed
    return new, count, vars(counts)
