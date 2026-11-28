addon("Core/Schema.lua")
local S = ns.Schema
local schema = S.New(2)
local calls = {}
schema:Register(0, function(data)
    calls[#calls + 1] = 0
    data.nested.value = data.nested.value + 1
end)
schema:Register(1, function(data)
    calls[#calls + 1] = 1
    data.added = true
end)
local input = { nested = { value = 4 }, unknown = { x = 9 } }
local result = assert(schema:Migrate(input))
eq(result.schemaVersion, 2)
eq(result.nested.value, 5)
eq(result.unknown.x, 9)
eq(input.nested.value, 4)
eq(input.schemaVersion, nil)
eq(calls[1], 0); eq(calls[2], 1)
local again = assert(schema:Migrate(result))
eq(again.nested.value, 5); eq(#calls, 2)
assert(again ~= result and again.unknown ~= result.unknown)
local future = { schemaVersion = 3, nested = { value = 8 } }
local value, err = schema:Migrate(future)
eq(value, nil); assert(err); eq(future.nested.value, 8)
local missing = S.New(2)
missing:Register(0, function(data) data.nested.value = 99 end)
value, err = missing:Migrate(input)
eq(value, nil); assert(err); eq(input.nested.value, 4)
local failing = S.New(1)
failing:Register(0, function(data) data.nested.value = 99; error("step failed") end)
value, err = failing:Migrate(input)
eq(value, nil); assert(err:find("step failed", 1, true)); eq(input.nested.value, 4)
for _, version in ipairs({ -1, 0.5, math.huge, -math.huge, 0/0, "1" }) do
    value, err = schema:Migrate({ schemaVersion = version })
    eq(value, nil); assert(err)
end
local explicitFailure = S.New(1)
explicitFailure:Register(0, function(data) data.nested.value = 77; return false, "rejected" end)
value, err = explicitFailure:Migrate(input)
eq(value, nil); assert(err:find("rejected", 1, true)); eq(input.nested.value, 4)
local nilFailure = S.New(1)
nilFailure:Register(0, function(data) data.nested.value = 77; return nil, "invalid data" end)
value, err = nilFailure:Migrate(input)
eq(value, nil); assert(err:find("invalid data", 1, true)); eq(input.nested.value, 4)
local silentFailure = S.New(1)
silentFailure:Register(0, function() return false end)
value, err = silentFailure:Migrate(input)
eq(value, nil); assert(err)
local deep = {}
local cursor = deep
for _ = 1, 30000 do
    cursor.child = {}
    cursor = cursor.child
end
local ok
ok, value, err = pcall(function() return S.New(0):Migrate(deep) end)
assert(ok)
assert(value or err)
assert(deep.child)
assert(not pcall(S.New, math.huge))
assert(not pcall(function() schema:Register(0, function() end) end))
