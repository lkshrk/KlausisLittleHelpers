local NAMES = { "CreateFrame", "GameTooltip", "StaticPopupDialogs", "StaticPopup_Show", "UIParent", "EllesmereUI", "issecretvalue" }
local saved = {}
for _, k in ipairs(NAMES) do saved[k] = rawget(_G, k) end

local NOOP = function() end
local Methods = {}
local function Obj(kind, parent)
    local o = { kind = kind, parent = parent, scripts = {}, points = {}, regions = {}, enabled = true, alpha = 1, text = "" }
    setmetatable(o, { __index = function(_, k) return Methods[k] or NOOP end })
    if kind == "EditBox" then o.caret = Obj("NativeCaret", o) end
    return o
end
function Methods:SetScript(name, fn)
    self.baseScripts = rawget(self, "baseScripts") or {}
    self.baseScripts[name] = fn
    local allHooks = rawget(self, "hooks")
    local hooks = allHooks and allHooks[name]
    self.scripts[name] = function(...)
        if fn then fn(...) end
        if hooks then for _, hook in ipairs(hooks) do hook(...) end end
    end
end
function Methods:GetScript(name) return self.scripts[name] end
function Methods:HookScript(name, fn)
    self.hooks = rawget(self, "hooks") or {}
    self.hooks[name] = self.hooks[name] or {}
    table.insert(self.hooks[name], fn)
    local baseScripts = rawget(self, "baseScripts")
    self:SetScript(name, baseScripts and baseScripts[name])
end
function Methods:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Methods:ClearAllPoints() self.points = {} end
function Methods:SetWidth(w) self.width = w end
function Methods:GetWidth() return self.width or 0 end
function Methods:SetHeight(h) self.height = h end
function Methods:GetHeight() return self.height or 0 end
function Methods:SetSize(w, h) self.width, self.height = w, h end
function Methods:SetText(s) self.text = s end
function Methods:GetText() return self.text end
function Methods:SetTextInsets(...) self.insets = { ... }; self.insetCalls = (rawget(self, "insetCalls") or 0) + 1 end
function Methods:SetTextColor(r, g, b) self.color = { r, g, b } end
function Methods:SetWordWrap(on) self.wrap = on end
function Methods:SetFontObject(obj) self.font = obj end
function Methods:SetFont(path, size) self.font = size end
function Methods:GetStringHeight() return self.text == "" and 0 or 12 * math.ceil(#self.text * 6 / math.max(self.width or 1, 1)) end
function Methods:SetAlpha(a) self.alpha = a end
function Methods:SetEnabled(on) self.enabled = on and true or false end
function Methods:IsEnabled() return self.enabled end
function Methods:SetChecked(on) self.checked = on end
function Methods:GetChecked() return self.checked end
function Methods:SetCheckedTexture(asset) self.checkedTex = Obj("Texture", self); self.checkedTex.file = asset end
function Methods:GetCheckedTexture() return self.checkedTex end
function Methods:SetThumbTexture(asset) self.thumb = Obj("Texture", self); self.thumb.file = asset end
function Methods:GetThumbTexture() return self.thumb end
function Methods:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
function Methods:SetValueStep(s) self.step = s end
function Methods:SetObeyStepOnDrag(on) self.obey = on end
function Methods:SetValue(v)
    self.value = v
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v, false) end
end
function Methods:GetValue() return self.value end
function Methods:SetFocus() self.focused = true end
function Methods:HasFocus() return self.focused == true end
function Methods:Show() self.shown = true end
function Methods:Hide() self.shown = false end
function Methods:SetShown(on) self.shown = on and true or false end
function Methods:ClearFocus()
    if not self.focused then return end
    self.focused = false
    if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
