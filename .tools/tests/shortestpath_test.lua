addon("Modules/TurnInRouteGraph.lua")
addon("Modules/ShortestPath.lua")
local oldFrame, oldAPI = _G.CreateFrame, _G.ShortestPathForever
local callback, calls, frameCalls, framesCreated = nil, 0, 0, 0
_G.CreateFrame = function()
    framesCreated = framesCreated + 1
    return { SetScript = function(_, _, fn) callback = fn end }
end
---@type table<string, any>
local api = { version = 2 }
for _, name in ipairs({ "NavigateRoute", "CurrentStop", "Cancel", "Journey", "JourneyState", "Active", "Ended", "Subscribe" }) do api[name] = function() end end
_G.ShortestPathForever = { API = api }
ns.IS_FOREVER = true
local SP = ns.ShortestPath
local start = { mapID = 1, x = 0, y = 0 }
local function stop(x) return { mapID = 1, x = x / 10, y = 0, questIds = { x }, quests = { "Q" } } end
local function run()
    local frames = 0
    while callback and frames < 10000 do
        frameCalls = 0
        callback()
        ok(frameCalls <= 1, "one estimate per frame")
        frames = frames + 1
    end
    ok(frames < 10000, "job completes")
end
api.Estimate = function(_, x, _, _, y)
    calls, frameCalls = calls + 1, frameCalls + 1
    local costs = { [0] = { 9, 1, 8 }, [1] = { 0, 9, 1 }, [2] = { 1, 0, 9 }, [3] = { 9, 9, 0 } }
    return costs[math.floor(x * 10 + 0.5)][math.floor(y * 10 + 0.5)]
end
ok(SP.Available(), "compatible API")
ns.IS_FOREVER = false; eq(SP.Available(), false, "retail")
ns.IS_FOREVER = true
for _, version in ipairs({ 0, 3 }) do api.version = version; eq(SP.Available(), false, "unsupported version") end
api.version = 2
for _, name in ipairs({ "Estimate", "NavigateRoute", "CurrentStop", "Cancel", "Journey", "JourneyState", "Active", "Ended", "Subscribe" }) do
    local fn = api[name]; api[name] = false; eq(SP.Available(), false, name); api[name] = fn
end
_G.ShortestPathForever = nil; eq(SP.Available(), false, "absent API")
_G.ShortestPathForever = { API = "invalid" }; eq(SP.Available(), false, "invalid API")
_G.ShortestPathForever = { API = api }
local result, reason
SP.Order(start, { stop(1), stop(2), stop(3) }, function(p, r) result, reason = p, r end)
run()
eq(reason, nil); eq(result.total, 3); eq(result.route[1].stop.x, 0.2); eq(result.route[2].stop.x, 0.1); eq(result.route[3].stop.x, 0.3)
calls = 0
SP.Order(start, { stop(1), stop(1) }, function(p) result = p end)
run(); eq(calls, 1, "duplicate directed coordinates cached")
eq(framesCreated, 1, "repeated jobs reuse one frame")
local firstDone, secondDone = false, false
SP.Order(start, { stop(1) }, function() firstDone = true end)
SP.Order(start, { stop(2) }, function() secondDone = true end)
run(); ok(firstDone and secondDone, "concurrent jobs complete")
eq(framesCreated, 1, "concurrent jobs share the driver")
firstDone, secondDone = false, false
local cancelFirst = SP.Order(start, { stop(1) }, function() firstDone = true end)
SP.Order(start, { stop(2) }, function() secondDone = true end)
cancelFirst(); cancelFirst(); run()
eq(firstDone, false, "cancelled concurrent job stays silent")
ok(secondDone, "cancelling one job preserves another")
firstDone, secondDone = false, false
SP.Order(start, { stop(1) }, function()
    firstDone = true
    SP.Order(start, { stop(2) }, function() secondDone = true end)
end)
run(); ok(firstDone and secondDone, "completion can enqueue a new job")
eq(framesCreated, 1, "callback job reuses driver")
local completed = false
calls = 0
local cancel = SP.Order(start, { stop(1), stop(2) }, function() completed = true end)
assert(callback)(); cancel(); run(); eq(calls, 1); eq(completed, false)
for _, value in ipairs({ "combat", "invalid", "throw", "negative", "infinity", "nan" }) do
    api.Estimate = function()
        if value == "throw" then error("bad") end
        if value == "negative" then return -1 end
        if value == "infinity" then return math.huge end
        if value == "nan" then return 0/0 end
        return nil, value
    end
    result, reason = nil, nil
    SP.Order(start, { stop(1) }, function(p, r) result, reason = p, r end)
    run(); eq(result, nil, value); ok(reason ~= nil, value)
