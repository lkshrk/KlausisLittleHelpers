addon("Modules/TurnInRouteGraph.lua")
ns.IS_FOREVER = true
addon("Modules/RouteDraw.lua"); addon("Modules/RouteWaypoints.lua"); addon("Modules/RoutePlanner.lua")
local RP = ns.RoutePlanner

local touched = {}
local function Stub(values)
    for k, v in pairs(values) do
        if touched[k] == nil then touched[k] = { rawget(_G, k) } end
        _G[k] = v
    end
end

local scripts, hooks, timers = {}, {}, {}
local frame = setmetatable({ SetScript = function(_, name, fn) scripts[name] = fn end },
    { __index = function() return function() end end })
local function RunTimers()
    local due = timers
    timers = {}
    for _, fn in ipairs(due) do fn() end
end

local valid, nextUid, arrows, callbacks = {}, 0, {}, {}
local throwNext = false
local registry = { [1] = {} }
local TomTom = {
    AddWaypoint = function(_, mapID, x, y, opts)
        local key = mapID .. ":" .. x .. ":" .. y .. ":" .. tostring(opts.title)
        if registry[1][key] then return registry[1][key] end
        nextUid = nextUid + 1
        local uid = { mapID, x, y, title = opts.title, id = nextUid, key = key }
        valid[uid] = true
        registry[1][key] = uid
        return uid
    end,
    RemoveWaypoint = function(_, uid)
        if not valid[uid] then return end
        if throwNext then throwNext = false; error("boom") end
        valid[uid] = nil
        registry[1][uid.key] = nil
        for _, fn in ipairs(callbacks.WaypointRemoved or {}) do fn("WaypointRemoved", uid) end
    end,
    IsValidWaypoint = function(_, uid) return valid[uid] == true end,
    waypoints = registry,
    DefaultCallbacks = function() return { distance = {} } end,
    SetCrazyArrow = function(_, uid) arrows[#arrows + 1] = uid end,
    RegisterCallback = function(owner, event, fn)
        ok(owner ~= nil, "callback owner")
        callbacks[event] = callbacks[event] or {}
        table.insert(callbacks[event], fn)
    end,
}

local player = { wx = 0, wy = 0 }
local now, onTaxi, mounted, runSpeed = 100, false, false, 7
local faction = { [10] = 2, [20] = 2 }
local printed = {}
Stub({
    TomTom = TomTom, KLH_CharDB = {},
    LibStub = function() return nil end,
    WorldMapFrame = { IsShown = function() return false end },
    C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end },
    CreateFrame = function() return frame end,
    hooksecurefunc = function(name, fn) hooks[name] = fn end,
    CopyTable = function(t) local copy = {} for k, v in pairs(t) do copy[k] = v end return copy end,
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
    C_QuestLog = { IsQuestFlaggedCompleted = function() return false end },
    GetUnitSpeed = function() return 0, runSpeed end,
    IsMounted = function() return mounted end,
    UnitOnTaxi = function() return onTaxi end,
    GetTime = function() return now end,
    UnitFactionGroup = function() return "Alliance" end,
    Enum = { UIMapType = { Continent = 2 }, FlightPathFaction = { Horde = 0, Alliance = 1, Neutral = 2 } },
    C_Map = {
        GetBestMapForUnit = function() return 1414 end,
        GetMapInfo = function(id)
            if id == 1414 then return { mapID = 1414, name = "Kalimdor", mapType = 2 } end
            return { mapID = id, name = "Zone", mapType = 3, parentMapID = 1414 }
        end,
    },
    C_TaxiMap = {
        GetTaxiNodesForMap = function()
            return {
                { nodeID = 10, name = "A", position = { x = 0.01, y = 0 }, faction = faction[10] },
                { nodeID = 20, name = "B", position = { x = 9.99, y = 0 }, faction = faction[20] },
            }
        end,
        GetAllTaxiNodes = function()
            return {
                { slotIndex = 1, nodeID = 10, position = { x = 0.01, y = 0 } },
                { slotIndex = 2, nodeID = 20, position = { x = 9.99, y = 0 } },
            }
        end,
    },
    GetTaxiMapID = function() return 1414 end,
    GetNumRoutes = function() return 1 end,
    TaxiGetNodeSlot = function(_, _, isFrom) return isFrom and 1 or 2 end,
})
local hbd = {
    GetWorldCoordinatesFromZone = function(_, x, y, mapID) if mapID then return x * 1000, y * 1000, 0 end end,
    GetPlayerWorldPosition = function() return player.wx, player.wy, 0 end,
    GetAllMapIDs = function() return {} end,
    GetZoneCoordinatesFromWorld = function() end,
}
local entries = {}
ns.CreateListWindow = function() return { SetEntries = function(_, list) entries = list end } end
ns.Print = function(msg) printed[#printed + 1] = msg end
ns.Transports = {}
ns.TaxiPaths = { [10] = { [20] = { 9980, 0, {} } } }
RP.Init({ hbd = hbd, onRefresh = function() end })
ok(scripts.OnEvent ~= nil, "event handler captured")
ok(hooks.TakeTaxiNode ~= nil, "taxi hook captured")
ok(callbacks.WaypointRemoved and callbacks.WaypointsReloaded, "TomTom callbacks registered")
timers = {}
local function Fire(event, ...) scripts.OnEvent(frame, event, ...) end

local function Kinds(plan)
    local kinds = {}
    for _, step in ipairs(plan.route[1].steps) do kinds[#kinds + 1] = step.kind end
    return table.concat(kinds, ",")
end
local function Far() return { { name = "Far", mapID = 1, x = 10, y = 0, quests = { "Q" }, questIds = { 1 } } } end
local plan = RP.Plan(Far(), {})
eq(Kinds(plan), "ground,flight,ground", "two taxi nodes: walk to A, fly to B, walk on")
eq(table.concat(plan.route[1].steps[2].hops, ","), "10,20")
faction[20] = 0
eq(Kinds(RP.Plan(Far(), {})), "ground", "Horde-only node excluded for Alliance")
faction[20] = 1
eq(Kinds(RP.Plan(Far(), {})), "ground,flight,ground", "Alliance node allowed for Alliance")
faction[20] = 2

local function Point(kind, name, x, y)
    return { kind = kind, name = name, zone = "Zone", mapID = 1, x = x, y = y, wx = x * 1000, wy = y * 1000, instance = 0 }
end
local function Leg(name, x, ids)
    local stop = Point("stop", name, x, 0)
    stop.questIds, stop.quests = ids, {}
    for i, id in ipairs(ids) do stop.quests[i] = "Q" .. id end
    return {
        stop = stop,
        steps = { { kind = "flight", from = Point("taxi", "A", 0.01, 0), to = Point("taxi", "B", 9.99, 0), hops = { 10, 20 } } },
    }
end
local function TwoLegs()
    return { start = Point("start", "Start", 0, 0), route = { Leg("Nia", 9.5, { 1 }), Leg("Bo", 9.7, { 2, 3 }) } }
end

eq(RP.Start(TwoLegs(), { waypoints = "add" }), 4, "two transits and two stops")
local one, two = entries[1].data, entries[2].data
ok(one.transit[1].uid ~= two.transit[1].uid, "same flight in two legs keeps two waypoints")
ok(one.transit[1].uid.title:find("^1%. Fly to B"), one.transit[1].uid.title)
ok(two.transit[1].uid.title:find("^2%. Fly to B"), two.transit[1].uid.title)
eq(arrows[#arrows], one.transit[1].uid, "arrow on the first transit")
local arrowCount = #arrows

Fire("QUEST_TURNED_IN", 2)
eq(#entries, 2, "partial turn-in keeps both legs")
eq(#arrows, arrowCount, "a refresh with the same first leg leaves a hand-pointed arrow alone")

TomTom:RemoveWaypoint(one.uid)
RunTimers()
eq(RP.Active(), true, "removing a stop waypoint by hand keeps the route")
eq(#entries, 2, "and keeps the leg"); eq(one.uid, nil, "leg forgets the removed uid")
TomTom:RemoveWaypoint(one.transit[1].uid)
RunTimers()
eq(one.transit[1].uid, nil)
eq(_G.KLH_CharDB.turnInRoute.route.legs[1].steps[1].passed, true, "hand-removed transit counts as passed")

Fire("QUEST_TURNED_IN", 1)
eq(#entries, 1, "turning in the first stop drops its leg")
eq(arrows[#arrows], two.transit[1].uid, "first leg changed: arrow moves on")

wipe(printed)
RP.Abort()
eq(RP.Active(), false)
eq(#printed, 1, "own removals do not re-enter the route"); eq(printed[1], "Turn-in route aborted.")

RP.Start(TwoLegs(), { waypoints = "add" })
one = entries[1].data
local oldTransit = one.transit[1].uid
local burst = {}
for uid in pairs(valid) do burst[#burst + 1] = uid end
for _, uid in ipairs(burst) do
    valid[uid] = nil
    registry[1][uid.key] = nil
    for _, fn in ipairs(callbacks.WaypointRemoved) do fn("WaypointRemoved", uid) end
end
for _, fn in ipairs(callbacks.WaypointsReloaded) do fn("WaypointsReloaded") end
RunTimers()
eq(one.steps[1].passed, nil, "a reload burst does not mark transits passed")
eq(RP.Active(), true)
ok(one.transit[1] and one.transit[1].uid ~= oldTransit and valid[one.transit[1].uid], "reload re-adds the transit waypoint")
ok(one.uid and valid[one.uid], "reload re-adds the stop waypoint")
TomTom:RemoveWaypoint(one.transit[1].uid)
RunTimers()
eq(one.steps[1].passed, true, "a lone removal after a reload still counts as passed")
RP.Abort()

RP.Start(TwoLegs(), { waypoints = "add" })
throwNext = true
RP.Abort()
eq(throwNext, false, "RemoveWaypoint was attempted and threw")
RP.Start(TwoLegs(), { waypoints = "add" })
one = entries[1].data
TomTom:RemoveWaypoint(one.transit[1].uid)
RunTimers()
eq(one.steps[1].passed, true, "ownRemoval resets after a throwing RemoveWaypoint")
RP.Abort()

TomTom.waypoints = "broken"
RP.Start(TwoLegs(), { waypoints = "replace" })
eq(RP.Active(), true, "replace survives a non-table TomTom.waypoints")
TomTom.waypoints = { [1] = "broken" }
RP.Start(TwoLegs(), { waypoints = "replace" })
eq(RP.Active(), true, "replace survives non-table entries")
TomTom.waypoints = registry
RP.Abort()

RP.Start({ start = Point("start", "Start", 0, 0), route = { Leg("Nia", 9.5, { 7 }) } }, { waypoints = false })
eq(RP.Active(), true)
wipe(printed)
Fire("QUEST_TURNED_IN", 7)
eq(RP.Active(), false, "last turn-in ends the route")
eq(_G.KLH_CharDB.turnInRoute.route, nil, "and clears the saved route")
eq(printed[1], "Turn-in route complete.")

local function Fly(seconds, landX)
    _G.KLH_CharDB = {}
    onTaxi = true
    hooks.TakeTaxiNode(2)
    onTaxi = false
    now = now + seconds
    player.wx, player.wy = landX, 0
    Fire("PLAYER_CONTROL_GAINED")
    return _G.KLH_CharDB.turnInRoute and _G.KLH_CharDB.turnInRoute.taxiSpeed
end
ok(math.abs((Fly(9980 / 40, 9990) or 0) - 40) < 1e-9, "40 yd/s at the destination is learned")
eq(Fly(9980 / 100, 9990), nil, "100 yd/s is above the clamp")
eq(Fly(9980 / 10, 9990), nil, "10 yd/s is below the clamp")
eq(Fly(9980 / 40, 5000), nil, "landing away from the destination is ignored")
ok(math.abs((Fly(9980 / 40, 9990 + 60) or 0) - 40) < 1e-9, "landing within the radius counts")

_G.KLH_CharDB = {}
local function Mount(speed, taxi)
    mounted, runSpeed, onTaxi = true, speed, taxi == true
    Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
    RunTimers()
    onTaxi = false
    return _G.KLH_CharDB.turnInRoute.mountSpeed
end
eq(Mount(14), 14)
eq(Mount(30), 30, "a sprint raises the speed for now")
for _ = 1, 4 do Mount(14) end
eq(Mount(14), 14, "and ages out after five samples")
eq(Mount(60, true), 14, "taxi speed is not a mount sample")
mounted, runSpeed = false, 50
Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
RunTimers()
eq(_G.KLH_CharDB.turnInRoute.mountSpeed, 14, "not mounted, no sample")

for k, saved in pairs(touched) do _G[k] = saved[1] end
