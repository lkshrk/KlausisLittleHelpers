local _, ns = ...

-- IDs from wago.tools Forever 1.60.1.71037 (SpellName, ItemSparse, ItemXItemEffect, ItemEffect: 1800000 ms category cooldown).
local KEY = "SoulstoneReminder"
local BUFF_IDS = { 20707, 20762, 20763, 20764, 20765 }
local ITEM_IDS = { 5232, 16892, 16893, 16895, 16896 }
local ICON_ITEM = 16896
local ICON_FALLBACK = "Interface\\Icons\\Spell_Shadow_SoulGem"
local PURPLE = { 0.58, 0.51, 0.79 }
local ICON_SIZE = 40
local ROW_HEIGHT = 18
local BANNER_WIDTH = 280
local BOUNCE_OFFSET = 8
local BOUNCE_SECONDS = 0.5
local EVENTS = { "GROUP_ROSTER_UPDATE", "UNIT_AURA", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "READY_CHECK", "BAG_UPDATE_COOLDOWN", "UNIT_SPELLCAST_SUCCEEDED" }
local GCD = 1.5
local RETRY_DELAY = 1
local TEST_SECONDS = 30
local PREFIX = "KLH"
local HELLO = "SSR1:HELLO"
local HELLO_GAP = 10
local HELLO_REFRESH = 60
local HELLO_WAIT = 2
local INSTANCE_VALUES = { party = "Dungeons", raid = "Raids", both = "Dungeons and raids" }
local INSTANCE_ORDER = { "party", "raid", "both" }

local BUFF_SET = {}
for _, id in ipairs(BUFF_IDS) do BUFF_SET[id] = true end

local banner, bounceTime, tracker, throttle, eventFrame
local running, prefixRegistered = false, false
local dismissed = false
local queued, heldTrigger, retrying = false, nil, false
local triggerCount = 0
local testing, testToken = false, 0

local function SetTesting(value)
    if testing == value then return end
    testing = value
    if ns.NotifyOptionsChanged then ns.NotifyOptionsChanged() end
end
local peers
local commsReady, commsFailed = false, false
local lastHello, lastReply, helloWanted = nil, nil, false

local function Settings()
    return ns.GetSettings(KEY)
end

local function IsSecret(value)
    local isSecret = _G.issecretvalue
    return isSecret ~= nil and isSecret(value) == true
end

local function Plain(value, kind)
    if type(value) ~= kind or IsSecret(value) then return nil end
    return value
end

local function Now()
    return _G.GetTime and Plain(_G.GetTime(), "number") or 0
end

local function InCombat()
    if _G.InCombatLockdown and _G.InCombatLockdown() then return true end
    return _G.UnitAffectingCombat ~= nil and Plain(_G.UnitAffectingCombat("player"), "boolean") == true
end

local function InstanceType()
    if not _G.IsInInstance then return "none" end
    local inside, kind = _G.IsInInstance()
    if not inside then return "none" end
    return Plain(kind, "string") or "none"
end

local function InstanceAllowed(kind)
    if kind ~= "party" and kind ~= "raid" then return false end
    local allowed = Settings().instances
    return allowed == "both" or allowed == kind
end

