local names = { "LibStub", "AddonCompartmentFrame", "KLH_OnAddonCompartmentClick", "KLH_OnAddonCompartmentEnter", "KLH_OnAddonCompartmentLeave" }
local saved = {}
for _, name in ipairs(names) do saved[name] = rawget(_G, name) end
local oldNS = ns
local good, problem = pcall(function()
    local spec, object, db, menuOwner, menuItems, shownTooltip, hiddenTooltip
    local calls, settings, opened = {}, { hide = true }, 0
    local running = false
    local ldb = { NewDataObject = function(_, name, obj) eq(name, "KlausisLittleHelpers"); object = obj; return obj end }
    local icon = {}
    for _, method in ipairs({ "Register", "Show", "Hide", "Refresh" }) do
        icon[method] = function(_, name, obj, data) calls[method] = { name, obj, data }; if method == "Register" then db = data end end
    end
    _G.LibStub = function(name, silent)
        ok(silent)
        if name == "LibDataBroker-1.1" then return ldb end
        if name == "LibDBIcon-1.0" then return icon end
    end
    ns = {
        RegisterFeature = function(s) spec = s end,
        IsRunning = function() return running end,
        GetSettings = function(key) eq(key, "MinimapButton"); return settings end,
        OpenOptions = function() opened = opened + 1 end,
        Launchers = function() return { { text = "Example", onClick = function() end } } end,
        UI = {
            ContextMenu = function(owner, items) menuOwner, menuItems = owner, items end,
            ShowLinesTooltip = function(owner, lines) shownTooltip = { owner, lines } end,
            HideTooltip = function() hiddenTooltip = true end,
        },
    }
    addon("Modules/MinimapButton.lua")
    eq(spec.tab, "qol"); ok(spec.alwaysOn); eq(spec.options, nil, "no settings: the button is always shown")
    _G.KLH_OnAddonCompartmentEnter(nil, {})
    _G.KLH_OnAddonCompartmentClick(nil, "LeftButton")
    _G.KLH_OnAddonCompartmentClick(nil, "RightButton")
    _G.KLH_OnAddonCompartmentLeave()
    eq(shownTooltip, nil); eq(hiddenTooltip, nil); eq(opened, 0)
    eq(menuItems, nil, "compartment inactive when the feature did not start")
    running = true
    spec.enable()
    eq(calls.Register[1], "KlausisLittleHelpers")
    eq(object.type, "launcher"); eq(object.icon, "Interface\\Icons\\INV_Pet_MechanicalSquirrel"); eq(db, settings); eq(settings.hide, nil, "registering clears an old hide flag")
    local frame = {}
    object.OnClick(frame, "LeftButton"); eq(opened, 1)
    object.OnClick(frame, "RightButton"); eq(menuOwner, frame); eq(menuItems[1].text, "Example")
    ns.Launchers = function() return {} end
    object.OnClick(frame, "RightButton"); eq(menuItems[1].text, "No helpers available"); eq(menuItems[1].onClick, nil)
    eq(menuItems[1].title, true)
    local lines = {}
    object.OnTooltipShow({ AddLine = function(_, text) lines[#lines + 1] = text end })
    eq(table.concat(lines, "|"), "Klausi's Little Helpers|Left-click: settings|Right-click: helpers|Drag: move")
    settings = { hide = true, minimapPos = 90 }; spec.onReset()
    eq(calls.Refresh[2], settings); eq(settings.hide, nil, "a button hidden before comes back"); eq(settings.minimapPos, 90)
    _G.KLH_OnAddonCompartmentEnter(nil, frame); eq(shownTooltip[1], frame); eq(#shownTooltip[2], 4)
    _G.KLH_OnAddonCompartmentClick("KlausisLittleHelpers", "LeftButton"); eq(opened, 2)
    _G.KLH_OnAddonCompartmentClick("KlausisLittleHelpers", "RightButton"); eq(menuOwner, frame, "falls back to the hovered row")
    _G.AddonCompartmentFrame = {}
    _G.KLH_OnAddonCompartmentClick("KlausisLittleHelpers", "RightButton"); eq(menuOwner, _G.AddonCompartmentFrame, "anchors to the compartment button, which outlives its menu rows")
    _G.KLH_OnAddonCompartmentLeave(); ok(hiddenTooltip)
    object = nil; icon = nil; spec.enable(); eq(object, nil)
end)
ns = oldNS
for _, name in ipairs(names) do _G[name] = saved[name] end
if not good then error(problem, 0) end
