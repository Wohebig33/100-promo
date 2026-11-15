# Cheat powers for a Roblox game

All abilities live in one menu. Each ability is its own ModuleScript in
`ReplicatedStorage > Abilities`, and the menu picks up whatever is in that
folder, including modules added while a play test is running.

## Studio layout

```
ReplicatedStorage
└── Abilities                 (Folder)
    ├── Flight                (ModuleScript)  ReplicatedStorage/Abilities/Flight.lua
    ├── ESP                   (ModuleScript)  ReplicatedStorage/Abilities/ESP.lua
    ├── AimAssist             (ModuleScript)  ReplicatedStorage/Abilities/AimAssist.lua
    ├── Noclip                (ModuleScript)  ReplicatedStorage/Abilities/Noclip.lua
    ├── SpeedBoost            (ModuleScript)  ReplicatedStorage/Abilities/SpeedBoost.lua
    ├── Map                   (ModuleScript)  ReplicatedStorage/Abilities/Map.lua
    └── ServerList            (ModuleScript)  ReplicatedStorage/Abilities/ServerList.lua
ServerScriptService
├── AbilityGrants             (Script)        ServerScriptService/AbilityGrants.server.lua
├── AbilitySettings           (Script)        ServerScriptService/AbilitySettings.server.lua
├── Commands                  (Script)        ServerScriptService/Commands.server.lua
├── Map                       (Script)        ServerScriptService/Map.server.lua
├── ServerList                (Script)        ServerScriptService/ServerList.server.lua
└── TeleportUtil              (ModuleScript)  ServerScriptService/TeleportUtil.lua
StarterPlayer
└── StarterPlayerScripts
    ├── AbilityMenu           (LocalScript)   StarterPlayerScripts/AbilityMenu.client.lua
    └── CommandFeedback       (LocalScript)   StarterPlayerScripts/CommandFeedback.client.lua
```

**Upgrading from the earlier version:** delete the old `Flight`, `ESP`,
`AimAssist`, `Noclip`, `SpeedBoost`, `AbilityHUD`, `Map` and `ServerList`
LocalScripts from StarterPlayerScripts. They now live in the Abilities
folder, and keeping both would run everything twice.

## Using it

- **HUD** (right edge of the screen): every ability you have, its key and
  whether it's on. Speed boost shows its multiplier. Click the HUD to open
  the menu.
- **Menu** (**Right Shift**, or click the HUD):
  - **ON / OFF** turns a toggle ability on or off. **Use** runs an action
    ability, like opening the map.
  - **Sliders** adjust an ability's settings and apply immediately:
    Flight's **Fly speed** (10 to 500 studs/s, default 60) and Speed
    boost's **Speed** (x1.5 to x10, default x3). Speed boost's Faster and
    Slower keys move its slider too.
  - **Rebinding:** click a key button and press any keyboard key, mouse
    button or controller button. Every key can be rebound, including extra
    ones such as Flight's up/down/boost, Aim assist's hold-to-aim and
    Speed's faster/slower.
  - **X** next to a key unbinds it.
  - **One key, one job:** giving a key to something takes it off whatever
    had it, and you get a notification.
  - **Left click:** while a key button says "Press a key...", clicking on
    the menu cancels. To bind Left click, click in the game world.
  - **Menu key, HUD on/off and Reset keys** are in the footer.
- Keybinds, slider values and the HUD setting are saved per player, by
  `AbilitySettings`.

