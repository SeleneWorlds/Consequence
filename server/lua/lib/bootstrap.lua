local Handlers = require("consequence.server.lua.lib.handlers")
local ConditionBuiltins = require("consequence.server.lua.builtins.conditions")
local ActionBuiltins = require("consequence.server.lua.builtins.actions")

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
