local combat, handler = true, nil
local saved = {}
for _, k in ipairs({ "InCombatLockdown", "geterrorhandler", "CreateFrame" }) do saved[k] = rawget(_G, k) end
_G.InCombatLockdown = function() return combat end
_G.geterrorhandler = function() return print end
_G.CreateFrame = function()
    return {
        RegisterEvent = function() end,
        SetScript = function(_, _, fn) handler = fn end,
    }
end
addon("Core/UI.lua")
local calls = {}
ns.UI.Defer("a", function() calls[#calls + 1] = "a1" end)
ns.UI.Defer("a", function() calls[#calls + 1] = "a2" end)
ns.UI.Defer("b", function() calls[#calls + 1] = "b" end)
eq(#calls, 0, "deferred in combat")
combat = false
handler()
eq(table.concat(calls, ","), "a2,b", "latest per key runs once")
handler()
eq(#calls, 2, "queue drained")
ns.UI.Defer("c", function() calls[#calls + 1] = "c" end)
eq(calls[3], "c", "runs now out of combat")
local r, g, b = ns.UI.Accent()
eq(r, 0.05); eq(g, 0.82); eq(b, 0.62)
for k, v in pairs(saved) do _G[k] = v end

do
    local savedTexture = rawget(_G, "C_Texture")
    local function Tex()
        local t = {}
        t.SetAtlas = function(self, name) self.atlas = name end
        t.SetTexture = function(self, file) self.file = file end
        return t
    end
    _G.C_Texture = { GetAtlasInfo = function(name) return name == "common-dropdown-classic-a-buttonDown" and {} or nil end }
    local t = Tex()
    eq(ns.UI.SetArrowTexture(t), "common-dropdown-classic-a-buttonDown", "first atlas the client has")
    eq(t.atlas, "common-dropdown-classic-a-buttonDown")
    _G.C_Texture = { GetAtlasInfo = function() return nil end }
    t = Tex()
    eq(ns.UI.SetArrowTexture(t), "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up", "file fallback without the atlases")
    eq(t.atlas, nil); ok(t.file ~= nil)
    _G.C_Texture = savedTexture
end

do
    local savedTip = rawget(_G, "GameTooltip")
    local tipCalls = {}
    local tip = setmetatable({}, { __index = function(_, k)
        return function(_, ...) tipCalls[#tipCalls + 1] = { k, ... } end
    end })
    _G.GameTooltip = tip
    ns.UI.ShowItemTooltip("owner", 248699, "Fill each with 20 Dream Dust.")
    local names = {}
    for _, c in ipairs(tipCalls) do names[#names + 1] = c[1] end
    local seq = table.concat(names, ",")
    ok(seq:find("SetOwner,SetItemByID,AddLine,AddLine,Show", 1, true), "item tooltip, then our hint below it: " .. seq)
    local set
    for _, c in ipairs(tipCalls) do if c[1] == "SetItemByID" then set = c[2] end end
    eq(set, 248699)
    eq(tipCalls[#tipCalls - 1][2], "Fill each with 20 Dream Dust.")
    tipCalls = {}
    ns.UI.ShowItemTooltip("owner", 1)
    local adds = 0
    for _, c in ipairs(tipCalls) do if c[1] == "AddLine" then adds = adds + 1 end end
    eq(adds, 0, "no hint, no extra lines")
    _G.GameTooltip = savedTip
end
