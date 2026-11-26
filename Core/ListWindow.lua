local _, ns = ...
local UI = ns.UI

local PAD = 8
local HEADER_H = 25
local ROW_GAP = 4
local HEADER_GAP = 8
local INDENT = 10
local ROW_PAD = 2
local BUTTON_H = 22
local MAX_HEIGHT_FRACTION = 0.6
local MIN_VIEW_H = 40
local WHEEL_STEP = 40
local ICON_SIZE = 12
local ICON_GAP = 3
local EXTRA_GAP = 8

local function PaintButton(b, hover)
    local r, g, bl = UI.Accent()
    if b.IsEnabled and not b:IsEnabled() then
        b.label:SetAlpha(0.3)
        b.border:SetColor(1, 1, 1, 0.1)
        return
    end
    b.label:SetAlpha((hover or b.selected) and 1 or 0.7)
    if b.selected then b.bg:SetColorTexture(r, g, bl, 0.35) else b.bg:SetColorTexture(0, 0, 0, 0.5) end
    if hover or b.selected then b.border:SetColor(r, g, bl, 0.6) else b.border:SetColor(1, 1, 1, 0.25) end
end

--- A small house-styled button; b:SetSelected(on) keeps the accent border.
function ns.CreateWindowButton(parent, width, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, BUTTON_H)
    if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
    local bg = UI.Solid(b, "BACKGROUND", 0, 0, 0, 0.5)
    bg:SetAllPoints()
    b.bg = bg
    b.border = UI.Border(b, 1, 1, 1, 0.25)
    b.label = UI.Font(b, 12, 1, 1, 1)
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    b.SetSelected = function(self, on)
        self.selected = on and true or nil
        PaintButton(self, false)
    end
    b.SetActive = function(self, on)
        self:SetEnabled(on)
        PaintButton(self, false)
    end
    b:SetScript("OnEnter", function(self) PaintButton(self, true) end)
    b:SetScript("OnLeave", function(self) PaintButton(self, false) end)
    b:SetScript("OnClick", onClick)
    PaintButton(b, false)
    return b
end

--- rowHeights: heights of the rows; chrome: all fixed height around them. Returns window height, needsScroll.
function ns.ListWindowLayout(rowHeights, chrome, maxHeight)
    local content = 0
    for _, h in ipairs(rowHeights) do content = content + h + ROW_GAP end
    local height = chrome + content
    if type(maxHeight) ~= "number" or maxHeight <= 0 or height <= maxHeight then return height, false end
    return math.max(maxHeight, chrome + MIN_VIEW_H), true
end

local function MaxHeight()
    local parent = _G.UIParent
    local h = parent and parent.GetHeight and parent:GetHeight()
    if type(h) ~= "number" or h <= 0 then return nil end
    return math.floor(h * MAX_HEIGHT_FRACTION)
end

local function OnWheel(scroll, delta)
    local range = scroll:GetVerticalScrollRange() or 0
    local v = (scroll:GetVerticalScroll() or 0) - delta * WHEEL_STEP
    scroll:SetVerticalScroll(math.max(0, math.min(range, v)))
end

local Window = {}
Window.__index = Window

local function SavePosition(window)
    window.frame:StopMovingOrSizing()
    local point, _, relPoint, x, y = window.frame:GetPoint(1)
    ns.GetSettings(window.key).windowPoint = { point, relPoint, x, y }
end

local function OnRowClick(row)
    local window = row.window
    if IsControlKeyDown() then
        if window.onCtrlClick then window.onCtrlClick(row.data) end
    elseif window.onClick then
        window.onClick(row.data)
    end
end

