local _, ns = ...

local V = {}
ns.RouteView = V

local MARKER_SIZE = 22
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local LINE_THICKNESS = 3
local LINE_FRAME_LEVEL = 1500
local GROUND_COLOR = { 1, 0.82, 0, 0.9 }
local FLIGHT_COLOR = { 0.4, 0.73, 1, 0.9 }
local BOAT_COLOR = { 0.3, 0.9, 0.8, 0.9 }
local PINS_REF = "KLH_TurnInRoute"

local UI, HBD, Pins
local lineFrame
local markers = {}
local lines = {}
local drawPending = false
local legs = {}
local RouteStart = function() return nil end

function V.Attach(routeLegs, routeStart)
    legs, RouteStart = routeLegs, routeStart
end

local function Disc(marker, sublevel, r, g, b)
    local tex = marker:CreateTexture(nil, "ARTWORK", nil, sublevel)
    tex:SetPoint("CENTER")
    tex:SetColorTexture(r, g, b, 1)
    local mask = marker:CreateMaskTexture()
    mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
    return tex
end

local function Marker(slot, text)
    local marker = markers[slot]
    if not marker then
        marker = CreateFrame("Frame", nil, UIParent)
        marker.discs = {
            { Disc(marker, 1, 0.05, 0.04, 0.03), 0 },
            { Disc(marker, 2, 1, 0.82, 0), 2 },
            { Disc(marker, 3, 0.1, 0.09, 0.08), 5 },
        }
        marker.label = UI.Font(marker, 9, 1, 1, 1)
        marker.label:SetShadowOffset(1, -1)
        marker.label:SetShadowColor(0, 0, 0, 1)
        marker.label:SetPoint("CENTER", marker, "CENTER", 0, 0)
        markers[slot] = marker
    end
    marker.label:SetText(text)
    local w = math.max(MARKER_SIZE, math.ceil(marker.label:GetStringWidth()) + 12)
    marker:SetSize(w, MARKER_SIZE)
    for _, disc in ipairs(marker.discs) do disc[1]:SetSize(w - disc[2], MARKER_SIZE - disc[2]) end
    return marker
end

local function MarkerText(numbers)
    local first, last = numbers[1], numbers[#numbers]
    if #numbers >= 3 and last - first + 1 == #numbers then return first .. "-" .. last end
    return table.concat(numbers, "/")
end

local function PlaceMarkers(mapID, mapInstance, w, h, scale)
    local radius = (MARKER_SIZE + 2) / scale
    local clusters = {}
    for _, leg in ipairs(legs) do
        local stop = leg.stop
        if not leg.done and stop.instance == mapInstance then
            local x, y = HBD:GetZoneCoordinatesFromWorld(stop.wx, stop.wy, mapID)
            if x then
                local cx, cy, home = x * w, y * h, nil
                for _, cluster in ipairs(clusters) do
                    local dx, dy = cluster.cx - cx, cluster.cy - cy
                    if dx * dx + dy * dy < radius * radius then
                        home = cluster
                        break
                    end
                end
                if home then
                    home.numbers[#home.numbers + 1] = leg.number
                else
                    clusters[#clusters + 1] = { x = x, y = y, cx = cx, cy = cy, numbers = { leg.number } }
                end
            end
        end
    end
    for slot, cluster in ipairs(clusters) do
        Pins:AddWorldMapIconMap(PINS_REF, Marker(slot, MarkerText(cluster.numbers)), mapID, cluster.x, cluster.y,
            0, "PIN_FRAME_LEVEL_TOPMOST")
    end
end

local function Line(i)
    local line = lines[i]
    if not line then
        line = lineFrame:CreateLine(nil, "OVERLAY")
        lines[i] = line
    end
    line:Show()
    return line
end

function V.Draw()
    if Pins then Pins:RemoveAllWorldMapIcons(PINS_REF) end
    if not lineFrame then return end
    for _, line in ipairs(lines) do line:Hide() end
    if not (RouteStart() and _G.WorldMapFrame:IsShown()) then return end
    local mapID = _G.WorldMapFrame:GetMapID()
    local _, _, mapInstance = HBD:GetWorldCoordinatesFromZone(0.5, 0.5, mapID)
    if not mapInstance then return end
    local w, h = lineFrame:GetSize()
    local scale = _G.WorldMapFrame.ScrollContainer:GetCanvasScale() or 1
    if scale <= 0 then scale = 1 end
    local thickness = LINE_THICKNESS / scale
    local used = 0
    local function Segment(ax, ay, bx, by, color)
        local x1, y1 = HBD:GetZoneCoordinatesFromWorld(ax, ay, mapID, true)
        local x2, y2 = HBD:GetZoneCoordinatesFromWorld(bx, by, mapID, true)
        if not (x1 and x2) then return end
        used = used + 1
        local line = Line(used)
        line:SetThickness(thickness)
        line:SetColorTexture(color[1], color[2], color[3], color[4])
        line:SetStartPoint("TOPLEFT", lineFrame, x1 * w, -y1 * h)
        line:SetEndPoint("TOPLEFT", lineFrame, x2 * w, -y2 * h)
    end
    local function Here(point) return point.instance == mapInstance end
    for _, leg in ipairs(legs) do
        if not leg.done then
            for _, step in ipairs(leg.steps) do
                local from, to = step.from, step.to
                if step.kind == "flight" and Here(from) then
                    for k = 1, #step.hops - 1 do
                        local path = ns.TaxiPaths[step.hops[k]] and ns.TaxiPaths[step.hops[k]][step.hops[k + 1]]
                        local curve = path and path[3] or {}
                        for p = 1, #curve - 3, 2 do
                            Segment(curve[p], curve[p + 1], curve[p + 2], curve[p + 3], FLIGHT_COLOR)
                        end
                    end
                elseif step.kind == "boat" and Here(from) and Here(to) then
                    Segment(from.wx, from.wy, to.wx, to.wy, BOAT_COLOR)
                elseif step.kind == "ground" and Here(from) then
                    Segment(from.wx, from.wy, to.wx, to.wy, GROUND_COLOR)
                end
            end
        end
    end
    if Pins then PlaceMarkers(mapID, mapInstance, w, h, scale) end
end

function V.QueueDraw()
    if drawPending then return end
    drawPending = true
    C_Timer.After(0, function()
        drawPending = false
        V.Draw()
    end)
end

local function FindPins()
    Pins = _G.LibStub and _G.LibStub("HereBeDragons-Pins-2.0", true)
    local loader = _G.QuestieLoader
    if not Pins and loader and type(loader.ImportModule) == "function" then
        local questiePins = loader:ImportModule("HBDPins")
        if type(questiePins) == "table" and type(questiePins.AddWorldMapIconMap) == "function" then Pins = questiePins end
    end
end

function V.Init(ui, hbd)
    UI, HBD = ui, hbd
    FindPins()
    local canvas = _G.WorldMapFrame.ScrollContainer and _G.WorldMapFrame.ScrollContainer.Child
    if canvas then
        lineFrame = CreateFrame("Frame", nil, canvas)
        lineFrame:SetAllPoints(canvas)
        lineFrame:SetFrameLevel(LINE_FRAME_LEVEL)
        for _, method in ipairs({ "OnMapChanged", "OnCanvasScaleChanged", "OnFrameSizeChanged" }) do
            if _G.WorldMapFrame[method] then hooksecurefunc(_G.WorldMapFrame, method, V.QueueDraw) end
        end
        _G.WorldMapFrame:HookScript("OnShow", V.QueueDraw)
    end
end
