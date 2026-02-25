import React, { useEffect, useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { useStore, stateColors } from '../store';
import { cn } from '../lib/utils';
import { 
  User, 
  Database, 
  Layout, 
  ShieldCheck, 
  FileText, 
  CheckCircle2, 
  Clock, 
  ChevronRight,
  Play,
  Pause,
  RotateCcw
} from 'lucide-react';

interface Step {
  id: string;
  label: string;
  role: string;
  status: 'completed' | 'active' | 'pending' | 'failed' | 'skipped';
  duration?: string;
}

const roleIcons: Record<string, any> = {
  architect: User,
  backend: Database,
  frontend: Layout,
  security: ShieldCheck,
  docs: FileText,
};

export const PipelineTheater: React.FC = () => {
  const [steps, setSteps] = useState<Step[]>([]);
  const { fsmState, progress } = useStore();
  const [selectedStep, setSelectedStep] = useState<Step | null>(null);

  useEffect(() => {
    fetch('/api/pipeline/steps')
      .then(res => res.json())
      .then(setSteps);
  }, []);

  return (
    <div className="h-full flex flex-col p-8 relative">
      <div className="flex items-center justify-between mb-12">
        <div>
          <h2 className="text-2xl font-bold tracking-tight">Pipeline Theater</h2>
          <p className="text-sm text-white/40">Visualizing the river of orchestration</p>
        </div>
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-2 px-4 py-2 bg-white/5 rounded-full border border-white/5">
            <div className="w-2 h-2 rounded-full bg-state-executing animate-pulse" />
            <span className="text-xs font-mono uppercase tracking-widest">Live Execution</span>
          </div>
        </div>
      </div>

      {/* River Flow Visualization */}
      <div className="flex-1 flex items-center justify-center relative overflow-x-auto min-h-[400px]">
        {/* Animated River SVG Background */}
        <svg className="absolute inset-0 w-full h-full pointer-events-none" preserveAspectRatio="none">
          <defs>
            <linearGradient id="riverGrad" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stopColor="var(--color-state-executing)" stopOpacity="0" />
              <stop offset="50%" stopColor="var(--color-state-executing)" stopOpacity="0.1" />
              <stop offset="100%" stopColor="var(--color-state-executing)" stopOpacity="0" />
            </linearGradient>
            <filter id="glow">
              <feGaussianBlur stdDeviation="4" result="coloredBlur"/>
              <feMerge>
                <feMergeNode in="coloredBlur"/>
                <feMergeNode in="SourceGraphic"/>
              </feMerge>
            </filter>
          </defs>
          <motion.path 
            d="M 0,200 Q 200,180 400,200 T 800,200 T 1200,200" 
            fill="none" 
            stroke="url(#riverGrad)" 
            strokeWidth="40" 
            filter="url(#glow)"
            animate={{ d: ["M 0,200 Q 200,180 400,200 T 800,200 T 1200,200", "M 0,200 Q 200,220 400,200 T 800,200 T 1200,200", "M 0,200 Q 200,180 400,200 T 800,200 T 1200,200"] }}
            transition={{ duration: 4, repeat: Infinity, ease: "easeInOut" }}
          />
          {/* Particles */}
          {[...Array(5)].map((_, i) => (
            <motion.circle
              key={i}
              r="2"
              fill="var(--color-state-executing)"
              initial={{ cx: 0, cy: 200, opacity: 0 }}
              animate={{ cx: 1200, cy: 200, opacity: [0, 1, 0] }}
              transition={{ duration: 3, repeat: Infinity, delay: i * 0.6, ease: "linear" }}
            />
          ))}
        </svg>

        <div className="flex items-center gap-16 px-20 relative z-10">
          {steps.map((step, index) => (
            <React.Fragment key={step.id}>
              {/* Step Island */}
              <motion.div
                initial={{ opacity: 0, x: -20 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: index * 0.1 }}
                onClick={() => setSelectedStep(step)}
                className={cn(
                  "relative group cursor-pointer",
                  step.status === 'active' && "animate-pulse-subtle"
                )}
              >
                <div className={cn(
                  "w-20 h-20 rounded-3xl flex items-center justify-center transition-all duration-500 border-2",
                  step.status === 'completed' ? "bg-state-done/20 border-state-done shadow-[0_0_15px_rgba(34,197,94,0.3)]" :
                  step.status === 'active' ? "bg-state-executing/20 border-state-executing shadow-[0_0_20px_rgba(0,180,216,0.4)]" :
                  "bg-white/5 border-white/10 opacity-40"
                )}>
                  {roleIcons[step.role] ? React.createElement(roleIcons[step.role], { size: 32 }) : <User size={32} />}
                </div>
                
                <div className="absolute -bottom-8 left-1/2 -translate-x-1/2 whitespace-nowrap text-center">
                  <div className="text-[10px] font-bold uppercase tracking-widest text-white/40 mb-0.5">{step.role}</div>
                  <div className="text-xs font-medium">{step.label}</div>
                </div>

                {step.duration && (
                  <div className="absolute -top-6 left-1/2 -translate-x-1/2 bg-white/10 px-2 py-0.5 rounded text-[10px] font-mono text-white/60">
                    {step.duration}
                  </div>
                )}
              </motion.div>

              {/* Connector / Water Flow */}
              {index < steps.length - 1 && (
                <div className="w-16 h-1 bg-white/5 relative overflow-hidden rounded-full">
                  <motion.div 
                    className="absolute inset-0 bg-gradient-to-r from-transparent via-white/20 to-transparent"
                    animate={{ x: ['-100%', '100%'] }}
                    transition={{ duration: 2, repeat: Infinity, ease: "linear" }}
                  />
                  {step.status === 'completed' && (
                    <div className="absolute inset-0 bg-state-done/40" />
                  )}
                </div>
              )}
            </React.Fragment>
          ))}

          {/* Final Gate */}
          <div className="ml-8 flex flex-col items-center gap-4 opacity-40">
            <div className="w-16 h-32 border-2 border-dashed border-white/20 rounded-2xl flex flex-col items-center justify-center gap-4">
              <div className="w-8 h-8 rounded-lg bg-white/5" />
              <div className="w-8 h-8 rounded-lg bg-white/5" />
            </div>
            <span className="text-[10px] font-bold uppercase tracking-widest text-white/20">Quality Gates</span>
          </div>
        </div>
      </div>

      {/* Controls Bar */}
      <div className="mt-auto bg-surface-1/50 backdrop-blur-xl border border-white/5 rounded-2xl p-4 flex items-center gap-6">
        <div className="flex items-center gap-2">
          <button className="p-2 rounded-lg hover:bg-white/10 transition-colors text-white/40 hover:text-white" title="Restart Run">
            <RotateCcw size={18} />
          </button>
          <button className="p-2 rounded-lg bg-white/10 hover:bg-white/20 transition-colors text-white" title="Play/Pause Replay">
            {fsmState === 'IDLE' ? <Play size={18} fill="currentColor" /> : <Pause size={18} fill="currentColor" />}
          </button>
          <div className="flex items-center gap-1 ml-2 px-2 border-l border-white/10">
            <button className="p-1 rounded hover:bg-white/10 text-[10px] font-mono text-white/40 hover:text-white">1x</button>
            <button className="p-1 rounded hover:bg-white/10 text-[10px] font-mono text-white/40 hover:text-white">2x</button>
            <button className="p-1 rounded hover:bg-white/10 text-[10px] font-mono text-white/40 hover:text-white">4x</button>
          </div>
        </div>
        
        <div className="flex-1 space-y-2">
          <div className="flex justify-between text-[10px] font-mono text-white/40 uppercase tracking-widest">
            <span>Overall Progress</span>
            <span>{Math.round(progress * 100)}%</span>
          </div>
          <div className="h-1.5 w-full bg-white/5 rounded-full overflow-hidden">
            <motion.div 
              className="h-full bg-state-executing shadow-[0_0_10px_rgba(0,180,216,0.5)]"
              animate={{ width: `${progress * 100}%` }}
            />
          </div>
        </div>

        <div className="text-right">
          <div className="text-[10px] font-mono text-white/40 uppercase tracking-widest">Est. Remaining</div>
          <div className="text-sm font-bold">~14m 20s</div>
        </div>
      </div>

      {/* Step Detail Panel */}
      <AnimatePresence>
        {selectedStep && (
          <>
            <motion.div 
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setSelectedStep(null)}
              className="absolute inset-0 bg-bg-base/60 backdrop-blur-sm z-40"
            />
            <motion.div
              initial={{ x: '100%' }}
              animate={{ x: 0 }}
              exit={{ x: '100%' }}
              transition={{ type: 'spring', damping: 25, stiffness: 200 }}
              className="absolute top-0 right-0 h-full w-96 bg-surface-2 border-l border-white/10 z-50 p-6 shadow-2xl"
            >
              <div className="flex items-center justify-between mb-8">
                <div className="flex items-center gap-3">
                  <div className="p-2 rounded-xl bg-white/5 border border-white/10">
                    {roleIcons[selectedStep.role] ? React.createElement(roleIcons[selectedStep.role], { size: 20 }) : <User size={20} />}
                  </div>
                  <div>
                    <h3 className="font-bold">{selectedStep.label}</h3>
                    <p className="text-[10px] uppercase tracking-widest text-white/40">{selectedStep.role}</p>
                  </div>
                </div>
                <button 
                  onClick={() => setSelectedStep(null)}
                  className="p-2 hover:bg-white/5 rounded-lg transition-colors"
                >
                  <ChevronRight size={20} />
                </button>
              </div>

              <div className="space-y-6">
                <section>
                  <h4 className="text-[10px] font-bold uppercase tracking-widest text-white/40 mb-3">Status</h4>
                  <div className="flex items-center gap-2">
                    <div className={cn(
                      "w-2 h-2 rounded-full",
                      selectedStep.status === 'completed' ? "bg-state-done" :
                      selectedStep.status === 'active' ? "bg-state-executing animate-pulse" :
                      "bg-white/20"
                    )} />
                    <span className="text-sm capitalize">{selectedStep.status}</span>
                  </div>
                </section>

                <section>
                  <h4 className="text-[10px] font-bold uppercase tracking-widest text-white/40 mb-3">Agent Output</h4>
                  <div className="bg-white/5 rounded-xl p-4 font-mono text-xs leading-relaxed text-white/60">
                    {selectedStep.status === 'pending' ? 'Waiting for dispatch...' : 
                     selectedStep.status === 'active' ? 'Processing instructions and generating code artifacts...' :
                     'Successfully implemented the requested changes. Verified with unit tests.'}
                  </div>
                </section>

                {selectedStep.duration && (
                  <section>
                    <h4 className="text-[10px] font-bold uppercase tracking-widest text-white/40 mb-3">Timing</h4>
                    <div className="flex items-center gap-2 text-sm">
                      <Clock size={14} className="text-white/40" />
                      <span>{selectedStep.duration} total duration</span>
                    </div>
                  </section>
                )}
              </div>

              <button className="absolute bottom-6 left-6 right-6 py-3 bg-white/5 hover:bg-white/10 border border-white/10 rounded-xl text-sm font-medium transition-all">
                View in Evidence Vault
              </button>
            </motion.div>
          </>
        )}
      </AnimatePresence>
    </div>
  );
};
