local combat, handler = true, nil
local saved = {}
for _, k in ipairs({ "InCombatLockdown", "geterrorhandler", "CreateFrame" }) do saved[k] = rawget(_G, k) end
_G.InCombatLockdown = function() return combat end
_G.geterrorhandler = function() return print end
_G.CreateFrame = function()
    return {
        RegisterEvent = function() end,
        SetScript = function(_, _, fn) handler = fn end,
    }
end
addon("Core/UI.lua")
eq(ns.UI.FormatMoney(1234567), "123g 46s")
eq(ns.UI.FormatMoney(12345), "1g 23s")
eq(ns.UI.FormatMoney(1234), "12s 34c")
eq(ns.UI.FormatMoney(5), "5c")
eq(ns.UI.FormatMoney(12345678), "1,234g 57s")
eq(ns.UI.FormatMoney(19999), "2g 00s")
eq(ns.UI.FormatMoney(nil), "0c")
local calls = {}
ns.UI.Defer("a", function() calls[#calls + 1] = "a1" end)
ns.UI.Defer("a", function() calls[#calls + 1] = "a2" end)
ns.UI.Defer("b", function() calls[#calls + 1] = "b" end)
eq(#calls, 0, "deferred in combat")
combat = false
handler()
eq(table.concat(calls, ","), "a2,b", "latest per key runs once")
handler()
eq(#calls, 2, "queue drained")
ns.UI.Defer("c", function() calls[#calls + 1] = "c" end)
eq(calls[3], "c", "runs now out of combat")
local r, g, b = ns.UI.Accent()
eq(r, 0.05); eq(g, 0.82); eq(b, 0.62)
for k, v in pairs(saved) do _G[k] = v end

do
    local savedTexture = rawget(_G, "C_Texture")
    local function Tex()
        local t = {}
        t.SetAtlas = function(self, name) self.atlas = name end
        t.SetTexture = function(self, file) self.file = file end
        return t
    end
    _G.C_Texture = { GetAtlasInfo = function(name) return name == "common-dropdown-classic-a-buttonDown" and {} or nil end }
    local t = Tex()
    eq(ns.UI.SetArrowTexture(t), "common-dropdown-classic-a-buttonDown", "first atlas the client has")
    eq(t.atlas, "common-dropdown-classic-a-buttonDown")
    _G.C_Texture = { GetAtlasInfo = function() return nil end }
    t = Tex()
    eq(ns.UI.SetArrowTexture(t), "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up", "file fallback without the atlases")
    eq(t.atlas, nil); ok(t.file ~= nil)
    _G.C_Texture = savedTexture
end

do
    local savedTip = rawget(_G, "GameTooltip")
    local tipCalls = {}
    local tip = setmetatable({}, { __index = function(_, k)
        return function(_, ...) tipCalls[#tipCalls + 1] = { k, ... } end
    end })
    _G.GameTooltip = tip
    ns.UI.ShowItemTooltip("owner", 248699, "Fill each with 20 Dream Dust.")
    local names = {}
    for _, c in ipairs(tipCalls) do names[#names + 1] = c[1] end
    local seq = table.concat(names, ",")
    ok(seq:find("SetOwner,SetItemByID,AddLine,AddLine,Show", 1, true), "item tooltip, then our hint below it: " .. seq)
    local set
    for _, c in ipairs(tipCalls) do if c[1] == "SetItemByID" then set = c[2] end end
    eq(set, 248699)
    eq(tipCalls[#tipCalls - 1][2], "Fill each with 20 Dream Dust.")
    tipCalls = {}
    ns.UI.ShowItemTooltip("owner", 1)
    local adds = 0
    for _, c in ipairs(tipCalls) do if c[1] == "AddLine" then adds = adds + 1 end end
    eq(adds, 0, "no hint, no extra lines")
    tipCalls = {}
    ns.UI.ShowLinesTooltip("button", { { left = "x" } }, true)
    eq(tipCalls[1][1], "SetOwner"); eq(tipCalls[1][3], "ANCHOR_NONE")
    local point
    for _, c in ipairs(tipCalls) do if c[1] == "SetPoint" then point = c end end
    ok(point and point[2] == "TOPLEFT" and point[3] == "button" and point[4] == "BOTTOMLEFT", "below the owner, left edges aligned")
    tipCalls = {}
    ns.UI.ShowLinesTooltip("button", { { left = "x" } })
    eq(tipCalls[1][3], "ANCHOR_RIGHT", "to the right by default")
    _G.GameTooltip = savedTip
end

do
    local oldMenu = _G.MenuUtil
    local titles, radios, buttons, clicked = {}, {}, {}, false
    _G.MenuUtil = { CreateContextMenu = function(_, build)
        build(nil, {
            CreateTitle = function(_, text) titles[#titles + 1] = text end,
            CreateRadio = function(_, text) radios[#radios + 1] = text end,
            CreateButton = function(_, text, fn) buttons[#buttons + 1] = { text, fn } end,
        })
    end }
    ns.UI.ContextMenu({}, { { text = "Empty", title = true }, { text = "Action", onClick = function() clicked = true end },
        { text = "Choice", isActive = false } })
    eq(titles[1], "Empty")
    eq(buttons[1][1], "Action", "plain actions are buttons, not radios"); eq(#buttons, 1)
    buttons[1][2](); ok(clicked, "the button runs its action")
    eq(radios[1], "Choice", "only items with a selected state are radios"); eq(#radios, 1)
    _G.MenuUtil = oldMenu
end

do
    local oldFrame, oldMenu = _G.CreateFrame, _G.MenuUtil
    local made = {}
    _G.MenuUtil = nil
    _G.CreateFrame = function(kind)
        local frame = { kind = kind, scripts = {} }
        setmetatable(frame, { __index = function(_, key)
            if key == "SetScript" then return function(self, event, fn) self.scripts[event] = fn end end
            if key == "EnableMouse" then return function(self, enabled) self.mouse = enabled end end
            if key == "Show" then return function(self)
                local was = self.shown
                self.shown = true
                if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
            end end
            if key == "Hide" then return function(self)
                local was = self.shown
                self.shown = false
                if was and self.scripts.OnHide then self.scripts.OnHide(self) end
            end end
            if key == "IsShown" then return function(self) return self.shown == true end end
            if key == "IsMouseOver" then return function(self) return self.over == true end end
            if key == "EnableKeyboard" then return function(self, on) self.keyboard = on end end
            if key == "SetPropagateKeyboardInput" then return function(self, on) self.propagate = on end end
            if key == "SetSize" then return function(self, w, h) self.w, self.h = w, h end end
            if key == "CreateFontString" then return function()
                local fs = {}
                fs.SetWidth = function(self, w) self.width = w end
                fs.SetWordWrap = function(self, on) self.wrap = on end
                fs.SetText = function(self, t) self.text = t end
                return setmetatable(fs, { __index = function() return function() end end })
            end end
            if key == "CreateTexture" then return function() return setmetatable({}, { __index = function() return function() end end }) end end
            return function() end
        end })
        made[#made + 1] = frame
        return frame
    end
    local owner = { GetWidth = function() return 120 end, IsMouseOver = function(self) return self.over == true end }
    ns.UI.ContextMenu(owner, { { text = "Empty", title = true } })
    eq(made[2].mouse, false, "a title takes no clicks")
    made[2].scripts.OnClick(made[2])
    eq(made[1].shown, true, "clicking a title does not close the menu")
    local hits = 0
    ns.UI.ContextMenu(owner, { { text = "Action", onClick = function() hits = hits + 1 end } })
    eq(made[2].mouse, true)
    made[2].scripts.OnClick(made[2])
    eq(hits, 1, "an action runs"); eq(made[1].shown, false, "and closes the menu")

    local many, picked = {}, nil
    for i = 1, 50 do many[i] = { text = "Item " .. i, onClick = function() picked = i end } end
    ns.UI.DropdownMenu(owner, many)
    local menu = made[1]
    eq(menu.h, 20 * 20 + 2, "a long menu is capped at twenty rows")
    eq(made[22], nil, "only twenty buttons are made")
    menu.scripts.OnMouseWheel(menu, -3)
    made[2].scripts.OnClick(made[2])
    eq(picked, 4, "the wheel scrolls the rows")
    ns.UI.DropdownMenu(owner, many)
    menu.scripts.OnMouseWheel(menu, -100)
    made[21].scripts.OnClick(made[21])
    eq(picked, 50, "scrolling stops at the last item")
    ns.UI.DropdownMenu(owner, many)
    ns.UI.CloseMenus()
    eq(menu.shown, false, "CloseMenus hides the menu")

    local closed = 0
    ns.UI.OnMenuClosed(function() closed = closed + 1 end)
    local two = { { text = "A very long entry that does not fit the menu" }, { text = "B" } }
    ns.UI.DropdownMenu(owner, two)
    eq(menu.shown, true)
    eq(made[2].text.width, 120 - 16, "item text is limited to the menu width")
    eq(made[2].text.wrap, false, "item text does not wrap")
    eq(ns.UI.IsMenuOpen(owner), true); eq(ns.UI.IsMenuOpen({}), false, "open for its owner only")
    owner.over = true
    menu.scripts.OnEvent(menu, "GLOBAL_MOUSE_DOWN")
    eq(menu.shown, true, "a mouse down on the owner leaves the menu to its click")
    ns.UI.DropdownMenu(owner, two)
    eq(menu.shown, false, "a second click on the owner closes the menu")
    eq(closed, 1, "closing runs the menu closed handlers")
    owner.over = false
    ns.UI.DropdownMenu(owner, {})
    eq(menu.shown, false, "an empty dropdown opens no menu")
    ns.UI.DropdownMenu(owner, two)
    menu.scripts.OnEvent(menu, "GLOBAL_MOUSE_DOWN")
    eq(menu.shown, false, "a mouse down elsewhere closes the menu")

    ns.UI.DropdownMenu(owner, two)
    eq(menu.keyboard, true, "an open menu takes keys")
    eq(menu.propagate, true, "and passes them on")
    menu.scripts.OnKeyDown(menu, "W")
    eq(menu.shown, true); eq(menu.propagate, true, "other keys pass through")
    menu.scripts.OnKeyDown(menu, "ESCAPE")
    eq(menu.shown, false, "escape closes the menu")
    eq(menu.propagate, false, "and does not reach the window")
    eq(menu.keyboard, false, "a closed menu takes no keys")
    _G.CreateFrame, _G.MenuUtil = oldFrame, oldMenu
end
