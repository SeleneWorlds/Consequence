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
    return Consequence.parseScript(source, {
        fileName = "success.csqn",
        defaultNamespaces = { "consequence" }
    })
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
        [[greet: match("hello") -> reply("Hello")]],
        function(api)
            api.registerPositionalArguments("reply", { "text" })
        end
    )

    assertDeepEquals(result.interactions, {
        {
            trigger = "greet",
            conditions = {
                { type = "match", patterns = { "hello" } }
            },
            actions = {
                { type = "reply", text = "Hello" }
            }
        }
    }, "Simple interaction should lower to runtime-shaped tables.")
end

local function testParsesBuiltInMatchVarargs()
    local result = parseSuccess(
        [[greet: match("^hello", "world$") -> reply("Hello")]],
        function(api)
            api.registerPositionalArguments("reply", { "text" })
        end
    )

    assertDeepEquals(result.interactions, {
        {
            trigger = "greet",
            conditions = {
                { type = "match", patterns = { "^hello", "world$" } }
            },
            actions = {
                { type = "reply", text = "Hello" }
            }
        }
    }, "Simple interaction should lower to runtime-shaped tables.")
end

local function testParsesBuiltInPickVarargs()
    local result = parseSuccess(
        [[greet: reply(pick("Hello", "Hi"))]],
        function(api)
            api.registerPositionalArguments("reply", { "text" })
        end
    )

    assertDeepEquals(result.interactions, {
        {
            trigger = "greet",
            conditions = {},
            actions = {
                {
                    type = "reply",
                    text = {
                        type = "pick",
                        options = { "Hello", "Hi" }
                    }
                }
            }
        }
    }, "Built-in pick action should lower varargs into options.")
end

local function testParsesBuiltInIfTernary()
    local result = parseSuccess(
        [[greet: flag -> reply(if(check("ok"), "yes", pick("no", "maybe")))]],
        function(api)
            api.registerPositionalArguments("reply", { "text" })
            api.registerPositionalArguments("check", { "value" })
        end
    )

    assertDeepEquals(result.interactions[1], {
        trigger = "greet",
        conditions = {
            { type = "flag" }
        },
        actions = {
            {
                type = "reply",
                text = {
                    type = "if",
                    condition = {
                        type = "check",
                        value = "ok"
                    },
                    trueEffect = "yes",
                    falseEffect = {
                        type = "pick",
                        options = { "no", "maybe" }
                    }
                }
            }
        }
    }, "Built-in if action should lower three positional arguments into a ternary effect.")
end

local function testSupportsNamespacesDefaultsAndNestedCalls()
    local result = parseSuccess(
        [[foo:bar: localFlag, check(i18n("de", "en")) -> "Hi", baz:qux(showTrades("ore"))]],
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
            { type = "localFlag" },
            {
                type = "check",
                condition = {
                    type = "i18n",
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
                    type = "showTrades",
                    item = "ore"
                }
            }
        }
    }, "Nested calls and namespace defaults should lower correctly.")
end

local function testAcceptsBareAndQualifiedRegistrations()
    local result = parseSuccess(
        [[useNpc: german -> i18n("Hallo", "Hello")]],
        function(api)
            api.registerPositionalArguments("consequence:i18n", { "german", "english" })
        end
    )

    assertDeepEquals(result.interactions[1], {
        trigger = "useNpc",
        conditions = {
            { type = "german" }
        },
        actions = {
            {
                type = "i18n",
                german = "Hallo",
                english = "Hello"
            }
        }
    }, "Fully-qualified registrations should work for bare invocations.")
end

local function testSupportsMultilineAndTrailingCommas()
    local result = parseSuccess(
        [[
trigger:
  flag,
  match(
    "hello",
  ) -> reply(
  "hi",
), otherAction
        ]],
        function(api)
            api.registerPositionalArguments("reply", { "text" })
        end
    )

    assertDeepEquals(result.interactions[1], {
        trigger = "trigger",
        conditions = {
            { type = "flag" },
            { type = "match", patterns = { "hello" } }
        },
        actions = {
            { type = "reply", text = "hi" },
            { type = "otherAction" }
        }
    }, "Multiline calls and trailing commas should parse.")
