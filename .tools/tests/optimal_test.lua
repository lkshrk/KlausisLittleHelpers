addon("Modules/WritCrateSearch.lua")
local S = ns.WritSearch

local function rnd(a, b) return math.random(a, b) end
local REPS = { 75, 125, 200 }

local function bestWrits(writs, need)
    if need <= 0 then return 0, 0 end
    local best, bestGain
    for mask = 0, 2 ^ #writs - 1 do
        local cost, gain, m = 0, 0, mask
        for i = 1, #writs do
            if m % 2 == 1 then cost, gain = cost + writs[i].cost, gain + writs[i].rep end
            m = math.floor(m / 2)
        end
        if gain >= need and (not best or cost < best) then best, bestGain = cost, gain end
    end
    return best, bestGain
end

local function maxWritGain(writs)
    local g = 0
    for _, w in ipairs(writs) do g = g + w.rep end
    return g
end

local function bestFavor(crates, need)
    if need <= 0 then return 0 end
    local best
    local function walk(i, favor, cost)
        if best and cost >= best then return end
        if favor >= need then
            best = cost
            return
        end
        if i > #crates then return end
        local c = crates[i]
        local most = math.ceil((need - favor) / c.favor)
        for n = 0, most do
            local owned = math.min(n, c.owned or 0)
            local bought = n - owned
            if bought > 0 and not c.buyCost then break end
            local buy = bought > 0 and bought * (c.buyCost + c.fillCost) or 0
            walk(i + 1, favor + n * c.favor, cost + owned * c.fillCost + buy)
        end
    end
    walk(1, 0, 0)
    return best
end

local function Brute(writs, target, receipts)
    local best, bestGain
    local rmax = receipts and math.ceil(target / 50) or 0
    for r = 0, rmax do
        local need = math.max(0, target - 50 * r)
        local wc, wg = bestWrits(writs, need)
        local feasible = wc ~= nil
        if not feasible then wc, wg = nil, maxWritGain(writs) end
        local cost = wc
        if r > 0 and cost then
            if not receipts.crateCost then
                cost = nil
            else
                cost = cost + r * receipts.crateCost
                local balance = receipts.useBalance and receipts.favorBalance or 0
                local fc = bestFavor(receipts.crates, math.max(0, 15 * r - balance))
                cost = fc and cost + fc or nil
            end
        end
        if feasible and cost and (not best or cost < best) then best, bestGain = cost, 50 * r + wg end
    end
    return best, bestGain
end

