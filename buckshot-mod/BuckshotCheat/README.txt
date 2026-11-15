BUCKSHOT CHEAT - in-game cheat menu for Buckshot Roulette (single player)
=========================================================================

INSTALL
 1. Steam > right-click Buckshot Roulette > Manage > Browse local files.
 2. Copy this whole "BuckshotCheat" folder into that game folder
    (the one with "Buckshot Roulette.exe" in it).
 3. Double-click INSTALL.bat inside BuckshotCheat.
 4. Start the game. Press F1 (or Insert) to open the menu.

The game's own files are not changed. INSTALL.bat only creates a small
"override.cfg" next to the game's .exe that tells the game to load cheat.gd.

UNINSTALL
 Double-click UNINSTALL.bat, then delete the BuckshotCheat folder.

WHAT IT DOES
 Shells   - always-on HUD (top right) with every shell in order, current
            shell framed in gold. L = live, B = blank.
          - Next = LIVE / Next = BLANK change the shell in the chamber.
          - All LIVE / All BLANK change every shell left in the gun.
 Health   - Me +1 / Me -1 / Me max, Dealer -1 / Dealer to 1.
          - "Keep my health full" refills you after every hit.
            (A single hit bigger than your health, e.g. a sawed-off shot
            at 2 lives, can still kill you - set the next shell to BLANK.)
 Items    - "Only: <item>" makes the next briefcase hand out that item.
          - "Items to grab" sets how many you take from the briefcase (max 8).
            Takes effect the next time the briefcase opens.

 The mod turns itself off in multiplayer.

TROUBLESHOOTING
 * Menu never appears: run INSTALL.bat again (needed if you moved the folder).
 * Menu says "Waiting for a single-player game..." during a match: a game
   update probably renamed something. Send the log from
   %APPDATA%\Godot\app_userdata\Buckshot Roulette\logs\godot.log
   (look for lines starting with [BuckshotCheat]).
 * Windows only. Linux / Steam Deck would need override.cfg written by hand.
