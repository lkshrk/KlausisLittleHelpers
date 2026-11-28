local _, ns = ...

local Schema = {}
ns.Schema = Schema

local function validVersion(version)
    return type(version) == "number" and version >= 0 and version <= 9007199254740991
        and version == math.floor(version)
end

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[clone(key, seen)] = clone(item, seen)
    end
    return copy
end

function Schema.New(target)
    assert(validVersion(target), "invalid target version")
    local steps = {}
    local schema = {}

    function schema:Register(from, step)
        assert(validVersion(from) and from < target, "invalid step version")
        assert(type(step) == "function", "step must be a function")
        assert(not steps[from], "step already registered")
        steps[from] = step
    end

    function schema:Migrate(data)
        if type(data) ~= "table" then return nil, "data must be a table" end
        local version = data.schemaVersion
        if version == nil then version = 0 end
        if not validVersion(version) then return nil, "invalid schema version" end
        if version > target then return nil, "future schema version" end
        for from = version, target - 1 do
            if not steps[from] then return nil, "missing migration step " .. from end
        end
        local cloned, result = pcall(clone, data, {})
        if not cloned then return nil, "clone failed: " .. tostring(result) end
        for from = version, target - 1 do
            local ok, outcome, reason = pcall(steps[from], result)
            if not ok or outcome == false or (outcome == nil and reason ~= nil) then
                local detail = ok and reason or outcome
                return nil, "migration step " .. from .. " failed: " .. tostring(detail)
            end
            result.schemaVersion = from + 1
        end
        result.schemaVersion = target
        return result
    end

    return schema
end
