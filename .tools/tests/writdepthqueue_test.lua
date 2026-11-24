addon("Modules/WritCrateDepth.lua")
local D = ns.WritDepth

local function NewApi()
    local api = { ready = true, keyInfo = {}, sent = {}, timers = {}, commodity = {}, items = {} }
    api.Ready = function() return api.ready end
    api.Busy = function() return api.busy == true end
    api.MakeItemKey = function(id) return { itemID = id, itemLevel = 0 } end
    api.HasKeyInfo = function(key) return api.keyInfo[key.itemID] ~= false end
    api.Search = function(key) api.sent[#api.sent + 1] = key.itemID end
    api.Commodity = function(id) return api.commodity[id] or {} end
    api.Items = function(key) return api.items[key.itemID] or {} end
    api.After = function(delay, fn) api.timers[#api.timers + 1] = { delay = delay, fn = fn } end
    api.Tick = function(limit)
        local due, keep = {}, {}
        for _, t in ipairs(api.timers) do
            if t.delay <= (limit or 1) then due[#due + 1] = t else keep[#keep + 1] = t end
        end
        api.timers = keep
        for _, t in ipairs(due) do t.fn() end
    end
    return api
end

local api = NewApi()
local q = D.NewQueue(api)
local progress, result, calls = {}, nil, 0
local function Track(done, total) progress[#progress + 1] = done .. "/" .. total end
local function Done(listings, closed) result, calls = listings, calls + 1; result.closed = closed end

api.commodity[1] = { { unitPrice = 30, quantity = 2 }, { unitPrice = 10, quantity = 5 } }
api.items[2] = { { unitPrice = 500, quantity = 1 } }
q:Run({ 1, 2, 1 }, Track, Done)
eq(#api.sent, 1, "one query in flight"); eq(api.sent[1], 1)
q:OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 99)
eq(#progress, 0, "other item's results ignored")
q:OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 1)
eq(progress[1], "1/2", "duplicate ids counted once")
eq(#api.sent, 1, "next query waits for the gap")
api.Tick()
eq(#api.sent, 2); eq(api.sent[2], 2)
q:OnEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 2 })
eq(calls, 0, "done only after the gap")
api.Tick()
eq(calls, 1, "run finished")
eq(result[1][1].unitPrice, 10, "commodity listings sorted")
eq(result[2][1].unitPrice, 500, "item fallback path")
eq(progress[#progress], "2/2")

api.sent = {}
calls = 0
q:Run({ 1, 2 }, Track, Done)
eq(#api.sent, 0, "cache reused for the AH session")
eq(calls, 1, "cached run finishes at once")

api.sent, calls, api.timers = {}, 0, {}
api.ready = false
q:Run({ 3 }, Track, Done)
eq(#api.sent, 0, "throttle not ready: no query")
eq(#api.timers, 1, "one wait timer, no busy loop")
ok(api.timers[1].delay > 0, "wait has a delay")
api.Tick()
eq(#api.sent, 0, "still throttled"); eq(#api.timers, 1, "waits again")
api.ready = true
q:OnEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
eq(#api.sent, 1, "throttle ready event resumes"); eq(api.sent[1], 3)
api.Tick()
eq(#api.sent, 1, "stale wait timer sends nothing")
q:OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 3)
api.Tick()
eq(calls, 1); eq(#result[3], 0, "zero listings cached as empty")

api.sent, calls = {}, 0
api.busy = true
q:Run({ 4 }, Track, Done)
eq(#api.sent, 0, "waits while Auctionator is searching")
api.busy = false
api.Tick()
eq(#api.sent, 1)

local stale = 0
q:Run({ 5, 6 }, Track, function() stale = stale + 1 end)
eq(api.sent[#api.sent], 5)
q:Run({ 7 }, Track, Done)
eq(api.sent[#api.sent], 7, "new run starts at once")
q:OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 5)
api.Tick()
eq(stale, 0, "first run's late results ignored")
q:OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 7)
api.Tick()
eq(stale, 0); eq(result[5], nil, "stale item not cached"); ok(result[7] ~= nil, "second run done")

api.sent, calls = {}, 0
api.commodity[8] = { { unitPrice = 1, quantity = 1 } }
q:Run({ 8, 9 }, Track, Done)
q:OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 8)
q:OnEvent("AUCTION_HOUSE_CLOSED")
eq(calls, 1, "close delivers partial results"); eq(result.closed, true)
ok(result[8] ~= nil and result[9] == nil, "partial live prices kept")
api.Tick()
q:OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 9)
api.Tick()
eq(calls, 1, "no late callbacks after close")
api.sent = {}
q:Run({ 8 }, Track, Done)
eq(api.sent[1], 8, "cache cleared on close")
q:Cancel()

api.sent, calls = {}, 0
api.keyInfo[10] = false
q:Run({ 10 }, Track, Done)
eq(#api.sent, 0, "waits for item key info")
api.keyInfo[10] = nil
q:OnEvent("ITEM_KEY_ITEM_INFO_RECEIVED", 10)
eq(api.sent[1], 10, "key info event resumes")
for _ = 1, 10 do api.Tick(10) end
eq(calls, 1, "timed-out item skipped, run finished"); eq(result[10], nil)

api.sent, calls, api.timers = {}, 0, {}
api.keyInfo[11] = false
q:Run({ 11 }, Track, Done)
for _ = 1, 25 do q:OnEvent("ITEM_KEY_ITEM_INFO_RECEIVED", 999) end
eq(calls, 0, "unrelated key-info events do not use up the key wait")
api.keyInfo[11] = nil
api.Tick()
eq(api.sent[1], 11, "query sent once key info arrives")
q:Cancel()

api.sent, calls, api.timers = {}, 0, {}
api.commodity[12] = { { unitPrice = 1, quantity = 1 } }
api.commodity[13] = { { unitPrice = 1, quantity = 1 } }
q:Run({ 12, 13 }, Track, Done)
q:OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 12)
q:OnEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
eq(#api.sent, 1, "gap after a result kept when another event arrives")
api.Tick()
eq(api.sent[2], 13, "next query after the gap")
q:Cancel()

local savedC, savedT = _G.C_AuctionHouse, _G.C_Timer
local function nop() end
_G.C_AuctionHouse = {
    MakeItemKey = nop, GetItemKeyInfo = nop, SendSearchQuery = nop,
    GetNumCommoditySearchResults = nop, GetCommoditySearchResultInfo = nop,
    GetNumItemSearchResults = function() return 2 end,
    GetItemSearchResultInfo = function(_, i)
        if i == 1 then return { buyoutAmount = 400, quantity = 4 } end
        return { bidAmount = 50, quantity = 1 }
    end,
}
_G.C_Timer = { After = nop }
local live = D.LiveApi()
local stacks = live and live.Items({ itemID = 14 }) or {}
_G.C_AuctionHouse, _G.C_Timer = savedC, savedT
eq(#stacks, 1, "bid-only auction dropped")
eq(stacks[1] and stacks[1].unitPrice, 100, "stack buyout priced per unit")
eq(stacks[1] and stacks[1].quantity, 4)
