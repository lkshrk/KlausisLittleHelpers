local NAMES = { "CreateFrame", "GameTooltip", "StaticPopupDialogs", "StaticPopup_Show", "UIParent", "LibStub", "C_Timer",
    "UISpecialFrames", "Settings", "SettingsPanel", "HideUIPanel", "InCombatLockdown", "geterrorhandler", "C_AddOns",
    "KLHOptionsWindow", "KLH" }
local saved = {}
for _, k in ipairs(NAMES) do saved[k] = rawget(_G, k) end

local NOOP = function() end
local Methods = {}
local frames = {}
local function Obj(kind, parent)
    local o = { kind = kind, parent = parent, scripts = {}, points = {}, enabled = true, alpha = 1, text = "", shown = true }
    return setmetatable(o, { __index = function(_, k) return Methods[k] or NOOP end })
end
function Methods:SetScript(name, fn) self.scripts[name] = fn end
function Methods:GetScript(name) return self.scripts[name] end
function Methods:HookScript(name, fn)
    local old = self.scripts[name]
    self.scripts[name] = old and function(...) old(...); fn(...) end or fn
end
function Methods:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Methods:ClearAllPoints() self.points = {} end
function Methods:SetWidth(w) self.width = w end
function Methods:GetWidth() return rawget(self, "width") or 0 end
function Methods:GetFrameLevel() return rawget(self, "level") or 0 end
function Methods:SetFrameLevel(level) self.level = level end
function Methods:SetHeight(h) self.height = h end
function Methods:GetHeight() return rawget(self, "height") or 0 end
function Methods:SetSize(w, h) self.width, self.height = w, h end
function Methods:SetText(s) self.text = s end
function Methods:GetText() return self.text end
function Methods:SetTextColor(r, g, b) self.color = { r, g, b } end
function Methods:GetStringHeight() return self.text == "" and 0 or 12 * math.ceil(#self.text * 6 / math.max(self.width or 1, 1)) end
function Methods:SetEnabled(on) self.enabled = on and true or false end
function Methods:IsEnabled() return self.enabled end
function Methods:SetChecked(on) self.checked = on end
function Methods:GetChecked() return self.checked end
function Methods:SetCheckedTexture() self.checkedTex = Obj("Texture", self) end
function Methods:GetCheckedTexture() return self.checkedTex end
function Methods:SetThumbTexture() self.thumb = Obj("Texture", self) end
function Methods:GetThumbTexture() return self.thumb end
function Methods:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
function Methods:SetValue(v)
    self.value = v
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v, true) end
end
function Methods:GetValue() return self.value end
function Methods:Show() self.shown = true end
function Methods:Hide()
    local was = self.shown
    self.shown = false
    if self.focused then self:ClearFocus() end
    if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Methods:IsShown() return self.shown end
function Methods:SetShown(on) if on then self:Show() else self:Hide() end end
function Methods:SetFrameStrata(s) self.strata = s end
function Methods:SetVerticalScroll(v) self.scroll = v end
function Methods:GetVerticalScroll() return rawget(self, "scroll") or 0 end
function Methods:GetVerticalScrollRange() return 0 end
function Methods:SetScrollChild(child) self.child = child end
function Methods:GetScrollChild() return self.child end
function Methods:SetFocus() self.focused = true end
function Methods:HasFocus() return self.focused == true end
function Methods:ClearFocus()
    if not self.focused then return end
    self.focused = false
    if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
end
function Methods:CreateTexture() return Obj("Texture", self) end
function Methods:CreateFontString() return Obj("FontString", self) end

local function Fire(frame, script, ...)
    local fn = frame.scripts[script]
    if fn then return fn(frame, ...) end
end

local timers = {}
local function RunTimers()
    while #timers > 0 do
        local batch = timers
        timers = {}
        for _, fn in ipairs(batch) do fn() end
    end
end

