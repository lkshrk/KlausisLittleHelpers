local charStore = {}
local savedGetSettings = ns.GetSettings
addon("Modules/TurnInRouteGraph.lua")
ns.IS_FOREVER = true
addon("Modules/RouteDraw.lua"); addon("Modules/RouteWaypoints.lua"); ns.CharData = function(key) charStore[key] = charStore[key] or {}; return charStore[key] end
addon("Modules/RoutePlanner.lua")
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
        GetPlayerMapPosition = function() return { GetXY = function() return 0.1, 0.1 end } end,
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

local pendingCallback, pendingCancelled
ns.ShortestPath = {
    Available = function() return true end,
    Order = function(_, _, done)
        pendingCallback = done
        return function() pendingCancelled = true end
    end,
}
RP.RegisterSource("pending", { title = "Pending", collect = function()
    return { { name = "Pending", mapID = 1, x = 0.5, y = 0.5, quests = { "Q" }, questIds = { 99 } } }
end })
local pendingDone = false
RP.PlanSources({ "pending" }, {}, function() pendingDone = true end)
RP.Abort()
ok(pendingCancelled, "abort cancels pending route planning without active legs")
pendingCallback(nil)
eq(pendingDone, false, "late planning callback cannot start a route after abort")
ns.ShortestPath = nil

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

