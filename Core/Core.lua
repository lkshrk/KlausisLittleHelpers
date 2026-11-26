local ADDON_NAME, ns = ...

local function DetectForever()
    local build = _G.GetBuildInfo and select(4, _G.GetBuildInfo())
    return type(build) == "number" and build >= 16000 and build < 20000
end

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = DeepCopy(x) end
    return out
end

ns.ID = ADDON_NAME
ns.LABEL = "Klausi's Little Helpers"
ns.IS_FOREVER = DetectForever()
ns.features = {}
ns.featureOrder = {}
_G.KLH = ns

local db

local function Profile()
    if not db then
        db = _G.LibStub("AceDB-3.0"):New("KLH_DB", { profile = { features = {} } })
    end
    return db.profile
end

function ns.GetDB()
    Profile()
    return db
end

function ns.Print(msg)
    print("|cff0cd29dKLH:|r " .. tostring(msg))
end

-- A feature missing from this table loads on no client.
ns.FEATURE_CLIENTS = {
    TustUIXPBar = "all",
    QuestieRXPSync = "forever",
    TurnInRoute = "forever",
    WritCratePlanner = "forever",
    SoulstoneReminder = "forever",
    LayerPrompt = "forever",
}

function ns.ClientAllows(key, isForever)
    local clients = ns.FEATURE_CLIENTS[key]
    if clients == "all" then return true end
    if clients == "forever" then return isForever == true end
    if clients == "retail" then return isForever ~= true end
    return false
end

