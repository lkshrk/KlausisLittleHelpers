local _, ns = ...

local name = "KlausisLittleHelpers"
local iconPath = "Interface\\Icons\\INV_Pet_MechanicalSquirrel"
local tooltipLines = { "Klausi's Little Helpers", "Left-click: settings", "Right-click: helpers", "Drag: move" }
local compartmentFrame
local icon

local function Settings()
    local settings = ns.GetSettings("MinimapButton")
    settings.hide = nil
    return settings
end

local function OnClick(frame, button)
    if button == "LeftButton" then
        ns.OpenOptions()
    elseif button == "RightButton" then
        local items = ns.Launchers()
        if #items == 0 then items = { { text = "No helpers available", title = true } } end
        ns.UI.ContextMenu(frame, items)
    end
end

function KLH_OnAddonCompartmentClick(_, button)
    if not ns.IsRunning("MinimapButton") then return end
    OnClick(_G.AddonCompartmentFrame or compartmentFrame, button)
end

function KLH_OnAddonCompartmentEnter(_, frame)
    if not ns.IsRunning("MinimapButton") then return end
    compartmentFrame = frame
    local lines = {}
    for i, text in ipairs(tooltipLines) do lines[i] = { left = text, header = i == 1 } end
    ns.UI.ShowLinesTooltip(frame, lines)
end

function KLH_OnAddonCompartmentLeave()
    if not ns.IsRunning("MinimapButton") then return end
    ns.UI.HideTooltip()
end

ns.RegisterFeature({
    key = "MinimapButton",
    title = "Minimap Button",
    description = "Adds a minimap button for settings and helpers.",
    help = "A round button on the minimap: left-click opens these settings, right-click lists the helpers you can open. Drag it along the minimap edge to move it.",
    tab = "qol",
    alwaysOn = true,
    enable = function()
        local ldb = _G.LibStub("LibDataBroker-1.1", true)
        local dbIcon = _G.LibStub("LibDBIcon-1.0", true)
        if not ldb or not dbIcon then return end
        icon = dbIcon
        local object = ldb:NewDataObject(name, {
            type = "launcher",
            icon = iconPath,
            OnClick = OnClick,
            OnTooltipShow = function(tt)
                for _, text in ipairs(tooltipLines) do tt:AddLine(text, 1, 1, 1) end
            end,
        })
        icon:Register(name, object, Settings())
    end,
    onReset = function()
        if icon then icon:Refresh(name, Settings()) end
    end,
})
