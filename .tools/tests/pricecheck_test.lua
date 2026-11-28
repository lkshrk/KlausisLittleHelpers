addon("Core/UI.lua")
ns.RegisterFeature = function() end
addon("Modules/WritCrateSearch.lua"); addon("Modules/WritCrateState.lua")
addon("Modules/WritCrateHistory.lua"); addon("Modules/WritCratePlanner.lua")
local P, H = ns.WritPlanner, ns.WritHistory
H.Today = function() return 12 end

local input = {
    data = { Writs = { { questID = 1, writID = 1, itemID = 2, name = "W", item = "I", qty = 1, rep = 100 } }, WaylaidCrates = {} },
    prices = { [1] = 100, [2] = 100 }, owned = {}, doneToday = {},
}
local r = { mode = "rep", target = 100, input = input, cands = ns.WritState.BuildCandidates(input),
    standing = { standingID = 4, current = 0 }, bundleOf = {} }
r.options = { { level = 0, plan = P.RepriceLines(ns.WritSearch.RepPlan(r.cands.writs, 100), input.prices, input, {}) } }
local level = r.options[1].level

local settings = { priceMethod = "typical", historyDays = 14, minDays = 2, cheapBelow = 15, highAbove = 15, dontBuyAbove = 50 }
local hist = { [1] = { [10] = 60, [11] = 60 }, [2] = { [10] = 40, [11] = 40 } }

local at = P.CheapestAt(r, { [1] = 50, [2] = 50 }, settings)
eq(at.cost, 100); eq(at.gain, 100)

local pc = P.PriceCheck(r, settings, hist)
eq(pc.daily[1].day, 10, "typical method retains daily observations"); eq(pc.days, 2); eq(pc.usualUnit, 1, "100 copper per 100 rep at typical prices"); eq(pc.method, "typical")
eq(pc.byLevel[level].tier, "dontbuy", "today 2/rep vs usual 1/rep")
ok(math.abs(pc.byLevel[level].pct - 1) < 1e-9)
eq(pc.byLevel[level].unit, 2)

settings.minDays = 3
eq(P.PriceCheck(r, settings, hist).reason, "few"); eq(P.PriceCheck(r, settings, hist).days, 2)
settings.minDays = 2
eq(P.PriceCheck(r, settings, {}).reason, "none")

input.prices[9] = 70
local unrelated = { [1] = { [11] = 60 }, [2] = { [11] = 40 }, [9] = { [3] = 1, [5] = 1, [8] = 1, [10] = 1, [11] = 1 } }
local fewPc = P.PriceCheck(r, settings, unrelated)
eq(fewPc.reason, "few", "only the plan's items count towards the minimum days")
eq(fewPc.days, 1, "the plan's items cover one day")
unrelated[1][10] = 60
eq(P.PriceCheck(r, settings, unrelated).days, 2, "reported days are the plan's days")
input.prices[9] = nil

local scanTrend = { pctPerDay = 2, count = 5, span = 7 }
local rj = P.RejudgeAtScan({ method = "typical", days = 2, usualUnit = 1, trend = scanTrend, byLevel = { [0] = { tier = "cheap", pct = -0.5, unit = 0.5 } } },
    r, { [1] = 110, [2] = 100 }, settings)
eq(rj.byLevel[level].unit, 2.1, "repriced at the given scan prices")
eq(rj.byLevel[level].tier, "dontbuy"); eq(rj.byLevel[level].pct, 1.1)
eq(rj.usualUnit, 1, "the usual unit is kept"); eq(rj.days, 2); eq(rj.method, "typical")
eq(rj.trend, scanTrend, "live scan retains historical trend")
eq(P.RejudgeAtScan({ reason = "few", days = 1 }, r, {}, settings).reason, "few", "reason states pass through")
eq(P.RejudgeAtScan(nil, r, {}, settings), nil)

settings.priceMethod = "days"
local byDay = P.PriceCheck(r, settings, { [1] = { [10] = 50, [11] = 150 }, [2] = { [10] = 50, [11] = 50 } })
eq(byDay.usualUnit, 2, "recent daily unit has greater weight"); eq(byDay.method, "days"); eq(byDay.daily[1].day, 10); eq(byDay.daily[1].costByItem[1], 50)

