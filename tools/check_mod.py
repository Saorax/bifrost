"""check a content mod against the game's load rules for maps, modes and cosmetic items, without starting the game.

    python tools/check_mod.py examples/mods/sample-map [more mod folders] [--tables build/tabledata]

the game checks its tables as it parses them, and a failed check throws: one bad row stops the whole archive from
loading ("File Loading Error"). this applies the mods to the extracted tables the same way the loader does
(``tools/preview_content_mod.py``) and checks every row a mod adds or changes in LevelTypes, LevelSetTypes,
GameModeTypes, ScoringTypes, avatarTypes, TauntTypes, EmojiTypes, SpawnBotTypes, TrailEffectTypes,
SeasonBorderTypes and MonikerTypes. when a mod touches legends, skins, weapon skins, stances or power swaps it also
runs the checks of ``tools/check_legend_mod.py``. each finding cites the check's place in ``src/as3/10.11/scripts``;
the item id limits are Bifrost's: src/mods/raise_id_limits raises the game's taunt 447, sidekick 255,
KO effect 63 and border 127 limits to 1023.

exit 1 if any rule the game enforces is broken, or a mod row would crash the game later (a game mode whose
ScoringType doesn't exist). warnings are for things the game accepts but that won't work as intended.
"""

from __future__ import annotations

import argparse
import copy
import csv
import io
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools import check_legend_mod as legend
from tools import preview_content_mod as preview

LEGEND_TABLES = {"HeroTypes", "costumeTypes", "weaponSkinTypes", "RuneTypes", "PowerSwapTypes"}
EXTRA_COLUMNS = {"LevelTypes": {"BulletWaves", "ShadowTint"}, "GameModeTypes": {"EquippedItem", "IsDefaultForScoringType"},
                 "ScoringTypes": {"RoguePlayer"}, "EmojiTypes": {"SpriteType"}}
SPECS = {
    "LevelTypes": dict(kind="map", key="LevelName", id="LevelID", file="LevelType.as", unknown=435, name=450, dup_id=454,
                       cap=320),
    "LevelSetTypes": dict(kind="level set", key="LevelSetName", id="LevelSetID", file="class_248.as", unknown=125,
                          name=132, dup_id=136, cap=128),
    "GameModeTypes": dict(kind="game mode", key="GameModeName", id="GameModeID", file="class_163.as", unknown=283,
                          name=294, dup_id=288, cap=256),
    "ScoringTypes": dict(kind="scoring type", key="ScoringName", id="ScoringID", file="ScoringType.as", unknown=573,
                         name=700, dup_id=694, cap=128),
    "TauntTypes": dict(kind="emote", key="TauntName", id="TauntID", file="class_629.as", unknown=223, name=236,
                       dup_id=240, zero=228, limit=(1023, 244)),
    "EmojiTypes": dict(kind="emoji", key="EmojiName", id="EmojiID", file="class_120.as", unknown=187),
    "SpawnBotTypes": dict(kind="sidekick", key="SpawnBotName", id="SpawnBotID", file="class_574.as", unknown=227,
                          name=239, dup_id=243, zero=232, limit=(1023, 247)),
    "TrailEffectTypes": dict(kind="KO effect", key="TrailEffectName", id="TrailEffectID", file="class_650.as",
                             unknown=229, name=241, dup_id=245, zero=249, limit=(1023, 255)),
    "SeasonBorderTypes": dict(kind="border", key="SeasonBorderName", id="SeasonBorderID", file="class_559.as",
                              unknown=103, name=116, dup_id=120, limit=(1023, 124)),
    "MonikerTypes": dict(kind="title", key="MonikerName", id="MonikerID", file="class_279.as", unknown=103),
}
TEAM_COLOURS = {"Red", "Blue", "Yellow", "Purple"}
VARIATIONS = {"relay", "scramble", "shift"}
DAMAGE = {"FALSE", "TRUE", "SPECIALENTS", "NORMALENTS", "STAMINA", "STAMINA_NO_KNOCKBACK"}
AUTO_SETS = (("1-2 players", ["LevelSet1v1", "LevelSet2v2", "LevelSetFFA", "LevelSetAll"],
              ["LevelSet1v1", "LevelSet2v2", "LevelSetFFA", "LevelSetAll"]),
             ("3-4 players", ["LevelSetFFA", "LevelSetAll"], ["LevelSet2v2", "LevelSetFFA", "LevelSetAll"]),
             ("5-6 players", ["LevelSetBig", "LevelSetAll"],
              ["LevelSet3v3", "LevelSetBigTeam", "LevelSetBig", "LevelSetAll"]),
             ("7+ players", ["LevelSetBig", "LevelSetAll"], ["LevelSetBigTeam", "LevelSetBig", "LevelSetAll"]))
