local _, ns = ...
local UI = ns.UI

local FRAME_NAME = "KLHOptionsWindow"
local WIDTH, HEIGHT = 900, 600
local TITLE_H = 30
local SIDEBAR_W = 190
local PAD = 16
local COLUMNS = 3
local COL_GAP = 16
local ROW_GAP = 10
local PAGE_TITLE_H = 28
local ENTRY_H = 22
local ENTRY_GAP = 2
local HEADING_GAP = 10
local INDENT = 14
local WHEEL_STEP = 40
local SCROLL_INSET = 6

local WIDGET = { toggle = "Checkbox", select = "Dropdown", range = "Slider", execute = "Button",
    input = "Input", header = "Header", description = "Text" }

local Win = { entries = {}, placed = {}, renders = 0 }
ns.OptionsWindow = Win

local pool = {}
local lastPage, dragging, pendingRebuild, timerQueued

function ns.OptionsGrid(spans, columns)
    local cells, row, col = {}, 1, 1
    for i, span in ipairs(spans) do
        span = math.max(1, math.min(span, columns))
        if col + span - 1 > columns then
            row, col = row + 1, 1
        end
        cells[i] = { row = row, col = col, span = span }
        col = col + span
    end
    return cells
end

local function Shown()
    return Win.frame ~= nil and Win.frame:IsShown()
end

local Render

local function Busy()
    if dragging or UI.IsMenuOpen() then return true end
    for _, p in ipairs(Win.placed) do
        if p.widget:HasFocus() then return true end
    end
    return false
end

local function Flush()
    timerQueued = nil
    if not pendingRebuild or Busy() then return end
    pendingRebuild = nil
    if Shown() then Render(Win.pageId, true) end
end

local function ScheduleRebuild()
    pendingRebuild = true
    if timerQueued or Busy() then return end
    timerQueued = true
    if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0, Flush) else Flush() end
end

local function Resume()
    if pendingRebuild then ScheduleRebuild() end
end

local function RefreshInPlace()
    for _, p in ipairs(Win.placed) do
        if not p.widget:HasFocus() then p.widget:Refresh() end
        p.widget:SetEnabled(not p.control.disabled())
    end
end

local function Changed()
    if not Shown() then return end
    RefreshInPlace()
    ScheduleRebuild()
end

function ns.NotifyOptionsChanged()
    Changed()
end

local function PoolKey(control)
    local name = WIDGET[control.kind]
    if name == "Text" then return name .. ":" .. tostring(control.fontSize) end
    if name == "Header" and control.desc then return name .. ":desc" end
    return name
end

local function Opts(control)
    local opts = setmetatable({}, { __index = control })
    if control.set then opts.set = function(value) control.set(value); Changed() end end
    if control.run then opts.run = function() control.run(); Changed() end end
    return opts
end

local function Acquire(control)
    local key = PoolKey(control)
    local free = pool[key]
    local widget = free and table.remove(free)
    local opts = Opts(control)
    if widget then
        widget.opts = opts
        widget.frame:Show()
        return widget
    end
    widget = ns.Widgets[WIDGET[control.kind]](Win.content, opts)
    widget.poolKey = key
    if widget.slider then
        widget.slider:HookScript("OnMouseDown", function() dragging = widget end)
        widget.slider:HookScript("OnMouseUp", function()
            dragging = nil
            Resume()
        end)
    end
    if widget.editBox then widget.editBox:HookScript("OnEditFocusLost", Resume) end
    return widget
end

local function ReleaseAll()
    UI.CloseMenus()
    for _, p in ipairs(Win.placed) do
        p.widget.frame:Hide()
        local key = p.widget.poolKey
        pool[key] = pool[key] or {}
        table.insert(pool[key], p.widget)
    end
    Win.placed = {}
end

local function CellWidth(span)
    local column = (Win.contentWidth - (COLUMNS - 1) * COL_GAP) / COLUMNS
    return math.floor(column * span + COL_GAP * (span - 1))
end

