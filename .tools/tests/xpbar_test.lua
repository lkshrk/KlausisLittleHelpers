local charStore = {}
local names = { "EllesmereUI", "EUI_CLIENT_BLOCKED", "TustEUI", "TustEUICharacterDB", "TustUIEnhancedXPBarFrame", "KLH_CharDB",
    "hooksecurefunc", "CreateFrame", "GetTime", "UnitXP", "UnitXPMax", "UnitLevel", "GetMaxLevelForPlayerExpansion",
    "GameRulesUtil", "geterrorhandler", "C_Timer", "LibStub" }
local saved = {}
for _, k in ipairs(names) do saved[k] = rawget(_G, k) end

local now, xp, maxXP = 10000, 900, 1000
local timers, frames = {}, {}
local settings = { showSessionXP = true, rateSource = "session" }

local function FontString(parent)
    local fs = { text = "", parent = parent }
    function fs:SetText(t) self.text = t end
    function fs:GetText() return self.text end
    function fs:GetParent() return self.parent end
    function fs:GetObjectType() return "FontString" end
    function fs:GetFont() return "font", 12, "" end
    function fs:GetTextColor() return 1, 1, 1, 1 end
    function fs:GetShadowColor() return 0, 0, 0, 1 end
    function fs:GetShadowOffset() return 1, -1 end
    function fs:GetJustifyH() return "LEFT" end
    function fs:GetWidth() return 200 end
    function fs:GetPoint() return "BOTTOMLEFT" end
    for _, m in ipairs({ "SetFont", "SetTextColor", "SetShadowColor", "SetShadowOffset", "SetJustifyH", "SetWordWrap",
        "SetWidth", "ClearAllPoints", "SetPoint" }) do fs[m] = function() end end
    return fs
end

local good, problem = pcall(function()
    _G.EllesmereUI = {
        L = function(s) return s end,
        Lf = function(s, ...) return s:format(...) end,
        AbbreviateNumberFixed = function(n) return "abbr" .. n end,
    }
    _G.GetTime = function() return now end
    _G.UnitXP = function() return xp end
    _G.UnitXPMax = function() return maxXP end
    _G.UnitLevel = function() return 30 end
    _G.GetMaxLevelForPlayerExpansion = function() return 60 end
    _G.GameRulesUtil = nil
    _G.geterrorhandler = function() return error end
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    charStore = {}
    _G.hooksecurefunc = function(t, key, hook)
        local orig = t[key]
        t[key] = function(...) local r = orig(...); hook(...); return r end
    end
    _G.CreateFrame = function()
        local f = { events = {} }
        function f:RegisterEvent(e) self.events[e] = true end
        function f:SetScript(_, fn) self.handler = fn end
        frames[#frames + 1] = f
        return f
    end
    _G.LibStub = function() return { NotifyChange = function() end } end
    _G.TustEUI = {}

    addon("Core/Core.lua")
    ns.CharData = function(key) charStore[key] = charStore[key] or {}; return charStore[key] end
    ns.IS_FOREVER = false
    ns.GetSettings = function() return settings end
    local spec
    ns.RegisterFeature = function(s) spec = s end
    addon("Modules/TustUIXPBar.lua")
    spec.enable()
    eq(#timers, 1, "no Apply hook: retries until the bar exists")

    local bar = { CreateFontString = function(self) return FontString(self) end }
    local rate = FontString(bar)
    bar.GetRegions = function() return rate end
    bar.GetChildren = function() end
    _G.TustUIEnhancedXPBarFrame = bar
    local plain = rate.SetText
    timers[1]()
    ok(rate.SetText ~= plain, "attached on retry")

    local opts = spec.options()
    local function Label() return opts.stats.name() end
    eq(Label(), "Saved: no XP yet")
    charStore.tustXPBar.xp, charStore.tustXPBar.time = 1500, 3720
    eq(Label(), "Saved: 1.5K XP in 1h 2m (1.5K XP/Hour)")
    charStore.tustXPBar.xp, charStore.tustXPBar.time = 2500000, 90061
    eq(Label(), "Saved: 2.5M XP in 1d 1h 1m (99.9K XP/Hour)")
    charStore.tustXPBar.xp, charStore.tustXPBar.time = 7, 30
    eq(Label(), "Saved: 7 XP in < 1m (840 XP/Hour)")
    ns.IS_FOREVER = true
    eq(Label(), "Saved: abbr7 XP in < 1m (abbr840 XP/Hour)", "Forever uses EUI's abbreviation")
    ns.IS_FOREVER = false

    charStore.tustXPBar.xp, charStore.tustXPBar.time = 0, 0
    for _, f in ipairs(frames) do
        if f.events.PLAYER_XP_UPDATE then
            xp = 100
            f.handler(f, "PLAYER_XP_UPDATE", "player")
        end
    end
    eq(charStore.tustXPBar.xp, 200, "level-up wrap counts the rest of the old level")

    settings.rateSource = "both"
    charStore.tustXPBar.xp, charStore.tustXPBar.time = 3600, 3600
    local function Session(gained)
        _G.TustEUICharacterDB = { enhancedXPBar = { startTime = now - 3600, gainedXP = gained } }
        rate:SetText("Leveling in: 1h 0m (1K XP/Hour)")
        return rate:GetText()
    end
    ok(Session(2000):find("|cffff5a5a", 1, true), "far below all-time is red")
    ok(Session(5000):find("|cff5aff7a", 1, true), "far above all-time is green")
    ok(Session(3700):find("|cffffffff", 1, true), "near all-time is white")
    ok(Session(3060):find("|cffffffff", 1, true), "15% below is still white")
    ok(Session(3000):find("|cffff5a5a", 1, true), "past 15% below is red")

    eq(table.concat(spec.requires, ","), "Tust_EUI,EllesmereUI", "requires both addons")
    _G.EllesmereUI = nil
    ns.IS_FOREVER = true
    local fine, why = pcall(function()
        Session(3000)
        rate:SetText("Time this session: 5m")
        eq(opts.stats.name(), "", "no stats label without EllesmereUI")
    end)
    ok(fine, "hook survives a missing EllesmereUI: " .. tostring(why))
    ns.IS_FOREVER = false
end)
for _, k in ipairs(names) do _G[k] = saved[k] end
ok(good, tostring(problem))
