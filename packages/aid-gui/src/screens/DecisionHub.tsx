import React, { useState, useEffect, useCallback, useRef } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { useStore, stateColors } from '../store';
import { createApiClient } from '../api/client';
import { cn } from '../lib/utils';
import { Gavel, Check, X, Info, ExternalLink, FileText, GitBranch, Archive, Clock, History, Bell, BellOff } from 'lucide-react';
import { useNotifications } from '../hooks/useNotifications';
import type { ApiError, PendingDecisionEntry, DecisionEntry } from '../types/api';

const client = createApiClient('default');

export const DecisionHub: React.FC = () => {
  const {
    pendingDecisionsList,
    decisionHistory,
    decisionsLoading,
    setPendingDecisionsList,
    setDecisionHistory,
    setDecisionsLoading,
    removePendingDecision,
    addDecisionToHistory,
  } = useStore();

  const {
    playNotificationSound,
    showBrowserNotification,
    requestPermission,
    permissionState,
  } = useNotifications();

  const [notificationsEnabled, setNotificationsEnabled] = useState(true);
  const [feedback, setFeedback] = useState('');
  const [actionInFlight, setActionInFlight] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Track the previous pending count to detect new arrivals
  const prevPendingCountRef = useRef(pendingDecisionsList.length);

  // Trigger notifications when new pending decisions arrive
  useEffect(() => {
    const prevCount = prevPendingCountRef.current;
    const currentCount = pendingDecisionsList.length;
    prevPendingCountRef.current = currentCount;

    // Only notify when count increases (new decisions arrived)
    if (currentCount > prevCount && prevCount >= 0 && notificationsEnabled) {
      playNotificationSound();

      // Show browser notification with the newest decision's state
      if (pendingDecisionsList.length > 0) {
        const newest = pendingDecisionsList[0];
        const body = `${newest.state.replace(/_/g, ' ')} - EPIC ${newest.epicId}`;
        showBrowserNotification(body);
      }
    }
  }, [pendingDecisionsList, notificationsEnabled, playNotificationSound, showBrowserNotification]);

  // Fetch pending decisions and decision history on mount
  useEffect(() => {
    let cancelled = false;

    async function fetchDecisions() {
      setDecisionsLoading(true);
      setError(null);

      const [pendingResult, historyResult] = await Promise.all([
        client.getDecisionsPending(),
        client.getDecisions(),
      ]);

      if (cancelled) return;

      if (!pendingResult.ok) {
        const err = pendingResult as ApiError;
        setError(err.error.message);
      } else {
        setPendingDecisionsList(pendingResult.data);
      }

      if (!historyResult.ok) {
        const err = historyResult as ApiError;
        if (!error) setError(err.error.message);
      } else {
        setDecisionHistory(historyResult.data);
      }

      setDecisionsLoading(false);
    }

    fetchDecisions();

    return () => {
      cancelled = true;
    };
  }, []);

  const handleDecision = useCallback(async (decision: 'approved' | 'rejected') => {
    if (pendingDecisionsList.length === 0 || actionInFlight) return;

    const pending = pendingDecisionsList[0];
    setActionInFlight(true);
    setError(null);

    // Optimistic update: remove from pending, add to history
    removePendingDecision(pending.epicId, pending.runId);
    const historyEntry: DecisionEntry = {
      timestamp: new Date().toISOString(),
      type: 'decision',
      epicId: pending.epicId,
      runId: pending.runId,
      decision,
      feedback: decision === 'rejected' && feedback ? feedback : null,
      channel: 'gui',
      latencyMinutes: 0,
    };
    addDecisionToHistory(historyEntry);
    setFeedback('');

    const result = await client.postDecision({
      epicId: pending.epicId,
      runId: pending.runId,
      decision,
      ...(decision === 'rejected' && feedback ? { feedback } : {}),
    });

    if (!result.ok) {
      const err = result as ApiError;
      setError(err.error.message);
      // Revert optimistic update on failure: re-add to pending
      setPendingDecisionsList([pending, ...pendingDecisionsList.slice(1)]);
    }

    setActionInFlight(false);
  }, [pendingDecisionsList, feedback, actionInFlight, removePendingDecision, addDecisionToHistory, setPendingDecisionsList]);

  // Format a decision state for display
  const formatState = (state: string) => {
    return state.replace(/_/g, ' ');
  };

  // Format relative time from ISO timestamp
  const formatRelativeTime = (timestamp: string) => {
    const now = Date.now();
    const then = new Date(timestamp).getTime();
    const diffMs = now - then;
    const diffMin = Math.floor(diffMs / 60000);
    if (diffMin < 1) return 'just now';
    if (diffMin < 60) return `${diffMin}m ago`;
    const diffHours = Math.floor(diffMin / 60);
    if (diffHours < 24) return `${diffHours}h ago`;
    const diffDays = Math.floor(diffHours / 24);
    return `${diffDays}d ago`;
  };

  // Format latency minutes for display
  const formatLatency = (minutes: number | undefined) => {
    if (minutes === undefined || minutes === null) return '--';
    if (minutes < 1) return '<1m';
    if (minutes < 60) return `${Math.round(minutes)}m`;
    const hours = Math.floor(minutes / 60);
    const mins = Math.round(minutes % 60);
    return mins > 0 ? `${hours}h ${mins}m` : `${hours}h`;
  };

  // Skeleton loader for the pending decision card
  if (decisionsLoading) {
    return (
      <div className="h-full flex flex-col p-8">
        <div className="flex items-center justify-between mb-8">
          <div>
            <div className="h-7 w-48 bg-white/5 rounded-lg animate-pulse" />
            <div className="h-4 w-72 bg-white/5 rounded-lg animate-pulse mt-2" />
          </div>
          <div className="h-6 w-24 bg-white/5 rounded-full animate-pulse" />
        </div>
        <div className="flex-1 overflow-y-auto custom-scrollbar pr-4">
          <div className="flex flex-col items-center justify-start min-h-full gap-12 pb-12">
            <div className="max-w-2xl w-full glass p-8 rounded-[2rem] border border-white/5 mt-8">
              <div className="flex items-center gap-4 mb-8">
                <div className="w-12 h-12 rounded-2xl bg-white/5 animate-pulse" />
                <div className="flex-1">
                  <div className="h-3 w-28 bg-white/5 rounded animate-pulse mb-2" />
                  <div className="h-6 w-56 bg-white/5 rounded animate-pulse" />
                </div>
              </div>
              <div className="h-4 w-full bg-white/5 rounded animate-pulse mb-2" />
              <div className="h-4 w-3/4 bg-white/5 rounded animate-pulse mb-8" />
              <div className="grid grid-cols-2 gap-4 mb-8">
                {[1, 2, 3, 4].map(i => (
                  <div key={i} className="h-16 bg-white/5 rounded-2xl animate-pulse" />
                ))}
              </div>
              <div className="flex gap-4">
                <div className="flex-1 h-14 bg-white/5 rounded-2xl animate-pulse" />
                <div className="flex-1 h-14 bg-white/5 rounded-2xl animate-pulse" />
              </div>
            </div>

            <div className="w-full max-w-2xl">
              <div className="h-4 w-32 bg-white/5 rounded animate-pulse mb-6" />
              <div className="space-y-3">
                {[1, 2, 3].map(i => (
                  <div key={i} className="h-16 bg-white/5 rounded-2xl animate-pulse" />
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="h-full flex flex-col p-8">
      <div className="flex items-center justify-between mb-8">
        <div>
          <h2 className="text-2xl font-bold tracking-tight">Decision Hub</h2>
          <p className="text-sm text-white/40">Critical points requiring human intervention</p>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={() => {
              const next = !notificationsEnabled;
              setNotificationsEnabled(next);
              if (next && permissionState !== 'granted' && permissionState !== 'unsupported') {
                requestPermission();
              }
            }}
            className={cn(
              "flex items-center gap-1.5 px-3 py-1.5 rounded-full border text-[10px] font-bold uppercase tracking-widest transition-all",
              notificationsEnabled
                ? "bg-state-done/10 border-state-done/20 text-state-done hover:bg-state-done/20"
                : "bg-white/5 border-white/10 text-white/40 hover:bg-white/10 hover:text-white/60"
            )}
            title={notificationsEnabled ? 'Disable notifications' : 'Enable notifications'}
          >
            {notificationsEnabled ? <Bell size={12} /> : <BellOff size={12} />}
            {notificationsEnabled ? 'Notifications On' : 'Notifications Off'}
          </button>
          <div className="px-3 py-1 rounded-full bg-state-pm-approval/10 border border-state-pm-approval/20 text-[10px] font-bold uppercase tracking-widest text-state-pm-approval">
            {pendingDecisionsList.length} Pending
          </div>
        </div>
      </div>

      {error && (
        <div className="mb-4 px-4 py-3 rounded-2xl bg-state-error/10 border border-state-error/20 text-sm text-state-error">
          {error}
        </div>
      )}

      <div className="flex-1 overflow-y-auto custom-scrollbar pr-4">
        <div className="flex flex-col items-center justify-start min-h-full gap-12 pb-12">
          <AnimatePresence mode="wait">
            {pendingDecisionsList.length > 0 ? (
              <motion.div
                key={`decision-card-${pendingDecisionsList[0].epicId}-${pendingDecisionsList[0].runId}`}
                initial={{ opacity: 0, scale: 0.95, y: 20 }}
                animate={{ opacity: 1, scale: 1, y: 0 }}
                exit={{ opacity: 0, scale: 1.05, y: -20 }}
                className="max-w-2xl w-full glass p-8 rounded-[2rem] border-state-pm-approval/30 shadow-[0_0_50px_rgba(232,168,50,0.1)] relative overflow-hidden mt-8"
              >
                {/* Background Glow */}
                <div className="absolute top-0 right-0 w-64 h-64 bg-state-pm-approval/5 blur-[100px] -mr-32 -mt-32" />

                <div className="flex items-center gap-4 mb-8">
                  <div className="p-3 rounded-2xl bg-state-pm-approval/20 text-state-pm-approval">
                    <Gavel size={24} />
                  </div>
                  <div>
                    <div className="text-[10px] font-bold uppercase tracking-[0.2em] text-state-pm-approval mb-1">Decision Required</div>
                    <h3 className="text-2xl font-bold tracking-tight">{formatState(pendingDecisionsList[0].state)}</h3>
                  </div>
                </div>

                <p className="text-white/60 leading-relaxed mb-8">
                  EPIC <span className="font-mono text-white/80">{pendingDecisionsList[0].epicId}</span> run <span className="font-mono text-white/80">{pendingDecisionsList[0].runId}</span> is awaiting your decision.
                </p>

                <div className="grid grid-cols-2 gap-4 mb-8">
                  <ContextItem icon={GitBranch} label="Epic ID" value={pendingDecisionsList[0].epicId} />
                  <ContextItem icon={Archive} label="Run ID" value={pendingDecisionsList[0].runId} />
                  <ContextItem icon={FileText} label="State" value={pendingDecisionsList[0].state} />
                  <ContextItem icon={Info} label="Evidence" value={pendingDecisionsList[0].evidencePath.split('/').slice(-2).join('/')} />
                </div>

                <div className="flex items-center gap-4 mb-8">
                  <button className="flex-1 flex items-center justify-center gap-2 py-2 text-xs font-medium bg-white/5 hover:bg-white/10 rounded-xl border border-white/10 transition-all">
                    <ExternalLink size={14} /> View Pipeline
                  </button>
                  <button className="flex-1 flex items-center justify-center gap-2 py-2 text-xs font-medium bg-white/5 hover:bg-white/10 rounded-xl border border-white/10 transition-all">
                    <ExternalLink size={14} /> View Evidence
                  </button>
                </div>

                <div className="space-y-4">
                  <div className="flex gap-4">
                    <button
                      disabled={actionInFlight}
                      onClick={() => handleDecision('approved')}
                      className="flex-1 bg-state-done hover:bg-state-done/90 text-bg-base font-bold py-4 rounded-2xl transition-all flex items-center justify-center gap-2 shadow-lg shadow-state-done/20 disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                      <Check size={20} /> APPROVE
                    </button>
                    <button
                      disabled={actionInFlight}
                      onClick={() => handleDecision('rejected')}
                      className="flex-1 bg-white/5 hover:bg-state-error/20 hover:text-state-error hover:border-state-error/50 border border-white/10 text-white font-bold py-4 rounded-2xl transition-all flex items-center justify-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                      <X size={20} /> REJECT
                    </button>
                  </div>
                  <textarea
                    value={feedback}
                    onChange={(e) => setFeedback(e.target.value)}
                    placeholder="Optional feedback for the agents..."
                    className="w-full bg-white/5 border border-white/10 rounded-2xl p-4 text-sm focus:outline-none focus:border-white/20 transition-all min-h-[100px] resize-none"
                  />
                </div>
              </motion.div>
            ) : (
              <motion.div
                key="no-decisions"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                className="text-center space-y-4 mt-20"
              >
                <div className="w-20 h-20 rounded-full bg-white/5 flex items-center justify-center mx-auto text-white/20">
                  <Gavel size={40} />
                </div>
                <h3 className="text-xl font-medium text-white/40">No pending decisions</h3>
                <p className="text-sm text-white/20">The pipeline is flowing smoothly.</p>
              </motion.div>
            )}
          </AnimatePresence>

          {/* Past Decisions Section */}
          <div className="w-full max-w-2xl">
            <div className="flex items-center gap-2 mb-6">
              <History size={16} className="text-white/40" />
              <h3 className="text-[10px] font-bold uppercase tracking-widest text-white/40">Past Decisions</h3>
            </div>

            <div className="space-y-3">
              {decisionHistory.length === 0 ? (
                <div className="text-center py-8 text-white/20 text-sm">
                  No decision history yet.
                </div>
              ) : (
                decisionHistory.map((decision, index) => (
                  <div key={`${decision.timestamp}-${decision.epicId ?? ''}-${index}`} className="glass p-4 rounded-2xl border border-white/5 flex items-center justify-between hover:bg-white/5 transition-colors cursor-pointer group">
                    <div className="flex items-center gap-4">
                      <div className={cn(
                        "w-8 h-8 rounded-full flex items-center justify-center",
                        decision.decision === 'approved' || decision.decision === 'GO' ? "bg-state-done/20 text-state-done" : "bg-state-error/20 text-state-error"
                      )}>
                        {decision.decision === 'approved' || decision.decision === 'GO' ? <Check size={14} /> : <X size={14} />}
                      </div>
                      <div>
                        <h4 className="text-sm font-medium group-hover:text-white transition-colors">
                          {decision.type ? formatState(decision.type) : 'Decision'}{decision.epicId ? ` - ${decision.epicId}` : ''}
                        </h4>
                        <div className="flex items-center gap-3 mt-1">
                          <span className="text-[10px] font-mono text-white/40 flex items-center gap-1">
                            <Clock size={10} /> {formatRelativeTime(decision.timestamp)}
                          </span>
                          <span className="text-[10px] font-mono text-white/20">
                            Response: {formatLatency(decision.latencyMinutes)}
                          </span>
                          {decision.feedback && (
                            <span className="text-[10px] font-mono text-white/20 truncate max-w-[200px]" title={decision.feedback}>
                              "{decision.feedback}"
                            </span>
                          )}
                        </div>
                      </div>
                    </div>
                    <button className="opacity-0 group-hover:opacity-100 p-2 hover:bg-white/10 rounded-lg transition-all text-white/40 hover:text-white">
                      <ExternalLink size={14} />
                    </button>
                  </div>
                ))
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

const ContextItem = ({ icon: Icon, label, value }: { icon: any, label: string, value: string }) => (
  <div className="bg-white/5 border border-white/5 rounded-2xl p-4">
    <div className="flex items-center gap-2 text-white/40 mb-1">
      <Icon size={14} />
      <span className="text-[10px] font-bold uppercase tracking-widest">{label}</span>
    </div>
    <div className="text-sm font-medium">{value}</div>
  </div>
);
