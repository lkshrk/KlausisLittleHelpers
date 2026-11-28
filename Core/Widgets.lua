local _, ns = ...
local UI = ns.UI

local W = {}
ns.Widgets = W

local CONFIRM_POPUP = "KLH_OPTIONS_CONFIRM"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_WIDTH = 200
local ROW_H = 24
local LABEL_H = 18
local CELL_H = LABEL_H + ROW_H
local HEADER_H = 26
local TEXT_PAD = 4
local BOX = 26
local BOX_INSET = 4
local CHECK_INSET = 8
local GAP = 6
local VALUE_W = 48
local OK_W = 36
local LABEL_SIZE = 12
local GREY = 0.5
local FONT_SIZES = { small = 11, medium = 13, large = 16 }

local function Resolve(v)
    if type(v) == "function" then return v() end
    return v
end

local function Label(opts)
    local label = Resolve(opts.label)
    if label == nil then return "" end
    return tostring(label)
end

local function ConfirmText(opts, pending)
    if type(opts.confirmText) == "function" then return opts.confirmText(pending) end
    local confirm = opts.confirm
    if type(confirm) == "function" then confirm = confirm(pending) end
    if type(confirm) == "string" then return confirm end
    if confirm then return Label(opts) end
end

local function RegisterConfirmPopup()
    local dialogs = _G.StaticPopupDialogs
    if not dialogs or dialogs[CONFIRM_POPUP] then return end
    dialogs[CONFIRM_POPUP] = {
        text = "%s",
        button1 = _G.YES or "Yes",
        button2 = _G.NO or "No",
        OnAccept = function(_, data) if data then data.accept() end end,
        OnCancel = function(_, data) if data and data.cancel then data.cancel() end end,
        -- A click raises the toplevel DIALOG options window over a DIALOG popup.
        OnShow = function(dialog) dialog:SetFrameStrata("FULLSCREEN_DIALOG") end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

local function Confirm(text, accept, cancel)
    if not text then
        accept()
        return
    end
    RegisterConfirmPopup()
    if _G.StaticPopup_Show then _G.StaticPopup_Show(CONFIRM_POPUP, text, nil, { accept = accept, cancel = cancel }) end
end

local Widget = {}
Widget.__index = Widget

local function New(opts, frame, height)
    return setmetatable({ opts = opts or {}, frame = frame, height = height, enabled = true }, Widget)
end

function Widget:SetWidth(width)
    self.width = width
    self.frame:SetWidth(width)
    if self.Layout then self:Layout(width) end
end

function Widget:Height()
    return self.height
end

function Widget:SetEnabled(on)
    self.enabled = on and true or false
    if self.Paint then self:Paint() end
end

function Widget:Refresh() end

function Widget:HasFocus()
    return self.editBox ~= nil and self.editBox:HasFocus() and true or false
end

function Widget:Commit(value, opts)
    opts = opts or self.opts
    Confirm(ConfirmText(opts, value), function()
        if opts.set then opts.set(value) end
        self:Refresh()
    end, function() self:Refresh() end)
end

local function ShowTip(owner, widget)
    local lines = { { left = Label(widget.opts), header = true } }
    local desc = Resolve(widget.opts.desc)
    if type(desc) == "string" and desc ~= "" then lines[2] = { left = desc } end
    UI.ShowLinesTooltip(owner, lines)
end

local function AddTooltip(widget, ...)
    for i = 1, select("#", ...) do
        local region = select(i, ...)
        region:HookScript("OnEnter", function(self) ShowTip(self, widget) end)
        region:HookScript("OnLeave", function() UI.HideTooltip() end)
    end
end

local function LabelColor(fs, enabled)
    if enabled then fs:SetTextColor(1, 1, 1) else fs:SetTextColor(GREY, GREY, GREY) end
end

local function TopLabel(frame)
    local fs = UI.Font(frame, LABEL_SIZE)
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    fs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    fs:SetHeight(LABEL_H)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Container(parent, height)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(height)
    frame:EnableMouse(true)
    return frame
end

local function Finish(widget)
    widget:SetWidth(DEFAULT_WIDTH)
    widget:Refresh()
    widget:Paint()
    return widget
end

local function Boxed(frame)
    UI.Solid(frame, "BACKGROUND", 0, 0, 0, 0.5):SetAllPoints()
    return UI.Border(frame, 1, 1, 1, 0.25)
end

local function EditBox(parent)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetHeight(ROW_H)
    box:SetAutoFocus(false)
    local font = UI.FontObject(LABEL_SIZE)
    if font then box:SetFontObject(font) else box:SetFont(UI.FontPath(), LABEL_SIZE, "") end
    box:SetTextColor(1, 1, 1, 1)
    box:SetTextInsets(6, 6, 0, 0)
    Boxed(box)
    UI.SkinEditBox(box)
    return box
end

function W.Checkbox(parent, opts)
    local frame = CreateFrame("Button", nil, parent)
    frame:SetHeight(CELL_H)
    if frame.SetMotionScriptsWhileDisabled then frame:SetMotionScriptsWhileDisabled(true) end
    local w = New(opts, frame, CELL_H)
    local label = UI.Font(frame, LABEL_SIZE)
    label:SetPoint("LEFT", frame, "TOPLEFT", BOX - BOX_INSET + GAP, -(LABEL_H + ROW_H / 2))
    label:SetPoint("RIGHT", frame, "RIGHT", 0, -LABEL_H / 2)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)

    local box = CreateFrame("CheckButton", nil, frame)
    box:SetSize(BOX, BOX)
    box:SetPoint("LEFT", frame, "TOPLEFT", -BOX_INSET, -(LABEL_H + ROW_H / 2))
    box:EnableMouse(false)
    local edge = UI.Solid(box, "BACKGROUND", 1, 1, 1, 0.25)
    edge:SetPoint("TOPLEFT", box, "TOPLEFT", BOX_INSET - 1, -(BOX_INSET - 1))
    edge:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -(BOX_INSET - 1), BOX_INSET - 1)
    local fill = UI.Solid(box, "BORDER", 0.02, 0.02, 0.02, 1)
    fill:SetPoint("TOPLEFT", box, "TOPLEFT", BOX_INSET, -BOX_INSET)
    fill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -BOX_INSET, BOX_INSET)
    box:SetCheckedTexture(WHITE)
    local check = box:GetCheckedTexture()
    if check then
        check:ClearAllPoints()
        check:SetPoint("TOPLEFT", box, "TOPLEFT", CHECK_INSET, -CHECK_INSET)
        check:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -CHECK_INSET, CHECK_INSET)
    end
    UI.SkinCheckbox(box, { borderInset = BOX_INSET })
    w.label, w.box, w.check = label, box, check

    function w:Refresh()
        label:SetText(Label(self.opts))
        box:SetChecked(self.opts.get and self.opts.get() and true or false)
    end

    function w:Paint()
        frame:SetEnabled(self.enabled)
        LabelColor(label, self.enabled)
        box:SetAlpha(self.enabled and 1 or GREY)
        if check then check:SetVertexColor(UI.Accent()) end
    end

    frame:SetScript("OnClick", function()
        if w.enabled then w:Commit(not (w.opts.get and w.opts.get())) end
    end)
    AddTooltip(w, frame)
    return Finish(w)