for _, method in ipairs({ "typical", "days" }) do
    settings.priceMethod = method
    input.prices[1] = nil
    local short = P.PriceCheck(r, settings, hist).reason
    input.prices[1] = 100
    ok(short == "short" or short == "empty", method .. ": usual plan reaches less: " .. tostring(short))
end

settings.priceMethod = "typical"
eq(P.PriceCheck(r, settings, { [1] = {}, [2] = {} }).reason, "none", "items without history rows")

local two = {
    data = { Writs = {
        { questID = 1, writID = 1, itemID = 2, name = "W", item = "I", qty = 1, rep = 100 },
        { questID = 2, writID = 3, itemID = 4, name = "V", item = "J", qty = 1, rep = 60 },
    }, WaylaidCrates = {} },
    prices = { [1] = 100, [2] = 100, [3] = 100, [4] = 100 }, owned = {}, doneToday = {},
}
local r2 = { mode = "rep", target = 100, input = two, cands = ns.WritState.BuildCandidates(two),
    standing = { standingID = 4, current = 0 }, bundleOf = {} }
r2.options = { { level = 0, plan = P.RepriceLines(ns.WritSearch.RepPlan(r2.cands.writs, 100), two.prices, two, {}) } }
eq(r2.options[1].plan.short, 0)
local hist2 = { [1] = { [10] = 60, [11] = 60 }, [2] = { [10] = 40, [11] = 40 } }
two.prices[1] = nil
eq(P.PriceCheck(r2, settings, hist2).reason, "short", "usual plan reaches only 60 of 100")
settings.priceMethod = "days"
eq(P.PriceCheck(r2, settings, hist2).reason, "short", "no past day reaches the target")

addon("Data/WaylaidCrates.lua")
local crate = ns.Data.WaylaidCrates[1]
local fprices, fhist = { [crate.itemID] = 100 }, { [crate.itemID] = { [10] = 60, [11] = 60 } }
for _, b in ipairs(crate.bundles) do fprices[b.itemID] = 10; fhist[b.itemID] = { [10] = 5, [11] = 5 } end
local fin = { data = { Writs = {}, WaylaidCrates = { crate } }, prices = fprices, owned = {}, doneToday = {} }
local rf = { mode = "favor", target = 10, input = fin, cands = ns.WritState.BuildCandidates(fin),
    standing = { standingID = 4, current = 0 }, bundleOf = {} }
rf.options = { { level = 0, plan = P.RepriceLines(ns.WritSearch.FavorPlan(rf.cands.crates, 10), fprices, fin, {}) } }
local fpc = P.PriceCheck(rf, settings, fhist)
ok(fpc.usualUnit and fpc.usualUnit > 0, "favor mode has a usual unit: " .. tostring(fpc.reason))
ok(fpc.byLevel[0] and fpc.byLevel[0].tier, "favor mode has a tier")

settings.minDays, settings.historyDays = 14, 2
ok(P.PriceCheck(r, settings, hist).reason ~= "few", "minimum days is capped by history days")
settings.minDays, settings.historyDays = 2, 14

eq(P.PricePct({ byLevel = { [0] = { tier = "high", pct = 0.27 } } }, 0), "|cffff8700+27%|r")
eq(P.PricePct({ byLevel = { [0] = { tier = "cheap", pct = -0.18 } } }, 0), "|cff40d94d-18%|r")
eq(P.PricePct({ byLevel = { [0] = { tier = "ok", pct = 0.001 } } }, 0), "|cffcccccc+0%|r")
eq(P.PricePct({ byLevel = {} }, 5), nil, "no verdict for the level")
eq(P.PricePct({ reason = "few", days = 2 }, 0), nil, "reason states have no percent")
eq(P.PricePct(nil, 0), nil)
eq(P.YoungNote({ days = 6 }), " |cff9d9d9d(6 days)|r", "young history is marked")
eq(P.YoungNote({ days = 1 }), " |cff9d9d9d(1 day)|r")
eq(P.YoungNote({ days = 10 }), "", "ten days or more is not marked")
eq(P.YoungNote(nil), "")

