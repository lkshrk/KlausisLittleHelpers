if EUI_CLIENT_BLOCKED then return end

local _, ns = ...
local EUI = EllesmereUI

local MAX_FEATURE_MODULES = 19

local function AskReload(key)
    if ns.IsEnabled(key) == ns.WasEnabledAtLoad(key) then return end
    EUI:ShowConfirmPopup({
        title = "Reload Required",
        message = "Turning a LKS UI feature on or off takes effect after a reload.",
        confirmText = "Reload",
        cancelText = "Later",
        reload = true,
    })
end

local function FeatureToggle(key)
    local spec = ns.features[key]
    return {
        type = "toggle",
        text = spec.title,
        tooltip = spec.description,
        getValue = function() return ns.IsEnabled(key) end,
        setValue = function(v)
            ns.GetSettings(key).enabled = v or nil
            EUI:RefreshPage()
            AskReload(key)
        end,
    }
end

local function BuildFeaturesPage(_, parent, yOffset)
    local W = EUI.Widgets
    local y = yOffset
    local _, h
    if #ns.featureOrder == 0 then
        _, h = W:SectionHeader(parent, "NO FEATURES INSTALLED", y); y = y - h
        return math.abs(y)
    end
    _, h = W:SectionHeader(parent, "FEATURES", y); y = y - h
    local order = ns.featureOrder
    for i = 1, #order, 2 do
        local right = order[i + 1] and FeatureToggle(order[i + 1]) or EUI.BlankRowCfg()
        _, h = W:DualRow(parent, y, FeatureToggle(order[i]), right); y = y - h
    end
    return math.abs(y)
end

local function FeatureModule(spec)
    local key = spec.key
    return {
        key = key,
        title = spec.title,
        description = spec.description,
        pages = { spec.title },
        buildPage = function(_, parent, yOffset)
            local y = spec.buildOptions(EUI.Widgets, parent, yOffset, ns.GetSettings(key))
            return math.abs(y)
        end,
        onReset = function()
            local wasEnabled = ns.IsEnabled(key)
            ns.ResetFeature(key)
            ns.GetSettings(key).enabled = wasEnabled or nil
            EUI:RefreshPage(true)
        end,
    }
end

function ns.RegisterOptions()
    local modules = {
        {
            key = "General",
            title = "General",
            description = "Optional additions to EllesmereUI. Every feature starts off.",
            pages = { "Features" },
            buildPage = BuildFeaturesPage,
        },
    }
    for _, key in ipairs(ns.featureOrder) do
        local spec = ns.features[key]
        if spec.buildOptions and #modules <= MAX_FEATURE_MODULES then
            modules[#modules + 1] = FeatureModule(spec)
        end
    end
    EUI.RegisterPlugin(ns.ID, { label = ns.LABEL, position = "top", modules = modules })
end
