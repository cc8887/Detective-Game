@echo off
setlocal enabledelayedexpansion

REM One-click installer for the project's MCP dependencies (Windows).
REM
REM What this script does:
REM   1. Checks Node.js (provides `npx` for @coding-solo/godot-mcp)
REM   2. Checks the Godot binary (used by godot-mcp via GODOT_PATH)
REM   3. Offers to install missing pieces via winget interactively
REM   4. Verifies @coding-solo/godot-mcp is resolvable on the npm registry
REM   5. Rewrites GODOT_PATH in both .devin\config.json (Devin) and .mcp.json
REM      (Claude Code) so the shared configs match the local machine (idempotent)
REM
REM Usage: install-mcp.cmd
REM   Re-run safely at any time; it is idempotent.

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "DEVIN_CONFIG=%SCRIPT_DIR%\.devin\config.json"
set "CLAUDE_CONFIG=%SCRIPT_DIR%\.mcp.json"
set "UPDATE_HELPER=%SCRIPT_DIR%\scripts\update-mcp-config.js"

REM --- helpers ----------------------------------------------------------------

goto :main

:info
echo [INFO]  %~1
goto :eof

:ok
echo [OK]    %~1
goto :eof

:warn
echo [WARN]  %~1
goto :eof

:fail
echo [ERROR] %~1 1>&2
goto :eof

:ask_yn
REM Sets global ASK_RESULT to 1 on yes, 0 on no.
set /p "ASK_REPLY=%~1 (y/N) "
if /i "!ASK_REPLY!"=="y" ( set "ASK_RESULT=1" ) else if /i "!ASK_REPLY!"=="yes" ( set "ASK_RESULT=1" ) else ( set "ASK_RESULT=0" )
goto :eof

:find_godot
REM Sets global GODOT_PATH to the first existing Godot executable, or empty.
set "GODOT_PATH="
where godot >nul 2>&1 && for /f "delims=" %%I in ('where godot') do ( set "GODOT_PATH=%%I" & goto :eof )
if exist "%ProgramFiles%\Godot\godot.exe"        ( set "GODOT_PATH=%ProgramFiles%\Godot\godot.exe"        & goto :eof )
if exist "%ProgramFiles%\Godot Engine\godot.exe" ( set "GODOT_PATH=%ProgramFiles%\Godot Engine\godot.exe" & goto :eof )
if exist "%ProgramFiles(x86)%\Godot\godot.exe"   ( set "GODOT_PATH=%ProgramFiles(x86)%\Godot\godot.exe"   & goto :eof )
if exist "%LocalAppData%\Programs\Godot\godot.exe" ( set "GODOT_PATH=%LocalAppData%\Programs\Godot\godot.exe" & goto :eof )
goto :eof

:check_node
where node >nul 2>&1
if errorlevel 1 ( goto :node_missing )
where npx >nul 2>&1
if errorlevel 1 ( goto :node_missing )
for /f "delims=" %%V in ('node -v') do set "NODE_VERSION=%%V"
for /f "delims=" %%P in ('where node') do ( set "NODE_PATH=%%P" & goto :eof_node )
:eof_node
call :ok "Node.js found: !NODE_VERSION! (!NODE_PATH!)"
goto :eof
:node_missing
exit /b 1

:install_node
call :info "Installing Node.js via winget..."
winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements
if errorlevel 1 ( call :fail "winget install Node.js failed." & exit /b 1 )
REM Refresh PATH for this session so node/npx become available immediately.
set "PATH=%ProgramFiles%\nodejs;%ProgramFiles(x86)%\nodejs;%PATH%"
goto :eof

:install_godot
call :info "Installing Godot via winget..."
winget install --id GodotEngine.GodotEngine -e --accept-source-agreements --accept-package-agreements
if errorlevel 1 ( call :fail "winget install Godot failed." & exit /b 1 )
goto :eof

:update_config
REM Delegates to the shared Node helper so the JSON-editing logic is identical
REM across platforms and lives in one place. The helper is a no-op (exit 0)
REM when GODOT_PATH is already correct, so re-running on an already-correct
REM config produces no diff. If .mcp.json is missing the helper scaffolds it
REM (Claude Code format, no `transport` field).
REM Usage: call :update_config <config.json> <template>
node "%UPDATE_HELPER%" "%~1" "%GODOT_PATH%" "%~2"
if errorlevel 1 exit /b 1
goto :eof

:main

REM --- pre-flight -------------------------------------------------------------

REM .devin\config.json is the source of truth committed to the repo; the
REM installer only patches GODOT_PATH inside it. .mcp.json (Claude Code) is
REM also committed; if missing the helper will scaffold it on the fly.
if not exist "%DEVIN_CONFIG%" (
    call :fail "Cannot find %DEVIN_CONFIG%"
    call :fail "Make sure you run this script from the Detective-Game repository root."
    exit /b 1
)
if not exist "%UPDATE_HELPER%" (
    call :fail "Cannot find %UPDATE_HELPER%"
    call :fail "Make sure you run this script from the Detective-Game repository root."
    exit /b 1
)

