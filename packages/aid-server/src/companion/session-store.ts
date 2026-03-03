/**
 * Session store — JSONL-based persistence for companion sessions.
 *
 * Each session is stored as a single `.jsonl` file under
 * `<aidoPath>/work/companion-sessions/<sessionId>.jsonl`.
 *
 * File format:
 *   Line 1  — system message whose `content` is JSON-encoded SessionMetadata
 *   Line 2+ — user / assistant messages appended over time
 *
 * JSONL is chosen because it is append-friendly: new messages are written
 * with a single `appendFile` call — no need to read-modify-write the
 * entire conversation.
 */

import { randomUUID } from 'node:crypto';
import {
  appendFile,
  mkdir,
  readFile,
  readdir,
  rename,
  unlink,
  writeFile,
} from 'node:fs/promises';
import { join } from 'node:path';

import type {
  CompanionMessage,
  CompanionSession,
  SessionMetadata,
} from './types.js';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const SESSIONS_DIR = 'work/companion-sessions';
const ARCHIVE_DIR = 'work/companion-sessions/archive';
const MAX_TITLE_LENGTH = 80;

// ---------------------------------------------------------------------------
// SessionStore
// ---------------------------------------------------------------------------

export class SessionStore {
  private readonly sessionsDir: string;
  private readonly archiveDir: string;

  constructor(aidoPath: string) {
    this.sessionsDir = join(aidoPath, SESSIONS_DIR);
    this.archiveDir = join(aidoPath, ARCHIVE_DIR);
  }

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /**
   * Create a new session, writing the initial metadata line to disk.
   *
   * @returns The newly created session (with an empty `messages` array).
   */
  async createSession(
    projectId: string,
    adapterUsed: string,
  ): Promise<CompanionSession> {
    await this.ensureDir();

    const now = new Date().toISOString();
    const id = randomUUID();

    const metadata: SessionMetadata = {
      sessionId: id,
      projectId,
      title: 'New conversation',
      createdAt: now,
      updatedAt: now,
      adapterUsed,
    };

    const metaMessage: CompanionMessage = {
      id: randomUUID(),
      role: 'system',
      content: JSON.stringify(metadata),
      timestamp: now,
    };

    const filePath = this.sessionFile(id);
    await writeFile(filePath, JSON.stringify(metaMessage) + '\n', 'utf-8');

    return {
      id,
      projectId,
      title: metadata.title,
      messages: [],
      createdAt: now,
      updatedAt: now,
      adapterUsed,
    };
  }

  /**
   * Load a session from disk by its ID.
   *
   * @returns The full session with messages, or `null` if not found or if
   *          `sessionId` is not a valid UUID (treat as not-found, not an error).
   */
  async getSession(sessionId: string): Promise<CompanionSession | null> {
    // Non-UUID IDs cannot correspond to any file — return null immediately.
    if (!this.isValidSessionId(sessionId)) return null;

    const lines = await this.readLines(sessionId);
    if (lines.length === 0) return null;

    return this.parseSession(lines);
  }

  /**
   * List all sessions for a given project (metadata only, no messages).
   *
   * Sessions are sorted newest-first by `updatedAt`.
   */
  async listSessions(projectId: string): Promise<CompanionSession[]> {
    await this.ensureDir();

    let entries: string[];
    try {
      entries = await readdir(this.sessionsDir);
    } catch {
      return [];
    }

    const sessions: CompanionSession[] = [];

    for (const entry of entries) {
      if (!entry.endsWith('.jsonl')) continue;

      const sessionId = entry.replace(/\.jsonl$/, '');
      // Read only the first line (metadata) to avoid loading all messages.
      const metaLine = await this.readFirstLine(sessionId);
      if (!metaLine) continue;

      const session = this.parseSessionFromMeta(metaLine);
      if (session && session.projectId === projectId) {
        sessions.push(session);
      }
    }

    // Newest first
    sessions.sort(
      (a, b) =>
        new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime(),
    );

    return sessions;
  }

  /**
   * Append a message to an existing session and update metadata timestamps
   * and title (derived from the first user message).
   */
  async appendMessage(
    sessionId: string,
    message: CompanionMessage,
  ): Promise<void> {
    // Throw on invalid IDs for write operations — this is a programming error.
    this.assertValidSessionId(sessionId);
    const filePath = this.sessionFile(sessionId);

    // Append the message line
    await appendFile(filePath, JSON.stringify(message) + '\n', 'utf-8');

    // Update metadata (title and updatedAt) — rewrite only line 1
    await this.updateMetadata(sessionId, message);
  }

