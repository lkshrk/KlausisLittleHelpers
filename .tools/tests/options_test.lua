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
eq(a.args.enabled.width, "normal", "enable toggle shares a row")
ns.FEATURE_CLIENTS.MinimapButton = "all"
local minimap = ns.BuildOptionsTable({ MinimapButton = { key = "MinimapButton", title = "Minimap", alwaysOn = true } }, { "MinimapButton" }, ctx)
eq(minimap.args.helpers, nil, "minimap launcher has no options page")
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

assert(loadfile("Core/OptionsModel.lua"))("KlausisLittleHelpers", ns)
local function valid(tab, name)
    local entries = ns.OptionsModel.Entries(tab)
    ok(#entries > 0, name .. " has entries")
    for _, entry in ipairs(entries) do
        if not entry.heading then
            local page = ns.OptionsModel.Page(tab, entry.id)
            ok(page ~= nil, name .. ": " .. entry.id .. " renders")
            if name == "modules" and entry.level == 2 then
                ok(#page.controls > 0, entry.id .. " has controls")
            end
        end
    end
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

local SUPPORTED = { group = true, toggle = true, select = true, range = true, execute = true, input = true,
    description = true, header = true }
local everySpec, everyKey = {}, {}
local everyStub = setmetatable({
    RegisterFeature = function(spec) everySpec[spec.key] = spec; everyKey[#everyKey + 1] = spec.key end,
}, { __index = stub })
local toc = assert(io.open("KlausisLittleHelpers.toc", "r"))
for line in toc:lines() do
    local path = line:match("^(Modules\\%S+%.lua)")
    if path then
        local chunk = assert(loadfile((path:gsub("\\", "/"))))
        local loaded, why = pcall(chunk, "KlausisLittleHelpers", everyStub)
        ok(loaded, path .. " loads: " .. tostring(why))
    end
end
toc:close()
local registered = 0
for key in pairs(ns.FEATURE_CLIENTS) do if everySpec[key] then registered = registered + 1 end end
ok(#everyKey >= 8, "every module registers its feature")
eq(#everyKey, registered, "every module feature is listed in FEATURE_CLIENTS")
local function CheckTypes(node, path)
    for k, arg in pairs(node.args or {}) do
        local where = path .. "." .. tostring(k)
        ok(SUPPORTED[arg.type], where .. " has a supported type: " .. tostring(arg.type))
        if arg.type == "group" then CheckTypes(arg, where) end
    end
end
for _, forever in ipairs({ true, false }) do
    CheckTypes(ns.BuildOptionsTable(everySpec, everyKey, { isForever = forever, isLoaded = function() return true end,
        settings = function() return {} end }), forever and "forever" or "retail")
end
local checkSettingsContract
local coverage = {
    -- Related tests are partial; individual setting behavior and profile changes remain unverified unless tested there.
    FarmTracker = { fishIdleMinutes = "farmtracker_test.lua: setter and fishing idle behavior" },
    TurnInRoute = { useHearth = "routewiring_test.lua: route wiring and Shortest Path disabled state", useTeleports = "routewiring_test.lua: route wiring and Shortest Path disabled state", useShortestPath = "routewiring_test.lua: option, profile and planner wiring", waypoints = "routewiring_test.lua: route wiring and Shortest Path disabled state" },
    TustUIXPBar = { showSessionXP = "xpbar_test.lua: display behavior", rateSource = "xpbar_test.lua: rate behavior" },
    SoulstoneReminder = { instances = "soulstonewiring_test.lua: reminder wiring", banner = "soulstonewiring_test.lua: reminder wiring", announce = "soulstonewiring_test.lua: reminder wiring", whisper = "soulstonewiring_test.lua: reminder wiring", sound = "soulstonewiring_test.lua: reminder wiring" },
    WritCratePlanner = {
        countBank = "writdepthwiring_test.lua: bank option wiring", useFavorForReceipts = "candidates_test.lua: planner math",
        liveMinQty = "writdepthwiring_test.lua: depth wiring", priceMethod = "pricecheck_test.lua: price calculation",
        historyDays = "pricecheck_test.lua: price calculation", halfLife = "market_test.lua: weighted market prices",
        minDays = "pricecheck_test.lua: price calculation", cheapBelow = "pricecheck_test.lua: price calculation",
        highAbove = "pricecheck_test.lua: price calculation", dontBuyAbove = "pricecheck_test.lua: price calculation",
        marketShare = "market_test.lua: market calculation",
    },
}
local settingTypes = { toggle = true, range = true, select = true, input = true }
local currentSettings
everyStub.GetSettings = function() return currentSettings end
checkSettingsContract = function(featureSpecs, inventory, report)
for feature in pairs(inventory) do
    report(featureSpecs[feature] ~= nil and type(featureSpecs[feature].options) == "function", feature .. " inventory feature is current")
end
for _, spec in pairs(featureSpecs) do
    if spec.options then
        currentSettings = spec.defaults or {}
        local args = spec.options(currentSettings)
        local seenOptions = {}
        local ok = report
        local function checkOptions(options, prefix, defaults)
            for key, arg in pairs(options) do
                local path = prefix .. key
                if arg.type == "group" then
                    checkOptions(arg.args or {}, path .. ".", type(defaults) == "table" and defaults[key] or nil)
                elseif settingTypes[arg.type] then
                    seenOptions[path] = true
                    local entry = inventory[spec.key] and inventory[spec.key][path]
                    ok(entry ~= nil, spec.key .. "." .. path .. " needs a behavior/profile coverage inventory entry")
                    if entry then
                        local file = entry:match("^([^:]+): .+")
                        local handle = file and io.open(".tools/tests/" .. file, "r")
                        ok(handle ~= nil, spec.key .. "." .. path .. " references an existing test")
                        if handle then handle:close() end
                    end
                    ok(type(arg.get) == "function" and type(arg.set) == "function", spec.key .. "." .. path .. " has callbacks")
                    local default
                    if type(defaults) == "table" then default = defaults[key] end
                    ok(default ~= nil, spec.key .. "." .. path .. " has a default")
                    if arg.type == "toggle" then ok(type(default) == "boolean", spec.key .. "." .. path .. " has a boolean default") end
                    if arg.type == "range" then
                        ok(type(default) == "number" and type(arg.min) == "number" and type(arg.max) == "number" and arg.min <= default and default <= arg.max, spec.key .. "." .. path .. " has a valid range and default")
                        ok(type(arg.step) == "number" and arg.step > 0, spec.key .. "." .. path .. " has a positive step")
                    end
                    if arg.type == "select" and type(arg.values) == "table" then
                        ok(arg.values[default] ~= nil, spec.key .. "." .. path .. " default is a choice")
                    end
                    if type(arg.get) == "function" then ok(arg.get() == default, spec.key .. "." .. path .. " getter reads default") end
                elseif arg.type == "execute" then
                    ok(type(arg.func) == "function", spec.key .. "." .. path .. " has an action")
                end
            end
        end
        checkOptions(args, "", currentSettings)
        for key in pairs(inventory[spec.key] or {}) do ok(seenOptions[key], spec.key .. "." .. key .. " inventory entry is current") end
    end
end

end
checkSettingsContract(everySpec, coverage, ok)
local fixtureErrors = {}
checkSettingsContract({ Nested = { key = "Nested", defaults = { group = { value = true } }, options = function() return { group = { type = "group", args = { value = { type = "toggle", get = function() return true end, set = function() end } } } } end } }, { Nested = { ["group.value"] = "options_test.lua: fixture" }, Gone = { old = "options_test.lua: fixture" } }, function(success, message) if not success then fixtureErrors[#fixtureErrors + 1] = message end end)
ok(#fixtureErrors == 1 and fixtureErrors[1]:find("Gone", 1, true), "nested defaults and stale features are checked")


_G.LibStub = nil

local callbacks, popups, notified = {}, 0, 0
local fakeDB = { char = {}, global = {}, profile = { features = {} }, RegisterCallback = function(_, event, fn) callbacks[event] = fn end }
local libs = {
    ["AceDB-3.0"] = { New = function() return fakeDB end },
    ["AceDBOptions-3.0"] = { GetOptionsTable = function() return {} end },
}
_G.LibStub = function(name) return libs[name] end
_G.StaticPopup_Show = function() popups = popups + 1 end
ns.NotifyOptionsChanged = function() notified = notified + 1 end
ns.FEATURE_CLIENTS.Sw, ns.FEATURE_CLIENTS.On = "all", "all"
ns.RegisterFeature({ key = "Sw", title = "Switchable", enable = function() end })
local redraws = 0
ns.RegisterFeature({ key = "On", title = "Always", alwaysOn = true, enable = function() end, onReset = function() redraws = redraws + 1 end })
local realLoaded = ns.WasEnabledAtLoad
ns.WasEnabledAtLoad = function(key) return key == "On" end
ns.RegisterOptions()
ok(type(ns.OptionsRoot) == "function", "RegisterOptions exposes the options root builder")
ok(ns.OptionsRoot().args.general, "the root is the built options table")
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
valid(ts, "ts")
