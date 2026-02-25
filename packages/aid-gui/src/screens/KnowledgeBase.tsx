import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { useStore } from '../store';
import { cn } from '../lib/utils';
import { BookOpen, Search, Terminal, User, Hexagon, Network, ChevronRight, ExternalLink, Code, Cpu } from 'lucide-react';

export const KnowledgeBase: React.FC = () => {
  const [selectedNode, setSelectedNode] = useState<any>(null);

  const nodes = [
    { id: 'n1', type: 'command', label: '/aid-run-epic', description: 'Main orchestration command. Executes EPIC pipeline with 12-state FSM, dispatches agents, runs quality gates.' },
    { id: 'n2', type: 'agent', label: 'architect', description: 'High-level system designer. Responsible for plan.json generation and structural decisions.' },
    { id: 'n3', type: 'skill', label: 'epic-orchestrator', description: 'Core logic for managing EPIC lifecycles and state transitions.' },
    { id: 'n4', type: 'skill', label: 'parallel-dispatch', description: 'Handles concurrent agent execution and resource allocation.' },
    { id: 'n5', type: 'skill', label: 'gates-engine', description: 'Validation layer that runs tests, linters, and security scanners.' },
  ];

  return (
    <div className="h-full flex flex-col overflow-hidden">
      <div className="p-8 border-b border-white/5 flex items-center justify-between bg-surface-1/20">
        <div>
          <h2 className="text-2xl font-bold tracking-tight">Knowledge Base</h2>
          <p className="text-sm text-white/40">Interactive visual browser of AID's architecture</p>
        </div>
        <div className="flex items-center gap-4">
          <div className="relative">
            <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-white/20" />
            <input 
              type="text" 
              placeholder="Search concepts..." 
              className="w-64 bg-white/5 border border-white/10 rounded-lg py-2 pl-9 pr-3 text-xs focus:outline-none focus:border-white/20"
            />
          </div>
          <div className="flex bg-white/5 p-1 rounded-lg border border-white/10">
            <button className="px-3 py-1 rounded text-[10px] font-bold uppercase tracking-widest bg-white/10 text-white">All</button>
            <button className="px-3 py-1 rounded text-[10px] font-bold uppercase tracking-widest text-white/40 hover:text-white">Agents</button>
            <button className="px-3 py-1 rounded text-[10px] font-bold uppercase tracking-widest text-white/40 hover:text-white">Skills</button>
          </div>
        </div>
      </div>

      <div className="flex-1 flex overflow-hidden">
        {/* Graph Area */}
        <div className="flex-1 relative bg-bg-base/40 overflow-hidden cursor-grab active:cursor-grabbing">
          <div className="absolute inset-0 opacity-[0.03]" style={{ backgroundImage: 'linear-gradient(rgba(255,255,255,0.1) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.1) 1px, transparent 1px)', backgroundSize: '100px 100px' }} />
          
          <div className="absolute inset-0 flex items-center justify-center">
            <div className="relative w-full h-full">
              {nodes.map((node, i) => (
                <motion.div
                  key={node.id}
                  drag
                  dragMomentum={false}
                  onClick={() => setSelectedNode(node)}
                  initial={{ opacity: 0, scale: 0 }}
                  animate={{ opacity: 1, scale: 1 }}
                  transition={{ delay: i * 0.1, type: 'spring' }}
                  className={cn(
                    "absolute p-4 rounded-2xl border cursor-pointer transition-all group",
                    selectedNode?.id === node.id ? "ring-2 ring-white/20 shadow-2xl" : "hover:scale-105"
                  )}
                  style={{ 
                    left: `${20 + (i * 15)}%`, 
                    top: `${30 + (i % 2 * 20)}%`,
                    backgroundColor: node.type === 'command' ? 'rgba(0,180,216,0.1)' : node.type === 'agent' ? 'rgba(34,197,94,0.1)' : 'rgba(124,92,191,0.1)',
                    borderColor: node.type === 'command' ? 'rgba(0,180,216,0.3)' : node.type === 'agent' ? 'rgba(34,197,94,0.3)' : 'rgba(124,92,191,0.3)'
                  }}
                >
                  <div className="flex items-center gap-3">
                    <div className={cn(
                      "p-2 rounded-xl",
                      node.type === 'command' ? "text-state-executing" : node.type === 'agent' ? "text-state-done" : "text-state-phase-check"
                    )}>
                      {node.type === 'command' ? <Terminal size={20} /> : node.type === 'agent' ? <User size={20} /> : <Hexagon size={20} />}
                    </div>
                    <div>
                      <div className="text-[10px] font-bold uppercase tracking-widest opacity-40">{node.type}</div>
                      <div className="text-sm font-bold">{node.label}</div>
                    </div>
                  </div>
                </motion.div>
              ))}

              {/* Mock Connections */}
              <svg className="absolute inset-0 w-full h-full pointer-events-none opacity-20">
                <line x1="25%" y1="35%" x2="40%" y2="55%" stroke="white" strokeWidth="1" strokeDasharray="4" />
                <line x1="40%" y1="55%" x2="55%" y2="35%" stroke="white" strokeWidth="1" strokeDasharray="4" />
                <line x1="55%" y1="35%" x2="70%" y2="55%" stroke="white" strokeWidth="1" strokeDasharray="4" />
              </svg>
            </div>
          </div>

          <div className="absolute bottom-8 left-8 flex gap-4">
            <div className="flex items-center gap-2 text-[10px] font-bold uppercase tracking-widest text-white/40">
              <div className="w-2 h-2 rounded-full bg-state-executing" /> Commands
            </div>
            <div className="flex items-center gap-2 text-[10px] font-bold uppercase tracking-widest text-white/40">
              <div className="w-2 h-2 rounded-full bg-state-done" /> Agents
            </div>
            <div className="flex items-center gap-2 text-[10px] font-bold uppercase tracking-widest text-white/40">
              <div className="w-2 h-2 rounded-full bg-state-phase-check" /> Skills
            </div>
          </div>
        </div>

        {/* Detail Panel */}
        <AnimatePresence>
          {selectedNode && (
            <motion.aside
              initial={{ x: '100%' }}
              animate={{ x: 0 }}
              exit={{ x: '100%' }}
              className="w-96 border-l border-white/5 bg-surface-2 p-8 flex flex-col shadow-2xl z-20"
            >
              <div className="flex items-center justify-between mb-8">
                <div className={cn(
                  "p-3 rounded-2xl",
                  selectedNode.type === 'command' ? "bg-state-executing/20 text-state-executing" : 
                  selectedNode.type === 'agent' ? "bg-state-done/20 text-state-done" : 
                  "bg-state-phase-check/20 text-state-phase-check"
                )}>
                  {selectedNode.type === 'command' ? <Terminal size={24} /> : selectedNode.type === 'agent' ? <User size={24} /> : <Hexagon size={24} />}
                </div>
                <button 
                  onClick={() => setSelectedNode(null)}
                  className="p-2 hover:bg-white/5 rounded-lg transition-colors text-white/40"
                >
                  <ChevronRight size={20} />
                </button>
              </div>

              <div className="flex-1 space-y-8 overflow-y-auto custom-scrollbar pr-2">
                <section>
                  <div className="text-[10px] font-bold uppercase tracking-[0.2em] text-white/40 mb-2">{selectedNode.type}</div>
                  <h3 className="text-2xl font-bold tracking-tight mb-4">{selectedNode.label}</h3>
                  <p className="text-sm text-white/60 leading-relaxed">
                    {selectedNode.description}
                  </p>
                </section>

                <section className="space-y-4">
                  <h4 className="text-[10px] font-bold uppercase tracking-widest text-white/40">Related Concepts</h4>
                  <div className="space-y-2">
                    {['epic-orchestrator', 'parallel-dispatch', 'gates-engine'].map(rel => (
                      <button key={rel} className="w-full flex items-center justify-between p-3 rounded-xl bg-white/5 hover:bg-white/10 border border-white/5 transition-all group">
                        <span className="text-xs font-medium">{rel}</span>
                        <ChevronRight size={14} className="text-white/20 group-hover:text-white transition-colors" />
                      </button>
                    ))}
                  </div>
                </section>

                <section className="space-y-4">
                  <h4 className="text-[10px] font-bold uppercase tracking-widest text-white/40">Documentation</h4>
                  <div className="p-4 rounded-xl bg-black/40 border border-white/5 space-y-3">
                    <div className="flex items-center gap-2 text-state-executing">
                      <Code size={14} />
                      <span className="text-[10px] font-mono">Usage Example</span>
                    </div>
                    <pre className="text-[10px] font-mono text-white/40 overflow-x-auto">
                      aid run {selectedNode.label.replace('/', '')} --epic E-005
                    </pre>
                  </div>
                </section>
              </div>

              <button className="mt-8 w-full py-3 bg-white/5 hover:bg-white/10 border border-white/10 rounded-xl text-sm font-medium transition-all flex items-center justify-center gap-2">
                <ExternalLink size={14} /> Read Full Documentation
              </button>
            </motion.aside>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
};
