local _, ns = ...

local KEY = "LayerPrompt"
local TOAST_ADDON = "Blizzard_SocialToast"
local STRATA = "DIALOG"
local WIDTH, HEIGHT = 250, 50
-- Below the TOP -135 StaticPopup, which shares the DIALOG strata.
local DEFAULT = { point = "TOP", relPoint = "TOP", x = 0, y = -320 }

local LP = {}
ns.LayerPrompt = LP

local mover, hooked, watcher
local unlocked = false

local function Settings()
    return ns.GetSettings(KEY)
end

local function Position()
    local pos = Settings().pos
    if type(pos) == "table" and pos.point then return pos end
    return DEFAULT
end

local function Mover()
    if mover then return mover end
    local frame = _G.CreateFrame("Frame", nil, _G.UIParent)
    frame:Hide()
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata(STRATA)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if point then Settings().pos = { point = point, relPoint = relPoint, x = x, y = y } end
        LP.Apply()
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then LP.SetUnlocked(false) end
    end)
    ns.UI.Solid(frame, "BACKGROUND", 0.05, 0.05, 0.05, 0.85):SetAllPoints()
    local r, g, b = ns.UI.Accent()
    ns.UI.Border(frame, r, g, b, 1)
    local label = ns.UI.Font(frame, 12)
    label:SetPoint("CENTER")
    label:SetText("Layer change prompt\nDrag to move, right-click to lock")
    if ns.UI.SkinPanel then ns.UI.SkinPanel(frame) end
    mover = frame
    return frame
end

local function Place(frame)
    local pos = Position()
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, _G.UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
end

function LP.Apply()
    local holder = Mover()
    if not unlocked then Place(holder) end
    local toast = _G.ShardTransferImminentFrame
    if not toast then return end
    toast:ClearAllPoints()
    toast:SetPoint("TOP", holder, "TOP", 0, 0)
    toast:SetFrameStrata(STRATA)
    local minimize = _G.ShardTransferImminentMinimizeButton
    if minimize then minimize:SetFrameStrata(STRATA) end
end

local function Hook()
    local toast = _G.ShardTransferImminentFrame
    if hooked or not toast then return end
    hooked = true
    toast:HookScript("OnShow", LP.Apply)
    LP.Apply()
end

function LP.IsUnlocked()
    return unlocked
end

function LP.SetUnlocked(value)
    unlocked = value and true or false
    local holder = Mover()
    if unlocked then Place(holder) end
    holder:SetShown(unlocked)
    LP.Apply()
    if ns.NotifyOptionsChanged then ns.NotifyOptionsChanged() end
end

function LP.Reset()
    Settings().pos = nil
    Place(Mover())
    LP.Apply()
end

ns.RegisterFeature({
    key = KEY,
    title = "Layer Change Prompt",
    tab = "qol",
    section = "Interface",
    description = "Moves Blizzard's layer change prompt and keeps it above other frames.",
    help = "Puts Blizzard's \"moving you to another layer\" prompt (click it to change layer now) where you want it, above other frames.",
    alwaysOn = true,
    defaults = {},
    enable = function()
        if not _G.CreateFrame then return end
        if _G.ShardTransferImminentFrame then
            Hook()
        elseif not watcher then
            watcher = _G.CreateFrame("Frame")
            watcher:RegisterEvent("ADDON_LOADED")
            watcher:SetScript("OnEvent", function(self, _, name)
                if name ~= TOAST_ADDON then return end
                self:UnregisterEvent("ADDON_LOADED")
                Hook()
            end)
        end
    end,
    options = function()
        return {
            move = {
                type = "execute", order = 1,
                name = function() return unlocked and "Lock position" or "Move prompt" end,
                desc = "Show a box where the prompt appears. Drag it, then lock it here or right-click the box.",
                func = function() LP.SetUnlocked(not unlocked) end,
            },
            reset = {
                type = "execute", order = 2, name = "Reset position",
                desc = "Move the prompt back to the top centre.",
                func = LP.Reset,
            },
        }
    end,
    onReset = function()
        if mover then LP.SetUnlocked(false) end
    end,
})
