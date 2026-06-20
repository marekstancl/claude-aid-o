// Event pipeline contract types — shared between aid-server watcher and aid-gui WebSocket.
// Adapted per §7.3: timestamp → ts; topics match P047 §7.3 vocabulary exactly.

export type EventTopic =
  | 'pipeline'
  | 'pipeline.timeline'      // timeline.jsonl entries (was pipeline.stage_log in v1 salvage)
  | 'gates'                  // gates_report.json + per-gate outputs
  | 'compliance'             // compliance.json
  | 'checkpoints'            // verifier-output-*.md files
  | 'queue'                  // queue.yaml
  | 'decisions'              // decisions/*.md
  | 'audit'                  // audit-report.md
  | 'epics'                  // EPIC spec files (.aid-o/tasks/*.md)
  | 'backlog'                // work/backlog.md
  | 'config'                 // .aid-o/config/**
  | 'system';                // watcher lifecycle events

export const ALL_EVENT_TOPICS: EventTopic[] = [
  'pipeline',
  'pipeline.timeline',
  'gates',
  'compliance',
  'checkpoints',
  'queue',
  'decisions',
  'audit',
  'epics',
  'backlog',
  'config',
  'system',
];

// Identifies which run directory a file change belongs to.
export interface RunRef { epicId: string; runId: string; }

export interface FileChangeEvent {
  type: 'file_change';
  projectId: string;               // which workspace this change came from
  topic: EventTopic;
  filePath?: string;               // relative path from .aid-o root; omitted in abbreviated emits
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
