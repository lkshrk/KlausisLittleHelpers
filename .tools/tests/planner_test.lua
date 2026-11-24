ns.RegisterFeature = function() end
addon("Modules/WritCratePlanner.lua")
local P = ns.WritPlanner

eq(P.GainTo({ standingID = 4, current = 1000, max = 3000 }, 5), 2000)
eq(P.GainTo({ standingID = 4, current = 1000, max = 3000 }, 6), 8000)
eq(P.GainTo({ standingID = 5, current = 200, max = 0 }, 8), 5800 + 12000 + 21000)
eq(P.GainTo({ standingID = 6, current = 0 }, 6), 0)
eq(P.GainTo({ standingID = 8, current = 0 }, 6), 0)
eq(P.GainTo({}, 6), nil)

eq(P.ParseAmount("+5,800 rep"), 5800); eq(P.ParseAmount(" 500 "), 500); eq(P.ParseAmount("Honored"), nil)
eq(P.FormatMoney(450300), "45g 03s"); eq(P.FormatMoney(12345678), "1,234g 56s 78c"); eq(P.FormatMoney(305), "3s 05c")
eq(P.FormatMoney(7), "7c"); eq(P.FormatNumber(42000), "42,000"); eq(P.FormatNumber(500), "500")

local writ = { writID = 10, name = "Big Bronze Knife", itemID = 20, item = "Big Bronze Knife", qty = 2 }
local crate = { itemID = 30, name = "Expert Ingots" }
local plan = { lines = {
    { kind = "writ", ref = writ, count = 1 },
    { kind = "crate", ref = crate, count = 2, owned = true },
    { kind = "crate", ref = crate, count = 3, owned = false },
    { kind = "receipt", count = 3, bought = 2, crateRef = { itemID = 31, name = "Apprentice Herbs" } },
} }
local bundleOf = { [crate] = { itemID = 40, name = "Mithril Bar", count = 20 } }
local terms = P.ShoppingTerms(plan, { [20] = 1, [40] = 30, [30] = 2 }, bundleOf)
eq(#terms, 5)
eq(find(terms, "itemID", 10).name, "Craftsman's Writ: Big Bronze Knife"); eq(find(terms, "itemID", 10).count, 1)
eq(find(terms, "itemID", 20).count, 1)
eq(find(terms, "itemID", 30).name, "Waylaid Crate: Expert Ingots"); eq(find(terms, "itemID", 30).count, 3)
eq(find(terms, "itemID", 40).count, 20 * 5 - 30)
eq(find(terms, "itemID", 31).count, 2)
plan.lines[4] = { kind = "receipt", count = 1, bought = 0 }
terms = P.ShoppingTerms(plan, { [10] = 1, [20] = 2, [40] = 100 }, bundleOf)
eq(#terms, 1); eq(terms[1].itemID, 30)


local quested = { lines = { { kind = "writ", ref = { questID = 7, writID = 10, name = "K", itemID = 20, item = "K", qty = 1 }, count = 1 } } }
terms = P.ShoppingTerms(quested, {}, nil, { [7] = true })
eq(#terms, 1); eq(terms[1].itemID, 20, "accepted writ not on the list")
eq(#P.ShoppingTerms(quested, {}, nil, nil), 2)

local crates = { { itemID = 1 }, { itemID = 2 }, { itemID = 3 } }
local ownedEmpty, crateCost, crateRef = P.EmptyCrates({ data = { WaylaidCrates = crates }, owned = { [1] = 2, [3] = 1 },
    prices = { [2] = 50, [3] = 40 } })
eq(ownedEmpty, 3); eq(crateCost, 40); eq(crateRef, crates[3])
ownedEmpty, crateCost, crateRef = P.EmptyCrates({ data = { WaylaidCrates = crates }, owned = {}, prices = {} })
eq(ownedEmpty, 0); eq(crateCost, nil); eq(crateRef, nil)

local st = { mode = "rep" }
eq(P.SwitchMode(st, "rep"), false)
eq(P.SwitchMode(st, "favor"), true); eq(st.mode, "favor")
eq(P.SwitchMode(st, "rep"), true); eq(st.mode, "rep")

eq(P.CleanAmount(" 5 800\n"), "5800", "spaces and new lines stripped")
eq(P.CleanAmount("\t12,345 rep"), "12345", "tabs, commas and words stripped")
eq(P.CleanAmount("abc"), "", "no digits: empty")
eq(P.CleanAmount("12345678901"), "123456789", "at most 9 digits")
eq(P.CleanAmount(nil), "")

local fr = { mode = "rep", target = 500, writsCapped = true, cands = { unpriced = {} },
    plan = { lines = { {} }, cost = 100, gain = 500, short = 0, zones = 1 } }
local text = P.Footer(fr).text
ok(text:find("Writs give no rep past Friendly.", 1, true) and not text:find("receipts cover", 1, true), "no receipts, no receipt promise")
fr.receipts = true
ok(P.Footer(fr).text:find("receipts cover the rest", 1, true), "receipts offered")
eq(P.Summary(fr), nil, "picked plan: cost, gain and zones are on its row, no summary")
ok(not P.Footer(fr).text:find("1s 00c", 1, true), "cost not repeated below the list")
fr.plan.short = 20
local sum = P.Summary(fr).text
ok(sum:find("Reaches +500 of +500 today", 1, true) or sum:find("left for another day", 1, true), "shortfall still warned: " .. sum)
fr.plan.short = 0
fr.progress = { 3, 8 }
sum = P.Summary(fr).text
ok(sum:find("3 of 8 items", 1, true), "progress shown")
ok(sum:find("Adding up AH listings...", 1, true) and not sum:find("1s 00c", 1, true), "loading summary: " .. sum)
ok(not P.Footer(fr).text:find("Adding up", 1, true), "progress not in the footer")
fr.progress = nil

local unlabeled = { itemID = 248549, name = "Waylaid Crate", labeled = false }
ownedEmpty, crateCost, crateRef = P.EmptyCrates({ data = { WaylaidCrates = crates, UnlabeledCrate = unlabeled },
    owned = { [1] = 1, [248549] = 2 }, prices = { [2] = 50, [248549] = 20 } })
eq(ownedEmpty, 3, "unlabeled crates count as empty"); eq(crateCost, 20); eq(crateRef, unlabeled)
terms = P.ShoppingTerms({ lines = { { kind = "receipt", count = 1, bought = 1, crateRef = unlabeled } } }, {}, nil)
eq(terms[1].name, "Waylaid Crate", "unlabeled crate keeps its own name")

local saved = _G.C_Item
_G.C_Item = { GetItemNameByID = function(id) if id == 20 then return "Live Knife" end end }
terms = P.ShoppingTerms({ lines = { { kind = "writ", ref = writ, count = 1 } } }, {}, nil)
eq(find(terms, "itemID", 20).name, "Live Knife", "client item name wins")
eq(find(terms, "itemID", 10).name, "Craftsman's Writ: Big Bronze Knife", "data name when the client has none")
_G.C_Item = saved

eq(P.ResetText(3 * 3600 + 7 * 60 + 59), "Writs reset in 3h 7m")
eq(P.ResetText(59), "Writs reset in 0h 0m"); eq(P.ResetText(86399), "Writs reset in 23h 59m")
eq(P.ResetText(nil), nil); eq(P.ResetText(-1), nil)
fr.reset = "Writs reset in 1h 2m"
ok(P.Footer(fr).text:find("Writs reset in 1h 2m", 1, true), "reset line shown")
fr.reset = nil
ok(not P.Footer(fr).text:find("reset in", 1, true), "reset line omitted without the API")
fr.cands.lowLevel = true
ok(P.Footer(fr).text:find("Writs need level 10.", 1, true), "low level noted")

local savedLabel = rawget(_G, "FACTION_STANDING_LABEL6")
eq(P.StandingName(6), "Honored", "fallback standing name")
_G.FACTION_STANDING_LABEL6 = "Respecte"
eq(P.StandingName(6), "Respecte", "client standing label wins")
ok(P.Summary({ mode = "rep", target = 0, cands = { unpriced = {} } }).text:find("Already reached.", 1, true))
ok(P.Summary({ mode = "rep", cands = { unpriced = {} } }).text:find("Type a target amount, or pick a standing.", 1, true))
_G.FACTION_STANDING_LABEL6 = savedLabel

local savedItem = _G.C_Item
_G.C_Item = { GetItemNameByID = function(id) if id == 1 then return "A" end end, RequestLoadItemDataByID = function() end }
local missing = P.MissingNames({ { itemID = 1 }, { itemID = 2 } })
eq(missing[1], nil); eq(missing[2], true)
_G.C_Item = nil
eq(next(P.MissingNames({ { itemID = 2 } })), nil, "no item API, nothing to wait for")
_G.C_Item = savedItem

do
    local ids = P.NeedIDs({ [3] = 1, [1] = 2, [2] = 1, [4] = 1 }, { [2] = {} }, { [4] = true })
    eq(table.concat(ids, ","), "1,3", "ids already fetched or tried this run are not asked for again")
    eq(#P.NeedIDs({ [5] = 1 }), 1)
    eq(table.concat(P.NeedIDs({ [6] = 1, [7] = 10, [8] = 60 }, nil, nil, 10), ","), "7,8", "only items bought at least the threshold")
end

do
    local w1 = { name = "Writ One", zone = "Ashenvale", qty = 1 }
    local w2 = { name = "Writ Two", zone = "Duskwood", qty = 1 }
    local w3 = { name = "Writ Three", zone = "Ashenvale", qty = 1 }
    local er = { input = { owned = {}, onQuest = {} }, bundleOf = {}, plan = { lines = {
        { kind = "writ", ref = w1, zone = "Ashenvale", cost = 120, gain = 75 },
        { kind = "writ", ref = w2, zone = "Duskwood", cost = 50, gain = 75 },
        { kind = "writ", ref = w3, zone = "Ashenvale", cost = 10, gain = 125 },
        { kind = "receipt", count = 2, cost = 30, gain = 100 },
    } } }
    local e = P.Entries(er)
    local shape = {}
    for _, x in ipairs(e) do shape[#shape + 1] = x.header and ("[" .. x.text .. "]") or x.text end
    eq(table.concat(shape, "|"), "[- Ashenvale (2)]|Writ One|Writ Three|[- Duskwood (1)]|Writ Two|[- Receipts (2)]|2. Use 2 empty crates you have|3. Get 2x Forged Delivery Receipt",
        "rows grouped by zone in plan order, crates and receipts last")
    eq(e[2].indent, true, "rows under a header are indented")
    ok(e[2].right:find("1s 20c", 1, true) and e[2].right:find("+75", 1, true), "cost and rep in the right column: " .. e[2].right)
    local receiptOnly = P.Entries({ input = { owned = {} }, bundleOf = {}, plan = { lines = {
        { kind = "receipt", count = 1, cost = 30, gain = 50 } } } })
    eq(receiptOnly[1].header, true, "receipt-only plan still gets its Receipts steps"); eq(receiptOnly[2].indent, true)
end

do
    local dup = { mode = "rep", target = 500, cands = { unpriced = { "Old Helm", "Odd Bag" } },
        input = { notInScan = { "Old Helm" } }, plan = { lines = { {} }, cost = 100, gain = 500, short = 0, zones = 1 } }
    local foot = P.Footer(dup).text
    ok(foot:find("Not in your last scan\nOld Helm", 1, true), "section header then one name per line: " .. foot)
    ok(foot:find("No price\nOdd Bag", 1, true), foot)
    local _, helms = foot:gsub("Old Helm", "")
    eq(helms, 1, "items not in the scan are not listed twice")
    local info = P.Footer(dup)
    eq(info.lines[1].left, "Planner info", "info popup has a title"); eq(info.lines[1].gold, true)
    dup.age = 0
    eq(P.Footer(dup).lines[1].left, "Prices from today's scan", "title says how fresh the prices are")
    dup.age = 3
    local stale = P.Footer(dup)
    eq(stale.lines[1].left, "Scan is 3 days old: rescan the AH"); eq(stale.lines[1].warn, true); eq(stale.warn, true)
    dup.age = nil
    local header
    for _, l in ipairs(info.lines) do if l.left == "Not in your last scan" then header = l end end
    ok(header and header.header, "section names are headers")
    local many = { mode = "rep", target = 500, cands = { unpriced = {} }, input = { notInScan = {} },
        plan = { lines = { {} }, cost = 100, gain = 500, short = 0, zones = 1 } }
    for i = 1, 12 do many.input.notInScan[i] = "Item " .. i end
    ok(P.Footer(many).text:find("and 4 more", 1, true), "long lists are cut after 8 names")

    local ps = { mode = "rep" }
    eq(P.RestoreState(ps, { mode = "favor", target = "900" }), "900", "saved target text returned")
    eq(ps.mode, "favor")
    ps = { mode = "rep" }
    eq(P.RestoreState(ps, nil), "", "nothing saved: empty target"); eq(ps.mode, "rep")
    eq(P.RestoreState(ps, { mode = "bogus", target = 5 }), "", "bad saved values ignored"); eq(ps.mode, "rep")
end

do
    local function opt(level, cost, zones) return { level = level, plan = { cost = cost, zones = zones, lines = {} } } end
    local front = P.Frontier({ opt(0.2, 140, 4), opt(0, 100, 9), opt(0.05, 104, 6), opt(0.1, 104, 6), opt(0.15, 120, 7) })
    local shape = {}
    for _, o in ipairs(front) do shape[#shape + 1] = o.plan.cost .. "/" .. o.plan.zones .. "@" .. o.level end
    eq(table.concat(shape, " "), "100/9@0 104/6@0.05 140/4@0.2", "cheapest first, then only plans with fewer zones; ties keep the lower level")
    eq(#P.Frontier({ { level = 0, plan = { cost = 5, lines = {} } }, { level = 0.1, plan = { cost = 5, lines = {} } } }), 1,
        "favor plans without zones collapse to one")

    local w = { name = "Writ One", zone = "Ashenvale", qty = 1 }
    local base = { mode = "rep", target = 75, input = { owned = {}, onQuest = {} }, bundleOf = {}, selected = 2, options = {
        { level = 0, plan = { cost = 100, gain = 75, zones = 2, short = 0, lines = { { kind = "writ", ref = w, zone = "Ashenvale", cost = 100, gain = 75 } } } },
        { level = 0.05, plan = { cost = 104, gain = 75, zones = 1, short = 0, lines = { { kind = "writ", ref = w, zone = "Ashenvale", cost = 104, gain = 75 } } } },
    } }
    local rows = P.OptionRows(base)
    eq(#rows, 2); eq(rows[1].text, "Cheapest"); eq(rows[1].data, 1); eq(rows[2].data, 2)
    eq(rows[2].text, "-1 zone, +4c", "trade-off named by what it saves and costs")
    ok(rows[1].right:find("1s 00c", 1, true) and rows[1].right:find("2 zones", 1, true), "cost and zones: " .. rows[1].right)
    eq(rows[2].selected, true); eq(rows[1].selected, nil)
    local lines = rows[1].tooltipLines
    ok(type(lines) == "table" and #lines >= 3, "hover popup lines")
    eq(lines[1].left, "Cheapest", "popup titled with the option"); eq(lines[1].gold, true)
    local stats = {}
    for _, l in ipairs(lines) do if l.right and l.label then stats[l.left] = l.right end end
    ok(stats.Cost and stats.Cost:find("1s 00c", 1, true), "cost row")
    eq(stats.Gain, "+75 rep"); eq(stats.Zones, "2")
    local flat = {}
    for _, l in ipairs(lines) do flat[#flat + 1] = (l.left or "") .. "=" .. (l.right or "") end
    flat = table.concat(flat, ";")
    ok(flat:find("Ashenvale (1)=1s 00c", 1, true) and flat:find("+75", 1, true), "popup has one line per zone: " .. flat)
    ok(not flat:find("Writ One", 1, true), "popup lists no single writs: " .. flat)

    base.progress = { 1, 4 }
    rows = P.OptionRows(base)
    eq(rows[1].tooltipLines, nil, "no popup while the search runs"); eq(rows[1].data, nil, "no picking while the search runs")
    base.progress, base.selected, base.plan = nil, nil, base.options[1].plan
    rows = P.OptionRows(base)
    eq(rows[1].selected, nil); eq(rows[2].selected, nil)
    eq(P.Summary(base), nil, "no summary until an option is picked")
    local idle = P.Summary({ idle = true, mode = "rep", target = 5800 }).text
    ok(idle:find("Press Search to plan +5,800 rep.", 1, true), idle)

    eq(P.ShortMoney(1234567), "123g 45s"); eq(P.ShortMoney(4567), "45s 67c"); eq(P.ShortMoney(45), "45c")
    local three = { mode = "rep", options = {
        { plan = { cost = 5000000, zones = 18 } }, { plan = { cost = 5019446, zones = 13 } }, { plan = { cost = 5602100, zones = 9 } } } }
    eq(P.OptionLabel(three, 1), "Cheapest"); eq(P.OptionLabel(three, 2), "-5 zones, +1g 94s"); eq(P.OptionLabel(three, 3), "-9 zones, +60g 21s")
end

do
    ok(type(P.FewestBuys) == "function", "fewest-buys planner")
    local writs = {
        { ref = { name = "Cheap A" }, cost = 100, rep = 75, zone = "Z1" },
        { ref = { name = "Cheap B" }, cost = 100, rep = 75, zone = "Z1" },
        { ref = { name = "Big C" }, cost = 500, rep = 150, zone = "Z2" },
    }
    local fake = { RepPlan = function(ws, target)
        table.sort(ws, function(x, y) return x.cost / x.rep < y.cost / y.rep end)
        local fp = { lines = {}, cost = 0, gain = 0, zones = 0, short = 0, target = target }
        for _, w in ipairs(ws) do
            if fp.gain >= target then break end
            fp.lines[#fp.lines + 1] = { kind = "writ", ref = w.ref, count = 1, cost = w.cost, gain = w.rep, zone = w.zone }
            fp.cost, fp.gain = fp.cost + w.cost, fp.gain + w.rep
        end
        return fp
    end }
    local fb = P.FewestBuys(fake, writs, 150)
    eq(#fb.lines, 1, "one big writ instead of two cheap ones"); eq(fb.lines[1].ref.name, "Big C")
    eq(fb.cost, 500, "real cost, not the penalty"); eq(fb.lines[1].cost, 500)
    eq(writs[1].cost, 100, "input writs untouched")
end

do
    local withFavor = { lines = { { kind = "receipt", count = 62, cost = 1812, gain = 3100 } }, cost = 1812, gain = 5800, short = 0, zones = 0,
        favor = { need = 930, fromBalance = 160, fromCrates = 770 } }
    local fr2 = { mode = "rep", target = 5800, plan = withFavor, options = { { level = 0, plan = withFavor } }, selected = 1,
        input = { owned = {}, onQuest = {} }, bundleOf = {}, cands = { unpriced = {} } }
    local sum2 = P.Summary(fr2).text
    ok(sum2:find("Uses 930 Favor: 160 you have, 770 from crates", 1, true), sum2)
    withFavor.favor.fromBalance = 0
    ok(P.Summary(fr2).text:find("Uses 930 Favor, all from crates", 1, true), "own Favor kept: " .. P.Summary(fr2).text)
    withFavor.favor.fromBalance = 160
    local lines = P.PlanLines(fr2, fr2.options[1], "Cheapest")
    local stats = {}
    for _, l in ipairs(lines) do if l.label then stats[l.left] = l.right end end
    eq(stats["Favor for receipts"], "930"); eq(stats["Paid with your Favor"], "160"); eq(stats["From crates"], "770")
    withFavor.favor.fromBalance = 0
    stats = {}
    for _, l in ipairs(P.PlanLines(fr2, fr2.options[1], "Cheapest")) do if l.label then stats[l.left] = l.right end end
    eq(stats["Paid with your Favor"], nil, "no own-Favor row when it is not spent"); eq(stats["From crates"], "930")
    withFavor.favor.fromBalance = 160

    ok(P.Footer({ mode = "rep", idle = true, cands = { unpriced = {} }, input = {}, reset = "Writs reset in 1h 2m" }) ~= nil,
        "notes exist before a search")
end

do
    local w1 = { name = "Writ One", zone = "Ashenvale", qty = 1 }
    local w2 = { name = "Writ Two", zone = "Duskwood", qty = 1 }
    local lines = {
        { kind = "writ", ref = w1, zone = "Ashenvale", cost = 120, gain = 75 },
        { kind = "writ", ref = w2, zone = "Duskwood", cost = 50, gain = 75 },
        { kind = "receipt", count = 2, cost = 30, gain = 100 },
    }
    local fplan = { lines = lines, cost = 200, gain = 250, zones = 2, short = 0 }
    local r = { mode = "rep", target = 250, input = { owned = {}, onQuest = {} }, bundleOf = {}, cands = { unpriced = {} },
        plan = fplan, options = { { level = 0, plan = fplan }, { level = 0.05, plan = fplan } } }
    local function shape(entries)
        local out = {}
        for _, e in ipairs(entries) do
            out[#out + 1] = e.header and ("[" .. e.text .. "]") or e.text
        end
        return table.concat(out, "|")
    end
    local folded = P.Entries(r, { open = { Duskwood = true } })
    ok(shape(folded):find("Ashenvale %(1%)%]|%[") ~= nil, "zones not opened stay folded: " .. shape(folded))
    ok(shape(folded):find("Duskwood (1)]|Writ Two", 1, true) ~= nil, "opened zone shows its writs: " .. shape(folded))
    ok(folded[1].text:find("Ashenvale (1)", 1, true) and folded[1].data and folded[1].data.group == "Ashenvale", "zone header: name (count): " .. folded[1].text)
    ok(folded[1].right:find("1s 20c", 1, true) and folded[1].right:find("+75", 1, true), "header: cost then rep like its rows: " .. tostring(folded[1].right))
    local other = folded[#folded]
    ok(other.text:find("Receipts (2)", 1, true) and other.right:find("+100", 1, true), "receipts group counts items and rep: " .. other.text .. " " .. other.right)
    eq(#P.Entries(r, { open = {} }), 3, "all zones folded by default")

    local rows, pinned = P.WindowRows(r, { open = {} })
    eq(#rows, 2, "nothing picked: only the options"); eq(pinned, nil, "nothing pinned")
    r.selected = 2
    rows, pinned = P.WindowRows(r, { open = {} })
    eq(#pinned, 2, "picked: two pinned rows")
    eq(pinned[1].data, "options", "Show other options first"); eq(pinned[1].button, true, "drawn as a button")
    eq(pinned[2].data, 2, "then the picked option"); eq(pinned[2].selected, nil, "pinned without the selection highlight")
    eq(r.selected, 2, "but still picked")
    eq(rows[1].header, true, "the scroll list holds the writ list")
    eq(#rows, 3, "zones folded")
end

do
    local rw = { writID = 1, itemID = 2, qty = 2, questID = 9 }
    local rc = { itemID = 10 }
    local rb = { [rc] = { itemID = 11, count = 20 } }
    local rp = { cost = 999, lines = {
        { kind = "writ", ref = rw, count = 1, cost = 1 },
        { kind = "crate", ref = rc, count = 3, owned = false, cost = 1 },
        { kind = "crate", ref = rc, count = 1, owned = true, cost = 1 },
        { kind = "receipt", count = 4, bought = 2, crateRef = rc, cost = 1 },
    } }
    local shared = rp.lines[4]
    local prices = { [1] = 100, [2] = 30, [10] = 7, [11] = 2 }
    local out = P.RepriceLines(rp, prices, { owned = { [2] = 1 }, onQuest = {} }, rb)
    eq(out.lines[1].cost, 100 + 30, "writ: writ plus the one missing item")
    eq(out.lines[2].cost, 3 * (20 * 2 + 7), "bought crates: fill plus crate")
    eq(out.lines[3].cost, 20 * 2, "owned crate: fill only")
    eq(out.lines[4].cost, 2 * 7, "receipts: the empty crates bought")
    eq(out.cost, 130 + 141 + 40 + 14, "total is the sum of its lines")
    eq(shared.cost, 1, "lines are copied, shared lines untouched")

    local fav = { mode = "favor", target = 200, input = { owned = {}, onQuest = {} }, rb = {}, cands = { unpriced = {} } }
    local fplan2 = { lines = {}, cost = 5, gain = 200, zones = 0, short = 0 }
    local zl = P.PlanLines(fav, { plan = fplan2 }, "Cheapest")
    for _, l in ipairs(zl) do ok(l.left ~= "Zones", "no Zones row in Favor mode") end
    fav.options, fav.plan = { { level = 0, plan = fplan2 } }, fplan2
    ok(not P.OptionRows(fav)[1].right:find("zone", 1, true), "favor option row shows Favor, not zones")
end

do
    local textiles = { itemID = 248688, name = "Journeyman Textiles" }
    local empty = { itemID = 248549, name = "Waylaid Crate" }
    local rplan = { cost = 0, gain = 3100, zones = 0, short = 0, favor = { need = 930, fromBalance = 160, fromCrates = 770 }, lines = {
        { kind = "receipt", count = 62, bought = 62, crateRef = empty, cost = 1812, gain = 3100 },
        { kind = "crate", ref = textiles, count = 77, owned = false, cost = 274257, gain = 770 },
    } }
    local rr = { mode = "rep", target = 3100, plan = rplan, input = { owned = {}, onQuest = {} },
        bundleOf = { [textiles] = { name = "Wool Cloth", count = 20 } }, cands = { unpriced = {} } }
    local e = P.Entries(rr)
    local texts = {}
    for _, x in ipairs(e) do texts[#texts + 1] = x.text end
    local joined = table.concat(texts, "|")
    ok(e[1].header and e[1].text:find("Receipts (62)", 1, true), "receipts group titled with the receipt count: " .. e[1].text)
    ok(e[1].right:find("+3,100", 1, true), "group rep is the receipts' rep")
    ok(joined:find("1. Use 160 Favor you have|1. Fill 77x Journeyman Textiles|2. Buy 62x Waylaid Crate|3. Get 62x Forged Delivery Receipt", 1, true),
        "steps in order: " .. joined)
    local fill, trade
    for _, x in ipairs(e) do
        if x.text:find("Fill", 1, true) then fill = x end
        if x.text:find("3. Get", 1, true) then trade = x end
    end
    ok(fill.tooltip:find("20 Wool Cloth", 1, true), "fill step names the bundle: " .. fill.tooltip)
    ok(fill.right:find("+770 Favor", 1, true), fill.right)
    ok(trade.right:find("+3,100", 1, true) and not trade.right:find("%dc"), "trade step: rep, no cost: " .. trade.right)
    ok(trade.tooltip:find("930 Favor", 1, true) and trade.tooltip:find("Uncertified Scribe", 1, true), trade.tooltip)
end

do
    local rc = { itemID = 10 }
    local rb = { [rc] = { itemID = 11, count = 20 } }
    local rw1 = { writID = 1, itemID = 2, qty = 1, questID = 8 }
    local rw2 = { writID = 3, itemID = 2, qty = 1, questID = 9 }
    local rp = { cost = 0, lines = {
        { kind = "writ", ref = rw1, count = 1, cost = 0 },
        { kind = "writ", ref = rw2, count = 1, cost = 0 },
        { kind = "crate", ref = rc, count = 3, owned = false, cost = 0 },
    } }
    local prices = { [1] = 100, [2] = 30, [3] = 100, [10] = 7, [11] = 2 }
    local out = P.RepriceLines(rp, prices, { owned = { [2] = 1, [11] = 25 }, onQuest = {} }, rb)
    eq(out.lines[1].cost, 100, "first writ uses the owned item")
    eq(out.lines[2].cost, 130, "the owned item is not counted twice")
    eq(out.lines[3].cost, 3 * 7 + (60 - 25) * 2, "owned bundle items cut the fill cost")

    local function reason(fields)
        local r = { mode = "rep", target = 500, cands = { unpriced = {} }, input = {},
            plan = { lines = {}, cost = 0, gain = 0, short = 500 }, options = { { level = 0, plan = { lines = {} } } } }
        for k, v in pairs(fields) do
            if k == "cands" then for ck, cv in pairs(v) do r.cands[ck] = cv end else r[k] = v end
        end
        return P.Summary(r).text
    end
    ok(reason({ cands = { lowLevel = true } }):find("level 10", 1, true), "empty plan: level reason")
    ok(reason({ allDone = true }):find("done today", 1, true), "empty plan: all writs done today")
    ok(reason({ cands = { unpriced = { "A" } } }):find("Scan the AH", 1, true), "empty plan: missing prices")
    ok(reason({}):find("Nothing to plan", 1, true), "empty plan: generic")
end

do
    local w = { name = "W", zone = "Z", writID = 1, itemID = 2, qty = 1 }
    local line = { kind = "writ", ref = w, zone = "Z", cost = 10, gain = 75 }
    local p1 = { cost = 10, gain = 75, zones = 1, short = 0, lines = { line } }
    local p2 = { cost = 12, gain = 75, zones = 1, short = 0, lines = { line } }
    local r = { mode = "rep", target = 75, input = { owned = {}, onQuest = {} }, bundleOf = {}, cands = { unpriced = {} },
        plan = p1, options = { { level = 0, plan = p1, marks = { [2] = { live = true, short = 0 } } }, { level = 0.05, plan = p2 } } }
    local rows = P.OptionRows(r)
    local function popupText(i)
        local out = {}
        for _, l in ipairs(rows[i].tooltipLines) do out[#out + 1] = l.left end
        return table.concat(out, "|")
    end
    ok(not popupText(2):find("none listed", 1, true), "an option without marks does not borrow another option's notes")
    r.selected = 1
    local e = P.Entries(setmetatable({ plan = p1, option = r.options[1] }, { __index = r }))
    local texts = {}
    for _, x in ipairs(e) do texts[#texts + 1] = x.text end
    ok(table.concat(texts, "|"):find("(none listed)", 1, true), "an option view shows its own notes")
    r.options[2].marks = { [2] = { short = 3, atScan = true } }
    e = P.Entries(setmetatable({ plan = p2, option = r.options[2] }, { __index = r }))
    texts = {}
    for _, x in ipairs(e) do texts[#texts + 1] = x.text end
    ok(table.concat(texts, "|"):find("(only 3 listed at last scan)", 1, true), "marks added later are read live")
end
