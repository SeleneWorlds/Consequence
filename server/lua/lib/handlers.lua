local Handlers = {
    EffectTypes = {}
}

local function validateId(id)
    if type(id) ~= "string" or id == "" then
        error("Handler type id must be a non-empty string.")
    end
end

local function validateHandler(handler)
    if type(handler) ~= "function" then
        error("Handler must be a function.")
    end
end

local function register(map, id, handler)
    validateId(id)
    validateHandler(handler)
    map[id] = handler
end

local function get(map, id)
    if type(id) ~= "string" or id == "" then
        return nil
    end
    return map[id]
end

local function validateDefaultNamespaces(defaultNamespaces)
    if defaultNamespaces == nil then
        return {}
    end
    if type(defaultNamespaces) ~= "table" then
        error("Default namespaces must be provided as an array.", 0)
    end

    local copied = {}
    for index, value in ipairs(defaultNamespaces) do
        validateId(value)
        copied[index] = value
    end
    return copied
end

function Handlers.registerEffectType(id, handler)
    register(Handlers.EffectTypes, id, handler)
end

function Handlers.getEffectType(id, defaultNamespaces)
    local handler = get(Handlers.EffectTypes, id)
    if handler ~= nil then
        return handler, id
    end

    if type(id) ~= "string" or id == "" or id:find(":", 1, true) ~= nil then
        return nil, id
    end

    for _, namespace in ipairs(validateDefaultNamespaces(defaultNamespaces)) do
        local candidate = namespace .. ":" .. id
        handler = get(Handlers.EffectTypes, candidate)
        if handler ~= nil then
            return handler, candidate
        end
    end

    return nil, id
end

return Handlers
