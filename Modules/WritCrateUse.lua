local _, ns = ...

ns.WritUse = ns.WritUse or {}
local U = ns.WritUse
local UI = ns.UI

local RECEIPT = 262902
local MACRO_ICON = 134400
local ACCOUNT_MACROS = 120

local MACROS = {
    receipt = { name = "KLH Receipt", button = "KLHApplyReceiptButton", tooltip = "item:262902" },
    fill = { name = "KLH Fill Crate", button = "KLHFillCrateButton", iconItem = 248682, icon = "Interface\\Icons\\INV_Crate_07" },
}

local function LabeledCrates()
    local rows = {}
    for _, row in ipairs(ns.Data.WaylaidCrates or {}) do rows[row.itemID] = row end
    return rows
end

local function EmptyCrateIDs()
    local ids = {}
    for itemID in pairs(LabeledCrates()) do ids[itemID] = true end
    if ns.Data.UnlabeledCrate then ids[ns.Data.UnlabeledCrate.itemID] = true end
    return ids
end

--- items in bag order, skip: crate itemIDs that refused a receipt; returns { receipts, crates, uses, target? }.
function U.ReceiptPlan(items, skip)
    local crateIDs = EmptyCrateIDs()
    local plan = { receipts = 0, crates = 0, uses = 0 }
    for _, it in ipairs(items) do
        if it.itemID == RECEIPT then
            plan.receipts = plan.receipts + (it.count or 1)
        elseif crateIDs[it.itemID] and not (skip and skip[it.itemID]) then
            plan.crates = plan.crates + (it.count or 1)
            plan.target = plan.target or it
        end
    end
    plan.uses = math.min(plan.receipts, plan.crates)
    if plan.uses == 0 then plan.target = nil end
    return plan
end