SET_COLUMNS = ("LevelSetAll", "LevelSet1v1", "LevelSetFFA", "LevelSet2v2", "LevelSetBig", "LevelSetBigTeam",
               "LevelSet3v3")

truthy = legend.truthy
listed = legend.listed
number = legend.number


def text(row: ET.Element, tag: str) -> str | None:
    el = row.find(tag)
    return None if el is None else (el.text or "").strip()


def has(row: ET.Element, tag: str) -> bool:
    return bool(text(row, tag))


def decimal(value: str | None) -> float:
    try:
        return float(value or 0)
    except ValueError:
        return 0.0


def float3(value: str | None) -> bool:
    parts = (value or "").split(",")
    return len(parts) == 3 and all(re.fullmatch(r"\s*[+-]?\d*\.?\d+(e[+-]?\d+)?\s*", p) for p in parts)


class XmlTable:

    def __init__(self, name: str, root: ET.Element, before: dict[int, bytes], columns: set[str]):
        self.name = name
        keyed = [a for r in root for a in preview.key_attributes(r)]
        key = SPECS.get(name, {}).get("key") or (keyed[0] if keyed else None)
        self.rows = [r for r in root if r.get(key) not in ("Template", "XLTemplate")]
        self.mine = [r for r in self.rows if id(r) not in before or ET.tostring(r) != before[id(r)]]
        self.added = [r for r in self.rows if id(r) not in before]
        self.columns = columns | EXTRA_COLUMNS.get(name, set())
        self.by_name = {r.get(key): r for r in self.rows} if key else {}


class ModTables:

    def __init__(self, tables: Path, mods: list[dict]):
        self.root = tables
        self.mods = mods
        self.lines = preview.resolve_duplicate_names(mods, preview.game_names(tables, {t for m in mods for t in m["tables"]}))
        self.legend: legend.Tables | None = None
        self.originals: dict[str, dict[int, ET.Element]] = {}
        self._xml: dict[str, XmlTable | None] = {}
        self._csv: dict[str, tuple[list[str], list[dict], set[str]] | None] = {}

    def find(self, file: str) -> Path | None:
        found = sorted(self.root.rglob(file))
        if len(found) > 1:
            raise preview.ModError(f"{len(found)} files named {file} under {self.root}")
        return found[0] if found else None

    def xml(self, name: str) -> XmlTable | None:
        if name not in self._xml:
            path = self.find(f"{name}.xml")
            if path is None:
                self._xml[name] = None
            else:
                root = ET.parse(path).getroot()
                before = {id(r): ET.tostring(r) for r in root}
                self.originals[name] = {id(r): copy.deepcopy(r) for r in root}
                columns = {c.tag for r in root for c in r}
                self.lines += preview.apply(name, root, self.mods)
                self._xml[name] = XmlTable(name, root, before, columns)
        return self._xml[name]

    def csv(self, name: str) -> tuple[list[str], list[dict], set[str]] | None:
        if name not in self._csv:
            path = self.find(f"{name}.csv")
            if path is None:
                self._csv[name] = None
            else:
                out, lines = preview.apply_csv(name, path.read_text(encoding="utf-8"), self.mods)
                self.lines += lines
                rows = list(csv.reader(io.StringIO(out.split("\n", 1)[1])))
                mine = set()
                for line in lines:
                    m = (re.match(rf"row (?:added|changed) {name}/(.+?)(?: \(copy of [^)]*\))? \([^()]*\)$", line)
                         or re.match(rf"row added {name}: ([^,]*)", line))
                    if m:
                        mine.add(m.group(1))
                self._csv[name] = (rows[0], [dict(zip(rows[0], r)) for r in rows[1:]
                                             if r and r[0] and r[0] != "Template"], mine)
        return self._csv[name]

    def touches(self, table: str) -> bool:
        return any(table in m["tables"] for m in self.mods)

    def level_descs(self) -> set[str]:
        names = set()
        for path in self.root.rglob("LevelDesc_*.xml"):
            with open(path, encoding="utf-8", errors="replace") as f:
                m = re.search(r'LevelName="([^"]*)"', f.read(2000))
            if m:
                names.add(m.group(1))
        for mod in self.mods:
            for file in mod["files"]:
                try:
                    root = ET.parse(mod["folder"] / file).getroot()
                except (OSError, ET.ParseError):
                    continue
                if root.tag == "LevelDesc" and root.get("LevelName"):
                    names.add(preview.swap_token(root.get("LevelName"), mod.get("file_renames", {})))
        return names


