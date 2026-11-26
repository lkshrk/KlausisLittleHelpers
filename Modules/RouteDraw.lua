local _, ns = ...

local V = {}
ns.RouteView = V

local MARKER_SIZE = 22
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local LINE_THICKNESS = 3
local LINE_FRAME_LEVEL = 1500
local MAX_FRAME_LEVEL = 9900
local DOT_LENGTH, DOT_GAP = 4, 5
local CLIP_MARGIN = 50
local BOW, BOW_PIECES = 0.1, 16
local GROUND_COLOR = { 1, 0.82, 0, 0.9 }
local FLIGHT_COLOR = { 0.4, 0.73, 1, 0.9 }
local BOAT_COLOR = { 0.3, 0.9, 0.8, 0.9 }
local UI, HBD
local lineFrame, markerFrame
local markers = {}
local lines = {}
local drawPending = false
local raisedMap
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
        marker = CreateFrame("Frame", nil, markerFrame)
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

-- Converts with the point's own instance: the Azeroth world map shows several continents at once.
local function ToMap(wx, wy, instance, mapID, outOfBounds)
    if HBD.GetZoneCoordinatesFromWorldInstance then
        return HBD:GetZoneCoordinatesFromWorldInstance(wx, wy, instance, mapID, outOfBounds)
    end
    if instance ~= nil and instance ~= select(3, HBD:GetWorldCoordinatesFromZone(0.5, 0.5, mapID)) then return nil end
    return HBD:GetZoneCoordinatesFromWorld(wx, wy, mapID, outOfBounds)
end

function V.Clip(x1, y1, x2, y2, minX, minY, maxX, maxY)
    local t0, t1 = 0, 1
    local dx, dy = x2 - x1, y2 - y1
    local edges = { { -dx, x1 - minX }, { dx, maxX - x1 }, { -dy, y1 - minY }, { dy, maxY - y1 } }
    for _, e in ipairs(edges) do
        local p, q = e[1], e[2]
        if p == 0 then
            if q < 0 then return nil end
        else
            local t = q / p
            if p < 0 then
                if t > t1 then return nil end
                if t > t0 then t0 = t end
            else
                if t < t0 then return nil end
                if t < t1 then t1 = t end
            end
        end
    end
    return t0, t1
end

local function PlaceMarkers(mapID, w, h, scale)
    local radius = (MARKER_SIZE + 2) / scale
    local clusters = {}
    for _, leg in ipairs(legs) do
        local stop = leg.stop
        if not leg.done then
            local x, y = ToMap(stop.wx, stop.wy, stop.instance, mapID)
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
        local marker = Marker(slot, MarkerText(cluster.numbers))
        -- Kept at a constant screen size; offsets are in the marker's own (scaled) units.
        marker:SetScale(1 / scale)
        marker:ClearAllPoints()
        marker:SetPoint("CENTER", markerFrame, "TOPLEFT", cluster.cx * scale, -cluster.cy * scale)
        marker:Show()
    end
end

