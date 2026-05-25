local ModuleLoader = require("consequence.server.lua.lib.module_loader")
local ParserRegistry = require("consequence.server.lua.lib.parser_registry")
local Utils = require("consequence.server.lua.lib.utils")

local Actions = {}

local function isArray(value)
    if type(value) ~= "table" then
        return false
    end

    local count = 0
    for key, _ in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
            return false
        end
        count = count + 1
    end

    return count == #value
end

local function resolveValue(value, context, payload, Handlers, options)
    if type(value) ~= "table" then
        return value
    end

    local effectType = value.type
    local handler = type(effectType) == "string" and Handlers.getEffectType(effectType, options and options.defaultNamespaces) or nil
    if handler ~= nil then
        return handler(value, context, payload, nil, options)
    end

    if not isArray(value) then
        return value
    end

    local resolved = {}
    for index, entry in ipairs(value) do
        resolved[index] = resolveValue(entry, context, payload, Handlers, options)
    end
    return resolved
end

local function evaluateCondition(value, context, payload, Handlers, options)
    if type(value) ~= "table" then
        return value ~= nil and value ~= false
    end

    local effectType = value.type
    local handler = type(effectType) == "string" and Handlers.getEffectType(effectType, options and options.defaultNamespaces) or nil
    if handler == nil then
        return value ~= nil
    end

    return handler(value, context, payload, "condition", options) == true
end

local function resolveArgs(spec, context, payload, Handlers, options)
    if type(spec.args) == "table" then
        return resolveValue(spec.args, context, payload, Handlers, options)
    end
    if type(spec.argsFromContext) == "string" then
        local value = Utils.getPath(context, spec.argsFromContext)
        if type(value) == "table" then
            return resolveValue(value, context, payload, Handlers, options)
        end
    end
    if type(spec.argsFromPayload) == "string" then
        local value = Utils.getPath(payload, spec.argsFromPayload)
        if type(value) == "table" then
            return resolveValue(value, context, payload, Handlers, options)
        end
    end
    return {}
end

local function callMethod(target, methodName, args)
    if target == nil then
        error("Could not resolve action target.")
    end
    if type(methodName) ~= "string" or methodName == "" then
        error("Action method must be a non-empty string.")
    end
    local method = target[methodName]
    if type(method) ~= "function" then
        error("Target does not have method '" .. methodName .. "'.")
    end
    return method(target, table.unpack(args))
end

function Actions.register(Handlers)
    ParserRegistry.registerPositionalArguments("consequence:pick", { "...options" })
    ParserRegistry.registerPositionalArguments("consequence:if", { "condition", "trueEffect", "falseEffect" })

    Handlers.registerEffectType("consequence:text", function(spec, context, payload, phase, options)
        local text = spec.text
        local textHandler = nil
        if type(options) == "table" and type(options.textHandler) == "function" then
            textHandler = options.textHandler
        elseif type(context) == "table" and type(context.textHandler) == "function" then
            textHandler = context.textHandler
        end

        if textHandler ~= nil then
            return textHandler(text, spec, context, payload, phase, options)
        end
        return text
    end)

    Handlers.registerEffectType("consequence:call_context", function(spec, context, payload, _, options)
        return callMethod(
            Utils.getPath(context, spec.path),
            spec.method,
            resolveArgs(spec, context, payload, Handlers, options)
        )
    end)

    Handlers.registerEffectType("consequence:call_payload", function(spec, context, payload, _, options)
        return callMethod(
            Utils.getPath(payload, spec.path),
            spec.method,
            resolveArgs(spec, context, payload, Handlers, options)
        )
    end)

    Handlers.registerEffectType("consequence:pick", function(spec)
        local options = spec.options or {}
        if #options == 0 then
            return nil
        end
        if #options == 1 then
            return options[1]
        end
        return options[math.random(#options)]
    end)

    Handlers.registerEffectType("consequence:if", function(spec, context, payload, _, options)
        if evaluateCondition(spec.condition, context, payload, Handlers, options) then
            return resolveValue(spec.trueEffect, context, payload, Handlers, options)
        end
        return resolveValue(spec.falseEffect, context, payload, Handlers, options)
    end)

    Handlers.registerEffectType("consequence:script", function(spec, context, payload)
        local fn = ModuleLoader.resolveEffectFunction(spec)
        return fn(spec, context, payload)
    end)
end

return Actions
