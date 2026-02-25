import React, { useState } from 'react';
import { motion } from 'motion/react';
import { useStore } from '../store';
import { cn } from '../lib/utils';
import { Lightbulb, Plus, Rocket, Clock, CheckCircle2, MoreHorizontal, Filter, LayoutGrid, Network } from 'lucide-react';

export const IdeasToExecution: React.FC = () => {
  const [view, setView] = useState<'board' | 'brainstorm'>('board');

  const columns = [
    { id: 'ideas', title: 'Ideas', items: [
      { id: 'i1', title: 'OAuth Integration', tags: ['#auth', '#security'], priority: 'high' },
      { id: 'i2', title: 'Dark Mode Polish', tags: ['#ui'], priority: 'low' }
    ]},
    { id: 'planned', title: 'Planned', items: [
      { id: 'i3', title: 'API V2 Endpoints', tags: ['#backend'], priority: 'medium' }
    ]},
    { id: 'queued', title: 'Queued', items: [
      { id: 'i4', title: 'Refactor Auth Service', tags: ['#refactor'], priority: 'high', linkedEpic: 'E-005', scheduled: '2h' }
    ]},
    { id: 'running', title: 'Running', items: [
      { id: 'i5', title: 'Dashboard UI', tags: ['#frontend'], priority: 'medium', progress: 65 }
    ]},
    { id: 'done', title: 'Done', items: [
      { id: 'i6', title: 'Initial Setup', tags: ['#infra'], priority: 'low' }
    ]},
  ];

  return (
    <div className="h-full flex flex-col p-8 overflow-hidden">
      <div className="flex items-center justify-between mb-8">
        <div>
          <h2 className="text-2xl font-bold tracking-tight">Ideas to Execution</h2>
          <p className="text-sm text-white/40">The journey from napkin sketch to running code</p>
        </div>
        <div className="flex items-center gap-4">
          <div className="flex bg-white/5 p-1 rounded-xl border border-white/10">
            <button 
              onClick={() => setView('board')}
              className={cn("p-2 rounded-lg transition-all", view === 'board' ? "bg-white/10 text-white" : "text-white/40 hover:text-white")}
            >
              <LayoutGrid size={18} />
            </button>
            <button 
              onClick={() => setView('brainstorm')}
              className={cn("p-2 rounded-lg transition-all", view === 'brainstorm' ? "bg-white/10 text-white" : "text-white/40 hover:text-white")}
            >
              <Network size={18} />
            </button>
          </div>
          <button className="flex items-center gap-2 px-4 py-2 bg-state-executing text-bg-base font-bold rounded-xl shadow-lg shadow-state-executing/20 hover:scale-105 transition-all">
            <Plus size={18} /> Quick Capture
          </button>
        </div>
      </div>

      {view === 'board' ? (
        <div className="flex-1 flex gap-6 overflow-x-auto pb-4 custom-scrollbar">
          {columns.map(col => (
            <div key={col.id} className="w-80 shrink-0 flex flex-col">
              <div className="flex items-center justify-between mb-4 px-2">
                <div className="flex items-center gap-2">
                  <span className="text-[10px] font-bold uppercase tracking-[0.2em] text-white/40">{col.title}</span>
                  <span className="text-[10px] font-mono bg-white/5 px-1.5 py-0.5 rounded text-white/20">{col.items.length}</span>
                </div>
                <button className="text-white/20 hover:text-white transition-colors"><MoreHorizontal size={14} /></button>
              </div>

              <div className="flex-1 space-y-3 p-2 bg-white/[0.02] rounded-2xl border border-white/5 overflow-y-auto custom-scrollbar">
                {col.items.map(item => (
                  <motion.div
                    key={item.id}
                    whileHover={{ y: -2, backgroundColor: 'rgba(255,255,255,0.05)' }}
                    className="glass p-4 rounded-xl border border-white/5 cursor-grab active:cursor-grabbing group"
                  >
                    <div className="flex items-start justify-between mb-3">
                      <h4 className="text-sm font-medium leading-tight group-hover:text-state-executing transition-colors">{item.title}</h4>
                      {item.priority === 'high' && <div className="w-1.5 h-1.5 rounded-full bg-state-error shadow-[0_0_8px_rgba(239,68,68,0.5)]" />}
                    </div>
                    
                    <div className="flex flex-wrap gap-1.5 mb-4">
                      {item.tags.map(tag => (
                        <span key={tag} className="text-[9px] font-mono text-white/30">{tag}</span>
                      ))}
                    </div>

                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        {item.progress !== undefined ? (
                          <div className="flex items-center gap-2">
                            <div className="w-12 h-1 bg-white/10 rounded-full overflow-hidden">
                              <div className="h-full bg-state-executing" style={{ width: `${item.progress}%` }} />
                            </div>
                            <span className="text-[10px] font-mono text-white/40">{item.progress}%</span>
                          </div>
                        ) : item.scheduled ? (
                          <div className="flex items-center gap-1.5 text-[10px] font-mono text-state-plan-review">
                            <Clock size={10} />
                            <span>T-{item.scheduled}</span>
                          </div>
                        ) : item.linkedEpic ? (
                          <div className="flex items-center gap-1.5 text-[10px] font-mono text-state-executing">
                            <Rocket size={10} />
                            <span>{item.linkedEpic}</span>
                          </div>
                        ) : (
                          <Clock size={12} className="text-white/20" />
                        )}
                      </div>
                      <button className="opacity-0 group-hover:opacity-100 transition-opacity p-1 hover:bg-white/10 rounded text-white/40 hover:text-white">
                        <MoreHorizontal size={12} />
                      </button>
                    </div>
                  </motion.div>
                ))}
                <button className="w-full py-3 border border-dashed border-white/10 rounded-xl text-[10px] font-bold uppercase tracking-widest text-white/20 hover:text-white/40 hover:border-white/20 transition-all">
                  + Add Item
                </button>
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="flex-1 glass rounded-[2.5rem] border border-white/5 relative overflow-hidden flex items-center justify-center">
          <div className="absolute inset-0 opacity-10" style={{ backgroundImage: 'radial-gradient(circle at 2px 2px, white 1px, transparent 0)', backgroundSize: '40px 40px' }} />
          <div className="text-center space-y-4 relative z-10">
            <div className="w-20 h-20 rounded-full bg-white/5 flex items-center justify-center mx-auto text-white/20">
              <Network size={40} />
            </div>
            <h3 className="text-xl font-medium text-white/40">Brainstorm Canvas</h3>
            <p className="text-sm text-white/20 max-w-xs mx-auto">Visualize connections between ideas and map your project's future.</p>
            <button className="px-6 py-2 bg-white/5 hover:bg-white/10 border border-white/10 rounded-xl text-xs font-medium transition-all">
              Initialize Canvas
            </button>
          </div>
        </div>
      )}
    </div>
  );
};
