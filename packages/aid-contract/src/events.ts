// Event pipeline contract types — shared between aid-server watcher and aid-gui WebSocket.
// Salvaged from packages/aid-gui/server/types.ts and adapted per §7.3:
// broadcast timestamp field standardizes on `ts` (FileChangeEvent.timestamp → ts).

export type EventTopic =
  | 'pipeline'
  | 'pipeline.stage_log'
  | 'evidence'
  | 'decisions'
  | 'config'
  | 'queue'
  | 'audit'
  | 'usage'
  | 'queue.schedule'
  | 'system';

export const ALL_EVENT_TOPICS: EventTopic[] = [
  'pipeline',
  'pipeline.stage_log',
  'evidence',
  'decisions',
  'config',
  'queue',
  'audit',
  'usage',
  'queue.schedule',
  'system',
];

export interface FileChangeEvent {
  type: 'file_change';
  topic: EventTopic;
  filePath: string;
  changeType: 'add' | 'change' | 'unlink';
  parsedData: unknown | null;
  ts: string;                          // §7.3: renamed from `timestamp`; ISO 8601
}

// In the contract, InternalEvent covers the one broadcast event type.
// Server-internal types (StageLogEvent, HeartbeatEvent, ConnectionEvent)
// stay in aid-server and may extend this union locally.
export type InternalEvent = FileChangeEvent;

export interface WatcherOptions {
  ignorePatterns?: string[];
  debounceMs?: number;
}

export interface PathClassification {
  topic: EventTopic;
  parser: 'yaml' | 'json' | 'jsonl' | 'markdown' | 'epicSpec' | null;
  excluded: boolean;
}

export interface ParseWarning {
  message: string;
  line?: number;
  severity: 'info' | 'warning' | 'error';
}

export interface ParseResult<T> {
  data: T | null;
  warnings: ParseWarning[];
  source: string;
}
