local _, ns = ...

local UI = {}
ns.UI = UI

local ACCENT = { 0.05, 0.82, 0.62 }
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"

function UI.Accent()
    return ACCENT[1], ACCENT[2], ACCENT[3]
end

function UI.FormatNumber(n)
    local s = tostring(math.floor(n + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

function UI.FormatMoney(copper)
    copper = math.floor((copper or 0) + 0.5)
    if copper >= 10000 then
        local silver = math.floor((copper + 50) / 100)
        return ("%sg %02ds"):format(UI.FormatNumber(math.floor(silver / 100)), silver % 100)
    end
    local s, c = math.floor(copper / 100), copper % 100
    if s > 0 then return ("%ds %02dc"):format(s, c) end
    return ("%dc"):format(c)
end

function UI.FontPath()
    return _G.STANDARD_TEXT_FONT or FALLBACK_FONT
end

local ARROW_ATLASES = { "common-dropdown-a-button", "common-dropdown-classic-a-buttonDown" }
local EUI_ARROW = "Azerite-PointingArrow"
local ARROW_FILE = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up"

function UI.SetArrowTexture(tex)
    local atlasInfo = _G.C_Texture and _G.C_Texture.GetAtlasInfo
    if atlasInfo and tex.SetAtlas then
        if UI.Skinned and UI.Skinned() and atlasInfo(EUI_ARROW) then
            tex:SetAtlas(EUI_ARROW)
            return EUI_ARROW
        end
        for _, name in ipairs(ARROW_ATLASES) do
            if atlasInfo(name) then
                tex:SetAtlas(name)
                return name
            end
        end
    end
    tex:SetTexture(ARROW_FILE)
    return ARROW_FILE
end

local FONT_OBJECTS = {
    { 11, "GameFontHighlightSmall" }, { 13, "GameFontHighlight" }, { 15, "GameFontHighlightMedium" }, { 99, "GameFontHighlightLarge" },
}

function UI.FontObject(size)
    for _, f in ipairs(FONT_OBJECTS) do
        if (size or 12) <= f[1] and type(_G[f[2]]) == "table" then return _G[f[2]] end
    end
end

function UI.Font(parent, size, r, g, b, a)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local obj = UI.FontObject(size)
    if obj then fs:SetFontObject(obj) else fs:SetFont(UI.FontPath(), size, "") end
    fs:SetTextColor(r or 1, g or 1, b or 1, a or 1)
    return fs
end

function UI.Solid(parent, layer, r, g, b, a)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetColorTexture(r, g, b, a or 1)
    return tex
end

function UI.Border(frame, r, g, b, a)
    local edges = {}
    local function Edge(p1, p2, w, h)
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetPoint(p1)
        t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        edges[#edges + 1] = t
    end
    Edge("TOPLEFT", "TOPRIGHT", nil, 1)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    Edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    Edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
    local border = {}
    function border.SetColor(_, cr, cg, cb, ca)
        for _, t in ipairs(edges) do t:SetColorTexture(cr, cg, cb, ca or 1) end
    end
    border:SetColor(r, g, b, a)
    return border
end

local scaledFrom

local function RestoreTooltipScale()
    if scaledFrom then
        GameTooltip:SetScale(scaledFrom)
        scaledFrom = nil
    end
end

local restoreHooked

function UI.ShowItemTooltip(owner, itemID, extra)
    RestoreTooltipScale()
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(itemID)
    if extra then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(extra, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

--- anchor: a GameTooltip anchor such as "ANCHOR_TOP"; default "ANCHOR_RIGHT".
function UI.ShowTooltip(owner, text, anchor)
    RestoreTooltipScale()
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

--- lines: { { left, right?, label?, header?, gold?, grey?, warn? }, ... }; shrinks the tooltip when taller than the screen.
--- below: true opens it under owner with left edges aligned instead of to its right.
function UI.ShowLinesTooltip(owner, lines, below)
    RestoreTooltipScale()
    if below then
        GameTooltip:SetOwner(owner, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
    else
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    end
    for _, l in ipairs(lines) do
        if l.right and l.label then
            GameTooltip:AddDoubleLine(l.left, l.right, 0.62, 0.62, 0.62, 1, 1, 1)
        elseif l.right then
            GameTooltip:AddDoubleLine(l.left, l.right, 1, 1, 1, 1, 1, 1)
        elseif l.warn then
            GameTooltip:AddLine(l.left, 1, 0.53, 0, true)
        elseif l.grey then
            GameTooltip:AddLine(l.left, 0.62, 0.62, 0.62, true)
        elseif l.header then
            local r, g, b = UI.Accent()
            GameTooltip:AddLine(l.left, r, g, b)
        elseif l.gold then
            GameTooltip:AddLine(l.left, 1, 0.82, 0)
        else
            GameTooltip:AddLine(l.left, 1, 1, 1, true)
        end
    end
    GameTooltip:Show()
    local screen = UIParent and UIParent:GetHeight()
    local h = GameTooltip:GetHeight()
    if type(screen) == "number" and type(h) == "number" and h > screen * 0.95 then
        if not restoreHooked then
            GameTooltip:HookScript("OnHide", RestoreTooltipScale)
            restoreHooked = true
        end
        scaledFrom = scaledFrom or GameTooltip:GetScale()
        GameTooltip:SetScale(scaledFrom * screen * 0.95 / h)
    end
end

function UI.HideTooltip()
    GameTooltip:Hide()
    RestoreTooltipScale()
end

local fallbackMenu
local MENU_ROW_H = 20
local MENU_MAX_ROWS = 20
local MENU_TEXT_PAD = 8
local menuClosedHandlers = {}

local function InCombat()
    return _G.InCombatLockdown and _G.InCombatLockdown() and true or false
end

local function OnMenuShow(self)
    self:RegisterEvent("GLOBAL_MOUSE_DOWN")
    if not InCombat() then
        self:EnableKeyboard(true)
        self:SetPropagateKeyboardInput(true)
    end
end

local function OnMenuHide(self)
    self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
    if not InCombat() then self:EnableKeyboard(false) end
    self.owner = nil
    for _, fn in ipairs(menuClosedHandlers) do fn() end
end

local function OnMenuKey(self, key)
    if InCombat() then return end
    if key == "ESCAPE" then
        self:SetPropagateKeyboardInput(false)
        self:Hide()
    else
        self:SetPropagateKeyboardInput(true)
    end
end

local function OnMenuMouseDown(self)
    local owner = self.owner
    if self:IsMouseOver() or (owner and owner.IsMouseOver and owner:IsMouseOver()) then return end
    self:Hide()
end

local function FillMenu(menu)
    for i = 1, menu.rows do
        local item = menu.items[menu.offset + i]
        local button = menu.buttons[i]
        button.item = item
        button.text:SetWidth(math.max(1, menu.textWidth))
        button.text:SetText(item.text)
        button.right:SetText(item.right or "")
        if item.isActive then button.text:SetTextColor(UI.Accent()) else button.text:SetTextColor(1, 1, 1) end
        button:EnableMouse(not item.title)
        button:Show()
    end
    for i = menu.rows + 1, #menu.buttons do menu.buttons[i]:Hide() end
end

local function OnMenuClick(button)
    local item = button.item
    if not item or item.title then return end
    fallbackMenu:Hide()
    if item.onClick then item.onClick() end
end

local function OnMenuWheel(menu, delta)
    local offset = math.max(0, math.min(#menu.items - menu.rows, menu.offset - delta))
    if offset == menu.offset then return end
    menu.offset = offset
    FillMenu(menu)
end

local function OpenFallbackMenu(owner, items, exactWidth)
    if not fallbackMenu then
        fallbackMenu = CreateFrame("Frame", nil, UIParent)
        fallbackMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        fallbackMenu:EnableMouse(true)
        fallbackMenu:EnableMouseWheel(true)
        fallbackMenu:Hide()
        fallbackMenu:SetClampedToScreen(true)
        UI.Solid(fallbackMenu, "BACKGROUND", 0.077, 0.068, 0.058, 1):SetAllPoints()
        fallbackMenu.border = UI.Border(fallbackMenu, 1, 1, 1, 0.25)
        if UI.SkinPanel then UI.SkinPanel(fallbackMenu) end
        fallbackMenu.buttons = {}
        fallbackMenu:SetScript("OnShow", OnMenuShow)
        fallbackMenu:SetScript("OnHide", OnMenuHide)
        fallbackMenu:SetScript("OnEvent", OnMenuMouseDown)
        fallbackMenu:SetScript("OnKeyDown", OnMenuKey)
        fallbackMenu:SetScript("OnMouseWheel", OnMenuWheel)
    end
    local menu = fallbackMenu
    local width = exactWidth and owner:GetWidth() or math.max(owner:GetWidth(), 120)
    menu.items, menu.offset, menu.rows, menu.textWidth = items, 0, math.min(#items, MENU_MAX_ROWS), width - MENU_TEXT_PAD * 2
    for i = 1, menu.rows do
        local button = menu.buttons[i]
        if not button then
            button = CreateFrame("Button", nil, menu)
            button:SetHeight(MENU_ROW_H)
            UI.Solid(button, "HIGHLIGHT", 1, 1, 1, 0.08):SetAllPoints()
            button.text = UI.Font(button, 12, 1, 1, 1)
            button.text:SetPoint("LEFT", button, "LEFT", MENU_TEXT_PAD, 0)
            button.text:SetJustifyH("LEFT")
            button.text:SetWordWrap(false)
            button.right = UI.Font(button, 12, 1, 1, 1)
            button.right:SetPoint("RIGHT", button, "RIGHT", -MENU_TEXT_PAD, 0)
            button.right:SetJustifyH("RIGHT")
            button:SetScript("OnClick", OnMenuClick)
            menu.buttons[i] = button
        end
        button:SetWidth(width)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -(i - 1) * MENU_ROW_H - 1)
    end
    FillMenu(menu)
    menu:SetSize(width, menu.rows * MENU_ROW_H + 2)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    menu.owner = owner
    menu:Show()
end

function UI.CloseMenus()
    if fallbackMenu then fallbackMenu:Hide() end
end

function UI.IsMenuOpen(owner)
    if not (fallbackMenu and fallbackMenu:IsShown()) then return false end
    return owner == nil or fallbackMenu.owner == owner
end

--- Runs fn each time a fallback menu closes.
function UI.OnMenuClosed(fn)
    menuClosedHandlers[#menuClosedHandlers + 1] = fn
end

--- Toggles a menu below anchor, as wide as anchor and left-aligned; items: { { text, right?, onClick } }.
function UI.DropdownMenu(anchor, items)
    if UI.IsMenuOpen(anchor) or #items == 0 then
        UI.CloseMenus()
        return
    end
    OpenFallbackMenu(anchor, items, true)
end

--- items: { { text, isActive?, onClick }, ... }
function UI.ContextMenu(owner, items)
    if _G.MenuUtil and _G.MenuUtil.CreateContextMenu then
        _G.MenuUtil.CreateContextMenu(owner, function(_, root)
            for _, item in ipairs(items) do
                if item.title then
                    root:CreateTitle(item.text)
                elseif item.isActive ~= nil then
                    root:CreateRadio(item.text, function() return item.isActive == true end, function()
                        if item.onClick then item.onClick() end
                    end)
                else
                    root:CreateButton(item.text, function()
                        if item.onClick then item.onClick() end
                    end)
                end
            end
        end)
        return
    end
    OpenFallbackMenu(owner, items)
end

local pending, pendingOrder, watcher = {}, {}, nil

local function Flush()
    local order = pendingOrder
    local jobs = pending
    pending, pendingOrder = {}, {}
    for _, key in ipairs(order) do
        local fn = jobs[key]
        if fn then
            jobs[key] = nil
            xpcall(fn, _G.geterrorhandler())
        end
    end
end

--- Runs fn now out of combat, else once after combat ends; the latest call per key wins.
function UI.Defer(key, fn)
    if not (_G.InCombatLockdown and _G.InCombatLockdown()) then
        pending[key] = nil
        fn()
        return
    end
    if pending[key] == nil then pendingOrder[#pendingOrder + 1] = key end
    pending[key] = fn
    if not watcher then
        watcher = CreateFrame("Frame")
        watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        watcher:SetScript("OnEvent", Flush)
    end
end
