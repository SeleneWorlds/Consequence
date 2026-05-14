local Log = {}

local function formatPrefix(level)
    return "[chatty-npcs][" .. level .. "]"
end

function Log.info(message)
    print(formatPrefix("info"), tostring(message))
end

function Log.warn(message)
    print(formatPrefix("warn"), tostring(message))
end

function Log.error(message, err)
    print(formatPrefix("error"), tostring(message))
    if err ~= nil then
        print(formatPrefix("error"), tostring(err))
    end
    if debug and debug.traceback then
        print(debug.traceback())
    end
end

return Log
