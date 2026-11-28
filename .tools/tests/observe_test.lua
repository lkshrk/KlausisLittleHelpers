addon("Data/Writs.lua"); addon("Data/WaylaidCrates.lua"); addon("Modules/WritCrateSearch.lua"); addon("Modules/WritCrateState.lua")
local W = ns.WritState
local s = W.Observe({}, { kind = "crate", key = "artisan:gathered", favor = 20 })
eq(s.sealedFavor["artisan:gathered"], 20)
s = W.Observe(s, { kind = "writ", tier = "expert", rep = 0, pastFriendly = true })
eq(s.writRep.expert.pastFriendly.yes, nil, "one zero past Friendly is not enough")
eq(W.PastFriendly(s), nil)
s = W.Observe(s, { kind = "writ", tier = "expert", rep = 0, pastFriendly = true })
eq(s.writRep.expert.pastFriendly.yes, 0, "second zero past Friendly confirms it")
s = W.Observe(s, { kind = "writ", tier = "expert", rep = 125, pastFriendly = false, rowRep = 125 })
eq(s.writRep.expert.rep, 125); eq(s.writRep.expert.pastFriendly.no, 125)
local c = W.BuildCandidates({ data = ns.Data, prices = { [11176] = 1977 }, owned = { [248699] = 1 }, doneToday = {}, faction = "A", observed = s })
eq(find(c.crates, "ref", nil, function(x) return x.ref.itemID == 248699 end).confirmed, true)
c = W.BuildCandidates({ data = ns.Data, prices = { [11176] = 1977 }, owned = { [248699] = 1 }, doneToday = {}, faction = "A", observed = {} })
eq(find(c.crates, "ref", nil, function(x) return x.ref.itemID == 248699 end).confirmed, true)
s = W.Observe({}, { kind = "crate", key = "artisan:gathered", favor = 25 })
c = W.BuildCandidates({ data = ns.Data, prices = { [11176] = 1977, [14047] = 100 }, owned = { [248699] = 1, [248698] = 1 },
    doneToday = {}, faction = "A", observed = s })
eq(find(c.crates, "ref", nil, function(x) return x.ref.itemID == 248699 end).favor, 25)
local textiles = find(c.crates, "ref", nil, function(x) return x.ref.itemID == 248698 end)
eq(textiles.favor, 5, "item-specific reward overrides category observation"); eq(textiles.confirmed, true)
s = W.Observe({}, { kind = "crate", key = "artisan:gathered", favor = 5 })
c = W.BuildCandidates({ data = ns.Data, prices = { [11176] = 1977, [14047] = 100 }, owned = { [248699] = 1, [248698] = 1 }, doneToday = {}, faction = "A", observed = s })
eq(find(c.crates, "ref", nil, function(x) return x.ref.itemID == 248699 end).favor, 20, "stale textiles observation ignored")
eq(find(c.crates, "ref", nil, function(x) return x.ref.itemID == 248698 end).favor, 5)
eq(s.sealedFavor["artisan:gathered"], 5, "saved observation retained")
s = W.Observe(s, { kind = "crate", key = "artisan:crafted", favor = 5 })
eq(s.sealedFavor["artisan:crafted"], 5)
local crafted = W.BuildCandidates({ data = ns.Data, prices = { [14048] = 100 }, owned = { [248711] = 1 }, doneToday = {}, faction = "A", observed = s })
eq(find(crafted.crates, "ref", nil, function(x) return x.ref.itemID == 248711 end).favor, 5, "other categories retain observations")
s = W.Observe({}, { kind = "crate", key = "artisan:gathered", favor = 20 })
c = W.BuildCandidates({ data = ns.Data, prices = { [11176] = 1977, [14047] = 100 }, owned = { [248699] = 1, [248698] = 1 },
    doneToday = {}, faction = "A", observed = s })
eq(find(c.crates, "ref", nil, function(x) return x.ref.itemID == 248698 end).favor, 5)
eq(find(c.crates, "ref", nil, function(x) return x.ref.itemID == 248699 end).favor, 20)
s = W.Observe({}, { kind = "crate", key = "artisan:crafted", favor = 40 })
c = W.BuildCandidates({ data = ns.Data, prices = { [11176] = 1977 }, owned = { [248699] = 1 }, doneToday = {}, faction = "A", observed = s })
eq(find(c.crates, "ref", nil, function(x) return x.ref.itemID == 248699 end).confirmed, true, "other kind remains confirmed")

