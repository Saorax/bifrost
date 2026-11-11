"""check a legend or skin mod against the game's own legend, skin and power-swap rules, without starting the game.

    python tools/check_legend_mod.py examples/mods/sample-legend [more mod folders] [--tables build/tabledata]

the game checks its tables as it parses them, and a failed check throws: one bad row stops the whole archive from
loading ("File Loading Error"). this applies the mods to the extracted tables the same way the loader does
(``tools/preview_content_mod.py``), then runs the checks from the 10.11 code on every legend (HeroTypes row), stance
(RuneTypes row), skin (costumeTypes row), weapon skin and power swap (PowerSwapTypes row) a mod adds or changes.
each finding cites the check's place in ``src/as3/10.11/scripts``. ``tools/check_mod.py`` runs these checks too,
next to the ones for maps, modes and cosmetic items.

exit 1 if any rule the game enforces is broken. warnings are for things the game accepts but that won't work as
intended.
"""

from __future__ import annotations

import argparse
import csv
import io
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools import preview_content_mod as preview

HERO_FIELDS = set("""HeroID Height Width HeroDisplayName AlphabetizedName ReleaseOrderID BotDisplayName MissionTags
CostumeName Portrait PortraitFileName IsBeta IsActive CanRandom AltSigModeCostumes AltSigModeWeapons BaseWeapon1
BaseWeapon2 SpecialPower1 SpecialPower2 SpecialPower1_Forward SpecialPower1_Down SpecialPower2_Forward
SpecialPower2_Down Dexterity Strength Speed Weight BioName BioAKAKey BioQuoteAboutKey BioQuoteAboutAttribKey
BioQuoteFromKey BioQuoteFromAttribKey BioTextKey SplashArt PaperDollWeapon IdleInPreview IdleInStore OverIdleAnim
OverIdleSound MinOverIdleTime RangeOverIdleTime HomeField NameSoundEvent SoundBank ColorRewards Rewards RewardLevels
OnSelectedSoundEvent PaperDollFacesLeft PaperDollOffset MeetLegendsScaleOverride""".split())
DEFAULT_WEAPONS = ("Sword", "RocketLance")
SWAP_GFX = ("CastGfx", "FireGfx", "HitGfx")
SWAP_GFX_CITE = {"CastGfx": 410, "FireGfx": 487, "HitGfx": 449}
STANCES = 10


def weapon_tag(weapon: str) -> str:
    return "LanceUser" if weapon == "RocketLance" else weapon + "User"


def listed(text: str | None) -> list[str]:
    return [x.strip() for x in (text or "").split(",") if x.strip()]


def truthy(text: str | None) -> bool:
    return (text or "").strip().lower() == "true"


def number(text: str | None) -> int:
    text = (text or "").strip()
    return int(text) if re.fullmatch(r"-?\d+", text) else 0


def hero_weapons(field, hero: ET.Element) -> tuple[str, str]:
    return tuple(field(hero, f"BaseWeapon{i + 1}") or DEFAULT_WEAPONS[i] for i in range(2))


