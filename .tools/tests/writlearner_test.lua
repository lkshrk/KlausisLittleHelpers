addon("Data/Writs.lua"); addon("Data/WaylaidCrates.lua"); addon("Modules/WritCrateSearch.lua"); addon("Modules/WritCrateState.lua")
local W = ns.WritState
local L = W.Learner

local row = ns.Data.Writs[1]
local store = {}
local function New() store = {} return L.New({ data = ns.Data, observed = function() return store end }) end
local function Record(list) for _, e in ipairs(list) do W.Observe(store, e) end return list end
local function Standing(id, total) return { standingID = id, current = total, total = total } end

local learner = New()
local calls = 0
local function Lazy() calls = calls + 1 return Standing(4, 1000) end
eq(#learner:OnQuestComplete(999999, Lazy), 0); eq(calls, 0, "non-writ quest reads no standing")
eq(#learner:OnFaction(Lazy), 0); eq(calls, 0, "no pending turn-in reads no standing")

local function TurnIn(l, before, after, at)
    l:OnQuestComplete(row.questID, before)
    local obs, due = l:OnTurnedIn(row.questID, at or 100)
    eq(#obs, 0)
    return Record(l:OnFaction(after)), due
end

local obs, due = TurnIn(learner, Standing(4, 1000), Standing(4, 1000 + row.rep))
eq(#obs, 1, "complete, turned in, faction: one writ reading"); eq(obs[1].kind, "writ"); eq(obs[1].rep, row.rep)
eq(obs[1].tier, row.tier); eq(obs[1].pastFriendly, false); eq(obs[1].rowRep, row.rep)
eq(due, 100 + L.WINDOW, "turn-in due after the window")
eq(store.writRep[row.tier].rep, row.rep, "plausible gain learned")
eq(#learner:Tick(due, Standing(4, 9999)), 0, "settled turn-in is not expired again")

learner = New()
eq(#TurnIn(learner, Standing(4, 1000), Standing(4, 1000 + row.rep * 3)), 1); eq(store.writRep[row.tier].rep, nil, "gain beyond 50% of the row rep not learned")
TurnIn(learner, Standing(4, 1000), Standing(4, 1000 + row.rep * 3))
eq(store.writRep[row.tier].rep, row.rep * 3, "same reading twice is learned")

learner = New()
TurnIn(learner, Standing(4, 1000), Standing(4, 1000 + row.rep + 3))
eq(store.writRep[row.tier].rep, nil, "off-step reading not learned")

learner = New()
learner:OnQuestComplete(row.questID, Standing(4, 1000))
eq(#learner:OnFaction(Standing(4, 1000)), 0, "faction update before the turn-in is ignored")
due = select(2, learner:OnTurnedIn(row.questID, 50))
eq(#learner:OnFaction(Standing(4, 1000)), 0, "unchanged standing keeps waiting")
eq(#learner:Tick(due - 0.5, Standing(4, 1000 + row.rep)), 0, "inside the window: nothing")
obs = learner:Tick(due, Standing(4, 1000 + row.rep))
eq(#obs, 1, "late reputation is read when the window ends"); eq(obs[1].rep, row.rep)

learner = New()
learner:OnQuestComplete(row.questID, Standing(4, 1000))
eq(select(2, learner:OnTurnedIn(row.questID + 1, 50)), nil, "other quest turned in: nothing pending")
eq(#learner:Tick(100, Standing(4, 1200)), 0)

learner = New()
learner:OnQuestComplete(row.questID, Standing(8, 42000))
eq(select(2, learner:OnTurnedIn(row.questID, 50)), nil, "Exalted turn-ins are not watched")

learner = New()
learner:OnQuestComplete(row.questID, Standing(5, 3500))
due = select(2, learner:OnTurnedIn(row.questID, 10))
eq(#learner:OnFaction(Standing(5, 3500)), 0)
obs = Record(learner:Tick(due, Standing(5, 3500)))
eq(#obs, 1); eq(obs[1].rep, 0, "no gain past Friendly reads as 0"); eq(obs[1].pastFriendly, true)
eq(store.writRep[row.tier].pastFriendly.yes, nil, "a single zero is not trusted")
learner:OnQuestComplete(row.questID, Standing(5, 3500))
due = select(2, learner:OnTurnedIn(row.questID, 20))
Record(learner:Tick(due, Standing(5, 3500)))
eq(store.writRep[row.tier].pastFriendly.yes, 0, "second zero confirms it")

learner = New()
learner:OnQuestComplete(row.questID, Standing(4, 1000))
local _, first = learner:OnTurnedIn(row.questID, 10)
learner:OnQuestComplete(row.questID, Standing(4, 1000))
local _, second = learner:OnTurnedIn(row.questID, 12)
eq(#learner:Tick(first, Standing(4, 1000)), 0, "an older timer does not expire a newer turn-in")
eq(#learner:Tick(second, Standing(4, 1000)), 0, "below Friendly an unchanged standing records nothing")
eq(#learner:OnFaction(Standing(4, 2000)), 0, "and the turn-in is gone")

local GATHERED = 248768
local function Crates(order, gain, gap, known)
    local l = New()
    if known then store.sealedFavor = { ["artisan:gathered"] = known } end
    l:OnBags({ [GATHERED] = 2 }, 0)
    local out = {}
    local function Add(list) for _, e in ipairs(list) do out[#out + 1] = e end end
    if order == "bags" then
        Add(l:OnBags({ [GATHERED] = 1 }, 1))
        Add(l:OnCurrency(W.FAVOR_CURRENCY, gain, 1 + gap))
    else
        Add(l:OnCurrency(W.FAVOR_CURRENCY, gain, 1))
        Add(l:OnBags({ [GATHERED] = 1 }, 1 + gap))
    end
    return out, l
end
obs = Crates("bags", 20, 0)
eq(#obs, 1, "bag update then currency"); eq(obs[1].kind, "crate"); eq(obs[1].key, "artisan:gathered"); eq(obs[1].favor, 20)
obs = Crates("currency", 25, 0.2)
eq(#obs, 1, "currency then bag update"); eq(obs[1].favor, 25)
eq(#Crates("currency", 25, 5.5), 0, "departure after the window is not matched")
eq(#Crates("bags", 25, 5.5), 0, "gain after the window is not matched")
eq(#Crates("bags", 23, 0), 0, "gain off the 5 step ignored")
eq(Crates("bags", 40, 0, 20)[1].favor, 20, "known favor doubled is halved")
eq(#Crates("bags", 25, 0, 20), 0, "known favor: other gains ignored")

learner = New()
learner:OnBags({ [GATHERED] = 2 }, 0)
learner:OnBags({ [GATHERED] = 1 }, 1)
eq(#learner:OnCurrency(W.FAVOR_CURRENCY + 1, 20, 1), 0, "other currency ignored")
eq(#learner:OnCurrency(W.FAVOR_CURRENCY, -15, 1), 0, "spent favor ignored")
eq(#learner:OnCurrency(W.FAVOR_CURRENCY, nil, 1), 0, "missing change ignored")
eq(#learner:OnCurrency(W.FAVOR_CURRENCY, 20, 1), 1, "departure still pending afterwards")

learner = New()
learner:OnBags({ [GATHERED] = 1, [248772] = 1 }, 0)
learner:OnBags({ [GATHERED] = 0, [248772] = 0 }, 1)
eq(#learner:OnCurrency(W.FAVOR_CURRENCY, 20, 1), 0, "two crate kinds at once: skipped")
learner:OnBags({ [GATHERED] = 0, [248772] = 0 }, 1.5)
eq(#learner:OnCurrency(W.FAVOR_CURRENCY, 20, 2), 0, "and the departures are dropped")

learner = New()
learner:OnBags({ [248709] = 1 }, 0)
learner:OnBags({ [248709] = 0 }, 1)
eq(#learner:OnCurrency(W.FAVOR_CURRENCY, 30, 1), 0, "empty crate departure is not a sealed crate")
learner:OnBags({ [GATHERED] = 1 }, 10)
eq(#learner:OnBags({ [GATHERED] = 0 }, 11), 0, "stale gain dropped")
eq(#learner:OnCurrency(W.FAVOR_CURRENCY, 20, 11), 1, "Sealed crates matched by item ID")
