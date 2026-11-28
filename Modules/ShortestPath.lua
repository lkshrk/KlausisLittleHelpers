local _, ns = ...

local SP, G = {}, ns.RouteGraph
ns.ShortestPath = SP

local required = { "Estimate", "NavigateRoute", "CurrentStop", "Cancel", "Journey", "JourneyState", "Active", "Ended", "Subscribe" }

local function API()
    local api = _G.ShortestPathForever and _G.ShortestPathForever.API
    if not ns.IS_FOREVER or type(api) ~= "table" or (api.version ~= 1 and api.version ~= 2) then return end
    for _, name in ipairs(required) do
        if type(api[name]) ~= "function" then return end
    end
    return api
end

function SP.Available()
    return API() ~= nil
end

local OWNER = "KlausisLittleHelpers"

function SP.Status()
    local api = API()
    if not api then return "unknown" end
    local ok1, index, indexReason = pcall(api.CurrentStop, OWNER)
    local ok2, journey, journeyReason = pcall(api.Journey)
    local ok3, state = pcall(api.JourneyState)
    if not ok1 or not ok2 or not ok3 or type(state) ~= "table" or type(state.busy) ~= "boolean" then return "unknown" end
    if type(index) == "number" and index >= 1 then
        if state.owner == OWNER and state.busy and type(journey) == "table" and journey.owner == OWNER then return "owned" end
        if state.owner == OWNER and state.busy and state.pending and state.blocked ~= "corpse"
            and journey == nil and journeyReason == "loading" then return "pending" end
        return "unknown"
    end
    if index ~= nil or indexReason ~= "none" then return "unknown" end
    if journey == nil and journeyReason == "none" and not state.busy and state.owner == nil then return "empty" end
    if type(journey) == "table" and state.busy then return "foreign" end
    return "unknown"
end

function SP.Watch(callback)
    local api = API()
    local live = true
    local function notify() if live then callback(SP.Status()) end end
    local ok, unsubscribe
    if api then ok, unsubscribe = pcall(api.Subscribe, notify) end
    if not ok or type(unsubscribe) ~= "function" then unsubscribe = nil end
    return function()
        if not live then return end
        live = false
        if unsubscribe then pcall(unsubscribe) end
    end
end

function SP.CancelOwned()
    local api = API()
    if not api then return false end
    local ok, index = pcall(api.CurrentStop, OWNER)
    if not ok or type(index) ~= "number" or index < 1 then return false end
    local stateOK, state = pcall(api.JourneyState)
    local journeyOK, journey = pcall(api.Journey)
    if not stateOK or type(state) ~= "table" or state.owner ~= OWNER or not state.busy
        or not journeyOK or type(journey) ~= "table" or journey.owner ~= OWNER then return false end
    local success, cancelled = pcall(api.Cancel, OWNER)
    return success and cancelled == true
end