class Tables:

    def __init__(self, tables: Path, mods: list[dict]):
        self.root = tables
        self.mods = mods
        self.touched: dict[str, set[str]] = {}
        self.added: dict[str, set[str]] = {}
        self.lines: list[str] = []
        self.heroes = ET.parse(self.find("HeroTypes.xml")).getroot()
        self._note(preview.apply("HeroTypes", self.heroes, mods))
        colours = ET.parse(self.find("ColorSchemeTypes.xml")).getroot()
        self._note(preview.apply("ColorSchemeTypes", colours, mods))
        self.colours = {r.get("ColorSchemeName") for r in colours}
        self.costumes = self._csv(self.find("costumeTypes.csv"), "costumeTypes", mods)
        self.weapon_skins = self._csv(self.find("weaponSkinTypes.csv"), "weaponSkinTypes", mods)
        runes = ET.parse(self.find("RuneTypes.xml")).getroot()
        before = {id(r) for r in runes}
        self._note(preview.apply("RuneTypes", runes, mods))
        self.stances: dict[str, list[dict]] = {}
        self.rune_rows: list[tuple[ET.Element, str | None, bool]] = []
        hero = None
        for r in runes:
            name = r.findtext("HeroName")
            if name is not None and name != hero:
                hero = name
                self.stances[hero] = []
            if hero is not None:
                self.stances[hero].append({c.tag: (c.text or "").strip() for c in r})
            self.rune_rows.append((r, hero, id(r) not in before))
        added = iter([(r, h) for r, h, new in self.rune_rows if new])
        self.rune_added: dict[str, list[tuple[ET.Element, str | None]]] = {}
        for mod in mods:
            count = sum(1 for x in mod["tables"].get("RuneTypes", []) if not (isinstance(x, dict) and "stance" in x))
            rows = [r for r in (next(added, None) for _ in range(count)) if r is not None]
            if rows:
                self.rune_added[mod["id"]] = rows
        self.swaps: list[tuple[ET.Element, bool]] | None = None
        swaps = self.find("PowerSwapTypes.xml", optional=True)
        if swaps is not None:
            root = ET.parse(swaps).getroot()
            before_rows = {id(r): ET.tostring(r) for r in root}
            self.swap_columns = {c.tag for r in root for c in r}
            self._note(preview.apply("PowerSwapTypes", root, mods))
            self.swaps = [(r, id(r) not in before_rows or ET.tostring(r) != before_rows[id(r)]) for r in root]
            powers = self.find("powerTypes.csv", optional=True)
            self.powers = {p["PowerName"]: p for p in self._csv(powers, "powerTypes", mods)} if powers else {}
            bots = self.find("SpawnBotTypes.xml", optional=True)
            self.spawn_bots: dict[str, int] = {}
            if bots is not None:
                root = ET.parse(bots).getroot()
                self._note(preview.apply("SpawnBotTypes", root, mods))
                self.spawn_bots = {r.get("SpawnBotName"): number(r.findtext("SpawnBotID")) for r in root}

    def find(self, name: str, optional: bool = False) -> Path | None:
        found = sorted(self.root.rglob(name))
        if optional and not found:
            return None
        if len(found) != 1:
            raise preview.ModError(f"{len(found)} files named {name} under {self.root}")
        return found[0]

    def _csv(self, path: Path, table: str, mods: list[dict]) -> list[dict]:
        text, lines = preview.apply_csv(table, path.read_text(encoding="utf-8"), mods)
        self._note(lines)
        rows = list(csv.reader(io.StringIO(text.split("\n", 1)[1])))
        return [dict(zip(rows[0], r)) for r in rows[1:] if r and r[0] and r[0] != "Template"]

    def _note(self, lines: list[str]) -> None:
        self.lines += lines
        for line in lines:
            m = re.match(r"row (added|changed) (\w+)/(.+?)(?: \(copy of [^)]*\))? \([^()]*\)$", line)
            if m:
                key = re.sub(r"^\w+\[(.*)\]$", r"\1", m.group(3))
                self.touched.setdefault(m.group(2), set()).add(key)
                if m.group(1) == "added":
                    self.added.setdefault(m.group(2), set()).add(key)


def field_of(h: ET.Element, name: str) -> str | None:
    return (h.find(name).text or "") if h.find(name) is not None else None


