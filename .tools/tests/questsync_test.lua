local names = { "C_Timer", "C_QuestLog", "RXPV2GuideWindow", "RXPFrame", "wipe", "LibStub", "CreateFrame",
    "securecallfunction", "print", "QuestieLoader" }
local saved = {}
for _, k in ipairs(names) do saved[k] = rawget(_G, k) end
local timers, watched, order, printed = {}, {}, {}, {}
local frames = {}
_G.print = function(s) printed[#printed + 1] = tostring(s) end
_G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.securecallfunction = function(fn, ...) return fn(...) end
_G.CreateFrame = function()
    local f = { events = {} }
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:SetScript(_, fn) self.handler = fn end
    frames[#frames + 1] = f
    return f
end
local log = { { questID = 1 }, { questID = 2 }, { questID = 3, isHeader = true } }
_G.C_QuestLog = {
    GetNumQuestLogEntries = function() return #log end,
    GetInfo = function(i) return log[i] end,
    GetLogIndexForQuestID = function(id) for i, q in ipairs(log) do if q.questID == id then return i end end end,
    GetQuestWatchType = function(id) return watched[id] end,
    AddQuestWatch = function(id) watched[id] = 0; order[#order + 1] = "+" .. id end,
    RemoveQuestWatch = function(id) watched[id] = nil; order[#order + 1] = "-" .. id end,
}
local visible = false
_G.RXPV2GuideWindow = { frame = { IsVisible = function() return visible end, HookScript = function() end } }
local function Run()
    local list = timers
    timers = {}
    for _, fn in ipairs(list) do fn() end
end
local function Fire(event, ...)
    for _, f in ipairs(frames) do
        if f.events[event] and f.handler then f.handler(f, event, ...) end
    end
end
local function Count(text)
    local n = 0
    for _, line in ipairs(printed) do if line:find(text, 1, true) then n = n + 1 end end
    return n
end

local good, problem = pcall(function()
    _G.LibStub = nil
    dofile("Libs/LibStub/LibStub.lua")
    dofile("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")
    dofile("Libs/AceEvent-3.0/AceEvent-3.0.lua")
    local AceEvent = _G.LibStub("AceEvent-3.0")
    local spec
    ns.RegisterFeature = function(s) spec = s end
    ns.Print = function(s) printed[#printed + 1] = tostring(s) end
    addon("Modules/QuestieRXPSync.lua")
    eq(ns.QuestSync, nil, "no test seam")
    spec.enable()
    local function Send(guide) AceEvent:SendMessage("RXP_GUIDE_LOADED", "RXP", guide) end

    watched[2] = 0
    Send({ steps = { { elements = { { tag = "accept", questId = 1 } } } } })
    Run(); Run()
    eq(watched[1], nil, "nothing synced while hidden")
    visible = true
    Run(); Run(); Run()
    eq(watched[1], 0, "guide quest tracked"); eq(watched[2], nil, "other quest untracked")
    eq(table.concat(order, ","), "-2,+1", "removals before adds")

    order = {}
    log[#log + 1] = { questID = 4 }
    Fire("QUEST_ACCEPTED", 4)
    Run(); Run()
    eq(watched[4], nil, "accepted non-guide quest untracked"); eq(#order, 0, "nothing else touched")
    watched[4] = 0
    Fire("QUEST_ACCEPTED", 4)
    Run(); Run()
    eq(watched[4], nil, "accepted non-guide quest removed from the tracker")
    eq(table.concat(order, ","), "-4", "accept syncs only that quest")

    order = {}
    Send({ steps = { { elements = { { tag = "goto" } } }, { text = "x" } } })
    Run(); Run()
    eq(#order, 0, "unrecognised guide changes nothing")
    eq(Count("this guide section has no quests"), 1)
    Send({ steps = { { elements = {} } } })
    Run(); Run()
    eq(Count("this guide section has no quests"), 1, "printed once")

    visible = false
    Send({ steps = { { elements = { { tag = "turnin", questId = 2 } } } } })
    for _ = 1, 40 do Run() end
    eq(watched[2], nil, "still hidden, nothing synced")
    eq(Count("no RestedXP guide window found"), 1, "gives up once with a note")

    eq(Count("tracker API changed"), 0, "no notice without Questie")
    _G.QuestieLoader = { ImportModule = function() return {} end }
    spec.enable(); spec.enable()
    eq(Count("tracker API changed"), 1, "one notice when Questie's tracker lacks IsTrackedByQuestie")
    _G.QuestieLoader = { ImportModule = function() return { IsTrackedByQuestie = function() return false end } end }
    spec.enable()
    eq(Count("tracker API changed"), 1, "no extra notice for a working tracker")
end)
for _, k in ipairs(names) do _G[k] = saved[k] end
ok(good, tostring(problem))
