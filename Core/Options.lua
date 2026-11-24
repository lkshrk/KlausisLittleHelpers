local _, ns = ...

local RELOAD_POPUP = "KLH_RELOAD"

local function Prefix(text, desc)
    if not text then return desc end
    if type(desc) == "function" then
        return function(...)
            local d = desc(...)
            if d and d ~= "" then return text .. "\n" .. d end
            return text
        end
    end
    if desc and desc ~= "" then return text .. "\n" .. desc end
    return text
end

function ns.NotifyOptionsChanged()
    local registry = _G.LibStub and _G.LibStub("AceConfigRegistry-3.0", true)
    if registry then registry:NotifyChange(ns.ID) end
end

local function AskReload(key)
    if ns.IsEnabled(key) == ns.WasEnabledAtLoad(key) then return end
    if _G.StaticPopup_Show then _G.StaticPopup_Show(RELOAD_POPUP) end
end

local function ApplyOrAsk(key)
    if ns.features[key].disable then ns.ApplyFeature(key) else AskReload(key) end
end

local function ApplyChanges()
    for _, key in ipairs(ns.featureOrder) do
        if not ns.features[key].alwaysOn then ApplyOrAsk(key) end
    end
end

local function OnProfileSwap()
    ApplyChanges()
    for _, key in ipairs(ns.featureOrder) do
        local spec = ns.features[key]
        if spec.onReset and ns.IsRunning(key) then spec.onReset() end
    end
    ns.NotifyOptionsChanged()
end

