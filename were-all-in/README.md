# We're All In: main menu

A main menu for **We're All In**, themed like a casino card table. It's one HTML file with no build step: open `index.html` in a browser.

## What's in it
- **Title screen** with "Press any key". Falling chips and card suits react to the mouse.
- **Main menu:** Play, Settings, Achievements, Credits, Quit. A playing card on the right flips to match the option you're on.
- **Play:** Quick Match, Host a Table (makes a 5-letter table code), Practice vs Bots, Daily Deal. Each one runs a joke loading screen with tips.
- **Settings** in three tabs:
  - Audio: master, music and SFX volume.
  - Video: fullscreen, how many chips fall, screen shake, reduce motion.
  - Gameplay: player name, bot nerve, four-colour deck, loading tips, and a Pirate language mode.
- **Achievements:** 9 you can unlock from the menu itself. One of them is the Konami code.
- **Credits** that roll on their own.
- **Quit** asks "Fold already?" before you go.
- Music and sound effects are made in the browser with Web Audio, so there are no audio files.
- Works with a mouse, the keyboard (arrows, Enter, Esc) or a gamepad (D-pad or stick, A, B, Start).

Settings and achievements save to localStorage.

## Hooking up the game
When a player picks a mode and the loading screen finishes, the page fires `wai:start`:

```js
window.addEventListener('wai:start', e => {
  const { mode, settings } = e.detail; // mode: quick | host | bots | daily
  // load your table scene here
});
```

The play modes, credits and tips are placeholders. Edit the `MODES`, `CREDITS` and `TIPS` lists near the top of the script.
