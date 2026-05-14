local Handlers = require("chatty-npcs.server.lua.lib.handlers")
local ConditionBuiltins = require("chatty-npcs.server.lua.builtins.conditions")
local ActionBuiltins = require("chatty-npcs.server.lua.builtins.actions")

local Bootstrap = {
    Initialized = false
}

function Bootstrap.ensureInitialized()
    if Bootstrap.Initialized then
        return
    end

    ConditionBuiltins.register(Handlers)
    ActionBuiltins.register(Handlers)

    Bootstrap.Initialized = true
end

return Bootstrap
