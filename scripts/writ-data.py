#!/usr/bin/env python3
"""Usage: scripts/writ-data.py <questie-db-dir> <tooltip-cache-dir> [--fetch] [--build <version>]

Writes Data/Writs.lua and Data/WaylaidCrates.lua from scripts/data/writs-forever.tsv,
scripts/data/waylaid-crates.tsv, the QuestieDB Forever addon in <questie-db-dir> and the
Wowhead Forever tooltips in <tooltip-cache-dir> (<item_id>.json, names.json). Item names come
from the tooltips (crates, sealed crates, writs, requested and bundle items), else from the TSV.
--fetch downloads missing tooltips and bundle item IDs into the cache first.
--build sets the game build named in the generated headers (default 1.60.1).
"""
import base64
import csv
import html
import json
import re
import struct
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

DEFAULT_BUILD = "1.60.1"
BUILD = DEFAULT_BUILD
ROOT = Path(__file__).resolve().parent.parent
CAMP_FACTION = {"Alliance": 2586, "Horde": 2587}
TIER_ORDER = ["apprentice", "journeyman", "expert", "artisan"]
FAVOR = {
    "gathered": dict(zip(TIER_ORDER, (5, 10, 15, 20))),
    "crafted": dict(zip(TIER_ORDER, (10, 20, 30, 40))),
}
UNCONFIRMED_TIERS = {"artisan"}
PREFIX = "Waylaid Crate: "
WRIT_PREFIX = "Craftsman's Writ: "
SEALED_TIERS = ["apprentice", "journeyman", "expert", "artisan", "elite"]
SEALED_FIRST = {1: 248765, 2: 248770, 3: 248775}
SEALED_KIND = {1: "gathered", 2: "crafted", 3: None}
UNLABELED_CRATE = 248549
RECEIPT = 262902
SEARCH_MISSES = {"Runecloth": 14047}
TOOLTIP_URL = "https://nether.wowhead.com/forever/tooltip/item/"
SEARCH_URL = "https://www.wowhead.com/forever/search/suggestions-template?q="


def cbor_decode(data):
    pos = 0

    def length(info):
        nonlocal pos
        if info < 24:
            return info
        size = {24: 1, 25: 2, 26: 4, 27: 8}.get(info)
        if size is None:
            raise ValueError("Unsupported CBOR length")
        value = int.from_bytes(data[pos:pos + size], "big")
        pos += size
        return value

    def item(depth=0):
        nonlocal pos
        if depth > 100 or pos >= len(data):
            raise ValueError("Malformed CBOR")
        head = data[pos]
        pos += 1
        major, info = head >> 5, head & 31
        if major == 7:
            if info in (20, 21, 22, 23):
                return {20: False, 21: True, 22: None, 23: None}[info]
            fmt = {25: ">e", 26: ">f", 27: ">d"}.get(info)
            if not fmt:
                raise ValueError("Unsupported CBOR simple value")
            size = struct.calcsize(fmt)
            value = struct.unpack(fmt, data[pos:pos + size])[0]
            pos += size
            return value
        n = length(info)
        if major == 0:
            return n
        if major == 1:
            return -1 - n
        if major in (2, 3):
            chunk = data[pos:pos + n]
            pos += n
            return chunk.decode("utf-8", "replace")
        if major == 4:
            return [item(depth + 1) for _ in range(n)]
        if major == 5:
            out = {}
            for _ in range(n):
                key = item(depth + 1)
                out[key] = item(depth + 1)
            return out
        if major == 6:
            return item(depth + 1)
        raise ValueError("Unsupported CBOR type")

    return item()