def check(t: Tables) -> tuple[list[str], list[str]]:
    errors, warnings = [], []
    heroes = [h for h in t.heroes if h.get("HeroName") not in (None, "Template")]
    field = field_of
    by_name = {c["CostumeName"]: c for c in t.costumes}
    for h in heroes:
        name = h.get("HeroName")
        if name not in t.touched.get("HeroTypes", set()):
            continue
        where = f"legend {name}"
        for c in h:
            if c.tag not in HERO_FIELDS:
                errors.append(f"{where}: unknown property {c.tag} (HeroType.as:621)")
        hid = (field(h, "HeroID") or "").strip()
        if hid in ("", "0"):
            errors.append(f"{where}: HeroID missing or 0 (HeroType.as:626)")
        elif not hid.isdigit():
            errors.append(f"{where}: HeroID {hid} is not a whole number (HeroType.as:372)")
        elif int(hid) >= 65536:
            errors.append(f"{where}: HeroID {hid} is 65536 or more; the roster keys a crossover skin on HeroID | "
                          "CostumeIndex << 16 and reads the legend back from the low 16 bits (HeroType.as:1020, 1032)")
        if sum(1 for o in heroes if o.get("HeroName") == name) > 1:
            errors.append(f"{where}: duplicate HeroName (HeroType.as:645)")
        if hid and sum(1 for o in heroes if (field(o, "HeroID") or "").strip() == hid) > 1:
            errors.append(f"{where}: duplicate HeroID {hid} (HeroType.as:649)")
        stats = [field(h, s) for s in ("Strength", "Dexterity", "Speed", "Weight")]
        total = sum(int(s) for s in stats if s and s.strip().lstrip("-").isdigit())
        if total not in (0, 22):
            errors.append(f"{where}: Strength+Dexterity+Speed+Weight is {total}, must be 22 (HeroType.as:655)")
        w1, w2 = hero_weapons(field, h)
        doll = field(h, "PaperDollWeapon")
        if doll and doll not in (w1, w2):
            errors.append(f"{where}: PaperDollWeapon {doll} is neither weapon (HeroType.as:659)")
        active_random = truthy(field(h, "IsActive")) and truthy(field(h, "CanRandom"))
        if active_random:
            tags = listed(field(h, "MissionTags"))
            for i, w in enumerate((w1, w2)):
                tag = weapon_tag(w)
                if tag not in tags:
                    errors.append(f"{where}: MissionTags lacks {tag} for weapon {w} (HeroType.as:741)")
                elif tags.index(tag) != i:
                    errors.append(f"{where}: {tag} must be listed {'first' if i == 0 else 'second'} in MissionTags "
                                  "(HeroType.as:745)")
            rewards = listed(field(h, "ColorRewards"))
            if not rewards:
                errors.append(f"{where}: an active, randomable legend needs ColorRewards (HeroType.as:907)")
            for c in rewards:
                if c not in t.colours:
                    errors.append(f"{where}: ColorRewards has unknown colour {c} (HeroType.as:923)")
        if len(listed(field(h, "Rewards"))) != len(listed(field(h, "RewardLevels"))):
            errors.append(f"{where}: Rewards and RewardLevels differ in length (HeroType.as:938)")
        if active_random or truthy(field(h, "IsActive")):
            stance_rules(t, h, name, where, errors, warnings)
        for w in (w1, w2):
            if not any(s.get("OwnerHero") == name and s.get("BaseWeapon") == w for s in t.weapon_skins):
                warnings.append(f"{where}: no default {w} skin in weaponSkinTypes (OwnerHero {name}, BaseWeapon {w}); "
                                "every game legend has one per weapon")
        skin = field(h, "CostumeName")
        if skin not in by_name:
            errors.append(f"{where}: default skin {skin} is not in costumeTypes (HeroType.as:764)")
        else:
            if by_name[skin].get("CostumeIndex", "").strip() not in ("0", ""):
                errors.append(f"{where}: default skin {skin} has CostumeIndex {by_name[skin]['CostumeIndex']}, "
                              "must be 0 (HeroType.as:768)")
            if by_name[skin].get("OwnerHero") != name:
                errors.append(f"{where}: default skin {skin} belongs to {by_name[skin].get('OwnerHero')}")
    rune_rows(t, {h.get("HeroName") for h in heroes}, errors, warnings)
    weapons_of = {h.get("HeroName"): hero_weapons(field, h) for h in heroes}
    owners = weapon_owners(t.costumes, weapons_of)
    for s in t.weapon_skins:
        name = s["WeaponSkinName"]
        if name not in t.touched.get("weaponSkinTypes", set()):
            continue
        if bool(s.get("DbID", "").strip()) == bool(owners.get(name)):
            errors.append(f"weapon skin {name}: needs a DbID or a skin that owns it (a costumeTypes row whose "
                          "legend weapon + WeaponSet makes this name), not both or neither: the game stops at start-up "
                          "(class_725.as:764)")
    alt_sig = {h.get("HeroName"): set(listed(field(h, "AltSigModeCostumes"))) for h in heroes}
    skin_names = {s["WeaponSkinName"] for s in t.weapon_skins}
    hero_names = set(weapons_of)
    for c in t.costumes:
        name = c["CostumeName"]
        if name not in t.touched.get("costumeTypes", set()):
            continue
        where = f"skin {name}"
        if sum(1 for o in t.costumes if o["CostumeName"] == name) > 1:
            errors.append(f"{where}: duplicate CostumeName (CostumeType.as:971)")
        if sum(1 for o in t.costumes if o["CostumeID"] == c["CostumeID"]) > 1:
            errors.append(f"{where}: duplicate CostumeID {c['CostumeID']} (CostumeType.as:975)")
        if c.get("OwnerHero") not in hero_names:
            errors.append(f"{where}: OwnerHero {c.get('OwnerHero')} is not a legend (CostumeType.as:980)")
        if " " in name:
            errors.append(f"{where}: space in CostumeName (CostumeType.as:984)")
        for w in weapons_of.get(c.get("OwnerHero"), ()):
            if w + c.get("WeaponSet", "") not in skin_names:
                errors.append(f"{where}: its {w} skin {w + c.get('WeaponSet', '')} (weapon + WeaponSet) is not in "
                              "weaponSkinTypes: the game stops at start-up (CostumeType.as:1058, HeroType.as:818)")
        crossover_rules(c, by_name, name in t.added.get("costumeTypes", set()), where, errors, warnings)
        costume_index_rules(c, t.costumes, alt_sig.get(c.get("OwnerHero"), set()), where, warnings)
    upgrade_rules(t.costumes, "CostumeName", "OwnerHero", "skin", "CostumeType.as",
                  (378, 382, 386, 405), t.touched.get("costumeTypes", set()), errors)
    upgrade_rules(t.weapon_skins, "WeaponSkinName", "BaseWeapon", "weapon skin", "class_725.as",
                  (230, 234, 238, 242), t.touched.get("weaponSkinTypes", set()), errors)
    power_swap_rules(t, hero_names, by_name, errors, warnings)
    return errors, warnings


