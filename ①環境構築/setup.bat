@echo off
rem Training environment setup (ASCII only on purpose)
set "SETUP_PS1=%~dp0setup.ps1"
net session >nul 2>&1
if %errorlevel% equ 0 goto :run

echo Requesting administrator rights. Please click Yes in the dialog.
powershell -NoProfile -Command "Start-Process -FilePath powershell -Verb RunAs -ArgumentList (\"-NoProfile -ExecutionPolicy Bypass -NoExit -File `\"\" + $env:SETUP_PS1 + \"`\"\")"
if %errorlevel% neq 0 (
  echo Could not start as administrator. Right-click setup.bat and choose Run as administrator.
  pause
)
exit /b

:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%SETUP_PS1%"
pause
