@echo off
setlocal
set "DIR=%~dp0"
rem Prefer portable AutoHotkey shipped in .\autohotkey\
set "AHK=%DIR%autohotkey\AutoHotkey64.exe"
if not exist "%AHK%" set "AHK=%DIR%autohotkey\AutoHotkey32.exe"
rem Fallback: portable copy dropped next to the script
if not exist "%AHK%" set "AHK=%DIR%AutoHotkey64.exe"
if not exist "%AHK%" set "AHK=%DIR%AutoHotkey32.exe"
rem Final fallback: system-wide install on PATH
if not exist "%AHK%" set "AHK=AutoHotkey.exe"
start "" "%AHK%" "%DIR%workspace_tool.ahk"