end

local function testSupportsVarargPositionalArguments()
    local result = parseSuccess(
        [[greet: flag -> reply("hello", "there", otherAction)]],
        function(api)
            api.registerPositionalArguments("reply", { "text", "...extras" })
        end
    )

    assertDeepEquals(result.interactions[1], {
        trigger = "greet",
        conditions = {
            { type = "flag" }
        },
        actions = {
            {
                type = "reply",
                text = "hello",
                extras = {
                    "there",
                    { type = "otherAction" }
                }
            }
        }
    }, "Vararg positional arguments should collect remaining lowered values.")
end

local function testFailsOnMissingPositionalRegistration()
    local errorMessage = parseFailure([[greet: needs_registration("hello") -> wave]])
    assertTrue(errorMessage:find("broken.csqn:1:8:", 1, true) ~= nil, errorMessage)
    assertTrue(
        errorMessage:find("No positional argument registration for 'needs_registration'", 1, true) ~= nil,
        errorMessage
    )
end

local function testFailsOnTooManyPositionalArguments()
    local errorMessage = parseFailure(
        [[greet: reply("one", "two")]],
        function(api)
            api.registerPositionalArguments("reply", { "text" })
        end
    )
    assertTrue(errorMessage:find("broken.csqn:1:8:", 1, true) ~= nil, errorMessage)
    assertTrue(
        errorMessage:find("Too many positional arguments for 'reply'", 1, true) ~= nil,
        errorMessage
    )
end