end

local function KeyOrder(a, b)
    local na, nb = tonumber(a), tonumber(b)
    if na and nb then return na < nb end
    return tostring(a) < tostring(b)
end

local function Choices(opts)
    local values = Resolve(opts.values) or {}
    local order = Resolve(opts.sorting)
    if type(order) ~= "table" then
        order = {}
        for key in pairs(values) do order[#order + 1] = key end
        table.sort(order, KeyOrder)
    end
    return values, order
end

function W.Dropdown(parent, opts)
    local frame = Container(parent, CELL_H)
    local w = New(opts, frame, CELL_H)
    local label = TopLabel(frame)

    local button = CreateFrame("Button", nil, frame)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -LABEL_H)
    button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -LABEL_H)
    button:SetHeight(ROW_H)
    if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end
    Boxed(button)
    UI.Solid(button, "HIGHLIGHT", 1, 1, 1, 0.05):SetAllPoints()
    local arrow = button:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", button, "RIGHT", -6, 0)
    UI.SetArrowTexture(arrow)
    local text = UI.Font(button, LABEL_SIZE)
    text:SetPoint("LEFT", button, "LEFT", 8, 0)
    text:SetPoint("RIGHT", arrow, "LEFT", -4, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    button.Text = text
    UI.SkinDropdown(button)
    w.label, w.button, w.text, w.arrow = label, button, text, arrow

    function w:Refresh()
        label:SetText(Label(self.opts))
        local values = Choices(self.opts)
        local current = self.opts.get and self.opts.get()
        local shown = current ~= nil and values[current]
        text:SetText(shown and tostring(shown) or "")
    end

    function w:Paint()
        button:SetEnabled(self.enabled)
        LabelColor(label, self.enabled)
        LabelColor(text, self.enabled)
        arrow:SetAlpha(self.enabled and 1 or GREY)
    end

    button:SetScript("OnClick", function()
        if not w.enabled then return end
        local menuOpts = w.opts
        local values, order = Choices(menuOpts)
        local current = menuOpts.get and menuOpts.get()
        local items = {}
        for _, key in ipairs(order) do
            if values[key] ~= nil then
                items[#items + 1] = {
                    text = tostring(values[key]), isActive = key == current,
                    onClick = function() w:Commit(key, menuOpts) end,
                }
            end
        end
        if #items > 0 or UI.IsMenuOpen(button) then UI.DropdownMenu(button, items) end
    end)
    AddTooltip(w, frame, button)
    return Finish(w)
end

local function Trim(n)
    local s = ("%.2f"):format(n):gsub("0+$", ""):gsub("%.$", "")
    return s
end

local function FormatValue(value, isPercent)
    if isPercent then return Trim(value * 100) .. "%" end
    return Trim(value)
end

function W.Slider(parent, opts)
    local frame = Container(parent, CELL_H)
    local w = New(opts, frame, CELL_H)
    local label = TopLabel(frame)

    local slider = CreateFrame("Slider", nil, frame)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -LABEL_H)
    slider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(VALUE_W + GAP), -LABEL_H)
    slider:SetHeight(ROW_H)
    if slider.SetMotionScriptsWhileDisabled then slider:SetMotionScriptsWhileDisabled(true) end
    slider:EnableMouseWheel(true)
    local track = UI.Solid(slider, "BACKGROUND", 1, 1, 1, 0.15)
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetHeight(4)
    slider:SetThumbTexture(WHITE)
    local thumb = slider:GetThumbTexture()
    if thumb then thumb:SetSize(8, 16) end

    local valueText = EditBox(frame)
    valueText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -LABEL_H)
    valueText:SetWidth(VALUE_W)
    valueText:SetTextInsets(4, 4, 0, 0)
    valueText:SetJustifyH("CENTER")
    w.label, w.slider, w.valueText, w.thumb, w.editBox = label, slider, valueText, thumb, valueText

    local function Value()
        local range = w.opts.range or {}
        return tonumber(w.opts.get and w.opts.get()) or range.min or 0
    end

    function w:Refresh()
        local range = self.opts.range or {}
        local min, max, step = range.min or 0, range.max or 100, range.step or 0
        local value = Value()
        label:SetText(Label(self.opts))
        self.refreshing = true
        slider:SetMinMaxValues(min, max)
        slider:SetValueStep(step > 0 and step or 0)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(step > 0) end
        slider:SetValue(value)
        self.refreshing = false
        valueText:SetText(FormatValue(value, range.isPercent))
    end

    function w:Paint()
        slider:SetEnabled(self.enabled)
        valueText:SetEnabled(self.enabled)
        if not self.enabled then valueText:ClearFocus() end
        LabelColor(label, self.enabled)
        LabelColor(valueText, self.enabled)
        if thumb then
            local r, g, b = UI.Accent()
            if self.enabled then thumb:SetVertexColor(r, g, b) else thumb:SetVertexColor(GREY, GREY, GREY) end
        end
    end

    slider:SetScript("OnValueChanged", function(_, value)
        if not w.refreshing then w:Commit(value) end
    end)
    slider:SetScript("OnMouseWheel", function(_, delta)
        if not w.enabled then return end
        local range = w.opts.range or {}
        local step = range.bigStep or range.step or 0
        if step <= 0 then step = ((range.max or 100) - (range.min or 0)) / 100 end
        w:Commit(Value() + delta * step)
    end)
    valueText:SetScript("OnEnterPressed", function(self)
        local text = self:GetText():gsub("%%", "")
        local typed = tonumber(text)
        w:Refresh()
        self:ClearFocus()
        if not typed then return end
        if (w.opts.range or {}).isPercent then typed = typed / 100 end
        w:Commit(typed)
    end)
    valueText:SetScript("OnEscapePressed", function(self)
        w:Refresh()
        self:ClearFocus()
    end)
    valueText:SetScript("OnEditFocusLost", function() w:Refresh() end)
    AddTooltip(w, frame, slider, valueText)
    return Finish(w)
