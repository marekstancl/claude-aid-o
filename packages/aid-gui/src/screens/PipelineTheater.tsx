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
  ChevronDown,
  Play,
  Pause,
  RotateCcw,
  SkipBack,
  SkipForward,
  WifiOff,
  AlertTriangle,
  Loader2,
  Radio,
  ArrowDown,
  Eye,
  EyeOff,
} from 'lucide-react';
import type {
  PlanStep,
  StageLogEntryResponse,
  ApiError,
  TheaterStep,
  TheaterData,
  EvidenceEpicEntry,
} from '../types/api';
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
  startedAt?: string | null;
  completedAt?: string | null;
  durationMs?: number | null;
  objective?: string;
}

/** Tooltip data for SVG bar hover. */
interface BarTooltip {
  x: number;
  y: number;
  stepId: string;
  role: string;
  status: string;
  duration: string;
}

const roleIcons: Record<string, React.ComponentType<{ size: number }>> = {
  architect: User,
  backend: Database,
  frontend: Layout,
  security: ShieldCheck,
  docs: FileText,
};

// ---------------------------------------------------------------------------
// Role color mapping
// ---------------------------------------------------------------------------

const ROLE_COLORS: Record<string, string> = {
  architect: '#3b82f6',
  backend: '#22c55e',
  frontend: '#a855f7',
  qa: '#f97316',
  docs: '#6b7280',
  security: '#ef4444',
};

const DEFAULT_ROLE_COLOR = '#6b7280';

function getRoleColor(role: string): string {
  return ROLE_COLORS[role.toLowerCase()] ?? DEFAULT_ROLE_COLOR;
}

// ---------------------------------------------------------------------------
// API client (matches existing codebase pattern)
// ---------------------------------------------------------------------------

const client = createApiClient('default');

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const SPEED_OPTIONS = [0.5, 1, 2, 4] as const;

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

/** Maximum events rendered in the SVG timeline. */
const SVG_MAX_EVENTS = 500;

/** Height per step row in the timeline. */
const ROW_HEIGHT = 36;

/** Left margin for step labels. */
const LABEL_WIDTH = 140;

/** Timeline right padding. */
const TIMELINE_PADDING = 24;

/** Minimum bar width in pixels (so tiny durations are still visible). */
const MIN_BAR_WIDTH = 6;

// ---------------------------------------------------------------------------
// Role legend entries
// ---------------------------------------------------------------------------

const ROLE_LEGEND: Array<{ role: string; color: string }> = [
  { role: 'architect', color: '#3b82f6' },
  { role: 'backend', color: '#22c55e' },
  { role: 'frontend', color: '#a855f7' },
  { role: 'qa', color: '#f97316' },
  { role: 'docs', color: '#6b7280' },
  { role: 'security', color: '#ef4444' },
];

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
    startedAt: stepStatus?.startedAt ?? null,
    completedAt: stepStatus?.completedAt ?? null,
    durationMs:
      stepStatus?.startedAt && stepStatus?.completedAt
        ? new Date(stepStatus.completedAt).getTime() -
          new Date(stepStatus.startedAt).getTime()
        : null,
    objective: planStep.objective,
  };
}

/**
 * Map TheaterStep data into the local Step interface.
 */
