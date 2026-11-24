local names = { "SettingsPanel", "HideUIPanel", "C_Timer", "InCombatLockdown", "geterrorhandler", "CreateFrame" }
local saved = {}
for _, k in ipairs(names) do saved[k] = rawget(_G, k) end
addon("Core/Core.lua"); addon("Core/Options.lua")
local log, timers = {}, {}
local shown = true
_G.SettingsPanel = { IsShown = function() return shown end, Hide = function() log[#log + 1] = "hide" end,
    Close = function(_, skip) shown = false; log[#log + 1] = "close:" .. tostring(skip) end }
_G.HideUIPanel = function() log[#log + 1] = "hideui" end
_G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local realOpen = ns.OpenOptions
ns.OpenOptions = function() log[#log + 1] = "open" end
ns.OpenFromSettings()
eq(table.concat(log, ","), "close:true", "settings panel closes through its own Close before anything opens")
eq(#timers, 1)
timers[1]()
eq(table.concat(log, ","), "close:true,open", "options open a frame later")
log, timers = {}, {}
ns.OpenFromSettings()
eq(#log, 0, "no close when the panel is already closed"); timers[1]()
eq(table.concat(log, ","), "open")

log, timers, shown = {}, {}, true
_G.SettingsPanel.Close = nil
ns.OpenFromSettings()
eq(table.concat(log, ","), "hideui", "HideUIPanel when the panel has no Close")

local combat, regen = true, nil
_G.InCombatLockdown = function() return combat end
_G.geterrorhandler = function() return print end
_G.CreateFrame = function()
    return { RegisterEvent = function() end, SetScript = function(_, _, fn) regen = fn end }
end
addon("Core/UI.lua")
log, timers, shown = {}, {}, true
_G.SettingsPanel.Close = function() shown = false; log[#log + 1] = "close" end
ns.OpenFromSettings()
eq(#log, 0, "nothing happens in combat"); eq(#timers, 0)
combat = false
regen()
eq(table.concat(log, ","), "close", "deferred until combat ends"); eq(#timers, 1)

ns.OpenOptions = realOpen
for _, k in ipairs(names) do _G[k] = saved[k] end
