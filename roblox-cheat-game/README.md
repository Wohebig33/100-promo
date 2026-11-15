# Cheat powers for a Roblox game

Paste each file into Roblox Studio as described below.

| File | Insert as | Where |
|---|---|---|
| `ServerScriptService/AbilityGrants.server.lua` | Script | ServerScriptService |
| `ServerScriptService/Commands.server.lua` | Script | ServerScriptService |
| `ServerScriptService/ServerList.server.lua` | Script | ServerScriptService |
| `ServerScriptService/Map.server.lua` | Script | ServerScriptService |
| `ServerScriptService/TeleportUtil.lua` | **ModuleScript** named `TeleportUtil` | ServerScriptService |
| `StarterPlayerScripts/Map.client.lua` | LocalScript | StarterPlayer > StarterPlayerScripts |
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
| **M** or `/map` | Open the map (see below) |
| `/tp <x> <y> <z>` | Teleport to coordinates. `~` means your current value, `~5` means yours + 5 |
| `/tp <player>` | Teleport to a player |
| `/tp <who> <player>` · `/tp <who> <x> <y> <z>` | Teleport other players (admin) |
| `/kill` | Kill yourself |
| `/kill <name>` | Kill a player (partial username or display name works) |
| `/kill @a` · `@r` · `@p` · `@s` | Everyone · random player · nearest other player · yourself |

## Map

- Full-screen top-down grid with no edges. Drag to move; scroll wheel,
  pinch or the **+ / -** buttons to zoom (from 20 px per stud out to
  500 studs per pixel). **Me** recenters on you.
- Shows you (with the direction you're facing), other players and your
  waypoints. Waypoints that are off-screen stick to the edge so you can
  still click them.
- **Add a waypoint:** right-click the map, or press **Place** and then
  click/tap. Or use **Save waypoint where I'm standing**.
- **Use a waypoint:** click it, then **Go here**. You can rename or
  delete it from the same panel.
- **Coordinates:** type X, Y, Z in the top-left panel and press **Go**.
  Leave Y blank to land on the ground.
- Waypoints placed on the map have no height, so you land on the
  highest surface there. If nothing is there, it asks for a Y instead
  of dropping you into the void.
- Waypoints are personal (50 max), and names go through Roblox's text
  filter. They're saved between sessions with DataStores. That needs a
  published place, and **Enable Studio Access to API Services** turned
  on to save while testing in Studio.
- The map draws a coordinate grid, not the terrain or buildings.

## Permissions

- `AbilityGrants` gives every player the `CanFly`, `CanSeeESP`,
  `CanAimAssist`, `CanServerHop` and `CanTeleport` attributes. Change it to tie powers
  to game passes, pickups, teams, etc.
- `/kill` on yourself works for everyone. Killing other players needs
  admin: the game owner, a UserId in `Commands`' `Admins` list, or a
  player with the `IsAdmin` attribute. Everyone counts as admin in Studio.
  Set `AnyoneCanKillOthers = true` to let anyone do it.
- `/tp` works the same way: moving yourself only needs `CanTeleport`.
  Moving other players needs admin unless `AnyoneCanTeleportOthers = true`.

## Server list requirements

- The place must be published.
- To see the list while testing in Studio, turn on
  Game Settings > Security > **Enable Studio Access to API Services**.
- Teleporting only works in a live game. In Studio the Join button
  replies with a message instead.
- Private and reserved servers are not listed.
