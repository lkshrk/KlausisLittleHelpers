addon("Modules/TurnInRouteGraph.lua")
local G = ns.RouteGraph

local function ScanDijkstra(vertices, edges, source)
    local n = #vertices
    local dist, prev, via, done = {}, {}, {}, {}
    for v = 1, n do dist[v] = math.huge end
    dist[source] = 0
    for _ = 1, n do
        local u, best = nil, math.huge
        for v = 1, n do
            if not done[v] and dist[v] < best then u, best = v, dist[v] end
        end
        if not u then break end
        done[u] = true
        for _, edge in ipairs(edges[u]) do
            local t = best + edge.time
            if t < dist[edge.to] then dist[edge.to], prev[edge.to], via[edge.to] = t, u, edge.step end
        end
    end
    return dist, prev, via
end

local function FullTwoOpt(cost, path, total)
    local n, improved = #path, true
    while improved do
        improved = false
        for i = 2, n - 1 do
            for j = i + 1, n do
                G.Reverse(path, i, j)
                local t = G.PathCost(cost, path)
                if t < total - 0.01 then
                    total, improved = t, true
                else
                    G.Reverse(path, i, j)
                end
            end
        end
    end
    return total
end

math.randomseed(20261124)

local function RandomGraph(n, density, integer)
    local vertices, edges = {}, {}
    for v = 1, n do vertices[v], edges[v] = { id = v }, {} end
    for a = 1, n do
        for b = 1, n do
            if a ~= b and math.random() < density then
                local time = integer and math.random(0, 6) or math.random() * 100
                edges[a][#edges[a] + 1] = { to = b, time = time, step = (math.random() < 0.5) and "ground" or { kind = "flight" } }
            end
        end
    end
    return vertices, edges
end

local mismatches = 0
for g = 1, 200 do
    local n = math.random(1, 60)
    local vertices, edges = RandomGraph(n, math.random() * 0.4, g % 2 == 0)
    local source = math.random(1, n)
    local d1, p1, v1 = G.Dijkstra(vertices, edges, source)
    local d2, p2, v2 = ScanDijkstra(vertices, edges, source)
    for v = 1, n do
        if d1[v] ~= d2[v] or p1[v] ~= p2[v] or v1[v] ~= v2[v] then mismatches = mismatches + 1 end
    end
end
eq(mismatches, 0, "heap Dijkstra matches the scan on 200 random graphs, ties included")

local function RandomCost(n, integer, holes)
    local cost = {}
    for a = 1, n do
        cost[a] = {}
        for b = 1, n do
            if a == b then
                cost[a][b] = 0
            elseif holes and math.random() < 0.05 then
                cost[a][b] = math.huge
            else
                cost[a][b] = integer and math.random(1, 9) or math.random() * 1000
            end
        end
    end
    return cost
end

local function Shuffled(n)
    local path = { 1 }
    for v = 2, n do path[v] = v end
    for v = n, 3, -1 do
        local k = math.random(2, v)
        path[v], path[k] = path[k], path[v]
    end
    return path
end

mismatches = 0
for g = 1, 200 do
    local n = math.random(2, 40)
    local cost = RandomCost(n, g % 3 == 0, g % 5 == 0)
    local a = Shuffled(n)
    local b = {}
    for k, v in ipairs(a) do b[k] = v end
    local ta = G.TwoOpt(cost, a, G.PathCost(cost, a))
    local tb = FullTwoOpt(cost, b, G.PathCost(cost, b))
    if ta ~= tb or table.concat(a, ",") ~= table.concat(b, ",") then mismatches = mismatches + 1 end
end
eq(mismatches, 0, "incremental TwoOpt matches the full recompute on 200 random directed costs")
