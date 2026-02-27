/**
 * WebSocket handler with topic-based pub/sub and file watching.
 */

import { WebSocketServer, WebSocket } from 'ws';
import { watch } from 'chokidar';
import { join, relative } from 'node:path';
import type { Server } from 'node:http';
import type { ServerConfig } from '../config.js';
import { FsReader } from '../services/fs-reader.js';

const EVENT_TOPICS = [
  'pipeline', 'pipeline.stage_log', 'evidence', 'decisions',
  'config', 'queue', 'audit', 'usage', 'queue.schedule', 'system', 'ideas', 'epics',
  'companion.stream', 'companion.session',
] as const;

type EventTopic = (typeof EVENT_TOPICS)[number] | '*';

interface ClientState {
  ws: WebSocket;
  topics: Set<string>;
  lastActivity: number;
}

export class WsHandler {
  private wss!: WebSocketServer;
  private clients: Map<WebSocket, ClientState> = new Map();
  private heartbeatTimer?: ReturnType<typeof setInterval>;
  private idleTimer?: ReturnType<typeof setInterval>;
  private fsReader: FsReader;

  constructor(private readonly config: ServerConfig) {
    this.fsReader = new FsReader(config.projectRoot);
  }

  attach(server: Server): void {
    this.wss = new WebSocketServer({ server, path: '/ws' });

    this.wss.on('connection', (ws) => {
      const state: ClientState = { ws, topics: new Set(), lastActivity: Date.now() };
      this.clients.set(ws, state);

      // Send connected message
      this.send(ws, {
        type: 'connected',
        topic: 'system',
        availableTopics: [...EVENT_TOPICS],
        timestamp: new Date().toISOString(),
      });

      ws.on('message', (raw) => {
        state.lastActivity = Date.now();
        try {
          const msg = JSON.parse(raw.toString());
          this.handleMessage(ws, state, msg);
        } catch {
          this.send(ws, { type: 'error', message: 'Invalid JSON', timestamp: new Date().toISOString() });
        }
      });

      ws.on('close', () => {
        this.clients.delete(ws);
      });
    });

    // Heartbeat every 30s
    this.heartbeatTimer = setInterval(() => {
      const msg = {
        type: 'heartbeat',
        topic: 'system',
        timestamp: new Date().toISOString(),
        clientCount: this.clients.size,
      };
      for (const [ws] of this.clients) {
        if (ws.readyState === WebSocket.OPEN) this.send(ws, msg);
      }
    }, this.config.wsHeartbeatInterval);

    // Idle timeout check every 30s
    this.idleTimer = setInterval(() => {
      const now = Date.now();
      for (const [ws, state] of this.clients) {
        if (now - state.lastActivity > this.config.wsIdleTimeout) {
          ws.close(4001, 'Idle timeout');
          this.clients.delete(ws);
        }
      }
    }, 30_000);

    // Watch .aid-o/ for file changes
    this.startFileWatcher();
  }

  private handleMessage(ws: WebSocket, state: ClientState, msg: any): void {
    switch (msg.type) {
      case 'subscribe': {
        const topics: string[] = msg.topics ?? [];
        for (const t of topics) state.topics.add(t);
        this.send(ws, { type: 'subscribed', topics, timestamp: new Date().toISOString() });

        // If subscribing to stage_log, send replay
        if (topics.includes('pipeline.stage_log') || topics.includes('*')) {
          this.sendStageLogReplay(ws);
        }
        break;
      }
      case 'unsubscribe': {
        const topics: string[] = msg.topics ?? [];
        if (topics.includes('*')) {
          state.topics.clear();
        } else {
          for (const t of topics) state.topics.delete(t);
        }
        this.send(ws, { type: 'unsubscribed', topics, timestamp: new Date().toISOString() });
        break;
      }
      case 'ping':
        this.send(ws, { type: 'pong', timestamp: new Date().toISOString() });
        break;
    }
  }

  private async sendStageLogReplay(ws: WebSocket): Promise<void> {
    const evidenceBase = join(this.fsReader.aidoPath, '04-engine', 'evidence');
    const epicDirs = await this.fsReader.listDir(evidenceBase);
    const allEntries: any[] = [];

    for (const epicDir of epicDirs.slice(-3)) {
      const runs = await this.fsReader.listDir(join(evidenceBase, epicDir));
      for (const run of runs) {
        const entries = await this.fsReader.readJsonl(join(evidenceBase, epicDir, run, 'stage_log.jsonl'));
        allEntries.push(...entries);
      }
    }

    allEntries.sort((a: any, b: any) => (a.timestamp ?? '').localeCompare(b.timestamp ?? ''));

    if (allEntries.length > 0) {
      this.send(ws, {
        type: 'replay',
        topic: 'pipeline.stage_log',
        data: allEntries.slice(-200),
        timestamp: new Date().toISOString(),
      });
    }
  }

  private startFileWatcher(): void {
    const aidoPath = join(this.config.projectRoot, '.aid-o');
    const watcher = watch(aidoPath, {
      ignoreInitial: true,
      persistent: true,
      depth: 6,
      ignored: ['**/node_modules/**', '**/.git/**'],
    });

    watcher.on('all', async (event, filePath) => {
      const relPath = relative(aidoPath, filePath);
      const topic = this.classifyFileChange(relPath);
      const changeType = event === 'add' ? 'add' : event === 'unlink' ? 'unlink' : 'change';

      let parsedData: unknown = null;
      if (changeType !== 'unlink') {
        try {
          const result = await this.fsReader.readParsed(filePath);
          parsedData = result.content;
        } catch {
          // ignore read errors
        }
      }

      const eventMsg = {
        type: 'event',
        topic,
        data: {
          type: relPath.includes('stage_log') ? 'stage_log' : 'file_change',
          topic,
          filePath: relPath,
          changeType,
          parsedData,
          timestamp: new Date().toISOString(),
        },
        timestamp: new Date().toISOString(),
      };

      this.broadcast(topic, eventMsg);
    });
  }

  private classifyFileChange(relPath: string): string {
    if (relPath.includes('04-engine/companion-sessions/')) return 'companion.session';
    if (relPath.includes('02-epics/') || relPath.startsWith('02-epics')) return 'epics';
    if (relPath.includes('ideas.json')) return 'ideas';
    if (relPath.includes('epic-queue')) return 'queue';
    if (relPath.includes('schedule')) return 'queue.schedule';
    if (relPath.includes('auto-mode-state') || relPath.includes('plan_progress')) return 'pipeline';
    if (relPath.includes('stage_log')) return 'pipeline.stage_log';
    if (relPath.includes('evidence')) return 'evidence';
    if (relPath.includes('decisions') || relPath.includes('pending-decision')) return 'decisions';
    if (relPath.includes('audit')) return 'audit';
    if (relPath.startsWith('03-config')) return 'config';
    return 'system';
  }

  private broadcast(topic: string, msg: any): void {
    for (const [ws, state] of this.clients) {
      if (ws.readyState !== WebSocket.OPEN) continue;
      if (state.topics.has('*') || state.topics.has(topic)) {
        this.send(ws, msg);
      }
    }
  }

  private send(ws: WebSocket, data: any): void {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(data));
    }
  }

  close(): void {
    if (this.heartbeatTimer) clearInterval(this.heartbeatTimer);
    if (this.idleTimer) clearInterval(this.idleTimer);
    this.wss?.close();
  }
}
