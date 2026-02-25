import React, { useEffect, useState } from 'react';
import { motion } from 'motion/react';
import { useStore, stateColors } from '../store';
import { cn } from '../lib/utils';
import { Zap, Heart, Gavel, Layers, Clock } from 'lucide-react';

export const CommandCenter: React.FC = () => {
  const { fsmState, progress, epic, duration } = useStore();
  const [stats, setStats] = useState({ queue: 3, health: 92, decisions: 1 });

  return (
    <div className="h-full flex flex-col items-center justify-center p-8 relative overflow-hidden">
      {/* Background Ambient Glow */}
      <div 
        className="absolute inset-0 pointer-events-none transition-colors duration-1000 opacity-20"
        style={{ 
          background: `radial-gradient(circle at 50% 50%, ${stateColors[fsmState]}, transparent 70%)` 
        }}
      />

      {/* Central Radial Element */}
      <div className="relative z-10 flex flex-col items-center">
        <div className="relative w-80 h-80 flex items-center justify-center">
          {/* Animated Rings */}
          <svg className="absolute inset-0 w-full h-full -rotate-90">
            <circle
              cx="160"
              cy="160"
              r="140"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              className="text-white/5"
            />
            <motion.circle
              cx="160"
              cy="160"
              r="140"
              fill="none"
              stroke="currentColor"
              strokeWidth="4"
              strokeDasharray="880"
              initial={{ strokeDashoffset: 880 }}
              animate={{ strokeDashoffset: 880 - (880 * progress) }}
              transition={{ duration: 1.5, ease: "easeOut" }}
              style={{ color: stateColors[fsmState] }}
              className="drop-shadow-[0_0_8px_currentColor]"
            />
          </svg>

          {/* Inner Content */}
          <div className="text-center space-y-2">
            <motion.span 
              key={fsmState}
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              className="block text-[10px] uppercase tracking-[0.3em] text-white/40 font-bold"
            >
              FSM State
            </motion.span>
            <motion.h1 
              key={fsmState + 'title'}
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              className="text-5xl font-bold tracking-tighter"
              style={{ 
                background: `linear-gradient(to bottom, white, ${stateColors[fsmState]})`,
                WebkitBackgroundClip: 'text',
                WebkitTextFillColor: 'transparent'
              }}
            >
              {fsmState}
            </motion.h1>
            <div className="flex items-center justify-center gap-2 mt-4">
              {[...Array(8)].map((_, i) => (
                <div 
                  key={i}
                  className={cn(
                    "w-1.5 h-1.5 rounded-full transition-all duration-500",
                    i < Math.floor(progress * 8) 
                      ? "bg-white scale-110 shadow-[0_0_8px_white]" 
                      : "bg-white/10"
                  )}
                />
              ))}
            </div>
          </div>
        </div>

        {/* Timeline Strip */}
        <div className="mt-16 w-full max-w-2xl bg-white/5 border border-white/5 rounded-full p-1 flex items-center gap-1 relative overflow-hidden glass">
          <div className="absolute left-4 text-[10px] font-mono text-white/20 uppercase tracking-widest">Start</div>
          <div className="flex-1 flex items-center justify-center gap-4 py-3">
            {[...Array(12)].map((_, i) => (
              <motion.div 
                key={i}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                transition={{ delay: i * 0.05 }}
                className={cn(
                  "w-2 h-2 rounded-full transition-colors",
                  i < 5 ? "bg-state-done" : i === 5 ? "bg-state-executing animate-pulse" : "bg-white/5"
                )}
              />
            ))}
          </div>
          <div className="absolute right-4 text-[10px] font-mono text-white/20 uppercase tracking-widest">End</div>
        </div>

        {/* Satellite Metrics */}
        <div className="mt-12 grid grid-cols-3 gap-6 w-full max-w-3xl">
          <SatelliteCard 
            icon={Layers} 
            label="Queue" 
            value={stats.queue} 
            color="var(--color-state-plan-ready)" 
          />
          <SatelliteCard 
            icon={Heart} 
            label="Health" 
            value={`${stats.health}%`} 
            color="var(--color-state-done)" 
          />
          <SatelliteCard 
            icon={Gavel} 
            label="Decisions" 
            value={stats.decisions} 
            color="var(--color-state-pm-approval)" 
            pulse={stats.decisions > 0}
          />
        </div>

        <div className="mt-8 flex items-center gap-6 text-white/40">
          <div className="flex items-center gap-2">
            <Zap size={14} className="text-state-executing" />
            <span className="text-xs font-mono">{epic || 'NO ACTIVE EPIC'}</span>
          </div>
          <div className="flex items-center gap-2">
            <Clock size={14} />
            <span className="text-xs font-mono">{duration || '--:--'}</span>
          </div>
        </div>
      </div>
    </div>
  );
};

interface SatelliteCardProps {
  icon: any;
  label: string;
  value: string | number;
  color: string;
  pulse?: boolean;
}

const SatelliteCard: React.FC<SatelliteCardProps> = ({ icon: Icon, label, value, color, pulse }) => (
  <motion.div 
    whileHover={{ y: -4, backgroundColor: 'rgba(255,255,255,0.08)' }}
    className={cn(
      "glass p-4 rounded-2xl flex flex-col items-center gap-1 transition-all group cursor-pointer",
      pulse && "ring-1 ring-offset-2 ring-offset-bg-base ring-state-pm-approval/50 animate-pulse-subtle"
    )}
  >
    <Icon size={18} style={{ color }} className="mb-1" />
    <span className="text-[10px] uppercase tracking-widest text-white/40 font-bold">{label}</span>
    <span className="text-xl font-bold tracking-tight">{value}</span>
  </motion.div>
);
