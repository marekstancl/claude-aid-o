/** Server configuration from environment variables. */

import { DEFAULT_HOST_ROOT } from './services/pathmap.js';

/**
 * Default cross-project discovery root.
 *
 * Host-native dev resolves projects under `/opt/eco/projects`; the container
 * compose overrides this to `/projects` via `AID_PROJECTS_ROOT`. Reuses the
 * pathmap default so the two stay in lockstep.
 */
export const DEFAULT_PROJECTS_ROOT = DEFAULT_HOST_ROOT;

/** Default 10-minute TTL for the project-scan safety sweep (spec §7.2). */
export const DEFAULT_SCAN_TTL_MS = 600_000;

/** Default size of the merged-activity ring buffer (spec §7.2). */
export const DEFAULT_ACTIVITY_BUFFER_SIZE = 500;

export interface ServerConfig {
  port: number;
  host: string;
  /**
   * Root directory of a SINGLE project (where its `.aid-o/` lives).
   *
   * @deprecated Legacy single-project bootstrap field. Read by `index.ts` and
   * `ws/handler.ts` (e.g. `new FsReader(config.projectRoot)` and
   * `join(config.projectRoot, '.aid-o')`). It will be removed once the server
   * bootstrap is rewired to multi-project discovery via ProjectScanner (a later
   * route-rewiring phase). Use {@link ServerConfig.projectsRoot} for
   * cross-project discovery.
   */
  projectRoot: string;
  /**
   * Cross-project discovery root — the directory whose immediate children are
   * candidate projects. Host-native dev defaults to `/opt/eco/projects`; the
   * container compose sets `/projects`.
   */
  projectsRoot: string;
  /**
   * Host-side equivalent of {@link ServerConfig.projectsRoot}, used by the
   * pathmap factory (`createPathMap({ projectsRoot, hostRoot })`) to translate
   * container paths back to host paths in emitted links/evidence.
   */
  hostRoot: string;
  /**
   * Allowed CORS origins.
   * - `'*'` (string) enables wildcard CORS (any origin).
   * - `string[]` enables a whitelist of specific origins.
   */
  corsOrigins: string | string[];
  /** WebSocket heartbeat interval in ms. */
  wsHeartbeatInterval: number;
  /** WebSocket idle timeout in ms. */
  wsIdleTimeout: number;
  /** TTL for the project-scan safety sweep / re-discover cadence, in ms. */
  scanTtlMs: number;
  /** Size of the merged-activity ring buffer (number of retained events). */
  activityBufferSize: number;
}

/** Parse the AID_CORS_ORIGINS env var into a wildcard string or origin array. */
function parseCorsOrigins(raw: string | undefined): string | string[] {
  const DEFAULT_ORIGINS = 'http://localhost:5173,http://localhost:3000,http://localhost:3911';
  const value = (raw ?? DEFAULT_ORIGINS).trim();

  // Wildcard: return the string '*' so the cors package enables any-origin.
  if (value === '*') {
    return '*';
  }

  // Comma-separated whitelist: split, trim, and filter empty entries.
  return value.split(',').map((o) => o.trim()).filter(Boolean);
}

/**
 * Parse a positive-integer env var, falling back to `fallback` when the var is
 * unset, empty, or not a finite positive integer.
 */
function parsePositiveInt(raw: string | undefined, fallback: number): number {
  const value = parseInt(raw ?? '', 10);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

export function loadConfig(): ServerConfig {
  return {
    port: parseInt(process.env.AID_PORT ?? '3911', 10),
    host: process.env.AID_HOST ?? '127.0.0.1',
    // Backward-compat single-project field — kept until the multi-project
    // bootstrap rewire (see ServerConfig.projectRoot @deprecated note).
    projectRoot: process.env.AID_PROJECT_ROOT ?? process.cwd(),
    projectsRoot: process.env.AID_PROJECTS_ROOT ?? DEFAULT_PROJECTS_ROOT,
    hostRoot: process.env.AID_HOST_ROOT ?? DEFAULT_HOST_ROOT,
    corsOrigins: parseCorsOrigins(process.env.AID_CORS_ORIGINS),
    wsHeartbeatInterval: 30_000,
    wsIdleTimeout: 90_000,
    scanTtlMs: parsePositiveInt(process.env.AID_SCAN_TTL_MS, DEFAULT_SCAN_TTL_MS),
    activityBufferSize: parsePositiveInt(
      process.env.AID_ACTIVITY_BUFFER,
      DEFAULT_ACTIVITY_BUFFER_SIZE,
    ),
  };
}
