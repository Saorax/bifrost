"""check a legend mod against the game's own legend and skin rules, without starting the game.

    python tools/check_legend_mod.py examples/mods/sample-legend [more mod folders] [--tables build/tabledata]

the game checks its tables as it parses them, and a failed check throws: one bad row stops the whole archive from
loading ("File Loading Error"). this applies the mods to the extracted tables the same way the loader does
(``tools/preview_content_mod.py``), then runs the checks from the 10.11 code on every legend (HeroTypes row) and
skin (costumeTypes row) a mod adds or changes. each finding cites the check's place in ``src/as3/10.11/scripts``.

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


def weapon_tag(weapon: str) -> str:
    return "LanceUser" if weapon == "RocketLance" else weapon + "User"


def listed(text: str | None) -> list[str]:
    return [x.strip() for x in (text or "").split(",") if x.strip()]


def truthy(text: str | None) -> bool:
    return (text or "").strip().lower() == "true"


class Tables:

    def __init__(self, tables: Path, mods: list[dict]):
        def find(name: str) -> Path:
            found = sorted(tables.rglob(name))
            if len(found) != 1:
                raise preview.ModError(f"{len(found)} files named {name} under {tables}")
            return found[0]
        self.touched: dict[str, set[str]] = {}
        self.lines: list[str] = []
        self.heroes = ET.parse(find("HeroTypes.xml")).getroot()
        self._note(preview.apply("HeroTypes", self.heroes, mods))
        colours = ET.parse(find("ColorSchemeTypes.xml")).getroot()
        self._note(preview.apply("ColorSchemeTypes", colours, mods))
        self.colours = {r.get("ColorSchemeName") for r in colours}
        self.costumes = self._csv(find("costumeTypes.csv"), "costumeTypes", mods)
        self.weapon_skins = self._csv(find("weaponSkinTypes.csv"), "weaponSkinTypes", mods)
        runes = ET.parse(find("RuneTypes.xml")).getroot()
        self._note(preview.apply("RuneTypes", runes, mods))
        self.stances: dict[str, list[dict]] = {}
        hero = None
        for r in runes:
            if r.find("HeroName") is not None:
                hero = r.findtext("HeroName")
                self.stances[hero] = []
            if hero is not None:
                self.stances[hero].append({c.tag: (c.text or "").strip() for c in r})

    def _csv(self, path: Path, table: str, mods: list[dict]) -> list[dict]:
        text, lines = preview.apply_csv(table, path.read_text(encoding="utf-8"), mods)
        self._note(lines)
        rows = list(csv.reader(io.StringIO(text.split("\n", 1)[1])))
        return [dict(zip(rows[0], r)) for r in rows[1:] if r and r[0] and r[0] != "Template"]

    def _note(self, lines: list[str]) -> None:
        self.lines += lines
        for line in lines:
            m = re.match(r"row (?:added|changed) (\w+)/(.+?)(?: \(copy of [^)]*\))? \([^()]*\)$", line)
            if m:
                key = re.sub(r"^\w+\[(.*)\]$", r"\1", m.group(2))
                self.touched.setdefault(m.group(1), set()).add(key)


def check(t: Tables) -> tuple[list[str], list[str]]:
    errors, warnings = [], []
    heroes = [h for h in t.heroes if h.get("HeroName") not in (None, "Template")]
    field = lambda h, name: (h.find(name).text or "") if h.find(name) is not None else None
    by_name = {c["CostumeName"]: c for c in t.costumes}
    for h in heroes:
        name = h.get("HeroName")
        if name not in t.touched.get("HeroTypes", set()):
            continue
        where = f"legend {name}"
        for c in h:
            if c.tag not in HERO_FIELDS:
                errors.append(f"{where}: unknown property {c.tag} (HeroType.as:621)")
        hid = field(h, "HeroID")
        if not hid or hid.strip() in ("", "0"):
            errors.append(f"{where}: HeroID missing or 0 (HeroType.as:626)")
        if sum(1 for o in heroes if o.get("HeroName") == name) > 1:
            errors.append(f"{where}: duplicate HeroName (HeroType.as:645)")
        if hid and sum(1 for o in heroes if field(o, "HeroID") == hid) > 1:
            errors.append(f"{where}: duplicate HeroID {hid} (HeroType.as:649)")
        stats = [field(h, s) for s in ("Strength", "Dexterity", "Speed", "Weight")]
        total = sum(int(s) for s in stats if s and s.strip().lstrip("-").isdigit())
        if total not in (0, 22):
            errors.append(f"{where}: Strength+Dexterity+Speed+Weight is {total}, must be 22 (HeroType.as:655)")
        w1, w2 = field(h, "BaseWeapon1"), field(h, "BaseWeapon2")
        doll = field(h, "PaperDollWeapon")
        if doll and doll not in (w1, w2):
            errors.append(f"{where}: PaperDollWeapon {doll} is neither weapon (HeroType.as:659)")
        active_random = truthy(field(h, "IsActive")) and truthy(field(h, "CanRandom"))
        if active_random:
            tags = listed(field(h, "MissionTags"))
            for i, w in enumerate((w1, w2)):
                tag = weapon_tag(w or "")
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
            group = t.stances.get(name)
            if group is None:
                errors.append(f"{where}: no stances in RuneTypes (a row with <HeroName>{name}</HeroName> and nine "
                              "more): the game stops at start-up (class_356.as:328)")
            else:
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
                for i in range(10):
                    if str(i) not in seen:
                        errors.append(f"{where}: missing stance index {i} (class_356.as:{339 if i == 0 else 353})")
                base = next((s for s in group if s.get("RuneIndex") == "0"), None)
                wanted = {k: (field(h, k) or "").strip() for k in ("Strength", "Dexterity", "Weight", "Speed")}
                if base and any(base.get(k) != v for k, v in wanted.items()):
                    warnings.append(f"{where}: base stance (index 0) {[base.get(k) for k in wanted]} differs from "
                                    f"its HeroTypes stats {list(wanted.values())}; every game legend has them equal")
        for w in (w1, w2):
            if w and not any(s.get("OwnerHero") == name and s.get("BaseWeapon") == w for s in t.weapon_skins):
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
    hero_names = {h.get("HeroName") for h in heroes}
    weapons_of = {h.get("HeroName"): (field(h, "BaseWeapon1"), field(h, "BaseWeapon2")) for h in heroes}
    for s in t.weapon_skins:
        name = s["WeaponSkinName"]
        if name not in t.touched.get("weaponSkinTypes", set()):
            continue
        owned = any(c.get("OwnerHero") in weapons_of and not truthy(c.get("DoesNotOwnWeaponSet"))
                    and name in {(w or "") + c.get("WeaponSet", "") for w in weapons_of[c["OwnerHero"]]}
                    for c in t.costumes if c.get("WeaponSet"))
        if bool(s.get("DbID", "").strip()) == owned:
            errors.append(f"weapon skin {name}: needs a DbID or a skin that owns it (a costumeTypes row whose "
                          "legend weapon + WeaponSet makes this name), not both or neither: the game stops at start-up "
                          "(class_725.as:764)")
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
        skin_names = {s["WeaponSkinName"] for s in t.weapon_skins}
        for w in weapons_of.get(c.get("OwnerHero"), ()):
            if w and w + c.get("WeaponSet", "") not in skin_names:
                errors.append(f"{where}: its {w} skin {w + c.get('WeaponSet', '')} (weapon + WeaponSet) is not in "
                              "weaponSkinTypes: the game stops at start-up (CostumeType.as:1058, HeroType.as:818)")
        index = c.get("CostumeIndex", "").strip()
        same = [o["CostumeName"] for o in t.costumes if o is not c and o.get("OwnerHero") == c.get("OwnerHero")
                and o.get("CostumeIndex", "").strip() == index]
        if same:
            warnings.append(f"{where}: CostumeIndex {index} is also {same[0]}'s; owned skins are a bit mask by index "
                            "(class_719.method_8971), so they would share ownership")
        if index.isdigit() and int(index) > 31:
            warnings.append(f"{where}: CostumeIndex {index} is past the 32-bit ownership mask")
    return errors, warnings


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
    checked = len(tables.touched.get("HeroTypes", set())) + len(tables.touched.get("costumeTypes", set()))
    for line in errors:
        print(f"error {line}")
    for line in warnings:
        print(f"warning {line}")
    print(f"{checked} legend and skin rows checked: {len(errors)} errors, {len(warnings)} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