  /**
   * Derive a session title from the conversation messages.
   *
   * Uses the first user message, truncated to `MAX_TITLE_LENGTH` characters.
   */
  getSessionTitle(messages: CompanionMessage[]): string {
    const firstUser = messages.find((m) => m.role === 'user');
    if (!firstUser) return 'New conversation';

    const raw = firstUser.content.trim().replace(/\s+/g, ' ');
    if (raw.length <= MAX_TITLE_LENGTH) return raw;
    return raw.slice(0, MAX_TITLE_LENGTH - 1) + '\u2026';
  }

  /**
   * Delete a session file permanently.
   *
   * @returns `true` if the session was deleted, `false` if not found.
   */
  async deleteSession(sessionId: string): Promise<boolean> {
    if (!this.isValidSessionId(sessionId)) return false;
    const filePath = this.sessionFile(sessionId);
    try {
      await unlink(filePath);
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Archive a session by moving its file to the archive sub-directory.
   *
   * @returns `true` if the session was archived, `false` if not found.
   */
  async archiveSession(sessionId: string): Promise<boolean> {
    if (!this.isValidSessionId(sessionId)) return false;
    const src = this.sessionFile(sessionId);
    await mkdir(this.archiveDir, { recursive: true });
    const dst = join(this.archiveDir, `${sessionId}.jsonl`);
    try {
      await rename(src, dst);
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Rename a session by updating its metadata title.
   *
   * @returns The updated session title, or `null` if the session was not found.
   */
  async renameSession(sessionId: string, newTitle: string): Promise<string | null> {
    if (!this.isValidSessionId(sessionId)) return null;
    const filePath = this.sessionFile(sessionId);
    let raw: string;
    try {
      raw = await readFile(filePath, 'utf-8');
    } catch {
      return null;
    }

    const allLines = raw.split('\n').filter((line) => line.trim().length > 0);
    if (allLines.length === 0) return null;

    let metaMsg: CompanionMessage;
    try {
      metaMsg = JSON.parse(allLines[0]) as CompanionMessage;
    } catch {
      return null;
    }

    let metadata: SessionMetadata;
    try {
      metadata = JSON.parse(metaMsg.content) as SessionMetadata;
    } catch {
      return null;
    }

    const trimmed = newTitle.trim().replace(/\s+/g, ' ');
    metadata.title = trimmed.length <= MAX_TITLE_LENGTH
      ? trimmed
      : trimmed.slice(0, MAX_TITLE_LENGTH - 1) + '\u2026';
    metadata.updatedAt = new Date().toISOString();

    metaMsg.content = JSON.stringify(metadata);
    allLines[0] = JSON.stringify(metaMsg);

    await writeFile(filePath, allLines.join('\n') + '\n', 'utf-8');
    return metadata.title;
  }

  // -----------------------------------------------------------------------
  // Internals
  // -----------------------------------------------------------------------

  /** UUID v4 pattern — the only acceptable session ID format. */
  private static readonly UUID_RE =
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

  /**
   * Guard: throws if `sessionId` is not a UUID v4.
   * Only call this before write operations (appendMessage, createSession paths).
   * Read operations (getSession, readLines) return null rather than throwing
   * so that callers can treat an unknown or invalid ID as "not found".
   */
  private assertValidSessionId(sessionId: string): void {
    if (!SessionStore.UUID_RE.test(sessionId)) {
      throw new Error(`Invalid sessionId: "${sessionId}". Must be a UUID v4.`);
    }
  }

  /**
   * Returns `false` (and does not throw) when the ID fails the UUID check.
   * Used by read-only paths so they can return null instead of propagating
   * an error to the caller.
   */
  private isValidSessionId(sessionId: string): boolean {
    return SessionStore.UUID_RE.test(sessionId);
  }

  private sessionFile(sessionId: string): string {
    // Note: callers are responsible for validation.
    // Write paths call assertValidSessionId first.
    // Read paths call isValidSessionId and short-circuit to null.
    return join(this.sessionsDir, `${sessionId}.jsonl`);
  }

  private async ensureDir(): Promise<void> {
    await mkdir(this.sessionsDir, { recursive: true });
  }

  /**
   * Read only the first line of a session file (the metadata line).
   * Used by `listSessions()` to avoid loading full conversation history.
   * Returns null if the file is absent or unreadable.
   */
  private async readFirstLine(sessionId: string): Promise<CompanionMessage | null> {
    const filePath = join(this.sessionsDir, `${sessionId}.jsonl`);
    let raw: string;
    try {
      raw = await readFile(filePath, 'utf-8');
    } catch {
      return null;
    }
    const firstLine = raw.split('\n').find((l) => l.trim().length > 0);
    if (!firstLine) return null;
    try {
      return JSON.parse(firstLine) as CompanionMessage;
    } catch {
      return null;
    }
  }

  /**
   * Build a metadata-only `CompanionSession` (messages: []) from a single
   * metadata line. Used by `listSessions()` to avoid reading all messages.
   */
  private parseSessionFromMeta(metaLine: CompanionMessage): CompanionSession | null {
    if (metaLine.role !== 'system') return null;
    let metadata: SessionMetadata;
    try {
      metadata = JSON.parse(metaLine.content) as SessionMetadata;
    } catch {
      return null;
    }
    return {
      id: metadata.sessionId,
      projectId: metadata.projectId,
      title: metadata.title,
      messages: [],
      createdAt: metadata.createdAt,
      updatedAt: metadata.updatedAt,
      adapterUsed: metadata.adapterUsed,
    };
  }

  /** Read and parse all lines from a session file. */
  private async readLines(sessionId: string): Promise<CompanionMessage[]> {
    const filePath = this.sessionFile(sessionId);
    let raw: string;
    try {
      raw = await readFile(filePath, 'utf-8');
    } catch {
      return [];
    }

    return raw
      .split('\n')
      .filter((line) => line.trim().length > 0)
      .map((line) => {
        try {
          return JSON.parse(line) as CompanionMessage;
        } catch {
          return null;
        }
      })
      .filter((msg): msg is CompanionMessage => msg !== null);
  }

  /**
   * Parse a list of message lines into a CompanionSession.
   *
   * The first line (system message) encodes session metadata in its
   * `content` field as a JSON string.
   */
  private parseSession(lines: CompanionMessage[]): CompanionSession | null {
    const metaLine = lines[0];
    if (!metaLine || metaLine.role !== 'system') return null;

    let metadata: SessionMetadata;
    try {
      metadata = JSON.parse(metaLine.content) as SessionMetadata;
    } catch {
      return null;
    }

    // All non-system messages are conversation content
    const messages = lines.filter((m) => m.role !== 'system');

    return {
      id: metadata.sessionId,
      projectId: metadata.projectId,
      title: metadata.title,
      messages,
      createdAt: metadata.createdAt,
      updatedAt: metadata.updatedAt,
      adapterUsed: metadata.adapterUsed,
    };
  }

  /**
   * Update the metadata line (line 1) of a session file.
   *
   * This rewrites the entire file, but only to update the first line.
   * The operation is safe because we read-then-write atomically with
   * the full content.
   */
  private async updateMetadata(
    sessionId: string,
    latestMessage: CompanionMessage,
  ): Promise<void> {
    const filePath = this.sessionFile(sessionId);
    let raw: string;
    try {
      raw = await readFile(filePath, 'utf-8');
    } catch {
      return;
    }

    const allLines = raw.split('\n').filter((line) => line.trim().length > 0);
    if (allLines.length === 0) return;

    // Parse existing metadata
    let metaMsg: CompanionMessage;
    try {
      metaMsg = JSON.parse(allLines[0]) as CompanionMessage;
    } catch {
      return;
    }

    let metadata: SessionMetadata;
    try {
      metadata = JSON.parse(metaMsg.content) as SessionMetadata;
    } catch {
      return;
    }

    // Update timestamp
    metadata.updatedAt = new Date().toISOString();

    // Update title if this is the first user message
    if (latestMessage.role === 'user' && metadata.title === 'New conversation') {
      const allMessages = allLines.slice(1).map((line) => {
        try {
          return JSON.parse(line) as CompanionMessage;
        } catch {
          return null;
        }
      }).filter((m): m is CompanionMessage => m !== null);

      metadata.title = this.getSessionTitle(allMessages);
    }

    // Rewrite metadata line
    metaMsg.content = JSON.stringify(metadata);
    allLines[0] = JSON.stringify(metaMsg);

    await writeFile(filePath, allLines.join('\n') + '\n', 'utf-8');
  }
}
