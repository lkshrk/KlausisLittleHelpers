addon("Core/UI.lua")
ns.RegisterFeature = function() end
addon("Modules/WritCrateSearch.lua"); addon("Modules/WritCrateState.lua")
addon("Modules/WritCrateHistory.lua"); addon("Modules/WritCratePlanner.lua")
local P = ns.WritPlanner

local writs = {}
for i = 1, 4 do
    writs[i] = { questID = i, writID = 10 + i, itemID = 20 + i, name = "W" .. i, item = "I" .. i, qty = 1, rep = 100 }
end
local crate = { itemID = 30, name = "C", tier = "expert", kind = "crafted", favor = 30, confirmed = true,
    bundles = { { itemID = 31, name = "B", count = 10 } } }
local input = {
    data = { Writs = writs, WaylaidCrates = { crate } },
    prices = { [11] = 50, [21] = 50, [12] = 100, [22] = 100, [13] = 150, [23] = 150, [14] = 200, [24] = 200, [30] = 300, [31] = 30 },
    owned = { [21] = 5, [11] = 1 }, bags = { [21] = 5 }, doneToday = { [1] = true }, onQuest = { [2] = true }, level = 5,
}
local settings = { priceMethod = "typical", historyDays = 14, minDays = 2, cheapBelow = 15, highAbove = 15, dontBuyAbove = 50,
    marketShare = 25 }
local hist = {
    [11] = { [10] = 25, [11] = 25 }, [21] = { [10] = 25, [11] = 25 },
    [30] = { [10] = 400, [11] = 400 }, [31] = { [10] = 40, [11] = 40 },
}

local neutral = P.NeutralInput(input)
eq(next(neutral.owned), nil, "the market ignores owned items")
eq(next(neutral.doneToday), nil, "and writs done today")
eq(neutral.level, nil, "and the player's level")
eq(input.owned[21], 5, "the player's own input is left untouched")

