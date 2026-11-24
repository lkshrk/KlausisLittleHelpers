local _, ns = ...

ns.WritSearch = ns.WritSearch or {}
local S = ns.WritSearch

local floor, ceil, huge = math.floor, math.ceil, math.huge

local function solve(items, target, step)
    local K = ceil(target / step)
    local dp = {}
    for k = 0, K do dp[k] = huge end
    dp[0] = 0
    local layers = {}
    for i = 1, #items do
        local item = items[i]
        local g = floor(item.gain / step + 0.5)
        local take = {}
        layers[i] = take
        if g > 0 then
            local cost = item.cost
            if item.unbounded then
                for k = 0, K - 1 do
                    local c = dp[k] + cost
                    local n = k + g
                    if n > K then n = K end
                    if c < dp[n] then dp[n] = c; take[n] = k end
                end
            else
                for k = K - 1, 0, -1 do
                    local c = dp[k] + cost
                    local n = k + g
                    if n > K then n = K end
                    if c < dp[n] then dp[n] = c; take[n] = k end
                end
            end
        end
    end
    return dp, layers, K
end

function S.CoverTable(items, target, step)
    local dp, _, K = solve(items, target, step)
    for k = K - 1, 0, -1 do
        if dp[k + 1] < dp[k] then dp[k] = dp[k + 1] end
    end
    return dp
end

