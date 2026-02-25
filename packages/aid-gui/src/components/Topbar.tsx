import React, { useState } from 'react';
import { Search, Bell, Settings, Sparkles, Mic, Zap } from 'lucide-react';
import { useStore } from '../store';
import { cn } from '../lib/utils';

interface TopbarProps {
  onSearchClick: () => void;
}

/**
 * Map wsStatus to a colored dot and tooltip label for the connection indicator.
 */
const connectionIndicator: Record<string, { color: string; label: string }> = {
  connected:    { color: 'bg-green-400',  label: 'Connected' },
  connecting:   { color: 'bg-gray-400',   label: 'Connecting...' },
  reconnecting: { color: 'bg-yellow-400', label: 'Reconnecting...' },
  disconnected: { color: 'bg-red-400',    label: 'Disconnected' },
};

export const Topbar: React.FC<TopbarProps> = ({ onSearchClick }) => {
  const { currentProject, fsmState } = useStore();
  const wsStatus = useStore((s) => s.wsStatus);
  const ccUsage = useStore((s) => s.ccUsage);
  const [isSearchFocused, setIsSearchFocused] = useState(false);

  const indicator = connectionIndicator[wsStatus] ?? connectionIndicator.disconnected;

  // Derive a usage display from the CC usage metrics.
  // totalEvents is the primary counter; we show it against a soft cap for context.
  const totalEvents = ccUsage.totalEvents;
  const usageCap = 100_000;
  const usagePercent = Math.min(100, Math.round((totalEvents / usageCap) * 100));

  // Format large numbers with 'k' suffix for compactness
  const formatCount = (n: number): string => {
    if (n >= 1000) {
      const k = n / 1000;
      return k % 1 === 0 ? `${k}k` : `${k.toFixed(1)}k`;
    }
    return String(n);
  };

  return (
    <header className="fixed top-0 right-0 left-0 h-14 bg-bg-base/80 backdrop-blur-md border-b border-white/5 z-30 flex items-center justify-between px-6 ml-16 md:ml-0 pl-[inherit]">
      <div className="flex items-center gap-4">
        {/* Project selector with connection status indicator */}
        <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-white/5 border border-white/5 hover:bg-white/10 cursor-pointer transition-colors">
          <div
            className={cn(
              "w-2 h-2 rounded-full transition-colors duration-300",
              indicator.color,
              wsStatus === 'connected' && "animate-pulse",
              wsStatus === 'reconnecting' && "animate-pulse"
            )}
            title={indicator.label}
          />
          <span className="text-xs font-medium">{currentProject?.name || 'Select Project'}</span>
        </div>

        {/* CC Usage Gauge */}
        <div className="hidden lg:flex items-center gap-3 px-3 py-1.5 rounded-full bg-white/5 border border-white/5">
          <Zap size={14} className="text-state-executing" />
          <div className="flex flex-col">
            <div className="flex items-center justify-between gap-4">
              <span className="text-[10px] font-bold uppercase tracking-widest text-white/40">CC Usage</span>
              {wsStatus === 'connecting' ? (
                <div className="h-3 w-20 bg-white/5 rounded animate-pulse" />
              ) : (
                <span className="text-[10px] font-mono text-white/60">
                  {formatCount(totalEvents)} / {formatCount(usageCap)}
                </span>
              )}
            </div>
            <div className="w-24 h-1 bg-white/10 rounded-full overflow-hidden mt-0.5">
              {wsStatus === 'connecting' ? (
                <div className="h-full w-0" />
              ) : (
                <div
                  className={cn(
                    "h-full transition-all duration-500",
                    usagePercent > 80 ? "bg-red-400" : usagePercent > 60 ? "bg-yellow-400" : "bg-state-executing"
                  )}
                  style={{ width: `${usagePercent}%` }}
                />
              )}
            </div>
          </div>
        </div>

        {/* Connection status text for small screens or when disconnected */}
        {(wsStatus === 'disconnected' || wsStatus === 'reconnecting') && (
          <div className="hidden md:flex items-center gap-1.5">
            <span className={cn(
              "w-1.5 h-1.5 rounded-full",
              wsStatus === 'disconnected' ? "bg-red-400" : "bg-yellow-400"
            )} />
            <span className="text-xs text-white/40 font-mono">
              {wsStatus === 'disconnected' ? 'Connection lost' : 'Reconnecting...'}
            </span>
          </div>
        )}
      </div>

      <div className={cn(
        "flex-1 max-w-xl mx-8 transition-all duration-300 relative",
        isSearchFocused ? "max-w-2xl" : "max-w-md"
      )}>
        <div className="relative group">
          <div className="absolute left-3 top-1/2 -translate-y-1/2 text-white/20 group-focus-within:text-state-executing transition-colors">
            <Sparkles size={16} />
          </div>
          <input
            type="text"
            placeholder="Ask AI Companion (Cmd+K)..."
            onClick={onSearchClick}
            readOnly
            className="w-full bg-white/5 border border-white/10 rounded-full py-2 pl-10 pr-10 text-sm focus:outline-none focus:border-state-executing/50 focus:bg-white/10 transition-all cursor-pointer placeholder:text-white/20"
          />
          <div className="absolute right-3 top-1/2 -translate-y-1/2 flex items-center gap-2">
            <button className="p-1 hover:bg-white/10 rounded text-white/40 hover:text-white transition-colors">
              <Mic size={14} />
            </button>
            <div className="text-[10px] font-mono bg-white/10 px-1.5 py-0.5 rounded text-white/40">⌘K</div>
          </div>
        </div>
      </div>

      <div className="flex items-center gap-3">
        <button className="p-2 rounded-xl hover:bg-white/5 text-white/40 hover:text-white transition-colors relative">
          <Bell size={20} />
          <div className="absolute top-2 right-2 w-2 h-2 bg-state-pm-approval rounded-full border-2 border-bg-base" />
        </button>
        <button className="p-2 rounded-xl hover:bg-white/5 text-white/40 hover:text-white transition-colors">
          <Settings size={20} />
        </button>
      </div>
    </header>
  );
};
