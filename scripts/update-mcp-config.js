#!/usr/bin/env node
/**
 * Shared helper for install-mcp.sh / install-mcp.cmd.
 *
 * Patches the `mcpServers.godot.env.GODOT_PATH` field in an MCP client config
 * file to point at the local Godot executable, preserving the rest of the
 * file's formatting. Supports both Devin-style (.devin/config.json, with a
 * `transport` field) and Claude-Code-style (.mcp.json, no `transport` field)
 * configs.
 *
 * Usage: node update-mcp-config.js <config.json> <godot_path> [template]
 *
 *   template - optional, one of "devin" | "claude". Used only when the config
 *              file does not exist yet, to decide which skeleton to create.
 *              Defaults to "claude". Ignored when the file already exists.
 *
 * - Exits 0 and prints "[OK]    GODOT_PATH already correct: ..." when the path
 *   is already correct (so re-running the installer is a no-op).
 * - Exits 0 and prints "[OK]    Updated GODOT_PATH: ... -> ..." (or
 *   "[OK]    Created <config> with GODOT_PATH=...") when it changed/created
 *   the file.
 * - Exits non-zero on error.
 */
"use strict";

const fs = require("fs");

const configPath = process.argv[2];
const godotPath = process.argv[3];
const template = process.argv[4] || "claude";

if (!configPath || !godotPath) {
    console.error("Usage: node update-mcp-config.js <config.json> <godot_path> [template]");
    process.exit(2);
}

// --- create the file if it does not exist ------------------------------------

let raw;
try {
    raw = fs.readFileSync(configPath, "utf8");
} catch (e) {
    if (e.code !== "ENOENT") {
        console.error("Failed to read " + configPath + ": " + e.message);
        process.exit(1);
    }
    // File missing: scaffold it from the appropriate template.
    // JSON.stringify handles backslash escaping for us.
    const skeleton = JSON.stringify(
        {
            mcpServers: {
                godot: {
                    command: "npx",
                    args: ["-y", "@coding-solo/godot-mcp"],
                    env: { GODOT_PATH: godotPath, DEBUG: "true" },
                    ...(template === "devin" ? { transport: "stdio" } : {})
                }
            }
        },
        null,
        2
    ) + "\n";
    // Sanity check the escaped path round-trips through JSON.parse.
    try {
        JSON.parse(skeleton);
    } catch (ce) {
        console.error("Internal error: generated invalid JSON for " + configPath + ": " + ce.message);
        process.exit(1);
    }
    fs.writeFileSync(configPath, skeleton);
    console.log("[OK]    Created " + configPath + " with GODOT_PATH=" + godotPath);
    process.exit(0);
}

// --- patch an existing file --------------------------------------------------

let json;
try {
    json = JSON.parse(raw);
} catch (e) {
    console.error("Failed to parse " + configPath + ": " + e.message);
    process.exit(1);
}

json.mcpServers = json.mcpServers || {};
json.mcpServers.godot = json.mcpServers.godot || {};
json.mcpServers.godot.env = json.mcpServers.godot.env || {};
const before = json.mcpServers.godot.env.GODOT_PATH || null;

if (before === godotPath) {
    console.log("[OK]    GODOT_PATH already correct in " + configPath + ": " + godotPath);
    process.exit(0);
}

// Patch just the GODOT_PATH line so the rest of the file keeps its original
// formatting (inline arrays, indentation, trailing newline, etc.).
const escaped = godotPath.replace(/\\/g, "\\\\");
const newRaw = raw.replace(
    /"GODOT_PATH"\s*:\s*"[^"]*"/,
    '"GODOT_PATH": "' + escaped + '"'
);

if (newRaw !== raw && newRaw.indexOf('"GODOT_PATH": "' + godotPath + '"') !== -1) {
    fs.writeFileSync(configPath, newRaw);
} else {
    // Fallback: full re-serialize if the targeted regex did not match.
    json.mcpServers.godot.env.GODOT_PATH = godotPath;
    fs.writeFileSync(configPath, JSON.stringify(json, null, 2) + "\n");
}

console.log("[OK]    Updated GODOT_PATH in " + configPath + ": " + (before || "<unset>") + " -> " + godotPath);
