addon("Core/Core.lua"); addon("Core/Options.lua")
ns.FEATURE_CLIENTS.A, ns.FEATURE_CLIENTS.B, ns.FEATURE_CLIENTS.C, ns.FEATURE_CLIENTS.D = "forever", "retail", "all", "forever"
local features = {
    A = { key = "A", title = "Quest Sync", tab = "qol", description = "d", requires = { "Questie", "RXPGuides" }, options = function() return { x = { type = "toggle", name = "X" } } end },
    B = { key = "B", title = "Route", alwaysOn = true },
}
local ctx = { isForever = true, isLoaded = function(n) return n == "Questie" end,
              title = function(n) return ({ Questie = "|cffffffffQuestie|r" })[n] end }
local t = ns.BuildOptionsTable(features, { "A", "B" }, ctx)
eq(t.childGroups, "tab")
local a = t.args.qol.args.A
eq(a.type, "group"); eq(a.inline, true)
eq(a.name, "|cff808080Quest Sync|r")
ok(a.args.requires.name:find("Requires: RXPGuides", 1, true), "section states it")
eq(a.args.requires.disabled, nil); eq(a.args.requires.order, 0); eq(a.args.enabled.order, 0.5)
ok(a.args.x.order == nil or a.args.x.order >= 1, "feature args after the header lines")
for k, arg in pairs(a.args) do
    if k ~= "requires" and k ~= "help" then eq(arg.disabled, true, k .. " disabled") end
end
ok(a.args.x.desc:find("^Requires: RXPGuides"), "args carry it too")
ok(a.args.enabled ~= nil, "switchable feature has an enable toggle")
eq(a.args.reset, nil, "no per-feature reset button")
eq(t.args.helpers, nil, "retail-only feature and its tab left out on Forever")
eq(t.args.A, nil); eq(t.args.B, nil)

eq(t.type, "group"); eq(t.name, ns.LABEL)
local general = t.args.general
eq(general.type, "group"); eq(general.name, "General")
eq(general.args.about.inline, true)
ok(general.args.about.args.text.name:find("/klh", 1, true), "About explains /klh")
ok(general.args.about.args.text.name:find(ns.LABEL, 1, true), "About names the addon")
ok(general.args.unavailable.name:find("Quest Sync: Requires: RXPGuides", 1, true), "General lists gated features")
eq(t.args.thirdparty, nil, "empty tab omitted")
ok(t.args.profiles == nil, "no profiles without ctx.profiles")

local more = {
    C = { key = "C", title = "Planner", tab = "helpers", alwaysOn = true, requires = { "Auctionator" },
          options = function(s) return { y = { type = "toggle", name = "Y", desc = "why", get = function() return s.v end } } end },
    D = { key = "D", title = "Bar", tab = "thirdparty", alwaysOn = true, requires = { "Tust_EUI" } },
    F = { key = "F", title = "Untabbed", alwaysOn = true },
}
ns.FEATURE_CLIENTS.F = "all"
local seen
local ctx2 = { isForever = true, isLoaded = function(n) return n == "Tust_EUI" end,
               title = function(n) return ({ Auctionator = "|cff00ff00Auction|rator" })[n] end,
               settings = function(key) seen = key; return { v = true } end,
               profiles = { type = "group", name = "Profiles", args = {} } }
local t2 = ns.BuildOptionsTable(more, { "D", "C", "F" }, ctx2)
local c, d2 = t2.args.helpers.args.C, t2.args.thirdparty.args.D
eq(c.args.y.desc, "Requires: Auctionator\nwhy")
eq(c.args.enabled, nil)
eq(seen, "C")
eq(d2.disabled, nil); eq(d2.name, "Bar"); eq(d2.args.requires, nil)
eq(d2.args.reset, nil)
ok(t2.args.helpers.args.F ~= nil, "missing tab defaults to helpers")
ok(c.order < t2.args.helpers.args.F.order, "groups follow registration order")
eq(t2.args.qol, nil, "empty tab omitted")