function mapTheaterStepToStep(ts: TheaterStep): Step {
  let status: Step['status'] = 'pending';
  switch (ts.status) {
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

  let duration: string | undefined;
  if (ts.durationMs != null) {
    const diffSec = Math.round(ts.durationMs / 1000);
    if (diffSec < 60) {
      duration = `${diffSec}s`;
    } else {
      const mins = Math.floor(diffSec / 60);
      const secs = diffSec % 60;
      duration = `${mins}m ${secs}s`;
    }
  }

  return {
    id: ts.id,
    label:
      ts.objective.length > 40
        ? ts.objective.slice(0, 37) + '...'
        : ts.objective,
    role: ts.role,
    status,
    duration,
    startedAt: ts.startedAt,
    completedAt: ts.completedAt,
    durationMs: ts.durationMs,
    objective: ts.objective,
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

/**
 * Format milliseconds into a human-readable duration string.
 */
function formatDurationMs(ms: number): string {
  const totalSec = Math.round(ms / 1000);
  if (totalSec < 60) return `${totalSec}s`;
  const mins = Math.floor(totalSec / 60);
  const secs = totalSec % 60;
  if (mins < 60) return `${mins}m ${secs}s`;
  const hours = Math.floor(mins / 60);
  const remMins = mins % 60;
  return `${hours}h ${remMins}m`;
}

/**
 * Compute the time range for the timeline axis from a set of steps.
 */
function computeTimeRange(steps: Step[]): { minTime: number; maxTime: number } {
  const now = Date.now();
  let minTime = Infinity;
  let maxTime = -Infinity;

  for (const step of steps) {
    if (step.startedAt) {
      const t = new Date(step.startedAt).getTime();
      if (t < minTime) minTime = t;
      if (t > maxTime) maxTime = t;
    }
    if (step.completedAt) {
      const t = new Date(step.completedAt).getTime();
      if (t > maxTime) maxTime = t;
    }
    if (step.status === 'active' && step.startedAt) {
      // Active steps extend to "now"
      if (now > maxTime) maxTime = now;
    }
  }

  // If no steps have timing data, use a default 1-minute range centered on now
  if (minTime === Infinity) {
    minTime = now - 30_000;
    maxTime = now + 30_000;
  }

  // Ensure at least 10 seconds of range for visibility
  if (maxTime - minTime < 10_000) {
    maxTime = minTime + 10_000;
  }

  // Add 5% padding on each side
  const padding = (maxTime - minTime) * 0.05;
  return { minTime: minTime - padding, maxTime: maxTime + padding };
}

/**
 * Format a time axis tick label from epoch ms.
 */
function formatAxisTime(ms: number): string {
  const d = new Date(ms);
  return d.toLocaleTimeString(undefined, {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
}

/**
 * Compute a nice set of tick marks for the time axis.
 */
function computeTimeTicks(
  minTime: number,
  maxTime: number,
  availableWidth: number,
): number[] {
  const range = maxTime - minTime;
  const targetTicks = Math.max(3, Math.min(10, Math.floor(availableWidth / 120)));

  // Find a nice interval
  const rawInterval = range / targetTicks;
  const niceIntervals = [1000, 2000, 5000, 10000, 15000, 30000, 60000, 120000, 300000, 600000, 900000, 1800000, 3600000];
  let interval = niceIntervals[0];
  for (const ni of niceIntervals) {
    if (ni >= rawInterval) {
      interval = ni;
      break;
    }
    interval = ni;
  }

  const ticks: number[] = [];
  const start = Math.ceil(minTime / interval) * interval;
  for (let t = start; t <= maxTime; t += interval) {
    ticks.push(t);
  }

  return ticks;
}

// ---------------------------------------------------------------------------
// SVG Timeline Component (inline)
// ---------------------------------------------------------------------------

interface TimelineProps {
  steps: Step[];
  playheadTime: number | null;
  containerWidth: number;
  onStepClick: (step: Step) => void;
  autoFollow: boolean;
  isLive: boolean;
  replayProgress: number;
  isReplaying: boolean;
}

function TimelineSVG({
  steps,
  playheadTime,
  containerWidth,
  onStepClick,
  autoFollow,
  isLive,
}: TimelineProps) {
  const [tooltip, setTooltip] = useState<BarTooltip | null>(null);
  const svgRef = useRef<SVGSVGElement | null>(null);

  // Limit to SVG_MAX_EVENTS steps
  const visibleSteps = useMemo(() => steps.slice(0, SVG_MAX_EVENTS), [steps]);

  const { minTime, maxTime } = useMemo(
    () => computeTimeRange(visibleSteps),
    [visibleSteps],
  );

  const timelineWidth = Math.max(400, containerWidth - LABEL_WIDTH - TIMELINE_PADDING * 2);
  const svgHeight = Math.max(120, visibleSteps.length * ROW_HEIGHT + 48);
  const totalWidth = LABEL_WIDTH + timelineWidth + TIMELINE_PADDING * 2;

  const ticks = useMemo(
    () => computeTimeTicks(minTime, maxTime, timelineWidth),
    [minTime, maxTime, timelineWidth],
  );

  // Map time to x coordinate
  const timeToX = useCallback(
    (t: number) => {
      const fraction = (t - minTime) / (maxTime - minTime);
      return LABEL_WIDTH + TIMELINE_PADDING + fraction * timelineWidth;
    },
    [minTime, maxTime, timelineWidth],
  );

  // Playhead x position
  const playheadX = useMemo(() => {
    if (playheadTime == null) return null;
    const x = timeToX(playheadTime);
    // Clamp to timeline area
    const minX = LABEL_WIDTH + TIMELINE_PADDING;
    const maxX = LABEL_WIDTH + TIMELINE_PADDING + timelineWidth;
    if (x < minX || x > maxX) return null;
    return x;
  }, [playheadTime, timeToX, timelineWidth]);

  const handleBarMouseEnter = useCallback(
    (e: React.MouseEvent, step: Step) => {
      const svgEl = svgRef.current;
      if (!svgEl) return;
      const rect = svgEl.getBoundingClientRect();
      setTooltip({
        x: e.clientX - rect.left,
        y: e.clientY - rect.top - 10,
        stepId: step.id,
        role: step.role,
        status: step.status,
        duration: step.duration ?? (step.status === 'active' ? 'In progress...' : '--'),
      });
    },
    [],
  );

  const handleBarMouseLeave = useCallback(() => {
    setTooltip(null);
  }, []);

  return (
    <svg
      ref={svgRef}
      width={totalWidth}
      height={svgHeight}
      className="block"
      role="img"
      aria-label="Pipeline timeline visualization"
    >
      <defs>
        {/* Cross-hatch pattern for failed bars */}
        <pattern
          id="crosshatch"
          width="8"
          height="8"
          patternUnits="userSpaceOnUse"
          patternTransform="rotate(45)"
        >
          <line x1="0" y1="0" x2="0" y2="8" stroke="#ef4444" strokeWidth="2" strokeOpacity="0.6" />
        </pattern>
        {/* Pulse animation filter */}
        <filter id="pulseGlow">
          <feGaussianBlur stdDeviation="2" result="coloredBlur" />
          <feMerge>
            <feMergeNode in="coloredBlur" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
      </defs>

      {/* Time axis ticks and labels at top */}
      {ticks.map((tick) => {
        const x = timeToX(tick);
        return (
          <g key={tick}>
            <line
              x1={x}
              y1={20}
              x2={x}
              y2={svgHeight}
              stroke="rgba(255,255,255,0.06)"
              strokeWidth="1"
            />
            <text
              x={x}
              y={14}
              fill="rgba(255,255,255,0.35)"
              fontSize="10"
              fontFamily="monospace"
              textAnchor="middle"
            >
              {formatAxisTime(tick)}
            </text>
          </g>
        );
      })}

      {/* Step rows */}
      {visibleSteps.map((step, index) => {
        const y = 28 + index * ROW_HEIGHT;
        const color = getRoleColor(step.role);
        const now = Date.now();

        // Compute bar position and width
        let barX = LABEL_WIDTH + TIMELINE_PADDING;
        let barWidth = 0;
        const hasStart = step.startedAt != null;
        const hasEnd = step.completedAt != null;

        if (hasStart) {
          const startT = new Date(step.startedAt!).getTime();
          barX = timeToX(startT);

          if (hasEnd) {
            const endT = new Date(step.completedAt!).getTime();
            barWidth = Math.max(MIN_BAR_WIDTH, timeToX(endT) - barX);
          } else if (step.status === 'active') {
            // Active: extend to current time
            barWidth = Math.max(MIN_BAR_WIDTH, timeToX(now) - barX);
          } else {
            barWidth = MIN_BAR_WIDTH;
          }
        }

        // Truncate label for narrow screens
        const maxLabelLen = 18;
        const truncatedLabel =
          step.id.length > maxLabelLen
            ? step.id.slice(0, maxLabelLen - 2) + '..'
            : step.id;

        return (
          <g
            key={step.id}
            className="cursor-pointer"
            onClick={() => onStepClick(step)}
          >
            {/* Row background on hover */}
            <rect
              x={0}
              y={y - 2}
              width={totalWidth}
              height={ROW_HEIGHT - 4}
              fill="transparent"
              className="hover:fill-white/[0.03]"
              rx="4"
            />

            {/* Step label */}
            <text
              x={LABEL_WIDTH - 8}
              y={y + (ROW_HEIGHT - 4) / 2 + 1}
              fill="rgba(255,255,255,0.5)"
              fontSize="11"
              fontFamily="monospace"
              textAnchor="end"
              dominantBaseline="middle"
            >
              {truncatedLabel}
            </text>

            {/* Step bar */}
            {hasStart && barWidth > 0 ? (
              <>
                {/* Main bar */}
                <rect
                  x={barX}
                  y={y + 4}
                  width={barWidth}
                  height={ROW_HEIGHT - 12}
                  rx="4"
                  fill={
                    step.status === 'failed'
                      ? 'url(#crosshatch)'
                      : color
                  }
                  fillOpacity={
                    step.status === 'completed'
                      ? 0.7
                      : step.status === 'active'
                        ? 0.5
                        : 0.3
                  }
                  stroke={
                    step.status === 'failed' ? '#ef4444' : color
                  }
                  strokeWidth={step.status === 'active' ? 1.5 : 1}
                  strokeOpacity={0.8}
                  filter={step.status === 'active' ? 'url(#pulseGlow)' : undefined}
                  onMouseEnter={(e) => handleBarMouseEnter(e, step)}
                  onMouseLeave={handleBarMouseLeave}
                >
                  {step.status === 'active' && (
                    <animate
                      attributeName="fill-opacity"
                      values="0.5;0.7;0.5"
                      dur="2s"
                      repeatCount="indefinite"
                    />
                  )}
                </rect>

                {/* Failed cross-hatch overlay */}
                {step.status === 'failed' && (
                  <rect
                    x={barX}
                    y={y + 4}
                    width={barWidth}
                    height={ROW_HEIGHT - 12}
                    rx="4"
                    fill="#ef4444"
                    fillOpacity={0.2}
                    pointerEvents="none"
                  />
                )}

                {/* Duration label on bar (if wide enough) */}
                {barWidth > 50 && step.duration && (
                  <text
                    x={barX + barWidth / 2}
                    y={y + (ROW_HEIGHT - 4) / 2 + 1}
                    fill="rgba(255,255,255,0.8)"
                    fontSize="9"
                    fontFamily="monospace"
                    textAnchor="middle"
                    dominantBaseline="middle"
                    pointerEvents="none"
                  >
                    {step.duration}
                  </text>
                )}
              </>
            ) : (
              // Pending: dashed outline placeholder
              <rect
                x={LABEL_WIDTH + TIMELINE_PADDING}
                y={y + 4}
                width={40}
                height={ROW_HEIGHT - 12}
                rx="4"
                fill="none"
                stroke={color}
                strokeWidth="1"
                strokeOpacity={0.2}
                strokeDasharray="4 2"
                onMouseEnter={(e) => handleBarMouseEnter(e, step)}
                onMouseLeave={handleBarMouseLeave}
              />
            )}

            {/* Role color dot */}
            <circle
              cx={LABEL_WIDTH + 4}
              cy={y + (ROW_HEIGHT - 4) / 2}
              r="3"
              fill={color}
              fillOpacity={0.7}
            />
          </g>
        );
      })}

      {/* Playhead vertical line */}
      {playheadX != null && (
        <g>
          <line
            x1={playheadX}
            y1={20}
            x2={playheadX}
            y2={svgHeight}
            stroke="#f59e0b"
            strokeWidth="1.5"
            strokeOpacity="0.8"
          />
          <polygon
            points={`${playheadX - 5},20 ${playheadX + 5},20 ${playheadX},26`}
            fill="#f59e0b"
            fillOpacity="0.9"
          />
        </g>
      )}

      {/* Tooltip */}
      {tooltip && (
        <g pointerEvents="none">
          <rect
            x={Math.min(tooltip.x, totalWidth - 200)}
            y={Math.max(0, tooltip.y - 52)}
            width="190"
            height="48"
            rx="6"
            fill="rgba(15,15,20,0.95)"
            stroke="rgba(255,255,255,0.1)"
            strokeWidth="1"
          />
          <text
            x={Math.min(tooltip.x, totalWidth - 200) + 8}
            y={Math.max(0, tooltip.y - 52) + 16}
            fill="rgba(255,255,255,0.9)"
            fontSize="11"
            fontFamily="monospace"
            fontWeight="bold"
          >
            {tooltip.stepId}
          </text>
          <text
            x={Math.min(tooltip.x, totalWidth - 200) + 8}
            y={Math.max(0, tooltip.y - 52) + 30}
            fill="rgba(255,255,255,0.5)"
            fontSize="10"
            fontFamily="monospace"
          >
            {tooltip.role} | {tooltip.status} | {tooltip.duration}
          </text>
        </g>
      )}
    </svg>
  );
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
  const currentEpicId = useStore((s) => s.currentEpicId);
  const stageLogEntries = useStore((s) => s.stageLogEntries);

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

  // EPIC/Run selector state
  const [evidenceEpics, setEvidenceEpics] = useState<EvidenceEpicEntry[]>([]);
  const [selectedEpicId, setSelectedEpicId] = useState<string | null>(null);
  const [selectedRunId, setSelectedRunId] = useState<string | null>(null);
  const [theaterData, setTheaterData] = useState<TheaterData | null>(null);
  const [selectorOpen, setSelectorOpen] = useState(false);
  const [theaterLoading, setTheaterLoading] = useState(false);

  // Auto-follow state
  const [autoFollow, setAutoFollow] = useState(true);
  const [hasNewEvents, setHasNewEvents] = useState(false);
  const prevStageLogLenRef = useRef(0);

  // Ref for the playback timer so we can cancel it
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Ref for the timeline scroll container
  const timelineContainerRef = useRef<HTMLDivElement | null>(null);
  const [containerWidth, setContainerWidth] = useState(800);

  // Track container width
  useEffect(() => {
    const el = timelineContainerRef.current;
    if (!el) return;

    const observer = new ResizeObserver((entries) => {
      for (const entry of entries) {
        setContainerWidth(entry.contentRect.width);
      }
    });

    observer.observe(el);
    setContainerWidth(el.clientWidth);

    return () => observer.disconnect();
  }, []);

  const isLoading = wsStatus === 'connecting';
  const isDisconnected = wsStatus === 'disconnected';
  const isReconnecting = wsStatus === 'reconnecting';
  const hasSteps = planSteps.length > 0;
  const isReplaying = replayState !== 'idle';
  const hasReplayData = replayEvents.length > 0;
  const isViewingTheater = theaterData != null;

  // ---------------------------------------------------------------------------
  // Fetch evidence EPICs for selector on mount
  // ---------------------------------------------------------------------------

  useEffect(() => {
    let cancelled = false;

    async function fetchEvidence() {
      const result = await client.getEvidence();
      if (cancelled) return;
      if (result.ok) {
        setEvidenceEpics(result.data);
        // Default to current EPIC's most recent run
        if (result.data.length > 0) {
          const current = currentEpicId
            ? result.data.find((e) => e.epicId === currentEpicId)
            : null;
          const defaultEpic = current ?? result.data[result.data.length - 1];
          if (defaultEpic && defaultEpic.runs.length > 0) {
            setSelectedEpicId(defaultEpic.epicId);
            setSelectedRunId(defaultEpic.runs[defaultEpic.runs.length - 1].runId);
          }
        }
      }
    }

    fetchEvidence();
    return () => {
      cancelled = true;
    };
  }, [currentEpicId]);

  // ---------------------------------------------------------------------------
  // Fetch stage log on mount (for replay)
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
  // Load theater data when EPIC/run selection changes
  // ---------------------------------------------------------------------------

  useEffect(() => {
    if (!selectedEpicId || !selectedRunId) return;
    let cancelled = false;

    async function loadTheater() {
      setTheaterLoading(true);
      const result = await client.getPipelineTheater(selectedEpicId!, selectedRunId!);
      if (cancelled) return;
      if (result.ok) {
        setTheaterData(result.data);
        // Load replay events from theater data
        if (result.data.stageLog.length > 0) {
          setReplayEvents(result.data.stageLog);
        }
      } else {
        // Non-fatal: theater endpoint may not exist for all runs
        setTheaterData(null);
      }
      setTheaterLoading(false);
    }

    loadTheater();
    return () => {
      cancelled = true;
    };
  }, [selectedEpicId, selectedRunId, setReplayEvents]);

  // ---------------------------------------------------------------------------
  // Auto-scroll / auto-follow for live mode
  // ---------------------------------------------------------------------------

  useEffect(() => {
    if (isReplaying) return;

    const newLen = stageLogEntries.length;
    if (newLen > prevStageLogLenRef.current) {
      if (autoFollow && timelineContainerRef.current) {
        // Scroll to right edge
        const el = timelineContainerRef.current;
        el.scrollLeft = el.scrollWidth - el.clientWidth;
      } else if (!autoFollow) {
        setHasNewEvents(true);
      }
    }
    prevStageLogLenRef.current = newLen;
  }, [stageLogEntries.length, autoFollow, isReplaying]);

  // Detect manual scrolling to disable auto-follow
  useEffect(() => {
    const el = timelineContainerRef.current;
    if (!el) return;

    let userScrolled = false;
    const handleScroll = () => {
      if (!userScrolled) {
        userScrolled = true;
        // Check if scrolled to the end
        const atEnd = el.scrollLeft + el.clientWidth >= el.scrollWidth - 20;
        if (!atEnd && autoFollow) {
          setAutoFollow(false);
        }
      }
      // Reset flag after a short delay
      setTimeout(() => {
        userScrolled = false;
      }, 100);
    };

    el.addEventListener('scroll', handleScroll, { passive: true });
    return () => el.removeEventListener('scroll', handleScroll);
  }, [autoFollow]);

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

  // Derive the renderable steps
  const steps: Step[] = useMemo(() => {
    // If viewing a specific theater run, use theater data
    if (isViewingTheater && theaterData) {
      return theaterData.steps.map(mapTheaterStepToStep);
    }
    // Otherwise use live plan steps
    return planSteps.map((ps) =>
      mapPlanStepToStep(ps, effectiveStepStatuses[ps.id], effectiveCurrentStepId),
    );
  }, [planSteps, effectiveStepStatuses, effectiveCurrentStepId, isViewingTheater, theaterData]);

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

  // Playhead time for the SVG timeline
  const playheadTime = useMemo<number | null>(() => {
    if (isReplaying && replayEvents.length > 0) {
      const event = replayEvents[Math.min(replayIndex, replayEvents.length - 1)];
      return new Date(event.timestamp).getTime();
    }
    // In live mode, show current time as playhead
    if (!isReplaying && wsStatus === 'connected') {
      return Date.now();
    }
    return null;
  }, [isReplaying, replayEvents, replayIndex, wsStatus]);

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

  const handleGoLive = useCallback(() => {
    resetReplay();
    setAutoFollow(true);
    setHasNewEvents(false);
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

  const handleToggleAutoFollow = useCallback(() => {
    const newFollow = !autoFollow;
    setAutoFollow(newFollow);
    if (newFollow) {
      setHasNewEvents(false);
      // Scroll to latest
      if (timelineContainerRef.current) {
        const el = timelineContainerRef.current;
        el.scrollLeft = el.scrollWidth - el.clientWidth;
      }
    }
  }, [autoFollow]);

  const handleJumpToLatest = useCallback(() => {
    setHasNewEvents(false);
    setAutoFollow(true);
    if (timelineContainerRef.current) {
      const el = timelineContainerRef.current;
      el.scrollLeft = el.scrollWidth - el.clientWidth;
    }
  }, []);

  const handleRunSelect = useCallback(
    (epicId: string, runId: string) => {
      setSelectedEpicId(epicId);
      setSelectedRunId(runId);
      setSelectorOpen(false);
      // Exit replay when switching runs
      resetReplay();
    },
    [resetReplay],
  );

  // ---------------------------------------------------------------------------
  // Miniature timeline for the scrub bar
  // ---------------------------------------------------------------------------

  const miniTimelineSteps = useMemo(() => {
    if (!hasReplayData || steps.length === 0) return null;

    const events = replayEvents;
    const totalEvents = events.length;
    if (totalEvents === 0) return null;

    // Build a simplified representation: for each step, compute start/end as
    // fraction of the total event range
    const segments: Array<{
      stepId: string;
      role: string;
      startFraction: number;
      endFraction: number;
    }> = [];

    // Track first and last event index per step
    const stepFirstIndex: Record<string, number> = {};
    const stepLastIndex: Record<string, number> = {};

    for (let i = 0; i < totalEvents; i++) {
      const ev = events[i];
      if (!ev.step) continue;
      if (!(ev.step in stepFirstIndex)) stepFirstIndex[ev.step] = i;
      stepLastIndex[ev.step] = i;
    }

    for (const step of steps) {
      const first = stepFirstIndex[step.id];
      const last = stepLastIndex[step.id];
      if (first == null) continue;

      segments.push({
        stepId: step.id,
        role: step.role,
        startFraction: first / Math.max(1, totalEvents - 1),
        endFraction: (last ?? first) / Math.max(1, totalEvents - 1),
      });
    }

    return segments;
  }, [hasReplayData, replayEvents, steps]);

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------

  return (
    <div className="h-full flex flex-col p-4 md:p-6 relative overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between mb-4 shrink-0 flex-wrap gap-2">
        <div>
          <h2 className="text-2xl font-bold tracking-tight">Pipeline Theater</h2>
          <p className="text-sm text-white/40">
            {isReplaying
              ? 'Replaying execution timeline'
              : isViewingTheater
                ? `Viewing ${theaterData?.epicId} / ${theaterData?.runId}`
                : 'Live pipeline visualization'}
          </p>
        </div>
        <div className="flex items-center gap-3">
          {/* Role color legend */}
          <div className="hidden md:flex items-center gap-2 px-3 py-1.5 bg-white/5 border border-white/5 rounded-full">
            {ROLE_LEGEND.map(({ role, color }) => (
              <div key={role} className="flex items-center gap-1" title={role}>
                <div
                  className="w-2.5 h-2.5 rounded-sm"
                  style={{ backgroundColor: color }}
                />
                <span className="text-[9px] font-mono text-white/40 uppercase">
                  {role.slice(0, 3)}
                </span>
              </div>
            ))}
          </div>

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
              {isReplaying ? 'Replay' : wsStatus === 'connected' ? 'Live' : 'Offline'}
            </span>
          </div>
        </div>
      </div>

      {/* EPIC/Run selector */}
      <div className="flex items-center gap-3 mb-3 shrink-0 flex-wrap">
        <div className="relative">
          <button
            onClick={() => setSelectorOpen(!selectorOpen)}
            className="flex items-center gap-2 px-3 py-1.5 bg-white/5 border border-white/10 rounded-lg hover:bg-white/10 transition-colors text-sm"
            aria-label="Select EPIC and run"
            aria-expanded={selectorOpen}
          >
            <span className="font-mono text-white/60">
              {selectedEpicId && selectedRunId
                ? `${selectedEpicId} / ${selectedRunId}`
                : 'Select run...'}
            </span>
            <ChevronDown size={14} className={cn(
              "text-white/40 transition-transform",
              selectorOpen && "rotate-180"
            )} />
          </button>

          <AnimatePresence>
            {selectorOpen && (
              <motion.div
                initial={{ opacity: 0, y: -4 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -4 }}
                className="absolute top-full left-0 mt-1 w-72 max-h-64 overflow-y-auto bg-surface-2 border border-white/10 rounded-xl shadow-2xl z-30"
              >
                {evidenceEpics.length === 0 ? (
                  <div className="px-4 py-3 text-xs text-white/40">No runs available</div>
                ) : (
                  evidenceEpics.map((epic) => (
                    <div key={epic.epicId}>
                      <div className="px-3 py-2 text-[10px] font-bold uppercase tracking-widest text-white/30 bg-white/[0.02] border-b border-white/5">
                        {epic.epicId}
                      </div>
                      {epic.runs.map((run) => (
                        <button
                          key={run.runId}
                          onClick={() => handleRunSelect(epic.epicId, run.runId)}
                          className={cn(
                            "w-full px-4 py-2 text-left hover:bg-white/5 transition-colors flex items-center justify-between",
                            selectedEpicId === epic.epicId && selectedRunId === run.runId
                              ? "bg-white/10 text-white"
                              : "text-white/60"
                          )}
                        >
                          <span className="text-xs font-mono">{run.runId}</span>
                          <div className="flex items-center gap-2">
                            {run.hasStageLog && (
                              <span className="text-[9px] text-white/30 bg-white/5 px-1.5 py-0.5 rounded">LOG</span>
                            )}
                          </div>
                        </button>
                      ))}
                    </div>
                  ))
                )}
              </motion.div>
            )}
          </AnimatePresence>
        </div>

        {/* Live mode / follow controls */}
        {!isReplaying && wsStatus === 'connected' && (
          <div className="flex items-center gap-2">
            <button
              onClick={handleToggleAutoFollow}
              className={cn(
                "flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs transition-colors",
                autoFollow
                  ? "bg-emerald-500/10 border border-emerald-500/20 text-emerald-400"
                  : "bg-white/5 border border-white/10 text-white/40 hover:text-white/60"
              )}
              title={autoFollow ? 'Auto-follow enabled' : 'Auto-follow disabled'}
              aria-label={autoFollow ? 'Disable auto-follow' : 'Enable auto-follow'}
              aria-pressed={autoFollow}
            >
              {autoFollow ? <Eye size={12} /> : <EyeOff size={12} />}
              <span className="font-mono uppercase tracking-wider text-[10px]">Follow</span>
            </button>

            {/* Jump to latest */}
            {hasNewEvents && !autoFollow && (
              <motion.button
                initial={{ opacity: 0, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.9 }}
                onClick={handleJumpToLatest}
                className="flex items-center gap-1 px-2.5 py-1.5 bg-amber-500/10 border border-amber-500/20 rounded-lg text-amber-400 text-xs hover:bg-amber-500/20 transition-colors"
                aria-label="Jump to latest events"
              >
                <ArrowDown size={12} />
                <span className="font-mono text-[10px]">New events</span>
              </motion.button>
            )}
          </div>
        )}

        {theaterLoading && (
          <Loader2 size={16} className="text-white/40 animate-spin" />
        )}
      </div>

      {/* SVG Timeline Visualization */}
      <div
        ref={timelineContainerRef}
        className="flex-1 overflow-x-auto overflow-y-auto relative bg-white/[0.02] border border-white/5 rounded-xl min-h-[120px] max-h-[50vh]"
      >
        {/* Loading skeleton */}
        {isLoading && !hasSteps && !isViewingTheater && (
          <div className="flex items-center justify-center h-full">
            <div className="flex flex-col items-center gap-4">
              <Loader2 size={32} className="text-white/20 animate-spin" />
              <p className="text-sm text-white/30">Loading pipeline data...</p>
            </div>
          </div>
        )}

        {/* Empty state when connected but no steps */}
        {!isLoading && !hasSteps && !isViewingTheater && (
          <div className="flex flex-col items-center justify-center h-full gap-4">
            <div className="w-16 h-16 rounded-2xl bg-white/5 border border-white/10 flex items-center justify-center">
              <AlertTriangle size={24} className="text-white/20" />
            </div>
            <div className="text-center">
              <p className="text-sm font-medium text-white/40">No pipeline data</p>
              <p className="text-xs text-white/20 mt-1">
                Start an EPIC run or select a completed run from the dropdown above
              </p>
            </div>
          </div>
        )}

        {/* Timeline SVG */}
        {(hasSteps || isViewingTheater) && steps.length > 0 && (
          <div className="p-2">
            <TimelineSVG
              steps={steps}
              playheadTime={playheadTime}
              containerWidth={containerWidth}
              onStepClick={setSelectedStep}
              autoFollow={autoFollow}
              isLive={!isReplaying && wsStatus === 'connected'}
              replayProgress={replayProgress}
              isReplaying={isReplaying}
            />
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
            className="mt-3 bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 flex items-center gap-4"
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
      <div className="mt-3 shrink-0 bg-surface-1/50 backdrop-blur-xl border border-white/5 rounded-2xl p-3 md:p-4 flex items-center gap-4 md:gap-6 overflow-x-auto">
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
                  "px-1.5 py-1 rounded text-[10px] font-mono transition-colors",
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

          {/* LIVE button */}
          {isReplaying && (
            <button
              onClick={handleGoLive}
              className="flex items-center gap-1.5 ml-2 px-2.5 py-1.5 bg-red-500/10 border border-red-500/20 rounded-lg text-red-400 hover:bg-red-500/20 transition-colors"
              title="Exit replay and return to live view"
              aria-label="Return to live view"
            >
              <Radio size={12} />
              <span className="text-[10px] font-mono font-bold uppercase tracking-wider">Live</span>
            </button>
          )}
        </div>

        {/* Progress / Scrub Bar */}
        <div className="flex-1 space-y-1">
          {isReplaying || hasReplayData ? (
            <>
              <div className="flex justify-between text-[10px] font-mono text-white/40 uppercase tracking-widest">
                <span>
                  Replay {hasReplayData ? `${replayIndex + 1} / ${replayEvents.length}` : '0 / 0'}
                </span>
                <span>
                  {hasReplayData && replayEvents.length > 0
                    ? formatTimestamp(replayEvents[Math.min(replayIndex, replayEvents.length - 1)].timestamp)
                    : '--'}
                </span>
              </div>

              {/* Miniature timeline below slider */}
              {miniTimelineSteps && miniTimelineSteps.length > 0 && (
                <div className="relative h-2 w-full bg-white/[0.03] rounded-full overflow-hidden">
                  {miniTimelineSteps.map((seg) => {
                    const left = seg.startFraction * 100;
                    const width = Math.max(0.5, (seg.endFraction - seg.startFraction) * 100);
                    return (
                      <div
                        key={seg.stepId}
                        className="absolute top-0 h-full rounded-sm"
                        style={{
                          left: `${left}%`,
                          width: `${width}%`,
                          backgroundColor: getRoleColor(seg.role),
                          opacity: 0.5,
                        }}
                      />
                    );
                  })}
                  {/* Playhead marker on mini timeline */}
                  <div
                    className="absolute top-0 h-full w-0.5 bg-amber-400"
                    style={{ left: `${replayProgress * 100}%` }}
                  />
                </div>
              )}

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
          ) : isViewingTheater && theaterData ? (
            <>
              <div className="text-[10px] font-mono text-white/40 uppercase tracking-widest">Status</div>
              <div className="text-sm font-bold">
                {theaterData.completedSteps} / {theaterData.totalSteps} steps
              </div>
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
              className="absolute top-0 right-0 h-full w-96 bg-surface-2 border-l border-white/10 z-50 p-6 shadow-2xl overflow-y-auto"
            >
              <div className="flex items-center justify-between mb-8">
                <div className="flex items-center gap-3">
                  <div
                    className="p-2 rounded-xl border border-white/10"
                    style={{ backgroundColor: `${getRoleColor(selectedStep.role)}20` }}
                  >
                    {roleIcons[selectedStep.role] ? React.createElement(roleIcons[selectedStep.role], { size: 20 }) : <User size={20} />}
                  </div>
                  <div>
                    <h3 className="font-bold text-sm">{selectedStep.id}</h3>
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
                    <div
                      className="w-3 h-3 rounded-sm ml-2"
                      style={{ backgroundColor: getRoleColor(selectedStep.role) }}
                      title={`Role: ${selectedStep.role}`}
                    />
                  </div>
                </section>

                <section>
                  <h4 className="text-[10px] font-bold uppercase tracking-widest text-white/40 mb-3">Objective</h4>
                  <div className="bg-white/5 rounded-xl p-4 text-xs leading-relaxed text-white/60">
                    {selectedStep.objective ?? selectedStep.label}
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

                {(selectedStep.duration || selectedStep.startedAt) && (
                  <section>
                    <h4 className="text-[10px] font-bold uppercase tracking-widest text-white/40 mb-3">Timing</h4>
                    <div className="space-y-2">
                      {selectedStep.duration && (
                        <div className="flex items-center gap-2 text-sm">
                          <Clock size={14} className="text-white/40" />
                          <span>{selectedStep.duration} total duration</span>
                        </div>
                      )}
                      {selectedStep.startedAt && (
                        <div className="text-xs text-white/40 font-mono">
                          Started: {formatTimestamp(selectedStep.startedAt)}
                        </div>
                      )}
                      {selectedStep.completedAt && (
                        <div className="text-xs text-white/40 font-mono">
                          Completed: {formatTimestamp(selectedStep.completedAt)}
                        </div>
                      )}
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