local ran, err = pcall(function()
    _G.CreateFrame = function(kind, name, parent, template)
        local o = Obj(kind, parent)
        o.name, o.template = name, template
        frames[#frames + 1] = o
        if name then _G[name] = o end
        return o
    end
    _G.UIParent = Obj("Frame")
    _G.GameTooltip = setmetatable({}, { __index = function() return NOOP end })
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = NOOP
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    _G.UISpecialFrames = {}
    _G.InCombatLockdown = nil
    _G.geterrorhandler = function() return function(e) error(e, 0) end end
    _G.C_AddOns = { IsAddOnLoaded = function() return true end }
    local blizzPanel
    _G.Settings = {
        RegisterCanvasLayoutCategory = function(panel) blizzPanel = panel; return {} end,
        RegisterAddOnCategory = NOOP,
    }
    local fakeDB = { char = {}, global = {}, profile = { features = {} }, callbacks = {} }
    fakeDB.RegisterCallback = function(_, event, fn) fakeDB.callbacks[event] = fn end
    local profilesTable = { type = "group", name = "Profiles", args = {
        current = { type = "description", order = 1, name = function() return "Current: " .. (fakeDB.profileName or "Default") end },
    } }
    _G.LibStub = function(name)
        if name == "AceDB-3.0" then return { New = function() return fakeDB end } end
        if name == "AceDBOptions-3.0" then return { GetOptionsTable = function() return profilesTable end } end
    end

    addon("Core/Core.lua")
    addon("Core/UI.lua")
    addon("Core/Skin.lua")
    addon("Core/Widgets.lua")
    addon("Core/OptionsModel.lua")
    addon("Core/Options.lua")
    addon("Core/ListWindow.lua")
    addon("Core/OptionsWindow.lua")

    local G = ns.OptionsGrid
    ok(type(G) == "function", "ns.OptionsGrid exists")
    local function Cells(spans)
        local out = {}
        for i, c in ipairs(G(spans, 3)) do out[i] = c.row .. ":" .. c.col .. ":" .. c.span end
        return table.concat(out, " ")
    end
    eq(Cells({ 1, 1, 1, 1 }), "1:1:1 1:2:1 1:3:1 2:1:1", "single cells fill three columns, then wrap")
    eq(Cells({ 1, 3, 1 }), "1:1:1 2:1:3 3:1:1", "a full row starts and ends its own row")
    eq(Cells({ 2, 2 }), "1:1:2 2:1:2", "a double that does not fit wraps")
    eq(Cells({ 1, 2, 1 }), "1:1:1 1:2:2 2:1:1", "a double fills the rest of a row")
    eq(Cells({ 3, 3 }), "1:1:3 2:1:3", "headers each take a row")
    eq(Cells({}), "", "no controls, no cells")

    local function S() return ns.GetSettings("WinA") end
    ns.FEATURE_CLIENTS.WinA, ns.FEATURE_CLIENTS.WinB = "all", "all"
    ns.RegisterFeature({
        key = "WinA", title = "Window A", help = "Help for A.", alwaysOn = true, tab = "helpers",
        defaults = { flag = false, size = 1, mode = "x" },
        enable = NOOP,
        options = function()
            return {
                flag = { type = "toggle", order = 1, name = function() return S().flag and "Flag on" or "Flag off" end,
                    get = function() return S().flag end, set = function(_, v) S().flag = v end },
                dep = { type = "toggle", order = 2, name = "Dependent", disabled = function() return not S().flag end,
                    get = function() return false end, set = NOOP },
                size = { type = "range", order = 3, name = "Size", min = 0, max = 10, step = 1,
                    get = function() return S().size end, set = function(_, v) S().size = v end },
                mode = { type = "select", order = 4, name = "Mode", values = { x = "X", y = "Y" },
                    get = function() return S().mode end, set = function(_, v) S().mode = v end },
                extra = { type = "toggle", order = 5, name = "Extra", hidden = function() return not S().flag end,
                    get = function() return false end, set = NOOP },
                newName = { type = "input", order = 6, name = "New name", get = false,
                    set = function(_, v) S().created = v end },
            }
        end,
    })
    ns.RegisterFeature({
        key = "WinB", title = "Window B", alwaysOn = true, tab = "qol", enable = NOOP,
        options = function() return { b = { type = "toggle", order = 1, name = "B", get = NOOP, set = NOOP } } end,
    })
    ns.RegisterOptions()

    local Win = ns.OptionsWindow
    ns.OpenOptions()
    local frame = _G.KLHOptionsWindow
    ok(frame and frame.shown, "OpenOptions shows the window")
    eq(frame.width, 900, "window width"); eq(frame.height, 600, "window height")
    eq(frame.strata, "DIALOG", "window strata")
    local esc = false
    for _, name in ipairs(_G.UISpecialFrames) do if name == "KLHOptionsWindow" then esc = true end end
    ok(esc, "Esc closes the window through UISpecialFrames")

    local labels = {}
    for i, b in ipairs(Win.entries) do labels[i] = b.entry.label end
    eq(table.concat(labels, ","), "General,QoL,Window B,Helpers,Window A,Profiles", "sidebar lists tabs as headings with their features")
    eq(Win.pageId, "general", "first page is General")
    local function Entry(label)
        for _, b in ipairs(Win.entries) do if b.entry.label == label then return b end end
    end
    ok(Entry("Helpers").entry.heading, "a tab is a heading")
    Fire(Entry("Helpers"), "OnClick")
    eq(Win.pageId, "general", "a heading is not a page")

    Fire(Entry("Window A"), "OnClick")
    eq(Win.pageId, "helpers.WinA", "clicking an entry opens its page")
    eq(Win.title.text, "Window A", "page title")
    local function Placed(label)
        for _, p in ipairs(Win.placed) do if p.control.label == label then return p end end
    end
    ok(Placed("Help for A."), "help line renders")
    ok(Placed("Flag off") and Placed("Size") and Placed("Mode") and Placed("Dependent"), "controls render")
    eq(Placed("Extra"), nil, "hidden control left out")
    eq(Placed("Dependent").widget.enabled, false, "dependent starts disabled")
    local size, dep0, mode = Placed("Size"), Placed("Dependent"), Placed("Mode")
    eq(size.cell.row, dep0.cell.row, "single cells share a row")
    eq(size.cell.col, 3, "third column")
    eq(mode.cell.row, size.cell.row + 1, "a fourth cell wraps")
    eq(size.widget.frame.width, mode.widget.frame.width, "cells keep equal widths")
    eq(size.widget.frame.width, dep0.widget.frame.width, "checkbox and slider cells equal")
    ok(Placed("Help for A.").widget.frame.width > size.widget.frame.width * 2, "help line spans the row")
    local function Top(p) return -p.widget.frame.points[1][5] end
    eq(Top(dep0), Top(size), "cells in a row share their top edge")
    eq(dep0.widget:Height(), size.widget:Height(), "a checkbox is as tall as a slider")

    local renders = Win.renders
    local dep = Placed("Dependent")
    Fire(Placed("Flag off").widget.frame, "OnClick")
    eq(S().flag, true, "checkbox sets")
    eq(dep.widget.enabled, true, "dependent enabled in place right after the set")
    eq(Win.renders, renders, "no rebuild in the same frame")
    RunTimers()
    eq(Win.renders, renders + 1, "page rebuilt a frame later")
    ok(Placed("Flag on"), "rebuilt page picks up the new label")
    ok(Placed("Extra"), "rebuilt page shows a control no longer hidden")

    local slider = Placed("Size").widget
    renders = Win.renders
    Fire(slider.slider, "OnMouseDown")
    slider.slider:SetValue(5)
    eq(S().size, 5, "slider sets while dragging")
    slider.slider:SetValue(6)
    RunTimers()
    eq(S().size, 6)
    eq(Win.renders, renders, "no rebuild while the slider is held")
    eq(Placed("Size").widget, slider, "dragged slider stays the same widget")
    Fire(slider.slider, "OnMouseUp")
    RunTimers()
    eq(Win.renders, renders + 1, "rebuild once the drag ends")

    ns.CloseOptions()
    eq(frame.shown, false, "CloseOptions hides the window")
    ns.OpenOptions()
    eq(Win.pageId, "helpers.WinA", "reopening shows the last page")
    ns.OpenOptions("profiles")
    eq(Win.pageId, "profiles", "OpenOptions opens a given page")
    eq(Placed("Current: Default") ~= nil, true, "profiles page renders")
    ns.OpenOptions("helpers.WinA")

    eq(Placed("Flag on").widget.box:GetChecked(), true)
    fakeDB.profile = { features = { WinA = { flag = false } } }
    fakeDB.callbacks.OnProfileChanged()
    eq(Placed("Flag on").widget.box:GetChecked(), false, "profile swap refreshes values in place")
    RunTimers()
    ok(Placed("Flag off") and not Placed("Extra"), "profile swap re-renders the page")

    local input = Placed("New name")
    eq(input.widget.box.text, "", "an input whose get is false shows an empty box")
    input.widget.box:SetFocus()
    input.widget.box:SetText("Typing")
    ns.NotifyOptionsChanged()
    eq(input.widget.box.text, "Typing", "a refresh keeps the text of a focused box")
    eq(S().created, nil)
    renders = Win.renders
    RunTimers()
    eq(Win.renders, renders, "no rebuild while an input has focus")
    input.widget.box:ClearFocus()
    RunTimers()
    eq(Win.renders, renders + 1, "rebuild once the input loses focus")

    local modeButton = Placed("Mode").widget.button
    Fire(modeButton, "OnClick")
    local menu
    for _, f in ipairs(frames) do if f.strata == "FULLSCREEN_DIALOG" then menu = f end end
    ok(menu and menu.shown, "dropdown menu opens")
    Fire(modeButton, "OnClick")
    eq(menu.shown, false, "a second click on the dropdown closes its menu")
    Fire(modeButton, "OnClick")
    ok(menu.shown, "a third click opens it again")
    renders = Win.renders
    ns.NotifyOptionsChanged()
    RunTimers()
    eq(Win.renders, renders, "no rebuild while a menu is open")
    ok(menu.shown, "the open menu survives a deferred change")
    Fire(menu, "OnKeyDown", "ESCAPE")
    eq(menu.shown, false, "escape closes the menu first")
    ok(frame.shown, "and not the window")
    RunTimers()
    eq(Win.renders, renders + 1, "rebuild once the menu closes")

    Fire(Placed("Mode").widget.button, "OnClick")
    ok(menu.shown)
    Fire(Win.scroll, "OnMouseWheel", -1)
    eq(menu.shown, false, "scrolling the page closes the menu")
    Fire(Placed("Mode").widget.button, "OnClick")
    Fire(Win.sidebarScroll, "OnMouseWheel", -1)
    eq(menu.shown, false, "scrolling the sidebar closes the menu")
    Fire(Placed("Mode").widget.button, "OnClick")
    ok(menu.shown)

    renders = Win.renders
    ns.CloseOptions()
    eq(menu.shown, false, "hiding the window closes the open menu")
    input.widget.box:SetFocus()
    input.widget.box:SetText("Typing")
    input.widget.box:ClearFocus()
    eq(S().created, nil, "hiding the window does not commit a typed input")
    ns.NotifyOptionsChanged()
    RunTimers()
    eq(Win.renders, renders, "a closed window does not render")

    local entryButton
    for _, f in ipairs(frames) do
        if f.template == "UIPanelButtonTemplate" and f.parent == blizzPanel then entryButton = f end
    end
    ok(entryButton, "Blizzard AddOns entry has a button")
    local panelShown = true
    _G.SettingsPanel = { IsShown = function() return panelShown end, Close = function() panelShown = false end }
    Fire(entryButton, "OnClick")
    eq(panelShown, false, "Blizzard settings close first")
    eq(frame.shown, false, "window opens a frame later")
    RunTimers()
    ok(frame.shown, "Blizzard entry opens the window")

    for i = 1, 40 do
        local key = "Many" .. i
        ns.FEATURE_CLIENTS[key] = "all"
        ns.RegisterFeature({ key = key, title = key, alwaysOn = true, enable = NOOP })
    end
    ns.OpenOptions()
    local content = Win.sidebarContent
    eq(Win.entries[#Win.entries].parent, content, "entries live in the sidebar scroll child")
    ok(content.height > 600, "the sidebar content grows past the window")
    eq(Win.sidebarScroll.child, content)
    Win.sidebarScroll.height = 570
    Fire(Win.sidebarScroll, "OnMouseWheel", -1)
    ok(Win.sidebarScroll.scroll > 0, "the wheel scrolls the sidebar")
    Fire(Win.sidebarScroll, "OnMouseWheel", -1000)
    eq(Win.sidebarScroll.scroll, content.height - 570, "scrolling stops at the last entry")

    local short = false
    local many = {}
    for i = 1, 60 do
        many["t" .. i] = { type = "toggle", order = i, name = "T" .. i, get = NOOP, set = NOOP,
            hidden = function() return short and i > 3 end }
    end
    ns.FEATURE_CLIENTS.WinC = "all"
    ns.RegisterFeature({ key = "WinC", title = "Window C", alwaysOn = true, enable = NOOP,
        options = function() return many end })
    ns.OpenOptions("helpers.WinC")
    eq(Win.pageId, "helpers.WinC")
    ok(Win.content.height > 700, "a long page")
    Win.scroll:SetVerticalScroll(150)
    short = true
    ns.NotifyOptionsChanged()
    RunTimers()
    ok(Win.content.height < 200, "the page got shorter")
    eq(Win.scroll.scroll, 0, "the scroll clamps to the shorter page")
end)

for _, k in ipairs(NAMES) do _G[k] = saved[k] end
ok(ran, tostring(err))
