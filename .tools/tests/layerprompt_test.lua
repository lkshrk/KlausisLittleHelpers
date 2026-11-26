local names = { "CreateFrame", "UIParent", "GetBuildInfo", "C_AddOns", "geterrorhandler", "LibStub", "KLH",
    "ShardTransferImminentFrame", "ShardTransferImminentMinimizeButton" }
local saved = {}
for _, k in ipairs(names) do saved[k] = rawget(_G, k) end

local frames = {}
local function NewObject()
    local o = { events = {}, scripts = {}, hooks = {}, shown = true, points = {} }
    return setmetatable(o, { __index = function(_, k)
        local fn = ({
            RegisterEvent = function(self, e) self.events[e] = true end,
            UnregisterEvent = function(self, e) self.events[e] = nil end,
            SetScript = function(self, name, f) self.scripts[name] = f end,
            HookScript = function(self, name, f) self.hooks[name] = f end,
            Show = function(self) self.shown = true end,
            Hide = function(self) self.shown = false end,
            SetShown = function(self, v) self.shown = v and true or false end,
            IsShown = function(self) return self.shown end,
            ClearAllPoints = function(self) self.points = {} end,
            SetPoint = function(self, p, rel, rp, x, y) self.points[#self.points + 1] = { p, rel, rp, x, y } end,
            GetPoint = function(self) local p = self.points[1]; if p then return p[1], p[2], p[3], p[4], p[5] end end,
            SetFrameStrata = function(self, s) self.strata = s end,
            StopMovingOrSizing = function(self) self.points = { { "CENTER", _G.UIParent, "CENTER", 40, 60 } } end,
            CreateTexture = function() return NewObject() end,
        })[k]
        return fn or function() end
    end })
end
_G.UIParent = NewObject()
_G.CreateFrame = function()
    local f = NewObject()
    frames[#frames + 1] = f
    return f
end
_G.GetBuildInfo = function() return "1.60.1", "71037", "", 16001 end
_G.C_AddOns = { IsAddOnLoaded = function() return false end }
_G.geterrorhandler = function() return function(e) error(e, 0) end end
local fakeDB = { profile = { features = {} } }
_G.LibStub = function(name) if name == "AceDB-3.0" then return { New = function() return fakeDB end } end end
_G.ShardTransferImminentFrame = nil

local good, problem = pcall(function()
    addon("Core/Core.lua")
    ns.UI = {
        Accent = function() return 0, 1, 0 end,
        Font = function() return NewObject() end,
        Solid = function() return NewObject() end,
        Border = function() end,
    }
    addon("Modules/LayerPrompt.lua")
    local spec = ns.features.LayerPrompt
    ok(spec ~= nil, "registers on Forever")
    eq(spec.tab, "qol"); eq(spec.section, "Interface"); ok(spec.alwaysOn, "always on")

    local loader = frames[1]
    loader.scripts.OnEvent(loader, "PLAYER_LOGIN")
    local watcher = frames[#frames]
    ok(watcher.events.ADDON_LOADED, "waits for the toast addon when its frame is missing")

    local toast, minimize = NewObject(), NewObject()
    toast.shown, minimize.shown = false, false
    _G.ShardTransferImminentFrame, _G.ShardTransferImminentMinimizeButton = toast, minimize
    watcher.scripts.OnEvent(watcher, "ADDON_LOADED", "SomeOtherAddon")
    eq(toast.hooks.OnShow, nil, "ignores other addons")
    watcher.scripts.OnEvent(watcher, "ADDON_LOADED", "Blizzard_SocialToast")
    ok(toast.hooks.OnShow ~= nil, "hooks the toast once its addon loads")
    eq(watcher.events.ADDON_LOADED, nil, "stops watching")

    local holder = toast.points[1][2]
    eq(#toast.points, 1); eq(toast.points[1][1], "TOP"); ok(holder ~= _G.UIParent, "anchored to its holder")
    eq(toast.strata, "DIALOG"); eq(minimize.strata, "DIALOG")
    eq(holder.points[1][1], "TOP"); eq(holder.points[1][5], -320, "default top centre, below the StaticPopup")
    eq(holder.shown, false, "holder hidden while locked")

    toast.points = { { "BOTTOMLEFT", "ChatAlertFrame", "TOPLEFT", 30, 55 } }
    toast.hooks.OnShow(toast)
    eq(toast.points[1][2], holder, "re-anchors every time it shows")

    local args = spec.options(ns.GetSettings("LayerPrompt"))
    eq(args.move.name(), "Move prompt")
    args.move.func()
    eq(holder.shown, true, "unlock shows the drag box")
    eq(args.move.name(), "Lock position")
    holder.scripts.OnDragStop(holder)
    local pos = ns.GetSettings("LayerPrompt").pos
    eq(pos.point, "CENTER"); eq(pos.x, 40); eq(pos.y, 60)
    args.move.func()
    eq(holder.shown, false, "lock hides it")
    eq(holder.points[1][1], "CENTER"); eq(holder.points[1][5], 60, "keeps the dragged spot")

    args.move.func()
    holder.scripts.OnMouseUp(holder, "LeftButton")
    eq(holder.shown, true, "left click keeps it unlocked")
    holder.scripts.OnMouseUp(holder, "RightButton")
    eq(holder.shown, false, "right-click locks")
    args.move.func()
    spec.onReset()
    eq(holder.shown, false, "a profile swap locks it")
    eq(args.move.name(), "Move prompt")

    args.reset.func()
    eq(ns.GetSettings("LayerPrompt").pos, nil)
    eq(holder.points[1][5], -320, "reset returns to top centre")

    local early, hooks = NewObject(), 0
    early.HookScript = function(self, name, f)
        hooks = hooks + 1
        self.hooks[name] = f
    end
    _G.ShardTransferImminentFrame = early
    local register, again = ns.RegisterFeature, nil
    ns.RegisterFeature = function(s) again = s end
    addon("Modules/LayerPrompt.lua")
    ns.RegisterFeature = register
    local created = #frames
    again.enable()
    eq(hooks, 1, "a toast frame present at login is hooked right away, once")
    eq(#frames, created + 1, "no addon watcher, only the holder")
    local earlyHolder = early.points[1] and early.points[1][2]
    ok(earlyHolder ~= nil and earlyHolder ~= _G.UIParent, "anchored to the holder at once")
    eq(early.points[1][1], "TOP"); eq(early.strata, "DIALOG")
    eq(earlyHolder.points[1][5], -320)
    again.enable()
    eq(hooks, 1, "enabling again does not hook twice")
end)

for _, k in ipairs(names) do _G[k] = saved[k] end
if not good then error(problem, 0) end
