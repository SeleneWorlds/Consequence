local ModuleLoader = require("consequence.server.lua.lib.module_loader")
local Utils = require("consequence.server.lua.lib.utils")

local Actions = {}

local function resolveArgs(spec, context, payload)
    if type(spec.args) == "table" then
        return spec.args
    end
    if type(spec.argsFromContext) == "string" then
        local value = Utils.getPath(context, spec.argsFromContext)
        if type(value) == "table" then
            return value
        end
    end
    if type(spec.argsFromPayload) == "string" then
        local value = Utils.getPath(payload, spec.argsFromPayload)
        if type(value) == "table" then
            return value
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
    Handlers.registerActionType("consequence:call_context", function(spec, context, payload)
        return callMethod(
            Utils.getPath(context, spec.path),
            spec.method,
            resolveArgs(spec, context, payload)
        )
    end)

    Handlers.registerActionType("consequence:call_payload", function(spec, context, payload)
        return callMethod(
            Utils.getPath(payload, spec.path),
            spec.method,
            resolveArgs(spec, context, payload)
        )
    end)

    Handlers.registerActionType("consequence:script", function(spec, context, payload)
        local fn = ModuleLoader.resolveFunction(spec, "run")
        return fn(spec, context, payload)
    end)
end

return Actions