local function testBuiltInMatchConditionEvaluation()
    assertTrue(
        Consequence.evaluateEffect({ type = "consequence:match", patterns = { "^hello", "world$" } }, nil, {
            message = "hello world"
        }),
        "Built-in match condition should succeed when any pattern matches."
    )

    assertTrue(
        not Consequence.evaluateEffect({ type = "consequence:match", patterns = { "^goodbye" } }, nil, {
            message = "hello world"
        }),
        "Built-in match condition should fail when no pattern matches."
    )

    assertTrue(
        not Consequence.evaluateEffect({ type = "consequence:match", patterns = {} }, nil, {
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

    local ok, result = Consequence.runEffect({ type = "consequence:pick", options = { "one", "two" } }, nil, nil)
    math.random = originalRandom

    assertTrue(ok, "Built-in pick action should execute successfully.")
    assertTrue(result == "two", "Built-in pick action should return the randomly selected option.")
end

local function testBuiltInIfActionEvaluation()
    local context
    context = {
        npc = {
            speak = function(_, message)
                context.captured = message
            end
        }
    }

    local ok = Consequence.runEffect({
        type = "consequence:call_context",
        path = "npc",
        method = "speak",
        args = {
            {
                type = "consequence:if",
                condition = {
                    type = "consequence:match",
                    patterns = { "^hello" }
                },
                trueEffect = "matched",
                falseEffect = "missed"
            }
        }
    }, context, {
        message = "hello world"
    })

    assertTrue(ok, "Built-in if action should execute successfully.")
    assertTrue(context.captured == "matched", "Built-in if action should resolve the true branch.")
end

local function testBuiltInIfConditionEvaluation()
    assertTrue(
        Consequence.evaluateEffect({
            type = "consequence:if",
            condition = {
                type = "consequence:match",
                patterns = { "^hello" }
            },
            trueEffect = true,
            falseEffect = false
        }, nil, {
            message = "hello world"
        }),
        "Built-in if effect should return the true branch when its condition passes."
    )

    assertTrue(
        not Consequence.evaluateEffect({
            type = "consequence:if",
            condition = {
                type = "consequence:match",
                patterns = { "^goodbye" }
            },
            trueEffect = true,
            falseEffect = false
        }, nil, {
            message = "hello world"
        }),
        "Built-in if effect should return the false branch when its condition fails."
    )
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

    local ok = Consequence.runEffect({
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

local function testBuiltInTextActionReturnsLiteralText()
    local ok, result = Consequence.runEffect({ type = "consequence:text", text = "Hello" }, nil, nil)

    assertTrue(ok, "Built-in text action should execute successfully.")
    assertTrue(result == "Hello", "Built-in text action should return the literal text by default.")
end

local function testBuiltInTextActionUsesContextTextHandler()
    local received = nil
    local ok, result = Consequence.runEffect({
        type = "consequence:text",
        text = "Hello"
    }, {
        textHandler = function(text)
            received = text
            return string.upper(text)
        end
    }, nil)

    assertTrue(ok, "Built-in text action should execute successfully with a text handler.")
    assertTrue(received == "Hello", "Built-in text action should pass the literal text to the context text handler.")
    assertTrue(result == "HELLO", "Built-in text action should return the text handler result when present.")
end

local function testBuiltInTextActionPrefersOptionsTextHandler()
    local contextReceived = nil
    local optionsReceived = nil
    local ok, result = Consequence.runEffect({
        type = "consequence:text",
        text = "Hello"
    }, {
        textHandler = function(text)
            contextReceived = text
            return "context:" .. text
        end
    }, nil, nil, {
        textHandler = function(text)
            optionsReceived = text
            return "options:" .. text
        end
    })

    assertTrue(ok, "Built-in text action should execute successfully with an options text handler.")
    assertTrue(contextReceived == nil, "Built-in text action should prefer the options text handler over the context handler.")
    assertTrue(optionsReceived == "Hello", "Built-in text action should pass the literal text to the options text handler.")
    assertTrue(result == "options:Hello", "Built-in text action should return the options text handler result when present.")
end

local function testFailsOnSyntaxDiagnostics()
    local missingConditionSeparator = parseFailure([[foo -> bar]])
    assertTrue(missingConditionSeparator:find("broken.csqn:1:5:", 1, true) ~= nil, missingConditionSeparator)
    assertTrue(
        missingConditionSeparator:find("Expected ':' after interaction trigger", 1, true) ~= nil,
        missingConditionSeparator
    )

    local unterminatedString = parseFailure([[greet: "hello]])
    assertTrue(unterminatedString:find("broken.csqn:1:8:", 1, true) ~= nil, unterminatedString)
    assertTrue(
        unterminatedString:find("Unterminated string literal", 1, true) ~= nil,
        unterminatedString
    )

    local unmatchedParen = parseFailure([[greet: match("hello" -> wave]])
    assertTrue(unmatchedParen:find("broken.csqn:1:22:", 1, true) ~= nil, unmatchedParen)
    assertTrue(
        unmatchedParen:find("Expected ')' to close call", 1, true) ~= nil,
        unmatchedParen
    )

    local emptyConditions = parseFailure([[greet: -> wave]])
    assertTrue(emptyConditions:find("broken.csqn:1:8:", 1, true) ~= nil, emptyConditions)
    assertTrue(
        emptyConditions:find("Expected expression", 1, true) ~= nil,
        emptyConditions
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
        [[greet: reply("hello")]],
        function(api)
            api.registerPositionalArguments("reply", { "text" })
        end
    )
    assertDeepEquals(withRegistration.interactions, {
        {
            trigger = "greet",
            conditions = {},
            actions = {
                { type = "reply", text = "hello" }
            }
        }
    })

    local errorMessage = parseFailure([[greet: reply("hello")]])
    assertTrue(
        errorMessage:find("No positional argument registration for 'reply'", 1, true) ~= nil,
        errorMessage
    )
end

local function testResolvesBareEffectsAgainstConfiguredDefaultNamespaces()
    Consequence.clearParserRegistrations()

    local captured = {}
    Consequence.registerEffectType("alpha:reply", function(spec)
        captured[#captured + 1] = "alpha:" .. tostring(spec.text)
        return true
    end)
    Consequence.registerEffectType("beta:reply", function(spec)
        captured[#captured + 1] = "beta:" .. tostring(spec.text)
        return true
    end)

    local ok = Consequence.runEffect({ type = "reply", text = "hello" }, nil, nil, "action", {
        defaultNamespaces = { "beta", "alpha" }
    })

    assertTrue(ok, "Bare effect should resolve using configured default namespaces.")
    assertDeepEquals(captured, { "beta:hello" }, "Runtime should choose the first registered namespace match.")
end

local function testPrefersExactBareRegistrationOverDefaultNamespaceFallback()
    Consequence.clearParserRegistrations()

    local captured = {}
    Consequence.registerEffectType("reply", function(spec)
        captured[#captured + 1] = "bare:" .. tostring(spec.text)
        return true
    end)
    Consequence.registerEffectType("beta:reply", function(spec)
        captured[#captured + 1] = "beta:" .. tostring(spec.text)
        return true
    end)

    local ok = Consequence.runEffect({ type = "reply", text = "hello" }, nil, nil, "action", {
        defaultNamespaces = { "beta" }
    })

    assertTrue(ok, "Exact bare effect should resolve successfully.")
    assertDeepEquals(captured, { "bare:hello" }, "Exact registrations should win before namespace fallback.")
end

local function testFireDefinitionsReturnsLastActionResultFirst()
    Consequence.clearParserRegistrations()

    Consequence.registerEffectType("capture", function(spec)
        return spec.value
    end)

    local result, summary = Consequence.fireDefinitions({
        {
            interactions = {
                {
                    trigger = "greet",
                    conditions = {},
                    actions = {
                        { type = "capture", value = "first" },
                        { type = "capture", value = "second" }
                    }
                }
            }
        }
    }, "greet")

    assertTrue(result == "second", "fireDefinitions should return the last action result of the first matching interaction.")
    assertTrue(summary.matchedDefinitions == 1, "fireDefinitions should still return the summary as a second value.")
    assertTrue(summary.effectCount == 2, "fireDefinitions summary should still report the executed action count.")
    assertTrue(summary.results[1].result == "second", "Interaction summary should retain the last action result.")
end

local function testFireDefinitionsReturnsNilWhenNothingMatches()
    local result, summary = Consequence.fireDefinitions({
        {
            interactions = {
                {
                    trigger = "greet",
                    conditions = {},
                    actions = {
                        { type = "consequence:text", text = "Hello" }
                    }
                }
            }
        }
    }, "farewell")

    assertTrue(result == nil, "fireDefinitions should return nil when no interaction matches.")
    assertTrue(summary.matchedDefinitions == 0, "Summary should report no matches when nothing matches.")
    assertTrue(summary.effectCount == 0, "Summary should report zero executed actions when nothing matches.")
end

local function testFireDefinitionsReturnsTextWithoutHandler()
    local result, summary = Consequence.fireDefinitions({
        {
            interactions = {
                {
                    trigger = "greet",
                    conditions = {},
                    actions = {
                        { type = "consequence:text", text = "Hello" }
                    }
                }
            }
        }
    }, "greet")

    assertTrue(result == "Hello", "fireDefinitions should surface the built-in text result when no text handler is configured.")
    assertTrue(summary.results[1].result == "Hello", "Summary should retain the matched interaction result.")
end

local M = {}

function M.run()
    testParsesSimpleInteraction()
    testParsesBuiltInMatchVarargs()
    testParsesBuiltInPickVarargs()
    testParsesBuiltInIfTernary()
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
    testBuiltInIfActionEvaluation()
    testBuiltInIfConditionEvaluation()
    testNestedPickActionResolvesInsideArgs()
    testBuiltInTextActionReturnsLiteralText()
    testBuiltInTextActionUsesContextTextHandler()
    testBuiltInTextActionPrefersOptionsTextHandler()
    testResolvesBareEffectsAgainstConfiguredDefaultNamespaces()
    testPrefersExactBareRegistrationOverDefaultNamespaceFallback()
    testFireDefinitionsReturnsLastActionResultFirst()
    testFireDefinitionsReturnsNilWhenNothingMatches()
    testFireDefinitionsReturnsTextWithoutHandler()
end

return M