end
function Methods:GetRegions() return unpack(self.regions) end
function Methods:GetFrameLevel() local level, parent = rawget(self, "level"), rawget(self, "parent"); return level or (parent and parent:GetFrameLevel() + 1) or 0 end
function Methods:SetFrameLevel(level) self.level = level end
function Methods:CreateTexture() local t = Obj("Texture", self); self.regions[#self.regions + 1] = t; return t end
function Methods:CreateFontString() local t = Obj("FontString", self); return t end

local function Fire(frame, script, ...)
    local fn = frame.scripts[script]
    if fn then return fn(frame, ...) end
end

local tip = {}
local popups = {}

local ran, err = pcall(function()
    _G.CreateFrame = function(kind, _, parent) return Obj(kind, parent) end
    _G.UIParent = nil
    _G.GameTooltip = setmetatable({}, { __index = function(_, k)
        if k == "SetOwner" then return function(_, owner) tip.owner, tip.lines, tip.shown = owner, {}, false end end
        if k == "AddLine" or k == "SetText" then return function(_, text) tip.lines[#tip.lines + 1] = text end end
        if k == "Show" then return function() tip.shown = true end end
        if k == "Hide" then return function() tip.shown = false end end
        if k == "GetHeight" then return function() return 10 end end
        return NOOP
    end })
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function(which, text, _, data)
        popups[#popups + 1] = { which = which, text = text, data = data }
    end

    local registerSkin
    _G.EllesmereUI = { RegisterSkin = function(_, callback) registerSkin = callback end }
    addon("Core/UI.lua")
    addon("Core/Skin.lua")
    addon("Core/OptionsModel.lua")
    addon("Core/ListWindow.lua")
    addon("Core/Widgets.lua")
    local W = ns.Widgets
    ok(W, "ns.Widgets exists")

    local function checkCaret(widget, label)
        local box = widget.editBox
        box:SetFocus()
        ok(box:HasFocus(), label .. " receives focus")
        eq(#box.regions, 5, label .. " has direct background regions without a custom caret")
        eq(box.caret.alpha, 1, label .. " retains native caret")
        eq(box.parent, widget.frame, label .. " places edit box directly in widget")
    end
    local input = W.Input(Obj("Frame"), { get = function() return "text" end })
    local slider = W.Slider(Obj("Frame"), { get = function() return 5 end, range = {} })
    checkCaret(input, "input before skin registration")
    checkCaret(slider, "slider before skin registration")
    local skinned = {}
    registerSkin({ EditBox = function(frame)
        skinned[#skinned + 1] = frame
        for _, region in ipairs({ frame:GetRegions() }) do region:SetAlpha(0) end
    end })
    eq(skinned[1], input.editBox, "late skin receives input")
    eq(skinned[2], slider.editBox, "late skin receives slider input")
    checkCaret(input, "input after late skin registration")
    checkCaret(slider, "slider after late skin registration")
    local ready = W.Input(Obj("Frame"), { get = function() return "" end })
    eq(skinned[3], ready.editBox, "ready skin receives input")
    checkCaret(ready, "input with skin ready")
    _G.EllesmereUI = nil
    addon("Core/Skin.lua")
    checkCaret(W.Input(Obj("Frame"), { get = function() return "" end }), "input without EUI")
    checkCaret(W.Slider(Obj("Frame"), { range = {} }), "slider without EUI")

    local menus = {}
    ns.UI.DropdownMenu = function(anchor, items) menus[#menus + 1] = { anchor = anchor, items = items } end
    ns.UI.IsMenuOpen = function() return false end

    local function Store(initial)
        local s = { value = initial, sets = {} }
        s.get = function() return s.value end
        s.set = function(v) s.sets[#s.sets + 1] = v; s.value = v end
        return s
    end

    local function TooltipShows(widget, text, msg)
        Fire(widget.frame, "OnEnter")
        local found = false
        for _, line in ipairs(tip.lines or {}) do if line == text then found = true end end
        ok(tip.shown and found, msg)
        Fire(widget.frame, "OnLeave")
        eq(tip.shown, false, msg .. " (hidden on leave)")
    end

    for _, name in ipairs({ "Checkbox", "Dropdown", "Slider", "Button", "Input", "Header", "Text" }) do
        local w = W[name](Obj("Frame"), { label = "L", get = function() end, values = {}, range = {} })
        ok(w.frame, name .. " has a frame")
        w:SetWidth(180)
        eq(w.frame.width, 180, name .. " takes its width")
        eq(type(w:Height()), "number", name .. " reports a height")
        ok(w:Height() > 0, name .. " height positive")
        w:Refresh()
        w:SetEnabled(false)
        w:SetEnabled(true)
    end

    do
        local s = Store(true)
        local cb = W.Checkbox(Obj("Frame"), { label = "A very long label that will not fit", desc = "What it does", get = s.get, set = s.set })
        cb:SetWidth(150)
        cb:Refresh()
        eq(cb.box:GetChecked(), true, "checkbox reads get on Refresh")
        s.value = false
        cb:Refresh()
        eq(cb.box:GetChecked(), false, "checkbox re-reads get")
        Fire(cb.frame, "OnClick")
        eq(s.sets[1], true, "click sets the toggled value")
        eq(cb.box:GetChecked(), true, "click refreshes the box")
        eq(cb.label.wrap, false, "checkbox label does not wrap")
        local function Anchors(region)
            local out = {}
            for _, pt in ipairs(region.points) do out[pt[1]] = pt end
            return out
        end
        local la = Anchors(cb.label)
        ok(la.LEFT and la.RIGHT, "checkbox label sits beside the box")
        eq(cb:Height(), 42, "checkbox cell is as tall as the other controls")
        eq(cb.frame.height, 42)
        local bp = cb.box.points[1]
        eq(bp[1], "LEFT"); eq(bp[3], "TOPLEFT")
        eq(bp[5], -(18 + 24 / 2), "the box is centered on the control line")
        eq(cb.box.width, 26, "the box frame leaves a 4 px inset around an 18 px box")
        s.value = false
        cb:Refresh()
        Fire(cb.frame, "OnClick")
        eq(s.sets[#s.sets], true, "clicking the label area toggles")
        ok(cb.label.parent == cb.frame, "the label sits on the clickable cell")
        s.value = true
        cb:Refresh()
        TooltipShows(cb, "What it does", "checkbox tooltip shows desc")
        TooltipShows(cb, "A very long label that will not fit", "checkbox tooltip shows the full label")
        cb:SetEnabled(false)
        eq(cb.frame:IsEnabled(), false, "disabled checkbox is not clickable")
        ok(cb.label.color[1] < 1, "disabled checkbox label greys")
        TooltipShows(cb, "What it does", "disabled checkbox still shows its tooltip")
        cb:SetEnabled(true)
        eq(cb.frame:IsEnabled(), true)
        eq(cb.label.color[1], 1, "enabled label white")
    end

    do
        local s = Store("b")
        local values = { a = "Alpha", b = "Beta", c = "Gamma" }
        local dd = W.Dropdown(Obj("Frame"), { label = "Pick", desc = "Choose one", get = s.get, set = s.set,
            values = function() return values end, sorting = function() return { "c", "a", "b" } end })
        dd:Refresh()
        eq(dd.text.text, "Beta", "dropdown shows the current value's text")
        Fire(dd.button, "OnClick")
        local menu = menus[#menus]
        ok(menu, "dropdown opens UI.DropdownMenu")
        eq(menu.anchor, dd.button, "menu anchors to the button")
        eq(#menu.items, 3)
        eq(menu.items[1].text, "Gamma", "menu follows sorting")
        eq(menu.items[2].text, "Alpha"); eq(menu.items[3].text, "Beta")
        eq(menu.items[3].isActive, true, "current value is marked")
        ok(not menu.items[1].isActive, "others are not marked")
        menu.items[1].onClick()
        eq(s.sets[1], "c", "picking an item sets its key")
        eq(dd.text.text, "Gamma", "dropdown refreshes after set")
        TooltipShows(dd, "Choose one", "dropdown tooltip shows desc")
        dd:SetEnabled(false)
        eq(dd.button:IsEnabled(), false, "disabled dropdown button")
        ok(dd.label.color[1] < 1, "disabled dropdown label greys")

        local plain = W.Dropdown(Obj("Frame"), { label = "P", get = function() return 2 end, set = NOOP,
            values = { [10] = "Ten", [2] = "Two", [1] = "One" } })
        Fire(plain.button, "OnClick")
        local items = menus[#menus].items
        eq(items[1].text, "One", "without sorting keys sort numerically")
        eq(items[2].text, "Two"); eq(items[3].text, "Ten")
        eq(items[2].isActive, true)

        local first = Store(1)
        local reused = W.Dropdown(Obj("Frame"), { label = "R", get = first.get, set = first.set, values = { [1] = "A", [2] = "B" } })
        Fire(reused.button, "OnClick")
        local open = menus[#menus].items
        local second = Store(1)
        reused.opts = { label = "R2", get = second.get, set = second.set, values = { [1] = "A", [2] = "B" } }
        open[2].onClick()
        eq(first.sets[1], 2, "a menu commits to the options it opened with")
        eq(#second.sets, 0, "not to the options of a reused widget")

        local count = #menus
        local empty = W.Dropdown(Obj("Frame"), { label = "E", get = NOOP, set = NOOP, values = {} })
        Fire(empty.button, "OnClick")
        eq(#menus, count, "a dropdown without values opens no menu")
    end

    do
        local store = { v = 0.5 }
        local root = { type = "group", args = { scale = { type = "range", name = "Scale", desc = "How big",
            min = 0, max = 1, step = 0.05, isPercent = true,
            get = function() return store.v end, set = function(_, v) store.v = v end } } }
        local control = ns.OptionsModel.Page(root, "").controls[1]
        local sl = W.Slider(Obj("Frame"), control)
        sl:Refresh()
        eq(sl.slider.min, 0, "slider min from range"); eq(sl.slider.max, 1, "slider max from range")
        eq(sl.slider.step, 0.05, "slider snaps to step"); eq(sl.slider.obey, true, "slider obeys the step on drag")
        eq(sl.slider.value, 0.5, "slider reads get on Refresh")
        eq(sl.valueText.text, "50%", "percent value text")
        eq(sl.label.text, "Scale")
        eq(sl.valueText.width, 48, "the value box is narrow")
        eq(sl.valueText.points[1][5], -18, "the value box sits on the control line")
        eq(sl.slider.points[2][4], -(48 + 6), "the bar takes the rest of the width")
        eq(sl:Height(), 42)
        Fire(sl.slider, "OnValueChanged", 0.537, true)
        eq(store.v, 0.55, "user drag sets a snapped value")
        eq(sl.valueText.text, "55%", "value text follows the set")
        Fire(sl.slider, "OnValueChanged", 1.4, true)
        eq(store.v, 1, "set clamps to max")
        eq(sl.valueText.text, "100%")
        eq(sl.slider.value, 1, "slider refreshed to the clamped value")
        TooltipShows(sl, "How big", "slider tooltip shows desc")
        sl:SetEnabled(false)
        eq(sl.slider:IsEnabled(), false, "disabled slider")
        ok(sl.label.color[1] < 1, "disabled slider label greys")

        local n = Store(3)
        local plain = W.Slider(Obj("Frame"), { label = "N", get = n.get, set = n.set, range = { min = 0, max = 10, step = 0.5 } })
        plain:Refresh()
        eq(plain.valueText.text, "3", "integer value text")
        n.value = 1.25
        plain:Refresh()
        eq(plain.valueText.text, "1.25", "decimal value text")
        local sets = #n.sets
        plain:Refresh()
        eq(#n.sets, sets, "refresh does not call set")

        plain.opts = { label = "Pooled", get = n.get, set = n.set, range = { min = 0, max = 10 } }
        plain:Refresh()
        eq(plain.slider.step, 0, "a reused slider drops the old step")
        eq(plain.slider.obey, false, "and does not snap on drag")

        local writ = { v = 3 }
        local writRoot = { type = "group", args = { count = { type = "range", name = "Count", min = 2, max = 100, step = 1, bigStep = 5,
            get = function() return writ.v end, set = function(_, v) writ.v = v end } } }
        local wc = W.Slider(Obj("Frame"), ns.OptionsModel.Page(writRoot, "").controls[1])
        wc:Refresh()
        eq(wc.slider.step, 1, "dragging uses step, not bigStep")
        eq(wc.slider.obey, true)
        Fire(wc.slider, "OnValueChanged", 10, true)
        eq(writ.v, 10, "drag sets 10")
        Fire(wc.slider, "OnMouseWheel", 1)
        eq(writ.v, 15, "the wheel moves by bigStep")
        Fire(wc.slider, "OnMouseWheel", -1)
        eq(writ.v, 10)
        writ.v = 3
        wc:Refresh()
        wc.valueText:SetFocus()
        wc.valueText:SetText("10")
        Fire(wc.valueText, "OnEnterPressed")
        eq(writ.v, 10, "typing 10 sets 10")
        eq(wc.valueText.text, "10", "the box shows the set value")
        eq(wc.valueText.focused, false, "enter clears focus")
        wc.valueText:SetFocus()
        wc.valueText:SetText("10.4")
        Fire(wc.valueText, "OnEnterPressed")
        eq(writ.v, 10, "a typed value snaps to the step")
        wc.valueText:SetFocus()
        wc.valueText:SetText("500")
        Fire(wc.valueText, "OnEnterPressed")
        eq(writ.v, 100, "a typed value clamps")
        wc.valueText:SetFocus()
        wc.valueText:SetText("abc")
        Fire(wc.valueText, "OnEnterPressed")
        eq(writ.v, 100, "text that is no number sets nothing")
        eq(wc.valueText.text, "100", "and reverts")
        wc.valueText:SetFocus()
        wc.valueText:SetText("7")
        Fire(wc.valueText, "OnEscapePressed")
        eq(writ.v, 100, "escape does not commit"); eq(wc.valueText.text, "100", "escape reverts")
        wc.valueText:SetFocus()
        wc.valueText:SetText("7")
        wc.valueText:ClearFocus()
        eq(writ.v, 100, "focus loss does not commit"); eq(wc.valueText.text, "100", "focus loss reverts")

        sl.opts.get = function() return store.v end
        sl:SetEnabled(true)
        sl.valueText:SetFocus()
        sl.valueText:SetText("25%")
        Fire(sl.valueText, "OnEnterPressed")
        eq(store.v, 0.25, "a typed percent sets the fraction")
    end

    do
        local runs = 0
        local b = W.Button(Obj("Frame"), { label = "Go", desc = "Runs it", run = function() runs = runs + 1 end })
        eq(b:Height(), 42, "button cell is as tall as the other controls")
        eq(b.button.height, 24, "the button fills the control line")
        eq(b.button.points[1][1], "TOPLEFT"); eq(b.button.points[1][5], -18, "the button sits below the empty label line")
        eq(b.button.points[2][1], "TOPRIGHT")
        Fire(b.button, "OnClick")
        eq(runs, 1, "button runs without confirm")
        TooltipShows(b, "Runs it", "button tooltip shows desc")
        b:SetEnabled(false)
        eq(b.button:IsEnabled(), false, "disabled button")

        local before = #popups
        local c = W.Button(Obj("Frame"), { label = "Reset", run = function() runs = runs + 1 end,
            confirmText = function() return "Really reset?" end })
        Fire(c.button, "OnClick")
        eq(runs, 1, "confirm button waits")
        eq(#popups, before + 1, "confirm popup shown")
        local p = popups[#popups]
        eq(p.which, "KLH_OPTIONS_CONFIRM"); eq(p.text, "Really reset?")
        local dialog = _G.StaticPopupDialogs.KLH_OPTIONS_CONFIRM
        ok(dialog, "confirm popup registered")
        dialog.OnAccept(nil, p.data)
        eq(runs, 2, "accepting runs")
        Fire(c.button, "OnClick")
        dialog.OnCancel(nil, popups[#popups].data)
        eq(runs, 2, "cancelling does not run")

        local str = W.Button(Obj("Frame"), { label = "X", run = function() runs = runs + 1 end, confirm = "Sure?" })
        Fire(str.button, "OnClick")
        eq(popups[#popups].text, "Sure?", "string confirm is the text")
        local yes = W.Button(Obj("Frame"), { label = "Wipe", run = NOOP, confirm = true })
        Fire(yes.button, "OnClick")
        eq(popups[#popups].text, "Wipe", "confirm true asks with the label")
        eq(runs, 2)
    end

    do
        local s = Store(false)
        local before = #popups
        local cb = W.Checkbox(Obj("Frame"), { label = "Danger", get = s.get, set = s.set,
            confirmText = function(pending) return pending and "Turn on?" or nil end })
        cb:Refresh()
        Fire(cb.frame, "OnClick")
        eq(#s.sets, 0, "set with confirm waits")
        eq(#popups, before + 1)
        eq(popups[#popups].text, "Turn on?", "confirm text gets the pending value")
        _G.StaticPopupDialogs.KLH_OPTIONS_CONFIRM.OnCancel(nil, popups[#popups].data)
        eq(#s.sets, 0); eq(cb.box:GetChecked(), false, "cancel keeps the old value")
        Fire(cb.frame, "OnClick")
        _G.StaticPopupDialogs.KLH_OPTIONS_CONFIRM.OnAccept(nil, popups[#popups].data)
        eq(s.sets[1], true, "accept sets"); eq(cb.box:GetChecked(), true)
    end

    do
        local s = Store("Old")
        local inp = W.Input(Obj("Frame"), { label = "Name", desc = "Profile name", get = s.get, set = s.set })
        local initialInsets = inp.box.insetCalls
        inp:Refresh()
        eq(inp.box.insetCalls, initialInsets, "refresh does not reapply unchanged input insets")
        eq(inp.box.text, "Old", "input reads get on Refresh")
        inp.box:SetText("Typing")
        Fire(inp.box, "OnTextChanged")
        eq(inp.box.insetCalls, initialInsets + 1, "dirty input updates insets once")
        Fire(inp.box, "OnTextChanged")
        inp:Paint()
        eq(inp.box.insetCalls, initialInsets + 1, "unchanged dirty input does not repeat inset writes")
        inp:Refresh()
        eq(inp.box.insetCalls, initialInsets + 2, "clean input restores insets")
        inp.box:SetFocus()
        inp.box:SetText("New")
        Fire(inp.box, "OnEnterPressed")
        eq(s.sets[1], "New", "enter commits")
        eq(#s.sets, 1, "focus loss after enter does not commit again")
        eq(inp.box.focused, false, "enter clears focus")
        inp.box:SetFocus()
        inp.box:SetText("Typed")
        inp.box:ClearFocus()
        eq(#s.sets, 1, "focus loss does not commit")
        eq(inp.box.text, "New", "focus loss reverts the typed text")
        inp.box:SetFocus()
        inp.box:SetText("Discard")
        Fire(inp.box, "OnEscapePressed")
        eq(#s.sets, 1, "escape does not commit")
        eq(inp.box.text, "New", "escape reverts")
        eq(inp.okButton.shown, false, "no OK button while the text is saved")
        inp.box:SetFocus()
        inp.box:SetText("Clicked")
        Fire(inp.box, "OnTextChanged")
        eq(inp.okButton.shown, true, "OK button shows while the text differs")
        Fire(inp.okButton, "OnClick")
        eq(s.sets[2], "Clicked", "OK commits the text")
        eq(inp.okButton.shown, false, "OK hides after the commit")
        eq(inp.box.focused, false, "OK clears focus")

        local falsy = W.Input(Obj("Frame"), { label = "New", get = function() return false end, set = NOOP })
        falsy:Refresh()
        eq(falsy.box.text, "", "get returning false shows an empty box")

        local blank = Store(nil)
        local new = W.Input(Obj("Frame"), { label = "New", get = blank.get, set = function(v) blank.sets[#blank.sets + 1] = v end })
        new:Refresh()
        eq(new.box.text, "", "nil value shows empty")
        new.box:SetFocus(); new.box:SetText("Fresh")
        Fire(new.box, "OnEnterPressed")
        eq(#blank.sets, 1, "a set that leaves get unchanged commits once")
        TooltipShows(inp, "Profile name", "input tooltip shows desc")
        inp:SetEnabled(false)
        eq(inp.box:IsEnabled(), false, "disabled input")
        ok(inp.label.color[1] < 1, "disabled input label greys")
    end

    do
        local h = W.Header(Obj("Frame"), { label = "Section" })
        h:SetWidth(600)
        h:Refresh()
        eq(h.label.text, "Section", "header label")
        ok(h.line, "header draws a line")
        local anchors = {}
        for _, p in ipairs(h.line.points) do anchors[p[1]] = true end
        ok((anchors.LEFT or anchors.BOTTOMLEFT or anchors.TOPLEFT) and (anchors.RIGHT or anchors.BOTTOMRIGHT or anchors.TOPRIGHT),
            "header line spans the full width")
    end

    do
        local t = W.Text(Obj("Frame"), { label = string.rep("word ", 40), fontSize = "large" })
        t:SetWidth(100)
        t:Refresh()
        eq(t.text.wrap, true, "text wraps")
        eq(t.text.width, 100, "text spans the width")
        local tall = t:Height()
        t:SetWidth(600)
        ok(t:Height() < tall, "text height follows the wrapped height")
        local small = W.Text(Obj("Frame"), { label = "x" })
        ok(t.text.font ~= small.text.font, "fontSize picks a different font")
    end
end)

for _, k in ipairs(NAMES) do _G[k] = saved[k] end
if not ran then error(err, 0) end
