local saved = { Auctionator = rawget(_G, "Auctionator"), time = rawget(_G, "time") }

local good, problem = pcall(function()
    addon("Modules/WritCrateHistory.lua")
    local H = ns.WritHistory
    eq(H.Median({ 3, 1, 2 }), 2); eq(H.Median({ 4, 1, 3, 2 }), 2.5); eq(H.Median({}), nil)
    _G.Auctionator = { Constants = { SCAN_DAY_0 = 0 }, Database = { GetPriceHistory = function(_, key)
        if key == "7" then return { { rawDay = "100", minSeen = 50 }, { rawDay = "99", minSeen = 70 }, { rawDay = "98", minSeen = 0 } } end
        if key == "8" then error("boom") end
        return {}
    end } }
    eq(H.Today(100 * 86400 + 5), 100)
    local hist = H.ReadHistory({ 7, 8, 9 })
    eq(hist[7][100], 50); eq(hist[7][99], 70); eq(hist[7][98], nil, "zero lows skipped")
    eq(hist[8], nil, "an erroring item is skipped"); eq(hist[9], nil, "an item with no usable rows is left out")
    _G.Auctionator = nil
    eq(next(H.ReadHistory({ 7 })), nil, "no Auctionator, no history")

    local h = { [1] = { [10] = 100, [11] = 300, [12] = 200, [13] = 5 }, [2] = { [12] = 40, [13] = 1 } }
    local p, days = H.TypicalPrices(h, 13, 3, { [1] = 999, [2] = 50, [3] = 77 })
    eq(p[1], 200, "median of the window"); eq(p[2], 40); eq(p[3], 77, "no history keeps today's price"); eq(days, 3)
    local _, d2 = H.TypicalPrices(h, 13, 1, { [1] = 1 })
    eq(d2, 1, "window limits the days")
    eq(select(1, H.TypicalPrices({ [1] = { [13] = 5 } }, 13, 3, { [1] = 99 }))[1], 99, "today's low is ignored")
    eq(select(2, H.TypicalPrices({ [1] = { [13] = 5 } }, 13, 3, { [1] = 99 })), 0)

    local list = H.DayPrices(h, 13, 3, { [1] = 999, [2] = 50 })
    eq(#list, 3); eq(list[1].day, 10); eq(list[1].prices[1], 100); eq(list[1].prices[2], 50, "before any low: today's price")
    eq(list[3].prices[2], 40); eq(list[2].prices[1], 300)
    eq(#H.DayPrices({ [1] = { [13] = 5 } }, 13, 3, { [1] = 99 }), 0, "today is not a sample")

    local s = { cheapBelow = 15, highAbove = 15, dontBuyAbove = 50 }
    eq(H.Verdict(85, 100, s).tier, "cheap"); eq(H.Verdict(86, 100, s).tier, "ok")
    eq(H.Verdict(115, 100, s).tier, "ok"); eq(H.Verdict(116, 100, s).tier, "high")
    eq(H.Verdict(150, 100, s).tier, "high"); eq(H.Verdict(151, 100, s).tier, "dontbuy")
    ok(math.abs(H.Verdict(127, 100, s).pct - 0.27) < 1e-9)
    eq(H.Verdict(nil, 100, s), nil); eq(H.Verdict(10, 0, s), nil)
    local edge = H.Verdict(115.4, 100, s)
    eq(edge.tier, "ok", "115.4% shows as +15%, so it is ok"); eq(edge.pct, 0.15)
    edge = H.Verdict(115.6, 100, s)
    eq(edge.tier, "high", "115.6% shows as +16%, so it is high"); eq(edge.pct, 0.16)
    edge = H.Verdict(84.6, 100, s)
    eq(edge.tier, "cheap", "-15.4% rounds to -15%"); eq(edge.pct, -0.15)
    eq(H.Verdict(150.4, 100, s).tier, "high"); eq(H.Verdict(150.6, 100, s).tier, "dontbuy")

    local cov = { [1] = { [8] = 1, [10] = 1, [11] = 1, [12] = 1, [13] = 1 }, [2] = { [9] = 1, [11] = 1 }, [3] = { [5] = 1 } }
    eq(H.DaysCovered(cov, { 1, 2 }, 13, 4), 4, "days 9 to 12 across both items, today excluded")
    eq(H.DaysCovered(cov, { 2 }, 13, 4), 2)
    eq(H.DaysCovered(cov, { 3, 4 }, 13, 4), 0, "outside the window or no history")
    eq(H.DaysCovered(cov, {}, 13, 4), 0)
    eq(H.TIER_ICON.ok, nil); ok(H.TIER_ICON.dontbuy:find("chevron%-double%-up%.png$"))
    local function SameColor(c, r, g, b) return c[1] == r and c[2] == g and c[3] == b and #c == 3 end
    ok(SameColor(H.TIER_COLOR.cheap, 0.25, 0.85, 0.3)); ok(SameColor(H.TIER_COLOR.ok, 0.8, 0.8, 0.8))
    ok(SameColor(H.TIER_COLOR.high, 1, 0.53, 0)); ok(SameColor(H.TIER_COLOR.dontbuy, 1, 0.2, 0.2))
    local asked
    _G.time = function(t)
        if t then asked = t; return 1000 end
        return 1000 + 7 * 86400 + 9
    end
    eq(H.Today(1000 + 3 * 86400 + 5), 3, "fallback day 0 without Auctionator")
    eq(asked.year, 2020); eq(asked.month, 1); eq(asked.day, 1); eq(asked.hour, 0)
    eq(H.Today(), 7, "time() default")
    _G.Auctionator = { Database = {} }
    eq(H.Today(1000 + 2 * 86400), 2, "Database without Constants uses the fallback")
    eq(next(H.ReadHistory({ 7 })), nil)
    _G.Auctionator = "not a table"
    eq(next(H.ReadHistory({ 7 })), nil, "a non-table Auctionator is ignored")
    eq(H.Today(1000 + 2 * 86400), 2)
    _G.Auctionator = { Constants = "x", Database = { GetPriceHistory = "no" } }
    eq(next(H.ReadHistory({ 7 })), nil, "a non-function GetPriceHistory is ignored")
    eq(H.Today(1000 + 2 * 86400), 2, "non-table Constants uses the fallback")
    _G.Auctionator = { Database = "x" }
    eq(next(H.ReadHistory({ 7 })), nil)
    _G.Auctionator = { Database = { GetPriceHistory = function() return { "junk", 5, { rawDay = "4", minSeen = 9 } } end } }
    eq(H.ReadHistory({ 7 })[7][4], 9, "non-table rows are skipped")
    eq(H.TIER_LABEL.dontbuy, "Don't buy"); eq(#H.TIER_COLOR.cheap, 3)
end)

for k, v in pairs(saved) do _G[k] = v end
if not good then error(problem, 0) end
