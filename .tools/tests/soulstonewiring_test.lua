local names = { "CreateFrame", "C_Timer", "UIParent", "IsInInstance", "IsInGroup", "IsInRaid", "GetNumGroupMembers", "GetRaidRosterInfo",
    "UnitExists", "UnitGUID", "UnitName", "UnitClass", "UnitLevel", "UnitIsConnected", "UnitIsVisible", "UnitGroupRolesAssigned",
    "UnitAffectingCombat", "UnitIsDeadOrGhost", "IsEncounterInProgress", "C_UnitAuras", "InCombatLockdown", "GetTime",
    "C_Item", "C_Container", "C_ChatInfo", "SendChatMessage", "PlaySound", "SOUNDKIT", "C_CombatLog",
    "CombatLogGetCurrentEventInfo", "GetPlayerInfoByGUID", "LE_PARTY_CATEGORY_INSTANCE", "LibStub", "GetBuildInfo",
    "C_AddOns", "geterrorhandler", "KLH", "issecretvalue" }
local saved = {}
for _, k in ipairs(names) do saved[k] = rawget(_G, k) end

local frames, timers, sent, sounds = {}, {}, {}, 0
local function NewObject()
    local o = { events = {}, scripts = {}, shown = true, texts = {} }
    return setmetatable(o, { __index = function(_, k)
        local fn = ({
            RegisterEvent = function(self, e) self.events[e] = true end,
            UnregisterEvent = function(self, e) self.events[e] = nil end,
            SetScript = function(self, name, fn) self.scripts[name] = fn end,
            Show = function(self) self.shown = true end,
            Hide = function(self) self.shown = false end,
            IsShown = function(self) return self.shown end,
            SetText = function(self, s) self.text = s end,
            GetText = function(self) return self.text end,
            CreateFontString = function(self) local f = NewObject(); self.texts[#self.texts + 1] = f; return f end,
            CreateTexture = function() return NewObject() end,
            GetPoint = function() return "TOP", nil, "TOP", 0, -100 end,
            SetFont = function(self, _, size, flags) self.fontSize, self.fontFlags = size, flags end,
            SetShadowOffset = function(self, x, y) self.shadow = { x, y } end,
            SetHeight = function(self, h) self.height = h end,
            SetSize = function(self, w, h) self.width, self.height = w, h end,
            CreateAnimationGroup = function(self)
                local g = NewObject()
                g.playing, g.anims = false, {}
                g.Play = function(group) group.playing = true end
                g.Stop = function(group) group.playing = false end
                g.IsPlaying = function(group) return group.playing end
                g.SetLooping = function(group, mode) group.looping = mode end
                g.CreateAnimation = function(group, kind)
                    local a = NewObject()
                    a.kind = kind
                    a.SetOffset = function(anim, x, y) anim.offset = { x, y } end
                    a.SetDuration = function(anim, d) anim.duration = d end
                    a.SetSmoothing = function(anim, mode) anim.smoothing = mode end
                    group.anims[#group.anims + 1] = a
                    return a
                end
                self.animGroup = g
                return g
            end,
        })[k]
        return fn or function() end
    end })
end
_G.UIParent = NewObject()
_G.CreateFrame = function(_, _, _, template)
    local f = NewObject()
    f.template = template
    frames[#frames + 1] = f
    return f
end
_G.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
local function Run(limit)
    local list = timers
    timers = {}
    for _, t in ipairs(list) do
        if t.delay <= (limit or 0) then t.fn() else timers[#timers + 1] = t end
    end
end
local function Fire(event, ...)
    for _, f in ipairs(frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

local instance, now, encounter, dead = "party", 1000, false, false
local raid = false
local roster = {}
local function Party()
    raid = false
    roster = {
        player = { guid = "me", name = "Anduin", class = "PRIEST", level = 60 },
        party1 = { guid = "w1", name = "Gul'dan", realm = "Draenor", class = "WARLOCK", level = 60 },
    }
end
Party()
local auras = {}
local function Count()
    local n = 0
    for unit in pairs(roster) do if unit ~= "player" or not raid then n = n + 1 end end
    return n
end
_G.GetBuildInfo = function() return "1.60.1", "71037", "", 16001 end
_G.C_AddOns = { IsAddOnLoaded = function() return false end }
_G.geterrorhandler = function() return function(e) error(e, 0) end end
_G.IsInInstance = function() return instance ~= "none", instance end
_G.IsInGroup = function(category) return category == nil end
_G.IsInRaid = function() return raid end
_G.GetNumGroupMembers = function() return Count() end
_G.UnitExists = function(u) return roster[u] ~= nil end
_G.UnitGUID = function(u) return roster[u] and roster[u].guid end
_G.UnitName = function(u) return roster[u] and roster[u].name, roster[u] and roster[u].realm end
_G.UnitClass = function(u) return roster[u] and roster[u].class, roster[u] and roster[u].class end
_G.UnitLevel = function(u) return roster[u] and roster[u].level end
_G.UnitIsConnected = function(u) return roster[u] ~= nil and roster[u].offline ~= true end
_G.UnitIsVisible = function(u) return roster[u] ~= nil and roster[u].far ~= true end
_G.GetRaidRosterInfo = function(i)
    local units = {}
    for unit in pairs(roster) do units[#units + 1] = unit end
    table.sort(units)
    local r = roster[units[i - 1]]
    if i == 1 or not r then return nil, 0, 1 end
    return r.name, 0, 1, r.level, r.class, r.class, r.zone or "Blackrock Spire", r.offline ~= true
end
_G.UnitGroupRolesAssigned = function() return "NONE" end
_G.UnitAffectingCombat = function(u) return roster[u] ~= nil and roster[u].combat == true end
_G.UnitIsDeadOrGhost = function() return dead end
_G.IsEncounterInProgress = function() return encounter end
_G.C_UnitAuras = { GetUnitAuraBySpellID = function(u, id) return auras[u] and auras[u][id] end }
_G.InCombatLockdown = function() return roster.player.combat == true end
_G.GetTime = function() return now end
local bags = {}
_G.C_Item = { GetItemCount = function(id) return bags[id] and 1 or 0 end }
_G.C_Container = { GetItemCooldown = function(id) local b = bags[id]; if b then return b.start, b.duration, 1 end return 0, 0, 1 end }
_G.C_ChatInfo = { SendChatMessage = function(text, kind, _, target) sent[#sent + 1] = { text = text, kind = kind, target = target } end }
_G.SendChatMessage = nil
_G.PlaySound = function() sounds = sounds + 1 end
_G.SOUNDKIT = { RAID_WARNING = 8959 }
_G.C_CombatLog = nil
local fakeDB = { profile = { features = {} } }
_G.LibStub = function(name) if name == "AceDB-3.0" then return { New = function() return fakeDB end } end end

local good, problem = pcall(function()
    addon("Core/Core.lua")
    ns.UI = {
        Accent = function() return 0, 1, 0 end,
        Font = function() return NewObject() end,
        Solid = function() return NewObject() end,
        Border = function() return { SetColor = function() end } end,
        Defer = function(_, fn) fn() end,
    }
    addon("Modules/SoulstoneLogic.lua")
    addon("Modules/SoulstoneReminder.lua")
    local spec = ns.features.SoulstoneReminder
    ok(spec ~= nil, "registers on Forever")
    eq(spec.title, "Soulstone Reminder"); eq(spec.tab, "qol"); eq(spec.section, "Dungeons & Raids")
    ok(not spec.alwaysOn, "switchable")
    local loader = frames[1]
    eq(#frames, 1, "only the core loader frame exists")
    loader.scripts.OnEvent(loader, "PLAYER_LOGIN")
    eq(#frames, 1, "disabled feature creates no frames at login")
    eq(ns.WasEnabledAtLoad("SoulstoneReminder"), false)

    eq(spec.defaults.instances, "both"); eq(spec.defaults.banner, true)
    eq(spec.defaults.announce, false); eq(spec.defaults.whisper, false); eq(spec.defaults.sound, false)
    local args = spec.options(ns.GetSettings("SoulstoneReminder"))
    eq(args.instances.type, "select"); eq(args.instances.name, "Active in"); eq(args.instances.order, 1)
    eq(args.instances.values.party, "Dungeons"); eq(args.instances.values.raid, "Raids")
    eq(args.instances.values.both, "Dungeons and raids")
    eq(args.banner.name, "Show banner"); eq(args.banner.order, 2); eq(args.banner.width, "normal")
    eq(args.announce.name, "Announce to group"); eq(args.announce.order, 3); eq(args.announce.width, "normal")
    eq(args.whisper.name, "Whisper warlock"); eq(args.whisper.order, 4); eq(args.whisper.width, "normal")
    eq(args.sound.name, "Play a sound"); eq(args.sound.order, 5)
    eq(args.test.type, "execute"); eq(args.test.name(), "Show test banner"); eq(args.test.order, 6)
    eq(args.resetPosition.type, "execute"); eq(args.resetPosition.name, "Reset position"); eq(args.resetPosition.order, 7)
    eq(args.instances.get(), "both")
    for _, k in ipairs({ "banner", "announce", "whisper", "sound" }) do eq(args[k].get(), spec.defaults[k], k) end
    eq(args.test.disabled(), true, "test banner greyed while not running")
    eq(#frames, 1, "building options creates nothing")

    fakeDB.profile.features.SoulstoneReminder.enabled = true
    loader.scripts.OnEvent(loader, "PLAYER_LOGIN")
    eq(args.test.disabled(), false, "test banner available once running")
    local events = frames[2] and frames[2].events or {}
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "UNIT_AURA", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "READY_CHECK", "BAG_UPDATE_COOLDOWN",
        "UNIT_SPELLCAST_SUCCEEDED" }) do
        ok(events[e], e .. " registered")
    end
    eq(events.COMBAT_LOG_EVENT_UNFILTERED, nil, "combat log is protected on Forever")

    local function Banner()
        for _, f in ipairs(frames) do if rawget(f, "isSoulstoneBanner") then return f end end
    end
    local function CloseButton()
        for _, f in ipairs(frames) do if f.template == "UIPanelCloseButton" then return f end end
    end
    local function ShownRows(b)
        local out = {}
        for _, row in ipairs(b.rows) do if row.shown then out[#out + 1] = row:GetText() end end
        return out
    end
    local function Settle(seconds)
        now = now + (seconds or 0)
        Run(seconds or 0)
    end
    local store = fakeDB.profile.features.SoulstoneReminder

    store.announce, store.whisper, store.sound = true, true, true
    Fire("READY_CHECK")
    Settle()
    local banner = Banner()
    ok(banner and banner.shown, "ready check shows banner")
    eq(CloseButton(), nil, "no close button")
    local rows = ShownRows(banner)
    eq(#rows, 2, "headline plus one Ready row")
    eq(rows[1], "No Soulstone on healer")
    eq(rows[2], "Ready: Gul'dan", "rows drop the realm")
    eq(banner.rows[1].fontFlags, "OUTLINE", "outlined text")
    ok(banner.rows[1].shadow ~= nil, "shadowed text")
    ok(banner.icon ~= nil and banner.icon.width == 40, "40 px icon row")
    local twoRowHeight = banner.height
    ok(type(twoRowHeight) == "number" and twoRowHeight > 40, "height set from rows")
    ok(banner.scripts.OnUpdate, "bounce runs while shown")
    local lastY
    banner.icon.SetPoint = function(_, _, _, _, _, y) lastY = y end
    local top = 0
    for _ = 1, 100 do
        banner.scripts.OnUpdate(banner, 0.01)
        ok(lastY >= 0 and lastY <= 8.0001, "bounce stays within 0..8 px")
        if lastY > top then top = lastY end
    end
    ok(top > 7.9, "bounce reaches 8 px")
    ok(lastY < 0.01, "a full 1 s cycle ends back at rest, no jump")
    eq(#sent, 2, "announce and whisper")
    eq(sent[1].kind, "INSTANCE_CHAT", "announce always uses instance chat")
    eq(sent[1].text, "Soulstone ready (Gul'dan-Draenor), no healer has one.")
    eq(sent[2].kind, "WHISPER"); eq(sent[2].target, "Gul'dan-Draenor")
    eq(sounds, 1)

    Fire("READY_CHECK")
    Settle(10)
    eq(#sent, 2, "throttled within 60 s")

    roster.player.combat = true
    Fire("PLAYER_REGEN_DISABLED")
    Settle()
    eq(banner.shown, false, "combat hides")
    Fire("READY_CHECK")
    Settle()
    eq(banner.shown, false, "ready check in combat does not show")

    roster.player.combat, roster.party1.combat = nil, true
    Fire("PLAYER_REGEN_ENABLED")
    Settle(120)
    eq(banner.shown, false, "group still fighting keeps it hidden")
    eq(#sent, 2, "trigger held while a member is in combat")
    roster.party1.combat = nil
    encounter = true
    Settle(1)
    eq(banner.shown, false, "encounter in progress keeps it hidden")
    eq(#sent, 2)
    encounter, dead = false, true
    Settle(1)
    eq(banner.shown, false, "dead player keeps it hidden")
    eq(#sent, 2)
    dead = false
    Settle(1)
    ok(banner.shown, "held trigger fires once the group is out of combat")
    eq(#sent, 4, "held trigger sends chat once")
    Settle(1)
    eq(#sent, 4, "held trigger fires only once")

    auras.player = { [20765] = { spellId = 20765 } }
    Fire("UNIT_AURA", "player")
    Settle()
    eq(banner.shown, false, "buff appearing hides")
    auras.player = nil

    store.announce, store.whisper = false, false
    Fire("READY_CHECK")
    Settle(120)
    ok(banner.shown)
    eq(#sent, 4, "no chat with toggles off")


    roster.party1.level = 17
    Fire("GROUP_ROSTER_UPDATE")
    Settle()
    eq(banner.shown, false, "warlock under 18 not ready")
    roster.party1.level = 60
    roster.player.level = 9
    Fire("GROUP_ROSTER_UPDATE")
    Settle()
    eq(banner.shown, false, "priest under 10 does not count")
    roster.player.level = 60

    roster.party1.offline = true
    Fire("GROUP_ROSTER_UPDATE")
    Settle()
    eq(banner.shown, false, "offline warlock skipped")
    roster.party1.offline = nil
    roster.party2 = { guid = "p2", name = "Uther", class = "PALADIN", level = 60, far = true }
    Fire("GROUP_ROSTER_UPDATE")
    Settle()
    eq(banner.shown, false, "unseen rez member: unknown, show nothing")
    roster.party2.zone = "Orgrimmar"
    Fire("GROUP_ROSTER_UPDATE")
    Settle()
    ok(banner.shown, "rez member outside the instance: assumed without a soulstone")
    roster.party2 = nil
    Fire("GROUP_ROSTER_UPDATE")
    Settle()
    ok(banner.shown, "back to normal")

    _G.GetPlayerInfoByGUID = function(guid) if guid == "w1" then return "Warlock", "WARLOCK" end end
    Settle(1800)
    Fire("GROUP_ROSTER_UPDATE")
    Settle()
    ok(banner.shown, "ready again after 30 min")

    roster.party1.combat = true
    Fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast-1", 20765)
    Fire("UNIT_SPELLCAST_SUCCEEDED", "nameplate1", "cast-2", 20765)
    Settle()
    roster.party1.combat = nil
    Fire("GROUP_ROSTER_UPDATE")
    Settle()
    eq(banner.shown, false, "spellcast event starts the cooldown")
    Settle(1800)
    Fire("GROUP_ROSTER_UPDATE")
    Settle()
    ok(banner.shown)

    raid = true
    roster = {
        raid1 = { guid = "me", name = "Anduin", class = "PRIEST", level = 60 },
        raid2 = { guid = "w1", name = "Gul'dan", class = "WARLOCK", level = 60 },
        raid3 = { guid = "x", name = "Garrosh", class = "WARRIOR", level = 60, combat = true },
        player = { guid = "me", name = "Anduin", class = "PRIEST", level = 60, combat = true },
    }
    instance = "raid"
    Fire("PLAYER_REGEN_DISABLED")
    local appliedAt = now - 100
    auras.raid3 = { [20765] = { spellId = 20765, sourceUnit = "raid2", duration = 1800, expirationTime = appliedAt + 1800 } }
    Fire("UNIT_AURA", "raid3")
    Settle()
    eq(banner.shown, false, "nothing drawn in combat")
    auras.raid3 = nil
    roster.player.combat, roster.raid3.combat = nil, nil
    Fire("PLAYER_REGEN_ENABLED")
    Settle()
    eq(banner.shown, false, "aura seen in combat on a warrior started the caster's cooldown")
    now = appliedAt + 1799
    Fire("GROUP_ROSTER_UPDATE")
    Settle()
    eq(banner.shown, false, "cooldown counted from the aura's applied time")
    now = appliedAt + 1800
    Fire("GROUP_ROSTER_UPDATE")
    Settle()
    ok(banner.shown, "ready 30 min after the aura was applied")

    Party()
    roster.player.class = "WARLOCK"
    roster.party1 = { guid = "p1", name = "Uther", class = "PALADIN", level = 60 }
    instance = "party"
    bags[16896] = { start = now - 0.5, duration = 1.5 }
    Fire("BAG_UPDATE_COOLDOWN")
    Settle()
    ok(banner.shown, "global cooldown counts as ready")
    eq(ShownRows(banner)[2], "Put your soulstone on Uther")
    eq(#ShownRows(banner), 2, "no Ready row for yourself")
    bags[16896] = { start = now - 10, duration = 1800 }
    Fire("BAG_UPDATE_COOLDOWN")
    Settle()
    eq(banner.shown, false, "real item cooldown is not ready")
    bags[16896] = nil

    instance = "none"
    Fire("ZONE_CHANGED_NEW_AREA")
    Settle()
    eq(banner.shown, false, "leaving the instance hides")

    ok(args.test.desc:find("drag it to move it", 1, true), "test button explains dragging")
    local moves = 0
    banner.StartMoving = function() moves = moves + 1 end
    banner.scripts.OnDragStart(banner)
    eq(moves, 0, "real banner cannot be dragged")
    args.test.func()
    ok(banner.shown, "test banner shows")
    banner.scripts.OnDragStart(banner)
    eq(moves, 1, "test banner can be dragged")
    local testRows = ShownRows(banner)
    eq(#testRows, 3, "test banner: headline and two Ready rows")
    eq(testRows[1], "No Soulstone on healer"); ok(testRows[2]:find("^Ready: ") and testRows[3]:find("^Ready: "))
    ok(banner.height > twoRowHeight, "height grows with rows")
    Fire("GROUP_ROSTER_UPDATE")
    Settle()
    ok(banner.shown, "refresh keeps the test banner")
    Settle(30)
    eq(banner.shown, false, "test banner clears after 30 s")
    eq(args.test.name(), "Show test banner", "label back after the timeout")
    args.test.func()
    ok(banner.shown)
    eq(args.test.name(), "Hide test banner", "label flips while shown")
    args.test.func()
    eq(banner.shown, false, "second click hides the test banner")
    eq(args.test.name(), "Show test banner")
    args.test.func()
    ok(banner.shown)
    banner.scripts.OnMouseUp(banner, "LeftButton")
    ok(banner.shown, "left click does not dismiss")
    banner.scripts.OnMouseUp(banner, "RightButton")
    eq(banner.shown, false, "right-click clears the test banner")
    eq(args.test.name(), "Show test banner", "label back after right-click")
    eq(banner.scripts.OnUpdate, nil, "bounce stops on hide")
    Fire("GROUP_ROSTER_UPDATE")
    Settle()
    eq(banner.shown, false, "stays hidden after right-click")

    instance = "party"
    Party()
    Fire("GROUP_ROSTER_UPDATE")
    Settle()
    ok(banner.shown, "real banner back")
    banner.scripts.OnMouseUp(banner, "RightButton")
    eq(banner.shown, false, "right-click dismisses the real banner")
    Fire("GROUP_ROSTER_UPDATE")
    Settle()
    eq(banner.shown, false, "dismissed until the next trigger")
    Fire("READY_CHECK")
    Settle(120)
    ok(banner.shown, "next trigger shows it again")
    ok(banner.scripts.OnUpdate, "bounce plays again")
    instance = "none"
    Fire("ZONE_CHANGED_NEW_AREA")
    Settle()

    ok(type(spec.disable) == "function", "switches live")
    instance = "party"
    Party()
    store.announce, store.whisper = true, false
    local frameCount = #frames
    Fire("READY_CHECK")
    args.test.func()
    store.enabled = nil
    ns.ApplyFeature("SoulstoneReminder")
    eq(ns.IsRunning("SoulstoneReminder"), false, "stopped")
    eq(banner.shown, false, "disable hides the banner and ends test mode")
    eq(next(frames[2].events), nil, "disable unregisters every event")
    local sentBefore = #sent
    Settle(120)
    eq(banner.shown, false, "a pending timer after disable does nothing")
    eq(#sent, sentBefore, "no chat after disable")
    eq(args.test.disabled(), true, "test banner greyed while stopped")
    args.test.func()
    eq(banner.shown, false, "test banner does nothing while stopped")

    store.enabled = true
    ns.ApplyFeature("SoulstoneReminder")
    eq(ns.IsRunning("SoulstoneReminder"), true)
    eq(#frames, frameCount, "re-enable reuses the frames")
    ok(frames[2].events.READY_CHECK and frames[2].events.UNIT_AURA, "events registered again")
    eq(args.test.disabled(), false)
    Fire("READY_CHECK")
    Settle(120)
    ok(banner.shown, "works again after re-enable")
    eq(#sent, sentBefore + 1, "announces again after re-enable")
end)
for _, k in ipairs(names) do _G[k] = saved[k] end
ok(good, tostring(problem))
