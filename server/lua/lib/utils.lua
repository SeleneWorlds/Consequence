local Utils = {}

local function splitPath(path)
    local parts = {}
    for segment in string.gmatch(path, "[^.]+") do
        table.insert(parts, segment)
    end
    return parts
end

function Utils.hasValue(value)
    return value ~= nil
end

function Utils.getPath(root, path)
    if path == nil or path == "" then
        return root
    end
    if type(path) ~= "string" then
        return nil
    end
    local value = root
    for _, segment in ipairs(splitPath(path)) do
        if type(value) ~= "table" then
            return nil
        end
        value = value[segment]
        if value == nil then
            return nil
        end
    end
    return value
end

function Utils.setPath(root, path, value)
    if type(root) ~= "table" then
        error("setPath root must be a table.")
    end
    if type(path) ~= "string" or path == "" then
        error("setPath path must be a non-empty string.")
    end

    local parts = splitPath(path)
    local cursor = root
    for index = 1, #parts - 1 do
        local segment = parts[index]
        local nextValue = cursor[segment]
        if type(nextValue) ~= "table" then
            nextValue = {}
            cursor[segment] = nextValue
        end
        cursor = nextValue
    end

    cursor[parts[#parts]] = value
end

function Utils.shallowMerge(target, source)
    if type(target) ~= "table" then
        error("shallowMerge target must be a table.")
    end
    if type(source) ~= "table" then
        return target
    end
    for key, value in pairs(source) do
        target[key] = value
    end
    return target
end

function Utils.normalizeText(value, trim, lowercase)
    if type(value) ~= "string" then
        return value
    end
    if trim ~= false then
        value = value:match("^%s*(.-)%s*$")
    end
    if lowercase ~= false then
        value = string.lower(value)
    end
    return value
end

function Utils.resolveValue(spec, context, payload)
    if type(spec) ~= "table" then
        return nil
    end
    if spec.value ~= nil then
        return spec.value
    end
    if type(spec.valueFromContext) == "string" then
        return Utils.getPath(context, spec.valueFromContext)
    end
    if type(spec.valueFromPayload) == "string" then
        return Utils.getPath(payload, spec.valueFromPayload)
    end
    return nil
end

return Utils
