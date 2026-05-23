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
            api.registerPositionalArguments("reply", { "text" })
        end
    )

    assertDeepEquals(result.interactions, {
        {
            trigger = "consequence:greet",
            conditions = {
                { type = "consequence:match", patterns = { "hello" } }
            },
            actions = {
                { type = "consequence:reply", text = "Hello" }
            }
        }
    }, "Simple interaction should lower to runtime-shaped tables.")
end

local function testParsesBuiltInMatchVarargs()
    local result = parseSuccess(
        [[greet(match("^hello", "world$")) -> reply("Hello")]],
        function(api)
            api.registerPositionalArguments("reply", { "text" })
        end
    )

    assertDeepEquals(result.interactions, {
        {
            trigger = "consequence:greet",
            conditions = {
                { type = "consequence:match", patterns = { "^hello", "world$" } }
            },
            actions = {
                { type = "consequence:reply", text = "Hello" }
            }
        }
    }, "Simple interaction should lower to runtime-shaped tables.")
end

local function testParsesBuiltInPickVarargs()
    local result = parseSuccess(
        [[greet -> reply(pick("Hello", "Hi"))]],
        function(api)
            api.registerPositionalArguments("reply", { "text" })
        end
    )

    assertDeepEquals(result.interactions, {
        {
            trigger = "consequence:greet",
            conditions = {},
            actions = {
                {
                    type = "consequence:reply",
                    text = {
                        type = "consequence:pick",
                        options = { "Hello", "Hi" }
                    }
                }
            }
        }
    }, "Built-in pick action should lower varargs into options.")
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
            api.registerPositionalArguments("reply", { "text" })
        end
    )

    assertDeepEquals(result.interactions[1], {
        trigger = "consequence:trigger",
        conditions = {
            { type = "consequence:flag" },
            { type = "consequence:match", patterns = { "hello" } }
        },
        actions = {
            { type = "consequence:reply", text = "hi" },
            { type = "consequence:otherAction" }
        }
    }, "Multiline calls and trailing commas should parse.")
end

local function testSupportsVarargPositionalArguments()
    local result = parseSuccess(
        [[greet(flag) -> reply("hello", "there", otherAction)]],
        function(api)
            api.registerPositionalArguments("reply", { "text", "...extras" })
        end
    )

    assertDeepEquals(result.interactions[1], {
        trigger = "consequence:greet",
        conditions = {
            { type = "consequence:flag" }
        },
        actions = {
            {
                type = "consequence:reply",
                text = "hello",
                extras = {
                    "there",
                    { type = "consequence:otherAction" }
                }
            }
        }
    }, "Vararg positional arguments should collect remaining lowered values.")
end

local function testFailsOnMissingPositionalRegistration()
    local errorMessage = parseFailure([[greet(needs_registration("hello")) -> wave]])
    assertTrue(errorMessage:find("broken.csqn:1:7:", 1, true) ~= nil, errorMessage)
    assertTrue(
        errorMessage:find("No positional argument registration for 'consequence:needs_registration'", 1, true) ~= nil,
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

local function testBuiltInMatchConditionEvaluation()
    assertTrue(
        Consequence.evaluateCondition({ type = "consequence:match", patterns = { "^hello", "world$" } }, nil, {
            message = "hello world"
        }),
        "Built-in match condition should succeed when any pattern matches."
    )

    assertTrue(
        not Consequence.evaluateCondition({ type = "consequence:match", patterns = { "^goodbye" } }, nil, {
            message = "hello world"
        }),
        "Built-in match condition should fail when no pattern matches."
    )

    assertTrue(
        not Consequence.evaluateCondition({ type = "consequence:match", patterns = {} }, nil, {
            message = "hello world"
        }),
        "Built-in match condition should fail when no patterns are provided."
    )
end

local function testBuiltInPickActionEvaluation()
    local originalRandom = math.random
    math.random = function(limit)
        assertTrue(limit == 2, "pick should request a random index within the option count.")
        return 2
    end

    local ok, result = Consequence.runAction({ type = "consequence:pick", options = { "one", "two" } }, nil, nil)
    math.random = originalRandom

    assertTrue(ok, "Built-in pick action should execute successfully.")
    assertTrue(result == "two", "Built-in pick action should return the randomly selected option.")
end

local function testNestedPickActionResolvesInsideArgs()
    local originalRandom = math.random
    math.random = function(limit)
        assertTrue(limit == 2, "Nested pick should request a random index within the option count.")
        return 2
    end

    local captured = nil
    local context = {
        npc = {
            speak = function(_, message)
                captured = message
            end
        }
    }

    local ok = Consequence.runAction({
        type = "consequence:call_context",
        path = "npc",
        method = "speak",
        args = {
            {
                type = "consequence:pick",
                options = { "Hello", "Hi" }
            }
        }
    }, context, nil)

    math.random = originalRandom

    assertTrue(ok, "Nested pick action should resolve successfully inside call arguments.")
    assertTrue(captured == "Hi", "Nested pick action should resolve to the selected argument value.")
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

local function testFailsOnNonTrailingVarargRegistration()
    local ok, err = pcall(function()
        Consequence.clearParserRegistrations()
        Consequence.registerPositionalArguments("reply", { "...texts", "suffix" })
    end)
    assertTrue(not ok, "Expected registration failure.")
    local errorMessage = tostring(err)
    assertTrue(
        errorMessage:find("Vararg positional argument name must be the last entry", 1, true) ~= nil,
        errorMessage
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
    testParsesBuiltInMatchVarargs()
    testParsesBuiltInPickVarargs()
    testSupportsNamespacesDefaultsAndNestedCalls()
    testAcceptsBareAndQualifiedRegistrations()
    testSupportsMultilineAndTrailingCommas()
    testSupportsVarargPositionalArguments()
    testFailsOnMissingPositionalRegistration()
    testFailsOnTooManyPositionalArguments()
    testFailsOnSyntaxDiagnostics()
    testFailsOnNonTrailingVarargRegistration()
    testClearParserRegistrationsResetsState()
    testBuiltInMatchConditionEvaluation()
    testBuiltInPickActionEvaluation()
    testNestedPickActionResolvesInsideArgs()
end

return M
