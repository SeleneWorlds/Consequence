package.preload["selene.registries"] = function()
    return {
        findAll = function(_)
            return {}
        end
    }
end

local function fail(message)
    error(message, 0)
end

local function assertTrue(value, message)
    if not value then
        fail(message or "Expected condition to be true.")
    end
end

local function isArray(value)
    if type(value) ~= "table" then
        return false
    end

    local count = 0
    for key, _ in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
            return false
        end
        count = count + 1
    end

    return count == #value
end

local function render(value, seen)
    if type(value) ~= "table" then
        if type(value) == "string" then
            return string.format("%q", value)
        end
        return tostring(value)
    end

    seen = seen or {}
    if seen[value] then
        return "<cycle>"
    end
    seen[value] = true

    local parts = {}
    if isArray(value) then
        for index = 1, #value do
            parts[#parts + 1] = render(value[index], seen)
        end
        seen[value] = nil
        return "[" .. table.concat(parts, ", ") .. "]"
    end

    for key, entry in pairs(value) do
        parts[#parts + 1] = tostring(key) .. "=" .. render(entry, seen)
    end
    table.sort(parts)
    seen[value] = nil
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function deepEqual(actual, expected)
    if actual == expected then
        return true
    end
    if type(actual) ~= type(expected) then
        return false
    end
    if type(actual) ~= "table" then
        return false
    end

    for key, value in pairs(expected) do
        if not deepEqual(actual[key], value) then
            return false
        end
    end
    for key, value in pairs(actual) do
        if not deepEqual(value, expected[key]) then
            return false
        end
    end
    return true
end

local function assertDeepEquals(actual, expected, message)
    if not deepEqual(actual, expected) then
        fail((message or "Values differ.") .. "\nexpected: " .. render(expected) .. "\nactual: " .. render(actual))
    end
end

local Consequence = require("consequence.server.lua.consequence")

local function parseSuccess(source, ...)
    Consequence.clearParserRegistrations()
    for _, setup in ipairs({ ... }) do
        setup(Consequence)
    end
    return Consequence.parseScript(source, { fileName = "success.csqn" })
end

local function parseFailure(source, ...)
    Consequence.clearParserRegistrations()
    for _, setup in ipairs({ ... }) do
        setup(Consequence)
    end

    local ok, err = pcall(function()
        return Consequence.parseScript(source, { fileName = "broken.csqn" })
    end)
    assertTrue(not ok, "Expected parse failure.")
    return tostring(err)
end

local function testParsesSimpleInteraction()
    local result = parseSuccess(
        [[greet(match("hello")) -> reply("Hello")]],
        function(api)
            api.registerPositionalArguments("match", { "text" })
            api.registerPositionalArguments("reply", { "text" })
        end
    )

    assertDeepEquals(result.interactions, {
        {
            trigger = "consequence:greet",
            conditions = {
                { type = "consequence:match", text = "hello" }
            },
            actions = {
                { type = "consequence:reply", text = "Hello" }
            }
        }
    }, "Simple interaction should lower to runtime-shaped tables.")
end

local function testSupportsNamespacesDefaultsAndNestedCalls()
    local result = parseSuccess(
        [[foo:bar(localFlag, check(i18n("de", "en"))) -> "Hi", baz:qux(showTrades("ore"))]],
        function(api)
            api.registerPositionalArguments("check", { "condition" })
            api.registerPositionalArguments("i18n", { "german", "english" })
            api.registerPositionalArguments("baz:qux", { "trade" })
            api.registerPositionalArguments("showTrades", { "item" })
        end
    )

    assertDeepEquals(result.interactions[1], {
        trigger = "foo:bar",
        conditions = {
            { type = "consequence:localFlag" },
            {
                type = "consequence:check",
                condition = {
                    type = "consequence:i18n",
                    german = "de",
                    english = "en"
                }
            }
        },
        actions = {
            { type = "consequence:text", text = "Hi" },
            {
                type = "baz:qux",
                trade = {
                    type = "consequence:showTrades",
                    item = "ore"
                }
            }
        }
    }, "Nested calls and namespace defaults should lower correctly.")
end

local function testAcceptsBareAndQualifiedRegistrations()
    local result = parseSuccess(
        [[useNpc(german) -> i18n("Hallo", "Hello")]],
        function(api)
            api.registerPositionalArguments("consequence:i18n", { "german", "english" })
        end
    )

    assertDeepEquals(result.interactions[1], {
        trigger = "consequence:useNpc",
        conditions = {
            { type = "consequence:german" }
        },
        actions = {
            {
                type = "consequence:i18n",
                german = "Hallo",
                english = "Hello"
            }
        }
    }, "Fully-qualified registrations should work for bare invocations.")
end

local function testSupportsMultilineAndTrailingCommas()
    local result = parseSuccess(
        [[
trigger(
  flag,
  match(
    "hello",
  ),
) -> reply(
  "hi",
), otherAction
        ]],
        function(api)
            api.registerPositionalArguments("match", { "text" })
            api.registerPositionalArguments("reply", { "text" })
        end
    )

    assertDeepEquals(result.interactions[1], {
        trigger = "consequence:trigger",
        conditions = {
            { type = "consequence:flag" },
            { type = "consequence:match", text = "hello" }
        },
        actions = {
            { type = "consequence:reply", text = "hi" },
            { type = "consequence:otherAction" }
        }
    }, "Multiline calls and trailing commas should parse.")
end

local function testFailsOnMissingPositionalRegistration()
    local errorMessage = parseFailure([[greet(match("hello")) -> wave]])
    assertTrue(errorMessage:find("broken.csqn:1:7:", 1, true) ~= nil, errorMessage)
    assertTrue(
        errorMessage:find("No positional argument registration for 'consequence:match'", 1, true) ~= nil,
        errorMessage
    )
end

local function testFailsOnTooManyPositionalArguments()
    local errorMessage = parseFailure(
        [[greet -> reply("one", "two")]],
        function(api)
            api.registerPositionalArguments("reply", { "text" })
        end
    )
    assertTrue(errorMessage:find("broken.csqn:1:10:", 1, true) ~= nil, errorMessage)
    assertTrue(
        errorMessage:find("Too many positional arguments for 'consequence:reply'", 1, true) ~= nil,
        errorMessage
    )
end

local function testFailsOnSyntaxDiagnostics()
    local malformedNamespace = parseFailure([[foo: -> bar]])
    assertTrue(malformedNamespace:find("broken.csqn:1:6:", 1, true) ~= nil, malformedNamespace)
    assertTrue(
        malformedNamespace:find("Expected symbol name after ':'", 1, true) ~= nil,
        malformedNamespace
    )

    local unterminatedString = parseFailure([[greet -> "hello]])
    assertTrue(unterminatedString:find("broken.csqn:1:10:", 1, true) ~= nil, unterminatedString)
    assertTrue(
        unterminatedString:find("Unterminated string literal", 1, true) ~= nil,
        unterminatedString
    )

    local unmatchedParen = parseFailure([[greet(match("hello") -> wave]])
    assertTrue(unmatchedParen:find("broken.csqn:1:22:", 1, true) ~= nil, unmatchedParen)
    assertTrue(
        unmatchedParen:find("Expected ')' to close call", 1, true) ~= nil,
        unmatchedParen
    )

    local missingArrow = parseFailure([[greet(match("hello"))]])
    assertTrue(missingArrow:find("broken.csqn:1:22:", 1, true) ~= nil, missingArrow)
    assertTrue(
        missingArrow:find("Expected '->' after interaction trigger", 1, true) ~= nil,
        missingArrow
    )
end

local function testClearParserRegistrationsResetsState()
    local withRegistration = parseSuccess(
        [[greet -> reply("hello")]],
        function(api)
            api.registerPositionalArguments("reply", { "text" })
        end
    )
    assertDeepEquals(withRegistration.interactions, {
        {
            trigger = "consequence:greet",
            conditions = {},
            actions = {
                { type = "consequence:reply", text = "hello" }
            }
        }
    })

    local errorMessage = parseFailure([[greet -> reply("hello")]])
    assertTrue(
        errorMessage:find("No positional argument registration for 'consequence:reply'", 1, true) ~= nil,
        errorMessage
    )
end

local M = {}

function M.run()
    testParsesSimpleInteraction()
    testSupportsNamespacesDefaultsAndNestedCalls()
    testAcceptsBareAndQualifiedRegistrations()
    testSupportsMultilineAndTrailingCommas()
    testFailsOnMissingPositionalRegistration()
    testFailsOnTooManyPositionalArguments()
    testFailsOnSyntaxDiagnostics()
    testClearParserRegistrationsResetsState()
end

return M
