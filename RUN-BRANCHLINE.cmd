@echo off
start "Branchline Git Workbench" /D "%~dp0" powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0start.ps1" -Port 4848
