local touched = {}
local function Stub(values)
    for k, v in pairs(values) do
        if touched[k] == nil then touched[k] = { rawget(_G, k) } end
        _G[k] = v
    end
end
Stub({ KLH = false })

addon("Core/Core.lua"); addon("Core/UI.lua"); addon("Modules/TurnInRouteGraph.lua")
ns.IS_FOREVER = true
addon("Modules/RouteDraw.lua"); addon("Modules/RouteWaypoints.lua"); addon("Modules/RoutePlanner.lua"); addon("Modules/TurnInRoute.lua")
local RP, T = ns.RoutePlanner, ns.TurnInRoute
local printed = {}
ns.Print = function(msg) printed[#printed + 1] = msg end
ok(ns.features.TurnInRoute ~= nil, "feature registered")

local function Fn() end
local full = {
    QuestieDB = { IsComplete = Fn, GetQuest = Fn }, ZoneDB = { GetUiMapIdByAreaId = Fn }, DistanceUtils = { GetNearestFinisherOrStarter = Fn },
    HBD = { GetPlayerWorldPosition = Fn, GetZoneCoordinatesFromWorld = Fn, GetWorldCoordinatesFromZone = Fn, GetAllMapIDs = Fn },
}
eq(T.MissingQuestieApi(full), nil, "every function present")
full.HBD.GetZoneCoordinatesFromWorld = nil
eq(T.MissingQuestieApi(full), "HBD.GetZoneCoordinatesFromWorld")
full.HBD.GetZoneCoordinatesFromWorld = Fn
full.ZoneDB.GetUiMapIdByAreaId = true
eq(T.MissingQuestieApi(full), "ZoneDB.GetUiMapIdByAreaId", "a non-function counts as missing")
eq(T.MissingQuestieApi({}), "QuestieDB.IsComplete", "empty modules from ImportModule")

local scripts = {}
local frame = setmetatable({ SetScript = function(_, name, fn) scripts[name] = fn end },
    { __index = function() return function() end end })
local modules = {}
local inCombat = false
Stub({
    QuestieLoader = { ImportModule = function(_, name) modules[name] = modules[name] or {}; return modules[name] end },
    WorldMapFrame = { IsShown = function() return false end, HookScript = function() end },
    CreateFrame = function() return frame end,
    hooksecurefunc = function() end,
    C_Timer = { After = function() end },
    InCombatLockdown = function() return inCombat end,
    geterrorhandler = function() return function(e) error(e) end end,
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
})
ns.CreateListWindow = function() return { SetEntries = function() end } end

ns.features.TurnInRoute.enable({})
eq(#printed, 1, "one notice when Questie changed")
eq(printed[1], "Turn-in Route: Questie changed (QuestieDB.IsComplete missing); route planning is off.")
eq(#RP.Sources(), 0, "no sources registered")

local state = { [5] = true, [6] = 1, [7] = false, [8] = 0 }
modules.QuestieDB = {
    IsComplete = function(id) return state[id] end,
    GetQuest = function() return { Finisher = { 1 } } end,
}
modules.ZoneDB = { GetUiMapIdByAreaId = function() return 1446 end }
modules.DistanceUtils = { GetNearestFinisherOrStarter = function() return { 50, 50 }, 1, "NPC" end }
modules.HBD = { GetPlayerWorldPosition = Fn, GetZoneCoordinatesFromWorld = Fn, GetWorldCoordinatesFromZone = Fn, GetAllMapIDs = Fn }
Stub({
    C_QuestLog = {
        GetNumQuestLogEntries = function() return 4 end,
        GetInfo = function(i) return { questID = i + 4, title = "Q" .. (i + 4) } end,
    },
})
wipe(printed)
ns.features.TurnInRoute.enable({})
eq(#printed, 0, "no notice with the full API")
ok(#RP.Sources() == 2, "quests and writs registered")
local stops, _, count = RP.Collect({ "quests" })
eq(count, 2, "IsComplete true and 1 both count")
eq(#stops, 1); eq(stops[1].questIds[1], 5); eq(stops[1].questIds[2], 6)

local hidden = {}
Stub({
    LibStub = function(name)
        if name == "AceAddon-3.0" then
            return { GetAddon = function() return { settings = { profile = { showEnabled = true } } } end }
        elseif name == "AceDB-3.0" then
            return { New = function() return { profile = { features = {} } } end }
        end
    end,
    SlashCmdList = { ACECONSOLE_RXP = function(arg) hidden[#hidden + 1] = arg end },
})
local planSources = RP.PlanSources
RP.PlanSources = function() return "Route.", true end
inCombat = true
wipe(printed)
T.Plan({ "quests" })
eq(#hidden, 0, "RestedXP is not hidden in combat")
ok(printed[1]:find("RestedXP paused", 1, true), printed[1])
inCombat = false
scripts.OnEvent(frame, "PLAYER_REGEN_ENABLED")
eq(#hidden, 1, "hidden once combat ends"); eq(hidden[1], "hide")
T.Plan({ "quests" })
eq(#hidden, 2, "out of combat it hides at once")
RP.PlanSources = planSources

for k, saved in pairs(touched) do _G[k] = saved[1] end
