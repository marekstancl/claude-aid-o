// Event pipeline contract types — shared between aid-server watcher and aid-gui WebSocket.
// Adapted per §7.3: timestamp → ts; topics updated to P047 step-16 vocabulary.

export type EventTopic =
  | 'pipeline'
  | 'pipeline.timeline'      // timeline.jsonl entries (was pipeline.stage_log in v1 salvage)
  | 'evidence'
  | 'decisions'
  | 'config'
  | 'queue'
  | 'queue.schedule'
  | 'gates'                  // gates_report.json + per-gate outputs
  | 'checkpoints'            // verifier-output-*.md files
  | 'epics'                  // EPIC spec files (.aid-o/tasks/*.md)
  | 'backlog'                // work/backlog.md
  | 'audit'
  | 'usage'
  | 'system';

export const ALL_EVENT_TOPICS: EventTopic[] = [
  'pipeline',
  'pipeline.timeline',
  'evidence',
  'decisions',
  'config',
  'queue',
  'queue.schedule',
  'gates',
  'checkpoints',
  'epics',
  'backlog',
  'audit',
  'usage',
  'system',
];

// Identifies which run directory a file change belongs to.
export interface RunRef { epicId: string; runId: string; }

export interface FileChangeEvent {
  type: 'file_change';
  projectId: string;               // which workspace this change came from
  topic: EventTopic;
  filePath: string;
  changeType: 'add' | 'change' | 'unlink';
  runRef: RunRef | null;           // set when path is under work/evidence/<epic>/<run>/
  parsedData: unknown;
  ts: string;                      // §7.3: ISO 8601; field was `timestamp` in the salvage source
}

/**
 * MVP1 contract union — contains only FileChangeEvent.
 * Server-local event types (StageLogEvent, HeartbeatEvent, ConnectionEvent)
 * stay outside this contract; each consumer package extends the union locally.
 * MVP2 may promote additional event types here if they become cross-package.
 */
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
