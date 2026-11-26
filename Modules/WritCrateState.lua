local _, ns = ...

ns.WritState = ns.WritState or {}
local W = ns.WritState

W.FAVOR_CURRENCY = 3402
W.CALLER = "KlausisLittleHelpers"

local REP_STEP = ns.WritSearch.REP_STEP
local CALLER = W.CALLER
local WRIT_LEVEL = 10
local CHAR_KEY = "WritCratePlanner"

function W.SealedKey(tier, kind)
    return tier .. ":" .. kind
end

local function ObservedRep(observed, tier)
    local t = observed and observed.writRep and observed.writRep[tier]
    local rep = t and t.rep
    if type(rep) ~= "number" then return nil end
    local floored = math.floor(rep / REP_STEP) * REP_STEP
    if floored > 0 then return floored end
end

local function Plausible(rep, rowRep)
    if rep % REP_STEP ~= 0 then return false end
    return type(rowRep) ~= "number" or math.abs(rep - rowRep) <= rowRep * 0.5
end

function W.BuildCandidates(input)
    local data, prices, owned = input.data, input.prices, input.owned
    local done, faction, onQuest = input.doneToday, input.faction, input.onQuest or {}
    local seen = input.observed and input.observed.sealedFavor or {}
    local out = { writs = {}, crates = {}, unpriced = {} }
    local writs = data.Writs
    if input.level and input.level < WRIT_LEVEL then
        writs, out.lowLevel = {}, true
    end

    for _, row in ipairs(writs) do
        if not row.friendly or not faction or row.friendly:find(faction, 1, true) then
            if not done[row.questID] then
                local haveWrit = onQuest[row.questID] or (owned[row.writID] or 0) > 0
                local writPart = haveWrit and 0 or prices[row.writID]
                local qty = row.qty or 1
                local itemPart = prices[row.itemID] and prices[row.itemID] * qty
                if not itemPart and (owned[row.itemID] or 0) >= qty then itemPart = 0 end
                if writPart and itemPart then
                    out.writs[#out.writs + 1] = {
                        ref = row, cost = writPart + itemPart, rep = ObservedRep(input.observed, row.tier) or row.rep,
                        zone = row.zone,
                    }
                else
                    out.unpriced[#out.unpriced + 1] = row.name
                end
            end
        end
    end

    for _, row in ipairs(data.WaylaidCrates) do
        local best, bestCost
        for _, bundle in ipairs(row.bundles) do
            local price = prices[bundle.itemID]
            if price then
                local cost = price * bundle.count
                if not bestCost or cost < bestCost then best, bestCost = bundle, cost end
            end
        end
        local have, buyCost = owned[row.itemID] or 0, prices[row.itemID]
        local known = seen[W.SealedKey(row.tier, row.kind)]
        if not best then
            out.unpriced[#out.unpriced + 1] = row.name
        elseif have > 0 or buyCost then
            out.crates[#out.crates + 1] = {
                ref = row, favor = known or best.favor or row.favor,
                confirmed = known ~= nil or row.confirmed,
                fillCost = bestCost, fillBundle = best, owned = have, buyCost = buyCost,
            }
        end
    end
    return out
end

function W.Observe(store, event)
    store = store or {}
    if event.kind == "crate" then
        store.sealedFavor = store.sealedFavor or {}
        store.sealedFavor[event.key] = event.favor
    elseif event.kind == "writ" then
        store.writRep = store.writRep or {}
        local t = store.writRep[event.tier] or {}
        store.writRep[event.tier] = t
        t.pastFriendly = t.pastFriendly or {}
        t.unconfirmed = t.unconfirmed or {}
        local side, rep = event.pastFriendly and "yes" or "no", event.rep
        if rep == 0 then
            if event.pastFriendly then
                if t.unconfirmed.yes == 0 then
                    t.pastFriendly.yes, t.unconfirmed.yes = 0, nil
                else
                    t.unconfirmed.yes = 0
                end
            end
        elseif Plausible(rep, event.rowRep) or t.unconfirmed[side] == rep then
            t.pastFriendly[side], t.unconfirmed[side] = rep, nil
            if not event.pastFriendly then t.rep = rep end
        else
            t.unconfirmed[side] = rep
        end
    end
    return store
end

function W.SettleWrit(before, after, expired)
    local b, a = before.total or before.current, after and (after.total or after.current)
    if not (b and a) then return nil end
    if a ~= b then
        return a > b and a - b or nil
    end
    if expired and before.standingID >= 5 then return 0 end
    return nil
end

function W.PastFriendly(observed)
    local found
    for _, t in pairs(observed and observed.writRep or {}) do
        local rep = t.pastFriendly and t.pastFriendly.yes
        if rep and rep > 0 then return rep end
        if rep == 0 then found = 0 end
    end
    return found
end

function W.CrateFavor(row, gain, known)
    local confirmed = known ~= nil or row.confirmed
    known = known or row.favor
    if gain == known then return known end
    if confirmed then return gain == known * 2 and known or nil end
    if gain % 5 == 0 and gain >= 5 and gain <= 80 then return gain end
    return nil
end

function W.SealedRow(data, itemID)
    local sealed = data.SealedCrates and data.SealedCrates[itemID]
    if not (sealed and sealed.kind) then return nil end
    for _, row in ipairs(data.WaylaidCrates) do
        if row.tier == sealed.tier and row.kind == sealed.kind then return row, W.SealedKey(sealed.tier, sealed.kind) end
    end
    return nil
end

function W.DepartedCrate(data, departed, now, window)
    local found, foundKey, kinds = nil, nil, 0
    for itemID, d in pairs(departed) do
        if now - d.at <= window then
            local row, key = W.SealedRow(data, itemID)
            if row and key ~= foundKey then
                found, foundKey, kinds = row, key, kinds + 1
            end
        end
    end
    if kinds ~= 1 then return nil, kinds end
    return found, kinds, foundKey
end

local function CharData()
    return ns.CharData(CHAR_KEY)
end

function W.ContainerIDs(env)
    local E = type(env.Enum) == "table" and env.Enum.BagIndex or {}
    local first = E.Backpack or env.BACKPACK_CONTAINER or 0
    local last = first + (env.NUM_TOTAL_EQUIPPED_BAG_SLOTS or env.NUM_BAG_SLOTS or 4)
    local bags, bank = {}, { E.Bank }
    for id = first, last do bags[#bags + 1] = id end
    local i = 1
    while E["CharacterBankTab_" .. i] do
        bank[#bank + 1] = E["CharacterBankTab_" .. i]
        i = i + 1
    end
    return bags, bank
end

local function CountBags(ids, into)
    local C = _G.C_Container
    if not C or not C.GetContainerNumSlots or not C.GetContainerItemInfo then return 0 end
    local slots = 0
    for _, bag in ipairs(ids) do
        local n = C.GetContainerNumSlots(bag) or 0
        slots = slots + n
        for slot = 1, n do
            local info = C.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                into[info.itemID] = (into[info.itemID] or 0) + (info.stackCount or 1)
            end
        end
    end
    return slots
end

function W.Observed()
    local d = CharData()
    if type(d.observed) ~= "table" then d.observed = {} end
    return d.observed
end

function W.Record(event)
    W.Observe(W.Observed(), event)
end

function W.BagCounts()
    local out = {}
    CountBags((W.ContainerIDs(_G)), out)
    return out
end

function W.SealedCounts(sealed)
    local item = _G.C_Item
    local out = {}
    if not (item and item.GetItemCount) then return out end
    for itemID in pairs(sealed or {}) do out[itemID] = item.GetItemCount(itemID) or 0 end
    return out
end

function W.ScanBank()
    local bank = {}
    local _, ids = W.ContainerIDs(_G)
    -- No slots means the bank is not readable right now; keep the last scan.
    if CountBags(ids, bank) == 0 then return end
    bank.scannedAt = _G.time and _G.time() or 0
    CharData().bank = bank
end

function W.Api()
    local A = _G.Auctionator
    return type(A) == "table" and type(A.API) == "table" and A.API.v1 or nil
end

function W.Snapshot(settings)
    local input = {
        data = ns.Data, prices = {}, owned = {}, doneToday = {}, onQuest = {}, faction = nil, notInScan = {},
        observed = W.Observed(),
    }
    local faction = _G.UnitFactionGroup and _G.UnitFactionGroup("player")
    input.faction = faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
    local level = _G.UnitLevel and _G.UnitLevel("player")
    if type(level) == "number" and level > 0 then input.level = level end

    input.bags = {}
    CountBags((W.ContainerIDs(_G)), input.bags)
    for itemID, n in pairs(input.bags) do input.owned[itemID] = n end
    if settings and settings.countBank then
        local bank = CharData().bank
        if bank then
            input.bankAt = bank.scannedAt
            for itemID, n in pairs(bank) do
                if type(itemID) == "number" then input.owned[itemID] = (input.owned[itemID] or 0) + n end
            end
        end
    end

    local auc = W.Api()
    local ages, names = {}, {}
    local function price(itemID, name)
        if input.prices[itemID] ~= nil or not auc or not auc.GetAuctionPriceByItemID then return end
        local p = auc.GetAuctionPriceByItemID(CALLER, itemID)
        if p and p > 0 then
            input.prices[itemID] = p
            names[itemID] = name
            local age = auc.GetAuctionAgeByItemID and auc.GetAuctionAgeByItemID(CALLER, itemID)
            if type(age) == "number" then
                ages[itemID] = age
                if not input.scanAge or age < input.scanAge then input.scanAge = age end
            end
        end
    end

    local quest = _G.C_QuestLog
    for _, row in ipairs(ns.Data.Writs) do
        price(row.writID, row.name); price(row.itemID, row.item)
        if quest and quest.IsQuestFlaggedCompleted and quest.IsQuestFlaggedCompleted(row.questID) then
            input.doneToday[row.questID] = true
        end
        if quest and quest.IsOnQuest and quest.IsOnQuest(row.questID) then input.onQuest[row.questID] = true end
    end
    for _, row in ipairs(ns.Data.WaylaidCrates) do
        price(row.itemID, row.name)
        for _, bundle in ipairs(row.bundles) do price(bundle.itemID, bundle.name) end
    end
    if ns.Data.UnlabeledCrate then price(ns.Data.UnlabeledCrate.itemID, ns.Data.UnlabeledCrate.name) end
    for itemID, age in pairs(ages) do
        if age > input.scanAge then
            input.prices[itemID] = nil
            input.notInScan[#input.notInScan + 1] = names[itemID] or tostring(itemID)
        end
    end
    table.sort(input.notInScan)
    return input
end

local warnedStanding = false
function W.Standing()
    local group = _G.UnitFactionGroup and _G.UnitFactionGroup("player")
    local factionID = ns.Data.CampFaction and ns.Data.CampFaction[group]
    local out = { factionID = factionID }
    local rep = _G.C_Reputation
    local data = factionID and rep and rep.GetFactionDataByID and rep.GetFactionDataByID(factionID)
    if data then
        out.standingID = data.reaction
        out.total = data.currentStanding
        out.current = (data.currentStanding or 0) - (data.currentReactionThreshold or 0)
        out.max = (data.nextReactionThreshold or 0) - (data.currentReactionThreshold or 0)
    end
    local cur = _G.C_CurrencyInfo
    local info = cur and cur.GetCurrencyInfo and cur.GetCurrencyInfo(W.FAVOR_CURRENCY)
    if info then out.favor = info.quantity or 0 end
    if not (data and info) and not warnedStanding then
        warnedStanding = true
        ns.Print("Writ & Crate Planner: the game returned no " .. (data and "Merchant's Favor" or "trade camp reputation") .. " data; it shows as unknown.")
    end
    return out
end

local Learner = {}
Learner.__index = Learner
W.Learner = Learner
Learner.WINDOW = 5
local FRIENDLY = 5

local function Current(standing)
    if type(standing) == "function" then return standing() end
    return standing
end

function Learner.New(opts)
    local self = setmetatable({ data = opts.data, observed = opts.observed, writByQuest = {}, departed = {} }, Learner)
    for _, row in ipairs(opts.data.Writs or {}) do self.writByQuest[row.questID] = row end
    return self
end

function Learner:Settle(standing, expired, out)
    local t = self.turnedIn
    if not t then return out end
    local rep = W.SettleWrit(t, Current(standing), expired)
    if rep then
        self.turnedIn = nil
        out[#out + 1] = { kind = "writ", tier = t.tier, rep = rep, pastFriendly = t.pastFriendly, rowRep = t.rowRep }
    elseif expired then
        self.turnedIn = nil
    end
    return out
end

function Learner:ResolveGain(now, out)
    local g = self.pendingGain
    if not g then return out end
    if now - g.at > Learner.WINDOW then
        self.pendingGain = nil
        return out
    end
    local row, kinds, key = W.DepartedCrate(self.data, self.departed, now, Learner.WINDOW)
    if kinds == 0 then return out end
    self.pendingGain, self.departed = nil, {}
    if not row then return out end
    local seen = self.observed().sealedFavor
    local favor = W.CrateFavor(row, g.gain, seen and seen[key])
    if favor then out[#out + 1] = { kind = "crate", key = key, favor = favor } end
    return out
end

function Learner:OnQuestComplete(questID, standing)
    local row = self.writByQuest[questID]
    local st = row and Current(standing)
    if st and st.standingID and st.standingID < 8 and st.current then
        self.opened = { questID = row.questID, tier = row.tier, rowRep = row.rep, current = st.current, total = st.total,
            standingID = st.standingID }
    else
        self.opened = nil
    end
    return {}
end

function Learner:OnTurnedIn(questID, now)
    local o = self.opened
    if not (o and o.questID == questID) then return {} end
    self.turnedIn = { tier = o.tier, rowRep = o.rowRep, current = o.current, total = o.total, standingID = o.standingID,
        pastFriendly = o.standingID >= FRIENDLY, at = now }
    self.opened = nil
    return {}, now + Learner.WINDOW
end

function Learner:OnFaction(standing)
    return self:Settle(standing, false, {})
end

function Learner:Tick(now, standing)
    local t = self.turnedIn
    if not (t and now >= t.at + Learner.WINDOW) then return {} end
    return self:Settle(standing, true, {})
end

function Learner:OnCurrency(id, change, now)
    if id ~= W.FAVOR_CURRENCY or type(change) ~= "number" or change <= 0 then return {} end
    self.pendingGain = { gain = change, at = now }
    return self:ResolveGain(now, {})
end

function Learner:OnBags(counts, now)
    if self.bags then
        for itemID, n in pairs(self.bags) do
            if (counts[itemID] or 0) < n then self.departed[itemID] = { at = now } end
        end
    end
    self.bags = counts
    return self:ResolveGain(now, {})
end
