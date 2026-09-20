/**
 * AidWebSocket tests — REAL ws client against a REAL server on an ephemeral
 * port. No mocked sockets (Phase-2 lesson). Always dial 127.0.0.1, never
 * "localhost", to avoid IPv6/IPv4 mismatch.
 */

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { createServer, type Server as HttpServer } from 'node:http';
import { AddressInfo } from 'node:net';
import { WebSocket } from 'ws';
import type { ActivityEvent, FileChangeEvent } from '@aid/contract';
import { AidWebSocket } from './websocket.js';

// ---------------------------------------------------------------------------
// Test harness
// ---------------------------------------------------------------------------

let httpServer: HttpServer;
let aidWs: AidWebSocket;
let port: number;
const openClients: WebSocket[] = [];

async function startServer(
  options?: ConstructorParameters<typeof AidWebSocket>[2],
): Promise<void> {
  httpServer = createServer();
  aidWs = new AidWebSocket(httpServer, '/ws', options);
  await new Promise<void>((resolve) => {
    httpServer.listen(0, '127.0.0.1', () => {
      port = (httpServer.address() as AddressInfo).port;
      aidWs.start();
      resolve();
    });
  });
}

interface TestClient {
  socket: WebSocket;
  frames: Record<string, unknown>[];
}

/**
 * Open a real ws client. The frame collector is attached BEFORE the socket
 * opens so the synchronous `connected` frame is never raced/lost. Resolves
 * once OPEN.
 */
function connect(): Promise<TestClient> {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(`ws://127.0.0.1:${port}/ws`);
    openClients.push(socket);
    const frames: Record<string, unknown>[] = [];
    socket.on('message', (data) => {
      frames.push(JSON.parse(data.toString()) as Record<string, unknown>);
    });
    socket.once('open', () => resolve({ socket, frames }));
    socket.once('error', reject);
  });
}

/** Wait until predicate is true over the collected frames, or time out. */
async function waitFor(
  predicate: () => boolean,
  timeoutMs = 1000,
): Promise<void> {
  const start = Date.now();
  while (!predicate()) {
    if (Date.now() - start > timeoutMs) {
      throw new Error('waitFor timed out');
    }
    await new Promise((r) => setTimeout(r, 10));
  }
}

function makeFileChange(projectId: string): FileChangeEvent {
  return {
    type: 'file_change',
    projectId,
    topic: 'pipeline.timeline',
    changeType: 'change',
    parsedData: { hello: 'world' },
    ts: new Date().toISOString(),
  };
}

beforeEach(async () => {
  await startServer();
});

afterEach(async () => {
  for (const client of openClients) {
    try {
      client.removeAllListeners();
      client.terminate();
    } catch {
      // already closed
    }
  }
  openClients.length = 0;
  aidWs.stop();
  await new Promise<void>((resolve) => httpServer.close(() => resolve()));
});

// ---------------------------------------------------------------------------
// AC1 — topic-AND-project filter (two real connections)
// ---------------------------------------------------------------------------

describe('AC1 — topic-AND-project delivery filter', () => {
  it('delivers an acta broadcast ONLY to the acta-subscribed client', async () => {
    const acta = await connect();
    const actb = await connect();
    const actaFrames = acta.frames;
    const actbFrames = actb.frames;

    // Both subscribe to the SAME topic but DIFFERENT projects.
    acta.socket.send(
      JSON.stringify({
        type: 'subscribe',
        topics: ['pipeline.timeline'],
        projects: ['acta'],
      }),
    );
    actb.socket.send(
      JSON.stringify({
        type: 'subscribe',
        topics: ['pipeline.timeline'],
        projects: ['actb'],
      }),
    );

    await waitFor(
      () =>
        actaFrames.some((f) => f.type === 'subscribed') &&
        actbFrames.some((f) => f.type === 'subscribed'),
    );

    aidWs.broadcast(makeFileChange('acta'));

    await waitFor(() => actaFrames.some((f) => f.type === 'event'));

    const actaEvents = actaFrames.filter((f) => f.type === 'event');
    const actbEvents = actbFrames.filter((f) => f.type === 'event');

    expect(actaEvents).toHaveLength(1);
    expect((actaEvents[0].data as FileChangeEvent).projectId).toBe('acta');
    // The actb-scoped client must NOT receive the acta event.
    expect(actbEvents).toHaveLength(0);
  });

  it('empty projects set = all projects (wildcard)', async () => {
    const { socket, frames } = await connect();

    socket.send(
      JSON.stringify({
        type: 'subscribe',
        topics: ['pipeline.timeline'],
        projects: [],
      }),
    );
    await waitFor(() => frames.some((f) => f.type === 'subscribed'));

    aidWs.broadcast(makeFileChange('any-project'));
    await waitFor(() => frames.some((f) => f.type === 'event'));

    const events = frames.filter((f) => f.type === 'event');
    expect(events).toHaveLength(1);
    expect((events[0].data as FileChangeEvent).projectId).toBe('any-project');
  });
});

