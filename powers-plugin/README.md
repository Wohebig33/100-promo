# Powers — Paper plugin for Minecraft 26.3

Server-side powers for your own Minecraft server: flight with adjustable
speed, a speed boost, noclip, a player tracker, ESP, aim assist and personal
waypoints, all controlled from an in-game menu. Players don't install anything. Every
power is granted by permission.

## Install

1. Run a **Paper 26.3** server on **Java 25**.
2. Drop `dist/Powers-1.1.0.jar` into the server's `plugins/` folder
   (remove any older `Powers-*.jar`).
3. Restart the server. `plugins/Powers/config.yml` is created on first start.

## Using it

Open the menu with **`/powers`**, or **sneak + press the swap-hands key**
(F by default; players can change it in Minecraft's Controls).

| Menu item | Click | Right-click | Shift + right-click |
|---|---|---|---|
| Fly (feather) | On / off | Faster | Slower |
| Speed boost (sugar) | On / off | Faster | Slower |
| Noclip (ender eye) | On / off | | |
| Tracker (compass) | On / off | | |
| ESP (spyglass) | On / off | | |
| Aim assist (bow) | On / off | Stronger | Weaker |
| Waypoints (lodestone) | Open the list | | |
| Turn everything off (barrier) | All powers off | | |

Powers that are on glow in the menu, and a green **boss bar** at the top of
the screen lists them, for example `Fly 4 · Speed x2.5 · Tracker`.

| Power | What it does |
|---|---|
| **Fly** | Survival/adventure flight. Fly speed 1–10, where 1 is normal creative speed (default 2). |
| **Speed boost** | Walk speed ×1.5 to ×5 in steps of 0.5 (default ×2). ×5 is Minecraft's maximum. |
| **Noclip** | Switches you to spectator mode so you can fly through blocks. Turning it off puts your previous game mode back. |
| **Tracker** | Your action bar shows the 3 nearest players in your world, with their distance and an arrow toward them, e.g. `Steve 34m ↗`. |
| **ESP** | Floating labels above other players with their name, health and distance, visible through walls. Only the ESP user sees them. |
| **Aim assist** | While you draw a bow, charge a crossbow or ready a trident, your view is pulled toward the nearest player in front of you. Strength 1–10 (default 3; 10 snaps straight on). |
| **Waypoints** | Personal saved locations. Click one to teleport there; shift + right-click deletes it. |

Fly speed, speed multiplier, aim strength and waypoints are saved on each player, so they
survive restarts. Powers themselves switch off when a player leaves, so
nobody is left stuck in spectator mode or at ×5 speed.

## Commands

| Command | Permission | |
|---|---|---|
| `/powers` | `powers.menu` | Open the menu |
| `/fly` | `powers.fly` | Turn flight on or off |
| `/flyspeed <1-10>` | `powers.fly` | Set fly speed |
| `/speed` · `/speed <1.5-5>` | `powers.speed` | Toggle the boost, or set its multiplier and turn it on |
| `/noclip` | `powers.noclip` | Turn noclip on or off |
| `/tracker` | `powers.tracker` | Turn the tracker on or off |
| `/esp` | `powers.esp` | Turn ESP on or off |
| `/aimassist` (`/aim`) · `/aimassist <1-10>` | `powers.aimassist` | Toggle aim assist, or set its strength and turn it on |
| `/waypoint` (`/wp`) | `powers.waypoints` | Open the waypoint list |
| `/waypoint set [name]` | | Save where you're standing (same name = move it) |
| `/waypoint go <name>` · `delete <name>` · `list` | | |

Waypoint names use letters, numbers, `-` and `_` (up to 24 characters).
Coordinates and player teleporting are already built into Minecraft:
`/tp <x> <y> <z>` (with `~` for relative values), `/tp <player>` and
`/kill`, using the vanilla `minecraft.command.tp` / `minecraft.command.kill`
permissions.

## Permissions

All permissions default to **operators only**. `powers.*` grants all of them.
To give powers to everyone, use a permissions plugin such as LuckPerms:

```
lp group default permission set powers.* true
```

Or grant single powers, e.g. `powers.fly` and `powers.menu`. Items for
powers a player doesn't have show as locked in the menu.

## Config (`plugins/Powers/config.yml`)

| Key | Default | |
|---|---|---|
| `menu-shortcut` | `true` | Sneak + swap-hands opens the menu |
| `tracker-range` | `2000` | How far the tracker looks for players, in blocks |
| `max-waypoints` | `45` | Most waypoints per player (the menu shows 45) |
| `esp.range` | `96` | How far away players get an ESP label, in blocks |
| `aim-assist.trigger` | `ranged` | When it aims: `ranged` (drawing a bow/crossbow/trident), `sneak` (while sneaking) or `always` |
| `aim-assist.range` | `48` | How far away targets can be, in blocks |
| `aim-assist.fov` | `30` | Only targets within this many degrees of where you're looking |
| `aim-assist.target-mobs` | `false` | Also aim at mobs, not just players |

## How ESP and aim assist work

Both run on your server, so players don't need any mods.

- **ESP** spawns a text label above each nearby player that only the ESP
  user can see. The labels show through walls and glide along with the
  player. They are never saved to the world. A label only reaches a player
  within the server's entity tracking range, so very distant players have no
  label. The tracker covers longer distances.
- **Aim assist** turns the player's view from the server 20 times a second,
  so it feels a little steppier than mouse movement. Lower strengths blend
  in more smoothly. It only targets players (and mobs, if enabled) that the
  player has a clear line of sight to.

## What didn't carry over from the Roblox version

- **Server list:** switching servers needs a proxy such as Velocity, so it
  isn't part of a single-server plugin.
- **Rebinding keys:** a server can't read keyboard keys. Players open the
  menu with the swap-hands key, which they can rebind in Minecraft's
  Controls. Everything else is done by clicking in the menu.
- **Zoomable map:** waypoints are a clickable list instead.

## Building from source

Requires JDK 25 and Maven:

```
mvn package
```

The jar is written to `target/Powers-1.1.0.jar`.
