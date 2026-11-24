local names = { "LibStub", "CreateFrame", "geterrorhandler", "StaticPopup_Show", "C_AddOns" }
local saved = {}
for _, k in ipairs(names) do saved[k] = rawget(_G, k) end
local fakeDB = { profile = { features = {} }, callbacks = {} }
fakeDB.RegisterCallback = function(_, event, fn) fakeDB.callbacks[event] = fn end
local notified, popups = 0, 0
local libs = {
    ["AceDB-3.0"] = { New = function() return fakeDB end },
    ["AceDBOptions-3.0"] = { GetOptionsTable = function() return {} end },
    ["AceConfig-3.0"] = { RegisterOptionsTable = function() end },
    ["AceConfigDialog-3.0"] = { SetDefaultSize = function() end },
    ["AceConfigRegistry-3.0"] = { NotifyChange = function() notified = notified + 1 end },
}
_G.LibStub = function(name) return libs[name] end
_G.CreateFrame = nil
_G.StaticPopup_Show = function() popups = popups + 1 end
_G.geterrorhandler = function() return function(e) error(e, 0) end end
local loaded = {}
_G.C_AddOns = { IsAddOnLoaded = function(n) return loaded[n] == true end }

local good, problem = pcall(function()
    addon("Core/Core.lua")
    addon("Core/Options.lua")
    local calls = {}
    local function Spec(key, extra)
        local spec = { key = key, title = key,
            enable = function() calls[#calls + 1] = "+" .. key end }
        for k, v in pairs(extra or {}) do spec[k] = v end
        return spec
    end
    ns.FEATURE_CLIENTS.Live, ns.FEATURE_CLIENTS.Old, ns.FEATURE_CLIENTS.Gated = "all", "all", "all"
    ns.RegisterFeature(Spec("Live", { disable = function() calls[#calls + 1] = "-Live" end }))
    ns.RegisterFeature(Spec("Old"))
    ns.RegisterFeature(Spec("Gated", { requires = { "Missing" }, disable = function() calls[#calls + 1] = "-Gated" end }))

    eq(ns.IsRunning("Live"), false)
    ns.GetSettings("Live").enabled = true
    ns.ApplyFeature("Live")
    eq(calls[1], "+Live", "live feature starts"); eq(ns.IsRunning("Live"), true)
    eq(ns.WasEnabledAtLoad("Live"), true, "alias shares the running state")
    ns.ApplyFeature("Live")
    eq(#calls, 1, "already running: no second enable")
    ns.GetSettings("Live").enabled = nil
    ns.ApplyFeature("Live")
    eq(calls[2], "-Live", "live feature stops"); eq(ns.IsRunning("Live"), false)
    ns.ApplyFeature("Live")
    eq(#calls, 2, "already stopped: no second disable")

    ns.GetSettings("Old").enabled = true
    ns.ApplyFeature("Old")
    eq(#calls, 2, "feature without disable is never switched live"); eq(ns.IsRunning("Old"), false)

    ns.GetSettings("Gated").enabled = true
    ns.ApplyFeature("Gated")
    eq(#calls, 2, "gating still applies"); eq(ns.IsRunning("Gated"), false)
    loaded.Missing = true
    ns.ApplyFeature("Gated")
    eq(calls[3], "+Gated")
    loaded.Missing = nil
    ns.ApplyFeature("Gated")
    eq(calls[4], "-Gated", "losing a requirement stops it")
    ns.GetSettings("Gated").enabled = nil
    ns.GetSettings("Old").enabled = nil

    ns.RegisterOptions()
    local t = ns.BuildOptionsTable(ns.features, ns.featureOrder, { isForever = true, isLoaded = function() return true end })
    local liveToggle = t.args.helpers.args.Live.args.enabled
    local oldToggle = t.args.helpers.args.Old.args.enabled
    ok(not tostring(liveToggle.desc or ""):lower():find("reload"), "live toggle does not mention a reload")
    local before = notified
    liveToggle.set(nil, true)
    eq(popups, 0, "live toggle asks no reload"); eq(ns.IsRunning("Live"), true)
    ok(notified > before, "options redrawn")
    liveToggle.set(nil, false)
    eq(popups, 0); eq(ns.IsRunning("Live"), false)
    oldToggle.set(nil, true)
    eq(popups, 1, "non-live toggle still asks for a reload")
    oldToggle.set(nil, false)

    fakeDB.profile.features.Live = { enabled = true }
    popups = 0
    fakeDB.callbacks.OnProfileChanged()
    eq(ns.IsRunning("Live"), true, "profile swap applies live features")
    eq(popups, 0, "no reload for a live feature on profile swap")
    fakeDB.profile.features.Live = {}
    fakeDB.callbacks.OnProfileReset()
    eq(ns.IsRunning("Live"), false)
end)
for _, k in ipairs(names) do _G[k] = saved[k] end
ok(good, tostring(problem))
