local _, ns = ...
local UI = ns.UI
local RP = ns.RoutePlanner

local KEY = "TurnInRoute"
local ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"
local TOOLTIP = "Turn-in Route: click to plan every ready turn-in, right-click for sources and abort."

local T = {}
ns.TurnInRoute = T

local QuestieDB, ZoneDB, DistanceUtils
local mapButton

function T.ReadyWrits(writs, bagCount, onQuest)
    local stops, unknown = {}, 0
    for _, writ in ipairs(writs) do
        local present = bagCount(writ.writID) >= 1 or (onQuest and onQuest(writ.questID))
        if present and bagCount(writ.itemID) >= (writ.qty or 1) then
            if writ.mapID then
                stops[#stops + 1] = {
                    name = writ.npc or "?", mapID = writ.mapID, x = writ.x / 100, y = writ.y / 100,
                    quests = { "Writ: " .. writ.name }, questIds = { writ.questID },
                }
            else
                unknown = unknown + 1
            end
        end
    end
    return stops, unknown
end

function T.WritQuestIds(writs)
    local ids = {}
    for _, writ in ipairs(writs) do ids[writ.questID] = true end
    return ids
end

local QUESTIE_API = {
    { "QuestieDB", "IsComplete" }, { "QuestieDB", "GetQuest" }, { "DistanceUtils", "GetNearestFinisherOrStarter" },
    { "ZoneDB", "GetUiMapIdByAreaId" }, { "HBD", "GetPlayerWorldPosition" }, { "HBD", "GetZoneCoordinatesFromWorld" },
    { "HBD", "GetWorldCoordinatesFromZone" }, { "HBD", "GetAllMapIDs" },
}

function T.MissingQuestieApi(modules)
    for _, api in ipairs(QUESTIE_API) do
        local module = modules[api[1]]
        if type(module) ~= "table" or type(module[api[2]]) ~= "function" then return api[1] .. "." .. api[2] end
    end
end

