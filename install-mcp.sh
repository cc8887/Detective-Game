#!/usr/bin/env bash
# One-click installer for the project's MCP dependencies.
#
# What this script does:
#   1. Checks Node.js (provides `npx` for @coding-solo/godot-mcp)
#   2. Checks the Godot binary (used by godot-mcp via GODOT_PATH)
#   3. Offers to install missing pieces via Homebrew (macOS) interactively
#   4. Verifies @coding-solo/godot-mcp is resolvable on the npm registry
#   5. Rewrites GODOT_PATH in both .devin/config.json (Devin) and .mcp.json
#      (Claude Code) so the shared configs match the local machine (idempotent)
#
# Usage: ./install-mcp.sh
#   Re-run safely at any time; it is idempotent.

set -u

# --- helpers -----------------------------------------------------------------

COLOR_RESET=$'\033[0m'
COLOR_RED=$'\033[31m'
COLOR_GREEN=$'\033[32m'
COLOR_YELLOW=$'\033[33m'
COLOR_BLUE=$'\033[34m'

info()  { printf "${COLOR_BLUE}[INFO]${COLOR_RESET}  %s\n"  "$*"; }
ok()    { printf "${COLOR_GREEN}[OK]${COLOR_RESET}    %s\n"  "$*"; }
warn()  { printf "${COLOR_YELLOW}[WARN]${COLOR_RESET}  %s\n"  "$*"; }
fail()  { printf "${COLOR_RED}[ERROR]${COLOR_RESET} %s\n" "$*" >&2; }

ask_yn() {
    # ask_yn <prompt> -> returns 0 on yes, 1 on no
    local prompt="$1 (y/N) "
    local reply
    read -r -p "$prompt" reply
    case "$reply" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Resolve the repo root from this script's location so it works from any CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVIN_CONFIG="$SCRIPT_DIR/.devin/config.json"
CLAUDE_CONFIG="$SCRIPT_DIR/.mcp.json"
UPDATE_HELPER="$SCRIPT_DIR/scripts/update-mcp-config.js"

# --- pre-flight --------------------------------------------------------------

# .devin/config.json is the source of truth committed to the repo; the
# installer only patches GODOT_PATH inside it. .mcp.json (Claude Code) is
# also committed; if missing the helper will scaffold it on the fly.
if [ ! -f "$DEVIN_CONFIG" ]; then
    fail "Cannot find $DEVIN_CONFIG"
    fail "Make sure you run this script from the Detective-Game repository root."
    exit 1
fi
if [ ! -f "$UPDATE_HELPER" ]; then
    fail "Cannot find $UPDATE_HELPER"
    fail "Make sure you run this script from the Detective-Game repository root."
    exit 1
fi

OS_TYPE="$(uname -s)"
case "$OS_TYPE" in
    Darwin) PLATFORM="macos" ;;
    Linux)  PLATFORM="linux" ;;
    *)      PLATFORM="unknown" ;;
esac

info "Detected platform: $PLATFORM"
info "Devin config:      $DEVIN_CONFIG"
info "Claude Code config: $CLAUDE_CONFIG"
echo

# --- 1. Node.js --------------------------------------------------------------

check_node() {
    if command_exists node && command_exists npx; then
        local version
        version="$(node -v 2>/dev/null || echo unknown)"
        ok "Node.js found: $version ($(command -v node))"
        return 0
    fi
    return 1
}

install_node_macos() {
    if ! command_exists brew; then
        warn "Homebrew is not installed. Installing Homebrew first..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
            fail "Homebrew installation failed."
            return 1
        }
    fi
    info "Installing Node.js via Homebrew..."
    brew install node || { fail "brew install node failed."; return 1; }
}

install_node_linux() {
    warn "Auto-install on Linux is not supported by this script."
    info "Install Node.js via your package manager or NodeSource, e.g.:"
    info "  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -"
    info "  sudo apt-get install -y nodejs"
    return 1
}

if check_node; then
    :
else
    warn "Node.js (or npx) was not found. @coding-solo/godot-mcp needs npx to run."
    if [ "$PLATFORM" = "macos" ]; then
        if ask_yn "Install Node.js via Homebrew now?"; then
            install_node_macos || { fail "Node.js setup failed."; exit 1; }
            check_node || { fail "Node.js still not on PATH. Open a new shell and re-run."; exit 1; }
        else
            fail "Node.js is required. Install it and re-run this script."
            exit 1
        fi
    elif [ "$PLATFORM" = "linux" ]; then
        install_node_linux
        exit 1
    else
        fail "Unsupported platform for auto-install. Please install Node.js manually."
        exit 1
    fi
