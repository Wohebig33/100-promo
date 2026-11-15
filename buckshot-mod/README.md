# Buckshot Cheat (drop-in mod)

An in-game cheat menu for Buckshot Roulette single player on Steam. Copy the `BuckshotCheat` folder into the game folder, run `INSTALL.bat` once, and press **F1** in game. Install steps and what each button does are in [`BuckshotCheat/README.txt`](BuckshotCheat/README.txt).

## How it hooks in
Godot reads an `override.cfg` file from the folder that holds the game's .exe. `INSTALL.bat` writes one there that registers `cheat.gd` as an autoload, using the script's absolute path. The game's .exe and .pck files aren't changed.

At runtime, the script finds the round manager by its properties (`health_player`, `health_opponent`, `shellSpawner`) rather than by a node path. It then reads and writes:

| Feature | Game state |
|---|---|
| Shell order and count | `shellSpawner.sequenceArray` (`"live"` / `"blank"`, index 0 is the chamber) |
| Health | `health_player`, `health_opponent`, then `healthCounter.UpdateDisplay()` |
| Briefcase item | `itemManager.amounts.array_amounts[*].amount_active` (re-applied every frame, restored when turned off) |
| Items per grab | `roundArray[currentRound].numberOfItemsToGrab` |

The names come from a community reconstruction of the game's scripts and from a Steam-targeted mod menu that uses the same names. I haven't checked them against the current Steam build. If an update renames them, the menu shows "Waiting for a single-player game..." and none of the cheats do anything.

The mod switches off when the current scene looks like multiplayer.
