local ModuleLoader = require("consequence.server.lua.lib.module_loader")
local ParserRegistry = require("consequence.server.lua.lib.parser_registry")
local Utils = require("consequence.server.lua.lib.utils")

local Conditions = {}

local function matchField(spec, root, context, payload, defaultPath)
    local path = spec.path or defaultPath
    local actual = Utils.getPath(root, path)

    if spec.value ~= nil or spec.valueFromContext ~= nil or spec.valueFromPayload ~= nil then
        local expected = Utils.resolveValue(spec, context, payload)
        return actual == expected
    end

    if type(actual) ~= "string" then
        return false
    end

    actual = Utils.normalizeText(actual, spec.trim, spec.caseSensitive ~= true)

    if spec.equals ~= nil then
        local expected = Utils.normalizeText(spec.equals, spec.trim, spec.caseSensitive ~= true)
        return actual == expected
    end

    if spec.contains ~= nil then
        local expected = Utils.normalizeText(spec.contains, spec.trim, spec.caseSensitive ~= true)
        return string.find(actual, expected, 1, true) ~= nil
    end

    if spec.pattern ~= nil then
        return string.find(actual, spec.pattern) ~= nil
    end

    if type(spec.oneOf) == "table" then
        for _, candidate in ipairs(spec.oneOf) do
            local expected = Utils.normalizeText(candidate, spec.trim, spec.caseSensitive ~= true)
            if actual == expected then
                return true
            end
        end
        return false
    end

    return true
end

function Conditions.register(Handlers)
    ParserRegistry.registerPositionalArguments("consequence:match", { "...patterns" })

    Handlers.registerEffectType("consequence:all", function(spec, context, payload, _, options)
        for _, nestedEffect in ipairs(spec.effects or {}) do
            local handler = Handlers.getEffectType(nestedEffect.type, options and options.defaultNamespaces)
            if not handler or not handler(nestedEffect, context, payload, nil, options) then
                return false
            end
        end
        return true
    end)

    Handlers.registerEffectType("consequence:any", function(spec, context, payload, _, options)
        local sawEffect = false
        for _, nestedEffect in ipairs(spec.effects or {}) do
            sawEffect = true
            local handler = Handlers.getEffectType(nestedEffect.type, options and options.defaultNamespaces)
            if handler and handler(nestedEffect, context, payload, nil, options) then
                return true
            end
        end
        return not sawEffect
    end)

    Handlers.registerEffectType("consequence:not", function(spec, context, payload, _, options)
        local nestedEffect = spec.effect
        if type(nestedEffect) ~= "table" then
            return true
        end
        local handler = Handlers.getEffectType(nestedEffect.type, options and options.defaultNamespaces)
        return not (handler and handler(nestedEffect, context, payload, nil, options))
    end)

    Handlers.registerEffectType("consequence:context_field_match", function(spec, context, payload)
        return matchField(spec, context or {}, context, payload, nil)
    end)

    Handlers.registerEffectType("consequence:payload_field_match", function(spec, context, payload)
        return matchField(spec, payload or {}, context, payload, "message")
    end)

    Handlers.registerEffectType("consequence:match", function(spec, _, payload)
        local actual = Utils.getPath(payload or {}, "message")
        if type(actual) ~= "string" then
            return false
        end
        actual = string.lower(actual)

        local patterns = spec.patterns or {}
        if #patterns == 0 then
            return false
        end

        for _, pattern in ipairs(patterns) do
            if type(pattern) == "string" and string.find(actual, pattern) ~= nil then
                return true
            end
        end

        return false
    end)

    Handlers.registerEffectType("consequence:script", function(spec, context, payload)
        local fn = ModuleLoader.resolveEffectFunction(spec)
        return fn(spec, context, payload)
    end)
end

return Conditions
