/**
 * Queue Scheduling Engine — timer-based scheduler for EPIC queue execution.
 *
 * Manages a 1-second tick that evaluates whether the next EPIC in the queue
 * is ready to start. The scheduler does NOT start EPICs directly — it only
 * signals readiness via events. The orchestrator listens for the "ready"
 * event and handles actual execution.
 *
 * Storage: ~/.aid-gui/schedules.json (per-project schedule configs).
 * Events:
 *   - "status"  — ScheduleStatusEvent broadcast every tick
 *   - "ready"   — emitted when the scheduler determines a new EPIC can start
 */

import { EventEmitter } from 'node:events';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';
import type { ScheduleConfig, SchedulesStorage, ScheduleStatusEvent } from '../types.ts';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const STORAGE_DIR = path.join(os.homedir(), '.aid-gui');
const STORAGE_FILE = path.join(STORAGE_DIR, 'schedules.json');

const DEFAULT_CONFIG: ScheduleConfig = {
  enabled: false,
  cooldownSeconds: 30,
  maxConcurrent: 1,
  delayedStartAt: null,
  autoPauseAtCcLimit: true,
  ccLimitThreshold: 100,
  lastRunCompletedAt: null,
};

const TICK_INTERVAL_MS = 1000;

// ---------------------------------------------------------------------------
// Storage helpers (atomic read/write, same pattern as ideas storage)
// ---------------------------------------------------------------------------

/**
 * Read the schedules.json storage file.
 * Returns a default empty storage if the file does not exist.
 */
async function readStorage(): Promise<SchedulesStorage> {
  try {
    const content = await fs.readFile(STORAGE_FILE, 'utf-8');
    const parsed = JSON.parse(content) as SchedulesStorage;
    if (typeof parsed !== 'object' || parsed === null || typeof parsed.version !== 'number') {
      return { version: 1, schedules: {} };
    }
    if (typeof parsed.schedules !== 'object' || parsed.schedules === null) {
      parsed.schedules = {};
    }
    return parsed;
  } catch (err: unknown) {
    if (err instanceof Error && 'code' in err && (err as NodeJS.ErrnoException).code === 'ENOENT') {
      return { version: 1, schedules: {} };
    }
    throw err;
  }
}

/**
 * Write the schedules.json storage file atomically.
 * Creates the ~/.aid-gui/ directory if it does not exist.
 */
async function writeStorage(storage: SchedulesStorage): Promise<void> {
  await fs.mkdir(STORAGE_DIR, { recursive: true });

  const tmpPath = STORAGE_FILE + '.tmp';
  const content = JSON.stringify(storage, null, 2) + '\n';

  await fs.writeFile(tmpPath, content, 'utf-8');
  await fs.rename(tmpPath, STORAGE_FILE);
}

/**
 * Read the schedule config for a specific project path.
 * Returns the default config if no entry exists for this project.
 */
async function readConfigForProject(projectPath: string): Promise<ScheduleConfig> {
  const storage = await readStorage();
  const config = storage.schedules[projectPath];
  if (!config) {
    return { ...DEFAULT_CONFIG };
  }
  return config;
}

/**
 * Write the schedule config for a specific project path.
 * Merges with existing storage and writes atomically.
 */
async function writeConfigForProject(projectPath: string, config: ScheduleConfig): Promise<void> {
  const storage = await readStorage();
  storage.schedules[projectPath] = config;
  await writeStorage(storage);
}

// ---------------------------------------------------------------------------
// QueueScheduler
// ---------------------------------------------------------------------------

export class QueueScheduler extends EventEmitter {
  private timer: ReturnType<typeof setInterval> | null = null;
  private projectPath: string | null = null;
  private lastStatus: ScheduleStatusEvent | null = null;

  /**
   * Start the scheduler tick for a project.
   * If the scheduler is already running for a different project, it stops
   * the current timer before starting a new one.
   */
  start(projectPath: string): void {
    if (this.timer !== null) {
      this.stop();
    }

    this.projectPath = projectPath;

    this.timer = setInterval(() => {
      this.tick().catch((err: unknown) => {
        const message = err instanceof Error ? err.message : String(err);
        console.error(`[QueueScheduler] Tick error: ${message}`);
      });
    }, TICK_INTERVAL_MS);

    // Run first tick immediately so callers get an initial status.
    this.tick().catch((err: unknown) => {
      const message = err instanceof Error ? err.message : String(err);
      console.error(`[QueueScheduler] Initial tick error: ${message}`);
    });
  }

  /**
   * Stop the scheduler timer. Clears the interval and resets state.
   */
  stop(): void {
    if (this.timer !== null) {
      clearInterval(this.timer);
      this.timer = null;
    }
    this.projectPath = null;
    this.lastStatus = null;
  }

