addon("Core/Core.lua")
local loaded = { Questie = true }
local function isLoaded(n) return loaded[n] == true end
ns.FEATURE_CLIENTS.B = "all"
eq(table.concat(ns.MissingAddons({ requires = { "Questie", "RXPGuides" } }, isLoaded), ","), "RXPGuides")
ok(not ns.ShouldEnable({ key = "B", requires = { "RXPGuides" }, alwaysOn = true }, { isForever = true, isLoaded = isLoaded }), "missing addon blocks")
ns.FEATURE_CLIENTS.R, ns.FEATURE_CLIENTS.F, ns.FEATURE_CLIENTS.B = "retail", "forever", "all"
ok(not ns.ShouldEnable({ key = "R", alwaysOn = true }, { isForever = true, isLoaded = isLoaded }), "retail-only off on Forever")
ok(ns.ShouldEnable({ key = "R", alwaysOn = true }, { isForever = false, isLoaded = isLoaded }), "retail-only on retail")
ok(not ns.ShouldEnable({ key = "F", alwaysOn = true }, { isForever = false, isLoaded = isLoaded }), "forever-only off on retail")
ok(ns.ShouldEnable({ key = "B", alwaysOn = true }, { isForever = false, isLoaded = isLoaded }), "all runs on retail")
ok(not ns.ShouldEnable({ key = "Unlisted", alwaysOn = true }, { isForever = true, isLoaded = isLoaded }), "unlisted runs nowhere")
eq(ns.FEATURE_CLIENTS.TustUIXPBar, "all"); eq(ns.FEATURE_CLIENTS.QuestieRXPSync, "forever")
eq(ns.FEATURE_CLIENTS.TurnInRoute, "forever"); eq(ns.FEATURE_CLIENTS.WritCratePlanner, "forever")
ok(ns.ShouldEnable({ key = "B", requires = { "Questie" }, alwaysOn = true }, { isForever = true, isLoaded = isLoaded }), "met")
ok(not ns.ShouldEnable({ key = "B" }, { isForever = true, isLoaded = isLoaded, enabled = false }), "switchable off")
ok(ns.ShouldEnable({ key = "B" }, { isForever = true, isLoaded = isLoaded, enabled = true }), "switchable on")
eq(ns.RequiresText({ "A" }, function() return "|TInterface\\Icons\\X:16|t |A:atlas:16:16|a |cff00ff00Name|r" end), "Requires: Name")
eq(ns.RequiresText({ "A" }, function() return "Pre |A:atlas:16:16|a Post" end), "Requires: Pre Post", "stripping a middle code leaves one space")

local names = { "LibStub", "CreateFrame", "geterrorhandler", "print", "KLH_CharDB", "C_AddOns" }
local saved = {}
for _, k in ipairs(names) do saved[k] = rawget(_G, k) end
local printed, handler = {}, nil
local fakeDB = { profile = { features = {} } }
_G.LibStub = function(name) if name == "AceDB-3.0" then return { New = function() return fakeDB end } end end
_G.CreateFrame = function()
    return { RegisterEvent = function() end, UnregisterEvent = function() end, SetScript = function(_, _, fn) handler = fn end }
end
_G.print = function(s) printed[#printed + 1] = tostring(s) end
local errors = {}
_G.geterrorhandler = function() return function(e) errors[#errors + 1] = tostring(e) end end
local good, problem = pcall(function()
    ns = { Data = {} }
    addon("Core/Core.lua")
    local defaults = { n = 1, list = { 1, 2 } }
    ns.FEATURE_CLIENTS.D1, ns.FEATURE_CLIENTS.Bad, ns.FEATURE_CLIENTS.Good = "all", "all", "all"
    ns.RegisterFeature({ key = "D1", alwaysOn = true, defaults = defaults, enable = function() end })
    local s = ns.GetSettings("D1")
    eq(s.n, 1, "default read through"); eq(rawget(s, "n"), nil, "scalar default not copied into the profile")
    s.n = 5; s.list[1] = 9
    eq(defaults.n, 1, "profile edit leaves defaults alone"); eq(defaults.list[1], 1, "table default copied before edit")
    eq(ns.GetSettings("D1").n, 5)
    ns.ResetFeature("D1")
    eq(ns.GetSettings("D1").n, 1, "reset falls back to defaults"); eq(ns.GetSettings("D1").list[1], 1)
    defaults.n = 7
    eq(ns.GetSettings("D1").n, 7, "changed default reaches an untouched setting")

    local ran = {}
    ns.RegisterFeature({ key = "Bad", alwaysOn = true, enable = function() error("boom") end })
    ns.RegisterFeature({ key = "Good", alwaysOn = true, enable = function() ran[#ran + 1] = "good" end })
    handler({ UnregisterEvent = function() end }, "PLAYER_LOGIN")
    eq(ran[1], "good", "a failing enable does not stop the next one"); eq(#errors, 1)

    ns.RegisterFeature({ key = "Nowhere", enable = function() end })
    ns.RegisterFeature({ key = "Nowhere2", enable = function() end })
    eq(ns.features.Nowhere, nil)
    local hits = 0
    for _, line in ipairs(printed) do if line:find("Developer error: feature Nowhere ", 1, true) then hits = hits + 1 end end
    eq(hits, 1, "unlisted feature reported as developer error")
    ns.FEATURE_CLIENTS.Other = ns.IS_FOREVER and "retail" or "forever"
    local before = #printed
    ns.RegisterFeature({ key = "Other", enable = function() end })
    eq(#printed, before, "other-client feature stays quiet"); eq(ns.features.Other, nil)

    _G.KLH_CharDB = nil
    local cd = ns.CharData("x"); cd.v = 1
    eq(_G.KLH_CharDB.x.v, 1); ok(ns.CharData("x") == cd, "same table")
end)
for _, k in ipairs(names) do _G[k] = saved[k] end
ok(good, tostring(problem))
