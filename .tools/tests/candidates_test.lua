addon("Data/Writs.lua"); addon("Data/WaylaidCrates.lua"); addon("Modules/WritCrateSearch.lua"); addon("Modules/WritCrateState.lua")
local base = { data = ns.Data, prices = { [264089] = 2000, [10498] = 2398 }, owned = {}, doneToday = {}, faction = "A" }
local c = ns.WritState.BuildCandidates(base)
local g = find(c.writs, "ref", nil, function(x) return x.ref.questID == 94289 end)
eq(g.cost, 4398); eq(g.zone, "Tanaris")
ok(#c.unpriced > 0, "unpriced writs listed, not priced at 0")
base.doneToday[94289] = true; c = ns.WritState.BuildCandidates(base)
ok(not has(c.writs, "ref", nil, function(x) return x.ref.questID == 94289 end), "done today excluded")
base.doneToday = {}; base.owned[10498] = 1; c = ns.WritState.BuildCandidates(base)
eq(find(c.writs, "ref", nil, function(x) return x.ref.questID == 94289 end).cost, 2000)
local hordeOnly; for _, row in ipairs(ns.Data.Writs) do if row.friendly == "H" then hordeOnly = row break end end
if hordeOnly then
    base.prices[hordeOnly.writID] = 100; base.prices[hordeOnly.itemID] = 100
    c = ns.WritState.BuildCandidates(base)
    ok(not has(c.writs, "ref", nil, function(x) return x.ref.questID == hordeOnly.questID end), "hostile turn-in dropped")
end

local crate = ns.Data.WaylaidCrates[1]
local b1, b2 = crate.bundles[1], crate.bundles[2]
local cp = { data = ns.Data, prices = { [b1.itemID] = 10, [b2.itemID] = 5 }, owned = {}, doneToday = {}, faction = "A" }
c = ns.WritState.BuildCandidates(cp)
ok(not has(c.crates, "ref", nil, function(x) return x.ref == crate end), "crate without owned or buy price skipped")
cp.prices[crate.itemID] = 700
c = ns.WritState.BuildCandidates(cp)
local cc = find(c.crates, "ref", nil, function(x) return x.ref == crate end)
eq(cc.fillBundle, b2); eq(cc.fillCost, 5 * b2.count); eq(cc.buyCost, 700); eq(cc.owned, 0)
eq(cc.favor, crate.favor); eq(cc.confirmed, crate.confirmed)
cp.prices[crate.itemID] = nil; cp.owned[crate.itemID] = 3
c = ns.WritState.BuildCandidates(cp)
cc = find(c.crates, "ref", nil, function(x) return x.ref == crate end)
eq(cc.owned, 3); eq(cc.buyCost, nil)
cp.prices = {}
c = ns.WritState.BuildCandidates(cp)
ok(not has(c.crates, "ref", nil, function(x) return x.ref == crate end), "crate with no priced bundle dropped")
ok(has(c.unpriced, nil, nil, function(n) return n == crate.name end), "unpriced crate listed")

base.owned = {}; base.onQuest = { [94289] = true }; c = ns.WritState.BuildCandidates(base)
eq(find(c.writs, "ref", nil, function(x) return x.ref.questID == 94289 end).cost, 2398, "accepted writ costs nothing")
base.prices[264089] = nil; c = ns.WritState.BuildCandidates(base)
ok(has(c.writs, "ref", nil, function(x) return x.ref.questID == 94289 end), "accepted writ needs no writ price")
base.onQuest = nil; base.prices[264089] = 2000

local multi = { Writs = { { questID = 1, writID = 10, itemID = 11, name = "X", item = "X", qty = 3, rep = 125 } }, WaylaidCrates = {} }
local mb = { data = multi, prices = { [10] = 5, [11] = 100 }, owned = { [11] = 2 }, doneToday = {} }
eq(ns.WritState.BuildCandidates(mb).writs[1].cost, 105, "partly owned item costs the missing part")
mb.owned[11] = 3; eq(ns.WritState.BuildCandidates(mb).writs[1].cost, 5)
mb.owned[11] = 0; eq(ns.WritState.BuildCandidates(mb).writs[1].cost, 305)

local W = ns.WritState
local bags, bank = W.ContainerIDs({ Enum = { BagIndex = { Backpack = 0, ReagentBag = 5, CharacterBankTab_1 = 6,
    CharacterBankTab_2 = 7, CharacterBankTab_3 = 8, AccountBankTab_1 = 15 } }, NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5, NUM_BAG_SLOTS = 4 })
eq(#bags, 6); eq(bags[1], 0); eq(bags[6], 5)
eq(#bank, 3); eq(bank[1], 6); eq(bank[3], 8)
bags, bank = W.ContainerIDs({})
eq(#bags, 5); eq(bags[5], 4); eq(#bank, 0)
bags, bank = W.ContainerIDs({ Enum = { BagIndex = { Backpack = 0, Bank = -1, CharacterBankTab_1 = 6 } } })
eq(#bags, 5); eq(#bank, 2); eq(bank[1], -1); eq(bank[2], 6)

base.level = 9; c = ns.WritState.BuildCandidates(base)
eq(#c.writs, 0, "below level 10 no writs"); eq(c.lowLevel, true)
base.level = 10; c = ns.WritState.BuildCandidates(base)
ok(has(c.writs, "ref", nil, function(x) return x.ref.questID == 94289 end), "level 10 gets writs"); eq(c.lowLevel, nil)
base.level = nil; c = ns.WritState.BuildCandidates(base)
ok(#c.writs > 0, "unknown level does not block writs")
