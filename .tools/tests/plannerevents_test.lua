local charStore = {}
local names = { "CreateFrame", "C_Timer", "GetTime", "GetQuestID", "C_Item", "C_Container", "C_Reputation", "C_CurrencyInfo",
    "UnitFactionGroup", "UnitLevel", "KLH_CharDB", "Auctionator", "InCombatLockdown", "C_QuestLog", "Enum", "print",
    "GetServerTime", "date", "C_EventUtils", "AuctionHouseFrame", "AuctionatorTabs_Shopping", "geterrorhandler", "UISpecialFrames" }
local saved = {}
for _, k in ipairs(names) do saved[k] = rawget(_G, k) end

local Mock
Mock = setmetatable({}, { __index = function() return Mock end, __call = function() return Mock end })
local frames = {}
local function NewFrame(kind)
    local f = setmetatable({ events = {} }, { __index = Mock })
    f.RegisterEvent = function(self, e) self.events[e] = true end
    f.UnregisterEvent = function(self, e) self.events[e] = nil end
    f.SetScript = function(self, name, fn) if name == "OnUpdate" then self.onUpdate = fn else self.handler = fn end end
    if kind == "EditBox" then f.GetText = function() return "125" end; f.isTarget = true end
    frames[#frames + 1] = f
    return f
end
local function Fire(event, ...)
    for _, f in ipairs(frames) do
        if f.events[event] and f.handler then f.handler(f, event, ...) end
    end
end

local now, timers, printed = 100, {}, {}
local counts, itemNames, requested = {}, {}, {}
local repTotal = 1000
local currency = { quantity = 40 }
local lists = {}

local tabClicks = 0
local good, problem = pcall(function()
    local reported = {}
    _G.geterrorhandler = function() return function(e) reported[#reported + 1] = tostring(e) end end
    _G.print = function(s) printed[#printed + 1] = tostring(s) end
    addon("Core/Core.lua")
    ns.CharData = function(key) charStore[key] = charStore[key] or {}; return charStore[key] end
    _G.CreateFrame = function(kind) return NewFrame(kind) end
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    _G.GetTime = function() return now end
    _G.GetServerTime = function() return 1700000000 end
    _G.date = os.date
    _G.InCombatLockdown = function() return false end
    _G.UnitFactionGroup = function() return "Alliance" end
    _G.UnitLevel = function() return 30 end
    charStore = {}
    _G.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() end }
    _G.C_Item = {
        GetItemCount = function(id) return counts[id] or 0 end,
        GetItemNameByID = function(id) return itemNames[id] end,
        RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end,
    }
    _G.C_Reputation = { GetFactionDataByID = function()
        return { reaction = 4, currentStanding = repTotal, currentReactionThreshold = 0, nextReactionThreshold = 3000 }
    end }
    _G.C_CurrencyInfo = { GetCurrencyInfo = function() return currency end }

    ns.IS_FOREVER = true
    addon("Data/Writs.lua"); addon("Data/WaylaidCrates.lua")
    addon("Modules/WritCrateSearch.lua"); addon("Modules/WritCrateState.lua"); addon("Modules/WritCrateDepth.lua")
    local W = ns.WritState
    local scans = 0
    W.ScanBank = function() scans = scans + 1 end

    local spec, slash, window
    addon("Core/UI.lua")
    ns.UI.Defer = function(_, fn) fn() end
    setmetatable(ns.UI, { __index = function() return Mock end })
    local btns = {}
    ns.CreateWindowButton = function(_, _, text, fn)
        local b = setmetatable({ fn = fn }, { __index = Mock })
        btns[text] = b
        return b
    end
    ns.CreateListWindow = function(opts)
        local frame = setmetatable({}, { __index = Mock })
        frame.SetPoint = function(self, ...) self.point = { ... } end
        window = setmetatable({ opts = opts, frame = frame }, { __index = Mock })
        window.Build = function() opts.top(Mock, 300, 0) end
        window.IsShown = function(self) return self.visible == true end
        window.Show = function(self) self.visible = true end
        window.Hide = function(self) self.visible = false end
        window.SetEntries = function(self, entries, summary)
            self.entries, self.summary, self.visible = entries, summary, true
        end
        return window
    end
    local settings = { countBank = false }
    ns.GetSettings = function() return settings end
    ns.RegisterFeature = function(s) spec = s end
    ns.RegisterSlashCommand = function(_, fn) slash = fn end
    addon("Modules/WritCrateHistory.lua")
    _G.UISpecialFrames = {}
    addon("Modules/WritCratePlanner.lua")

    ok(spec.launcher and spec.launcher.onClick, "planner has a helpers menu launcher")
    _G.Auctionator = { API = { v1 = {} } }
    spec.enable()
    slash("")
    ok(printed[#printed]:find("Auctionator API changed", 1, true), "API change named: " .. tostring(printed[#printed]))
    frames = {}

    local row = ns.Data.Writs[1]
    for _, r in ipairs(ns.Data.Writs) do if r.questID == 94289 then row = r end end
    _G.Auctionator = { API = { v1 = {
        GetAuctionPriceByItemID = function(_, id) return ({ [row.writID] = 2000, [row.itemID] = 2398 })[id] end,
        ConvertToSearchString = function(_, t) return t.searchString .. "x" .. t.quantity end,
        CreateShoppingList = function(_, name, terms) lists[#lists + 1] = { name = name, terms = terms } end,
    } } }
    spec.enable()

    Fire("BANKFRAME_OPENED"); eq(scans, 1, "bank read on open")
    Fire("PLAYERBANKSLOTS_CHANGED"); eq(scans, 2, "bank change read while open")
    Fire("BANKFRAME_CLOSED"); eq(scans, 2, "closing reads nothing")
    Fire("PLAYERBANKSLOTS_CHANGED"); Fire("BAG_UPDATE_DELAYED"); eq(scans, 2, "no reads while closed")

    _G.C_Container = { GetContainerNumSlots = function() error("full bag scan") end }
    counts[248768] = 2
    Fire("BAG_UPDATE_DELAYED")
    counts[248768] = 1
    Fire("BAG_UPDATE_DELAYED")
    Fire("CURRENCY_DISPLAY_UPDATE", W.FAVOR_CURRENCY, 60, 20)
    eq(charStore.WritCratePlanner.observed.sealedFavor["artisan:gathered"], 20, "sealed departure via item counts")
    _G.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() end }

    local function TurnIn(gain)
        _G.GetQuestID = function() return row.questID end
        Fire("QUEST_COMPLETE")
        Fire("QUEST_TURNED_IN", row.questID)
        repTotal = repTotal + gain
        Fire("UPDATE_FACTION")
    end
    TurnIn(row.rep * 3)
    local wr = charStore.WritCratePlanner.observed.writRep
    eq(wr and wr[row.tier] and wr[row.tier].rep, nil, "gain far from the row rep not learned")
    TurnIn(row.rep)
    eq(wr[row.tier].rep, row.rep, "plausible gain learned")

    slash("")
    ok(window ~= nil, "slash opens the planner away from the auction house")
    eq(_G.UISpecialFrames[1], "KLHWritCratePlannerWindow", "planner participates in Escape handling")
    eq(window.frame.point[1], "CENTER", "first standalone opening uses a central position")
    eq(window.frame.point[2], UIParent, "standalone position is relative to UIParent")
    settings.windowPoint = { "BOTTOM", "BOTTOM", 45, 80 }
    window:Hide()
    spec.launcher.onClick()
    eq(window.frame.point[1], "BOTTOM", "launcher restores saved standalone anchor")
    eq(window.frame.point[4], 45, "launcher restores saved horizontal offset")
    settings.windowPoint = nil
    local scanning = ns.WritDepth.AuctionatorScanning
    ns.WritDepth.AuctionatorScanning = function() return true end
    btns.Search.fn()
    eq(ns.WritPlanner.LastResult(), nil, "search away from the auction house cannot create a result")
    ns.WritDepth.AuctionatorScanning = scanning
    local originalIndex = ns.WritPlanner.MarketIndex
    ns.WritPlanner.MarketIndex = function() error("market failure") end
    Fire("AUCTION_HOUSE_SHOW")
    for _, fn in ipairs(timers) do fn() end
    ok(reported[#reported] and reported[#reported]:find("market failure", 1, true), "market errors reach error handler")
    ns.WritPlanner.MarketIndex = originalIndex
    slash("")
    ok(window ~= nil, "slash opens window")
    btns.Search.fn()
    local completed = ns.WritPlanner.LastResult()
    ok(completed ~= nil, "search at AH completes")
    ok(window:IsShown(), "standalone planner is visible before AH closes")
    Fire("AUCTION_HOUSE_CLOSED")
    ok(not window:IsShown(), "closing AH hides standalone planner")
    eq(ns.WritPlanner.LastResult(), completed, "closing AH retains completed result")
    ok(window.summary.text:find("Calculated:", 1, true), "offline result displays calculation time")
    ok(window.summary.text:find("|cffffd100Prices may have changed - search again to refresh.|r", 1, true), "offline stale warning is yellow")
    btns.Search.fn()
    eq(ns.WritPlanner.LastResult(), completed, "offline search retains completed result")
    btns.Favor.fn()
    eq(ns.WritPlanner.LastResult(), completed, "offline mode retains completed result")
    window.opts.actions[1].onClick()
    eq(ns.WritPlanner.LastResult(), completed, "offline reset retains completed result")
    spec.onReset()
    eq(ns.WritPlanner.LastResult(), completed, "profile reset retains completed result")
    Fire("AUCTION_HOUSE_SHOW")
    eq(ns.WritPlanner.LastResult(), completed, "returning to AH retains result")
    ok(window.summary.text:find("Calculated:", 1, true), "result displays calculation time")
    ok(window.summary.text:find("Prices may have changed - search again to refresh.", 1, true), "return warns prices may be stale")
    window.opts.onClick(1)
    local create
    for _, a in ipairs(window.opts.actions) do if a.text == "Create Auctionator list" then create = a.onClick end end
    itemNames[row.itemID] = "Couteau"
    create()
    eq(#lists, 0, "list waits for missing names"); eq(#requested, 1); eq(requested[1], row.writID)
    create()
    eq(#requested, 1, "second click while waiting requests nothing")
    itemNames[row.writID] = "Ordre"
    Fire("GET_ITEM_INFO_RECEIVED", row.writID, true)
    eq(#lists, 1, "list built once the names arrive")
    eq(tabClicks, 0, "AH closed: no tab switch")
    local joined = table.concat(lists[1].terms, ";")
    ok(joined:find("Ordrex1", 1, true) and joined:find("Couteaux1", 1, true), joined)
    itemNames[row.itemID], itemNames[row.writID] = nil, nil
    requested = {}
    create()
    eq(#requested, 2); eq(#lists, 1)
    for _, fn in ipairs(timers) do fn() end
    eq(#lists, 2, "timeout builds the list with data names")

    _G.AuctionHouseFrame = { IsShown = function() return true end }
    _G.AuctionatorTabs_Shopping = { Click = function() tabClicks = tabClicks + 1 end }
    local fired = {}
    _G.Auctionator.Shopping = { ListManager = { GetByName = function(_, name) return { name = name } end },
        Tab = { Events = { ListSearchRequested = "list search" } } }
    _G.Auctionator.EventBus = {
        RegisterSource = function(self) return self end, UnregisterSource = function(self) return self end,
        Fire = function(self, _, event, list) fired[#fired + 1] = { event = event, list = list } return self end,
    }
    create()
    for _, fn in ipairs(timers) do fn() end
    eq(tabClicks, 1, "AH open: Shopping tab shown")
    eq(fired[1] and fired[1].event, "list search", "our list opened and searched")
    eq(fired[1] and fired[1].list and fired[1].list.name, lists[#lists].name)
    _G.Auctionator.EventBus = { Fire = function() error("internal changed") end }
    create()
    for _, fn in ipairs(timers) do fn() end
    eq(tabClicks, 2, "tab still shown when Auctionator internals change")

    itemNames[row.itemID], itemNames[row.writID] = nil, nil
    local beforeOldRequest = #lists
    create()
    local oldTimeout = timers[#timers]
    btns.Search.fn()
    Fire("GET_ITEM_INFO_RECEIVED", row.itemID, true)
    Fire("GET_ITEM_INFO_RECEIVED", row.writID, true)
    oldTimeout()
    eq(#lists, beforeOldRequest, "old name request cannot create list after new search")
    create()
    Fire("GET_ITEM_INFO_RECEIVED", row.itemID, true)
    Fire("GET_ITEM_INFO_RECEIVED", row.writID, true)
    eq(#lists, beforeOldRequest + 1, "new search can start its own name request")

    local savedGoal = charStore.WritCratePlanner.plan.goal
    local savedTarget = charStore.WritCratePlanner.plan.target
    local target
    for _, frame in ipairs(frames) do if frame.isTarget then target = frame end end
    target.GetText = function() return "200" end
    ns.WritDepth.ScanOutdated = function() return true end
    local pendingScan = false
    ns.WritDepth.StartScan = function() pendingScan = true; return true end
    ns.WritDepth.AuctionatorScanning = function() return pendingScan end
    btns.Search.fn()
    target.GetText = function() return "125" end
    ns.WritPlanner.Cancel()
    eq(charStore.WritCratePlanner.plan.goal, savedGoal, "cancel preserves completed goal")
    eq(charStore.WritCratePlanner.plan.target, savedTarget, "cancel preserves completed target")
    ns.WritDepth.AuctionatorScanning = scanning

    local countBeforeStale = #lists
    repTotal = repTotal + 1
    window:Hide()
    spec.launcher.onClick()
    ok(window.summary.text:find("Progress or daily reset changed", 1, true), "stale progress is visible")
    create()
    eq(#lists, countBeforeStale, "stale progress cannot create a shopping list")
    repTotal = repTotal - 1
    ns.WritPlanner.LastResult().stamp.resetAt = 1700000000
    window:Hide()
    spec.launcher.onClick()
    ok(window.summary.text:find("Progress or daily reset changed", 1, true), "daily reset is visible")
    create()
    eq(#lists, countBeforeStale, "daily reset prevents a shopping list")

    currency = nil
    local st = W.Standing()
    eq(st.favor, nil, "no currency data leaves favor unknown")
    local warned = 0
    for _, line in ipairs(printed) do if line:find("no Merchant's Favor data", 1, true) then warned = warned + 1 end end
    W.Standing()
    local again = 0
    for _, line in ipairs(printed) do if line:find("no Merchant's Favor data", 1, true) then again = again + 1 end end
    eq(warned, 1); eq(again, 1, "printed once")
end)
for _, k in ipairs(names) do _G[k] = saved[k] end
ok(good, tostring(problem))
