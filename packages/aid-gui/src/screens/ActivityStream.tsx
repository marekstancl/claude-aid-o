import React, { useEffect, useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { useStore, stateColors } from '../store';
import { cn } from '../lib/utils';
import { Clock, MessageSquare, Zap, Shield, Gavel, ArrowRight, Filter } from 'lucide-react';

interface ActivityEvent {
  id: string;
  time: string;
  state: string;
  step?: string;
  message: string;
}

export const ActivityStream: React.FC = () => {
  const [events, setEvents] = useState<ActivityEvent[]>([]);
  const [activeFilter, setActiveFilter] = useState('All');
  const { fsmState } = useStore();

  const filters = ['All', 'Dispatch', 'Gate', 'Decision', 'Transition'];

  useEffect(() => {
    fetch('/api/activity')
      .then(res => res.json())
      .then(setEvents);
  }, []);

  return (
    <div className="h-full flex flex-col p-8">
      <div className="flex items-center justify-between mb-8">
        <div>
          <h2 className="text-2xl font-bold tracking-tight">Activity Stream</h2>
          <p className="text-sm text-white/40">Real-time orchestration events</p>
        </div>
        <div className="flex items-center gap-4">
          <div className="flex bg-white/5 p-1 rounded-xl border border-white/10">
            {filters.map(filter => (
              <button 
                key={filter}
                onClick={() => setActiveFilter(filter)}
                className={cn(
                  "px-4 py-1.5 rounded-lg text-xs font-medium transition-all",
                  activeFilter === filter 
                    ? "bg-white/10 text-white shadow-sm" 
                    : "text-white/40 hover:text-white hover:bg-white/5"
                )}
              >
                {filter}
              </button>
            ))}
          </div>
          <button className="p-2 rounded-xl bg-white/5 border border-white/10 text-white/40 hover:text-white transition-colors">
            <Filter size={16} />
          </button>
          <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-state-done/10 border border-state-done/20">
            <div className="w-1.5 h-1.5 rounded-full bg-state-done" />
            <span className="text-[10px] font-bold uppercase tracking-widest text-state-done">Live</span>
          </div>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto space-y-4 pr-4 custom-scrollbar">
        <AnimatePresence initial={false}>
          {events.map((event, index) => (
            <motion.div
              key={event.id}
              initial={{ opacity: 0, x: -20, filter: 'blur(10px)' }}
              animate={{ opacity: 1, x: 0, filter: 'blur(0px)' }}
              transition={{ duration: 0.4, delay: index * 0.1 }}
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
                    style={{ backgroundColor: `${stateColors[event.state as any]}22`, color: stateColors[event.state as any] }}
                  >
                    {event.state}
                  </div>
                  {event.step && (
                    <div className="text-[10px] font-mono text-white/40 uppercase tracking-widest">
                      {event.step}
                    </div>
                  )}
                </div>
                <button className="opacity-0 group-hover:opacity-100 transition-opacity p-1 hover:bg-white/10 rounded text-white/40 hover:text-white">
                  <ArrowRight size={14} />
                </button>
              </div>
              
              <div className="flex gap-4">
                <div className="mt-1 p-2 rounded-lg bg-white/5 text-white/40">
                  {event.message.includes('dispatched') ? <Zap size={16} /> : 
                   event.message.includes('completed') ? <CheckCircleIcon size={16} /> :
                   <MessageSquare size={16} />}
                </div>
                <div className="flex-1">
                  <p className="text-sm leading-relaxed text-white/80">{event.message}</p>
                  {event.message.includes('dispatched') && (
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
