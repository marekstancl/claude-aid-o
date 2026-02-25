/**
 * Tail-follow streamer for `stage_log.jsonl` files.
 *
 * Watches a stage_log.jsonl file for new appended lines and emits parsed
 * StageLogEvent objects. Maintains a circular buffer of the last N entries
 * (default 100) for replay when new clients connect.
 *
 * Architecture reference: ADR-002, Section "Stage 1b: Watch (Stage Log Streamer)"
 *
 * Usage:
 *   const stream = new StageLogStream({ bufferSize: 100 });
 *   stream.on('event', (event: StageLogEvent) => { ... });
 *   stream.on('replay_ready', () => { ... });
 *   await stream.start('/path/to/stage_log.jsonl');
 *   // Later, on file rotation:
 *   await stream.switchFile('/path/to/new/stage_log.jsonl');
 *   // On shutdown:
 *   stream.stop();
 */

import { EventEmitter } from 'node:events';
import * as fs from 'node:fs';
import * as path from 'node:path';
import type { StageLogEntry, StageLogEvent } from '../types.ts';
import { snakeToCamel } from '../parsers/utils.ts';

// Re-export StageLogEvent for consumers that import from this module.
export type { StageLogEvent } from '../types.ts';

// ---------------------------------------------------------------------------
// StageLogStream options
// ---------------------------------------------------------------------------

export interface StageLogStreamOptions {
  /** Maximum number of entries to keep in the circular buffer. Default: 100. */
  bufferSize?: number;
}

// ---------------------------------------------------------------------------
// CircularBuffer — fixed-size ring buffer for StageLogEvent replay
// ---------------------------------------------------------------------------

/**
 * Fixed-size circular buffer providing O(1) insertion and O(n) ordered
 * retrieval. When full, the oldest entry is overwritten.
 */
class CircularBuffer<T> {
  private readonly items: (T | undefined)[];
  private head: number = 0;
  private count: number = 0;
  private readonly capacity: number;

  constructor(capacity: number) {
    if (capacity < 1) {
      throw new Error(`CircularBuffer capacity must be >= 1, got ${capacity}`);
    }
    this.capacity = capacity;
    this.items = new Array<T | undefined>(capacity).fill(undefined);
  }

  /** Add an item to the buffer. Overwrites the oldest entry when full. */
  push(item: T): void {
    this.items[this.head] = item;
    this.head = (this.head + 1) % this.capacity;
    if (this.count < this.capacity) {
      this.count++;
    }
  }

  /** Return all buffered items in insertion order (oldest first). */
  toArray(): T[] {
    if (this.count === 0) return [];

    const result: T[] = [];
    // When buffer is not yet full, items start at index 0.
    // When full, the oldest item is at `head` (which is where the next write
    // will go, meaning the current value there is the oldest).
    const start = this.count < this.capacity ? 0 : this.head;
    for (let i = 0; i < this.count; i++) {
      const idx = (start + i) % this.capacity;
      result.push(this.items[idx] as T);
    }
    return result;
  }

  /** Clear all entries from the buffer. */
  clear(): void {
    this.items.fill(undefined);
    this.head = 0;
    this.count = 0;
  }

  /** Current number of items in the buffer. */
  get size(): number {
    return this.count;
  }
}

// ---------------------------------------------------------------------------
// Path extraction helpers
// ---------------------------------------------------------------------------

/**
 * Extract epicId and runId from a stage_log.jsonl file path.
 *
 * Expected path pattern:
 *   .../.aid-o/04-engine/evidence/{epicId}/{runId}/stage_log.jsonl
 *
 * If the path does not match the expected pattern, returns placeholder values.
 */
