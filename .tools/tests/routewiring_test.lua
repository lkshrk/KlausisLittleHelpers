local charStore = {}
addon("Core/Core.lua"); addon("Core/Options.lua"); addon("Modules/TurnInRouteGraph.lua")
ns.IS_FOREVER = true
addon("Modules/RouteDraw.lua"); addon("Modules/RouteWaypoints.lua"); ns.CharData = function(key) charStore[key] = charStore[key] or {}; return charStore[key] end
addon("Modules/RoutePlanner.lua"); addon("Modules/TurnInRoute.lua")
local RP = ns.RoutePlanner

local touched = {}
local function Stub(values)
    for k, v in pairs(values) do
        if touched[k] == nil then touched[k] = { rawget(_G, k) } end
        _G[k] = v
    end
end

local function Points(scale)
    return {
        GetWorldCoordinatesFromZone = function(_, x, y, mapID) if mapID then return x * scale, y * scale, 0 end end,
        GetPlayerWorldPosition = function() return 0, 0, 0 end,
        GetAllMapIDs = function() return {} end,
        GetZoneCoordinatesFromWorld = function() end,
    }
end

local log, valid, nextUid = {}, {}, 0
local registry = { [1] = {} }
local TomTom = {
    AddWaypoint = function(_, mapID)
        nextUid = nextUid + 1
        local uid = { mapID, id = nextUid }
        valid[uid] = true
        registry[1][uid.id] = uid
        log[#log + 1] = "add"
        return uid
    end,
    RemoveWaypoint = function(_, uid) valid[uid] = nil; registry[1][uid.id] = nil; log[#log + 1] = "remove" end,
    IsValidWaypoint = function(_, uid) return valid[uid] == true end,
    waypoints = registry,
    DefaultCallbacks = function() return { distance = {} } end,
    SetCrazyArrow = function() log[#log + 1] = "arrow" end,
}
local function Count(what)
    local n = 0
    for _, entry in ipairs(log) do if entry == what then n = n + 1 end end
    return n
end

local completed, entries, timers = {}, {}, {}
local canvas = { Child = {} }
local frame = setmetatable({}, { __index = function() return function() end end })
local bind = { name = "Inn Town", ready = true, count = 1, start = 0 }
local now = 100
Stub({
    TomTom = TomTom, KLH_CharDB = {}, KLH = ns,
    WorldMapFrame = { IsShown = function() return false end, ScrollContainer = canvas, HookScript = function() end },
    C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end },
    CreateFrame = function() return frame end,
    hooksecurefunc = function() end,
    CopyTable = function(t) local copy = {} for k, v in pairs(t) do copy[k] = v end return copy end,
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
    C_QuestLog = {
        IsQuestFlaggedCompleted = function(id) return completed[id] == true end,
        GetLogIndexForQuestID = function() return nil end,
    },
    GetUnitSpeed = function() return 0, 7 end,
    IsMounted = function() return false end,
    GetTime = function() return now end,
    GetBindLocation = function() return bind.name end,
    C_Item = { GetItemCount = function() return bind.count end },
    C_Container = { GetItemCooldown = function() return bind.start, bind.duration or 0 end },
    C_SpellBook = { IsSpellKnown = function() return false end },
    UnitFactionGroup = function() return "Alliance" end,
    UnitOnTaxi = function() return false end,
    Enum = { UIMapType = { Continent = 2 }, FlightPathFaction = { Horde = 0, Alliance = 1, Neutral = 2 } },
    C_Map = {
        GetBestMapForUnit = function() return nil end,
        GetMapInfo = function(id) return { mapID = id, name = "Zone", mapType = 3, parentMapID = 0 } end,
    },
    C_TaxiMap = { GetTaxiNodesForMap = function() return {} end },
})
local hbd = Points(1000)
ns.CreateListWindow = function()
    return { SetEntries = function(_, list) entries = list end }
end
local printed = {}
ns.Print = function(msg) printed[#printed + 1] = msg end
ns.Transports = {}
RP.Init({ hbd = hbd, onRefresh = function() end })
eq(#timers, 1, "init schedules the restore")

local function Point(kind, name, x, y)
    return { kind = kind, name = name, zone = "Zone", mapID = 1, x = x, y = y, wx = x * 1000, wy = y * 1000, instance = 0 }
end

local function OldRoute()
    return {
        start = Point("start", "Start", 0.1, 0.1),
        legs = {
            {
                number = 1,
                stop = (function()
                    local stop = Point("stop", "Nia", 0.5, 0.5)
                    stop.quests, stop.questIds = { "Q1" }, { 1 }
                    return stop
                end)(),
                steps = {
                    { kind = "flight", from = Point("taxi", "A", 0.2, 0.2), to = Point("taxi", "B", 0.4, 0.4), hops = { 10, 20 } },
                    { kind = "ground", from = Point("taxi", "B", 0.4, 0.4), to = Point("stop", "Nia", 0.5, 0.5) },
                },
            },
            {
                number = 2,
                stop = (function()
                    local stop = Point("stop", "Bo", 0.7, 0.7)
                    stop.quests, stop.questIds = { "Q2" }, { 2 }
                    return stop
                end)(),
                steps = {
                    { kind = "flight", from = Point("taxi", "C", 0.6, 0.6), to = Point("taxi", "D", 0.65, 0.65), hops = { 30, 40 }, passed = true },
                },
            },
        },
    }
end

local function Restore(route)
    charStore = { turnInRoute = { route = route } }
    RP.Restore()
end

_G.TomTom = TomTom
wipe(log)
local route = OldRoute()
eq(route.waypoints, nil, "old format has no waypoints field")
Restore(route)
eq(RP.Active(), true, "restored route is active")
eq(#entries, 2, "both legs kept")
eq(entries[1].data.number, 1); eq(entries[2].data.number, 2)
eq(entries[1].data.steps[1].kind, "flight"); eq(entries[1].data.steps[1].hops[2], 20)
eq(Count("add"), 3, "one flight and one stop for leg 1, only the stop for leg 2 (flight passed)")
ok(entries[1].data.uid ~= nil and entries[2].data.uid ~= nil, "legs hold their stop waypoint")
eq(#entries[1].data.transit, 1); eq(#entries[2].data.transit, 0)
eq(charStore.turnInRoute.route.waypoints, true, "route re-saved with the waypoint flag")
eq(#charStore.turnInRoute.route.legs, 2)
RP.Abort()
eq(RP.Active(), false)

wipe(log)
_G.TomTom = nil
Restore(OldRoute())
eq(RP.Active(), true, "restores without TomTom")
eq(#entries, 2)
eq(#log, 0, "no TomTom call when it is absent")
eq(charStore.turnInRoute.route.waypoints, false)
RP.Abort()

_G.TomTom = setmetatable({}, { __index = function(_, k) log[#log + 1] = "touch:" .. k end })
Restore(OldRoute())
eq(RP.Active(), true, "restores with a TomTom lacking AddWaypoint")
eq(#entries, 2)
eq(#log, 1, "only the AddWaypoint probe")
eq(log[1], "touch:AddWaypoint")
RP.Abort()
_G.TomTom = TomTom

completed = { [11] = true, [21] = true, [22] = true }
route = OldRoute()
route.legs[1].stop.quests, route.legs[1].stop.questIds = { "QA", "QB" }, { 10, 11 }
route.legs[2].stop.quests, route.legs[2].stop.questIds = { "QC", "QD" }, { 21, 22 }
route.legs[3] = {
    number = 3,
    stop = (function()
        local stop = Point("stop", "Cy", 0.8, 0.8)
        stop.quests, stop.questIds = { "QE" }, { 30 }
        return stop
    end)(),
    steps = {},
}
Restore(route)
eq(#entries, 2, "fully turned-in stop is gone")
local first, last = entries[1].data.stop, entries[2].data.stop
eq(#first.questIds, 1); eq(first.questIds[1], 10); eq(#first.quests, 1); eq(first.quests[1], "QA")
eq(last.name, "Cy"); eq(last.questIds[1], 30, "id not flagged completed is kept")
ok(not has(entries, nil, nil, function(e) return e.data.stop.name == "Bo" end), "second stop dropped")
eq(#charStore.turnInRoute.route.legs, 2)
RP.Abort()
completed = {}

RP.RegisterSource("x", {
    title = "X", order = 1,
    collect = function()
        return { { name = "Nia", mapID = 1, x = 0.5, y = 0.5, quests = { "Q1" }, questIds = { 1 } } }
    end,
})
_G.TomTom = nil
wipe(log)
local message, started = RP.PlanSources({ "x" }, { waypoints = "replace" })
ok(message:find("^Route:"), message); eq(started, true); eq(RP.Active(), true)
eq(#log, 0, "no TomTom call")
eq(charStore.turnInRoute.route.waypoints, false)
RP.Abort()

_G.TomTom = TomTom
wipe(log)
message, started = RP.PlanSources({ "x" }, { waypoints = "replace" })
ok(message:find("^TomTom route:"), message); eq(started, true); eq(RP.Active(), true)
ok(Count("add") >= 1, "waypoint added")
RP.Abort()
wipe(log)
message = RP.PlanSources({ "x" }, {})
ok(message:find("^TomTom route:"), "waypoints default to add")
RP.Abort()

local function Far()
    return { { name = "Far", mapID = 1, x = 10, y = 0, quests = { "Q" }, questIds = { 1 } } }
end
local function Kinds(plan)
    local kinds = {}
    for _, step in ipairs(plan.route[1].steps) do kinds[#kinds + 1] = step.kind end
    return table.concat(kinds, ",")
end
charStore = { turnInRoute = { bind = { wx = 9900, wy = 0, instance = 0, name = "Inn Town" } } }
local walk = RP.Plan(Far(), { hearth = false })
eq(Kinds(walk), "ground", "useHearth = false gives no shortcut")
local hearth = RP.Plan(Far(), { hearth = true })
eq(Kinds(hearth), "hearth,ground", "useHearth = true hearths first")
eq(hearth.route[1].steps[1].to.name, "Inn Town"); eq(hearth.route[1].steps[1].to.kind, "inn")
ok(hearth.total < walk.total, "hearth is faster")
eq(Kinds(RP.Plan(Far(), {})), "ground", "no option, no shortcut")
do
    local queries, itemStub, spellStub, savedTeleports = 0, _G.C_Item, _G.C_SpellBook, ns.Teleports
    ns.Teleports = { { spellID = 1, reagent = 2 } }
    _G.C_Item = { GetItemCount = function() queries = queries + 1; return 1 end }
    _G.C_SpellBook = { IsSpellKnown = function() queries = queries + 1; return true end }
    RP.Plan(Far(), { hearth = false, teleports = false })
    eq(queries, 0, "no spellbook or bag queries with every shortcut off")
    RP.Plan(Far(), { teleports = true })
    ok(queries > 0, "teleports on queries the spellbook and bags")
    _G.C_Item, _G.C_SpellBook, ns.Teleports = itemStub, spellStub, savedTeleports
end

bind.count = 0
eq(Kinds(RP.Plan(Far(), { hearth = true })), "ground", "no hearthstone in the bags")
bind.count, bind.start, bind.duration = 1, 90, 60
eq(Kinds(RP.Plan(Far(), { hearth = true })), "ground", "hearthstone on cooldown")
bind.start = 0
eq(Kinds(RP.Plan(Far(), { hearth = true })), "hearth,ground", "cooldown over")
bind.name = "Elsewhere"
eq(Kinds(RP.Plan(Far(), { hearth = true })), "ground", "bind location changed since it was recorded")
bind.name = "Inn Town"
charStore.turnInRoute.bind = nil
eq(Kinds(RP.Plan(Far(), { hearth = true })), "ground", "no recorded bind")
charStore.turnInRoute.bind = { wx = 9900, wy = 0, instance = 0, name = "Inn Town" }

RP.RegisterSource("far", { title = "Far", order = 2, collect = Far })
_G.TomTom = nil
RP.PlanSources({ "far" }, { useHearth = true })
eq(entries[1].data.steps[1].kind, "hearth", "settings.useHearth reaches the planner")
RP.Abort()
RP.PlanSources({ "far" }, { useHearth = false })
eq(entries[1].data.steps[1].kind, "ground", "settings.useHearth = false")
RP.Abort()

local loaded = { Questie = false, TomTom = false }
Stub({ C_AddOns = { IsAddOnLoaded = function(name) return loaded[name] == true end } })
local function Build()
    local ctx = {
        isForever = true, isLoaded = ns.AddonLoaded, title = function() end,
        settings = function() return { waypoints = "add" } end,
    }
    local good, result = pcall(ns.BuildOptionsTable, ns.features, { "TurnInRoute" }, ctx)
    ok(good, tostring(result))
    return result.args.helpers.args.TurnInRoute
end
ok(ns.features.TurnInRoute ~= nil, "feature registered")
local routeSpec = ns.features.TurnInRoute
eq(routeSpec.launcher.text, "Turn-in Route")
local before = #printed
routeSpec.launcher.onClick()
eq(#printed, before, "launcher is silent before enable")
routeSpec.enable()
routeSpec.launcher.onClick()
ok(printed[#printed]:find("unavailable", 1, true), "missing loader explained")
before = #printed
local modules = {
    QuestieDB = { IsComplete = function() end, GetQuest = function() end },
    ZoneDB = { GetUiMapIdByAreaId = function() end },
    DistanceUtils = { GetNearestFinisherOrStarter = function() end },
    HBD = hbd,
}
Stub({ QuestieLoader = { ImportModule = function(_, name) return modules[name] end } })
local isComplete = modules.QuestieDB.IsComplete
modules.QuestieDB.IsComplete = nil
routeSpec.enable()
local failure = printed[#printed]
routeSpec.launcher.onClick()
eq(printed[#printed], failure, "launcher repeats Questie API failure")
eq(#printed, before + 2, "enable and launcher report failure")
modules.QuestieDB.IsComplete = isComplete
routeSpec.enable()
local originalPlan, originalSettings, originalPrint = RP.PlanSources, ns.GetSettings, ns.Print
local profile = { useShortestPath = true }
ns.GetSettings = function() return profile end
ns.Print = function() end
local plannedKeys, plannedSettings
RP.PlanSources = function(keys, settings) plannedKeys, plannedSettings = keys, settings; return "planned", false end
local routeOptions = routeSpec.options()
local shortestOption = routeOptions.useShortestPath
local originalLoaded = ns.AddonLoaded
ns.AddonLoaded = function(name) return name == "TomTom" end
profile.useHearth, profile.useTeleports, profile.waypoints = true, false, "replace"
local descriptions = {
    useHearth = "Let the route start with your hearthstone when it is bound, ready and faster.",
    useTeleports = "Let the route start with a known mage city teleport when you carry the Rune of Teleportation.",
    waypoints = "Add keeps your other waypoints. Replace clears them all first.",
}
local shortestHint = "\n|cffffd100Disabled with Shortest Path.|r"
ns.ShortestPath = { Available = function() return true end }
for _, key in ipairs({ "useHearth", "useTeleports", "waypoints" }) do
    eq(routeOptions[key].disabled(), true, key .. " disabled by Shortest Path")
    local desc = routeOptions[key].desc
    if type(desc) == "function" then desc = desc() end
    eq(desc, descriptions[key] .. shortestHint, key .. " keeps description and highlights disabled hint")
end
ns.ShortestPath.Available = function() return false end
for _, key in ipairs({ "useHearth", "useTeleports", "waypoints" }) do
    eq(routeOptions[key].disabled(), false, key .. " enabled when Shortest Path unavailable")
end
ns.ShortestPath.Available = function() return true end
local settingsChanges, originalChanged = 0, RP.SettingsChanged
RP.SettingsChanged = function() settingsChanges = settingsChanges + 1 end
shortestOption.set(nil, false)
eq(settingsChanges, 1, "option applies journey setting immediately")
routeSpec.onReset()
eq(settingsChanges, 2, "profile changes apply journey setting")
RP.SettingsChanged = originalChanged
for _, key in ipairs({ "useHearth", "useTeleports", "waypoints" }) do
    eq(routeOptions[key].disabled(), false, key .. " enabled without Shortest Path")
end
eq(routeOptions.useHearth.get(), true, "hearth choice preserved")
eq(routeOptions.useTeleports.get(), false, "teleport choice preserved")
eq(routeOptions.waypoints.get(), "replace", "waypoint choice preserved")
ns.AddonLoaded = function() return false end
eq(routeOptions.waypoints.disabled(), true, "missing TomTom still disables waypoints")
ns.AddonLoaded = originalLoaded
profile = { useShortestPath = true }
eq(routeOptions.useHearth.disabled(), true, "disabled state follows profile switch")
profile = { useShortestPath = false }
eq(routeOptions.useHearth.disabled(), false, "enabled state follows profile switch")
profile = { useShortestPath = true }
eq(routeSpec.defaults.useShortestPath, true, "Shortest Path enabled by default")
eq(shortestOption.get(), true, "Shortest Path option reads current profile")
shortestOption.set(nil, false)
eq(profile.useShortestPath, false, "Shortest Path option writes current profile")
routeSpec.launcher.onClick()
eq(assert(plannedSettings).useShortestPath, false, "disabled setting reaches planner")
profile = { useShortestPath = true }
eq(shortestOption.get(), true, "Shortest Path option follows profile switch")
routeSpec.launcher.onClick()
eq(assert(plannedSettings).useShortestPath, true, "new profile reaches planner")
routeSpec.launcher.onClick()
local expectedKeys = {}
for _, source in ipairs(RP.Sources()) do expectedKeys[#expectedKeys + 1] = source.key end
eq(table.concat(assert(plannedKeys), ","), table.concat(expectedKeys, ","), "launcher plans all sources")
RP.PlanSources, ns.Print = originalPlan, originalPrint
profile = { useShortestPath = false }

local group = Build()
ok(group.name:find("808080", 1, true), "group greyed")
ok(group.desc:find("^Requires:"), group.desc)
ok(group.desc:find("Questie", 1, true))
eq(group.args.requires.type, "description")
for key, arg in pairs(group.args) do
    if key ~= "requires" and key ~= "help" and key ~= "optional" then eq(arg.disabled, true, key .. " disabled") end
end
local desc = group.args.waypoints.desc
eq(type(desc), "function")
local text = desc()
eq(type(text), "string"); ok(text:find("^Requires: Questie"), text); ok(text:find("TomTom", 1, true))
eq(type(group.args.useHearth.desc), "string"); ok(group.args.useHearth.desc:find("^Requires:"))

loaded.Questie = true
group = Build()
eq(group.desc, ns.features.TurnInRoute.description, "Questie alone ungates the group")
eq(group.args.requires, nil)
eq(group.args.useHearth.disabled(), false)
local waypoints = group.args.waypoints
eq(type(waypoints.desc), "function")
text = waypoints.desc()
eq(type(text), "string"); ok(text:find("Requires: TomTom", 1, true))
eq(waypoints.disabled(), true, "waypoint select greyed without TomTom")

loaded.TomTom = true
group = Build()
text = group.args.waypoints.desc()
eq(type(text), "string"); ok(text:find("^Add keeps"), text)
eq(group.args.waypoints.disabled(), false)
ns.GetSettings = originalSettings

local pending, cancelled = {}, 0
ns.ShortestPath = {
    Available = function() return true end,
    Order = function(start, stops, done)
        eq(start.mapID, 1); eq(start.x, 0.2); eq(start.y, 0.3)
        pending[#pending + 1] = done
        return function() cancelled = cancelled + 1 end
    end,
}
_G.C_Map.GetBestMapForUnit = function() return 1 end
_G.C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.2, 0.3 end } end
local results = {}
local available = ns.ShortestPath.Available
ns.ShortestPath.Available = function() error("disabled SPF must not be queried") end
RP.PlanSources({ "x" }, { useShortestPath = false }, function(msg, didStart) results[#results + 1] = { msg, didStart } end)
eq(#results, 1, "disabled SPF completes with KLH fallback")
eq(results[1][2], true, "disabled SPF starts KLH guidance")
RP.Abort()
results = {}
ns.ShortestPath.Available = available
RP.PlanSources({ "x" }, {}, function(msg, didStart) results[#results + 1] = { msg, didStart } end)
eq(#results, 0, "planning waits for estimates")
RP.PlanSources({ "x" }, {}, function(msg, didStart) results[#results + 1] = { msg, didStart } end)
eq(cancelled, 1, "new request cancels old job")
pending[1](nil, "error")
eq(#results, 0, "stale completion ignored")
pending[2](nil, "error")
eq(#results, 1, "failed estimate completes once")
eq(results[1][2], true, "failed estimate starts fallback")
pending[2](nil, "error")
eq(#results, 1, "completion is once only")
RP.Abort()
local handed, response = 0, nil
ns.ShortestPath.Start = function(plan, _, done)
    handed = handed + 1
    response = done
    return function() cancelled = cancelled + 1 end
end
results = {}
RP.PlanSources({ "x" }, {}, function(msg, didStart) results[#results + 1] = { msg, didStart } end)
local planned = RP.Plan(RP.Collect({ "x" }), {})
pending[3](planned)
eq(handed, 1, "ordered plan enters ownership gate")
eq(#results, 0, "wait for ownership decision")
assert(response)(false, "declined")
eq(#results, 1, "decline starts fallback")
eq(results[1][2], true)
RP.Abort()
local update, submitted
Stub({
    CreateFrame = function() return { SetScript = function(_, _, fn) update = fn end } end,
    InCombatLockdown = function() return false end,
    ShortestPathForever = { API = {
        version = 1,
        Estimate = function() return 60 end,
        NavigateRoute = function(_, stops) submitted = stops; return true end,
        CurrentStop = function() return nil, "none" end,
        Journey = function() return nil, "none" end,
        JourneyState = function() return { busy = false } end,
        Cancel = function() return true end,
        Active = function() end,
        Ended = function() end,
        Subscribe = function() return function() end end,
    } },
})
addon("Modules/ShortestPath.lua")
results = {}
RP.PlanSources({ "x" }, {}, function(msg, didStart) results[#results + 1] = { msg, didStart } end)
while update do update() end
eq(results[1][2], true, "real SPF adapter starts route")
eq(submitted[1].title, "Nia")
ok(entries[1].text:find("Zone", 1, true), "zone rendered")
ok(entries[1].text:find("Q1", 1, true), "quest rendered")
local saved = charStore.turnInRoute.route
local stop = saved.legs[1].stop
eq(stop.kind, "stop"); eq(stop.zone, "Zone")
eq(stop.wx, 500); eq(stop.wy, 500); eq(stop.instance, 0)
eq(stop.quests[1], "Q1"); eq(stop.questIds[1], 1)
eq(saved.start.kind, "start"); eq(saved.start.wx, 0); eq(saved.start.wy, 0); eq(saved.start.instance, 0)
RP.Abort()
ns.ShortestPath = nil
for k, savedGlobal in pairs(touched) do _G[k] = savedGlobal[1] end