eq(W.PastFriendly(nil), nil); eq(W.PastFriendly({}), nil)
eq(W.PastFriendly({ writRep = { expert = { pastFriendly = { yes = 0 } } } }), 0)
eq(W.PastFriendly({ writRep = { expert = { pastFriendly = { yes = 0 } }, artisan = { pastFriendly = { yes = 200 } } } }), 200)

local row, key = W.SealedRow(ns.Data, 248768)
eq(row.tier, "artisan"); eq(row.kind, "gathered"); eq(key, "artisan:gathered")
local reordered = { SealedCrates = ns.Data.SealedCrates, WaylaidCrates = { textiles.ref, row } }
eq(W.SealedRow(reordered, 248768), row, "category observation ignores item override")
eq(W.CrateFavor(row, 20), 20); eq(W.CrateFavor(row, 25), nil); eq(W.CrateFavor(row, 40), 20)
local unknown = { favor = 20, confirmed = false }
eq(W.CrateFavor(unknown, 25), 25); eq(W.CrateFavor(unknown, 40), 40)
eq(W.CrateFavor(unknown, 70), 70, "no Shipping Label exclusion")
eq(W.CrateFavor(row, 23), nil); eq(W.CrateFavor(row, 85), nil)
eq(W.CrateFavor(row, 40, 20), 20, "known favor doubled is halved")
eq(W.CrateFavor(row, 25, 20), nil, "known favor: other gains ignored")
local ingots = find(ns.Data.WaylaidCrates, "itemID", 248709)
eq(W.CrateFavor(ingots, 30), 30); eq(W.CrateFavor(ingots, 60), 30)
eq(W.CrateFavor(ingots, 80), nil); eq(W.CrateFavor(ingots, 35), nil)
eq(W.SealedRow(ns.Data, 248709), nil, "empty crate is not sealed")
eq(W.SealedRow(ns.Data, 248769), nil, "Elite has no crate rows")
eq(W.SealedRow(ns.Data, 248777), nil, "blue kind unknown")
eq(select(2, W.SealedRow(ns.Data, 248772)), "expert:crafted")

local departed = { [248768] = { at = 10 } }
local found, kinds, fkey = W.DepartedCrate(ns.Data, departed, 12, 5)
eq(found, row); eq(kinds, 1); eq(fkey, "artisan:gathered")
departed[248772] = { at = 11 }
found, kinds = W.DepartedCrate(ns.Data, departed, 12, 5)
eq(found, nil, "two tier kinds in the window skipped"); eq(kinds, 2)
found = W.DepartedCrate(ns.Data, departed, 15.5, 5); fkey = select(3, W.DepartedCrate(ns.Data, departed, 15.5, 5))
eq(found.tier, "expert"); eq(found.kind, "crafted"); eq(fkey, "expert:crafted", "old departure outside the window")
eq(W.DepartedCrate(ns.Data, {}, 12, 5), nil)
eq(select(2, W.DepartedCrate(ns.Data, { [248777] = { at = 10 } }, 12, 5)), 0, "blue sealed crate records nothing")
eq(select(2, W.DepartedCrate(ns.Data, { [2589] = { at = 10 } }, 12, 5)), 0, "other items ignored")