settings.priceMethod = "typical"
settings.minDays = 2
r.priceCheck = P.PriceCheck(r, settings, hist)
local rows = P.OptionRows(r)
ok(rows[1].icon and rows[1].icon.file:match("chevron%-double%-up%.png$"), "dontbuy shows the double chevron")
eq(rows[1].icon.r, 1); eq(rows[1].icon.g, 0.2); eq(rows[1].icon.b, 0.2)
local winRows = P.WindowRows(r, nil)
eq(winRows[1].icon.file, rows[1].icon.file)

r.priceCheck.byLevel[level].tier = "ok"
eq(P.OptionRows(r)[1].icon, nil, "ok has no icon")
r.priceCheck.byLevel[level].tier = "high"
ok(P.OptionRows(r)[1].icon.file:match("chevron%-up%.png$"))
r.priceCheck.byLevel[level].tier = "cheap"
ok(P.OptionRows(r)[1].icon.file:match("chevron%-down%.png$"))
r.priceCheck.byLevel[level].tier = "dontbuy"
r.priceCheck.byLevel[level].unit = 2
r.priceCheck.byLevel[level].pct = 1

local tip = P.PlanLines(r, r.options[1], "Cheapest")
ok(has(tip, nil, nil, function(l) return l.left == "Price check" and l.right == "|cffff3333+100%|r |cff9d9d9d(2 days)|r" and l.label end), "tooltip price row, right aligned in the tier colour")
local found = {}
for _, l in ipairs(tip) do found[l.left] = l end
eq(found["  Per rep"].right, P.FormatMoney(2), "tooltip shows today's cost per unit")
eq(found["  Usual"].right, P.FormatMoney(r.priceCheck.usualUnit), "and the usual one")
eq(found["  Trend estimate"].right, "Insufficient reliable history", "planner tooltip without trend")
r.priceCheck.trend = scanTrend
ok(has(P.PlanLines(r, r.options[1], "Cheapest"), nil, nil, function(l)
    return l.left == "  Trend estimate" and l.right == "+2.0%/day (5 days, 7-day span)"
end), "planner tooltip with trend")
r.priceCheck.trend = nil

r.selected, r.plan = 1, r.options[1].plan
ok(not (P.Summary(r) or { text = "" }).text:find("Price", 1, true), "the summary carries no price line; the row chevron and tooltip do")

local foot = P.Footer(r)
ok(has(foot.lines, nil, nil, function(l) return l.left == "Price check: Typical prices, 2 days" end), "footer typical")
r.priceCheck.method = "days"
ok(has(P.Footer(r).lines, nil, nil, function(l) return l.left == "Price check: Past days, 2 days" end), "footer days")

local function footerHas(pcv, text)
    r.priceCheck = pcv
    return has(P.Footer(r).lines, nil, nil, function(l) return l.left == text end)
end
ok(footerHas({ reason = "none" }, "No price history"))
ok(footerHas({ reason = "few", days = 3 }, "Not enough price history (3 days)"))
ok(footerHas({ reason = "empty" }, "No usual price for this target"))
ok(footerHas({ reason = "short" }, "No usual price for this target"))
r.priceCheck = { reason = "few", days = 3 }
r.selected = 1
ok(has(P.PlanLines(r, r.options[1], "x"), nil, nil, function(l) return l.left == "Price check" and l.right == "Not enough price history (3 days)" end), "tooltip reason")
ok(not (P.Summary(r) or { text = "" }).text:find("Price", 1, true), "reason leaves the summary alone")

local edgeVerdict = H.Verdict(115.6, 100, settings)
eq(P.PricePct({ byLevel = { [0] = edgeVerdict } }, 0), "|cffff8700+16%|r", "the shown percent is the one the tier used")
edgeVerdict = H.Verdict(84.6, 100, settings)
eq(P.PricePct({ byLevel = { [0] = edgeVerdict } }, 0), "|cff40d94d-15%|r")
