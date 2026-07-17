@echo off
title Stop Branchline Git Workbench
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0stop.ps1" -Port 4848
if errorlevel 1 pause