math.randomseed(20261124)
local checked, mismatches = 0, {}
for case = 1, 250 do
    local writs = {}
    for i = 1, rnd(1, 8) do
        writs[i] = { ref = { id = i }, cost = rnd(50, 20000), rep = REPS[rnd(1, 3)], zone = "Z" .. rnd(1, 4) }
    end
    local target = rnd(1, 24) * 25
    local receipts
    if rnd(1, 3) > 1 then
        local crates = {}
        for i = 1, rnd(1, 3) do
            crates[i] = { ref = { id = i }, favor = ({ 5, 10, 15, 20, 30 })[rnd(1, 5)], fillCost = rnd(100, 6000),
                owned = 0, buyCost = rnd(1, 4) > 1 and rnd(50, 900) or nil, confirmed = true }
        end
        receipts = { favorBalance = rnd(0, 60), useBalance = rnd(0, 1) == 1, crateCost = rnd(1, 5) > 1 and rnd(20, 600) or nil,
            crates = crates, ownedEmpty = 0 }
    end
    local plan = S.RepPlan(writs, target, receipts, nil)
    local want = Brute(writs, target, receipts)
    checked = checked + 1
    if want then
        if plan.short > 0 or math.abs(plan.cost - want) > 0.001 then
            mismatches[#mismatches + 1] = ("case %d: solver %s (short %d), cheapest %s"):format(case, tostring(plan.cost), plan.short, tostring(want))
        end
    elseif plan.short == 0 then
        mismatches[#mismatches + 1] = ("case %d: solver claims to reach %d, brute force finds no way"):format(case, target)
    end
end
eq(checked, 250)
ok(#mismatches == 0, "RepPlan matches brute force: " .. table.concat(mismatches, "; ", 1, math.min(#mismatches, 5)))

local favorMismatch = {}
for case = 1, 200 do
    local crates = {}
    for i = 1, rnd(1, 3) do
        crates[i] = { ref = { id = i }, favor = ({ 5, 10, 15, 20, 30 })[rnd(1, 5)], fillCost = rnd(100, 6000),
            owned = rnd(0, 2), buyCost = rnd(1, 4) > 1 and rnd(50, 900) or nil, confirmed = true }
    end
    local target = rnd(1, 30) * 5
    local plan = S.FavorPlan(crates, target)
    local want = bestFavor(crates, target)
    if want and (plan.short > 0 or math.abs(plan.cost - want) > 0.001) then
        favorMismatch[#favorMismatch + 1] = ("case %d: solver %s, cheapest %s"):format(case, tostring(plan.cost), tostring(want))
    end
end
ok(#favorMismatch == 0, "FavorPlan matches brute force: " .. table.concat(favorMismatch, "; ", 1, math.min(#favorMismatch, 5)))

local function BruteOwned(writs, target, receipts)
    local crates = receipts.crates
    local pooled = 0
    for _, c in ipairs(crates) do pooled = pooled + (c.owned or 0) end
    local plain = math.max(0, receipts.ownedEmpty - pooled)
    local best
    for r = 0, math.ceil(target / 50) do
        local wc = bestWrits(writs, math.max(0, target - 50 * r))
        if wc then
            local used = math.min(r, receipts.ownedEmpty)
            local bought = r - used
            if bought == 0 or receipts.crateCost then
                local fromPool = math.max(0, used - plain)
                local base = wc + bought * (receipts.crateCost or 0)
                local favorNeed = math.max(0, 15 * r - (receipts.useBalance and receipts.favorBalance or 0))
                local function split(i, left, copy)
                    if i > #crates then
                        if left == 0 then
                            local fc = bestFavor(copy, favorNeed)
                            if fc and (not best or base + fc < best) then best = base + fc end
                        end
                        return
                    end
                    for take = 0, math.min(left, crates[i].owned or 0) do
                        local c = {}
                        for k, v in pairs(crates[i]) do c[k] = v end
                        c.owned = (c.owned or 0) - take
                        copy[i] = c
                        split(i + 1, left - take, copy)
                    end
                end
                split(1, fromPool, {})
            end
        end
    end
    return best
end

local ownedMismatch = {}
for case = 1, 200 do
    local writs = {}
    for i = 1, rnd(0, 6) do
        writs[i] = { ref = { id = i }, cost = rnd(50, 20000), rep = REPS[rnd(1, 3)], zone = "Z" .. rnd(1, 4) }
    end
    local crates, pooled = {}, 0
    for i = 1, rnd(1, 3) do
        crates[i] = { ref = { id = i }, favor = ({ 5, 10, 15, 20, 30 })[rnd(1, 5)], fillCost = rnd(100, 6000),
            owned = rnd(0, 3), buyCost = rnd(1, 4) > 1 and rnd(50, 900) or nil, confirmed = true }
        pooled = pooled + crates[i].owned
    end
    local receipts = { favorBalance = rnd(0, 60), useBalance = rnd(0, 1) == 1, crateCost = rnd(1, 4) > 1 and rnd(20, 600) or nil,
        crates = crates, ownedEmpty = pooled + rnd(0, 3) }
    local target = rnd(1, 16) * 25
    local plan = S.RepPlan(writs, target, receipts, nil)
    local want = BruteOwned(writs, target, receipts)
    if want and (plan.short > 0 or math.abs(plan.cost - want) > 0.001) then
        ownedMismatch[#ownedMismatch + 1] = ("case %d: solver %s, cheapest %s"):format(case, tostring(plan.cost), tostring(want))
    end
end
ok(#ownedMismatch == 0, ("owned crates split between filling and receipts: %d of 200 dearer than needed: %s"):format(
    #ownedMismatch, table.concat(ownedMismatch, "; ", 1, math.min(#ownedMismatch, 5))))
