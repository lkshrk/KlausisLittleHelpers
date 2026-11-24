local _, ns = ...

ns.WritDepth = ns.WritDepth or {}
local D = ns.WritDepth

function D.Cost(listings, n)
    local total, available, left = 0, 0, n
    for _, l in ipairs(listings or {}) do
        available = available + l.quantity
        if left > 0 then
            local take = math.min(left, l.quantity)
            total = total + take * l.unitPrice
            left = left - take
        end
    end
    if left > 0 then return nil, available end
    return total, available
end

function D.Needs(plan, owned, bundleOf, onQuest)
    local needs = {}
    for _, t in ipairs(ns.WritPlanner.ShoppingTerms(plan, owned, bundleOf, onQuest)) do
        needs[t.itemID] = (needs[t.itemID] or 0) + t.count
    end
    return needs
end

local function ShortPrice(list, n, available, scan)
    local part = D.Cost(list, available)
    local rest = math.max(list[#list].unitPrice, scan or 0)
    return (part + (n - available) * rest) / n
end

function D.EffectivePrices(needs, listings, scanPrices)
    local prices, marks = {}, {}
    for itemID, p in pairs(scanPrices) do prices[itemID] = p end
    for itemID, list in pairs(listings) do
        if not needs[itemID] then prices[itemID] = list[1] and list[1].unitPrice or nil end
    end
    for itemID, n in pairs(needs) do
        local list = listings[itemID]
        if not list then
            marks[itemID] = { live = false }
        else
            local total, available = D.Cost(list, n)
            if total then
                prices[itemID] = total / n
                marks[itemID] = { live = true }
            else
                prices[itemID] = available > 0 and ShortPrice(list, n, available, scanPrices[itemID]) or nil
                marks[itemID] = { live = true, short = available }
            end
        end
    end
    return prices, marks
end

function D.PlanCost(plan, owned, listings, scanPrices, bundleOf, onQuest)
    local needs = D.Needs(plan, owned, bundleOf, onQuest)
    local prices = D.EffectivePrices(needs, listings, scanPrices)
    local cost = 0
    for itemID, n in pairs(needs) do
        if not prices[itemID] then return nil end
        cost = cost + prices[itemID] * n
    end
    return cost
end

function D.ShortAtScan(needs, availableByItem)
    local out = {}
    for itemID, n in pairs(needs) do
        local available = availableByItem[itemID]
        if type(available) == "number" and available < n then out[itemID] = available end
    end
    return out
end

local GAP, TIMEOUT, TRIES, KEY_TRIES = 0.3, 5, 3, 20

local Queue = {}
Queue.__index = Queue

function D.NewQueue(api)
    return setmetatable({ api = api, cache = {} }, Queue)
end

local function Collect(cache, ids)
    local out = {}
    for _, id in ipairs(ids) do out[id] = cache[id] end
    return out
end

function Queue:Wait(run, delay, cooldown)
    local token = {}
    run.wake, run.cooldown = token, cooldown
    self.api.After(delay, function()
        if self.run == run and run.wake == token then
            run.wake, run.cooldown = nil, nil
            self:Step(run, true)
        end
    end)
end

function Queue:Next(run)
    run.inflight, run.at, run.done = nil, run.at + 1, run.done + 1
    if run.onProgress then run.onProgress(run.done, run.total) end
    self:Wait(run, GAP, true)
end

function Queue:Step(run, fromTimer)
    if self.run ~= run or run.inflight then return end
    while run.ids[run.at] and self.cache[run.ids[run.at]] do
        run.at, run.done = run.at + 1, run.done + 1
    end
    local id = run.ids[run.at]
    if not id then
        self.run = nil
        if run.onDone then run.onDone(Collect(self.cache, run.ids)) end
        return
    end
    local api = self.api
    if not api.Ready() or (api.Busy and api.Busy()) then
        self:Wait(run, GAP)
        return
    end
    local key = api.MakeItemKey(id)
    if not (key and api.HasKeyInfo(key)) then
        if fromTimer then run.keyTries = (run.keyTries or 0) + 1 end
        if (run.keyTries or 0) > KEY_TRIES then
            run.keyTries = nil
            self:Next(run)
        else
            self:Wait(run, GAP)
        end
        return
    end
    run.keyTries, run.wake = nil, nil
    local flight = { id = id }
    run.inflight = flight
    api.Search(key)
    api.After(TIMEOUT, function()
        if self.run ~= run or run.inflight ~= flight then return end
        run.inflight = nil
        run.tries = (run.tries or 0) + 1
        if run.tries >= TRIES then
            run.tries = nil
            self:Next(run)
        else
            self:Step(run)
        end
    end)
end

function Queue:Run(itemIDs, onProgress, onDone)
    local ids, seen = {}, {}
    for _, id in ipairs(itemIDs) do
        if not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    local run = { ids = ids, total = #ids, at = 1, done = 0, onProgress = onProgress, onDone = onDone }
    self.run = run
    self:Step(run)
end

function Queue:Cancel()
    self.run = nil
end

function Queue:Clear()
    self.run, self.cache = nil, {}
end

function Queue:Receive(id, read)
    local run = self.run
    local flight = run and run.inflight
    if not (flight and flight.id == id) then return end
    local list = {}
    for _, l in ipairs(read() or {}) do list[#list + 1] = l end
    table.sort(list, function(a, b) return a.unitPrice < b.unitPrice end)
    self.cache[id] = list
    run.tries = nil
    self:Next(run)
end

function Queue:OnEvent(event, arg)
    local run = self.run
    if event == "AUCTION_HOUSE_CLOSED" then
        self.run = nil
        local partial = run and Collect(self.cache, run.ids)
        self.cache = {}
        if run and run.onDone then run.onDone(partial, true) end
    elseif event == "AUCTION_HOUSE_SHOW" then
        self.cache = {}
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        self:Receive(arg, function() return self.api.Commodity(arg) end)
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        if type(arg) == "table" then self:Receive(arg.itemID, function() return self.api.Items(arg) end) end
    elseif run and not run.inflight and not run.cooldown then
        self:Step(run)
    end
end

function D.ScanAvailable(needs)
    local out = {}
    local A = _G.Auctionator
    local db = type(A) == "table" and A.Database
    if type(db) ~= "table" or type(db.GetPriceHistory) ~= "function" then return out end
    for itemID in pairs(needs) do
        local good, history = pcall(db.GetPriceHistory, db, tostring(itemID))
        local latest = good and type(history) == "table" and history[1]
        if type(latest) == "table" and type(latest.available) == "number" then out[itemID] = latest.available end
    end
    return out
end

local SORTS = { { sortOrder = 0, reverseSort = false } }

local function ScanFrame()
    local good, ref = pcall(function() return _G.Auctionator.State.IncrementalScanFrameRef end)
    return good and type(ref) == "table" and ref or nil
end

function D.AuctionatorScanning()
    local ref = ScanFrame()
    return ref ~= nil and ref.doingFullScan == true
end

function D.ScanOutdated()
    local ref = ScanFrame()
    if not (ref and type(ref.IsAutoscanReady) == "function") then return false end
    local good, ready = pcall(ref.IsAutoscanReady, ref)
    return good and ready == true
end

function D.StartScan()
    local ref = ScanFrame()
    if not (ref and type(ref.InitiateScan) == "function") then return false end
    return (pcall(ref.InitiateScan, ref))
end

local function AuctionatorBusy()
    if D.AuctionatorScanning() then return true end
    local A = _G.Auctionator
    local ah = type(A) == "table" and A.AH
    local q = type(ah) == "table" and ah.Queue
    local list = type(q) == "table" and q.queue
    return type(list) == "table" and #list > 0
end

local function Listing(unitPrice, quantity)
    if type(unitPrice) == "number" and type(quantity) == "number" and quantity > 0 then
        return { unitPrice = unitPrice, quantity = quantity }
    end
end

function D.LiveApi()
    local C, T = _G.C_AuctionHouse, _G.C_Timer
    if type(C) ~= "table" or type(T) ~= "table" or not T.After then return nil end
    for _, f in ipairs({ "MakeItemKey", "GetItemKeyInfo", "SendSearchQuery", "GetNumCommoditySearchResults",
        "GetCommoditySearchResultInfo", "GetNumItemSearchResults", "GetItemSearchResultInfo" }) do
        if type(C[f]) ~= "function" then return nil end
    end
    return {
        Ready = function()
            return not C.IsThrottledMessageSystemReady or C.IsThrottledMessageSystemReady() == true
        end,
        Busy = AuctionatorBusy,
        MakeItemKey = function(itemID) return C.MakeItemKey(itemID) end,
        HasKeyInfo = function(key) return C.GetItemKeyInfo(key) ~= nil end,
        Search = function(key) pcall(C.SendSearchQuery, key, SORTS, false) end,
        Commodity = function(itemID)
            local out = {}
            for i = 1, C.GetNumCommoditySearchResults(itemID) or 0 do
                local info = C.GetCommoditySearchResultInfo(itemID, i)
                out[#out + 1] = info and Listing(info.unitPrice, info.quantity) or nil
            end
            return out
        end,
        Items = function(key)
            local out = {}
            for i = 1, C.GetNumItemSearchResults(key) or 0 do
                local info = C.GetItemSearchResultInfo(key, i)
                local buyout, quantity = info and info.buyoutAmount, info and info.quantity
                if type(buyout) == "number" and type(quantity) == "number" and quantity > 0 then
                    out[#out + 1] = Listing(buyout / quantity, quantity)
                end
            end
            return out
        end,
        After = function(delay, fn) T.After(delay, fn) end,
    }
end