function extractIdsFromPath(filePath: string): { epicId: string; runId: string } {
  // Normalize separators to forward slashes for consistent matching.
  const normalized = filePath.replace(/\\/g, '/');

  // Match: .../evidence/{epicId}/{runId}/stage_log.jsonl
  const match = normalized.match(/evidence\/([^/]+)\/([^/]+)\/stage_log\.jsonl$/);
  if (match) {
    return { epicId: match[1], runId: match[2] };
  }

  // Fallback: use parent directory names.
  const dir = path.dirname(filePath);
  const runId = path.basename(dir);
  const epicId = path.basename(path.dirname(dir));
  return { epicId: epicId || 'unknown', runId: runId || 'unknown' };
}

// ---------------------------------------------------------------------------
// StageLogStream
// ---------------------------------------------------------------------------

/**
 * Tail-follow streamer for stage_log.jsonl files.
 *
 * Emits:
 *   - `'event'`        — a new StageLogEvent for each appended line
 *   - `'replay_ready'` — fired after initial file read populates the buffer
 *   - `'error'`        — non-fatal errors (malformed lines, watch failures)
 *
 * The streamer tracks its byte offset in the file and only reads new content
 * after each fs.watch notification. This avoids re-parsing the entire file
 * on every append.
 */
export class StageLogStream extends EventEmitter {
  private readonly buffer: CircularBuffer<StageLogEvent>;
  private watcher: fs.FSWatcher | null = null;
  private filePath: string | null = null;
  private byteOffset: number = 0;
  private epicId: string = 'unknown';
  private runId: string = 'unknown';
  private reading: boolean = false;
  private pendingRead: boolean = false;
  private stopped: boolean = false;
  /** Incomplete line fragment carried over between reads. */
  private lineRemainder: string = '';

  constructor(options?: StageLogStreamOptions) {
    super();
    const bufferSize = options?.bufferSize ?? 100;
    this.buffer = new CircularBuffer<StageLogEvent>(bufferSize);
  }

  /**
   * Start tailing the specified stage_log.jsonl file.
   *
   * Reads any existing content into the buffer (up to bufferSize entries),
   * then watches for new appends.
   *
   * @param filePath - Absolute path to the stage_log.jsonl file.
   */
  async start(filePath: string): Promise<void> {
    if (this.watcher) {
      this.stop();
    }

    this.stopped = false;
    this.filePath = filePath;
    this.byteOffset = 0;
    this.lineRemainder = '';
    const ids = extractIdsFromPath(filePath);
    this.epicId = ids.epicId;
    this.runId = ids.runId;

    // Read existing content for the replay buffer.
    await this.readNewContent();
    this.emit('replay_ready');

    // Start watching for changes.
    this.startWatching();
  }

  /**
   * Stop tailing the current file. Closes the watcher but preserves the
   * buffer contents (use switchFile to clear the buffer).
   */
  stop(): void {
    this.stopped = true;
    if (this.watcher) {
      this.watcher.close();
      this.watcher = null;
    }
    this.filePath = null;
    this.lineRemainder = '';
  }

  /**
   * Handle file rotation: stop watching the old file, clear the buffer,
   * and start tailing a new file from the beginning.
   *
   * @param newFilePath - Absolute path to the new stage_log.jsonl file.
   */
  async switchFile(newFilePath: string): Promise<void> {
    this.stop();
    this.buffer.clear();
    this.byteOffset = 0;
    this.lineRemainder = '';
    await this.start(newFilePath);
  }

  /**
   * Return the current buffer contents for replay.
   * Entries are ordered from oldest to newest.
   */
  getBuffer(): StageLogEvent[] {
    return this.buffer.toArray();
  }

  /**
   * Return the number of events currently in the buffer.
   */
  get bufferSize(): number {
    return this.buffer.size;
  }

  /**
   * Return the file path currently being tailed, or null if stopped.
   */
  get currentFilePath(): string | null {
    return this.filePath;
  }

  // -------------------------------------------------------------------------
  // Private methods
  // -------------------------------------------------------------------------

