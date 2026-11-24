local SKIP = { ["Modules/TustUIXPBar.lua"] = true, ["Core/Skin.lua"] = true }
local FORBIDDEN = { "EllesmereUI", "EUI.", "EUI_CLIENT_BLOCKED" }

local toc = io.open("KlausisLittleHelpers.toc", "r")
ok(toc, "toc readable")
local offenders = {}
for line in toc:lines() do
    local path = line:match("^(Core\\%S+%.lua)") or line:match("^(Modules\\%S+%.lua)") or line:match("^(Data\\%S+%.lua)")
    if path then
        path = path:gsub("\\", "/")
        if not SKIP[path] then
            local f = io.open(path, "r")
            ok(f, path .. " readable")
            local text = f:read("*a")
            f:close()
            for _, word in ipairs(FORBIDDEN) do
                if text:find(word, 1, true) then offenders[#offenders + 1] = path .. " (" .. word .. ")" end
            end
        end
    end
end
toc:close()
ok(#offenders == 0, "EUI references: " .. table.concat(offenders, ", "))
