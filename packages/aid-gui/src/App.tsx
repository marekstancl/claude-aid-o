import React, { useState, useEffect, useRef } from 'react';
import { Routes, Route } from 'react-router';
import { Sidebar } from './components/Sidebar';
import { Topbar } from './components/Topbar';
import { useStore } from './store';
import { motion, AnimatePresence } from 'motion/react';

import { CommandCenter } from './screens/CommandCenter';

import { ActivityStream } from './screens/ActivityStream';
import { DecisionHub } from './screens/DecisionHub';
import { EvidenceVault } from './screens/EvidenceVault';
import { HealthObservatory } from './screens/HealthObservatory';
import { IdeasToExecution } from './screens/IdeasToExecution';
import { QueueScheduler } from './screens/QueueScheduler';
import { KnowledgeBase } from './screens/KnowledgeBase';
import { EpicLifecycle } from './screens/EpicLifecycle';

import { useNavigate } from 'react-router';
import { AICompanion } from './components/AICompanion';
import { ErrorBoundary } from './components/ErrorBoundary';
import { ToastProvider, useToast } from './components/Toast';
import { useWebSocket } from './hooks/useWebSocket';

const MOBILE_BREAKPOINT = 768;

export default function App() {
  const [isSidebarCollapsed, setIsSidebarCollapsed] = useState(false);
  const [isMobile, setIsMobile] = useState(() => window.innerWidth < MOBILE_BREAKPOINT);
  const { setProject, fsmState, currentProject } = useStore();
  const isCompanionOpen = useStore((s) => s.companionOpen);
  const companionMode = useStore((s) => s.companionMode);
  const commandPaletteOpen = useStore((s) => s.commandPaletteOpen);
  const setCompanionOpen = useStore((s) => s.setCompanionOpen);
  const stepStatuses = useStore((s) => s.stepStatuses);
  const currentEpicId = useStore((s) => s.currentEpicId);
  const navigate = useNavigate();

  // Connect WebSocket — the hook manages connection lifecycle, reconnection,
  // and dispatches all incoming events to the Zustand store automatically.
  useWebSocket(currentProject?.id ?? null);

  const isAnyCompanionOpen = isCompanionOpen || commandPaletteOpen;

  // Dynamic tab title — show progress during active pipeline runs
  useEffect(() => {
    const entries = Object.values(stepStatuses);
    const total = entries.length;
    const done = entries.filter((s) => s.status === 'done' || s.status === 'skipped').length;
    const isActive = !['IDLE', 'DONE', 'FIRST_AID_COMPLETE', 'ERROR'].includes(fsmState);
    if (isActive && total > 0) {
      document.title = `⚡ ${done}/${total} — ${currentEpicId ?? 'EPIC'} — AID`;
    } else if (fsmState === 'DONE' || fsmState === 'FIRST_AID_COMPLETE') {
      document.title = '✅ Done — AID Dashboard';
    } else {
      document.title = 'AID Dashboard';
    }
  }, [fsmState, stepStatuses, currentEpicId]);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        const store = useStore.getState();
        if (store.commandPaletteOpen) {
          // Palette is open → close it
          store.setCommandPaletteOpen(false);
        } else {
          // Open palette — always reset to home (suggestions)
          store.setCompanionCurrentSession(null);
          store.resetCompanionStream();
          store.setCompanionError(null);
          store.setCommandPaletteOpen(true);
          store.setCompanionMode('palette');
        }
      }

      if (!isAnyCompanionOpen && !['INPUT', 'TEXTAREA'].includes((e.target as HTMLElement).tagName)) {
        if (e.key === '[') setIsSidebarCollapsed(prev => !prev);
        if (e.key === '1') navigate('/');
        if (e.key === '2') navigate('/epics');
        if (e.key === '3') navigate('/queue');
        if (e.key === '4') navigate('/activity');
        if (e.key === '5') navigate('/decisions');
        if (e.key === '6') navigate('/evidence');
        if (e.key === '7') navigate('/health');
        if (e.key === '8') navigate('/ideas');
        if (e.key === '9') navigate('/knowledge');
        if (e.key === '?') {
          // Help overlay placeholder
        }
        if (e.key === ' ') {
          e.preventDefault();
          // Play/Pause replay placeholder
        }
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isAnyCompanionOpen, navigate]);

  // Detect mobile viewport and auto-collapse sidebar
  useEffect(() => {
    const mediaQuery = window.matchMedia(`(max-width: ${MOBILE_BREAKPOINT - 1}px)`);

    const handleChange = (e: MediaQueryListEvent | MediaQueryList) => {
      const mobile = e.matches;
      setIsMobile(mobile);
      if (mobile) {
        setIsSidebarCollapsed(true);
      }
    };

    // Set initial state
    handleChange(mediaQuery);

    mediaQuery.addEventListener('change', handleChange);
    return () => mediaQuery.removeEventListener('change', handleChange);
  }, []);

  useEffect(() => {
    // Initial data fetch — API returns { ok, data } envelope
    fetch('/api/projects')
      .then(res => res.json())
      .then(result => {
        const projects = result.ok ? result.data : result;
        if (Array.isArray(projects) && projects.length > 0) {
          setProject(projects[0]);
          // Fetch pipeline state for the selected project
          fetch(`/api/p/${encodeURIComponent(projects[0].id)}/pipeline`)
            .then(r => r.json())
            .then(pResult => {
              if (pResult.ok && pResult.data) {
                const d = pResult.data;
                useStore.getState().updatePipeline({
                  fsmState: d.currentState,
                  progress: d.progress,
                  activeStep: d.currentStepId,
                  epic: d.currentEpicId,
                });
              }
            })
            .catch(() => {});
        }
      })
      .catch(() => {});
  }, [setProject]);

  return (
    <ToastProvider>
      <PipelineToasts />
      <div
        className="min-h-screen flex bg-bg-base text-white/90"
        style={{
          // @ts-ignore
          '--state-color': `var(--color-state-${fsmState.toLowerCase().replaceAll('_', '-')})`,
          '--state-glow-color': `var(--color-state-${fsmState.toLowerCase().replaceAll('_', '-')})44`
        }}
      >
        <Sidebar
          isCollapsed={isSidebarCollapsed}
          onToggle={() => setIsSidebarCollapsed(!isSidebarCollapsed)}
          isMobile={isMobile}
        />

        <div className={`flex-1 flex flex-col transition-all duration-300 ${isMobile ? 'ml-0' : isSidebarCollapsed ? 'ml-16' : 'ml-60'}`}>
          <Topbar isSidebarCollapsed={isSidebarCollapsed} isMobile={isMobile} />

          <main className="flex-1 mt-14 relative overflow-hidden">
            <AnimatePresence mode="wait">
              <Routes>
                <Route path="/" element={<ErrorBoundary><PageWrapper><CommandCenter /></PageWrapper></ErrorBoundary>} />
                <Route path="/activity" element={<ErrorBoundary><PageWrapper><ActivityStream /></PageWrapper></ErrorBoundary>} />
                <Route path="/decisions" element={<ErrorBoundary><PageWrapper><DecisionHub /></PageWrapper></ErrorBoundary>} />
                <Route path="/epics" element={<ErrorBoundary><PageWrapper><EpicLifecycle /></PageWrapper></ErrorBoundary>} />
                <Route path="/evidence" element={<ErrorBoundary><PageWrapper><EvidenceVault /></PageWrapper></ErrorBoundary>} />
                <Route path="/health" element={<ErrorBoundary><PageWrapper><HealthObservatory /></PageWrapper></ErrorBoundary>} />
                <Route path="/ideas" element={<ErrorBoundary><PageWrapper><IdeasToExecution /></PageWrapper></ErrorBoundary>} />
                <Route path="/queue" element={<ErrorBoundary><PageWrapper><QueueScheduler /></PageWrapper></ErrorBoundary>} />
                <Route path="/knowledge" element={<ErrorBoundary><PageWrapper><KnowledgeBase /></PageWrapper></ErrorBoundary>} />
              </Routes>
            </AnimatePresence>
          </main>
        </div>

        <ErrorBoundary>
          <AICompanion isOpen={isCompanionOpen && companionMode === 'panel'} onClose={() => setCompanionOpen(false)} />
        </ErrorBoundary>
      </div>
    </ToastProvider>
  );
}

