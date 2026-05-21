local Bootstrap = require("consequence.server.lua.lib.bootstrap")

Bootstrap.ensureInitialized()

return require("consequence.server.lua.lib.runtime")
