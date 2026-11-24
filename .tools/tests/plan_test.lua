addon("Modules/WritCrateSearch.lua")
local S = ns.WritSearch
local ingots = { ref = { name = "Expert Ingots" }, favor = 30, confirmed = true, fillCost = 8990, owned = 2, buyCost = 99 }
local p = S.FavorPlan({ ingots }, 90)
eq(p.gain, 90); eq(p.cost, 8990 * 2 + (99 + 8990))
eq(find(p.lines, "owned", true).count, 2); eq(find(p.lines, "owned", false).count, 1)
eq(#p.lines, 2); eq(p.lines[1].kind, "crate"); eq(p.lines[1].confirmed, true)
eq(p.short, 0)
p = S.FavorPlan({ { ref = {}, favor = 30, confirmed = false, fillCost = 10, owned = 1 } }, 90)
eq(p.gain, 30); eq(p.short, 60); eq(p.lines[1].confirmed, false)
eq(#S.FavorPlan({ ingots }, 0).lines, 0)

local w1 = { ref = { questID = 1 }, cost = 4398, rep = 125, zone = "Tanaris" }
p = S.RepPlan({ w1 }, 175, nil); eq(p.gain, 125); eq(p.short, 50); eq(p.zones, 1)
p = S.RepPlan({ w1 }, 175, { favorBalance = 15, useBalance = true, crateCost = 35, crates = {} })
eq(p.gain, 175); eq(p.cost, 4398 + 35); eq(p.short, 0)
eq(find(p.lines, "kind", "receipt").count, 1)
p = S.RepPlan({ w1 }, 175, { favorBalance = 15, useBalance = false, crateCost = 35, crates = { ingots } })
eq(p.cost, 4398 + 35 + 8990)
ok(has(p.lines, "kind", "crate"), "crate line present")
p = S.RepPlan({ w1 }, 175, { favorBalance = 0, useBalance = true, crateCost = 35, crates = {} })
eq(p.gain, 125); eq(p.short, 50)

local w2 = { ref = { questID = 2 }, cost = 100, rep = 125, zone = "Un'Goro" }
p = S.RepPlan({ w1, w2 }, 250, nil); eq(p.zones, 2); eq(p.cost, 4498); eq(p.gain, 250)
p = S.RepPlan({ w1, w2 }, 250, { favorBalance = 300, useBalance = true, crateCost = 35, crates = {} })
eq(p.cost, 35 * 5); eq(find(p.lines, "kind", "receipt").count, 5)

local herbs = { ref = { name = "Apprentice Herbs" }, favor = 5, confirmed = true, fillCost = 50, owned = 1, buyCost = 35 }
local fillOnly = { ref = { name = "Expert Ingots" }, favor = 45, confirmed = true, fillCost = 100, owned = 0, buyCost = 1000 }
p = S.RepPlan({}, 150, { favorBalance = 0, useBalance = false, crateCost = 35, crateRef = herbs.ref,
    crates = { herbs, fillOnly }, ownedEmpty = 1 })
local receipt = find(p.lines, "kind", "receipt")
eq(receipt.count, 3); eq(receipt.bought, 2); eq(receipt.crateRef, herbs.ref); eq(receipt.cost, 2 * 35)
ok(not has(p.lines, nil, nil, function(l) return l.kind == "crate" and l.owned end), "owned empty crate not also filled")
eq(p.cost, 2 * 35 + 9 * (35 + 50)); eq(p.gain, 150)

p = S.RepPlan({ w1 }, 175, { favorBalance = 300, useBalance = true, crateCost = nil, crates = {}, ownedEmpty = 0 })
ok(not has(p.lines, "kind", "receipt"), "no receipts without a crate"); eq(p.gain, 125)
p = S.RepPlan({}, 100, { favorBalance = 300, useBalance = true, crateCost = nil, crates = {}, ownedEmpty = 1 })
eq(find(p.lines, "kind", "receipt").count, 1); eq(find(p.lines, "kind", "receipt").bought, 0); eq(p.short, 50)

p = S.RepPlan({}, 150, { favorBalance = 20, useBalance = true, crateCost = 35, crateRef = herbs.ref,
    crates = { herbs, fillOnly }, ownedEmpty = 1 })
eq(p.favor and p.favor.need, 45, "favor needed for 3 receipts")
eq(p.favor.fromBalance, 20, "owned favor spent first")
eq(p.favor.fromCrates >= 25, true, "rest from crates")
p = S.RepPlan({ w1 }, 125, nil)
eq(p.favor, nil, "no receipts, no favor")
