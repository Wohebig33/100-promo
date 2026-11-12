# Sinborn

An action RPG with Seven Deadly Sins bloodlines. Its loop is modeled on Roblox Bloodlines-style games: spin for a random bloodline, grind your stats, and fight bosses.

There are two versions:

- **Browser:** open `index.html` in a desktop browser.
- **Roblox Studio:** open `roblox/Sinborn.rbxlx`. Setup, Rojo sync and manual paste steps are in [`roblox/README.md`](roblox/README.md).

The browser version needs a keyboard and mouse. Progress saves to the browser's localStorage.

## Core loop
- **Spin for a bloodline.** Each spin rolls one of seven sins: Sloth 30%, Gluttony 25%, Greed 18%, Envy 12%, Lust 9%, Wrath 5%, Pride 1%. A pity counter guarantees a Legendary or Mythic within 50 spins. Each bloodline has stat multipliers, a passive and four skills.
- **Spin for an affinity.** This is a second roll for an element: Hellfire, Cocytus Frost, Brimstone, Storm or Umbra. Each element gives two more skills.
- **Reliquary.** Store up to two bloodlines so you can keep spinning without losing a good roll.
- **Train stats.** Melee hits train Strength. Charging Malice trains Malice, faster at the Altar. Dashing and running train Agility. Taking hits trains Vitality. Each level also gives 3 stat points.
- **Skill tree.** Skills unlock at levels 1, 4, 9 and 15, affinity skills at 2 and 7, and Sin Awakening at 12. Every skill gains mastery (up to 5) with use, which adds damage and cuts its cooldown.
- **Missions.** The Board of Penance posts D–S rank missions: slay, hunt, elite and shard runs. They pay XP, souls and spins.
- **Ranks.** Initiate → Acolyte → Sinner → Fallen → Archfiend → Sin Prince → Sin Lord. Each new rank gives 2 spins.
- **Bosses.** Seven Hollow Princes sit behind sealed arenas that need levels 5 to 30. Each kill gives 3 spins.
- **Death.** You lose 25% of your souls and your active mission.

## Controls
WASD to move, click or J for melee, right-click or F to block, Space to dash, hold C to charge Malice, 1–4 for bloodline skills, Q and E for affinity skills, G for Awakening, T to interact, K for stats and skills, Esc to pause.

---

# We're All In: main menu

There's a playable main menu for **We're All In** in [`were-all-in/`](were-all-in/README.md). Open `were-all-in/index.html` in a browser.

---

# House Edge: mod panel

[`house-edge/`](house-edge/README.md) is a trainer for single-player games, made for We're All In. It runs outside the game, joins it automatically and lets you lock or change values like chips and health. It has a built-in value finder, hotkeys, Cheat Engine table import and Party Mode. Download the Windows build from the Actions tab.
