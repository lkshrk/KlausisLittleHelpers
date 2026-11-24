addon("Modules/TurnInRouteGraph.lua")
local G = ns.RouteGraph
local function near(a, b, msg)
    ok(math.abs(a - b) < 1e-9, (msg or "near") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

local nodes = { { id = 10 }, { id = 20 }, { id = 30 }, { id = 40 } }
local paths = { [10] = { [20] = { 100, 5 } }, [20] = { [30] = { 160, 5 } } }
local flight, hop = G.FlightTimes(nodes, paths, 20)
near(flight[1][2], 100 / 20 + 5)
near(flight[1][3], 100 / 20 + 5 + 160 / 20 + 5, "A to C through B")
eq(flight[2][1], math.huge, "paths are one-way")
eq(flight[1][4], math.huge, "unreachable node"); eq(flight[4][4], 0)
local ids = G.FlightHops(nodes, hop, 1, 3)
eq(#ids, 3); eq(ids[1], 10); eq(ids[2], 20); eq(ids[3], 30)
eq(#G.FlightHops(nodes, hop, 1, 2), 2)
eq(#G.FlightHops(nodes, hop, 2, 2), 1)

local two = { { docks = { { 0, 1, 2, "H" }, { 1, 3, 4 } }, legs = { 400, 600 }, stops = 100 } }
local docks = G.DockRides(two, "A", 20)
eq(#docks, 1); eq(#docks[1].rides, 0); eq(docks[1].index, 2); eq(docks[1].instance, 1)
eq(docks[1].wx, 3); eq(docks[1].wy, 4); eq(docks[1].kind, "dock"); eq(docks[1].transport, 1)
eq(#G.DockRides(nil, "A", 20), 0)
local both = { { docks = { { 0, 1, 2 }, { 1, 3, 4, "H" } }, legs = { 400, 600 }, stops = 100 } }
docks = G.DockRides(both, "H", 20)
eq(#docks, 2)
local loop = 100 + (400 + 600) / 20
eq(docks[1].rides[1].to, docks[2])
near(docks[1].rides[1].time, loop / 2 + 400 / 20)
near(docks[2].rides[1].time, loop / 2 + 600 / 20)
local three = { { docks = { { 0, 1, 2 }, { 0, 3, 4 }, { 1, 5, 6 } }, legs = { 400, 200, 600 }, stops = 180 } }
docks = G.DockRides(three, "A", 20)
loop = 180 + (400 + 200 + 600) / 20
eq(#docks, 3); eq(#docks[1].rides, 2)
near(docks[1].rides[1].time, loop / 2 + 400 / 20)
near(docks[1].rides[2].time, loop / 2 + 400 / 20 + 60 + 200 / 20, "intermediate dock adds 60 s")
near(docks[3].rides[1].time, loop / 2 + 600 / 20, "ride wraps past the loop end")
near(docks[3].rides[2].time, loop / 2 + 600 / 20 + 60 + 400 / 20)

local function link(to, time, step) return { to = to, time = time, step = step } end
local vs = { { id = "s" }, { id = "a" }, { id = "b" }, { id = "c" } }
local edges = {
    { link(2, 1, "ground"), link(4, 100, "boat") },
    { link(3, 1, "ground") },
    { link(4, 1, { kind = "flight", hops = { 1, 2 } }) },
    {},
}
local dist, prev, via = G.Dijkstra(vs, edges, 1)
eq(dist[1], 0); eq(dist[4], 3)
eq(prev[4], 3); eq(prev[3], 2); eq(prev[2], 1); eq(prev[1], nil)
eq(via[2], "ground"); eq(via[4].kind, "flight")
dist = G.Dijkstra(vs, { { link(2, 1, "ground") }, {}, {}, {} }, 1)
eq(dist[3], math.huge)

local steps = G.Steps(vs, prev, via, 1, 4)
eq(#steps, 2, "ground links merge")
eq(steps[1].kind, "ground"); eq(steps[1].from, vs[1]); eq(steps[1].to, vs[3]); eq(steps[1].hops, nil)
eq(steps[2].kind, "flight"); eq(steps[2].from, vs[3]); eq(steps[2].to, vs[4]); eq(steps[2].hops[2], 2)
eq(#G.Steps(vs, prev, via, 1, 1), 0)

local function brute(cost, n)
    local best = math.huge
    local function walk(path, used, total)
        if total >= best then return end
        if #path == n then best = total return end
        for b = 2, n do
            if not used[b] then
                used[b] = true; path[#path + 1] = b
                walk(path, used, total + cost[path[#path - 1]][b])
                path[#path] = nil; used[b] = nil
            end
        end
    end
    walk({ 1 }, { [1] = true }, 0)
    return best
end
math.randomseed(20260101)
local function randomCost(n)
    local pts, cost, keys = {}, {}, {}
    for i = 1, n do pts[i] = { math.random() * 1000, math.random() * 1000 }; keys[i] = i end
    for i = 1, n do
        cost[i] = {}
        for j = 1, n do
            cost[i][j] = i == j and 0 or math.sqrt((pts[i][1] - pts[j][1]) ^ 2 + (pts[i][2] - pts[j][2]) ^ 2)
        end
    end
    return cost, keys
end
local function validPermutation(path, n)
    eq(#path, n); eq(path[1], 1)
    local seen = {}
    for _, v in ipairs(path) do ok(not seen[v] and v >= 1 and v <= n, "permutation"); seen[v] = true end
end
for round = 1, 20 do
    local n = 5 + round % 4
    local cost, keys = randomCost(n)
    local path, total = G.ShortestPath(cost, keys)
    validPermutation(path, n)
    near(total, G.PathCost(cost, path), "total matches path")
    ok(math.abs(total - brute(cost, n)) < 0.01, "round " .. round .. " exact")
end
local cost14, keys14 = randomCost(14)
local t0 = os.clock()
local path14 = G.ShortestPath(cost14, keys14)
local heuristicTime = os.clock() - t0
validPermutation(path14, 14)
ok(heuristicTime < 0.5, "14 points in time: " .. heuristicTime)
local cost12, keys12 = randomCost(12)
t0 = os.clock()
local path12 = G.ShortestPath(cost12, keys12)
local exactTime = os.clock() - t0
validPermutation(path12, 12)
ok(exactTime < 0.5, "12 points in time: " .. exactTime)
local sub = G.ShortestPath({ { 0, 5, math.huge }, { 5, 0, math.huge }, { math.huge, math.huge, 0 } }, { 1, 2 })
eq(#sub, 2)

local p = { 1, 2, 3, 4, 5 }
G.Reverse(p, 2, 4); eq(table.concat(p, ","), "1,4,3,2,5")

local ground = {
    { wx = 0, wy = 0, instance = 0 }, { wx = 300, wy = 400, instance = 0 }, { wx = 10, wy = 10, instance = 1 },
}
local ge = G.GroundEdges(ground, 10, 1.3)
eq(#ge, 3); eq(#ge[1], 1); eq(#ge[2], 1); eq(#ge[3], 0)
eq(ge[1][1].to, 2); eq(ge[2][1].to, 1); eq(ge[1][1].step, "ground")
near(ge[1][1].time, 500 * 1.3 / 10); near(ge[2][1].time, 500 * 1.3 / 10)

addon("Data/TaxiPaths.lua")
ok(next(ns.TaxiPaths) ~= nil, "taxi paths present")
for from, row in pairs(ns.TaxiPaths) do
    eq(type(from), "number")
    for to, path in pairs(row) do
        eq(type(to), "number"); ok(from ~= to, "no self path")
        ok(path[1] > 0, "yards"); ok(path[2] >= 0, "stop seconds"); eq(type(path[3]), "table")
        eq(#path[3] % 2, 0)
    end
end
eq(#ns.Transports, 13)
for i, t in ipairs(ns.Transports) do
    eq(#t.legs, #t.docks, "legs match docks for transport " .. i)
    ok(t.stops > 0, "stops")
    for _, d in ipairs(t.docks) do
        eq(type(d[1]), "number"); eq(type(d[2]), "number"); eq(type(d[3]), "number")
        ok(d[4] == nil or d[4] == "A" or d[4] == "H", "dock side")
    end
    for _, y in ipairs(t.legs) do ok(y > 0, "leg yards") end
end
local wrapped = find(ns.Transports, nil, nil, function(t) return t.docks[1][2] == 2444 and t.docks[1][3] == -4348 end)
ok(wrapped, "transport whose first dock merged into its last")
eq(wrapped.legs[1], 3188, "merged leg keeps the long way round"); eq(wrapped.legs[2], 1299)

local none, noneTotal = G.ShortestPath({}, {})
eq(#none, 0, "no keys, empty path"); eq(noneTotal, 0)
local single, singleTotal = G.ShortestPath({ [7] = { [7] = 0 } }, { 7 })
eq(#single, 1, "one key"); eq(single[1], 7); eq(singleTotal, 0)
local big, bigKeys = randomCost(16)
local offset, offsetKeys = {}, {}
for i = 1, 16 do
    offset[i + 100] = {}
    for j = 1, 16 do offset[i + 100][j + 100] = big[i][j] end
    offsetKeys[i] = bigKeys[i] + 100
end
local shifted, shiftedTotal = G.ShortestPath(offset, offsetKeys)
eq(#shifted, 16); eq(shifted[1], 101, "heuristic starts from keys[1]")
near(shiftedTotal, G.PathCost(offset, shifted), "or-opt total matches its path")
local plain, plainTotal = G.ShortestPath(big, bigKeys)
near(shiftedTotal, plainTotal, "key ids do not change the heuristic")
for q = 1, 16 do eq(shifted[q], plain[q] + 100) end
