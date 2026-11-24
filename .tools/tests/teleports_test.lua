ns.IS_FOREVER = true
addon("Data/Teleports.lua")

local SPELLS = { [3561] = true, [3562] = true, [3565] = true, [3567] = true, [3563] = true, [3566] = true }
local CITY = {
    Stormwind = { side = "A", instance = 0 }, Ironforge = { side = "A", instance = 0 },
    Darnassus = { side = "A", instance = 1 }, Orgrimmar = { side = "H", instance = 1 },
    Undercity = { side = "H", instance = 0 }, ["Thunder Bluff"] = { side = "H", instance = 1 },
}
local BOUND = 20000

eq(#ns.Teleports, 6, "one row per city")
local seenSpell, seenName = {}, {}
for _, row in ipairs(ns.Teleports) do
    local name = tostring(row.name)
    local city = CITY[row.name]
    ok(city ~= nil, name .. " is a known city")
    ok(SPELLS[row.spellID], name .. " has a known teleport spell")
    ok(not seenSpell[row.spellID], name .. " spell is unique")
    ok(not seenName[name], name .. " is unique")
    seenSpell[row.spellID], seenName[name] = true, true
    eq(row.reagent, 17031, name .. " reagent")
    if city then
        eq(row.side, city.side, name .. " side")
        eq(row.instance, city.instance, name .. " continent")
    end
    ok(row.side == "A" or row.side == "H", name .. " side is A or H")
    ok(row.instance == 0 or row.instance == 1, name .. " instance is 0 or 1")
    ok(type(row.wx) == "number" and math.abs(row.wx) <= BOUND, name .. " wx in world bounds")
    ok(type(row.wy) == "number" and math.abs(row.wy) <= BOUND, name .. " wy in world bounds")
end
