import React, { useState, useEffect, useMemo } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { useStore } from '../store';
import { createApiClient } from '../api/client';
import { cn } from '../lib/utils';
import { BookOpen, Search, Terminal, User, Hexagon, Network, ChevronRight, ExternalLink, Code, Cpu } from 'lucide-react';
import type { ApiError, KnowledgeItem } from '../types/api';

const client = createApiClient('default');

type FilterType = 'all' | 'agent' | 'skill' | 'command';

export const KnowledgeBase: React.FC = () => {
  const knowledgeItems = useStore((s) => s.knowledgeItems);
  const knowledgeLoading = useStore((s) => s.knowledgeLoading);
  const setKnowledgeItems = useStore((s) => s.setKnowledgeItems);
  const setKnowledgeLoading = useStore((s) => s.setKnowledgeLoading);

  const [selectedNode, setSelectedNode] = useState<KnowledgeItem | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [activeFilter, setActiveFilter] = useState<FilterType>('all');

  // Fetch knowledge data on mount
  useEffect(() => {
    let cancelled = false;
    const fetchKnowledge = async () => {
      setKnowledgeLoading(true);
      const result = await client.getKnowledge();
      if (cancelled) return;
      if (result.ok) {
        setKnowledgeItems(result.data);
      } else {
        console.error('Failed to fetch knowledge data:', (result as ApiError).error.message);
      }
      setKnowledgeLoading(false);
    };
    fetchKnowledge();
    return () => { cancelled = true; };
  }, [setKnowledgeItems, setKnowledgeLoading]);

  // Filter and search items
  const filteredItems = useMemo(() => {
    let items = knowledgeItems;

    // Apply type filter
    if (activeFilter !== 'all') {
      items = items.filter((item) => item.type === activeFilter);
    }

    // Apply search filter
    if (searchQuery.trim()) {
      const query = searchQuery.toLowerCase();
      items = items.filter(
        (item) =>
          item.name.toLowerCase().includes(query) ||
          item.description.toLowerCase().includes(query),
      );
    }

    return items;
  }, [knowledgeItems, activeFilter, searchQuery]);

  // Compute node positions based on index and type
  const getNodePosition = (index: number, total: number, type: KnowledgeItem['type']) => {
    // Distribute nodes in a grid-like layout with type-based vertical offset
    const typeOffset = type === 'agent' ? 0 : type === 'skill' ? 1 : 2;
    const cols = Math.max(3, Math.ceil(Math.sqrt(total)));
    const row = Math.floor(index / cols);
    const col = index % cols;

    const xSpacing = 80 / Math.max(cols, 1);
    const ySpacing = 50 / Math.max(Math.ceil(total / cols), 1);

    const left = 10 + col * xSpacing + (typeOffset * 3);
    const top = 15 + row * ySpacing + (typeOffset * 5);

    return { left: `${Math.min(left, 80)}%`, top: `${Math.min(top, 75)}%` };
  };

  // Generate SVG connection lines between adjacent nodes
  const connectionLines = useMemo(() => {
    if (filteredItems.length < 2) return [];
    const lines: { x1: string; y1: string; x2: string; y2: string }[] = [];
    for (let i = 0; i < filteredItems.length - 1; i++) {
      const pos1 = getNodePosition(i, filteredItems.length, filteredItems[i].type);
      const pos2 = getNodePosition(i + 1, filteredItems.length, filteredItems[i + 1].type);
      lines.push({
        x1: pos1.left,
        y1: pos1.top,
        x2: pos2.left,
        y2: pos2.top,
      });
    }
    return lines;
  }, [filteredItems]);

  const filterButtons: { label: string; value: FilterType }[] = [
    { label: 'All', value: 'all' },
    { label: 'Agents', value: 'agent' },
    { label: 'Skills', value: 'skill' },
    { label: 'Commands', value: 'command' },
  ];

  // Skeleton loading state
  if (knowledgeLoading && knowledgeItems.length === 0) {
    return (
      <div className="h-full flex flex-col overflow-hidden">
        <div className="p-8 border-b border-white/5 flex items-center justify-between bg-surface-1/20">
          <div>
            <div className="h-7 w-48 bg-white/10 rounded animate-pulse mb-2" />
            <div className="h-4 w-72 bg-white/5 rounded animate-pulse" />
          </div>
          <div className="flex items-center gap-4">
            <div className="h-9 w-64 bg-white/5 rounded-lg animate-pulse" />
            <div className="h-9 w-56 bg-white/5 rounded-lg animate-pulse" />
          </div>
        </div>
        <div className="flex-1 relative bg-bg-base/40 overflow-hidden">
          <div className="absolute inset-0 opacity-[0.03]" style={{ backgroundImage: 'linear-gradient(rgba(255,255,255,0.1) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.1) 1px, transparent 1px)', backgroundSize: '100px 100px' }} />
          <div className="absolute inset-0 flex items-center justify-center">
            <div className="relative w-full h-full">
              {[0, 1, 2, 3, 4].map((i) => (
                <div
                  key={i}
                  className="absolute p-4 rounded-2xl border border-white/10 bg-white/5 animate-pulse"
                  style={{ left: `${20 + i * 15}%`, top: `${30 + (i % 2) * 20}%`, width: 180, height: 72 }}
                />
              ))}
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
      </div>
    );
  }

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
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-64 bg-white/5 border border-white/10 rounded-lg py-2 pl-9 pr-3 text-xs focus:outline-none focus:border-white/20"
            />
          </div>
          <div className="flex bg-white/5 p-1 rounded-lg border border-white/10">
            {filterButtons.map((btn) => (
              <button
                key={btn.value}
                onClick={() => setActiveFilter(btn.value)}
                className={cn(
                  "px-3 py-1 rounded text-[10px] font-bold uppercase tracking-widest",
                  activeFilter === btn.value
                    ? "bg-white/10 text-white"
                    : "text-white/40 hover:text-white"
                )}
              >
                {btn.label}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="flex-1 flex overflow-hidden">
        {/* Graph Area */}
        <div className="flex-1 relative bg-bg-base/40 overflow-hidden cursor-grab active:cursor-grabbing">
          <div className="absolute inset-0 opacity-[0.03]" style={{ backgroundImage: 'linear-gradient(rgba(255,255,255,0.1) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.1) 1px, transparent 1px)', backgroundSize: '100px 100px' }} />

          <div className="absolute inset-0 flex items-center justify-center">
            <div className="relative w-full h-full">
              {filteredItems.map((item, i) => {
                const pos = getNodePosition(i, filteredItems.length, item.type);
                return (
                  <motion.div
                    key={`${item.type}-${item.name}`}
                    drag
                    dragMomentum={false}
                    onClick={() => setSelectedNode(item)}
                    initial={{ opacity: 0, scale: 0 }}
                    animate={{ opacity: 1, scale: 1 }}
                    transition={{ delay: i * 0.1, type: 'spring' }}
                    className={cn(
                      "absolute p-4 rounded-2xl border cursor-pointer transition-all group",
                      selectedNode?.name === item.name && selectedNode?.type === item.type ? "ring-2 ring-white/20 shadow-2xl" : "hover:scale-105"
                    )}
                    style={{
                      left: pos.left,
                      top: pos.top,
                      backgroundColor: item.type === 'command' ? 'rgba(0,180,216,0.1)' : item.type === 'agent' ? 'rgba(34,197,94,0.1)' : 'rgba(124,92,191,0.1)',
                      borderColor: item.type === 'command' ? 'rgba(0,180,216,0.3)' : item.type === 'agent' ? 'rgba(34,197,94,0.3)' : 'rgba(124,92,191,0.3)'
                    }}
                  >
                    <div className="flex items-center gap-3">
                      <div className={cn(
                        "p-2 rounded-xl",
                        item.type === 'command' ? "text-state-executing" : item.type === 'agent' ? "text-state-done" : "text-state-phase-check"
                      )}>
                        {item.type === 'command' ? <Terminal size={20} /> : item.type === 'agent' ? <User size={20} /> : <Hexagon size={20} />}
                      </div>
                      <div>
                        <div className="text-[10px] font-bold uppercase tracking-widest opacity-40">{item.type}</div>
                        <div className="text-sm font-bold">{item.name}</div>
                      </div>
                    </div>
                  </motion.div>
                );
              })}

              {/* Connection Lines */}
              <svg className="absolute inset-0 w-full h-full pointer-events-none opacity-20">
                {connectionLines.map((line, i) => (
                  <line
                    key={i}
                    x1={line.x1}
                    y1={line.y1}
                    x2={line.x2}
                    y2={line.y2}
                    stroke="white"
                    strokeWidth="1"
                    strokeDasharray="4"
                  />
                ))}
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
                  <h3 className="text-2xl font-bold tracking-tight mb-4">{selectedNode.name}</h3>
                  <p className="text-sm text-white/60 leading-relaxed">
                    {selectedNode.description}
                  </p>
                </section>

                <section className="space-y-4">
                  <h4 className="text-[10px] font-bold uppercase tracking-widest text-white/40">Source File</h4>
                  <div className="p-3 rounded-xl bg-white/5 border border-white/5">
                    <span className="text-xs font-mono text-white/60">{selectedNode.filename}</span>
                  </div>
                </section>

                <section className="space-y-4">
                  <h4 className="text-[10px] font-bold uppercase tracking-widest text-white/40">Related Concepts</h4>
                  <div className="space-y-2">
                    {knowledgeItems
                      .filter((item) => item.name !== selectedNode.name && item.type === selectedNode.type)
                      .slice(0, 3)
                      .map((rel) => (
                        <button
                          key={`${rel.type}-${rel.name}`}
                          onClick={() => setSelectedNode(rel)}
                          className="w-full flex items-center justify-between p-3 rounded-xl bg-white/5 hover:bg-white/10 border border-white/5 transition-all group"
                        >
                          <span className="text-xs font-medium">{rel.name}</span>
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
                      aid run {selectedNode.name.replace('/', '')} --epic E-005
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
