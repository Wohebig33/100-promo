# House Edge

A mod panel (a "trainer") for single-player games, made for **We're All In**. It runs outside the game in its own window, joins the game while it's running, and lets you change what the game keeps in memory: chips, money, health, timers.

> **Single-player and local play only.** Don't use it online against other people or in games with anti-cheat. It spoils the game for others and can get your Steam account banned.

## Get it

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

## Use it

1. **Start the game** from Steam, then start House Edge.
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
   - **Hotkeys** (F1 to F12, Num0 to Num9, or Ctrl/Shift/Alt plus a key) toggle the lock from inside the game.
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