local function RenderPage(page, keepScroll)
    local offset = keepScroll and Win.scroll:GetVerticalScroll() or 0
    ReleaseAll()
    Win.title:SetText(page and page.title or "")
    Win.title:SetTextColor(UI.Accent())
    local visible = {}
    for _, control in ipairs(page and page.controls or {}) do
        if WIDGET[control.kind] and not control.hidden() then visible[#visible + 1] = control end
    end
    local spans = {}
    for i, control in ipairs(visible) do spans[i] = control.span end
    local rowHeights = {}
    for i, cell in ipairs(ns.OptionsGrid(spans, COLUMNS)) do
        local control = visible[i]
        local widget = Acquire(control)
        widget:SetWidth(CellWidth(cell.span))
        widget:Refresh()
        widget:SetEnabled(not control.disabled())
        rowHeights[cell.row] = math.max(rowHeights[cell.row] or 0, widget:Height())
        Win.placed[i] = { widget = widget, control = control, cell = cell }
    end
    local tops, y = {}, PAGE_TITLE_H
    for row, h in ipairs(rowHeights) do
        tops[row] = y
        y = y + h + ROW_GAP
    end
    for _, p in ipairs(Win.placed) do
        local frame, cell = p.widget.frame, p.cell
        local x = (CellWidth(1) + COL_GAP) * (cell.col - 1)
        local top = tops[cell.row]
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", Win.content, "TOPLEFT", x, -top)
    end
    Win.content:SetHeight(math.max(1, y))
    local range = math.max(0, y - (HEIGHT - TITLE_H - PAD))
    Win.scroll:SetVerticalScroll(math.max(0, math.min(offset, range)))
    Win.renders = Win.renders + 1
end

local function PaintEntry(b)
    local r, g, bl = UI.Accent()
    if b.entry.heading then
        b.label:SetTextColor(r, g, bl)
        b.bg:SetColorTexture(0, 0, 0, 0)
    elseif b.entry.id == Win.pageId then
        b.label:SetTextColor(1, 1, 1)
        b.bg:SetColorTexture(r, g, bl, 0.3)
    else
        b.label:SetTextColor(0.75, 0.75, 0.75)
        b.bg:SetColorTexture(0, 0, 0, 0)
    end
end

local entryButtons = {}

local function EntryButton(i)
    local b = entryButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, Win.sidebarContent)
    b:SetHeight(ENTRY_H)
    b.bg = UI.Solid(b, "BACKGROUND", 0, 0, 0, 0)
    b.bg:SetAllPoints()
    b.hover = UI.Solid(b, "HIGHLIGHT", 1, 1, 1, 0.05)
    b.hover:SetAllPoints()
    b.label = UI.Font(b, 12)
    b.label:SetJustifyH("LEFT")
    b.label:SetWordWrap(false)
    b:SetScript("OnClick", function(self)
        if self.entry.heading then return end
        Render(self.entry.id, false)
    end)
    entryButtons[i] = b
    return b
end

local function RenderSidebar(entries)
    local y = PAD / 2
    Win.entries = {}
    for i, entry in ipairs(entries) do
        local b = EntryButton(i)
        Win.entries[i] = b
        b.entry = entry
        if entry.heading and i > 1 then y = y + HEADING_GAP end
        local indent = entry.level > 1 and INDENT or 0
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", Win.sidebarContent, "TOPLEFT", 0, -y)
        b:SetPoint("TOPRIGHT", Win.sidebarContent, "TOPRIGHT", 0, -y)
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", b, "LEFT", PAD / 2 + indent, 0)
        b.label:SetPoint("RIGHT", b, "RIGHT", -PAD / 2, 0)
        b.label:SetText(entry.label)
        b.hover:SetShown(not entry.heading)
        PaintEntry(b)
        b:Show()
        y = y + ENTRY_H + ENTRY_GAP
    end
    for i = #entries + 1, #entryButtons do entryButtons[i]:Hide() end
    Win.sidebarContent:SetHeight(math.max(1, y + PAD / 2))
end

local function PickPage(entries, id)
    local first
    for _, entry in ipairs(entries) do
        if not entry.heading then
            if entry.id == id then return id end
            first = first or entry.id
        end
    end
    return first