class Questie:
    def __init__(self, folder):
        self.folder = Path(folder)
        self.meta = {}
        with open(self.folder / "QuestieDB_Forever.toc", encoding="utf-8") as f:
            for line in f:
                if line.startswith("## "):
                    key, sep, value = line[3:].rstrip("\r\n").partition(": ")
                    if sep:
                        self.meta[key] = value
        match = re.search(r"v([0-9.]+)", self.meta.get("Title", ""))
        self.version = match.group(1) if match else "unknown"
        self.areas, self.zone_names = self.read_zones()

    def stored(self, key):
        value = self.meta.get(key)
        if value is None:
            return None
        count = re.fullmatch(r"~(\d+)~", value)
        if not count:
            return value
        return "".join(self.meta[f"{key}-{i}"] for i in range(1, int(count.group(1)) + 1))

    def decode(self, key):
        value = self.stored(key)
        return None if value is None else cbor_decode(base64.b64decode(value))

    def read_zones(self):
        text = (self.folder / "support/Forever/Zones/areaIdToUiMapId.lua").read_text(encoding="utf-8")
        areas, names = {}, {}
        for area, map_id, comment in re.findall(r"\[(\d+)\]\s*=\s*(\d+),\s*--\s*(.+)", text):
            areas.setdefault(int(area), int(map_id))
            comment = comment.strip()
            if "->" not in comment and ":" not in comment:
                names.setdefault(comment, int(map_id))
        return areas, names

    def finisher(self, quest_id):
        finished = self.decode(f"X-Quest-{quest_id}-3")
        if not finished or not finished[0]:
            return None
        npc_id = finished[0][0]
        row = self.decode(f"X-Npc-{npc_id}-S")
        if not row:
            return None
        found = {"npcID": npc_id, "npc": row.get(1), "friendly": row.get(13)}
        for area, spawns in (self.decode(f"X-Npc-{npc_id}-7") or {}).items():
            if area in self.areas and spawns:
                found.update(areaID=area, mapID=self.areas[area], x=round(spawns[0][0], 2), y=round(spawns[0][1], 2))
                break
        return found

    def camp_factions(self, quest_id):
        rewards = self.decode(f"X-Quest-{quest_id}-26") or []
        return {pair[0] for pair in rewards}


def lua_str(text):
    out = []
    for byte in text.encode("utf-8"):
        ch = chr(byte)
        if ch in '"\\':
            out.append("\\" + ch)
        elif 32 <= byte < 127:
            out.append(ch)
        else:
            out.append(f"\\{byte:03d}")
    return '"' + "".join(out) + '"'


def lua_val(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, int):
        return str(value)
    return lua_str(value)


def lua_row(fields):
    return "{ " + ", ".join(f"{k} = {v}" for k, v in fields if v is not None) + " }"


