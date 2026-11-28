local _, ns = ...

local KEY = "FarmTracker"
local DEFAULT_POINT = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 300, y = -250 }
local PAD, FONT_SIZE, LINE_HEIGHT, MIN_WIDTH, STOP_SIZE, LABEL_GAP, DIVIDER_GAP, NAME_GAP = 6, 12, 14, 280, 14, 6, 4, 8
local LOOT_SLOT_ITEM = 1
local FISHING_SPELLS = { [7620] = true, [131474] = true, [131476] = true, [131490] = true }
local ANON, ITEM, OLD = {}, {}, {}

local L = ns.FarmLogic
local FT = {}
ns.FarmTracker = FT

local labelStrings, valueStrings, nameStrings, cellStrings = {}, {}, {}, {}
local current, loot, ticker, events, watcher, divider, bookFishingID, pauseLabel, header

local function Settings()
    return ns.GetSettings(KEY)
end

local function Now()
    return _G.GetTime()
end

local function Areas()
    local global = ns.GetDB().global
    if type(global.FarmTracker) ~= "table" then global.FarmTracker = {} end
    if type(global.FarmTracker.areas) ~= "table" then global.FarmTracker.areas = {} end
    return global.FarmTracker.areas
end

local function Area(key)
    local areas = Areas()
    if type(areas[key]) ~= "table" then areas[key] = { seconds = 0, attempts = 0, gold = 0, items = {} } end
    return areas[key]
end

local function AreaKey(kind)
    local zone = _G.GetRealZoneText() or ""
    if kind == "fish" then return "fish:" .. zone .. ":" .. (_G.GetSubZoneText() or "") end
    return "farm:" .. zone
end

local function FishingProfession()
    if not (_G.GetProfessions and _G.GetProfessionInfo) then return end
    local index = select(4, _G.GetProfessions())
    if not index then return end
    return _G.GetProfessionInfo(index)
end

local function BookFishingID()
    if bookFishingID then return bookFishingID end
    local book = _G.C_SpellBook
    local bank = _G.Enum and _G.Enum.SpellBookSpellBank and _G.Enum.SpellBookSpellBank.Player
    if type(book) ~= "table" or type(book.GetSpellBookItemName) ~= "function"
        or type(book.GetSpellBookItemType) ~= "function" or bank == nil then return end
    local name, _, _, _, numSpells, offset = FishingProfession()
    if type(name) ~= "string" or type(numSpells) ~= "number" or type(offset) ~= "number" then return end
    for i = 1, numSpells do
        if book.GetSpellBookItemName(offset + i, bank) == name then
            local _, _, spellID = book.GetSpellBookItemType(offset + i, bank)
            if type(spellID) == "number" then
                bookFishingID = spellID
                return spellID
            end
        end
    end
end

local function IsFishingSpell(spellID)
    return FISHING_SPELLS[spellID] == true or spellID == BookFishingID()
end

function FT.Current()
    return current
end

function FT.Watcher()
    return watcher
end

local function MergeSeconds(session, now)
    if session.paused then return end
    local area = Area(session.areaKey)
    area.seconds = (area.seconds or 0) + math.max(0, now - session.mergedAt)
    session.mergedAt = now
end

local function Place(frame)
    local pos = Settings().point
    if type(pos) ~= "table" or not pos.point then pos = DEFAULT_POINT end
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, _G.UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
end

local function Watcher()
    if watcher then return watcher end
    local frame = _G.CreateFrame("Frame", nil, _G.UIParent)
    frame:Hide()
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetLeft(), self:GetTop()
        if x and y then Settings().point = { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = x, y = y } end
        Place(self)
    end)
    ns.UI.Solid(frame, "BACKGROUND", 0, 0, 0, 0.35):SetAllPoints()

    local stop = _G.CreateFrame("Button", nil, frame)
    stop:SetSize(STOP_SIZE, STOP_SIZE)
    stop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    local label = ns.UI.Font(stop, FONT_SIZE, 1, 0.82, 0)
    label:SetPoint("CENTER")
    label:SetText("x")
    stop:SetScript("OnClick", function() FT.Stop() end)
    stop:SetScript("OnEnter", function(self) ns.UI.ShowTooltip(self, "Stop this session") end)
    stop:SetScript("OnLeave", function() ns.UI.HideTooltip() end)

    local pause = _G.CreateFrame("Button", nil, frame)
    pause:SetSize(STOP_SIZE, STOP_SIZE)
    pause:SetPoint("TOPRIGHT", stop, "TOPLEFT", -2, 0)
    pauseLabel = ns.UI.Font(pause, FONT_SIZE, 1, 0.82, 0)
    pauseLabel:SetPoint("CENTER")
    pauseLabel:SetText("||")
    pause:SetScript("OnClick", function()
        FT.TogglePause()
    end)
    pause:SetScript("OnEnter", function(self) ns.UI.ShowTooltip(self, "Pause or resume this session") end)
    pause:SetScript("OnLeave", function() ns.UI.HideTooltip() end)

    header = ns.UI.Font(frame, FONT_SIZE, 1, 0.82, 0)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)

    divider = ns.UI.Solid(frame, "ARTWORK", 1, 0.82, 0, 0.4)
    divider:SetHeight(1)
    divider:Hide()

    Place(frame)
    watcher = frame
    return frame
