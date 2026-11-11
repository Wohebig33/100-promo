# Sinborn for Roblox Studio

This is the Roblox version of Sinborn. Every bloodline is one of the seven deadly sins. Code builds the whole map: Limbo village, the training dummies, the seven sealed boss arenas, rocks and lava pools. The server runs all combat and saving, and the client handles input, the HUD and effects.

## Open it in Studio (easiest)

1. Download `Sinborn.rbxlx` from this folder.
2. Double-click it, or in Roblox Studio choose **File → Open from File…** and pick it.
3. Press **Play** (F5).

To keep progress between sessions, publish the place first (**File → Publish to Roblox**). Then turn on **Game Settings → Security → Enable Studio Access to API Services**. Until you do, the game runs normally but a toast says saving is off.

To share it, publish the place and set it to Public under **Game Settings → Permissions**.

## Or sync with Rojo

The folder is a standard [Rojo](https://rojo.space) project:

```bash
rojo serve
```

Then connect from the Rojo plugin in Studio. `python3 build_place.py` rebuilds `Sinborn.rbxlx` from `src/` after you edit the scripts.

## Or paste the scripts by hand

| Studio location | Type | Name | File |
|---|---|---|---|
| ReplicatedStorage | Folder | `Sinborn` | – |
| ReplicatedStorage › Sinborn | ModuleScript | `Config` | `src/shared/Config.lua` |
| ServerScriptService | Script | `SinbornServer` | `src/server/init.server.lua` |
| ServerScriptService › SinbornServer | ModuleScript | `Data` | `src/server/Data.lua` |
| ServerScriptService › SinbornServer | ModuleScript | `World` | `src/server/World.lua` |
| StarterPlayer › StarterPlayerScripts | LocalScript | `SinbornClient` | `src/client/init.client.lua` |
| StarterPlayerScripts › SinbornClient | ModuleScript | `UI` | `src/client/UI.lua` |
| StarterPlayerScripts › SinbornClient | ModuleScript | `FX` | `src/client/FX.lua` |

The names must match exactly, because the scripts look each other up by name.

## Controls

| Key | Action |
|---|---|
| WASD, Space | Move, jump |
| Left click (hold) or J | Melee combo; trains Strength |
| Q | Dash; trains Agility |
| Hold C | Charge Malice; trains Malice, faster at the Altar |
| Hold F | Block |
| 1 2 3 4 | Bloodline skills, aimed at the mouse |
| Z X | Affinity skills |
| G | Sin Awakening (level 12) |
| E | Use the Shrine, Board, Ferryman or Altar |
| K | Stats and skill tree |

On phones and tablets, tap the skill bar. On-screen Strike, Dash, Charge, Block and Stats buttons also appear, and skills aim where your character faces.

## How it plays

- **Spins:** your first bloodline and affinity are free rolls, and you start with 8 spins. The odds are Sloth 30%, Gluttony 25%, Greed 18%, Envy 12%, Lust 9%, Wrath 5% and Pride 1%. If you go 50 spins without a Legendary or better, the next spin gives you one. The two Reliquary slots store a bloodline before you gamble.
- **Training:** stats rise from what you do, and each level also gives 3 points.
- **Skill tree:** skills unlock at levels 1, 4, 9 and 15, affinity skills at 2 and 7, and Awakening at 12. Each skill also gains mastery (up to 5) as you use it.
- **Missions:** the Board of Penance posts D to S rank missions (slay, hunt, named elite, soul shards).
- **Bosses:** seven arenas, sealed until levels 5, 9, 13, 17, 21, 25 and 30. Several players can fight one boss together, and its HP scales with the number of players. Your first kill of each boss pays 3 spins. Leave the arena and walk back in for a rematch.
- **Death:** you lose 25% of your souls and your active mission, then respawn in Limbo.

## Tuning

Damage formulas, odds, skill numbers, boss levels and map size are all in `src/shared/Config.lua`.
