import React, { useEffect, useState, useCallback } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { createApiClient } from '../api/client';
import { cn } from '../lib/utils';
import {
  Layers,
  Rocket,
  CheckCircle2,
  Clock,
  AlertTriangle,
  Play,
  Calendar,
  FileText,
  ChevronRight,
  X,
  Loader2,
} from 'lucide-react';
import type { ApiError, EpicMetadata } from '../types/api';

const client = createApiClient('default');

const STATUS_CONFIG: Record<string, { color: string; bg: string; icon: React.ComponentType<{ size: number; className?: string }> }> = {
  active:    { color: 'text-state-executing',    bg: 'bg-state-executing/15',    icon: Play },
  running:   { color: 'text-yellow-400',         bg: 'bg-yellow-400/15',         icon: Clock },
  completed: { color: 'text-green-400',          bg: 'bg-green-400/15',          icon: CheckCircle2 },
  failed:    { color: 'text-state-error',        bg: 'bg-state-error/15',        icon: AlertTriangle },
  draft:     { color: 'text-white/40',           bg: 'bg-white/5',              icon: FileText },
};

function getStatusConfig(status: string) {
  return STATUS_CONFIG[status.toLowerCase()] ?? STATUS_CONFIG.draft;
}

export const EpicLifecycle: React.FC = () => {
  const [epics, setEpics] = useState<EpicMetadata[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedEpic, setSelectedEpic] = useState<EpicMetadata | null>(null);
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    async function fetchEpics() {
      setLoading(true);
      const result = await client.getEpics();
      if (cancelled) return;
      if (result.ok) {
        setEpics(result.data);
      } else {
        setError((result as ApiError).error.message);
      }
      setLoading(false);
    }
    fetchEpics();
    return () => { cancelled = true; };
  }, []);

  const handleRunEpic = useCallback(async (epicId: string, mode: 'now' | 'schedule') => {
    setActionLoading(epicId);
    const result = await client.runEpic(epicId, mode);
    if (result.ok) {
      setEpics(prev => prev.map(e => e.id === epicId ? { ...e, status: 'queued' } : e));
    } else {
      setError((result as ApiError).error.message);
    }
    setActionLoading(null);
  }, []);

  if (loading) {
    return (
      <div className="h-full flex flex-col p-8">
        <div className="h-7 w-48 bg-white/5 rounded animate-pulse mb-2" />
        <div className="h-4 w-72 bg-white/5 rounded animate-pulse mb-8" />
        <div className="grid gap-4 grid-cols-1 md:grid-cols-2 lg:grid-cols-3">
          {[1, 2, 3, 4, 5, 6].map(i => (
            <div key={i} className="h-36 bg-white/5 rounded-2xl animate-pulse" />
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="h-full flex flex-col p-8 overflow-y-auto custom-scrollbar">
      {error && (
        <div className="mb-4 p-3 bg-state-error/10 border border-state-error/20 rounded-xl text-sm text-state-error flex items-center justify-between">
          <span>{error}</span>
          <button onClick={() => setError(null)} className="p-1 hover:bg-white/10 rounded"><X size={14} /></button>
        </div>
      )}

      <div className="mb-8">
        <h2 className="text-2xl font-bold tracking-tight">EPIC Lifecycle</h2>
        <p className="text-sm text-white/40">Manage your EPICs from draft to completion</p>
      </div>

      {/* Status summary */}
      <div className="flex gap-4 mb-8 flex-wrap">
        {Object.entries(
          epics.reduce<Record<string, number>>((acc, e) => {
            const s = e.status.toLowerCase();
            acc[s] = (acc[s] || 0) + 1;
            return acc;
          }, {}),
        ).map(([status, count]) => {
          const cfg = getStatusConfig(status);
          const Icon = cfg.icon;
          return (
            <div key={status} className={cn("flex items-center gap-2 px-3 py-1.5 rounded-lg border border-white/5", cfg.bg)}>
              <Icon size={14} className={cfg.color} />
              <span className={cn("text-xs font-bold uppercase tracking-widest", cfg.color)}>{status}</span>
              <span className="text-xs font-mono text-white/30">{count}</span>
            </div>
          );
        })}
      </div>

      {epics.length === 0 ? (
        <div className="flex-1 flex flex-col items-center justify-center">
          <Layers size={48} className="text-white/10 mb-4" />
          <h3 className="text-lg font-medium text-white/30 mb-2">No EPICs found</h3>
          <p className="text-sm text-white/20">Create EPICs in <code className="text-white/30">.aid-o/02-epics/</code> to get started</p>
        </div>
      ) : (
        <div className="grid gap-4 grid-cols-1 md:grid-cols-2 lg:grid-cols-3">
          {epics.map(epic => {
            const cfg = getStatusConfig(epic.status);
            const Icon = cfg.icon;
            const progress = epic.runsTotal > 0 ? Math.round((epic.runsCompleted / epic.runsTotal) * 100) : 0;

            return (
              <motion.div
                key={epic.id}
                initial={{ opacity: 0, y: 12 }}
                animate={{ opacity: 1, y: 0 }}
                className={cn(
                  "glass p-5 rounded-2xl border border-white/5 hover:border-white/10 transition-all cursor-pointer group",
                )}
                onClick={() => setSelectedEpic(epic)}
              >
                <div className="flex items-start justify-between mb-3">
                  <div className="flex items-center gap-2">
                    <div className={cn("p-1.5 rounded-lg", cfg.bg)}>
                      <Icon size={14} className={cfg.color} />
                    </div>
                    <span className={cn("text-[10px] font-bold uppercase tracking-widest", cfg.color)}>
                      {epic.status}
                    </span>
                  </div>
                  <ChevronRight size={16} className="text-white/20 group-hover:text-white/40 transition-colors" />
                </div>

                <h3 className="text-sm font-bold leading-tight mb-1 group-hover:text-state-executing transition-colors line-clamp-2">
                  {epic.title}
                </h3>
                <p className="text-[10px] font-mono text-white/30 mb-4">{epic.id}</p>

                {epic.runsTotal > 0 && (
                  <div className="mb-3">
                    <div className="flex items-center justify-between mb-1">
                      <span className="text-[10px] text-white/30">Runs</span>
                      <span className="text-[10px] font-mono text-white/40">{epic.runsCompleted}/{epic.runsTotal}</span>
                    </div>
                    <div className="h-1.5 bg-white/5 rounded-full overflow-hidden">
                      <div
                        className="h-full bg-state-executing rounded-full transition-all"
                        style={{ width: `${progress}%` }}
                      />
                    </div>
                  </div>
                )}

                {epic.planRef && (
                  <div className="flex items-center gap-1.5 text-[10px] text-white/25 font-mono">
                    <FileText size={10} />
                    <span className="truncate">{epic.planRef}</span>
                  </div>
                )}
              </motion.div>
            );
          })}
        </div>
      )}

      {/* Detail panel */}
      <AnimatePresence>
        {selectedEpic && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-50 flex justify-end bg-black/50 backdrop-blur-sm"
            onClick={() => setSelectedEpic(null)}
          >
            <motion.div
              initial={{ x: '100%' }}
              animate={{ x: 0 }}
              exit={{ x: '100%' }}
              transition={{ type: 'spring', damping: 30, stiffness: 300 }}
              onClick={(e) => e.stopPropagation()}
              className="w-full max-w-md h-full bg-surface-1 border-l border-white/10 shadow-2xl overflow-y-auto"
            >
              <div className="p-6 space-y-6">
                <div className="flex items-start justify-between">
                  <div className="flex-1 mr-4">
                    <h3 className="text-lg font-bold leading-tight">{selectedEpic.title}</h3>
                    <p className="text-xs text-white/40 mt-1 font-mono">{selectedEpic.id}</p>
                  </div>
                  <button
                    onClick={() => setSelectedEpic(null)}
                    className="p-1.5 hover:bg-white/10 rounded-lg text-white/40 hover:text-white transition-colors shrink-0"
                  >
                    <X size={18} />
                  </button>
                </div>

                <div className="flex items-center gap-3">
                  {(() => {
                    const cfg = getStatusConfig(selectedEpic.status);
                    const SIcon = cfg.icon;
                    return (
                      <span className={cn("flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-widest px-2.5 py-1 rounded-lg", cfg.bg, cfg.color)}>
                        <SIcon size={12} />
                        {selectedEpic.status}
                      </span>
                    );
                  })()}
                </div>

                {selectedEpic.runsTotal > 0 && (
                  <div>
                    <label className="text-[10px] font-bold uppercase tracking-widest text-white/40 block mb-2">Execution Progress</label>
                    <div className="flex items-center gap-3">
                      <div className="flex-1 h-2 bg-white/5 rounded-full overflow-hidden">
                        <div
                          className="h-full bg-state-executing rounded-full transition-all"
                          style={{ width: `${Math.round((selectedEpic.runsCompleted / selectedEpic.runsTotal) * 100)}%` }}
                        />
                      </div>
                      <span className="text-sm font-mono text-white/50">{selectedEpic.runsCompleted}/{selectedEpic.runsTotal}</span>
                    </div>
                  </div>
                )}

                <div>
                  <label className="text-[10px] font-bold uppercase tracking-widest text-white/40 block mb-2">Details</label>
                  <div className="space-y-2 text-xs text-white/40 font-mono">
                    <div className="flex justify-between py-1.5 border-b border-white/5">
                      <span>File</span>
                      <span className="text-white/60">{selectedEpic.fileName}</span>
                    </div>
                    <div className="flex justify-between py-1.5 border-b border-white/5">
                      <span>Path</span>
                      <span className="text-white/60">{selectedEpic.path}</span>
                    </div>
                    {selectedEpic.planRef && (
                      <div className="flex justify-between py-1.5 border-b border-white/5">
                        <span>Plan</span>
                        <span className="text-white/60">{selectedEpic.planRef}</span>
                      </div>
                    )}
                  </div>
                </div>

                <div className="flex gap-2 pt-4 border-t border-white/5">
                  <button
                    onClick={() => handleRunEpic(selectedEpic.id, 'now')}
                    disabled={actionLoading === selectedEpic.id}
                    className="flex-1 flex items-center justify-center gap-2 py-2.5 bg-state-executing/10 text-state-executing border border-state-executing/20 rounded-xl text-xs font-bold hover:bg-state-executing/20 transition-colors disabled:opacity-40"
                  >
                    {actionLoading === selectedEpic.id ? <Loader2 size={14} className="animate-spin" /> : <Rocket size={14} />}
                    Run Now
                  </button>
                  <button
                    onClick={() => handleRunEpic(selectedEpic.id, 'schedule')}
                    disabled={actionLoading === selectedEpic.id}
                    className="flex-1 flex items-center justify-center gap-2 py-2.5 bg-white/5 text-white/60 border border-white/10 rounded-xl text-xs font-bold hover:bg-white/10 transition-colors disabled:opacity-40"
                  >
                    <Calendar size={14} /> Schedule
                  </button>
                </div>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
};
