@echo off
cd /d "%~dp0"
if not exist "%~dp0start.ps1" certutil -f -decode "%~dp0start-source.b64" "%~dp0start.ps1" >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1" -Port 4848
pause
