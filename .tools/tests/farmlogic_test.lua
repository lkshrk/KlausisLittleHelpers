addon("Modules/FarmTrackerLogic.lua")
local L = ns.FarmLogic
local fish = L.NewSession("fish", "fish:zone:bay", 100)
local area = {}
L.Record(fish, area, { sources = 5, slots = {
    { itemID = 1, name = "Fish", quality = 1, quantity = 3, sources = 3 },
    { itemID = 2, name = "Other", quality = 1, quantity = 2, sources = 2 },
} })
local rows = L.Rows(fish, area)
eq(rows[1].sPct, 60); eq(rows[1].aPct, 60); eq(area.items[1].count, 3)
eq(L.FishingEnds(fish, 699, "fish:zone:bay", 10), false)
eq(L.FishingEnds(fish, 700, "fish:zone:bay", 10), true)
eq(L.FishingEnds(fish, 101, "fish:zone:other", 10), true)
eq(L.Clock(3725), "01:02:05")
local farm = L.NewSession("farm", "farm:zone", 0)
local farmArea = { items = { [3] = { name = "Old", quality = 4, count = 1, drops = 1 } } }
L.Record(farm, farmArea, { sources = 10, slots = {
    { itemID = 4, name = "Linen", quality = 1, quantity = 4, sources = 3 },
} })
L.AddGold(farm, farmArea, 123)
rows = L.Rows(farm, farmArea)
eq(rows[1].name, "Old"); eq(rows[1].sCount, 0); eq(rows[1].sPct, 0)
eq(rows[2].sCount, 4); eq(rows[2].sPct, 30); eq(farmArea.attempts, 10)
eq(farm.gold, 123); eq(farmArea.gold, 123)
local sortedArea = { items = {
    [10] = { name = "Zulu", quality = 1, count = 9 },
    [11] = { name = "Epic", quality = 4, count = 1 },
    [12] = { name = "Alpha", quality = 1, count = 9 },
    [13] = { name = "More area", quality = 1, count = 10 },
    [14] = { name = "More session", quality = 1, count = 2 },
} }
local sortedSession = L.NewSession("fish", "fish:z:s", 0)
sortedSession.items = { [10] = { count = 1 }, [12] = { count = 1 }, [13] = { count = 1 }, [14] = { count = 2 } }
local sorted = L.Rows(sortedSession, sortedArea)
eq(sorted[1].name, "Epic"); eq(sorted[2].name, "More session"); eq(sorted[3].name, "More area")
eq(sorted[4].name, "Alpha"); eq(sorted[5].name, "Zulu")
_G.ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" } }
ns.UI = ns.UI or {}
local oldMoney = ns.UI.FormatMoney
ns.UI.FormatMoney = function(n) return tostring(n) .. "c" end
local lines = L.Lines({ kind = "fish", skill = { rank = 300, modifier = 22 }, sSeconds = 23,
    aSeconds = 3725, sTotal = 5, aTotal = 5, rows = L.Rows(fish, area) })
eq(lines[1].label, "|cffffd100Skill:|r"); eq(lines[1].value, "|cff20ff20300+22|r")
eq(lines[2].label, "|cffffd100Elapsed:|r"); eq(lines[2].value, "00:00:23/01:02:05")
eq(lines[4].label, "|cffffd100Totals:|r"); eq(lines[4].value, "5 (5)")
eq(lines[5].name, "|cffffffffFish|r")
eq(table.concat(lines[5].cells, "|"), "(|3| : |60.0%|, |3| : |60.0%|)")
lines = L.Lines({ kind = "fish", sSeconds = 0, aSeconds = 0, showPercent = false, rows = L.Rows(fish, area) })
eq(table.concat(lines[4].cells, "|"), "(|3|, |3|)", "percent columns can be left out")
lines = L.Lines({ kind = "farm", sSeconds = 0, aSeconds = 0, sTotal = 10, aTotal = 10,
    sGold = 123, aGold = 123, rows = {} })
