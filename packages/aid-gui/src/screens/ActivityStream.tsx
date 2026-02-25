import React, { useEffect, useRef, useState, useMemo, useCallback } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { useStore, stateColors } from '../store';
import type { StageLogEntryResponse } from '../types/api';
import { cn } from '../lib/utils';
import { Clock, MessageSquare, Zap, Shield, Gavel, ArrowRight, Filter, WifiOff, Loader2 } from 'lucide-react';

// ---------------------------------------------------------------------------
// Display event type mapped from StageLogEntryResponse
// ---------------------------------------------------------------------------

interface ActivityEvent {
  id: string;
  time: string;
  state: string;
  step?: string;
  message: string;
  action: string;
  result: string;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Format an ISO 8601 timestamp into a short display time.
 * Shows HH:MM:SS for today's entries, or MM-DD HH:MM for older entries.
 */
function formatTimestamp(iso: string): string {
  try {
    const date = new Date(iso);
    if (isNaN(date.getTime())) return iso;
    const now = new Date();
    const isToday =
      date.getFullYear() === now.getFullYear() &&
      date.getMonth() === now.getMonth() &&
      date.getDate() === now.getDate();

    if (isToday) {
      return date.toLocaleTimeString('en-US', {
        hour12: false,
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
      });
    }
    return date.toLocaleString('en-US', {
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });
  } catch {
    return iso;
  }
}

/**
 * Map a StageLogEntryResponse to the display ActivityEvent.
 */
function toActivityEvent(entry: StageLogEntryResponse, index: number): ActivityEvent {
  return {
    id: `${entry.timestamp}-${entry.action}-${index}`,
    time: formatTimestamp(entry.timestamp),
    state: entry.state,
    step: entry.step ?? undefined,
    message: entry.details,
    action: entry.action,
    result: entry.result,
  };
}

/**
 * Pick an icon component for an activity event based on its action.
 */
function getActionIcon(action: string, result: string): React.ReactNode {
  const lower = action.toLowerCase();
  if (lower.includes('dispatch')) return <Zap size={16} />;
  if (lower.includes('gate')) return <Shield size={16} />;
  if (lower.includes('decision') || lower.includes('approval')) return <Gavel size={16} />;
  if (lower.includes('transition') || result === 'pass' || result === 'fail') {
    return <CheckCircleIcon size={16} />;
  }
  return <MessageSquare size={16} />;
}

// ---------------------------------------------------------------------------
// Filter definitions
// ---------------------------------------------------------------------------

type FilterName = 'All' | 'Dispatch' | 'Gate' | 'Decision' | 'Transition';

const FILTERS: FilterName[] = ['All', 'Dispatch', 'Gate', 'Decision', 'Transition'];

function matchesFilter(event: ActivityEvent, filter: FilterName): boolean {
  if (filter === 'All') return true;

  const actionLower = event.action.toLowerCase();
  const stateLower = event.state.toLowerCase();

  switch (filter) {
    case 'Dispatch':
      return actionLower.includes('dispatch');
    case 'Gate':
      return (
        actionLower.includes('gate') ||
        stateLower === 'gates' ||
        stateLower === 'gate_retry' ||
        stateLower === 'gates_retry'
      );
    case 'Decision':
      return (
        actionLower.includes('decision') ||
        actionLower.includes('approval') ||
        stateLower === 'pm_approval'
      );
    case 'Transition':
      return (
        actionLower.includes('transition') ||
        event.result === 'pass' ||
        event.result === 'fail'
      );
    default:
      return true;
  }
}

// ---------------------------------------------------------------------------
// Skeleton loader for the connecting state
// ---------------------------------------------------------------------------

const SkeletonCard: React.FC<{ delay: number }> = ({ delay }) => (
  <motion.div
    initial={{ opacity: 0 }}
    animate={{ opacity: 1 }}
    transition={{ duration: 0.4, delay }}
    className="glass p-5 rounded-2xl border border-white/5"
  >
    <div className="flex items-start justify-between mb-3">
      <div className="flex items-center gap-3">
        <div className="w-20 h-5 rounded-md bg-white/5 animate-pulse" />
        <div className="w-16 h-5 rounded-md bg-white/5 animate-pulse" />
        <div className="w-24 h-4 rounded-md bg-white/5 animate-pulse" />
      </div>
    </div>
    <div className="flex gap-4">
      <div className="w-8 h-8 rounded-lg bg-white/5 animate-pulse" />
      <div className="flex-1 space-y-2">
        <div className="w-3/4 h-4 rounded bg-white/5 animate-pulse" />
        <div className="w-1/2 h-4 rounded bg-white/5 animate-pulse" />
      </div>
    </div>
  </motion.div>
);

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

export const ActivityStream: React.FC = () => {
  const stageLogEntries = useStore((s) => s.stageLogEntries);
  const wsStatus = useStore((s) => s.wsStatus);
  const [activeFilter, setActiveFilter] = useState<FilterName>('All');

  // ---- Auto-scroll refs ----
  const scrollRef = useRef<HTMLDivElement>(null);
  const isAutoScrollRef = useRef(true);

  // ---- Map store entries to display events ----
  const allEvents = useMemo(
    () => stageLogEntries.map(toActivityEvent),
    [stageLogEntries],
  );

  // ---- Apply filter ----
  const filteredEvents = useMemo(
    () => allEvents.filter((ev) => matchesFilter(ev, activeFilter)),
    [allEvents, activeFilter],
  );

  // ---- Scroll handler: detect manual scroll away from bottom ----
  const handleScroll = useCallback(() => {
    const el = scrollRef.current;
    if (!el) return;
    const atBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 50;
    isAutoScrollRef.current = atBottom;
  }, []);

  // ---- Auto-scroll when new entries arrive ----
  useEffect(() => {
    if (isAutoScrollRef.current && scrollRef.current) {
      scrollRef.current.scrollTo({
        top: scrollRef.current.scrollHeight,
        behavior: 'smooth',
      });
    }
  }, [filteredEvents.length]);

  // ---- Derived states ----
  const isConnecting = wsStatus === 'connecting';
  const isDisconnected = wsStatus === 'disconnected';
  const isReconnecting = wsStatus === 'reconnecting';
  const showSkeleton = stageLogEntries.length === 0 && isConnecting;
  const showDisconnected = isDisconnected && stageLogEntries.length === 0;
  const showEmpty = !showSkeleton && !showDisconnected && filteredEvents.length === 0;

  return (
    <div className="h-full flex flex-col p-8">
      {/* ---- Header ---- */}
      <div className="flex items-center justify-between mb-8">
        <div>
          <h2 className="text-2xl font-bold tracking-tight">Activity Stream</h2>
          <p className="text-sm text-white/40">Real-time orchestration events</p>
        </div>
        <div className="flex items-center gap-4">
          {/* Filter tabs */}
          <div className="flex bg-white/5 p-1 rounded-xl border border-white/10">
            {FILTERS.map((filter) => (
              <button
                key={filter}
                onClick={() => setActiveFilter(filter)}
                className={cn(
                  'px-4 py-1.5 rounded-lg text-xs font-medium transition-all',
                  activeFilter === filter
                    ? 'bg-white/10 text-white shadow-sm'
                    : 'text-white/40 hover:text-white hover:bg-white/5',
                )}
              >
                {filter}
              </button>
            ))}
          </div>

          {/* Filter icon button */}
          <button className="p-2 rounded-xl bg-white/5 border border-white/10 text-white/40 hover:text-white transition-colors">
            <Filter size={16} />
          </button>

          {/* Entry count badge */}
          <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-white/5 border border-white/10">
            <span className="text-[10px] font-bold uppercase tracking-widest text-white/60">
              {filteredEvents.length}
            </span>
          </div>

          {/* Connection status indicator */}
          {isDisconnected || isReconnecting ? (
            <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-state-error/10 border border-state-error/20">
              {isReconnecting ? (
                <Loader2 size={10} className="text-state-error animate-spin" />
              ) : (
                <WifiOff size={10} className="text-state-error" />
              )}
              <span className="text-[10px] font-bold uppercase tracking-widest text-state-error">
                {isReconnecting ? 'Reconnecting' : 'Offline'}
              </span>
            </div>
          ) : isConnecting ? (
            <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-yellow-500/10 border border-yellow-500/20">
              <Loader2 size={10} className="text-yellow-400 animate-spin" />
              <span className="text-[10px] font-bold uppercase tracking-widest text-yellow-400">
                Connecting
              </span>
            </div>
          ) : (
            <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-state-done/10 border border-state-done/20">
              <div className="w-1.5 h-1.5 rounded-full bg-state-done" />
              <span className="text-[10px] font-bold uppercase tracking-widest text-state-done">
                Live
              </span>
            </div>
          )}
        </div>
      </div>

      {/* ---- Scrollable event list ---- */}
      <div
        ref={scrollRef}
        onScroll={handleScroll}
        className="flex-1 overflow-y-auto space-y-4 pr-4 custom-scrollbar"
      >
        {/* Loading skeleton */}
        {showSkeleton && (
          <div className="space-y-4">
            {Array.from({ length: 5 }).map((_, i) => (
              <SkeletonCard key={`skeleton-${i}`} delay={i * 0.1} />
            ))}
          </div>
        )}

        {/* Disconnected error state */}
        {showDisconnected && (
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            className="flex flex-col items-center justify-center h-full gap-4 text-center"
          >
            <div className="p-4 rounded-2xl bg-state-error/10 border border-state-error/20">
              <WifiOff size={32} className="text-state-error" />
            </div>
            <div>
              <p className="text-sm font-medium text-white/80">Connection lost</p>
              <p className="text-xs text-white/40 mt-1">
                Unable to receive live events. Check your connection.
              </p>
            </div>
          </motion.div>
        )}

        {/* Empty state (connected but no matching events) */}
        {showEmpty && (
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            className="flex flex-col items-center justify-center h-full gap-4 text-center"
          >
            <div className="p-4 rounded-2xl bg-white/5 border border-white/10">
              <MessageSquare size={32} className="text-white/20" />
            </div>
            <div>
              <p className="text-sm font-medium text-white/80">
                {activeFilter === 'All'
                  ? 'No events yet'
                  : `No ${activeFilter.toLowerCase()} events`}
              </p>
              <p className="text-xs text-white/40 mt-1">
                {activeFilter === 'All'
                  ? 'Events will appear here as the pipeline runs.'
                  : 'Try selecting a different filter.'}
              </p>
            </div>
          </motion.div>
        )}

        {/* Event cards */}
        <AnimatePresence initial={false}>
          {filteredEvents.map((event, index) => (
            <motion.div
              key={event.id}
              initial={{ opacity: 0, x: -20, filter: 'blur(10px)' }}
              animate={{ opacity: 1, x: 0, filter: 'blur(0px)' }}
              transition={{ duration: 0.4, delay: index < 20 ? index * 0.1 : 0 }}
              className="glass p-5 rounded-2xl border border-white/5 hover:border-white/10 transition-colors group"
            >
              <div className="flex items-start justify-between mb-3">
                <div className="flex items-center gap-3">
                  <div className="flex items-center gap-1.5 px-2 py-0.5 rounded-md bg-white/5 border border-white/5">
                    <Clock size={12} className="text-white/40" />
                    <span className="text-[10px] font-mono text-white/60">{event.time}</span>
                  </div>
                  <div
                    className="px-2 py-0.5 rounded-md text-[10px] font-bold uppercase tracking-widest"
                    style={{
                      backgroundColor: `${stateColors[event.state as keyof typeof stateColors] ?? 'var(--color-state-idle)'}22`,
                      color: stateColors[event.state as keyof typeof stateColors] ?? 'var(--color-state-idle)',
                    }}
                  >
                    {event.state}
                  </div>
                  {event.step && (
                    <div className="text-[10px] font-mono text-white/40 uppercase tracking-widest">
                      {event.step}
                    </div>
                  )}
                  {/* Result badge for pass/fail */}
                  {(event.result === 'pass' || event.result === 'success') && (
                    <div className="px-1.5 py-0.5 rounded text-[9px] font-bold uppercase tracking-widest bg-state-done/15 text-state-done">
                      {event.result}
                    </div>
                  )}
                  {event.result === 'fail' && (
                    <div className="px-1.5 py-0.5 rounded text-[9px] font-bold uppercase tracking-widest bg-state-error/15 text-state-error">
                      fail
                    </div>
                  )}
                </div>
                <button className="opacity-0 group-hover:opacity-100 transition-opacity p-1 hover:bg-white/10 rounded text-white/40 hover:text-white">
                  <ArrowRight size={14} />
                </button>
              </div>

              <div className="flex gap-4">
                <div className="mt-1 p-2 rounded-lg bg-white/5 text-white/40">
                  {getActionIcon(event.action, event.result)}
                </div>
                <div className="flex-1">
                  <p className="text-sm leading-relaxed text-white/80">{event.message}</p>
                  {event.action.toLowerCase().includes('dispatch') && (
                    <div className="mt-3 flex items-center gap-2">
                      <button className="text-[10px] font-bold uppercase tracking-widest text-state-executing hover:underline">
                        View Step Details
                      </button>
                    </div>
                  )}
                </div>
              </div>
            </motion.div>
          ))}
        </AnimatePresence>
      </div>
    </div>
  );
};

const CheckCircleIcon = ({ size }: { size: number }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-state-done">
    <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />
    <polyline points="22 4 12 14.01 9 11.01" />
  </svg>
);
