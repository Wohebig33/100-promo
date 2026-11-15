# Cheat powers for a Roblox game

Paste each file into Roblox Studio as described below.

| File | Insert as | Where |
|---|---|---|
| `ServerScriptService/AbilityGrants.server.lua` | Script | ServerScriptService |
| `ServerScriptService/Commands.server.lua` | Script | ServerScriptService |
| `ServerScriptService/ServerList.server.lua` | Script | ServerScriptService |
| `StarterPlayerScripts/Flight.client.lua` | LocalScript | StarterPlayer > StarterPlayerScripts |
| `StarterPlayerScripts/ESP.client.lua` | LocalScript | StarterPlayer > StarterPlayerScripts |
| `StarterPlayerScripts/AimAssist.client.lua` | LocalScript | StarterPlayer > StarterPlayerScripts |
| `StarterPlayerScripts/ServerList.client.lua` | LocalScript | StarterPlayer > StarterPlayerScripts |
| `StarterPlayerScripts/CommandFeedback.client.lua` | LocalScript | StarterPlayer > StarterPlayerScripts |

## Controls

| Key / command | What it does |
|---|---|
| **F** | Toggle flight (WASD, Space up, Left Ctrl down, Shift boost) |
| **G** | Toggle ESP (highlights + name / health / distance) |
| **H** | Toggle aim assist (hold right-click to pull toward a target) |
| **L** or `/servers` | Open the server list and teleport to another server |
| `/kill` | Kill yourself |
| `/kill <name>` | Kill a player (partial username or display name works) |
| `/kill @a` · `@r` · `@p` · `@s` | Everyone · random player · nearest other player · yourself |

## Permissions

- `AbilityGrants` gives every player the `CanFly`, `CanSeeESP`,
  `CanAimAssist` and `CanServerHop` attributes. Change it to tie powers
  to game passes, pickups, teams, etc.
- `/kill` on yourself works for everyone. Killing other players needs
  admin: the game owner, a UserId in `Commands`' `Admins` list, or a
  player with the `IsAdmin` attribute. Everyone counts as admin in Studio.
  Set `AnyoneCanKillOthers = true` to let anyone do it.

## Server list requirements

- The place must be published.
- To see the list while testing in Studio, turn on
  Game Settings > Security > **Enable Studio Access to API Services**.
- Teleporting only works in a live game. In Studio the Join button
  replies with a message instead.
- Private and reserved servers are not listed.