// ---------------------------------------------------------------------------
// AC2 — `ts` envelope, zero `timestamp`
// ---------------------------------------------------------------------------

describe('AC2 — every frame carries top-level ts', () => {
  it('connected/subscribed/event/replay frames all have ts and no timestamp', async () => {
    aidWs.setActivityBufferSupplier(() => [makeActivity('acta')]);

    const { socket, frames } = await connect();

    await waitFor(() => frames.some((f) => f.type === 'connected'));

    socket.send(
      JSON.stringify({
        type: 'subscribe',
        topics: ['pipeline.timeline'],
        projects: ['acta'],
      }),
    );
    await waitFor(() => frames.some((f) => f.type === 'replay'));

    aidWs.broadcast(makeFileChange('acta'));
    await waitFor(() => frames.some((f) => f.type === 'event'));

    // ping → pong frame (another server→client frame).
    socket.send(JSON.stringify({ type: 'ping' }));
    await waitFor(() => frames.some((f) => f.type === 'pong'));

    expect(frames.length).toBeGreaterThanOrEqual(4);
    for (const frame of frames) {
      expect(typeof frame.ts).toBe('string');
      expect('timestamp' in frame).toBe(false);
    }
  });

  it('error frame carries ts', async () => {
    const { socket, frames } = await connect();
    await waitFor(() => frames.some((f) => f.type === 'connected'));

    socket.send('not json');
    await waitFor(() => frames.some((f) => f.type === 'error'));

    const err = frames.find((f) => f.type === 'error')!;
    expect(typeof err.ts).toBe('string');
    expect('timestamp' in err).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// AC3 — replay-on-subscribe from the activity supplier
// ---------------------------------------------------------------------------

function makeActivity(projectId: string): ActivityEvent {
  return {
    projectId,
    epicId: 'E-047-3_7',
    runId: 'R-1',
    ts: new Date().toISOString(),
    event: 'state_change',
    from: 'READY',
    to: 'EXECUTE',
    // `raw.topic` carries the activity-topic vocabulary used by the SHARED
    // filter (Step 8): replay now applies topic matching identically to the REST
    // `/activity` bootstrap, so the subscribed topic ('pipeline.timeline') must
    // be present here for the event to survive the filter.
    raw: { source: 'timeline.jsonl', topic: 'pipeline.timeline' },
  };
}

describe('AC3 — replay frame on subscribe', () => {
  it('subscribing to pipeline.timeline yields a replay frame of ActivityEvents', async () => {
    aidWs.setActivityBufferSupplier(() => [
      makeActivity('acta'),
      makeActivity('acta'),
    ]);

    const { socket, frames } = await connect();

    socket.send(
      JSON.stringify({
        type: 'subscribe',
        topics: ['pipeline.timeline'],
        projects: ['acta'],
      }),
    );
    await waitFor(() => frames.some((f) => f.type === 'replay'));

    const replay = frames.find((f) => f.type === 'replay')!;
    const data = replay.data as ActivityEvent[];
    expect(Array.isArray(data)).toBe(true);
    expect(data).toHaveLength(2);
    // ActivityEvent shape sanity.
    expect(data[0].projectId).toBe('acta');
    expect(typeof data[0].ts).toBe('string');
    expect(typeof data[0].event).toBe('string');
    expect(typeof data[0].raw).toBe('object');
  });

  it('no replay frame when the supplier is empty', async () => {
    aidWs.setActivityBufferSupplier(() => []);

    const { socket, frames } = await connect();

    socket.send(
      JSON.stringify({ type: 'subscribe', topics: ['pipeline.timeline'], projects: [] }),
    );
    await waitFor(() => frames.some((f) => f.type === 'subscribed'));
    // Give any stray replay a chance to arrive.
    await new Promise((r) => setTimeout(r, 50));
    expect(frames.some((f) => f.type === 'replay')).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// AC4 — idle timeout close 4001 (shortened timer for the test)
// ---------------------------------------------------------------------------

describe('AC4 — idle timeout closes with code 4001', () => {
  beforeEach(async () => {
    // Restart with a short idle timeout; production default is 90s.
    aidWs.stop();
    await new Promise<void>((resolve) => httpServer.close(() => resolve()));
    await startServer({ idleTimeoutMs: 60, idleCheckIntervalMs: 20 });
  });

  it('closes an idle connection with code 4001', async () => {
    const { socket } = await connect();
    const closeInfo = await new Promise<{ code: number }>((resolve) => {
      socket.once('close', (code) => resolve({ code }));
    });
    expect(closeInfo.code).toBe(4001);
  });
});