call :info "Detected platform: Windows"
call :info "Devin config:      %DEVIN_CONFIG%"
call :info "Claude Code config: %CLAUDE_CONFIG%"
echo.

REM --- 1. Node.js -------------------------------------------------------------

call :check_node
if errorlevel 1 (
    call :warn "Node.js (or npx) was not found. @coding-solo/godot-mcp needs npx to run."
    where winget >nul 2>&1
    if errorlevel 1 (
        call :fail "winget is not available on this system. Please install Node.js from https://nodejs.org/ and re-run."
        exit /b 1
    )
    call :ask_yn "Install Node.js LTS via winget now?"
    if "!ASK_RESULT!"=="1" (
        call :install_node || ( call :fail "Node.js setup failed." & exit /b 1 )
        call :check_node || ( call :fail "Node.js still not on PATH. Open a new shell and re-run." & exit /b 1 )
    ) else (
        call :fail "Node.js is required. Install it and re-run this script."
        exit /b 1
    )
)
echo.

REM --- 2. Godot ---------------------------------------------------------------

call :find_godot
if defined GODOT_PATH (
    call :ok "Godot found: !GODOT_PATH!"
) else (
    call :warn "Godot was not found on PATH or in common locations."
    where winget >nul 2>&1
    if errorlevel 1 (
        call :fail "winget is not available. Please install Godot from https://godotengine.org/download/windows/ and re-run."
        exit /b 1
    )
    call :ask_yn "Install Godot via winget now?"
    if "!ASK_RESULT!"=="1" (
        call :install_godot || ( call :fail "Godot setup failed." & exit /b 1 )
        REM Refresh PATH and re-scan.
        call :find_godot
        if not defined GODOT_PATH (
            call :fail "Godot installed but not found on PATH. Open a new shell and re-run, or set GODOT_PATH manually."
            exit /b 1
        )
        call :ok "Godot found: !GODOT_PATH!"
    ) else (
        call :fail "Godot is required by godot-mcp. Install it and re-run."
        exit /b 1
    )
)
echo.

REM --- 3. Verify the MCP package is reachable --------------------------------

call :info "Verifying @coding-solo/godot-mcp is reachable on the npm registry..."
REM We deliberately do NOT execute the package here: godot-mcp starts a stdio
REM server that does not exit on EOF, so running it would hang. The package is
REM tiny (~140 KB), so the first real MCP-client launch will download it in
REM about a second. We only check that the registry can resolve it.
call npm view @coding-solo/godot-mcp version >nul 2>&1
if not errorlevel 1 (
    call :ok "Package @coding-solo/godot-mcp is resolvable from npm."
) else (
    call :warn "Could not reach @coding-solo/godot-mcp on the npm registry."
    call :warn "Check your network/registry; the MCP client will retry on first launch."
)
echo.

REM --- 4. Update MCP client configs -----------------------------------------
REM Patches GODOT_PATH in both the Devin config (.devin\config.json) and the
REM Claude Code config (.mcp.json). The shared Node helper is a no-op when
REM the path is already correct, so re-running produces no diff. If .mcp.json
REM does not exist yet, the helper scaffolds it (Claude Code format).

call :info "Updating MCP client configs ..."
call :update_config "%DEVIN_CONFIG%" devin || ( call :fail "Failed to update %DEVIN_CONFIG%" & exit /b 1 )
call :update_config "%CLAUDE_CONFIG%" claude || ( call :fail "Failed to update %CLAUDE_CONFIG%" & exit /b 1 )
echo.

REM --- 5. Install Godot addon dependencies -----------------------------------
REM Delegates to install-addons.cmd (LimboAI GDExtension, etc.). Idempotent.
REM We don't hard-fail the MCP setup if addons can't be installed.

set "ADDONS_INSTALLER=%SCRIPT_DIR%\install-addons.cmd"
if exist "%ADDONS_INSTALLER%" (
    call :info "Installing Godot addon dependencies (LimboAI) ..."
    call "%ADDONS_INSTALLER%"
    if errorlevel 1 (
        call :warn "install-addons.cmd reported a failure. LimboAI may be missing;"
        call :warn "run install-addons.cmd manually to diagnose."
    )
    echo.
) else (
    call :warn "install-addons.cmd not found at %ADDONS_INSTALLER%"
    call :warn "Skip Godot addon installation. Run install-addons.cmd manually if needed."
    echo.
)

REM --- 6. Summary -------------------------------------------------------------

call :ok "MCP setup complete."
echo.
echo   Node.js        : !NODE_PATH!
echo   Godot          : !GODOT_PATH!
echo   Devin config   : %DEVIN_CONFIG%
echo   Claude config  : %CLAUDE_CONFIG%
echo.
call :info "Next step: restart your MCP client (Devin / Claude Code / Cursor / Windsurf) so it picks up the new config."
call :info "Next step: open the project in Godot once so the LimboAI GDExtension is registered."

endlocal
exit /b 0