local function OptionalText(spec, ctx)
    local names, missing = {}, {}
    for i, name in ipairs(spec.optional or {}) do
        local t = ctx.title and ctx.title(name)
        t = type(t) == "string" and ns.StripColors(t) or ""
        names[i] = t ~= "" and t or name
        if not ctx.isLoaded(name) then missing[#missing + 1] = names[i] end
    end
    if #names == 0 then return nil end
    local reason = type(spec.optionalReason) == "string" and spec.optionalReason ~= "" and spec.optionalReason or nil
    if #missing == 0 then return "Uses " .. table.concat(names, ", ") .. " if installed." end
    if reason then return "Install " .. table.concat(missing, ", ") .. " for " .. reason .. "." end
    return "Uses " .. table.concat(names, ", ") .. " if installed (not loaded)."
end

local function FeatureGroup(spec, index, ctx)
    local key = spec.key
    local args = spec.options and spec.options(ctx.settings and ctx.settings(key)) or {}
    if not spec.alwaysOn then
        args.enabled = {
            type = "toggle", order = 0.5, width = "full",
            name = "Enable " .. spec.title, desc = spec.description,
            get = function() return ns.IsEnabled(key) end,
            set = function(_, v)
                ns.GetSettings(key).enabled = v or nil
                ApplyOrAsk(key)
                if spec.disable then ns.NotifyOptionsChanged() end
            end,
        }
    end
    local missing = ns.MissingAddons(spec, ctx.isLoaded)
    local requires = #missing > 0 and ns.RequiresText(missing, ctx.title) or nil
    if requires then
        for _, arg in pairs(args) do
            arg.desc = Prefix(requires, arg.desc)
            arg.disabled = true
        end
        args.requires = { type = "description", order = 0, fontSize = "medium", name = requires }
    end
    if spec.help then
        args.help = { type = "description", order = 0.2, fontSize = "medium", name = spec.help }
    end
    local optional = OptionalText(spec, ctx)
    if optional then
        args.optional = { type = "description", order = 0.3, fontSize = "medium", name = optional }
    end
    return {
        type = "group", order = index, inline = true,
        name = requires and ("|cff808080" .. spec.title .. "|r") or spec.title,
        desc = Prefix(requires, spec.description),
        args = args,
    }, requires
end

local TABS = {
    { key = "qol", name = "QoL" },
    { key = "helpers", name = "Helpers" },
    { key = "thirdparty", name = "3rd Party" },
}

local function AddonVersion()
    local meta = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    local version = meta and meta(ns.ID, "Version")
    if type(version) ~= "string" or version == "" then return "unknown" end
    return version
end

local function AboutText(ctx)
    local lines = {
        ns.LABEL .. " " .. (ctx.version or AddonVersion()),
        "Small helpers for questing, routes and professions.",
        "",
        "/klh opens this window.",
        "/klh <command> runs a feature command; a wrong name lists the known ones.",
        "A feature whose addons are missing stays greyed with a Requires line.",
        "This window is also under Esc > Options > AddOns.",
    }
    return table.concat(lines, "\n")
end

function ns.BuildOptionsTable(features, order, ctx)
    local sections, gated = {}, {}
    for _, tab in ipairs(TABS) do sections[tab.key] = {} end
    for index, key in ipairs(order) do
        local spec = features[key]
        if spec and ns.ClientAllows(spec.key, ctx.isForever) then
            local group, requires = FeatureGroup(spec, index, ctx)
            local tab = sections[spec.tab] and spec.tab or "helpers"
            local name = type(spec.section) == "string" and spec.section ~= "" and spec.section or nil
            if name then
                local sectionKey = "section_" .. name:gsub("[^%w]", "")
                local holder = sections[tab][sectionKey]
                if not holder then
                    holder = { type = "group", inline = true, order = index, name = name, args = {} }
                    sections[tab][sectionKey] = holder
                end
                holder.args[key] = group
            else
                sections[tab][key] = group
            end
            if requires then gated[#gated + 1] = spec.title .. ": " .. requires end
        end
    end
    local general = {
        about = {
            type = "group", order = 1, inline = true, name = "About",
            args = { text = { type = "description", order = 1, fontSize = "medium", name = AboutText(ctx) } },
        },
    }
    if #gated > 0 then
        general.unavailable = { type = "description", order = 2, fontSize = "medium", name = table.concat(gated, "\n") }
    end
    local args = { general = { type = "group", order = 1, name = "General", args = general } }
    for position, tab in ipairs(TABS) do
        if next(sections[tab.key]) then
            args[tab.key] = { type = "group", order = position + 1, name = tab.name, args = sections[tab.key] }
        end
    end
    if ctx.profiles then
        ctx.profiles.order = 1000
        args.profiles = ctx.profiles
    end
    return { type = "group", name = ns.LABEL, childGroups = "tab", args = args }
end

function ns.CloseOptions()
    local LS = _G.LibStub
    local dialog = LS and LS("AceConfigDialog-3.0", true)
    if dialog then dialog:Close(ns.ID) end
    local panel = _G.SettingsPanel
    if panel and panel:IsShown() then
        if panel.Close then panel:Close(true) elseif _G.HideUIPanel then _G.HideUIPanel(panel) else panel:Hide() end
    end
end

function ns.OpenOptions()
    _G.LibStub("AceConfigDialog-3.0"):Open(ns.ID)
end

local function RegisterReloadPopup()
    if not _G.StaticPopupDialogs then return end
    _G.StaticPopupDialogs[RELOAD_POPUP] = {
        text = "Turning a Klausi's Little Helpers feature on or off takes effect after a reload.",
        button1 = "Reload",
        button2 = "Later",
        OnAccept = function() _G.ReloadUI() end,
        -- Blizzard resets the strata on every show; the options window sits above DIALOG.
        OnShow = function(dialog) dialog:SetFrameStrata("FULLSCREEN_DIALOG") end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

-- AceConfigDialog closes its windows with the Blizzard settings panel, so leave that panel first.
local function OpenFromSettingsNow()
    local panel = _G.SettingsPanel
    if panel and panel:IsShown() then
        if panel.Close then
            panel:Close(true)
        elseif _G.HideUIPanel then
            _G.HideUIPanel(panel)
        else
            panel:Hide()
        end
    end
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, ns.OpenOptions)
    else
        ns.OpenOptions()
    end
end

function ns.OpenFromSettings()
    if ns.UI and ns.UI.Defer then
        ns.UI.Defer("KLH_OpenFromSettings", OpenFromSettingsNow)
    else
        OpenFromSettingsNow()
    end
end

local function RegisterBlizzardEntry()
    local settings = _G.Settings
    if not (settings and settings.RegisterCanvasLayoutCategory and settings.RegisterAddOnCategory) then return end
    local panel = _G.CreateFrame("Frame")
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(ns.LABEL)
    local button = _G.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(240, 24)
    button:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    button:SetText("Open " .. ns.LABEL)
    button:SetScript("OnClick", function() ns.OpenFromSettings() end)
    settings.RegisterAddOnCategory(settings.RegisterCanvasLayoutCategory(panel, ns.LABEL))
end

function ns.RegisterOptions()
    local LibStub = _G.LibStub
    local db = ns.GetDB()
    local ctx = {
        isForever = ns.IS_FOREVER,
        isLoaded = ns.AddonLoaded,
        title = ns.AddonTitle,
        settings = ns.GetSettings,
        profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(db),
    }
    for _, event in ipairs({ "OnProfileChanged", "OnProfileCopied", "OnProfileReset" }) do
        db.RegisterCallback(ns, event, OnProfileSwap)
    end
    LibStub("AceConfig-3.0"):RegisterOptionsTable(ns.ID, function()
        return ns.BuildOptionsTable(ns.features, ns.featureOrder, ctx)
    end)
    LibStub("AceConfigDialog-3.0"):SetDefaultSize(ns.ID, 760, 560)
    RegisterReloadPopup()
    RegisterBlizzardEntry()
end
