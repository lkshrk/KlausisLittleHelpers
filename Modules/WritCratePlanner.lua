local _, ns = ...
local UI = ns.UI

ns.WritPlanner = ns.WritPlanner or {}
local P = ns.WritPlanner

local KEY = "WritCratePlanner"
local PAD = 8
local WIDTH = 420
local FRIENDLY = 5
local STEPS = { [4] = 3000, [5] = 6000, [6] = 12000, [7] = 21000 }
local STANDING_NAMES = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
local TARGET_STANDINGS = { 5, 6, 7, 8 }
local WRIT_PREFIX = "Craftsman's Writ: "
local CRATE_PREFIX = "Waylaid Crate: "
local LIST_REP, LIST_FAVOR = "KLH Writs", "KLH Crates"
local GREY, ORANGE = "|cff9d9d9d", "|cffff8800"
local UNCONFIRMED = " " .. ORANGE .. "(unconfirmed)|r"
local CRATE_TIP = "Favor for Artisan crates is player-reported and not yet confirmed."
local RECEIPT_TIP = "Each receipt costs 15 Merchant's Favor from the camp's Uncertified Scribe and goes on one empty crate."

function P.GainTo(standing, target)
    local s = standing and standing.standingID
    if not s then return nil end
    if s >= target then return 0 end
    local gain = math.max(0, (STEPS[s] or standing.max or 0) - (standing.current or 0))
    for r = s + 1, target - 1 do gain = gain + (STEPS[r] or 0) end
    return gain
end

function P.ParseAmount(text)
    local digits = tostring(text or ""):gsub("[,%.%s]", ""):match("%d+")
    return digits and tonumber(digits) or nil
end

function P.CleanAmount(text)
    return (tostring(text or ""):gsub("%D", ""):sub(1, 9))
end

