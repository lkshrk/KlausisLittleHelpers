ns.RegisterFeature = function() end
addon("Modules/WritCrateDepth.lua")
addon("Modules/WritCratePlanner.lua")
local D = ns.WritDepth

local one = { { unitPrice = 100, quantity = 50 } }
local total, avail = D.Cost(one, 20)
eq(total, 2000, "single tier"); eq(avail, 50)

local tiers = { { unitPrice = 100, quantity = 5 }, { unitPrice = 150, quantity = 10 }, { unitPrice = 400, quantity = 3 } }
total, avail = D.Cost(tiers, 12)
eq(total, 5 * 100 + 7 * 150, "many tiers"); eq(avail, 18)
total = D.Cost(tiers, 18)
eq(total, 500 + 1500 + 1200, "exactly all")
total, avail = D.Cost(tiers, 19)
eq(total, nil, "not enough listed"); eq(avail, 18)
total, avail = D.Cost({}, 3)
eq(total, nil, "zero listings"); eq(avail, 0)
eq((D.Cost(tiers, 0)), 0, "nothing needed costs nothing")

local writ = { writID = 10, name = "Knife", itemID = 20, item = "Knife", qty = 4, questID = 1 }
local crate = { itemID = 30, name = "Ingots" }
local bundleOf = { [crate] = { itemID = 40, name = "Bar", count = 10 } }
local plan = { lines = {
    { kind = "writ", ref = writ, count = 1 },
    { kind = "crate", ref = crate, count = 2, owned = false },
} }
local needs = D.Needs(plan, { [20] = 3, [40] = 5 }, bundleOf)
eq(needs[10], 1); eq(needs[20], 1, "owned reduces need"); eq(needs[30], 2); eq(needs[40], 15)
needs = D.Needs(plan, { [20] = 4 }, bundleOf)
eq(needs[20], nil, "fully owned item not needed")

local scan = { [10] = 1000, [20] = 50, [30] = 700, [40] = 9, [99] = 5 }
local listings = {
    [40] = { { unitPrice = 10, quantity = 5 }, { unitPrice = 20, quantity = 20 } },
    [20] = {},
    [30] = { { unitPrice = 600, quantity = 1 } },
}
needs = { [10] = 1, [20] = 2, [30] = 2, [40] = 15 }
local prices, marks = D.EffectivePrices(needs, listings, scan)
eq(prices[40], (5 * 10 + 10 * 20) / 15, "effective unit price")
eq(marks[40].live, true); eq(marks[40].short, nil)
eq(prices[20], nil, "nothing listed: unbuyable, so its writ is left out")
eq(marks[20].live, true); eq(marks[20].short, 0, "zero listings marked")
eq(prices[30], (600 + 700) / 2, "short item: rest at max(highest listed, scan)")
eq(marks[30].live, true); eq(marks[30].short, 1)
eq(prices[10], 1000, "unfetched item keeps scan price"); eq(marks[10].live, false); eq(marks[10].short, nil)
eq(prices[99], 5, "items outside the plan keep scan price")
local noScan = D.EffectivePrices({ [77] = 3 }, { [77] = {} }, {})
eq(noScan[77], nil, "no listings and no scan price stays unpriced")

local cheap = { lines = { { kind = "crate", ref = crate, count = 1, owned = true } } }
local dear = { lines = { { kind = "crate", ref = crate, count = 2, owned = true } } }
local bl = { [40] = { { unitPrice = 10, quantity = 10 }, { unitPrice = 50, quantity = 100 } } }
local outside = D.EffectivePrices({}, { [50] = { { unitPrice = 7, quantity = 1 }, { unitPrice = 9, quantity = 4 } }, [51] = {} },
    { [50] = 2, [51] = 3 })
eq(outside[50], 7, "fetched item outside the plan priced at its cheapest listing")
eq(outside[51], nil, "fetched item outside the plan with nothing listed is unbuyable")
eq(D.PlanCost(cheap, {}, { [40] = {} }, scan, bundleOf), nil, "plan needing an item with nothing listed has no cost")
eq(D.PlanCost(cheap, {}, bl, scan, bundleOf), 100, "plan cost from depth")
eq(D.PlanCost(dear, {}, bl, scan, bundleOf), 100 + 500, "bigger buy pays the next tier")
eq(D.PlanCost(cheap, { [40] = 10 }, bl, scan, bundleOf), 100, "owned mats count at their cheapest listing")
eq(D.PlanCost(cheap, { [40] = 4 }, bl, scan, bundleOf), 100, "partly owned: the rest is bought, the owned part valued")
ok(D.PlanCost(cheap, {}, bl, scan, bundleOf) < D.PlanCost(dear, {}, bl, scan, bundleOf), "plan cost compare")

local short = D.ShortAtScan({ [1] = 10, [2] = 5, [3] = 4 }, { [1] = 6, [2] = 5 })
eq(short[1], 6, "needs more than listed at scan"); eq(short[2], nil); eq(short[3], nil, "unknown available")