/** Watches stage_log and FSM state for milestone toasts */
function PipelineToasts() {
  const { toast } = useToast();
  const stageLogEntries = useStore((s) => s.stageLogEntries);
  const fsmState = useStore((s) => s.fsmState);
  const prevFsm = useRef(fsmState);
  const prevLogLen = useRef(stageLogEntries.length);

  // Toast on FSM state transitions
  useEffect(() => {
    const prev = prevFsm.current;
    prevFsm.current = fsmState;
    if (prev === fsmState) return;

    if (fsmState === 'EXECUTING' && prev !== 'EXECUTING') {
      toast('info', 'Steroids injected — treatment in progress');
    }
    if (fsmState === 'GATES' && prev !== 'GATES') {
      toast('info', 'Lab results pending — running diagnostics');
    }
    if ((fsmState === 'DONE' || fsmState === 'FIRST_AID_COMPLETE') && prev !== 'DONE' && prev !== 'FIRST_AID_COMPLETE') {
      toast('success', 'Patient discharged — EPIC treatment complete');
    }
    if (fsmState === 'ERROR') {
      toast('error', 'Code Blue — pipeline flatlined, check escalations');
    }
  }, [fsmState, toast]);

  // Toast on important stage_log events
  useEffect(() => {
    const prevLen = prevLogLen.current;
    prevLogLen.current = stageLogEntries.length;
    if (stageLogEntries.length <= prevLen) return;

    // Only process new entries
    const newEntries = stageLogEntries.slice(prevLen);
    for (const entry of newEntries) {
      if (entry.action === 'gates_complete' && entry.result === 'pass') {
        toast('success', `Lab clear${entry.step ? ` — ${entry.step}` : ''}`);
      } else if (entry.action === 'gates_complete' && entry.result === 'fail') {
        toast('warning', `Lab abnormal${entry.step ? ` — ${entry.step}` : ''}, re-testing`);
      } else if (entry.action === 'escalation') {
        toast('warning', `Escalation to Ward: ${entry.details}`);
      }
    }
  }, [stageLogEntries, toast]);

  return null;
}

function PageWrapper({ children }: { children: React.ReactNode }) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -20 }}
      transition={{ duration: 0.2, ease: "easeOut" }}
      className="h-full"
    >
      {children}
    </motion.div>
  );
}
