-- Usage: lua5.1 .tools/tests/run.lua <test files...>
local passed = 0
local failures = {}
local current

local function fail(msg, detail)
    local line = "FAIL " .. (current and (current .. ": ") or "") .. (msg or "?") .. (detail and (": " .. detail) or "")
    failures[#failures + 1] = line
end

local function NewEnv()
    local env = setmetatable({}, { __index = _G })
    env.eq = function(a, b, msg)
        if a ~= b then fail(msg or "eq", tostring(a) .. " ~= " .. tostring(b)) end
        passed = passed + 1
    end
    env.ok = function(cond, msg)
        if not cond then fail(msg or "ok") end
        passed = passed + 1
    end
    env.find = function(list, field, value, pred)
        for _, row in ipairs(list) do
            if pred then
                if pred(row) then return row end
            elseif row[field] == value then
                return row
            end
        end
    end
    env.has = function(list, field, value, pred)
        return env.find(list, field, value, pred) ~= nil
    end
    env.ns = { Data = {} }
    env.addon = function(path)
        local chunk, err = loadfile(path)
        if not chunk then fail("load " .. path, err) return end
        if path == "Core/Core.lua" then
            assert(loadfile("Core/Schema.lua"))("KlausisLittleHelpers", env.ns)
        end
        chunk("KlausisLittleHelpers", env.ns)
    end
    return env
end

for _, file in ipairs(arg) do
    current = file
    local env = NewEnv()
    local chunk, err = loadfile(file)
    if not chunk then
        fail("compile", err)
    else
        setfenv(chunk, env)
        local good, problem = pcall(chunk)
        if not good then fail("error", tostring(problem)) end
    end
end
current = nil

if #failures > 0 then
    io.stderr:write(table.concat(failures, "\n") .. "\n")
    io.stderr:write(#failures .. " failure(s), " .. passed .. " assertions passed\n")
    os.exit(1)
end

print("PASS " .. #arg .. " files, " .. passed .. " assertions")
