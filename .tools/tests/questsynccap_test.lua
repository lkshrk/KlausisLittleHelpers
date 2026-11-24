local names = { "C_Timer", "C_QuestLog", "RXPV2GuideWindow", "RXPFrame", "wipe", "LibStub", "CreateFrame",
    "securecallfunction", "QuestieLoader", "Constants", "RXPCData" }
local saved = {}
for _, k in ipairs(names) do saved[k] = rawget(_G, k) end
local timers, watched, frames = {}, {}, {}
_G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.securecallfunction = function(fn, ...) return fn(...) end
_G.QuestieLoader = nil
_G.Constants = { QuestWatchConsts = { MAX_QUEST_WATCHES = 3 } }
_G.RXPCData = { currentStep = 2 }
_G.CreateFrame = function()
    local f = { events = {} }
    function f:RegisterEvent(e) self.events[e] = true end
    function f:SetScript(_, fn) self.handler = fn end
    frames[#frames + 1] = f
    return f
end
local log = {}
for id = 1, 5 do log[id] = { questID = id } end
local function Count() local n = 0 for _ in pairs(watched) do n = n + 1 end return n end
_G.C_QuestLog = {
    GetNumQuestLogEntries = function() return #log end,
    GetInfo = function(i) return log[i] end,
    GetLogIndexForQuestID = function(id) for i, q in ipairs(log) do if q.questID == id then return i end end end,
    GetQuestWatchType = function(id) return watched[id] end,
    GetNumQuestWatches = function() return Count() end,
    AddQuestWatch = function(id) if Count() < 3 then watched[id] = 0 end end,
    RemoveQuestWatch = function(id) watched[id] = nil end,
}
_G.RXPV2GuideWindow = { frame = { IsVisible = function() return true end, HookScript = function() end } }
local function Run() for _ = 1, 3 do local l = timers; timers = {}; for _, fn in ipairs(l) do fn() end end end

local good, problem = pcall(function()
    _G.LibStub = nil
    dofile("Libs/LibStub/LibStub.lua")
    dofile("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")
    dofile("Libs/AceEvent-3.0/AceEvent-3.0.lua")
    local AceEvent = _G.LibStub("AceEvent-3.0")
    local spec
    ns.RegisterFeature = function(s) spec = s end
    ns.Print = function() end
    addon("Modules/QuestieRXPSync.lua")
    eq(spec.requires[1], "RXPGuides"); eq(#spec.requires, 1, "Questie is optional"); eq(spec.optional[1], "Questie")
    spec.enable()
    local function step(id) return { elements = { { tag = "accept", questId = id } } } end
    -- Guide order: quest 5 at step 1 (behind), 4 at 2, 3 at 3, 2 at 4, 1 at 5.
    AceEvent:SendMessage("RXP_GUIDE_LOADED", "RXP", { steps = { step(5), step(4), step(3), step(2), step(1) } })
    Run()
    eq(Count(), 3, "stock tracker capped at its limit")
    ok(watched[4] and watched[3] and watched[2], "the guide's next quests are tracked first")
    eq(watched[5], nil, "a quest whose steps are behind comes last"); eq(watched[1], nil)
    log[#log + 1] = { questID = 6 }
    AceEvent:SendMessage("RXP_GUIDE_LOADED", "RXP", { steps = { step(6), step(4) } })
    Run()
    ok(watched[6] and watched[4], "a new guide replaces the tracked set")
    eq(watched[3], nil, "quests outside the new guide are untracked")
end)
for _, k in ipairs(names) do _G[k] = saved[k] end
ok(good, tostring(problem))