def where(t: XmlTable, row: ET.Element) -> str:
    spec = SPECS[t.name]
    return f"{spec['kind']} {row.get(spec['key'])}"


def basic(t: XmlTable, errors: list[str], warnings: list[str], rows: list[ET.Element] | None = None) -> None:
    spec = SPECS[t.name]
    rows = t.rows if rows is None else rows
    cite = lambda line: f"({spec['file']}:{line})"
    for r in t.mine:
        w = where(t, r)
        for c in r:
            if c.tag not in t.columns:
                errors.append(f"{w}: unknown property {c.tag}; no game row has it and the loader stops on columns it "
                              f"doesn't read {cite(spec['unknown'])}")
        if r not in rows:
            continue
        if spec.get("name") and sum(1 for o in rows if o.get(spec["key"]) == r.get(spec["key"])) > 1:
            errors.append(f"{w}: duplicate {spec['key']} {cite(spec['name'])}")
        value = text(r, spec["id"])
        if spec.get("dup_id") and value and sum(1 for o in rows if text(o, spec["id"]) == value) > 1:
            errors.append(f"{w}: duplicate {spec['id']} {value} {cite(spec['dup_id'])}")
        if spec.get("zero") and number(value) == 0:
            errors.append(f"{w}: {spec['id']} missing or 0 {cite(spec['zero'])}")
        if spec.get("limit") and number(value) >= spec["limit"][0]:
            errors.append(f"{w}: {spec['id']} {value} is {spec['limit'][0]} or more; the client stops (the limit "
                          f"src/mods/raise_id_limits sets) {cite(spec['limit'][1])}")
        if spec.get("cap") and number(value) >= spec["cap"]:
            warnings.append(f"{w}: {spec['id']} {value} is {spec['cap']} or more, past the official server's table "
                            "size (the client only builds a message it never shows); keep mod ids below it")


