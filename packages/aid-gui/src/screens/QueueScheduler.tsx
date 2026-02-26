import React, { useState, useEffect, useCallback } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { Clock, GripVertical, AlertCircle, Play, Settings, Zap, TrendingUp, AlertTriangle, Rocket, X, CheckCircle, Loader2 } from 'lucide-react';
import { ResponsiveContainer, AreaChart, Area } from 'recharts';
import { cn } from '../lib/utils';
import { useStore } from '../store';
import { createApiClient } from '../api/client';
import type { ApiError, QueueScheduleEntry } from '../types/api';
import {
  DndContext,
  closestCenter,
  PointerSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
} from '@dnd-kit/core';
import { SortableContext, useSortable, verticalListSortingStrategy } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';

const client = createApiClient('default');

// ---------------------------------------------------------------------------
// Priority mapping for drag-to-reorder persistence
// ---------------------------------------------------------------------------

const PRIORITY_ORDER: QueueScheduleEntry['priority'][] = ['critical', 'high', 'medium', 'low'];

function priorityForIndex(index: number, total: number): QueueScheduleEntry['priority'] {
  if (total <= 1) return 'high';
  const ratio = index / (total - 1);
  if (ratio < 0.25) return 'critical';
  if (ratio < 0.5) return 'high';
  if (ratio < 0.75) return 'medium';
  return 'low';
}

// ---------------------------------------------------------------------------
// Status color helpers
// ---------------------------------------------------------------------------

function statusBadgeClasses(status: QueueScheduleEntry['status']): string {
  switch (status) {
    case 'running':
      return 'bg-state-executing/20 text-state-executing';
    case 'completed':
      return 'bg-state-done/20 text-state-done';
    case 'failed':
      return 'bg-state-error/20 text-state-error';
    case 'paused':
      return 'bg-state-pm-approval/20 text-state-pm-approval';
    case 'queued':
    default:
      return 'bg-white/10 text-white/40';
  }
}

function statusLabel(status: QueueScheduleEntry['status']): string {
  switch (status) {
    case 'running': return 'Running';
    case 'queued': return 'Queued';
    case 'completed': return 'Completed';
    case 'failed': return 'Failed';
    case 'paused': return 'Paused';
    default: return status;
  }
}

function priorityLabel(priority: QueueScheduleEntry['priority']): string {
  return priority.charAt(0).toUpperCase() + priority.slice(1);
}

// ---------------------------------------------------------------------------
// Sortable queue item component
// ---------------------------------------------------------------------------

interface SortableQueueItemProps {
  entry: QueueScheduleEntry;
  index: number;
  isFirst: boolean;
}

const SortableQueueItem: React.FC<SortableQueueItemProps> = ({ entry, index, isFirst }) => {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: entry.epicId, data: { type: 'queue-entry', entry } });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.3 : 1,
  };

  const isNext = isFirst && entry.status === 'queued';
  const isRunning = entry.status === 'running';
  const addedDate = new Date(entry.addedAt);
  const timeAgo = formatTimeAgo(addedDate);

  return (
    <motion.div
      ref={setNodeRef}
      style={style}
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: index * 0.1 }}
      className={cn(
        "flex items-center gap-4 p-4 rounded-xl border transition-all cursor-grab active:cursor-grabbing group",
        isNext || isRunning
          ? "bg-white/10 border-white/20 shadow-lg"
          : "bg-white/5 border-white/5 hover:bg-white/10 hover:border-white/10"
      )}
      {...attributes}
      {...listeners}
    >
      <div className="text-white/20 group-hover:text-white/40 transition-colors">
        <GripVertical size={20} />
      </div>

      <div className="flex-1 flex items-center justify-between">
        <div className="flex items-center gap-4">
          <div className={cn(
            "px-2 py-1 rounded text-[10px] font-bold uppercase tracking-widest",
            statusBadgeClasses(entry.status)
          )}>
            {entry.epicId}
          </div>
          <div>
            <h4 className="font-bold text-sm">{entry.epicId}</h4>
            <div className="flex items-center gap-3 mt-0.5">
              {isNext && (
                <div className="text-[10px] text-state-executing flex items-center gap-1">
                  <AlertCircle size={10} /> Next to execute
                </div>
              )}
              {isRunning && (
                <div className="text-[10px] text-state-executing flex items-center gap-1">
                  <Play size={10} /> Running
                </div>
              )}
              <span className="text-[10px] text-white/30">
                {priorityLabel(entry.priority)}
              </span>
            </div>
          </div>
        </div>

        <div className="flex items-center gap-6">
          <div className="flex items-center gap-2 text-white/40">
            <Clock size={14} />
            <span className="text-xs font-mono">{timeAgo}</span>
          </div>
          <div className={cn(
            "px-2 py-0.5 rounded text-[9px] font-bold uppercase tracking-widest",
            statusBadgeClasses(entry.status)
          )}>
            {statusLabel(entry.status)}
          </div>
          <button className="opacity-0 group-hover:opacity-100 p-2 hover:bg-white/10 rounded-lg transition-all text-white/40 hover:text-white">
            Edit
          </button>
        </div>
      </div>
    </motion.div>
  );
};

