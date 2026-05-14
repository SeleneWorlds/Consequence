local Registries = require("selene.registries")

local Definitions = {
    Cached = nil
}

function Definitions.clearCache()
    Definitions.Cached = nil
end

function Definitions.loadAll()
    if Definitions.Cached ~= nil then
        return Definitions.Cached
    end

    local allEntries = Registries.findAll("chatty_npcs:interactions") or {}
    local entries = {}
    for _, entry in pairs(allEntries) do
        table.insert(entries, entry)
    end

    Definitions.Cached = entries
    return Definitions.Cached
end

return Definitions