local spStatus, watched, submissions, cancels = "empty", nil, {}, 0
local activeSettings = { useShortestPath = true, waypoints = "replace" }
ns.GetSettings = function() return activeSettings end
ns.ShortestPath = {
    Available = function() return true end,
    Status = function() return spStatus end,
    Watch = function(fn) watched = fn; return function() watched = nil end end,
    CancelOwned = function() if spStatus == "owned" then cancels = cancels + 1; spStatus = "empty"; return true end return false end,
    Order = function(_, _, done)
        local p = TwoLegs(); p.routed, p.total, p.unknown, p.unreachable = 3, 60, 2, 1
        done(p); return function() end
    end,
    Start = function(planToStart, _, done)
        submissions[#submissions + 1] = planToStart
        spStatus = "owned"
        done(true)
        return function() end
    end,
}
RP.Start(TwoLegs(), { waypoints = "add" })
local resultMessage
RP.PlanSources({ "pending" }, activeSettings, function(message) resultMessage = message end)
ok(resultMessage:find("1 unreachable", 1, true), "SPF success reports unreachable turn-ins")
ok(resultMessage:find("2 without a known", 1, true), "SPF success reports unknown turn-ins")
ok(watched ~= nil, "accepted journey is watched")
eq(RP.UsingShortestPath(), true, "accepted SPF journey owns guidance")
eq(next(valid), nil, "handoff removes KLH TomTom waypoints")
activeSettings.useShortestPath = false
if RP.SettingsChanged then RP.SettingsChanged() end
eq(RP.UsingShortestPath(), false, "disabling SPF leaves active guidance")
eq(cancels, 1, "disabling SPF cancels owned journey")
ok(next(valid) ~= nil, "disabling SPF restores configured KLH waypoints")
activeSettings.useShortestPath = true
RP.PlanSources({ "pending" }, activeSettings, function() end)
cancels = 0
local before = #submissions
spStatus = "pending"
assert(watched)("pending")
eq(RP.UsingShortestPath(), true, "owned loading retains SPF guidance")
Fire("QUEST_REMOVED", 2)
eq(#submissions, before, "held-stop update waits while SPF loads")
spStatus = "owned"
assert(watched)("owned")
eq(#submissions, before + 1, "held-stop update resumes once ownership is visible")
before = #submissions
Fire("QUEST_REMOVED", 1)
eq(#submissions, before + 1, "stop removal resubmits held stops")
eq(#submissions[#submissions].route, 1, "quest removal resubmits remaining stops")
RP.Abort()
eq(cancels, 1, "abort cancels owned SPF journey")
RP.PlanSources({ "pending" }, activeSettings, function() end)
local foreignWaypoint = TomTom:AddWaypoint(1, 0.7, 0.7, { title = "Other" })
spStatus = "foreign"
assert(watched)("foreign")
eq(valid[foreignWaypoint], nil, "fallback honors replace waypoint preference")
eq(RP.UsingShortestPath(), false, "foreign replacement switches to fallback")
ok(next(valid) ~= nil, "foreign replacement rebuilds KLH waypoints")
eq(cancels, 1, "foreign replacement is not cancelled")
RP.Abort()
RP.PlanSources({ "pending" }, activeSettings, function() end)
local obsoleteWatch = watched
spStatus = "pending"
RP.Abort()
eq(cancels, 1, "abort defers cancellation while owned journey loads")
assert(watched)("pending")
eq(cancels, 1, "pending notification does not cancel")
spStatus = "owned"
assert(watched)("owned")
eq(cancels, 2, "deferred abort cancels owned journey when visible")
RP.PlanSources({ "pending" }, activeSettings, function() end)
assert(obsoleteWatch)("empty")
eq(RP.UsingShortestPath(), true, "obsolete watch cannot disturb a newer journey")
local asyncDone, asyncCancelled
ns.ShortestPath.Start = function(_, _, done)
    asyncDone = done
    return function() asyncCancelled = true end
end
Fire("QUEST_REMOVED", 1)
RP.Abort()
ok(asyncCancelled, "abort cancels pending held-stop resubmission")
asyncDone(false)
eq(RP.Active(), false, "late resubmission cannot recreate aborted route")
local liveSettings = { useShortestPath = true }
local liveCallback, starts = nil, 0
ns.GetSettings = function() return liveSettings end
ns.ShortestPath.Order = function(_, _, done) liveCallback = done; return function() end end
ns.ShortestPath.Start = function() starts = starts + 1 end
RP.PlanSources({ "pending" }, liveSettings, function() end, function() return liveSettings end)
liveSettings = { useShortestPath = false }
local latePlan = TwoLegs(); latePlan.routed, latePlan.total = 3, 60
assert(liveCallback)(latePlan)
eq(starts, 0, "profile switch prevents late SPF submission")
RP.Abort()
local popupData, popupHidden
Stub({
    StaticPopupDialogs = {},
    StaticPopup_Show = function(_, _, _, data) popupData = data; return {} end,
    StaticPopup_Hide = function() popupHidden = true end,
})
ns.ShortestPath.Order = function(_, _, done) done(latePlan); return function() end end
local answered
ns.ShortestPath.Start = function(_, confirm, done)
    confirm({ owner = "Other", destination = "There" }, function(answer) answered = answer; done(false, "declined") end)
    return function() end
end
RP.PlanSources({ "pending" }, {}, function() end)
ok(popupData ~= nil, "foreign SPF journey prompts before replacement")
if popupData then
    _G.StaticPopupDialogs.KLH_ROUTE_REPLACE_SHORTEST_PATH.OnCancel(nil, popupData)
    eq(answered, false, "decline is passed to adapter")
end
RP.Abort()
popupData = nil
RP.PlanSources({ "pending" }, {}, function() end)
if popupData then
    _G.StaticPopupDialogs.KLH_ROUTE_REPLACE_SHORTEST_PATH.OnAccept(nil, popupData)
    eq(answered, true, "acceptance is passed to adapter")
end
RP.Abort()
local popupSettings = { useShortestPath = true }
answered = nil
popupData = nil
RP.PlanSources({ "pending" }, popupSettings, function() end, function() return popupSettings end)
popupSettings.useShortestPath = false
_G.StaticPopupDialogs.KLH_ROUTE_REPLACE_SHORTEST_PATH.OnAccept(nil, popupData)
eq(answered, false, "disabling SPF before confirmation never accepts replacement")
RP.Abort()
popupSettings = { useShortestPath = true }
local originalSettings = popupSettings
answered, popupData = nil, nil
RP.PlanSources({ "pending" }, originalSettings, function() end, function() return popupSettings end)
popupSettings = { useShortestPath = true }
_G.StaticPopupDialogs.KLH_ROUTE_REPLACE_SHORTEST_PATH.OnAccept(nil, popupData)
eq(answered, false, "profile switch before confirmation never accepts replacement")
RP.Abort()
popupData = nil
RP.PlanSources({ "pending" }, {}, function() end)
local oldPopup = popupData
Fire("QUEST_REMOVED", 99)
ok(popupHidden, "quest removal hides pending replacement confirmation")
RP.Abort()
ok(popupHidden, "abort hides pending replacement confirmation")
if oldPopup then
    answered = nil
    _G.StaticPopupDialogs.KLH_ROUTE_REPLACE_SHORTEST_PATH.OnAccept(nil, oldPopup)
    eq(answered, nil, "aborted confirmation cannot submit")
end
ns.ShortestPath = nil

local updates, journey, submittedRoutes, actualCancels = {}, nil, {}, 0
local actualAPI = { version = 2 }
actualAPI.Estimate = function(_, x, _, _, toX) return math.abs(x - toX) * 100 + 1 end
actualAPI.NavigateRoute = function(owner, stops)
    journey = { owner = owner, stops = stops }
    submittedRoutes[#submittedRoutes + 1] = stops
    return true
end
actualAPI.CurrentStop = function(owner)
    if journey and journey.owner == owner then return 1 end
    return nil, "none"
end
local loading = false
local watcher
actualAPI.Journey = function() if loading then return nil, "loading" end if journey then return journey end return nil, "none" end
actualAPI.JourneyState = function() return { busy = journey ~= nil, owner = journey and journey.owner, pending = loading } end
actualAPI.Cancel = function(owner)
    if journey and journey.owner == owner then journey = nil; actualCancels = actualCancels + 1; return true end
    return false
end
actualAPI.Active = function() return journey ~= nil end
actualAPI.Ended = function() return nil end
actualAPI.Subscribe = function(callback) watcher = callback; return function() watcher = nil end end
Stub({
    ShortestPathForever = { API = actualAPI },
    InCombatLockdown = function() return false end,
    CreateFrame = function()
        return { SetScript = function(_, script, fn) if script == "OnUpdate" then updates[1] = fn end end }
    end,
})
addon("Modules/ShortestPath.lua")
local function RunUpdates()
    local count = 0
    while updates[#updates] and count < 100 do updates[#updates](); count = count + 1 end
    ok(count < 100, "real SPF ordering completes")
end
RP.RegisterSource("integration", { collect = function()
    return {
        { name = "One", zone = "Zone", mapID = 1, x = 0.2, y = 0.2, quests = { "One" }, questIds = { 101 } },
        { name = "Two", zone = "Zone", mapID = 1, x = 0.3, y = 0.3, quests = { "Two" }, questIds = { 102 } },
    }
end })
local integrated = false
RP.PlanSources({ "integration" }, {}, function(_, started) integrated = started end)
eq(#submittedRoutes, 0, "real adapter orders across frames before submission")
RunUpdates()
ok(integrated, "real adapter and planner start route")
eq(#submittedRoutes[1], 2, "real adapter submits every stop")
ok(submittedRoutes[1][1].hold and submittedRoutes[1][2].hold, "submitted stops are held")
eq(RP.UsingShortestPath(), true, "real SPF journey owns route")
eq(next(valid), nil, "real SPF journey suppresses KLH TomTom waypoints")
local savedSPRoute, savedJourney = charStore.turnInRoute.route, journey
RP.Abort()
charStore.turnInRoute.route, journey = savedSPRoute, savedJourney
actualCancels = 0
ns.GetSettings = function() return { useShortestPath = true, waypoints = "add" } end
RP.Restore()
eq(RP.UsingShortestPath(), true, "restore retains enabled owned SPF journey")
eq(actualCancels, 0, "restore does not cancel owned SPF journey")
eq(next(valid), nil, "restore does not add fallback waypoints for SPF")
RP.Abort()
charStore.turnInRoute.route, journey = savedSPRoute, savedJourney
loading = true
RP.Restore()
eq(RP.UsingShortestPath(), true, "restore retains pending SPF journey")
Fire("QUEST_REMOVED", 101)
eq(#submittedRoutes, 1, "pending restore defers journey update")
loading = false
watcher()
eq(#submittedRoutes, 2, "pending restore updates once journey loads")
eq(#submittedRoutes[2], 1, "restored journey update excludes removed quest")
RP.Abort()
savedSPRoute.shortestPath = nil
charStore.turnInRoute.route, journey = savedSPRoute, savedJourney
actualCancels = 0
local restoreSettings = { useShortestPath = false, waypoints = "add" }
ns.GetSettings = function() return restoreSettings end
RP.Restore()
eq(actualCancels, 1, "restore cancels surviving owned SPF journey when disabled")
ok(next(valid) ~= nil, "restored SPF route gains KLH waypoints")
ok(entries[1] and #entries[1].data.steps > 0, "restored SPF route is replanned for KLH")
RP.Abort()
charStore.turnInRoute.route = savedSPRoute
savedSPRoute.shortestPath = true
journey = { owner = "Other", goal = { map = 1, x = 0.4, y = 0.4 } }
RP.Restore()
eq(journey.owner, "Other", "restoring SPF route never cancels foreign journey")
eq(actualCancels, 1, "foreign restore does not call owned cancellation")
RP.Abort()
journey = nil
actualCancels = 0
RP.PlanSources({ "integration" }, {}, function() end)
RunUpdates()
wipe(submittedRoutes)
Fire("QUEST_REMOVED", 101)
eq(#submittedRoutes, 1, "quest removal resubmits through real adapter")
eq(#submittedRoutes[1], 1, "resubmission retains remaining stop")
RP.Abort()
eq(actualCancels, 1, "abort cancels real owned journey")
updates = {}
RP.PlanSources({ "integration" }, {}, function() error("cancelled integration completed") end)
RP.Abort()
RunUpdates()
eq(#submittedRoutes, 1, "abort pending real ordering prevents submission")
updates = {}
local staleDone = false
RP.PlanSources({ "integration" }, {}, function() staleDone = true end)
Fire("QUEST_TURNED_IN", 101)
RunUpdates()
eq(#submittedRoutes, 1, "quest event cancels stale pending SPF ordering")
eq(staleDone, false, "cancelled stale ordering does not install route")
local oldGet, oldChar, oldPrint = ns.GetSettings, ns.CharData, ns.Print
local actualProfile = { features = {} }
Stub({
    GetBuildInfo = function() return nil, nil, nil, 16001 end,
    CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end,
    LibStub = function(name) if name == "AceDB-3.0" then return { New = function() return { profile = actualProfile, char = charStore } end } end end,
})
addon("Core/Core.lua")
addon("Core/OptionsModel.lua")
addon("Modules/TurnInRoute.lua")
local routeFeature = assert(ns.features.TurnInRoute)
local optionRoot = { type = "group", args = { route = { type = "group", name = "Route", args = routeFeature.options() } } }
local page = ns.OptionsModel.Page(optionRoot, "route")
local toggle = assert(find(page.controls, "key", "useShortestPath"))
eq(toggle.get(), true, "real profile defaults to SPF")
toggle.set(false)
eq(toggle.get(), false, "settings adapter records disabled SPF")
eq(ns.GetSettings("TurnInRoute").useShortestPath, false, "real profile retains false")
RP.Abort()
local countBefore = #submittedRoutes
local oldArrow = TomTom.SetCrazyArrow
TomTom.SetCrazyArrow = function(self, uid)
    oldArrow(self, uid)
    actualAPI.NavigateRoute("TomTom", { { map = uid[1], x = uid[2], y = uid[3] } })
end
ns.TurnInRoute.Plan({ "integration" })
TomTom.SetCrazyArrow = oldArrow
RunUpdates()
eq(#submittedRoutes, countBefore + 1, "SPF TomTom follower independently starts guidance")
eq(journey and journey.owner, "TomTom", "SPF follower owns the new journey")
eq(RP.UsingShortestPath(), false, "toggle then abort then route uses KLH")
RP.Abort()
ns.GetSettings, ns.CharData, ns.Print = oldGet, oldChar, oldPrint
ns.ShortestPath = nil

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
eq(charStore.turnInRoute.route.legs[1].steps[1].passed, true, "hand-removed transit counts as passed")

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
eq(charStore.turnInRoute.route, nil, "and clears the saved route")
eq(printed[1], "Turn-in route complete.")

local function Fly(seconds, landX)
    charStore = {}
    onTaxi = true
    hooks.TakeTaxiNode(2)
    onTaxi = false
    now = now + seconds
    player.wx, player.wy = landX, 0
    Fire("PLAYER_CONTROL_GAINED")
    return charStore.turnInRoute and charStore.turnInRoute.taxiSpeed
end
ok(math.abs((Fly(9980 / 40, 9990) or 0) - 40) < 1e-9, "40 yd/s at the destination is learned")
eq(Fly(9980 / 100, 9990), nil, "100 yd/s is above the clamp")
eq(Fly(9980 / 10, 9990), nil, "10 yd/s is below the clamp")
eq(Fly(9980 / 40, 5000), nil, "landing away from the destination is ignored")
ok(math.abs((Fly(9980 / 40, 9990 + 60) or 0) - 40) < 1e-9, "landing within the radius counts")

charStore = {}
local function Mount(speed, taxi)
    mounted, runSpeed, onTaxi = true, speed, taxi == true
    Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
    RunTimers()
    onTaxi = false
    return charStore.turnInRoute.mountSpeed
end
eq(Mount(14), 14)
eq(Mount(30), 30, "a sprint raises the speed for now")
for _ = 1, 4 do Mount(14) end
eq(Mount(14), 14, "and ages out after five samples")
eq(Mount(60, true), 14, "taxi speed is not a mount sample")
mounted, runSpeed = false, 50
Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
RunTimers()
eq(charStore.turnInRoute.mountSpeed, 14, "not mounted, no sample")

ns.GetSettings = savedGetSettings
for k, saved in pairs(touched) do _G[k] = saved[1] end