def stance_rules(t: Tables, h: ET.Element, name: str, where: str, errors: list[str], warnings: list[str]) -> None:
    group = t.stances.get(name)
    if group is None:
        errors.append(f"{where}: no stances in RuneTypes (a row with <HeroName>{name}</HeroName> and nine "
                      "more): the game stops at start-up (class_356.as:328)")
        return
    seen: dict[str, int] = {}
    for s in group:
        idx = s.get("RuneIndex", "")
        seen[idx] = seen.get(idx, 0) + 1
        for stat in ("Strength", "Dexterity", "Weight", "Speed"):
            if s.get(stat, "0").isdigit() and int(s.get(stat, "0")) > 11:
                errors.append(f"{where}: stance {idx} has {stat} {s[stat]}, above 11 (class_356.as:190)")
    for idx, n in seen.items():
        if n > 1:
            errors.append(f"{where}: duplicate stance index {idx} (class_356.as:206)")
    for i in range(STANCES):
        if str(i) not in seen:
            errors.append(f"{where}: missing stance index {i} (class_356.as:{339 if i == 0 else 353})")
    base = next((s for s in group if s.get("RuneIndex") == "0"), None)
    wanted = {k: (field_of(h, k) or "").strip() for k in ("Strength", "Dexterity", "Weight", "Speed")}
    if base and any(base.get(k) != v for k, v in wanted.items()):
        warnings.append(f"{where}: base stance (index 0) {[base.get(k) for k in wanted]} differs from "
                        f"its HeroTypes stats {list(wanted.values())}; every game legend has them equal")


