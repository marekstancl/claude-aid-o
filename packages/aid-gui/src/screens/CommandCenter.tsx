import React, { useEffect, useMemo, useState, useCallback } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { useStore, stateColors } from '../store';
import { createApiClient } from '../api/client';
import { cn } from '../lib/utils';
import {
  Zap,
  Heart,
  Gavel,
  Layers,
  Clock,
  WifiOff,
  Activity,
  CheckCircle2,
  XCircle,
  Pause,
  ChevronRight,
  ChevronDown,
  Bot,
  ShieldAlert,
  Syringe,
  Play,
  Rocket,
  Loader2,
  X,
  Sparkles,
  User,
  Database,
  Layout,
  FileText,
} from 'lucide-react';
import type { QueueScheduleEntry, EpicMetadata, UsageResponse } from '../types/api';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function formatDuration(seconds: number): string {
  if (seconds < 0) return '0s';
  if (seconds < 60) return `${seconds}s`;
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  if (m < 60) return `${m}m ${s}s`;
  const h = Math.floor(m / 60);
  return `${h}h ${m % 60}m`;
}

/** Map FSM state to a medical/hospital-themed display label. */
function stateLabel(state: string): string {
  const map: Record<string, string> = {
    IDLE: 'On Call',
    PLAN_REVIEW: 'Diagnosis',
    PLAN_READY: 'Prescription',
    EXECUTING: 'Infusing',
    PHASE_CHECK: 'Vital Signs',
    PHASE_RETRY: 'Second Opinion',
    GATES: 'Lab Results',
    GATES_RETRY: 'Retest',
    PM_APPROVAL: "Doctor's Orders",
    CURATOR_RESOLVE: 'Recovery',
    DONE: 'Discharged',
    ERROR: 'Code Red',
    // FIRST AID autonomous mode wrapper states
    FIRST_AID_INIT: 'Triage',
    QUEUE_PROCESSING: 'Operating',
    QUEUE_ADVANCE: 'Next Patient',
    FIRST_AID_COMPLETE: 'All Clear',
  };
  return map[state] ?? state;
}