function Window:Build()
    local f = CreateFrame("Frame", self.name, UIParent)
    f:SetWidth(self.width)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    local p = ns.GetSettings(self.key).windowPoint
    if type(p) == "table" and p[1] then
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -80, -260)
    end
    UI.Solid(f, "BACKGROUND", 0.077, 0.068, 0.058, 1):SetAllPoints()
    UI.Border(f, 1, 1, 1, 0.15)
    UI.SkinWindow(f)

    local header = CreateFrame("Button", nil, f)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_H)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function() SavePosition(self) end)
    local label = UI.Font(header, 12, 1, 0.82, 0)
    label:SetPoint("LEFT", header, "LEFT", PAD, 0)
    label:SetText(self.title)

    local anchor, anchorPoint, gap = header, "RIGHT", -2
    for k = #self.buttons, 1, -1 do
        local spec = self.buttons[k]
        local button
        if spec.close then
            button = CreateFrame("Button", nil, header, "UIPanelCloseButtonNoScripts")
            button:SetSize(HEADER_H - 1, HEADER_H - 1)
            UI.SkinCloseButton(button)
        else
            button = CreateFrame("Button", nil, header)
            local text = UI.Font(button, 11, 1, 1, 1, 0.6)
            text:SetPoint("CENTER")
            text:SetText(spec.text)
            button:SetSize(math.ceil(text:GetStringWidth()) + PAD * 2, HEADER_H)
            button:SetScript("OnEnter", function() text:SetAlpha(1) end)
            button:SetScript("OnLeave", function() text:SetAlpha(0.6) end)
        end
        button:SetPoint("RIGHT", anchor, anchorPoint, gap, 0)
        button:SetScript("OnClick", function() spec.onClick() end)
        anchor, anchorPoint, gap = button, "LEFT", 0
    end
    self.headerAnchor, self.headerAnchorPoint, self.header = anchor, anchorPoint, header
    self.topH = self.top and self.top(f, self.width - PAD * 2, -(HEADER_H + ROW_GAP)) or 0
    if self.actions then
        local n = #self.actions
        local w = (self.width - PAD * 2 - (n - 1) * ROW_GAP) / n
        self.buttonFrames = {}
        for i, spec in ipairs(self.actions) do
            local b = ns.CreateWindowButton(f, w, spec.text, spec.onClick)
            UI.SkinButton(b)
            b:HookScript("OnEnter", function(btn) if btn.tip then UI.ShowTooltip(btn, btn.tip, "ANCHOR_TOP") end end)
            b:HookScript("OnLeave", function() UI.HideTooltip() end)
            self.buttonFrames[i] = b
        end
    end
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetWidth(self.width - PAD * 2)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", OnWheel)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(self.width - PAD * 2)
    content:SetHeight(1)
    scroll:SetScrollChild(content)
    self.scroll, self.content = scroll, content
    f:Hide()
    self.frame = f
end

function Window:Block(key, parent, size, r, g, b)
    local block = self[key]
    if block then return block end
    local textW = self.width - PAD * 2
    block = CreateFrame("Frame", nil, parent)
    block:SetWidth(textW)
    block:EnableMouse(true)
    block.text = UI.Font(block, size, r, g, b)
    block.text:SetPoint("TOPLEFT")
    block.text:SetWidth(textW)
    block.text:SetJustifyH("LEFT")
    block.text:SetWordWrap(true)
    block.text:SetSpacing(2)
    block:SetScript("OnEnter", function(fr) if fr.tooltip then UI.ShowTooltip(fr, fr.tooltip) end end)
    block:SetScript("OnLeave", function() UI.HideTooltip() end)
    self[key] = block
    return block
end

function Window:Separator(key, parent)
    local line = self[key]
    if line then return line end
    line = UI.Solid(parent, "ARTWORK", 1, 1, 1, 0.15)
    line:SetHeight(1)
    line:SetWidth(self.width - PAD * 2)
    self[key] = line
    return line
end

local function FillBlock(block, spec)
    block.text:SetText(spec.text or "")
    block.tooltip = spec.tooltip
    local h = block.text:GetStringHeight() + 4
    block:SetHeight(h)
    block:Show()
    return h
end