fi
echo

# --- 2. Godot ----------------------------------------------------------------

# Print the first Godot candidate that actually exists and is executable.
find_godot_path() {
    local candidate
    # 1. Whatever is on PATH
    if command_exists godot; then
        command -v godot
        return 0
    fi
    # 2. Common Homebrew locations on Apple Silicon / Intel
    for candidate in \
        "/opt/homebrew/bin/godot" \
        "/usr/local/bin/godot" \
        "/opt/homebrew/bin/godot4" \
        "/usr/local/bin/godot4"; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    # 3. Godot.app bundle
    for candidate in \
        "/Applications/Godot.app/Contents/MacOS/Godot" \
        "$HOME/Applications/Godot.app/Contents/MacOS/Godot"; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    # 4. Linux common locations
    for candidate in \
        "/usr/bin/godot" \
        "/usr/local/bin/godot" \
        "$HOME/.local/bin/godot" \
        "/snap/bin/godot"; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

install_godot_macos() {
    if ! command_exists brew; then
        fail "Homebrew is required to install Godot automatically."
        return 1
    fi
    info "Installing Godot via Homebrew cask..."
    brew install --cask godot || { fail "brew install --cask godot failed."; return 1; }
}

install_godot_linux() {
    warn "Auto-install of Godot on Linux is not supported by this script."
    info "Download Godot from https://godotengine.org/download/linux/ or use your distro's package."
    info "Then place the binary on your PATH or set GODOT_PATH manually."
    return 1
}

GODOT_PATH="$(find_godot_path || true)"
if [ -n "$GODOT_PATH" ]; then
    ok "Godot found: $GODOT_PATH"
else
    warn "Godot was not found on PATH or in common locations."
    if [ "$PLATFORM" = "macos" ]; then
        if ask_yn "Install Godot via Homebrew cask now?"; then
            install_godot_macos || { fail "Godot setup failed."; exit 1; }
            GODOT_PATH="$(find_godot_path || true)"
            if [ -z "$GODOT_PATH" ]; then
                fail "Godot installed but not found on PATH. Open a new shell and re-run."
                exit 1
            fi
            ok "Godot found: $GODOT_PATH"
        else
            fail "Godot is required by godot-mcp. Install it and re-run."
            exit 1
        fi
    elif [ "$PLATFORM" = "linux" ]; then
        install_godot_linux
        exit 1
    else
        fail "Unsupported platform for auto-install. Please install Godot manually."
        exit 1
    fi
fi
echo

# --- 3. Verify the MCP package is reachable ----------------------------------

info "Verifying @coding-solo/godot-mcp is reachable on the npm registry..."
# We deliberately do NOT execute the package here: godot-mcp starts a stdio
# server that does not exit on EOF, so running it would hang. The package is
# tiny (~140 KB), so the first real MCP-client launch will download it in
# about a second. We only check that the registry can resolve it.
if npm view @coding-solo/godot-mcp version >/dev/null 2>&1; then
    ok "Package @coding-solo/godot-mcp is resolvable from npm."
else
    warn "Could not reach @coding-solo/godot-mcp on the npm registry."
    warn "Check your network/registry; the MCP client will retry on first launch."
fi
echo

# --- 4. Update MCP client configs -------------------------------------------
# Patches GODOT_PATH in both the Devin config (.devin/config.json) and the
# Claude Code config (.mcp.json). The shared Node helper is a no-op when the
# path is already correct, so re-running this script produces no diff. If
# .mcp.json does not exist yet, the helper scaffolds it (Claude Code format,
# no `transport` field).

update_one_config() {
    # update_one_config <config.json> <template>
    local cfg="$1" tpl="$2"
    node "$UPDATE_HELPER" "$cfg" "$GODOT_PATH" "$tpl" \
        || { fail "Failed to update $cfg"; return 1; }
}

info "Updating MCP client configs ..."
update_one_config "$DEVIN_CONFIG"   devin   || exit 1
update_one_config "$CLAUDE_CONFIG"  claude  || exit 1
echo

# --- 5. Summary --------------------------------------------------------------

ok "MCP setup complete."
echo
printf "  Node.js        : %s\n" "$(command -v node)"
printf "  Godot          : %s\n" "$GODOT_PATH"
printf "  Devin config   : %s\n" "$DEVIN_CONFIG"
printf "  Claude config  : %s\n" "$CLAUDE_CONFIG"
echo
info "Next step: restart your MCP client (Devin / Claude Code / Cursor / Windsurf) so it picks up the new config."
