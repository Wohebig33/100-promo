# Buckshot Helper

An always-on-top cheat window for Buckshot Roulette single player. It tracks the shotgun's chamber, shows the exact chance that each shell is live, and tells you who to shoot.

It does not read or change the game. You enter what the game shows you, so it works with any version of the game.

## Run
Install Python 3 from python.org with the default options, which include tkinter. Then double-click `run_helper.bat` on Windows, or run:

```bash
python buckshot_helper.py
```

## Use
1. At each new load, set the live and blank counts the game shows, then click **New load** (Ctrl+N).
2. After every shot, click LIVE or BLANK under **Shot fired**, or press **L** or **B**.
3. Enter what your items reveal:
   - **Beer:** click what got racked out.
   - **Magnifying glass:** click what you saw (Q or W).
   - **Burner phone:** set which shell it named ("third shell" = 3) and click LIVE or BLANK.
   - **Inverter:** press **I**. The odds flip, and the shell's real type is still counted correctly after it fires.
4. Read the big number and the advice under it. A blank on yourself gives you a free turn, so the advice is to shoot yourself whenever live is under 50%.

The row of boxes shows every shell left in the gun. Red means a known live, blue means a known blank, and a percentage means unknown. Ctrl+Z undoes a mistake. You can also turn **On top** off and adjust the window's opacity.

Shells you've ruled out count as known. For example, if 1 live and 2 blank were loaded and the live has already fired, every remaining shell shows as BLNK.