--- Labeled crates filled from one stack covering a bundle, skip: refused crate itemIDs; returns { uses, crate?, stack? }.
function U.FillPlan(items, skip)
    local rows = LabeledCrates()
    local stacks = {}
    for _, it in ipairs(items) do
        if not rows[it.itemID] then stacks[#stacks + 1] = { bag = it.bag, slot = it.slot, itemID = it.itemID, left = it.count or 1 } end
    end
    local plan = { uses = 0 }
    for _, it in ipairs(items) do
        local row = not (skip and skip[it.itemID]) and rows[it.itemID]
        for _ = 1, row and (it.count or 1) or 0 do
            local picked
            for _, bundle in ipairs(row.bundles or {}) do
                for _, st in ipairs(stacks) do
                    if st.itemID == bundle.itemID and st.left >= bundle.count then
                        picked = st
                        st.left = st.left - bundle.count
                        break
                    end
                end
                if picked then break end
            end
            if picked then
                plan.uses = plan.uses + 1
                if not plan.crate then plan.crate, plan.stack = it, picked end
            end
        end
    end
    return plan
end

function U.MacroBody(kind)
    local m = MACROS[kind]
    if m.tooltip then return ("#showtooltip %s\n/click %s"):format(m.tooltip, m.button) end
    return "/click " .. m.button
end

function U.ScanBags()
    local C = _G.C_Container
    local items = {}
    if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then return items end
    for _, bag in ipairs((ns.WritState.ContainerIDs(_G))) do
        for slot = 1, C.GetContainerNumSlots(bag) or 0 do
            local info = C.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                items[#items + 1] = { bag = bag, slot = slot, itemID = info.itemID, count = info.stackCount or 1 }
            end
        end
    end
    return items
end

local buttons = {}
local refused = { receipt = {}, fill = {} }
local BUSY_TIMEOUT = 3
local busyUntil = 0

local function Now()
    return _G.GetTime and _G.GetTime() or 0
end

local function Busy()
    if Now() < busyUntil then return true end
    local unitCasting, unitChannel = _G.UnitCastingInfo, _G.UnitChannelInfo
    return (unitCasting and unitCasting("player") ~= nil) or (unitChannel and unitChannel("player") ~= nil)
end

local function Disarm(b)
    b:SetAttribute("type", nil)
    b.aim = nil
end
local EMPTY = {
    receipt = "Nothing to do: you need a Forged Delivery Receipt and an empty Waylaid Crate in your bags.",
    fill = "Nothing to fill: no labeled Waylaid Crate with a stack big enough for one of its bundles.",
}

local function ItemName(itemID)
    local item = _G.C_Item
    local name = item and item.GetItemNameByID and item.GetItemNameByID(itemID)
    return type(name) == "string" and name ~= "" and name or ("item " .. itemID)
end

local function Arm(kind, b, items)
    if kind == "receipt" then
        local plan = U.ReceiptPlan(items, refused.receipt)
        local t = plan.target
        b:SetAttribute("type", t and "item" or nil)
        b:SetAttribute("item", t and ("item:" .. RECEIPT) or nil)
        b:SetAttribute("target-bag", t and t.bag or nil)
        b:SetAttribute("target-slot", t and t.slot or nil)
        b.aim = t
        return t
    end
    local plan = U.FillPlan(items, refused.fill)
    local c, st = plan.crate, plan.stack
    b:SetAttribute("type", c and "item" or nil)
    b:SetAttribute("item", c and ("%d %d"):format(c.bag, c.slot) or nil)
    b:SetAttribute("target-bag", st and st.bag or nil)
    b:SetAttribute("target-slot", st and st.slot or nil)
    b.aim, b.stackItem = c, st and st.itemID
    return c
end

local function Update()
    if InCombatLockdown() then return end
    local items = U.ScanBags()
    for kind, b in pairs(buttons) do Arm(kind, b, items) end
end

local function Build(kind)
    local b = CreateFrame("Button", MACROS[kind].button, UIParent, "SecureActionButtonTemplate")
    b:SetSize(1, 1)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("useOnKeyDown", false)
    b:SetScript("PreClick", function(self)
        if InCombatLockdown() then return end
        if Busy() then
            Disarm(self)
            return
        end
        local aim = Arm(kind, self, U.ScanBags())
        if aim then
            busyUntil = Now() + BUSY_TIMEOUT
        else
            ns.Print(EMPTY[kind])
        end
    end)
    b:SetScript("PostClick", function(self)
        local aim = self.aim
        if not (aim and _G.SpellIsTargeting and _G.SpellIsTargeting()) then return end
        if _G.SpellStopTargeting then _G.SpellStopTargeting() end
        busyUntil = 0
        refused[kind][aim.itemID] = true
        if kind == "receipt" then
            ns.Print(("A receipt could not go on %s: the game refused it as a target. Skipping that crate kind for this session.")
                :format(ItemName(aim.itemID)))
        else
            ns.Print(("%s could not be filled from %s: the game refused it. Skipping that crate kind for this session.")
                :format(ItemName(aim.itemID), ItemName(self.stackItem or 0)))
        end
        Update()
    end)
    b:Hide()
    return b
end

function U.Init()
    if buttons.receipt then return end
    UI.Defer("KLH_WritUseInit", function()
        buttons.receipt, buttons.fill = Build("receipt"), Build("fill")
        local events = CreateFrame("Frame")
        events:RegisterEvent("BAG_UPDATE_DELAYED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:RegisterEvent("UNIT_SPELLCAST_FAILED")
        events:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
        events:SetScript("OnEvent", function(_, event, unit)
            if event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
                if unit == "player" then busyUntil = 0 end
                return
            end
            if event == "BAG_UPDATE_DELAYED" then busyUntil = 0 end
            Update()
        end)
        Update()
    end)
end

local function AccountMax()
    local consts = _G.Constants and _G.Constants.MacroConsts
    return (consts and consts.MAX_ACCOUNT_MACROS) or _G.MAX_ACCOUNT_MACROS or ACCOUNT_MACROS
end

local function MacroIcon(m)
    local item = _G.C_Item
    local fromItem = m.iconItem and item and item.GetItemIconByID and item.GetItemIconByID(m.iconItem)
    return fromItem or m.icon or MACRO_ICON
end

local function EnsureMacro(kind)
    local m = MACROS[kind]
    local icon = MacroIcon(m)
    local body = U.MacroBody(kind)
    local max = AccountMax()
    local index = GetMacroIndexByName(m.name)
    while index and index > max do
        DeleteMacro(index)
        index = GetMacroIndexByName(m.name)
    end
    if index and index > 0 then
        EditMacro(index, m.name, icon, body)
        return index
    end
    if (GetNumMacros() or 0) >= max then return nil end
    return CreateMacro(m.name, icon, body, false)
end

local function OpenMacroWindow(select)
    if type(_G.ShowMacroFrame) ~= "function" then return end
    if ns.CloseOptions then ns.CloseOptions() end
    _G.ShowMacroFrame()
    local frame = _G.MacroFrame
    if not frame then return end
    if frame.ChangeTab then pcall(frame.ChangeTab, frame, 1) end
    if select and frame.SelectMacro then pcall(frame.SelectMacro, frame, select, true) end
end

--- Creates or updates both general macros and opens the macro window on the General tab.
function U.MakeMacros()
    if InCombatLockdown() then
        ns.Print("Macros cannot be made in combat.")
        return false
    end
    local made = {}
    for _, kind in ipairs({ "receipt", "fill" }) do
        local index = EnsureMacro(kind)
        if not index or index == 0 then
            ns.Print("Your general macros are full; delete one and try again.")
            return false
        end
        made[#made + 1] = MACROS[kind].name
    end
    ns.Print(("Macros \"%s\" and \"%s\" are in your general macros: drag them to an action bar."):format(made[1], made[2]))
    OpenMacroWindow(GetMacroIndexByName(MACROS.fill.name))
    return true
end
