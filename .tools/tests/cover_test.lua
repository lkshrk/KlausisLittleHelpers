addon("Modules/WritCrateSearch.lua")
local S = ns.WritSearch
local function it(cost, gain, u) return { cost = cost, gain = gain, unbounded = u } end
local r = S.Cover({ it(43, 125), it(78, 125), it(50, 75), it(52, 75) }, 200, 25)
eq(r.cost, 93); eq(r.gain, 200); eq(r.short, 0)
r = S.Cover({ it(10, 50, true) }, 120, 25); eq(r.cost, 30); eq(r.picks[1].count, 3)
r = S.Cover({ it(43, 125) }, 0, 25); eq(#r.picks, 0); eq(r.short, 0)
r = S.Cover({ it(43, 125), it(50, 75) }, 500, 25)
eq(r.gain, 200); eq(r.short, 300); eq(r.cost, 93)
local big = {}; for i = 1, 150 do big[i] = it(4000 + i * 37, ({75, 125, 200})[i % 3 + 1]) end
local t = os.clock(); S.Cover(big, 42000, 25); ok(os.clock() - t < 0.5, "exalted-size in time")
local best = S.CoverTable({ it(43, 125), it(50, 75) }, 200, 25)
eq(best[0], 0); eq(best[3], 43); eq(best[5], 43); eq(best[6], 93); eq(best[8], 93)
ok(S.CoverTable({ it(43, 125) }, 200, 25)[8] == math.huge, "impossible state")
