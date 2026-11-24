addon("Core/Core.lua"); addon("Modules/TurnInRouteGraph.lua"); addon("Modules/RouteDraw.lua"); addon("Modules/RouteWaypoints.lua"); addon("Modules/RoutePlanner.lua"); addon("Modules/TurnInRoute.lua")
local T = ns.TurnInRoute
local writs = {
    { writID = 1, itemID = 10, qty = 2, name = "A", npc = "Nia", mapID = 1446, x = 52.3, y = 26.9, questID = 100 },
    { writID = 2, itemID = 20, qty = 1, name = "B", npc = "Bo", questID = 200 },
    { writID = 3, itemID = 30, qty = 1, name = "C", npc = "Cy", mapID = 1446, x = 1, y = 1, questID = 300 },
}
local bags = { [1] = 1, [10] = 2, [2] = 1, [20] = 1, [3] = 1 }
local stops, unknown = T.ReadyWrits(writs, function(id) return bags[id] or 0 end)
eq(#stops, 1); eq(stops[1].questIds[1], 100); ok(math.abs(stops[1].x - 0.523) < 1e-9); eq(unknown, 1)
eq(stops[1].quests[1], "Writ: A"); eq(stops[1].name, "Nia")
bags[10] = 1; eq(#T.ReadyWrits(writs, function(id) return bags[id] or 0 end), 0)
local noWrit = { [10] = 2 }
local ready = T.ReadyWrits(writs, function(id) return noWrit[id] or 0 end, function(id) return id == 100 end)
eq(#ready, 1, "quest in log counts when the writ item is gone"); eq(ready[1].questIds[1], 100)
eq(#T.ReadyWrits(writs, function(id) return noWrit[id] or 0 end, function() return false end), 0)
ok(T.WritQuestIds(writs)[300], "writ quests are skipped by the Quests source")
local items = T.MenuItems({ { key = "quests", title = "Quests", order = 1 }, { key = "writs", title = "Writs", order = 2 } }, false)
eq(items[1].text, "Plan all"); eq(items[2].text, "Quests"); eq(items[3].text, "Writs"); eq(items[4], nil)
eq(T.MenuItems({}, true)[2].text, "Abort route")
