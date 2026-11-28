addon("Core/Core.lua")

local fixtures = {
    [0] = {
        input = function() return { schemaVersion = 0, database = { profiles = { Default = { marker = "kept" } } } } end,
        verify = function(result) return result.database.profiles.Default.marker == "kept" end,
    },
}

local function check(factory, cases)
    local schema, target = factory()
    if type(target) ~= "number" or target < 0 or target ~= math.floor(target) then return false end
    for version = 0, target do
        local fixture = cases[version]
        if type(fixture) ~= "table" or type(fixture.input) ~= "function" or type(fixture.verify) ~= "function" then
            return false
        end
        local input = fixture.input()
        if type(input) ~= "table" or input.schemaVersion ~= version then return false end
        local result = schema:Migrate(input)
        if not result or result.schemaVersion ~= target or not fixture.verify(result) then return false end
    end
    return true
end

ok(check(ns.StorageSchema, fixtures), "storage migration fixtures and steps cover every version")
local function synthetic(withStep)
    return function()
        local schema = ns.Schema.New(1)
        if withStep then schema:Register(0, function(data) data.migrated = true end) end
        return schema, 1
    end
end
local syntheticFixtures = {
    [0] = { input = function() return { schemaVersion = 0 } end, verify = function(data) return data.migrated end },
    [1] = { input = function() return { schemaVersion = 1, migrated = true } end, verify = function(data) return data.migrated end },
}
ok(check(synthetic(true), syntheticFixtures), "complete synthetic migration passes")
ok(not check(synthetic(false), syntheticFixtures), "missing migration step fails")
ok(not check(synthetic(true), { [1] = syntheticFixtures[1] }), "missing prior fixture fails")
