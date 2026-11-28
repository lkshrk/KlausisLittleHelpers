if EUI_CLIENT_BLOCKED then return end

local _, ns = ...
local KEY = "TustUIXPBar"
local ceil, floor, max = math.ceil, math.floor, math.max
local format = string.format

local RATE_VALUES = { session = "Session", alltime = "All-Time", both = "Both" }
local RATE_ORDER = { "session", "alltime", "both" }
local RATE_TOLERANCE = 0.15
local COLOR_EVEN, COLOR_BELOW, COLOR_ABOVE = "ffffffff", "ffff5a5a", "ff5aff7a"
local ATTACH_TRIES, ATTACH_INTERVAL = 10, 3

local tracking = false
local hooked = {}
local original = {}
local extraLines = {}
local rewriting = false
local liveStart, lastXP, lastMaxXP
local matchers

local function L(text)
    local eui = _G.EllesmereUI
    return eui and type(eui.L) == "function" and eui.L(text) or text
end

local function Lf(template, ...)
    local eui = _G.EllesmereUI
    if eui and type(eui.Lf) == "function" then return eui.Lf(template, ...) end
    return format(template, ...)
end

local function Settings()
    return ns.GetSettings(KEY)
end

local function Stats()
    local s = ns.CharData("tustXPBar")
    if type(s.xp) ~= "number" then s.xp = 0 end
    if type(s.time) ~= "number" then s.time = 0 end
    return s
end

local function TustSession()
    local db = _G.TustEUICharacterDB
    local state = type(db) == "table" and db.enhancedXPBar
    if type(state) ~= "table" or type(state.startTime) ~= "number" or state.startTime <= 0 then return nil end
    return state
end

local function MaxLevel()
    if GameRulesUtil and GameRulesUtil.GetEffectiveMaxLevelForPlayer then
        return GameRulesUtil.GetEffectiveMaxLevelForPlayer()
    end
    return GetMaxLevelForPlayerExpansion()
end

local function Bank(level)
    local now = GetTime()
    local s = Stats()
    if liveStart then s.time = s.time + max(0, now - liveStart) end
    local leveling = (level or UnitLevel("player")) < MaxLevel() and (UnitXPMax("player") or 0) > 0
    liveStart = leveling and now or nil
end

local function SavedTime()
    local t = Stats().time
    if liveStart then t = t + max(0, GetTime() - liveStart) end
    return t
end

local function SavedRate()
    local xp, seconds = Stats().xp, SavedTime()
    if xp <= 0 or seconds <= 5 then return 0 end
    return ceil(xp / (seconds / 3600))
end

local function ResetStats()
    local s = Stats()
    s.xp, s.time = 0, 0
    liveStart = nil
    if tracking then Bank() end
end

-- Same rules as TustUI's own XP numbers, so the added values match the bar.
local function ShortNumber(n)
    n = tonumber(n) or 0
    local eui = _G.EllesmereUI
    local abbreviate = eui and (eui.AbbreviateNumberFixed or eui.AbbreviateNumber)
    if ns.IS_FOREVER and type(abbreviate) == "function" then return abbreviate(n) end
    if n >= 1000000 then return format("%.1fM", n / 1000000) end
    if n >= 1000 then return format("%.1fK", n / 1000) end
    return tostring(floor(n))
end

local function FormatTime(seconds)
    if not seconds or seconds <= 0 then return "--" end
    if seconds < 60 then return L("< 1m") end
    local days = floor(seconds / 86400)
    local hours = floor(seconds % 86400 / 3600)
    local minutes = floor(seconds % 3600 / 60)
    if days > 0 then return Lf("%dd %dh %dm", days, hours, minutes) end
    if hours > 0 then return Lf("%dh %dm", hours, minutes) end
    return Lf("%dm", minutes)
end

local function SessionRate()
    local state = TustSession()
    if not state then return 0 end
    local xp, seconds = tonumber(state.gainedXP) or 0, GetTime() - state.startTime
    if xp <= 0 or seconds <= 5 then return 0 end
    return ceil(xp / (seconds / 3600))
end

local function DecorateSession(text)
    if not Settings().showSessionXP then return text end
    local state = TustSession()
    return format("%s (%s XP)", text, ShortNumber(state and state.gainedXP))
