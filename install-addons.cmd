@echo off
setlocal enabledelayedexpansion

REM One-click installer for the project's Godot addon dependencies (Windows).
REM
REM Currently installs:
REM   * LimboAI (GDExtension build) -> addons\limboai
REM
REM Usage: install-addons.cmd
REM   Re-run safely at any time; it is idempotent.
REM
REM To upgrade LimboAI, edit LIMBOAI_VERSION below and re-run.

set "LIMBOAI_VERSION=1.8.0"
set "LIMBOAI_ZIP_NAME=limboai+v%LIMBOAI_VERSION%.gdextension-4.6.zip"
set "LIMBOAI_URL=https://github.com/limbonaut/limboai/releases/download/v%LIMBOAI_VERSION%/%LIMBOAI_ZIP_NAME%"
set "LIMBOAI_TARGET_DIR=addons\limboai"

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "TARGET_DIR=%SCRIPT_DIR%\%LIMBOAI_TARGET_DIR%"
set "VERSION_FILE=%TARGET_DIR%\version.txt"

if not exist "%SCRIPT_DIR%\project.godot" (
    echo [ERROR] Cannot find project.godot next to this script.
    echo         Run this script from the Detective-Game repository root.
    exit /b 1
)

where curl >nul 2>&1
if errorlevel 1 (
    echo [ERROR] curl is required. Install it and re-run.
    exit /b 1
)
where tar >nul 2>&1
if errorlevel 1 (
    echo [ERROR] tar (with zip support) is required on Windows 10+.
    exit /b 1
)

REM --- idempotency check -----------------------------------------------------

if exist "%VERSION_FILE%" (
    set /p INSTALLED_VERSION=<"%VERSION_FILE%"
    set "INSTALLED_VERSION=!INSTALLED_VERSION: =!"
    if "!INSTALLED_VERSION!"=="v%LIMBOAI_VERSION%" (
        echo [OK]    LimboAI v%LIMBOAI_VERSION% already installed at %LIMBOAI_TARGET_DIR%\
        echo [OK]    Nothing to do. To upgrade, bump LIMBOAI_VERSION in this script and re-run.
        exit /b 0
    )
    echo [WARN] Installed LimboAI version ^(!INSTALLED_VERSION!^) differs from pin ^(v%LIMBOAI_VERSION%^). Reinstalling...
)

REM --- download + extract ----------------------------------------------------

set "TMP_DIR=%TEMP%\detective-game-limboai-%RANDOM%"
if exist "%TMP_DIR%" rmdir /s /q "%TMP_DIR%"
mkdir "%TMP_DIR%"

set "ZIP_PATH=%TMP_DIR%\%LIMBOAI_ZIP_NAME%"
echo [INFO]  Downloading LimboAI v%LIMBOAI_VERSION% ...
echo [INFO]    %LIMBOAI_URL%
curl -fL --retry 3 -o "%ZIP_PATH%" "%LIMBOAI_URL%"
if errorlevel 1 (
    echo [ERROR] Failed to download LimboAI release archive.
    rmdir /s /q "%TMP_DIR%"
    exit /b 1
)

echo [INFO]  Extracting addons\limboai ...
set "EXTRACT_DIR=%TMP_DIR%\extract"
mkdir "%EXTRACT_DIR%"
tar -xf "%ZIP_PATH%" -C "%EXTRACT_DIR%"
if errorlevel 1 (
    echo [ERROR] Failed to extract the archive.
    rmdir /s /q "%TMP_DIR%"
    exit /b 1
)

if not exist "%EXTRACT_DIR%\addons\limboai" (
    echo [ERROR] Archive did not contain addons\limboai. The release layout may have changed.
    rmdir /s /q "%TMP_DIR%"
    exit /b 1
)

if exist "%TARGET_DIR%" rmdir /s /q "%TARGET_DIR%"
if not exist "%SCRIPT_DIR%\addons" mkdir "%SCRIPT_DIR%\addons"
xcopy /e /i /q "%EXTRACT_DIR%\addons\limboai" "%TARGET_DIR%" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy LimboAI into place.
    rmdir /s /q "%TMP_DIR%"
    exit /b 1
)

rmdir /s /q "%TMP_DIR%"

if not exist "%VERSION_FILE%" (
    echo [ERROR] Installation finished but version.txt is missing.
    exit /b 1
)

echo [OK]    LimboAI installed: %LIMBOAI_TARGET_DIR%\ ^(version v%LIMBOAI_VERSION%^)
echo.
echo [INFO]  Next step: open the project in Godot 4.6+ once so it registers the GDExtension.
echo [INFO]    The classes ^(BTSequence, BTPlayer, Blackboard, ...^) become available automatically.
echo.
exit /b 0