local keys2 = {}
for k in pairs(t2.args) do keys2[#keys2 + 1] = k end
table.sort(keys2, function(x, y) return t2.args[x].order < t2.args[y].order end)
eq(table.concat(keys2, ","), "general,helpers,thirdparty,profiles", "tab order")
ok(t2.args.profiles.order > t2.args.thirdparty.order, "profiles last")

local full = {
    A = { key = "A", title = "QS", tab = "qol", alwaysOn = true },
    B = { key = "B", title = "TR", tab = "helpers", alwaysOn = true },
    C = { key = "C", title = "WP", tab = "helpers", alwaysOn = true },
    D = { key = "D", title = "XP", tab = "thirdparty", alwaysOn = true },
}
ns.FEATURE_CLIENTS.A = "all"; ns.FEATURE_CLIENTS.B = "all"
local ctx3 = { isForever = true, isLoaded = function() return true end, profiles = { type = "group", name = "Profiles", args = {} } }
local t5 = ns.BuildOptionsTable(full, { "A", "B", "C", "D" }, ctx3)
local keys5 = {}
for k in pairs(t5.args) do keys5[#keys5 + 1] = k end
table.sort(keys5, function(x, y) return t5.args[x].order < t5.args[y].order end)
eq(table.concat(keys5, ","), "general,qol,helpers,thirdparty,profiles")
ok(t5.args.qol.args.A and t5.args.helpers.args.B and t5.args.helpers.args.C and t5.args.thirdparty.args.D, "features in their tabs")
ok(t5.args.helpers.args.B.order < t5.args.helpers.args.C.order, "registration order inside a tab")
eq(t5.args.general.args.unavailable, nil)
local t6 = ns.BuildOptionsTable(full, { "A", "B", "C", "D" }, { isForever = false, isLoaded = ctx3.isLoaded, profiles = { type = "group", name = "Profiles", args = {} } })
ok(t6.args.general and t6.args.profiles, "retail keeps General and Profiles")
ns.FEATURE_CLIENTS.A, ns.FEATURE_CLIENTS.B = "forever", "retail"

eq(ns.RequiresText({ "A", "B" }, function(n) return n == "B" and "|cffff0000Bee|r" or "" end), "Requires: A, Bee")

dofile("Libs/LibStub/LibStub.lua")
dofile("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")
dofile("Libs/AceConfig-3.0/AceConfigRegistry-3.0/AceConfigRegistry-3.0.lua")
local registry = _G.LibStub("AceConfigRegistry-3.0")
local function valid(tab, name)
    local good, problem = pcall(registry.ValidateOptionsTable, registry, tab, name)
    ok(good, tostring(problem))
end
valid(t, "t"); valid(t2, "t2"); valid(t5, "t5")

local specs = {}
local stub = setmetatable({
    RegisterFeature = function(spec) specs[#specs + 1] = spec end,
    GetSettings = function() return {} end,
    UI = {}, Data = {}, WritState = {}, WritSearch = {},
    CreateListWindow = function() return {} end,
}, { __index = ns })
for _, path in ipairs({ "Modules/TustUIXPBar.lua", "Modules/QuestieRXPSync.lua", "Modules/TurnInRoute.lua", "Modules/WritCratePlanner.lua" }) do
    local chunk = assert(loadfile(path))
    chunk("KlausisLittleHelpers", stub)
end
eq(#specs, 4)
local tabOf = {}
local titleOf = {}
for _, spec in ipairs(specs) do
    tabOf[spec.key] = spec.tab
    titleOf[spec.key] = spec.title
    ok(type(spec.help) == "string" and #spec.help > 40, spec.key .. " has a help text")
end
eq(titleOf.QuestieRXPSync, "RestedXP Quest Sync"); eq(titleOf.TustUIXPBar, "TustUI Enhanced XP Bar")
eq(tabOf.QuestieRXPSync, "thirdparty"); eq(tabOf.TurnInRoute, "helpers"); eq(tabOf.WritCratePlanner, "helpers"); eq(tabOf.TustUIXPBar, "thirdparty")
local all, keys = {}, {}
for _, spec in ipairs(specs) do all[spec.key] = spec; keys[#keys + 1] = spec.key end
for _, spec in ipairs(specs) do
    for k, arg in pairs(spec.options and spec.options({}) or {}) do
        ok(arg.order and arg.order >= 1, spec.key .. "." .. k .. " order >= 1")
    end
end
valid(ns.BuildOptionsTable(all, keys, { isForever = true, isLoaded = function() return true end, settings = function() return {} end }), "modules")
eq(all.WritCratePlanner.commands[1], "writs")
_G.LibStub = nil

local callbacks, popups, notified = {}, 0, 0
local fakeDB = { global = {}, profile = { features = {} }, RegisterCallback = function(_, event, fn) callbacks[event] = fn end }
local libs = {
    ["AceDB-3.0"] = { New = function() return fakeDB end },
    ["AceDBOptions-3.0"] = { GetOptionsTable = function() return {} end },
    ["AceConfig-3.0"] = { RegisterOptionsTable = function() end },
    ["AceConfigDialog-3.0"] = { SetDefaultSize = function() end },
    ["AceConfigRegistry-3.0"] = { NotifyChange = function() notified = notified + 1 end },
}
_G.LibStub = function(name) return libs[name] end
_G.StaticPopup_Show = function() popups = popups + 1 end
ns.FEATURE_CLIENTS.Sw, ns.FEATURE_CLIENTS.On = "all", "all"
ns.RegisterFeature({ key = "Sw", title = "Switchable", enable = function() end })
local redraws = 0
ns.RegisterFeature({ key = "On", title = "Always", alwaysOn = true, enable = function() end, onReset = function() redraws = redraws + 1 end })
local realLoaded = ns.WasEnabledAtLoad
ns.WasEnabledAtLoad = function(key) return key == "On" end
ns.RegisterOptions()
for _, event in ipairs({ "OnProfileChanged", "OnProfileCopied", "OnProfileReset" }) do
    ok(callbacks[event], event .. " registered")
end
callbacks.OnProfileChanged()
eq(popups, 0, "no reload ask while switchable state matches load"); eq(notified, 1)
fakeDB.profile.features.Sw = { enabled = true }
callbacks.OnProfileReset()
eq(popups, 1, "reload asked once the profile flips a switchable feature"); eq(notified, 2)
eq(redraws, 2, "running features redraw after each profile change")
ns.WasEnabledAtLoad = realLoaded
_G.LibStub = nil; _G.StaticPopup_Show = nil

local t3 = ns.BuildOptionsTable(features, { "A", "B" }, { isForever = false, isLoaded = function() return true end, title = function() end })
eq(t3.args.qol, nil); ok(t3.args.helpers.args.B ~= nil, "retail shows retail features and hides Forever ones")

local fn = {
    E = { key = "E", title = "Fn", alwaysOn = true, requires = { "Auctionator" },
          options = function() return { z = { type = "select", name = "Z", desc = function() return "dyn" end } } end },
}
ns.FEATURE_CLIENTS.E = "forever"
local t4 = ns.BuildOptionsTable(fn, { "E" }, ctx2)
local d = t4.args.helpers.args.E.args.z.desc
eq(type(d), "function"); ok(d():find("^Requires:"), "function desc is prefixed"); ok(d():find("dyn", 1, true))

local hf = { H = { key = "H", title = "Helped", alwaysOn = true, help = "Use it on the map.", enable = function() end } }
ns.FEATURE_CLIENTS.H = "all"
local th = ns.BuildOptionsTable(hf, { "H" }, { isForever = true, isLoaded = function() return true end, title = function() end })
local hs = th.args.helpers.args.H.args.help
eq(hs.type, "description"); eq(hs.name, "Use it on the map.")
ok(hs.order > 0 and hs.order < 0.5, "help sits after the requires line and before the enable toggle")

local optFeatures = {
    P = { key = "P", title = "Plain", tab = "helpers", alwaysOn = true, optional = { "TomTom" } },
    R = { key = "R", title = "Reasoned", tab = "helpers", alwaysOn = true, optional = { "TomTom", "Auctionator" }, optionalReason = "waypoints" },
    N = { key = "N", title = "None", tab = "helpers", alwaysOn = true },
}
ns.FEATURE_CLIENTS.P, ns.FEATURE_CLIENTS.R, ns.FEATURE_CLIENTS.N = "all", "all", "all"
local function optText(loaded)
    local tt = ns.BuildOptionsTable(optFeatures, { "P", "R", "N" }, { isForever = true,
        isLoaded = function(n) return loaded[n] == true end,
        title = function(n) return ({ TomTom = "|cffffffffTom|rTom" })[n] end })
    local g = tt.args.helpers.args
    return g.P.args.optional and g.P.args.optional.name, g.R.args.optional and g.R.args.optional.name, g.N.args.optional
end
local p1, r1, n1 = optText({})
eq(p1, "Uses TomTom if installed (not loaded).", "no reason: neutral line")
eq(r1, "Install TomTom, Auctionator for waypoints.", "reason: install hint")
eq(n1, nil, "no optional addons, no line")
local p2, r2 = optText({ TomTom = true, Auctionator = true })
eq(p2, "Uses TomTom if installed."); eq(r2, "Uses TomTom, Auctionator if installed.")
local _, r3 = optText({ TomTom = true })
eq(r3, "Install Auctionator for waypoints.", "only missing addons named")

local sectioned = {
    S1 = { key = "S1", title = "First", tab = "qol", section = "Dungeons & Raids", alwaysOn = true },
    S0 = { key = "S0", title = "Loose", tab = "qol", alwaysOn = true },
    S2 = { key = "S2", title = "Second", tab = "qol", section = "Dungeons & Raids", alwaysOn = true },
}
ns.FEATURE_CLIENTS.S0, ns.FEATURE_CLIENTS.S1, ns.FEATURE_CLIENTS.S2 = "all", "all", "all"
local ts = ns.BuildOptionsTable(sectioned, { "S1", "S0", "S2" }, { isForever = true, isLoaded = function() return true end })
ok(ts.args.qol ~= nil, "QoL tab present")
local qargs = ts.args.qol.args
local groupKey, groupCount
for k, v in pairs(qargs) do
    if v.name == "Dungeons & Raids" then groupKey, groupCount = k, (groupCount or 0) + 1 end
end
eq(groupCount, 1, "one section group")
local sg = qargs[groupKey]
ok(groupKey:find("^section_"), "section key prefixed")
eq(sg.type, "group"); eq(sg.inline, true)
local h1, h2 = sg.args.S1_header, sg.args.S2_header
ok(h1 and h2, "each sectioned feature gets a header inside the section")
eq(h1.type, "header"); eq(h1.name, "First")
for k, v in pairs(sg.args) do ok(v.type ~= "group", "no box inside a section: " .. k) end
eq(qargs.S1, nil); eq(qargs.S2, nil)
ok(qargs.S0 ~= nil and qargs.S0.inline, "plain feature is its own box at tab level")
ok(sg.order < qargs.S0.order, "section ordered by its first feature")
ok(h1.order < h2.order, "registration order inside a section")
local flat = {
    F1 = { key = "F1", title = "Flat", tab = "qol", section = "Box",
        options = function() return {
            a = { type = "toggle", order = 2, name = "A", get = function() end, set = function() end },
            b = { type = "toggle", order = 1, name = "B", get = function() end, set = function() end },
        } end },
    F2 = { key = "F2", title = "Next", tab = "qol", section = "Box", alwaysOn = true,
        options = function() return { c = { type = "execute", order = 1, name = "C", func = function() end } } end },
}
ns.FEATURE_CLIENTS.F1, ns.FEATURE_CLIENTS.F2 = "all", "all"
local tf = ns.BuildOptionsTable(flat, { "F1", "F2" }, { isForever = true, isLoaded = function() return true end })
local box = tf.args.qol.args.section_Box.args
ok(box.F1_header.order < box.F1_enabled.order, "header before the Enable toggle")
ok(box.F1_enabled.order < box.F1_b.order, "Enable toggle before options")
ok(box.F1_b.order < box.F1_a.order, "options keep their order")
ok(box.F1_a.order < box.F2_header.order, "next feature starts after the last option")
ok(box.F2_c ~= nil, "second feature flattened too")
dofile("Libs/LibStub/LibStub.lua")
dofile("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")
dofile("Libs/AceConfig-3.0/AceConfigRegistry-3.0/AceConfigRegistry-3.0.lua")
local reg = _G.LibStub("AceConfigRegistry-3.0")
local vgood, vproblem = pcall(reg.ValidateOptionsTable, reg, ts, "ts")
ok(vgood, tostring(vproblem))
_G.LibStub = nil

local function FakeFrame()
    local f = { hooks = {}, textures = {} }
    f.CreateTexture = function()
        local tex = { shown = true }
        tex.SetColorTexture = function(tx, _, _, _, alpha) tx.alpha = alpha end
        tex.SetPoint = function() end
        tex.Show = function(tx) tx.shown = true end
        tex.Hide = function(tx) tx.shown = false end
        f.textures[#f.textures + 1] = tex
        return tex
    end
    f.HookScript = function(frame, name, hook) frame.hooks[name] = hook end
    return f
end
local pooled = FakeFrame()
local dialog = { OpenFrames = {} }
function dialog:Open(id) self.OpenFrames[id] = { frame = pooled } end
_G.LibStub = function(name) if name == "AceConfigDialog-3.0" then return dialog end end
ns.OpenOptions()
eq(#pooled.textures, 1, "adds one background")
ok(pooled.textures[1].shown and pooled.textures[1].alpha > 0.9, "opaque while open")
pooled.hooks.OnHide(pooled)
eq(pooled.textures[1].shown, false, "hidden when the window closes, for other addons reusing the frame")
ns.OpenOptions()
eq(#pooled.textures, 1, "reopening reuses it"); eq(pooled.textures[1].shown, true)
_G.LibStub = nil
