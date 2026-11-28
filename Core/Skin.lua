local _, ns = ...
local UI = ns.UI

local skin, registered
local pending = {}

local baseAccent = UI.Accent

function UI.Accent()
    if skin and skin.GetAccentColor then return skin.GetAccentColor() end
    return baseAccent()
end

function UI.Skinned()
    return skin ~= nil
end

local function Apply(kind, frame, opts)
    local fn = skin and skin[kind]
    if fn then pcall(fn, frame, opts) end
end

local function Skin(kind, frame, opts)
    if skin then
        Apply(kind, frame, opts)
    elseif registered then
        pending[#pending + 1] = { kind, frame, opts }
    end
end

function UI.SkinWindow(frame)
    Skin("Shell", frame)
end

function UI.SkinCloseButton(button)
    Skin("CloseButton", button)
end

function UI.SkinButton(button)
    Skin("Button", button)
end

function UI.SkinEditBox(box)
    Skin("EditBox", box)
end

function UI.SkinPanel(frame)
    Skin("Panel", frame)
end

function UI.SkinCheckbox(box, opts)
    Skin("Checkbox", box, opts)
end

function UI.SkinDropdown(button)
    Skin("Dropdown", button)
end

local eui = _G.EllesmereUI
if type(eui) == "table" and type(eui.RegisterSkin) == "function" then
    registered = true
    eui.RegisterSkin("KlausisLittleHelpers", function(S)
        skin = S
        for _, p in ipairs(pending) do Apply(p[1], p[2], p[3]) end
        pending = {}
    end)
end