function ns.MissingAddons(spec, isLoaded)
    local missing = {}
    for _, name in ipairs(spec.requires or {}) do
        if not isLoaded(name) then missing[#missing + 1] = name end
    end
    return missing
end

local function StripColors(s)
    s = s:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return (s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end
ns.StripColors = StripColors

function ns.RequiresText(missing, title)
    local names = {}
    for i, name in ipairs(missing) do
        local t = title and title(name)
        t = type(t) == "string" and StripColors(t) or ""
        names[i] = t ~= "" and t or name
    end
    return "Requires: " .. table.concat(names, ", ")
end

function ns.AddonTitle(name)
    local get = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata
    if not get then return nil end
    local good, title = pcall(get, name, "Title")
    return good and title or nil
end

function ns.ShouldEnable(spec, ctx)
    if not ns.ClientAllows(spec.key, ctx.isForever) then return false end
    if #ns.MissingAddons(spec, ctx.isLoaded) > 0 then return false end
    return spec.alwaysOn == true or ctx.enabled == true
end

local commandOwner, readThrough, unlistedWarned = {}, {}, {}

local function ReadThrough(defaults)
    return { __index = function(t, k)
        local v = defaults[k]
        if type(v) == "table" then
            v = DeepCopy(v)
            rawset(t, k, v)
        end
        return v
    end }
end

function ns.RegisterFeature(spec)
    assert(type(spec) == "table" and type(spec.key) == "string", "feature needs a key")
    assert(not ns.features[spec.key], "duplicate feature " .. spec.key)
    assert(type(spec.enable) == "function", "feature needs enable()")
    if ns.FEATURE_CLIENTS[spec.key] == nil then
        if not unlistedWarned[spec.key] then
            unlistedWarned[spec.key] = true
            ns.Print("Developer error: feature " .. spec.key .. " is missing from ns.FEATURE_CLIENTS and loads nowhere.")
        end
        return
    end
    if not ns.ClientAllows(spec.key, ns.IS_FOREVER) then return end
    ns.features[spec.key] = spec
    if spec.defaults then readThrough[spec.key] = ReadThrough(spec.defaults) end
    ns.featureOrder[#ns.featureOrder + 1] = spec.key
    for _, name in ipairs(spec.commands or {}) do commandOwner[name:lower()] = spec.key end
end

function ns.GetSettings(key)
    local all = Profile().features
    local s = all[key]
    if type(s) ~= "table" then
        s = {}
        all[key] = s
    end
    local mt = readThrough[key]
    if mt and getmetatable(s) == nil then setmetatable(s, mt) end
    return s
end

function ns.CharData(key)
    local root = _G.KLH_CharDB
    if type(root) ~= "table" then
        root = {}
        _G.KLH_CharDB = root
    end
    if type(root[key]) ~= "table" then root[key] = {} end
    return root[key]
end

function ns.IsEnabled(key)
    local spec = ns.features[key]
    if spec and spec.alwaysOn then return true end
    return ns.GetSettings(key).enabled == true
end

function ns.ResetFeature(key)
    Profile().features[key] = nil
end

local enabledAtLoad = {}
function ns.WasEnabledAtLoad(key)
    return enabledAtLoad[key] == true
end
function ns.IsRunning(key)
    return ns.WasEnabledAtLoad(key)
end

local function AddonLoaded(name)
    local fn = _G.C_AddOns and _G.C_AddOns.IsAddOnLoaded or _G.IsAddOnLoaded
    return fn and fn(name) == true or false
end
ns.AddonLoaded = AddonLoaded

local function EnableFeatures()
    for _, key in ipairs(ns.featureOrder) do
        local spec = ns.features[key]
        local ctx = { isForever = ns.IS_FOREVER, isLoaded = AddonLoaded, enabled = ns.IsEnabled(key) }
        if ns.ShouldEnable(spec, ctx) then
            enabledAtLoad[key] = true
            xpcall(spec.enable, _G.geterrorhandler(), ns.GetSettings(key))
        end
    end
end

function ns.ApplyFeature(key)
    local spec = ns.features[key]
    if not (spec and spec.disable) then return end
    local ctx = { isForever = ns.IS_FOREVER, isLoaded = AddonLoaded, enabled = ns.IsEnabled(key) }
    local should = ns.ShouldEnable(spec, ctx)
    if should and not enabledAtLoad[key] then
        enabledAtLoad[key] = true
        xpcall(spec.enable, _G.geterrorhandler(), ns.GetSettings(key))
    elseif enabledAtLoad[key] and not should then
        enabledAtLoad[key] = nil
        xpcall(spec.disable, _G.geterrorhandler(), ns.GetSettings(key))
    end
end

if _G.CreateFrame then
    local loader = _G.CreateFrame("Frame")
    loader:RegisterEvent("ADDON_LOADED")
    loader:RegisterEvent("PLAYER_LOGIN")
    loader:SetScript("OnEvent", function(self, event, name)
        if event == "ADDON_LOADED" then
            if name ~= ADDON_NAME then return end
            self:UnregisterEvent("ADDON_LOADED")
            ns.RegisterOptions()
        else
            self:UnregisterEvent("PLAYER_LOGIN")
            EnableFeatures()
        end
    end)
end

local commands, commandOrder = {}, {}

--- /klh <name> <rest> calls fn(rest).
function ns.RegisterSlashCommand(name, fn)
    assert(type(name) == "string" and type(fn) == "function", "slash command needs a name and a function")
    name = name:lower()
    assert(not commands[name], "duplicate slash command " .. name)
    commands[name] = fn
    commandOrder[#commandOrder + 1] = name
end

local function OnSlash(msg)
    local name, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    if not name or name == "" then
        ns.OpenOptions()
        return
    end
    local fn = commands[name:lower()]
    local owner = ns.features[commandOwner[name:lower()] or ""]
    local missing = owner and ns.MissingAddons(owner, AddonLoaded) or {}
    if fn then
        fn(rest)
    elseif #missing > 0 then
        ns.Print(owner.title .. ": " .. ns.RequiresText(missing, ns.AddonTitle))
    elseif #commandOrder == 0 then
        ns.Print("Unknown command " .. name .. ". /klh opens the options.")
    else
        ns.Print("Unknown command " .. name .. ". Known: " .. table.concat(commandOrder, ", ") .. ". /klh alone opens the options.")
    end
end

if _G.SlashCmdList then
    _G.SLASH_KLH1 = "/klh"
    _G.SlashCmdList.KLH = OnSlash
end