def check_levels(mt: ModTables, errors: list[str], warnings: list[str]) -> None:
    t = mt.xml("LevelTypes")
    if t is None or not t.mine:
        return
    live = [r for r in t.rows if not truthy(r.get("DevOnly"))]
    basic(t, errors, warnings, live)
    colours = mt.xml("ColorSchemeTypes")
    descs = mt.level_descs()
    sets = mt.xml("LevelSetTypes")
    for r in t.mine:
        w = where(t, r)
        if r not in live:
            continue
        if number(text(r, "LevelID")) == 0:
            warnings.append(f"{w}: LevelID missing or 0; level sets and rooms find maps by a non-zero id")
        for side in ("Left", "Right"):
            if truthy(text(r, f"Hard{side}Kill")) and decimal(text(r, f"{side}Kill")) <= 200:
                errors.append(f"{w}: Hard{side}Kill needs {side}Kill above 200 "
                              f"(LevelType.as:{462 if side == 'Left' else 466})")
        order = listed(text(r, "TeamColorOrder"))
        avoid = text(r, "AvoidTeamColor")
        for c in order + ([avoid] if avoid else []):
            if c not in TEAM_COLOURS:
                errors.append(f"{w}: team colour {c}; only Red, Blue, Yellow and Purple (LevelType.as:237)")
        if avoid and avoid in order:
            errors.append(f"{w}: AvoidTeamColor {avoid} is in TeamColorOrder (LevelType.as:470)")
        if colours is not None:
            for c in listed(text(r, "ColorExclusionList")):
                if c not in colours.by_name:
                    errors.append(f"{w}: ColorExclusionList has {c}, which is not in ColorSchemeTypes "
                                  "(LevelType.as:589)")
        if r.get("LevelName") not in descs and r.get("LevelName") != "Random":
            errors.append(f"{w}: a live map (not DevOnly) without a LevelDesc with LevelName=\"{r.get('LevelName')}\" "
                          "(a file in the mod's \"files\"): the game stops (LevelType.as:630)")
        if sets is not None and r in t.added:
            level_reach(mt, r.get("LevelName"), sets, warnings)


def level_reach(mt: ModTables, name: str, sets: XmlTable, warnings: list[str]) -> None:
    holding = {s.get("LevelSetName") for s in sets.rows if name in listed(text(s, "LevelTypes"))}
    if not holding:
        warnings.append(f"map {name}: in no LevelSetTypes list, so no room picks it (append it with "
                        "<LevelTypes>+" + name + "</LevelTypes> to a set)")
        return
    scoring = mt.xml("ScoringTypes")
    if scoring is None:
        return
    missed: dict[str, tuple[set[str], set[str]]] = {}
    for s in scoring.rows:
        if not truthy(s.get("Enabled")) or truthy(text(s, "ForceAutoLevelSet")):
            continue
        offered = {text(s, c) for c in SET_COLUMNS} | set(listed(text(s, "ExtraLevelSets")))
        if not offered & holding:
            continue
        teams = [True] if truthy(text(s, "MustHaveTeams")) else [False] if truthy(text(s, "CannotHaveTeams")) else [False, True]
        for label, solo, team in AUTO_SETS:
            for on in teams:
                chosen = next((text(s, c) for c in (team if on else solo) if text(s, c)), None)
                if chosen and chosen not in holding:
                    sizes, modes = missed.setdefault(chosen, (set(), set()))
                    sizes.add(label)
                    modes.add(s.get("ScoringName"))
    if missed:
        parts = []
        for k, (sizes, modes) in sorted(missed.items()):
            shown = sorted(modes)[:3]
            parts.append(f"{k} ({', '.join(sorted(sizes))} in {', '.join(shown)}"
                         f"{f' and {len(modes) - 3} more' if len(modes) > 3 else ''})")
        warnings.append(f"map {name}: is only in {', '.join(sorted(holding))}; a room on Auto picks from its scoring "
                        f"type's set for the player count, and these sets don't have it: {'; '.join(parts)}")


def check_level_sets(mt: ModTables, errors: list[str], warnings: list[str]) -> None:
    t = mt.xml("LevelSetTypes")
    if t is None or not t.mine:
        return
    basic(t, errors, warnings)
    levels = mt.xml("LevelTypes")
    descs = mt.level_descs()
    for r in t.mine:
        w = where(t, r)
        names = listed(text(r, "LevelTypes"))
        if not names and number(text(r, "LevelSetID")) != 0:
            errors.append(f"{w}: no levels in LevelTypes (class_248.as:156)")
        original = mt.originals["LevelSetTypes"].get(id(r))
        before = set(listed(text(original, "LevelTypes"))) if original is not None else set()
        for n in names:
            if n in before or levels is None:
                continue
            row = levels.by_name.get(n)
            why = ("is not in LevelTypes" if row is None else "is DevOnly" if truthy(row.get("DevOnly"))
                   else "has no LevelDesc" if n not in descs else None)
            if why:
                warnings.append(f"{w}: map {n} {why}, so the set silently leaves it out")