def http_get(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8")


def tsv_rows(path):
    with open(path, newline="", encoding="utf-8") as f:
        lines = [line for line in f if not line.startswith("#")]
    return list(csv.DictReader(lines, delimiter="\t", quoting=csv.QUOTE_NONE))


class Tooltips:
    def __init__(self, cache, fetch):
        self.cache, self.fetch = cache, fetch

    def get(self, item_id):
        path = self.cache / f"{item_id}.json"
        if not path.exists():
            if not self.fetch:
                return None
            path.write_text(http_get(TOOLTIP_URL + str(item_id)), encoding="utf-8")
            time.sleep(0.3)
        return json.loads(path.read_text(encoding="utf-8"))

    def name(self, item_id, fallback, prefix=""):
        tip = self.get(item_id)
        name = tip and tip.get("name")
        if not name:
            return fallback
        if prefix:
            if not name.startswith(prefix):
                sys.exit(f"item {item_id}: {name!r} does not start with {prefix!r}")
            name = name[len(prefix):]
        return name


def build_writs(questie, tips):
    rows = tsv_rows(ROOT / "scripts/data/writs-forever.tsv")
    camps = set()
    out = []
    for r in rows:
        quest_id = int(r["quest_id"])
        camps |= questie.camp_factions(quest_id)
        found = questie.finisher(quest_id)
        if found and "mapID" in found:
            zone = next((n for n, m in questie.zone_names.items() if m == found["mapID"]), r["turnin_zone"] or None)
            where = dict(found, zone=zone)
        else:
            where = {"npc": r["turnin_npc"] or None}
            if r["turnin_zone"]:
                if r["turnin_zone"] not in questie.zone_names:
                    sys.exit(f"unmapped zone {r['turnin_zone']!r} (quest {quest_id})")
                where.update(zone=r["turnin_zone"], mapID=questie.zone_names[r["turnin_zone"]])
                if r["turnin_x"]:
                    where.update(x=float(r["turnin_x"]), y=float(r["turnin_y"]))
            if found:
                where.update(npcID=found["npcID"], npc=found["npc"] or where["npc"], friendly=found["friendly"])
        out.append(lua_row([
            ("tier", lua_val(r["tier"])), ("profession", lua_val(r["profession"])), ("skill", int(r["skill"])),
            ("writID", int(r["writ_id"])), ("name", lua_val(tips.name(int(r["writ_id"]), r["writ"], WRIT_PREFIX))),
            ("questID", quest_id), ("itemID", int(r["item_id"])), ("item", lua_val(tips.name(int(r["item_id"]), r["item"]))), ("qty", int(r["qty"])), ("rep", int(r["rep"])),
            ("npcID", where.get("npcID")), ("npc", lua_val(where["npc"]) if where.get("npc") else None),
            ("friendly", lua_val(where["friendly"]) if where.get("friendly") else None),
            ("zone", lua_val(where["zone"]) if where.get("zone") else None), ("mapID", where.get("mapID")),
            ("x", where.get("x")), ("y", where.get("y")),
        ]))
    if camps != set(CAMP_FACTION.values()):
        sys.exit(f"QuestieDB camp factions {sorted(camps)} differ from {CAMP_FACTION}")
    return out


def bundle_lines(tooltip):
    return [(int(n), html.unescape(name).strip()) for n, name in re.findall(r"<br />- (\d+) ([^<]+)", tooltip)]


def resolve_names(cache, names, fetch):
    path = cache / "names.json"
    known = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    for name in sorted(set(names) - set(known)):
        if not fetch:
            sys.exit(f"bundle item {name!r} not in {path}; run with --fetch")
        results = json.loads(http_get(SEARCH_URL + urllib.parse.quote(name)))["results"]
        match = next((r["id"] for r in results if r.get("type") == 3 and r["name"] == name), None)
        if match is None and name in SEARCH_MISSES:
            match = SEARCH_MISSES[name]
            if json.loads(http_get(TOOLTIP_URL + str(match)))["name"] != name:
                sys.exit(f"SEARCH_MISSES id {match} is not {name!r}")
        if match is None:
            sys.exit(f"cannot resolve bundle item {name!r}")
        known[name] = match
        time.sleep(0.3)
    path.write_text(json.dumps(known, indent=1, sort_keys=True), encoding="utf-8")
    return known


def build_crates(cache, tips):
    crates = [(int(r["item_id"]), r["tier"], r["kind"]) for r in tsv_rows(ROOT / "scripts/data/waylaid-crates.tsv")]
    parsed = []
    for item_id, tier, kind in crates:
        tip = tips.get(item_id)
        if tip is None:
            sys.exit(f"{cache / f'{item_id}.json'} missing; run with --fetch")
        if not tip["name"].startswith(PREFIX):
            sys.exit(f"item {item_id} is not a labeled crate: {tip['name']!r}")
        name = tip["name"][len(PREFIX):]
        if tier not in name.lower().split():
            sys.exit(f"item {item_id}: tier {tier} not in name {name!r}")
        lines = bundle_lines(tip["tooltip"])
        if not lines:
            sys.exit(f"item {item_id} ({name}): no bundle lines")
        parsed.append((item_id, name, tier, kind, lines))
    ids = resolve_names(cache, [n for p in parsed for _, n in p[4]], tips.fetch)
    out = []
    for item_id, name, tier, kind, lines in parsed:
        bundles = ", ".join(
            lua_row([("itemID", ids[n]), ("name", lua_val(tips.name(ids[n], n))), ("count", c)]) for c, n in lines
        )
        out.append(lua_row([
            ("itemID", item_id), ("name", lua_val(name)), ("tier", lua_val(tier)), ("kind", lua_val(kind)),
            ("favor", FAVOR[kind][tier]), ("confirmed", lua_val(tier not in UNCONFIRMED_TIERS)),
            ("bundles", "{ " + bundles + " }"),
        ]))
    return out


def build_sealed(tips):
    out = []
    for quality, first in SEALED_FIRST.items():
        for i, tier in enumerate(SEALED_TIERS):
            item_id = first + i
            tip = tips.get(item_id)
            if tip and (tip.get("name") != f"Sealed {tier.capitalize()} Crate" or tip.get("quality") != quality):
                sys.exit(f"sealed crate {item_id}: {tip.get('name')!r} quality {tip.get('quality')} is not {tier} {quality}")
            kind = SEALED_KIND[quality]
            out.append(f"    [{item_id}] = " + lua_row([("tier", lua_val(tier)), ("kind", lua_val(kind) if kind else None)]) + ",")
    return out


def write(name, header, body, tail=()):
    lines = ["local _, ns = ...", "if ns.IS_FOREVER == false then return end", "", *header, "ns.Data = ns.Data or {}", *body, *tail]
    (ROOT / "Data" / name).write_text("\n".join(lines) + "\n", encoding="ascii")


def main():
    global BUILD
    argv = sys.argv[1:]
    fetch = "--fetch" in argv
    args = [a for a in argv if a != "--fetch"]
    if "--build" in args:
        i = args.index("--build")
        if i + 1 >= len(args) or args[i + 1].startswith("--"):
            sys.exit(__doc__)
        BUILD = args[i + 1]
        del args[i:i + 2]
    if len(args) != 2:
        sys.exit(__doc__)
    questie, cache = Questie(args[0]), Path(args[1]).expanduser()
    cache.mkdir(parents=True, exist_ok=True)
    tips = Tooltips(cache, fetch)

    writs = build_writs(questie, tips)
    write(
        "Writs.lua",
        [
            f"-- Generated by scripts/writ-data.py from scripts/data/writs-forever.tsv and QuestieDB Forever {questie.version} (GPL-3.0), build {BUILD}.",
        ],
        ["ns.Data.Writs = {", *[f"    {row}," for row in writs], "}"],
        [
            f"ns.Data.CampFaction = {{ Alliance = {CAMP_FACTION['Alliance']}, Horde = {CAMP_FACTION['Horde']} }}",
        ],
    )
    crates = build_crates(cache, tips)
    unlabeled = tips.name(UNLABELED_CRATE, "Waylaid Crate")
    write(
        "WaylaidCrates.lua",
        [f"-- Generated by scripts/writ-data.py from scripts/data/waylaid-crates.tsv and Wowhead Forever tooltips, build {BUILD}."],
        ["ns.Data.WaylaidCrates = {", *[f"    {row}," for row in crates], "}"],
        [
            "ns.Data.SealedCrates = {", *build_sealed(tips), "}",
            "ns.Data.UnlabeledCrate = " + lua_row([("itemID", UNLABELED_CRATE), ("name", lua_val(unlabeled)), ("labeled", "false")]),
            f"ns.Data.DeliveryReceipt = {RECEIPT}",
        ],
    )
    known = sum("npcID" in row for row in writs)
    print(f"Data/Writs.lua: {len(writs)} writs, {known} with QuestieDB turn-ins; Data/WaylaidCrates.lua: {len(crates)} crates")


if __name__ == "__main__":
    main()
