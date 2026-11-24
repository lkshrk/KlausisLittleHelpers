local printed, realPrint = {}, _G.print
local got
_G.SlashCmdList = {}
_G.print = function(s) printed[#printed + 1] = tostring(s) end
local good, problem = pcall(function()
    addon("Core/Core.lua")
    local slash = _G.SlashCmdList.KLH
    ns.FEATURE_CLIENTS.W = "all"
    ns.RegisterFeature({ key = "W", title = "Writ & Crate Planner", requires = { "Auctionator" }, commands = { "writs" }, alwaysOn = true, enable = function() end })
    slash("writs")
    slash("nope")
    ns.RegisterSlashCommand("echo", function(rest) got = rest end)
    slash("  Echo   one two  ")
end)
_G.print, _G.SlashCmdList = realPrint, nil
ok(good, tostring(problem))
ok(printed[1]:find("Writ & Crate Planner: Requires: Auctionator", 1, true), printed[1])
ok(printed[2]:find("Unknown command nope", 1, true), printed[2])
eq(got, "one two", "registered command receives rest")