s = W.Observe({}, { kind = "writ", tier = "expert", rep = 137, pastFriendly = false, rowRep = 125 })
eq(s.writRep.expert.rep, nil, "off-step reading not learned")
s = W.Observe(s, { kind = "writ", tier = "expert", rep = 137, pastFriendly = false, rowRep = 125 })
eq(s.writRep.expert.rep, 137, "same reading seen twice is learned")
s = W.Observe(s, { kind = "writ", tier = "expert", rep = 0, pastFriendly = true })
eq(s.writRep.expert.rep, 137, "most recent positive rep kept")
local far = W.Observe({}, { kind = "writ", tier = "expert", rep = 400, pastFriendly = false, rowRep = 125 })
eq(far.writRep.expert.rep, nil, "reading beyond 50% of the row rep not learned")
far = W.Observe(far, { kind = "writ", tier = "expert", rep = 150, pastFriendly = false, rowRep = 125 })
eq(far.writRep.expert.rep, 150, "plausible reading learned at once")
far = W.Observe(far, { kind = "writ", tier = "expert", rep = 175, pastFriendly = true, rowRep = 125 })
eq(far.writRep.expert.rep, 150, "past-Friendly reading leaves the pre-Friendly rep")
eq(far.writRep.expert.pastFriendly.yes, 175)
far = W.Observe(far, { kind = "writ", tier = "expert", rep = 0, pastFriendly = true })
far = W.Observe(far, { kind = "writ", tier = "expert", rep = 125, pastFriendly = true, rowRep = 125 })
far = W.Observe(far, { kind = "writ", tier = "expert", rep = 0, pastFriendly = true })
eq(far.writRep.expert.pastFriendly.yes, 125, "zeros split by a real gain do not confirm")
local exp = { Writs = { { questID = 1, writID = 10, itemID = 11, name = "X", item = "X", qty = 1, rep = 125, tier = "expert", zone = "Z" } },
    WaylaidCrates = {} }
local cw = W.BuildCandidates({ data = exp, prices = { [10] = 5, [11] = 6 }, owned = {}, doneToday = {}, observed = s })
eq(cw.writs[1].rep, 125, "observed rep rounded down to 25")
s.writRep.expert.rep = 160
eq(W.BuildCandidates({ data = exp, prices = { [10] = 5, [11] = 6 }, owned = {}, doneToday = {}, observed = s }).writs[1].rep, 150)
eq(W.BuildCandidates({ data = exp, prices = { [10] = 5, [11] = 6 }, owned = {}, doneToday = {}, observed = {} }).writs[1].rep, 125)
s.writRep.expert.rep = 12
eq(W.BuildCandidates({ data = exp, prices = { [10] = 5, [11] = 6 }, owned = {}, doneToday = {}, observed = s }).writs[1].rep, 125,
    "reading below one step falls back to the row rep")

local S = ns.WritSearch
local w1 = { ref = { name = "W" }, cost = 100, rep = 125, zone = "Z" }
local w2 = { ref = { name = "V" }, cost = 100, rep = 125, zone = "Z" }
local p = S.RepPlan({ w1, w2 }, 250, nil, 125)
eq(p.gain, 125); eq(p.short, 125)
p = S.RepPlan({ w1, w2 }, 250, nil, 0); eq(p.gain, 0)
p = S.RepPlan({ w1, w2 }, 250, nil); eq(p.gain, 250)

local synth = { Writs = { { questID = 1, writID = 10, itemID = 11, name = "X", item = "X", qty = 1, rep = 125, zone = "Z", friendly = "H" } }, WaylaidCrates = {}, CampFaction = {} }
local base = { data = synth, prices = { [10] = 5, [11] = 6 }, owned = {}, doneToday = {}, faction = "A" }
eq(#W.BuildCandidates(base).writs, 0)
base.faction = "H"
eq(#W.BuildCandidates(base).writs, 1)

local before = { standingID = 5, current = 100 }
eq(W.SettleWrit(before, { standingID = 5, current = 225 }, false), 125)
eq(W.SettleWrit(before, { standingID = 5, current = 100 }, false), nil)
eq(W.SettleWrit(before, { standingID = 5, current = 100 }, true), 0)
eq(W.SettleWrit({ standingID = 4, current = 100 }, { standingID = 4, current = 100 }, true), nil)
eq(W.SettleWrit(before, { standingID = 5, current = 50 }, false), nil)
eq(W.SettleWrit({ standingID = 5, current = 5950, total = 8950 }, { standingID = 6, current = 75, total = 9075 }, false), 125)
eq(W.SettleWrit({ standingID = 5, current = 100, total = 3100 }, { standingID = 5, current = 50, total = 3050 }, true), nil)
eq(W.SettleWrit({ standingID = 5, current = 5950, total = 8950 }, { standingID = 6, current = 0, total = 9000 }, true), 50)