// ---------------------------------------------------------------------------
// Time formatting helper
// ---------------------------------------------------------------------------

function formatTimeAgo(date: Date): string {
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMin = Math.floor(diffMs / 60000);
  if (diffMin < 1) return 'just now';
  if (diffMin < 60) return `${diffMin}m ago`;
  const diffH = Math.floor(diffMin / 60);
  if (diffH < 24) return `${diffH}h ${diffMin % 60}m ago`;
  const diffD = Math.floor(diffH / 24);
  return `${diffD}d ago`;
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

export const QueueScheduler: React.FC = () => {
  // Store state
  const queueEntries = useStore((s) => s.queueEntries) ?? [];
  const scheduleConfig = useStore((s) => s.scheduleConfig);
  const scheduleStatus = useStore((s) => s.scheduleStatus);
  const usageData = useStore((s) => s.usageData);
  const queueDetailLoading = useStore((s) => s.queueDetailLoading);

  // Store actions
  const setQueueEntries = useStore((s) => s.setQueueEntries);
  const setScheduleConfig = useStore((s) => s.setScheduleConfig);
  const setScheduleStatus = useStore((s) => s.setScheduleStatus);
  const setUsageData = useStore((s) => s.setUsageData);
  const setQueueDetailLoading = useStore((s) => s.setQueueDetailLoading);
  const reorderQueueEntry = useStore((s) => s.reorderQueueEntry);

  // DnD sensors
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
  );

  // ---------------------------------------------------------------------------
  // Data fetching on mount
  // ---------------------------------------------------------------------------

  useEffect(() => {
    let cancelled = false;

    async function fetchData() {
      setQueueDetailLoading(true);

      const [queueResult, scheduleResult, usageResult, statusResult] = await Promise.all([
        client.getQueue(),
        client.getQueueSchedule(),
        client.getUsage(),
        client.getQueueScheduleStatus(),
      ]);

      if (cancelled) return;

      if (queueResult.ok) {
        setQueueEntries(queueResult.data.queue);
      } else {
        console.error('Failed to fetch queue:', (queueResult as ApiError).error.message);
      }

      if (scheduleResult.ok) {
        setScheduleConfig(scheduleResult.data);
      } else {
        console.error('Failed to fetch schedule config:', (scheduleResult as ApiError).error.message);
      }

      if (usageResult.ok) {
        setUsageData(usageResult.data);
      } else {
        console.error('Failed to fetch usage data:', (usageResult as ApiError).error.message);
      }

      if (statusResult.ok) {
        setScheduleStatus(statusResult.data);
      } else {
        console.error('Failed to fetch schedule status:', (statusResult as ApiError).error.message);
      }

      setQueueDetailLoading(false);
    }

    fetchData();
    return () => { cancelled = true; };
  }, [setQueueEntries, setScheduleConfig, setUsageData, setScheduleStatus, setQueueDetailLoading]);

  // ---------------------------------------------------------------------------
  // Drag-to-reorder handler
  // ---------------------------------------------------------------------------

  const handleDragEnd = useCallback(async (event: DragEndEvent) => {
    const { active, over } = event;
    if (!over || active.id === over.id) return;

    const oldIndex = queueEntries.findIndex((e) => e.epicId === active.id);
    const newIndex = queueEntries.findIndex((e) => e.epicId === over.id);
    if (oldIndex === -1 || newIndex === -1) return;

    // Optimistic local reorder
    reorderQueueEntry(active.id as string, newIndex);

    // Persist to server
    const newPriority = priorityForIndex(newIndex, queueEntries.length);
    const result = await client.updateQueueEntry(active.id as string, { priority: newPriority });
    if (!result.ok) {
      console.error('Failed to persist reorder:', (result as ApiError).error.message);
    }
  }, [queueEntries, reorderQueueEntry]);

  // ---------------------------------------------------------------------------
  // Settings change handlers
  // ---------------------------------------------------------------------------

  const handleCooldownChange = useCallback(async (e: React.ChangeEvent<HTMLSelectElement>) => {
    const cooldownSeconds = parseInt(e.target.value, 10) * 60;
    const result = await client.updateQueueSchedule({ cooldownSeconds });
    if (result.ok) {
      setScheduleConfig(result.data);
    } else {
      console.error('Failed to update cooldown:', (result as ApiError).error.message);
    }
  }, [setScheduleConfig]);

  const handleMaxConcurrentChange = useCallback(async (e: React.ChangeEvent<HTMLSelectElement>) => {
    const maxConcurrent = parseInt(e.target.value, 10);
    const result = await client.updateQueueSchedule({ maxConcurrent });
    if (result.ok) {
      setScheduleConfig(result.data);
    } else {
      console.error('Failed to update max concurrent:', (result as ApiError).error.message);
    }
  }, [setScheduleConfig]);

  const handleAutoPauseToggle = useCallback(async (e: React.ChangeEvent<HTMLInputElement>) => {
    const autoPauseAtCcLimit = e.target.checked;
    const result = await client.updateQueueSchedule({ autoPauseAtCcLimit });
    if (result.ok) {
      setScheduleConfig(result.data);
    } else {
      console.error('Failed to update auto-pause:', (result as ApiError).error.message);
    }
  }, [setScheduleConfig]);

  // ---------------------------------------------------------------------------
  // Launch queue state & handlers
  // ---------------------------------------------------------------------------

  const [showLaunchConfirm, setShowLaunchConfirm] = useState(false);
  const [launchLoading, setLaunchLoading] = useState(false);
  const [launchFeedback, setLaunchFeedback] = useState<{
    type: 'success' | 'error';
    message: string;
  } | null>(null);

  const isQueueEmpty = queueEntries.filter((e) => e.status === 'queued').length === 0;
  const hasRunningEntry = queueEntries.some((e) => e.status === 'running');
  const isLaunchDisabled = isQueueEmpty || hasRunningEntry || launchLoading;

  const handleLaunchQueue = useCallback(() => {
    setLaunchFeedback(null);
    setShowLaunchConfirm(true);
  }, []);

  const handleLaunchConfirm = useCallback(async () => {
    setLaunchLoading(true);
    setLaunchFeedback(null);

    const result = await client.launchQueue();

    setLaunchLoading(false);
    setShowLaunchConfirm(false);

    if (result.ok) {
      const epicLabel = result.data.epicId ? ` (${result.data.epicId})` : '';
      setLaunchFeedback({
        type: 'success',
        message: `Queue launched successfully${epicLabel}`,
      });

      // Refresh queue data after successful launch
      const refreshResult = await client.getQueue();
      if (refreshResult.ok) {
        setQueueEntries(refreshResult.data.queue);
      }
      const statusRefresh = await client.getQueueScheduleStatus();
      if (statusRefresh.ok) {
        setScheduleStatus(statusRefresh.data);
      }

      // Auto-dismiss success feedback after 4 seconds
      setTimeout(() => setLaunchFeedback(null), 4000);
    } else {
      setLaunchFeedback({
        type: 'error',
        message: (result as ApiError).error.message ?? 'Failed to launch queue',
      });
    }
  }, [setQueueEntries, setScheduleStatus]);

  const handleLaunchCancel = useCallback(() => {
    setShowLaunchConfirm(false);
  }, []);

  // ---------------------------------------------------------------------------
  // Computed values
  // ---------------------------------------------------------------------------

  // Estimated queue time based on number of queued entries
  const queuedCount = queueEntries.filter((e) => e.status === 'queued').length;
  const runningEntry = queueEntries.find((e) => e.status === 'running');
  const cooldownMinutes = scheduleConfig ? Math.round(scheduleConfig.cooldownSeconds / 60) : 30;

  // Estimated total time (rough heuristic: 1h per entry + cooldown gaps)
  const estMinutes = queuedCount * 60 + (queuedCount > 0 ? (queuedCount - 1) * cooldownMinutes : 0);
  const estHours = Math.floor(estMinutes / 60);
  const estMins = estMinutes % 60;
  const estTimeStr = estHours > 0 ? `${estHours}h ${estMins}m` : `${estMins}m`;

  // CC Usage
  const totalEvents = usageData?.totalEvents ?? 0;
  const agentDispatches = usageData?.agentDispatches ?? 0;
  const gateEvaluations = usageData?.gateEvaluations ?? 0;

  // CC threshold for progress bar
  const ccThreshold = scheduleConfig?.ccLimitThreshold ?? 100000;
  const ccPercent = ccThreshold > 0 ? Math.min(100, Math.round((totalEvents / ccThreshold) * 100)) : 0;
  const ccWarning = ccPercent >= 70;

  // Usage trend from perEpic data
  const usageTrendData = (usageData?.perEpic ?? []).map((entry, idx) => ({
    day: String(idx + 1),
    tokens: entry.events,
  }));

  // Average cost per EPIC
  const perEpicEntries = usageData?.perEpic ?? [];
  const avgCostPerEpic = perEpicEntries.length > 0
    ? Math.round(totalEvents / perEpicEntries.length)
    : 0;

  // Estimated remaining EPICs before threshold
  const remainingBudget = Math.max(0, ccThreshold - totalEvents);
  const estRemainingEpics = avgCostPerEpic > 0 ? Math.floor(remainingBudget / avgCostPerEpic) : 0;

  // Cooldown value for the dropdown (in minutes)
  const cooldownDropdownValue = String(cooldownMinutes);

  // Max concurrent value
  const maxConcurrentValue = String(scheduleConfig?.maxConcurrent ?? 1);

  // Auto-pause checked
  const autoPauseChecked = scheduleConfig?.autoPauseAtCcLimit ?? true;

  // ---------------------------------------------------------------------------
  // Timeline blocks computation from real queue entries
  // ---------------------------------------------------------------------------

  const timelineEntries = queueEntries.filter(
    (e) => e.status === 'running' || e.status === 'queued'
  );
  const totalTimelineSlots = timelineEntries.length * 2 + (timelineEntries.length > 0 ? timelineEntries.length - 1 : 0);
  const baseBlockWidth = timelineEntries.length > 0 ? Math.max(10, Math.floor(80 / timelineEntries.length)) : 0;
  const gapWidth = timelineEntries.length > 1 ? Math.max(3, Math.floor(10 / (timelineEntries.length - 1))) : 0;

  // ---------------------------------------------------------------------------
  // Skeleton loading state
  // ---------------------------------------------------------------------------

  if (queueDetailLoading && queueEntries.length === 0) {
    return (
      <div className="h-full flex flex-col p-8 overflow-y-auto custom-scrollbar">
        <div className="flex items-center justify-between mb-8">
          <div>
            <div className="h-7 w-48 bg-white/10 rounded animate-pulse mb-2" />
            <div className="h-4 w-72 bg-white/5 rounded animate-pulse" />
          </div>
          <div className="h-12 w-40 bg-white/5 rounded-xl animate-pulse" />
        </div>

        <div className="flex-1 flex flex-col gap-6">
          {/* Timeline skeleton */}
          <div className="glass p-6 rounded-[2rem] border border-white/5 relative overflow-hidden flex-shrink-0">
            <div className="h-3 w-32 bg-white/10 rounded animate-pulse mb-6" />
            <div className="h-32 w-full bg-white/5 rounded-xl animate-pulse" />
          </div>

          {/* Bottom section skeleton */}
          <div className="flex-1 flex gap-6 min-h-0">
            <div className="flex-[2] glass p-6 rounded-[2rem] border border-white/5 flex flex-col">
              <div className="h-3 w-20 bg-white/10 rounded animate-pulse mb-6" />
              <div className="flex-1 space-y-3">
                {[0, 1, 2].map((i) => (
                  <div key={i} className="h-16 bg-white/5 rounded-xl animate-pulse" />
                ))}
              </div>
            </div>
            <div className="flex-1 flex flex-col gap-6">
              <div className="glass p-6 rounded-[2rem] border border-white/5">
                <div className="h-3 w-28 bg-white/10 rounded animate-pulse mb-6" />
                <div className="space-y-4">
                  {[0, 1, 2, 3].map((i) => (
                    <div key={i} className="h-8 bg-white/5 rounded-lg animate-pulse" />
                  ))}
                </div>
              </div>
              <div className="glass p-6 rounded-[2rem] border border-white/5 flex-1">
                <div className="h-3 w-20 bg-white/10 rounded animate-pulse mb-4" />
                <div className="h-10 w-24 bg-white/5 rounded animate-pulse mb-4" />
                <div className="h-2 w-full bg-white/5 rounded-full animate-pulse" />
              </div>
            </div>
          </div>
        </div>
      </div>
    );
  }

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------

  return (
    <div className="h-full flex flex-col p-8 overflow-y-auto custom-scrollbar">
      <div className="flex items-center justify-between mb-8">
        <div>
          <h2 className="text-2xl font-bold tracking-tight">Queue Scheduler</h2>
          <p className="text-sm text-white/40">Manage and sequence upcoming EPICs</p>
        </div>
        <div className="flex items-center gap-4">
          <div className="glass px-4 py-2 rounded-xl flex items-center gap-3">
            <div className="flex flex-col">
              <span className="text-[10px] font-bold uppercase tracking-widest text-white/40">Est. Queue Time</span>
              <span className="text-sm font-mono font-bold">{estTimeStr}</span>
            </div>
          </div>
        </div>
      </div>

      <div className="flex-1 flex flex-col gap-6">
        {/* Timeline View */}
        <div className="glass p-6 rounded-[2rem] border border-white/5 relative overflow-hidden flex-shrink-0">
          <h3 className="text-[10px] font-bold uppercase tracking-widest text-white/40 mb-6">Execution Timeline</h3>

          <div className="relative h-32 w-full">
            {/* Time markers */}
            <div className="absolute top-0 left-0 w-full flex justify-between text-[10px] font-mono text-white/20 px-4">
              <span>Now</span>
              <span>+1h</span>
              <span>+2h</span>
              <span>+3h</span>
              <span>+4h</span>
            </div>

            {/* Timeline track */}
            <div className="absolute top-8 left-4 right-4 h-16 bg-white/5 rounded-xl overflow-hidden flex">
              {timelineEntries.map((entry, idx) => (
                <React.Fragment key={entry.epicId}>
                  {/* Entry block */}
                  <div
                    className={cn(
                      "h-full border-r flex items-center justify-center relative group cursor-pointer",
                      entry.status === 'running'
                        ? "bg-state-executing/20 border-state-executing/50"
                        : entry.status === 'completed'
                          ? "bg-white/5 border-white/10 opacity-50"
                          : "bg-white/10 border-white/20 hover:bg-white/15 transition-colors"
                    )}
                    style={{ width: `${baseBlockWidth}%` }}
                  >
                    {entry.status === 'running' && (
                      <div className="absolute inset-0 bg-state-executing/10 animate-pulse" />
                    )}
                    <span className={cn(
                      "text-xs font-bold z-10",
                      entry.status === 'running' ? "text-state-executing" : "text-white/60"
                    )}>
                      {entry.epicId}
                    </span>

                    {/* Tooltip */}
                    <div className="absolute bottom-full mb-2 opacity-0 group-hover:opacity-100 transition-opacity bg-surface-2 border border-white/10 px-3 py-2 rounded-lg text-xs whitespace-nowrap z-20 pointer-events-none">
                      <div className={cn(
                        "font-bold",
                        entry.status === 'running' ? "text-state-executing" : ""
                      )}>
                        {entry.epicId}
                      </div>
                      <div className="text-white/60">
                        {statusLabel(entry.status)} | {priorityLabel(entry.priority)}
                      </div>
                    </div>
                  </div>

                  {/* Cooldown gap (not after the last entry) */}
                  {idx < timelineEntries.length - 1 && (
                    <div
                      className="h-full bg-transparent border-r border-white/10 flex items-center justify-center relative"
                      style={{ width: `${gapWidth}%` }}
                    >
                      <span className="text-[8px] font-mono text-white/40 rotate-[-90deg] whitespace-nowrap">
                        {cooldownMinutes}m
                      </span>
                    </div>
                  )}
                </React.Fragment>
              ))}

              {/* Empty state if no entries */}
              {timelineEntries.length === 0 && (
                <div className="flex-1 flex items-center justify-center text-xs text-white/20">
                  No entries in queue
                </div>
              )}
            </div>

            {/* "Now" indicator line */}
            {runningEntry && (
              <div className="absolute top-4 bottom-0 left-[24%] w-px bg-state-executing shadow-[0_0_8px_rgba(0,180,216,0.8)] z-10">
                <div className="absolute -top-1 -left-1 w-2 h-2 rounded-full bg-state-executing" />
              </div>
            )}
          </div>
        </div>

        {/* Bottom Section: Queue List & Settings */}
        <div className="flex-1 flex gap-6 min-h-0">
          {/* Queue List */}
          <div className="flex-[2] glass p-6 rounded-[2rem] border border-white/5 flex flex-col">
            <div className="flex items-center justify-between mb-6">
              <h3 className="text-[10px] font-bold uppercase tracking-widest text-white/40">Up Next</h3>
              <button className="text-xs font-medium text-state-executing hover:underline flex items-center gap-1">
                <Play size={12} /> Force Start Next
              </button>
            </div>

            <DndContext
              sensors={sensors}
              collisionDetection={closestCenter}
              onDragEnd={handleDragEnd}
            >
              <SortableContext
                items={queueEntries.map((e) => e.epicId)}
                strategy={verticalListSortingStrategy}
              >
                <div className="flex-1 space-y-3 overflow-y-auto custom-scrollbar pr-2">
                  {queueEntries.length === 0 && !queueDetailLoading && (
                    <div className="flex-1 flex items-center justify-center py-12 text-sm text-white/30">
                      Queue is empty
                    </div>
                  )}
                  {queueEntries.map((entry, index) => (
                    <SortableQueueItem
                      key={entry.epicId}
                      entry={entry}
                      index={index}
                      isFirst={index === 0}
                    />
                  ))}
                </div>
              </SortableContext>
            </DndContext>
          </div>

          {/* Right Column: Settings & CC Usage */}
          <div className="flex-1 flex flex-col gap-6">
            {/* Queue Settings */}
            <div className="glass p-6 rounded-[2rem] border border-white/5">
              <div className="flex items-center gap-2 mb-6">
                <Settings size={16} className="text-white/40" />
                <h3 className="text-[10px] font-bold uppercase tracking-widest text-white/40">Queue Settings</h3>
              </div>

              <div className="space-y-4">
                <div className="flex items-center justify-between">
                  <span className="text-sm text-white/60">Cooldown between EPICs</span>
                  <select
                    className="bg-white/5 border border-white/10 rounded-lg px-3 py-1.5 text-xs focus:outline-none focus:border-white/20"
                    value={cooldownDropdownValue}
                    onChange={handleCooldownChange}
                  >
                    <option value="15">15 min</option>
                    <option value="30">30 min</option>
                    <option value="60">1 hour</option>
                    <option value="120">2 hours</option>
                  </select>
                </div>

                <div className="flex items-center justify-between">
                  <span className="text-sm text-white/60">Max concurrent EPICs</span>
                  <select
                    className="bg-white/5 border border-white/10 rounded-lg px-3 py-1.5 text-xs focus:outline-none focus:border-white/20"
                    value={maxConcurrentValue}
                    onChange={handleMaxConcurrentChange}
                  >
                    <option value="1">1</option>
                    <option value="2">2</option>
                    <option value="3">3</option>
                  </select>
                </div>

                <div className="flex items-center justify-between">
                  <span className="text-sm text-white/60">Auto-pause at CC limit</span>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input
                      type="checkbox"
                      className="sr-only peer"
                      checked={autoPauseChecked}
                      onChange={handleAutoPauseToggle}
                    />
                    <div className="w-9 h-5 bg-white/10 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:bg-state-executing"></div>
                  </label>
                </div>

                <div className="flex items-center justify-between">
                  <span className="text-sm text-white/60">Start time</span>
                  <input
                    type="datetime-local"
                    className="bg-white/5 border border-white/10 rounded-lg px-3 py-1.5 text-xs focus:outline-none focus:border-white/20 text-white/60"
                    defaultValue={scheduleConfig?.delayedStartAt ?? ''}
                  />
                </div>

                <button
                  className={cn(
                    "w-full mt-4 font-bold py-3 rounded-xl transition-all flex items-center justify-center gap-2",
                    isLaunchDisabled
                      ? "bg-white/5 text-white/20 cursor-not-allowed"
                      : "bg-state-executing hover:bg-state-executing/90 text-bg-base shadow-lg shadow-state-executing/20"
                  )}
                  onClick={handleLaunchQueue}
                  disabled={isLaunchDisabled}
                  title={
                    isQueueEmpty
                      ? 'Queue is empty'
                      : hasRunningEntry
                        ? 'An EPIC is already running'
                        : 'Launch the queue'
                  }
                >
                  <Rocket size={16} /> LAUNCH QUEUE
                </button>

                {/* Launch feedback toast */}
                <AnimatePresence>
                  {launchFeedback && (
                    <motion.div
                      initial={{ opacity: 0, y: 8 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0, y: 8 }}
                      className={cn(
                        "mt-3 px-4 py-2.5 rounded-xl text-xs font-medium flex items-center gap-2 border",
                        launchFeedback.type === 'success'
                          ? "bg-state-done/10 border-state-done/20 text-state-done"
                          : "bg-state-error/10 border-state-error/20 text-state-error"
                      )}
                    >
                      {launchFeedback.type === 'success'
                        ? <CheckCircle size={14} />
                        : <AlertCircle size={14} />
                      }
                      {launchFeedback.message}
                      <button
                        onClick={() => setLaunchFeedback(null)}
                        className="ml-auto p-0.5 hover:bg-white/10 rounded transition-colors"
                      >
                        <X size={12} />
                      </button>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            </div>

            {/* CC Usage Detail */}
            <div className="glass p-6 rounded-[2rem] border border-white/5 flex-1 flex flex-col">
              <div className="flex items-center justify-between mb-4">
                <div className="flex items-center gap-2">
                  <Zap size={16} className="text-state-pm-approval" />
                  <h3 className="text-[10px] font-bold uppercase tracking-widest text-white/40">CC Usage</h3>
                </div>
                {ccWarning && (
                  <div className="px-2 py-0.5 rounded bg-state-pm-approval/20 text-state-pm-approval text-[10px] font-bold uppercase tracking-widest flex items-center gap-1">
                    <AlertTriangle size={10} /> Warning
                  </div>
                )}
              </div>

              <div className="mb-6">
                <div className="flex items-end justify-between mb-2">
                  <span className="text-3xl font-bold tracking-tight">
                    {totalEvents >= 1000 ? `${Math.round(totalEvents / 1000)}k` : totalEvents}
                  </span>
                  <span className="text-sm text-white/40 mb-1">
                    / {ccThreshold >= 1000 ? `${Math.round(ccThreshold / 1000)}k` : ccThreshold} events
                  </span>
                </div>
                <div className="h-2 w-full bg-white/5 rounded-full overflow-hidden">
                  <div className="h-full bg-state-pm-approval" style={{ width: `${ccPercent}%` }} />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4 mb-6">
                <div className="bg-white/5 rounded-xl p-3 border border-white/5">
                  <div className="text-[10px] font-bold uppercase tracking-widest text-white/40 mb-1">Agent Dispatches</div>
                  <div className="text-lg font-medium">
                    {agentDispatches >= 1000 ? `${Math.round(agentDispatches / 1000)}k` : agentDispatches}
                  </div>
                </div>
                <div className="bg-white/5 rounded-xl p-3 border border-white/5">
                  <div className="text-[10px] font-bold uppercase tracking-widest text-white/40 mb-1">Gate Evaluations</div>
                  <div className="text-lg font-medium">
                    {gateEvaluations >= 1000 ? `${Math.round(gateEvaluations / 1000)}k` : gateEvaluations}
                  </div>
                </div>
              </div>

              <div className="flex-1 flex flex-col justify-end">
                <div className="flex items-center gap-2 text-white/40 mb-2">
                  <TrendingUp size={12} />
                  <span className="text-[10px] font-bold uppercase tracking-widest">Usage Trend</span>
                </div>
                <div className="h-16 w-full">
                  <ResponsiveContainer width="100%" height="100%">
                    <AreaChart data={usageTrendData.length > 0 ? usageTrendData : [{ day: '1', tokens: 0 }]}>
                      <defs>
                        <linearGradient id="colorTokens" x1="0" y1="0" x2="0" y2="1">
                          <stop offset="5%" stopColor="var(--color-state-pm-approval)" stopOpacity={0.3}/>
                          <stop offset="95%" stopColor="var(--color-state-pm-approval)" stopOpacity={0}/>
                        </linearGradient>
                      </defs>
                      <Area type="monotone" dataKey="tokens" stroke="var(--color-state-pm-approval)" fillOpacity={1} fill="url(#colorTokens)" />
                    </AreaChart>
                  </ResponsiveContainer>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Launch Confirmation Dialog */}
      <AnimatePresence>
        {showLaunchConfirm && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm"
            onClick={handleLaunchCancel}
          >
            <motion.div
              initial={{ scale: 0.95, y: 20 }}
              animate={{ scale: 1, y: 0 }}
              exit={{ scale: 0.95, y: 20 }}
              onClick={(e) => e.stopPropagation()}
              className="glass p-6 rounded-2xl border border-white/10 w-[420px] shadow-2xl"
            >
              <div className="flex items-center justify-between mb-6">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-xl bg-state-executing/20 flex items-center justify-center">
                    <Rocket size={20} className="text-state-executing" />
                  </div>
                  <h3 className="text-lg font-bold">Launch Queue</h3>
                </div>
                <button
                  onClick={handleLaunchCancel}
                  className="p-1 hover:bg-white/10 rounded text-white/40 hover:text-white transition-colors"
                  disabled={launchLoading}
                >
                  <X size={18} />
                </button>
              </div>

              <p className="text-sm text-white/60 mb-2">
                This will start executing the queue sequentially. The first queued EPIC will begin immediately.
              </p>

              <div className="bg-white/5 rounded-xl p-4 border border-white/5 mb-6">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-white/40">Queued EPICs</span>
                  <span className="font-bold font-mono">{queuedCount}</span>
                </div>
                <div className="flex items-center justify-between text-sm mt-2">
                  <span className="text-white/40">Estimated time</span>
                  <span className="font-bold font-mono">{estTimeStr}</span>
                </div>
                <div className="flex items-center justify-between text-sm mt-2">
                  <span className="text-white/40">Cooldown between EPICs</span>
                  <span className="font-bold font-mono">{cooldownMinutes}m</span>
                </div>
              </div>

              <div className="flex items-center gap-3">
                <button
                  onClick={handleLaunchCancel}
                  disabled={launchLoading}
                  className="flex-1 py-2.5 rounded-xl border border-white/10 text-sm font-medium text-white/60 hover:bg-white/5 hover:text-white transition-all disabled:opacity-50"
                >
                  Cancel
                </button>
                <button
                  onClick={handleLaunchConfirm}
                  disabled={launchLoading}
                  className={cn(
                    "flex-1 py-2.5 rounded-xl text-sm font-bold transition-all flex items-center justify-center gap-2",
                    launchLoading
                      ? "bg-state-executing/50 text-bg-base cursor-wait"
                      : "bg-state-executing hover:bg-state-executing/90 text-bg-base shadow-lg shadow-state-executing/20"
                  )}
                >
                  {launchLoading ? (
                    <>
                      <Loader2 size={16} className="animate-spin" />
                      Launching...
                    </>
                  ) : (
                    <>
                      <Rocket size={16} />
                      Confirm Launch
                    </>
                  )}
                </button>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
};
