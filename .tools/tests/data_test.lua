addon("Data/Writs.lua"); addon("Data/WaylaidCrates.lua")
eq(#ns.Data.Writs, 150, "writ count")
eq(#ns.Data.WaylaidCrates, 30, "crate count")
local w = find(ns.Data.Writs, "questID", 94289)
eq(w.name, "Gyromatic Micro-Adjuster"); eq(w.itemID, 10498); eq(w.rep, 125); eq(w.mapID, 1446)
eq(w.npcID, 14743); eq(w.npc, "Jhordy Lapforge"); eq(w.friendly, "AH")
local known = 0; for _, row in ipairs(ns.Data.Writs) do if row.npcID then known = known + 1 end end
ok(known >= 131, "QuestieDB turn-ins baked in")
ok(ns.Data.CampFaction.Alliance and ns.Data.CampFaction.Horde, "camp factions")
local r = find(ns.Data.Writs, "zone", "Riverglades"); eq(r.mapID, 2548)
local c = find(ns.Data.WaylaidCrates, "itemID", 248709)
eq(c.name, "Expert Ingots"); eq(c.kind, "crafted"); eq(c.favor, 30); eq(c.confirmed, true)
eq(c.bundles[1].itemID, 3860); eq(c.bundles[1].count, 20)
local a = find(ns.Data.WaylaidCrates, "itemID", 248699)
eq(a.favor, 20); eq(a.confirmed, true)
eq(find(ns.Data.Writs, "itemID", 10592).item, "Catseye Draught", "Forever item name")
eq(find(ns.Data.Writs, "itemID", 18645).item, "Gnomish Alarm-O-Bot")
for _, row in ipairs(ns.Data.WaylaidCrates) do
    if row.tier == "artisan" then
        eq(row.favor, row.itemID == 248698 and 5 or row.kind == "crafted" and 40 or 20, "artisan favor: " .. row.name)
        eq(row.confirmed, true, "artisan confirmation: " .. row.name)
    end
end
eq(find(ns.Data.WaylaidCrates, "itemID", 248711).confirmed, true)
local S = ns.Data.SealedCrates
eq(S[248765].tier, "apprentice"); eq(S[248765].kind, "gathered"); eq(S[248769].tier, "elite")
eq(S[248772].tier, "expert"); eq(S[248772].kind, "crafted"); eq(S[248779].tier, "elite"); eq(S[248775].kind, nil)
local n = 0; for _ in pairs(S) do n = n + 1 end; eq(n, 15, "sealed crate count")
eq(ns.Data.UnlabeledCrate.itemID, 248549); eq(ns.Data.UnlabeledCrate.labeled, false); eq(ns.Data.DeliveryReceipt, 262902)
