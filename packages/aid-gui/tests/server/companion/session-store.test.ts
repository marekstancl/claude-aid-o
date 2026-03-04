/**
 * Unit tests for SessionStore (packages/aid-server/src/companion/session-store.ts).
 *
 * Each test uses a temporary directory isolated via os.tmpdir() + mkdtemp.
 * The SessionStore constructor accepts aidoPath, which is the root of the
 * .aid-o/ directory. The store writes under <aidoPath>/work/companion-sessions/.
 *
 * Coverage:
 *   createSession   — creates a JSONL file with correct metadata header
 *   getSession      — reads and parses a session by ID; returns null for missing IDs
 *   listSessions    — filters by projectId, returns metadata only (no messages), sorted newest-first
 *   appendMessage   — appends a message line and updates the metadata header
 *   getSessionTitle — derives title from first user message, truncates at 80 chars
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';

// Import from the actual source (aid-server)
import { SessionStore } from '../../../../aid-server/src/companion/session-store.ts';
import type { CompanionMessage } from '../../../../aid-server/src/companion/types.ts';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

let tmpDir: string;
let store: SessionStore;

beforeEach(async () => {
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'session-store-test-'));
  store = new SessionStore(tmpDir);
});

afterEach(async () => {
  await fs.rm(tmpDir, { recursive: true, force: true });
});

function makeMessage(overrides: Partial<CompanionMessage> = {}): CompanionMessage {
  return {
    id: 'msg-001',
    role: 'user',
    content: 'Hello world',
    timestamp: '2026-02-27T10:00:00.000Z',
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// createSession
// ---------------------------------------------------------------------------

describe('SessionStore — createSession', () => {
  it('returns a session object with the provided projectId and adapterUsed', async () => {
    const session = await store.createSession('proj-1', 'stub');

    expect(session.projectId).toBe('proj-1');
    expect(session.adapterUsed).toBe('stub');
  });

  it('returns a session with a non-empty UUID id', async () => {
    const session = await store.createSession('proj-1', 'stub');

    expect(typeof session.id).toBe('string');
    expect(session.id.length).toBeGreaterThan(0);
    // UUID v4 pattern
    expect(session.id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
  });

  it('returns a session with default title "New conversation"', async () => {
    const session = await store.createSession('proj-1', 'stub');
    expect(session.title).toBe('New conversation');
  });

  it('returns a session with an empty messages array', async () => {
    const session = await store.createSession('proj-1', 'stub');
    expect(session.messages).toEqual([]);
  });

  it('returns a session with createdAt and updatedAt ISO timestamps', async () => {
    const before = new Date().toISOString();
    const session = await store.createSession('proj-1', 'stub');
    const after = new Date().toISOString();

    expect(session.createdAt >= before).toBe(true);
    expect(session.createdAt <= after).toBe(true);
    expect(session.updatedAt >= before).toBe(true);
    expect(session.updatedAt <= after).toBe(true);
  });

  it('creates the sessions directory if it does not exist', async () => {
    const sessionsDir = path.join(tmpDir, 'work', 'companion-sessions');

    // Directory must not exist yet
    let dirExists = true;
    try { await fs.access(sessionsDir); } catch { dirExists = false; }
    expect(dirExists).toBe(false);

    await store.createSession('proj-1', 'stub');

    // Directory must now exist
    await expect(fs.access(sessionsDir)).resolves.toBeUndefined();
  });

  it('writes a JSONL file for the new session on disk', async () => {
    const session = await store.createSession('proj-1', 'stub');

    const filePath = path.join(tmpDir, 'work', 'companion-sessions', `${session.id}.jsonl`);
    await expect(fs.access(filePath)).resolves.toBeUndefined();
  });

  it('creates two sessions with different IDs', async () => {
    const s1 = await store.createSession('proj-1', 'stub');
    const s2 = await store.createSession('proj-1', 'stub');

    expect(s1.id).not.toBe(s2.id);
  });

  it('stores the adapterUsed field in the persisted metadata', async () => {
    const session = await store.createSession('proj-2', 'ai-sdk');

    const loaded = await store.getSession(session.id);
    expect(loaded?.adapterUsed).toBe('ai-sdk');
  });
});

// ---------------------------------------------------------------------------
// getSession
// ---------------------------------------------------------------------------

describe('SessionStore — getSession', () => {
  it('returns null for a session ID that does not exist', async () => {
    const result = await store.getSession('non-existent-id-xyz');
    expect(result).toBeNull();
  });

  it('returns the session created by createSession', async () => {
    const created = await store.createSession('proj-1', 'stub');
    const loaded = await store.getSession(created.id);

    expect(loaded).not.toBeNull();
    expect(loaded!.id).toBe(created.id);
    expect(loaded!.projectId).toBe('proj-1');
    expect(loaded!.adapterUsed).toBe('stub');
  });

  it('returns the session with an empty messages array when no messages appended', async () => {
    const created = await store.createSession('proj-1', 'stub');
    const loaded = await store.getSession(created.id);

    expect(loaded!.messages).toEqual([]);
  });

  it('returns appended messages after appendMessage is called', async () => {
    const session = await store.createSession('proj-1', 'stub');
    const msg = makeMessage({ content: 'Test message', role: 'user' });

    await store.appendMessage(session.id, msg);
    const loaded = await store.getSession(session.id);

    expect(loaded!.messages).toHaveLength(1);
    expect(loaded!.messages[0].content).toBe('Test message');
    expect(loaded!.messages[0].role).toBe('user');
  });

  it('returns messages in the order they were appended', async () => {
    const session = await store.createSession('proj-1', 'stub');

    await store.appendMessage(session.id, makeMessage({ id: 'm1', content: 'First', role: 'user' }));
    await store.appendMessage(session.id, makeMessage({ id: 'm2', content: 'Second', role: 'assistant' }));
    await store.appendMessage(session.id, makeMessage({ id: 'm3', content: 'Third', role: 'user' }));

    const loaded = await store.getSession(session.id);

    expect(loaded!.messages).toHaveLength(3);
    expect(loaded!.messages[0].id).toBe('m1');
    expect(loaded!.messages[1].id).toBe('m2');
    expect(loaded!.messages[2].id).toBe('m3');
  });

  it('does not include the system metadata message in the returned messages array', async () => {
    const session = await store.createSession('proj-1', 'stub');
    const loaded = await store.getSession(session.id);

    // No system messages should appear in the public messages array
    const systemMessages = loaded!.messages.filter((m) => m.role === 'system');
    expect(systemMessages).toHaveLength(0);
  });

  it('preserves the complete message content without truncation', async () => {
    const session = await store.createSession('proj-1', 'stub');
    const longContent = 'A'.repeat(2000);

    await store.appendMessage(session.id, makeMessage({ content: longContent }));
    const loaded = await store.getSession(session.id);

    expect(loaded!.messages[0].content).toBe(longContent);
  });
});

// ---------------------------------------------------------------------------
// listSessions
// ---------------------------------------------------------------------------

describe('SessionStore — listSessions', () => {
  it('returns an empty array when no sessions exist', async () => {
    const result = await store.listSessions('proj-1');
    expect(result).toEqual([]);
  });

  it('returns sessions belonging to the requested projectId', async () => {
    await store.createSession('proj-1', 'stub');
    await store.createSession('proj-1', 'stub');

    const result = await store.listSessions('proj-1');
    expect(result).toHaveLength(2);
    expect(result.every((s) => s.projectId === 'proj-1')).toBe(true);
  });

  it('does not return sessions for a different projectId', async () => {
    await store.createSession('proj-A', 'stub');
    await store.createSession('proj-B', 'stub');

    const result = await store.listSessions('proj-A');
    expect(result).toHaveLength(1);
    expect(result[0].projectId).toBe('proj-A');
  });

  it('returns metadata only — messages array is empty in each result', async () => {
    const session = await store.createSession('proj-1', 'stub');
    await store.appendMessage(session.id, makeMessage({ content: 'A message' }));

    const result = await store.listSessions('proj-1');

    expect(result).toHaveLength(1);
    expect(result[0].messages).toEqual([]);
  });

  it('returns an empty array when the project has no matching sessions', async () => {
    await store.createSession('proj-X', 'stub');

    const result = await store.listSessions('proj-not-exist');
    expect(result).toHaveLength(0);
  });

  it('sorts sessions newest-first by updatedAt', async () => {
    // Create session A, then append a message to B to make it newer
    const sA = await store.createSession('proj-1', 'stub');

    // Small delay so timestamps differ
    await new Promise((resolve) => setTimeout(resolve, 5));

    const sB = await store.createSession('proj-1', 'stub');

    // Append a message to B to ensure its updatedAt is more recent
    await store.appendMessage(sB.id, makeMessage({ content: 'Message in B' }));

    const result = await store.listSessions('proj-1');

    expect(result).toHaveLength(2);
    // B (newer updatedAt) must come first
    const updatedAtFirst = new Date(result[0].updatedAt).getTime();
    const updatedAtSecond = new Date(result[1].updatedAt).getTime();
    expect(updatedAtFirst).toBeGreaterThanOrEqual(updatedAtSecond);

    // Specifically, sA should be second (older)
    expect(result[1].id).toBe(sA.id);
  });
});

// ---------------------------------------------------------------------------
// appendMessage
// ---------------------------------------------------------------------------

describe('SessionStore — appendMessage', () => {
  it('increments the message count after appending', async () => {
    const session = await store.createSession('proj-1', 'stub');

    await store.appendMessage(session.id, makeMessage({ id: 'a', content: 'First' }));
    await store.appendMessage(session.id, makeMessage({ id: 'b', content: 'Second' }));

    const loaded = await store.getSession(session.id);
    expect(loaded!.messages).toHaveLength(2);
  });

  it('updates updatedAt timestamp after appending a message', async () => {
    const session = await store.createSession('proj-1', 'stub');
    const createdUpdatedAt = session.updatedAt;

    // Small pause so the timestamp can advance
    await new Promise((resolve) => setTimeout(resolve, 5));

    await store.appendMessage(session.id, makeMessage());

    const loaded = await store.getSession(session.id);
    expect(loaded!.updatedAt >= createdUpdatedAt).toBe(true);
  });

  it('updates the session title from "New conversation" when first user message is appended', async () => {
    const session = await store.createSession('proj-1', 'stub');
    expect(session.title).toBe('New conversation');

    await store.appendMessage(session.id, makeMessage({ role: 'user', content: 'What is the pipeline status?' }));

    const loaded = await store.getSession(session.id);
    expect(loaded!.title).toBe('What is the pipeline status?');
  });

  it('does not overwrite the title when a second user message is appended', async () => {
    const session = await store.createSession('proj-1', 'stub');

    await store.appendMessage(session.id, makeMessage({ id: 'm1', role: 'user', content: 'First question' }));
    await store.appendMessage(session.id, makeMessage({ id: 'm2', role: 'user', content: 'Second question' }));

    const loaded = await store.getSession(session.id);
    // Title should still reflect the first user message
    expect(loaded!.title).toBe('First question');
  });

  it('preserves all message fields (id, role, content, timestamp)', async () => {
    const session = await store.createSession('proj-1', 'stub');
    const msg: CompanionMessage = {
      id: 'msg-uuid-123',
      role: 'assistant',
      content: 'Here is my response.',
      timestamp: '2026-02-27T12:00:00.000Z',
      model: 'claude-sonnet-4-5',
    };

    await store.appendMessage(session.id, msg);

    const loaded = await store.getSession(session.id);
    expect(loaded!.messages[0]).toEqual(msg);
  });

  it('appends user and assistant messages in correct order', async () => {
    const session = await store.createSession('proj-1', 'stub');

    await store.appendMessage(session.id, makeMessage({ id: 'u1', role: 'user', content: 'Hello' }));
    await store.appendMessage(session.id, makeMessage({ id: 'a1', role: 'assistant', content: 'Hi there' }));

    const loaded = await store.getSession(session.id);
    expect(loaded!.messages[0].id).toBe('u1');
    expect(loaded!.messages[1].id).toBe('a1');
  });
});

// ---------------------------------------------------------------------------
// getSessionTitle (pure logic)
// ---------------------------------------------------------------------------

describe('SessionStore — getSessionTitle', () => {
  it('returns "New conversation" when there are no messages', () => {
    const title = store.getSessionTitle([]);
    expect(title).toBe('New conversation');
  });

  it('returns "New conversation" when there are only assistant messages', () => {
    const msgs = [makeMessage({ role: 'assistant', content: 'Hello' })];
    const title = store.getSessionTitle(msgs);
    expect(title).toBe('New conversation');
  });

  it('returns the first user message as the title', () => {
    const msgs = [
      makeMessage({ role: 'assistant', content: 'Intro' }),
      makeMessage({ role: 'user', content: 'What is the project health?' }),
    ];
    const title = store.getSessionTitle(msgs);
    expect(title).toBe('What is the project health?');
  });

  it('trims leading and trailing whitespace from the title', () => {
    const msgs = [makeMessage({ role: 'user', content: '  trimmed title  ' })];
    const title = store.getSessionTitle(msgs);
    expect(title).toBe('trimmed title');
  });

  it('collapses internal whitespace in the title', () => {
    const msgs = [makeMessage({ role: 'user', content: 'word1   word2\t\tword3' })];
    const title = store.getSessionTitle(msgs);
    expect(title).toBe('word1 word2 word3');
  });

  it('returns the message verbatim when it is within 80 characters', () => {
    const shortContent = 'A'.repeat(80);
    const msgs = [makeMessage({ role: 'user', content: shortContent })];
    const title = store.getSessionTitle(msgs);
    expect(title).toBe(shortContent);
    expect(title.length).toBe(80);
  });

  it('truncates to 79 characters plus ellipsis when message exceeds 80 characters', () => {
    const longContent = 'A'.repeat(100);
    const msgs = [makeMessage({ role: 'user', content: longContent })];
    const title = store.getSessionTitle(msgs);
    // 79 'A's + the Unicode ellipsis character
    expect(title.length).toBe(80);
    expect(title.endsWith('\u2026')).toBe(true);
    expect(title.startsWith('AAAA')).toBe(true);
  });

  it('does not truncate a message of exactly 80 characters', () => {
    const content = 'X'.repeat(80);
    const msgs = [makeMessage({ role: 'user', content })];
    const title = store.getSessionTitle(msgs);
    // No truncation — exactly at limit
    expect(title).toBe(content);
    expect(title.includes('\u2026')).toBe(false);
  });
});