def rune_rows(t: Tables, hero_names: set[str], errors: list[str], warnings: list[str]) -> None:
    for mod_id, rows in t.rune_added.items():
        first, hero = rows[0]
        if first.find("HeroName") is None:
            errors.append(f"RuneTypes rows of {mod_id}: the first one (RuneIndex {first.findtext('RuneIndex')}) has no "
                          f"HeroName, so they join {hero}'s stances; a row without HeroName belongs to the last HeroName "
                          "above it (class_356.as:147)")
        for r, owner in rows:
            idx = (r.findtext("RuneIndex") or "").strip()
            if not idx.isdigit() or int(idx) >= STANCES:
                errors.append(f"RuneTypes row of {mod_id} for {owner}: RuneIndex {idx or '(none)'}; a legend's stances "
                              f"are a fixed list of {STANCES} (0-9), so the game stops while reading RuneTypes "
                              "(class_356.as:151, 181)")
        for owner in sorted({o for _, o in rows if o is not None} - hero_names):
            warnings.append(f"RuneTypes rows of {mod_id}: stances for {owner}, which is not a legend in HeroTypes")


def weapon_owners(costumes: list[dict], weapons_of: dict) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for c in costumes:
        hero = c.get("OwnerHero")
        if hero not in weapons_of:
            continue
        collectors = c["CostumeName"] == "Collectors"
        if not collectors and (truthy(c.get("DoesNotOwnWeaponSet")) or c.get("WeaponSet", "") == "Asgard"):
            continue
        for w in weapons_of[hero]:
            out.setdefault(w + c.get("WeaponSet", ""), []).append(c["CostumeName"])
    return out


def crossover_rules(c: dict, by_name: dict, added: bool, where: str, errors: list[str], warnings: list[str]) -> None:
    g = lambda k: (c.get(k) or "").strip()
    if bool(g("ReplacementPortrait")) != bool(g("ReplacementPortraitFileName")):
        errors.append(f"{where}: ReplacementPortrait and ReplacementPortraitFileName must be set together "
                      "(CostumeType.as:988)")
    if bool(g("CrossoverGem")) != bool(g("CrossoverGemFileName")):
        errors.append(f"{where}: CrossoverGem and CrossoverGemFileName must be set together (CostumeType.as:992)")
    parent, roster = g("ParentCrossover"), number(g("RosterOrderID"))
    if truthy(g("IsCrossover")):
        if (roster != 0) == bool(parent):
            errors.append(f"{where}: a crossover needs a RosterOrderID or a ParentCrossover, not both or neither "
                          "(CostumeType.as:1001)")
        if not g("ReplacementPortrait") and not parent:
            errors.append(f"{where}: a crossover without ParentCrossover needs a ReplacementPortrait "
                          "(CostumeType.as:1005)")
        if bool(g("CrossoverGem")) == bool(parent):
            text = (f"{where}: a crossover needs a CrossoverGem or a ParentCrossover, not both or neither "
                    "(CostumeType.as:1009)")
            if added:
                warnings.append(text + "; bifrost waives this one for skins a mod adds (ContentMods.waiveCheck), "
                                       "the stock client stops")
            else:
                errors.append(text)
        if number(g("CostumeIndex")) == 0:
            errors.append(f"{where}: a crossover can't have CostumeIndex 0 (CostumeType.as:1014)")
    else:
        if parent:
            errors.append(f"{where}: ParentCrossover {parent} but IsCrossover isn't TRUE (CostumeType.as:1021)")
        if roster > 0:
            errors.append(f"{where}: RosterOrderID {roster} but IsCrossover isn't TRUE (CostumeType.as:1025)")
    if parent:
        p = by_name.get(parent)
        if p is None:
            errors.append(f"{where}: ParentCrossover {parent} is not a skin (CostumeType.as:354)")
        else:
            if not truthy(p.get("IsCrossover")):
                errors.append(f"{where}: ParentCrossover {parent} is not a crossover (CostumeType.as:360)")
            if p.get("OwnerHero") != c.get("OwnerHero"):
                errors.append(f"{where}: ParentCrossover {parent} belongs to {p.get('OwnerHero')} (CostumeType.as:364)")
            if (p.get("ParentCrossover") or "").strip():
                errors.append(f"{where}: ParentCrossover {parent} has a ParentCrossover itself (CostumeType.as:368)")


