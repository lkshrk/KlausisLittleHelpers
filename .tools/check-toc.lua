-- Usage: lua5.1 .tools/check-toc.lua LKS_UI.toc
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
