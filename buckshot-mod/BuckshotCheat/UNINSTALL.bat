@echo off
setlocal EnableExtensions
title Buckshot Cheat - uninstall
set "MOD=%~dp0"
set "EXE="
for %%D in ("%MOD%.." "%MOD%." "%MOD%..\Buckshot Roulette_windows") do (
  for %%E in ("%%~fD\Buckshot*.exe") do if not defined EXE set "EXE=%%~fE"
)
if not defined EXE goto :noexe
for %%E in ("%EXE%") do set "GAMEDIR=%%~dpE"
set "CFG=%GAMEDIR%override.cfg"
set "TMPCFG=%TEMP%\buckshot_cheat_cfg.tmp"
if not exist "%CFG%" goto :done

findstr /v /c:"BuckshotCheat=" "%CFG%" > "%TMPCFG%"
rem If nothing but section headers is left, the file was only ours: delete it
findstr /c:"=" "%TMPCFG%" >nul
if errorlevel 1 del "%CFG%"
if not errorlevel 1 copy /y "%TMPCFG%" "%CFG%" >nul
del "%TMPCFG%" >nul 2>&1

:done
echo.
echo  Uninstalled. The game will start normally.
echo  You can delete the BuckshotCheat folder now.
echo.
pause
exit /b 0

:noexe
echo Could not find "Buckshot Roulette.exe" next to this folder.
pause
exit /b 1
