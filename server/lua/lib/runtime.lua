local Bootstrap = require("chatty-npcs.server.lua.lib.bootstrap")
local Definitions = require("chatty-npcs.server.lua.lib.definitions")
local Handlers = require("chatty-npcs.server.lua.lib.handlers")
local Log = require("chatty-npcs.server.lua.lib.log")

local Runtime = {}

local function getField(entry, fieldName)
    if type(entry) ~= "table" then
        return nil
    end
    if type(entry.getField) == "function" then
        return entry:getField(fieldName)
    end
    return entry[fieldName]
end

local function getSpecType(spec, fallbackType)
    if type(spec) ~= "table" then
        return fallbackType
    end
    return spec.type or fallbackType
end

local function getTriggerId(spec)
    if type(spec) == "string" then
        return spec
    end
    if type(spec) ~= "table" then
        return "chatty_npcs:any"
    end
    return spec.id or spec.type or "chatty_npcs:any"
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

function Runtime.evaluateCondition(spec, context, payload)
    local conditionType = getSpecType(spec)
    local handler = Handlers.getConditionType(conditionType)
    if not handler then
        Log.warn("Unknown condition type '" .. tostring(conditionType) .. "'.")
        return false
    end

    local ok, result = runProtected(
        "Condition handler failed for type '" .. tostring(conditionType) .. "'.",
        handler,
        spec,
        context,
        payload
    )
    return ok and result == true
end

function Runtime.runAction(spec, context, payload)
    local actionType = getSpecType(spec)
    local handler = Handlers.getActionType(actionType)
    if not handler then
        Log.warn("Unknown action type '" .. tostring(actionType) .. "'.")
        return false
    end

    return runProtected(
        "Action handler failed for type '" .. tostring(actionType) .. "'.",
        handler,
        spec,
        context,
        payload
    )
end

local function evaluateInteraction(definition, interaction, label, triggerId, payload, context)
    local triggerSpec = getField(interaction, "trigger")
    if getTriggerId(triggerSpec) ~= triggerId then
        return {
            definition = definition,
            interaction = interaction,
            matched = false,
            actionsRun = 0
        }
    end

    for _, condition in ipairs(getField(interaction, "conditions") or {}) do
        if not Runtime.evaluateCondition(condition, context, payload) then
            return {
                definition = definition,
                interaction = interaction,
                matched = false,
                actionsRun = 0
            }
        end
    end

    local actionsRun = 0
    for _, action in ipairs(getField(interaction, "actions") or {}) do
        local ok = Runtime.runAction(action, context, payload)
        if not ok then
            return {
                definition = definition,
                interaction = interaction,
                matched = true,
                aborted = true,
                actionsRun = actionsRun
            }
        end
        actionsRun = actionsRun + 1
    end

    return {
        definition = definition,
        interaction = interaction,
        matched = true,
        aborted = false,
        actionsRun = actionsRun
    }
end

function Runtime.fireDefinitions(definitions, triggerId, context, payload)
    Bootstrap.ensureInitialized()

    local effectiveContext = context or {}
    local effectivePayload = payload or {}

    local summary = {
        trigger = triggerId,
        context = effectiveContext,
        payload = effectivePayload,
        definitionsChecked = 0,
        interactionsChecked = 0,
        matchedDefinitions = 0,
        actionCount = 0,
        results = {}
    }

    for _, definition in ipairs(definitions or {}) do
        summary.definitionsChecked = summary.definitionsChecked + 1
        for interactionIndex, interaction in ipairs(getField(definition, "interactions") or {}) do
            summary.interactionsChecked = summary.interactionsChecked + 1
            local result = evaluateInteraction(
                definition,
                interaction,
                "definition #" .. tostring(summary.definitionsChecked) .. " / interaction #" .. tostring(interactionIndex),
                triggerId,
                effectivePayload,
                effectiveContext
            )
            table.insert(summary.results, result)
            if result.matched then
                summary.matchedDefinitions = summary.matchedDefinitions + 1
                summary.actionCount = summary.actionCount + (result.actionsRun or 0)
                return summary
            end
        end
    end

    return summary
end

function Runtime.fireTrigger(triggerId, context, payload)
    return Runtime.fireDefinitions(Definitions.loadAll(), triggerId, context, payload)
end

function Runtime.registerTriggerType(id, handler)
    Bootstrap.ensureInitialized()
    Log.warn(
        "registerTriggerType('" .. tostring(id) .. "') is deprecated; use event ids in interactions and condition handlers for matching logic."
    )
    return nil, handler
end

function Runtime.registerConditionType(id, handler)
    Bootstrap.ensureInitialized()
    Handlers.registerConditionType(id, handler)
end

function Runtime.registerActionType(id, handler)
    Bootstrap.ensureInitialized()
    Handlers.registerActionType(id, handler)
end

function Runtime.clearDefinitionCache()
    Definitions.clearCache()
end

return Runtime
