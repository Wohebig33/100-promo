@echo off
setlocal EnableExtensions
title Buckshot Cheat - install
set "MOD=%~dp0"
if not exist "%MOD%cheat.gd" goto :nomod

rem Find the game's .exe: in this folder's parent, this folder, or Buckshot Roulette_windows
set "EXE="
for %%D in ("%MOD%.." "%MOD%." "%MOD%..\Buckshot Roulette_windows") do (
  for %%E in ("%%~fD\Buckshot*.exe") do if not defined EXE set "EXE=%%~fE"
)
if not defined EXE goto :noexe
for %%E in ("%EXE%") do set "GAMEDIR=%%~dpE"
set "CFG=%GAMEDIR%override.cfg"
set "TMPCFG=%TEMP%\buckshot_cheat_cfg.tmp"

rem Godot wants forward slashes
set "GD=%MOD%cheat.gd"
set "GD=%GD:\=/%"

rem Keep anything else already in override.cfg (other mods), drop old copies of our line
type nul > "%TMPCFG%"
if exist "%CFG%" copy /y "%CFG%" "%CFG%.bak" >nul
if exist "%CFG%" findstr /v /c:"BuckshotCheat=" "%CFG%.bak" > "%TMPCFG%"

> "%CFG%" echo [autoload]
>>"%CFG%" echo(
>>"%CFG%" echo BuckshotCheat="*%GD%"
>>"%CFG%" echo(
type "%TMPCFG%" >> "%CFG%"
del "%TMPCFG%" >nul 2>&1

echo.
echo  Installed!
echo  Game:   %EXE%
echo  Config: %CFG%
echo.
echo  Start Buckshot Roulette and press F1 (or Insert) in game.
echo  If you move this folder, run INSTALL.bat again.
echo.
pause
exit /b 0

:nomod
echo cheat.gd is missing. Keep INSTALL.bat inside the BuckshotCheat folder.
pause
exit /b 1

:noexe
echo Could not find "Buckshot Roulette.exe".
echo Put the BuckshotCheat folder inside the game folder, next to the .exe:
echo   Steam ^> right-click Buckshot Roulette ^> Manage ^> Browse local files
pause
exit /b 1
