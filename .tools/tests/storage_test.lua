local function Session(character, store, legacy, failNew, migrations)
    local frames = {}
    local g = setmetatable({ KLH_Store = store, KLH_DB = legacy, KLH_CharDB = legacy }, { __index = _G })
    g._G = g
    g.GetRealmName = function() return "Realm" end
    g.UnitName = function() return character end
    g.UnitClass = function() return "Mage", "MAGE" end
    g.UnitRace = function() return "Human", "Human" end
    g.UnitFactionGroup = function() return "Alliance" end
    g.GetLocale = function() return "enUS" end
    g.GetCurrentRegion = function() return 1 end
    g.CreateFrame = function()
        local frame = { RegisterEvent = function() end, UnregisterEvent = function() end }
        frame.SetScript = function(self, _, fn) self.handler = fn end
        frames[#frames + 1] = frame
        return frame
    end
    local function load(path, ...)
        local chunk = assert(loadfile(path))
        setfenv(chunk, g)
        return chunk(...)
    end
    load("Libs/LibStub/LibStub.lua")
    load("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")
    load("Libs/AceDB-3.0/AceDB-3.0.lua")
    if failNew == true then g.LibStub("AceDB-3.0").New = function() error("startup failure") end end
    if failNew == "profile" then
        local ace = g.LibStub("AceDB-3.0")
        local new = ace.New
        ace.New = function(self, ...)
            local candidate = new(self, ...)
            candidate.keys.profile = nil
            return candidate
        end
    end
    local namespace = {}
    load("Core/Schema.lua", "KlausisLittleHelpers", namespace)
    if migrations then
        local new = namespace.Schema.New
        namespace.Schema.New = function()
            local schema = new(1)
            schema:Register(0, migrations)
            return schema
        end
    end
    load("Core/Core.lua", "KlausisLittleHelpers", namespace)
    return g, namespace, function() frames[1].handler(frames[1], "PLAYER_LOGOUT") end
end

local firstGlobal, firstNS, firstLogout = Session("First", nil)
local firstDB = firstNS.GetDB()
eq(firstDB:GetCurrentProfile(), "Default", "first character uses shared default profile")
firstNS.GetSettings("sample").value = 42
firstLogout()
local secondGlobal, secondNS = Session("Second", firstGlobal.KLH_Store)
eq(secondNS.GetDB():GetCurrentProfile(), "Default", "second character uses shared default profile")
eq(secondNS.GetSettings("sample").value, 42, "default profile settings are shared")
eq(secondGlobal.KLH_Store.database.profiles["Second - Realm"], nil, "no automatic character profile")
local mappedStore = { schemaVersion = 0, database = {
    profileKeys = { ["Existing - Realm"] = "Custom" },
    profiles = { Custom = { features = { sample = { value = 99 } } } },
} }
local _, mappedNS = Session("Existing", mappedStore)
eq(mappedNS.GetDB():GetCurrentProfile(), "Custom", "existing profile mapping is preserved")
eq(mappedNS.GetSettings("sample").value, 99, "existing profile settings are preserved")

local old = { profile = { features = { old = true } }, turnInRoute = { old = true } }
local g, n, logout = Session("One", nil, old)
local db = n.GetDB()
eq(g.KLH_Store.schemaVersion, 0, "version persists outside defaults")
ok(db.sv == g.KLH_Store.database, "AceDB uses published database")
eq(n.GetSettings("old").old, nil, "legacy profile ignored")
eq(n.CharData("turnInRoute").old, nil, "legacy character ignored")
n.CharData("turnInRoute").route = "one"
n.GetSettings("sample").value = 7
db:SetProfile("shared")
n.GetSettings("sample").value = 9
db:CopyProfile("Default")
eq(n.GetSettings("sample").value, 7, "profile copy remains native")
db:ResetProfile()
eq(n.GetSettings("sample").value, nil, "profile reset remains native")
eq(n.CharData("turnInRoute").route, "one", "profile operations preserve character data")
logout()
eq(g.KLH_Store.schemaVersion, 0, "logout retains schema version")
local g2, n2, logout2 = Session("Two", g.KLH_Store, old)
eq(n2.CharData("turnInRoute").route, nil, "second character isolated")
n2.CharData("turnInRoute").route = "two"
logout2()
local g3, n3 = Session("One", g2.KLH_Store, old)
eq(n3.CharData("turnInRoute").route, "one", "first character restored")
eq(g3.KLH_Store.database.char["Two - Realm"].turnInRoute.route, "two", "second character persisted")
for _, source in ipairs({ { schemaVersion = 1, nested = { value = 1 } }, { schemaVersion = "bad" }, { schemaVersion = -1 } }) do
    local failed, bad = Session("One", source, old)
    local success = pcall(bad.GetDB)
    ok(not success, "invalid schema fails closed")
    ok(failed.KLH_Store == source, "failure does not publish")
end
local calls = 0
local function migrate(root)
    calls = calls + 1
    root.migrated = true
end
local resetGlobal, resetNS, resetLogout = Session("One", {}, old, false, migrate)
resetNS.GetDB():ResetDB()
resetLogout()
eq(resetGlobal.KLH_Store.schemaVersion, 1, "ResetDB preserves envelope version")
local _, reloaded = Session("One", resetGlobal.KLH_Store, old, false, migrate)
reloaded.GetDB()
eq(calls, 1, "ResetDB and logout do not replay migrations")
local malformed = { schemaVersion = 0, database = "bad" }
local malformedGlobal, malformedNS = Session("One", malformed, old)
ok(not pcall(malformedNS.GetDB), "malformed database fails closed")
ok(malformedGlobal.KLH_Store == malformed, "malformed database is not published")
for _, failure in ipairs({ "malformed", "profile" }) do
    local original = { schemaVersion = 0, database = failure == "malformed" and { profiles = "bad" } or {} }
    local failedGlobal, failedNS, failedLogout = Session("One", original, old, failure == "profile" and "profile" or false)
    local registry = failedGlobal.LibStub("AceDB-3.0").db_registry
    ok(not pcall(failedNS.GetDB), "lazy profile failure propagates")
    ok(failedGlobal.KLH_Store == original, "lazy profile failure does not publish")
    eq(next(registry), nil, "failed database removed from registry")
    failedLogout()
    ok(failedGlobal.KLH_Store == original, "logout leaves failed source untouched")
end
local source = { schemaVersion = 0, nested = { value = 1 } }
local failed, bad = Session("One", source, old, true)
ok(not pcall(bad.GetDB), "AceDB startup failure propagates")
ok(failed.KLH_Store == source and source.nested.value == 1, "startup failure rolls back")