end

function W.Button(parent, opts)
    local frame = Container(parent, CELL_H)
    local w = New(opts, frame, CELL_H)
    local button = ns.CreateWindowButton(frame, DEFAULT_WIDTH, "", function()
        if not w.enabled then return end
        local run = w.opts.run
        Confirm(ConfirmText(w.opts), function() if run then run() end end)
    end)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -LABEL_H)
    button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -LABEL_H)
    button:SetHeight(ROW_H)
    button.label:SetWordWrap(false)
    UI.SkinButton(button)
    w.button, w.label = button, button.label

    function w:Layout(width)
        button.label:SetWidth(math.max(1, width - 8))
    end

    function w:Refresh()
        button.label:SetText(Label(self.opts))
    end

    function w:Paint()
        button:SetActive(self.enabled)
    end

    AddTooltip(w, frame, button)
    return Finish(w)
end

function W.Input(parent, opts)
    local frame = Container(parent, CELL_H)
    local w = New(opts, frame, CELL_H)
    local label = TopLabel(frame)

    local box = EditBox(frame)
    box:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -LABEL_H)
    box:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -LABEL_H)
    local okButton = ns.CreateWindowButton(box, OK_W, "OK", function()
        local text = box:GetText()
        w:Refresh()
        box:ClearFocus()
        w:Commit(text)
    end)
    okButton:SetHeight(ROW_H - 4)
    okButton:SetPoint("RIGHT", box, "RIGHT", -2, 0)
    UI.SkinButton(okButton)
    okButton:Hide()
    w.label, w.box, w.okButton, w.editBox = label, box, okButton, box

    local function Current()
        local value = w.opts.get and w.opts.get()
        if value == nil or value == false then return "" end
        return tostring(value)
    end

    local lastDirty
    local function UpdateOk()
        local dirty = w.enabled and box:GetText() ~= Current()
        if dirty == lastDirty then return end
        lastDirty = dirty
        okButton:SetShown(dirty)
        box:SetTextInsets(6, dirty and (OK_W + 6) or 6, 0, 0)
    end

    function w:Refresh()
        label:SetText(Label(self.opts))
        box:SetText(Current())
        UpdateOk()
    end

    function w:Paint()
        box:SetEnabled(self.enabled)
        if not self.enabled then box:ClearFocus() end
        LabelColor(label, self.enabled)
        LabelColor(box, self.enabled)
        UpdateOk()
    end

    box:SetScript("OnTextChanged", UpdateOk)

    box:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        w:Refresh()
        self:ClearFocus()
        w:Commit(text)
    end)
    box:SetScript("OnEscapePressed", function(self)
        w:Refresh()
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", function()
        if not okButton:IsMouseOver() then w:Refresh() end
    end)
    AddTooltip(w, frame, box)
    return Finish(w)
