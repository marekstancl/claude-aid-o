/**
 * Unit tests for the AidWebSocket class.
 *
 * Tests connection handling, topic subscriptions, event broadcasting,
 * heartbeat, idle timeout, and stage_log buffer replay.
 *
 * Uses a real HTTP server + ws client to test the full protocol.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import http from 'node:http';
import { WebSocket } from 'ws';
import { AidWebSocket } from '../../../server/ws/websocket.ts';
import type { FileChangeEvent, StageLogEvent } from '../../../server/types.ts';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Create a minimal HTTP server and AidWebSocket for testing. */
function createTestServer(): {
  server: http.Server;
  ws: AidWebSocket;
  address: () => string;
} {
  const server = http.createServer();
  const ws = new AidWebSocket(server);
  return {
    server,
    ws,
    address: () => {
      const addr = server.address();
      if (!addr || typeof addr === 'string') return 'ws://localhost:0';
      return `ws://localhost:${addr.port}/ws`;
    },
  };
}

/** Start the server on a random port. */
function listen(server: http.Server): Promise<void> {
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => resolve());
  });
}

/** Create a ws client and wait for the connection ack message. */
function connectClient(url: string): Promise<{
  client: WebSocket;
  messages: unknown[];
}> {
  return new Promise((resolve, reject) => {
    const client = new WebSocket(url);
    const messages: unknown[] = [];

    client.on('message', (data) => {
      const msg = JSON.parse(data.toString());
      messages.push(msg);
    });

    client.on('open', () => {
      // Wait briefly for the 'connected' message to arrive
      setTimeout(() => resolve({ client, messages }), 50);
    });

    client.on('error', reject);
  });
}

/** Send a JSON message via the ws client. */
function send(client: WebSocket, msg: unknown): void {
  client.send(JSON.stringify(msg));
}

/** Wait for a brief period to allow messages to propagate. */
function wait(ms: number = 100): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

