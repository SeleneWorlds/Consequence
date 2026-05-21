local Registry = {
    positionalArguments = {}
}

local function fail(message)
    error(message, 0)
end

local function isIdentifier(value)
    return type(value) == "string" and value:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
end

local function validateIdentifier(value, label)
    if not isIdentifier(value) then
        fail(label .. " must be a valid identifier.")
    end
end

function Registry.normalizeSymbolParts(namespace, name)
    validateIdentifier(name, "Symbol name")
    if namespace == nil or namespace == "" then
        return "consequence:" .. name
    end
    validateIdentifier(namespace, "Symbol namespace")
    return namespace .. ":" .. name
end

function Registry.normalizeSymbol(symbol)
    if type(symbol) ~= "string" then
        fail("Symbol must be a string.")
    end

    local firstColon = symbol:find(":", 1, true)
    if not firstColon then
        return Registry.normalizeSymbolParts(nil, symbol)
    end

    if symbol:find(":", firstColon + 1, true) then
        fail("Symbol must contain at most one namespace separator.")
    end

    local namespace = symbol:sub(1, firstColon - 1)
    local name = symbol:sub(firstColon + 1)
    if namespace == "" or name == "" then
        fail("Symbol namespace and name must both be present.")
    end

    return Registry.normalizeSymbolParts(namespace, name)
end

local function copyNames(names)
    if type(names) ~= "table" then
        fail("Positional argument names must be provided as an array.")
    end

    local copied = {}
    local seen = {}
    for index, value in ipairs(names) do
        validateIdentifier(value, "Positional argument name")
        if seen[value] then
            fail("Duplicate positional argument name '" .. value .. "'.")
        end
        copied[index] = value
        seen[value] = true
    end

    for key, _ in pairs(names) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) or key > #copied then
            fail("Positional argument names must be a dense array.")
        end
    end

    return copied
end

function Registry.registerPositionalArguments(symbol, names)
    local normalized = Registry.normalizeSymbol(symbol)
    Registry.positionalArguments[normalized] = copyNames(names)
end

function Registry.getPositionalArguments(symbol)
    local names = Registry.positionalArguments[symbol]
    if names == nil then
        return nil
    end

    local copied = {}
    for index, value in ipairs(names) do
        copied[index] = value
    end
    return copied
end

function Registry.clear()
    Registry.positionalArguments = {}
end

return Registry
