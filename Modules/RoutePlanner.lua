local _, ns = ...
local G = ns.RouteGraph

local RP = {}
ns.RoutePlanner = RP

local KEY = "TurnInRoute"
local WALK_SPEED = 7
local GROUND_DETOUR = 1.3
local TAXI_SPEED = 32
local BOAT_SPEED = 20
local MIN_TIMED_FLIGHT = 20
local FLIGHT_OVERHEAD = 20
local HEARTHSTONE = 6948
local RESTORE_DELAY = 3
local MOUNT_SAMPLES = 5
local LANDING_RADIUS = 100
local POINT_FIELDS = { "kind", "name", "zone", "mapID", "x", "y", "wx", "wy", "instance" }
local HINT = "Click: point the TomTom arrow here. Ctrl+click: drop this stop."

local V, W = ns.RouteView, ns.RouteWaypoints
local HBD
local window
local sources = {}
local legs = {}
local continentOfInstance = {}
local routeStart
local useWaypoints = false
local flightPlan
local shortestPath = false
local pendingUpdate = false
local unwatch, cancelUpdate, deferredUnwatch
local routeGeneration, updateGeneration = 0, 0
local fallbackSettings = {}
local planGeneration, cancelPlan = 0, nil
local UpdateShortestPath, LeaveShortestPath, Fallback, WatchShortestPath
local CloseConfirmation
local confirmPopup
local POPUP = "KLH_ROUTE_REPLACE_SHORTEST_PATH"

CloseConfirmation = function()
    if not confirmPopup then return end
    confirmPopup = nil
    if _G.StaticPopup_Hide then _G.StaticPopup_Hide(POPUP) end
end