local function GroupUnits()
    local units = {}
    if not (_G.IsInGroup and _G.IsInGroup()) then return units end
    local count = _G.GetNumGroupMembers and Plain(_G.GetNumGroupMembers(), "number") or 0
    if _G.IsInRaid and _G.IsInRaid() then
        for i = 1, count do units[#units + 1] = "raid" .. i end
    else
        units[1] = "player"
        for i = 1, count - 1 do units[#units + 1] = "party" .. i end
    end
    return units
end

local function GroupBusy()
    if InCombat() then return true end
    if _G.IsEncounterInProgress and Plain(_G.IsEncounterInProgress(), "boolean") == true then return true end
    if _G.UnitIsDeadOrGhost and Plain(_G.UnitIsDeadOrGhost("player"), "boolean") == true then return true end
    if not _G.UnitAffectingCombat then return false end
    for _, unit in ipairs(GroupUnits()) do
        if Plain(_G.UnitAffectingCombat(unit), "boolean") == true then return true end
    end
    return false
end

local function FullName(unit)
    if not _G.UnitName then return nil end
    local name, realm = _G.UnitName(unit)
    name, realm = Plain(name, "string"), Plain(realm, "string")
    if not name or name == "" then return nil end
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

local function ObserveCaster(aura)
    local source = Plain(aura.sourceUnit, "string")
    local guid = source and _G.UnitGUID and Plain(_G.UnitGUID(source), "string")
    local expires, duration = Plain(aura.expirationTime, "number"), Plain(aura.duration, "number")
    if guid and expires and duration and expires > 0 and duration > 0 then
        tracker:OnUsed(guid, expires - duration)
    end
end

local function HasStone(unit)
    local auras = _G.C_UnitAuras
    local find = auras and auras.GetUnitAuraBySpellID
    if not find then return false end
    for _, id in ipairs(BUFF_IDS) do
        local aura = find(unit, id)
        if aura ~= nil then
            if Plain(aura, "table") and tracker then ObserveCaster(aura) end
            return true
        end
    end
    return false
end

local function ItemCount(id)
    local fn = (_G.C_Item and _G.C_Item.GetItemCount) or _G.GetItemCount
    return fn and Plain(fn(id), "number") or 0
end

local function ItemCooldown(id)
    local fn = (_G.C_Container and _G.C_Container.GetItemCooldown) or (_G.C_Item and _G.C_Item.GetItemCooldown)
    if not fn then return 0, 0 end
    local start, duration = fn(id)
    return Plain(start, "number") or 0, Plain(duration, "number") or 0
end

local function OwnStoneReady()
    local now = Now()
    for _, id in ipairs(ITEM_IDS) do
        if ItemCount(id) > 0 then
            local start, duration = ItemCooldown(id)
            if start == 0 or duration <= GCD or start + duration <= now then return true end
        end
    end
    return false
end

--- Zone of each group member by name from the raid roster, whose slots can have gaps; empty where the client gives none.
local function RosterZones()
    local zones = {}
    local roster = _G.GetRaidRosterInfo
    if not roster then return zones end
    for i = 1, _G.MAX_RAID_MEMBERS or 40 do
        local name, _, _, _, _, _, zone = roster(i)
        name, zone = Plain(name, "string"), Plain(zone, "string")
        if name and zone and zone ~= "" then zones[name] = zone end
    end
    return zones
end

local function Snapshot()
    local playerGUID = _G.UnitGUID and Plain(_G.UnitGUID("player"), "string")
    local members = {}
    local zones = RosterZones()
    local myName = FullName("player")
    local myZone = myName and zones[myName]
    for _, unit in ipairs(GroupUnits()) do
        local exists = _G.UnitExists and _G.UnitExists(unit)
        local guid = exists and _G.UnitGUID and Plain(_G.UnitGUID(unit), "string")
        local name = guid and FullName(unit)
        local class = name and _G.UnitClass and Plain(select(2, _G.UnitClass(unit)), "string")
        if class then
            local role = _G.UnitGroupRolesAssigned and _G.UnitGroupRolesAssigned(unit)
            local member = {
                guid = guid, name = name, class = class, isHealer = role == "HEALER", hasStone = HasStone(unit),
                level = _G.UnitLevel and Plain(_G.UnitLevel(unit), "number"),
                connected = _G.UnitIsConnected and Plain(_G.UnitIsConnected(unit), "boolean"),
                visible = _G.UnitIsVisible and Plain(_G.UnitIsVisible(unit), "boolean"),
            }
            if guid == playerGUID and class == "WARLOCK" then member.ownReady = OwnStoneReady() end
            member.zone = zones[name]
            member.elsewhere = myZone ~= nil and member.zone ~= nil and member.zone ~= myZone
            members[#members + 1] = member
        end
    end
    return {
        instance = InstanceType(), allowed = Settings().instances, inCombat = InCombat(),
        now = Now(), player = playerGUID, members = members, tracker = tracker,
    }
end

local function SavePosition(frame)
    local point, _, relPoint, x, y = frame:GetPoint()
    if point then Settings().pos = { point = point, relPoint = relPoint, x = x, y = y } end
end

local function ApplyPosition()
    if not banner then return end
    local pos = Settings().pos
    banner:ClearAllPoints()
    if type(pos) == "table" and pos.point then
        banner:SetPoint(pos.point, _G.UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        banner:SetPoint("TOP", _G.UIParent, "TOP", 0, -140)
    end
end

local function ItemIcon()
    local get = _G.C_Item and _G.C_Item.GetItemIconByID
    return get and get(ICON_ITEM) or ICON_FALLBACK
end

local function PlaceIcon(frame, y)
    frame.icon:ClearAllPoints()
    frame.icon:SetPoint("TOP", frame, "TOP", 0, y)
end

local function StopBounce()
    if not banner then return end
    banner:SetScript("OnUpdate", nil)
    bounceTime = nil
    PlaceIcon(banner, 0)
end

-- Moves the icon (rows hang off it) instead of a looping Translation, which flickers at the turn.
local function OnBounce(frame, elapsed)
    bounceTime = (bounceTime or 0) + (elapsed or 0)
    local phase = (bounceTime % (2 * BOUNCE_SECONDS)) / (2 * BOUNCE_SECONDS)
    PlaceIcon(frame, BOUNCE_OFFSET * (1 - math.cos(2 * math.pi * phase)) / 2)
end

local function StartBounce(frame)
    if bounceTime then return end
    bounceTime = 0
    frame:SetScript("OnUpdate", OnBounce)
end

local function HideBanner()
    if not banner then return end
    StopBounce()
    banner:Hide()
end

local function Banner()
    if banner then return banner end
    local frame = _G.CreateFrame("Frame", nil, _G.UIParent)
    frame.isSoulstoneBanner = true
    frame:Hide()
    frame:SetSize(BANNER_WIDTH, ICON_SIZE)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if testing then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if testing then SavePosition(self) end
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button ~= "RightButton" then return end
        if testing then SetTesting(false) else dismissed = true end
        HideBanner()
    end)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetTexture(ItemIcon())
    frame.icon = icon
    PlaceIcon(frame, 0)
    frame.rows = {}
    banner = frame
    ApplyPosition()
    return frame
end

local function Row(frame, i)
    local row = frame.rows[i]
    if row then return row end
    local UI = ns.UI
    local size = i == 1 and 15 or 13
    if i == 1 then
        row = UI.Font(frame, size, PURPLE[1], PURPLE[2], PURPLE[3])
    else
        row = UI.Font(frame, size, 1, 1, 1)
    end
    row:SetFont(UI.FontPath and UI.FontPath() or "Fonts\\FRIZQT__.TTF", size, "OUTLINE")
    row:SetShadowOffset(1, -1)
    row:SetShadowColor(0, 0, 0, 1)
    row:SetJustifyH("CENTER")
    local anchor = i == 1 and frame.icon or frame.rows[i - 1]
    row:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
    frame.rows[i] = row
    return row
end

local function ShowBanner(rows)
    local frame = Banner()
    for i, text in ipairs(rows) do
        local row = Row(frame, i)
        row:SetText(text)
        row:Show()
    end
    for i = #rows + 1, #frame.rows do frame.rows[i]:Hide() end
    frame:SetHeight(ICON_SIZE + #rows * (ROW_HEIGHT + 2))
    frame:Show()
    StartBounce(frame)
end

local function Send(text, kind, target)
    local send = (_G.C_ChatInfo and _G.C_ChatInfo.SendChatMessage) or _G.SendChatMessage
    if send then send(text, kind, nil, target) end
end

local function GroupChannel()
    local instanceCategory = _G.LE_PARTY_CATEGORY_INSTANCE
    if instanceCategory and _G.IsInGroup and _G.IsInGroup(instanceCategory) then return "INSTANCE_CHAT" end
    return (_G.IsInRaid and _G.IsInRaid()) and "RAID" or "PARTY"
end

local function WantsComms()
    local s = Settings()
    return commsReady and (s.announce or s.whisper) and true or false
end

local function SendHello(now)
    local send = _G.C_ChatInfo and _G.C_ChatInfo.SendAddonMessage
    if not send then
        commsFailed = true
        return false
    end
    local result = send(PREFIX, HELLO, GroupChannel())
    commsFailed = result ~= nil and result ~= 0 and result ~= true
    if commsFailed then return false end
    lastHello = now
    return true
end

local function RosterIDs()
    local ids, byName = {}, {}
    local realm = _G.GetNormalizedRealmName and Plain(_G.GetNormalizedRealmName(), "string")
    for _, unit in ipairs(GroupUnits()) do
        local guid = _G.UnitGUID and Plain(_G.UnitGUID(unit), "string")
        local name = guid and FullName(unit)
        if name then
            ids[guid] = true
            byName[name] = guid
            if realm and not name:find("-", 1, true) then byName[name .. "-" .. realm] = guid end
        end
    end
    return ids, byName
end

local function Elected()
    if not commsReady or commsFailed then return true end
    local me = _G.UnitGUID and Plain(_G.UnitGUID("player"), "string")
    if not me then return true end
    local now = Now()
    peers:Prune(RosterIDs(), now)
    return peers:Elected(me, now)
end

local function Chat(result, trigger)
    if not (trigger and throttle:Allow(trigger, Now())) then return end
    local s = Settings()
    local speaker = (s.announce or s.whisper) and Elected()
    if s.announce and speaker then Send(result.announce, "INSTANCE_CHAT") end
    if s.whisper and speaker then
        for _, w in ipairs(result.whispers) do Send(w.text, "WHISPER", w.target) end
    end
    if s.sound and _G.PlaySound and _G.SOUNDKIT and _G.SOUNDKIT.RAID_WARNING then
        _G.PlaySound(_G.SOUNDKIT.RAID_WARNING)
    end
end

local Refresh

local function Retry()
    retrying = false
    if not running then return end
    Refresh()
end

local function ScheduleRetry(delay)
    if retrying or not (_G.C_Timer and _G.C_Timer.After) then return end
    retrying = true
    _G.C_Timer.After(delay, Retry)
end

Refresh = function()
    if not running then return end
    if testing then return end
    if not InstanceAllowed(InstanceType()) then
        heldTrigger = nil
        HideBanner()
        return
    end
    if GroupBusy() then
        HideBanner()
        if heldTrigger then ScheduleRetry(RETRY_DELAY) end
        return
    end
    local now = Now()
    if WantsComms() then
        if helloWanted and (not lastHello or now - lastHello >= HELLO_GAP) then
            helloWanted = false
            SendHello(now)
        end
        if heldTrigger and (not lastHello or now - lastHello > HELLO_REFRESH) then SendHello(now) end
        if heldTrigger and not commsFailed and lastHello and now - lastHello < HELLO_WAIT then
            ScheduleRetry(HELLO_WAIT - (now - lastHello))
            return
        end
    end
    local trigger = heldTrigger
    heldTrigger = nil
    if trigger then dismissed = false end
    local result = ns.Soulstone.Evaluate(Snapshot())
    if not result then
        HideBanner()
        return
    end
    if Settings().banner and not dismissed then ShowBanner(result.rows) else HideBanner() end
    Chat(result, trigger)
end

local function Flush()
    queued = false
    Refresh()
end

local function QueueRefresh(trigger)
    if trigger then heldTrigger = trigger end
    if queued then return end
    queued = true
    if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0, Flush) else Flush() end
end

local function ShowTest()
    if not running then return end
    testToken = testToken + 1
    local token = testToken
    SetTesting(true)
    ShowBanner({ ns.Soulstone.HEADLINE, "Ready: Gul'dan", "Ready: Kanrethad" })
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(TEST_SECONDS, function()
            if not (testing and token == testToken) then return end
            SetTesting(false)
            HideBanner()
            QueueRefresh()
        end)
    end
end

local function EndTest()
    SetTesting(false)
    HideBanner()
end

local function ToggleTest()
    if testing then
        EndTest()
        QueueRefresh()
    else
        ShowTest()
    end
end

local function MemberLine(m, snap)
    local level = m.level and (" " .. m.level) or ""
    local state
    if m.class == "WARLOCK" then
        local ready = m.guid == snap.player and m.ownReady or (m.guid ~= snap.player and tracker:Ready(m.guid, snap.now))
        state = ready and "soulstone ready" or "soulstone on cooldown or not in bags"
    else
        state = (m.visible == false and "too far away" or "in range") .. ", " .. (m.hasStone and "has a soulstone" or "no soulstone")
    end
    if m.elsewhere then state = "outside the instance (" .. m.zone .. "), counts as no soulstone" end
    if m.connected == false then state = "offline" end
    return ("  %s (%s%s): %s"):format(m.name, m.class:lower(), level, state)
end

local function Explain()
    if not running then
        ns.Print("Soulstone Reminder is off.")
        return
    end
    local snap = Snapshot()
    local result, reason = ns.Soulstone.Evaluate(snap)
    if result then
        ns.Print(("Soulstone Reminder would show now (%s): %s"):format(snap.instance, result.announce))
    else
        ns.Print(("Soulstone Reminder shows nothing (%s): %s."):format(snap.instance, reason or "unknown"))
    end
    for _, m in ipairs(snap.members) do
        if ns.Soulstone.REZ_LEVEL[m.class] or m.class == "WARLOCK" then ns.Print(MemberLine(m, snap)) end
    end
end

local commandRegistered

local function NextTrigger(kind)
    triggerCount = triggerCount + 1
    return kind .. triggerCount
end

local function IsGroupUnit(unit)
    return unit == "player" or (type(unit) == "string" and (unit:find("^party%d+$") or unit:find("^raid%d+$")) ~= nil)
end

local function OnSpellcast(unit, spellId)
    spellId = Plain(spellId, "number")
    if not (spellId and BUFF_SET[spellId] and IsGroupUnit(unit)) then return end
    local class = _G.UnitClass and Plain(select(2, _G.UnitClass(unit)), "string")
    local guid = _G.UnitGUID and Plain(_G.UnitGUID(unit), "string")
    if class ~= "WARLOCK" or not guid then return end
    tracker:OnUsed(guid, Now())
    if not InCombat() then QueueRefresh() end
end

local function OnAddonMessage(prefix, text, sender)
    if Plain(prefix, "string") ~= PREFIX or Plain(text, "string") ~= HELLO then return end
    sender = Plain(sender, "string")
    local _, byName = RosterIDs()
    local id = sender and byName[sender]
    local me = _G.UnitGUID and Plain(_G.UnitGUID("player"), "string")
    if not id or id == me then return end
    local now = Now()
    peers:Seen(id, now)
    if not WantsComms() or InCombat() or not InstanceAllowed(InstanceType()) then return end
    if lastReply and now - lastReply < HELLO_GAP then return end
    lastReply = now
    SendHello(now)
end

local function OnEvent(_, event, unit, arg2, spellId, sender)
    if not running then return end
    if event == "CHAT_MSG_ADDON" then
        OnAddonMessage(unit, arg2, sender)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnSpellcast(unit, spellId)
    elseif event == "PLAYER_REGEN_DISABLED" then
        EndTest()
    elseif event == "PLAYER_REGEN_ENABLED" then
        QueueRefresh(NextTrigger("combat"))
    elseif event == "READY_CHECK" then
        QueueRefresh(NextTrigger("ready"))
    elseif event == "UNIT_AURA" then
        if not IsGroupUnit(unit) then return end
        if InCombat() then HasStone(unit) else QueueRefresh() end
    else
        if event ~= "BAG_UPDATE_COOLDOWN" then helloWanted = true end
        QueueRefresh()
    end
end

local function Toggle(key, order, name, desc)
    return {
        type = "toggle", order = order, width = "normal", name = name, desc = desc,
        get = function() return Settings()[key] end,
        set = function(_, v)
            Settings()[key] = v
            if running then QueueRefresh() end
        end,
    }
end

local function NotRunning()
    return not ns.IsRunning(KEY)
end

ns.RegisterFeature({
    key = KEY,
    title = "Soulstone Reminder",
    tab = "qol",
    section = "Dungeons & Raids",
    description = "Reminder for Soulstone recovery in instances and raids.",
    help = "Reminder for Soulstone recovery in instances and raids. /klh soulstone says why it shows or doesn't show right now.",
    commands = { "soulstone" },
    defaults = { instances = "both", banner = true, announce = false, whisper = false, sound = false },
    enable = function()
        if not _G.CreateFrame then return end
        tracker = tracker or ns.Soulstone.NewTracker()
        throttle = throttle or ns.Soulstone.NewThrottle()
        peers = peers or ns.Soulstone.NewPeers()
        if not eventFrame then
            eventFrame = _G.CreateFrame("Frame")
            eventFrame:SetScript("OnEvent", OnEvent)
        end
        local chat = _G.C_ChatInfo
        if not prefixRegistered and chat and chat.RegisterAddonMessagePrefix and chat.SendAddonMessage then
            prefixRegistered = true
            local result = chat.RegisterAddonMessagePrefix(PREFIX)
            commsReady = result == nil or result == 0 or result == 1 or result == true
        end
        for _, event in ipairs(EVENTS) do eventFrame:RegisterEvent(event) end
        if commsReady then eventFrame:RegisterEvent("CHAT_MSG_ADDON") end
        running = true
        helloWanted = true
        if not commandRegistered and ns.RegisterSlashCommand then
            commandRegistered = true
            ns.RegisterSlashCommand("soulstone", Explain)
        end
        QueueRefresh()
    end,
    disable = function()
        running = false
        if eventFrame then
            for _, event in ipairs(EVENTS) do eventFrame:UnregisterEvent(event) end
            eventFrame:UnregisterEvent("CHAT_MSG_ADDON")
        end
        SetTesting(false)
        testToken = testToken + 1
        HideBanner()
        heldTrigger, queued, retrying = nil, false, false
        lastHello, lastReply, helloWanted = nil, nil, false
        commsFailed = false
    end,
    options = function()
        return {
            instances = {
                type = "select", order = 1, name = "Active in", desc = "Instance types the reminder runs in.",
                values = INSTANCE_VALUES, sorting = INSTANCE_ORDER,
                get = function() return Settings().instances end,
                set = function(_, v)
                    Settings().instances = v
                    if running then QueueRefresh() end
                end,
            },
            br1 = { type = "description", order = 1.5, name = "", width = "full" },
            banner = Toggle("banner", 2, "Show banner", "Show the reminder banner."),
            announce = Toggle("announce", 3, "Announce to group", "Post one line in instance chat after combat and on a ready check."),
            whisper = Toggle("whisper", 4, "Whisper warlock", "Whisper each warlock whose stone is ready; never yourself."),
            br2 = { type = "description", order = 4.5, name = "", width = "full" },
            sound = {
                type = "toggle", order = 5, name = "Play a sound", desc = "Play the raid warning sound with the reminder.",
                get = function() return Settings().sound end,
                set = function(_, v) Settings().sound = v end,
            },
            br3 = { type = "description", order = 5.5, name = "", width = "full" },
            test = {
                type = "execute", order = 6,
                name = function() return testing and "Hide test banner" or "Show test banner" end,
                desc = "Show the banner with sample text; drag it to move it. Outside the test it stays in place; right-click hides it.",
                disabled = NotRunning,
                func = ToggleTest,
            },
            resetPosition = {
                type = "execute", order = 7, name = "Reset position", desc = "Move the banner back to the top centre.",
                func = function()
                    Settings().pos = nil
                    ApplyPosition()
                end,
            },
        }
    end,
    onReset = function()
        ApplyPosition()
        if running then QueueRefresh() end
    end,
})
