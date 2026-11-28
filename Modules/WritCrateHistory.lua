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

local function Finite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function ValidPrice(n)
    return Finite(n) and n > 0
end

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
                if Finite(day) and ValidPrice(low) then days[day] = low end
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

function H.WeightedMedian(observations, today, halfLife)
    if not Finite(today) or not Finite(halfLife) or halfLife <= 0 then return nil end
    local sorted, newest = {}, nil
    for _, row in ipairs(observations) do
        if type(row) == "table" and Finite(row.day) and row.day < today and Finite(row.value) and row.value >= 0 then
            sorted[#sorted + 1] = { day = row.day, value = row.value }
            if not newest or row.day > newest then newest = row.day end
        end
    end
    if not newest then return nil end
    table.sort(sorted, function(a, b)
        if a.value == b.value then return a.day < b.day end
        return a.value < b.value
    end)
    local total = 0
    for _, row in ipairs(sorted) do
        row.weight = 2 ^ ((row.day - newest) / halfLife)
        total = total + row.weight
    end
    local cumulative = 0
    for i, row in ipairs(sorted) do
        cumulative = cumulative + row.weight
        if cumulative == total / 2 and sorted[i + 1] then
            return row.value / 2 + sorted[i + 1].value / 2
        elseif cumulative > total / 2 then
            return row.value
        end
    end
end

local function Qualified(row)
    if type(row) ~= "table" or not Finite(row.day) or not ValidPrice(row.value) then return false end
    local total, fresh, observed = 0, 0, 0
    local function add(cost, provenance)
        if not Finite(cost) or cost < 0 or type(provenance) ~= "table" then return false end
        local kind, source = provenance.kind, provenance.sourceDay
        if kind ~= "fallback" and kind ~= "observed" and kind ~= "carried" then return false end
        if kind ~= "fallback" and (not Finite(source) or source > row.day
            or (kind == "observed" and source ~= row.day) or (kind == "carried" and source >= row.day)) then return false end
        total = total + cost
        if kind == "observed" then observed = observed + cost end
        if kind == "observed" or (kind == "carried" and row.day - source <= 3) then fresh = fresh + cost end
        return true
    end
    if row.costByItem and type(row.provenance) == "table" and ValidPrice(row.gain) then
        for id, cost in pairs(row.costByItem) do
            if not Finite(cost) or not add(cost / row.gain, row.provenance[id]) then return false end
        end
    elseif type(row.components) == "table" then
        for _, c in ipairs(row.components) do
            if type(c) ~= "table" or not ValidPrice(c.gain) or not ValidPrice(c.selectedCount)
                or not Finite(c.cost) or not Finite(c.contribution)
                or math.abs(c.cost / c.gain / c.selectedCount - c.contribution) > 1e-9 * math.max(1, math.abs(c.contribution))
                or not add(c.contribution, c.provenance) then return false end
        end
    else
        return false
    end
    return ValidPrice(total) and Finite(fresh) and Finite(observed)
        and math.abs(total - row.value) <= 1e-9 * math.max(1, row.value)
        and fresh / total >= 0.8 and observed / total >= 0.2
end

function H.Trend(observations, today)
    if not Finite(today) or type(observations) ~= "table" then return nil end
    local rows, seen, first, last = {}, {}, nil, nil
    for _, row in ipairs(observations) do
        if Qualified(row) and row.day <= today then
            if seen[row.day] then return nil end
            seen[row.day] = true
            rows[#rows + 1] = { day = row.day, log = math.log(row.value) }
            first = first and math.min(first, row.day) or row.day
            last = last and math.max(last, row.day) or row.day
        end
    end
    local count = #rows
    if count < 5 or last - first < 7 or today - last > 3 then return nil end
    local function slope(skip)
        local n, x, y = 0, 0, 0
        for i, row in ipairs(rows) do
            if i ~= skip then n = n + 1; x = x + (row.day - first); y = y + row.log end
        end
        x, y = x / n, y / n
        local cov, var = 0, 0
        for i, row in ipairs(rows) do
            if i ~= skip then
                local dx = row.day - first - x
                cov, var = cov + dx * (row.log - y), var + dx * dx
            end
        end
        if not Finite(cov) or not Finite(var) or var <= 0 then return nil end
        local result = cov / var
        return Finite(result) and result or nil
    end
    local rate = slope()
    if not rate then return nil end
    for i = 1, count do
        local other = slope(i)
        if not other or (rate > 1e-12 and other < -1e-12) or (rate < -1e-12 and other > 1e-12) then return nil end
    end
    local pct = (math.exp(rate) - 1) * 100
    if not Finite(pct) then return nil end
    return { pctPerDay = pct, count = count, span = last - first }
end

function H.TypicalPrices(history, today, windowDays, fallback, halfLife)
    if not Finite(halfLife) or halfLife <= 0 then halfLife = 4 end
    local first = today - windowDays
    local prices, seen, days = {}, {}, 0
    for id, price in pairs(fallback) do
        local lows = {}
        for day, low in pairs(history[id] or {}) do
            if Finite(day) and day >= first and day < today and ValidPrice(low) then
                lows[#lows + 1] = { day = day, value = low }
                if not seen[day] then
                    seen[day] = true
                    days = days + 1
                end
            end
        end
        prices[id] = H.WeightedMedian(lows, today, halfLife) or price
    end
    return prices, days
end

function H.DaysCovered(history, itemIDs, today, windowDays)
    local first, seen, days = today - windowDays, {}, 0
    for _, id in ipairs(itemIDs) do
        for day, low in pairs(history[id] or {}) do
            if Finite(day) and day >= first and day < today and ValidPrice(low) and not seen[day] then
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
        local prices, provenance = {}, {}
        for id, price in pairs(fallback) do
            local low = (history[id] or {})[day]
            if ValidPrice(low) then
                last[id] = { price = low, day = day }
                any = true
            end
            local previous = last[id]
            prices[id] = previous and previous.price or price
            provenance[id] = previous and { kind = previous.day == day and "observed" or "carried", sourceDay = previous.day }
                or { kind = "fallback" }
        end
        if any then out[#out + 1] = { day = day, prices = prices, provenance = provenance } end
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
