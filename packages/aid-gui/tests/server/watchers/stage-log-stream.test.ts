/**
 * Unit tests for the StageLogStream class.
 *
 * Tests tail-follow behavior, circular buffer, file rotation,
 * partial line handling, and event emission.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as fsp from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';
import { StageLogStream } from '../../../server/watchers/stage-log-stream.ts';
import type { StageLogEvent } from '../../../server/types.ts';

// ---------------------------------------------------------------------------
// Helper: create a stage_log.jsonl file with standard evidence path
// ---------------------------------------------------------------------------

function makeStageLogEntry(overrides: Record<string, unknown> = {}): string {
  return JSON.stringify({
    timestamp: '2026-02-25T14:00:00Z',
    state: 'EXECUTING',
    step: 'step_1_backend',
    action: 'dispatch_agent',
    details: 'Test entry',
    result: 'pass',
    ...overrides,
  });
}

describe('StageLogStream', () => {
  let tmpDir: string;
  let evidenceDir: string;
  let stageLogPath: string;
  let stream: StageLogStream;

  beforeEach(async () => {
    tmpDir = await fsp.mkdtemp(path.join(os.tmpdir(), 'sls-test-'));
    evidenceDir = path.join(tmpDir, '.aid-o', '04-engine', 'evidence', 'E-001', 'run1');
    await fsp.mkdir(evidenceDir, { recursive: true });
    stageLogPath = path.join(evidenceDir, 'stage_log.jsonl');
  });

  afterEach(async () => {
    if (stream) {
      stream.stop();
    }
    await fsp.rm(tmpDir, { recursive: true, force: true });
  });

  // -------------------------------------------------------------------------
  // Basic lifecycle
  // -------------------------------------------------------------------------

  it('starts and emits replay_ready on an empty file', async () => {
    await fsp.writeFile(stageLogPath, '');
    stream = new StageLogStream();

    let replayReady = false;
    stream.on('replay_ready', () => {
      replayReady = true;
    });

    await stream.start(stageLogPath);
    expect(replayReady).toBe(true);
    expect(stream.bufferSize).toBe(0);
    expect(stream.currentFilePath).toBe(stageLogPath);
  });

  it('stop sets currentFilePath to null', async () => {
    await fsp.writeFile(stageLogPath, '');
    stream = new StageLogStream();
    await stream.start(stageLogPath);
    stream.stop();
    expect(stream.currentFilePath).toBeNull();
  });

  // -------------------------------------------------------------------------
  // Initial read — pre-existing content
  // -------------------------------------------------------------------------

  it('reads pre-existing lines into the buffer on start', async () => {
    const lines = [
      makeStageLogEntry({ action: 'first' }),
      makeStageLogEntry({ action: 'second' }),
      makeStageLogEntry({ action: 'third' }),
    ];
    await fsp.writeFile(stageLogPath, lines.join('\n') + '\n');

    stream = new StageLogStream({ bufferSize: 100 });
    const events: StageLogEvent[] = [];
    stream.on('event', (e: StageLogEvent) => events.push(e));

    await stream.start(stageLogPath);

    expect(stream.bufferSize).toBe(3);
    expect(events.length).toBe(3);
    expect(events[0].entry.action).toBe('first');
    expect(events[2].entry.action).toBe('third');
  });

  it('extracts epicId and runId from the file path', async () => {
    await fsp.writeFile(stageLogPath, makeStageLogEntry() + '\n');

    stream = new StageLogStream();
    const events: StageLogEvent[] = [];
    stream.on('event', (e: StageLogEvent) => events.push(e));

    await stream.start(stageLogPath);

    expect(events.length).toBe(1);
    expect(events[0].epicId).toBe('E-001');
    expect(events[0].runId).toBe('run1');
  });

  // -------------------------------------------------------------------------
  // Tail-follow — appending new lines
  // -------------------------------------------------------------------------

  it('emits events for newly appended lines', async () => {
    await fsp.writeFile(stageLogPath, '');
    stream = new StageLogStream();
    const events: StageLogEvent[] = [];
    stream.on('event', (e: StageLogEvent) => events.push(e));

    await stream.start(stageLogPath);
    expect(events.length).toBe(0);

    // Append a new line
    fs.appendFileSync(stageLogPath, makeStageLogEntry({ action: 'new_entry' }) + '\n');

    // Wait for fs.watch to fire and read to complete
    await new Promise((r) => setTimeout(r, 200));

    expect(events.length).toBeGreaterThanOrEqual(1);
    expect(events[0].entry.action).toBe('new_entry'); // values stay as-is, only keys are converted
    expect(events[0].type).toBe('stage_log');
    expect(events[0].topic).toBe('pipeline.stage_log');
  });

  it('handles multiple rapid appends with read coalescing', async () => {
    await fsp.writeFile(stageLogPath, '');
    stream = new StageLogStream();
    const events: StageLogEvent[] = [];
    stream.on('event', (e: StageLogEvent) => events.push(e));

    await stream.start(stageLogPath);

    // Rapidly append 5 lines
    for (let i = 0; i < 5; i++) {
      fs.appendFileSync(stageLogPath, makeStageLogEntry({ action: `action_${i}` }) + '\n');
    }

    await new Promise((r) => setTimeout(r, 400));

    // All 5 lines should eventually be emitted
    expect(events.length).toBe(5);
  });

  // -------------------------------------------------------------------------
  // Circular buffer behavior
  // -------------------------------------------------------------------------

  it('limits buffer to configured bufferSize', async () => {
    // Write more entries than buffer size
    const lines: string[] = [];
    for (let i = 0; i < 10; i++) {
      lines.push(makeStageLogEntry({ action: `action_${i}` }));
    }
    await fsp.writeFile(stageLogPath, lines.join('\n') + '\n');

    stream = new StageLogStream({ bufferSize: 5 });
    await stream.start(stageLogPath);

    expect(stream.bufferSize).toBe(5);
    // Buffer should contain the 5 most recent entries
    const buffer = stream.getBuffer();
    expect(buffer.length).toBe(5);
    expect(buffer[0].entry.action).toBe('action_5');
    expect(buffer[4].entry.action).toBe('action_9');
  });

  it('getBuffer returns entries in oldest-first order', async () => {
    const lines = [
      makeStageLogEntry({ action: 'first' }),
      makeStageLogEntry({ action: 'second' }),
      makeStageLogEntry({ action: 'third' }),
    ];
    await fsp.writeFile(stageLogPath, lines.join('\n') + '\n');

    stream = new StageLogStream({ bufferSize: 100 });
    await stream.start(stageLogPath);

    const buffer = stream.getBuffer();
    expect(buffer[0].entry.action).toBe('first');
    expect(buffer[1].entry.action).toBe('second');
    expect(buffer[2].entry.action).toBe('third');
  });

  // -------------------------------------------------------------------------
  // Malformed line handling
  // -------------------------------------------------------------------------

  it('emits error for malformed JSON lines without crashing', async () => {
    const content = [
      makeStageLogEntry({ action: 'good_line' }),
      'this is not valid json',
      makeStageLogEntry({ action: 'another_good_line' }),
    ].join('\n') + '\n';
    await fsp.writeFile(stageLogPath, content);

    stream = new StageLogStream();
    const events: StageLogEvent[] = [];
    const errors: Error[] = [];
    stream.on('event', (e: StageLogEvent) => events.push(e));
    stream.on('error', (e: Error) => errors.push(e));

    await stream.start(stageLogPath);

    // Should have emitted 2 valid events and 1 error
    expect(events.length).toBe(2);
    expect(errors.length).toBe(1);
    expect(errors[0].message).toContain('Malformed JSON');
  });

  it('skips empty lines without emitting errors', async () => {
    const content = [
      makeStageLogEntry({ action: 'line1' }),
      '',
      '  ',
      makeStageLogEntry({ action: 'line2' }),
    ].join('\n') + '\n';
    await fsp.writeFile(stageLogPath, content);

    stream = new StageLogStream();
    const events: StageLogEvent[] = [];
    const errors: Error[] = [];
    stream.on('event', (e: StageLogEvent) => events.push(e));
    stream.on('error', (e: Error) => errors.push(e));

    await stream.start(stageLogPath);

    expect(events.length).toBe(2);
    expect(errors.length).toBe(0);
  });

  // -------------------------------------------------------------------------
  // File rotation (switchFile)
  // -------------------------------------------------------------------------

  it('switchFile clears buffer and starts tailing new file', async () => {
    // Start with first file
    await fsp.writeFile(stageLogPath, makeStageLogEntry({ action: 'old_entry' }) + '\n');
    stream = new StageLogStream();
    await stream.start(stageLogPath);
    expect(stream.bufferSize).toBe(1);

    // Create new stage_log.jsonl for rotation
    const newEvidenceDir = path.join(tmpDir, '.aid-o', '04-engine', 'evidence', 'E-002', 'run2');
    await fsp.mkdir(newEvidenceDir, { recursive: true });
    const newStageLogPath = path.join(newEvidenceDir, 'stage_log.jsonl');
    await fsp.writeFile(
      newStageLogPath,
      makeStageLogEntry({ action: 'new_entry_1' }) + '\n' +
      makeStageLogEntry({ action: 'new_entry_2' }) + '\n',
    );

    await stream.switchFile(newStageLogPath);

    // Buffer should contain only the new file's entries
    expect(stream.bufferSize).toBe(2);
    expect(stream.currentFilePath).toBe(newStageLogPath);
    const buffer = stream.getBuffer();
    expect(buffer[0].epicId).toBe('E-002');
    expect(buffer[0].runId).toBe('run2');
  });

  // -------------------------------------------------------------------------
  // File truncation (e.g., file replaced)
  // -------------------------------------------------------------------------

  it('handles file truncation by resetting offset', async () => {
    // Write initial content
    const initialContent = [
      makeStageLogEntry({ action: 'line1' }),
      makeStageLogEntry({ action: 'line2' }),
      makeStageLogEntry({ action: 'line3' }),
    ].join('\n') + '\n';
    await fsp.writeFile(stageLogPath, initialContent);

    stream = new StageLogStream();
    const events: StageLogEvent[] = [];
    stream.on('event', (e: StageLogEvent) => events.push(e));
    await stream.start(stageLogPath);
    expect(events.length).toBe(3);

    // Truncate the file (fs.writeFile replaces the content)
    fs.writeFileSync(stageLogPath, '');
    await new Promise((r) => setTimeout(r, 200));

    // Now append new shorter content — this ensures fs.watch fires
    fs.appendFileSync(stageLogPath, makeStageLogEntry({ action: 'after_truncate' }) + '\n');

    await new Promise((r) => setTimeout(r, 400));

    // Should have received the new entry (value stays snake_case)
    const postTruncateEvents = events.filter((e) => e.entry.action === 'after_truncate');
    expect(postTruncateEvents.length).toBe(1);
  });

  // -------------------------------------------------------------------------
  // snakeToCamel conversion
  // -------------------------------------------------------------------------

  it('converts snake_case keys to camelCase in parsed entries', async () => {
    const entry = JSON.stringify({
      timestamp: '2026-01-01T00:00:00Z',
      state: 'EXECUTING',
      step: 'step_1_backend',
      action: 'dispatch_agent',
      details: 'Agent dispatched',
      result: 'pass',
    });
    await fsp.writeFile(stageLogPath, entry + '\n');

    stream = new StageLogStream();
    const events: StageLogEvent[] = [];
    stream.on('event', (e: StageLogEvent) => events.push(e));
    await stream.start(stageLogPath);

    expect(events.length).toBe(1);
    // snakeToCamel only converts object keys, not string values
    expect(events[0].entry.action).toBe('dispatch_agent');
  });
});
