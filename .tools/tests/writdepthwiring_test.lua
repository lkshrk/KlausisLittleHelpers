local charStore = {}
local names = { "time", "CreateFrame", "C_Timer", "GetTime", "C_Item", "C_Container", "C_Reputation", "C_CurrencyInfo",
    "UnitFactionGroup", "UnitLevel", "KLH_CharDB", "Auctionator", "InCombatLockdown", "C_QuestLog", "print",
    "C_EventUtils", "C_AuctionHouse", "AuctionHouseFrame" }
local saved = {}
for _, k in ipairs(names) do saved[k] = rawget(_G, k) end

local Mock
Mock = setmetatable({}, { __index = function() return Mock end, __call = function() return Mock end })
local frames = {}
local editBox
local rep = 0
local reaction = 4
local function NewFrame(kind)
    local f = setmetatable({ events = {} }, { __index = Mock })
    f.RegisterEvent = function(self, e) self.events[e] = true end
    f.UnregisterEvent = function(self, e) self.events[e] = nil end
    f.SetScript = function(self, name, fn) if name == "OnUpdate" then self.onUpdate = fn else self.handler = fn end end
    if kind == "EditBox" then
        editBox = f
        f.SetScript = function(self, name, fn) self.scripts = self.scripts or {}; self.scripts[name] = fn end
        f.GetText = function(self) return self.text or "" end
        f.SetText = function(self, t) self.text = t end
    end
    frames[#frames + 1] = f
    return f
end
local function Fire(event, ...)
    for _, f in ipairs(frames) do
        if f.events[event] and f.handler then f.handler(f, event, ...) end
    end
end

local timers = {}
local function Tick()
    local due, keep = {}, {}
    for _, t in ipairs(timers) do
        if t.delay <= 1 then due[#due + 1] = t else keep[#keep + 1] = t end
    end
    timers = keep
    for _, t in ipairs(due) do t.fn() end
end

local good, problem = pcall(function()
    _G.print = function() end
    _G.time = os.time
    addon("Core/Core.lua")
    ns.CharData = function(key) charStore[key] = charStore[key] or {}; return charStore[key] end
    _G.CreateFrame = function(kind) return NewFrame(kind) end
    _G.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
    _G.GetTime = function() return 0 end
    _G.InCombatLockdown = function() return false end
    _G.UnitFactionGroup = function() return "Alliance" end
    _G.UnitLevel = function() return 30 end
    charStore = { WritCratePlanner = { plan = { mode = "rep", target = "125" } } }
    _G.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() end }
    _G.C_Item = { GetItemCount = function() return 0 end, GetItemNameByID = function() end }
    _G.C_Reputation = { GetFactionDataByID = function()
        return { reaction = reaction, currentStanding = rep, currentReactionThreshold = 0, nextReactionThreshold = 3000 }
    end }
    _G.C_CurrencyInfo = { GetCurrencyInfo = function() return { quantity = 0 } end }
    _G.AuctionHouseFrame = setmetatable({ IsShown = function() return true end }, { __index = Mock })

    ns.IS_FOREVER = true
    addon("Data/Writs.lua"); addon("Data/WaylaidCrates.lua")
    addon("Modules/WritCrateSearch.lua"); addon("Modules/WritCrateState.lua"); addon("Modules/WritCrateDepth.lua")

    local spec, slash, window
    local actionsOn = {}
    local function Selected()
        for _, e in ipairs(window.entries) do if e.selected then return e end end
    end
    local function FirstRow()
        local r = ns.WritPlanner.LastResult()
        if not (r and r.plan) then return "" end
        for _, e in ipairs(ns.WritPlanner.Entries(r)) do
            if not e.header then return e.text end
        end
        return ""
    end
    addon("Core/UI.lua")
    local deferred = {}
    ns.UI.Defer = function(key, fn) deferred[key] = fn end
    setmetatable(ns.UI, { __index = function() return Mock end })
    local ahButtonClick
    local btns = {}
    ns.CreateWindowButton = function(_, _, text, fn)
        if text == "Writ Planner" then ahButtonClick = fn end
        local b = setmetatable({ fn = fn, text = text }, { __index = Mock })
        b.SetActive = function(self, on) self.on = on end
        b.label = setmetatable({ SetText = function(_, t) b.text = t end }, { __index = Mock })
        btns[text] = b
        return b
    end
    ns.CreateListWindow = function(opts)
        window = setmetatable({ opts = opts, frame = Mock }, { __index = Mock })
        window.Build = function() opts.top(Mock, 300, 0) end
        window.IsShown = function() return true end
        window.SetActionState = function(_, i, on, tip) actionsOn[i] = { on = on, tip = tip } end
        window.SetInfo = function(self, info) self.footer = info or { text = "" } end
        window.SetEntries = function(self, entries, summary, pinned) self.entries, self.summary, self.pinned = entries, summary, pinned end
        return window
    end
    local settings = { countBank = false, liveMinQty = 1, priceMethod = "typical", historyDays = 14, minDays = 5,
        cheapBelow = 15, highAbove = 15, dontBuyAbove = 50 }
    ns.GetSettings = function() return settings end
    ns.RegisterFeature = function(s) spec = s end
    ns.RegisterSlashCommand = function(_, fn) slash = fn end
    addon("Modules/WritCrateHistory.lua")
    addon("Modules/WritCratePlanner.lua")

    local A, B
    for _, r in ipairs(ns.Data.Writs) do
        if r.questID == 94289 then A = r elseif r.questID == 94261 then B = r end
    end
    local scan = { [A.writID] = 100, [A.itemID] = 100, [B.writID] = 150, [B.itemID] = 150 }
    local ages = {}
    local history = { [tostring(A.itemID)] = { { available = 0 } }, [tostring(A.writID)] = { { available = 7 } } }
    _G.Auctionator = {
        API = { v1 = {
            GetAuctionPriceByItemID = function(_, id) return scan[id] end,
            GetAuctionAgeByItemID = function(_, id) return ages[id] end,
            ConvertToSearchString = function(_, t) return t.searchString end,
            CreateShoppingList = function() end,
        } },
        Database = { GetPriceHistory = function(_, key) return history[key] or {} end },
    }
    local sent, listings = {}, {}
    _G.C_AuctionHouse = {
        MakeItemKey = function(id) return { itemID = id } end,
        GetItemKeyInfo = function() return {} end,
        IsThrottledMessageSystemReady = function() return true end,
        SendSearchQuery = function(key) sent[#sent + 1] = key.itemID end,
        GetNumCommoditySearchResults = function(id) return #(listings[id] or {}) end,
        GetCommoditySearchResultInfo = function(id, i) return listings[id][i] end,
        GetNumItemSearchResults = function() return 0 end,
        GetItemSearchResultInfo = function() end,
    }
    spec.enable()
    local recalc

    Fire("AUCTION_HOUSE_SHOW")
    slash("")
    Fire("AUCTION_HOUSE_CLOSED")
    ok(window ~= nil, "window opened")
    recalc = btns.Search.fn
    local reset
    for _, a in ipairs(window.opts.actions) do if a.text == "Reset" then reset = a.onClick end end
    ok(reset ~= nil, "Reset action")
    eq(window.opts.actions[2].text, "Create Auctionator list", "list button where Search was")
    eq(rawget(window, "entries") and #window.entries or 0, 0, "opening does not calculate")
    ok(window.summary.text:find("Press Search", 1, true), "idle until Search: " .. window.summary.text)
    recalc()
    eq(#sent, 0, "no AH queries away from the AH")
    editBox.scripts.OnEnterPressed(editBox)
    eq(ns.WritPlanner.LastResult(), nil, "Enter cannot search away from AH")
    eq(#sent, 0, "Enter starts no offline queries")
    eq(ns.WritPlanner.LastResult(), nil, "offline search does not calculate")

    listings[A.writID] = { { unitPrice = 5000, quantity = 3, itemID = A.writID } }
    listings[A.itemID] = { { unitPrice = 100, quantity = 9, itemID = A.itemID } }
    listings[B.writID] = { { unitPrice = 150, quantity = 2, itemID = B.writID } }
    listings[B.itemID] = { { unitPrice = 150, quantity = 1, itemID = B.itemID } }
    Fire("AUCTION_HOUSE_SHOW")
    recalc()
    ok(window.summary.text:find("0 of 2 items", 1, true), "progress: " .. window.summary.text)
    ok(window.summary.text:find("Adding up AH listings...", 1, true), "loading view: " .. window.summary.text)
    eq(btns.Search.text, "Cancel", "Search turns into Cancel while it runs"); eq(btns.Search.on, true, "Cancel is clickable")
    local queried = #sent
    _G.InCombatLockdown = function() return true end
    spec.options().liveMinQty.set(nil, 2)
    eq(ns.WritPlanner.LastResult(), nil, "combat setting cancels active depth result")
    Tick(); Tick()
    eq(#sent, queried, "combat setting cancels pending depth queries")
    _G.InCombatLockdown = function() return false end
    deferred.KLH_WritPlannerSettings()
    settings.liveMinQty = 1
    recalc()
    queried = #sent
    btns.Search.fn()
    Tick(); Tick()
    eq(#sent, queried, "Cancel stops the lookups at once")
    eq(btns.Search.text, "Search", "back to Search")
    eq(#window.entries, 0, "cancelled first search has no completed result")
    ok(not (rawget(window, "summary") and window.summary.text:find("Adding up", 1, true)), "no progress after Cancel")

    recalc()
    queried = #sent
    ns.WritPlanner.StopAll()
    Tick(); Tick()
    eq(#sent, queried, "closing the window stops the lookups")
    eq(ns.WritPlanner.LastResult(), nil, "an interrupted search is not shown again")
    recalc()
    queried = #sent
    btns.Favor.fn()
    Tick(); Tick()
    eq(#sent, queried, "switching mode stops the running lookups")
    eq(ns.WritPlanner.LastResult(), nil, "and no result of the other mode comes back")
    eq(#window.entries, 0, "Favor view stays idle")
    btns.Rep.fn()
    editBox:SetText("125")
    local today = ns.WritHistory.Today()
    local rows = {}
    for d = 1, 6 do rows[#rows + 1] = { rawDay = tostring(today - d), minSeen = 40 } end
    _G.Auctionator.Database = { GetPriceHistory = function(_, key)
        for _, id in ipairs({ A.itemID, A.writID, B.itemID, B.writID }) do
            if key == tostring(id) then return rows end
        end
        return {}
    end }
    recalc()
    local baseCheck = ns.WritPlanner.LastResult().priceCheck
    ok(baseCheck ~= nil and baseCheck.reason == nil, "scan result carries a real verdict")
    eq(window.entries[1] and window.entries[1].text, "Cheapest", "options listed while loading")
    eq(actionsOn[2].on, false, "Create list disabled while calculating"); eq(btns.Search.text, "Cancel", "Cancel while calculating")
    eq(window.entries[1].tooltipLines, nil, "no popup while calculating")
    local function Answer()
        local guard = 0
        while guard < 20 do
            guard = guard + 1
            local id = sent[#sent]
            if id then
                sent[#sent] = nil
                Fire("COMMODITY_SEARCH_RESULTS_UPDATED", id)
            end
            Tick()
            if #sent == 0 and #timers == 0 then break end
        end
    end
    Answer()
    local done = ns.WritPlanner.LastResult()
    local pc = done.priceCheck
    eq(pc.usualUnit, baseCheck.usualUnit, "usual unit kept by the finished depth run")
    eq(pc.days, baseCheck.days); eq(pc.method, baseCheck.method)
    ok(FirstRow():find(B.name, 1, true), "replanned onto the writ that is really cheaper")
    for _, o in ipairs(done.options) do
        local from = o.from or done
        local plan = ns.WritPlanner.RepriceLines(o.plan, scan, from.input, from.bundleOf)
        local v = pc.byLevel[o.level]
        ok(v ~= nil, "verdict for the shown option at level " .. tostring(o.level))
        ok(v and math.abs(v.unit - plan.cost / plan.gain) < 1e-9, "verdict judges the shown plan at scan prices")
        local expected = ns.WritHistory.Verdict(plan.cost / plan.gain, pc.usualUnit, settings)
        eq(v and v.tier, expected.tier); eq(v and v.pct, expected.pct)
    end
    local opts = spec.options()
    local beforeCombatQueries = #sent
    _G.InCombatLockdown = function() return true end
    opts.countBank.set(nil, true)
    eq(ns.WritPlanner.LastResult(), done, "combat settings preserve completed result")
    window.opts.actions[2].onClick()
    eq(#sent, beforeCombatQueries, "combat invalidation starts no queries")
    ok(deferred.KLH_WritPlannerSettings ~= nil, "combat refresh deferred")
    _G.InCombatLockdown = function() return false end
    deferred.KLH_WritPlannerSettings()
    ok(window.summary.text:find("settings changed", 1, true), "deferred refresh shows stale state")
    recalc()
    Answer()
    local priorMarket = ns.WritPlanner.MarketResult()
    local queriesBefore = #sent
    opts.minDays.set(nil, 6)
    ok(ns.WritPlanner.LastResult() ~= nil, "changing settings preserves the result")
    ok(window.summary.text:find("settings changed", 1, true), "settings change asks for a new search")
    eq(#sent, queriesBefore, "settings change starts no AH queries")
    ok(ns.WritPlanner.MarketResult() ~= priorMarket, "market recalculated on setting change")
    ok(opts.minDays.desc:find("capped", 1, true) and opts.minDays.desc:find("across items", 1, true), "coverage description")
    ok(opts.priceMethod.desc:find("weighted", 1, true) and opts.priceMethod.desc:find("falls back", 1, true), "price method description")
    ok(opts.highAbove.desc:find("rounded", 1, true) and opts.highAbove.desc:find("overlap", 1, true), "threshold description")
    recalc()
    Answer()
    priorMarket = ns.WritPlanner.MarketResult()
    spec.onReset()
    ok(ns.WritPlanner.LastResult() ~= nil, "profile reset preserves result")
    ok(window.summary.text:find("settings changed", 1, true), "profile reset asks for search")
    ok(ns.WritPlanner.MarketResult() ~= priorMarket, "profile reset refreshes market")
    eq(#sent, queriesBefore, "profile reset starts no queries")
    recalc()
    Answer()
    done = ns.WritPlanner.LastResult()
    local cheapest = done.options[1]
    ok(baseCheck.byLevel[cheapest.level].unit ~= pc.byLevel[cheapest.level].unit, "the scan plan's unit is not reused for the live plan")
    ok(window.entries[1].icon and window.entries[1].icon.file:find("chevron", 1, true), "shown option row keeps its tier icon")
    ok(not FirstRow():find("listed", 1, true), "no short mark: " .. FirstRow())
    ok(window.footer.text:find("2 items priced by their listings, 0 at Auctionator's cheapest", 1, true), window.footer.text)
    ok(window.entries[1].right:find("3s 00c", 1, true), "real total: " .. window.entries[1].right)
    eq(rawget(window, "summary"), nil, "progress cleared; no summary until an option is picked")
    eq(btns.Search.on, true, "Search enabled again"); eq(actionsOn[1].on, true, "Reset enabled")
    eq(Selected(), nil, "no option picked by default")
    eq(actionsOn[2].on, false, "Create list needs a picked option")
    ok(actionsOn[2].tip and actionsOn[2].tip:find("Pick an option", 1, true), "Create list explains: " .. tostring(actionsOn[2].tip))
    window.opts.onClick(1)
    eq(actionsOn[2].on, true, "Create list enabled once an option is picked")
    spec.onReset()
    eq(window.pinned and window.pinned[1] and window.pinned[1].data, "options", "profile reset preserves selected result view")
    window.opts.onClick("options")
    window.opts.onClick(1)
    local savedPlan = charStore.WritCratePlanner.plan
    eq(savedPlan and savedPlan.target, "125", "target saved per character"); eq(savedPlan and savedPlan.mode, "rep")

    slash("")
    eq(#sent, 0, "cached listings reused on reopen")
    ok(FirstRow():find(B.name, 1, true), "cached run replans the same")

    local retainedBeforeMode = ns.WritPlanner.LastResult()
    btns.Favor.fn()
    Fire("AUCTION_HOUSE_CLOSED")
    slash("")
    eq(ns.WritPlanner.LastResult(), retainedBeforeMode, "offline reopen restores result after mode change")
    eq(editBox:GetText(), "125", "restored result restores target")
    Fire("AUCTION_HOUSE_SHOW")
    btns.Favor.fn()
    btns.Rep.fn()
    editBox:SetText("200")
    recalc()
    btns.Search.fn()
    eq(ns.WritPlanner.LastResult(), retainedBeforeMode, "cancel restores previous completed result")
    eq(editBox:GetText(), "125", "cancel restores previous target")
    eq(btns.Rep.text, "Rep", "rep control remains available")

    listings[B.itemID] = {}
    recalc()
    ok(#sent > 0, "Search fetches live listings again")
    Answer()
    ok(FirstRow():find(A.name, 1, true), "writ whose item has none listed is avoided: " .. FirstRow())
    ok(not FirstRow():find("listed", 1, true), "no 0-listed line: " .. FirstRow())
    ok(window.entries[1].right:find("51s 00c", 1, true), "real total: " .. window.entries[1].right)

    local hidden = false
    window.Hide = function() hidden = true end
    Fire("AUCTION_HOUSE_CLOSED")
    ok(hidden, "window opened away from the AH closes with it")
    hidden = false
    Fire("AUCTION_HOUSE_SHOW")
    ok(ahButtonClick ~= nil, "AH button created")
    ahButtonClick()
    Answer()
    Fire("AUCTION_HOUSE_CLOSED")
    ok(hidden, "window opened from the AH closes with it")
    Fire("AUCTION_HOUSE_SHOW")
    window.IsShown = function() return false end
    slash("")
    window.IsShown = function() return true end
    Answer()

    listings[A.writID][1].unitPrice = 1
    Fire("AUCTION_HOUSE_CLOSED")
    Fire("AUCTION_HOUSE_SHOW")
    recalc()
    local first = sent[#sent]
    sent[#sent] = nil
    Fire("COMMODITY_SEARCH_RESULTS_UPDATED", first)
    local previous = ns.WritPlanner.LastResult()
    Fire("AUCTION_HOUSE_CLOSED")
    ok(ns.WritPlanner.LastResult() ~= previous, "AH close discards incomplete result")
    local retained = ns.WritPlanner.LastResult()
    window.opts.onClick(1)
    window.opts.onClick("options")
    eq(ns.WritPlanner.LastResult(), retained, "offline navigation preserves completed result")
    editBox.scripts.OnEnterPressed(editBox)
    eq(ns.WritPlanner.LastResult(), retained, "offline Enter preserves completed result")
    Tick()
    Fire("COMMODITY_SEARCH_RESULTS_UPDATED", A.itemID)
    eq(#sent, 0, "nothing queried after close")

    Fire("AUCTION_HOUSE_SHOW")
    ages[A.writID], ages[A.itemID], ages[B.writID], ages[B.itemID] = 5, 0, 0, 0
    recalc()
    Answer()
    ok(not FirstRow():find(A.name, 1, true), "item missing from the last scan leaves its writ out: " .. FirstRow())
    ok(window.footer.text:find("Not in your last scan", 1, true), "stale items named: " .. window.footer.text)
    ok(not window.footer.text:find("days old", 1, true), "no rescan warning when the scan is fresh: " .. window.footer.text)
    ages[A.writID], ages[A.itemID], ages[B.writID], ages[B.itemID] = 3, 3, 3, 3
    recalc()
    Answer()
    ok(window.footer.text:find("Scan is 3 days old", 1, true), "old scan warned: " .. window.footer.text)
    ok(not window.footer.text:find("Not in your last scan", 1, true), "same-age items are all from the last scan")

    window.opts.onClick(1)
    eq(window.pinned and window.pinned[2] and window.pinned[2].data, 1, "clicking an option pins it")
    eq(window.pinned[2].selected, nil, "pinned row has no selection highlight")
    ok(window.pinned[2].icon and window.pinned[2].icon.file:find("chevron", 1, true), "pinned row keeps its tier icon")
    eq(actionsOn[2].on, true, "still picked: Create list enabled")
    eq(window.pinned[1].data, "options", "Show other options pinned above it")
    local function Find(pred) for _, e in ipairs(window.entries) do if pred(e) then return e end end end
    local header = Find(function(e) return e.header and type(e.data) == "table" end)
    ok(header ~= nil, "zone headers are clickable")
    local before = #window.entries
    window.opts.onClick(header.data)
    ok(#window.entries > before, "clicking a folded zone opens it")
    local expanded = #window.entries
    spec.onReset()
    eq(#window.entries, expanded, "profile reset preserves expanded group")
    window.opts.onClick(header.data)
    eq(#window.entries, before, "clicking again folds it")
    window.opts.onClick("options")
    eq(rawget(window, "pinned"), nil, "Show other options goes back to the option list")
    eq(Selected(), nil, "and nothing is picked")
    window.opts.onClick(1)
    Fire("AUCTION_HOUSE_SHOW")
    _G.Auctionator.State = { IncrementalScanFrameRef = { doingFullScan = true } }
    sent = {}
    recalc()
    eq(#sent, 0, "no search while Auctionator scans")
    ok(window.summary.text:find("Waiting for Auctionator", 1, true), "waiting instead of calculating: " .. window.summary.text)
    eq(btns.Search.text, "Cancel", "a waiting search can be cancelled")
    btns.Search.fn()
    eq(btns.Search.text, "Search"); eq(btns.Search.on, false, "Search disabled while Auctionator scans")
    ok(btns.Search.tip and btns.Search.tip:find("Auctionator is scanning", 1, true), "disabled Search explains why")
    recalc()
    eq(#sent, 0, "no AH queries while Auctionator scans")
    local P = ns.WritPlanner
    _G.Auctionator.State.IncrementalScanFrameRef.doingFullScan = false
    eq(P.SyncScanState(), true, "scan end noticed")
    eq(btns.Search.on, true, "Search unlocks when the scan ends")
    ok(#window.entries > 0, "the waiting search runs when the scan ends")
    Answer()
    _G.Auctionator.State.IncrementalScanFrameRef.doingFullScan = true
    eq(P.SyncScanState(), true, "scan noticed while the window just sits open")
    eq(btns.Search.on, false, "Search disabled as soon as a scan starts")
    eq(P.SyncScanState(), false, "no redraw while nothing changes")
    _G.Auctionator.State.IncrementalScanFrameRef.doingFullScan = false
    eq(P.SyncScanState(), true); eq(btns.Search.on, true, "and enabled again when it ends")
    local after = rawget(window, "summary")
    ok(not (after and after.text:find("Waiting for Auctionator", 1, true)), "calculation runs after the scan")
    ok(#window.entries > 0, "results after the scan")

    local started = 0
    local ref = _G.Auctionator.State.IncrementalScanFrameRef
    ref.IsAutoscanReady = function() return true end
    ref.InitiateScan = function(self) self.doingFullScan = true; started = started + 1 end
    Fire("AUCTION_HOUSE_SHOW")
    sent = {}
    recalc()
    eq(started, 1, "outdated Auctionator data: its scan is started first")
    eq(#sent, 0, "no lookups before the refresh")
    ok(window.summary.text:find("Refreshing outdated Auctionator prices", 1, true), window.summary.text)
    ref.IsAutoscanReady = function() return false end
    ref.doingFullScan = false
    ns.WritPlanner.SyncScanState()
    eq(started, 1, "one refresh only")
    ok(#window.entries > 0, "search runs on the fresh prices")
    ref.IsAutoscanReady, ref.InitiateScan = nil, nil

    reset()
    eq(#window.entries, 0, "Reset clears the results")
    eq(charStore.WritCratePlanner.plan.target, "", "Reset clears the saved target")

    editBox:SetText("125")
    recalc()
    Answer()
    ok(#window.entries > 0, "result before turning in")
    local function Reopen()
        window.IsShown = function() return false end
        slash("")
        window.IsShown = function() return true end
    end
    Reopen()
    ok(#window.entries > 0, "nothing changed: reopening shows the last result")
    rep = 100
    Reopen()
    ok(#window.entries > 0, "rep gained since the search: completed result retained")
    eq(editBox:GetText(), "25", "target shrinks by the rep gained")
    rep = 130
    Reopen()
    eq(editBox:GetText(), "", "target reached: field cleared")

    settings.liveMinQty = 10
    editBox:SetText("125")
    Fire("AUCTION_HOUSE_SHOW")
    sent = {}
    recalc()
    eq(#sent, 0, "single writs and items are not checked live")
    ok(#window.entries > 0, "result straight from scan prices")
    settings.liveMinQty = 1
    recalc()
    ok(#sent > 0, "with the threshold at 1 the same items are checked")
    Answer()

    reaction = 5
    editBox:SetText("5000")
    recalc()
    Answer()
    for _, e in ipairs(window.entries) do ok(e.data ~= "receipts", "no receipts-off warning row any more") end

    local MP = ns.WritPlanner
    Fire("AUCTION_HOUSE_CLOSED")
    Fire("AUCTION_HOUSE_SHOW")
    Tick()
    local firstMarket = MP.MarketResult()
    ok(firstMarket ~= nil and firstMarket.rep ~= nil and firstMarket.favor ~= nil, "the market index is computed when the AH opens")
    local watcher
    for _, f in ipairs(frames) do if f.onUpdate and f.events.AUCTION_HOUSE_SHOW then watcher = f end end
    ok(watcher ~= nil, "the AH watches Auctionator's scan state")
    local scanRef = _G.Auctionator.State.IncrementalScanFrameRef
    scanRef.doingFullScan = true
    watcher.onUpdate(watcher, 1)
    eq(MP.MarketResult(), firstMarket, "nothing is recomputed while Auctionator scans")
    scanRef.doingFullScan = false
    watcher.onUpdate(watcher, 1)
    ok(MP.MarketResult() ~= firstMarket, "and it is computed again when the scan finishes")
    local second = MP.MarketResult()
    watcher.onUpdate(watcher, 1)
    eq(MP.MarketResult(), second, "no recompute without a new scan")
    Fire("AUCTION_HOUSE_CLOSED")
    eq(rawget(watcher, "onUpdate"), nil, "the watcher stops when the AH closes")
end)
for _, k in ipairs(names) do _G[k] = saved[k] end
ok(good, tostring(problem))