  /**
   * Set up fs.watch on the target file. On each 'change' event, read new
   * content from the last known byte offset.
   */
  private startWatching(): void {
    if (!this.filePath || this.stopped) return;

    try {
      this.watcher = fs.watch(this.filePath, (eventType) => {
        if (this.stopped) return;

        if (eventType === 'change') {
          this.scheduleRead();
        } else if (eventType === 'rename') {
          // File was renamed or deleted — could indicate rotation.
          // Emit an error so the coordinator can decide what to do.
          this.emit('error', new Error(
            `Watched file was renamed or deleted: ${this.filePath}`
          ));
        }
      });

      this.watcher.on('error', (err: Error) => {
        this.emit('error', new Error(
          `fs.watch error on ${this.filePath}: ${err.message}`
        ));
      });
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      this.emit('error', new Error(
        `Failed to start watching ${this.filePath}: ${message}`
      ));
    }
  }

  /**
   * Schedule a read of new content. If a read is already in progress,
   * set a flag to re-read after the current read completes (coalescing
   * multiple rapid fs.watch events into fewer reads).
   */
  private scheduleRead(): void {
    if (this.reading) {
      this.pendingRead = true;
      return;
    }
    this.readNewContent().catch((err: unknown) => {
      const message = err instanceof Error ? err.message : String(err);
      this.emit('error', new Error(`Read error: ${message}`));
    });
  }

  /**
   * Read new bytes from the file starting at the current byte offset,
   * split into lines, parse each line as JSON, and emit events.
   */
  private async readNewContent(): Promise<void> {
    if (!this.filePath || this.stopped) return;

    this.reading = true;
    try {
      // Check file size to determine if there is new content.
      let stats: fs.Stats;
      try {
        stats = fs.statSync(this.filePath);
      } catch {
        // File may not exist yet — wait for it.
        return;
      }

      const fileSize = stats.size;

      // If the file shrank (e.g., truncated/replaced), reset offset.
      if (fileSize < this.byteOffset) {
        this.byteOffset = 0;
        this.lineRemainder = '';
      }

      // Nothing new to read.
      if (fileSize === this.byteOffset) return;

      // Read only the new bytes.
      const bytesToRead = fileSize - this.byteOffset;
      const buffer = Buffer.alloc(bytesToRead);

      const fd = fs.openSync(this.filePath, 'r');
      try {
        fs.readSync(fd, buffer, 0, bytesToRead, this.byteOffset);
      } finally {
        fs.closeSync(fd);
      }

      this.byteOffset = fileSize;
      const chunk = buffer.toString('utf-8');

      this.processChunk(chunk);
    } finally {
      this.reading = false;

      // If another change came in while we were reading, do another read.
      if (this.pendingRead) {
        this.pendingRead = false;
        this.scheduleRead();
      }
    }
  }

  /**
   * Process a chunk of text: combine with any leftover partial line from
   * the previous read, split by newlines, and parse complete lines.
   */
  private processChunk(chunk: string): void {
    const text = this.lineRemainder + chunk;
    const lines = text.split('\n');

    // The last element may be an incomplete line if the chunk did not end
    // with a newline. Save it for the next read.
    this.lineRemainder = lines.pop() ?? '';

    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.length === 0) continue;

      this.parseLine(trimmed);
    }
  }

  /**
   * Parse a single JSON line into a StageLogEntry, wrap it in a
   * StageLogEvent, add to buffer, and emit.
   */
  private parseLine(line: string): void {
    let raw: unknown;
    try {
      raw = JSON.parse(line);
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Invalid JSON';
      this.emit('error', new Error(
        `Malformed JSON line in ${this.filePath}: ${message}`
      ));
      return;
    }

    // Convert snake_case keys to camelCase using the shared utility.
    const entry = snakeToCamel<StageLogEntry>(raw);

    const event: StageLogEvent = {
      type: 'stage_log',
      topic: 'pipeline.stage_log',
      entry,
      epicId: this.epicId,
      runId: this.runId,
      timestamp: new Date().toISOString(),
    };

    this.buffer.push(event);
    this.emit('event', event);
  }
}
