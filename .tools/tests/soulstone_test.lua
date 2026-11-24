addon("Modules/SoulstoneLogic.lua")
local S = ns.Soulstone
ok(S ~= nil, "module loaded")

eq(S.COOLDOWN, 1800); eq(S.CHAT_GAP, 60)
for _, c in ipairs({ "PRIEST", "PALADIN", "SHAMAN", "DRUID" }) do ok(S.REZ_CLASSES[c], c .. " resurrects") end
eq(S.REZ_CLASSES.WARLOCK, nil); eq(S.REZ_CLASSES.MAGE, nil); eq(S.REZ_CLASSES.WARRIOR, nil)

local function Member(guid, name, class, extra)
    local m = { guid = guid, name = name, class = class }
    for k, v in pairs(extra or {}) do m[k] = v end
    return m
end

local function Snap(over)
    local s = {
        instance = "party", allowed = "both", inCombat = false, now = 1000, player = "me",
        members = {
            Member("me", "Anduin", "PRIEST"),
            Member("w1", "Gul'dan", "WARLOCK"),
        },
        tracker = S.NewTracker(),
    }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

local r = S.Evaluate(Snap())
ok(r ~= nil, "shows in party")
eq(r.lines, nil, "rows replace lines")
eq(#r.rows, 2)
eq(r.rows[1], "No Soulstone on healer")
eq(r.rows[2], "Ready: Gul'dan")
eq(r.suggest, "Anduin"); eq(r.selfWarlock, false)
eq(#r.readyWarlocks, 1); eq(r.readyWarlocks[1], "Gul'dan")
eq(r.announce, "Soulstone ready (Gul'dan), no healer has one.")
eq(#r.whispers, 1)
eq(r.whispers[1].target, "Gul'dan")
eq(r.whispers[1].text, "Your soulstone is ready; no healer has one. Suggest: Anduin.")

ok(S.Evaluate(Snap({ instance = "raid" })) ~= nil, "shows in raid")
eq(S.Evaluate(Snap({ instance = "raid", allowed = "party" })), nil, "raid off when dungeons only")
eq(S.Evaluate(Snap({ instance = "party", allowed = "raid" })), nil, "party off when raids only")
ok(S.Evaluate(Snap({ instance = "party", allowed = "party" })) ~= nil)
ok(S.Evaluate(Snap({ instance = "raid", allowed = "raid" })) ~= nil)
for _, t in ipairs({ "none", "pvp", "arena", "scenario" }) do
    eq(S.Evaluate(Snap({ instance = t })), nil, "hidden in " .. t)
end
eq(S.Evaluate(Snap({ inCombat = true })), nil, "hidden in combat")
eq(S.Evaluate(Snap({ instance = "raid", inCombat = true })), nil, "ready check in combat shows nothing")

eq(S.Evaluate(Snap({ members = { Member("me", "Anduin", "PRIEST"), Member("x", "Garrosh", "WARRIOR") } })), nil, "no warlock")
eq(S.Evaluate(Snap({ player = "w1", members = {
    Member("w1", "Gul'dan", "WARLOCK", { ownReady = true }), Member("m", "Jaina", "MAGE") } })), nil, "warlock + mage: no rez class")
eq(S.Evaluate(Snap({ members = { Member("me", "Anduin", "PRIEST", { hasStone = true }), Member("w1", "Gul'dan", "WARLOCK") } })), nil, "covered")
eq(S.Evaluate(Snap({ members = {
    Member("me", "Anduin", "PRIEST"), Member("d", "Malfurion", "DRUID", { hasStone = true }), Member("w1", "Gul'dan", "WARLOCK") } })), nil,
    "any rez member with a stone covers")
ok(S.Evaluate(Snap({ members = {
    Member("me", "Anduin", "PRIEST"), Member("x", "Garrosh", "WARRIOR", { hasStone = true }), Member("w1", "Gul'dan", "WARLOCK") } })) ~= nil,
    "stone on a warrior does not cover")

local tr = S.NewTracker()
ok(tr:Ready("unknown", 0), "unknown guid is ready")
tr:OnUsed("w1", 100)
eq(tr:Ready("w1", 100), false)
eq(tr:Ready("w1", 100 + 1799), false)
ok(tr:Ready("w1", 100 + 1800), "ready after 30 min")
ok(tr:Ready("w2", 200), "other guids unaffected")
tr:OnUsed("w1", 100)
eq(tr:Ready("w1", 1899), false, "same time is harmless")
tr:OnUsed("w1", 50)
eq(tr:Ready("w1", 1899), false, "older time does not move the cooldown back")
ok(tr:Ready("w1", 1900))
tr:OnUsed("w1", 500)
eq(tr:Ready("w1", 2299), false, "newer time moves it forward")

local used = S.NewTracker()
used:OnUsed("w1", 900)
eq(S.Evaluate(Snap({ tracker = used })), nil, "other warlock on cooldown")
eq(S.Evaluate(Snap({ tracker = used, members = { Member("me", "Anduin", "PRIEST") } })), nil, "warlock left")
eq(S.Evaluate(Snap({ tracker = used })), nil, "rejoined warlock keeps its cooldown")
ok(S.Evaluate(Snap({ tracker = used, now = 900 + 1800 })) ~= nil, "ready again after cooldown")

local selfSnap = function(ownReady, tracker)
    return Snap({ player = "me", tracker = tracker, members = {
        Member("me", "Gul'dan", "WARLOCK", { ownReady = ownReady }),
        Member("p", "Uther", "PALADIN"),
        Member("s", "Thrall", "SHAMAN", { isHealer = true }),
    } })
end
local own = S.NewTracker()
own:OnUsed("me", 1000)
local rs = S.Evaluate(selfSnap(true, own))
ok(rs ~= nil, "own warlock uses ownReady, not the tracker")
eq(rs.selfWarlock, true)
eq(rs.suggest, "Thrall", "healer first")
eq(#rs.rows, 2, "no Ready row for yourself")
eq(rs.rows[1], "No Soulstone on healer")
eq(rs.rows[2], "Put your soulstone on Thrall")
eq(#rs.whispers, 0, "never whispers yourself")
eq(rs.announce, "Soulstone ready (Gul'dan), no healer has one.")
eq(S.Evaluate(selfSnap(false, S.NewTracker())), nil, "own stone not ready")
eq(S.Evaluate(selfSnap(nil, S.NewTracker())), nil, "own row without ownReady is not ready")

local rn = S.Evaluate(Snap({ members = {
    Member("me", "Anduin", "PRIEST"),
    Member("p", "Uther", "PALADIN"),
    Member("w1", "Gul'dan-Draenor", "WARLOCK"),
    Member("w2", "Kanrethad", "WARLOCK"),
} }))
eq(rn.suggest, "Anduin", "first rez member without roles")
eq(#rn.rows, 3, "one row per ready warlock")
eq(rn.rows[2], "Ready: Gul'dan", "rows drop the realm")
eq(rn.rows[3], "Ready: Kanrethad")
eq(rn.announce, "Soulstone ready (Gul'dan-Draenor, Kanrethad), no healer has one.")
eq(#rn.whispers, 2)
eq(rn.whispers[1].target, "Gul'dan-Draenor", "realm kept in whisper target")
eq(rn.whispers[2].target, "Kanrethad")

local mixed = Snap({ player = "me", members = {
    Member("me", "Gul'dan", "WARLOCK", { ownReady = true }),
    Member("w2", "Kanrethad", "WARLOCK"),
    Member("p", "Uther", "PALADIN", { isHealer = true }),
} })
local rm = S.Evaluate(mixed)
eq(rm.selfWarlock, true)
eq(#rm.rows, 3); eq(rm.rows[2], "Put your soulstone on Uther"); eq(rm.rows[3], "Ready: Kanrethad", "other ready warlocks follow")
eq(#rm.whispers, 1); eq(rm.whispers[1].target, "Kanrethad")
eq(rm.whispers[1].text, "Your soulstone is ready; no healer has one. Suggest: Uther.")

local th = S.NewThrottle()
ok(th:Allow("combat1", 0), "first trigger")
eq(th:Allow("combat1", 100), false, "once per trigger")
eq(th:Allow("ready1", 30), false, "60 s gap")
ok(th:Allow("ready1", 60), "after the gap")
eq(th:Allow("ready2", 119), false)
ok(th:Allow("ready2", 120))

eq(S.WARLOCK_LEVEL, 18)
eq(S.REZ_LEVEL.PRIEST, 10); eq(S.REZ_LEVEL.PALADIN, 12); eq(S.REZ_LEVEL.SHAMAN, 12); eq(S.REZ_LEVEL.DRUID, 20)
local function Lv(rezClass, rezLevel, lockLevel)
    return S.Evaluate(Snap({ members = {
        Member("me", "Anduin", rezClass, { level = rezLevel }),
        Member("w1", "Gul'dan", "WARLOCK", { level = lockLevel }),
    } }))
end
eq(Lv("PRIEST", 60, 17), nil, "warlock under 18 has no stone")
ok(Lv("PRIEST", 60, 18) ~= nil, "warlock at 18")
eq(Lv("PRIEST", 9, 60), nil, "priest under 10 cannot resurrect")
ok(Lv("PRIEST", 10, 60) ~= nil)
eq(Lv("PALADIN", 11, 60), nil); ok(Lv("PALADIN", 12, 60) ~= nil)
eq(Lv("SHAMAN", 11, 60), nil); ok(Lv("SHAMAN", 12, 60) ~= nil)
eq(Lv("DRUID", 19, 60), nil, "druid needs Rebirth at 20"); ok(Lv("DRUID", 20, 60) ~= nil)
local low = S.Evaluate(Snap({ members = {
    Member("d", "Lowbie", "DRUID", { level = 15, isHealer = true }),
    Member("me", "Anduin", "PRIEST", { level = 60 }),
    Member("w1", "Gul'dan", "WARLOCK", { level = 60 }),
} }))
eq(low.suggest, "Anduin", "a rez class under its level is never suggested")
eq(S.Evaluate(Snap({ members = {
    Member("d", "Lowbie", "DRUID", { level = 15, hasStone = true }),
    Member("me", "Anduin", "PRIEST", { level = 60 }),
    Member("w1", "Gul'dan", "WARLOCK"),
} })) ~= nil, true, "a stone on a rez class under its level does not cover")

eq(S.Evaluate(Snap({ members = {
    Member("me", "Anduin", "PRIEST"), Member("w1", "Gul'dan", "WARLOCK", { connected = false }) } })), nil, "offline warlock skipped")
eq(S.Evaluate(Snap({ members = {
    Member("me", "Anduin", "PRIEST", { connected = false }), Member("w1", "Gul'dan", "WARLOCK") } })), nil, "offline healer skipped")
local off = S.Evaluate(Snap({ members = {
    Member("h", "Offline", "PRIEST", { connected = false, isHealer = true }),
    Member("me", "Anduin", "PALADIN"),
    Member("w1", "Gul'dan", "WARLOCK"),
    Member("w2", "Gone", "WARLOCK", { connected = false }),
} }))
eq(off.suggest, "Anduin", "never suggest an offline player")
eq(#off.whispers, 1); eq(off.whispers[1].target, "Gul'dan", "never whisper an offline player")
eq(S.Evaluate(Snap({ members = {
    Member("me", "Anduin", "PRIEST"), Member("p", "Far", "PALADIN", { visible = false }), Member("w1", "Gul'dan", "WARLOCK") } })), nil,
    "an unseen rez member makes the buff state unknown")
ok(S.Evaluate(Snap({ members = {
    Member("me", "Anduin", "PRIEST"), Member("x", "Far", "WARRIOR", { visible = false }), Member("w1", "Gul'dan", "WARLOCK") } })) ~= nil,
    "an unseen non-rez member does not matter")

eq(S.PEER_TTL, 300)
local peers = S.NewPeers()
ok(peers:Elected("Player-1-B", 0), "alone you are elected")
peers:Seen("Player-1-C", 10)
ok(peers:Elected("Player-1-B", 10), "lower than every peer")
peers:Seen("Player-1-A", 10)
eq(peers:Elected("Player-1-B", 10), false, "a lower peer wins")
ok(peers:Elected("Player-1-A", 10), "the lowest guid wins")
peers:Prune({ ["Player-1-B"] = true, ["Player-1-C"] = true }, 20)
ok(peers:Elected("Player-1-B", 20), "peer left the group")
peers:Seen("Player-1-A", 100)
eq(peers:Elected("Player-1-B", 400), false, "seen 300 s ago still counts")
ok(peers:Elected("Player-1-B", 401), "stale peer ignored")
peers:Prune({ ["Player-1-A"] = true, ["Player-1-B"] = true }, 401)
peers:Seen("Player-1-A", 50)
ok(peers:Elected("Player-1-B", 401), "stale peer pruned, older sighting does not revive it")
peers:Seen(nil, 500)
ok(peers:Elected("Player-1-B", 500), "nil id ignored")
