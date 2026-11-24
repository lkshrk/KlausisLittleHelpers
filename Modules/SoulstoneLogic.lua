local _, ns = ...

local Soulstone = {}
ns.Soulstone = Soulstone

Soulstone.REZ_CLASSES = { PRIEST = true, PALADIN = true, SHAMAN = true, DRUID = true }
Soulstone.REZ_LEVEL = { PRIEST = 10, PALADIN = 12, SHAMAN = 12, DRUID = 20 }
Soulstone.WARLOCK_LEVEL = 18
Soulstone.COOLDOWN = 1800
Soulstone.CHAT_GAP = 60

local HEADLINE = "No Soulstone on healer"
Soulstone.HEADLINE = HEADLINE

function Soulstone.NewTracker()
    local used = {}
    local tracker = {}
    function tracker.OnUsed(_, guid, now)
        if guid and type(now) == "number" and (used[guid] == nil or now > used[guid]) then used[guid] = now end
    end
    function tracker.Ready(_, guid, now)
        local last = guid and used[guid]
        return last == nil or now - last >= Soulstone.COOLDOWN
    end
    return tracker
end

function Soulstone.NewThrottle()
    local seen, last = {}, nil
    local throttle = {}
    function throttle.Allow(_, trigger, now)
        if trigger == nil or seen[trigger] then return false end
        if last and now - last < Soulstone.CHAT_GAP then return false end
        seen[trigger] = true
        last = now
        return true
    end
    return throttle
end

Soulstone.PEER_TTL = 300

function Soulstone.NewPeers()
    local seen = {}
    local peers = {}
    function peers.Seen(_, id, now)
        if id and type(now) == "number" and (seen[id] == nil or now > seen[id]) then seen[id] = now end
    end
    function peers.Prune(_, roster, now)
        for id, last in pairs(seen) do
            if not roster[id] or now - last > Soulstone.PEER_TTL then seen[id] = nil end
        end
    end
    function peers.Elected(_, self, now)
        for id, last in pairs(seen) do
            if id ~= self and now - last <= Soulstone.PEER_TTL and id < self then return false end
        end
        return true
    end
    return peers
end

local function InstanceAllowed(instance, allowed)
    if instance ~= "party" and instance ~= "raid" then return false end
    return allowed == "both" or allowed == instance
end

local function AtLeast(member, level)
    return member.level == nil or member.level >= level
end

local function IsReady(member, snap)
    if member.guid == snap.player then return member.ownReady == true end
    return snap.tracker == nil or snap.tracker:Ready(member.guid, snap.now)
end

function Soulstone.Evaluate(snap)
    if not InstanceAllowed(snap.instance, snap.allowed) or snap.inCombat then return nil end
    local rez, healer, ready, readyMembers = nil, nil, {}, {}
    local selfWarlock = false
    for _, m in ipairs(snap.members or {}) do
        local online = m.connected ~= false
        local rezLevel = online and Soulstone.REZ_LEVEL[m.class]
        if rezLevel and AtLeast(m, rezLevel) then
            if m.visible == false or m.hasStone then return nil end
            rez = rez or m.name
            if m.isHealer and not healer then healer = m.name end
        elseif online and m.class == "WARLOCK" and AtLeast(m, Soulstone.WARLOCK_LEVEL) and IsReady(m, snap) then
            ready[#ready + 1] = m.name
            readyMembers[#readyMembers + 1] = m
            if m.guid == snap.player then selfWarlock = true end
        end
    end
    if not rez or #ready == 0 then return nil end
    local suggest = healer or rez
    local names = table.concat(ready, ", ")
    local whispers = {}
    for _, m in ipairs(readyMembers) do
        if m.guid ~= snap.player then
            whispers[#whispers + 1] = {
                target = m.name,
                text = "Your soulstone is ready; no healer has one. Suggest: " .. suggest .. ".",
            }
        end
    end
    local rows = { HEADLINE }
    if selfWarlock then rows[2] = "Put your soulstone on " .. suggest end
    for _, m in ipairs(readyMembers) do
        if m.guid ~= snap.player then rows[#rows + 1] = "Ready: " .. (m.name:match("^([^-]+)") or m.name) end
    end
    return {
        readyWarlocks = ready,
        suggest = suggest,
        selfWarlock = selfWarlock,
        rows = rows,
        announce = "Soulstone ready (" .. names .. "), no healer has one.",
        whispers = whispers,
    }
end
