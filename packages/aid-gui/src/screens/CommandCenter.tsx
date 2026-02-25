import React from 'react';
import { motion } from 'motion/react';
import { useStore, stateColors } from '../store';
import { cn } from '../lib/utils';
import { Zap, Heart, Gavel, Layers, Clock, WifiOff } from 'lucide-react';

export const CommandCenter: React.FC = () => {
  const { fsmState, progress, epic, duration } = useStore();
  const wsStatus = useStore((s) => s.wsStatus);
  const queueCount = useStore((s) => s.queueCount);
  const healthScore = useStore((s) => s.healthScore);
  const pendingDecisions = useStore((s) => s.pendingDecisions);
  const currentEpicId = useStore((s) => s.currentEpicId);

  const isLoading = wsStatus === 'connecting';
  const isDisconnected = wsStatus === 'disconnected';
  const isReconnecting = wsStatus === 'reconnecting';

  // Prefer the pipeline-slice epicId, fall back to legacy epic
  const displayEpic = currentEpicId || epic || null;

  return (
    <div className="h-full flex flex-col items-center justify-center p-8 relative overflow-hidden">
      {/* Background Ambient Glow */}
      <div
        className="absolute inset-0 pointer-events-none transition-colors duration-1000 opacity-20"
        style={{
          background: `radial-gradient(circle at 50% 50%, ${stateColors[fsmState]}, transparent 70%)`
        }}
      />

      {/* Disconnected / Reconnecting Banner */}
      {(isDisconnected || isReconnecting) && (
        <div className="absolute top-4 left-1/2 -translate-x-1/2 z-20 flex items-center gap-2 px-4 py-2 bg-red-500/10 border border-red-500/20 rounded-full backdrop-blur-sm">
          <WifiOff size={14} className="text-red-400" />
          <span className="text-xs text-red-400/80 font-mono">
            {isDisconnected ? 'Connection lost' : 'Reconnecting...'}
          </span>
          {isDisconnected && (
            <button
              onClick={() => window.location.reload()}
              className="text-xs text-red-300 underline underline-offset-2 hover:text-red-200 transition-colors"
            >
              Retry
            </button>
          )}
        </div>
      )}

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
            {isLoading ? (
              <div className="flex flex-col items-center gap-2">
                <div className="h-12 w-48 bg-white/5 rounded animate-pulse" />
              </div>
            ) : (
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
            )}
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
          {isLoading ? (
            <>
              <SatelliteCardSkeleton />
              <SatelliteCardSkeleton />
              <SatelliteCardSkeleton />
            </>
          ) : (
            <>
              <SatelliteCard
                icon={Layers}
                label="Queue"
                value={queueCount}
                color="var(--color-state-plan-ready)"
              />
              <SatelliteCard
                icon={Heart}
                label="Health"
                value={healthScore !== null ? `${healthScore}%` : '--'}
                color="var(--color-state-done)"
              />
              <SatelliteCard
                icon={Gavel}
                label="Decisions"
                value={pendingDecisions}
                color="var(--color-state-pm-approval)"
                pulse={pendingDecisions > 0}
              />
            </>
          )}
        </div>

        <div className="mt-8 flex items-center gap-6 text-white/40">
          <div className="flex items-center gap-2">
            <Zap size={14} className="text-state-executing" />
            {isLoading ? (
              <div className="h-4 w-32 bg-white/5 rounded animate-pulse" />
            ) : (
              <span className="text-xs font-mono">{displayEpic || 'NO ACTIVE EPIC'}</span>
            )}
          </div>
          <div className="flex items-center gap-2">
            <Clock size={14} />
            {isLoading ? (
              <div className="h-4 w-16 bg-white/5 rounded animate-pulse" />
            ) : (
              <span className="text-xs font-mono">{duration || '--:--'}</span>
            )}
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

const SatelliteCardSkeleton: React.FC = () => (
  <div className="glass p-4 rounded-2xl flex flex-col items-center gap-2">
    <div className="h-5 w-5 bg-white/5 rounded animate-pulse mb-1" />
    <div className="h-3 w-16 bg-white/5 rounded animate-pulse" />
    <div className="h-6 w-10 bg-white/5 rounded animate-pulse" />
  </div>
);
