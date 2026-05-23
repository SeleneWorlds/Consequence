# consequence

`consequence` is a Selene Lua bundle that exposes a data-driven event engine for
trigger-based interactions.

## Public API

```lua
local Consequence = require("consequence.server.lua.consequence")

Consequence.registerEffectType("my_bundle:custom_check", function(spec, context, payload)
    return true
end)

Consequence.registerEffectType("my_bundle:custom_reply", function(spec, context, payload)
    context.lastEffect = spec.name
end)

local result = Consequence.fireTrigger("thirdparty:receive_text", {
    npc = npc,
    player = player
}, {
    message = "hello"
})
```

## Registry Data

Interaction definitions live under `server/data/consequence/interactions`.
Each JSON represents one NPC's full interaction set. Define distinct
event-to-effect combinations in an `interactions` array. `trigger` is only the
event identifier fired through `fireTrigger(...)`; `conditions` are effects that decide whether
that interaction should handle the payload, and `actions` are effects that run after a match.
Runtime stops after the first
successful interaction for a payload.

Example:

```json
{
  "interactions": [
    {
      "trigger": "thirdparty:receive_text",
      "conditions": [
        {
          "type": "consequence:payload_field_match",
          "path": "message",
          "equals": "hello"
        },
        {
          "type": "consequence:context_field_match",
          "path": "player.role",
          "equals": "traveler"
        }
      ],
      "actions": [
        {
          "type": "consequence:call_context",
          "path": "npc",
          "method": "speak",
          "args": ["Hello there."]
        }
      ]
    },
    {
      "trigger": "consequence:use_npc",
      "actions": [
        {
          "type": "consequence:call_context",
          "path": "npc",
          "method": "speak",
          "args": ["Need something?"]
        }
      ]
    }
  ]
}
```

## Built-in Types

Effects commonly used in `conditions`:
- `consequence:all`
- `consequence:any`
- `consequence:match`
- `consequence:not`
- `consequence:context_field_match`
- `consequence:payload_field_match`
- `consequence:script`

`consequence:match` matches `payload.message` against one or more Lua patterns.
In consequence scripts, use it as `match("pattern1", "pattern2")`.

Effects commonly used in `actions`:
- `consequence:call_context`
- `consequence:call_payload`
- `consequence:pick`
- `consequence:script`

`consequence:pick` returns one of its arguments at random.
In consequence scripts, use it as `pick("option1", "option2")`.

`consequence:script` is phase-agnostic. It loads the named module and uses the
first available exported function in this order: `apply`, `evaluate`, `run`.
