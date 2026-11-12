# House Edge

A mod panel (a "trainer") for single-player games, made for **We're All In**. It runs outside the game in its own window, joins the game while it's running, and lets you change what the game keeps in memory: chips, money, health, timers.

> **Single-player and local play only.** Don't use it online against other people or in games with anti-cheat. It spoils the game for others and can get your Steam account banned.

## Two ways to use it

| | **In-game menu** (`ingame/`) | **Desktop panel** (`HouseEdge.exe`) |
|---|---|---|
| Where the menu shows | Inside the game, over the action | Its own window next to the game |
| Install | Unzip into the game folder | Run the .exe |
| Finds values by | Name, read from the game's code: "chips", "health" | Memory scanning: type the number you see |
| Extras | Game speed, gravity, field of view, Party Mode | Hotkeys, Cheat Engine tables, Party Mode |
| Games | Unity games built with Mono, like We're All In | Any single-player game |

## In-game menu (We're All In)

We're All In is a Unity game built with Mono: it ships `UnityPlayer.dll` and a `MonoBleedingEdge` folder. So the menu can live inside the game through [BepInEx](https://github.com/BepInEx/BepInEx), the standard Unity mod loader.

1. Open this repo's **Actions** tab, then **House Edge (Windows build)**. Pick the latest green run and download **HouseEdge-InGame-drop-into-game-folder**.
2. In Steam, right-click the game and choose **Manage → Browse local files**.
3. Unzip everything into that folder, next to `WereAllIn.exe`: `winhttp.dll`, `doorstop_config.ini` and the `BepInEx` folder.
4. Play from Steam and hold **Q+E**.

The full steps are in [`ingame/INSTALL.txt`](ingame/INSTALL.txt), which also comes inside the zip. To uninstall, delete those three items.

What's in the menu:
- **Fun:** game speed from 0.1x to 5x, gravity (float, moon, heavy, upside down), field of view, an FPS counter, and pause while the menu is open.
- **Find values:** search the game's own code by name, or tap a quick word (chips, money, health, lives…). Set a result, double it, or add to it, then **Pin** the one that works.
- **Pinned:** lock a value. **All** applies it to every copy, so you can freeze every enemy. Pins reconnect by themselves after a scene change or a restart.
- **Party Mode:** every 20 seconds there's a random surprise, like turbo, slow-mo, moon gravity, fish-eye, or a jackpot on a pinned value.

Building it yourself: `ingame/` is a .NET project (`net46`) that compiles against BepInEx 5 and Unity's reference assemblies. CI builds it against the real BepInEx and packages the folder. To build without a BepInEx download, compile the stand-in first: `dotnet build ingame/stubs/BepInEx.Stub.csproj`, then `dotnet build ingame/HouseEdgeInGame.csproj`.

## Get the desktop panel

**Download (Windows):** open this repo's **Actions** tab, then **House Edge (Windows build)**. Pick the latest green run and download **HouseEdge-windows**. Unzip it and run `HouseEdge.exe`.

Windows SmartScreen or your antivirus may warn you, because trainers read other programs' memory. That's expected for this kind of tool. The source is all in this folder.

**Or run it from source:**

```bash
pip install -r requirements.txt
```

```bash
python run.py
```

Add `--browser` to open the panel in your browser instead of its own window.

## Start it with the game from Steam (easiest)

1. Open House Edge once, go to **Settings**, and press **Copy** next to **Start with the game from Steam**. The line looks like this:
   ```
   "C:\Users\you\Downloads\HouseEdge.exe" %command%
   ```
2. In your Steam **Library**, right-click the game and choose **Properties**. Under **General**, paste the line into **Launch Options**.
3. Press **Play** in Steam as usual.

House Edge then opens with the game and joins it right away, and it closes when you quit the game. Steam still counts it as playing the game. If you move `HouseEdge.exe` somewhere else later, copy the line again.

**Bring the panel up in the game:** hold **Q and E together** to show or hide it. The game still gets Q and E too, so if those keys do something in the game, pick a different combo in Settings. Set the game to **windowed** or **borderless fullscreen** in its video settings. In exclusive fullscreen, Windows won't draw another window on top of the game, but mod hotkeys still work there.

To undo it, clear the Launch Options box in Steam.

## Use it

1. **Start the game** from Steam, then start House Edge. Or set it up to start with the game, as above.
2. **Pick the game** from the list. House Edge remembers it and joins on its own every time the game starts.
3. **Make a mod with the Value finder:**
   - Find a number on screen, say **500 chips**. Type `500` and press **First scan**.
   - Change it in the game: win, lose or spend some.
   - Type the new number and press **Next scan**. Repeat until one or two results are left.
   - Press **+ Mod**, name it, and give it a hotkey if you like.
4. **Play with it:**
   - **Lock:** freezes the value. Infinite chips.
   - **Quick buttons:** `+100` adds, `x2` doubles, `9999` sets.
   - **Set to…:** type any value.
   - **Hotkeys** (F1 to F12, Num0 to Num9, Ctrl/Shift/Alt plus a key, or two keys together like Q+E) toggle the lock from inside the game.
   - **Party Mode:** every 20 seconds it presses a random quick button on a random mod. Good chaos for local co-op.
   - **Compact overlay** (the ⇲ button) shrinks the panel to just the mods. With "Keep the panel on top" it sits over the game in windowed or borderless mode.

For a value you can't see as a number, like a health bar, use **Unknown starting value** with type **Decimal (float)**. Then use **Went down** after taking damage, **Went up** after healing, and **Stayed the same** when nothing happened.

### Mods that survive a restart
Values found by scanning usually live in memory that moves every time the game starts. Those mods are marked **Not found** after a restart until you find them again, which takes about a minute. For mods that keep working:
- **Import a Cheat Engine table (.CT).** House Edge brings in the address entries, including pointer chains and hotkeys. Script entries (Auto Assembler) need Cheat Engine itself and are skipped.
- **Add by address:** enter a module, an offset and pointer offsets by hand, for example `GameAssembly.dll` + `1A2B3C`, offsets `10, 2C`.

Mods and settings are saved in `%APPDATA%\HouseEdge` (Windows) or `~/.config/house-edge` (Linux).

## How it works
- `house_edge/memory.py`: reads and writes the game's memory. On Windows it uses `ReadProcessMemory`/`WriteProcessMemory`. On Linux, including Proton and Steam Deck, it uses `/proc/<pid>/mem`.
- `house_edge/scanner.py`: the value finder. It reads memory in 8 MB chunks and compares with numpy.
- `house_edge/mods.py`: mods, pointer chains, Cheat Engine import and profiles.
- `house_edge/hotkeys.py`: global hotkeys on Windows.
- `house_edge/core.py`: auto-join, the 20-times-a-second lock loop, and a local API. The API only listens on 127.0.0.1 and needs a per-launch token.
- `house_edge/ui/index.html`: the panel.

## Test
```bash
python selftest.py
```
This starts a stand-in "game" process, then finds, changes, locks and pointer-follows values in it. It also checks the API and the Cheat Engine import. CI runs it on Windows and then builds and smoke-tests `HouseEdge.exe`.

## Not included (yet)
- **Game speed** (slow-mo or fast-forward) and **code patches** like "god mode". These need code injected into the game process, which House Edge doesn't do. Cheat Engine can do both.
- **Ready-made mods for We're All In.** I don't have the game, so there are no addresses yet. Find them with the Value finder, or import a .CT table.
