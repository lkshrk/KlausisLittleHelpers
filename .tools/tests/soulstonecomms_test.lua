local names = { "CreateFrame", "C_Timer", "UIParent", "IsInInstance", "IsInGroup", "IsInRaid", "GetNumGroupMembers",
    "UnitExists", "UnitGUID", "UnitName", "UnitClass", "UnitLevel", "UnitIsConnected", "UnitIsVisible", "UnitGroupRolesAssigned",
    "UnitAffectingCombat", "UnitIsDeadOrGhost", "IsEncounterInProgress", "C_UnitAuras", "InCombatLockdown", "GetTime",
    "C_Item", "C_Container", "C_ChatInfo", "SendChatMessage", "PlaySound", "SOUNDKIT", "C_CombatLog",
    "CombatLogGetCurrentEventInfo", "GetPlayerInfoByGUID", "LE_PARTY_CATEGORY_INSTANCE", "GetNormalizedRealmName" }
local saved = {}
for _, k in ipairs(names) do saved[k] = rawget(_G, k) end

local cur
local now = 1000
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
            CreateFontString = function() return NewObject() end,
            CreateTexture = function() return NewObject() end,
            GetPoint = function() return "TOP", nil, "TOP", 0, -100 end,
        })[k]
        return fn or function() end
    end })
end

local carl = { guid = "Player-1-0000000C", name = "Carl", class = "WARLOCK", level = 60 }
local function NewClient(guid, name)
    return { guid = guid, name = name, frames = {}, timers = {}, sent = {}, addon = {}, store = {}, sounds = 0,
             me = { guid = guid, name = name, class = "PRIEST", level = 60 } }
end
local alice = NewClient("Player-1-0000000A", "Alice")
local bob = NewClient("Player-1-0000000B", "Bob")
local clients = { alice, bob }
local inGroup = { alice = true, bob = true }
local function Roster(c)
    local r = { player = c.me }
    local i = 0
    local other = c == alice and bob or alice
    if (c == alice and inGroup.bob) or (c == bob and inGroup.alice) then
        i = i + 1
        r["party" .. i] = other.me
    end
    i = i + 1
    r["party" .. i] = carl
    return r
end
local function U(u) return Roster(cur)[u] end
local deliveries = {}
local addonSendResult = 0

