/**
 * Unit tests for the FileWatcher class.
 *
 * Tests path classification, event emission, debouncing, and lifecycle.
 * Uses the public classifyPath method directly (no filesystem operations).
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';
import { FileWatcher } from '../../../server/watchers/file-watcher.ts';
import type { FileChangeEvent, PathClassification } from '../../../server/types.ts';

// ---------------------------------------------------------------------------
// Path Classification Tests (pure, no filesystem)
// ---------------------------------------------------------------------------

describe('FileWatcher.classifyPath', () => {
  const AIDO_PATH = '/project/.aid-o';
  let watcher: FileWatcher;

  beforeEach(() => {
    watcher = new FileWatcher(AIDO_PATH);
  });

  it('classifies auto-mode-state.yaml as pipeline topic', () => {
    const result = watcher.classifyPath(
      '/project/.aid-o/04-engine/auto-mode-state.yaml',
    );
    expect(result).toEqual({
      topic: 'pipeline',
      parser: 'yaml',
      excluded: false,
    });
  });

  it('classifies plan_progress.json as pipeline topic', () => {
    const result = watcher.classifyPath(
      '/project/.aid-o/04-engine/evidence/E-001/20260101T000000Z/plan_progress.json',
    );
    expect(result).toEqual({
      topic: 'pipeline',
      parser: 'json',
      excluded: false,
    });
  });

  it('classifies plan.json as pipeline topic', () => {
    const result = watcher.classifyPath(
      '/project/.aid-o/04-engine/evidence/E-001/run1/plan.json',
    );
    expect(result).toEqual({
      topic: 'pipeline',
      parser: 'json',
      excluded: false,
    });
  });

  it('classifies epic-queue.yaml as queue topic', () => {
    const result = watcher.classifyPath(
      '/project/.aid-o/04-engine/epic-queue.yaml',
    );
    expect(result).toEqual({
      topic: 'queue',
      parser: 'yaml',
      excluded: false,
    });
  });

  it('classifies stage_log.jsonl as excluded', () => {
    const result = watcher.classifyPath(
      '/project/.aid-o/04-engine/evidence/E-001/run1/stage_log.jsonl',
    );
    expect(result).not.toBeNull();
    expect(result!.excluded).toBe(true);
    expect(result!.topic).toBe('pipeline.stage_log');
  });

  it('classifies pm_decision.json as decisions topic', () => {
    const result = watcher.classifyPath(
      '/project/.aid-o/04-engine/evidence/E-001/run1/pm_decision.json',
    );
    expect(result).toEqual({
      topic: 'decisions',
      parser: 'json',
      excluded: false,
    });
  });

  it('classifies pm_plan_approval.json as decisions topic', () => {
    const result = watcher.classifyPath(
      '/project/.aid-o/04-engine/evidence/E-001/run1/pm_plan_approval.json',
    );
    expect(result).toEqual({
      topic: 'decisions',
      parser: 'json',
      excluded: false,
    });
  });

  it('classifies gates_report.json as pipeline topic', () => {
    const result = watcher.classifyPath(
      '/project/.aid-o/04-engine/evidence/E-001/run1/gates_report.json',
    );
    expect(result).toEqual({
      topic: 'pipeline',
      parser: 'json',
      excluded: false,
    });
  });

  it('classifies gates/gates_report.json as pipeline topic', () => {
    const result = watcher.classifyPath(
      '/project/.aid-o/04-engine/evidence/E-001/run1/gates/gates_report.json',
    );
    expect(result).toEqual({
      topic: 'pipeline',
      parser: 'json',
      excluded: false,
    });
  });

  it('classifies audit-report.yaml as audit topic with yaml parser', () => {
    const result = watcher.classifyPath(
      '/project/.aid-o/04-engine/evidence/E-001/run1/audit-report.yaml',
    );
    expect(result).not.toBeNull();
    expect(result!.topic).toBe('audit');
    expect(result!.parser).toBe('yaml');
    expect(result!.excluded).toBe(false);
  });

  it('classifies audit-report.md as audit topic with markdown parser', () => {
    const result = watcher.classifyPath(
      '/project/.aid-o/04-engine/evidence/E-001/run1/audit-report.md',
    );
    expect(result).not.toBeNull();
    expect(result!.topic).toBe('audit');
    expect(result!.parser).toBe('markdown');
  });

  it('classifies evidence catch-all files as evidence topic', () => {
    const result = watcher.classifyPath(
      '/project/.aid-o/04-engine/evidence/E-001/run1/steps/step_1/output.md',
    );
    expect(result).not.toBeNull();
    expect(result!.topic).toBe('evidence');
  });

  it('classifies config directory files as config topic', () => {
    const result = watcher.classifyPath(
      '/project/.aid-o/03-config/permissions-auto.yaml',
    );
    expect(result).toEqual({
      topic: 'config',
      parser: null,
      excluded: false,
    });
  });

  it('classifies EPIC spec .md files as pipeline topic with epicSpec parser', () => {
    const result = watcher.classifyPath(
      '/project/.aid-o/02-epics/E-005-1_4-gui-foundation.md',
    );
    expect(result).toEqual({
      topic: 'pipeline',
      parser: 'epicSpec',
      excluded: false,
    });
  });

  it('classifies plan directory files as config topic with markdown parser', () => {
    const result = watcher.classifyPath(
      '/project/.aid-o/01-plans/P005-C.md',
    );
    expect(result).toEqual({
      topic: 'config',
      parser: 'markdown',
      excluded: false,
    });
  });

  it('classifies engine memory files as config topic', () => {
    const result = watcher.classifyPath(
      '/project/.aid-o/04-engine/memory/lessons-learned.md',
    );
    expect(result).toEqual({
      topic: 'config',
      parser: null,
      excluded: false,
    });
  });

  it('classifies run spec files as pipeline topic', () => {
    const result = watcher.classifyPath(
      '/project/.aid-o/04-engine/runs/run-spec.yaml',
    );
    expect(result).toEqual({
      topic: 'pipeline',
      parser: null,
      excluded: false,
    });
  });

  it('returns null for paths outside the .aid-o directory', () => {
    const result = watcher.classifyPath('/project/src/index.ts');
    expect(result).toBeNull();
  });

  it('returns null for unrecognized files in .aid-o root', () => {
    const result = watcher.classifyPath('/project/.aid-o/unknown.txt');
    expect(result).toBeNull();
  });

  it('handles nested EPIC evidence paths correctly', () => {
    const result = watcher.classifyPath(
      '/project/.aid-o/04-engine/evidence/E-005-2_4/20260225T143000Z/plan_progress.json',
    );
    expect(result).toEqual({
      topic: 'pipeline',
      parser: 'json',
      excluded: false,
    });
  });
});

// ---------------------------------------------------------------------------
// FileWatcher Lifecycle & Event Emission (requires temp filesystem)
// ---------------------------------------------------------------------------

describe('FileWatcher lifecycle (filesystem)', () => {
  let tmpDir: string;
  let aidoDir: string;
  let watcher: FileWatcher;

  beforeEach(async () => {
    tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'fw-test-'));
    aidoDir = path.join(tmpDir, '.aid-o');
    await fs.mkdir(path.join(aidoDir, '04-engine'), { recursive: true });
  });

  afterEach(async () => {
    if (watcher) {
      await watcher.stop();
    }
    await fs.rm(tmpDir, { recursive: true, force: true });
  });

  it('emits ready event after start', async () => {
    watcher = new FileWatcher(aidoDir);
    let readyFired = false;
    watcher.on('ready', () => {
      readyFired = true;
    });
    await watcher.start();
    expect(readyFired).toBe(true);
  });

  it('start is idempotent', async () => {
    watcher = new FileWatcher(aidoDir);
    await watcher.start();
    // Second start should return immediately without error.
    await watcher.start();
  });

  it('stop is safe to call when not started', async () => {
    watcher = new FileWatcher(aidoDir);
    // Should not throw.
    await watcher.stop();
  });

  it('emits a file_change event when a json file is created', async () => {
    watcher = new FileWatcher(aidoDir, { debounceMs: 20 });
    await watcher.start();

    const events: FileChangeEvent[] = [];
    watcher.on('event', (e: FileChangeEvent) => events.push(e));

    const targetDir = path.join(aidoDir, '04-engine');
    const filePath = path.join(targetDir, 'epic-queue.yaml');

    await fs.writeFile(filePath, 'paused: false\nqueue: []\n');

    // Wait for debounce + chokidar stabilityThreshold
    await new Promise((r) => setTimeout(r, 300));

    // Should have received at least one event
    const queueEvents = events.filter((e) => e.topic === 'queue');
    expect(queueEvents.length).toBeGreaterThanOrEqual(1);
    expect(queueEvents[0].type).toBe('file_change');
    expect(queueEvents[0].changeType).toBe('add');
    expect(queueEvents[0].parsedData).not.toBeNull();
  });

  it('does not emit events for excluded files (stage_log.jsonl)', async () => {
    watcher = new FileWatcher(aidoDir, { debounceMs: 20 });
    const evidenceDir = path.join(aidoDir, '04-engine', 'evidence', 'E-001', 'run1');
    await fs.mkdir(evidenceDir, { recursive: true });
    await watcher.start();

    const events: FileChangeEvent[] = [];
    watcher.on('event', (e: FileChangeEvent) => events.push(e));

    await fs.writeFile(
      path.join(evidenceDir, 'stage_log.jsonl'),
      '{"timestamp":"2026-01-01T00:00:00Z","state":"IDLE","step":null,"action":"test","details":"test","result":"pass"}\n',
    );

    await new Promise((r) => setTimeout(r, 300));

    // Should not have received any event for stage_log.jsonl
    const stageLogEvents = events.filter((e) => e.topic === 'pipeline.stage_log');
    expect(stageLogEvents.length).toBe(0);
  });

  it('emits events with parsed data for yaml files', async () => {
    watcher = new FileWatcher(aidoDir, { debounceMs: 20 });
    await watcher.start();

    const events: FileChangeEvent[] = [];
    watcher.on('event', (e: FileChangeEvent) => events.push(e));

    const filePath = path.join(aidoDir, '04-engine', 'auto-mode-state.yaml');
    await fs.writeFile(filePath, 'session:\n  mode: auto\n  session_id: FA-test\n');

    await new Promise((r) => setTimeout(r, 300));

    const pipelineEvents = events.filter((e) => e.topic === 'pipeline');
    expect(pipelineEvents.length).toBeGreaterThanOrEqual(1);
    // Parsed YAML data should be present
    expect(pipelineEvents[0].parsedData).not.toBeNull();
    expect(typeof pipelineEvents[0].parsedData).toBe('object');
  });
});
