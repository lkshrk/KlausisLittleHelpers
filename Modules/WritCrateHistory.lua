local _, ns = ...

local H = {}
ns.WritHistory = H

local ICON = "Interface\\AddOns\\KlausisLittleHelpers\\Media\\"

H.TIER_COLOR = {
    cheap = { 0.25, 0.85, 0.3 },
    ok = { 0.8, 0.8, 0.8 },
    high = { 1, 0.53, 0 },
    dontbuy = { 1, 0.2, 0.2 },
}
H.TIER_ICON = {
    cheap = ICON .. "chevron-down.png",
    high = ICON .. "chevron-up.png",
    dontbuy = ICON .. "chevron-double-up.png",
}
H.TIER_LABEL = { cheap = "Cheap", ok = "OK", high = "High", dontbuy = "Don't buy" }

local SECONDS_PER_DAY = 86400

local function Day0()
    local A = _G.Auctionator
    local constants = type(A) == "table" and A.Constants
    local day0 = type(constants) == "table" and tonumber(constants.SCAN_DAY_0)
    return day0 or time({ year = 2020, month = 1, day = 1, hour = 0 })
end

function H.Today(now)
    return math.floor(((now or time()) - Day0()) / SECONDS_PER_DAY)
end

function H.ReadHistory(itemIDs)
    local out = {}
    local A = _G.Auctionator
    local db = type(A) == "table" and A.Database
    if type(db) ~= "table" or type(db.GetPriceHistory) ~= "function" then return out end
    for _, id in ipairs(itemIDs) do
        local good, rows = pcall(db.GetPriceHistory, db, tostring(id))
        if good and type(rows) == "table" then
            local days = {}
            for _, row in ipairs(rows) do
                local day = type(row) == "table" and tonumber(row.rawDay)
                local low = day and tonumber(row.minSeen)
                if day and low and low > 0 then days[day] = low end
            end
            if next(days) then out[id] = days end
        end
    end
    return out
end

function H.Median(list)
    local n = #list
    if n == 0 then return nil end
    local sorted = {}
    for i = 1, n do sorted[i] = list[i] end
    table.sort(sorted)
    if n % 2 == 1 then return sorted[(n + 1) / 2] end
    return (sorted[n / 2] + sorted[n / 2 + 1]) / 2
end

function H.TypicalPrices(history, today, windowDays, fallback)
    local first = today - windowDays
    local prices, seen, days = {}, {}, 0
    for id, price in pairs(fallback) do
        local lows = {}
        for day, low in pairs(history[id] or {}) do
            if day >= first and day < today then
                lows[#lows + 1] = low
                if not seen[day] then
                    seen[day] = true
                    days = days + 1
                end
            end
        end
        prices[id] = H.Median(lows) or price
    end
    return prices, days
end

function H.DaysCovered(history, itemIDs, today, windowDays)
    local first, seen, days = today - windowDays, {}, 0
    for _, id in ipairs(itemIDs) do
        for day in pairs(history[id] or {}) do
            if day >= first and day < today and not seen[day] then
                seen[day] = true
                days = days + 1
            end
        end
    end
    return days
end

function H.DayPrices(history, today, windowDays, fallback)
    local first = today - windowDays
    local out = {}
    local last = {}
    for day = first, today - 1 do
        local any = false
        local prices = {}
        for id, price in pairs(fallback) do
            local low = (history[id] or {})[day]
            if low then
                last[id] = low
                any = true
            end
            prices[id] = last[id] or price
        end
        if any then out[#out + 1] = { day = day, prices = prices } end
    end
    return out
end

function H.Verdict(todayUnit, usualUnit, s)
    if not todayUnit or not usualUnit or usualUnit <= 0 then return nil end
    local pct = math.floor((todayUnit - usualUnit) * 100 / usualUnit + 0.5)
    local tier = "ok"
    if pct > s.dontBuyAbove then
        tier = "dontbuy"
    elseif pct > s.highAbove then
        tier = "high"
    elseif pct <= -s.cheapBelow then
        tier = "cheap"
    end
    return { tier = tier, pct = pct / 100 }
end