def costume_index_rules(c: dict, costumes: list[dict], alt_sig: set[str], where: str, warnings: list[str]) -> None:
    index = c.get("CostumeIndex", "").strip()
    same = [o["CostumeName"] for o in costumes if o is not c and o.get("OwnerHero") == c.get("OwnerHero")
            and o.get("CostumeIndex", "").strip() == index]
    if same:
        warnings.append(f"{where}: CostumeIndex {index} is also {same[0]}'s; owned skins are a bit mask by index "
                        "(class_719.method_8971), so they would share ownership")
    if not index.isdigit():
        return
    mine = int(index)
    for o in costumes:
        other = o.get("CostumeIndex", "").strip()
        if o is c or o.get("OwnerHero") != c.get("OwnerHero") or not other.isdigit() or int(other) == mine:
            continue
        if int(other) % 32 != mine % 32:
            continue
        high = c["CostumeName"] if mine > int(other) else o["CostumeName"]
        if mine % 32 == 0 and high in alt_sig:
            continue
        warnings.append(f"{where}: CostumeIndex {index} uses ownership bit {mine % 32}, the same as {o['CostumeName']} "
                        f"(CostumeIndex {other}); the mask is 32 bits and the shift count wraps (class_719.method_8971), "
                        "so they are owned together. only the alternate form in AltSigModeCostumes may share the "
                        "default skin's bit (index 32)")


def upgrade_rules(rows: list[dict], key: str, owner: str, kind: str, source: str, lines: tuple[int, int, int, int],
                  touched: set[str], errors: list[str]) -> None:
    by = {r[key]: r for r in rows}
    up = {r[key]: (r.get("UpgradesTo") or "").strip() for r in rows}
    sources: dict[str, list[str]] = {}
    for name, target in up.items():
        if target:
            sources.setdefault(target, []).append(name)
    for name, target in up.items():
        if not target or (name not in touched and target not in touched):
            continue
        where = f"{kind} {name}"
        if target not in by:
            errors.append(f"{where}: UpgradesTo {target}, which doesn't exist ({source}:{lines[0]})")
            continue
        seen, step = {name}, target
        while step and step in by and step not in seen:
            seen.add(step)
            step = up.get(step, "")
        if step == name:
            errors.append(f"{where}: UpgradesTo {target} leads back to {name} ({source}:{lines[1]})")
        if by[target].get(owner) != by[name].get(owner):
            errors.append(f"{where}: {owner} {by[name].get(owner)} but its upgrade {target} has "
                          f"{by[target].get(owner)} ({source}:{lines[2]})")
        if kind == "weapon skin" and (by[name].get("OwnerHero") or by[target].get("OwnerHero")):
            errors.append(f"{where}: upgrades to {target} but one of them has an OwnerHero (class_725.as:253)")
    for target, names in sorted(sources.items()):
        if len(names) > 1 and target in by and (target in touched or any(n in touched for n in names)):
            errors.append(f"{kind} {target}: the upgrade of both {names[0]} and {names[1]} (UpgradesTo); a {kind} can be "
                          f"the upgrade of only one other, and a copy keeps its source's UpgradesTo (set it to @none) "
                          f"({source}:{lines[3]})")