end

Render = function(id, keepScroll)
    local root = ns.OptionsRoot()
    local entries = ns.OptionsModel.Entries(root)
    id = PickPage(entries, id)
    pendingRebuild = nil
    Win.pageId, lastPage = id, id
    RenderSidebar(entries)
    RenderPage(id and ns.OptionsModel.Page(root, id), keepScroll)
end

local function OnWheel(scroll, delta)
    UI.CloseMenus()
    local range = math.max(0, (scroll:GetScrollChild():GetHeight() or 0) - (scroll:GetHeight() or 0))
    local v = (scroll:GetVerticalScroll() or 0) - delta * WHEEL_STEP
    scroll:SetVerticalScroll(math.max(0, math.min(range, v)))
end

local function Build()
    local f = CreateFrame("Frame", FRAME_NAME, UIParent)
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    UI.Solid(f, "BACKGROUND", 0.077, 0.068, 0.058, 1):SetAllPoints()
    UI.Border(f, 1, 1, 1, 0.15)
    UI.SkinWindow(f)
    f:SetScript("OnHide", function()
        dragging = nil
        UI.CloseMenus()
    end)

    local header = CreateFrame("Button", nil, f)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(TITLE_H)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    local label = UI.Font(header, 13, 1, 0.82, 0)
    label:SetPoint("LEFT", header, "LEFT", PAD, 0)
    label:SetText(ns.LABEL)
    local close = CreateFrame("Button", nil, header, "UIPanelCloseButtonNoScripts")
    close:SetSize(TITLE_H - 4, TITLE_H - 4)
    close:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    close:SetScript("OnClick", function() f:Hide() end)
    UI.SkinCloseButton(close)

    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -TITLE_H)
    sidebar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    sidebar:SetWidth(SIDEBAR_W)
    UI.Solid(sidebar, "BACKGROUND", 0, 0, 0, 0.25):SetAllPoints()
    local edge = UI.Solid(sidebar, "ARTWORK", 1, 1, 1, 0.1)
    edge:SetPoint("TOPRIGHT")
    edge:SetPoint("BOTTOMRIGHT")
    edge:SetWidth(1)
    local sidebarScroll = CreateFrame("ScrollFrame", nil, sidebar)
    sidebarScroll:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, 0)
    sidebarScroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -1, 0)
    sidebarScroll:EnableMouseWheel(true)
    sidebarScroll:SetScript("OnMouseWheel", OnWheel)
    local sidebarContent = CreateFrame("Frame", nil, sidebarScroll)
    sidebarContent:SetWidth(SIDEBAR_W - 1)
    sidebarContent:SetHeight(1)
    sidebarScroll:SetScrollChild(sidebarContent)

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", SIDEBAR_W + PAD, -(TITLE_H + PAD / 2))
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD / 2)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", OnWheel)
    local contentWidth = WIDTH - SIDEBAR_W - PAD * 2 - SCROLL_INSET
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(contentWidth)
    content:SetHeight(1)
    scroll:SetScrollChild(content)
    local title = UI.Font(content, 16)
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

    Win.frame, Win.sidebar, Win.scroll, Win.content, Win.title = f, sidebar, scroll, content, title
    Win.sidebarScroll, Win.sidebarContent = sidebarScroll, sidebarContent
    Win.contentWidth = contentWidth
    if type(_G.UISpecialFrames) == "table" then table.insert(_G.UISpecialFrames, FRAME_NAME) end
    UI.OnMenuClosed(Resume)
    f:Hide()
end

function ns.OpenOptions(pageId)
    if not ns.OptionsRoot then return end
    if not Win.frame then Build() end
    Win.frame:Show()
    Render(type(pageId) == "string" and pageId or lastPage, false)
    if Win.frame.Raise then Win.frame:Raise() end
end

function ns.CloseOptions()
    if Win.frame then Win.frame:Hide() end
    local panel = _G.SettingsPanel
    if panel and panel:IsShown() then
        if panel.Close then panel:Close(true) elseif _G.HideUIPanel then _G.HideUIPanel(panel) else panel:Hide() end
    end
end