| Default key | Ability | Extra keys |
|---|---|---|
| F | Flight | Fly up: Space · Fly down: L Ctrl · Boost: L Shift |
| G | ESP | |
| H | Aim assist | Hold to aim: Right click |
| N | Noclip | |
| B | Speed boost | Faster: ] · Slower: [ |
| M | Map (action) | |
| L | Server list (action) | |
| R Shift | Open the menu | |

Chat commands still work: `/kill`, `/tp`, `/map` and `/servers` (see below).

## Adding an ability

Drop a ModuleScript into `ReplicatedStorage > Abilities`. It shows up in
the menu and HUD straight away. A minimal toggle:

```lua
local Players = game:GetService("Players")

return {
	Name = "Super jump",
	Description = "Jump really high.",
	Type = "Toggle",
	Key = Enum.KeyCode.J,
	RequiredAttribute = "CanSuperJump", -- optional; leave out to allow everyone

	Enable = function(ctx)
		local humanoid = ctx.Player.Character and ctx.Player.Character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return false -- refuse to turn on
		end
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 150
	end,

	Disable = function(ctx)
		local humanoid = ctx.Player.Character and ctx.Player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.JumpPower = 50
		end
	end,
}
```

All fields:

| Field | |
|---|---|
| `Name`, `Description` | Shown in the menu and HUD |
| `Type` | `"Toggle"` (on/off) or `"Action"` (press to do something) |
| `Key` | Default key: an `Enum.KeyCode`, or `Enum.UserInputType.MouseButton1/2/3` |
| `RequiredAttribute` | Only players with this attribute set to `true` can use it |
| `Binds` | Extra rebindable keys: `{ { Id = "Up", Name = "Fly up", Default = Enum.KeyCode.Space } }` |
| `Settings` | Sliders: `{ { Id = "Speed", Name = "Fly speed", Min = 10, Max = 500, Step = 5, Default = 60, Suffix = " studs/s" } }`. Read with `ctx.GetSetting("Speed")` |
| `OnSettingChanged(ctx, id, value)` | Optional: a slider moved |
| `Init(ctx)` | Runs once when the module loads |
| `Enable(ctx)` / `Disable(ctx)` | Toggle turned on/off. Return `false` from Enable to refuse |
| `Activate(ctx)` | Action abilities: key pressed or Use clicked |
| `OnBind(ctx, id)` | An extra bind was pressed (toggles only get this while on) |
| `Destroy(ctx)` | The module was removed from the folder |

`ctx` gives you `ctx.Player`, `ctx.SetEnabled(bool)`, `ctx.IsEnabled()`,
`ctx.IsBindDown(id)` (for held keys), `ctx.GetBindName(id)`,
`ctx.GetSetting(id)`, `ctx.SetSetting(id, value)` (moves the slider too),
`ctx.SetStatus(text)` (replaces "ON" in the HUD) and `ctx.Notify(text)`.

If a module errors, its card shows the error and the other abilities keep
working. The Output window has the full message.

If the ability needs a permission, add its attribute to `AbilityGrants`.

## Chat commands

| Command | |
|---|---|
| `/kill` · `/kill <name>` · `/kill @a / @r / @p / @s` | Kill yourself, a player (partial names work), everyone, a random player, the nearest player or yourself |
| `/tp <x> <y> <z>` | Teleport to coordinates. `~` = your current value, `~5` = yours + 5 |
| `/tp <player>` | Teleport to a player |
| `/tp <who> <player>` · `/tp <who> <x> <y> <z>` | Teleport other players (admin) |
| `/map` · `/servers` | Open the map / server list |

## Map

- Full-screen top-down grid with no edges. Drag to move; scroll wheel,
  pinch or the **+ / -** buttons to zoom. **Me** recenters on you.
- Shows you, other players and your waypoints. Off-screen waypoints stick
  to the edge so you can still click them.
- **Add a waypoint:** right-click the map, press **Place** then click, or
  use **Save waypoint where I'm standing**.
- **Use a waypoint:** click it, then **Go here**. Rename or delete it from
  the same panel.
- **Coordinates:** type X / Y / Z in the top-left panel and press **Go**.
  Leave Y blank to land on the ground.
- Waypoints are personal (50 max), go through Roblox's text filter, and
  are saved between sessions.
- It draws a coordinate grid, not the terrain or buildings.

## Server list

Lists this game's running servers with player counts; **Join** teleports
you. Teleporting only works in a live game, not Studio. Private servers
aren't listed.

## Permissions

- `AbilityGrants` gives every player `CanFly`, `CanSeeESP`, `CanAimAssist`,
  `CanServerHop`, `CanTeleport`, `CanNoclip` and `CanSpeedBoost`. Change it
  to tie abilities to game passes, pickups, teams and so on. Abilities a
  player doesn't have are hidden from the HUD and locked in the menu.
- `/kill` and `/tp` on yourself work for anyone with the matching ability.
  Targeting other players needs admin: the game owner, a UserId in the
  `Admins` list in `Commands`, or a player with the `IsAdmin` attribute.
  Everyone counts as admin in Studio.

## Saving and Studio

The map waypoints, the server list and saved keybinds need a published
place. To test them in Studio, turn on Game Settings > Security >
**Enable Studio Access to API Services**. Without it everything still
works, but nothing is saved between sessions.
