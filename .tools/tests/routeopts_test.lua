addon("Data/Teleports.lua"); addon("Modules/TurnInRouteGraph.lua")
local G = ns.RouteGraph
eq(#ns.Teleports, 6)
local hearth = { name = "Inn", wx = 1, wy = 2, instance = 0 }
eq(#G.Shortcuts({ hearth = hearth, knownSpells = {}, reagents = {}, side = "A" }, { hearth = false, teleports = false }), 0)
local s = G.Shortcuts({ hearth = hearth, knownSpells = {}, reagents = {}, side = "A" }, { hearth = true, teleports = false })
eq(#s, 1); eq(s[1].kind, "hearth"); eq(s[1].time, 30)
local sw = find(ns.Teleports, "side", "A")
local facts = { knownSpells = { [sw.spellID] = true }, reagents = { [17031] = 1 }, side = "A" }
eq(#G.Shortcuts(facts, { teleports = true }), 1)
eq(G.Shortcuts(facts, { teleports = true })[1].time, 15)
facts.reagents = {}; eq(#G.Shortcuts(facts, { teleports = true }), 0)
facts.reagents = { [17031] = 1 }; facts.side = "H"; eq(#G.Shortcuts(facts, { teleports = true }), 0)
eq(#G.Shortcuts({ side = "A" }, { teleports = true }), 0)
eq(#G.Shortcuts({}, { hearth = true }), 0)
eq(#G.Shortcuts({}, nil), 0)
