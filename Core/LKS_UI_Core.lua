if EUI_CLIENT_BLOCKED then return end

local ADDON_NAME, ns = ...
local EUI = EllesmereUI

ns.ID = ADDON_NAME
ns.LABEL = "LKS UI"
ns.IS_FOREVER = EUI.IS_FOREVER == true
ns.features = {}
ns.featureOrder = {}
_G.LKS_UI = ns

-- Lite.NewDB derives the profile folder from the name and wipes the matching global, so this must never be a declared SavedVariable.
local DB_NAME = ADDON_NAME .. "DB"
local db

local function Profile()
    if not db then
        db = EUI.Lite.NewDB(DB_NAME, { profile = { features = {} } })
    end
    return db.profile
end

function ns.Print(msg)
    print("|cff0cd29dLKS UI:|r " .. tostring(msg))
end

local function RunsOnThisClient(spec)
    if spec.clients == "retail" then return not ns.IS_FOREVER end
    if spec.clients == "forever" then return ns.IS_FOREVER end
    return true
end

--- spec: key, title, description?, clients? ("retail"|"forever"), defaults?,
--- enable(settings), buildOptions?(W, parent, y, settings) -> y
function ns.RegisterFeature(spec)
    assert(type(spec) == "table" and type(spec.key) == "string", "feature needs a key")
    assert(not ns.features[spec.key], "duplicate feature " .. spec.key)
    assert(type(spec.enable) == "function", "feature needs enable()")
    if not RunsOnThisClient(spec) then return end
    ns.features[spec.key] = spec
    ns.featureOrder[#ns.featureOrder + 1] = spec.key
end

function ns.GetSettings(key)
    local spec = ns.features[key]
    local all = Profile().features
    local s = all[key]
    if type(s) ~= "table" then
        s = {}
        all[key] = s
    end
    if spec and spec.defaults then
        for k, v in pairs(spec.defaults) do
            if s[k] == nil then s[k] = EUI.Lite.DeepCopy(v) end
        end
    end
    return s
end

function ns.IsEnabled(key)
    return ns.GetSettings(key).enabled == true
end

function ns.ResetFeature(key)
    Profile().features[key] = nil
end

local enabledThisSession = {}
function ns.WasEnabledAtLoad(key)
    return enabledThisSession[key] == true
end

local function EnableFeatures()
    for _, key in ipairs(ns.featureOrder) do
        if ns.IsEnabled(key) then
            local spec = ns.features[key]
            local ok = xpcall(spec.enable, geterrorhandler(), ns.GetSettings(key))
            enabledThisSession[key] = ok
        end
    end
end

local loader = CreateFrame("Frame")
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

SLASH_LKSUI1 = "/lks"
SLASH_LKSUI2 = "/lksui"
SlashCmdList.LKSUI = function()
    EUI.OpenPlugin(ns.ID)
end