def check_scoring(mt: ModTables, errors: list[str], warnings: list[str]) -> None:
    t = mt.xml("ScoringTypes")
    if t is None or not t.mine:
        return
    basic(t, errors, warnings)
    cite = lambda line: f"(ScoringType.as:{line})"
    rule_sets = mt.xml("ItemSpawnRuleSetTypes")
    level_sets = mt.xml("LevelSetTypes")
    modes = mt.xml("GameModeTypes")
    copies = {row.get("set", {}).get("@ScoringName"): row["copy"] for m in mt.mods for row in m["tables"].get("ScoringTypes", [])
              if isinstance(row, dict) and row.get("copy")}
    for r in t.mine:
        w = where(t, r)
        b = lambda tag: truthy(text(r, tag))
        n = lambda tag: number(text(r, tag))
        if r in t.added and r.get("ScoringName") not in copies:
            warnings.append(f"{w}: a new scoring type that is not a \"copy\"; the client has rules only for its own "
                            f"names {cite(674)}. bifrost waives that check for added rows and plays a copy with its "
                            "source's rules, so this one needs a code mod that registers rules (ModModes.registerRules)")
        value = text(r, "CannotTakeDamage")
        if value is not None and value.upper() not in DAMAGE:
            errors.append(f"{w}: CannotTakeDamage {value}; one of {', '.join(sorted(DAMAGE))} {cite(560)}")
        if not has(r, "IconName"):
            errors.append(f"{w}: no IconName {cite(678)}")
        if b("MustHaveTeams") and b("CannotHaveTeams"):
            errors.append(f"{w}: both MustHaveTeams and CannotHaveTeams {cite(686)}")
        if b("StrictTeamSideSpawning") and not b("MustHaveTeams"):
            errors.append(f"{w}: StrictTeamSideSpawning needs MustHaveTeams {cite(690)}")
        if not has(r, "DefaultGameModeType"):
            errors.append(f"{w}: no DefaultGameModeType {cite(704)}")
        elif modes is not None and text(r, "DefaultGameModeType") not in modes.by_name:
            warnings.append(f"{w}: DefaultGameModeType {text(r, 'DefaultGameModeType')} is not in GameModeTypes; a room "
                            "switches to it when this scoring type is picked")
        auto = b("ForceAutoLevelSet")
        if auto == (text(r, "LevelSetAll") is not None):
            errors.append(f"{w}: needs LevelSetAll or ForceAutoLevelSet TRUE, not both or neither {cite(708)}")
        per = n("EntitiesPerPlayer") if text(r, "EntitiesPerPlayer") is not None else 1
        if per == 0:
            errors.append(f"{w}: EntitiesPerPlayer 0 {cite(712)}")
        if per > 1:
            if not b("ForceUniqueColors"):
                errors.append(f"{w}: EntitiesPerPlayer above 1 needs ForceUniqueColors {cite(716)}")
            for flag, line in (("AllowRotatingHeroes", 722), ("AllowShift", 726)):
                if b(flag):
                    errors.append(f"{w}: EntitiesPerPlayer above 1 with {flag} {cite(line)}")
            if n("NumExtraBots") + n("NumExtraNetBots") > 0:
                errors.append(f"{w}: EntitiesPerPlayer above 1 with extra bots {cite(730)}")
            if n("ForcedMaxPlayers") == 0 or n("ForcedMaxPlayers") * per > 8:
                errors.append(f"{w}: EntitiesPerPlayer above 1 needs ForcedMaxPlayers with players x entities up to 8 "
                              f"{cite(734)}")
        if b("UseDmgHUD"):
            if b("MustHaveTeams") and not 0 < n("ForcedMaxTeamSize") <= 3:
                errors.append(f"{w}: UseDmgHUD with MustHaveTeams needs ForcedMaxTeamSize 1-3 {cite(743)}")
            if not b("MustHaveTeams") and n("ForcedMaxPlayers") != 2:
                errors.append(f"{w}: UseDmgHUD without MustHaveTeams needs ForcedMaxPlayers 2 {cite(748)}")
        if has(r, "AlwaysEquipItem"):
            for flag, line in (("AllowRotatingHeroes", 755), ("AllowShift", 762)):
                if b(flag):
                    errors.append(f"{w}: {flag} with AlwaysEquipItem {text(r, 'AlwaysEquipItem')} {cite(line)}")
        size = n("ForcedMaxTeamSize")
        if size:
            players = n("ForcedMaxPlayers") or 8
            if b("CannotHaveTeams"):
                errors.append(f"{w}: ForcedMaxTeamSize with CannotHaveTeams {cite(769)}")
            if size * 2 < players:
                errors.append(f"{w}: ForcedMaxTeamSize {size} is below half of {players} players {cite(774)}")
            elif size >= players:
                errors.append(f"{w}: ForcedMaxTeamSize {size} is not below {players} players {cite(778)}")
        if auto:
            need = (("LevelSet2v2", 787), ("LevelSetBigTeam", 791)) if b("MustHaveTeams") else \
                (("LevelSetFFA", 799), ("LevelSetBig", 803))
            for col, line in need:
                if text(r, col) is None:
                    errors.append(f"{w}: ForceAutoLevelSet {'with' if b('MustHaveTeams') else 'without'} MustHaveTeams "
                                  f"needs {col} {cite(line)}")
            if listed(text(r, "ExtraLevelSets")):
                errors.append(f"{w}: ExtraLevelSets with ForceAutoLevelSet {cite(809)}")
        top, step = n("MaxScoreToWin"), n("ScoreToWinIncrement")
        if top and step and top % step:
            errors.append(f"{w}: ScoreToWinIncrement {step} doesn't divide MaxScoreToWin {top} {cite(814)}")
        rules = text(r, "ItemSpawnRuleSet")
        if not rules:
            errors.append(f"{w}: no ItemSpawnRuleSet {cite(870)}")
        elif rule_sets is not None and rules not in {x.get("RuleSetName") for x in rule_sets.rows}:
            errors.append(f"{w}: ItemSpawnRuleSet {rules} is not in ItemSpawnRuleSetTypes {cite(877)}")
        if level_sets is not None:
            for col in SET_COLUMNS + ("ExtraLevelSets",):
                for name in listed(text(r, col)):
                    if name not in level_sets.by_name:
                        warnings.append(f"{w}: {col} {name} is not in LevelSetTypes; the game leaves it out {cite(911)}")


