addon("Modules/WritCrateSearch.lua")
local S = ns.WritSearch
local function w(id, cost, zone) return { ref = { questID = id }, cost = cost, rep = 125, zone = zone } end
local writs = { w(1, 100, "Tanaris"), w(2, 100, "Moonglade"), w(3, 104, "Tanaris") }
local p = S.Tiebreak(S.RepPlan(writs, 250, nil), writs, 0.05)
eq(p.zones, 1); eq(p.cost, 204); eq(p.cheapestCost, 200); eq(p.gain, 250); eq(p.short, 0)
p = S.Tiebreak(S.RepPlan(writs, 250, nil), writs, 0.01)
eq(p.zones, 2); eq(p.cost, 200)

local short = S.Tiebreak(S.RepPlan({ writs[1] }, 500, nil), writs, 0.05)
eq(short.short, 375); eq(short.cheapestCost, 100)

local receipts = { favorBalance = 15, useBalance = true, crateCost = 35, crates = {} }
p = S.Tiebreak(S.RepPlan(writs, 175, receipts), writs, 0.05)
eq(find(p.lines, "kind", "receipt").count, 1); ok(p.gain >= 175, "target covered")

local nowhere = { w(1, 100, "Tanaris"), w(2, 100, "Moonglade"), w(3, 103, nil) }
p = S.Tiebreak(S.RepPlan(nowhere, 250, nil), nowhere, 0.05)
eq(p.zones, 2); eq(p.cost, 200)
p = S.RepPlan({ nowhere[1], nowhere[3] }, 250, nil); eq(p.zones, 2)
p = S.RepPlan({ w(4, 1, nil), w(5, 1, nil) }, 250, nil); eq(p.zones, 2)
