# chatty-npcs

`chatty-npcs` is a Selene Lua bundle that exposes a data-driven event engine for
simple NPC interactions.

This bundle does not spawn NPCs or intercept chat on its own. Consumer bundles
call `fireTrigger(...)` and provide a plain Lua context table plus optional
payload data.

## Public API

```lua
local ChattyNpcs = require("chatty-npcs.server.lua.chatty_npcs")

ChattyNpcs.registerConditionType("my_bundle:custom_condition", function(spec, context, payload)
    return true
end)

ChattyNpcs.registerActionType("my_bundle:custom_action", function(spec, context, payload)
    context.lastAction = spec.name
end)

local result = ChattyNpcs.fireTrigger("thirdparty:receive_text", {
    npc = npc,
    player = player
}, {
    message = "hello"
})
```

## Registry Data

Interaction definitions live under `server/data/chatty_npcs/interactions`.
Each JSON represents one NPC's full interaction set. Define distinct
event-to-action combinations in an `interactions` array. `trigger` is only the
event identifier fired through `fireTrigger(...)`; `conditions` decide whether
that interaction should handle the payload. Runtime stops after the first
successful interaction for a payload.

Example:

```json
{
  "interactions": [
    {
      "trigger": "thirdparty:receive_text",
      "conditions": [
        {
          "type": "chatty_npcs:payload_field_match",
          "path": "message",
          "equals": "hello"
        },
        {
          "type": "chatty_npcs:context_field_match",
          "path": "player.role",
          "equals": "traveler"
        }
      ],
      "actions": [
        {
          "type": "chatty_npcs:call_context",
          "path": "npc",
          "method": "speak",
          "args": ["Hello there."]
        }
      ]
    },
    {
      "trigger": "chatty_npcs:use_npc",
      "actions": [
        {
          "type": "chatty_npcs:call_context",
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

Conditions:
- `chatty_npcs:all`
- `chatty_npcs:any`
- `chatty_npcs:not`
- `chatty_npcs:context_field_match`
- `chatty_npcs:payload_field_match`
- `chatty_npcs:script`

Actions:
- `chatty_npcs:call_context`
- `chatty_npcs:call_payload`
- `chatty_npcs:script`
