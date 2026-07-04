@echo off
setlocal enabledelayedexpansion

:: Run gdUnit4 tests for the Detective-Game project
:: Usage: runtests.cmd [test_path]
::   test_path - optional path to a test suite or directory (default: res://test/)

:: Find Godot binary
set "godot_binary=%GODOT_BIN%"

if "!godot_binary!"=="" (
    echo Error: Godot binary not found.
    echo Please set the GODOT_BIN environment variable to your Godot executable path.
    echo   Example: set GODOT_BIN=C:\path\to\godot.exe
    exit /b 1
)

if not exist "!godot_binary!" (
    echo Error: The specified Godot binary '!godot_binary!' does not exist.
    exit /b 1
)

:: Default test path
set "test_path=res://test/"
if not "%~1"=="" set "test_path=%~1"

echo Running gdUnit4 tests: !test_path!
echo Using Godot: !godot_binary!

"!godot_binary!" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a "!test_path!" --ignoreHeadlessMode
set exit_code=%ERRORLEVEL%

echo.
echo Tests finished with exit code: %exit_code%
exit /b %exit_code%