def check_modes(mt: ModTables, errors: list[str], warnings: list[str]) -> None:
    t = mt.xml("GameModeTypes")
    if t is None or not t.mine:
        return
    basic(t, errors, warnings)
    scoring = mt.xml("ScoringTypes")
    level_sets = mt.xml("LevelSetTypes")
    for r in t.mine:
        w = where(t, r)
        variation = text(r, "Variation")
        if variation and variation.lower() not in VARIATIONS:
            errors.append(f"{w}: Variation {variation}; Relay, Scramble, Shift or blank (class_163.as:308)")
        name = text(r, "ScoringType")
        if scoring is not None and name not in {s.get("ScoringName") for s in scoring.rows}:
            errors.append(f"{w}: ScoringType {name or '(none)'} is not in ScoringTypes. the loader doesn't check it, "
                          "but a room that loads this mode reads the scoring type's level sets and item rules from "
                          "nothing and crashes")
        if level_sets is not None:
            for col in ("LevelSet", "CompetitiveLevelSet"):
                if text(r, col) and text(r, col) not in level_sets.by_name:
                    warnings.append(f"{w}: {col} {text(r, col)} is not in LevelSetTypes")


def check_items(mt: ModTables, errors: list[str], warnings: list[str]) -> None:
    for name in ("TauntTypes", "EmojiTypes", "SpawnBotTypes", "TrailEffectTypes", "SeasonBorderTypes", "MonikerTypes"):
        t = mt.xml(name) if mt.touches(name) else None
        if t is not None and t.mine:
            basic(t, errors, warnings)
    taunts = mt.xml("TauntTypes") if mt.touches("TauntTypes") else None
    if taunts is not None and taunts.mine:
        powers = mt.csv("powerTypes")
        power_names = {p["PowerName"] for p in powers[1]} if powers else None
        for r in taunts.mine:
            w = where(taunts, r)
            for col, line in (("OffsetStore", 190), ("OffsetStoreMini", 206), ("OffsetInventory", 214)):
                if text(r, col) is not None and not float3(text(r, col)):
                    errors.append(f"{w}: {col} {text(r, col)} is not three comma-separated numbers (class_629.as:{line})")
            power = text(r, "PowerName")
            if power_names is not None and power not in power_names:
                errors.append(f"{w}: PowerName {power} is not in powerTypes (class_629.as:344)")
            shared = [o.get("TauntName") for o in taunts.rows if o is not r and text(o, "PowerName") == power]
            if power and shared:
                warnings.append(f"{w}: PowerName {power} is also {shared[0]}'s; the client maps a power to one emote "
                                "(the last row), so the two share the animation and that map. give a new emote its "
                                "own power")
    emoji = mt.xml("EmojiTypes") if mt.touches("EmojiTypes") else None
    if emoji is not None and emoji.mine:
        categories = [c for c in dict.fromkeys(text(o, "Category") for o in mt.originals["EmojiTypes"].values()
                                               if o.get("EmojiName") != "Template") if c]
        place = lambda r: text(r, "Category") if text(r, "Category") in categories else (categories[0] if categories else None)
        for r in emoji.mine:
            w = where(emoji, r)
            if text(r, "Category") not in categories:
                warnings.append(f"{w}: Category {text(r, 'Category')} is not a game category; it lands in the first one "
                                f"({categories[0] if categories else '?'})")
            if truthy(text(r, "DefaultUnlocked")):
                other = [o.get("EmojiName") for o in emoji.rows if o is not r and truthy(text(o, "DefaultUnlocked"))
                         and place(o) == place(r)]
                if other:
                    errors.append(f"{w}: DefaultUnlocked like {other[0]}, the default of category {place(r)}; one "
                                  "default per category (class_120.as:225). a copy of a default emoji keeps the flag: "
                                  "set DefaultUnlocked to false")
            value = text(r, "EmojiID")
            if value and sum(1 for o in emoji.rows if text(o, "EmojiID") == value) > 1:
                warnings.append(f"{w}: EmojiID {value} is used twice; the later row silently replaces the other")
    trails = mt.xml("TrailEffectTypes") if mt.touches("TrailEffectTypes") else None
    if trails is not None and trails.mine:
        emitters = mt.xml("EmitterTypes")
        for r in trails.mine:
            w = where(trails, r)
            for col, line in (("OffsetStore", 200), ("OffsetStoreMini", 208), ("OffsetInventory", 216),
                              ("OffsetPreviewer", 224)):
                if text(r, col) is not None and not float3(text(r, col)):
                    errors.append(f"{w}: {col} {text(r, col)} is not three comma-separated numbers (class_650.as:{line})")
            if truthy(text(r, "UseCustomHead")) and not truthy(text(r, "UseCostume")):
                errors.append(f"{w}: UseCustomHead without UseCostume (class_650.as:253)")
            names = listed(text(r, "EmitterTypes"))
            if not names:
                errors.append(f"{w}: no EmitterTypes (class_650.as:322)")
            for e in names:
                if emitters is not None and e not in {x.get("EmitterName") for x in emitters.rows}:
                    errors.append(f"{w}: EmitterTypes has {e}, which is not in EmitterTypes (class_650.as:315)")
    borders = mt.xml("SeasonBorderTypes") if mt.touches("SeasonBorderTypes") else None
    if borders is not None:
        for r in borders.mine:
            for col, line in (("DisplayNameKey", 111), ("AnimRig", 129)):
                if not has(r, col):
                    errors.append(f"{where(borders, r)}: no {col} (class_559.as:{line})")
    titles = mt.xml("MonikerTypes") if mt.touches("MonikerTypes") else None
    if titles is not None:
        for r in titles.mine:
            w = where(titles, r)
            value = text(r, "MonikerID")
            if value and sum(1 for o in titles.rows if text(o, "MonikerID") == value) > 1:
                warnings.append(f"{w}: MonikerID {value} is used twice; the later row silently replaces the other")
            if r in titles.added and not truthy(text(r, "ImplicitOwnership")):
                warnings.append(f"{w}: no ImplicitOwnership TRUE; bifrost owns mod items of every other kind, but a "
                                "title only through unlockAll (on by default) or this flag")
    avatars = mt.csv("avatarTypes") if mt.touches("avatarTypes") else None
    if avatars is not None:
        _, rows, mine = avatars
        for r in rows:
            name = r.get("AvatarName")
            if name not in mine:
                continue
            w = f"avatar {name}"
            if number(r.get("AvatarID")) == 0:
                errors.append(f"{w}: AvatarID missing or 0; 10.11 drops the row (class_16.as:197), 11.00.49 stops")
            if sum(1 for o in rows if o.get("AvatarName") == name) > 1:
                errors.append(f"{w}: duplicate AvatarName (class_16.as:210)")
            if r.get("AvatarID") and sum(1 for o in rows if o.get("AvatarID") == r.get("AvatarID")) > 1:
                errors.append(f"{w}: duplicate AvatarID {r.get('AvatarID')} (class_16.as:214)")
            for col, line in (("DisplayNameKey", 204), ("FlagArt", 219), ("FlagArtFile", 224), ("IconName", 229)):
                if col in avatars[0] and not (r.get(col) or "").strip():
                    errors.append(f"{w}: no {col} (class_16.as:{line})")