local mean, ids = P.TopMean({ { unit = 3, ids = { 1 } }, { unit = 1, ids = { 2 } }, { unit = 2, ids = { 3 } }, { unit = 4, ids = { 4 } } }, 25)
eq(mean, 1, "25% of four sources is the single cheapest"); eq(#ids, 1); eq(ids[1], 2)
eq((P.TopMean({ { unit = 3, ids = {} }, { unit = 1, ids = {} }, { unit = 2, ids = {} } }, 50)), 1.5, "the share rounds up to whole sources")
eq(P.TopMean({}, 25), nil)

local mi = P.MarketIndex(input, settings, hist, 12)
eq(mi.rep.unit, 1, "cheapest writ today: 100 copper for 100 rep, even though its item is owned and the writ is done")
eq(mi.rep.usualUnit, 0.5, "its usual: 50 copper for 100 rep")
eq(mi.rep.tier, "dontbuy"); ok(math.abs(mi.rep.pct - 1) < 1e-9); eq(mi.rep.days, 2); eq(mi.rep.share, 25)
eq(mi.favor.unit, 20, "crate today: (300 + 10 x 30) / 30 Favor")
eq(mi.favor.usualUnit, (400 + 400) / 30, "crate usual from its own history")
eq(mi.favor.tier, "cheap")
eq(mi.rep.best[1].components[1].cost, 50, "writ component cost")
eq(mi.rep.best[1].components[2].cost, 50, "material component cost")
eq(mi.favor.best[1].components[2].cost, 300, "crate fill component cost")
eq(mi.rep.daily[1].day, 10, "daily market unit retains its day")
eq(mi.rep.daily[1].components[1].provenance.kind, "observed")
local repPart, repTier = P.MarketPart(mi.rep)
eq(repPart, "|cffff3333+100%|r", "the button shows each market's change in its tier colour"); eq(repTier, "dontbuy")
local favorPart, favorTier = P.MarketPart(mi.favor)
eq(favorPart, "|cff40d94d-25%|r"); eq(favorTier, "cheap")
eq(P.MarketPart({ reason = "none" }), nil, "no verdict, no part")
eq(P.MarketPart(nil), nil)
eq(P.MarketPart({ tier = "ok", pct = 0.03 }), "|cffcccccc+3%|r", "OK still shows its change, without a chevron")

eq(mi.rep.count, 1, "25% of four writs counts one"); eq(mi.rep.total, 4, "out of four available writs")
eq(mi.rep.best[1].name, "Craftsman's Writ: W1", "the cheapest writ is named"); eq(mi.rep.best[1].unit, 1)
eq(mi.rep.low, 0.5, "lowest daily index in the window"); eq(mi.rep.high, 0.5, "highest daily index in the window")
eq(mi.rep.window, 14)
eq(mi.favor.best[1].name, "Waylaid Crate: C"); eq(mi.favor.total, 1)

settings.marketShare = 50
local half = P.MarketIndex(input, settings, hist, 12)
eq(half.rep.unit, 1.5, "50% of four writs: the two cheapest")
eq(half.rep.usualUnit, 1.25, "their usual: 0.5 and 2 (no history keeps today's price)")
eq(half.rep.tier, "high")
settings.marketShare = 25

settings.priceMethod = "days"
eq(P.MarketIndex(input, settings, hist, 12).rep.usualUnit, 0.5, "past days: median of each day's index")
settings.priceMethod = "typical"

eq(P.MarketIndex(input, settings, {}, 12).rep.reason, "none", "no history, no verdict")
settings.minDays = 3
local few = P.MarketIndex(input, settings, hist, 12)
eq(few.rep.reason, "few"); eq(few.rep.days, 2)
settings.minDays = 2
eq(P.MarketIndex({ data = { Writs = {}, WaylaidCrates = {} }, prices = {}, owned = {} }, settings, hist, 12).rep.reason, "empty")

local trendLines = P.MarketLines({ rep = { tier = "ok", pct = 0, unit = 1, usualUnit = 1,
    trend = { pctPerDay = 2, count = 5, span = 7 } } })
local foundTrend = false
for _, line in ipairs(trendLines) do
    if line.left == "  Trend estimate" then
        eq(line.right, "+2.0%/day (5 days, 7-day span)")
        foundTrend = true
    end
end
ok(foundTrend, "market tooltip labels trend estimate")
local lines = P.MarketLines(mi)
local byLeft = {}
for _, l in ipairs(lines) do byLeft[l.left] = l end
ok(byLeft["Writs, cheapest 25%"] and byLeft["Writs, cheapest 25%"].right:find("+100%", 1, true), "tooltip line per market with the change")
ok(byLeft["Crates, cheapest 25%"] and byLeft["Crates, cheapest 25%"].right:find("%-25%%"), "crates line: " .. tostring(byLeft["Crates, cheapest 25%"] and byLeft["Crates, cheapest 25%"].right))
ok(byLeft["  Per rep"] and byLeft["  Per Favor"] and byLeft["  Usual"], "per unit and usual rows")
eq(byLeft["  Trend estimate"].right, "Insufficient reliable history", "market tooltip without trend")
eq(byLeft["  Verdict"] and byLeft["  Verdict"].right, "Cheap", "the verdict in words")
eq(byLeft["  Last 14 days"] and byLeft["  Last 14 days"].right, P.FormatMoney(800 / 30) .. " - " .. P.FormatMoney(800 / 30), "the daily range")
ok(byLeft["  Counted"] and byLeft["  Counted"].right:find("of", 1, true), "how many sources count")
ok(byLeft["    Craftsman's Writ: W1"], "the cheapest writ is listed by name")
ok(byLeft["    Waylaid Crate: C"], "the cheapest crate is listed by name")
local reasonLines = P.MarketLines({ rep = { reason = "few", days = 2, share = 25 }, favor = { reason = "none", share = 25 } })
local reasons = {}
for _, l in ipairs(reasonLines) do reasons[l.left] = l.right end
eq(reasons["Writs, cheapest 25%"], "Not enough price history (2 days)")
eq(reasons["Crates, cheapest 25%"], "No price history")
settings.priceMethod, settings.halfLife = "days", 1
local shifted = { [11] = { [8] = 10, [9] = 10, [11] = 50 }, [21] = { [8] = 10, [9] = 10, [11] = 50 } }
eq(P.MarketIndex(input, settings, shifted, 12).rep.usualUnit, 1, "daily index uses half-life")
settings.priceMethod = "typical"
eq(P.MarketIndex(input, settings, shifted, 12).rep.usualUnit, 1, "typical prices use half-life")

local mixedInput = { data = { Writs = { writs[1], writs[2] }, WaylaidCrates = {} }, prices = input.prices, owned = {} }
writs[2].rep = 200
settings.marketShare = 100
settings.halfLife = -1
settings.priceMethod = "days"
local mixed = P.MarketIndex(mixedInput, settings, hist, 12).rep
local sum = 0
for _, component in ipairs(mixed.daily[1].components) do
    sum = sum + component.contribution
    if component.provenance.kind ~= "observed" then eq(component.reliable, false) end
end
ok(math.abs(sum - mixed.daily[1].value) < 1e-9, "normalized components sum to market unit")
settings.halfLife = 4
eq(mixed.usualUnit, P.MarketIndex(mixedInput, settings, hist, 12).rep.usualUnit, "invalid half-life defaults in daily method")
settings.priceMethod = "typical"
settings.halfLife = "invalid"
local malformed = P.MarketIndex(mixedInput, settings, hist, 12).rep.usualUnit
settings.halfLife = 4
eq(malformed, P.MarketIndex(mixedInput, settings, hist, 12).rep.usualUnit, "invalid half-life defaults in typical method")

local partial = { [11] = { [9] = 20 }, [21] = { [10] = 20, [11] = 20 } }
settings.marketShare = 25
local stale = P.MarketIndex(input, settings, partial, 12).rep.daily
local staleFound = false
for _, row in ipairs(stale) do
    for _, component in ipairs(row.components) do
        if component.provenance.kind == "carried" then
            staleFound = true
            eq(component.reliable, false, "carried prices are not reliable trend evidence")
        end
    end
end
ok(staleFound, "fixture includes carried price")
