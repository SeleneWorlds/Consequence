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

function Handlers.registerEffectType(id, handler)
    register(Handlers.EffectTypes, id, handler)
end

function Handlers.getEffectType(id)
    return get(Handlers.EffectTypes, id)
end

return Handlers
