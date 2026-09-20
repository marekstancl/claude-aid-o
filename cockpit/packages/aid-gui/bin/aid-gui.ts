#!/usr/bin/env node
/**
 * CLI entry point for the AID Orchestrator Dashboard GUI.
 *
 * Usage:
 *   npx aid-gui [options]
 *
 * Run `npx aid-gui --help` for available flags.
 */

import { Command } from "commander";
import path from "node:path";
import fs from "node:fs";
import { createRequire } from "node:module";

// ---------------------------------------------------------------------------
// Read version from package.json
// ---------------------------------------------------------------------------
const require = createRequire(import.meta.url);
const pkg = require("../package.json") as { version: string };

// ---------------------------------------------------------------------------
// Define CLI
// ---------------------------------------------------------------------------
const program = new Command();

program
  .name("aid-gui")
  .description("AID Orchestrator Dashboard -- real-time monitoring GUI")
  .version(pkg.version, "-V, --version")
  .option("--port <number>", "HTTP server port", "4200")
  .option("--project <path>", "Path to project root", ".")
  .option("--no-open", "Skip auto-opening browser")
  .option("--plugin-dir <path>", "Override knowledge base source directory")
  .parse(process.argv);

const opts = program.opts<{
  port: string;
  project: string;
  open: boolean;
  pluginDir?: string;
}>();

// ---------------------------------------------------------------------------
// Resolve paths
// ---------------------------------------------------------------------------
const projectPath = path.resolve(opts.project);
const aidoPath = path.join(projectPath, ".aid-o");
const aidoExists = fs.existsSync(aidoPath);

if (!aidoExists) {
  console.warn(
    `\n  Warning: .aid-o/ directory not found at ${aidoPath}` +
      "\n  The server will start but some features may not work.\n",
  );
}

// ---------------------------------------------------------------------------
// Set environment variables for the server
// ---------------------------------------------------------------------------
process.env.AID_PROJECT_PATH = aidoPath;
process.env.AID_GUI_PROJECT_ROOT = projectPath;

if (opts.pluginDir) {
  process.env.AID_PLUGIN_DIR = path.resolve(opts.pluginDir);
}

// ---------------------------------------------------------------------------
// Parse port
// ---------------------------------------------------------------------------
const port = Number(opts.port);
if (!Number.isFinite(port) || port < 1 || port > 65535) {
  console.error(`Error: Invalid port number "${opts.port}". Must be 1-65535.`);
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Start server
// ---------------------------------------------------------------------------
const { startServer } = await import("../server/index.ts");

await startServer({ port });

// ---------------------------------------------------------------------------
// Auto-open browser
// ---------------------------------------------------------------------------
if (opts.open !== false) {
  try {
    const openModule = await import("open");
    await openModule.default(`http://localhost:${port}`);
  } catch {
    // open package may not be available; non-fatal
  }
}

// ---------------------------------------------------------------------------
// Print startup banner
// ---------------------------------------------------------------------------
const statusMark = aidoExists ? "\u2713" : "\u26A0 not found";

console.log(`
  AID Dashboard
  \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
  URL:      http://localhost:${port}
  Project:  ${projectPath}
  .aid-o/:  ${aidoPath} ${statusMark}

  Press Ctrl+C to stop.
`);