_G.UIParent = NewObject()
_G.CreateFrame = function() local f = NewObject(); cur.frames[#cur.frames + 1] = f; return f end
_G.C_Timer = { After = function(delay, fn) cur.timers[#cur.timers + 1] = { at = now + delay, fn = fn } end }
_G.IsInInstance = function() return true, "party" end
_G.IsInGroup = function(category) return category == nil end
_G.IsInRaid = function() return false end
_G.GetNumGroupMembers = function() local n = 0; for _ in pairs(Roster(cur)) do n = n + 1 end; return n end
_G.UnitExists = function(u) return U(u) ~= nil end
_G.UnitGUID = function(u) return U(u) and U(u).guid end
_G.UnitName = function(u) return U(u) and U(u).name end
_G.UnitClass = function(u) return U(u) and U(u).class, U(u) and U(u).class end
_G.UnitLevel = function(u) return U(u) and U(u).level end
_G.UnitIsConnected = function(u) return U(u) ~= nil end
_G.UnitIsVisible = function(u) return U(u) ~= nil end
_G.UnitGroupRolesAssigned = function() return "NONE" end
_G.UnitAffectingCombat = function() return false end
_G.UnitIsDeadOrGhost = function() return false end
_G.IsEncounterInProgress = function() return false end
_G.C_UnitAuras = { GetUnitAuraBySpellID = function() end }
_G.InCombatLockdown = function() return false end
_G.GetTime = function() return now end
_G.GetNormalizedRealmName = function() return "Realm" end
_G.C_Item = { GetItemCount = function() return 0 end }
_G.C_Container = nil
_G.PlaySound = function() cur.sounds = cur.sounds + 1 end
_G.SOUNDKIT = { RAID_WARNING = 8959 }
_G.C_CombatLog = nil
local registered = {}
_G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix) registered[#registered + 1] = prefix; return 0 end,
    SendAddonMessage = function(prefix, text, kind)
        cur.addon[#cur.addon + 1] = { prefix = prefix, text = text, kind = kind }
        if addonSendResult ~= 0 then return addonSendResult end
        for _, c in ipairs(clients) do
            local member = (c == alice and inGroup.alice) or (c == bob and inGroup.bob)
            if c ~= cur and member then
                deliveries[#deliveries + 1] = { to = c, prefix = prefix, text = text, kind = kind, sender = cur.name .. "-Realm" }
            end
        end
        return 0
    end,
    SendChatMessage = function(text, kind, _, target) cur.sent[#cur.sent + 1] = { text = text, kind = kind, target = target } end,
}

local function As(c, fn) local prev = cur; cur = c; fn(); cur = prev end
local function Fire(c, event, ...)
    local args = { ... }
    As(c, function()
        for _, f in ipairs(c.frames) do
            if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, unpack(args)) end
        end
    end)
end
local function FireAll(event, ...) for _, c in ipairs(clients) do Fire(c, event, ...) end end
local function Pump()
    for _ = 1, 50 do
        local busy = false
        for _, c in ipairs(clients) do
            local list = c.timers
            c.timers = {}
            for _, t in ipairs(list) do
                if t.at <= now then busy = true; As(c, t.fn) else c.timers[#c.timers + 1] = t end
            end
        end
        local list = deliveries
        deliveries = {}
        for _, d in ipairs(list) do
            busy = true
            Fire(d.to, "CHAT_MSG_ADDON", d.prefix, d.text, d.kind, d.sender, "", 0, 0, d.sender, 0)
        end
        if not busy then return end
    end
end
local function Later(seconds) now = now + seconds; Pump() end
local function Hellos(c) local n = 0; for _, m in ipairs(c.addon) do if m.text == "SSR1:HELLO" then n = n + 1 end end; return n end
local function Banner(c) for _, f in ipairs(c.frames) do if rawget(f, "isSoulstoneBanner") then return f end end end

local good, problem = pcall(function()
    for _, c in ipairs(clients) do
        As(c, function()
            c.ns = { Data = {} }
            c.ns.UI = {
                Accent = function() return 0, 1, 0 end,
                Font = function() return NewObject() end,
                Solid = function() return NewObject() end,
                Border = function() return { SetColor = function() end } end,
            }
            c.ns.RegisterFeature = function(s) c.spec = s end
            c.ns.GetSettings = function() return setmetatable(c.store, { __index = c.spec.defaults }) end
            c.ns.WasEnabledAtLoad = function() return true end
            local chunk = assert(loadfile("Modules/SoulstoneLogic.lua"))
            chunk("KlausisLittleHelpers", c.ns)
            chunk = assert(loadfile("Modules/SoulstoneReminder.lua"))
            chunk("KlausisLittleHelpers", c.ns)
            c.store.announce, c.store.whisper = true, true
            c.spec.enable(c.ns.GetSettings())
        end)
        ok(c.frames[1].events.CHAT_MSG_ADDON, c.name .. " listens for addon messages")
    end
    eq(registered[1], "KLH"); eq(registered[2], "KLH")

    FireAll("GROUP_ROSTER_UPDATE")
    Pump()
    ok(Hellos(alice) >= 1 and Hellos(bob) >= 1, "both say hello on a roster change")
    eq(alice.addon[1].kind, "PARTY"); eq(alice.addon[1].prefix, "KLH")
    local before = Hellos(alice)
    Later(5)
    FireAll("GROUP_ROSTER_UPDATE")
    Pump()
    eq(Hellos(alice), before, "at most one hello per 10 s")

    Later(1)
    FireAll("READY_CHECK")
    Later(3)
    ok(Banner(alice).shown and Banner(bob).shown, "everyone shows the banner")
    eq(#alice.sent, 2, "lower guid announces and whispers")
    eq(alice.sent[1].text, "Soulstone ready (Carl), no healer has one.")
    eq(alice.sent[2].target, "Carl")
    eq(#bob.sent, 0, "higher guid stays quiet")

    Later(120)
    FireAll("READY_CHECK")
    Pump()
    Later(3)
    eq(#alice.sent, 4); eq(#bob.sent, 0, "still quiet after a fresh hello")

    inGroup.alice = false
    Fire(bob, "GROUP_ROSTER_UPDATE")
    Later(120)
    Fire(bob, "READY_CHECK")
    Later(3)
    eq(#bob.sent, 2, "a peer that left the group no longer wins")
    inGroup.alice = true

    addonSendResult = 9
    Later(120)
    FireAll("READY_CHECK")
    Later(3)
    eq(#alice.sent, 6); eq(#bob.sent, 4, "failed comms: announce yourself")
    addonSendResult = 0

    bob.store.announce, bob.store.whisper = false, false
    local bobHellos = Hellos(bob)
    Later(120)
    FireAll("GROUP_ROSTER_UPDATE")
    Pump()
    eq(Hellos(bob), bobHellos, "no hello without announce or whisper")
end)
for _, k in ipairs(names) do _G[k] = saved[k] end
ok(good, tostring(problem))
