/**
 * Auto-detect — Adapter priority detection.
 *
 * Probes for available companion backends in priority order:
 *   1. ai-sdk-provider  (best: native streaming, tool-use, structured output)
 *   2. CLI proxy         (`claude` CLI present on PATH)
 *   3. Stub              (always available — returns informational messages)
 *
 * The first adapter whose `isAvailable()` returns `true` wins.
 * If detection receives an explicit config override, it respects that instead.
 */

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

import type {
  CompanionChunk,
  CompanionResponse,
  CompanionService,
} from './types.js';
import { AiSdkAdapter } from './ai-sdk-adapter.js';

const execFileAsync = promisify(execFile);

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

export interface DetectConfig {
  /** Force a specific adapter instead of auto-detecting. */
  forceAdapter?: 'ai-sdk' | 'cli-proxy' | 'stub';
}

// ---------------------------------------------------------------------------
// Stub adapter — always available
// ---------------------------------------------------------------------------

const STUB_MESSAGE =
  'AI Companion is not configured. ' +
  'Install ai-sdk-provider-claude-code or ensure the claude CLI is available on your PATH.';

/**
 * Stub adapter that returns canned responses.
 * Used when no real backend is detected so the system still boots and
 * the user gets a helpful message instead of a crash.
 */
export class StubAdapter implements CompanionService {
  readonly name = 'stub' as const;

  async send(
    _message: string,
    sessionId: string,
  ): Promise<CompanionResponse> {
    return {
      text: STUB_MESSAGE,
      sessionId,
    };
  }

  async *stream(
    _message: string,
    sessionId: string,
  ): AsyncGenerator<CompanionChunk> {
    yield { type: 'text', text: STUB_MESSAGE };
    yield { type: 'done', sessionId };
  }

  async isAvailable(): Promise<boolean> {
    return true;
  }
}

// ---------------------------------------------------------------------------
// Detection helpers
// ---------------------------------------------------------------------------

/**
 * Check whether the `claude` CLI binary is available on PATH.
 */
async function probeCli(): Promise<boolean> {
  try {
    // `which` on Linux/macOS, `where` on Windows — but the server targets
    // Linux/macOS (see tsconfig target ES2022, platform info in env).
    await execFileAsync('which', ['claude']);
    return true;
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Placeholder adapters for CLI
// ---------------------------------------------------------------------------

/**
 * Placeholder for the CLI-proxy adapter.
 *
 * The full implementation lives in a future step; this placeholder simply
 * reports availability so auto-detection can prefer it when the CLI is
 * present.
 */
class CliProxyPlaceholder implements CompanionService {
  readonly name = 'cli-proxy' as const;

  async send(
    _message: string,
    sessionId: string,
  ): Promise<CompanionResponse> {
    return {
      text: 'CLI proxy adapter detected but not yet implemented. This is a placeholder.',
      sessionId,
    };
  }

  async *stream(
    _message: string,
    sessionId: string,
  ): AsyncGenerator<CompanionChunk> {
    yield {
      type: 'text',
      text: 'CLI proxy adapter detected but not yet implemented. This is a placeholder.',
    };
    yield { type: 'done', sessionId };
  }

  async isAvailable(): Promise<boolean> {
    return probeCli();
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Detect the best available companion adapter.
 *
 * Probes in priority order and returns the first one that reports
 * `isAvailable() === true`.  If `config.forceAdapter` is set, skips
 * probing and returns that adapter directly.
 */
export async function detectAdapter(
  config?: DetectConfig,
): Promise<CompanionService> {
  // Forced override — skip probing
  if (config?.forceAdapter) {
    const forced = adapterByName(config.forceAdapter);
    console.log(`[companion] Adapter forced: ${forced.name}`);
    return forced;
  }

  // Priority-ordered candidate list
  const candidates: CompanionService[] = [
    new AiSdkAdapter(),
    new CliProxyPlaceholder(),
    new StubAdapter(),
  ];

  const t0 = Date.now();
  for (const candidate of candidates) {
    try {
      const ok = await candidate.isAvailable();
      if (ok) {
        console.log(`[companion] Auto-detected adapter: ${candidate.name} (${Date.now() - t0}ms)`);
        return candidate;
      }
    } catch {
      // Probe failed — skip this candidate
    }
  }

  // Should never reach here because StubAdapter.isAvailable() always
  // returns true, but guard defensively.
  console.log('[companion] No adapter detected, falling back to stub');
  return new StubAdapter();
}

/** Instantiate an adapter by its well-known name. */
function adapterByName(name: 'ai-sdk' | 'cli-proxy' | 'stub'): CompanionService {
  switch (name) {
    case 'ai-sdk':
      return new AiSdkAdapter();
    case 'cli-proxy':
      return new CliProxyPlaceholder();
    case 'stub':
      return new StubAdapter();
  }
}
