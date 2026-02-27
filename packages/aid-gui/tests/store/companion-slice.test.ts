/**
 * Unit tests for CompanionSlice (packages/aid-gui/src/store.ts).
 *
 * Tests the Zustand store slice that manages AI Companion chat state:
 *   companionOpen, companionSessions, companionCurrentSession,
 *   companionStreaming, companionStreamingText, companionStatus, companionError
 *
 * Actions covered:
 *   setCompanionOpen, toggleCompanion
 *   setCompanionSessions, setCompanionCurrentSession
 *   setCompanionStreaming, appendCompanionStreamText, resetCompanionStream
 *   addCompanionMessage
 *   setCompanionStatus, setCompanionError
 *
 * All tests reset the store to its initial state before running, preventing
 * state leaks from the singleton Zustand store.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { useStore } from '../../src/store.ts';
import type {
  CompanionMessage,
  CompanionSessionSummary,
  CompanionSession,
  CompanionStatus,
} from '../../src/types/api.ts';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function resetStore(): void {
  useStore.setState(useStore.getInitialState());
}

function makeMessage(overrides: Partial<CompanionMessage> = {}): CompanionMessage {
  return {
    id: 'msg-001',
    role: 'user',
    content: 'Hello',
    timestamp: '2026-02-27T10:00:00.000Z',
    ...overrides,
  };
}

function makeSession(overrides: Partial<CompanionSession> = {}): CompanionSession {
  return {
    id: 'sess-001',
    projectId: 'proj-1',
    title: 'Test session',
    messages: [],
    createdAt: '2026-02-27T10:00:00.000Z',
    updatedAt: '2026-02-27T10:00:00.000Z',
    adapterUsed: 'stub',
    ...overrides,
  };
}

function makeSessionSummary(overrides: Partial<CompanionSessionSummary> = {}): CompanionSessionSummary {
  return {
    id: 'sess-001',
    title: 'Summary session',
    updatedAt: '2026-02-27T10:00:00.000Z',
    createdAt: '2026-02-27T10:00:00.000Z',
    messageCount: 0,
    adapterUsed: 'stub',
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

beforeEach(() => {
  resetStore();
});

// ---------------------------------------------------------------------------
// Initial state
// ---------------------------------------------------------------------------

describe('CompanionSlice — initial state', () => {
  it('companionOpen starts as false', () => {
    expect(useStore.getState().companionOpen).toBe(false);
  });

  it('companionSessions starts as an empty array', () => {
    expect(useStore.getState().companionSessions).toEqual([]);
  });

  it('companionCurrentSession starts as null', () => {
    expect(useStore.getState().companionCurrentSession).toBeNull();
  });

  it('companionStreaming starts as false', () => {
    expect(useStore.getState().companionStreaming).toBe(false);
  });

  it('companionStreamingText starts as an empty string', () => {
    expect(useStore.getState().companionStreamingText).toBe('');
  });

  it('companionStatus starts as null', () => {
    expect(useStore.getState().companionStatus).toBeNull();
  });

  it('companionError starts as null', () => {
    expect(useStore.getState().companionError).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// setCompanionOpen
// ---------------------------------------------------------------------------

describe('CompanionSlice — setCompanionOpen', () => {
  it('sets companionOpen to true', () => {
    useStore.getState().setCompanionOpen(true);
    expect(useStore.getState().companionOpen).toBe(true);
  });

  it('sets companionOpen to false', () => {
    useStore.getState().setCompanionOpen(true);
    useStore.getState().setCompanionOpen(false);
    expect(useStore.getState().companionOpen).toBe(false);
  });

  it('does not affect other companion state', () => {
    useStore.getState().setCompanionStreaming(true);
    useStore.getState().setCompanionOpen(true);

    // streaming must be unchanged
    expect(useStore.getState().companionStreaming).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// toggleCompanion
// ---------------------------------------------------------------------------

describe('CompanionSlice — toggleCompanion', () => {
  it('toggles companionOpen from false to true', () => {
    expect(useStore.getState().companionOpen).toBe(false);
    useStore.getState().toggleCompanion();
    expect(useStore.getState().companionOpen).toBe(true);
  });

  it('toggles companionOpen from true to false', () => {
    useStore.getState().setCompanionOpen(true);
    useStore.getState().toggleCompanion();
    expect(useStore.getState().companionOpen).toBe(false);
  });

  it('toggles back to original value on second call', () => {
    const initial = useStore.getState().companionOpen;
    useStore.getState().toggleCompanion();
    useStore.getState().toggleCompanion();
    expect(useStore.getState().companionOpen).toBe(initial);
  });
});

// ---------------------------------------------------------------------------
// setCompanionSessions
// ---------------------------------------------------------------------------

describe('CompanionSlice — setCompanionSessions', () => {
  it('stores the provided sessions array', () => {
    const sessions = [
      makeSessionSummary({ id: 'sess-1', title: 'Session 1' }),
      makeSessionSummary({ id: 'sess-2', title: 'Session 2' }),
    ];

    useStore.getState().setCompanionSessions(sessions);

    const stored = useStore.getState().companionSessions;
    expect(stored).toHaveLength(2);
    expect(stored[0].id).toBe('sess-1');
    expect(stored[1].title).toBe('Session 2');
  });

  it('replaces the previous sessions array entirely', () => {
    useStore.getState().setCompanionSessions([makeSessionSummary({ id: 'old' })]);
    useStore.getState().setCompanionSessions([makeSessionSummary({ id: 'new' })]);

    const stored = useStore.getState().companionSessions;
    expect(stored).toHaveLength(1);
    expect(stored[0].id).toBe('new');
  });

  it('accepts an empty array to clear sessions', () => {
    useStore.getState().setCompanionSessions([makeSessionSummary()]);
    useStore.getState().setCompanionSessions([]);

    expect(useStore.getState().companionSessions).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// setCompanionCurrentSession
// ---------------------------------------------------------------------------

describe('CompanionSlice — setCompanionCurrentSession', () => {
  it('sets the current session', () => {
    const session = makeSession({ id: 'active-sess' });
    useStore.getState().setCompanionCurrentSession(session);

    expect(useStore.getState().companionCurrentSession).toBeDefined();
    expect(useStore.getState().companionCurrentSession?.id).toBe('active-sess');
  });

  it('stores the full session including messages', () => {
    const session = makeSession({
      messages: [makeMessage({ content: 'Existing message' })],
    });

    useStore.getState().setCompanionCurrentSession(session);

    const stored = useStore.getState().companionCurrentSession;
    expect(stored?.messages).toHaveLength(1);
    expect(stored?.messages[0].content).toBe('Existing message');
  });

  it('accepts null to clear the current session', () => {
    useStore.getState().setCompanionCurrentSession(makeSession());
    useStore.getState().setCompanionCurrentSession(null);

    expect(useStore.getState().companionCurrentSession).toBeNull();
  });

  it('replaces the previous current session', () => {
    useStore.getState().setCompanionCurrentSession(makeSession({ id: 'first' }));
    useStore.getState().setCompanionCurrentSession(makeSession({ id: 'second' }));

    expect(useStore.getState().companionCurrentSession?.id).toBe('second');
  });
});

// ---------------------------------------------------------------------------
// setCompanionStreaming
// ---------------------------------------------------------------------------

describe('CompanionSlice — setCompanionStreaming', () => {
  it('sets companionStreaming to true', () => {
    useStore.getState().setCompanionStreaming(true);
    expect(useStore.getState().companionStreaming).toBe(true);
  });

  it('sets companionStreaming to false', () => {
    useStore.getState().setCompanionStreaming(true);
    useStore.getState().setCompanionStreaming(false);
    expect(useStore.getState().companionStreaming).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// appendCompanionStreamText
// ---------------------------------------------------------------------------

describe('CompanionSlice — appendCompanionStreamText', () => {
  it('appends text to the empty streaming buffer', () => {
    useStore.getState().appendCompanionStreamText('Hello');
    expect(useStore.getState().companionStreamingText).toBe('Hello');
  });

  it('concatenates successive appends', () => {
    useStore.getState().appendCompanionStreamText('Hello');
    useStore.getState().appendCompanionStreamText(', ');
    useStore.getState().appendCompanionStreamText('world');

    expect(useStore.getState().companionStreamingText).toBe('Hello, world');
  });

  it('appends an empty string without changing the buffer', () => {
    useStore.getState().appendCompanionStreamText('initial');
    useStore.getState().appendCompanionStreamText('');

    expect(useStore.getState().companionStreamingText).toBe('initial');
  });

  it('preserves whitespace and newlines', () => {
    useStore.getState().appendCompanionStreamText('line1\n');
    useStore.getState().appendCompanionStreamText('line2\n');

    expect(useStore.getState().companionStreamingText).toBe('line1\nline2\n');
  });
});

// ---------------------------------------------------------------------------
// resetCompanionStream
// ---------------------------------------------------------------------------

describe('CompanionSlice — resetCompanionStream', () => {
  it('clears the streaming text buffer', () => {
    useStore.getState().appendCompanionStreamText('some text');
    useStore.getState().resetCompanionStream();

    expect(useStore.getState().companionStreamingText).toBe('');
  });

  it('is idempotent when called on an already-empty buffer', () => {
    useStore.getState().resetCompanionStream();
    expect(useStore.getState().companionStreamingText).toBe('');
  });

  it('does not affect companionStreaming flag', () => {
    useStore.getState().setCompanionStreaming(true);
    useStore.getState().appendCompanionStreamText('text');
    useStore.getState().resetCompanionStream();

    expect(useStore.getState().companionStreaming).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// addCompanionMessage — with existing session
// ---------------------------------------------------------------------------

describe('CompanionSlice — addCompanionMessage (with existing session)', () => {
  it('appends a message to the current session messages array', () => {
    const session = makeSession({ messages: [] });
    useStore.getState().setCompanionCurrentSession(session);

    const msg = makeMessage({ content: 'Hello from test' });
    useStore.getState().addCompanionMessage(msg);

    const current = useStore.getState().companionCurrentSession;
    expect(current?.messages).toHaveLength(1);
    expect(current?.messages[0].content).toBe('Hello from test');
  });

  it('preserves existing messages when appending a new one', () => {
    const session = makeSession({
      messages: [makeMessage({ id: 'existing', content: 'pre-existing' })],
    });
    useStore.getState().setCompanionCurrentSession(session);

    useStore.getState().addCompanionMessage(makeMessage({ id: 'new', content: 'new message' }));

    const current = useStore.getState().companionCurrentSession;
    expect(current?.messages).toHaveLength(2);
    expect(current?.messages[0].id).toBe('existing');
    expect(current?.messages[1].id).toBe('new');
  });

  it('updates updatedAt on the current session', () => {
    const session = makeSession({ updatedAt: '2026-01-01T00:00:00.000Z' });
    useStore.getState().setCompanionCurrentSession(session);

    useStore.getState().addCompanionMessage(makeMessage());

    const current = useStore.getState().companionCurrentSession;
    // updatedAt must be >= the original session value
    expect(current?.updatedAt >= '2026-01-01T00:00:00.000Z').toBe(true);
  });

  it('preserves session id and projectId unchanged', () => {
    const session = makeSession({ id: 'preserved-id', projectId: 'preserved-proj' });
    useStore.getState().setCompanionCurrentSession(session);

    useStore.getState().addCompanionMessage(makeMessage());

    const current = useStore.getState().companionCurrentSession;
    expect(current?.id).toBe('preserved-id');
    expect(current?.projectId).toBe('preserved-proj');
  });

  it('appends multiple messages in order', () => {
    useStore.getState().setCompanionCurrentSession(makeSession());

    useStore.getState().addCompanionMessage(makeMessage({ id: 'a', role: 'user', content: 'Q1' }));
    useStore.getState().addCompanionMessage(makeMessage({ id: 'b', role: 'assistant', content: 'A1' }));
    useStore.getState().addCompanionMessage(makeMessage({ id: 'c', role: 'user', content: 'Q2' }));

    const msgs = useStore.getState().companionCurrentSession?.messages;
    expect(msgs).toHaveLength(3);
    expect(msgs?.[0].id).toBe('a');
    expect(msgs?.[1].id).toBe('b');
    expect(msgs?.[2].id).toBe('c');
  });
});

// ---------------------------------------------------------------------------
// addCompanionMessage — without existing session (transient shell)
// ---------------------------------------------------------------------------

describe('CompanionSlice — addCompanionMessage (no current session)', () => {
  it('creates a transient session shell when there is no current session', () => {
    expect(useStore.getState().companionCurrentSession).toBeNull();

    useStore.getState().addCompanionMessage(makeMessage({ content: 'First message' }));

    const current = useStore.getState().companionCurrentSession;
    expect(current).not.toBeNull();
    expect(current?.messages).toHaveLength(1);
    expect(current?.messages[0].content).toBe('First message');
  });

  it('created shell has a "New conversation" title', () => {
    useStore.getState().addCompanionMessage(makeMessage());

    const current = useStore.getState().companionCurrentSession;
    expect(current?.title).toBe('New conversation');
  });

  it('created shell message contains the correct content', () => {
    const msg = makeMessage({ id: 'shell-msg', content: 'Shell message', role: 'user' });
    useStore.getState().addCompanionMessage(msg);

    const current = useStore.getState().companionCurrentSession;
    expect(current?.messages[0].id).toBe('shell-msg');
    expect(current?.messages[0].role).toBe('user');
  });
});

// ---------------------------------------------------------------------------
// setCompanionStatus
// ---------------------------------------------------------------------------

describe('CompanionSlice — setCompanionStatus', () => {
  it('stores the provided status object', () => {
    const status: CompanionStatus = { adapter: 'stub', available: true };
    useStore.getState().setCompanionStatus(status);

    const stored = useStore.getState().companionStatus;
    expect(stored?.adapter).toBe('stub');
    expect(stored?.available).toBe(true);
  });

  it('accepts null to clear the status', () => {
    useStore.getState().setCompanionStatus({ adapter: 'ai-sdk', available: true });
    useStore.getState().setCompanionStatus(null);

    expect(useStore.getState().companionStatus).toBeNull();
  });

  it('replaces previous status on successive calls', () => {
    useStore.getState().setCompanionStatus({ adapter: 'stub', available: true });
    useStore.getState().setCompanionStatus({ adapter: 'ai-sdk', available: false });

    expect(useStore.getState().companionStatus?.adapter).toBe('ai-sdk');
    expect(useStore.getState().companionStatus?.available).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// setCompanionError
// ---------------------------------------------------------------------------

describe('CompanionSlice — setCompanionError', () => {
  it('stores an error message string', () => {
    useStore.getState().setCompanionError('Connection failed');
    expect(useStore.getState().companionError).toBe('Connection failed');
  });

  it('accepts null to clear the error', () => {
    useStore.getState().setCompanionError('Some error');
    useStore.getState().setCompanionError(null);

    expect(useStore.getState().companionError).toBeNull();
  });

  it('replaces a previous error with a new one', () => {
    useStore.getState().setCompanionError('First error');
    useStore.getState().setCompanionError('Second error');

    expect(useStore.getState().companionError).toBe('Second error');
  });
});

// ---------------------------------------------------------------------------
// Slice isolation — companion actions do not corrupt other slices
// ---------------------------------------------------------------------------

describe('CompanionSlice — isolation from other slices', () => {
  it('companion actions do not change pipeline state', () => {
    useStore.getState().setPipelineState({
      currentState: 'EXECUTING',
      currentEpicId: 'E-001',
      currentStepId: 'step_1',
      progress: { epicsCompleted: 1, epicsTotal: 3, stepsCompleted: 2, stepsTotal: 10 },
    });

    useStore.getState().setCompanionOpen(true);
    useStore.getState().setCompanionStreaming(true);
    useStore.getState().appendCompanionStreamText('streaming text');
    useStore.getState().addCompanionMessage(makeMessage());

    // Pipeline state must be unchanged
    expect(useStore.getState().currentState).toBe('EXECUTING');
    expect(useStore.getState().currentEpicId).toBe('E-001');
    expect(useStore.getState().pipelineProgress.epicsCompleted).toBe(1);
  });

  it('connection slice actions do not corrupt companion state', () => {
    useStore.getState().setCompanionSessions([makeSessionSummary({ id: 'keep-me' })]);

    useStore.getState().setWsStatus('connected');
    useStore.getState().incrementReconnectAttempt();
    useStore.getState().handleHeartbeat('2026-02-27T10:00:00.000Z', 3);

    // Companion state intact
    expect(useStore.getState().companionSessions).toHaveLength(1);
    expect(useStore.getState().companionSessions[0].id).toBe('keep-me');
  });

  it('resetting companion stream does not affect stage log', () => {
    useStore.getState().addStageLogEntry({
      timestamp: '2026-02-27T10:00:00.000Z',
      state: 'EXECUTING',
      step: 'step_1',
      action: 'dispatch_agent',
      details: 'test',
      result: 'pass',
    });

    useStore.getState().appendCompanionStreamText('stream data');
    useStore.getState().resetCompanionStream();

    expect(useStore.getState().stageLogEntries).toHaveLength(1);
    expect(useStore.getState().companionStreamingText).toBe('');
  });
});

// ---------------------------------------------------------------------------
// Store reset validation
// ---------------------------------------------------------------------------

describe('CompanionSlice — store reset between tests', () => {
  it('companion state is fully reset after beforeEach (first test)', () => {
    useStore.getState().setCompanionOpen(true);
    useStore.getState().setCompanionStreaming(true);
    useStore.getState().appendCompanionStreamText('dirty text');
    useStore.getState().setCompanionError('dirty error');

    // These changes will be visible in this test
    expect(useStore.getState().companionOpen).toBe(true);
  });

  it('companion state is fully reset after beforeEach (second test — verifies isolation)', () => {
    // After beforeEach reset, all companion fields must be back to initial defaults
    expect(useStore.getState().companionOpen).toBe(false);
    expect(useStore.getState().companionStreaming).toBe(false);
    expect(useStore.getState().companionStreamingText).toBe('');
    expect(useStore.getState().companionError).toBeNull();
    expect(useStore.getState().companionSessions).toEqual([]);
    expect(useStore.getState().companionCurrentSession).toBeNull();
  });
});