function T.MenuItems(sources, active)
    local items = { { text = "Plan all", onClick = function() T.Plan(nil) end } }
    for _, source in ipairs(sources) do
        items[#items + 1] = { text = source.title, onClick = function() T.Plan({ source.key }) end }
    end
    if active then items[#items + 1] = { text = "Abort route", onClick = function() RP.Abort() end } end
    return items
end

local function CollectWrits()
    local counts = ns.WritState and ns.WritState.BagCounts and ns.WritState.BagCounts() or {}
    return T.ReadyWrits(ns.Data.Writs or {}, function(id) return counts[id] or 0 end, function(id)
        return C_QuestLog.GetLogIndexForQuestID(id) ~= nil
    end)
end

local function CollectTurnIns()
    local stops, unknown = {}, 0
    local skip = T.WritQuestIds(ns.Data.Writs or {})
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        local id = info and not info.isHeader and info.questID
        local complete = id and id > 0 and not skip[id] and QuestieDB.IsComplete(id)
        if complete == 1 or complete == true then
            local quest = QuestieDB.GetQuest(id)
            local spawn, areaId, name
            if quest and quest.Finisher then
                spawn, areaId, name = DistanceUtils.GetNearestFinisherOrStarter(quest.Finisher)
            end
            local mapID = spawn and areaId and ZoneDB:GetUiMapIdByAreaId(areaId)
            if mapID then
                stops[#stops + 1] = {
                    name = name or "?", mapID = mapID, x = spawn[1] / 100, y = spawn[2] / 100,
                    quests = { info.title or ("Quest " .. id) }, questIds = { id },
                }
            else
                unknown = unknown + 1
            end
        end
    end
    return stops, unknown
end

local function PauseRestedXP()
    local AceAddon = _G.LibStub and _G.LibStub("AceAddon-3.0", true)
    local rxp = AceAddon and AceAddon:GetAddon("RXPGuides", true)
    local profile = rxp and rxp.settings and rxp.settings.profile
    local command = _G.SlashCmdList and _G.SlashCmdList.ACECONSOLE_RXP
    if not (profile and profile.showEnabled and command) then return false end
    UI.Defer("KLH_TurnInRoutePauseRXP", function() command("hide") end)
    return true
end

function T.Plan(keys)
    if not keys then
        keys = {}
        for _, source in ipairs(RP.Sources()) do keys[#keys + 1] = source.key end
    end
    local message, started = RP.PlanSources(keys, ns.GetSettings(KEY))
    if started and PauseRestedXP() then message = message .. " RestedXP paused, /rxp show resumes it." end
    ns.Print(message)
end

local function RouteTurnIns()
    T.Plan(nil)
end

local function CreateMapButton()
    if mapButton then return end
    local lib = _G.LibStub and _G.LibStub("Krowi_WorldMapButtons-1.4", true)
    if not lib then return end
    local b = lib:Add(nil, "Button")
    b:SetSize(32, 32)
    b:SetFrameStrata("HIGH")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(25, 25)
    bg:SetPoint("TOPLEFT", 2, -4)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -6)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    b.Refresh = function() end
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            UI.ContextMenu(b, T.MenuItems(RP.Sources(), RP.Active()))
        else
            RouteTurnIns()
        end
    end)
    b:SetScript("OnEnter", function(self) UI.ShowTooltip(self, TOOLTIP) end)
    b:SetScript("OnLeave", function() UI.HideTooltip() end)
    mapButton = b
    lib.SetPoints()
end

ns.RegisterFeature({
    key = KEY,
    title = "Turn-in Route",
    tab = "helpers",
    description = "Adds a world map button that draws the fastest route to every quest and writ ready to turn in, with flights, ships and zeppelins, optionally your hearthstone and mage teleports, numbered map markers and TomTom waypoints.",
    help = "Plans the fastest route to every quest and writ ready to turn in. Click the checkmark on the world map (right-click to pick Quests or Writs); in the route list, click a stop to point TomTom there, Ctrl+click to drop it.",
    defaults = { useHearth = false, useTeleports = false, waypoints = "add" },
    requires = { "Questie" },
    optional = { "TomTom" },
    optionalReason = "waypoints",
    alwaysOn = true,
    enable = function()
        local loader = _G.QuestieLoader
        if not (loader and loader.ImportModule and _G.WorldMapFrame) then return end
        QuestieDB = loader:ImportModule("QuestieDB")
        ZoneDB = loader:ImportModule("ZoneDB")
        DistanceUtils = loader:ImportModule("DistanceUtils")
        local HBD = loader:ImportModule("HBD")
        local missing = T.MissingQuestieApi({ QuestieDB = QuestieDB, ZoneDB = ZoneDB, DistanceUtils = DistanceUtils, HBD = HBD })
        if missing then
            ns.Print("Turn-in Route: Questie changed (" .. missing .. " missing); route planning is off.")
            return
        end
        RP.RegisterSource("quests", { title = "Quests", order = 1, collect = CollectTurnIns })
        RP.RegisterSource("writs", { title = "Writs", order = 2, collect = CollectWrits })
        RP.Init({ hbd = HBD, onRefresh = RouteTurnIns })
        _G.WorldMapFrame:HookScript("OnShow", CreateMapButton)
        if _G.WorldMapFrame:IsShown() then CreateMapButton() end
    end,
    options = function()
        local function Setting(key, order, name, desc)
            return {
                type = "toggle", order = order, name = name, desc = desc, width = "normal",
                get = function() return ns.GetSettings(KEY)[key] == true end,
                set = function(_, v) ns.GetSettings(KEY)[key] = v == true end,
            }
        end
        return {
            hint = { type = "description", order = 1, fontSize = "medium",
                     name = "Click the checkmark button on the world map to plan every ready turn-in. Right-click it to plan one source or abort." },
            useHearth = Setting("useHearth", 2, "Use Hearthstone",
                "Let the route start with your hearthstone when it is bound, ready and faster."),
            useTeleports = Setting("useTeleports", 3, "Use Mage Teleports",
                "Let the route start with a known mage city teleport when you carry the Rune of Teleportation."),
            waypoints = {
                type = "select", order = 4, name = "TomTom Waypoints",
                desc = function()
                    if ns.AddonLoaded("TomTom") then return "Add keeps your other waypoints. Replace clears them all first." end
                    return ns.RequiresText({ "TomTom" }, ns.AddonTitle)
                end,
                disabled = function() return not ns.AddonLoaded("TomTom") end,
                values = { add = "Add to my waypoints", replace = "Replace my waypoints" }, sorting = { "add", "replace" },
                get = function() return ns.GetSettings(KEY).waypoints or "add" end,
                set = function(_, v) ns.GetSettings(KEY).waypoints = v end,
            },
        }
    end,
})