const ACTIVE_STATES = new Set([
  'EXECUTING',
  'PHASE_CHECK',
  'PHASE_RETRY',
  'GATES',
  'GATES_RETRY',
  'PM_APPROVAL',
  'CURATOR_RESOLVE',
  'PLAN_REVIEW',
  'PLAN_READY',
  // FIRST AID autonomous mode wrapper states
  'FIRST_AID_INIT',
  'QUEUE_PROCESSING',
  'QUEUE_ADVANCE',
]);

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export const CommandCenter: React.FC = () => {
  const { fsmState, progress, epic, duration } = useStore();
  const wsStatus = useStore((s) => s.wsStatus);
  const healthScore = useStore((s) => s.healthScore);
  const pendingDecisions = useStore((s) => s.pendingDecisions);
  const currentEpicId = useStore((s) => s.currentEpicId);
  const currentStepId = useStore((s) => s.currentStepId);
  const pipelineProgress = useStore((s) => s.pipelineProgress);
  const steps = useStore((s) => s.steps);
  const stepStatuses = useStore((s) => s.stepStatuses);
  const activeProject = useStore((s) => s.activeProject);
  const autoModeSession = useStore((s) => s.autoModeSession);
  const stageLogEntries = useStore((s) => s.stageLogEntries);

  const isLoading = wsStatus === 'connecting';
  const isDisconnected = wsStatus === 'disconnected';
  const isReconnecting = wsStatus === 'reconnecting';
  const isActive = ACTIVE_STATES.has(fsmState);

  // Prefer the pipeline-slice epicId, fall back to legacy epic
  const displayEpic = currentEpicId || epic || null;

  // Local state for additional data
  const [queueEntries, setQueueEntries] = useState<QueueScheduleEntry[]>([]);
  const [epics, setEpics] = useState<EpicMetadata[]>([]);
  const [usageData, setUsageData] = useState<UsageResponse | null>(null);
  // Live elapsed timer
  const [now, setNow] = useState(Date.now());
  // Satellite detail expansion
  const [selectedSatellite, setSelectedSatellite] = useState<string | null>(null);
  // EPIC run loading state
  const [runLoading, setRunLoading] = useState<string | null>(null);
  // EPIC summary slide-over
  const [summaryEpic, setSummaryEpic] = useState<QueueScheduleEntry | null>(null);
  const [summaryData, setSummaryData] = useState<{ report?: string; plan?: any; progress?: any; gates?: any } | null>(null);
  const [summaryLoading, setSummaryLoading] = useState(false);

  // Swap between current EPIC % and total % every 4 seconds (always, even when idle)
  const [showTotal, setShowTotal] = useState(false);
  useEffect(() => {
    const id = setInterval(() => setShowTotal((p) => !p), 4000);
    return () => clearInterval(id);
  }, []);

  // Tick every second for live elapsed timers
  useEffect(() => {
    if (!isActive) return;
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, [isActive]);

  // Fetch queue + epics + usage data on mount and periodically
  useEffect(() => {
    if (!activeProject) return;
    let cancelled = false;
    const load = async () => {
      const client = createApiClient(activeProject.id);
      const [qr, er, ur] = await Promise.allSettled([
        client.getQueue(),
        client.getEpics(),
        client.getUsage(),
      ]);
      if (cancelled) return;
      if (qr.status === 'fulfilled' && qr.value.ok) setQueueEntries(qr.value.data.queue ?? []);
      if (er.status === 'fulfilled' && er.value.ok) setEpics(er.value.data ?? []);
      if (ur.status === 'fulfilled' && ur.value.ok) setUsageData(ur.value.data);
    };
    load();
    const interval = setInterval(load, 15000);
    return () => { cancelled = true; clearInterval(interval); };
  }, [activeProject]);

  // Queue-level progress from aggregate data (correct across session)
  const { epicsCompleted, epicsTotal } = pipelineProgress;
  const epicPct = epicsTotal > 0 ? Math.round((epicsCompleted / epicsTotal) * 100) : 0;

  // Per-EPIC step progress — derived from real-time stepStatuses (state.yaml),
  // NOT from the aggregate pipelineProgress which accumulates across ALL EPICs.
  const { currentStepsDone, currentStepsTotal } = useMemo(() => {
    const entries = Object.values(stepStatuses);
    if (entries.length === 0) return { currentStepsDone: 0, currentStepsTotal: 0 };
    const done = entries.filter((s) => s.status === 'done' || s.status === 'skipped').length;
    return { currentStepsDone: done, currentStepsTotal: entries.length };
  }, [stepStatuses]);
  const stepPct = currentStepsTotal > 0 ? Math.round((currentStepsDone / currentStepsTotal) * 100) : 0;

  // Find current step info
  const currentStep = useMemo(() => {
    if (!currentStepId) return null;
    return steps.find((s) => s.id === currentStepId) ?? null;
  }, [currentStepId, steps]);

  // Queue breakdown
  const running = useMemo(() => queueEntries.filter((e) => e.status === 'running'), [queueEntries]);
  const queued = useMemo(() => queueEntries.filter((e) => e.status === 'queued'), [queueEntries]);
  const completed = useMemo(() => queueEntries.filter((e) => e.status === 'completed'), [queueEntries]);
  const failed = useMemo(() => queueEntries.filter((e) => e.status === 'failed'), [queueEntries]);

  // Session-queued EPIC IDs — EPICs in the active FIRST AID queue that haven't started yet
  const sessionQueuedIds = useMemo(() => {
    if (!autoModeSession?.queueSnapshot) return new Set<string>();
    const runningIds = new Set(running.map((e) => e.epicId));
    const completedIds = new Set(completed.map((e) => e.epicId));
    const failedIds = new Set(failed.map((e) => e.epicId));
    return new Set(
      autoModeSession.queueSnapshot.filter(
        (id: string) => !runningIds.has(id) && !completedIds.has(id) && !failedIds.has(id),
      ),
    );
  }, [autoModeSession, running, completed, failed]);

  // Latest meaningful stage_log entry for progress strip
  const latestActivity = useMemo(() => {
    if (stageLogEntries.length === 0) return null;
    // Find last meaningful entry (skip noise)
    for (let i = stageLogEntries.length - 1; i >= 0; i--) {
      const e = stageLogEntries[i];
      if (e.action) return e;
    }
    return stageLogEntries[stageLogEntries.length - 1];
  }, [stageLogEntries]);

  // Use progress ring from per-EPIC step progress when active
  const ringProgress = isActive && currentStepsTotal > 0
    ? currentStepsDone / currentStepsTotal
    : progress;

  // Get the color for the current state
  const color = stateColors[fsmState] ?? stateColors.IDLE;

  // Compute live elapsed for the running EPIC
  const runningEntry = running[0];
  const currentEpicElapsed = useMemo(() => {
    if (!runningEntry?.startedAt) return null;
    const sec = Math.max(0, Math.floor((now - new Date(runningEntry.startedAt).getTime()) / 1000));
    return formatDuration(sec);
  }, [runningEntry?.startedAt, now]);

  // Total session elapsed (from earliest started entry)
  const sessionElapsed = useMemo(() => {
    const allStarted = queueEntries.filter((e) => e.startedAt).map((e) => new Date(e.startedAt!).getTime());
    if (allStarted.length === 0) return null;
    const earliest = Math.min(...allStarted);
    const sec = Math.max(0, Math.floor((now - earliest) / 1000));
    return formatDuration(sec);
  }, [queueEntries, now]);

  // Ring animation — track FSM state transitions
  const prevFsmState = React.useRef(fsmState);
  const [ringPhase, setRingPhase] = useState<'idle' | 'injecting' | 'active' | 'depleting' | 'allClear'>('idle');
  const [showParticles, setShowParticles] = useState(false);

  useEffect(() => {
    const prev = prevFsmState.current;
    prevFsmState.current = fsmState;

    // Detect injection: transition from idle/done to active
    const wasIdle = !ACTIVE_STATES.has(prev) && prev !== 'ERROR';
    const nowActive = ACTIVE_STATES.has(fsmState);
    if (wasIdle && nowActive) {
      setRingPhase('injecting');
      setShowParticles(true);
      setTimeout(() => setShowParticles(false), 2000);
      setTimeout(() => setRingPhase('active'), 2500);
      return;
    }

    // Detect completion: transition from active to done/complete
    const wasBusy = ACTIVE_STATES.has(prev);
    const nowDone = fsmState === 'DONE' || fsmState === 'FIRST_AID_COMPLETE';
    if (wasBusy && nowDone) {
      setRingPhase('depleting');
      setTimeout(() => setRingPhase('allClear'), 2000);
      return;
    }

    // Error state
    if (fsmState === 'ERROR') {
      setRingPhase('idle');
      return;
    }

    // Steady states
    if (nowActive) setRingPhase('active');
    else if (nowDone) setRingPhase('allClear');
    else setRingPhase('idle');
  }, [fsmState]);

  // Compute ring visual properties based on phase
  const ringColor = useMemo(() => {
    if (ringPhase === 'allClear') return 'var(--color-state-done)';
    if (ringPhase === 'injecting') return 'var(--color-state-executing)';
    return color;
  }, [ringPhase, color]);

  const ringGlow = ringPhase === 'injecting' ? 16 : ringPhase === 'allClear' ? 6 : 8;

  // Handle EPIC run from Command Center
  const handleRunEpic = useCallback(async (epicId: string) => {
    if (!activeProject || runLoading) return;
    setRunLoading(epicId);
    const client = createApiClient(activeProject.id);
    const result = await client.runEpic(epicId, 'now');
    if (result.ok) {
      // Re-fetch queue
      const qr = await client.getQueue();
      if (qr.ok) setQueueEntries(qr.data.queue ?? []);
    }
    setRunLoading(null);
  }, [activeProject, runLoading]);

  // Handle opening EPIC summary
  const handleOpenSummary = useCallback(async (entry: QueueScheduleEntry) => {
    if (!activeProject) return;
    setSummaryEpic(entry);
    setSummaryLoading(true);
    setSummaryData(null);

    const client = createApiClient(activeProject.id);
    // Find the latest run for this EPIC from evidence
    const ev = await client.getEvidence();
    if (ev.ok) {
      const epicEvidence = ev.data.find((e: any) => e.epicId === entry.epicId);
      if (epicEvidence && epicEvidence.runs.length > 0) {
        const latestRun = epicEvidence.runs[epicEvidence.runs.length - 1];
        const [report, plan, progress, gates] = await Promise.allSettled([
          latestRun.files.includes('final_report.md')
            ? client.getEvidenceFile(entry.epicId, latestRun.runId, 'final_report.md')
            : Promise.resolve(null),
          latestRun.hasPlan
            ? client.getEvidenceFile(entry.epicId, latestRun.runId, 'plan.json')
            : Promise.resolve(null),
          latestRun.files.includes('state.yaml')
            ? client.getEvidenceFile(entry.epicId, latestRun.runId, 'state.yaml')
            : Promise.resolve(null),
          latestRun.hasGatesReport
            ? client.getEvidenceFile(entry.epicId, latestRun.runId, 'gates_report.json')
            : Promise.resolve(null),
        ]);
        setSummaryData({
          report: report.status === 'fulfilled' && report.value && (report.value as any).ok ? (report.value as any).data.content : undefined,
          plan: plan.status === 'fulfilled' && plan.value && (plan.value as any).ok ? (plan.value as any).data.content : undefined,
          progress: progress.status === 'fulfilled' && progress.value && (progress.value as any).ok ? (progress.value as any).data.content : undefined,
          gates: gates.status === 'fulfilled' && gates.value && (gates.value as any).ok ? (gates.value as any).data.content : undefined,
        });
      }
    }
    setSummaryLoading(false);
  }, [activeProject]);

  return (
    <div className="h-full flex flex-col items-center justify-center p-8 relative overflow-hidden">
      {/* Background Ambient Glow */}
      <div
        className="absolute inset-0 pointer-events-none transition-colors duration-1000 opacity-20"
        style={{
          background: `radial-gradient(circle at 50% 50%, ${color}, transparent 70%)`,
        }}
      />

      {/* Disconnected / Reconnecting Banner */}
      {(isDisconnected || isReconnecting) && (
        <div className="absolute top-4 left-1/2 -translate-x-1/2 z-20 flex items-center gap-2 px-4 py-2 bg-red-500/10 border border-red-500/20 rounded-full backdrop-blur-sm">
          <WifiOff size={14} className="text-red-400" />
          <span className="text-xs text-red-400/80 font-mono">
            {isDisconnected ? 'Connection lost' : 'Reconnecting...'}
          </span>
          {isDisconnected && (
            <button
              onClick={() => window.location.reload()}
              className="text-xs text-red-300 underline underline-offset-2 hover:text-red-200 transition-colors"
            >
              Retry
            </button>
          )}
        </div>
      )}

      {/* Central Radial Element */}
      <div className="relative z-10 flex flex-col items-center">
        <div className="relative w-96 h-96 flex items-center justify-center">
          {/* Background ring */}
          <svg className="absolute inset-0 w-full h-full -rotate-90" viewBox="0 0 320 320">
            {/* Defs for ring gradients */}
            <defs>
              <linearGradient id="ring-inject-grad" x1="0%" y1="0%" x2="100%" y2="0%">
                <stop offset="0%" stopColor={ringColor} stopOpacity="0.3" />
                <stop offset="85%" stopColor={ringColor} stopOpacity="1" />
                <stop offset="100%" stopColor="white" stopOpacity="1" />
              </linearGradient>
            </defs>
            <circle
              cx="160"
              cy="160"
              r="140"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              className="text-white/5"
            />
            {/* All Clear: dotted ring background */}
            {ringPhase === 'allClear' && (
              <motion.circle
                cx="160"
                cy="160"
                r="140"
                fill="none"
                stroke={ringColor}
                strokeWidth="2"
                strokeDasharray="8 12"
                initial={{ opacity: 0 }}
                animate={{ opacity: 0.3 }}
                transition={{ duration: 1 }}
              />
            )}
            <motion.circle
              cx="160"
              cy="160"
              r="140"
              fill="none"
              stroke={ringPhase === 'injecting' ? 'url(#ring-inject-grad)' : 'currentColor'}
              strokeWidth={ringPhase === 'injecting' ? 6 : ringPhase === 'allClear' ? 3 : 4}
              strokeDasharray="880"
              strokeLinecap="round"
              initial={{ strokeDashoffset: 880 }}
              animate={{
                strokeDashoffset: ringPhase === 'allClear' ? 0
                  : ringPhase === 'depleting' ? 0
                  : 880 - 880 * ringProgress,
              }}
              transition={{
                duration: ringPhase === 'injecting' ? 2.5
                  : ringPhase === 'depleting' ? 2
                  : 1.5,
                ease: ringPhase === 'injecting'
                  ? [0.1, 0, 0.3, 1] // slow start, accelerate
                  : 'easeOut',
              }}
              style={{ color: ringColor }}
              className={`drop-shadow-[0_0_${ringGlow}px_currentColor]`}
            />
          </svg>

          {/* Syringe injection animation */}
          <AnimatePresence>
            {ringPhase === 'injecting' && (
              <motion.div
                className="absolute -top-4 left-1/2 -translate-x-1/2"
                initial={{ scale: 0, opacity: 0, rotate: -30 }}
                animate={{ scale: [0, 1.3, 1], opacity: [0, 1, 0], rotate: [-30, 0, 0] }}
                exit={{ scale: 0, opacity: 0 }}
                transition={{ duration: 1.5, ease: 'easeOut' }}
              >
                <Syringe size={24} style={{ color: ringColor, filter: `drop-shadow(0 0 8px ${ringColor})` }} />
              </motion.div>
            )}
          </AnimatePresence>

          {/* Particle burst on injection */}
          <AnimatePresence>
            {showParticles && (
              <>
                {[0, 60, 120, 200, 280, 340].map((angle, i) => (
                  <motion.div
                    key={`particle-${angle}`}
                    className="absolute w-1.5 h-1.5 rounded-full"
                    style={{
                      backgroundColor: ringColor,
                      left: '50%',
                      top: '50%',
                      boxShadow: `0 0 6px ${ringColor}`,
                    }}
                    initial={{ x: 0, y: 0, opacity: 1, scale: 1 }}
                    animate={{
                      x: Math.cos((angle * Math.PI) / 180) * (60 + i * 10),
                      y: Math.sin((angle * Math.PI) / 180) * (60 + i * 10),
                      opacity: 0,
                      scale: 0,
                    }}
                    exit={{ opacity: 0 }}
                    transition={{ duration: 1.5, delay: i * 0.08, ease: 'easeOut' }}
                  />
                ))}
              </>
            )}
          </AnimatePresence>

          {/* All Clear breathing pulse overlay */}
          {ringPhase === 'allClear' && (
            <motion.div
              className="absolute inset-0 rounded-full border-2"
              style={{ borderColor: ringColor }}
              animate={{ scale: [1, 1.03, 1], opacity: [0.15, 0.3, 0.15] }}
              transition={{ duration: 3, repeat: Infinity, ease: 'easeInOut' }}
            />
          )}

          {/* Inner Content */}
          <div className="text-center space-y-1">
            <motion.span
              key={fsmState}
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              className="block text-[10px] uppercase tracking-[0.3em] text-white/40 font-bold"
            >
              {isActive ? 'Pipeline Active' : 'Pipeline Status'}
            </motion.span>

            {isLoading ? (
              <div className="flex flex-col items-center gap-2">
                <div className="h-12 w-48 bg-white/5 rounded animate-pulse" />
              </div>
            ) : (
              <motion.h1
                key={fsmState + 'title'}
                initial={{ opacity: 0, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                className={cn(
                  'text-5xl font-bold tracking-tighter',
                  isActive && 'animate-heartbeat',
                )}
                style={{
                  background: `linear-gradient(to bottom, white, ${color})`,
                  WebkitBackgroundClip: 'text',
                  WebkitTextFillColor: 'transparent',
                }}
              >
                {stateLabel(fsmState)}
              </motion.h1>
            )}

            {/* Current step info */}
            {isActive && currentStep && (
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                className="text-[10px] text-white/30 mt-1"
              >
                <span className="text-white/50 font-mono">{currentStep.role}</span>
                <span className="mx-1">&middot;</span>
                <span className="max-w-[200px] truncate inline-block align-bottom">
                  {currentStep.objective}
                </span>
              </motion.div>
            )}

            {/* ECG Heartbeat Line — continuous scrolling animation */}
            <div
              className="flex items-center justify-center mt-3"
              style={{
                maskImage: 'linear-gradient(to right, transparent 0%, black 15%, black 85%, transparent 100%)',
                WebkitMaskImage: 'linear-gradient(to right, transparent 0%, black 15%, black 85%, transparent 100%)',
              }}
            >
              <svg
                viewBox="0 0 200 40"
                className="w-48 h-8"
                preserveAspectRatio="xMidYMid meet"
              >
                {/* Faded baseline */}
                <line
                  x1="0" y1="20" x2="200" y2="20"
                  stroke="currentColor" strokeWidth="0.5"
                  className="text-white/5"
                />
                {isActive ? (
                  <g>
                    {/* Clip to visible area */}
                    <defs>
                      <clipPath id="ecg-clip">
                        <rect x="0" y="0" width="200" height="40" />
                      </clipPath>
                    </defs>
                    {/* Wide ECG path that scrolls left continuously */}
                    <g clipPath="url(#ecg-clip)">
                      <path
                        d="M 0,20 L 15,20 L 20,20 Q 25,20 28,10 Q 30,2 32,20 Q 34,35 36,20 Q 38,5 40,20 L 45,20 L 60,20 L 65,20 Q 68,15 70,20 Q 72,25 74,20 L 90,20 L 100,20 L 115,20 L 120,20 Q 125,20 128,10 Q 130,2 132,20 Q 134,35 136,20 Q 138,5 140,20 L 145,20 L 160,20 L 165,20 Q 168,15 170,20 Q 172,25 174,20 L 190,20 L 200,20 L 215,20 L 220,20 Q 225,20 228,10 Q 230,2 232,20 Q 234,35 236,20 Q 238,5 240,20 L 245,20 L 260,20 L 265,20 Q 268,15 270,20 Q 272,25 274,20 L 290,20 L 300,20 L 315,20 L 320,20 Q 325,20 328,10 Q 330,2 332,20 Q 334,35 336,20 Q 338,5 340,20 L 345,20 L 360,20 L 365,20 Q 368,15 370,20 Q 372,25 374,20 L 390,20 L 400,20"
                        fill="none"
                        stroke={color}
                        strokeWidth="2"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        style={{ filter: `drop-shadow(0 0 4px ${color})` }}
                      >
                        <animateTransform
                          attributeName="transform"
                          type="translate"
                          values="0,0;-200,0"
                          dur="2.4s"
                          repeatCount="indefinite"
                        />
                      </path>
                    </g>
                  </g>
                ) : (
                  <line
                    x1="0" y1="20" x2="200" y2="20"
                    stroke="currentColor" strokeWidth="1"
                    className="text-white/10"
                  />
                )}
              </svg>
            </div>

            {/* Step progress text */}
            {isActive && currentStepsTotal > 0 && (
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                className="text-[10px] text-white/25 font-mono"
              >
                Step {currentStepsDone}/{currentStepsTotal}
              </motion.div>
            )}
          </div>
        </div>

        {/* Progress Strip — below the circle */}
        <div className="mt-6 w-full max-w-2xl bg-white/5 border border-white/5 rounded-full p-1 flex items-center relative overflow-hidden glass">
          {/* Left: queue counter during FIRST AID, or "Start" when idle */}
          <div className="absolute left-4 text-[10px] font-mono text-white/20 uppercase tracking-widest">
            {isActive && epicsTotal > 0
              ? `${epicsCompleted + (running.length > 0 ? 1 : 0)}/${epicsTotal}`
              : 'Start'}
          </div>

          <div className="flex-1 flex items-center justify-center py-2.5">
            {isActive ? (
              <div className="relative h-5 w-80 flex items-center justify-center overflow-hidden">
                <AnimatePresence mode="wait">
                  <motion.div
                    key={currentStepsTotal > 0 ? `steps-${currentStepsDone}` : latestActivity?.action ?? fsmState}
                    initial={{ opacity: 0, y: 8 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: -8 }}
                    transition={{ duration: 0.4 }}
                    className="absolute inset-0 flex items-center justify-center"
                  >
                    {currentStepsTotal > 0 ? (
                      /* Step progress — primary display when plan exists */
                      <span className="text-xs font-mono text-white/50">
                        <span className="text-white/80 font-bold">{stepPct}%</span>
                        <span className="text-white/25 ml-1.5">
                          step {currentStepsDone}/{currentStepsTotal}
                        </span>
                        {displayEpic && (
                          <span className="text-white/15 ml-1.5">· {displayEpic}</span>
                        )}
                      </span>
                    ) : latestActivity ? (
                      /* Live activity from stage_log when no plan yet */
                      <span className="text-[10px] font-mono text-white/40 truncate max-w-full px-2">
                        <span className="text-white/60">{latestActivity.action.replace(/_/g, ' ')}</span>
                        {latestActivity.details && (
                          <span className="text-white/20 ml-1">— {latestActivity.details.slice(0, 40)}</span>
                        )}
                      </span>
                    ) : (
                      /* Fallback: state label + session info */
                      <span className="text-xs font-mono text-white/40">
                        <span className="text-white/60">{stateLabel(fsmState)}</span>
                        {autoModeSession?.aggregate?.totalStepsExecuted > 0 && (
                          <span className="text-white/20 ml-1.5">
                            · {autoModeSession.aggregate.totalStepsExecuted} steps done
                          </span>
                        )}
                        {displayEpic && (
                          <span className="text-white/15 ml-1.5">· {displayEpic}</span>
                        )}
                      </span>
                    )}
                  </motion.div>
                </AnimatePresence>
              </div>
            ) : (
              /* Dynamic step dots when available, or static when idle */
              <div className="flex items-center gap-3">
                {steps.length > 0
                  ? steps.map((s) => {
                      const st = stepStatuses[s.id];
                      const isDone = st?.status === 'done';
                      const isExec = st?.status === 'executing';
                      const isFailed = st?.status === 'failed';
                      return (
                        <motion.div
                          key={s.id}
                          initial={{ opacity: 0 }}
                          animate={{ opacity: 1 }}
                          title={`${s.role}: ${s.objective}`}
                          className={cn(
                            'w-2 h-2 rounded-full transition-colors',
                            isDone
                              ? 'bg-state-done'
                              : isExec
                                ? 'bg-state-executing animate-pulse'
                                : isFailed
                                  ? 'bg-state-error'
                                  : 'bg-white/5',
                          )}
                        />
                      );
                    })
                  : [...Array(8)].map((_, i) => (
                      <div key={i} className="w-1.5 h-1.5 rounded-full bg-white/5" />
                    ))}
              </div>
            )}
          </div>

          <div className="absolute right-4 text-[10px] font-mono text-white/20 uppercase tracking-widest">
            {isActive ? (
              <span style={{ color }}>{stepPct}%</span>
            ) : (
              'End'
            )}
          </div>
        </div>

        {/* EPIC info + duration row */}
        <div className="mt-6 flex items-center gap-5 text-white/40 flex-wrap justify-center">
          <div className="flex items-center gap-2">
            <Zap size={14} style={{ color }} />
            {isLoading ? (
              <div className="h-4 w-32 bg-white/5 rounded animate-pulse" />
            ) : (
              <span className="text-xs font-mono">{displayEpic || 'NO ACTIVE EPIC'}</span>
            )}
          </div>
          {/* Current EPIC elapsed */}
          {currentEpicElapsed && (
            <div className="flex items-center gap-1.5">
              <Clock size={12} />
              <span className="text-[11px] font-mono">{currentEpicElapsed}</span>
              <span className="text-[9px] text-white/20">epic</span>
            </div>
          )}
          {/* Total session elapsed */}
          {sessionElapsed && (
            <div className="flex items-center gap-1.5">
              <Clock size={12} className="text-white/25" />
              <span className="text-[11px] font-mono text-white/30">{sessionElapsed}</span>
              <span className="text-[9px] text-white/15">total</span>
            </div>
          )}
          {/* Legacy duration fallback */}
          {!currentEpicElapsed && !sessionElapsed && (
            <div className="flex items-center gap-2">
              <Clock size={14} />
              <span className="text-xs font-mono">{duration || '--:--'}</span>
            </div>
          )}
        </div>

        {/* Satellite Metrics — alternate current/total every 4s */}
        <div className="mt-10 grid grid-cols-4 gap-4 w-full max-w-4xl">
          {isLoading ? (
            <>
              <SatelliteCardSkeleton />
              <SatelliteCardSkeleton />
              <SatelliteCardSkeleton />
              <SatelliteCardSkeleton />
            </>
          ) : (
            <>
              {/* Ward (Queue) */}
              <SatelliteCard
                icon={Layers}
                label="Ward"
                showTotal={showTotal}
                selected={selectedSatellite === 'Ward'}
                onClick={() => setSelectedSatellite(selectedSatellite === 'Ward' ? null : 'Ward')}
                current={{
                  value: `${running.length + queued.length}`,
                  sub: running.length > 0
                    ? `${running.length} operating · ${queued.length} waiting`
                    : queued.length > 0
                      ? `${queued.length} in queue`
                      : 'empty',
                }}
                total={{
                  value: `${completed.length + failed.length}`,
                  sub: failed.length > 0
                    ? `${completed.length} discharged · ${failed.length} failed`
                    : `${completed.length} discharged`,
                }}
                color="var(--color-state-plan-ready)"
              />
              {/* Lab (Gates) */}
              <SatelliteCard
                icon={Syringe}
                label="Lab"
                showTotal={showTotal}
                selected={selectedSatellite === 'Lab'}
                onClick={() => setSelectedSatellite(selectedSatellite === 'Lab' ? null : 'Lab')}
                current={{
                  value: autoModeSession?.aggregate?.totalGateRuns ?? (usageData?.gateEvaluations ?? 0),
                  sub: `${autoModeSession?.aggregate?.totalGateRetries ?? 0} retests`,
                }}
                total={{
                  value: healthScore !== null ? `${healthScore}%` : '--',
                  sub: healthScore !== null ? 'audit score' : 'no audit yet',
                }}
                color="var(--color-state-gates)"
              />
              {/* Escalations */}
              <SatelliteCard
                icon={ShieldAlert}
                label="Escalations"
                showTotal={showTotal}
                selected={selectedSatellite === 'Escalations'}
                onClick={() => setSelectedSatellite(selectedSatellite === 'Escalations' ? null : 'Escalations')}
                current={{
                  value: autoModeSession?.escalation
                    ? `${autoModeSession.escalation.count}/${autoModeSession.escalation.budget}`
                    : pendingDecisions > 0 ? String(pendingDecisions) : '0',
                  sub: autoModeSession?.escalation
                    ? `${autoModeSession.escalation.budget - autoModeSession.escalation.count} remaining`
                    : pendingDecisions > 0 ? 'pending decisions' : 'no escalations',
                }}
                total={{
                  value: autoModeSession?.aggregate?.totalEscalations ?? (usageData?.escalations ?? 0),
                  sub: 'total escalations',
                }}
                color="var(--color-state-pm-approval)"
                pulse={pendingDecisions > 0 || (autoModeSession?.escalation?.count ?? 0) >= (autoModeSession?.escalation?.budget ?? 1)}
              />
              {/* Vitals (Session) */}
              <SatelliteCard
                icon={Activity}
                label="Vitals"
                showTotal={showTotal}
                selected={selectedSatellite === 'Vitals'}
                onClick={() => setSelectedSatellite(selectedSatellite === 'Vitals' ? null : 'Vitals')}
                current={{
                  value: autoModeSession?.aggregate?.totalStepsExecuted ?? (usageData?.agentDispatches ?? 0),
                  sub: 'steps executed',
                }}
                total={{
                  value: usageData?.totalEvents ?? 0,
                  sub: 'total events',
                }}
                color="var(--color-state-executing)"
              />
            </>
          )}
        </div>

        {/* Satellite Detail Panel */}
        <AnimatePresence>
          {selectedSatellite && !isLoading && (
            <motion.div
              key={selectedSatellite}
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: 'auto' }}
              exit={{ opacity: 0, height: 0 }}
              transition={{ type: 'spring', damping: 25, stiffness: 300 }}
              className="w-full max-w-4xl mt-4 overflow-hidden"
            >
              <div className="glass rounded-2xl p-4 border border-white/5">
                <div className="flex items-center justify-between mb-3">
                  <span className="text-[10px] uppercase tracking-[0.2em] text-white/40 font-bold">
                    {selectedSatellite} Detail
                  </span>
                  <button
                    onClick={() => setSelectedSatellite(null)}
                    className="p-1 hover:bg-white/10 rounded text-white/30 hover:text-white/60 transition-colors"
                  >
                    <X size={12} />
                  </button>
                </div>

                {selectedSatellite === 'Ward' && (
                  <div className="space-y-2">
                    {queueEntries.length === 0 ? (
                      <p className="text-xs text-white/20">No entries in queue</p>
                    ) : (
                      [...queueEntries].sort((a, b) => new Date(b.addedAt).getTime() - new Date(a.addedAt).getTime()).map((e) => {
                        const meta = epics.find((m) => m.id === e.epicId);
                        const cfg = statusConfig[e.status] ?? statusConfig.queued;
                        const Icon = cfg.icon;
                        const dur = e.startedAt && e.completedAt
                          ? formatDuration(Math.floor((new Date(e.completedAt).getTime() - new Date(e.startedAt).getTime()) / 1000))
                          : e.startedAt
                            ? formatDuration(Math.max(0, Math.floor((now - new Date(e.startedAt).getTime()) / 1000)))
                            : null;
                        return (
                          <div key={e.epicId} className="flex items-center gap-3 py-1 border-b border-white/5 last:border-0">
                            <Icon size={12} className={cfg.color} />
                            <span className="text-xs text-white/60 flex-1">{meta?.title ?? e.epicId}</span>
                            <span className={cn('text-[9px] font-mono', priorityColors[e.priority])}>{e.priority}</span>
                            {dur && <span className="text-[9px] font-mono text-white/20">{dur}</span>}
                            <span className="text-[9px] text-white/20">{cfg.label}</span>
                          </div>
                        );
                      })
                    )}
                  </div>
                )}

                {selectedSatellite === 'Lab' && (
                  <div className="grid grid-cols-2 gap-4">
                    <div className="space-y-2">
                      <div className="text-[10px] text-white/30 uppercase tracking-wider font-bold">Gates</div>
                      <div className="flex items-baseline gap-2">
                        <span className="text-2xl font-bold">{autoModeSession?.aggregate?.totalGateRuns ?? (usageData?.gateEvaluations ?? 0)}</span>
                        <span className="text-[10px] text-white/20">evaluations</span>
                      </div>
                      <div className="flex items-baseline gap-2">
                        <span className="text-lg font-bold text-amber-400">{autoModeSession?.aggregate?.totalGateRetries ?? 0}</span>
                        <span className="text-[10px] text-white/20">retests</span>
                      </div>
                    </div>
                    <div className="space-y-2">
                      <div className="text-[10px] text-white/30 uppercase tracking-wider font-bold">Audit</div>
                      <div className="flex items-baseline gap-2">
                        <span className="text-2xl font-bold" style={{ color: healthScore !== null && healthScore >= 80 ? 'var(--color-state-done)' : healthScore !== null && healthScore >= 50 ? '#f59e0b' : 'var(--color-state-error)' }}>
                          {healthScore !== null ? `${healthScore}%` : '--'}
                        </span>
                        <span className="text-[10px] text-white/20">health score</span>
                      </div>
                    </div>
                  </div>
                )}

                {selectedSatellite === 'Escalations' && (
                  <div className="space-y-2">
                    {autoModeSession?.escalation ? (
                      <>
                        <div className="flex items-center gap-4">
                          <div>
                            <span className="text-2xl font-bold">{autoModeSession.escalation.count}</span>
                            <span className="text-xs text-white/20 ml-1">/ {autoModeSession.escalation.budget}</span>
                          </div>
                          <div className="flex-1 h-2 bg-white/5 rounded-full overflow-hidden">
                            <div
                              className="h-full rounded-full transition-all"
                              style={{
                                width: `${Math.min(100, (autoModeSession.escalation.count / autoModeSession.escalation.budget) * 100)}%`,
                                backgroundColor: autoModeSession.escalation.count >= autoModeSession.escalation.budget
                                  ? 'var(--color-state-error)' : 'var(--color-state-pm-approval)',
                              }}
                            />
                          </div>
                        </div>
                        <p className="text-[10px] text-white/20">
                          {autoModeSession.escalation.budget - autoModeSession.escalation.count} escalations remaining before budget exhausted
                        </p>
                      </>
                    ) : pendingDecisions > 0 ? (
                      <div className="flex items-center gap-2">
                        <span className="text-2xl font-bold text-state-pm-approval">{pendingDecisions}</span>
                        <span className="text-xs text-white/20">pending decisions requiring attention</span>
                      </div>
                    ) : (
                      <p className="text-xs text-white/20">No active escalations</p>
                    )}
                    <div className="pt-2 border-t border-white/5">
                      <span className="text-[10px] text-white/20">
                        Total session escalations: {autoModeSession?.aggregate?.totalEscalations ?? (usageData?.escalations ?? 0)}
                      </span>
                    </div>
                  </div>
                )}

                {selectedSatellite === 'Vitals' && (
                  <div className="space-y-3">
                    <div className="grid grid-cols-3 gap-3">
                      <div className="text-center">
                        <span className="text-xl font-bold">{autoModeSession?.aggregate?.totalStepsExecuted ?? (usageData?.agentDispatches ?? 0)}</span>
                        <span className="block text-[9px] text-white/20">steps executed</span>
                      </div>
                      <div className="text-center">
                        <span className="text-xl font-bold">{usageData?.totalEvents ?? 0}</span>
                        <span className="block text-[9px] text-white/20">total events</span>
                      </div>
                      <div className="text-center">
                        <span className="text-xl font-bold">{autoModeSession?.aggregate?.totalGateRetries ?? 0}</span>
                        <span className="block text-[9px] text-white/20">retries</span>
                      </div>
                    </div>
                  </div>
                )}
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {/* EPIC Run Summary — queue + completed + failed */}
        {(running.length > 0 || queued.length > 0 || completed.length > 0 || failed.length > 0) && (
          <div className="mt-8 w-full max-w-4xl">
            <div className="glass rounded-2xl p-4 space-y-1">
              <div className="flex items-center gap-2 mb-3">
                <Bot size={14} className="text-state-executing" />
                <span className="text-[10px] uppercase tracking-[0.2em] text-white/30 font-bold">
                  EPIC Runs
                </span>
                {epicsTotal > 0 && (
                  <span className="text-[10px] font-mono text-white/20 ml-auto">
                    {epicsCompleted}/{epicsTotal} completed
                  </span>
                )}
              </div>

              {/* Running EPICs */}
              {running.map((e) => (
                <EpicRow
                  key={e.epicId}
                  entry={e}
                  now={now}
                  meta={epics.find((m) => m.id === e.epicId)}
                  stepInfo={
                    e.epicId === displayEpic && currentStepsTotal > 0
                      ? `Step ${currentStepsDone}/${currentStepsTotal}`
                      : undefined
                  }
                />
              ))}

              {/* Queued EPICs — session-queued ones show as "Waiting Room" */}
              {queued.map((e) => (
                <EpicRow
                  key={e.epicId}
                  entry={e}
                  now={now}
                  meta={epics.find((m) => m.id === e.epicId)}
                  onRun={handleRunEpic}
                  runLoading={runLoading === e.epicId}
                  waiting={sessionQueuedIds.has(e.epicId)}
                />
              ))}

              {/* Completed EPICs (last 5, most recent first) */}
              {completed.slice(-5).reverse().map((e) => (
                <EpicRow
                  key={e.epicId}
                  entry={e}
                  now={now}
                  meta={epics.find((m) => m.id === e.epicId)}
                  onClick={() => handleOpenSummary(e)}
                />
              ))}

              {/* Failed EPICs */}
              {failed.map((e) => (
                <EpicRow
                  key={e.epicId}
                  entry={e}
                  now={now}
                  meta={epics.find((m) => m.id === e.epicId)}
                  onClick={() => handleOpenSummary(e)}
                />
              ))}
            </div>
          </div>
        )}
      </div>

      {/* EPIC Summary Slide-Over */}
      <AnimatePresence>
        {summaryEpic && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-50 flex justify-end bg-black/50 backdrop-blur-sm"
            onClick={() => { setSummaryEpic(null); setSummaryData(null); }}
          >
            <motion.div
              initial={{ x: '100%' }}
              animate={{ x: 0 }}
              exit={{ x: '100%' }}
              transition={{ type: 'spring', damping: 30, stiffness: 300 }}
              onClick={(e) => e.stopPropagation()}
              className="w-full max-w-lg h-full bg-surface-1 border-l border-white/10 shadow-2xl overflow-y-auto custom-scrollbar"
            >
              <div className="p-6 space-y-6">
                {/* Header */}
                <div className="flex items-start justify-between">
                  <div className="flex-1 mr-4">
                    <h3 className="text-lg font-bold leading-tight">
                      {epics.find((m) => m.id === summaryEpic.epicId)?.title ?? summaryEpic.epicId}
                    </h3>
                    <p className="text-xs text-white/40 mt-1 font-mono">{summaryEpic.epicId}</p>
                  </div>
                  <button
                    onClick={() => { setSummaryEpic(null); setSummaryData(null); }}
                    className="p-1.5 hover:bg-white/10 rounded-lg text-white/40 hover:text-white transition-colors shrink-0"
                  >
                    <X size={18} />
                  </button>
                </div>

                {/* Status + Duration */}
                <div className="flex items-center gap-3">
                  {(() => {
                    const cfg = statusConfig[summaryEpic.status] ?? statusConfig.queued;
                    const SIcon = cfg.icon;
                    return (
                      <span className={cn('flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-widest px-2.5 py-1 rounded-lg', cfg.color)}>
                        <SIcon size={12} />
                        {cfg.label}
                      </span>
                    );
                  })()}
                  {summaryEpic.startedAt && summaryEpic.completedAt && (
                    <span className="text-xs font-mono text-white/30">
                      {formatDuration(Math.floor((new Date(summaryEpic.completedAt).getTime() - new Date(summaryEpic.startedAt).getTime()) / 1000))}
                    </span>
                  )}
                </div>

                {summaryLoading ? (
                  <div className="flex flex-col items-center gap-3 py-12">
                    <Loader2 size={24} className="animate-spin text-white/30" />
                    <span className="text-xs text-white/20">Loading evidence...</span>
                  </div>
                ) : summaryData ? (
                  <>
                    {/* Plan Steps */}
                    {summaryData.plan && (
                      <div>
                        <label className="text-[10px] font-bold uppercase tracking-widest text-white/40 block mb-3">Plan Steps</label>
                        <div className="space-y-1">
                          {(typeof summaryData.plan === 'object' && summaryData.plan.steps
                            ? summaryData.plan.steps
                            : []
                          ).map((step: any, i: number) => {
                            const prog = summaryData.progress?.steps?.[step.id];
                            const isDone = prog?.status === 'done';
                            const isFailed = prog?.status === 'failed';
                            const RoleIcon = ROLE_ICONS[step.role] ?? FileText;
                            return (
                              <div key={step.id || i} className="flex items-center gap-2 py-1.5 border-b border-white/5 last:border-0">
                                <RoleIcon size={12} className="text-white/30" />
                                <div className="flex-1 min-w-0">
                                  <span className="text-xs text-white/60 line-clamp-1">{step.objective ?? step.id}</span>
                                  <span className="text-[9px] text-white/20 block">{step.role}</span>
                                </div>
                                {isDone && <CheckCircle2 size={12} className="text-state-done shrink-0" />}
                                {isFailed && <XCircle size={12} className="text-state-error shrink-0" />}
                                {!isDone && !isFailed && <div className="w-3 h-3 rounded-full bg-white/5 shrink-0" />}
                              </div>
                            );
                          })}
                        </div>
                      </div>
                    )}

                    {/* Gates Report */}
                    {summaryData.gates && (
                      <div>
                        <label className="text-[10px] font-bold uppercase tracking-widest text-white/40 block mb-3">Gates Report</label>
                        <div className="glass rounded-xl p-3">
                          {typeof summaryData.gates === 'object' ? (
                            <div className="grid grid-cols-3 gap-3 text-center">
                              <div>
                                <span className="text-lg font-bold text-state-done">{summaryData.gates.passed ?? 0}</span>
                                <span className="block text-[9px] text-white/20">passed</span>
                              </div>
                              <div>
                                <span className="text-lg font-bold text-state-error">{summaryData.gates.failed ?? 0}</span>
                                <span className="block text-[9px] text-white/20">failed</span>
                              </div>
                              <div>
                                <span className="text-lg font-bold text-amber-400">{summaryData.gates.retries ?? 0}</span>
                                <span className="block text-[9px] text-white/20">retries</span>
                              </div>
                            </div>
                          ) : (
                            <pre className="text-[10px] text-white/40 whitespace-pre-wrap max-h-40 overflow-y-auto">{JSON.stringify(summaryData.gates, null, 2)}</pre>
                          )}
                        </div>
                      </div>
                    )}

                    {/* Final Report */}
                    {summaryData.report && (
                      <div>
                        <label className="text-[10px] font-bold uppercase tracking-widest text-white/40 block mb-3">Final Report</label>
                        <div className="glass rounded-xl p-4 prose prose-invert prose-xs max-w-none">
                          <pre className="text-[11px] text-white/60 whitespace-pre-wrap leading-relaxed font-mono max-h-[60vh] overflow-y-auto custom-scrollbar">
                            {typeof summaryData.report === 'string' ? summaryData.report : JSON.stringify(summaryData.report, null, 2)}
                          </pre>
                        </div>
                      </div>
                    )}

                    {!summaryData.plan && !summaryData.gates && !summaryData.report && (
                      <div className="flex flex-col items-center gap-2 py-8 text-white/20">
                        <FileText size={24} />
                        <span className="text-xs">No evidence files found for this run</span>
                      </div>
                    )}
                  </>
                ) : (
                  <div className="flex flex-col items-center gap-2 py-8 text-white/20">
                    <FileText size={24} />
                    <span className="text-xs">No evidence data available</span>
                  </div>
                )}
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
};

// ---------------------------------------------------------------------------
// Role icon mapping for plan steps
// ---------------------------------------------------------------------------

const ROLE_ICONS: Record<string, React.ComponentType<{ size: number; className?: string }>> = {
  architect: User,
  backend: Database,
  frontend: Layout,
  qa: CheckCircle2,
  security: ShieldAlert,
  docs: FileText,
  'docs-writer': FileText,
  'docs-reviewer': FileText,
  domain: Layers,
  observability: Activity,
  release: Rocket,
};

// ---------------------------------------------------------------------------
// EPIC Row
// ---------------------------------------------------------------------------

/** Turn an epicId like "E-005-1_4-gui-foundation" into "Gui Foundation (E-005 1/4)" */
function formatEpicId(id: string): string {
  // Pattern with part number AND description: E-NNN-X_Y-some-description
  const m = id.match(/^(E-\d+)-(\d+)_(\d+)-([a-zA-Z].+)$/i);
  if (m) {
    const desc = m[4].replace(/-/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
    return `${desc} (${m[1]} ${m[2]}/${m[3]})`;
  }
  // Pattern with description only (no part number): E-NNN-some-description
  const m2 = id.match(/^(E-\d+)-([a-zA-Z].+)$/i);
  if (m2) {
    const desc = m2[2].replace(/-/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
    return `${desc} (${m2[1]})`;
  }
  // No description (e.g. E-020-1_2) — just return as-is
  return id;
}

interface EpicRowProps {
  entry: QueueScheduleEntry;
  now: number;
  meta?: EpicMetadata;
  stepInfo?: string;
  onRun?: (epicId: string) => void;
  runLoading?: boolean;
  onClick?: () => void;
  /** True when the EPIC is in an active FIRST AID session queue (waiting room). */
  waiting?: boolean;
}

const statusConfig: Record<
  string,
  { icon: typeof CheckCircle2; color: string; label: string }
> = {
  running: { icon: Zap, color: 'text-state-executing', label: 'Running' },
  queued: { icon: Pause, color: 'text-white/30', label: 'Queued' },
  waiting: { icon: Clock, color: 'text-amber-300', label: 'Waiting Room' },
  completed: { icon: CheckCircle2, color: 'text-state-done', label: 'Done' },
  failed: { icon: XCircle, color: 'text-state-error', label: 'Failed' },
  paused: { icon: Pause, color: 'text-amber-400', label: 'Paused' },
};

const priorityColors: Record<string, string> = {
  critical: 'text-red-400',
  high: 'text-amber-400',
  medium: 'text-white/40',
  low: 'text-white/20',
};

const EpicRow: React.FC<EpicRowProps> = ({ entry, now, meta, stepInfo, onRun, runLoading, onClick, waiting }) => {
  const effectiveStatus = waiting ? 'waiting' : entry.status;
  const cfg = statusConfig[effectiveStatus] ?? statusConfig.queued;
  const Icon = cfg.icon;
  const title = meta?.title ?? formatEpicId(entry.epicId);
  const isClickable = onClick && (entry.status === 'completed' || entry.status === 'failed');

  const durationText = useMemo(() => {
    if (entry.completedAt && entry.startedAt) {
      const sec = Math.floor(
        (new Date(entry.completedAt).getTime() - new Date(entry.startedAt).getTime()) / 1000,
      );
      return formatDuration(sec);
    }
    if (entry.startedAt) {
      const sec = Math.max(0, Math.floor((now - new Date(entry.startedAt).getTime()) / 1000));
      return formatDuration(sec);
    }
    return null;
  }, [entry.startedAt, entry.completedAt, now]);

  return (
    <div
      className={cn(
        'flex items-center gap-3 py-1.5 group',
        isClickable && 'cursor-pointer hover:bg-white/5 -mx-2 px-2 rounded-lg transition-colors',
      )}
      onClick={isClickable ? onClick : undefined}
    >
      <Icon
        size={14}
        className={cn(
          cfg.color,
          entry.status === 'running' && 'animate-pulse',
        )}
      />
      <div className="flex-1 min-w-0">
        <div className="flex items-start gap-2">
          <p className={cn(
            'text-xs text-white/60 group-hover:text-white/80 transition-colors flex-1 min-w-0',
            isClickable && 'group-hover:text-state-executing',
          )}>
            {title}
          </p>
          <span className={cn('text-[9px] font-mono shrink-0 mt-0.5', priorityColors[entry.priority])}>
            {entry.priority}
          </span>
        </div>
        <div className="flex items-center gap-2 text-[10px] text-white/20">
          <span>{cfg.label}</span>
          {stepInfo && (
            <>
              <ChevronRight size={8} className="text-white/10" />
              <span className="text-state-executing">{stepInfo}</span>
            </>
          )}
          {durationText && (
            <>
              <span className="text-white/10">&middot;</span>
              <span>{durationText}</span>
            </>
          )}
          {isClickable && (
            <>
              <span className="text-white/10">&middot;</span>
              <span className="text-white/15 group-hover:text-white/30">view summary</span>
            </>
          )}
        </div>
      </div>
      {/* Run button for queued EPICs — hidden for session-queued (waiting) EPICs */}
      {entry.status === 'queued' && !waiting && onRun && (
        <button
          onClick={(e) => { e.stopPropagation(); onRun(entry.epicId); }}
          disabled={!!runLoading}
          className="flex items-center gap-1 px-2 py-1 bg-state-executing/10 text-state-executing border border-state-executing/20 rounded-lg text-[10px] font-bold hover:bg-state-executing/20 transition-colors disabled:opacity-40"
        >
          {runLoading ? (
            <Loader2 size={10} className="animate-spin" />
          ) : (
            <Rocket size={10} />
          )}
          Run
        </button>
      )}
      {entry.status === 'running' && (
        <svg viewBox="0 0 60 16" className="w-16 h-4 shrink-0">
          <line x1="0" y1="8" x2="60" y2="8" stroke="currentColor" strokeWidth="0.5" className="text-white/10" />
          <motion.polyline
            points="0,8 8,8 12,8 15,2 18,14 21,5 24,11 27,8 35,8 39,8 42,3 45,13 48,6 51,10 54,8 60,8"
            fill="none"
            stroke="var(--color-state-executing)"
            strokeWidth="1.5"
            strokeLinecap="round"
            strokeLinejoin="round"
            initial={{ pathLength: 0, opacity: 0.4 }}
            animate={{ pathLength: [0, 1], opacity: [0.4, 1, 0.4] }}
            transition={{ duration: 1.8, repeat: Infinity, ease: 'easeInOut' }}
          />
        </svg>
      )}
    </div>
  );
};

// ---------------------------------------------------------------------------
// Satellite Cards — alternating current / total
// ---------------------------------------------------------------------------

interface SatelliteMetric {
  value: string | number;
  sub?: string;
}

interface SatelliteCardProps {
  icon: any;
  label: string;
  color: string;
  pulse?: boolean;
  showTotal: boolean;
  current: SatelliteMetric;
  total: SatelliteMetric;
  selected?: boolean;
  onClick?: () => void;
}

const SatelliteCard: React.FC<SatelliteCardProps> = ({
  icon: Icon,
  label,
  color,
  pulse,
  showTotal,
  current,
  total,
  selected,
  onClick,
}) => {
  return (
    <motion.div
      whileHover={{ y: -4, backgroundColor: 'rgba(255,255,255,0.08)' }}
      onClick={onClick}
      className={cn(
        'glass p-5 rounded-2xl flex flex-col items-center gap-1 transition-colors group cursor-pointer relative overflow-hidden min-w-0',
        pulse &&
          'ring-1 ring-offset-2 ring-offset-bg-base ring-state-pm-approval/50 animate-pulse-subtle',
        selected && 'ring-1 ring-white/20',
      )}
    >
      <Icon size={18} style={{ color }} className="mb-1" />
      <div className="flex items-center gap-1.5">
        <span className="text-[10px] uppercase tracking-widest text-white/40 font-bold">
          {label}
        </span>
        <span className={cn(
          'text-[8px] uppercase tracking-wider font-bold px-1 rounded w-8 text-center',
          showTotal ? 'text-white/20 bg-white/5' : 'text-white/30',
        )}>
          {showTotal ? 'total' : 'now'}
        </span>
      </div>
      {/* Both values always rendered, swap visibility via opacity — no DOM changes = no layout shift */}
      <div className="relative h-7 w-full">
        <span className={cn(
          'absolute inset-0 flex items-center justify-center text-xl font-bold tracking-tight transition-opacity duration-300',
          showTotal ? 'opacity-0' : 'opacity-100',
        )}>
          {current.value}
        </span>
        <span className={cn(
          'absolute inset-0 flex items-center justify-center text-xl font-bold tracking-tight transition-opacity duration-300',
          showTotal ? 'opacity-100' : 'opacity-0',
        )}>
          {total.value}
        </span>
      </div>
      <div className="relative h-4 w-full">
        <span className={cn(
          'absolute inset-0 flex items-center justify-center text-[9px] text-white/20 font-mono transition-opacity duration-300',
          showTotal ? 'opacity-0' : 'opacity-100',
        )}>
          {current.sub ?? '\u00A0'}
        </span>
        <span className={cn(
          'absolute inset-0 flex items-center justify-center text-[9px] text-white/20 font-mono transition-opacity duration-300',
          showTotal ? 'opacity-100' : 'opacity-0',
        )}>
          {total.sub ?? '\u00A0'}
        </span>
      </div>
    </motion.div>
  );
};

const SatelliteCardSkeleton: React.FC = () => (
  <div className="glass p-5 rounded-2xl flex flex-col items-center gap-2 min-h-[130px] justify-center">
    <div className="h-5 w-5 bg-white/5 rounded animate-pulse mb-1" />
    <div className="h-3 w-16 bg-white/5 rounded animate-pulse" />
    <div className="h-6 w-10 bg-white/5 rounded animate-pulse" />
  </div>
);
