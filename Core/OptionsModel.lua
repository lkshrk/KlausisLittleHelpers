local _, ns = ...

local M = {}
ns.OptionsModel = M

local DEFAULT_ORDER = 100
local SEPARATOR = "."
local KIND_SPAN = { toggle = 1, select = 1, range = 1, execute = 1, input = 1, description = 3, header = 3 }
local WIDTH_SPAN = { double = 2, full = 3 }
local INHERITED = { get = true, set = true, func = true, confirm = true, disabled = true, hidden = true }
local LITERAL_STRING = { name = true, desc = true, fontSize = true, width = true }

local function Copy(list, extra)
    local out = {}
    for i = 1, #list do out[i] = list[i] end
    if extra ~= nil then out[#out + 1] = extra end
    return out
end

function M.Info(path, option, options, handler)
    local info = Copy(path)
    info.option, info.options, info.handler = option, options, handler
    info.arg, info.type = option.arg, option.type
    return info
end

local function Node(root, path, chain)
    return { root = root, path = path, chain = chain, option = chain[#chain] }
end

local function Child(node, key)
    return Node(node.root, Copy(node.path, key), Copy(node.chain, node.option.args[key]))
end

local function Handler(node)
    local handler
    for i = 1, #node.chain do handler = node.chain[i].handler or handler end
    return handler
end

local function Member(node, field)
    if not INHERITED[field] then return node.option[field] end
    local member
    for i = 1, #node.chain do
        if node.chain[i][field] ~= nil then member = node.chain[i][field] end
    end
    return member
end

local function Callable(field, member)
    return type(member) == "function" or (type(member) == "string" and not LITERAL_STRING[field])
end

local function Call(node, field, member, ...)
    local handler = Handler(node)
    local info = M.Info(node.path, node.option, node.root, handler)
    if type(member) == "function" then return member(info, ...) end
    if not (handler and handler[member]) then
        error(("Method %s doesn't exist in handler for type %s"):format(member, field), 0)
    end
    return handler[member](handler, info, ...)
end

local function Value(node, field, ...)
    local member = Member(node, field)
    if Callable(field, member) then return Call(node, field, member, ...) end
    return member
end

local function Disabled(node)
    for depth = 1, #node.chain do
        local own = node.chain[depth].disabled
        if Callable("disabled", own) then own = Call(node, "disabled", own) end
        if own then return true end
    end
    return false
end

local function Label(node)
    local name = Value(node, "name")
    if type(name) == "string" then return name end
    return tostring(node.path[#node.path])
end

local function SortedChildren(node)
    local children, orders, names = {}, {}, {}
    for key in pairs(node.option.args or {}) do
        local child = Child(node, key)
        local order, name = Value(child, "order"), Value(child, "name")
        children[#children + 1] = child
        orders[child] = type(order) == "number" and order or DEFAULT_ORDER
        names[child] = type(name) == "string" and name:upper() or ""
    end
    table.sort(children, function(a, b)
        local oa, ob = orders[a], orders[b]
        if oa == ob then
            if names[a] ~= names[b] then return names[a] < names[b] end
            return tostring(a.path[#a.path]) < tostring(b.path[#b.path])
        end
        if (oa < 0) ~= (ob < 0) then return ob < 0 end
        return oa < ob
    end)
    return children
end

local function VisibleGroups(node)
    local groups = {}
    for _, child in ipairs(SortedChildren(node)) do
        if child.option.type == "group" and not Value(child, "hidden") then groups[#groups + 1] = child end
    end
    return groups
end

local function Id(path)
    return table.concat(path, SEPARATOR)
end

function M.Entries(root)
    local entries = {}
    for _, group in ipairs(VisibleGroups(Node(root, {}, { root }))) do
        local tree = group.option.childGroups == "tree"
        entries[#entries + 1] = { id = Id(group.path), label = Label(group), level = 1, heading = tree }
        if tree then
            for _, child in ipairs(VisibleGroups(group)) do
                entries[#entries + 1] = { id = Id(child.path), label = Label(child), level = 2, heading = false }
            end
        end
    end
    return entries
end

local function Clamp(option, value)
    local min = option.min or (not option.softMin and 0 or nil)
    local max = option.max or (not option.softMax and 100 or nil)
    local step = option.step
    if min then
        if step and step > 0 then value = math.floor((value - min) / step + 0.5) * step + min end
        value = math.max(value, min)
    end
    if max then value = math.min(value, max) end
    return value
end

local function KeyOrder(a, b)
    local na, nb = tonumber(a), tonumber(b)
    if na and nb then return na < nb end
    return tostring(a) < tostring(b)
end

local function Sorting(node)
    local sorting = Value(node, "sorting")
    if type(sorting) == "table" then return sorting end
    local keys = {}
    for key in pairs(Value(node, "values") or {}) do keys[#keys + 1] = key end
    table.sort(keys, KeyOrder)
    return keys
end

local function ConfirmText(node, ...)
    local confirm = Member(node, "confirm")
    if type(confirm) == "function" or type(confirm) == "string" then
        confirm = Call(node, "confirm", confirm, ...)
        if type(confirm) == "string" then return confirm end
    end
    if confirm ~= true then return nil end
    if node.option.confirmText then return node.option.confirmText end
    local name, desc = Label(node), Value(node, "desc")
    if desc then return name .. " - " .. desc end
    return name
end

local function Control(node, kind)
    local option = node.option
    local control = {
        kind = kind, id = Id(node.path), key = node.path[#node.path],
        span = KIND_SPAN[kind] == 3 and 3 or WIDTH_SPAN[option.width] or 1,
        label = Label(node), desc = Value(node, "desc"), fontSize = option.fontSize, style = option.style,
        disabled = function() return Disabled(node) end,
        hidden = function() return Value(node, "hidden") and true or false end,
        confirmText = function(...) return ConfirmText(node, ...) end,
    }
    if kind == "execute" then
        control.run = function()
            local func = Member(node, "func")
            if Callable("func", func) then return Call(node, "func", func) end
        end
    elseif kind ~= "description" and kind ~= "header" then
        control.get = function() return Value(node, "get") end
        control.set = function(value)
            if kind == "range" and type(value) == "number" then value = Clamp(option, value) end
            local set = Member(node, "set")
            if Callable("set", set) then return Call(node, "set", set, value) end
        end
    end
    if kind == "select" then
        control.values = function() return Value(node, "values") or {} end
        control.sorting = function() return Sorting(node) end
    elseif kind == "range" then
        control.range = {
            min = option.softMin or option.min or 0, max = option.softMax or option.max or 100,
            step = option.step or 0, bigStep = option.bigStep, isPercent = option.isPercent and true or false,
        }
    end
    return control
end

local function Collect(node, controls)
    for _, child in ipairs(SortedChildren(node)) do
        local kind = child.option.type
        if kind == "group" then
            if not Value(child, "hidden") then
                controls[#controls + 1] = Control(child, "header")
                Collect(child, controls)
            end
        elseif KIND_SPAN[kind] then
            controls[#controls + 1] = Control(child, kind)
        end
    end
end

local function Find(root, id)
    local node = Node(root, {}, { root })
    for key in id:gmatch("[^" .. SEPARATOR .. "]+") do
        local args = node.option.args
        if not (args and type(args[key]) == "table") then return nil end
        node = Child(node, key)
    end
    if node.option.type ~= "group" then return nil end
    return node
end

function M.Page(root, id)
    local node = Find(root, id)
    if not node then return nil end
    local controls = {}
    Collect(node, controls)
    return { id = id, title = Label(node), controls = controls }
end
