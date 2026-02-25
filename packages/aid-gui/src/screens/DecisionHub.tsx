import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { useStore, stateColors } from '../store';
import { cn } from '../lib/utils';
import { Gavel, Check, X, Info, ExternalLink, FileText, GitBranch, Archive, Clock, History } from 'lucide-react';

export const DecisionHub: React.FC = () => {
  const { fsmState } = useStore();
  const [pendingDecisions, setPendingDecisions] = useState([
    {
      id: 'd1',
      type: 'PM_APPROVAL',
      title: 'Merge Approval Required',
      description: 'Pipeline E-005-1_1 has completed all gates. Requesting approval to merge changes into main branch.',
      context: {
        steps: '12/12',
        gates: '6/6 Passed',
        changes: '47 files, +2,341 / -156 lines',
        duration: '1h 23m'
      }
    }
  ]);

  return (
    <div className="h-full flex flex-col p-8">
      <div className="flex items-center justify-between mb-8">
        <div>
          <h2 className="text-2xl font-bold tracking-tight">Decision Hub</h2>
          <p className="text-sm text-white/40">Critical points requiring human intervention</p>
        </div>
        <div className="px-3 py-1 rounded-full bg-state-pm-approval/10 border border-state-pm-approval/20 text-[10px] font-bold uppercase tracking-widest text-state-pm-approval">
          {pendingDecisions.length} Pending
        </div>
      </div>

      <div className="flex-1 overflow-y-auto custom-scrollbar pr-4">
        <div className="flex flex-col items-center justify-start min-h-full gap-12 pb-12">
          <AnimatePresence mode="wait">
            {pendingDecisions.length > 0 ? (
              <motion.div
                key="decision-card"
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
                    <h3 className="text-2xl font-bold tracking-tight">{pendingDecisions[0].title}</h3>
                  </div>
                </div>

                <p className="text-white/60 leading-relaxed mb-8">
                  {pendingDecisions[0].description}
                </p>

                <div className="grid grid-cols-2 gap-4 mb-8">
                  <ContextItem icon={GitBranch} label="Steps" value={pendingDecisions[0].context.steps} />
                  <ContextItem icon={Archive} label="Gates" value={pendingDecisions[0].context.gates} />
                  <ContextItem icon={FileText} label="Changes" value={pendingDecisions[0].context.changes} />
                  <ContextItem icon={Info} label="Duration" value={pendingDecisions[0].context.duration} />
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
                    <button className="flex-1 bg-state-done hover:bg-state-done/90 text-bg-base font-bold py-4 rounded-2xl transition-all flex items-center justify-center gap-2 shadow-lg shadow-state-done/20">
                      <Check size={20} /> APPROVE & MERGE
                    </button>
                    <button className="flex-1 bg-white/5 hover:bg-state-error/20 hover:text-state-error hover:border-state-error/50 border border-white/10 text-white font-bold py-4 rounded-2xl transition-all flex items-center justify-center gap-2">
                      <X size={20} /> REJECT
                    </button>
                  </div>
                  <textarea 
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
              {[
                { id: 'pd1', title: 'Approve Auth Refactor PR', status: 'approved', time: '2 hours ago', responseTime: '15m' },
                { id: 'pd2', title: 'Skip non-critical failing test', status: 'rejected', time: '1 day ago', responseTime: '4h 20m' },
                { id: 'pd3', title: 'Deploy v1.2.0 to Staging', status: 'approved', time: '2 days ago', responseTime: '5m' },
              ].map((decision) => (
                <div key={decision.id} className="glass p-4 rounded-2xl border border-white/5 flex items-center justify-between hover:bg-white/5 transition-colors cursor-pointer group">
                  <div className="flex items-center gap-4">
                    <div className={cn(
                      "w-8 h-8 rounded-full flex items-center justify-center",
                      decision.status === 'approved' ? "bg-state-done/20 text-state-done" : "bg-state-error/20 text-state-error"
                    )}>
                      {decision.status === 'approved' ? <Check size={14} /> : <X size={14} />}
                    </div>
                    <div>
                      <h4 className="text-sm font-medium group-hover:text-white transition-colors">{decision.title}</h4>
                      <div className="flex items-center gap-3 mt-1">
                        <span className="text-[10px] font-mono text-white/40 flex items-center gap-1">
                          <Clock size={10} /> {decision.time}
                        </span>
                        <span className="text-[10px] font-mono text-white/20">
                          Response: {decision.responseTime}
                        </span>
                      </div>
                    </div>
                  </div>
                  <button className="opacity-0 group-hover:opacity-100 p-2 hover:bg-white/10 rounded-lg transition-all text-white/40 hover:text-white">
                    <ExternalLink size={14} />
                  </button>
                </div>
              ))}
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
