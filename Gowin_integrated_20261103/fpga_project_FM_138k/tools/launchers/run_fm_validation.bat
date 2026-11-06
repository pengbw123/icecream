@echo off
setlocal
cd /d "%~dp0\.."
python apps\fm_validation_gui.py
if errorlevel 1 pause