function P.FormatNumber(n)
    local s = tostring(math.floor(n + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

function P.ResetText(seconds)
    if type(seconds) ~= "number" or seconds < 0 then return nil end
    local minutes = math.floor(seconds / 60)
    return ("Writs reset in %dh %dm"):format(math.floor(minutes / 60), minutes % 60)
end

local function DailyReset()
    local dt = _G.C_DateAndTime
    return dt and dt.GetSecondsUntilDailyReset and dt.GetSecondsUntilDailyReset()
end

local function ItemName(itemID, fallback)
    local item = _G.C_Item
    local name = item and item.GetItemNameByID and item.GetItemNameByID(itemID)
    if type(name) == "string" and name ~= "" then return name end
    return fallback
end

local function CrateItemName(ref)
    return ref.labeled == false and ref.name or CRATE_PREFIX .. ref.name
end

--- Every item label in the planner is the game's full item name; ours is only the fallback until the item is cached.
function P.ItemLabel(itemID, fallback)
    return ItemName(itemID, fallback)
end

function P.WritName(ref)
    return ItemName(ref.writID, WRIT_PREFIX .. ref.name)
end

function P.CrateName(ref)
    return ItemName(ref.itemID, CrateItemName(ref))
end

function P.FormatMoney(copper)
    copper = math.floor((copper or 0) + 0.5)
    if copper >= 10000 then
        local silver = math.floor((copper + 50) / 100)
        return ("%sg %02ds"):format(P.FormatNumber(math.floor(silver / 100)), silver % 100)
    end
    local s, c = math.floor(copper / 100), copper % 100
    if s > 0 then return ("%ds %02dc"):format(s, c) end
    return ("%dc"):format(c)
end

local function Terms(plan, bundleOf, onQuest)
    local terms, at = {}, {}
    local function add(itemID, name, count, minusOwned, mat)
        if not (itemID and name) or count <= 0 then return end
        local t = at[itemID]
        if not t then
            t = { itemID = itemID, name = name, count = 0, minusOwned = minusOwned, mat = mat }
            at[itemID] = t
            terms[#terms + 1] = t
        end
        t.count = t.count + count
    end
    for _, line in ipairs(plan.lines) do
        local ref = line.ref
        if line.kind == "writ" then
            if not (onQuest and onQuest[ref.questID]) then add(ref.writID, WRIT_PREFIX .. ref.name, line.count, true) end
            add(ref.itemID, ref.item, (ref.qty or 1) * line.count, true, true)
        elseif line.kind == "crate" then
            if not line.owned then add(ref.itemID, CrateItemName(ref), line.count, false) end
            local bundle = bundleOf and bundleOf[ref]
            if bundle then add(bundle.itemID, bundle.name, bundle.count * line.count, true, true) end
        elseif line.kind == "receipt" and line.crateRef then
            add(line.crateRef.itemID, CrateItemName(line.crateRef), line.bought or 0, false)
        end
    end
    return terms
end

function P.OwnedMats(plan, owned, bundleOf, onQuest)
    local out = {}
    for _, t in ipairs(Terms(plan, bundleOf, onQuest)) do
        local used = t.mat and math.min(t.count, owned and owned[t.itemID] or 0) or 0
        if used > 0 then out[t.itemID] = used end
    end
    return out
end

function P.BankText(plan, bundleOf, onQuest)
    local from = plan.fromBank
    if not from then return nil end
    local parts, listed = {}, {}
    local function part(id, name)
        local n = from[id]
        if listed[id] or not (n and n > 0) then return end
        listed[id] = true
        parts[#parts + 1] = ("%d %s"):format(n, ItemName(id, name))
    end
    for _, t in ipairs(Terms(plan, bundleOf, onQuest)) do part(t.itemID, t.name) end
    local rest = {}
    for id in pairs(plan.bankNames or {}) do rest[#rest + 1] = id end
    table.sort(rest)
    for _, id in ipairs(rest) do part(id, plan.bankNames[id]) end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

function P.ShoppingTerms(plan, owned, bundleOf, onQuest)
    local terms = Terms(plan, bundleOf, onQuest)
    local out = {}
    for _, t in ipairs(terms) do
        local n = t.count - (t.minusOwned and owned and owned[t.itemID] or 0)
        if n > 0 then out[#out + 1] = { itemID = t.itemID, name = ItemName(t.itemID, t.name), count = n } end
    end
    return out
end

local function Settings()
    return ns.GetSettings(KEY)
end

local function Api()
    return ns.WritState.Api()
end

local state = { mode = "rep", view = { open = {} } }
local window, last, ahButton
local statusText, targetBox, modeButtons, standingArrow, searchButton
local SEARCH_W = 64

local function StandingName(id)
    local label = id and _G["FACTION_STANDING_LABEL" .. id]
    if type(label) == "string" and label ~= "" then return label end
    return STANDING_NAMES[id] or "?"
end
P.StandingName = StandingName

local function EmptyCrateRows(data)
    local rows = {}
    for _, row in ipairs(data and data.WaylaidCrates or {}) do rows[#rows + 1] = row end
    if data and data.UnlabeledCrate then rows[#rows + 1] = data.UnlabeledCrate end
    return rows
end

function P.EmptyCrates(input)
    local ownedEmpty, bestCost, bestRow = 0, nil, nil
    for _, row in ipairs(EmptyCrateRows(input.data)) do
        ownedEmpty = ownedEmpty + (input.owned[row.itemID] or 0)
        local cost = input.prices[row.itemID]
        if cost and (not bestCost or cost < bestCost) then bestCost, bestRow = cost, row end
    end
    return ownedEmpty, bestCost, bestRow
end

function P.SwitchMode(st, mode)
    if st.mode == mode then return false end
    st.mode = mode
    return true
end

local OBSERVE_EVENTS = {
    "QUEST_COMPLETE", "QUEST_TURNED_IN", "UPDATE_FACTION", "CURRENCY_DISPLAY_UPDATE", "BAG_UPDATE_DELAYED",
}

local function RegisterObservers()
    local W = ns.WritState
    local sealed = ns.Data.SealedCrates or {}
    local learner = W.Learner.New({ data = ns.Data, observed = W.Observed })

    local function Record(observations)
        for _, event in ipairs(observations) do W.Record(event) end
    end

    local frame = CreateFrame("Frame")
    for _, event in ipairs(OBSERVE_EVENTS) do frame:RegisterEvent(event) end
    frame:SetScript("OnEvent", function(_, event, a, _, c)
        if event == "QUEST_COMPLETE" then
            Record(learner:OnQuestComplete(GetQuestID(), W.Standing))
        elseif event == "QUEST_TURNED_IN" then
            local observations, due = learner:OnTurnedIn(a, GetTime())
            Record(observations)
            if due then C_Timer.After(W.Learner.WINDOW, function() Record(learner:Tick(due, W.Standing)) end) end
        elseif event == "UPDATE_FACTION" then
            Record(learner:OnFaction(W.Standing))
        elseif event == "CURRENCY_DISPLAY_UPDATE" then
            Record(learner:OnCurrency(a, c, GetTime()))
        else
            Record(learner:OnBags(W.SealedCounts(sealed), GetTime()))
        end
    end)
    learner:OnBags(W.SealedCounts(sealed), GetTime())
end

local LEVELS = { 0, 0.05, 0.1, 0.2, 0.4 }

local BUY_PENALTY = 1e7

function P.FewestBuys(S, writs, target, receipts, cap)
    local heavy = {}
    for i, w in ipairs(writs) do
        heavy[i] = { ref = w.ref, cost = w.cost + BUY_PENALTY, rep = w.rep, zone = w.zone }
    end
    local plan = S.RepPlan(heavy, target, receipts, cap)
    for _, line in ipairs(plan.lines) do
        if line.kind == "writ" then
            local penalty = BUY_PENALTY * (line.count or 1)
            line.cost = line.cost - penalty
            plan.cost = plan.cost - penalty
        end
    end
    return plan
end

local function Buys(r, plan)
    return #P.ShoppingTerms(plan, r.input.owned, r.bundleOf, r.input.onQuest)
end

local function WithBuysOption(r, options, buysOption)
    local fewest
    for _, o in ipairs(options) do
        o.buys = Buys(o.from or r, o.plan)
        if not fewest or o.buys < fewest then fewest = o.buys end
    end
    if buysOption and #buysOption.plan.lines > 0 then
        buysOption.buys = Buys(buysOption.from or r, buysOption.plan)
        if not fewest or buysOption.buys < fewest then options[#options + 1] = buysOption end
    end
    return options
end

local function OptionView(r, o)
    return setmetatable({ plan = o.plan, option = o }, { __index = o.from or r })
end

local function SelectOption(r)
    local options = r.options
    if not options or #options == 0 then return end
    local pick
    for i, o in ipairs(options) do
        if state.pick ~= nil and o.level == state.pick then pick = i end
    end
    local o = options[pick or 1]
    r.selected, r.plan = pick, o.plan
    r.view = pick and OptionView(r, o) or nil
end

--- The marks of the option a view stands for, else of the result's picked or first option.
local function MarksOf(r)
    local o = rawget(r, "option") or (r.options and r.options[r.selected or 1])
    return o and o.marks
end

--- Items priced by their listings and items left at the scan price; nil when no listings were looked up.
local function LiveCounts(marks)
    local liveN, scanN = 0, 0
    for _, m in pairs(marks or {}) do
        if m.live == true then liveN = liveN + 1 elseif m.live == false then scanN = scanN + 1 end
    end
    if liveN + scanN == 0 then return nil end
    return liveN, scanN
end

local function SetOptions(r, options, buys)
    r.options = WithBuysOption(r, P.Frontier(options), buys)
    SelectOption(r)
end

local function ReceiptInput(input, standing, settings, cands)
    if (standing.standingID or 0) < FRIENDLY then return nil end
    local ownedEmpty, crateCost, crateRef = P.EmptyCrates(input)
    if ownedEmpty == 0 and not crateCost then return nil end
    return {
        favorBalance = standing.favor or 0, useBalance = settings.useFavorForReceipts == true,
        crateCost = crateCost, crateRef = crateRef, crates = cands.crates, ownedEmpty = ownedEmpty,
    }
end

local function BundlesOf(cands)
    local bundleOf = {}
    for _, c in ipairs(cands.crates) do bundleOf[c.ref] = c.fillBundle end
    return bundleOf
end

local function CheapestRep(r, input, cands, settings)
    local receipts = ReceiptInput(input, r.standing, settings, cands)
    local toFriendly = P.GainTo(r.standing, FRIENDLY)
    local cap = ns.WritState.PastFriendly(input.observed) == 0 and toFriendly or nil
    return ns.WritSearch.RepPlan(cands.writs, r.target, receipts, cap), receipts, cap
end

local function CheapestPlan(r, input, cands, settings)
    if r.mode == "favor" then return ns.WritSearch.FavorPlan(cands.crates, r.target) end
    return CheapestRep(r, input, cands, settings)
end

function P.CheapestAt(r, prices, settings)
    local input = {}
    for k, v in pairs(r.input) do input[k] = v end
    input.prices = prices
    local cands = ns.WritState.BuildCandidates(input)
    local plan = CheapestPlan(r, input, cands, settings or Settings())
    if not plan or #plan.lines == 0 then return nil end
    return P.RepriceLines(plan, prices, input, BundlesOf(cands))
end

local function Unit(plan)
    return plan.gain > 0 and plan.cost / plan.gain or nil
end

local function MedianUnit(r, dayPrices, settings, baseShort)
    local units = {}
    for _, day in ipairs(dayPrices) do
        local plan = P.CheapestAt(r, day.prices, settings)
        local unit = plan and plan.short <= baseShort and Unit(plan)
        if unit then units[#units + 1] = unit end
    end
    return ns.WritHistory.Median(units)
end

local function PlanItemIDs(r, plan)
    local ids = {}
    for _, t in ipairs(Terms(plan, r.bundleOf, r.input.onQuest)) do ids[#ids + 1] = t.itemID end
    return ids
end

local function JudgeLevels(options, usualUnit, settings, unitOf)
    local byLevel = {}
    for _, o in ipairs(options) do
        local unit = unitOf(o)
        local verdict = unit and ns.WritHistory.Verdict(unit, usualUnit, settings)
        if verdict then byLevel[o.level] = { tier = verdict.tier, pct = verdict.pct, unit = unit } end
    end
    return byLevel
end

function P.PriceCheck(r, settings, history)
    local H = ns.WritHistory
    if not (r.options and r.options[1]) then return nil end
    local prices, ids = r.input.prices, {}
    for id in pairs(prices) do ids[#ids + 1] = id end
    history = history or H.ReadHistory(ids)
    if not next(history) then return { reason = "none" } end
    local today = H.Today()
    local typical, anyDays = H.TypicalPrices(history, today, settings.historyDays, prices)
    if anyDays == 0 then return { reason = "none" } end
    local first = r.options[1]
    local days = H.DaysCovered(history, PlanItemIDs(first.from or r, first.plan), today, settings.historyDays)
    if days < math.min(settings.minDays, settings.historyDays) then return { reason = "few", days = days } end

    local baseShort = r.options[1].plan.short or 0
    local usualUnit
    if settings.priceMethod == "days" then
        usualUnit = MedianUnit(r, H.DayPrices(history, today, settings.historyDays, prices), settings, baseShort)
        if not usualUnit then return { reason = "short" } end
    else
        local usual = P.CheapestAt(r, typical, settings)
        if not usual then return { reason = "empty" } end
        if (usual.short or 0) > baseShort then return { reason = "short" } end
        usualUnit = Unit(usual)
        if not usualUnit then return { reason = "empty" } end
    end

    local byLevel = JudgeLevels(r.options, usualUnit, settings, function(o) return Unit(o.plan) end)
    return { method = settings.priceMethod == "days" and "days" or "typical", days = days, usualUnit = usualUnit, byLevel = byLevel }
end

local function RepOptions(r, settings)
    local S, input, cands = ns.WritSearch, r.input, r.cands
    local plan, receipts, cap = CheapestRep(r, input, cands, settings)
    local options = {}
    for _, level in ipairs(LEVELS) do
        local copy = {}
        for k, v in pairs(plan) do copy[k] = v end
        local tied = S.Tiebreak(copy, cands.writs, level)
        options[#options + 1] = { level = level, plan = P.RepriceLines(tied, input.prices, input, r.bundleOf) }
    end
    local fewest = P.FewestBuys(S, cands.writs, r.target, receipts, cap)
    local buys = { level = -1, kind = "buys", plan = P.RepriceLines(fewest, input.prices, input, r.bundleOf) }
    SetOptions(r, options, buys)
    r.writsCapped = cap ~= nil and r.target > cap
    r.receipts = receipts ~= nil
end

local function Calculate(prices, base)
    local settings = Settings()
    local input = ns.WritState.Snapshot(settings)
    if prices then input.prices = prices end
    local cands = ns.WritState.BuildCandidates(input)
    local standing = ns.WritState.Standing()
    local mode = base and base.mode or state.mode
    local r = { mode = mode, input = input, cands = cands, standing = standing, bundleOf = BundlesOf(cands),
        reset = P.ResetText(DailyReset()) }
    r.allDone = #cands.writs == 0 and #cands.unpriced == 0 and next(input.doneToday) ~= nil
    if base then
        r.target = base.target
    else
        r.target = P.ParseAmount(targetBox and targetBox:GetText())
    end
    if not r.target or r.target <= 0 then return r end

    if mode == "favor" then
        local plan = P.RepriceLines(CheapestPlan(r, input, cands, settings), input.prices, input, r.bundleOf)
        SetOptions(r, { { level = 0, plan = plan } })
    else
        RepOptions(r, settings)
    end
    r.age = input.scanAge
    return r
end

local function OwnedNote(line, input)
    local ref, owned = line.ref, input.owned
    local writ = (owned[ref.writID] or 0) > 0 or (input.onQuest and input.onQuest[ref.questID]) == true
    local item = (owned[ref.itemID] or 0) >= (ref.qty or 1)
    if writ and item then return " " .. GREY .. "(owned)|r" end
    if writ then return " " .. GREY .. "(writ owned)|r" end
    if item then return " " .. GREY .. "(item owned)|r" end
    return ""
end

local function LineItems(line, r)
    local ref = line.ref
    if line.kind == "writ" then return { ref.writID, ref.itemID } end
    if line.kind == "crate" then
        local bundle = r.bundleOf[ref]
        return { not line.owned and ref.itemID or nil, bundle and bundle.itemID or nil }
    end
    return { line.crateRef and line.crateRef.itemID or nil }
end

local function ShortNote(line, r)
    local marks = MarksOf(r)
    if not marks then return "" end
    local items = LineItems(line, r)
    for i = 1, 2 do
        local mark = items[i] and marks[items[i]]
        if mark and mark.atScan then return " " .. ORANGE .. ("(only %d listed at last scan)"):format(mark.short) .. "|r" end
        if mark and mark.short == 0 then return " " .. ORANGE .. "(none listed)|r" end
        if mark and mark.short then return " " .. ORANGE .. ("(only %d listed)"):format(mark.short) .. "|r" end
    end
    return ""
end

local function BaseEntry(line, r)
    local ref = line.ref
    if line.kind == "writ" then
        local tip = ("Requests %d %s. Turn in to %s"):format(ref.qty or 1, P.ItemLabel(ref.itemID, ref.item or "?"), ref.npc or "?")
        if ref.x and ref.y then tip = tip .. (" in %s (%.1f, %.1f)."):format(ref.zone or "?", ref.x, ref.y) else tip = tip .. "." end
        return { text = P.WritName(ref) .. OwnedNote(line, r.input), right = P.FormatMoney(line.cost), extra = ("+%d"):format(line.gain),
            tooltip = tip, itemID = ref.writID }
    elseif line.kind == "crate" then
        local text = ("%dx %s"):format(line.count, P.CrateName(ref)) .. (line.owned and (" " .. GREY .. "(owned)|r") or "")
        local bundle = r.bundleOf[ref]
        local tip = bundle and ("Fill each with %d %s."):format(bundle.count, P.ItemLabel(bundle.itemID, bundle.name)) or nil
        if line.confirmed == false then
            text = text .. UNCONFIRMED
            tip = (tip and tip .. "\n" or "") .. CRATE_TIP
        end
        return { text = text, right = P.FormatMoney(line.cost), extra = ("+%s Favor"):format(P.FormatNumber(line.gain)),
            tooltip = tip, itemID = ref.itemID }
    end
    return {
        text = ("%dx Forged Delivery Receipt"):format(line.count),
        right = P.FormatMoney(line.cost), extra = ("+%s"):format(P.FormatNumber(line.gain)),
        tooltip = RECEIPT_TIP,
    }
end

local function BankNote(line)
    if not line.fromBank then return "" end
    return " " .. ORANGE .. ("(%d from bank)"):format(line.fromBank) .. "|r"
end

local function LineEntry(line, r)
    local entry = BaseEntry(line, r)
    entry.text = entry.text .. BankNote(line) .. ShortNote(line, r)
    return entry
end

local function Plural(n, word)
    return ("%d %s%s"):format(n, word, n == 1 and "" or "s")
end

local OTHER_GROUP = "Crates & receipts"
local RECEIPT_GROUP = "Receipts"
local SCRIBE_TIP = "At the camp's Uncertified Scribe: %s Favor buys %s (15 each). "
    .. "Put one on each empty crate and turn it in for +50 rep."

function P.Groups(plan, mode)
    local groups, byName = {}, {}
    local function group(name)
        local g = byName[name]
        if not g then
            g = { title = name, lines = {}, count = 0, cost = 0, gain = 0 }
            byName[name] = g
            if name ~= OTHER_GROUP then groups[#groups + 1] = g end
        end
        return g
    end
    for _, line in ipairs(plan.lines) do
        local g = group(line.kind == "writ" and (line.zone or "?") or OTHER_GROUP)
        g.lines[#g.lines + 1] = line
        g.cost = g.cost + (line.cost or 0)
        g.count = g.count + (line.count or 1)
        if (line.kind == "crate") == (mode == "favor") then g.gain = g.gain + (line.gain or 0) end
    end
    local other = byName[OTHER_GROUP]
    if other then
        groups[#groups + 1] = other
        for _, line in ipairs(other.lines) do
            if line.kind == "receipt" and mode ~= "favor" then
                other.title, other.receipt, other.count = RECEIPT_GROUP, line, line.count or 0
            end
        end
    end
    return groups, #groups > 1 or (groups[1] and groups[1].title ~= OTHER_GROUP)
end

local MACRO_TIP = "The KLH Fill Crate and KLH Receipt macros do the filling and the receipts one key press at a time "
    .. "(Writ & Crate Planner settings, Create macros)."

local function NameList(names)
    if #names <= 1 then return names[1] or "" end
    return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

function P.ReceiptHowTo(g, r)
    local receipt, favor = g.receipt, r.plan.favor
    local fills, seen = {}, {}
    for _, line in ipairs(g.lines) do
        local name = line.kind == "crate" and P.CrateName(line.ref)
        if name and not seen[name] then
            seen[name] = true
            fills[#fills + 1] = name
        end
    end
    local count = receipt.count or 0
    local own = favor and favor.fromBalance > 0
    local parts = {}
    if #fills > 0 then parts[#parts + 1] = ("Fill and turn in every %s for Favor."):format(NameList(fills)) end
    local pay = #fills > 0 and (own and "that and your own Favor" or "that Favor") or "your Favor"
    parts[#parts + 1] = ("Buy %s at the Scribe with %s."):format(Plural(count, "receipt"), pay)
    local bought = receipt.bought or 0
    local target = bought > 0 and bought == count and receipt.crateRef and "empty " .. P.CrateName(receipt.crateRef) or "empty crate"
    parts[#parts + 1] = ("Put one on each %s and turn it in."):format(target)
    return table.concat(parts, " ")
end

function P.ReceiptSteps(g, r)
    local receipt, favor, rows = g.receipt, r.plan.favor, {}
    for _, line in ipairs(g.lines) do
        if line.kind == "crate" then
            local bundle = r.bundleOf[line.ref]
            local tip = bundle and ("Fill each with %d %s and turn it in at the camp for Favor."):format(bundle.count,
                P.ItemLabel(bundle.itemID, bundle.name))
                or "Fill each and turn it in at the camp for Favor."
            if line.confirmed == false then tip = tip .. "\n" .. CRATE_TIP end
            rows[#rows + 1] = {
                text = ("%dx %s"):format(line.count, P.CrateName(line.ref)) .. (line.owned and (" " .. GREY .. "(owned)|r") or "")
                    .. (line.confirmed == false and UNCONFIRMED or "") .. BankNote(line) .. ShortNote(line, r),
                right = P.FormatMoney(line.cost), extra = ("+%s Favor"):format(P.FormatNumber(line.gain)), tooltip = tip,
                itemID = line.ref.itemID,
            }
        end
    end
    local bought = receipt.bought or 0
    if bought > 0 then
        local name = receipt.crateRef and P.CrateName(receipt.crateRef) or "Waylaid Crate"
        rows[#rows + 1] = { text = ("%dx %s"):format(bought, name) .. " " .. GREY .. "(empty)|r" .. ShortNote(receipt, r),
            right = P.FormatMoney(receipt.cost), tooltip = "Empty crates to put the receipts on.",
            itemID = receipt.crateRef and receipt.crateRef.itemID }
    end
    local own = (receipt.count or 0) - bought
    if own > 0 then
        rows[#rows + 1] = { text = ("%dx empty crate%s you have"):format(own, own == 1 and "" or "s") .. BankNote(receipt),
            tooltip = "Empty crates you already carry take a receipt each." }
    end
    local need = favor and favor.need or (receipt.count or 0) * 15
    rows[#rows + 1] = {
        text = ("%dx Forged Delivery Receipt"):format(receipt.count or 0),
        extra = ("+%s"):format(P.FormatNumber(receipt.gain or 0)),
        tooltip = SCRIBE_TIP:format(P.FormatNumber(need), Plural(receipt.count or 0, "Forged Delivery Receipt")),
        itemID = ns.Data.DeliveryReceipt,
    }
    rows[#rows + 1] = {
        text = GREY .. P.ReceiptHowTo(g, r) .. "|r",
        tooltip = SCRIBE_TIP:format(P.FormatNumber(need), Plural(receipt.count or 0, "Forged Delivery Receipt")) .. "\n\n" .. MACRO_TIP,
    }
    return rows
end

local function GroupTitle(g)
    return ("%s (%d)"):format(g.title, g.count)
end

local function GroupExtra(g)
    if g.gain > 0 then return ("+%s"):format(P.FormatNumber(g.gain)) end
end

--- view: nil shows every group open; otherwise only the groups in view.open are open.
function P.Entries(r, view)
    local entries = {}
    local groups, headed = P.Groups(r.plan, r.mode)
    for _, g in ipairs(groups) do
        local closed = headed and view ~= nil and not (view.open and view.open[g.title])
        if headed then
            entries[#entries + 1] = { text = (closed and "+ " or "- ") .. GroupTitle(g), header = true, data = { group = g.title },
                right = P.FormatMoney(g.cost), extra = GroupExtra(g) }
        end
        if not closed then
            local rows = g.receipt and P.ReceiptSteps(g, r) or nil
            if not rows then
                rows = {}
                for _, line in ipairs(g.lines) do rows[#rows + 1] = LineEntry(line, r) end
            end
            for _, e in ipairs(rows) do
                e.indent = headed
                entries[#entries + 1] = e
            end
        end
    end
    return entries
end

local function Planned(r)
    return r.target and r.target > 0 and r.plan and #r.plan.lines > 0
end

local function Zones(n)
    return n == 1 and "1 zone" or ("%d zones"):format(n)
end

local function ColorCode(rgb)
    return ("|cff%02x%02x%02x"):format(math.floor(rgb[1] * 255 + 0.5), math.floor(rgb[2] * 255 + 0.5), math.floor(rgb[3] * 255 + 0.5))
end

local YOUNG_DAYS = 10

function P.YoungNote(pc)
    local days = pc and pc.days
    if not days or days >= YOUNG_DAYS then return "" end
    return " " .. GREY .. ("(%d day%s)"):format(days, days == 1 and "" or "s") .. "|r"
end

function P.PricePct(pc, level)
    local v = pc and pc.byLevel and pc.byLevel[level]
    if not v then return nil end
    return ColorCode(ns.WritHistory.TIER_COLOR[v.tier]) .. ("%+d%%"):format(math.floor(v.pct * 100 + 0.5)) .. "|r"
end

local PRICE_REASON = {
    none = "No price history",
    empty = "No usual price for this target",
    short = "No usual price for this target",
}

local function PriceReason(pc)
    if pc.reason == "few" then return ("Not enough price history (%d days)"):format(pc.days or 0) end
    return PRICE_REASON[pc.reason]
end

function P.Summary(r)
    local unit = r.mode == "favor" and "Favor" or "rep"
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    if r.waiting and r.refreshing then
        add("|cffffd100Refreshing outdated Auctionator prices first...|r")
        add(GREY .. "Auctionator is scanning the auction house; the search starts when it is done.|r")
        return { text = table.concat(lines, "\n") }
    elseif r.waiting then
        add("|cffffd100Waiting for Auctionator...|r")
        add(GREY .. "Its auction house scan is still running; the search starts when it is done.|r")
        return { text = table.concat(lines, "\n") }
    end
    if r.progress then
        add("|cffffd100Adding up AH listings...|r")
        add(GREY .. ("%d of %d items"):format(r.progress[1], r.progress[2]) .. "|r")
        return { text = table.concat(lines, "\n") }
    end
    if r.idle then
        if r.target and r.target > 0 then
            add(("Press Search to plan +%s %s."):format(P.FormatNumber(r.target), unit))
        else
            add(r.mode == "favor" and "Type a target amount." or "Type a target amount, or pick a standing.")
        end
    elseif Planned(r) and r.options and #r.options > 0 and not r.selected then
        return nil
    elseif Planned(r) then
        local plan = r.plan
        local v = r.view or r
        local bank = P.BankText(plan, v.bundleOf, v.input and v.input.onQuest)
        if bank then add(ORANGE .. "Get from your bank first: " .. bank .. P.BankAge(r.input and r.input.bankAt) .. "|r") end
        if (plan.ownValue or 0) > 0 then add(GREY .. P.CostSplit(plan) .. "|r") end
        if plan.short > 0 then
            add(ORANGE .. ("Reaches +%s of +%s today; %s %s left for another day."):format(P.FormatNumber(plan.gain),
                P.FormatNumber(r.target), P.FormatNumber(plan.short), unit) .. "|r")
        end
    else
        if not r.target then
            add(r.mode == "favor" and "Type a target amount." or "Type a target amount, or pick a standing.")
        elseif r.target <= 0 then
            add("Already reached.")
        else
            local cands = r.cands or {}
            if cands.lowLevel and r.mode == "rep" then
                add(ORANGE .. "Writs need level 10.|r")
            elseif r.allDone then
                add("Every writ is done today." .. (r.reset and (" " .. r.reset .. ".") or ""))
            elseif cands.unpriced and #cands.unpriced > 0 then
                add("Nothing priced to plan with. Scan the AH with Auctionator first.")
            else
                add("Nothing to plan with: no writs or crates are available.")
            end
        end
    end
    if #lines == 0 then return nil end
    return { text = table.concat(lines, "\n") }
end

function P.BankAge(scannedAt, now)
    now = now or (_G.time and _G.time())
    if not (scannedAt and now) then return "" end
    local days = math.floor((now - scannedAt) / 86400)
    if days < 1 then return "" end
    return (" (bank seen %d day%s ago)"):format(days, days == 1 and "" or "s")
end

function P.CostSplit(plan)
    local own = plan.ownValue or 0
    return ("Cost %s: buy %s, your mats %s"):format(P.ShortMoney(plan.cost), P.ShortMoney(math.max(0, (plan.cost or 0) - own)),
        P.ShortMoney(own))
end

function P.Frontier(options)
    local sorted = {}
    for _, o in ipairs(options) do sorted[#sorted + 1] = o end
    table.sort(sorted, function(x, y)
        if x.plan.cost ~= y.plan.cost then return x.plan.cost < y.plan.cost end
        return x.level < y.level
    end)
    local out, fewest = {}, nil
    for _, o in ipairs(sorted) do
        local zones = o.plan.zones
        if #out == 0 or (zones and fewest and zones < fewest) then
            out[#out + 1] = o
            fewest = zones
        end
    end
    return out
end

function P.ShortMoney(copper)
    return P.FormatMoney(copper)
end

function P.OptionLabel(r, i)
    local o, first = r.options[i], r.options[1]
    if o.kind == "buys" then return ("Fewest buys (%s)"):format(Plural(o.buys or 0, "item")) end
    if i == 1 then return "Cheapest" end
    if not (o.plan.zones and first.plan.zones) then return ("Option %d"):format(i) end
    local fewer = first.plan.zones - o.plan.zones
    return ("-%d zone%s, +%s"):format(fewer, fewer == 1 and "" or "s", P.ShortMoney(o.plan.cost - first.plan.cost))
end

function P.PlanLines(r, o, title)
    local unit = r.mode == "favor" and "Favor" or "rep"
    local plan = o.plan
    local lines = { { left = title or "Plan", gold = true } }
    local function stat(name, value) lines[#lines + 1] = { left = name, right = value, label = true } end
    stat("Cost", P.FormatMoney(plan.cost))
    if (plan.ownValue or 0) > 0 then
        stat("  To buy", P.FormatMoney(math.max(0, plan.cost - plan.ownValue)))
        stat("  Your mats", P.FormatMoney(plan.ownValue))
    end
    stat("Gain", ("+%s %s"):format(P.FormatNumber(plan.gain or 0), unit))
    local pc = r.priceCheck
    if pc then
        local pct = P.PricePct(pc, o.level)
        local value = pct and (pct .. P.YoungNote(pc)) or PriceReason(pc)
        if value then stat("Price check", value) end
        local v = pct and pc.byLevel[o.level]
        if v then
            stat("  Per " .. unit, P.FormatMoney(v.unit))
            stat("  Usual", P.FormatMoney(pc.usualUnit))
        end
    end
    if plan.zones and r.mode ~= "favor" then stat("Zones", tostring(plan.zones)) end
    if o.buys then stat("Items to buy", tostring(o.buys)) end
    local favor = plan.favor
    if favor then
        stat("Favor for receipts", P.FormatNumber(favor.need))
        if favor.fromBalance > 0 then stat("Paid with your Favor", P.FormatNumber(favor.fromBalance)) end
        stat("From crates", P.FormatNumber(math.max(0, favor.need - favor.fromBalance)))
    end
    if (plan.short or 0) > 0 then
        lines[#lines + 1] = { left = ("Reaches +%s of +%s today."):format(P.FormatNumber(plan.gain), P.FormatNumber(r.target)), warn = true }
    end
    local bank = P.BankText(plan, (o.from or r).bundleOf, (o.from or r).input and (o.from or r).input.onQuest)
    if bank then lines[#lines + 1] = { left = "Get from your bank first: " .. bank, warn = true } end
    lines[#lines + 1] = { left = " " }
    for _, g in ipairs((P.Groups(plan, r.mode))) do
        local extra = GroupExtra(g)
        lines[#lines + 1] = { left = GroupTitle(g), right = P.FormatMoney(g.cost) .. (extra and (GREY .. "  " .. extra .. "|r") or "") }
    end
    return lines
end

function P.OptionRows(r)
    local rows = {}
    for i, o in ipairs(r.options or {}) do
        local plan = o.plan
        local extra = (plan.zones and r.mode ~= "favor") and Zones(plan.zones) or ("+%s Favor"):format(P.FormatNumber(plan.gain or 0))
        local label = P.OptionLabel(r, i)
        local text = label
        if (plan.short or 0) > 0 then text = text .. " " .. ORANGE .. "(short)|r" end
        local loading = r.progress ~= nil
        local v = r.priceCheck and r.priceCheck.byLevel and r.priceCheck.byLevel[o.level]
        local file = v and ns.WritHistory.TIER_ICON[v.tier]
        local color = file and ns.WritHistory.TIER_COLOR[v.tier]
        rows[#rows + 1] = {
            text = text, right = P.FormatMoney(plan.cost), extra = extra,
            data = not loading and i or nil, selected = i == r.selected or nil,
            tooltipLines = not loading and P.PlanLines(r, o, label) or nil,
            icon = file and { file = file, r = color[1], g = color[2], b = color[3] } or nil,
        }
    end
    return rows
end

function P.WindowRows(r, view)
    local options = P.OptionRows(r)
    if not r.selected then return options, nil end
    local picked = {}
    for k, v in pairs(options[r.selected]) do picked[k] = v end
    picked.selected = nil
    local pinned = {
        { text = "Show other options", button = true, data = "options" },
        picked,
    }
    return P.Entries(r.view or r, view), pinned
end

function P.RestoreState(st, saved)
    if type(saved) ~= "table" then return "" end
    if saved.mode == "rep" or saved.mode == "favor" then st.mode = saved.mode end
    return type(saved.target) == "string" and saved.target or ""
end

local NAME_LIMIT = 8

local function Unpriced(names, stale)
    local skip, out = {}, {}
    for _, name in ipairs(stale) do skip[name] = true end
    for _, name in ipairs(names) do
        if not skip[name] then out[#out + 1] = name end
    end
    return out
end

function P.Footer(r)
    local title = { left = "Planner info", gold = true }
    local lines, warn = { title }, false
    local function add(text, kind)
        lines[#lines + 1] = { left = text, grey = kind == nil, warn = kind == "warn" }
        if kind == "warn" then warn = true end
    end
    local function section(heading, names)
        if #names == 0 then return end
        lines[#lines + 1] = { left = " " }
        lines[#lines + 1] = { left = heading, header = true }
        for i = 1, math.min(#names, NAME_LIMIT) do lines[#lines + 1] = { left = names[i], grey = true } end
        if #names > NAME_LIMIT then lines[#lines + 1] = { left = ("and %d more"):format(#names - NAME_LIMIT), grey = true } end
    end
    if Planned(r) then
        local liveN, scanN = LiveCounts(MarksOf(r))
        if liveN then
            add(("%s priced by %s listings, %d at Auctionator's cheapest"):format(Plural(liveN, "item"),
                liveN == 1 and "its" or "their", scanN))
        else
            add("Auctionator's cheapest price; buying many can cost more.")
        end
        if r.age and r.age >= 1 then
            title.left, title.gold, title.warn = ("Scan is %d day%s old: rescan the AH"):format(r.age, r.age == 1 and "" or "s"), nil, true
            warn = true
        elseif r.age then
            title.left = "Prices from today's scan"
        end
        if r.writsCapped then
            add(r.receipts and "Writs give no rep past Friendly; receipts cover the rest." or "Writs give no rep past Friendly.")
        end
        local pc = r.priceCheck
        if pc then
            if pc.method then
                add(("Price check: %s, %d days"):format(pc.method == "days" and "Past days" or "Typical prices", pc.days or 0))
            else
                local reason = PriceReason(pc)
                if reason then add(reason) end
            end
        end
    end
    if r.cands.lowLevel and r.mode == "rep" then add("Writs need level 10.", "warn") end
    if r.reset then add(r.reset) end
    local stale = r.input and r.input.notInScan or {}
    local unpriced = Unpriced(r.cands.unpriced, stale)
    section("Not in your last scan", stale)
    section(LiveCounts(MarksOf(r)) and "No price or none listed" or "No price", unpriced)
    if #lines == 1 and not r.age then return nil end
    local plain = {}
    for i = 1, #lines do plain[#plain + 1] = lines[i].left end
    return { lines = lines, text = table.concat(plain, "\n"), warn = warn }
end

local function StatusLine(standing)
    local parts = {}
    if standing.standingID then
        local s = StandingName(standing.standingID)
        if (standing.max or 0) > 0 then
            s = s .. (" %s / %s"):format(P.FormatNumber(standing.current or 0), P.FormatNumber(standing.max))
        end
        parts[1] = s
    else
        parts[1] = "Standing unknown"
    end
    parts[2] = "Favor " .. (standing.favor and P.FormatNumber(standing.favor) or "?")
    return table.concat(parts, "  |  ")
end

local SCAN_TIP = "Auctionator is scanning the auction house. Search unlocks when the scan is done."
local CALC_TIP = "Still adding up AH listings."
local PICK_TIP = "Pick an option first: click one of the results."
local NO_NOTES = { text = "Nothing to note yet.", lines = { { left = "Planner info", gold = true }, { left = "Nothing to note yet.", grey = true } } }

local function Scanning()
    return ns.WritDepth.AuctionatorScanning()
end

local Render, Search

local shown, shownScanning

local function UpdateButtons(r)
    local scanning = Scanning()
    shownScanning = scanning
    window:SetActionState(1, true)
    window:SetActionState(2, r.selected ~= nil and not r.progress, r.progress and CALC_TIP or PICK_TIP)
    local busy = r.progress ~= nil or r.waiting == true
    searchButton.label:SetText(busy and "Cancel" or "Search")
    searchButton:SetActive(busy or not scanning)
    searchButton.tip = (not busy and scanning) and SCAN_TIP or nil
end

local function Show(r)
    if not window then return end
    shown = r
    statusText:SetText(StatusLine(r.standing))
    for mode, b in pairs(modeButtons) do b:SetSelected(mode == state.mode) end
    standingArrow:SetShown(state.mode == "rep")
    targetBox:SetTextInsets(6, state.mode == "rep" and 24 or 6, 0, 0)
    local entries = {}
    local pinned
    if r.target and r.target > 0 and r.options and #r.options > 0 and #r.plan.lines > 0 then
        entries, pinned = P.WindowRows(r, state.view)
    end
    UpdateButtons(r)
    window:SetInfo(P.Footer(r) or NO_NOTES)
    window:SetEntries(entries, P.Summary(r), pinned)
end

function P.LastResult()
    return last
end

function P.SyncScanState()
    if not (window and shown) or Scanning() == shownScanning then return false end
    if shown.waiting and not Scanning() then Render() else Show(shown) end
    return true
end

local function PickOption(i)
    if i == "options" then
        state.pick = nil
        state.view = { open = {} }
        if last then
            SelectOption(last)
            Show(last)
        end
        return
    end
    if type(i) == "table" and i.group then
        state.view.open[i.group] = not state.view.open[i.group] or nil
        if last then Show(last) end
        return
    end
    local o = last and last.options and last.options[i]
    if not o then return end
    state.view = { open = {} }
    state.pick = o.level
    SelectOption(last)
    Show(last)
end

local MAX_ROUNDS = 3
local LIVE_MIN_QTY = 10
local depth = { ahOpen = false }

local function StopDepth()
    depth.run = nil
    if depth.queue then depth.queue:Cancel() end
end

local function NeedIDs(needs, have, tried, minQty)
    local ids = {}
    for id, n in pairs(needs) do
        if n >= (minQty or 1) and not ((have and have[id]) or (tried and tried[id])) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end
P.NeedIDs = NeedIDs

local function SameNeeds(a, b)
    for id, n in pairs(a) do if b[id] ~= n then return false end end
    for id in pairs(b) do if a[id] == nil then return false end end
    return true
end

local function PlanNeeds(r, plan)
    return ns.WritDepth.Needs(plan, r.input.owned, r.bundleOf, r.input.onQuest)
end

local function RNeeds(r)
    local all = {}
    for _, o in ipairs(r.options or {}) do
        for id, n in pairs(PlanNeeds(r, o.plan)) do all[id] = math.max(all[id] or 0, n) end
    end
    return all
end

-- Owned mats still cost their price so options compare at full value.
function P.RepriceLines(plan, prices, input, bundleOf)
    local onQuest, left, bags = input.onQuest or {}, {}, {}
    for id, n in pairs(input.owned or {}) do left[id] = n end
    for id, n in pairs(input.bags or input.owned or {}) do bags[id] = n end
    local fromBank, bankNames, ownValue = {}, {}, 0
    local function take(id, n)
        local used = math.min(n, left[id] or 0)
        left[id] = (left[id] or 0) - used
        local inBags = math.min(used, bags[id] or 0)
        bags[id] = (bags[id] or 0) - inBags
        local banked = used - inBags
        if banked > 0 then fromBank[id] = (fromBank[id] or 0) + banked end
        return n - used, used, banked
    end
    local function takeEmpties(n)
        local rows, banked = EmptyCrateRows(input.data), 0
        for _, row in ipairs(rows) do
            local inBags = math.min(n, bags[row.itemID] or 0, left[row.itemID] or 0)
            if inBags > 0 then
                take(row.itemID, inBags)
                n = n - inBags
            end
        end
        for _, row in ipairs(rows) do
            if n <= 0 then break end
            local missing, _, b = take(row.itemID, n)
            n = missing
            if b > 0 then
                banked = banked + b
                bankNames[row.itemID] = CrateItemName(row)
            end
        end
        return banked
    end
    local function mat(id, n)
        local missing, used, banked = take(id, n)
        local price = prices[id]
        if price then ownValue = ownValue + price * used end
        local cost = price and price * n or (missing == 0 and 0 or nil)
        return cost, banked
    end
    local total, lines = 0, {}
    for i, src in ipairs(plan.lines) do
        local line = {}
        for k, v in pairs(src) do line[k] = v end
        local ref, cost = line.ref, nil
        line.fromBank = nil
        if line.kind == "writ" then
            local count = line.count or 1
            local writs, writBank = 0, 0
            if not onQuest[ref.questID] then
                local missing, _, banked = take(ref.writID, count)
                writs, writBank = missing, banked
            end
            local itemPart, itemBank = mat(ref.itemID, (ref.qty or 1) * count)
            local writPart = writs == 0 and 0 or (prices[ref.writID] and prices[ref.writID] * writs)
            if writPart and itemPart then cost = writPart + itemPart end
            if writBank + itemBank > 0 then line.fromBank = writBank + itemBank end
        elseif line.kind == "crate" then
            local bundle, count = bundleOf[ref], line.count or 1
            local fill, banked
            if bundle then fill, banked = mat(bundle.itemID, bundle.count * count) end
            local buy = line.owned and 0 or (prices[ref.itemID] and prices[ref.itemID] * count)
            if fill and buy then cost = fill + buy end
            banked = banked or 0
            if line.owned then
                local _, _, crateBank = take(ref.itemID, count)
                if crateBank > 0 then bankNames[ref.itemID] = CrateItemName(ref) end
                banked = banked + crateBank
            end
            if banked > 0 then line.fromBank = banked end
        elseif line.kind == "receipt" then
            local bought = line.bought or 0
            local price = bought > 0 and line.crateRef and prices[line.crateRef.itemID]
            if bought == 0 then cost = 0 elseif price then cost = bought * price end
        end
        if cost then line.cost = cost end
        total = total + (line.cost or 0)
        lines[i] = line
    end
    for _, line in ipairs(lines) do
        local own = line.kind == "receipt" and (line.count or 0) - (line.bought or 0) or 0
        if own > 0 then
            local banked = takeEmpties(own)
            if banked > 0 then line.fromBank = banked end
        end
    end
    local out = {}
    for k, v in pairs(plan) do out[k] = v end
    out.lines, out.cost, out.ownValue = lines, total, ownValue
    out.fromBank = next(fromBank) and fromBank or nil
    out.bankNames = next(bankNames) and bankNames or nil
    return out
end

function P.RejudgeAtScan(pc, r, scan, settings)
    if not (pc and pc.usualUnit and r.options) then return pc end
    local out = {}
    for k, v in pairs(pc) do out[k] = v end
    out.byLevel = JudgeLevels(r.options, pc.usualUnit, settings, function(o)
        local from = o.from or r
        return Unit(P.RepriceLines(o.plan, scan, from.input, from.bundleOf))
    end)
    return out
end

local function FinishDepth(run)
    local D = ns.WritDepth
    local best = {}
    for _, r in ipairs(run.seen) do
        if Planned(r) then
            for _, o in ipairs(r.options) do
                local cost = D.PlanCost(o.plan, r.input.owned, run.listings, run.scan, r.bundleOf, r.input.onQuest)
                local b = best[o.level]
                if cost and (not b or cost < b.cost) then best[o.level] = { level = o.level, plan = o.plan, cost = cost, from = r, kind = o.kind } end
            end
        end
    end
    local options, buys = {}, nil
    for _, b in pairs(best) do
        local prices, marks = D.EffectivePrices(PlanNeeds(b.from, b.plan), run.listings, run.scan)
        local plan = P.RepriceLines(b.plan, prices, b.from.input, b.from.bundleOf)
        local o = { level = b.level, plan = plan, marks = marks, from = b.from, kind = b.kind }
        if b.kind == "buys" then buys = o else options[#options + 1] = o end
    end
    local r = run.seen[#run.seen] or run.base
    r.stamp = run.base.stamp
    if #options > 0 or buys then SetOptions(r, options, buys) end
    r.priceCheck = P.RejudgeAtScan(run.base.priceCheck, r, run.scan, Settings())
    r.progress = nil
    last = r
    Show(r)
end

local Fetch

local function Round(run, closed)
    if depth.run ~= run then return end
    local D = ns.WritDepth
    while true do
        run.rounds = run.rounds + 1
        local needs = RNeeds(run.latest)
        local prices = D.EffectivePrices(needs, run.listings, run.scan)
        local nr = Calculate(prices, run.base)
        run.seen[#run.seen + 1] = nr
        if not Planned(nr) then break end
        local nextNeeds = RNeeds(nr)
        local missing = NeedIDs(nextNeeds, run.listings, run.tried, run.minQty)
        if run.rounds >= MAX_ROUNDS or SameNeeds(needs, nextNeeds) then break end
        run.latest = nr
        if #missing > 0 then
            if closed or not depth.ahOpen then break end
            Fetch(run, missing)
            return
        end
    end
    depth.run = nil
    FinishDepth(run)
end

Fetch = function(run, ids)
    for _, id in ipairs(ids) do run.tried[id] = true end
    run.base.progress = { 0, #ids }
    Show(run.base)
    depth.queue:Run(ids, function(done, total)
        if depth.run ~= run then return end
        run.base.progress = { done, total }
        Show(run.base)
    end, function(listings, closed)
        if depth.run ~= run then return end
        for id, list in pairs(listings or {}) do run.listings[id] = list end
        Round(run, closed)
    end)
end

local function StartDepth(r)
    local D = ns.WritDepth
    StopDepth()
    if not Planned(r) then return end
    local needs = RNeeds(r)
    local minQty = Settings().liveMinQty or LIVE_MIN_QTY
    local ids = NeedIDs(needs, nil, nil, minQty)
    if depth.ahOpen and depth.queue and #ids > 0 then
        local run = { base = r, latest = r, seen = { r }, listings = {}, tried = {}, scan = r.input.prices, rounds = 0,
            minQty = minQty }
        depth.run = run
        Fetch(run, ids)
    else
        local atScan = D.ShortAtScan(needs, D.ScanAvailable(needs))
        if next(atScan) then
            for _, o in ipairs(r.options) do
                o.marks = o.marks or {}
                for id, k in pairs(atScan) do o.marks[id] = o.marks[id] or { short = k, atScan = true } end
            end
            Show(r)
        end
    end
end

local function Progress(mode)
    local st = ns.WritState.Standing()
    if mode == "favor" then return st.favor end
    return st.total
end

local function Now()
    local f = _G.GetServerTime
    return type(f) == "function" and f() or nil
end

local function ShowIdle()
    StopDepth()
    last = nil
    Show({ idle = true, mode = state.mode, standing = ns.WritState.Standing(), cands = { unpriced = {} }, input = {},
        target = P.ParseAmount(targetBox and targetBox:GetText()), reset = P.ResetText(DailyReset()) })
end

local function RefreshInputs()
    local saved = ns.CharData(KEY).plan
    if not (targetBox and type(saved) == "table" and saved.goal and saved.mode == state.mode) then return end
    if targetBox:GetText() ~= (saved.target or "") then return end
    local cur = Progress(state.mode)
    if type(cur) ~= "number" then return end
    local left = saved.goal - cur
    saved.target = left > 0 and tostring(left) or ""
    if left <= 0 then saved.goal = nil end
    targetBox:SetText(saved.target)
end

local function Stale(r)
    local stamp = r and r.stamp
    if not stamp then return false end
    if Progress(r.mode) ~= stamp.cur then return true end
    local now = Now()
    return now ~= nil and stamp.resetAt ~= nil and now >= stamp.resetAt
end

Render = function()
    if not window then return end
    local text = targetBox and targetBox:GetText() or ""
    local target, cur = P.ParseAmount(text), Progress(state.mode)
    ns.CharData(KEY).plan = { mode = state.mode, target = text,
        goal = target and type(cur) == "number" and cur + target or nil }
    local refreshing = false
    if depth.ahOpen and not Scanning() and ns.WritDepth.ScanOutdated() then
        refreshing = ns.WritDepth.StartScan() and Scanning()
    end
    if Scanning() then
        StopDepth()
        last = { waiting = true, refreshing = refreshing, mode = state.mode, standing = ns.WritState.Standing(),
            cands = { unpriced = {} }, input = {} }
        Show(last)
        return
    end
    local r = Calculate()
    r.priceCheck = P.PriceCheck(r, Settings())
    local secs, now = DailyReset(), Now()
    r.stamp = { cur = cur, resetAt = secs and now and now + secs or nil }
    last = r
    Show(r)
    StartDepth(r)
end

function P.MissingNames(terms)
    local item = _G.C_Item
    local missing = {}
    if not (item and item.GetItemNameByID and item.RequestLoadItemDataByID) then return missing end
    for _, t in ipairs(terms) do
        local name = item.GetItemNameByID(t.itemID)
        if not (type(name) == "string" and name ~= "") then missing[t.itemID] = true end
    end
    return missing
end

local NAME_WAIT = 2
local nameWait, nameFrame
local function OpenListSource() end

function P.OpenShoppingList(name)
    local ah, tab = _G.AuctionHouseFrame, _G.AuctionatorTabs_Shopping
    if not (ah and ah.IsShown and ah:IsShown() and type(tab) == "table" and tab.Click) then return false end
    tab:Click()
    pcall(function()
        local A = _G.Auctionator
        local list = A.Shopping.ListManager:GetByName(name)
        if not list then return end
        A.EventBus:RegisterSource(OpenListSource, "KlausisLittleHelpers shopping list")
        A.EventBus:Fire(OpenListSource, A.Shopping.Tab.Events.ListSearchRequested, list)
        A.EventBus:UnregisterSource(OpenListSource)
    end)
    return true
end

local CreateList

local function FinishNames()
    nameWait = nil
    if nameFrame then nameFrame:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
    CreateList(true)
end

local function WaitForNames(missing)
    for itemID in pairs(missing) do _G.C_Item.RequestLoadItemDataByID(itemID) end
    nameWait = missing
    if not nameFrame then
        nameFrame = CreateFrame("Frame")
        nameFrame:SetScript("OnEvent", function(_, _, itemID)
            if not nameWait then return end
            nameWait[itemID] = nil
            if next(nameWait) == nil then FinishNames() end
        end)
    end
    nameFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(NAME_WAIT, function() if nameWait == missing then FinishNames() end end)
    else
        ns.Print("Loading item names: click Create Auctionator list again.")
    end
end

CreateList = function(retried)
    local auc = Api()
    local r = last and (last.view or last)
    if not (auc and r and r.plan and #r.plan.lines > 0) then
        ns.Print("No plan to shop for.")
        return
    end
    local shopping = P.ShoppingTerms(r.plan, r.input.owned, r.bundleOf, r.input.onQuest)
    if #shopping == 0 then
        ns.Print("You already own everything on this plan.")
        return
    end
    if retried ~= true then
        if nameWait then return end
        local missing = P.MissingNames(shopping)
        if next(missing) then
            WaitForNames(missing)
            return
        end
    end
    local caller = ns.WritState.CALLER
    local terms = {}
    for _, t in ipairs(shopping) do
        terms[#terms + 1] = auc.ConvertToSearchString(caller, { searchString = t.name, isExact = true, quantity = t.count })
    end
    local name = r.mode == "favor" and LIST_FAVOR or LIST_REP
    auc.CreateShoppingList(caller, name, terms)
    ns.Print(("Auctionator list %s: %s."):format(name, Plural(#terms, "item")))
    P.OpenShoppingList(name)
end

local function SetMode(mode)
    if P.SwitchMode(state, mode) and targetBox then targetBox:SetText("") end
    ShowIdle()
end

local function Reset()
    state.pick = nil
    StopDepth()
    if targetBox then targetBox:SetText("") end
    ns.CharData(KEY).plan = { mode = state.mode, target = "" }
    ShowIdle()
end

local function OpenStandingMenu(owner)
    local items = {}
    local standing = ns.WritState.Standing()
    for _, id in ipairs(TARGET_STANDINGS) do
        local gain = P.GainTo(standing, id)
        items[#items + 1] = {
            text = StandingName(id), right = gain and P.FormatNumber(gain) or nil,
            onClick = function()
                if gain and targetBox then targetBox:SetText(tostring(gain)) end
            end,
        }
    end
    UI.DropdownMenu(targetBox or owner, items)
end


local function BuildTop(f, width, y)
    statusText = UI.Font(f, 11, 0.85, 0.85, 0.85)
    statusText:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    statusText:SetWidth(width)
    statusText:SetJustifyH("LEFT")
    local rowY = y - 18
    modeButtons = {
        rep = ns.CreateWindowButton(f, 50, "Rep", function() SetMode("rep") end),
        favor = ns.CreateWindowButton(f, 56, "Favor", function() SetMode("favor") end),
    }
    modeButtons.rep:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, rowY)
    modeButtons.favor:SetPoint("LEFT", modeButtons.rep, "RIGHT", -1, 0)
    searchButton = ns.CreateWindowButton(f, SEARCH_W, "Search", function()
        if last and (last.progress or last.waiting) then P.Cancel() else Search() end
    end)
    searchButton:SetPoint("TOPRIGHT", f, "TOPLEFT", PAD + width, rowY)
    UI.SkinButton(searchButton)
    searchButton:HookScript("OnEnter", function(self) if self.tip then UI.ShowTooltip(self, self.tip, "ANCHOR_BOTTOM") end end)
    searchButton:HookScript("OnLeave", function() UI.HideTooltip() end)

    local box = CreateFrame("EditBox", nil, f)
    box:SetSize(width - 50 - 56 + 1 - 8 - 6 - SEARCH_W, 22)
    box:SetPoint("LEFT", modeButtons.favor, "RIGHT", 8, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(64)
    local boxFont = UI.FontObject(12)
    if boxFont then box:SetFontObject(boxFont) else box:SetFont(UI.FontPath(), 12, "") end
    box:SetTextColor(1, 1, 1, 1)
    box:SetTextInsets(6, 24, 0, 0)
    UI.Solid(box, "BACKGROUND", 0.10, 0.10, 0.11, 0.9):SetAllPoints()
    UI.Border(box, 1, 1, 1, 0.12)
    box:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = self:GetText()
        local clean = P.CleanAmount(text)
        if clean ~= text then self:SetText(clean) end
    end)
    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        Search()
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnter", function(self)
        UI.ShowTooltip(self, "Amount to gain, for example 5800. Press Enter to search.")
    end)
    box:SetScript("OnLeave", function() UI.HideTooltip() end)
    targetBox = box
    UI.SkinEditBox(box)

    local arrow = CreateFrame("Button", nil, box)
    arrow:SetSize(22, 22)
    arrow:SetPoint("RIGHT", box, "RIGHT", 0, 0)
    arrow.tex = arrow:CreateTexture(nil, "OVERLAY")
    if UI.SetArrowTexture(arrow.tex) == "Azerite-PointingArrow" then arrow.tex:SetSize(14, 10) else arrow.tex:SetSize(16, 16) end
    arrow.tex:SetPoint("CENTER")
    arrow.tex:SetAlpha(0.7)
    arrow:SetScript("OnClick", function(self) OpenStandingMenu(self) end)
    arrow:SetScript("OnEnter", function(self)
        self.tex:SetAlpha(1)
        UI.ShowTooltip(self, "Fill in the rep needed for a standing.")
    end)
    arrow:SetScript("OnLeave", function(self)
        self.tex:SetAlpha(0.7)
        UI.HideTooltip()
    end)
    standingArrow = arrow
    return 18 + 22 + 6
end

Search = function()
    state.pick = nil
    state.view = { open = {} }
    if depth.queue then depth.queue:Clear() end
    Render()
end

function P.Cancel()
    if not last then return end
    if last.waiting then
        ShowIdle()
        return
    end
    StopDepth()
    last.progress = nil
    Show(last)
end

function P.StopAll()
    StopDepth()
    if last and (last.progress or last.waiting) then last = nil end
    nameWait = nil
    if nameFrame then nameFrame:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
end

local function SyncAHButton()
    if ahButton then ahButton:SetShown(depth.ahOpen and not (window and window:IsShown())) end
end

local function EnsureWindow()
    if window then return end
    window = ns.CreateListWindow({
        name = "KLHWritCratePlannerWindow", title = "Writ & Crate Planner", key = KEY, width = WIDTH,
        buttons = { { close = true, onClick = function() window:Hide() end } }, top = BuildTop,
        onClick = PickOption,
        actions = {
            { text = "Reset", onClick = Reset },
            { text = "Create Auctionator list", onClick = function() CreateList(false) end },
        },
    })
    window:Build()
    local target = P.RestoreState(state, ns.CharData(KEY).plan)
    if targetBox then targetBox:SetText(target) end
    local since = 0
    window.frame:HookScript("OnUpdate", function(_, elapsed)
        since = since + (elapsed or 0)
        if since < 0.5 then return end
        since = 0
        P.SyncScanState()
    end)
    window.frame:HookScript("OnHide", function() P.StopAll() end)
    window.frame:HookScript("OnShow", SyncAHButton)
    window.frame:HookScript("OnHide", SyncAHButton)
end

local function AuctionHost()
    return _G.AuctionHouseFrame or _G.AuctionFrame
end

local function Open(besideAH)
    if InCombatLockdown() then
        UI.Defer("KLH_WritPlannerOpen", function() Open(besideAH) end)
        return
    end
    EnsureWindow()
    depth.openedAtAH = besideAH == true
    local host = besideAH and AuctionHost()
    if host and host:IsShown() then
        window.frame:ClearAllPoints()
        window.frame:SetPoint("TOPLEFT", host, "TOPRIGHT", 4, 0)
        local h, hs, ws = host:GetHeight(), host:GetEffectiveScale(), window.frame:GetEffectiveScale()
        local valid = type(h) == "number" and type(hs) == "number" and type(ws) == "number" and ws > 0
        window:SetFixedHeight(valid and h * hs / ws or nil)
    else
        window:SetFixedHeight(nil)
    end
    RefreshInputs()
    if last and Stale(last) then last = nil end
    if last and not last.progress then Show(last) else ShowIdle() end
end

local function ToggleWindow()
    if window and window:IsShown() then
        window:Hide()
    else
        Open(false)
    end
end

local function ShowAHButton(retried)
    if InCombatLockdown() then
        UI.Defer("KLH_WritPlannerAHButton", function() ShowAHButton(retried) end)
        return
    end
    local host = AuctionHost()
    if not host then
        if not retried then C_Timer.After(0, function() ShowAHButton(true) end) end
        return
    end
    if not ahButton then
        ahButton = ns.CreateWindowButton(host, 110, "Writ Planner", function() Open(true) end)
        ahButton:SetPoint("TOPLEFT", host, "TOPRIGHT", 4, 0)
        ahButton:HookScript("OnEnter", function(self)
            UI.ShowTooltip(self, "Writ & Crate Planner: the cheapest writs and crates for a rep or Favor target.")
        end)
        ahButton:HookScript("OnLeave", function() UI.HideTooltip() end)
    end
    SyncAHButton()
end

local EVENTS = {
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
    "PLAYERBANKSLOTS_CHANGED", "BANK_TABS_CHANGED", "BAG_UPDATE_DELAYED",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
    "ITEM_KEY_ITEM_INFO_RECEIVED",
}
local QUEUE_EVENTS = {
    COMMODITY_SEARCH_RESULTS_UPDATED = true, ITEM_SEARCH_RESULTS_UPDATED = true,
    AUCTION_HOUSE_THROTTLED_SYSTEM_READY = true, ITEM_KEY_ITEM_INFO_RECEIVED = true,
}

local function OptionToggle(order, name, key, desc)
    return {
        type = "toggle", order = order, name = name, desc = desc, width = "normal",
        get = function() return Settings()[key] end,
        set = function(_, v)
            Settings()[key] = v == true
        end,
    }
end

local function PriceRange(order, name, min, max, desc, key)
    return {
        type = "range", order = order, name = name, desc = desc, min = min, max = max, step = 1,
        get = function() return Settings()[key] end,
        set = function(_, v) Settings()[key] = v end,
    }
end

ns.RegisterFeature({
    key = KEY,
    title = "Writ & Crate Planner",
    tab = "helpers",
    description = "Plans the cheapest Craftsman's Writs and Waylaid Crates for a trade camp rep or Merchant's Favor target from Auctionator prices, and turns the plan into an Auctionator shopping list.",
    help = "Finds the cheapest writs, crates and delivery receipts for a reputation or Merchant's Favor target from your Auctionator prices. At the auction house, click Writ Planner (or type /klh writs), enter a target and click Search. Create macros adds macros that apply receipts and fill crates.",
    requires = { "Auctionator" },
    alwaysOn = true,
    commands = { "writs" },
    defaults = {
        countBank = false, useFavorForReceipts = false, liveMinQty = 10,
        priceMethod = "typical", historyDays = 14, minDays = 5, cheapBelow = 15, highAbove = 15, dontBuyAbove = 50,
    },
    enable = function()
        RegisterObservers()
        local auc = Api()
        local usable = auc and auc.GetAuctionPriceByItemID and auc.CreateShoppingList and auc.ConvertToSearchString
        local why = _G.Auctionator and "Writ & Crate Planner: Auctionator API changed; update Auctionator or Klausi's Little Helpers."
            or "Writ & Crate Planner needs Auctionator."
        if ns.WritUse then ns.WritUse.Init() end
        ns.RegisterSlashCommand("writs", function(rest)
            local sub = (rest or ""):lower()
            if ns.WritUse and sub == "macros" then
                ns.WritUse.MakeMacros()
            elseif usable then
                ToggleWindow()
            else
                ns.Print(why)
            end
        end)
        if not usable then return end
        local events = CreateFrame("Frame")
        local valid = _G.C_EventUtils and _G.C_EventUtils.IsEventValid
        for _, event in ipairs(EVENTS) do
            if not valid or valid(event) then events:RegisterEvent(event) end
        end
        local bankOpen = false
        local liveApi = ns.WritDepth.LiveApi()
        depth.queue = liveApi and ns.WritDepth.NewQueue(liveApi)
        events:SetScript("OnEvent", function(_, event, arg)
            if event == "AUCTION_HOUSE_SHOW" then
                depth.ahOpen = true
                if depth.queue then depth.queue:OnEvent(event) end
                ShowAHButton(false)
            elseif event == "AUCTION_HOUSE_CLOSED" then
                depth.ahOpen = false
                local closeWindow = depth.openedAtAH and window and window:IsShown()
                if closeWindow then
                    depth.run = nil
                    if last and last.progress then last = nil end
                end
                if depth.queue then depth.queue:OnEvent(event) end
                if ahButton then ahButton:Hide() end
                if closeWindow then window:Hide() end
            elseif QUEUE_EVENTS[event] then
                if depth.queue then depth.queue:OnEvent(event, arg) end
            elseif event == "BANKFRAME_OPENED" then
                bankOpen = true
                ns.WritState.ScanBank()
            elseif event == "BANKFRAME_CLOSED" then
                bankOpen = false
            elseif bankOpen then
                ns.WritState.ScanBank()
            end
        end)
    end,
    options = function()
        return {
            countBank = OptionToggle(1, "Count bank items", "countBank",
                "Counts items in your bank as owned and lists what to take out of the bank before you buy. Owned items still count at their AH price, so options compare fairly. The bank is read each time you open it."),
            useFavorForReceipts = OptionToggle(2, "Spend my Favor on receipts", "useFavorForReceipts",
                "Spends the Merchant's Favor you have on Forged Delivery Receipts before filling crates for the rest. Off: receipts are still planned when they are cheaper, but all their Favor comes from filled crates and your own Favor is kept."),
            liveMinQty = {
                type = "range", order = 3, name = "Add up listings from", min = 2, max = 100, step = 1, bigStep = 5,
                desc = "For items you buy at least this many of, the planner looks up their auction house listings and adds up "
                    .. "what buying that many really costs, cheapest first. Smaller buys use Auctionator's cheapest price.",
                get = function() return Settings().liveMinQty or LIVE_MIN_QTY end,
                set = function(_, v) Settings().liveMinQty = v end,
            },
            priceHeader = { type = "header", order = 4, name = "Price check" },
            priceMethod = {
                type = "select", order = 5, name = "Usual price from",
                desc = "How the usual cost per rep or Favor is worked out from Auctionator's price history. Typical prices: the median daily low of each item. Past days: the plan priced for each past day, then the median of those costs.",
                values = { typical = "Typical prices", days = "Past days" },
                get = function() return Settings().priceMethod end,
                set = function(_, v) Settings().priceMethod = v end,
            },
            historyDays = PriceRange(6, "History days", 3, 21, "How many days of price history count as usual.", "historyDays"),
            minDays = PriceRange(7, "Minimum days", 2, 14, "Fewest days of price history needed before a verdict is shown.", "minDays"),
            cheapBelow = PriceRange(8, "Cheap below (%)", 5, 50, "Marks a plan Cheap when it costs at least this much less than usual.", "cheapBelow"),
            highAbove = PriceRange(9, "High above (%)", 5, 100, "Marks a plan High when it costs more than this much above usual.", "highAbove"),
            dontBuyAbove = PriceRange(10, "Don't buy above (%)", 20, 200, "Marks a plan Don't buy when it costs more than this much above usual.", "dontBuyAbove"),
            macroRow = { type = "description", order = 19, name = "", width = "full" },
            macros = {
                type = "execute", order = 20, name = "Create macros",
                desc = "Makes the general (account-wide) macros \"KLH Receipt\" (each press puts the next Forged Delivery Receipt on the next "
                    .. "empty Waylaid Crate) and \"KLH Fill Crate\" (each press fills the next labeled crate from a stack that covers "
                    .. "one of its bundles), then opens the macro window so you can drag them to your action bars. /klh writs macros does the same.",
                func = function() if ns.WritUse then ns.WritUse.MakeMacros() end end,
            },
        }
    end,
})