function Window:NewRow(parent)
    local textW = self.width - PAD * 2
    local row = CreateFrame("Button", nil, parent)
    row:SetWidth(textW)
    row:RegisterForClicks("LeftButtonUp")
    row.hl = UI.Solid(row, "HIGHLIGHT", 1, 1, 1, 0.06)
    row.hl:SetAllPoints()
    row.sel = UI.Solid(row, "BACKGROUND", 1, 1, 1, 0.12)
    row.sel:SetPoint("TOPLEFT", row, "TOPLEFT", -PAD + 2, 2)
    row.sel:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", PAD - 2, -2)
    row.sel:Hide()
    row.text = UI.Font(row, 12, 1, 1, 1)
    if _G.ChatFontNormal then row.text:SetFontObject(_G.ChatFontNormal) end
    row.text:SetJustifyH("LEFT")
    row.text:SetSpacing(2)
    row.right = UI.Font(row, 12, 1, 1, 1)
    if _G.PriceFont then row.right:SetFontObject(_G.PriceFont) end
    row.right:SetTextColor(1, 1, 1)
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -ROW_PAD)
    row.right:SetJustifyH("RIGHT")
    row.right:SetWordWrap(false)
    row.extra = UI.Font(row, 12, 0.62, 0.62, 0.62)
    if _G.PriceFont then row.extra:SetFontObject(_G.PriceFont) end
    row.extra:SetTextColor(0.62, 0.62, 0.62)
    row.extra:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -ROW_PAD)
    row.extra:SetJustifyH("RIGHT")
    row.extra:SetWordWrap(false)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("RIGHT", row.right, "LEFT", -ICON_GAP, 0)
    row.icon:Hide()
    row.window = self
    row:SetScript("OnClick", OnRowClick)
    row:SetScript("OnEnter", function(r)
        if r.tooltipLines then
            UI.ShowLinesTooltip(r, r.tooltipLines)
            return
        end
        if r.itemID and UI.ShowItemTooltip then
            UI.ShowItemTooltip(r, r.itemID, r.tooltip)
            return
        end
        local tip = r.tooltip or self.hint
        if tip then UI.ShowTooltip(r, tip) end
    end)
    row:SetScript("OnLeave", function() UI.HideTooltip() end)
    return row
end

function Window:Row(i)
    if not self.rows[i] then self.rows[i] = self:NewRow(self.content) end
    return self.rows[i]
end

function Window:PinRow(i)
    self.pinRows = self.pinRows or {}
    if not self.pinRows[i] then self.pinRows[i] = self:NewRow(self.frame) end
    return self.pinRows[i]
end

local function PlaceRight(row, extraCol)
    local shift = extraCol > 0 and extraCol + EXTRA_GAP or 0
    row.right:ClearAllPoints()
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -shift, -ROW_PAD)
    if not row.hasRight then return 0 end
    return (row.moneyW or 0) + shift + PAD
end

local function Measure(region)
    return region and math.ceil(region:GetStringWidth() or 0) or 0
end

local function FillRow(row, entry, textW)
    row.data = entry.data
    row.tooltip = entry.tooltip
    row.tooltipLines = entry.tooltipLines
    row.itemID = entry.itemID
    if entry.selected then
        local r, g, b = UI.Accent()
        row.sel:SetColorTexture(r, g, b, 0.18)
        row.sel:Show()
    else
        row.sel:Hide()
    end
    if entry.header then row.text:SetTextColor(UI.Accent()) else row.text:SetTextColor(1, 1, 1) end
    if entry.button and not row.box then
        row.box = UI.Solid(row, "BACKGROUND", 0, 0, 0, 0.5)
        row.box:SetAllPoints()
        row.boxBorder = UI.Border(row, 1, 1, 1, 0.25)
    end
    if row.box then
        row.box:SetShown(entry.button == true)
        row.boxBorder:SetColor(1, 1, 1, entry.button and 0.25 or 0)
    end
    row.text:ClearAllPoints()
    if entry.button then
        row.right:SetText("")
        if row.extra then row.extra:SetText("") end
        row.moneyW, row.extraW, row.rightW, row.hasIcon, row.hasRight = 0, 0, 0, false, false
        row.icon:Hide()
        row.text:SetPoint("CENTER")
        row.text:SetWidth(textW)
        row.text:SetJustifyH("CENTER")
        row.text:SetWordWrap(false)
        row.text:SetText(entry.text)
        return BUTTON_H
    end
    local indent = entry.indent and INDENT or 0
    row.right:SetText(entry.right or "")
    if row.extra then row.extra:SetText(entry.extra or "") end
    row.hasRight = entry.right ~= nil or entry.extra ~= nil
    row.moneyW, row.extraW = Measure(row.right), Measure(row.extra)
    local rightW = PlaceRight(row, row.extraW)
    local icon = entry.icon
    row.rightW, row.indent, row.textW, row.hasIcon = rightW, indent, textW, icon ~= nil
    if icon then
        row.icon:SetTexture(icon.file)
        row.icon:SetVertexColor(icon.r, icon.g, icon.b)
        row.icon:Show()
        rightW = rightW + ICON_SIZE + ICON_GAP
    else
        row.icon:Hide()
    end
    row.text:SetPoint("TOPLEFT", row, "TOPLEFT", indent, -ROW_PAD)
    row.text:SetWidth(textW - indent - rightW)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(not (entry.right or entry.extra))
    row.text:SetText(entry.text)
    return row.text:GetStringHeight() + ROW_PAD * 2
