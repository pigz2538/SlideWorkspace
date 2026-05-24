@echo off
setlocal
set "DIR=%~dp0"

rem Check if we're already elevated. `net session` fails for non-admin.
net session >nul 2>&1
if %errorLevel% neq 0 (
    rem Re-launch this batch file elevated via PowerShell. UAC prompt appears.
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

rem We are now elevated. Locate AHK.
set "AHK=%DIR%autohotkey\AutoHotkey64.exe"
if not exist "%AHK%" set "AHK=%DIR%autohotkey\AutoHotkey32.exe"
if not exist "%AHK%" set "AHK=%DIR%AutoHotkey64.exe"
if not exist "%AHK%" set "AHK=%DIR%AutoHotkey32.exe"
if not exist "%AHK%" set "AHK=AutoHotkey.exe"

rem Pass --admin so the script knows it should stay elevated (and any future
rem in-script elevation check is a no-op since we already have admin).
start "" "%AHK%" "%DIR%workspace_tool.ahk" --admin