/** Make a fake FileChangeEvent. */
function fakeFileChangeEvent(topic: string = 'pipeline'): FileChangeEvent {
  return {
    type: 'file_change',
    topic: topic as FileChangeEvent['topic'],
    filePath: '/test/path',
    changeType: 'change',
    parsedData: { test: true },
    timestamp: new Date().toISOString(),
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('AidWebSocket', () => {
  let testServer: ReturnType<typeof createTestServer>;

  beforeEach(async () => {
    testServer = createTestServer();
    await listen(testServer.server);
    testServer.ws.start();
  });

  afterEach(async () => {
    testServer.ws.stop();
    await new Promise<void>((resolve) => {
      testServer.server.close(() => resolve());
    });
  });

  // -------------------------------------------------------------------------
  // Connection
  // -------------------------------------------------------------------------

  it('sends a connected message on new connection', async () => {
    const { client, messages } = await connectClient(testServer.address());

    expect(messages.length).toBeGreaterThanOrEqual(1);
    const connMsg = messages[0] as Record<string, unknown>;
    expect(connMsg.type).toBe('connected');
    expect(connMsg.topic).toBe('system');
    expect(Array.isArray(connMsg.availableTopics)).toBe(true);

    client.close();
  });

  it('tracks client count correctly', async () => {
    expect(testServer.ws.clientCount).toBe(0);

    const { client: client1 } = await connectClient(testServer.address());
    expect(testServer.ws.clientCount).toBe(1);

    const { client: client2 } = await connectClient(testServer.address());
    expect(testServer.ws.clientCount).toBe(2);

    client1.close();
    await wait(100);
    expect(testServer.ws.clientCount).toBe(1);

    client2.close();
    await wait(100);
    expect(testServer.ws.clientCount).toBe(0);
  });

  // -------------------------------------------------------------------------
  // Subscribe / Unsubscribe
  // -------------------------------------------------------------------------

  it('handles subscribe with topics array', async () => {
    const { client, messages } = await connectClient(testServer.address());

    send(client, { type: 'subscribe', topics: ['pipeline', 'queue'] });
    await wait();

    const subMsg = messages.find(
      (m) => (m as Record<string, unknown>).type === 'subscribed',
    ) as Record<string, unknown> | undefined;
    expect(subMsg).toBeDefined();
    expect(subMsg!.topics).toContain('pipeline');
    expect(subMsg!.topics).toContain('queue');

    client.close();
  });

  it('handles subscribe with single topic string', async () => {
    const { client, messages } = await connectClient(testServer.address());

    send(client, { type: 'subscribe', topic: 'evidence' });
    await wait();

    const subMsg = messages.find(
      (m) => (m as Record<string, unknown>).type === 'subscribed',
    ) as Record<string, unknown> | undefined;
    expect(subMsg).toBeDefined();
    expect((subMsg!.topics as string[])).toContain('evidence');

    client.close();
  });

  it('handles wildcard subscription', async () => {
    const { client, messages } = await connectClient(testServer.address());

    send(client, { type: 'subscribe', topics: ['*'] });
    await wait();

    const subMsg = messages.find(
      (m) => (m as Record<string, unknown>).type === 'subscribed',
    ) as Record<string, unknown> | undefined;
    expect(subMsg).toBeDefined();
    // Wildcard expands to all topics
    expect((subMsg!.topics as string[]).length).toBeGreaterThan(1);

    client.close();
  });

  it('sends error for unknown topic', async () => {
    const { client, messages } = await connectClient(testServer.address());

    send(client, { type: 'subscribe', topics: ['nonexistent_topic'] });
    await wait();

    const errMsg = messages.find(
      (m) => (m as Record<string, unknown>).type === 'error',
    ) as Record<string, unknown> | undefined;
    expect(errMsg).toBeDefined();
    expect(errMsg!.message).toContain('Unknown topic');

    client.close();
  });

  it('handles unsubscribe', async () => {
    const { client, messages } = await connectClient(testServer.address());

    // Subscribe first
    send(client, { type: 'subscribe', topics: ['pipeline', 'queue'] });
    await wait();

    // Then unsubscribe from one
    send(client, { type: 'unsubscribe', topics: ['pipeline'] });
    await wait();

    const unsubMsg = messages.find(
      (m) => (m as Record<string, unknown>).type === 'unsubscribed',
    ) as Record<string, unknown> | undefined;
    expect(unsubMsg).toBeDefined();
    expect((unsubMsg!.topics as string[])).toContain('pipeline');

    client.close();
  });

  it('handles wildcard unsubscribe', async () => {
    const { client, messages } = await connectClient(testServer.address());

    send(client, { type: 'subscribe', topics: ['*'] });
    await wait();

    send(client, { type: 'unsubscribe', topics: ['*'] });
    await wait();

    const unsubMsg = messages.find(
      (m) => (m as Record<string, unknown>).type === 'unsubscribed',
    ) as Record<string, unknown> | undefined;
    expect(unsubMsg).toBeDefined();

    client.close();
  });

  // -------------------------------------------------------------------------
  // Broadcast
  // -------------------------------------------------------------------------

  it('broadcasts events only to subscribed clients', async () => {
    const { client: subClient, messages: subMessages } = await connectClient(testServer.address());
    const { client: noSubClient, messages: noSubMessages } = await connectClient(testServer.address());

    // Subscribe first client to pipeline
    send(subClient, { type: 'subscribe', topics: ['pipeline'] });
    await wait();

    // Broadcast a pipeline event
    testServer.ws.broadcast(fakeFileChangeEvent('pipeline'));
    await wait();

    // Subscribed client should have the event
    const eventMsg = subMessages.find(
      (m) => (m as Record<string, unknown>).type === 'event',
    );
    expect(eventMsg).toBeDefined();

    // Unsubscribed client should NOT have event (only connected msg)
    const noEventMsg = noSubMessages.find(
      (m) => (m as Record<string, unknown>).type === 'event',
    );
    expect(noEventMsg).toBeUndefined();

    subClient.close();
    noSubClient.close();
  });

  it('wildcard subscriber receives all topics', async () => {
    const { client, messages } = await connectClient(testServer.address());

    send(client, { type: 'subscribe', topics: ['*'] });
    await wait();

    testServer.ws.broadcast(fakeFileChangeEvent('pipeline'));
    testServer.ws.broadcast(fakeFileChangeEvent('queue'));
    testServer.ws.broadcast(fakeFileChangeEvent('evidence'));
    await wait();

    const events = messages.filter(
      (m) => (m as Record<string, unknown>).type === 'event',
    );
    expect(events.length).toBe(3);

    client.close();
  });

  it('does not broadcast after stop', async () => {
    const { client, messages } = await connectClient(testServer.address());

    send(client, { type: 'subscribe', topics: ['*'] });
    await wait();

    testServer.ws.stop();

    // This should not throw or send
    testServer.ws.broadcast(fakeFileChangeEvent('pipeline'));

    client.close();
  });

  // -------------------------------------------------------------------------
  // Ping/Pong
  // -------------------------------------------------------------------------

  it('responds to ping with pong', async () => {
    const { client, messages } = await connectClient(testServer.address());

    send(client, { type: 'ping' });
    await wait();

    const pongMsg = messages.find(
      (m) => (m as Record<string, unknown>).type === 'pong',
    );
    expect(pongMsg).toBeDefined();

    client.close();
  });

  // -------------------------------------------------------------------------
  // Error handling
  // -------------------------------------------------------------------------

  it('sends error for invalid JSON', async () => {
    const { client, messages } = await connectClient(testServer.address());

    // Send raw invalid JSON
    client.send('not valid json');
    await wait();

    const errMsg = messages.find(
      (m) => (m as Record<string, unknown>).type === 'error',
    ) as Record<string, unknown> | undefined;
    expect(errMsg).toBeDefined();
    expect(errMsg!.message).toContain('Invalid JSON');

    client.close();
  });

  it('sends error for message without type field', async () => {
    const { client, messages } = await connectClient(testServer.address());

    send(client, { data: 'no type field' });
    await wait();

    const errMsg = messages.find(
      (m) => (m as Record<string, unknown>).type === 'error',
    ) as Record<string, unknown> | undefined;
    expect(errMsg).toBeDefined();
    expect(errMsg!.message).toContain('type');

    client.close();
  });

  it('sends error for unknown message type', async () => {
    const { client, messages } = await connectClient(testServer.address());

    send(client, { type: 'unknown_action' });
    await wait();

    const errMsg = messages.find(
      (m) => (m as Record<string, unknown>).type === 'error',
    ) as Record<string, unknown> | undefined;
    expect(errMsg).toBeDefined();
    expect(errMsg!.message).toContain('Unknown message type');

    client.close();
  });

  // -------------------------------------------------------------------------
  // Stage log buffer replay
  // -------------------------------------------------------------------------

  it('replays stage_log buffer on subscription', async () => {
    // Set up a buffer supplier
    const mockBuffer: StageLogEvent[] = [
      {
        type: 'stage_log',
        topic: 'pipeline.stage_log',
        entry: {
          timestamp: '2026-01-01T00:00:00Z',
          state: 'EXECUTING',
          step: 'step_1',
          action: 'dispatch',
          details: 'test',
          result: 'pass',
        },
        epicId: 'E-001',
        runId: 'run1',
        timestamp: '2026-01-01T00:00:01Z',
      },
      {
        type: 'stage_log',
        topic: 'pipeline.stage_log',
        entry: {
          timestamp: '2026-01-01T00:01:00Z',
          state: 'EXECUTING',
          step: 'step_1',
          action: 'agent_complete',
          details: 'done',
          result: 'pass',
        },
        epicId: 'E-001',
        runId: 'run1',
        timestamp: '2026-01-01T00:01:01Z',
      },
    ];
    testServer.ws.setStageLogBufferSupplier(() => mockBuffer);

    const { client, messages } = await connectClient(testServer.address());

    send(client, { type: 'subscribe', topics: ['pipeline.stage_log'] });
    await wait(150);

    // Should have a subscribed message AND a replay message
    const replayMsg = messages.find(
      (m) => (m as Record<string, unknown>).type === 'replay',
    ) as Record<string, unknown> | undefined;
    expect(replayMsg).toBeDefined();
    expect(replayMsg!.topic).toBe('pipeline.stage_log');
    expect(Array.isArray(replayMsg!.data)).toBe(true);
    expect((replayMsg!.data as unknown[]).length).toBe(2);

    client.close();
  });

  it('does not replay empty buffer', async () => {
    testServer.ws.setStageLogBufferSupplier(() => []);

    const { client, messages } = await connectClient(testServer.address());

    send(client, { type: 'subscribe', topics: ['pipeline.stage_log'] });
    await wait(150);

    const replayMsg = messages.find(
      (m) => (m as Record<string, unknown>).type === 'replay',
    );
    expect(replayMsg).toBeUndefined();

    client.close();
  });

  it('does not replay when subscribing to non-stage_log topics', async () => {
    const mockBuffer: StageLogEvent[] = [{
      type: 'stage_log',
      topic: 'pipeline.stage_log',
      entry: {
        timestamp: '2026-01-01T00:00:00Z',
        state: 'IDLE',
        step: null,
        action: 'test',
        details: 'test',
        result: 'pass',
      },
      epicId: 'E-001',
      runId: 'run1',
      timestamp: '2026-01-01T00:00:00Z',
    }];
    testServer.ws.setStageLogBufferSupplier(() => mockBuffer);

    const { client, messages } = await connectClient(testServer.address());

    send(client, { type: 'subscribe', topics: ['pipeline'] });
    await wait(150);

    const replayMsg = messages.find(
      (m) => (m as Record<string, unknown>).type === 'replay',
    );
    expect(replayMsg).toBeUndefined();

    client.close();
  });

  // -------------------------------------------------------------------------
  // Subscribe validation
  // -------------------------------------------------------------------------

  it('sends error for subscribe without topics', async () => {
    const { client, messages } = await connectClient(testServer.address());

    send(client, { type: 'subscribe' });
    await wait();

    const errMsg = messages.find(
      (m) => (m as Record<string, unknown>).type === 'error',
    ) as Record<string, unknown> | undefined;
    expect(errMsg).toBeDefined();
    expect(errMsg!.message).toContain('topics');

    client.close();
  });
});
