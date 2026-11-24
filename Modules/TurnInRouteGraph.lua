local _, ns = ...

ns.RouteGraph = ns.RouteGraph or {}
local G = ns.RouteGraph

local function Distance(a, b)
    local dx, dy = a.wx - b.wx, a.wy - b.wy
    return math.sqrt(dx * dx + dy * dy)
end

function G.FlightTimes(nodes, paths, speed)
    local k, index, time, hop = #nodes, {}, {}, {}
    for i, node in ipairs(nodes) do index[node.id] = i end
    for i = 1, k do
        time[i], hop[i] = {}, {}
        for j = 1, k do time[i][j] = i == j and 0 or math.huge end
        for to, path in pairs(paths[nodes[i].id] or {}) do
            local j = index[to]
            if j then time[i][j], hop[i][j] = path[1] / speed + path[2], j end
        end
    end
    for m = 1, k do
        local viaM = time[m]
        for i = 1, k do
            local toM = time[i][m]
            if toM < math.huge then
                local row = time[i]
                for j = 1, k do
                    if toM + viaM[j] < row[j] then row[j], hop[i][j] = toM + viaM[j], hop[i][m] end
                end
            end
        end
    end
    return time, hop
end

function G.FlightHops(nodes, hop, i, j)
    local ids = { nodes[i].id }
    while i ~= j do
        i = hop[i][j]
        ids[#ids + 1] = nodes[i].id
    end
    return ids
end

function G.DockRides(transports, side, boatSpeed)
    local docks = {}
    for t, transport in ipairs(transports or {}) do
        local loop = transport.stops
        for _, yards in ipairs(transport.legs) do loop = loop + yards / boatSpeed end
        local group = {}
        for d, dock in ipairs(transport.docks) do
            if not dock[4] or dock[4] == side then
                local entry = { kind = "dock", transport = t, index = d, wx = dock[2], wy = dock[3], instance = dock[1] }
                group[#group + 1] = entry
                docks[#docks + 1] = entry
            end
        end
        for _, from in ipairs(group) do
            from.rides = {}
            for _, to in ipairs(group) do
                if to ~= from then
                    local ride, d = 0, from.index
                    while d ~= to.index do
                        ride = ride + transport.legs[d] / boatSpeed
                        d = d % #transport.docks + 1
                        if d ~= to.index then ride = ride + 60 end
                    end
                    from.rides[#from.rides + 1] = { to = to, time = loop / 2 + ride }
                end
            end
        end
    end
    return docks
end

function G.GroundEdges(vertices, speed, detour)
    local edges = {}
    for a = 1, #vertices do edges[a] = {} end
    for a = 1, #vertices do
        local va = vertices[a]
        for b = a + 1, #vertices do
            local vb = vertices[b]
            if va.instance == vb.instance then
                local t = Distance(va, vb) * detour / speed
                edges[a][#edges[a] + 1] = { to = b, time = t, step = "ground" }
                edges[b][#edges[b] + 1] = { to = a, time = t, step = "ground" }
            end
        end
    end
    return edges
end

local function HeapLess(hd, hv, a, b)
    return hd[a] < hd[b] or (hd[a] == hd[b] and hv[a] < hv[b])
end

local function HeapPush(hd, hv, size, d, v)
    size = size + 1
    local c = size
    hd[c], hv[c] = d, v
    while c > 1 do
        local p = math.floor(c / 2)
        if not HeapLess(hd, hv, c, p) then break end
        hd[c], hd[p], hv[c], hv[p] = hd[p], hd[c], hv[p], hv[c]
        c = p
    end
    return size
end

local function HeapPop(hd, hv, size)
    local d, v = hd[1], hv[1]
    hd[1], hv[1] = hd[size], hv[size]
    hd[size], hv[size] = nil, nil
    size = size - 1
    local p = 1
    while true do
        local l, small = p * 2, p
        if l <= size and HeapLess(hd, hv, l, small) then small = l end
        if l + 1 <= size and HeapLess(hd, hv, l + 1, small) then small = l + 1 end
        if small == p then break end
        hd[p], hd[small], hv[p], hv[small] = hd[small], hd[p], hv[small], hv[p]
        p = small
    end
    return d, v, size
end

function G.Dijkstra(vertices, edges, source)
    local n = #vertices
    local dist, prev, via, done = {}, {}, {}, {}
    for v = 1, n do dist[v] = math.huge end
    dist[source] = 0
    local hd, hv, size = {}, {}, 0
    if dist[source] < math.huge then size = HeapPush(hd, hv, size, 0, source) end
    while size > 0 do
        local best, u
        best, u, size = HeapPop(hd, hv, size)
        if not done[u] and best == dist[u] then
            done[u] = true
            for _, edge in ipairs(edges[u]) do
                local t = best + edge.time
                if t < dist[edge.to] then
                    dist[edge.to], prev[edge.to], via[edge.to] = t, u, edge.step
                    size = HeapPush(hd, hv, size, t, edge.to)
                end
            end
        end
    end
    return dist, prev, via
end

function G.Steps(vertices, prev, via, source, target)
    local chain = {}
    local v = target
    while v ~= source do
        table.insert(chain, 1, { from = vertices[prev[v]], to = vertices[v], step = via[v] })
        v = prev[v]
    end
    local steps = {}
    for _, link in ipairs(chain) do
        local kind = type(link.step) == "table" and link.step.kind or link.step
        local last = steps[#steps]
        if kind == "ground" and last and last.kind == "ground" then
            last.to = link.to
        else
            steps[#steps + 1] = { kind = kind, from = link.from, to = link.to, hops = type(link.step) == "table" and link.step.hops or nil }
        end
    end
    return steps
end

function G.PathCost(cost, path)
    local total = 0
    for i = 2, #path do total = total + cost[path[i - 1]][path[i]] end
    return total
end

function G.Reverse(path, i, j)
    while i < j do
        path[i], path[j] = path[j], path[i]
        i, j = i + 1, j - 1
    end
end

local EXACT_LIMIT = 12

local function Greedy(cost, keys)
    local path, used = { keys[1] }, { [keys[1]] = true }
    for _ = 2, #keys do
        local last, best, pick = path[#path], math.huge, nil
        for _, b in ipairs(keys) do
            if not used[b] and cost[last][b] < best then best, pick = cost[last][b], b end
        end
        if not pick then break end
        used[pick] = true
        path[#path + 1] = pick
    end
    return path
end

local function SegmentFlip(cost, path, i, j)
    local flip = 0
    for k = i, j - 1 do flip = flip + cost[path[k + 1]][path[k]] - cost[path[k]][path[k + 1]] end
    return flip
end

function G.TwoOpt(cost, path, total)
    local n, improved = #path, true
    while improved do
        improved = false
        for i = 2, n - 1 do
            local flip = 0
            for j = i + 1, n do
                local first, last, before = path[i], path[j], path[j - 1]
                flip = flip + cost[last][before] - cost[before][last]
                local t, exact
                if total < math.huge then
                    local a, b = path[i - 1], path[j + 1]
                    t = total + cost[a][last] - cost[a][first] + (b and cost[first][b] - cost[last][b] or 0) + flip
                    -- near the threshold, decide on the full sum so rounding never flips a choice
                    exact = math.abs(t - (total - 0.01)) <= 1e-9 * (1 + total)
                end
                if exact or total == math.huge then
                    G.Reverse(path, i, j)
                    t = G.PathCost(cost, path)
                    if t < total - 0.01 then
                        total, improved = t, true
                        flip = SegmentFlip(cost, path, i, j)
                    else
                        G.Reverse(path, i, j)
                    end
                elseif t < total - 0.01 then
                    G.Reverse(path, i, j)
                    total, improved = G.PathCost(cost, path), true
                    flip = SegmentFlip(cost, path, i, j)
                end
            end
        end
    end
    return total
end

local function MovedAt(path, i, len, at, q)
    if q >= at + len then q = q - len elseif q >= at then return path[i + q - at] end
    if q < i then return path[q] end
    return path[q + len]
end

local function MovedCost(cost, path, i, len, at)
    local total, prev = 0, MovedAt(path, i, len, at, 1)
    for q = 2, #path do
        local here = MovedAt(path, i, len, at, q)
        total, prev = total + cost[prev][here], here
    end
    return total
end

local function OrOpt(cost, path, total)
    local n, improved = #path, true
    while improved do
        improved = false
        for len = 1, 3 do
            for i = 2, n - len + 1 do
                local j = i + len - 1
                local a, b, first, last = path[i - 1], path[j + 1], path[i], path[j]
                local cut = cost[a][first] - (b and cost[a][b] or 0) + (b and cost[last][b] or 0)
                for at = 2, n - len + 1 do
                    if at ~= i then
                        local t
                        if total < math.huge then
                            local u, v = MovedAt(path, i, len, at, at - 1), MovedAt(path, i, len, at, at + len)
                            t = total - cut + cost[u][first] + (v and cost[last][v] - cost[u][v] or 0)
                        else
                            t = MovedCost(cost, path, i, len, at)
                        end
                        if t < total - 0.01 then
                            local moved = {}
                            for q = 1, n do moved[q] = MovedAt(path, i, len, at, q) end
                            for q = 1, n do path[q] = moved[q] end
                            total, improved = G.PathCost(cost, path), true
                            break
                        end
                    end
                end
                if improved then break end
            end
            if improved then break end
        end
    end
    return total
end

local function Exact(cost, keys)
    local m = #keys - 1
    local pow = { [0] = 1 }
    for i = 1, m do pow[i] = pow[i - 1] * 2 end
    local full = pow[m] - 1
    local dp, from = {}, {}
    for mask = 1, full do dp[mask], from[mask] = {}, {} end
    for j = 1, m do dp[pow[j - 1]][j] = cost[keys[1]][keys[j + 1]] end
    for mask = 1, full do
        local row = dp[mask]
        for j = 1, m do
            local here = row[j]
            if here and here < math.huge then
                for k = 1, m do
                    if math.floor(mask / pow[k - 1]) % 2 == 0 then
                        local next = mask + pow[k - 1]
                        local t = here + cost[keys[j + 1]][keys[k + 1]]
                        local cur = dp[next][k]
                        if not cur or t < cur then dp[next][k], from[next][k] = t, j end
                    end
                end
            end
        end
    end
    local best, last = math.huge, nil
    for j = 1, m do
        local t = dp[full][j]
        if t and t < best then best, last = t, j end
    end
    if not last then return nil end
    local path, mask = {}, full
    while last do
        table.insert(path, 1, keys[last + 1])
        local prior = from[mask][last]
        mask = mask - pow[last - 1]
        last = prior
    end
    table.insert(path, 1, keys[1])
    return path, best
end

function G.ShortestPath(cost, keys)
    if #keys == 0 then return {}, 0 end
    if #keys >= 2 and #keys <= EXACT_LIMIT then
        local path, total = Exact(cost, keys)
        if path then return path, total end
    end
    local path = Greedy(cost, keys)
    local total = G.TwoOpt(cost, path, G.PathCost(cost, path))
    total = OrOpt(cost, path, total)
    return path, total
end

local HEARTH_TIME, TELEPORT_TIME = 30, 15

function G.Shortcuts(facts, opts)
    opts = opts or {}
    local known, bag = facts.knownSpells or {}, facts.reagents or {}
    local list = {}
    if opts.hearth and facts.hearth then
        local h = facts.hearth
        list[#list + 1] = { kind = "hearth", name = h.name, wx = h.wx, wy = h.wy, instance = h.instance, time = HEARTH_TIME }
    end
    if opts.teleports then
        for _, t in ipairs(ns.Teleports or {}) do
            if t.side == facts.side and known[t.spellID] and (bag[t.reagent] or 0) > 0 then
                list[#list + 1] = { kind = "teleport", name = t.name, wx = t.wx, wy = t.wy, instance = t.instance, time = TELEPORT_TIME }
            end
        end
    end
    return list
end