end

local function PrefixOf(template)
    local s = L(template)
    local i = s:find("%", 1, true)
    s = i and s:sub(1, i - 1) or s
    return s ~= "" and s or nil
end

local function RateText(seconds, hourly, color)
    local rate = ShortNumber(hourly)
    if color then rate = format("|c%s%s|r", color, rate) end
    return Lf("Leveling in: %s (%s XP/Hour)", FormatTime(seconds), rate)
end

local function DecorateRate(text)
    local source = Settings().rateSource
    if source ~= "alltime" and source ~= "both" then return text end
    local saved = SavedRate()
    if saved <= 0 then return text end
    local remaining = max(0, (UnitXPMax("player") or 0) - (UnitXP("player") or 0))
    local savedLine = RateText(ceil(remaining / saved * 3600), saved)
    local session = source == "both" and SessionRate() or 0
    if source == "alltime" then return savedLine end
    local prefix = PrefixOf("Leveling in: %s (%s XP/Hour)") or ""
    if savedLine:sub(1, #prefix) == prefix then savedLine = savedLine:sub(#prefix + 1) end
    savedLine = format("%s: %s", L("All-Time"), savedLine)
    if session <= 0 then return text, savedLine end
    local ratio = session / saved
    local color = ratio < 1 - RATE_TOLERANCE and COLOR_BELOW
        or ratio > 1 + RATE_TOLERANCE and COLOR_ABOVE or COLOR_EVEN
    return RateText(ceil(remaining / session * 3600), session, color), savedLine
end

local function ExtraLine(fs)
    local line = extraLines[fs]
    if not line then
        line = fs:GetParent():CreateFontString(nil, "OVERLAY")
        hooked[line] = true
        extraLines[fs] = line
    end
    local font, size, flags = fs:GetFont()
    if font then line:SetFont(font, size, flags) end
    line:SetTextColor(fs:GetTextColor())
    line:SetShadowColor(fs:GetShadowColor())
    line:SetShadowOffset(fs:GetShadowOffset())
    line:SetJustifyH(fs:GetJustifyH())
    line:SetWordWrap(false)
    line:SetWidth(fs:GetWidth())
    return line
end

-- The extra row goes on the side away from the bar, and the session row always stays on top.
local function SetRows(fs, first, second)
    local line = extraLines[fs]
    if not second then
        if line then line:SetText("") end
        return first
    end
    line = ExtraLine(fs)
    local point = fs:GetPoint(1)
    local above = type(point) == "string" and point:find("TOP", 1, true) ~= nil
    line:ClearAllPoints()
    if above then
        line:SetPoint("BOTTOMLEFT", fs, "TOPLEFT", 0, 2)
        line:SetText(first)
        return second
    end
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -2)
    line:SetText(second)
    return first
end

-- TustUI reparents its bar texts in pairs() order, so they are told apart by their localized templates.
local function Decorator(text)
    if not matchers then
        matchers = {
            session = PrefixOf("Time this session: %s"),
            rate = PrefixOf("Leveling in: %s (%s XP/Hour)"),
        }
    end
    if matchers.session and text:find(matchers.session, 1, true) == 1 then return DecorateSession end
    if matchers.rate and text:find(matchers.rate, 1, true) == 1 then return DecorateRate end
    return nil
end

local function Rewrite(fs, text)
    original[fs] = text
    local decorate = type(text) == "string" and text ~= "" and Decorator(text)
    if not decorate then
        SetRows(fs)
        return
    end
    local ok, new = xpcall(function() return SetRows(fs, decorate(text)) end, geterrorhandler())
    if ok and new ~= fs:GetText() then
        rewriting = true
        fs:SetText(new)
        rewriting = false
    end
end

local function OnSetText(fs, text)
    if rewriting then return end
    Rewrite(fs, text)
end

local function HookStrings(frame)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "FontString" and not hooked[region] then
            hooked[region] = true
            hooksecurefunc(region, "SetText", OnSetText)
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do HookStrings(child) end
end

local function Attach()
    local frame = _G.TustUIEnhancedXPBarFrame
    if frame then HookStrings(frame) end
end

