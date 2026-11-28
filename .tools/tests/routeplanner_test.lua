local charStore = {}
addon("Modules/TurnInRouteGraph.lua"); addon("Modules/RouteDraw.lua"); addon("Modules/RouteWaypoints.lua"); ns.CharData = function(key) charStore[key] = charStore[key] or {}; return charStore[key] end
addon("Modules/RoutePlanner.lua")
local RP = ns.RoutePlanner
local a = { name = "N", mapID = 1, x = 0.5, y = 0.5, quests = { "Q1" }, questIds = { 1 } }
local b = { name = "N", mapID = 1, x = 0.5, y = 0.5, quests = { "W1" }, questIds = { 9 } }
local m = RP.MergeStops({ { a }, { b } })
eq(#m, 1); eq(#m[1].questIds, 2)
eq(m[1].quests[2], "W1"); eq(#a.questIds, 1, "sources keep their stops")
local c = { name = "C", mapID = 1, x = 0.5004, y = 0.4996, quests = { "Q2" }, questIds = { 2 } }
local d = { name = "D", mapID = 2, x = 0.5, y = 0.5, quests = { "Q3" }, questIds = { 3 } }
m = RP.MergeStops({ { a, d }, { c } })
eq(#m, 2); eq(#m[1].questIds, 2, "same spot within 0.1 %"); eq(m[2].mapID, 2)
RP.RegisterSource("bad", { title = "Bad", order = 2, collect = function() error("boom") end })
RP.RegisterSource("good", { title = "Good", order = 1, collect = function() return { a }, 2 end })
local stops, unknown, count, failed = RP.Collect({ "good", "bad" })
eq(#stops, 1); eq(unknown, 2); eq(count, 1); eq(failed[1], "Bad")
eq(RP.Sources()[1].key, "good"); eq(RP.Sources()[2].title, "Bad")
eq(#RP.Collect({ "missing" }), 0)
eq(table.concat(RP.WaypointSteps("add", true), ","), "remove-route,add")
eq(table.concat(RP.WaypointSteps("add", false), ","), "add")
eq(table.concat(RP.WaypointSteps("replace", true), ","), "remove-route,clear-all,add")
eq(table.concat(RP.WaypointSteps("replace", false), ","), "clear-all,add")
eq(table.concat(RP.WaypointSteps(false, true), ","), "remove-route")
eq(#RP.WaypointSteps(false, false), 0)
eq(RP.Active(), false)

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
    RemoveWaypoint = function(_, uid) valid[uid] = nil; registry[1][uid.id] = nil; log[#log + 1] = "remove:" .. uid.id end,
    IsValidWaypoint = function(_, uid) log[#log + 1] = "valid"; return valid[uid] == true end,
    waypoints = registry,
    ClearAllWaypoints = function() log[#log + 1] = "hide-only" end,
    DefaultCallbacks = function() log[#log + 1] = "callbacks"; return { distance = {} } end,
    SetCrazyArrow = function() log[#log + 1] = "arrow" end,
}
local frame = { RegisterEvent = function() end, SetScript = function() end }
local saved = {}
for k, v in pairs({
    TomTom = TomTom, WorldMapFrame = { IsShown = function() return false end },
    C_Timer = { After = function() end }, CreateFrame = function() return frame end,
    hooksecurefunc = function() end, CopyTable = function(t) local copy = {} for k2, v2 in pairs(t) do copy[k2] = v2 end return copy end,
    wipe = function(t) for k2 in pairs(t) do t[k2] = nil end return t end, KLH_CharDB = {},
}) do
    saved[k] = rawget(_G, k); _G[k] = v
end
ns.CreateListWindow = function() return { SetEntries = function() end } end
ns.Print = function() end
RP.Init({ hbd = {}, onRefresh = function() end })
local function OnePlan()
    local stop = { kind = "stop", name = "N", zone = "Z", mapID = 1, x = 0.5, y = 0.5, quests = { "Q" }, questIds = { 1 } }
    return { start = { kind = "start", name = "Start" }, route = { { stop = stop, steps = {} } } }
end
local function Kinds()
    local out = {}
    for _, entry in ipairs(log) do
        if entry:sub(1, 7) == "remove:" then out[#out + 1] = "remove" elseif entry == "clear-all" or entry == "add" then out[#out + 1] = entry end
    end
    return table.concat(out, ",")
end
local function Removed()
    local out = {}
    for _, entry in ipairs(log) do
        if entry:sub(1, 7) == "remove:" then out[#out + 1] = tonumber(entry:sub(8)) end
    end
    return out
end
local function Same(x, y)
    table.sort(x); table.sort(y)
    return table.concat(x, ",") == table.concat(y, ",")
end
eq(RP.Start(OnePlan(), { waypoints = "add" }), 1); eq(RP.Active(), true)
local userUid = { 1, id = 99 }
registry[1][99] = userUid; valid[userUid] = true
local previous = { nextUid }
wipe(log)
RP.Start(OnePlan(), { waypoints = "replace" })
eq(Kinds(), "remove,remove,add", "replace removes the route, then every remaining waypoint, then adds")
local removed = Removed()
ok(Same(removed, { previous[1], 99 }), "replace removes the previous start's uid and the user's")
eq(registry[1][99], nil, "user waypoint removed from TomTom.waypoints")
for _, entry in ipairs(log) do ok(entry ~= "hide-only", "never ClearAllWaypoints") end
previous = { nextUid }
wipe(log)
RP.Start(OnePlan(), { waypoints = "add" })
eq(Kinds(), "remove,add", "add never clears")
ok(Same(Removed(), previous), "add removes only the previous start's uid")
previous = { nextUid }
wipe(log)
RP.Start(OnePlan(), { waypoints = false })
eq(Kinds(), "remove", "false still removes the route's own waypoints")
ok(Same(Removed(), previous), "false removes the previous start's uid")
eq(RP.Start(OnePlan(), { waypoints = "add" }), 1)
_G.TomTom = nil
wipe(log)
RP.Start(OnePlan(), { waypoints = "replace" })
RP.Abort()
eq(#log, 0, "no TomTom, no calls")
eq(table.concat(RP.RestoreKeep({ 5, 6, 7 }, function(id) return id == 6 end), ","), "1,3", "restore drops only turned-in quests")
eq(#RP.RestoreKeep({}, function() return false end), 0)
for k, v in pairs(saved) do _G[k] = v end