function SP.Start(plan, confirm, done)
    local live = true
    local function finish(accepted, reason)
        if not live then return end
        live = false
        done(accepted, reason)
    end
    local function cancel() live = false end
    local api = API()
    if not api then finish(false, "unavailable"); return cancel end
    local stops = {}
    for _, entry in ipairs(plan.route or {}) do
        local stop = entry.stop
        stops[#stops + 1] = { map = stop.mapID, x = stop.x, y = stop.y, title = stop.name, kind = "turnin", hold = true }
    end
    if #stops == 0 or #stops > 64 then finish(false, "invalid"); return cancel end
    local function submit()
        if not live then return end
        if API() ~= api then finish(false, "unavailable"); return end
        if InCombatLockdown() then finish(false, "combat"); return end
        local success, accepted = pcall(api.NavigateRoute, OWNER, stops)
        if success and accepted == true then finish(true) else finish(false, success and "rejected" or "error") end
    end
    local function snapshot()
        local ok1, index, indexReason = pcall(api.CurrentStop, OWNER)
        local ok2, journey, journeyReason = pcall(api.Journey)
        local ok3, state = pcall(api.JourneyState)
        if not ok1 or not ok2 or not ok3 or type(state) ~= "table" or type(state.busy) ~= "boolean" then return "unknown" end
        if type(index) == "number" and index >= 1 then
            if state.owner == OWNER and state.busy and type(journey) == "table" and journey.owner == OWNER then return "owned" end
            return "unknown"
        end
        if index ~= nil or indexReason ~= "none" then return "unknown" end
        if journey == nil and journeyReason == "none" and not state.busy and state.owner == nil then return "empty" end
        local goal = type(journey) == "table" and journey.goal
        if not state.busy or type(goal) ~= "table" or type(goal.map) ~= "number"
            or type(goal.x) ~= "number" or type(goal.y) ~= "number" then return "unknown" end
        return "foreign", { owner = journey.owner, stateOwner = state.owner, map = goal.map, x = goal.x, y = goal.y,
            z = goal.z, index = journey.index, stateIndex = state.index, pending = state.pending,
            settling = state.settling, blocked = state.blocked, guided = journey.guided }
    end
    local current, before = snapshot()
    if current == "empty" or current == "owned" then
        submit()
    elseif current == "foreign" and before and type(confirm) == "function" then
        confirm(before, function(yes)
            if not live then return end
            if not yes then finish(false, "declined"); return end
            if API() ~= api then finish(false, "unavailable"); return end
            local now, after = snapshot()
            if now ~= "foreign" or not after then finish(false, "stale"); return end
            for _, key in ipairs({ "owner", "stateOwner", "map", "x", "y", "z", "index", "stateIndex", "pending", "settling", "blocked", "guided" }) do
                if before[key] ~= after[key] then finish(false, "stale"); return end
            end
            submit()
        end)
    else
        finish(false, "unknown")
    end
    return cancel
end

local function ValidPoint(p)
    return type(p) == "table" and type(p.mapID) == "number" and p.mapID > 0 and p.mapID < math.huge
        and type(p.x) == "number" and p.x >= 0 and p.x <= 1
        and type(p.y) == "number" and p.y >= 0 and p.y <= 1
end

local function PointKey(p)
    return ("%.17g,%.17g,%.17g"):format(p.mapID, p.x == 0 and 0 or p.x, p.y == 0 and 0 or p.y)
end

local driver, jobs
local function RemoveJob(job)
    for i = #jobs, 1, -1 do
        if jobs[i] == job then table.remove(jobs, i) end
    end
    if #jobs == 0 then driver:SetScript("OnUpdate", nil) end
end
local function AddJob(job)
    if not driver then
        driver = CreateFrame("Frame")
        jobs = {}
    end
    jobs[#jobs + 1] = job
    driver:SetScript("OnUpdate", function()
        local current = table.remove(jobs, 1)
        if current then
            jobs[#jobs + 1] = current
            current()
        end
        if #jobs == 0 then driver:SetScript("OnUpdate", nil) end
    end)
end
function SP.Order(start, stops, done)
    local api = API()
    local live = true
    local step
    local function finish(plan, reason)
        if not live then return end
        live = false
        RemoveJob(step)
        done(plan, reason)
    end
    local function cancel()
        if not live then return end
        live = false
        RemoveJob(step)
    end
    local points, keys, cost, cache = { start }, {}, {}, {}
    local plan = { count = 0, unknown = 0, routed = 0, unreachable = 0, route = {}, total = 0, start = start }
    for _, stop in ipairs(stops) do
        local count = #(stop.questIds or {})
        plan.count = plan.count + count
        if ValidPoint(stop) then points[#points + 1] = stop else plan.unknown = plan.unknown + count end
    end
    local a, b = 1, 1
    step = function()
        if not live then return end
        if not api or not ValidPoint(start) then finish(nil, "unavailable"); return end
        while a <= #points do
            cost[a] = cost[a] or {}
            if b > #points then
                if a == 1 then
                    local reachable, firstRow = { points[1] }, { 0 }
                    for i = 2, #points do
                        if cost[1][i] < math.huge then
                            reachable[#reachable + 1] = points[i]
                            firstRow[#firstRow + 1] = cost[1][i]
                        else
                            plan.unreachable = plan.unreachable + #(points[i].questIds or {})
                        end
                    end
                    if #reachable > 65 then finish(nil, "too many stops"); return end
                    points, cost[1] = reachable, firstRow
                end
                a, b = a + 1, 1
            else
                local from, to = points[a], points[b]
                local fromKey, toKey = PointKey(from), PointKey(to)
                local key = fromKey .. ">" .. toKey
                local value = (b == 1 or fromKey == toKey) and 0 or cache[key]
                if value == nil then
                    local success, seconds, reason = pcall(api.Estimate, from.mapID, from.x, from.y, to.mapID, to.x, to.y)
                    if not success then finish(nil, "error"); return end
                    if seconds == nil and reason == "unreachable" then seconds = math.huge
                    elseif type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 or seconds >= math.huge then
                        finish(nil, reason or "invalid"); return
                    end
                    cache[key], cost[a][b] = seconds, seconds
                    b = b + 1
                    return
                end
                cost[a][b] = value
                b = b + 1
            end
        end
        keys[1] = 1
        for i = 2, #points do
            if cost[1][i] < math.huge then keys[#keys + 1] = i
            else plan.unreachable = plan.unreachable + #(points[i].questIds or {}) end
        end
        if #keys > 65 then finish(nil, "too many stops"); return end
        local path, total = G.ShortestPath(cost, keys)
        if #path ~= #keys or total ~= total or total >= math.huge then finish(nil, "unreachable"); return end
        for i = 2, #path do
            if cost[path[i - 1]][path[i]] >= math.huge then finish(nil, "unreachable"); return end
            local stop = points[path[i]]
            plan.route[#plan.route + 1] = { stop = stop, steps = {} }
            plan.routed = plan.routed + #(stop.quests or {})
        end
        plan.total = total
        finish(plan)
    end
    AddJob(step)
    return cancel
end
