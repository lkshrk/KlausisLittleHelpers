-- Usage: lua5.1 .tools/check-toc.lua KlausisLittleHelpers.toc
local toc = assert(arg[1], "usage: check-toc.lua <file.toc>")
local listed, failed = {}, false

for line in io.lines(toc) do
    line = line:gsub("\r$", "")
    if line ~= "" and not line:find("^#") then
        local path = line:gsub("\\", "/")
        listed[path] = true
        local fh = io.open(path, "r")
        if fh then
            fh:close()
        else
            print(toc .. ": listed file missing: " .. path)
            failed = true
        end
    end
end

local embeds = "Libs/embeds.xml"
local efh = io.open(embeds, "r")
if efh then
    local xml = efh:read("*a")
    efh:close()
    for file in xml:gmatch('<%a+%s+file="([^"]+)"') do
        file = file:gsub("\\", "/")
        local fh = io.open("Libs/" .. file, "r")
        if fh then
            fh:close()
        else
            print(embeds .. ": entry missing: " .. file)
            failed = true
        end
    end
end

local pipe = io.popen("git ls-files --cached --others --exclude-standard -- '*.lua' ':!:scripts/**' ':!:tests/**' ':!:Libs/**' ':!:.tools/**'")
for path in pipe:lines() do
    if not listed[path] then
        print(toc .. ": not loaded: " .. path)
        failed = true
    end
end
pipe:close()

if failed then os.exit(1) end
print("toc: OK")
