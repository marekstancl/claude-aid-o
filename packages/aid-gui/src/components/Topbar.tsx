import React, { useState, useEffect } from 'react';
import { Search, Bell, Settings, Sparkles, Mic, Zap } from 'lucide-react';
import { useStore } from '../store';
import { cn } from '../lib/utils';

interface TopbarProps {
  onSearchClick: () => void;
}

export const Topbar: React.FC<TopbarProps> = ({ onSearchClick }) => {
  const { currentProject, fsmState } = useStore();
  const [isSearchFocused, setIsSearchFocused] = useState(false);

  return (
    <header className="fixed top-0 right-0 left-0 h-14 bg-bg-base/80 backdrop-blur-md border-b border-white/5 z-30 flex items-center justify-between px-6 ml-16 md:ml-0 pl-[inherit]">
      <div className="flex items-center gap-4">
        <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-white/5 border border-white/5 hover:bg-white/10 cursor-pointer transition-colors">
          <div className="w-2 h-2 rounded-full bg-state-done animate-pulse" />
          <span className="text-xs font-medium">{currentProject?.name || 'Select Project'}</span>
        </div>
        
        {/* CC Usage Gauge */}
        <div className="hidden lg:flex items-center gap-3 px-3 py-1.5 rounded-full bg-white/5 border border-white/5">
          <Zap size={14} className="text-state-executing" />
          <div className="flex flex-col">
            <div className="flex items-center justify-between gap-4">
              <span className="text-[10px] font-bold uppercase tracking-widest text-white/40">CC Usage</span>
              <span className="text-[10px] font-mono text-white/60">42k / 100k</span>
            </div>
            <div className="w-24 h-1 bg-white/10 rounded-full overflow-hidden mt-0.5">
              <div className="h-full bg-state-executing" style={{ width: '42%' }} />
            </div>
          </div>
        </div>
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
