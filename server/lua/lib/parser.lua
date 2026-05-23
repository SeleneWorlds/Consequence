local Lexer = require("consequence.server.lua.lib.parser_lexer")
local Registry = require("consequence.server.lua.lib.parser_registry")

local Parser = {}
Parser.__index = Parser

local function formatValue(value)
    if type(value) == "string" then
        return "'" .. value .. "'"
    end
    return tostring(value)
end

function Parser.new(tokens, fileName)
    return setmetatable({
        tokens = tokens,
        index = 1,
        fileName = fileName or "(script)"
    }, Parser)
end

function Parser:current()
    return self.tokens[self.index]
end

function Parser:advance()
    local token = self:current()
    self.index = self.index + 1
    return token
end

function Parser:failAt(token, message)
    error(self.fileName .. ":" .. tostring(token.line) .. ":" .. tostring(token.column) .. ": " .. message, 0)
end

function Parser:match(kind)
    if self:current().kind == kind then
        return self:advance()
    end
    return nil
end

function Parser:expect(kind, message)
    local token = self:current()
    if token.kind ~= kind then
        self:failAt(token, message)
    end
    return self:advance()
end

function Parser:parseSymbol()
    local first = self:expect("identifier", "Expected symbol name.")
    local namespace = nil
    local name = first.value

    if self:match("colon") then
        namespace = name
        local second = self:match("identifier")
        if second == nil then
            self:failAt(self:current(), "Expected symbol name after ':'.")
        end
        name = second.value
    end

    return {
        kind = "symbol",
        namespace = namespace,
        name = name,
        token = first
    }
end

function Parser:parseExpression()
    local token = self:current()
    if token.kind == "identifier" then
        local symbol = self:parseSymbol()
        if self:match("lparen") then
            return self:finishCall(symbol)
        end
        return symbol
    end

    if token.kind == "string" or token.kind == "number" or token.kind == "boolean" then
        self:advance()
        return {
            kind = "literal",
            value = token.value,
            token = token
        }
    end

    self:failAt(token, "Expected expression.")
end

function Parser:finishCall(symbol)
    local args = {}
    if self:match("rparen") then
        return {
            kind = "call",
            callee = symbol,
            args = args,
            token = symbol.token
        }
    end

    while true do
        table.insert(args, self:parseExpression())
        if not self:match("comma") then
            break
        end
        if self:match("rparen") then
            return {
                kind = "call",
                callee = symbol,
                args = args,
                token = symbol.token
            }
        end
    end

    self:expect("rparen", "Expected ')' to close call.")
    return {
        kind = "call",
        callee = symbol,
        args = args,
        token = symbol.token
    }
end

function Parser:lowerValue(node)
    if node.kind == "literal" then
        return node.value
    end
    if node.kind == "symbol" then
        return {
            type = Registry.normalizeSymbolParts(node.namespace, node.name)
        }
    end
    if node.kind == "call" then
        return self:lowerCall(node)
    end

    self:failAt(node.token, "Unsupported expression.")
end

function Parser:lowerCall(node)
    local symbolId = Registry.normalizeSymbolParts(node.callee.namespace, node.callee.name)
    local args = node.args or {}
    local positionalNames = Registry.getPositionalArguments(symbolId)
    local positionalCount = positionalNames ~= nil and #positionalNames or 0
    local varargEntry = positionalCount > 0 and positionalNames[positionalCount] or nil
    local hasVararg = varargEntry ~= nil and varargEntry.vararg == true
    local fixedArgumentCount = hasVararg and (positionalCount - 1) or positionalCount

    if #args > 0 and positionalNames == nil then
        self:failAt(node.callee.token, "No positional argument registration for " .. formatValue(symbolId) .. ".")
    end

    if positionalNames ~= nil and not hasVararg and #args > positionalCount then
        self:failAt(
            node.callee.token,
            "Too many positional arguments for " .. formatValue(symbolId) .. ": expected at most "
                .. tostring(positionalCount) .. ", got " .. tostring(#args) .. "."
        )
    end

    local spec = {
        type = symbolId
    }
    for index = 1, math.min(#args, fixedArgumentCount) do
        local fieldName = positionalNames[index].name
        spec[fieldName] = self:lowerValue(args[index])
    end

    if hasVararg then
        local values = {}
        for index = fixedArgumentCount + 1, #args do
            values[#values + 1] = self:lowerValue(args[index])
        end
        spec[varargEntry.name] = values
    else
        for index = fixedArgumentCount + 1, #args do
            if positionalNames[index] == nil then
                self:failAt(node.callee.token, "Missing positional argument mapping for " .. formatValue(symbolId) .. ".")
            end
            spec[positionalNames[index].name] = self:lowerValue(args[index])
        end
    end

    return spec
end

function Parser:lowerCondition(node)
    if node.kind == "symbol" then
        return {
            type = Registry.normalizeSymbolParts(node.namespace, node.name)
        }
    end
    if node.kind == "call" then
        return self:lowerCall(node)
    end

    self:failAt(node.token, "Conditions must be symbols or calls.")
end

function Parser:lowerAction(node)
    if node.kind == "literal" then
        if type(node.value) ~= "string" then
            self:failAt(node.token, "Top-level action literals must be strings.")
        end
        return {
            type = "consequence:text",
            text = node.value
        }
    end
    if node.kind == "symbol" then
        return {
            type = Registry.normalizeSymbolParts(node.namespace, node.name)
        }
    end
    if node.kind == "call" then
        return self:lowerCall(node)
    end

    self:failAt(node.token, "Actions must be literals, symbols, or calls.")
end

function Parser:parseInteraction()
    local lhs = self:parseExpression()
    if not self:match("arrow") then
        self:failAt(self:current(), "Expected '->' after interaction trigger.")
    end

    local actions = {}
    table.insert(actions, self:lowerAction(self:parseExpression()))
    while self:match("comma") do
        table.insert(actions, self:lowerAction(self:parseExpression()))
    end

    local interaction = {
        conditions = {},
        actions = actions
    }

    if lhs.kind == "symbol" then
        interaction.trigger = Registry.normalizeSymbolParts(lhs.namespace, lhs.name)
        return interaction
    end

    if lhs.kind == "call" then
        interaction.trigger = Registry.normalizeSymbolParts(lhs.callee.namespace, lhs.callee.name)
        for _, condition in ipairs(lhs.args) do
            table.insert(interaction.conditions, self:lowerCondition(condition))
        end
        return interaction
    end

    self:failAt(lhs.token, "Interaction trigger must be a symbol or call.")
end

function Parser:parseFile()
    local interactions = {}
    while self:current().kind ~= "eof" do
        table.insert(interactions, self:parseInteraction())
        local nextToken = self:current()
        if nextToken.kind ~= "eof" and not nextToken.leadingNewline then
            self:failAt(nextToken, "Expected a newline between interactions.")
        end
    end

    return {
        interactions = interactions
    }
end

function Parser.parseScript(source, options)
    if options ~= nil and type(options) ~= "table" then
        error("parseScript options must be a table.", 0)
    end

    local fileName = "(script)"
    if options ~= nil and options.fileName ~= nil then
        fileName = tostring(options.fileName)
    end

    local tokens = Lexer.tokenize(source, fileName)
    local parser = Parser.new(tokens, fileName)
    return parser:parseFile()
end

return Parser