def power_swap_rules(t: Tables, hero_names: set[str], by_name: dict, errors: list[str], warnings: list[str]) -> None:
    if t.swaps is None:
        return
    known = t.swap_columns
    plain_skins: dict[str, list[str]] = {}
    for c in t.costumes:
        if not truthy(c.get("IsCrossover")):
            plain_skins.setdefault(c.get("OwnerHero"), []).append(c["CostumeName"])
    touched_skins = t.touched.get("costumeTypes", set())
    keys: dict[tuple, tuple[str, bool]] = {}
    for row, mine in t.swaps:
        owner = row.get("OwnerCostume")
        if owner == "Template":
            continue
        target = (row.findtext("TargetPower") or "").strip()
        label = f"power swap {target} ({' '.join(f'{k}={v}' for k, v in sorted(row.attrib.items()))})"
        if mine:
            for c in row:
                if c.tag not in known:
                    errors.append(f"{label}: unknown property {c.tag} (class_306.as:154)")
            if any(x.startswith("Once:") for x in listed(row.findtext("HitSoundEvent"))):
                errors.append(f"{label}: 'Once:' in HitSoundEvent belongs in powerTypes only (class_306.as:141)")
        power = t.powers.get(target)
        if power is None:
            if mine:
                warnings.append(f"{label}: TargetPower {target or '(none)'} is not in powerTypes, so the game skips "
                                "the row")
            continue
        if mine:
            for g in SWAP_GFX:
                el = row.find(g)
                if el is not None and len(el) and not (power.get(g + ".AnimClass") or "").strip():
                    errors.append(f"{label}: a {g} swap, but {target} has no {g} (class_304.as:{SWAP_GFX_CITE[g]})")
            if (row.findtext("HitSoundEvent") or "").strip() and not (power.get("HitSoundEvent") or "").strip():
                errors.append(f"{label}: a HitSoundEvent swap, but {target} has none (class_304.as:542)")
        skins = listed(owner) if owner is not None else None
        if row.get("OwnerHero") is not None:
            skins = skins or []
            for hero in listed(row.get("OwnerHero")):
                if hero not in hero_names:
                    if mine:
                        warnings.append(f"{label}: OwnerHero {hero} is not a legend; the game stops reading the list "
                                        "there")
                    break
                skins += plain_skins.get(hero, [])
        bots = listed(row.get("OwnerSpawnBot")) if row.get("OwnerSpawnBot") is not None else None
        if skins is None and bots is None:
            if mine:
                warnings.append(f"{label}: no OwnerCostume, OwnerHero or OwnerSpawnBot, so it applies to nothing")
            continue
        asym = truthy(row.findtext("AsymRight"))
        pid = number(power.get("PowerID"))

        def register(cid: int, bot: str | None, skin: str | None) -> None:
            if bot is not None and bot not in t.spawn_bots:
                if mine:
                    errors.append(f"{label}: OwnerSpawnBot {bot} is not in SpawnBotTypes (class_306.as:379)")
                return
            bid = t.spawn_bots.get(bot, 0) if bot else 0
            key = ("asym", cid, pid) if asym else ("swap", pid, bid, cid)
            if asym and mine and (cid > 65535 or pid > 65535):
                errors.append(f"{label}: AsymRight needs CostumeID and PowerID up to 65535 (class_306.as:186, 190)")
            prev = keys.get(key)
            if prev is not None and (mine or prev[1] or skin in touched_skins):
                who = (f"skin {skin}" if skin else "any skin") + (f" and bot {bot}" if bot else "")
                errors.append(f"{label}: {who} already has {'an AsymRight' if asym else 'a'} swap for {target} from "
                              f"{prev[0]}; the game stops on a second one (class_306.as:{194 if asym else 215}). rows "
                              "with OwnerHero apply to every skin of the legend that isn't a crossover")
            keys[key] = (label, mine or bool(prev and prev[1]))

        if skins is None:
            for b in bots:
                register(0, b, None)
            continue
        for skin in skins:
            c = by_name.get(skin)
            if c is None:
                if mine:
                    errors.append(f"{label}: OwnerCostume {skin} is not a skin (class_306.as:339)")
                continue
            for b in (bots if bots is not None else [None]):
                register(number(c.get("CostumeID")), b, skin)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("mods", nargs="+", type=Path, help="mod folders (each with a mod.json)")
    p.add_argument("--tables", type=Path, default=ROOT / "build" / "tabledata",
                   help="extracted tables (tools/extract_client_data.mjs output)")
    args = p.parse_args(argv)
    try:
        mods = preview.order([preview.load_manifest(m) for m in args.mods])
        tables = Tables(args.tables, mods)
    except preview.ModError as e:
        print(f"check FAILED: {e}", file=sys.stderr)
        return 1
    errors, warnings = check(tables)
    checked = sum(len(tables.touched.get(k, set())) for k in ("HeroTypes", "costumeTypes", "weaponSkinTypes"))
    for line in errors:
        print(f"error {line}")
    for line in warnings:
        print(f"warning {line}")
    print(f"{checked} legend, skin and weapon skin rows checked: {len(errors)} errors, {len(warnings)} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