end
result, reason = nil, nil
SP.Order(nil, { stop(1) }, function(p, r) result, reason = p, r end)
run(); eq(result, nil); ok(reason ~= nil, "missing start")
calls = 0
api.Estimate = function(_, x, _, _, y) calls = calls + 1; if y == 0.2 or x == 0.2 then return nil, "unreachable" end return 1 end
SP.Order(start, { stop(1), stop(2) }, function(p, r) result, reason = p, r end)
run(); assert(result); eq(result.routed, 1); eq(result.unreachable, 1); eq(result.route[1].stop.x, 0.1); eq(calls, 2, "unreachable stops excluded from matrix")
api.Estimate = function(_, x, _, _, y) if x ~= 0 and y ~= 0 and x ~= y then return nil, "unreachable" end return 1 end
result, reason = nil, nil
SP.Order(start, { stop(1), stop(2) }, function(p, r) result, reason = p, r end)
run(); eq(result, nil); ok(reason ~= nil, "impossible transition fails")
local many = {}; for i = 1, 65 do many[i] = stop(i / 100) end
calls = 0
api.Estimate = function() calls = calls + 1; return 1 end
result, reason = nil, nil
SP.Order(start, many, function(p, r) result, reason = p, r end)
run(); eq(result, nil); ok(reason ~= nil, "too many stops"); ok(calls <= 65, "reject before stop matrix")
local twelve = {}; for i = 1, 12 do twelve[i] = stop(i) end
api.Estimate = function(_, x, _, _, y) if x ~= 0 and y ~= 0 then return nil, "unreachable" end return 1 end
result, reason = nil, nil
SP.Order(start, twelve, function(p, r) result, reason = p, r end)
run(); eq(result, nil); ok(reason ~= nil, "large unreachable route fails")
local notify, unsubscribed = nil, 0
api.Subscribe = function(cb) notify = cb; return function() unsubscribed = unsubscribed + 1 end end
local statuses = {}
local unwatch = SP.Watch(function(status) statuses[#statuses + 1] = status end)
ok(type(unwatch) == "function", "watch returns unsubscribe")
assert(notify)(); ok(statuses[1] ~= nil, "watch reads status")
unwatch(); unwatch(); eq(unsubscribed, 1, "unsubscribe once")
assert(notify)(); eq(#statuses, 1, "late notifications ignored")
local submitted, cancelled = 0, 0
local answer, accepted, why
local journey, state, ownerStop = nil, { busy = false }, nil
local oldCombat = _G.InCombatLockdown
_G.InCombatLockdown = function() return false end
api.Journey = function() if journey then return journey end return nil, "none" end
api.JourneyState = function() return state end
api.CurrentStop = function() if ownerStop then return ownerStop end return nil, "none" end
api.NavigateRoute = function(owner, stops) submitted = submitted + 1; eq(owner, "KlausisLittleHelpers"); eq(stops[1].hold, true); return true end
api.Cancel = function() cancelled = cancelled + 1; return true end
local one = { route = { { stop = stop(1) } } }
local function confirm(_, cb) answer = cb end
local function done(a, r) accepted, why = a, r end
SP.Start(one, confirm, done)
eq(accepted, true, "empty journey starts"); eq(why, nil, "success has no failure reason"); eq(submitted, 1); eq(SP.Status(), "empty")
ownerStop = 1; state = { busy = true, owner = "KlausisLittleHelpers" }
journey = { owner = nil, goal = { map = 1, x = 0.1, y = 0.2 } }
SP.Start(one, confirm, done); eq(accepted, false, "corpse journey is not owned"); eq(submitted, 1); eq(SP.Status(), "unknown", "corpse hides owned journey")
eq(SP.CancelOwned(), false, "corpse journey is not cancelled")
journey = nil
api.Journey = function() return nil, "loading" end
state.pending = true
eq(SP.Status(), "pending", "owned journey still loading")
state.blocked = "corpse"; eq(SP.Status(), "unknown", "loading corpse overlay is not owned")
state.blocked = nil; state.pending = nil
api.Journey = function() if journey then return journey end return nil, "none" end
journey = { owner = "KlausisLittleHelpers", goal = { map = 1, x = 0.1, y = 0.2 } }
SP.Start(one, confirm, done); eq(accepted, true, "owned journey starts"); eq(submitted, 2); eq(SP.Status(), "owned", "paused owned journey")
ok(SP.CancelOwned(), "cancel owned"); eq(cancelled, 1)
ownerStop = nil; state = { busy = true, owner = "other" }; journey = { owner = "other", goal = { map = 1, x = 0.1, y = 0.2 } }
answer, accepted = nil, nil
eq(SP.Status(), "foreign", "paused foreign journey")
SP.Start(one, confirm, done); ok(answer, "foreign confirmation"); assert(answer)(false); eq(accepted, false); eq(why, "declined"); eq(submitted, 2)
answer = nil; SP.Start(one, confirm, done); journey.goal.x = 0.3; assert(answer)(true); eq(accepted, false); eq(why, "stale"); eq(submitted, 2)
answer = nil; SP.Start(one, confirm, done); local cancelStart = SP.Start(one, confirm, done); cancelStart(); assert(answer)(true); eq(submitted, 2)
answer = nil; SP.Start(one, confirm, done); _G.InCombatLockdown = function() return true end; assert(answer)(true); eq(accepted, false); eq(why, "combat"); eq(submitted, 2)
_G.InCombatLockdown = function() return false end
answer = nil; SP.Start(one, confirm, done); assert(answer)(true); eq(accepted, true); eq(submitted, 3)
eq(SP.CancelOwned(), false); eq(cancelled, 1)
state = nil; journey = nil; api.JourneyState = function() return nil, "loading" end
SP.Start(one, confirm, done); eq(accepted, false); eq(why, "unknown"); eq(submitted, 3)
state = { busy = false }; api.JourneyState = function() return state end
api.NavigateRoute = function() return false end
SP.Start(one, confirm, done); eq(accepted, false); eq(why, "rejected")
api.NavigateRoute = function() error("failed") end
SP.Start(one, confirm, done); eq(accepted, false); eq(why, "error")
local maxRoute = { route = {} }
for i = 1, 64 do maxRoute.route[i] = { stop = stop(i) } end
api.NavigateRoute = function(_, stops) eq(#stops, 64); return true end
SP.Start(maxRoute, confirm, done); eq(accepted, true)
_G.InCombatLockdown = function() return true end
SP.Start(one, confirm, done); eq(accepted, false); eq(submitted, 3)
_G.InCombatLockdown = oldCombat
_G.CreateFrame, _G.ShortestPathForever = oldFrame, oldAPI
