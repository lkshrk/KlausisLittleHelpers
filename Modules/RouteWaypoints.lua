local _, ns = ...

local W = {}
ns.RouteWaypoints = W

local legs = {}
local Refresh = function() end
local Wanted = function() return false end
local arrowLeg, arrowUid
local ownRemoval = false
local goneQueue, goneQueued = {}, false

function W.Attach(routeLegs, refresh, wanted)
    legs, Refresh, Wanted = routeLegs, refresh, wanted
end

function W.Has()
    return _G.TomTom ~= nil and _G.TomTom.AddWaypoint ~= nil
end

local function ValidWaypoint(uid)
    return uid ~= nil and W.Has() and _G.TomTom:IsValidWaypoint(uid)
end

function W.ArrowTo(leg)
    local uid = leg.uid
    for _, transit in ipairs(leg.transit) do
        if ValidWaypoint(transit.uid) then
            uid = transit.uid
            break
        end
    end
    if ValidWaypoint(uid) then
        _G.TomTom:SetCrazyArrow(uid, uid.arrivaldistance, uid.title)
        arrowUid = uid
    end
end

function W.FollowArrow(first)
    if not first then
        arrowLeg, arrowUid = nil, nil
    elseif first ~= arrowLeg or not ValidWaypoint(arrowUid) then
        arrowLeg = first
        W.ArrowTo(first)
    end
end

local function RemoveOwn(uid)
    if not ValidWaypoint(uid) then return end
    ownRemoval = true
    pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, uid)
    ownRemoval = false
end

function W.RemoveLeg(leg)
    for _, transit in ipairs(leg.transit) do RemoveOwn(transit.uid) end
    RemoveOwn(leg.uid)
end

function W.RemoveRoute()
    for _, leg in ipairs(legs) do
        if not leg.done then W.RemoveLeg(leg) end
    end
end

function W.ClearAll()
    local uids, all = {}, _G.TomTom.waypoints
    for _, entries in pairs(type(all) == "table" and all or {}) do
        if type(entries) == "table" then
            for _, uid in pairs(entries) do uids[#uids + 1] = uid end
        end
    end
    for _, uid in ipairs(uids) do RemoveOwn(uid) end
end

function W.OnTaxiTaken()
    if not UnitOnTaxi("player") then return end
    for _, leg in ipairs(legs) do
        if not leg.done then
            for _, transit in ipairs(leg.transit) do
                if transit.kind == "flight" and ValidWaypoint(transit.uid) then
                    RemoveOwn(transit.uid)
                    transit.uid = nil
                    transit.step.passed = true
                    Refresh()
                    return
                end
            end
            return
        end
    end
end

local function OnWaypointGone(uid)
    if ownRemoval or uid == nil then return end
    for _, leg in ipairs(legs) do
        if not leg.done then
            if leg.uid == uid then
                leg.uid = nil
                return
            end
            for _, transit in ipairs(leg.transit) do
                if transit.uid == uid then
                    transit.uid = nil
                    transit.step.passed = true
                    Refresh()
                    return
                end
            end
        end
    end
end

local function FlushGone()
    goneQueued = false
    local queue = CopyTable(goneQueue)
    wipe(goneQueue)
    for _, uid in ipairs(queue) do OnWaypointGone(uid) end
end

local function QueueGone(uid)
    if ownRemoval or uid == nil then return end
    goneQueue[#goneQueue + 1] = uid
    if not goneQueued then
        goneQueued = true
        C_Timer.After(0, FlushGone)
    end
end

local function OnWaypointsReloaded()
    wipe(goneQueue)
    local changed = false
    for _, leg in ipairs(legs) do
        if not leg.done then
            local stale = (leg.uid and not ValidWaypoint(leg.uid)) or false
            for _, transit in ipairs(leg.transit) do
                if transit.uid and not ValidWaypoint(transit.uid) then stale = true end
            end
            if stale then
                W.RemoveLeg(leg)
                leg.uid = nil
                wipe(leg.transit)
                if Wanted() and W.Has() then W.AddLeg(leg) end
                changed = true
            end
        end
    end
    if changed then Refresh() end
end

local function AddWaypoint(point, title, keepOnArrival)
    if not point.mapID then return nil end
    local TomTom = _G.TomTom
    local opts = { title = title, from = "KlausisLittleHelpers", persistent = false, crazy = false, silent = true, world = false }
    if keepOnArrival then opts.cleardistance = 0 end
    opts.callbacks = TomTom:DefaultCallbacks(opts)
    for distance, callback in pairs(opts.callbacks.distance) do
        opts.callbacks.distance[distance] = function(event, uid, ...)
            callback(event, uid, ...)
            if not TomTom:IsValidWaypoint(uid) then OnWaypointGone(uid) end
        end
    end
    return TomTom:AddWaypoint(point.mapID, point.x, point.y, opts)
end

local TRANSIT_TITLE = {
    flight = function(step, number) return number .. ". Fly to " .. step.to.name end,
    boat = function(step, number) return number .. ". Sail to " .. step.to.name end,
}

function W.AddLeg(leg)
    local stop, count = leg.stop, 0
    for _, step in ipairs(leg.steps) do
        local title = TRANSIT_TITLE[step.kind]
        if title and not step.passed then
            local uid = AddWaypoint(step.from, title(step, leg.number))
            if uid then
                leg.transit[#leg.transit + 1] = { kind = step.kind, uid = uid, step = step }
                count = count + 1
            end
        end
    end
    leg.uid = AddWaypoint(stop, leg.number .. ". " .. stop.name .. ": " .. table.concat(stop.quests, ", "), true)
    return count + (leg.uid and 1 or 0)
end

function W.Init(owner)
    local TomTom = _G.TomTom
    if W.Has() and type(TomTom.RegisterCallback) == "function" then
        TomTom.RegisterCallback(owner, "WaypointRemoved", function(_, uid) QueueGone(uid) end)
        TomTom.RegisterCallback(owner, "WaypointsReloaded", OnWaypointsReloaded)
    end
end
