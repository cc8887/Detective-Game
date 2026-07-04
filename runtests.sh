#!/usr/bin/env bash
# Run gdUnit4 tests for the Detective-Game project
# Usage: ./runtests.sh [test_path]
#   test_path - optional path to a test suite or directory (default: res://test/)

set -e

# Find Godot binary
GODOT_BIN="${GODOT_BIN:-$(command -v godot 2>/dev/null || true)}"

if [ -z "$GODOT_BIN" ]; then
    echo "Error: Godot binary not found."
    echo "Please set the GODOT_BIN environment variable to your Godot executable path."
    echo "  Example: export GODOT_BIN=/path/to/godot"
    exit 1
fi

# Default test path
TEST_PATH="${1:-res://test/}"

echo "Running gdUnit4 tests: $TEST_PATH"
echo "Using Godot: $GODOT_BIN"

"$GODOT_BIN" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a "$TEST_PATH" --ignoreHeadlessMode
exit_code=$?

echo ""
echo "Tests finished with exit code: $exit_code"
exit $exit_code
