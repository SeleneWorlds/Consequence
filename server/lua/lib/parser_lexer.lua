local Lexer = {}
Lexer.__index = Lexer

local function formatError(fileName, line, column, message)
    return tostring(fileName or "(script)") .. ":" .. tostring(line) .. ":" .. tostring(column) .. ": " .. message
end

local function isIdentifierStart(char)
    return char ~= nil and char:match("^[A-Za-z_]$") ~= nil
end

local function isIdentifierPart(char)
    return char ~= nil and char:match("^[A-Za-z0-9_]$") ~= nil
end

local function isDigit(char)
    return char ~= nil and char:match("^%d$") ~= nil
end

function Lexer.new(source, fileName)
    return setmetatable({
        source = source,
        fileName = fileName or "(script)",
        index = 1,
        line = 1,
        column = 1
    }, Lexer)
end

function Lexer:fail(line, column, message)
    error(formatError(self.fileName, line, column, message), 0)
end

function Lexer:isAtEnd()
    return self.index > #self.source
end

function Lexer:peek(offset)
    offset = offset or 0
    return self.source:sub(self.index + offset, self.index + offset)
end

function Lexer:advance()
    local char = self:peek()
    self.index = self.index + 1
    if char == "\n" then
        self.line = self.line + 1
        self.column = 1
    else
        self.column = self.column + 1
    end
    return char
end

function Lexer:skipWhitespaceAndComments()
    local sawNewline = false

    while not self:isAtEnd() do
        local char = self:peek()
        if char == " " or char == "\t" or char == "\r" then
            self:advance()
        elseif char == "\n" then
            sawNewline = true
            self:advance()
        elseif char == "-" and self:peek(1) == "-" then
            self:advance()
            self:advance()
            while not self:isAtEnd() and self:peek() ~= "\n" do
                self:advance()
            end
        else
            break
        end
    end

    return sawNewline
end

function Lexer:readString(quote, tokenLine, tokenColumn)
    self:advance()
    local parts = {}

    while not self:isAtEnd() do
        local char = self:peek()
        if char == quote then
            self:advance()
            return table.concat(parts)
        end
        if char == "\n" or char == "\r" then
            self:fail(tokenLine, tokenColumn, "Unterminated string literal.")
        end
        if char == "\\" then
            self:advance()
            if self:isAtEnd() then
                self:fail(tokenLine, tokenColumn, "Unterminated string literal.")
            end
            local escaped = self:advance()
            if escaped == "n" then
                table.insert(parts, "\n")
            elseif escaped == "r" then
                table.insert(parts, "\r")
            elseif escaped == "t" then
                table.insert(parts, "\t")
            elseif escaped == "\\" then
                table.insert(parts, "\\")
            elseif escaped == "\"" then
                table.insert(parts, "\"")
            elseif escaped == "'" then
                table.insert(parts, "'")
            else
                self:fail(self.line, self.column - 1, "Unsupported escape sequence '\\" .. escaped .. "'.")
            end
        else
            table.insert(parts, self:advance())
        end
    end

    self:fail(tokenLine, tokenColumn, "Unterminated string literal.")
end

function Lexer:readNumber()
    local parts = {}
    while isDigit(self:peek()) do
        table.insert(parts, self:advance())
    end

    if self:peek() == "." and isDigit(self:peek(1)) then
        table.insert(parts, self:advance())
        while isDigit(self:peek()) do
            table.insert(parts, self:advance())
        end
    end

    return tonumber(table.concat(parts))
end

function Lexer:readIdentifier()
    local parts = {}
    while isIdentifierPart(self:peek()) do
        table.insert(parts, self:advance())
    end
    local value = table.concat(parts)
    if value == "true" then
        return "boolean", true
    end
    if value == "false" then
        return "boolean", false
    end
    return "identifier", value
end

function Lexer:nextToken()
    local leadingNewline = self:skipWhitespaceAndComments()
    local tokenLine = self.line
    local tokenColumn = self.column

    if self:isAtEnd() then
        return {
            kind = "eof",
            line = tokenLine,
            column = tokenColumn,
            leadingNewline = leadingNewline
        }
    end

    local char = self:peek()
    if isIdentifierStart(char) then
        local kind, value = self:readIdentifier()
        return {
            kind = kind,
            value = value,
            line = tokenLine,
            column = tokenColumn,
            leadingNewline = leadingNewline
        }
    end

    if isDigit(char) then
        return {
            kind = "number",
            value = self:readNumber(),
            line = tokenLine,
            column = tokenColumn,
            leadingNewline = leadingNewline
        }
    end

    if char == "\"" or char == "'" then
        return {
            kind = "string",
            value = self:readString(char, tokenLine, tokenColumn),
            line = tokenLine,
            column = tokenColumn,
            leadingNewline = leadingNewline
        }
    end

    if char == "-" and self:peek(1) == ">" then
        self:advance()
        self:advance()
        return {
            kind = "arrow",
            line = tokenLine,
            column = tokenColumn,
            leadingNewline = leadingNewline
        }
    end

    local singleCharKinds = {
        ["("] = "lparen",
        [")"] = "rparen",
        [","] = "comma",
        [":"] = "colon"
    }
    local kind = singleCharKinds[char]
    if kind ~= nil then
        self:advance()
        return {
            kind = kind,
            line = tokenLine,
            column = tokenColumn,
            leadingNewline = leadingNewline
        }
    end

    self:fail(tokenLine, tokenColumn, "Unexpected character '" .. char .. "'.")
end

function Lexer.tokenize(source, fileName)
    if type(source) ~= "string" then
        error("Source must be a string.", 0)
    end

    local lexer = Lexer.new(source, fileName)
    local tokens = {}
    while true do
        local token = lexer:nextToken()
        table.insert(tokens, token)
        if token.kind == "eof" then
            break
        end
    end
    return tokens
end

return Lexer