local function AttachWhenReady(tries)
    if _G.TustUIEnhancedXPBarFrame then
        Attach()
    elseif tries > 0 and _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(ATTACH_INTERVAL, function() AttachWhenReady(tries - 1) end)
    end
end

local function Refresh()
    for fs, text in pairs(original) do Rewrite(fs, text) end
end

local function CountXP()
    local current = UnitXP("player") or 0
    local gained = current - lastXP
    if gained < 0 then gained = (lastMaxXP - lastXP) + current end
    lastXP, lastMaxXP = current, UnitXPMax("player") or 0
    if gained > 0 then
        local s = Stats()
        s.xp = s.xp + gained
    end
end

local function OnEvent(_, event, arg)
    if event == "PLAYER_XP_UPDATE" then
        if arg == nil or arg == "player" then CountXP() end
    elseif event == "PLAYER_LEVEL_UP" then
        Bank(tonumber(arg))
    elseif event == "PLAYER_LOGOUT" then
        Bank()
    elseif event == "PLAYER_ENTERING_WORLD" then
        Attach()
        Bank()
    else
        Bank()
    end
end

local function StatsLabel()
    local s = Stats()
    if s.xp <= 0 then return "Saved: no XP yet" end
    return format("Saved: %s XP in %s (%s XP/Hour)",
        ShortNumber(s.xp), FormatTime(SavedTime()), ShortNumber(SavedRate()))
end

ns.RegisterFeature({
    key = KEY,
    title = "TustUI Enhanced XP Bar",
    tab = "thirdparty",
    requires = { "Tust_EUI", "EllesmereUI" },
    alwaysOn = true,
    description = "Adds session XP and an all-time XP/hour to TustUI's Enhanced XP Bar.",
    help = "Adds session XP and an all-time XP per hour to TustUI's Enhanced XP Bar; turn that bar on in TustUI.",
    defaults = {
        showSessionXP = true,
        rateSource = "session",
    },
    onReset = function() Refresh() end,
    enable = function()
        if not _G.TustEUI then return end
        tracking = true
        lastXP, lastMaxXP = UnitXP("player") or 0, UnitXPMax("player") or 0
        Bank()
        if type(_G.TustEUI.ApplyEnhancedXPBarSettings) == "function" then
            hooksecurefunc(_G.TustEUI, "ApplyEnhancedXPBarSettings", Attach)
            Attach()
        else
            AttachWhenReady(ATTACH_TRIES)
        end
        local events = CreateFrame("Frame")
        events:RegisterEvent("PLAYER_XP_UPDATE")
        events:RegisterEvent("PLAYER_LEVEL_UP")
        events:RegisterEvent("PLAYER_LOGOUT")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("UPDATE_EXPANSION_LEVEL")
        events:RegisterEvent("MAX_EXPANSION_LEVEL_UPDATED")
        events:SetScript("OnEvent", OnEvent)
    end,
    options = function()
        return {
            showSessionXP = {
                type = "toggle", order = 1, name = "Show Session XP",
                desc = "Adds the XP gained this session behind TustUI's session time.",
                get = function() return Settings().showSessionXP end,
                set = function(_, v)
                    Settings().showSessionXP = v == true
                    Refresh()
                    ns.NotifyOptionsChanged()
                end,
            },
            rateSource = {
                type = "select", order = 2, name = "XP/Hour Duration",
                desc = "Session: TustUI's own rate for this session.\nAll-Time: XP and time saved over every session of this character.\nBoth: the session ETA and rate, with the all-time ETA and rate on a second row. The session rate is white near the all-time rate, red when far below, green when far above.",
                values = RATE_VALUES, sorting = RATE_ORDER,
                get = function() return Settings().rateSource end,
                set = function(_, v)
                    Settings().rateSource = v
                    Refresh()
                    ns.NotifyOptionsChanged()
                end,
            },
            stats = { type = "description", order = 3, fontSize = "medium", width = "full", name = function() return _G.EllesmereUI and StatsLabel() or "" end },
            resetStats = {
                type = "execute", order = 4, name = "Reset Saved Stats",
                desc = "Clears the XP and time this character has saved for XP/hour.",
                confirm = true,
                func = function()
                    ResetStats()
                    Refresh()
                    ns.NotifyOptionsChanged()
                end,
            },
        }
    end,
})