end

function W.Header(parent, opts)
    local frame = Container(parent, HEADER_H)
    local w = New(opts, frame, HEADER_H)
    local label = UI.Font(frame, LABEL_SIZE + 1)
    label:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, GAP)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    local line = UI.Solid(frame, "ARTWORK", 1, 1, 1, 0.15)
    line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    w.label, w.line = label, line

    function w:Layout(width)
        label:SetWidth(math.max(1, width))
    end

    function w:Refresh()
        label:SetText(Label(self.opts))
    end

    function w:Paint()
        local r, g, b = UI.Accent()
        if self.enabled then label:SetTextColor(r, g, b) else label:SetTextColor(GREY, GREY, GREY) end
    end

    if w.opts.desc then AddTooltip(w, frame) end
    return Finish(w)
end

function W.Text(parent, opts)
    local frame = CreateFrame("Frame", nil, parent)
    local w = New(opts, frame, TEXT_PAD)
    local text = UI.Font(frame, FONT_SIZES[(opts or {}).fontSize] or FONT_SIZES.small)
    text:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    w.text = text

    local function Measure()
        w.height = math.ceil(text:GetStringHeight() or 0) + TEXT_PAD
        frame:SetHeight(w.height)
    end

    function w:Layout(width)
        text:SetWidth(width)
        Measure()
    end

    function w:Refresh()
        text:SetText(Label(self.opts))
        Measure()
    end

    function w:Paint()
        local c = self.enabled and 0.85 or GREY
        text:SetTextColor(c, c, c)
    end

    return Finish(w)
end
