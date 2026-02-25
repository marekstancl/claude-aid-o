import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { useStore } from '../store';
import { createApiClient } from '../api/client';
import { cn } from '../lib/utils';
import {
  User,
  Database,
  Layout,
  ShieldCheck,
  FileText,
  Clock,
  ChevronRight,
  Play,
  Pause,
  RotateCcw,
  SkipBack,
  SkipForward,
  WifiOff,
  AlertTriangle,
  Loader2,
} from 'lucide-react';
import type { PlanStep, StageLogEntryResponse, ApiError } from '../types/api';
import type { StepStatus, ReplayState } from '../types/store';

// ---------------------------------------------------------------------------
// Local types
// ---------------------------------------------------------------------------

interface Step {
  id: string;
  label: string;
  role: string;
  status: 'completed' | 'active' | 'pending' | 'failed' | 'skipped';
  duration?: string;
}

const roleIcons: Record<string, React.ComponentType<{ size: number }>> = {
  architect: User,
  backend: Database,
  frontend: Layout,
  security: ShieldCheck,
  docs: FileText,
};

// ---------------------------------------------------------------------------
// API client (matches existing codebase pattern)
// ---------------------------------------------------------------------------

const client = createApiClient('default');

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const SPEED_OPTIONS = [1, 2, 4] as const;

/**
 * Default delay between replay events when timestamps are identical or
 * very close together. This prevents events from being skipped too quickly
 * during playback.
 */
const MIN_REPLAY_DELAY_MS = 300;

/**
 * Maximum delay between replay events, to prevent excessively long waits
 * when there are large gaps between timestamps in the log.
 */
const MAX_REPLAY_DELAY_MS = 3000;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Map a PlanStep and its StepStatus into the local Step interface used
 * for rendering. Falls back to 'pending' when no status is available.
 */
function mapPlanStepToStep(
  planStep: PlanStep,
  stepStatus: StepStatus | undefined,
  currentStepId: string | null,
): Step {
  let status: Step['status'] = 'pending';

  if (stepStatus) {
    switch (stepStatus.status) {
      case 'done':
        status = 'completed';
        break;
      case 'executing':
        status = 'active';
        break;
      case 'failed':
        status = 'failed';
        break;
      case 'skipped':
        status = 'skipped';
        break;
      default:
        status = 'pending';
    }
  }

  // If the pipeline currentStepId matches this step and it is still pending,
  // mark it as active (covers the case where stepStatuses hasn't caught up yet).
  if (currentStepId === planStep.id && status === 'pending') {
    status = 'active';
  }

  // Compute a human-readable duration if timing is available
  let duration: string | undefined;
  if (stepStatus?.startedAt && stepStatus?.completedAt) {
    const startMs = new Date(stepStatus.startedAt).getTime();
    const endMs = new Date(stepStatus.completedAt).getTime();
    const diffSec = Math.round((endMs - startMs) / 1000);
    if (diffSec < 60) {
      duration = `${diffSec}s`;
    } else {
      const mins = Math.floor(diffSec / 60);
      const secs = diffSec % 60;
      duration = `${mins}m ${secs}s`;
    }
  }

  return {
    id: planStep.id,
    label:
      planStep.objective.length > 40
        ? planStep.objective.slice(0, 37) + '...'
        : planStep.objective,
    role: planStep.role,
    status,
    duration,
  };
}

/**
 * Given the full stage_log events up to (and including) `endIndex`,
 * reconstruct per-step statuses by scanning the events. This is how
 * we rebuild the pipeline visual state at any point in the replay.
 */
function reconstructStepStatuses(
  events: StageLogEntryResponse[],
  endIndex: number,
): Record<string, StepStatus> {
  const statuses: Record<string, StepStatus> = {};

  for (let i = 0; i <= endIndex && i < events.length; i++) {
    const event = events[i];
    if (!event.step) continue;

    const stepId = event.step;

    // Initialize if not seen yet
    if (!statuses[stepId]) {
      statuses[stepId] = { status: 'pending' };
    }

    // Map event action/result to step status
    const action = event.action.toLowerCase();
    const result = event.result;

    if (action.includes('dispatch') || action.includes('start') || action === 'executing') {
      statuses[stepId] = {
        ...statuses[stepId],
        status: 'executing',
        startedAt: statuses[stepId].startedAt ?? event.timestamp,
      };
    } else if (result === 'pass' || result === 'success') {
      statuses[stepId] = {
        ...statuses[stepId],
        status: 'done',
        completedAt: event.timestamp,
      };
    } else if (result === 'fail') {
      statuses[stepId] = {
        ...statuses[stepId],
        status: 'failed',
        completedAt: event.timestamp,
      };
    } else if (result === 'skip') {
      statuses[stepId] = {
        ...statuses[stepId],
        status: 'skipped',
        completedAt: event.timestamp,
      };
    }
  }

  return statuses;
}