  /**
   * Get the current schedule config for the active project.
   * Returns null if no project is active.
   */
  async getConfig(): Promise<ScheduleConfig | null> {
    if (!this.projectPath) {
      return null;
    }
    return readConfigForProject(this.projectPath);
  }

  /**
   * Update schedule config for a project.
   * Merges the provided partial updates with the existing config.
   * Returns the full updated config.
   */
  async updateConfig(projectPath: string, updates: Partial<ScheduleConfig>): Promise<ScheduleConfig> {
    const current = await readConfigForProject(projectPath);
    const updated: ScheduleConfig = { ...current, ...updates };
    await writeConfigForProject(projectPath, updated);
    return updated;
  }

  /**
   * Get the most recent schedule status event.
   * Returns an idle status if no tick has run yet.
   */
  getStatus(): ScheduleStatusEvent {
    if (this.lastStatus) {
      return this.lastStatus;
    }

    return {
      type: 'schedule_status',
      topic: 'queue.schedule',
      state: 'idle',
      remainingSeconds: null,
      config: { ...DEFAULT_CONFIG },
      timestamp: new Date().toISOString(),
    };
  }

  /**
   * Internal tick handler. Runs every second to evaluate scheduler state
   * and emit appropriate events.
   */
  private async tick(): Promise<void> {
    if (!this.projectPath) {
      return;
    }

    const config = await readConfigForProject(this.projectPath);
    const now = Date.now();

    // 1. If not enabled, emit idle status and skip.
    if (!config.enabled) {
      this.emitStatus('idle', null, config);
      return;
    }

    // 2. If delayedStartAt is set and now < delayedStartAt, emit waiting status.
    if (config.delayedStartAt) {
      const delayedStart = new Date(config.delayedStartAt).getTime();
      if (now < delayedStart) {
        const remainingSeconds = Math.ceil((delayedStart - now) / 1000);
        this.emitStatus('waiting', remainingSeconds, config);
        return;
      }
    }

    // 3. If cooldown active, emit cooldown status with remaining time.
    if (config.lastRunCompletedAt && config.cooldownSeconds > 0) {
      const cooldownEnd = new Date(config.lastRunCompletedAt).getTime() + config.cooldownSeconds * 1000;
      if (now < cooldownEnd) {
        const remainingSeconds = Math.ceil((cooldownEnd - now) / 1000);
        this.emitStatus('cooldown', remainingSeconds, config);
        return;
      }
    }

    // 4. If autoPauseAtCcLimit, check if the queue is paused.
    //    The scheduler does not directly read CC usage; it checks the queue
    //    pause state as a proxy (the orchestrator pauses the queue when
    //    the CC limit is reached).
    if (config.autoPauseAtCcLimit) {
      const isPaused = await this.isQueuePaused();
      if (isPaused) {
        this.emitStatus('paused', null, config);
        return;
      }
    }

    // 5. All conditions clear — emit ready status and signal readiness.
    this.emitStatus('ready', null, config);
    this.emit('ready');
  }

  /**
   * Check if the EPIC queue is currently paused by reading queue.yaml.
   * Returns false if the file cannot be read (queue not initialized).
   */
  private async isQueuePaused(): Promise<boolean> {
    if (!this.projectPath) {
      return false;
    }

    // Derive .aid-o path from project path.
    const aidoPath = path.join(this.projectPath, '.aid-o');
    const queueFilePath = path.join(aidoPath, 'config', 'queue.yaml');

    try {
      const content = await fs.readFile(queueFilePath, 'utf-8');
      // Simple check: look for "paused: true" in the YAML content.
      // This avoids importing the full YAML parser into the scheduler.
      const pausedMatch = content.match(/^paused:\s*(true|false)/m);
      return pausedMatch ? pausedMatch[1] === 'true' : false;
    } catch {
      return false;
    }
  }

  /**
   * Emit a schedule status event and store it as the latest status.
   */
  private emitStatus(
    state: ScheduleStatusEvent['state'],
    remainingSeconds: number | null,
    config: ScheduleConfig,
  ): void {
    const event: ScheduleStatusEvent = {
      type: 'schedule_status',
      topic: 'queue.schedule',
      state,
      remainingSeconds,
      config,
      timestamp: new Date().toISOString(),
    };

    this.lastStatus = event;
    this.emit('status', event);
  }
}

// ---------------------------------------------------------------------------
// Singleton instance
// ---------------------------------------------------------------------------

export const queueScheduler = new QueueScheduler();

// ---------------------------------------------------------------------------
// Exported storage helpers for use by the queue API
// ---------------------------------------------------------------------------

export { readConfigForProject, writeConfigForProject, DEFAULT_CONFIG };
