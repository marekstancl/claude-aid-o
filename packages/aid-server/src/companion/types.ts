/**
 * Companion module — Core types and interfaces.
 *
 * Defines the adapter contract (CompanionService) and all data structures
 * used by the AI Companion chat system. Any backend adapter (ai-sdk-provider,
 * CLI proxy, or stub) implements CompanionService so the rest of the system
 * is adapter-agnostic.
 */

// ---------------------------------------------------------------------------
// Adapter contract
// ---------------------------------------------------------------------------

/**
 * Adapter interface — every companion backend implements this.
 *
 * `send()` returns a complete response; `stream()` yields incremental chunks
 * suitable for SSE. `isAvailable()` is a cheap probe used by auto-detection
 * to decide which adapter to activate.
 */
export interface CompanionService {
  /** Human-readable adapter name, e.g. 'ai-sdk' | 'cli-proxy' | 'stub'. */
  readonly name: string;

  /** Send a message and receive the full response. */
  send(
    message: string,
    sessionId: string,
    systemPrompt?: string,
  ): Promise<CompanionResponse>;

  /** Stream a response as an async generator of chunks. */
  stream(
    message: string,
    sessionId: string,
    systemPrompt?: string,
  ): AsyncGenerator<CompanionChunk>;

  /** Quick check whether this adapter can serve requests right now. */
  isAvailable(): Promise<boolean>;
}

// ---------------------------------------------------------------------------
// Response types
// ---------------------------------------------------------------------------

/** Token-usage counters returned when the backend supports them. */
export interface TokenUsage {
  inputTokens: number;
  outputTokens: number;
}

/** Complete (non-streaming) response from the companion. */
export interface CompanionResponse {
  text: string;
  sessionId: string;
  model?: string;
  usage?: TokenUsage;
}

/**
 * A single chunk emitted during streaming.
 *
 * - `text`  — incremental text fragment.
 * - `done`  — final sentinel carrying session metadata.
 */
export type CompanionChunk =
  | { type: 'text'; text: string }
  | { type: 'done'; sessionId: string; model?: string; usage?: TokenUsage };

// ---------------------------------------------------------------------------
// Session & message types
// ---------------------------------------------------------------------------

/** A single message inside a companion session. */
export interface CompanionMessage {
  id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  timestamp: string;
  model?: string;
}

/**
 * Session metadata + conversation history.
 *
 * Persisted as a JSONL file — one line per message — with the first line
 * holding a system-role entry whose `content` is a JSON-encoded metadata
 * blob (id, projectId, title, dates).
 */
export interface CompanionSession {
  id: string;
  projectId: string;
  title: string;
  messages: CompanionMessage[];
  createdAt: string;
  updatedAt: string;
  /** Which adapter produced the responses in this session. */
  adapterUsed: string;
}

/**
 * Metadata stored in the first line of a session JSONL file.
 * The first line is a CompanionMessage with role 'system' and `content`
 * set to `JSON.stringify(SessionMetadata)`.
 */
export interface SessionMetadata {
  sessionId: string;
  projectId: string;
  title: string;
  createdAt: string;
  updatedAt: string;
  adapterUsed: string;
}
