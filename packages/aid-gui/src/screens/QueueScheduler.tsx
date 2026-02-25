import React from 'react';
import { motion } from 'motion/react';
import { Clock, GripVertical, AlertCircle, Play, Settings, Zap, TrendingUp, AlertTriangle } from 'lucide-react';
import { ResponsiveContainer, AreaChart, Area } from 'recharts';
import { cn } from '../lib/utils';

export const QueueScheduler: React.FC = () => {
  const queuedEpics = [
    { id: 'E-006', title: 'Payment Gateway Integration', duration: '2h 30m', status: 'next' },
    { id: 'E-007', title: 'User Profile Redesign', duration: '1h 15m', status: 'queued' },
    { id: 'E-008', title: 'Email Notification System', duration: '45m', status: 'queued' },
  ];

  return (
    <div className="h-full flex flex-col p-8 overflow-y-auto custom-scrollbar">
      <div className="flex items-center justify-between mb-8">
        <div>
          <h2 className="text-2xl font-bold tracking-tight">Queue Scheduler</h2>
          <p className="text-sm text-white/40">Manage and sequence upcoming EPICs</p>
        </div>
        <div className="flex items-center gap-4">
          <div className="glass px-4 py-2 rounded-xl flex items-center gap-3">
            <div className="flex flex-col">
              <span className="text-[10px] font-bold uppercase tracking-widest text-white/40">Est. Queue Time</span>
              <span className="text-sm font-mono font-bold">4h 30m</span>
            </div>
          </div>
        </div>
      </div>

      <div className="flex-1 flex flex-col gap-6">
        {/* Timeline View */}
        <div className="glass p-6 rounded-[2rem] border border-white/5 relative overflow-hidden flex-shrink-0">
          <h3 className="text-[10px] font-bold uppercase tracking-widest text-white/40 mb-6">Execution Timeline</h3>
          
          <div className="relative h-32 w-full">
            {/* Time markers */}
            <div className="absolute top-0 left-0 w-full flex justify-between text-[10px] font-mono text-white/20 px-4">
              <span>Now</span>
              <span>+1h</span>
              <span>+2h</span>
              <span>+3h</span>
              <span>+4h</span>
            </div>
            
            {/* Timeline track */}
            <div className="absolute top-8 left-4 right-4 h-16 bg-white/5 rounded-xl overflow-hidden flex">
              {/* Active EPIC */}
              <div className="h-full bg-state-executing/20 border-r border-state-executing/50 flex items-center justify-center relative group cursor-pointer" style={{ width: '20%' }}>
                <div className="absolute inset-0 bg-state-executing/10 animate-pulse" />
                <span className="text-xs font-bold text-state-executing z-10">E-005</span>
                
                {/* Tooltip */}
                <div className="absolute bottom-full mb-2 opacity-0 group-hover:opacity-100 transition-opacity bg-surface-2 border border-white/10 px-3 py-2 rounded-lg text-xs whitespace-nowrap z-20 pointer-events-none">
                  <div className="font-bold text-state-executing">E-005: Auth System Refactor</div>
                  <div className="text-white/60">Running (65%)</div>
                </div>
              </div>
              
              {/* Cooldown Gap */}
              <div className="h-full bg-transparent border-r border-white/10 flex items-center justify-center relative" style={{ width: '5%' }}>
                <span className="text-[8px] font-mono text-white/40 rotate-[-90deg] whitespace-nowrap">30m</span>
              </div>
              
              {/* Queued EPICs */}
              <div className="h-full bg-white/10 border-r border-white/20 flex items-center justify-center relative group cursor-pointer hover:bg-white/15 transition-colors" style={{ width: '35%' }}>
                <span className="text-xs font-bold text-white/60">E-006</span>
                <div className="absolute bottom-full mb-2 opacity-0 group-hover:opacity-100 transition-opacity bg-surface-2 border border-white/10 px-3 py-2 rounded-lg text-xs whitespace-nowrap z-20 pointer-events-none">
                  <div className="font-bold">E-006: Payment Gateway Integration</div>
                  <div className="text-white/60">Est: 2h 30m</div>
                </div>
              </div>
              
              <div className="h-full bg-transparent border-r border-white/10 flex items-center justify-center relative" style={{ width: '5%' }}>
                <span className="text-[8px] font-mono text-white/40 rotate-[-90deg] whitespace-nowrap">30m</span>
              </div>
              
              <div className="h-full bg-white/10 border-r border-white/20 flex items-center justify-center relative group cursor-pointer hover:bg-white/15 transition-colors" style={{ width: '20%' }}>
                <span className="text-xs font-bold text-white/60">E-007</span>
                <div className="absolute bottom-full mb-2 opacity-0 group-hover:opacity-100 transition-opacity bg-surface-2 border border-white/10 px-3 py-2 rounded-lg text-xs whitespace-nowrap z-20 pointer-events-none">
                  <div className="font-bold">E-007: User Profile Redesign</div>
                  <div className="text-white/60">Est: 1h 15m</div>
                </div>
              </div>
            </div>
            
            {/* "Now" indicator line */}
            <div className="absolute top-4 bottom-0 left-[24%] w-px bg-state-executing shadow-[0_0_8px_rgba(0,180,216,0.8)] z-10">
              <div className="absolute -top-1 -left-1 w-2 h-2 rounded-full bg-state-executing" />
            </div>
          </div>
        </div>

        {/* Bottom Section: Queue List & Settings */}
        <div className="flex-1 flex gap-6 min-h-0">
          {/* Queue List */}
          <div className="flex-[2] glass p-6 rounded-[2rem] border border-white/5 flex flex-col">
            <div className="flex items-center justify-between mb-6">
              <h3 className="text-[10px] font-bold uppercase tracking-widest text-white/40">Up Next</h3>
              <button className="text-xs font-medium text-state-executing hover:underline flex items-center gap-1">
                <Play size={12} /> Force Start Next
              </button>
            </div>
            
            <div className="flex-1 space-y-3 overflow-y-auto custom-scrollbar pr-2">
              {queuedEpics.map((epic, index) => (
                <motion.div
                  key={epic.id}
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: index * 0.1 }}
                  className={cn(
                    "flex items-center gap-4 p-4 rounded-xl border transition-all cursor-grab active:cursor-grabbing group",
                    epic.status === 'next' 
                      ? "bg-white/10 border-white/20 shadow-lg" 
                      : "bg-white/5 border-white/5 hover:bg-white/10 hover:border-white/10"
                  )}
                >
                  <div className="text-white/20 group-hover:text-white/40 transition-colors">
                    <GripVertical size={20} />
                  </div>
                  
                  <div className="flex-1 flex items-center justify-between">
                    <div className="flex items-center gap-4">
                      <div className={cn(
                        "px-2 py-1 rounded text-[10px] font-bold uppercase tracking-widest",
                        epic.status === 'next' ? "bg-state-executing/20 text-state-executing" : "bg-white/10 text-white/40"
                      )}>
                        {epic.id}
                      </div>
                      <div>
                        <h4 className="font-bold text-sm">{epic.title}</h4>
                        {epic.status === 'next' && (
                          <div className="text-[10px] text-state-executing mt-0.5 flex items-center gap-1">
                            <AlertCircle size={10} /> Next to execute
                          </div>
                        )}
                      </div>
                    </div>
                    
                    <div className="flex items-center gap-6">
                      <div className="flex items-center gap-2 text-white/40">
                        <Clock size={14} />
                        <span className="text-xs font-mono">{epic.duration}</span>
                      </div>
                      <button className="opacity-0 group-hover:opacity-100 p-2 hover:bg-white/10 rounded-lg transition-all text-white/40 hover:text-white">
                        Edit
                      </button>
                    </div>
                  </div>
                </motion.div>
              ))}
            </div>
          </div>

          {/* Right Column: Settings & CC Usage */}
          <div className="flex-1 flex flex-col gap-6">
            {/* Queue Settings */}
            <div className="glass p-6 rounded-[2rem] border border-white/5">
              <div className="flex items-center gap-2 mb-6">
                <Settings size={16} className="text-white/40" />
                <h3 className="text-[10px] font-bold uppercase tracking-widest text-white/40">Queue Settings</h3>
              </div>

              <div className="space-y-4">
                <div className="flex items-center justify-between">
                  <span className="text-sm text-white/60">Cooldown between EPICs</span>
                  <select className="bg-white/5 border border-white/10 rounded-lg px-3 py-1.5 text-xs focus:outline-none focus:border-white/20">
                    <option value="15">15 min</option>
                    <option value="30" selected>30 min</option>
                    <option value="60">1 hour</option>
                    <option value="120">2 hours</option>
                  </select>
                </div>
                
                <div className="flex items-center justify-between">
                  <span className="text-sm text-white/60">Max concurrent EPICs</span>
                  <select className="bg-white/5 border border-white/10 rounded-lg px-3 py-1.5 text-xs focus:outline-none focus:border-white/20">
                    <option value="1" selected>1</option>
                    <option value="2">2</option>
                    <option value="3">3</option>
                  </select>
                </div>

                <div className="flex items-center justify-between">
                  <span className="text-sm text-white/60">Auto-pause at CC limit</span>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input type="checkbox" className="sr-only peer" defaultChecked />
                    <div className="w-9 h-5 bg-white/10 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:bg-state-executing"></div>
                  </label>
                </div>

                <div className="flex items-center justify-between">
                  <span className="text-sm text-white/60">Start time</span>
                  <input type="datetime-local" className="bg-white/5 border border-white/10 rounded-lg px-3 py-1.5 text-xs focus:outline-none focus:border-white/20 text-white/60" />
                </div>

                <button className="w-full mt-4 bg-state-executing hover:bg-state-executing/90 text-bg-base font-bold py-3 rounded-xl transition-all shadow-lg shadow-state-executing/20 flex items-center justify-center gap-2">
                  <Play size={16} fill="currentColor" /> LAUNCH QUEUE
                </button>
              </div>
            </div>

            {/* CC Usage Detail */}
            <div className="glass p-6 rounded-[2rem] border border-white/5 flex-1 flex flex-col">
              <div className="flex items-center justify-between mb-4">
                <div className="flex items-center gap-2">
                  <Zap size={16} className="text-state-pm-approval" />
                  <h3 className="text-[10px] font-bold uppercase tracking-widest text-white/40">CC Usage</h3>
                </div>
                <div className="px-2 py-0.5 rounded bg-state-pm-approval/20 text-state-pm-approval text-[10px] font-bold uppercase tracking-widest flex items-center gap-1">
                  <AlertTriangle size={10} /> Warning
                </div>
              </div>

              <div className="mb-6">
                <div className="flex items-end justify-between mb-2">
                  <span className="text-3xl font-bold tracking-tight">74k</span>
                  <span className="text-sm text-white/40 mb-1">/ 100k tokens</span>
                </div>
                <div className="h-2 w-full bg-white/5 rounded-full overflow-hidden">
                  <div className="h-full bg-state-pm-approval" style={{ width: '74%' }} />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4 mb-6">
                <div className="bg-white/5 rounded-xl p-3 border border-white/5">
                  <div className="text-[10px] font-bold uppercase tracking-widest text-white/40 mb-1">Est. Remaining</div>
                  <div className="text-lg font-medium">~2 EPICs</div>
                </div>
                <div className="bg-white/5 rounded-xl p-3 border border-white/5">
                  <div className="text-[10px] font-bold uppercase tracking-widest text-white/40 mb-1">Avg. Cost</div>
                  <div className="text-lg font-medium">12k / EPIC</div>
                </div>
              </div>

              <div className="flex-1 flex flex-col justify-end">
                <div className="flex items-center gap-2 text-white/40 mb-2">
                  <TrendingUp size={12} />
                  <span className="text-[10px] font-bold uppercase tracking-widest">7-Day Trend</span>
                </div>
                <div className="h-16 w-full">
                  <ResponsiveContainer width="100%" height="100%">
                    <AreaChart data={[
                      { day: '1', tokens: 10 },
                      { day: '2', tokens: 25 },
                      { day: '3', tokens: 30 },
                      { day: '4', tokens: 45 },
                      { day: '5', tokens: 50 },
                      { day: '6', tokens: 65 },
                      { day: '7', tokens: 74 },
                    ]}>
                      <defs>
                        <linearGradient id="colorTokens" x1="0" y1="0" x2="0" y2="1">
                          <stop offset="5%" stopColor="var(--color-state-pm-approval)" stopOpacity={0.3}/>
                          <stop offset="95%" stopColor="var(--color-state-pm-approval)" stopOpacity={0}/>
                        </linearGradient>
                      </defs>
                      <Area type="monotone" dataKey="tokens" stroke="var(--color-state-pm-approval)" fillOpacity={1} fill="url(#colorTokens)" />
                    </AreaChart>
                  </ResponsiveContainer>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