/**
 * Extract the current FSM state from the replay event at the given index.
 */
function getReplayFsmState(
  events: StageLogEntryResponse[],
  index: number,
): string {
  if (events.length === 0 || index < 0) return 'IDLE';
  const clamped = Math.min(index, events.length - 1);
  return events[clamped].state;
}

/**
 * Extract the currently active step ID at the given replay index.
 * The "active" step is the most recent event's step field that indicates
 * an executing action.
 */
function getReplayCurrentStepId(
  events: StageLogEntryResponse[],
  index: number,
): string | null {
  // Walk backward from the index to find the most recent step-related event
  for (let i = Math.min(index, events.length - 1); i >= 0; i--) {
    if (events[i].step) {
      return events[i].step;
    }
  }
  return null;
}

/**
 * Compute the delay (in ms) between two consecutive replay events,
 * adjusted by the playback speed. Clamped to [MIN, MAX] range.
 */
function computeReplayDelay(
  events: StageLogEntryResponse[],
  fromIndex: number,
  speed: number,
): number {
  if (fromIndex + 1 >= events.length) return MIN_REPLAY_DELAY_MS;

  const t1 = new Date(events[fromIndex].timestamp).getTime();
  const t2 = new Date(events[fromIndex + 1].timestamp).getTime();
  const rawDelta = Math.abs(t2 - t1);

  // Scale real-time delta into a reasonable replay delay
  // Use log scale to compress very large gaps
  const scaledMs = rawDelta > 0 ? Math.min(rawDelta, MAX_REPLAY_DELAY_MS) : MIN_REPLAY_DELAY_MS;
  const adjusted = Math.max(MIN_REPLAY_DELAY_MS, scaledMs / speed);

  return Math.min(adjusted, MAX_REPLAY_DELAY_MS);
}

/**
 * Format a timestamp for display in the scrub bar.
 */