-- Other map addons stack their frames high on the canvas; the route stays above all of them.
local function RaiseLayers(canvas)
    local top = LINE_FRAME_LEVEL
    for _, child in ipairs({ canvas:GetChildren() }) do
        if child ~= lineFrame and child ~= markerFrame and child:GetFrameLevel() > top then top = child:GetFrameLevel() end
    end
    local level = math.min(top + 10, MAX_FRAME_LEVEL)
    lineFrame:SetFrameLevel(level)
    markerFrame:SetFrameLevel(level + 5)
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
    if not lineFrame then return end
    for _, marker in ipairs(markers) do marker:Hide() end
    for _, line in ipairs(lines) do line:Hide() end
    if not (RouteStart() and _G.WorldMapFrame:IsShown()) then return end
    local mapID = _G.WorldMapFrame:GetMapID()
    if not mapID then return end
    if mapID ~= raisedMap then
        RaiseLayers(_G.WorldMapFrame.ScrollContainer.Child)
        raisedMap = mapID
    end
    local w, h = lineFrame:GetSize()
    local scale = _G.WorldMapFrame.ScrollContainer:GetCanvasScale() or 1
    if scale <= 0 then scale = 1 end
    local thickness = LINE_THICKNESS / scale
    local used = 0
    local function Piece(x1, y1, x2, y2, color)
        used = used + 1
        local line = Line(used)
        line:SetThickness(thickness)
        line:SetColorTexture(color[1], color[2], color[3], color[4])
        line:SetStartPoint("TOPLEFT", lineFrame, x1, -y1)
        line:SetEndPoint("TOPLEFT", lineFrame, x2, -y2)
    end
    local dot, gap, margin = DOT_LENGTH / scale, DOT_GAP / scale, CLIP_MARGIN / scale
    local phase = 0
    local function Segment(ax, ay, bx, by, color, dotted, instance, toInstance)
        local x1, y1 = ToMap(ax, ay, instance, mapID, true)
        local x2, y2 = ToMap(bx, by, toInstance or instance, mapID, true)
        if not (x1 and x2) then return end
        x1, y1, x2, y2 = x1 * w, y1 * h, x2 * w, y2 * h
        if not dotted then return Piece(x1, y1, x2, y2, color) end
        local dx, dy = x2 - x1, y2 - y1
        local len = math.sqrt(dx * dx + dy * dy)
        if len == 0 then return end
        local period = dot + gap
        local t0, t1 = V.Clip(x1, y1, x2, y2, -margin, -margin, w + margin, h + margin)
        if not t0 then
            phase = (phase + len) % period
            return
        end
        local pos, stop = t0 * len, t1 * len
        phase = (phase + pos) % period
        -- The phase carries over between path segments so dots stay evenly spaced along a curve.
        while pos < stop do
            local left = phase < dot and dot - phase or period - phase
            local step = math.min(left, stop - pos)
            if phase < dot then
                local s, e = pos / len, (pos + step) / len
                Piece(x1 + dx * s, y1 + dy * s, x1 + dx * e, y1 + dy * e, color)
            end
            pos, phase = pos + step, (phase + step) % period
        end
        phase = (phase + len - stop) % period
    end
    -- Ground legs have no known path; the bow only sets them apart from the straight transit lines.
    local function Bow(ax, ay, bx, by, color, instance, toInstance)
        local x1, y1 = ToMap(ax, ay, instance, mapID, true)
        local x2, y2 = ToMap(bx, by, toInstance or instance, mapID, true)
        if not (x1 and x2) then return end
        x1, y1, x2, y2 = x1 * w, y1 * h, x2 * w, y2 * h
        local dx, dy = x2 - x1, y2 - y1
        local cx, cy = (x1 + x2) / 2 + dy * BOW * 2, (y1 + y2) / 2 - dx * BOW * 2
        local px, py = x1, y1
        for i = 1, BOW_PIECES do
            local t = i / BOW_PIECES
            local u = 1 - t
            local qx = u * u * x1 + 2 * u * t * cx + t * t * x2
            local qy = u * u * y1 + 2 * u * t * cy + t * t * y2
            Piece(px, py, qx, qy, color)
            px, py = qx, qy
        end
    end
    local function Here(point) return ToMap(point.wx or 0, point.wy or 0, point.instance, mapID, true) ~= nil end
    for _, leg in ipairs(legs) do
        if not leg.done then
            for _, step in ipairs(leg.steps) do
                local from, to = step.from, step.to
                if step.kind == "flight" and Here(from) then
                    phase = 0
                    for k = 1, #step.hops - 1 do
                        local path = ns.TaxiPaths[step.hops[k]] and ns.TaxiPaths[step.hops[k]][step.hops[k + 1]]
                        local curve = path and path[3] or {}
                        for p = 1, #curve - 3, 2 do
                            Segment(curve[p], curve[p + 1], curve[p + 2], curve[p + 3], FLIGHT_COLOR, true, from.instance)
                        end
                    end
                elseif step.kind == "boat" and Here(from) and Here(to) then
                    phase = 0
                    Segment(from.wx, from.wy, to.wx, to.wy, BOAT_COLOR, true, from.instance, to.instance)
                elseif step.kind == "ground" and Here(from) then
                    Bow(from.wx, from.wy, to.wx, to.wy, GROUND_COLOR, from.instance, to.instance)
                end
            end
        end
    end
    PlaceMarkers(mapID, w, h, scale)
end

function V.QueueDraw()
    if drawPending then return end
    drawPending = true
    C_Timer.After(0, function()
        drawPending = false
        V.Draw()
    end)
end

function V.Init(ui, hbd)
    UI, HBD = ui, hbd
    local canvas = _G.WorldMapFrame.ScrollContainer and _G.WorldMapFrame.ScrollContainer.Child
    if canvas then
        lineFrame = CreateFrame("Frame", nil, canvas)
        lineFrame:SetAllPoints(canvas)
        lineFrame:SetFrameLevel(LINE_FRAME_LEVEL)
        markerFrame = CreateFrame("Frame", nil, canvas)
        markerFrame:SetAllPoints(canvas)
        markerFrame:SetFrameLevel(LINE_FRAME_LEVEL + 5)
        for _, method in ipairs({ "OnMapChanged", "OnCanvasScaleChanged", "OnFrameSizeChanged" }) do
            if _G.WorldMapFrame[method] then hooksecurefunc(_G.WorldMapFrame, method, V.QueueDraw) end
        end
        _G.WorldMapFrame:HookScript("OnShow", function()
            raisedMap = nil
            V.QueueDraw()
        end)
    end
end
