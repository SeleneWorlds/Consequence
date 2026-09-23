local Bootstrap = require("consequence.server.lua.lib.bootstrap")
local Definitions = require("consequence.server.lua.lib.definitions")
local Handlers = require("consequence.server.lua.lib.handlers")
local Log = require("consequence.server.lua.lib.log")

local Runtime = {}

local DEFAULT_RUNTIME_OPTIONS = {
    defaultNamespaces = { "consequence" }
}

local RESERVED_RUNTIME_OPTION_KEYS = {
    defaultNamespaces = true
}

local function getField(entry, fieldName)
    if type(entry.getField) == "function" then
        return entry:getField(fieldName)
    end
    if type(entry) ~= "table" then
        return nil
    end
    return entry[fieldName]
end

local function getSpecType(spec, fallbackType)
    if type(spec) ~= "table" then
        return fallbackType
    end
    return spec.type or fallbackType
end

local function normalizeRuntimeOptions(options)
    if options == nil then
        options = {}
    elseif type(options) ~= "table" then
        error("Runtime options must be a table.", 0)
    end

    local normalized = {}
    local defaultNamespaces = options.defaultNamespaces
    if defaultNamespaces == nil then
        defaultNamespaces = DEFAULT_RUNTIME_OPTIONS.defaultNamespaces
    elseif type(defaultNamespaces) ~= "table" then
        error("Runtime option 'defaultNamespaces' must be an array.", 0)
    end

    normalized.defaultNamespaces = {}
    for index, namespace in ipairs(defaultNamespaces) do
        if type(namespace) ~= "string" or namespace == "" then
            error("Runtime default namespaces must contain non-empty strings.", 0)
        end
        normalized.defaultNamespaces[index] = namespace
    end

    for key, value in pairs(options) do
        if not RESERVED_RUNTIME_OPTION_KEYS[key] then
            normalized[key] = value
        end
    end

    return normalized
end

local function getTriggerId(spec)
    if type(spec) == "string" then
        return spec
    end
    if type(spec) ~= "table" then
        return "consequence:any"
    end
    return spec.id or spec.type or "consequence:any"
end

local function runProtected(label, fn, ...)
    local packed = table.pack(...)
    local ok, resultOrError = xpcall(function()
        return fn(table.unpack(packed, 1, packed.n))
    end, function(err)
        return err
    end)

    if not ok then
        Log.error(label, resultOrError)
        return false, resultOrError
    end

    return true, resultOrError
end

function Runtime.runEffect(spec, context, payload, phase, options)
    local runtimeOptions = normalizeRuntimeOptions(options)
    local effectType = getSpecType(spec)
    local handler, resolvedEffectType = Handlers.getEffectType(effectType, runtimeOptions.defaultNamespaces)
    if not handler then
        Log.warn("Unknown effect type '" .. tostring(effectType) .. "'.")
        return false
    end

    return runProtected(
        "Effect handler failed for type '" .. tostring(effectType) .. "'.",
        handler,
        spec,
        context,
        payload,
        phase,
        runtimeOptions,
        resolvedEffectType
    )
end

function Runtime.evaluateEffect(spec, context, payload, phase, options)
    local ok, result = Runtime.runEffect(spec, context, payload, phase or "condition", options)
    return ok and result == true
end

local function getConditionEffects(interaction)
    return getField(interaction, "conditions") or {}
end

local function getActionEffects(interaction)
    return getField(interaction, "actions") or {}
end

local function evaluateInteraction(definition, interaction, triggerId, payload, context, options)
    local triggerSpec = getField(interaction, "trigger")
    if getTriggerId(triggerSpec) ~= triggerId then
        return {
            definition = definition,
            interaction = interaction,
            matched = false,
            effectsRun = 0,
            actionResults = {}
        }
    end

    for _, effect in ipairs(getConditionEffects(interaction)) do
        if not Runtime.evaluateEffect(effect, context, payload, "condition", options) then
            return {
                definition = definition,
                interaction = interaction,
                matched = false,
                effectsRun = 0,
                actionResults = {}
            }
        end
    end

    local effectsRun = 0
    local lastResult = nil
    local actionResults = {}
    for _, effect in ipairs(getActionEffects(interaction)) do
        local ok, result = Runtime.runEffect(effect, context, payload, "action", options)
        if not ok then
            return {
                definition = definition,
                interaction = interaction,
                matched = true,
                aborted = true,
                effectsRun = effectsRun,
                actionResults = actionResults,
                result = lastResult
            }
        end
        effectsRun = effectsRun + 1
        if result ~= nil then
            actionResults[#actionResults + 1] = result
        end
        lastResult = result
    end

    return {
        definition = definition,
        interaction = interaction,
        matched = true,
        aborted = false,
        effectsRun = effectsRun,
        actionResults = actionResults,
        result = lastResult
    }
end

function Runtime.fireDefinitions(definitions, triggerId, context, payload, options)
    Bootstrap.ensureInitialized()
    local runtimeOptions = normalizeRuntimeOptions(options)

    local effectiveContext = context or {}
    local effectivePayload = payload or {}

    local summary = {
        trigger = triggerId,
        context = effectiveContext,
        payload = effectivePayload,
        definitionsChecked = 0,
        interactionsChecked = 0,
        matchedDefinitions = 0,
        effectCount = 0,
        results = {},
        defaultNamespaces = runtimeOptions.defaultNamespaces
    }

    for _, definition in ipairs(definitions or {}) do
        summary.definitionsChecked = summary.definitionsChecked + 1
        for interactionIndex, interaction in ipairs(getField(definition, "interactions") or {}) do
            summary.interactionsChecked = summary.interactionsChecked + 1
            local result = evaluateInteraction(
                definition,
                interaction,
                triggerId,
                effectivePayload,
                effectiveContext,
                runtimeOptions
            )
            table.insert(summary.results, result)
            if result.matched then
                summary.matchedDefinitions = summary.matchedDefinitions + 1
                summary.effectCount = summary.effectCount + (result.effectsRun or 0)
                return result.result, summary
            end
        end
    end

    return nil, summary
end

function Runtime.fireTrigger(triggerId, context, payload, options)
    return Runtime.fireDefinitions(Definitions.loadAll(), triggerId, context, payload, options)
end

function Runtime.registerTriggerType(id, handler)
    Bootstrap.ensureInitialized()
    Log.warn(
        "registerTriggerType('" .. tostring(id) .. "') is deprecated; use event ids in interactions and effect handlers for matching logic."
    )
    return nil, handler
end

function Runtime.registerEffectType(id, handler)
    Bootstrap.ensureInitialized()
    Handlers.registerEffectType(id, handler)
end

function Runtime.clearDefinitionCache()
    Definitions.clearCache()
end

return Runtime