function formatTimestamp(iso: string): string {
  try {
    const d = new Date(iso);
    return d.toLocaleTimeString(undefined, {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
  } catch {
    return iso;
  }
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export const PipelineTheater: React.FC = () => {
  // --- Live pipeline state from store ---
  const planSteps = useStore((s) => s.steps);
  const liveStepStatuses = useStore((s) => s.stepStatuses);
  const liveCurrentStepId = useStore((s) => s.currentStepId);
  const { fsmState, progress } = useStore();
  const wsStatus = useStore((s) => s.wsStatus);
  const pipelineProgress = useStore((s) => s.pipelineProgress);

  // --- Replay state from store ---
  const replayState = useStore((s) => s.replayState);
  const replayEvents = useStore((s) => s.replayEvents);
  const replayIndex = useStore((s) => s.replayIndex);
  const playbackSpeed = useStore((s) => s.playbackSpeed);
  const setReplayState = useStore((s) => s.setReplayState);
  const setReplayEvents = useStore((s) => s.setReplayEvents);
  const setReplayIndex = useStore((s) => s.setReplayIndex);
  const setPlaybackSpeed = useStore((s) => s.setPlaybackSpeed);
  const resetReplay = useStore((s) => s.resetReplay);

  // --- Local UI state ---
  const [selectedStep, setSelectedStep] = useState<Step | null>(null);
  const [loadingLog, setLoadingLog] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);

  // Ref for the playback timer so we can cancel it
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const isLoading = wsStatus === 'connecting';
  const isDisconnected = wsStatus === 'disconnected';
  const isReconnecting = wsStatus === 'reconnecting';
  const hasSteps = planSteps.length > 0;
  const isReplaying = replayState !== 'idle';
  const hasReplayData = replayEvents.length > 0;

  // ---------------------------------------------------------------------------
  // Fetch stage log on mount
  // ---------------------------------------------------------------------------

  useEffect(() => {
    let cancelled = false;

    async function fetchStageLog() {
      setLoadingLog(true);
      setLoadError(null);

      const result = await client.getStageLog();

      if (cancelled) return;

      if (result.ok) {
        setReplayEvents(result.data);
      } else {
        const err = result as ApiError;
        setLoadError(err.error.message);
      }

      setLoadingLog(false);
    }

    fetchStageLog();

    return () => {
      cancelled = true;
    };
  }, [setReplayEvents]);

  // ---------------------------------------------------------------------------
  // Playback auto-advance timer
  // ---------------------------------------------------------------------------

  useEffect(() => {
    // Clear any existing timer when dependencies change
    if (timerRef.current !== null) {
      clearTimeout(timerRef.current);
      timerRef.current = null;
    }

    if (replayState !== 'playing') return;
    if (replayIndex >= replayEvents.length - 1) {
      // Reached the end -- pause
      setReplayState('paused');
      return;
    }

    const delay = computeReplayDelay(replayEvents, replayIndex, playbackSpeed);

    timerRef.current = setTimeout(() => {
      setReplayIndex(replayIndex + 1);
    }, delay);

    return () => {
      if (timerRef.current !== null) {
        clearTimeout(timerRef.current);
        timerRef.current = null;
      }
    };
  }, [replayState, replayIndex, replayEvents, playbackSpeed, setReplayIndex, setReplayState]);

  // ---------------------------------------------------------------------------
  // Replay-derived state: reconstruct pipeline visual at current index
  // ---------------------------------------------------------------------------

  const replayStepStatuses = useMemo(() => {
    if (!isReplaying || replayEvents.length === 0) return null;
    return reconstructStepStatuses(replayEvents, replayIndex);
  }, [isReplaying, replayEvents, replayIndex]);

  const replayCurrentStepId = useMemo(() => {
    if (!isReplaying || replayEvents.length === 0) return null;
    return getReplayCurrentStepId(replayEvents, replayIndex);
  }, [isReplaying, replayEvents, replayIndex]);

  const replayFsmState = useMemo(() => {
    if (!isReplaying || replayEvents.length === 0) return 'IDLE';
    return getReplayFsmState(replayEvents, replayIndex);
  }, [isReplaying, replayEvents, replayIndex]);

  // Choose which step statuses and currentStepId to use for rendering
  const effectiveStepStatuses = isReplaying && replayStepStatuses ? replayStepStatuses : liveStepStatuses;
  const effectiveCurrentStepId = isReplaying ? replayCurrentStepId : liveCurrentStepId;

  // Derive the renderable steps from store data
  const steps: Step[] = useMemo(() => {
    return planSteps.map((ps) =>
      mapPlanStepToStep(ps, effectiveStepStatuses[ps.id], effectiveCurrentStepId),
    );
  }, [planSteps, effectiveStepStatuses, effectiveCurrentStepId]);

  // Current event for display
  const currentEvent = useMemo<StageLogEntryResponse | null>(() => {
    if (!isReplaying || replayEvents.length === 0) return null;
    return replayEvents[Math.min(replayIndex, replayEvents.length - 1)];
  }, [isReplaying, replayEvents, replayIndex]);

  // Compute estimated remaining from pipeline progress (live mode)
  const completedCount = pipelineProgress.stepsCompleted;
  const totalCount = pipelineProgress.stepsTotal;
  const remainingSteps = Math.max(0, totalCount - completedCount);

  // Replay progress percentage
  const replayProgress = hasReplayData
    ? replayEvents.length > 1
      ? replayIndex / (replayEvents.length - 1)
      : 1
    : 0;

  // ---------------------------------------------------------------------------
  // Replay control handlers
  // ---------------------------------------------------------------------------

  const handlePlayPause = useCallback(() => {
    if (replayState === 'idle') {
      // Start replay from beginning
      setReplayIndex(0);
      setReplayState('playing');
    } else if (replayState === 'playing') {
      setReplayState('paused');
    } else if (replayState === 'paused' || replayState === 'scrubbing') {
      // If at the end, restart from beginning
      if (replayIndex >= replayEvents.length - 1) {
        setReplayIndex(0);
      }
      setReplayState('playing');
    }
  }, [replayState, replayIndex, replayEvents.length, setReplayState, setReplayIndex]);

  const handleReset = useCallback(() => {
    resetReplay();
  }, [resetReplay]);

  const handleSkipBack = useCallback(() => {
    const newIndex = Math.max(0, replayIndex - 1);
    setReplayIndex(newIndex);
    if (replayState === 'idle') {
      setReplayState('paused');
    }
  }, [replayIndex, replayState, setReplayIndex, setReplayState]);

  const handleSkipForward = useCallback(() => {
    if (!hasReplayData) return;
    const newIndex = Math.min(replayEvents.length - 1, replayIndex + 1);
    setReplayIndex(newIndex);
    if (replayState === 'idle') {
      setReplayState('paused');
    }
  }, [hasReplayData, replayEvents.length, replayIndex, replayState, setReplayIndex, setReplayState]);

  const handleScrubChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const newIndex = parseInt(e.target.value, 10);
      setReplayIndex(newIndex);
      if (replayState === 'playing') {
        setReplayState('scrubbing');
      } else if (replayState === 'idle') {
        setReplayState('scrubbing');
      }
    },
    [replayState, setReplayIndex, setReplayState],
  );

  const handleScrubEnd = useCallback(() => {
    if (replayState === 'scrubbing') {
      setReplayState('paused');
    }
  }, [replayState, setReplayState]);

  const handleSpeedChange = useCallback(
    (speed: number) => {
      setPlaybackSpeed(speed);
    },
    [setPlaybackSpeed],
  );

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------

  return (
    <div className="h-full flex flex-col p-8 relative">
      {/* Header */}
      <div className="flex items-center justify-between mb-12">
        <div>
          <h2 className="text-2xl font-bold tracking-tight">Pipeline Theater</h2>
          <p className="text-sm text-white/40">
            {isReplaying
              ? 'Replaying execution timeline'
              : 'Visualizing the river of orchestration'}
          </p>
        </div>
        <div className="flex items-center gap-4">
          {/* Replay mode badge */}
          {isReplaying && (
            <div className="flex items-center gap-2 px-3 py-1.5 bg-purple-500/10 border border-purple-500/20 rounded-full">
              <div className={cn(
                "w-2 h-2 rounded-full",
                replayState === 'playing'
                  ? "bg-purple-400 animate-pulse"
                  : "bg-purple-400/60"
              )} />
              <span className="text-xs font-mono text-purple-400/80 uppercase tracking-widest">
                {replayState === 'playing' ? 'Replaying' : replayState === 'paused' ? 'Paused' : 'Scrubbing'}
              </span>
            </div>
          )}

          {/* Connection warning badges */}
          {(isDisconnected || isReconnecting) && (
            <div className="flex items-center gap-2 px-3 py-1.5 bg-red-500/10 border border-red-500/20 rounded-full">
              <WifiOff size={14} className="text-red-400" />
              <span className="text-xs font-mono text-red-400/80">
                {isDisconnected ? 'Disconnected' : 'Reconnecting...'}
              </span>
            </div>
          )}
          <div className="flex items-center gap-2 px-4 py-2 bg-white/5 rounded-full border border-white/5">
            <div className={cn(
              "w-2 h-2 rounded-full",
              isReplaying
                ? "bg-purple-400"
                : wsStatus === 'connected'
                  ? "bg-state-executing animate-pulse"
                  : "bg-white/20"
            )} />
            <span className="text-xs font-mono uppercase tracking-widest">
              {isReplaying ? 'Replay Mode' : wsStatus === 'connected' ? 'Live Execution' : 'Offline'}
            </span>
          </div>
        </div>
      </div>

      {/* River Flow Visualization */}
      <div className="flex-1 flex items-center justify-center relative overflow-x-auto min-h-[400px]">
        {/* Animated River SVG Background */}
        <svg className="absolute inset-0 w-full h-full pointer-events-none" preserveAspectRatio="none">
          <defs>
            <linearGradient id="riverGrad" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stopColor={isReplaying ? 'var(--color-purple-400, #a78bfa)' : 'var(--color-state-executing)'} stopOpacity="0" />
              <stop offset="50%" stopColor={isReplaying ? 'var(--color-purple-400, #a78bfa)' : 'var(--color-state-executing)'} stopOpacity="0.1" />
              <stop offset="100%" stopColor={isReplaying ? 'var(--color-purple-400, #a78bfa)' : 'var(--color-state-executing)'} stopOpacity="0" />
            </linearGradient>
            <filter id="glow">
              <feGaussianBlur stdDeviation="4" result="coloredBlur"/>
              <feMerge>
                <feMergeNode in="coloredBlur"/>
                <feMergeNode in="SourceGraphic"/>
              </feMerge>
            </filter>
          </defs>
          <motion.path
            d="M 0,200 Q 200,180 400,200 T 800,200 T 1200,200"
            fill="none"
            stroke="url(#riverGrad)"
            strokeWidth="40"
            filter="url(#glow)"
            animate={{ d: ["M 0,200 Q 200,180 400,200 T 800,200 T 1200,200", "M 0,200 Q 200,220 400,200 T 800,200 T 1200,200", "M 0,200 Q 200,180 400,200 T 800,200 T 1200,200"] }}
            transition={{ duration: 4, repeat: Infinity, ease: "easeInOut" }}
          />
          {/* Particles */}
          {[...Array(5)].map((_, i) => (
            <motion.circle
              key={i}
              r="2"
              fill={isReplaying ? 'var(--color-purple-400, #a78bfa)' : 'var(--color-state-executing)'}
              initial={{ cx: 0, cy: 200, opacity: 0 }}
              animate={{ cx: 1200, cy: 200, opacity: [0, 1, 0] }}
              transition={{ duration: 3, repeat: Infinity, delay: i * 0.6, ease: "linear" }}
            />
          ))}
        </svg>

        {/* Loading Skeleton State */}
        {isLoading && !hasSteps && (
          <div className="flex items-center gap-16 px-20 relative z-10">
            {[...Array(5)].map((_, i) => (
              <React.Fragment key={i}>
                <div className="relative">
                  <div className="w-20 h-20 rounded-3xl bg-white/5 border-2 border-white/10 animate-pulse" />
                  <div className="absolute -bottom-8 left-1/2 -translate-x-1/2 flex flex-col items-center gap-1">
                    <div className="h-2.5 w-14 bg-white/5 rounded animate-pulse" />
                    <div className="h-3 w-20 bg-white/5 rounded animate-pulse" />
                  </div>
                </div>
                {i < 4 && (
                  <div className="w-16 h-1 bg-white/5 rounded-full animate-pulse" />
                )}
              </React.Fragment>
            ))}
          </div>
        )}

        {/* Empty state when connected but no steps */}
        {!isLoading && !hasSteps && (
          <div className="flex flex-col items-center gap-4 relative z-10">
            <div className="w-16 h-16 rounded-2xl bg-white/5 border border-white/10 flex items-center justify-center">
              <AlertTriangle size={24} className="text-white/20" />
            </div>
            <div className="text-center">
              <p className="text-sm font-medium text-white/40">No pipeline steps loaded</p>
              <p className="text-xs text-white/20 mt-1">Start an EPIC run to see the execution flow</p>
            </div>
          </div>
        )}

        {/* Real steps */}
        {hasSteps && (
          <div className="flex items-center gap-16 px-20 relative z-10">
            {steps.map((step, index) => (
              <React.Fragment key={step.id}>
                {/* Step Island */}
                <motion.div
                  initial={{ opacity: 0, x: -20 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: index * 0.1 }}
                  onClick={() => setSelectedStep(step)}
                  className={cn(
                    "relative group cursor-pointer",
                    step.status === 'active' && "animate-pulse-subtle"
                  )}
                >
                  <div className={cn(
                    "w-20 h-20 rounded-3xl flex items-center justify-center transition-all duration-500 border-2",
                    step.status === 'completed' ? "bg-state-done/20 border-state-done shadow-[0_0_15px_rgba(34,197,94,0.3)]" :
                    step.status === 'active' ? "bg-state-executing/20 border-state-executing shadow-[0_0_20px_rgba(0,180,216,0.4)]" :
                    step.status === 'failed' ? "bg-red-500/20 border-red-500 shadow-[0_0_15px_rgba(239,68,68,0.3)]" :
                    step.status === 'skipped' ? "bg-yellow-500/10 border-yellow-500/40 opacity-50" :
                    "bg-white/5 border-white/10 opacity-40"
                  )}>
                    {roleIcons[step.role] ? React.createElement(roleIcons[step.role], { size: 32 }) : <User size={32} />}
                  </div>

                  <div className="absolute -bottom-8 left-1/2 -translate-x-1/2 whitespace-nowrap text-center">
                    <div className="text-[10px] font-bold uppercase tracking-widest text-white/40 mb-0.5">{step.role}</div>
                    <div className="text-xs font-medium">{step.label}</div>
                  </div>

                  {step.duration && (
                    <div className="absolute -top-6 left-1/2 -translate-x-1/2 bg-white/10 px-2 py-0.5 rounded text-[10px] font-mono text-white/60">
                      {step.duration}
                    </div>
                  )}
                </motion.div>

                {/* Connector / Water Flow */}
                {index < steps.length - 1 && (
                  <div className="w-16 h-1 bg-white/5 relative overflow-hidden rounded-full">
                    <motion.div
                      className="absolute inset-0 bg-gradient-to-r from-transparent via-white/20 to-transparent"
                      animate={{ x: ['-100%', '100%'] }}
                      transition={{ duration: 2, repeat: Infinity, ease: "linear" }}
                    />
                    {step.status === 'completed' && (
                      <div className="absolute inset-0 bg-state-done/40" />
                    )}
                  </div>
                )}
              </React.Fragment>
            ))}

            {/* Final Gate */}
            <div className="ml-8 flex flex-col items-center gap-4 opacity-40">
              <div className="w-16 h-32 border-2 border-dashed border-white/20 rounded-2xl flex flex-col items-center justify-center gap-4">
                <div className="w-8 h-8 rounded-lg bg-white/5" />
                <div className="w-8 h-8 rounded-lg bg-white/5" />
              </div>
              <span className="text-[10px] font-bold uppercase tracking-widest text-white/20">Quality Gates</span>
            </div>
          </div>
        )}
      </div>

      {/* Current Replay Event Info */}
      <AnimatePresence>
        {isReplaying && currentEvent && (
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 10 }}
            className="mb-3 bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 flex items-center gap-4"
          >
            <div className="flex items-center gap-2 shrink-0">
              <div className={cn(
                "w-2 h-2 rounded-full",
                currentEvent.result === 'pass' || currentEvent.result === 'success'
                  ? "bg-state-done"
                  : currentEvent.result === 'fail'
                    ? "bg-red-500"
                    : currentEvent.result === 'skip'
                      ? "bg-yellow-500"
                      : "bg-blue-400"
              )} />
              <span className="text-[10px] font-bold uppercase tracking-widest text-white/40">
                {currentEvent.state}
              </span>
            </div>
            <div className="text-xs text-white/60 truncate flex-1">
              <span className="font-mono text-white/40 mr-2">[{currentEvent.action}]</span>
              {currentEvent.details}
            </div>
            <div className="text-[10px] font-mono text-white/30 shrink-0">
              {formatTimestamp(currentEvent.timestamp)}
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Controls Bar */}
      <div className="mt-auto bg-surface-1/50 backdrop-blur-xl border border-white/5 rounded-2xl p-4 flex items-center gap-6">
        {/* Transport Controls */}
        <div className="flex items-center gap-2">
          <button
            onClick={handleReset}
            disabled={!hasReplayData}
            className={cn(
              "p-2 rounded-lg transition-colors",
              hasReplayData
                ? "hover:bg-white/10 text-white/40 hover:text-white"
                : "text-white/10 cursor-not-allowed"
            )}
            title="Reset replay"
            aria-label="Reset replay"
          >
            <RotateCcw size={18} />
          </button>

          <button
            onClick={handleSkipBack}
            disabled={!hasReplayData || replayIndex <= 0}
            className={cn(
              "p-2 rounded-lg transition-colors",
              hasReplayData && replayIndex > 0
                ? "hover:bg-white/10 text-white/40 hover:text-white"
                : "text-white/10 cursor-not-allowed"
            )}
            title="Previous event"
            aria-label="Previous event"
          >
            <SkipBack size={16} />
          </button>

          <button
            onClick={handlePlayPause}
            disabled={!hasReplayData && !loadingLog}
            className={cn(
              "p-2 rounded-lg transition-colors",
              hasReplayData
                ? "bg-white/10 hover:bg-white/20 text-white"
                : "text-white/10 cursor-not-allowed"
            )}
            title={replayState === 'playing' ? 'Pause replay' : 'Start replay'}
            aria-label={replayState === 'playing' ? 'Pause replay' : 'Start replay'}
          >
            {loadingLog ? (
              <Loader2 size={18} className="animate-spin" />
            ) : replayState === 'playing' ? (
              <Pause size={18} fill="currentColor" />
            ) : (
              <Play size={18} fill="currentColor" />
            )}
          </button>

          <button
            onClick={handleSkipForward}
            disabled={!hasReplayData || replayIndex >= replayEvents.length - 1}
            className={cn(
              "p-2 rounded-lg transition-colors",
              hasReplayData && replayIndex < replayEvents.length - 1
                ? "hover:bg-white/10 text-white/40 hover:text-white"
                : "text-white/10 cursor-not-allowed"
            )}
            title="Next event"
            aria-label="Next event"
          >
            <SkipForward size={16} />
          </button>

          {/* Speed Control */}
          <div className="flex items-center gap-1 ml-2 px-2 border-l border-white/10">
            {SPEED_OPTIONS.map((speed) => (
              <button
                key={speed}
                onClick={() => handleSpeedChange(speed)}
                disabled={!hasReplayData}
                className={cn(
                  "p-1 rounded text-[10px] font-mono transition-colors",
                  playbackSpeed === speed
                    ? "bg-white/20 text-white"
                    : hasReplayData
                      ? "hover:bg-white/10 text-white/40 hover:text-white"
                      : "text-white/10 cursor-not-allowed"
                )}
                title={`Playback speed ${speed}x`}
                aria-label={`Playback speed ${speed}x`}
                aria-pressed={playbackSpeed === speed}
              >
                {speed}x
              </button>
            ))}
          </div>
        </div>

        {/* Progress / Scrub Bar */}
        <div className="flex-1 space-y-2">
          {isReplaying || hasReplayData ? (
            <>
              <div className="flex justify-between text-[10px] font-mono text-white/40 uppercase tracking-widest">
                <span>
                  Replay {hasReplayData ? `${replayIndex + 1} / ${replayEvents.length}` : ''}
                </span>
                <span>
                  {hasReplayData && replayEvents.length > 0
                    ? formatTimestamp(replayEvents[Math.min(replayIndex, replayEvents.length - 1)].timestamp)
                    : '--'}
                </span>
              </div>
              <div className="relative">
                <input
                  type="range"
                  min={0}
                  max={Math.max(0, replayEvents.length - 1)}
                  value={replayIndex}
                  onChange={handleScrubChange}
                  onMouseUp={handleScrubEnd}
                  onTouchEnd={handleScrubEnd}
                  disabled={!hasReplayData}
                  className={cn(
                    "w-full h-1.5 rounded-full appearance-none cursor-pointer",
                    "bg-white/5",
                    "[&::-webkit-slider-thumb]:appearance-none",
                    "[&::-webkit-slider-thumb]:w-3",
                    "[&::-webkit-slider-thumb]:h-3",
                    "[&::-webkit-slider-thumb]:rounded-full",
                    "[&::-webkit-slider-thumb]:bg-purple-400",
                    "[&::-webkit-slider-thumb]:shadow-[0_0_6px_rgba(168,85,247,0.5)]",
                    "[&::-webkit-slider-thumb]:cursor-pointer",
                    "[&::-moz-range-thumb]:w-3",
                    "[&::-moz-range-thumb]:h-3",
                    "[&::-moz-range-thumb]:rounded-full",
                    "[&::-moz-range-thumb]:bg-purple-400",
                    "[&::-moz-range-thumb]:border-0",
                    "[&::-moz-range-thumb]:cursor-pointer",
                    !hasReplayData && "opacity-30 cursor-not-allowed"
                  )}
                  style={{
                    background: hasReplayData
                      ? `linear-gradient(to right, rgb(168 85 247 / 0.5) 0%, rgb(168 85 247 / 0.5) ${replayProgress * 100}%, rgb(255 255 255 / 0.05) ${replayProgress * 100}%, rgb(255 255 255 / 0.05) 100%)`
                      : undefined,
                  }}
                  aria-label="Replay scrub bar"
                  aria-valuemin={0}
                  aria-valuemax={replayEvents.length - 1}
                  aria-valuenow={replayIndex}
                  aria-valuetext={
                    hasReplayData
                      ? `Event ${replayIndex + 1} of ${replayEvents.length}`
                      : 'No events loaded'
                  }
                />
              </div>
            </>
          ) : (
            <>
              <div className="flex justify-between text-[10px] font-mono text-white/40 uppercase tracking-widest">
                <span>Overall Progress</span>
                <span>{Math.round(progress * 100)}%</span>
              </div>
              <div className="h-1.5 w-full bg-white/5 rounded-full overflow-hidden">
                <motion.div
                  className="h-full bg-state-executing shadow-[0_0_10px_rgba(0,180,216,0.5)]"
                  animate={{ width: `${progress * 100}%` }}
                />
              </div>
            </>
          )}
        </div>

        {/* Right info panel */}
        <div className="text-right">
          {isReplaying ? (
            <>
              <div className="text-[10px] font-mono text-white/40 uppercase tracking-widest">State</div>
              <div className="text-sm font-bold font-mono">{replayFsmState}</div>
            </>
          ) : (
            <>
              <div className="text-[10px] font-mono text-white/40 uppercase tracking-widest">Remaining</div>
              {isLoading ? (
                <div className="h-5 w-16 bg-white/5 rounded animate-pulse mt-1" />
              ) : (
                <div className="text-sm font-bold">
                  {totalCount > 0 ? `${remainingSteps} / ${totalCount} steps` : '--'}
                </div>
              )}
            </>
          )}
        </div>
      </div>

      {/* Error toast for stage log loading */}
      <AnimatePresence>
        {loadError && (
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 20 }}
            className="absolute bottom-24 left-1/2 -translate-x-1/2 bg-red-500/10 border border-red-500/20 rounded-xl px-4 py-2 flex items-center gap-2"
          >
            <AlertTriangle size={14} className="text-red-400 shrink-0" />
            <span className="text-xs text-red-400">{loadError}</span>
            <button
              onClick={() => setLoadError(null)}
              className="ml-2 text-red-400/60 hover:text-red-400 text-xs"
              aria-label="Dismiss error"
            >
              Dismiss
            </button>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Step Detail Panel */}
      <AnimatePresence>
        {selectedStep && (
          <>
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setSelectedStep(null)}
              className="absolute inset-0 bg-bg-base/60 backdrop-blur-sm z-40"
            />
            <motion.div
              initial={{ x: '100%' }}
              animate={{ x: 0 }}
              exit={{ x: '100%' }}
              transition={{ type: 'spring', damping: 25, stiffness: 200 }}
              className="absolute top-0 right-0 h-full w-96 bg-surface-2 border-l border-white/10 z-50 p-6 shadow-2xl"
            >
              <div className="flex items-center justify-between mb-8">
                <div className="flex items-center gap-3">
                  <div className="p-2 rounded-xl bg-white/5 border border-white/10">
                    {roleIcons[selectedStep.role] ? React.createElement(roleIcons[selectedStep.role], { size: 20 }) : <User size={20} />}
                  </div>
                  <div>
                    <h3 className="font-bold">{selectedStep.label}</h3>
                    <p className="text-[10px] uppercase tracking-widest text-white/40">{selectedStep.role}</p>
                  </div>
                </div>
                <button
                  onClick={() => setSelectedStep(null)}
                  className="p-2 hover:bg-white/5 rounded-lg transition-colors"
                  aria-label="Close detail panel"
                >
                  <ChevronRight size={20} />
                </button>
              </div>

              <div className="space-y-6">
                <section>
                  <h4 className="text-[10px] font-bold uppercase tracking-widest text-white/40 mb-3">Status</h4>
                  <div className="flex items-center gap-2">
                    <div className={cn(
                      "w-2 h-2 rounded-full",
                      selectedStep.status === 'completed' ? "bg-state-done" :
                      selectedStep.status === 'active' ? "bg-state-executing animate-pulse" :
                      selectedStep.status === 'failed' ? "bg-red-500" :
                      selectedStep.status === 'skipped' ? "bg-yellow-500" :
                      "bg-white/20"
                    )} />
                    <span className="text-sm capitalize">{selectedStep.status}</span>
                  </div>
                </section>

                <section>
                  <h4 className="text-[10px] font-bold uppercase tracking-widest text-white/40 mb-3">Agent Output</h4>
                  <div className="bg-white/5 rounded-xl p-4 font-mono text-xs leading-relaxed text-white/60">
                    {selectedStep.status === 'pending' ? 'Waiting for dispatch...' :
                     selectedStep.status === 'active' ? 'Processing instructions and generating code artifacts...' :
                     selectedStep.status === 'failed' ? 'Step execution failed. Check evidence vault for details.' :
                     selectedStep.status === 'skipped' ? 'Step was skipped during this run.' :
                     'Successfully implemented the requested changes. Verified with unit tests.'}
                  </div>
                </section>

                {selectedStep.duration && (
                  <section>
                    <h4 className="text-[10px] font-bold uppercase tracking-widest text-white/40 mb-3">Timing</h4>
                    <div className="flex items-center gap-2 text-sm">
                      <Clock size={14} className="text-white/40" />
                      <span>{selectedStep.duration} total duration</span>
                    </div>
                  </section>
                )}
              </div>

              <button className="absolute bottom-6 left-6 right-6 py-3 bg-white/5 hover:bg-white/10 border border-white/10 rounded-xl text-sm font-medium transition-all">
                View in Evidence Vault
              </button>
            </motion.div>
          </>
        )}
      </AnimatePresence>
    </div>
  );
};
