#!/usr/bin/env bash
# One-click installer for the project's Godot addon dependencies.
#
# Currently installs:
#   * LimboAI (GDExtension build) -> addons/limboai
#     Behavior Trees & State Machines for Godot 4. The GDExtension flavor
#     works with the stock Godot 4.6+ editor (no custom build needed).
#
# What this script does:
#   1. Checks for curl + unzip
#   2. Downloads the pinned LimboAI GDExtension zip from GitHub Releases
#   3. Extracts only the addons/limboai folder into the project
#   4. Verifies the installed version matches the pin
#
# Usage: ./install-addons.sh
#   Re-run safely at any time; it is idempotent (skips download when the
#   pinned version is already present and intact).
#
# To upgrade LimboAI, edit LIMBOAI_VERSION below and re-run.

set -u

# --- configuration ----------------------------------------------------------

LIMBOAI_VERSION="1.8.0"
# GDExtension build targets Godot 4.6+ (works with 4.7). See LimboAI's
# compatibility table in its README.
LIMBOAI_ZIP_NAME="limboai+v${LIMBOAI_VERSION}.gdextension-4.6.zip"
LIMBOAI_URL="https://github.com/limbonaut/limboai/releases/download/v${LIMBOAI_VERSION}/${LIMBOAI_ZIP_NAME}"
LIMBOAI_TARGET_DIR="addons/limboai"

# --- helpers ----------------------------------------------------------------

COLOR_RESET=$'\033[0m'
COLOR_RED=$'\033[31m'
COLOR_GREEN=$'\033[32m'
COLOR_YELLOW=$'\033[33m'
COLOR_BLUE=$'\033[34m'

info()  { printf "${COLOR_BLUE}[INFO]${COLOR_RESET}  %s\n"  "$*"; }
ok()    { printf "${COLOR_GREEN}[OK]${COLOR_RESET}    %s\n"  "$*"; }
warn()  { printf "${COLOR_YELLOW}[WARN]${COLOR_RESET}  %s\n"  "$*"; }
fail()  { printf "${COLOR_RED}[ERROR]${COLOR_RESET} %s\n" "$*" >&2; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Resolve the repo root from this script's location so it works from any CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${SCRIPT_DIR}/${LIMBOAI_TARGET_DIR}"
VERSION_FILE="${TARGET_DIR}/version.txt"

# --- pre-flight -------------------------------------------------------------

if [ ! -f "${SCRIPT_DIR}/project.godot" ]; then
    fail "Cannot find project.godot next to this script."
    fail "Make sure you run this script from the Detective-Game repository root."
    exit 1
fi

if ! command_exists curl; then
    fail "curl is required. Install it and re-run."
    exit 1
fi
if ! command_exists unzip; then
    fail "unzip is required. Install it and re-run."
    exit 1
fi

# --- idempotency check -------------------------------------------------------

# If the pinned version is already installed, exit early.
if [ -f "${VERSION_FILE}" ]; then
    INSTALLED_VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}" 2>/dev/null || true)"
    if [ "${INSTALLED_VERSION}" = "v${LIMBOAI_VERSION}" ]; then
        ok "LimboAI v${LIMBOAI_VERSION} already installed at ${LIMBOAI_TARGET_DIR}/"
        ok "Nothing to do. To upgrade, bump LIMBOAI_VERSION in this script and re-run."
        exit 0
    fi
    warn "Installed LimboAI version (${INSTALLED_VERSION}) differs from pin (v${LIMBOAI_VERSION}). Reinstalling..."
fi

# --- download + extract ------------------------------------------------------

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

ZIP_PATH="${TMP_DIR}/${LIMBOAI_ZIP_NAME}"
info "Downloading LimboAI v${LIMBOAI_VERSION} ..."
info "  ${LIMBOAI_URL}"
if ! curl -fL --retry 3 -o "${ZIP_PATH}" "${LIMBOAI_URL}"; then
    fail "Failed to download LimboAI release archive."
    fail "Check your network, or verify the version tag at https://github.com/limbonaut/limboai/releases"
    exit 1
fi

info "Extracting addons/limboai ..."
EXTRACT_DIR="${TMP_DIR}/extract"
if ! unzip -q "${ZIP_PATH}" -d "${EXTRACT_DIR}"; then
    fail "Failed to extract the archive."
    exit 1
fi

SRC_DIR="${EXTRACT_DIR}/addons/limboai"
if [ ! -d "${SRC_DIR}" ]; then
    fail "Archive did not contain addons/limboai. The release layout may have changed."
    exit 1
fi

# Replace the target dir atomically-ish: remove old, copy new.
rm -rf "${TARGET_DIR}"
mkdir -p "${SCRIPT_DIR}/addons"
cp -R "${SRC_DIR}" "${TARGET_DIR}"

# --- verify ------------------------------------------------------------------

if [ ! -f "${VERSION_FILE}" ]; then
    fail "Installation finished but version.txt is missing."
    exit 1
fi
INSTALLED_VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}" 2>/dev/null || true)"
if [ "${INSTALLED_VERSION}" != "v${LIMBOAI_VERSION}" ]; then
    warn "Installed version (${INSTALLED_VERSION}) does not match pin (v${LIMBOAI_VERSION})."
fi

ok "LimboAI installed: ${LIMBOAI_TARGET_DIR}/ (version ${INSTALLED_VERSION})"
echo
info "Next step: open the project in Godot 4.6+ once so it registers the GDExtension."
info "  The classes (BTSequence, BTPlayer, Blackboard, ...) become available automatically."
echo
exit 0