end

local function View(session, now)
    if session.paused then now = session.pausedAt end
    local area = Area(session.areaKey)
    local rows = L.Rows(session, area)
    local view = { kind = session.kind, rows = rows, sSeconds = now - session.started,
        aSeconds = (area.seconds or 0) + now - session.mergedAt, sGold = session.gold or 0, aGold = area.gold or 0 }
    if session.kind == "fish" then
        local sTotal, aTotal = 0, 0
        for _, row in ipairs(rows) do sTotal, aTotal = sTotal + row.sCount, aTotal + row.aCount end
        view.sTotal, view.aTotal = sTotal, aTotal
        view.sFailed, view.aFailed = session.failed or 0, area.failed or 0
        local _, _, rank, _, _, _, _, modifier = FishingProfession()
        if rank then view.skill = { rank = rank, modifier = modifier or 0 } end
    else
        view.sTotal, view.aTotal = session.attempts or 0, area.attempts or 0
    end
    return view
end

local function Text(pool, i, frame)
    local fs = pool[i]
    if not fs then
        fs = ns.UI.Font(frame, FONT_SIZE)
        fs:SetJustifyH("LEFT")
        pool[i] = fs
    end
    fs:Show()
    return fs
end

local function Anchor(fs, frame, x, y)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
end

local function HideFrom(pool, first)
    for i = first, #pool do pool[i]:Hide() end
end

