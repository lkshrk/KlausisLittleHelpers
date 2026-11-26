local names = { "CreateFrame", "UIParent", "WorldMapFrame", "hooksecurefunc", "C_Timer", "LibStub", "QuestieLoader" }
local saved = {}
for _, k in ipairs(names) do saved[k] = rawget(_G, k) end

local made = {}
local function Line()
    local l = { shown = true }
    function l:Show() self.shown = true end
    function l:Hide() self.shown = false end
    function l:SetThickness(t) self.thickness = t end
    function l:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function l:SetStartPoint(_, _, x, y) self.x1, self.y1 = x, y end
    function l:SetEndPoint(_, _, x, y) self.x2, self.y2 = x, y end
    made[#made + 1] = l
    return l
end
local frames = {}
local function Stub()
    return setmetatable({}, { __index = function() return function() end end })
end
local function Frame()
    local f = { level = 0, points = {}, shown = true }
    function f:SetAllPoints() end
    function f:SetFrameLevel(l) self.level = l end
    function f:GetFrameLevel() return self.level end
    function f:GetSize() return 1000, 1000 end
    function f:CreateLine() return Line() end
    function f:GetChildren() return unpack(self.children or {}) end
    function f:CreateTexture() return Stub() end
    function f:CreateMaskTexture() return Stub() end
    function f:SetSize() end
    function f:SetScale(s) self.scale = s end
    function f:ClearAllPoints() self.points = {} end
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    frames[#frames + 1] = f
    return f
end
_G.CreateFrame = function() return Frame() end
_G.UIParent = Frame()
_G.hooksecurefunc = function() end
_G.C_Timer = { After = function(_, fn) fn() end }
_G.LibStub = nil
_G.QuestieLoader = nil
_G.WorldMapFrame = {
    ScrollContainer = { Child = Frame(), GetCanvasScale = function() return 1 end },
    IsShown = function() return true end,
    GetMapID = function() return 1 end,
    HookScript = function(self, _, fn) self.onShow = fn end,
}

local good, problem = pcall(function()
    addon("Modules/RouteDraw.lua")
    local V = ns.RouteView
    local hbd = {
        GetWorldCoordinatesFromZone = function() return 0, 0, 0 end,
        GetZoneCoordinatesFromWorld = function(_, x, y) return x / 1000, y / 1000 end,
    }
    local function Label()
        local l = Stub()
        local mt = getmetatable(l)
        mt.__index = function(_, k)
            if k == "GetStringWidth" then return function() return 10 end end
            return function() end
        end
        return l
    end
    local before = #frames
    V.Init({ Font = Label }, hbd)
    local lineLayer, markerLayer = frames[before + 1], frames[before + 2]
    local other = Frame()
    other:SetFrameLevel(2923)
    _G.WorldMapFrame.ScrollContainer.Child.children = { other, lineLayer, markerLayer }
    ns.TaxiPaths = { [1] = { [2] = { 0, 0, { 0, 0, 100, 0, 100, 100 } } } }
    local here = { instance = 0 }
    local function P(x, y) return { instance = 0, wx = x, wy = y } end
    local legs = {
        { stop = P(0, 0), steps = {
            { kind = "ground", from = P(0, 0), to = P(300, 0) },
            { kind = "flight", from = here, to = here, hops = { 1, 2 } },
            { kind = "boat", from = P(0, 500), to = P(90, 500) },
        } },
    }
    V.Attach(legs, function() return true end)
    V.Draw()
    eq(lineLayer.level, 2933, "the lines go above the highest other map frame")
    eq(markerLayer.level, 2938, "the markers go above the lines")
    local marker = frames[#frames]
    eq(marker.shown, true, "the stop gets our own marker frame, not a shared map pin")
    eq(marker.points[1][1], "CENTER"); eq(marker.points[1][3], "TOPLEFT")
    eq(marker.scale, 1, "markers keep a constant screen size (canvas scale 1 here)")

    local shown = {}
    for _, l in ipairs(made) do if l.shown then shown[#shown + 1] = l end end
    local ground, dots, boat = {}, {}, {}
    for _, l in ipairs(shown) do
        if l.color[1] == 1 then ground[#ground + 1] = l
        elseif l.y1 == -500 then boat[#boat + 1] = l
        else dots[#dots + 1] = l end
    end
    eq(#boat, 10, "a boat step is dotted too: 90 units at 4 on, 5 off")
    for _, d in ipairs(boat) do ok(d.x2 - d.x1 <= 4 + 1e-9, "boat dots keep the dot length") end
    eq(#ground, 16, "a ground step is a solid bow of 16 pieces")
    eq(ground[1].x1, 0); eq(ground[1].y1, 0); eq(ground[16].x2, 300); ok(math.abs(ground[16].y2) < 1e-9, "the bow ends exactly at the stop")
    for i = 2, 16 do eq(ground[i].x1, ground[i - 1].x2, "pieces join without gaps") end
    local mid = ground[8]
    ok(math.abs(math.abs(mid.y2) - 30) < 1e-6, "the bow bulges by 10% of the leg at its middle: " .. tostring(mid.y2))

    ok(#dots > 10, "a flight is drawn as many dots")
    local total = 0
    for _, d in ipairs(dots) do
        local len = math.sqrt((d.x2 - d.x1) ^ 2 + (d.y2 - d.y1) ^ 2)
        ok(len <= 4 + 1e-9, "no dot is longer than the dot length")
        total = total + len
    end
    ok(math.abs(total - 200 * 4 / 9) < 4, "dots cover about 4 of every 9 units along the whole path")
    local corner = false
    for _, d in ipairs(dots) do
        if d.x1 < 100 and d.x2 == 100 and d.y2 > 0 then corner = true end
    end
    ok(not corner, "a dot never cuts across a bend")

    local canvas = _G.WorldMapFrame.ScrollContainer.Child
    local walks, getChildren = 0, canvas.GetChildren
    canvas.GetChildren = function(self) walks = walks + 1; return getChildren(self) end
    other:SetFrameLevel(9999)
    V.Draw()
    eq(walks, 0, "a redraw on the same map does not walk the canvas children again")
    eq(lineLayer.level, 2933)
    _G.WorldMapFrame.GetMapID = function() return 2 end
    V.Draw()
    eq(walks, 1, "a map change raises the layers again")
    eq(lineLayer.level, 9900, "capped below the engine's frame level limit")
    other:SetFrameLevel(3000)
    _G.WorldMapFrame.ScrollContainer.GetCanvasScale = function() return 2 end
    V.Draw()
    eq(walks, 1, "a zoom does not raise the layers")
    _G.WorldMapFrame.ScrollContainer.GetCanvasScale = function() return 1 end
    _G.WorldMapFrame.onShow()
    eq(walks, 2, "showing the map raises the layers again")
    eq(lineLayer.level, 3010)
    _G.WorldMapFrame.GetMapID = function() return 1 end
    other:SetFrameLevel(2923)
    V.Draw()
    for _, l in ipairs(made) do l:Hide() end
    local mapNow = 1
    _G.WorldMapFrame.GetMapID = function() return mapNow end
    hbd.GetZoneCoordinatesFromWorldInstance = function(_, x, y, instance, mapID)
        if mapID == 947 or instance == 0 then return x / 1000, y / 1000 end
    end
    V.Attach({ { stop = { instance = 1, wx = 0, wy = 0 }, steps = {
        { kind = "ground", from = { instance = 1, wx = 0, wy = 0 }, to = { instance = 1, wx = 300, wy = 0 } },
    } } }, function() return true end)
    local function Shown()
        local n = 0
        for _, l in ipairs(made) do if l.shown then n = n + 1 end end
        return n
    end
    V.Draw()
    eq(Shown(), 0, "a leg on another continent is not drawn on this continent's zone")
    mapNow = 947
    V.Draw()
    eq(Shown(), 16, "the world map draws legs of every continent, each converted with its own instance")

    local function LastShown()
        local out = {}
        for _, l in ipairs(made) do if l.shown then out[#out + 1] = l end end
        return out
    end
    hbd.GetZoneCoordinatesFromWorldInstance = function(_, x, y, instance) return (x + instance * 100) / 1000, y / 1000 end
    V.Attach({ { stop = P(0, 0), steps = {
        { kind = "ground", from = { instance = 0, wx = 0, wy = 0 }, to = { instance = 1, wx = 300, wy = 0 } },
    } } }, function() return true end)
    V.Draw()
    local bow = LastShown()
    eq(#bow, 16); ok(math.abs(bow[16].x2 - 400) < 1e-9, "a ground bow converts its end with the end's instance: " .. tostring(bow[16].x2))

    hbd.GetZoneCoordinatesFromWorldInstance = nil
    hbd.GetWorldCoordinatesFromZone = function(_, _, _, mapID) return 0, 0, mapID == 5 and 1 or 0 end
    V.Attach({ { stop = { instance = 1, wx = 0, wy = 0 }, steps = {
        { kind = "ground", from = { instance = 1, wx = 0, wy = 0 }, to = { instance = 1, wx = 300, wy = 0 } },
    } } }, function() return true end)
    mapNow = 1
    V.Draw()
    eq(Shown(), 0, "without instance-aware conversion, a point of another instance is off this map")
    mapNow = 5
    V.Draw()
    eq(Shown(), 16, "the map of the point's own instance draws it")
    hbd.GetWorldCoordinatesFromZone = function() return 0, 0, 0 end
    mapNow = 1

    local function MarkerFrame()
        for i = #frames, 1, -1 do
            local f = frames[i]
            if f.shown and f.scale then return f end
        end
    end
    V.Attach({ { stop = P(200, 300), steps = {} } }, function() return true end)
    for _, sc in ipairs({ 2, 0.5, 2 }) do
        _G.WorldMapFrame.ScrollContainer.GetCanvasScale = function() return sc end
        V.Draw()
        local m = MarkerFrame()
        eq(m.scale, 1 / sc, "marker scale undoes the canvas scale " .. sc)
        eq(m.points[1][1], "CENTER")
        eq(m.points[1][4], 200 * sc, "x offset in the marker's scaled units at " .. sc)
        eq(m.points[1][5], -300 * sc, "y offset in the marker's scaled units at " .. sc)
    end
    _G.WorldMapFrame.ScrollContainer.GetCanvasScale = function() return 1 end

    ns.TaxiPaths = { [1] = { [2] = { 0, 0, { -1000, 200, -900, 200, 500, 200 } } } }
    V.Attach({ { stop = P(0, 0), steps = { { kind = "flight", from = here, to = here, hops = { 1, 2 } } } } },
        function() return true end)
    local madeBefore = #made
    V.Draw()
    local clipped = LastShown()
    ok(#made - madeBefore < 100, "no line pieces made for the off-canvas part: " .. (#made - madeBefore))
    eq(#clipped, 61, "only dots inside the canvas plus margin: 550 units at 4 on, 5 off")
    for _, d in ipairs(clipped) do
        ok(d.x1 >= -50 - 1e-9, "no dot left of the margin: " .. d.x1)
        if d.x1 > -50 + 1e-9 then
            local off = (d.x1 + 1000) % 9
            ok(off < 1e-6 or off > 9 - 1e-6, "dot spacing continues across the skipped part: " .. d.x1)
        end
    end
    ns.TaxiPaths = { [1] = { [2] = { 0, 0, { -100000, 500, 500, 500 } } } }
    madeBefore = #made
    V.Draw()
    ok(#made - madeBefore < 100, "a long flight mostly off the canvas makes few pieces: " .. (#made - madeBefore))
    eq(V.Clip(-10, 0, -5, 0, 0, 0, 10, 10), nil, "fully outside")
    local a, b = V.Clip(-10, 5, 20, 5, 0, 0, 10, 10)
    ok(math.abs(a - 1 / 3) < 1e-9 and math.abs(b - 2 / 3) < 1e-9, "clipped on both sides")
end)

for _, k in ipairs(names) do _G[k] = saved[k] end
if not good then error(problem, 0) end
