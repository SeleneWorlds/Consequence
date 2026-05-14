local ModuleLoader = {}

function ModuleLoader.load(spec)
    local moduleName = spec.module or spec.script
    if type(moduleName) ~= "string" or moduleName == "" then
        error("Missing module or script field.")
    end

    local ok, loaded = pcall(require, moduleName)
    if not ok then
        error("Failed to load module '" .. moduleName .. "': " .. tostring(loaded))
    end

    return loaded, moduleName
end

function ModuleLoader.resolveFunction(spec, defaultFunctionName)
    local loaded, moduleName = ModuleLoader.load(spec)
    if type(loaded) == "function" then
        return loaded, moduleName
    end

    local functionName = spec["function"] or spec.functionName or defaultFunctionName
    if type(functionName) ~= "string" or functionName == "" then
        error("Missing function name for module '" .. moduleName .. "'.")
    end

    local fn = loaded[functionName]
    if type(fn) ~= "function" then
        error("Module '" .. moduleName .. "' does not export function '" .. functionName .. "'.")
    end

    return fn, moduleName
end

return ModuleLoader