function S.Cover(items, target, step)
    local result = { picks = {}, cost = 0, gain = 0, short = 0 }
    if target <= 0 then return result end
    local dp, layers, K = solve(items, target, step)
    local k = K
    while k > 0 and dp[k] == huge do k = k - 1 end
    local counts = {}
    local state = k
    for i = #items, 1, -1 do
        local take = layers[i]
        local prev = take[state]
        if prev then
            if items[i].unbounded then
                while prev do
                    counts[i] = (counts[i] or 0) + 1
                    state = prev
                    prev = take[state]
                end
            else
                counts[i] = 1
                state = prev
            end
        end
    end
    for i = 1, #items do
        if counts[i] then
            result.picks[#result.picks + 1] = { item = items[i], count = counts[i] }
            result.gain = result.gain + items[i].gain * counts[i]
        end
    end
    result.cost = dp[k]
    result.short = result.gain >= target and 0 or target - result.gain
    return result
end

S.REP_STEP = 25
local REP_STEP, FAVOR_STEP = S.REP_STEP, 5
local RECEIPT_REP, RECEIPT_FAVOR = 50, 15

local function favorItems(crates, target)
    local items = {}
    for _, c in ipairs(crates) do
        if c.favor > 0 then
            local owned = math.min(c.owned or 0, ceil(target / c.favor))
            for _ = 1, owned do
                items[#items + 1] = { cost = c.fillCost, gain = c.favor, ref = { crate = c, owned = true } }
            end
            if c.buyCost then
                items[#items + 1] = {
                    cost = c.buyCost + c.fillCost, gain = c.favor, unbounded = true, ref = { crate = c, owned = false },
                }
            end
        end
    end
    return items
end

local function favorPlan(crates, target)
    local plan = { lines = {}, cost = 0, gain = 0, short = 0, zones = 0 }
    if target <= 0 then return plan end
    local res = S.Cover(favorItems(crates, target), target, FAVOR_STEP)
    local byKey = {}
    for _, pick in ipairs(res.picks) do
        local key = pick.item.ref
        local c = key.crate
        local line = byKey[c] and byKey[c][key.owned]
        if not line then
            line = {
                kind = "crate", ref = c.ref, count = 0, cost = 0, gain = 0, owned = key.owned, confirmed = c.confirmed,
            }
            byKey[c] = byKey[c] or {}
            byKey[c][key.owned] = line
            plan.lines[#plan.lines + 1] = line
        end
        line.count = line.count + pick.count
        line.cost = line.cost + pick.item.cost * pick.count
        line.gain = line.gain + c.favor * pick.count
    end
    plan.cost, plan.gain, plan.short = res.cost, res.gain, res.short
    return plan
end

S.FavorPlan = favorPlan

local function writItems(writs)
    local items = {}
    for i, w in ipairs(writs) do items[i] = { cost = w.cost, gain = w.rep, ref = w } end
    return items
end

local function withoutEmpties(crates, ownedEmpty, used)
    local pooled = 0
    for _, c in ipairs(crates) do pooled = pooled + (c.owned or 0) end
    local remove = used - math.max(0, ownedEmpty - pooled)
    if remove <= 0 then return crates end
    local order = {}
    for i, c in ipairs(crates) do
        if (c.owned or 0) > 0 then order[#order + 1] = i end
    end
    table.sort(order, function(a, b)
        local ca, cb = crates[a], crates[b]
        return ca.favor * cb.fillCost < cb.favor * ca.fillCost
    end)
    local left = {}
    for _, i in ipairs(order) do
        local take = math.min(remove, crates[i].owned)
        left[i] = crates[i].owned - take
        remove = remove - take
    end
    local out = {}
    for i, c in ipairs(crates) do
        if left[i] then
            local copy = {}
            for k, v in pairs(c) do copy[k] = v end
            copy.owned = left[i]
            out[i] = copy
        else
            out[i] = c
        end
    end
    return out
end

function S.RepPlan(writs, target, receipts, writCap)
    local plan = { lines = {}, cost = 0, gain = 0, short = 0, zones = 0, target = target }
    if target <= 0 then return plan end
    local items = writItems(writs)
    local best = S.CoverTable(items, target, REP_STEP)
    local kmax = #best
    while kmax > 0 and best[kmax] == huge do kmax = kmax - 1 end

    local rmax = receipts and ceil(target / RECEIPT_REP) or 0
    local balance = receipts and receipts.useBalance and receipts.favorBalance or 0
    local ownedEmpty = receipts and receipts.ownedEmpty or 0
    local favorBest = {}
    local function favorTable(used)
        local t = favorBest[used]
        if not t then
            local crates = withoutEmpties(receipts.crates, ownedEmpty, used)
            t = S.CoverTable(favorItems(crates, rmax * RECEIPT_FAVOR), rmax * RECEIPT_FAVOR, FAVOR_STEP)
            favorBest[used] = t
        end
        return t
    end

    local function writNeed(r)
        local need = math.max(0, target - RECEIPT_REP * r)
        return writCap and math.min(need, writCap) or need
    end

    local pick
    for r = 0, rmax do
        local need = writNeed(r)
        local k = ceil(need / REP_STEP)
        local cost = best[math.min(k, kmax)]
        local gain = RECEIPT_REP * r + math.min(k, kmax) * REP_STEP
        if r > 0 then
            local bought = math.max(0, r - ownedEmpty)
            if bought > 0 and not receipts.crateCost then
                cost = huge
            else
                cost = cost + bought * (receipts.crateCost or 0)
                local rest = math.max(0, r * RECEIPT_FAVOR - balance)
                local favorCost = rest > 0 and favorTable(math.min(r, ownedEmpty))[ceil(rest / FAVOR_STEP)] or 0
                cost = cost + favorCost
            end
        end
        if cost < huge then
            local feasible = gain >= target
            local better
            if not pick then
                better = true
            elseif feasible ~= pick.feasible then
                better = feasible
            elseif feasible then
                better = cost < pick.cost
            else
                better = gain > pick.gain or (gain == pick.gain and cost < pick.cost)
            end
            if better then pick = { r = r, cost = cost, gain = gain, feasible = feasible } end
        end
    end

    local r = pick.r
    local writPlan = S.Cover(items, writNeed(r), REP_STEP)
    local zones = {}
    for _, p in ipairs(writPlan.picks) do
        local w = p.item.ref
        plan.lines[#plan.lines + 1] = {
            kind = "writ", ref = w.ref, count = p.count, cost = w.cost * p.count, gain = w.rep * p.count,
            owned = false, zone = w.zone,
        }
        local z = w.zone or w
        if not zones[z] then
            zones[z] = true
            plan.zones = plan.zones + 1
        end
    end
    plan.cost, plan.gain = writPlan.cost, writPlan.gain
    if r > 0 then
        local bought = math.max(0, r - ownedEmpty)
        local crateCost = bought * (receipts.crateCost or 0)
        plan.lines[#plan.lines + 1] = {
            kind = "receipt", ref = nil, count = r, cost = crateCost, gain = RECEIPT_REP * r, owned = false,
            bought = bought, crateRef = bought > 0 and receipts.crateRef or nil,
        }
        plan.cost = plan.cost + crateCost
        plan.gain = plan.gain + RECEIPT_REP * r
        local crates = withoutEmpties(receipts.crates, ownedEmpty, math.min(r, ownedEmpty))
        local need = r * RECEIPT_FAVOR
        local favor = favorPlan(crates, math.max(0, need - balance))
        for _, line in ipairs(favor.lines) do plan.lines[#plan.lines + 1] = line end
        plan.cost = plan.cost + favor.cost
        plan.favor = { need = need, fromBalance = math.min(balance, need), fromCrates = favor.gain }
    end
    plan.short = math.max(0, target - plan.gain)
    return plan
end

local function zoneCount(writs, counts)
    local seen, n = {}, 0
    for i = 1, #writs do
        local z, c = writs[i].zone or writs[i], counts[i] or 0
        if c > 0 and not seen[z] then
            seen[z] = true
            n = n + 1
        end
    end
    return n
end

function S.Tiebreak(plan, writs, threshold)
    local rest = { cost = 0, gain = 0 }
    local counts, at = {}, {}
    for i, w in ipairs(writs) do at[w.ref] = i end
    local kept = {}
    for _, line in ipairs(plan.lines) do
        if line.kind == "writ" then
            local i = at[line.ref]
            counts[i] = (counts[i] or 0) + line.count
        else
            kept[#kept + 1] = line
            rest.cost = rest.cost + line.cost
            rest.gain = rest.gain + line.gain
        end
    end
    local writCost = 0
    for i = 1, #writs do writCost = writCost + writs[i].cost * (counts[i] or 0) end
    plan.cheapestCost = plan.cost
    if plan.short > 0 or not next(counts) then return plan end

    local limit = plan.cheapestCost * (1 + threshold)
    local zones = zoneCount(writs, counts)
    while true do
        local bestOut, bestIn, bestDelta
        for out = 1, #writs do
            local c = counts[out] or 0
            if c > 0 then
                for into, w in ipairs(writs) do
                    local delta = w.cost - writs[out].cost
                    local gain = plan.gain - writs[out].rep + w.rep
                    if (counts[into] or 0) == 0 and gain >= plan.target and rest.cost + writCost + delta <= limit
                        and (not bestDelta or delta < bestDelta) then
                        counts[out], counts[into] = c - 1, (counts[into] or 0) + 1
                        local fewer = zoneCount(writs, counts) < zones
                        counts[out], counts[into] = c, counts[into] - 1
                        if fewer then bestOut, bestIn, bestDelta = out, into, delta end
                    end
                end
            end
        end
        if not bestOut then break end
        counts[bestOut] = counts[bestOut] - 1
        counts[bestIn] = (counts[bestIn] or 0) + 1
        writCost = writCost + bestDelta
        plan.gain = plan.gain - writs[bestOut].rep + writs[bestIn].rep
        zones = zoneCount(writs, counts)
    end

    local lines = {}
    for i, w in ipairs(writs) do
        local c = counts[i]
        if c and c > 0 then
            lines[#lines + 1] = {
                kind = "writ", ref = w.ref, count = c, cost = w.cost * c, gain = w.rep * c, owned = false, zone = w.zone,
            }
        end
    end
    for _, line in ipairs(kept) do lines[#lines + 1] = line end
    plan.lines, plan.zones = lines, zones
    plan.cost = rest.cost + writCost
    plan.short = math.max(0, plan.target - plan.gain)
    return plan
end