end

ns.ListWindowFillRow = FillRow

-- Widths are measured here, after every fill, since a font can report 0 while it is still loading.
local function AlignIcons(...)
    local rows = {}
    for i = 1, select("#", ...) do
        for _, row in ipairs((select(i, ...))) do rows[#rows + 1] = row end
    end
    local extraCol = 0
    for _, row in ipairs(rows) do
        if row.hasRight then
            row.moneyW, row.extraW = Measure(row.right), Measure(row.extra)
            if row.extraW > extraCol then extraCol = row.extraW end
        end
    end
    for _, row in ipairs(rows) do
        if row.hasRight then
            row.rightW = PlaceRight(row, extraCol)
            row.text:SetWidth(row.textW - row.indent - row.rightW)
        end
    end
    local widest = 0
    for _, row in ipairs(rows) do
        if row.hasIcon and row.rightW > widest then widest = row.rightW end
    end
    for _, row in ipairs(rows) do
        if row.hasIcon then
            row.icon:ClearAllPoints()
            row.icon:SetPoint("RIGHT", row.right, "LEFT", -(ICON_GAP + widest - row.rightW), 0)
            row.text:SetWidth(row.textW - row.indent - widest - ICON_SIZE - ICON_GAP)
        end
    end
end

ns.ListWindowAlignIcons = AlignIcons

function Window:SetEntries(entries, summary, pinned)
    if #entries == 0 and not summary and not pinned then
        self:Hide()
        return
    end
    if not self.frame then self:Build() end
    local scrollTop = HEADER_H + ROW_GAP + self.topH
    if summary then
        local block = self:Block("summaryBlock", self.frame, 12, 1, 1, 1)
        local h = FillBlock(block, summary)
        block:ClearAllPoints()
        block:SetPoint("TOPLEFT", self.frame, "TOPLEFT", PAD, -scrollTop)
        local line = self:Separator("summaryLine", self.frame)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", self.frame, "TOPLEFT", PAD, -(scrollTop + h + ROW_GAP))
        line:Show()
        scrollTop = scrollTop + h + ROW_GAP * 2 + 1
    else
        if self.summaryBlock then self.summaryBlock:Hide() end
        if self.topH > 0 then
            local line = self:Separator("summaryLine", self.frame)
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", self.frame, "TOPLEFT", PAD, -scrollTop)
            line:Show()
            scrollTop = scrollTop + ROW_GAP + 1
        elseif self.summaryLine then
            self.summaryLine:Hide()
        end
    end
    local textW = self.width - PAD * 2
    local pins = pinned or {}
    local pinRows, listRows = {}, {}
    for i, entry in ipairs(pins) do
        local row = self:PinRow(i)
        pinRows[i] = row
        local h = FillRow(row, entry, textW)
        row:SetHeight(h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", PAD, -scrollTop)
        row:Show()
        scrollTop = scrollTop + h + ROW_GAP
    end
    for i = #pins + 1, #(self.pinRows or {}) do self.pinRows[i]:Hide() end
    if #pins > 0 then
        local line = self:Separator("pinLine", self.frame)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", self.frame, "TOPLEFT", PAD, -scrollTop)
        line:Show()
        scrollTop = scrollTop + ROW_GAP + 1
    elseif self.pinLine then
        self.pinLine:Hide()
    end
    local heights, y = {}, 0
    for i, entry in ipairs(entries) do
        local row = self:Row(i)
        if entry.header and i > 1 then
            heights[#heights + 1] = HEADER_GAP - ROW_GAP
            y = y - HEADER_GAP
        end
        listRows[i] = row
        local h = FillRow(row, entry, textW)
        row:SetHeight(h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, y)
        row:Show()
        heights[#heights + 1] = h
        y = y - h - ROW_GAP
    end
    for i = #entries + 1, #self.rows do self.rows[i]:Hide() end
    AlignIcons(pinRows, listRows)
    local actionsH = self.buttonFrames and (BUTTON_H + ROW_GAP) or 0
    local chrome = scrollTop + actionsH + PAD - ROW_GAP
    local height, needsScroll = ns.ListWindowLayout(heights, chrome, self.fixedH or MaxHeight())
    if self.fixedH and height < self.fixedH then height = self.fixedH end
    local viewH = height - chrome
    self.content:SetHeight(math.max(1, -y))
    self.scroll:ClearAllPoints()
    self.scroll:SetPoint("TOPLEFT", self.frame, "TOPLEFT", PAD, -scrollTop)
    self.scroll:SetHeight(math.max(1, viewH))
    if not needsScroll then self.scroll:SetVerticalScroll(0) end
    if self.buttonFrames then
        local by = -(scrollTop + viewH)
        for i, b in ipairs(self.buttonFrames) do
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", PAD + (i - 1) * (b:GetWidth() + ROW_GAP), by)
        end
    end
    self.frame:SetHeight(height)
    self.frame:Show()
end

function Window:SetFixedHeight(h)
    self.fixedH = (type(h) == "number" and h > 0) and h or nil
end

function Window:SetActionState(i, on, tip)
    local b = self.buttonFrames and self.buttonFrames[i]
    if not b then return end
    b:SetActive(on and true or false)
    b.tip = (not on) and tip or nil
end

--- info: { text, lines?, warn? } shown by an info icon in the header on hover; nil hides it.
function Window:SetInfo(info)
    if not self.frame then self:Build() end
    local icon = self.infoIcon
    if not icon then
        icon = CreateFrame("Button", nil, self.header)
        icon:SetSize(16, 16)
        icon:SetPoint("RIGHT", self.headerAnchor, self.headerAnchorPoint, -4, 0)
        icon.tex = icon:CreateTexture(nil, "ARTWORK")
        icon.tex:SetTexture("Interface\\FriendsFrame\\InformationIcon")
        icon.tex:SetAllPoints()
        icon:SetScript("OnEnter", function(b)
            if b.lines then UI.ShowLinesTooltip(b, b.lines) elseif b.text then UI.ShowTooltip(b, b.text) end
        end)
        icon:SetScript("OnLeave", function() UI.HideTooltip() end)
        self.infoIcon = icon
    end
    if not info then
        icon:Hide()
        return
    end
    icon.text, icon.lines = info.text, info.lines
    if info.warn then icon.tex:SetVertexColor(1, 0.53, 0) else icon.tex:SetVertexColor(1, 1, 1) end
    icon:Show()
end

function Window:Hide()
    if self.frame then self.frame:Hide() end
end

function Window:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end

--- opts: name, title, key, width?, hint?, onClick?(data), onCtrlClick?(data), buttons?, top?(frame, width, y) -> height, actions?
function ns.CreateListWindow(opts)
    return setmetatable({
        name = opts.name, title = opts.title, key = opts.key, width = opts.width or 250, hint = opts.hint,
        onClick = opts.onClick, onCtrlClick = opts.onCtrlClick, buttons = opts.buttons or {}, rows = {},
        top = opts.top, actions = opts.actions,
    }, Window)
end
