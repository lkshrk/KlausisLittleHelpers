local names = { "LibStub", "GetLocale", "UnitClass", "NORMAL_FONT_COLOR_CODE", "FONT_COLOR_CODE_CLOSE" }
local saved = {}
for _, k in ipairs(names) do saved[k] = rawget(_G, k) end

local function Labels(controls)
    local out = {}
    for i, c in ipairs(controls) do out[i] = c.label end
    return table.concat(out, ",")
end

local function ByKey(page, key)
    for _, c in ipairs(page.controls) do
        if c.key == key then return c end
    end
end

local good, problem = pcall(function()
    addon("Core/Core.lua"); addon("Core/Options.lua"); addon("Core/OptionsModel.lua")
    local M = ns.OptionsModel
    ok(M ~= nil, "model loaded")

    for _, k in ipairs({ "A", "B", "C", "D", "E" }) do ns.FEATURE_CLIENTS[k] = "all" end
    local features = {
        A = { key = "A", title = "Quest Sync", tab = "qol", alwaysOn = true,
              options = function() return { x = { type = "toggle", order = 1, name = "X" } } end },
        B = { key = "B", title = "Bee", tab = "helpers", section = "Dungeons & Raids", alwaysOn = true,
              options = function() return { b1 = { type = "toggle", order = 1, name = "B1" } } end },
        C = { key = "C", title = "Cee", tab = "helpers", section = "Dungeons & Raids", alwaysOn = true,
              options = function() return { c1 = { type = "range", order = 1, name = "C1" } } end },
        D = { key = "D", title = "Dee", tab = "helpers", alwaysOn = true },
        E = { key = "E", title = "Eee", tab = "thirdparty", alwaysOn = true, requires = { "Nope" }, help = "Helps.",
              options = function()
                  return { more = { type = "group", inline = true, order = 1, name = "More",
                                    args = { q = { type = "toggle", order = 1, name = "Q" } } } }
              end },
    }
    local ctx = { isForever = true, isLoaded = function(n) return n ~= "Nope" end,
                  profiles = { type = "group", name = "Profiles", args = { p = { type = "description", name = "P" } } } }
    local root = ns.BuildOptionsTable(features, { "A", "B", "C", "D", "E" }, ctx)

    local entries = M.Entries(root)
    local ids, levels, heads = {}, {}, {}
    for i, e in ipairs(entries) do
        ids[i], levels[i], heads[i] = e.id, tostring(e.level), e.heading and "h" or "-"
    end
    eq(table.concat(ids, ","),
        "general,qol,qol.A,helpers,helpers.section_DungeonsRaids,helpers.D,thirdparty,thirdparty.E,profiles", "sidebar entries")
    eq(table.concat(levels), "112122121", "sidebar levels")
    eq(table.concat(heads), "-h-h--h--", "tabs are headings")
    eq(entries[5].label, "Dungeons & Raids", "section entry named by its section")
    eq(entries[4].label, "Helpers")

    local general = M.Page(root, "general")
    eq(general.title, "General")
    eq(general.controls[1].kind, "header"); eq(general.controls[1].label, "About", "inline group becomes a header")
    eq(general.controls[2].kind, "description")
    eq(general.controls[2].fontSize, "medium")
    eq(general.controls[1].span, 3); eq(general.controls[2].span, 3)
    ok(general.controls[3].label:find("Eee: Requires", 1, true), "General lists the gated feature")

    local section = M.Page(root, "helpers.section_DungeonsRaids")
    eq(section.title, "Dungeons & Raids")
    eq(Labels(section.controls), "Bee,B1,Cee,C1", "section: a header per feature, then its controls")
    eq(section.controls[1].kind, "header"); eq(section.controls[4].kind, "range")

    local e = M.Page(root, "thirdparty.E")
    eq(e.controls[1].kind, "description"); ok(e.controls[1].label:find("Requires", 1, true), "requires line first")
    eq(e.controls[2].label, "Helps.", "help line next")
    eq(e.controls[3].kind, "header"); eq(e.controls[3].label, "More")
    eq(e.controls[4].label, "Q")
    eq(e.controls[4].disabled(), true, "gated group's disabled inherited by its controls")
    eq(M.Page(root, "nope"), nil, "unknown page")
    eq(M.Page(root, "general.about.text"), nil, "a control is no page")

    local hiddenFlag = false
    local log = {}
    local h1 = { val = 5, tag = "one" }
    function h1:Get(info) log[#log + 1] = "get:" .. info[1] .. "/" .. info[#info]; return self.val end
    function h1:Set(_, v) self.val = v end
    function h1:Run(info) log[#log + 1] = "run:" .. info[#info] end
    function h1:List() return { a = "A", b = "B" } end
    function h1:Ask() return "Sure?" end
    local h2 = { tag = "two" }
    local ran
    local semantic = { type = "group", name = "Root", handler = h1, args = {
        page = { type = "group", name = "Page", order = 1, get = "Get", set = "Set", args = {
            t = { type = "toggle", name = "T", arg = "tee" },
            a = { type = "toggle", name = "b-second", order = 5 },
            b = { type = "toggle", name = "A-first", order = 5 },
            neg = { type = "toggle", name = "Neg", order = -1 },
            s = { type = "select", name = "S", values = "List", width = "double", sorting = { "b", "a" }, style = "radio" },
            f = { type = "select", name = "F", width = "full",
                  values = function() return { [2] = "two", [10] = "ten", [1] = "one" } end },
            r = { type = "range", name = "R", min = 0, max = 50, softMax = 20, step = 5, bigStep = 10, isPercent = true },
            x = { type = "execute", name = "X", desc = "does x", func = "Run", confirm = true },
            y = { type = "execute", name = "Y", func = function() ran = true end, confirm = "Ask" },
            z = { type = "input", name = "Z", confirm = function(_, v) return v == "bad" end },
            d = { type = "description", name = function(info) return "dyn " .. info.handler.val end, fontSize = "large" },
            hd = { type = "header", name = "H" },
            hide = { type = "toggle", name = "Hidden", hidden = function() return hiddenFlag end },
            color = { type = "color", name = "Color" },
            sub = { type = "group", inline = true, name = "Sub", order = 50, disabled = true, handler = h2, args = {
                c = { type = "toggle", name = "C", get = function(info) return info.handler.tag end },
                e = { type = "toggle", name = "E", disabled = false },
            } },
        } },
        gone = { type = "group", name = "Gone", hidden = true, args = {} },
        later = { type = "group", name = "Later", order = 2, args = {} },
    } }

    local se = M.Entries(semantic)
    eq(#se, 2, "hidden group left out"); eq(se[1].id, "page"); eq(se[2].id, "later")
    eq(se[1].level, 1); eq(se[1].heading, false)

    local page = M.Page(semantic, "page")
    eq(Labels(page.controls), "A-first,b-second,Sub,C,E,dyn 5,F,H,Hidden,R,S,T,X,Y,Z,Neg",
        "order default 100, ties by name, negative last, unknown types skipped")
    local spans = {}
    for i, c in ipairs(page.controls) do spans[i] = c.span end
    eq(table.concat(spans), "1131133311211111", "spans")
    eq(ByKey(page, "d").fontSize, "large")
    eq(ByKey(page, "s").style, "radio")

    local t = ByKey(page, "t")
    eq(t.get(), 5, "inherited method-name get"); eq(log[#log], "get:page/t", "info carries the path")
    t.set(true); eq(h1.val, true, "inherited method-name set")
    eq(t.disabled(), false); eq(t.hidden(), false)
    eq(t.confirmText(), nil, "no confirm")
    eq(t.run, nil); eq(t.values, nil)

    local c, e2 = ByKey(page, "c"), ByKey(page, "e")
    eq(c.get(), "two", "nearest handler inherited")
    eq(c.disabled(), true, "disabled inherited from the group"); eq(e2.disabled(), true, "a disabled group disables its controls even when they say otherwise")
    eq(page.controls[3].kind, "header"); eq(page.controls[3].disabled(), true)
    local fine, err = pcall(e2.get)
    ok(not fine and tostring(err):find("Method Get doesn't exist", 1, true), "method missing on the nearest handler errors")

    local hide = ByKey(page, "hide")
    eq(hide.hidden(), false); hiddenFlag = true; eq(hide.hidden(), true, "hidden function re-evaluated")

    local s, f = ByKey(page, "s"), ByKey(page, "f")
    eq(s.values().a, "A", "method-name values")
    eq(table.concat(s.sorting(), ","), "b,a", "explicit sorting")
    eq(f.values()[10], "ten", "function values")
    eq(table.concat(f.sorting(), ","), "1,2,10", "keys sorted numerically without sorting")

    local r = ByKey(page, "r")
    eq(r.range.min, 0); eq(r.range.max, 20, "softMax"); eq(r.range.step, 5, "drag step"); eq(r.range.bigStep, 10, "bigStep"); eq(r.range.isPercent, true)
    r.set(57); eq(h1.val, 50, "clamped to max")
    r.set(-3); eq(h1.val, 0, "clamped to min")
    r.set(23); eq(h1.val, 25, "snapped to step")
    eq(r.get(), 25)

    local x, y, z = ByKey(page, "x"), ByKey(page, "y"), ByKey(page, "z")
    eq(x.confirmText(), "X - does x", "confirm true falls back to name - desc")
    x.run(); eq(log[#log], "run:x", "method-name func")
    eq(y.confirmText(), "Sure?", "method-name confirm returning text")
    y.run(); eq(ran, true, "function func")
    eq(z.confirmText("bad"), "Z", "confirm function sees the value")
    eq(z.confirmText("fine"), nil)
    eq(z.kind, "input")
    eq(x.get, nil)

    local subHidden, outerOff, disabledInfo = true, false, nil
    local nested = { type = "group", name = "R", args = { pg = { type = "group", name = "P",
        disabled = function(i) disabledInfo = i; return outerOff end, args = {
            own = { type = "toggle", name = "Own", disabled = false },
            box = { type = "group", inline = true, name = "Box", hidden = function() return subHidden end, args = {
                inner = { type = "toggle", name = "Inner", hidden = false },
            } },
        } } } }
    eq(Labels(M.Page(nested, "pg").controls), "Own", "a hidden group skips its whole subtree")
    subHidden = false
    eq(Labels(M.Page(nested, "pg").controls), "Box,Inner,Own", "shown again once the group is visible")
    local own = ByKey(M.Page(nested, "pg"), "own")
    eq(own.disabled(), false)
    outerOff = true
    eq(own.disabled(), true, "an ancestor's disabled function disables the control")
    eq(disabledInfo[#disabledInfo], "own", "an ancestor's disabled gets the control's info")
    eq(#disabledInfo, 2); eq(disabledInfo.option, nested.args.pg.args.own)

    local opt = { type = "toggle", arg = "A1" }
    local info = M.Info({ "p", "q" }, opt, semantic, h2)
    eq(info[1], "p"); eq(info[2], "q"); eq(#info, 2)
    eq(info.option, opt); eq(info.options, semantic); eq(info.handler, h2)
    eq(info.arg, "A1"); eq(info.type, "toggle")

    local seen
    local argRoot = { type = "group", name = "R", args = { g = { type = "group", name = "G", args = {
        k = { type = "toggle", name = "K", arg = "tee", get = function(i) seen = i; return false end } } } } }
    eq(ByKey(M.Page(argRoot, "g"), "k").get(), false, "get = false style literal")
    eq(seen.arg, "tee"); eq(seen.options, argRoot); eq(seen.handler, nil)

    _G.LibStub = nil
    dofile("Libs/LibStub/LibStub.lua")
    _G.GetLocale = function() return "enUS" end
    _G.UnitClass = function() return "Mage" end
    _G.NORMAL_FONT_COLOR_CODE, _G.FONT_COLOR_CODE_CLOSE = "", ""
    dofile("Libs/AceDBOptions-3.0/AceDBOptions-3.0.lua")
    local db = { keys = { char = "Klausi - Realm", realm = "Realm", class = "MAGE" },
                 current = "Default", profiles = { Default = true, Alt = true }, resets = 0 }
    function db:GetCurrentProfile() return self.current end
    function db:GetProfiles(list)
        list = list or {}
        for k in pairs(list) do list[k] = nil end
        for name in pairs(self.profiles) do list[#list + 1] = name end
        return list, #list
    end
    function db:SetProfile(name) self.profiles[name] = true; self.current = name end
    function db:ResetProfile() self.resets = self.resets + 1 end
    function db:CopyProfile(name) self.copied = name end
    function db:DeleteProfile(name) self.profiles[name] = nil end

    ctx.profiles = _G.LibStub("AceDBOptions-3.0"):GetOptionsTable(db)
    local real = ns.BuildOptionsTable(features, { "A", "B", "C", "D", "E" }, ctx)
    local last = M.Entries(real)
    eq(last[#last].id, "profiles"); eq(last[#last].label, "Profiles")
    local profiles = M.Page(real, "profiles")
    local choose, new, reset = ByKey(profiles, "choose"), ByKey(profiles, "new"), ByKey(profiles, "reset")
    local copy, delete, current = ByKey(profiles, "copyfrom"), ByKey(profiles, "delete"), ByKey(profiles, "current")
    eq(choose.kind, "select"); eq(new.kind, "input"); eq(reset.kind, "execute"); eq(delete.kind, "select")
    eq(current.span, 3, "description stays full width"); eq(delete.span, 1)
    ok(current.label:find("Default", 1, true), "current profile line via info.handler")
    eq(choose.get(), "Default", "method-name get on the inherited handler")
    local list = choose.values()
    ok(list.Default and list.Alt and list["Klausi - Realm"] and list.Realm, "common profiles listed via info.arg")
    eq(list.MAGE, "Mage")
    eq(delete.values().Default, nil, "nocurrent leaves out the current profile")
    eq(delete.values().Alt, "Alt")
    eq(new.get(), false, "get = false")
    choose.set("Alt"); eq(db.current, "Alt", "select set switches profile")
    ok(ByKey(M.Page(real, "profiles"), "current").label:find("Alt", 1, true), "re-paged label follows")
    new.set("Fresh"); eq(db.current, "Fresh", "input set creates the profile")
    eq(reset.confirmText(), nil); reset.run(); eq(db.resets, 1, "Reset runs through the model")
    copy.set("Alt"); eq(db.copied, "Alt")
    eq(delete.confirmText("Alt"), "Are you sure you want to delete the selected profile?", "confirmText literal")
    eq(copy.disabled(), false)
    delete.set("Alt"); delete.set("Default")
    eq(db.profiles.Alt, nil)
    eq(copy.disabled(), true, "method-name disabled with info.arg")
end)

for _, k in ipairs(names) do _G[k] = saved[k] end
if not good then error(problem, 0) end