def check(mt: ModTables) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    check_levels(mt, errors, warnings)
    check_level_sets(mt, errors, warnings)
    check_scoring(mt, errors, warnings)
    check_modes(mt, errors, warnings)
    check_items(mt, errors, warnings)
    if any(mt.touches(t) for t in LEGEND_TABLES):
        mt.legend = legend.Tables(mt.root, mt.mods)
        e, w = legend.check(mt.legend)
        errors += e
        warnings += w
    return errors, warnings


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("mods", nargs="+", type=Path, help="mod folders (each with a mod.json)")
    p.add_argument("--tables", type=Path, default=ROOT / "build" / "tabledata",
                   help="extracted tables (tools/extract_client_data.mjs output)")
    args = p.parse_args(argv)
    try:
        mods = preview.order([preview.load_manifest(m) for m in args.mods])
        tables = ModTables(args.tables, mods)
        errors, warnings = check(tables)
    except preview.ModError as e:
        print(f"check FAILED: {e}", file=sys.stderr)
        return 1
    for line in tables.lines:
        if line.startswith("renamed "):
            print(line)
    for line in errors:
        print(f"error {line}")
    for line in warnings:
        print(f"warning {line}")
    rows = sum(len(t.mine) for t in tables._xml.values() if t is not None)
    rows += sum(len(c[2]) for c in tables._csv.values() if c is not None)
    if tables.legend is not None:
        rows += sum(len(tables.legend.touched.get(k, set())) for k in ("HeroTypes", "costumeTypes", "weaponSkinTypes"))
        rows += sum(1 for _, mine in (tables.legend.swaps or []) if mine)
    print(f"{rows} rows checked in {', '.join(sorted({t for m in mods for t in m['tables']})) or 'no tables'}: "
          f"{len(errors)} errors, {len(warnings)} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
