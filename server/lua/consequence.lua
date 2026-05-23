local Bootstrap = require("consequence.server.lua.lib.bootstrap")
local Parser = require("consequence.server.lua.lib.parser")
local ParserRegistry = require("consequence.server.lua.lib.parser_registry")

Bootstrap.ensureInitialized()

local Runtime = require("consequence.server.lua.lib.runtime")

Runtime.registerPositionalArguments = ParserRegistry.registerPositionalArguments
Runtime.parseScript = Parser.parseScript
Runtime.clearParserRegistrations = function()
    ParserRegistry.clear()
    Bootstrap.Initialized = false
    Bootstrap.ensureInitialized()
end

return Runtime