local function Redraw()
    local session = current
    if not session then
        if watcher then watcher:Hide() end
        return
    end
    local frame = Watcher()
    pauseLabel:SetText(session.paused and ">" or "||")
    local location = session.kind == "fish" and _G.GetSubZoneText() or _G.GetRealZoneText()
    if not location or location == "" then location = _G.GetRealZoneText() or "" end
    local title = session.kind == "fish" and "Fishing" or "Farming"
    header:SetText(title .. (location ~= "" and " - " .. location or "") .. (session.paused and " (Paused)" or ""))
    local summary, rows = {}, {}
    for _, line in ipairs(L.Lines(View(session, Now()))) do
        if line.label then summary[#summary + 1] = line else rows[#rows + 1] = line end
    end
    local labelWidth = 0
    for i, line in ipairs(summary) do
        local fs = Text(labelStrings, i, frame)
        fs:SetText(line.label)
        labelWidth = math.max(labelWidth, fs:GetStringWidth() or 0)
    end
    local valueX = PAD + labelWidth + LABEL_GAP
    local width = math.max(MIN_WIDTH, PAD + (header:GetStringWidth() or 0) + STOP_SIZE * 2 + 6)
    local y = PAD + LINE_HEIGHT
    for i, line in ipairs(summary) do
        Anchor(labelStrings[i], frame, PAD, y)
        local fs = Text(valueStrings, i, frame)
        fs:SetText(line.value)
        fs:SetJustifyH("RIGHT")
        fs:ClearAllPoints()
        fs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(STOP_SIZE * 2 + 6), -y)
        width = math.max(width, valueX + (fs:GetStringWidth() or 0) + STOP_SIZE * 2 + 6)
        y = y + LINE_HEIGHT
    end
    if #rows > 0 then
        divider:ClearAllPoints()
        divider:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(y + DIVIDER_GAP))
        divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(y + DIVIDER_GAP))
        divider:Show()
        y = y + DIVIDER_GAP * 2 + 1
    else
        divider:Hide()
    end
    local nameWidth, columns = 0, {}
    for i, row in ipairs(rows) do
        local fs = Text(nameStrings, i, frame)
        fs:SetText(row.name)
        nameWidth = math.max(nameWidth, fs:GetStringWidth() or 0)
        for j, cell in ipairs(row.cells) do
            cellStrings[j] = cellStrings[j] or {}
            local c = Text(cellStrings[j], i, frame)
            c:SetJustifyH("RIGHT")
            c:SetText(cell)
            columns[j] = math.max(columns[j] or 0, c:GetStringWidth() or 0)
        end
    end
    local edges, x = {}, PAD + nameWidth + NAME_GAP
    for j, w in ipairs(columns) do
        x = x + w
        edges[j] = x
    end
    if #rows > 0 then width = math.max(width, x + PAD) end
    for i, row in ipairs(rows) do
        Anchor(nameStrings[i], frame, PAD, y)
        for j = 1, #row.cells do
            local c = cellStrings[j][i]
            c:ClearAllPoints()
            c:SetPoint("TOPRIGHT", frame, "TOPRIGHT", edges[j] - x - PAD, -y)
        end
        y = y + LINE_HEIGHT
    end
    HideFrom(labelStrings, #summary + 1)
    HideFrom(valueStrings, #summary + 1)
    HideFrom(nameStrings, #rows + 1)
    for j, pool in ipairs(cellStrings) do HideFrom(pool, j <= #columns and #rows + 1 or 1) end
    frame:SetSize(width, y + PAD)
    frame:Show()
end

local Tick

local function Refresh()
    if ns.NotifyOptionsChanged then ns.NotifyOptionsChanged() end
    if current then
        if not ticker then ticker = _G.C_Timer.NewTicker(1, function() Tick() end) end
    elseif ticker then
        ticker:Cancel()
        ticker = nil
    end
    Redraw()
end

local function End()
    if not current then return end
    MergeSeconds(current, Now())
    current = nil
end

local function Start(kind, key)
    End()
    local now = Now()
    current = L.NewSession(kind, key or AreaKey(kind), now)
    current.mergedAt = now
    Area(current.areaKey)
    Refresh()
    return current
end

function FT.Stop()
    End()
    Refresh()
end

function FT.TogglePause()
    if not current then return end
    local now = Now()
    if current.paused then
        current.started = current.started + now - current.pausedAt
        current.mergedAt = now
        current.lastCast = now
        current.paused, current.pausedAt = nil, nil
    else
        MergeSeconds(current, now)
        current.paused, current.pausedAt = true, now
    end
    current.castPending, current.castStopped = nil, nil
    Redraw()
end

function FT.ToggleFarming()
    if not current then
        Start("farm")
    elseif current.kind == "farm" then
        FT.Stop()
    else
        ns.Print("Farm Tracker: a fishing session is running; stop it first (x on the watcher).")
    end
end

function FT.ResetArea()
    if not current then return end
    local kind, key = current.kind, current.areaKey
    Areas()[key] = nil
    if loot and loot.areaKey == key then loot.data = nil end
    current = nil
    Start(kind, key)
end

function FT.ResetAllAreas()
    local kind, key
    if current then kind, key = current.kind, current.areaKey end
    local areas = Areas()
    for areaKey in pairs(areas) do areas[areaKey] = nil end
    if loot then loot.data = nil end
    if kind then
        current = nil
        Start(kind, key)
    else
        Refresh()
    end
end
local function FishingHere()
    if current and current.kind == "fish" and current.areaKey == AreaKey("fish") then return current end
end

Tick = function()
    if current and not current.paused and current.kind == "fish"
        and L.FishingEnds(current, Now(), AreaKey("fish"), Settings().fishIdleMinutes or 10) then
        FT.Stop()
    else
        Redraw()
    end
end

local function OnChannel(unit, spellID)
    if unit ~= "player" or not spellID then return end
    if _G.issecretvalue and _G.issecretvalue(spellID) then return end
    if (current and (current.kind == "farm" or current.paused)) or not IsFishingSpell(spellID) then return end
    local fish = FishingHere()
    if fish then fish.lastCast = Now() else fish = Start("fish") end
    fish.castPending, fish.castStopped = true, nil
end

local function OnZone()
    if not current or current.areaKey == AreaKey(current.kind) then return end
    if current.paused then FT.Stop(); return end
    if current.kind == "farm" then Start("farm") else FT.Stop() end
end

local function SourceKey(guid, seen)
    if guid == nil or (_G.issecretvalue and _G.issecretvalue(guid)) or type(guid) ~= "string" then return ANON end
    if guid:sub(1, 5) == "Item-" then return ITEM end
    if seen and seen[guid] then return OLD end
    return guid
end

local function SlotSources(sourceInfo, i, seen)
    local keys = {}
    if sourceInfo then
        local info = { sourceInfo(i) }
        for j = 1, #info, 2 do keys[#keys + 1] = SourceKey(info[j], seen) end
    end
    if #keys == 0 then keys[1] = ANON end
    return keys
end

local function ReadLoot(seen)
    local count = _G.GetNumLootItems() or 0
    if count == 0 then return end
    local sourceInfo = type(_G.GetLootSourceInfo) == "function" and _G.GetLootSourceInfo or nil
    local byID, order, counted, guids, sources, other = {}, {}, {}, {}, 0, false
    for i = 1, count do
        local fresh = {}
        for _, key in ipairs(SlotSources(sourceInfo, i, seen)) do
            if key ~= ITEM then other = true end
            if key ~= ITEM and key ~= OLD then
                fresh[#fresh + 1] = key
                if not counted[key] then
                    counted[key] = true
                    sources = sources + 1
                    if key ~= ANON then guids[#guids + 1] = key end
                end
            end
        end
        local link = _G.GetLootSlotLink(i)
        local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
        local slotType = _G.GetLootSlotType and _G.GetLootSlotType(i)
        if #fresh > 0 and id and (slotType == nil or slotType == LOOT_SLOT_ITEM) then
            local _, name, quantity, _, quality = _G.GetLootSlotInfo(i)
            local slot = byID[id]
            if not slot then
                slot = { itemID = id, quantity = 0, from = {}, sources = 0 }
                byID[id] = slot
                order[#order + 1] = slot
            end
            slot.name, slot.quality = name or slot.name, quality or slot.quality
            slot.quantity = slot.quantity + (quantity or 1)
            for _, key in ipairs(fresh) do
                if not slot.from[key] then
                    slot.from[key] = true
                    slot.sources = slot.sources + 1
                end
            end
        end
    end
    local slots = {}
    for _, slot in ipairs(order) do
        slots[#slots + 1] = { itemID = slot.itemID, name = slot.name, quality = slot.quality,
            quantity = slot.quantity, sources = slot.sources }
    end
    return { sources = sources, slots = slots, guids = guids, fromItem = not other }
end

local function OnMoney(text)
    if not (current and not current.paused and current.kind == "farm") or (loot and (loot.fromItem or loot.fishing)) then return end
    if _G.issecretvalue and _G.issecretvalue(text) then return end
    local copper = L.LootMoney(text, _G)
    if not copper or copper <= 0 then return end
    L.AddGold(current, Area(current.areaKey), copper)
    Redraw()
end

local function OnLootReady()
    if loot or (current and current.paused) then return end
    local fishing = _G.IsFishingLoot and _G.IsFishingLoot()
    if not (current or fishing) then return end
    if fishing and current and current.kind == "farm" then
        loot = { fishing = true }
        return
    end
    if not fishing and current.kind ~= "farm" then return end
    local farm = not fishing and current or nil
    local data = ReadLoot(farm and farm.seen)
    if not data then return end
    loot = {}
    if data.fromItem then
        loot.fromItem = true
        return
    end
    local session = farm or FishingHere() or Start("fish")
    if fishing then session.lastCast = Now(); session.castPending = nil end
    for _, guid in ipairs(farm and data.guids or {}) do farm.seen[guid] = true end
    L.Record(session, Area(session.areaKey), data)
    loot.session, loot.areaKey, loot.data = session, session.areaKey, data
    loot.farm = farm
    Redraw()
end

local function OnLootOpened(isFromItem)
    if not isFromItem or (loot and loot.fromItem) then return end
    local data = loot and loot.data
    if data then
        L.Unrecord(loot.session, Area(loot.areaKey), data)
        if loot.farm then
            for _, guid in ipairs(data.guids) do loot.farm.seen[guid] = nil end
        end
    end
    loot = { fromItem = true }
    if data then Redraw() end
end

local function OnLootClosed()
    loot = nil
    Redraw()
end

local ZONE_EVENTS = { ZONE_CHANGED = true, ZONE_CHANGED_INDOORS = true, ZONE_CHANGED_NEW_AREA = true }

local function OnEvent(_, event, ...)
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        local unit, _, spellID = ...
        OnChannel(unit, spellID)
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local unit = ...
        if unit == "player" and current and current.kind == "fish" and current.castPending then
            current.castStopped = Now()
        end
    elseif event == "UI_INFO_MESSAGE" or event == "UI_ERROR_MESSAGE" then
        local _, message = ...
        if current and current.kind == "fish" and not current.paused and current.castPending
            and not (_G.issecretvalue and _G.issecretvalue(message)) and type(message) == "string"
            and (not current.castStopped or Now() - current.castStopped <= 2)
            and ((not (_G.issecretvalue and _G.issecretvalue(_G.ERR_FISH_ESCAPED))
                and type(_G.ERR_FISH_ESCAPED) == "string" and message == _G.ERR_FISH_ESCAPED)
                or (not (_G.issecretvalue and _G.issecretvalue(_G.ERR_FISH_NOT_HOOKED))
                    and type(_G.ERR_FISH_NOT_HOOKED) == "string" and message == _G.ERR_FISH_NOT_HOOKED)) then
            current.failed = (current.failed or 0) + 1
            local area = Area(current.areaKey)
            area.failed = (area.failed or 0) + 1
            current.castPending = nil
            Redraw()
        end
    elseif event == "LOOT_READY" then
        OnLootReady()
    elseif event == "LOOT_OPENED" then
        local _, isFromItem = ...
        OnLootOpened(isFromItem)
    elseif event == "CHAT_MSG_MONEY" then
        OnMoney((...))
    elseif event == "LOOT_CLOSED" then
        OnLootClosed()
    elseif event == "SPELLS_CHANGED" or event == "SKILL_LINES_CHANGED" then
        bookFishingID = nil
    elseif event == "PLAYER_LOGOUT" then
        if current then MergeSeconds(current, Now()) end
    elseif ZONE_EVENTS[event] then
        OnZone()
    end
end

ns.RegisterFeature({
    key = KEY,
    title = "Farm Tracker",
    tab = "helpers",
    description = "A small text watcher for fishing and farming: clocks, totals and what each spot yields.",
    help = "Casting Fishing starts a fishing session; it ends on a subzone change or when idle. /klh farm or the minimap"
        .. " button starts and stops farming. One session runs at a time; the x on the watcher stops it."
        .. " Area history is shared by all characters.",
    commands = { "farm" },
    alwaysOn = true,
    defaults = { fishIdleMinutes = 10 },
    launcher = { text = "Toggle farming", onClick = function() FT.ToggleFarming() end },
    enable = function()
        if events or not _G.CreateFrame then return end
        ns.RegisterSlashCommand("farm", function() FT.ToggleFarming() end)
        events = _G.CreateFrame("Frame")
        events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
        for _, event in ipairs({ "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED", "CHAT_MSG_MONEY", "PLAYER_LOGOUT",
            "SPELLS_CHANGED", "SKILL_LINES_CHANGED", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE" }) do
            events:RegisterEvent(event)
        end
        for event in pairs(ZONE_EVENTS) do events:RegisterEvent(event) end
        events:SetScript("OnEvent", OnEvent)
    end,
    options = function()
        return {
            fishIdleMinutes = {
                type = "range", order = 1, min = 1, max = 60, step = 1, name = "Fishing idle minutes",
                desc = "End a fishing session after this many minutes without a cast.",
                get = function() return Settings().fishIdleMinutes end,
                set = function(_, v) Settings().fishIdleMinutes = v end,
            },
            resetArea = {
                type = "execute", order = 2, name = "Reset this area",
                desc = "Clear the history of the area the running session records into, and restart the session.",
                confirm = true, confirmText = "Clear this area's farming history?",
                disabled = function() return FT.Current() == nil end,
                func = function() FT.ResetArea() end,
            },
            resetAllAreas = {
                type = "execute", order = 3, name = "Reset all areas",
                desc = "Clear all characters' area history and restart the running session, if any.",
                confirm = true, confirmText = "Clear farming history for all areas and characters?",
                func = function() FT.ResetAllAreas() end,
            },
        }
    end,
    onReset = function()
        if watcher then Place(watcher) end
    end,
})
