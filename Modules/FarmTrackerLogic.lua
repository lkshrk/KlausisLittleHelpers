local _, ns = ...

local L = {}
ns.FarmLogic = L

function L.NewSession(kind, areaKey, now)
    return { kind = kind, areaKey = areaKey, started = now, lastCast = now, attempts = 0, gold = 0, items = {},
        seen = {} }
end

local function record(target, loot, sign)
    target.attempts = (target.attempts or 0) + sign * (loot.sources or 0)
    target.items = target.items or {}
    for _, slot in ipairs(loot.slots or {}) do
        local item = target.items[slot.itemID] or { count = 0, drops = 0 }
        target.items[slot.itemID] = item
        item.count = (item.count or 0) + sign * (slot.quantity or 0)
        item.drops = (item.drops or 0) + sign * (slot.sources or 0)
        item.name = slot.name or item.name
        item.quality = slot.quality or item.quality
        if item.count <= 0 then target.items[slot.itemID] = nil end
    end
end

function L.Record(session, area, loot)
    record(session, loot, 1)
    record(area, loot, 1)
end

function L.Unrecord(session, area, loot)
    record(session, loot, -1)
    record(area, loot, -1)
end

function L.AddGold(session, area, copper)
    session.gold = (session.gold or 0) + copper
    area.gold = (area.gold or 0) + copper
end

function L.FishingEnds(session, now, subzoneKey, idleMinutes)
    return session.areaKey ~= subzoneKey or now - session.lastCast >= idleMinutes * 60
end

local function totalItems(items)
    local total = 0
    for _, item in pairs(items or {}) do total = total + (item.count or 0) end
    return total
end

local function percent(value, total)
    if total == 0 then return 0 end
    return value * 100 / total
end

function L.Rows(session, area)
    local rows = {}
    local fishing = session.kind == "fish"
    local sTotal = fishing and totalItems(session.items) or (session.attempts or 0)
    local aTotal = fishing and totalItems(area.items) or (area.attempts or 0)
    for id, item in pairs(area.items or {}) do
        local s = (session.items or {})[id] or {}
        local sCount, aCount = s.count or 0, item.count or 0
        rows[#rows + 1] = { itemID = id, name = item.name or s.name or "", quality = item.quality or s.quality or 0,
            sCount = sCount, sPct = percent(fishing and sCount or (s.drops or 0), sTotal),
            aCount = aCount, aPct = percent(fishing and aCount or (item.drops or 0), aTotal) }
    end
    table.sort(rows, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.sCount ~= b.sCount then return a.sCount > b.sCount end
        if a.aCount ~= b.aCount then return a.aCount > b.aCount end
        if a.name ~= b.name then return a.name < b.name end
        return a.itemID < b.itemID
    end)
    return rows
end

function L.Clock(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    return string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
end

function L.Lines(view)
    local lines = {}
    local function add(label, value) lines[#lines + 1] = { label = "|cffffd100" .. label .. ":|r", value = value } end
    if view.kind == "fish" and view.skill then
        add("Skill", string.format("|cff20ff20%d%+d|r", view.skill.rank or 0, view.skill.modifier or 0))
    end
    add("Elapsed", L.Clock(view.sSeconds) .. "/" .. L.Clock(view.aSeconds))
    if view.kind == "farm" then
        add("Gold", ns.UI.FormatMoney(view.sGold or 0) .. " (" .. ns.UI.FormatMoney(view.aGold or 0) .. ")")
    end
    if view.kind == "fish" then add("Failed", string.format("%d (%d)", view.sFailed or 0, view.aFailed or 0)) end
    add("Totals", string.format("%d (%d)", view.sTotal or 0, view.aTotal or 0))
    local percents = view.showPercent ~= false
    for _, row in ipairs(view.rows or {}) do
        local colour = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[row.quality]
        local hex = colour and colour.hex or "|cffffffff"
        local cells = { "(", string.format("%d", row.sCount) }
        if percents then cells[#cells + 1] = " : "; cells[#cells + 1] = string.format("%.1f%%", row.sPct) end
        cells[#cells + 1] = ", "
        cells[#cells + 1] = string.format("%d", row.aCount)
        if percents then cells[#cells + 1] = " : "; cells[#cells + 1] = string.format("%.1f%%", row.aPct) end
        cells[#cells + 1] = ")"
        lines[#lines + 1] = { name = hex .. row.name .. "|r", cells = cells }
    end
    return lines
end

local function split(body, sep)
    local alts = {}
    for alt in (body .. sep):gmatch("(.-)" .. sep) do alts[#alts + 1] = alt end
    return alts
end

local function escape(text)
    return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

local function patterns(template, capture)
    local out = { "" }
    local function add(alts)
        local grown = {}
        for _, p in ipairs(out) do
            for _, a in ipairs(alts) do grown[#grown + 1] = p .. a end
        end
        out = grown
    end
    local i = 1
    while i <= #template do
        local _, stop, body = template:find("^|4([^;]*);", i)
        local _, stop1, one, many = template:find("^|1([^;]*);([^;]*);", i)
        local _, stopArg = template:find("^%%%d*%$?[sd]", i)
        if stop then
            local alts = split(body, ":")
            for k, alt in ipairs(alts) do alts[k] = escape(alt) end
            add(alts)
            i = stop + 1
        elseif stop1 then
            add({ escape(one), escape(many) })
            i = stop1 + 1
        elseif stopArg then
            add({ capture })
            i = stopArg + 1
        elseif template:sub(i, i + 1) == "%%" then
            add({ "%%" })
            i = i + 2
        else
            add({ escape(template:sub(i, i)) })
            i = i + 1
        end
    end
    return out
end

local COINS = { { "GOLD_AMOUNT", 10000 }, { "SILVER_AMOUNT", 100 }, { "COPPER_AMOUNT", 1 } }
local OWN_MONEY = { "YOU_LOOT_MONEY_GUILD", "LOOT_MONEY_SPLIT_GUILD", "YOU_LOOT_MONEY", "LOOT_MONEY_SPLIT" }

local function matches(text, template, capture)
    if type(template) ~= "string" or template == "" then return end
    for _, p in ipairs(patterns(template, capture)) do
        local found = text:match("^" .. p .. "$")
        if found then return found end
    end
end

function L.Copper(text, strings)
    local total, found = 0, false
    for _, coin in ipairs(COINS) do
        local template = strings[coin[1]]
        if type(template) == "string" then
            for _, p in ipairs(patterns(template, "(%d[%d%.,]*)")) do
                local digits = text:match(p)
                if digits then
                    total, found = total + (tonumber((digits:gsub("%D", ""))) or 0) * coin[2], true
                    break
                end
            end
        end
    end
    if found then return total end
end

function L.LootMoney(text, strings)
    if type(text) ~= "string" then return end
    if matches(text, strings.LOOT_MONEY, "(.-)") then return end
    for _, key in ipairs(OWN_MONEY) do
        local amount = matches(text, strings[key], "(.-)")
        if amount then return L.Copper(amount, strings) end
    end
end
