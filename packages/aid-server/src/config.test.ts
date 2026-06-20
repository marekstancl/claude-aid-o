/**
 * config.ts test suite (EPIC E-047-2_7, Step 5).
 *
 * Covers the Phase 2 additive cross-project surface (projectsRoot, hostRoot,
 * scanTtlMs, activityBufferSize) WITHOUT regressing the legacy single-project
 * `projectRoot` field that index.ts and ws/handler.ts still depend on.
 *
 * Every case that mutates process.env saves and restores the relevant keys so
 * state never leaks across tests.
 */

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import {
  loadConfig,
  DEFAULT_PROJECTS_ROOT,
  DEFAULT_SCAN_TTL_MS,
  DEFAULT_ACTIVITY_BUFFER_SIZE,
} from './config.js';

// Every env key this suite or loadConfig() reads — snapshotted and restored.
const TOUCHED_ENV_KEYS = [
  'AID_PORT',
  'AID_HOST',
  'AID_PROJECT_ROOT',
  'AID_PROJECTS_ROOT',
  'AID_HOST_ROOT',
  'AID_CORS_ORIGINS',
  'AID_SCAN_TTL_MS',
  'AID_ACTIVITY_BUFFER',
] as const;

let savedEnv: Record<string, string | undefined>;

beforeEach(() => {
  // Snapshot, then clear, so each test starts from a known empty baseline.
  savedEnv = {};
  for (const key of TOUCHED_ENV_KEYS) {
    savedEnv[key] = process.env[key];
    delete process.env[key];
  }
});

afterEach(() => {
  // Restore exactly what was there before (including "was unset").
  for (const key of TOUCHED_ENV_KEYS) {
    const prior = savedEnv[key];
    if (prior === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = prior;
    }
  }
});

// AC1 — port default + override
describe('AC1 — port', () => {
  it('defaults to 3911', () => {
    expect(loadConfig().port).toBe(3911);
  });

  it('honors AID_PORT override', () => {
    process.env.AID_PORT = '4321';
    expect(loadConfig().port).toBe(4321);
  });
});

// AC2 — projectsRoot default + override
describe('AC2 — projectsRoot', () => {
  it('defaults to /opt/eco/projects', () => {
    expect(loadConfig().projectsRoot).toBe('/opt/eco/projects');
    expect(loadConfig().projectsRoot).toBe(DEFAULT_PROJECTS_ROOT);
  });

  it('is overridden by AID_PROJECTS_ROOT (container compose sets /projects)', () => {
    process.env.AID_PROJECTS_ROOT = '/projects';
    expect(loadConfig().projectsRoot).toBe('/projects');
  });
});

// AC3 — hostRoot default + override
describe('AC3 — hostRoot', () => {
  it('defaults to /opt/eco/projects', () => {
    expect(loadConfig().hostRoot).toBe('/opt/eco/projects');
  });

  it('is overridden by AID_HOST_ROOT', () => {
    process.env.AID_HOST_ROOT = '/some/other/host/root';
    expect(loadConfig().hostRoot).toBe('/some/other/host/root');
  });
});

// AC4 — CORS parsing
describe('AC4 — corsOrigins', () => {
  it("returns the wildcard string '*' for AID_CORS_ORIGINS='*'", () => {
    process.env.AID_CORS_ORIGINS = '*';
    expect(loadConfig().corsOrigins).toBe('*');
  });

  it('splits and trims a comma-separated list', () => {
    process.env.AID_CORS_ORIGINS = ' https://a.test , https://b.test ';
    expect(loadConfig().corsOrigins).toEqual(['https://a.test', 'https://b.test']);
  });

  it('defaults to a localhost whitelist that includes http://localhost:3911', () => {
    const origins = loadConfig().corsOrigins;
    expect(Array.isArray(origins)).toBe(true);
    expect(origins).toContain('http://localhost:3911');
  });
});

// AC5 — scanTtlMs + WS timing fields
describe('AC5 — scanTtlMs and WebSocket timing', () => {
  it('scanTtlMs defaults to 600000', () => {
    expect(loadConfig().scanTtlMs).toBe(600_000);
    expect(loadConfig().scanTtlMs).toBe(DEFAULT_SCAN_TTL_MS);
  });

  it('scanTtlMs is overridden by AID_SCAN_TTL_MS', () => {
    process.env.AID_SCAN_TTL_MS = '120000';
    expect(loadConfig().scanTtlMs).toBe(120_000);
  });

  it('falls back to the default when AID_SCAN_TTL_MS is not a positive integer', () => {
    process.env.AID_SCAN_TTL_MS = 'not-a-number';
    expect(loadConfig().scanTtlMs).toBe(600_000);
  });

  it('wsHeartbeatInterval is 30000 and wsIdleTimeout is 90000', () => {
    const config = loadConfig();
    expect(config.wsHeartbeatInterval).toBe(30_000);
    expect(config.wsIdleTimeout).toBe(90_000);
  });
});

// activityBufferSize — §7.2 ring buffer
describe('activityBufferSize', () => {
  it('defaults to 500', () => {
    expect(loadConfig().activityBufferSize).toBe(500);
    expect(loadConfig().activityBufferSize).toBe(DEFAULT_ACTIVITY_BUFFER_SIZE);
  });

  it('is overridden by AID_ACTIVITY_BUFFER', () => {
    process.env.AID_ACTIVITY_BUFFER = '1000';
    expect(loadConfig().activityBufferSize).toBe(1000);
  });
});

// AC6 — backward-compat: projectRoot still present and populated
describe('AC6 — projectRoot backward-compat', () => {
  it('is present and non-empty so index.ts / ws-handler keep compiling', () => {
    const config = loadConfig();
    expect(typeof config.projectRoot).toBe('string');
    expect(config.projectRoot.length).toBeGreaterThan(0);
  });

  it('honors AID_PROJECT_ROOT override', () => {
    process.env.AID_PROJECT_ROOT = '/tmp/some-project';
    expect(loadConfig().projectRoot).toBe('/tmp/some-project');
  });

  it('falls back to process.cwd() when AID_PROJECT_ROOT is unset', () => {
    expect(loadConfig().projectRoot).toBe(process.cwd());
  });
});