local function ConfirmReplacement(_, answer)
    CloseConfirmation()
    if not (_G.StaticPopupDialogs and _G.StaticPopup_Show) then answer(false); return end
    _G.StaticPopupDialogs[POPUP] = _G.StaticPopupDialogs[POPUP] or {
        text = "Replace the current Shortest Path journey with this turn-in route?",
        button1 = _G.YES or "Yes", button2 = _G.NO or "No",
        OnAccept = function(_, data) if data then data.reply(true) end end,
        OnCancel = function(_, data) if data then data.reply(false) end end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    local data = {}
    data.reply = function(accepted)
        if confirmPopup ~= data then return end
        confirmPopup = nil
        answer(accepted)
    end
    confirmPopup = data
    if not _G.StaticPopup_Show(POPUP, nil, nil, data) then
        confirmPopup = nil
        answer(false)
    end
end

function RP.UsingShortestPath()
    return shortestPath
end

local function LocationKey(stop)
    return tostring(stop.mapID) .. ":" .. math.floor((stop.x or 0) * 1000 + 0.5) .. ":" .. math.floor((stop.y or 0) * 1000 + 0.5)
end

function RP.MergeStops(lists)
    local merged, byLocation = {}, {}
    for _, list in ipairs(lists) do
        for _, stop in ipairs(list) do
            local key = LocationKey(stop)
            local into = byLocation[key]
            if not into then
                into = {}
                for field, value in pairs(stop) do into[field] = value end
                into.quests, into.questIds = {}, {}
                byLocation[key] = into
                merged[#merged + 1] = into
            end
            for k, id in ipairs(stop.questIds or {}) do
                into.questIds[#into.questIds + 1] = id
                into.quests[#into.quests + 1] = stop.quests and stop.quests[k] or ("Quest " .. id)
            end
        end
    end
    return merged
end

function RP.RegisterSource(key, spec)
    sources[key] = { key = key, title = spec.title or key, order = spec.order or 0, collect = spec.collect }
end

function RP.Sources()
    local list = {}
    for _, source in pairs(sources) do list[#list + 1] = { key = source.key, title = source.title, order = source.order } end
    table.sort(list, function(x, y)
        if x.order ~= y.order then return x.order < y.order end
        return x.key < y.key
    end)
    return list
end

function RP.Collect(keys)
    local lists, unknown, failed = {}, 0, {}
    for _, key in ipairs(keys) do
        local source = sources[key]
        if source then
            local good, stops, missing = pcall(source.collect)
            if good then
                lists[#lists + 1] = type(stops) == "table" and stops or {}
                unknown = unknown + (tonumber(missing) or 0)
            else
                failed[#failed + 1] = source.title
                local handler = _G.geterrorhandler
                if handler then handler()(stops) end
            end
        end
    end
    local merged, count = RP.MergeStops(lists), 0
    for _, stop in ipairs(merged) do count = count + #stop.questIds end
    return merged, unknown, count, failed
end

function RP.WaypointSteps(mode, hasOldRoute)
    local steps = {}
    if hasOldRoute then steps[#steps + 1] = "remove-route" end
    if mode ~= "add" and mode ~= "replace" then return steps end
    if mode == "replace" then steps[#steps + 1] = "clear-all" end
    steps[#steps + 1] = "add"
    return steps
end

function RP.Active()
    return #legs > 0
end

local function CharData()
    return ns.CharData("turnInRoute")
end

local function Plain(value)
    local isSecret = _G.issecretvalue
    if type(value) ~= "number" or (isSecret and isSecret(value)) then return nil end
    return value
end

local function RunSpeed()
    local _, run = GetUnitSpeed("player")
    return Plain(run) or 0
end

local function RecordMountSpeed()
    if not (IsMounted() and not UnitOnTaxi("player")) then return end
    local data, run = CharData(), RunSpeed()
    if run <= 0 then return end
    if type(data.mountSamples) ~= "table" then data.mountSamples = {} end
    local samples = data.mountSamples
    samples[#samples + 1] = run
    while #samples > MOUNT_SAMPLES do table.remove(samples, 1) end
    data.mountSpeed = math.max(unpack(samples))
end

local function GroundSpeed()
    RecordMountSpeed()
    return math.max(WALK_SPEED, RunSpeed(), CharData().mountSpeed or 0)
end

local function TaxiSpeed()
    return CharData().taxiSpeed or TAXI_SPEED
end

local function LandedAt(plan)
    local wx, wy, instance = HBD:GetPlayerWorldPosition()
    local dest = plan.destination
    if not (wx and dest and dest.instance == instance) then return false end
    local dx, dy = wx - dest.wx, wy - dest.wy
    return dx * dx + dy * dy <= LANDING_RADIUS * LANDING_RADIUS
end

local function OnLanded()
    local plan = flightPlan
    flightPlan = nil
    if not (plan and plan.started) or not LandedAt(plan) then return end
    local flown = GetTime() - plan.started - plan.delay
    if flown < MIN_TIMED_FLIGHT then return end
    local speed = plan.yards / flown
    if speed < 15 or speed > 80 then return end
    local data = CharData()
    local samples = math.min(data.taxiSamples or 0, 9)
    data.taxiSpeed = ((data.taxiSpeed or speed) * samples + speed) / (samples + 1)
    data.taxiSamples = samples + 1
end

local function WaitForTakeoff(tries)
    local plan = flightPlan
    if not plan or plan.started then return end
    if UnitOnTaxi("player") then
        plan.started = GetTime()
    elseif tries > 0 then
        C_Timer.After(0.5, function() WaitForTakeoff(tries - 1) end)
    else
        flightPlan = nil
    end
end

local function OnTakeTaxiNode(slot)
    flightPlan = nil
    local mapID = GetTaxiMapID()
    local nodeAt, nodeBySlot = {}, {}
    for _, node in ipairs(mapID and C_TaxiMap.GetAllTaxiNodes(mapID) or {}) do
        nodeAt[node.slotIndex], nodeBySlot[node.slotIndex] = node.nodeID, node
    end
    local yards, delay = 0, 0
    for route = 1, GetNumRoutes(slot) do
        local from, to = nodeAt[TaxiGetNodeSlot(slot, route, true)], nodeAt[TaxiGetNodeSlot(slot, route, false)]
        local path = from and to and ns.TaxiPaths[from] and ns.TaxiPaths[from][to]
        if not path then return end
        yards, delay = yards + path[1], delay + path[2]
    end
    local target = nodeBySlot[slot]
    local position = target and target.position
    local wx, wy, instance
    if position then wx, wy, instance = HBD:GetWorldCoordinatesFromZone(position.x, position.y, mapID) end
    if yards > 0 and wx then
        flightPlan = { yards = yards, delay = delay, destination = { wx = wx, wy = wy, instance = instance } }
        WaitForTakeoff(20)
    end
end

local function OnHearthBound()
    local wx, wy, instance = HBD:GetPlayerWorldPosition()
    if wx then CharData().bind = { wx = wx, wy = wy, instance = instance, name = GetBindLocation() } end
end

local function HearthReady()
    local bind = CharData().bind
    if type(bind) ~= "table" or not bind.wx or bind.name ~= GetBindLocation() then return nil end
    if (Plain(C_Item.GetItemCount(HEARTHSTONE)) or 0) < 1 then return nil end
    local start, duration = C_Container.GetItemCooldown(HEARTHSTONE)
    start, duration = Plain(start), Plain(duration)
    if not (start and duration) then return nil end
    if start > 0 and start + duration > GetTime() then return nil end
    return bind
end

local function ShortcutFacts(opts)
    local known, reagents = {}, {}
    local side = UnitFactionGroup("player") == "Horde" and "H" or "A"
    if not (opts.hearth or opts.teleports) then
        return { knownSpells = known, reagents = reagents, side = side }
    end
    for _, teleport in ipairs(ns.Teleports or {}) do
        known[teleport.spellID] = C_SpellBook.IsSpellKnown(teleport.spellID) == true
        if reagents[teleport.reagent] == nil then
            reagents[teleport.reagent] = Plain(C_Item.GetItemCount(teleport.reagent)) or 0
        end
    end
    return { hearth = HearthReady(), knownSpells = known, reagents = reagents, side = side }
end

local function MapName(uiMapID)
    local info = uiMapID and C_Map.GetMapInfo(uiMapID)
    return info and info.name or "?"
end

local function ContinentOf(uiMapID)
    local info = uiMapID and C_Map.GetMapInfo(uiMapID)
    while info do
        if info.mapType == Enum.UIMapType.Continent then return info.mapID, info.name end
        if not info.parentMapID or info.parentMapID == 0 then return end
        info = C_Map.GetMapInfo(info.parentMapID)
    end
end

local function ContinentAt(instance, wx, wy)
    local cached = continentOfInstance[instance]
    if cached ~= nil then return cached or nil end
    local best
    for _, mapID in ipairs(HBD:GetAllMapIDs()) do
        if not best or mapID < best then
            local info = C_Map.GetMapInfo(mapID)
            if info and info.mapType == Enum.UIMapType.Continent then
                local _, _, mapInstance = HBD:GetWorldCoordinatesFromZone(0.5, 0.5, mapID)
                if mapInstance == instance and HBD:GetZoneCoordinatesFromWorld(wx, wy, mapID) then best = mapID end
            end
        end
    end
    continentOfInstance[instance] = best or false
    return best
end

local function ZonePosition(continentMap, wx, wy)
    local cx, cy = HBD:GetZoneCoordinatesFromWorld(wx, wy, continentMap)
    if not cx then return end
    local zone = C_Map.GetMapInfoAtPosition(continentMap, cx, cy)
    if zone and zone.mapID then
        local zx, zy = HBD:GetZoneCoordinatesFromWorld(wx, wy, zone.mapID)
        if zx then return zone.mapID, zx, zy end
    end
    return continentMap, cx, cy
end

local function FactionAllows(nodeFaction, playerFaction)
    local F = Enum.FlightPathFaction
    if nodeFaction == F.Horde then return playerFaction == "Horde" end
    if nodeFaction == F.Alliance then return playerFaction == "Alliance" end
    return true
end

local function FlightNodes(continentMap, instance)
    local nodes = {}
    local faction = UnitFactionGroup("player")
    for _, node in ipairs(C_TaxiMap.GetTaxiNodesForMap(continentMap) or {}) do
        if not node.isUndiscovered and FactionAllows(node.faction, faction) then
            local x, y = node.position.x, node.position.y
            local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(x, y, continentMap)
            if wx and inst == instance then
                local mapID, zx, zy = ZonePosition(continentMap, wx, wy)
                nodes[#nodes + 1] = {
                    kind = "taxi", id = node.nodeID, name = node.name, wx = wx, wy = wy, instance = instance,
                    mapID = mapID, x = zx, y = zy,
                }
            end
        end
    end
    return nodes
end

local function Docks(continentMaps)
    local side = UnitFactionGroup("player") == "Horde" and "H" or "A"
    local docks = G.DockRides(ns.Transports, side, BOAT_SPEED)
    for _, entry in ipairs(docks) do
        local continentMap = continentMaps[entry.instance]
        if continentMap then
            entry.mapID, entry.x, entry.y = ZonePosition(continentMap, entry.wx, entry.wy)
            entry.name = entry.mapID and MapName(entry.mapID) or "?"
        else
            entry.name = "?"
        end
    end
    return docks
end

local function TravelGraph(start, stops, opts)
    local continentMaps = {}
    local startMap = ContinentOf(C_Map.GetBestMapForUnit("player"))
    if startMap then continentMaps[start.instance] = startMap end
    for _, stop in ipairs(stops) do
        local continentMap = ContinentOf(stop.mapID)
        if continentMap then continentMaps[stop.instance] = continentMaps[stop.instance] or continentMap end
    end
    local shortcuts = G.Shortcuts(ShortcutFacts(opts), opts)
    for _, shortcut in ipairs(shortcuts) do
        if not continentMaps[shortcut.instance] then
            continentMaps[shortcut.instance] = ContinentAt(shortcut.instance, shortcut.wx, shortcut.wy)
        end
    end

    local vertices = { start }
    for _, stop in ipairs(stops) do vertices[#vertices + 1] = stop end
    local keys = #vertices
    local edges
    local function Edge(a, b, time, step)
        edges[a][#edges[a] + 1] = { to = b, time = time, step = step }
    end

    local flights = {}
    for instance, continentMap in pairs(continentMaps) do
        local nodes = FlightNodes(continentMap, instance)
        if #nodes > 0 then
            local time, hop = G.FlightTimes(nodes, ns.TaxiPaths, TaxiSpeed())
            local first = #vertices + 1
            for _, node in ipairs(nodes) do vertices[#vertices + 1] = node end
            flights[#flights + 1] = { first = first, nodes = nodes, time = time, hop = hop }
        end
    end
    local docks = Docks(continentMaps)
    local dockVertex = {}
    for _, dock in ipairs(docks) do
        vertices[#vertices + 1] = dock
        dockVertex[dock] = #vertices
    end
    local jumps = {}
    for _, shortcut in ipairs(shortcuts) do
        local landing = {
            kind = shortcut.kind == "hearth" and "inn" or "teleport", name = shortcut.name,
            wx = shortcut.wx, wy = shortcut.wy, instance = shortcut.instance,
        }
        local continentMap = continentMaps[shortcut.instance]
        if continentMap then landing.mapID, landing.x, landing.y = ZonePosition(continentMap, shortcut.wx, shortcut.wy) end
        vertices[#vertices + 1] = landing
        jumps[#jumps + 1] = { vertex = #vertices, time = shortcut.time, kind = shortcut.kind }
    end

    edges = G.GroundEdges(vertices, GroundSpeed(), GROUND_DETOUR)
    for _, flight in ipairs(flights) do
        local k = #flight.nodes
        for i = 1, k do
            for j = 1, k do
                if i ~= j and flight.time[i][j] < math.huge then
                    Edge(flight.first + i - 1, flight.first + j - 1, FLIGHT_OVERHEAD + flight.time[i][j],
                        { kind = "flight", hops = G.FlightHops(flight.nodes, flight.hop, i, j) })
                end
            end
        end
    end
    for _, dock in ipairs(docks) do
        for _, ride in ipairs(dock.rides) do Edge(dockVertex[dock], dockVertex[ride.to], ride.time, "boat") end
    end
    for _, jump in ipairs(jumps) do Edge(1, jump.vertex, jump.time, jump.kind) end
    return vertices, edges, keys
end

function RP.Plan(stops, opts)
    opts = opts or {}
    local unknown, count, located = 0, 0, {}
    for _, stop in ipairs(stops) do
        count = count + #stop.questIds
        local wx, wy, instance
        if stop.mapID then wx, wy, instance = HBD:GetWorldCoordinatesFromZone(stop.x, stop.y, stop.mapID) end
        if wx then
            stop.kind, stop.zone, stop.wx, stop.wy, stop.instance = "stop", MapName(stop.mapID), wx, wy, instance
            located[#located + 1] = stop
        else
            unknown = unknown + #stop.questIds
        end
    end
    stops = located
    local px, py, playerInstance = HBD:GetPlayerWorldPosition()
    local plan = { count = count, unknown = unknown, routed = 0, unreachable = 0, route = {}, total = 0 }
    if not px or #stops == 0 then
        for _, stop in ipairs(stops) do plan.unreachable = plan.unreachable + #stop.quests end
        return plan
    end
    local start = { kind = "start", name = "Start", wx = px, wy = py, instance = playerInstance }
    plan.start = start
    local vertices, edges, keys = TravelGraph(start, stops, opts)
    local cost, searches = {}, {}
    for a = 1, keys do
        local dist, prev, via = G.Dijkstra(vertices, edges, a)
        cost[a], searches[a] = {}, { prev = prev, via = via }
        for b = 1, keys do cost[a][b] = dist[b] end
    end
    local reachable = { 1 }
    for b = 2, keys do
        if cost[1][b] < math.huge then reachable[#reachable + 1] = b end
    end
    plan.unreachable = count - unknown
    if #reachable < 2 then return plan end
    local path, total = G.ShortestPath(cost, reachable)
    plan.total = total
    for i = 2, #path do
        local a, b = path[i - 1], path[i]
        local stop = vertices[b]
        plan.route[#plan.route + 1] = { stop = stop, steps = G.Steps(vertices, searches[a].prev, searches[a].via, a, b) }
        plan.routed = plan.routed + #stop.quests
    end
    plan.unreachable = count - unknown - plan.routed
    return plan
end

local STEP_TEXT = {
    flight = function(step) return "|cff66bbffFly " .. step.from.name .. " to " .. step.to.name .. "|r" end,
    boat = function(step) return "|cff4de6ccSail " .. step.from.name .. " to " .. step.to.name .. "|r" end,
    hearth = function(step) return "|cffff9933Hearth to " .. step.to.name .. "|r" end,
    teleport = function(step) return "|cff69ccf0Teleport to " .. step.to.name .. "|r" end,
}

local function LegText(leg)
    local stop = leg.stop
    local parts = {}
    for _, step in ipairs(leg.steps) do
        local text = STEP_TEXT[step.kind]
        if text then parts[#parts + 1] = text(step) end
    end
    parts[#parts + 1] = "|cffffd100" .. leg.number .. ".|r " .. stop.name .. "  |cff9d9d9d" .. stop.zone .. "|r"
    for _, quest in ipairs(stop.quests) do parts[#parts + 1] = "  |cffbfbfbf" .. quest .. "|r" end
    return table.concat(parts, "\n")
end

local function SavedPoint(point)
    local copy = {}
    for _, field in ipairs(POINT_FIELDS) do copy[field] = point[field] end
    return copy
end

local function SaveRoute()
    if not routeStart then
        CharData().route = nil
        return
    end
    local saved = { start = SavedPoint(routeStart), legs = {}, waypoints = useWaypoints, shortestPath = shortestPath }
    for _, leg in ipairs(legs) do
        if not leg.done then
            local stop = SavedPoint(leg.stop)
            stop.quests, stop.questIds = CopyTable(leg.stop.quests), CopyTable(leg.stop.questIds)
            local steps = {}
            for i, step in ipairs(leg.steps) do
                steps[i] = {
                    kind = step.kind, from = SavedPoint(step.from), to = SavedPoint(step.to),
                    hops = step.hops and CopyTable(step.hops), passed = step.passed,
                }
            end
            saved.legs[#saved.legs + 1] = { number = leg.number, stop = stop, steps = steps }
        end
    end
    CharData().route = saved
end

local function Refresh()
    local entries, first = {}, nil
    for _, leg in ipairs(legs) do
        if not leg.done then
            first = first or leg
            entries[#entries + 1] = { text = LegText(leg), data = leg }
        end
    end
    window:SetEntries(entries)
    if not first then routeStart = nil end
    SaveRoute()
    V.Draw()
    W.FollowArrow(first)
    return first ~= nil
end

V.Attach(legs, function() return routeStart end)
W.Attach(legs, function() return Refresh() end, function() return useWaypoints end)

local function DropLeg(leg)
    leg.done = true
    W.RemoveLeg(leg)
    if not Refresh() and #legs > 0 then
        wipe(legs)
        if shortestPath then UpdateShortestPath() end
        ns.Print("Turn-in route complete.")
    elseif shortestPath then
        UpdateShortestPath()
    end
end

local function ClearRoute()
    W.RemoveRoute()
    for _, leg in ipairs(legs) do leg.done = true end
    wipe(legs)
    Refresh()
end

local function OnQuestGone(questId)
    if cancelPlan then
        planGeneration = planGeneration + 1
        cancelPlan()
        cancelPlan = nil
        CloseConfirmation()
        ns.Print("Turn-ins changed while planning; please plan the route again.")
    end
    for _, leg in ipairs(legs) do
        local stop = leg.stop
        if not leg.done then
            for k, id in ipairs(stop.questIds) do
                if id == questId then
                    table.remove(stop.questIds, k)
                    table.remove(stop.quests, k)
                    if #stop.questIds == 0 then
                        DropLeg(leg)
                    else
                        Refresh()
                        if shortestPath then UpdateShortestPath() end
                    end
                    return
                end
            end
        end
    end
end

function RP.Start(plan, opts)
    if shortestPath and not (opts and opts.shortestPath) then LeaveShortestPath(true) end
    local mode = opts and opts.waypoints or false
    if not W.Has() then mode = false end
    local add = false
    for _, action in ipairs(RP.WaypointSteps(mode, #legs > 0)) do
        if action == "remove-route" then
            W.RemoveRoute()
        elseif action == "clear-all" then
            W.ClearAll()
        else
            add = true
        end
    end
    for _, leg in ipairs(legs) do leg.done = true end
    wipe(legs)
    Refresh()
    routeStart = plan.start
    useWaypoints = add
    local waypoints = 0
    for i, planned in ipairs(plan.route) do
        local leg = { number = i, stop = planned.stop, steps = planned.steps, transit = {} }
        if add then waypoints = waypoints + W.AddLeg(leg) end
        legs[#legs + 1] = leg
    end
    Refresh()
    return waypoints
end

function RP.RestoreKeep(questIds, isCompleted)
    local keep = {}
    for i, id in ipairs(questIds) do
        if not isCompleted(id) then keep[#keep + 1] = i end
    end
    return keep
end

function RP.Restore()
    local saved = CharData().route
    if type(saved) ~= "table" or type(saved.legs) ~= "table" or #legs > 0 then return end
    local sp = ns.ShortestPath
    local status = sp and sp.Status()
    local isSP = saved.shortestPath or (saved.shortestPath == nil and (status == "owned" or status == "pending"))
    local add = not isSP and saved.waypoints ~= false and W.Has()
    local changed = false
    for _, entry in ipairs(saved.legs) do
        local stop = entry.stop
        local keep = RP.RestoreKeep(stop.questIds, C_QuestLog.IsQuestFlaggedCompleted)
        if #keep < #stop.questIds then
            changed = true
            local ids, names = {}, {}
            for _, i in ipairs(keep) do ids[#ids + 1] = stop.questIds[i]; names[#names + 1] = stop.quests[i] end
            stop.questIds, stop.quests = ids, names
        end
        if #stop.questIds > 0 then
            local leg = { number = entry.number, stop = stop, steps = entry.steps, transit = {} }
            if add then W.AddLeg(leg) end
            legs[#legs + 1] = leg
        end
    end
    if #legs > 0 then routeStart = saved.start end
    useWaypoints = add
    if isSP then
        local settings = ns.GetSettings(KEY)
        fallbackSettings = { hearth = settings.useHearth, teleports = settings.useTeleports, waypoints = settings.waypoints }
        if settings.useShortestPath ~= false and (status == "owned" or status == "pending") and #legs > 0 then
            shortestPath = true
            routeGeneration = routeGeneration + 1
            Refresh()
            WatchShortestPath(sp)
            if changed then UpdateShortestPath() end
        else
            Fallback(true)
        end
    else
        Refresh()
    end
end

local function StopWatching()
    if unwatch then unwatch(); unwatch = nil end
end

local function CancelDeferred()
    if deferredUnwatch then deferredUnwatch(); deferredUnwatch = nil end
end

LeaveShortestPath = function(cancelOwned)
    local sp = ns.ShortestPath
    shortestPath = false
    pendingUpdate = false
    routeGeneration = routeGeneration + 1
    updateGeneration = updateGeneration + 1
    if cancelUpdate then cancelUpdate(); cancelUpdate = nil end
    StopWatching()
    if cancelOwned and sp and not sp.CancelOwned() and sp.Status() == "pending" then
        CancelDeferred()
        deferredUnwatch = sp.Watch(function(status)
            if status == "owned" then
                sp.CancelOwned()
                CancelDeferred()
            elseif status == "empty" or status == "foreign" then
                CancelDeferred()
            end
        end)
    end
end

Fallback = function(cancelOwned)
    LeaveShortestPath(cancelOwned)
    local stops, previous = {}, {}
    for _, leg in ipairs(legs) do
        if not leg.done then stops[#stops + 1] = leg.stop; previous[leg.stop] = leg end
    end
    if #stops == 0 then Refresh(); return end
    local plan = RP.Plan(stops, fallbackSettings)
    local included = {}
    for _, entry in ipairs(plan.route) do included[entry.stop] = true end
    for _, stop in ipairs(stops) do
        if not included[stop] then plan.route[#plan.route + 1] = { stop = stop, steps = previous[stop].steps } end
    end
    plan.start = plan.start or routeStart
    RP.Start(plan, { waypoints = W.Has() and (fallbackSettings.waypoints or "add") or false })
end

WatchShortestPath = function(sp)
    local routeToken = routeGeneration
    unwatch = sp.Watch(function(status)
        if not shortestPath or routeToken ~= routeGeneration then return end
        if status == "owned" then
            if pendingUpdate then UpdateShortestPath() end
        elseif status ~= "pending" then
            Fallback(true)
        end
    end)
end

function RP.SettingsChanged()
    local settings = ns.GetSettings(KEY)
    if settings.useShortestPath ~= false then return end
    if shortestPath then
        fallbackSettings = { hearth = settings.useHearth, teleports = settings.useTeleports, waypoints = settings.waypoints }
        Fallback(true)
    end
end

UpdateShortestPath = function()
    local sp = ns.ShortestPath
    if not shortestPath or not sp then return end
    updateGeneration = updateGeneration + 1
    local generation = updateGeneration
    if cancelUpdate then cancelUpdate(); cancelUpdate = nil end
    if #legs == 0 then LeaveShortestPath(true); return end
    if sp.Status and sp.Status() == "pending" then pendingUpdate = true; return end
    pendingUpdate = false
    local route = {}
    for _, leg in ipairs(legs) do if not leg.done then route[#route + 1] = { stop = leg.stop } end end
    local waiting = true
    local cancel = sp.Start({ route = route }, function(_, answer) answer(false) end, function(accepted)
        waiting = false
        if not shortestPath or generation ~= updateGeneration then return end
        cancelUpdate = nil
        if not accepted then Fallback(true) end
    end)
    if waiting and generation == updateGeneration then cancelUpdate = cancel end
end

function RP.Abort()
    planGeneration = planGeneration + 1
    if cancelPlan then cancelPlan(); cancelPlan = nil end
    CloseConfirmation()
    if shortestPath then LeaveShortestPath(true) end
    if #legs == 0 then return end
    ClearRoute()
    ns.Print("Turn-in route aborted.")
end

function RP.PlanSources(keys, settings, done, getSettings)
    planGeneration = planGeneration + 1
    local generation = planGeneration
    if cancelPlan then cancelPlan(); cancelPlan = nil end
    CloseConfirmation()
    settings = settings or {}
    local stops, unknown, _, failed = RP.Collect(keys)
    local finished = false
    local function cancel()
        if finished then return end
        finished = true
        if generation == planGeneration then
            planGeneration = planGeneration + 1
            if cancelPlan then cancelPlan(); cancelPlan = nil end
            CloseConfirmation()
        end
    end
    local function fallback()
        if finished or generation ~= planGeneration then return end
        finished = true
        cancelPlan = nil
        local plan = RP.Plan(stops, { hearth = settings.useHearth, teleports = settings.useTeleports })
        plan.count, plan.unknown = plan.count + unknown, plan.unknown + unknown
        local message, started
        if plan.count == 0 then
            message = "Nothing to turn in."
        elseif #plan.route == 0 then
            if plan.unknown == plan.count then
                message = ("%d turn-ins, no known location."):format(plan.count)
            else
                message = ("%d turn-ins, none reachable."):format(plan.count)
            end
        else
            local mode = W.Has() and (settings.waypoints or "add") or false
            local waypoints = RP.Start(plan, { waypoints = mode })
            local minutes = math.ceil(plan.total / 60)
            if mode then
                message = ("TomTom route: %d turn-ins, %d waypoints, about %d min."):format(plan.routed, waypoints, minutes)
            else
                message = ("Route: %d turn-ins, about %d min."):format(plan.routed, minutes)
            end
            if plan.unreachable > 0 then message = message .. (" %d unreachable."):format(plan.unreachable) end
            if plan.unknown > 0 then message = message .. (" %d without a known turn-in location."):format(plan.unknown) end
            started = true
        end
        if #failed > 0 then message = message .. (" Could not read: %s."):format(table.concat(failed, ", ")) end
        if done then done(message, started) end
        return message, started
    end
    local sp = ns.ShortestPath
    local mapID = settings.useShortestPath ~= false and sp and sp.Available() and C_Map.GetBestMapForUnit("player")
    local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if position and #stops > 0 and done then
        local x, y = position:GetXY()
        local ordering = true
        local cancelOrder = sp.Order({ mapID = mapID, x = x, y = y }, stops, function(plan)
            ordering = false
            if finished or generation ~= planGeneration then return end
            cancelPlan = nil
            local currentSettings = getSettings and getSettings()
            if currentSettings and (currentSettings ~= settings or currentSettings.useShortestPath == false) then
                settings = currentSettings
                fallback()
                return
            end
            if not plan or #plan.route == 0 or not sp.Start then fallback(); return end
            local wx, wy, instance = HBD:GetPlayerWorldPosition()
            plan.start.kind, plan.start.name = "start", "Start"
            plan.start.wx, plan.start.wy, plan.start.instance = wx, wy, instance
            for _, leg in ipairs(plan.route) do
                local stop = leg.stop
                stop.kind, stop.zone = "stop", MapName(stop.mapID)
                stop.wx, stop.wy, stop.instance = HBD:GetWorldCoordinatesFromZone(stop.x, stop.y, stop.mapID)
            end
            local waiting = true
            local function confirmReplacement(journey, answer)
                ConfirmReplacement(journey, function(accepted)
                    local live = getSettings and getSettings()
                    if generation ~= planGeneration or (live and (live ~= settings or live.useShortestPath == false)) then
                        answer(false)
                        return
                    end
                    answer(accepted)
                end)
            end
            local cancelStart = sp.Start(plan, confirmReplacement, function(accepted, reason)
                waiting = false
                if finished or generation ~= planGeneration then return end
                cancelPlan = nil
                local liveSettings = getSettings and getSettings()
                if liveSettings and (liveSettings ~= settings or liveSettings.useShortestPath == false) then
                    if accepted then sp.CancelOwned() end
                    settings = liveSettings
                    fallback()
                    return
                end
                if not accepted then
                    if reason == "busy" or reason == "unknown" then
                        ns.Print("Shortest Path journey is occupied or unavailable; using KLH guidance.")
                    end
                    fallback()
                    return
                end
                finished = true
                CancelDeferred()
                if shortestPath then LeaveShortestPath(false) end
                W.RemoveRoute()
                shortestPath = true
                routeGeneration = routeGeneration + 1
                fallbackSettings = { hearth = settings.useHearth, teleports = settings.useTeleports, waypoints = settings.waypoints }
                RP.Start(plan, { waypoints = false, shortestPath = true })
                WatchShortestPath(sp)
                local message = ("Shortest Path route: %d turn-ins, about %d min."):format(plan.routed, math.ceil(plan.total / 60))
                if (plan.unreachable or 0) > 0 then message = message .. (" %d unreachable."):format(plan.unreachable) end
                local missing = (plan.unknown or 0) + unknown
                if missing > 0 then message = message .. (" %d without a known turn-in location."):format(missing) end
                if #failed > 0 then message = message .. (" Could not read: %s."):format(table.concat(failed, ", ")) end
                done(message, true)
            end)
            if waiting and not finished then cancelPlan = cancelStart end
        end)
        if ordering and not finished then cancelPlan = cancelOrder end
    else
        local message, started = fallback()
        if not done then return message, started end
    end
    return cancel
end

local EVENTS = {
    QUEST_TURNED_IN = function(questId) OnQuestGone(questId) end,
    QUEST_REMOVED = function(questId) OnQuestGone(questId) end,
    PLAYER_MOUNT_DISPLAY_CHANGED = function() C_Timer.After(1, RecordMountSpeed) end,
    PLAYER_CONTROL_LOST = function() if #legs > 0 then C_Timer.After(1, W.OnTaxiTaken) end end,
    PLAYER_CONTROL_GAINED = function()
        if flightPlan and flightPlan.started and not UnitOnTaxi("player") then OnLanded() end
    end,
    HEARTHSTONE_BOUND = function() C_Timer.After(1, OnHearthBound) end,
}

function RP.Init(opts)
    if window then return end
    HBD = opts.hbd
    window = ns.CreateListWindow({
        name = "KLHTurnInRouteWindow", title = "Turn-in Route", key = KEY, width = 270, hint = HINT,
        onClick = W.ArrowTo, onCtrlClick = DropLeg,
        buttons = { { text = "Refresh", onClick = opts.onRefresh }, { text = "Abort", onClick = RP.Abort } },
    })
    V.Init(ns.UI, HBD)
    local events = CreateFrame("Frame")
    for event in pairs(EVENTS) do events:RegisterEvent(event) end
    events:SetScript("OnEvent", function(_, event, ...) EVENTS[event](...) end)
    hooksecurefunc("TakeTaxiNode", OnTakeTaxiNode)
    W.Init(RP)
    C_Timer.After(RESTORE_DELAY, RP.Restore)
end
