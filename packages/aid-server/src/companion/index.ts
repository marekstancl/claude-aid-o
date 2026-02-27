/**
 * Companion module — barrel export and factory.
 *
 * Usage:
 *
 * ```ts
 * import { createCompanionService } from './companion/index.js';
 *
 * const { service, sessionStore } = await createCompanionService(aidoPath);
 * const session = await sessionStore.createSession(projectId, service.name);
 * const response = await service.send('Hello', session.id);
 * ```
 */

// Re-export types
export type {
  CompanionChunk,
  CompanionMessage,
  CompanionResponse,
  CompanionService,
  CompanionSession,
  SessionMetadata,
  TokenUsage,
} from './types.js';

// Re-export session store
export { SessionStore } from './session-store.js';

// Re-export adapters
export { AiSdkAdapter } from './ai-sdk-adapter.js';
export { detectAdapter, StubAdapter } from './auto-detect.js';
export type { DetectConfig } from './auto-detect.js';

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

import type { CompanionService } from './types.js';
import type { DetectConfig } from './auto-detect.js';
import { detectAdapter } from './auto-detect.js';
import { SessionStore } from './session-store.js';

export interface CompanionBundle {
  service: CompanionService;
  sessionStore: SessionStore;
}

/**
 * Create a fully-wired companion service.
 *
 * 1. Builds a `SessionStore` rooted at `aidoPath`.
 * 2. Runs adapter auto-detection (or honours `config.forceAdapter`).
 * 3. Returns both so the caller can use them together.
 *
 * @param aidoPath  Absolute path to the `.aid-o/` directory.
 * @param config    Optional detection config (e.g. force a specific adapter).
 */
export async function createCompanionService(
  aidoPath: string,
  config?: DetectConfig,
): Promise<CompanionBundle> {
  const sessionStore = new SessionStore(aidoPath);
  const service = await detectAdapter(config);

  return { service, sessionStore };
}
