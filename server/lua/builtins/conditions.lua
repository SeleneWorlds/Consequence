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

    Handlers.registerConditionType("consequence:all", function(spec, context, payload)
        for _, nestedCondition in ipairs(spec.conditions or {}) do
            local handler = Handlers.getConditionType(nestedCondition.type)
            if not handler or not handler(nestedCondition, context, payload) then
                return false
            end
        end
        return true
    end)

    Handlers.registerConditionType("consequence:any", function(spec, context, payload)
        local sawCondition = false
        for _, nestedCondition in ipairs(spec.conditions or {}) do
            sawCondition = true
            local handler = Handlers.getConditionType(nestedCondition.type)
            if handler and handler(nestedCondition, context, payload) then
                return true
            end
        end
        return not sawCondition
    end)

    Handlers.registerConditionType("consequence:not", function(spec, context, payload)
        local nestedCondition = spec.condition
        if type(nestedCondition) ~= "table" then
            return true
        end
        local handler = Handlers.getConditionType(nestedCondition.type)
        return not (handler and handler(nestedCondition, context, payload))
    end)

    Handlers.registerConditionType("consequence:context_field_match", function(spec, context, payload)
        return matchField(spec, context or {}, context, payload, nil)
    end)

    Handlers.registerConditionType("consequence:payload_field_match", function(spec, context, payload)
        return matchField(spec, payload or {}, context, payload, "message")
    end)

    Handlers.registerConditionType("consequence:match", function(spec, _, payload)
        local actual = Utils.getPath(payload or {}, "message")
        if type(actual) ~= "string" then
            return false
        end

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

    Handlers.registerConditionType("consequence:script", function(spec, context, payload)
        local fn = ModuleLoader.resolveFunction(spec, "evaluate")
        return fn(spec, context, payload)
    end)
end

return Conditions