eq(#lines, 3)
eq(lines[1].label, "|cffffd100Elapsed:|r"); eq(lines[1].value, "00:00:00/00:00:00")
eq(lines[2].label, "|cffffd100Gold:|r"); eq(lines[2].value, "123c (123c)")
eq(lines[3].label, "|cffffd100Totals:|r"); eq(lines[3].value, "10 (10)")
lines = L.Lines({ kind = "fish", sSeconds = 0, aSeconds = 0, rows = {} })
eq(lines[1].label, "|cffffd100Elapsed:|r", "no skill line without skill")
ns.UI.FormatMoney = oldMoney
_G.ITEM_QUALITY_COLORS = nil

local enUS = { GOLD_AMOUNT = "%d Gold", SILVER_AMOUNT = "%d Silver", COPPER_AMOUNT = "%d Copper",
    YOU_LOOT_MONEY = "You loot %s", LOOT_MONEY_SPLIT = "Your share of the loot is %s.",
    YOU_LOOT_MONEY_GUILD = "You loot %s (%s deposited to guild bank)",
    LOOT_MONEY_SPLIT_GUILD = "Your share of the loot is %s. (%s deposited to guild bank)",
    LOOT_MONEY = "%s loots %s." }
eq(L.LootMoney("You loot 1 Gold, 2 Silver, 3 Copper", enUS), 10203)
eq(L.LootMoney("You loot 45 Copper", enUS), 45)
eq(L.LootMoney("Your share of the loot is 7 Silver, 50 Copper.", enUS), 750, "group share")
eq(L.LootMoney("You loot 1 Gold (5 Silver deposited to guild bank)", enUS), 10000, "guild part not counted")
eq(L.LootMoney("Your share of the loot is 2 Silver. (1 Copper deposited to guild bank)", enUS), 200)
eq(L.LootMoney("You loot 1,234 Gold", enUS), 12340000, "thousands separator")
eq(L.LootMoney("Bob loots 5 Silver.", enUS), nil, "another player's loot")
eq(L.LootMoney("Received 5 Gold.", enUS), nil, "other money messages")
eq(L.LootMoney(nil, enUS), nil)
local ruRU = { GOLD_AMOUNT = "%d |4\208\183\208\190\208\187\208\190\209\130\208\176\209\143:\208\183\208\190\208\187\208\190\209\130\209\139\208\181:\208\183\208\190\208\187\208\190\209\130\209\139\209\133;",
    SILVER_AMOUNT = "%d |4s1:s2:s5;", COPPER_AMOUNT = "%d |4c1:c2:c5;", YOU_LOOT_MONEY = "Loot: %s.",
    LOOT_MONEY = "%s gets: %s." }
eq(L.LootMoney("Loot: 5 \208\183\208\190\208\187\208\190\209\130\209\139\209\133 2 s2 1 c1.", ruRU), 50201,
    "plural forms")
local koKR = { GOLD_AMOUNT = "%d G", SILVER_AMOUNT = "%d S", COPPER_AMOUNT = "%d C",
    YOU_LOOT_MONEY = "%s|1A;B; got.", LOOT_MONEY = "%s nim %s|1A;B; got." }
eq(L.LootMoney("3 SB got.", koKR), 300, "grammar suffix")
eq(L.LootMoney("Kim nim 3 SB got.", koKR), nil, "another player's loot with a suffix")
local deDE = { GOLD_AMOUNT = "%d Gold", SILVER_AMOUNT = "%d Silber", COPPER_AMOUNT = "%d Kupfer",
    YOU_LOOT_MONEY = "Ihr pl\195\188ndert %s", LOOT_MONEY = "%1$s pl\195\188ndert %2$s." }
eq(L.LootMoney("Ihr pl\195\188ndert 1.050 Gold 3 Kupfer", deDE), 10500003)
eq(L.LootMoney("Hans pl\195\188ndert 3 Kupfer.", deDE), nil, "positional arguments")
