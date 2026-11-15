@echo off
cd /d "%~dp0"
start "" pythonw buckshot_helper.py || python buckshot_helper.py
