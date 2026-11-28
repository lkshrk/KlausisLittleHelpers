local names = { "CreateFrame", "UIParent", "GetBuildInfo", "C_AddOns", "geterrorhandler", "LibStub", "KLH", "SlashCmdList",
    "SLASH_KLH1", "C_Timer", "GetTime", "GetProfessions", "GetProfessionInfo", "C_SpellBook", "Enum", "IsFishingLoot", "GetNumLootItems",
    "GetLootSlotInfo", "GetLootSlotLink", "GetLootSlotType", "GetLootSourceInfo", "GetRealZoneText", "GetSubZoneText",
    "GetMoney", "print", "issecretvalue", "GOLD_AMOUNT", "SILVER_AMOUNT", "COPPER_AMOUNT", "YOU_LOOT_MONEY",
    "ERR_FISH_ESCAPED", "ERR_FISH_NOT_HOOKED", "LOOT_MONEY_SPLIT", "YOU_LOOT_MONEY_GUILD", "LOOT_MONEY_SPLIT_GUILD", "LOOT_MONEY" }
local saved = {}
for _, k in ipairs(names) do saved[k] = rawget(_G, k) end

local frames, tickers = {}, {}
local function NewObject()
    local o = { events = {}, scripts = {}, shown = true, points = {}, texts = {} }
    return setmetatable(o, { __index = function(_, k)
        local fn = ({
            RegisterEvent = function(self, e) self.events[e] = true end,
            UnregisterEvent = function(self, e) self.events[e] = nil end,
            RegisterUnitEvent = function(self, e, unit) self.events[e] = unit end,
            SetScript = function(self, name, f) self.scripts[name] = f end,
            Show = function(self) self.shown = true end,
            Hide = function(self) self.shown = false end,
            SetShown = function(self, v) self.shown = v and true or false end,
            IsShown = function(self) return self.shown end,
            SetText = function(self, s) self.text = s end,
            GetText = function(self) return self.text end,
            ClearAllPoints = function(self) self.points = {} end,
            SetPoint = function(self, p, rel, rp, x, y) self.points[#self.points + 1] = { p, rel, rp, x, y } end,
            GetLeft = function() return 120 end,
            GetTop = function() return 700 end,
            GetStringWidth = function(self) return #(self.text or "") * 6 end,
            SetJustifyH = function(self, j) self.justify = j end,
            SetHeight = function(self, h) self.height = h end,
            SetWidth = function(self, w) self.width = w end,
            SetSize = function(self, w, h) self.width, self.height = w, h end,
            CreateFontString = function(self) local f = NewObject(); self.texts[#self.texts + 1] = f; return f end,
            CreateTexture = function() return NewObject() end,
        })[k]
        return fn or function() end
    end })
end
_G.UIParent = NewObject()
_G.CreateFrame = function(kind, _, parent)
    local f = NewObject()
    f.kind, f.parent = kind, parent
    frames[#frames + 1] = f
    return f
end
_G.GetBuildInfo = function() return "12.0.1", "1", "", 120001 end
_G.C_AddOns = { IsAddOnLoaded = function() return false end }
_G.geterrorhandler = function() return function(e) error(e, 0) end end
_G.SlashCmdList = {}
local printed
_G.print = function(msg) printed = msg end
local fakeDB = { char = {}, global = {}, profile = { features = {} } }
_G.LibStub = function(name) if name == "AceDB-3.0" then return { New = function() return fakeDB end } end end
_G.C_Timer = { NewTicker = function(_, fn)
    local t = { fn = fn }
    t.Cancel = function(self) self.cancelled = true end
    tickers[#tickers + 1] = t
    return t
end }

local now, money, zone, subzone = 1000, 5000, "Darkshore", "Auberdine"
local loot = { fishing = false, slots = {}, sources = nil }
_G.GetTime = function() return now end
_G.GetMoney = function() return money end
_G.GetRealZoneText = function() return zone end
_G.GetSubZoneText = function() return subzone end
_G.GetProfessions = function() return 1, nil, nil, 4, nil end
_G.GetProfessionInfo = function(i)
    if i == 4 then return "Fishing", 0, 300, 300, 1, 0, 356, 22 end
    return "Mining", 0, 100, 150, 1, 0, 186, 0
end
_G.Enum = { SpellBookSpellBank = { Player = 0 } }
_G.C_SpellBook = {
    GetSpellBookItemName = function(i, bank) if i == 1 and bank == 0 then return "Fishing" end end,
    GetSpellBookItemType = function(i) if i == 1 then return 1, 0, 999001 end end,
}
_G.IsFishingLoot = function() return loot.fishing end
_G.GetNumLootItems = function() return #loot.slots end
_G.GetLootSlotType = function(i) return loot.slots[i].type or 1 end
_G.GetLootSlotLink = function(i)
    local s = loot.slots[i]
    if s.id then return "|cffffffff|Hitem:" .. s.id .. "::::|h[" .. s.name .. "]|h|r" end
end
_G.GetLootSlotInfo = function(i)
    local s = loot.slots[i]
    return 0, s.name, s.qty or 1, nil, s.quality or 1
end
_G.GetLootSourceInfo = nil
_G.GOLD_AMOUNT, _G.SILVER_AMOUNT, _G.COPPER_AMOUNT = "%d Gold", "%d Silver", "%d Copper"
_G.YOU_LOOT_MONEY, _G.LOOT_MONEY_SPLIT = "You loot %s", "Your share of the loot is %s."
_G.YOU_LOOT_MONEY_GUILD = "You loot %s (%s deposited to guild bank)"
_G.LOOT_MONEY_SPLIT_GUILD = "Your share of the loot is %s. (%s deposited to guild bank)"
_G.LOOT_MONEY = "%s loots %s."
local solids = {}

local good, problem = pcall(function()
    addon("Core/Core.lua")
    ns.UI = {
        Accent = function() return 0, 1, 0 end,
        Font = function(parent) return parent:CreateFontString() end,
        Solid = function(parent, layer, r, g, b, a)
            local t = parent:CreateTexture()
            t.layer, t.rgba = layer, { r, g, b, a }
            solids[#solids + 1] = t
            return t
        end,
        Border = function() end,
        FormatMoney = function(c) return tostring(c) .. "c" end,
        ShowTooltip = function() end,
        HideTooltip = function() end,
    }
    addon("Modules/FarmTrackerLogic.lua")
    addon("Modules/FarmTracker.lua")
    local spec = ns.features.FarmTracker
    ok(spec ~= nil, "registers")
    eq(spec.tab, "helpers"); ok(spec.alwaysOn, "always on"); eq(spec.title, "Farm Tracker")
    eq(spec.launcher.text, "Toggle farming")
    eq(ns.GetSettings("FarmTracker").fishIdleMinutes, 10)

    local loader = frames[1]
    loader.scripts.OnEvent(loader, "PLAYER_LOGIN")
    local events = find(frames, nil, nil, function(f) return f.events.LOOT_READY end)
    ok(events ~= nil, "listens for loot")
    eq(events.events.UNIT_SPELLCAST_CHANNEL_START, "player", "listens for the player's casts only")
    ok(events.events.ZONE_CHANGED and events.events.PLAYER_LOGOUT and events.events.LOOT_OPENED
        and events.events.CHAT_MSG_MONEY and events.events.SPELLS_CHANGED, "listens for zones, logout, loot and money")
    eq(events.events.PLAYER_MONEY, nil, "money changes alone are not loot")
    local notified = 0
    ns.NotifyOptionsChanged = function() notified = notified + 1 end
    local function fire(event, ...) events.scripts.OnEvent(events, event, ...) end
    local function rowText(name)
        local y, cells = nil, {}
        for _, fs in ipairs(ns.FarmTracker.Watcher().texts) do
            if fs.shown and fs.text and fs.text:find(name, 1, true) then y = fs.points[1][5] end
        end
        for _, fs in ipairs(ns.FarmTracker.Watcher().texts) do
            if fs.shown and fs.text and fs.points[1] and fs.points[1][5] == y then cells[#cells + 1] = fs end
        end
        table.sort(cells, function(a, b)
            local function x(fs) return fs.points[1][4] + (fs.points[1][3] == "TOPRIGHT" and ns.FarmTracker.Watcher().width or 0) end
            return x(a) < x(b)
        end)
        local out = {}
        for _, fs in ipairs(cells) do out[#out + 1] = fs.text end
        return table.concat(out)
    end
    local function shownText()
        local out = {}
        for _, fs in ipairs(ns.FarmTracker.Watcher().texts) do if fs.shown and fs.text then out[#out + 1] = fs.text end end
        return table.concat(out, " / ")
    end
    local function divider()
        for _, t in ipairs(solids) do if t.rgba[4] == 0.4 then return t end end
    end
    local FT = ns.FarmTracker
    eq(FT.Current(), nil, "no session at login")
    local watcher = FT.Watcher()
    ok(watcher == nil or not watcher.shown, "watcher hidden without a session")

    fire("UNIT_SPELLCAST_CHANNEL_START", "target", "guid", 131474)
    eq(FT.Current(), nil, "other units ignored")
    fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 133)
    eq(FT.Current(), nil, "other spells ignored")
    fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 131476)
    local fish = FT.Current()
    ok(fish ~= nil and fish.kind == "fish", "casting Fishing starts a fishing session")
    ok(notified > 0, "a session start updates the options")
    fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 131474)
    eq(FT.Current(), fish, "the other channel ID keeps the session")
    eq(fish.areaKey, "fish:Darkshore:Auberdine")
    watcher = FT.Watcher()
    ok(watcher and watcher.shown, "watcher shown on start")
    eq(watcher.width, 280, "compact watcher uses 280 minimum width")
    ok(shownText():find("Fishing - Auberdine", 1, true), "header shows fishing subzone")
    FT.TogglePause()
    ok(shownText():find("Fishing - Auberdine (Paused)", 1, true), "header shows paused state")
    FT.TogglePause()
    subzone = string.rep("Long", 40)
    FT.TogglePause()
    ok(watcher.width >= 6 + (string.len("Fishing - ") + #subzone) * 6 + 34,
        "long header clears controls")
    subzone = "Auberdine"
    FT.TogglePause()
    ok(#tickers == 1 and not tickers[1].cancelled, "ticker runs")

    loot.fishing = true
    loot.slots = { { id = 6289, name = "Raw Longjaw Mud Snapper", quality = 1, qty = 1 },
        { id = 6358, name = "Oily Blackmouth", quality = 1, qty = 2 } }
    fire("LOOT_READY", true)
    fire("LOOT_READY", false)
    fire("LOOT_CLOSED")
    local areas = fakeDB.global.FarmTracker.areas
    local area = areas["fish:Darkshore:Auberdine"]
    ok(area ~= nil, "area stored in global")
    eq(area.items[6289].count, 1, "recorded once despite two LOOT_READY")
    eq(area.items[6358].count, 2)
    eq(area.items[6358].name, "Oily Blackmouth"); eq(area.items[6358].quality, 1)
    eq(fish.items[6358].count, 2, "session counts too")

    now = now + 30
    tickers[1].fn()
    local shown = shownText()
    ok(shown:find("Skill:|r / |cffffd100Elapsed:|r / |cffffd100Failed:|r / |cffffd100Totals:|r", 1, true), "labels in order: " .. shown)
    ok(shown:find("|cff20ff20300+22|r / 00:00:30/00:00:30 / 0 (0) / 3 (3)", 1, true), "values in order: " .. shown)
    local labels, values = {}, {}
    for _, fs in ipairs(watcher.texts) do
        local pt = fs.points[1]
        if fs.shown and fs.text and pt then
            if fs.text:find("^|cffffd100") then labels[pt[5]] = fs
            elseif pt[1] == "TOPRIGHT" and pt[5] >= -62 then values[pt[5]] = fs end
        end
    end
    for y, value in pairs(values) do
        local pt = value.points[1]
        ok(y <= -20, "summary starts below header")
        eq(pt[3], "TOPRIGHT", "summary values anchored to right edge")
        eq(pt[4], -34, "summary values leave room for both controls")
        eq(value.justify, "RIGHT", "summary values right justified")
        ok(watcher.width + pt[4] - value:GetStringWidth() >= 6 + labels[y]:GetStringWidth() + 6,
            "summary value clears label")
    end
    ok(divider() and divider().shown, "divider shown above item rows")
    eq(divider().rgba[1], 1); eq(divider().rgba[2], 0.82); eq(divider().rgba[3], 0)
    eq(rowText("Oily Blackmouth"), "|cffffffffOily Blackmouth|r(2 : 66.7%, 2 : 66.7%)")
    eq(rowText("Raw Longjaw Mud Snapper"), "|cffffffffRaw Longjaw Mud Snapper|r(1 : 33.3%, 1 : 33.3%)")
    local rowsByY, nameRight = {}, 0
    for _, fs in ipairs(watcher.texts) do
        local pt = fs.points[1]
        if fs.shown and pt and pt[1] == "TOPRIGHT" and pt[5] < -62 then
            rowsByY[pt[5]] = rowsByY[pt[5]] or {}
            table.insert(rowsByY[pt[5]], watcher.width + pt[4])
            eq(fs.justify, "RIGHT", "cells are right-justified")
        elseif fs.shown and pt and fs.text and fs.text:find("^|cffffffff") then
            nameRight = math.max(nameRight, pt[4] + fs:GetStringWidth())
        end
    end
    local edgeRows = {}
    for _, edges in pairs(rowsByY) do table.sort(edges); edgeRows[#edgeRows + 1] = edges end
    eq(#edgeRows, 2, "two item rows")
    eq(#edgeRows[1], 9, "nine cells per row")
    for j = 1, 9 do eq(edgeRows[1][j], edgeRows[2][j], "column " .. j .. " shares a right edge") end
    ok(edgeRows[1][1] - 6 >= nameRight, "columns start right of the widest name")
    eq(edgeRows[1][9], watcher.width - 6, "last column ends one pad from right edge")

    local lines = ns.FarmLogic.Lines
    ns.FarmLogic.Lines = function()
        return { { label = string.rep("L", 50), value = string.rep("V", 60) },
            { name = string.rep("N", 90), cells = { string.rep("9", 40) } } }
    end
    tickers[1].fn()
    ok(watcher.width > 280, "long content expands watcher")
    local label, value, name, cell
    for _, fs in ipairs(watcher.texts) do
        if fs.shown then
            if fs.text == string.rep("L", 50) then label = fs
            elseif fs.text == string.rep("V", 60) then value = fs
            elseif fs.text == string.rep("N", 90) then name = fs
            elseif fs.text == string.rep("9", 40) then cell = fs end
        end
    end
    ok(watcher.width - 34 - value:GetStringWidth() >= 12 + label:GetStringWidth(), "long summary clears label")
    ok(watcher.width + cell.points[1][4] - cell:GetStringWidth() >= 14 + name:GetStringWidth(),
        "long item name clears numeric cell")
    ns.FarmLogic.Lines = lines
    tickers[1].fn()

    subzone = "Auberdine Docks"
    fire("ZONE_CHANGED")
    eq(FT.Current(), nil, "a subzone change ends fishing")
    eq(area.seconds, 30, "seconds merged into the area")
    eq(watcher.shown, false, "watcher hidden on end")
    ok(tickers[1].cancelled, "ticker stops")

    subzone = "Auberdine"
    loot.fishing, loot.slots = true, { { id = 6289, name = "Raw Longjaw Mud Snapper", quality = 1, qty = 1 } }
    fire("LOOT_READY")
    fish = FT.Current()
    ok(fish and fish.kind == "fish", "fishing loot without a session starts one")
    eq(area.items[6289].count, 2, "same area survives a new session")
    fire("LOOT_CLOSED")
    now = now + 10
    tickers[#tickers].fn()
    ok(shownText():find("00:00:10/00:00:40", 1, true), "area clock adds the running session: " .. shownText())

    now = now + 600
    tickers[#tickers].fn()
    eq(FT.Current(), nil, "ten idle minutes end fishing")
    eq(area.seconds, 640)

    SlashCmdList.KLH("farm")
    local farm = FT.Current()
    ok(farm and farm.kind == "farm", "/klh farm starts farming")
    eq(farm.areaKey, "farm:Darkshore")
    ok(watcher.shown, "watcher shown for farming")
    eq(divider().shown, false, "no divider without item rows")

    loot.fishing = false
    loot.slots = { { type = 2, name = "12 Copper" },
        { id = 2589, name = "Linen Cloth", quality = 1, qty = 3 },
        { id = 2589, name = "Linen Cloth", quality = 1, qty = 1 } }
    _G.GetLootSourceInfo = function(i)
        if i == 1 then return "Creature-1", 12 end
        if i == 2 then return "Creature-1", 3 end
        return "Creature-2", 1
    end
    fire("LOOT_READY", true)
    money = money + 12
    fire("PLAYER_MONEY")
    fire("CHAT_MSG_MONEY", "You loot 12 Copper")
    fire("LOOT_READY", false)
    fire("LOOT_CLOSED")
    local farea = areas["farm:Darkshore"]
    eq(farea.attempts, 2, "two loot sources count two attempts")
    eq(farm.attempts, 2)
    eq(farea.items[2589].count, 4); eq(farea.items[2589].drops, 2, "both corpses dropped cloth")
    eq(farea.gold, 12, "gold gained while looting"); eq(farm.gold, 12)
    eq(farea.items[0], nil, "money slots are not items")
    fire("CHAT_MSG_MONEY", "Your share of the loot is 1 Silver, 5 Copper.")
    eq(farm.gold, 117, "a group share without a loot window counts"); eq(farea.gold, 117)
    money = money + 500
    fire("PLAYER_MONEY")
    eq(farm.gold, 117, "a vendor sale is not counted")
    fire("CHAT_MSG_MONEY", "Bob loots 3 Gold.")
    eq(farm.gold, 117, "another player's loot is not counted")
    _G.issecretvalue = function() return true end
    fire("CHAT_MSG_MONEY", "You loot 1 Gold")
    _G.issecretvalue = nil
    eq(farm.gold, 117, "secret money text is skipped")

    _G.GetLootSourceInfo = nil
    loot.slots = { { id = 2589, name = "Linen Cloth", quality = 1, qty = 1 } }
    fire("LOOT_READY")
    fire("LOOT_CLOSED")
    eq(farea.attempts, 3, "one attempt per window without source info")

    now = now + 4
    loot.fishing = true
    loot.slots = { { id = 6289, name = "Raw Longjaw Mud Snapper", quality = 1, qty = 1 } }
    fire("LOOT_READY")
    fire("LOOT_CLOSED")
    eq(FT.Current(), farm, "fished loot while farming keeps farming")
    eq(farea.items[6289], nil, "fished loot never counts for farming")
    eq(area.items[6289].count, 2, "nor for fishing")
    eq(farea.attempts, 3)
    fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
    eq(FT.Current(), farm, "a Fishing cast while farming is ignored")

    now = now + 5
    SlashCmdList.KLH("farm")
    eq(FT.Current(), nil, "/klh farm while farming stops it")
    eq(farea.seconds, 9, "farming seconds merged")
    eq(watcher.shown, false)
    loot.fishing = false
    loot.slots = { { id = 2589, name = "Linen Cloth", quality = 1, qty = 1 } }
    fire("LOOT_READY")
    fire("LOOT_CLOSED")
    eq(farea.attempts, 3, "no loot counts outside a session")

    fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 999001)
    fish = FT.Current()
    ok(fish and fish.kind == "fish", "the spellbook's Fishing spell starts fishing")
    fire("LOOT_READY")
    fire("CHAT_MSG_MONEY", "You loot 5 Copper")
    fire("LOOT_CLOSED")
    eq(fish.items[2589], nil, "fishing ignores other loot")
    eq(fish.gold, 0, "fishing ignores gold")
    eq(area.items[2589], nil); eq(area.gold or 0, 0)
    eq(farea.attempts, 3, "other loot while fishing does not count for farming")
    tickers[#tickers].fn()
    for _, fs in ipairs(watcher.texts) do
        ok(not (fs.shown and fs.text and fs.text:find("Gold:")), "fishing shows no gold row")
    end

    printed = nil
    SlashCmdList.KLH("farm")
    eq(FT.Current(), fish, "/klh farm while fishing keeps fishing")
    ok(printed and printed:find("Farm Tracker: a fishing session is running; stop it first %(x on the watcher%)%."),
        "explains why: " .. tostring(printed))
    spec.launcher.onClick()
    eq(FT.Current(), fish, "the launcher while fishing keeps fishing")
    FT.Stop()
    eq(FT.Current(), nil, "stop ends fishing")

    spec.launcher.onClick()
    ok(FT.Current() and FT.Current().kind == "farm", "launcher starts farming")
    eq(FT.Current().attempts, 0, "a new session starts empty")
    eq(areas["farm:Darkshore"].attempts, 3, "area keeps its history")
    spec.launcher.onClick()
    eq(FT.Current(), nil, "launcher again stops farming")
    spec.launcher.onClick()

    local args = spec.options(ns.GetSettings("FarmTracker"))
    eq(args.fishIdleMinutes.min, 1); eq(args.fishIdleMinutes.max, 60); eq(args.fishIdleMinutes.step, 1)
    args.fishIdleMinutes.set(nil, 2)
    eq(args.fishIdleMinutes.get(), 2)
    ok(args.resetArea.confirm, "reset asks first")
    eq(args.resetArea.disabled(), false)
    args.resetArea.func()
    eq(areas["farm:Darkshore"].attempts or 0, 0, "reset clears the area")
    eq(next(areas["farm:Darkshore"].items or {}), nil)
    ok(areas["fish:Darkshore:Auberdine"].items[6289] ~= nil, "other areas untouched")

    fire("LOOT_READY")
    fire("LOOT_CLOSED")
    eq(FT.Current().attempts, 1)
    now = now + 7
    zone = "Ashenvale"
    fire("ZONE_CHANGED_NEW_AREA")
    local moved = FT.Current()
    ok(moved and moved.kind == "farm" and moved.areaKey == "farm:Ashenvale", "a zone change restarts farming there")
    eq(moved.attempts, 0, "the new session starts empty")
    eq(areas["farm:Darkshore"].seconds, 7, "old area keeps its seconds")
    eq(areas["farm:Darkshore"].attempts, 1)
    now = now + 3
    fire("PLAYER_LOGOUT")
    eq(areas["farm:Ashenvale"].seconds, 3, "logout merges seconds")
    now = now + 2
    fire("PLAYER_LOGOUT")
    eq(areas["farm:Ashenvale"].seconds, 5, "no double counting after a merge")

    _G.issecretvalue = function() return true end
    fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 131474)
    eq(FT.Current().kind, "farm", "secret spell IDs are ignored")
    _G.issecretvalue = nil

    watcher.scripts.OnDragStop(watcher)
    local point = ns.GetSettings("FarmTracker").point
    eq(point.point, "TOPLEFT"); eq(point.x, 120); eq(point.y, 700)

    local stop = find(frames, nil, nil, function(f) return f.kind == "Button" and f.parent == watcher end)
    ok(stop ~= nil, "stop button exists")
    stop.scripts.OnClick(stop)
    eq(FT.Current(), nil, "stop button ends the session")
    eq(args.resetArea.disabled(), true, "reset disabled without a session")

    local function active()
        local n = 0
        for _, t in ipairs(tickers) do if not t.cancelled then n = n + 1 end end
        return n
    end

    local reads = 0
    local realCount = _G.GetNumLootItems
    _G.GetNumLootItems = function() reads = reads + 1; return realCount() end
    loot.fishing = false
    fire("LOOT_READY")
    fire("LOOT_CLOSED")
    eq(reads, 0, "loot without a session is never read")
    _G.GetNumLootItems = realCount

    fire("SPELLS_CHANGED")
    _G.C_SpellBook.GetSpellBookItemType = function(i) if i == 1 then return 1, 0, 999002 end end
    fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 999002)
    ok(FT.Current() and FT.Current().kind == "fish", "the spellbook ID is looked up again after SPELLS_CHANGED")
    local before = notified
    FT.Stop()
    ok(notified > before, "a session end updates the options")

    SlashCmdList.KLH("farm")
    farm = FT.Current()
    local aarea = areas["farm:Ashenvale"]
    local baseAttempts = aarea.attempts
    loot.slots = { { type = 2, name = "5 Copper" },
        { id = 2589, name = "Linen Cloth", quality = 1, qty = 2 },
        { type = 2, name = "3 Copper" } }
    _G.GetLootSourceInfo = function(i)
        if i == 3 then return "Creature-B", 3 end
        return "Creature-A", 1
    end
    fire("LOOT_READY")
    fire("CHAT_MSG_MONEY", "You loot 5 Copper")
    money = money + 8
    fire("PLAYER_MONEY")
    fire("CHAT_MSG_MONEY", "You loot 3 Copper")
    fire("LOOT_CLOSED")
    eq(farm.attempts, 2, "two corpses, two attempts")
    eq(farm.gold, 8, "each coin message credits once, nothing again on money or close")
    tickers[#tickers].fn()
    eq(rowText("Linen Cloth"), "|cffffffffLinen Cloth|r(2 : 50.0%, 2 : 50.0%)", "farm drop % per source")

    fire("LOOT_READY")
    fire("LOOT_CLOSED")
    eq(farm.attempts, 2, "a re-opened corpse adds no attempt")
    eq(farm.items[2589].count, 2, "nor items")
    eq(aarea.attempts, baseAttempts + 2)

    loot.slots = { { id = 2589, name = "Linen Cloth", quality = 1, qty = 1 } }
    _G.GetLootSourceInfo = function() return "Item-0-0-1", 1 end
    fire("LOOT_READY")
    fire("CHAT_MSG_MONEY", "You loot 10 Copper")
    fire("LOOT_CLOSED")
    eq(farm.attempts, 2, "loot from a bag item never counts")
    eq(farm.items[2589].count, 2); eq(farm.gold, 8, "nor its gold")

    _G.GetLootSourceInfo = nil
    fire("LOOT_READY")
    eq(farm.attempts, 3)
    fire("LOOT_OPENED", false, true)
    fire("CHAT_MSG_MONEY", "You loot 4 Copper")
    fire("LOOT_CLOSED")
    eq(farm.attempts, 2, "isFromItem undoes the window")
    eq(farm.items[2589].count, 2); eq(aarea.items[2589].count, 2); eq(farm.gold, 8)
    fire("LOOT_OPENED", false, true)
    fire("LOOT_READY")
    fire("LOOT_CLOSED")
    eq(farm.attempts, 2, "isFromItem before LOOT_READY skips the window")

    _G.GetLootSourceInfo = function() return "Creature-C", 1 end
    fire("LOOT_READY")
    zone = "Felwood"
    fire("ZONE_CHANGED_NEW_AREA")
    local felwood = FT.Current()
    ok(felwood ~= farm and felwood.areaKey == "farm:Felwood", "zone change mid-loot restarts farming")
    eq(active(), 1, "one ticker after a zone restart")
    fire("CHAT_MSG_MONEY", "You loot 20 Copper")
    fire("LOOT_CLOSED")
    eq(farm.gold, 8, "gold goes to the running session's current area")
    eq(aarea.gold, 8)
    eq(felwood.gold, 20); eq(areas["farm:Felwood"].gold, 20)
    FT.Stop()

    loot.fishing = true
    _G.GetLootSourceInfo = function() return "GameObject-Pool", 1 end
    loot.slots = { { id = 6289, name = "Raw Longjaw Mud Snapper", quality = 1, qty = 1 } }
    fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 131476)
    fish = FT.Current()
    fire("LOOT_READY")
    fire("LOOT_CLOSED")
    fire("LOOT_READY")
    fire("LOOT_CLOSED")
    eq(fish.items[6289].count, 2, "a fishing pool's GUID is not deduplicated")
    fire("CHAT_MSG_MONEY", "Your share of the loot is 9 Silver.")
    eq(fish.gold, 0, "fishing never counts gold")
    fire("LOOT_READY")
    args.resetArea.func()
    fire("LOOT_OPENED", false, true)
    fire("LOOT_CLOSED")
    eq(areas["fish:Felwood:Auberdine"].attempts, 0, "late item classification cannot undo reset area")
    local fresh = FT.Current()
    ok(fresh and fresh.kind == "fish" and fresh.areaKey == "fish:Felwood:Auberdine", "reset restarts the fishing session")
    eq(next(areas["fish:Felwood:Auberdine"].items), nil, "reset clears the fishing area")
    eq(active(), 1, "one ticker after a reset")
    local resetAll = args.resetAllAreas
    ok(resetAll and resetAll.confirm == true and resetAll.confirmText, "reset all requires confirmation")
    local global = ns.GetDB().global
    global.FarmTracker.unrelated = "keep"
    global.unrelated = "keep"
    fire("LOOT_READY")
    fire("LOOT_CLOSED")
    local beforeCancel = areas["fish:Felwood:Auberdine"]
    local function respondToConfirm(accepted)
        if not resetAll.confirm or accepted then resetAll.func() end
    end
    respondToConfirm(false)
    eq(areas["fish:Felwood:Auberdine"], beforeCancel, "cancel leaves area history unchanged")
    eq(beforeCancel.items[6289].count, 1, "cancel preserves recorded loot")
    eq(FT.Current(), fresh, "cancel leaves session unchanged")
    fire("LOOT_READY")
    respondToConfirm(true)
    fire("LOOT_OPENED", false, true)
    fire("LOOT_CLOSED")
    eq(areas["fish:Felwood:Auberdine"].attempts, 0, "late item classification cannot undo reset all")
    local restarted = FT.Current()
    ok(restarted and restarted ~= fresh and restarted.kind == fresh.kind and restarted.areaKey == fresh.areaKey,
        "reset all restarts the active session in the same area")
    eq(next(areas["fish:Felwood:Auberdine"].items), nil)
    for key in pairs(areas) do eq(key, restarted.areaKey, "only the new active area remains") end
    eq(active(), 1, "reset all keeps one ticker")
    eq(global.FarmTracker.unrelated, "keep")
    eq(global.unrelated, "keep")
    fire("LOOT_READY")
    fire("LOOT_CLOSED")
    eq(areas["fish:Felwood:Auberdine"].attempts, 1, "subsequent loot records after reset")
    FT.Stop()
    resetAll.func()
    eq(next(areas), nil, "reset all without a session clears every area")
    eq(FT.Current(), nil, "reset all does not start a session")
    eq(active(), 0, "reset all without a session leaves ticker stopped")
    loot.fishing = false
    _G.GetLootSourceInfo = nil
    FT.ToggleFarming()
    ok(shownText():find("Farming - Felwood", 1, true), "farming header uses zone")
    local paused = FT.Current()
    now = now + 10
    FT.TogglePause()
    now = now + 30
    fire("CHAT_MSG_MONEY", "You loot 1 Gold")
    eq(paused.gold, 0, "paused money ignored")
    FT.TogglePause()
    now = now + 5
    FT.Stop()
    eq(areas[paused.areaKey].seconds, 15, "paused time excluded")
    fire("UNIT_SPELLCAST_CHANNEL_START", "player", "cast", 7620)
    _G.ERR_FISH_ESCAPED = "Escaped locally"
    fire("UI_INFO_MESSAGE", 0, "Escaped locally")
    fire("UI_ERROR_MESSAGE", 0, "Escaped locally")
    eq(FT.Current().failed, 1, "one failure per cast")
    local fishSession = FT.Current()
    fire("UNIT_SPELLCAST_CHANNEL_START", "player", "cast", 7620)
    fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast", 7620)
    now = now + 3
    fire("UI_ERROR_MESSAGE", 0, "Escaped locally")
    eq(fishSession.failed, 1, "late failure ignored")
    fire("UNIT_SPELLCAST_CHANNEL_START", "player", "cast", 7620)
    FT.TogglePause()
    fire("UI_INFO_MESSAGE", 0, "Escaped locally")
    eq(fishSession.failed, 1, "paused failure ignored")
    FT.TogglePause()
    fire("UNIT_SPELLCAST_CHANNEL_START", "player", "cast", 7620)
    _G.ERR_FISH_NOT_HOOKED = "Localized failure"
    fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast", 7620)
    fire("UI_ERROR_MESSAGE", 0, "Localized failure")
    eq(fishSession.failed, 2, "localized post-stop failure counted")
    eq(areas[fishSession.areaKey].failed, 2, "area failures accumulated")
    FT.Stop()
end)

for _, k in ipairs(names) do _G[k] = saved[k] end
if not good then error(problem, 0) end
