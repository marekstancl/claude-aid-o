import React, { useState, useEffect } from 'react';
import { Routes, Route } from 'react-router';
import { Sidebar } from './components/Sidebar';
import { Topbar } from './components/Topbar';
import { useStore } from './store';
import { motion, AnimatePresence } from 'motion/react';

import { CommandCenter } from './screens/CommandCenter';
import { PipelineTheater } from './screens/PipelineTheater';
import { ActivityStream } from './screens/ActivityStream';
import { DecisionHub } from './screens/DecisionHub';
import { EvidenceVault } from './screens/EvidenceVault';
import { HealthObservatory } from './screens/HealthObservatory';
import { IdeasToExecution } from './screens/IdeasToExecution';
import { QueueScheduler } from './screens/QueueScheduler';
import { KnowledgeBase } from './screens/KnowledgeBase';

import { useNavigate } from 'react-router';
import { AICompanion } from './components/AICompanion';
import { ErrorBoundary } from './components/ErrorBoundary';
import { ToastProvider } from './components/Toast';
import { useWebSocket } from './hooks/useWebSocket';

const MOBILE_BREAKPOINT = 768;

export default function App() {
  const [isSidebarCollapsed, setIsSidebarCollapsed] = useState(false);
  const [isMobile, setIsMobile] = useState(() => window.innerWidth < MOBILE_BREAKPOINT);
  const { setProject, fsmState, currentProject } = useStore();
  const isCompanionOpen = useStore((s) => s.companionOpen);
  const toggleCompanion = useStore((s) => s.toggleCompanion);
  const setCompanionOpen = useStore((s) => s.setCompanionOpen);
  const navigate = useNavigate();

  // Connect WebSocket — the hook manages connection lifecycle, reconnection,
  // and dispatches all incoming events to the Zustand store automatically.
  useWebSocket(currentProject?.id ?? null);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        toggleCompanion();
      }
      
      if (!isCompanionOpen && !['INPUT', 'TEXTAREA'].includes((e.target as HTMLElement).tagName)) {
        if (e.key === '[') setIsSidebarCollapsed(prev => !prev);
        if (e.key === '1') navigate('/');
        if (e.key === '2') navigate('/pipeline');
        if (e.key === '3') navigate('/activity');
        if (e.key === '4') navigate('/decisions');
        if (e.key === '5') navigate('/evidence');
        if (e.key === '6') navigate('/health');
        if (e.key === '7') navigate('/ideas');
        if (e.key === '8') navigate('/queue');
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
  }, [isCompanionOpen, navigate, toggleCompanion]);

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
      <div
        className="min-h-screen flex bg-bg-base text-white/90"
        style={{
          // @ts-ignore
          '--state-color': `var(--color-state-${fsmState.toLowerCase().replace('_', '-')})`,
          '--state-glow-color': `var(--color-state-${fsmState.toLowerCase().replace('_', '-')})44`
        }}
      >
        <Sidebar
          isCollapsed={isSidebarCollapsed}
          onToggle={() => setIsSidebarCollapsed(!isSidebarCollapsed)}
          isMobile={isMobile}
        />

        <div className={`flex-1 flex flex-col transition-all duration-300 ${isMobile ? 'ml-0' : isSidebarCollapsed ? 'ml-16' : 'ml-60'}`}>
          <Topbar onSearchClick={() => setCompanionOpen(true)} />

          <main className="flex-1 mt-14 relative overflow-hidden">
            <AnimatePresence mode="wait">
              <Routes>
                <Route path="/" element={<ErrorBoundary><PageWrapper><CommandCenter /></PageWrapper></ErrorBoundary>} />
                <Route path="/pipeline" element={<ErrorBoundary><PageWrapper><PipelineTheater /></PageWrapper></ErrorBoundary>} />
                <Route path="/activity" element={<ErrorBoundary><PageWrapper><ActivityStream /></PageWrapper></ErrorBoundary>} />
                <Route path="/decisions" element={<ErrorBoundary><PageWrapper><DecisionHub /></PageWrapper></ErrorBoundary>} />
                <Route path="/evidence" element={<ErrorBoundary><PageWrapper><EvidenceVault /></PageWrapper></ErrorBoundary>} />
                <Route path="/health" element={<ErrorBoundary><PageWrapper><HealthObservatory /></PageWrapper></ErrorBoundary>} />
                <Route path="/ideas" element={<ErrorBoundary><PageWrapper><IdeasToExecution /></PageWrapper></ErrorBoundary>} />
                <Route path="/queue" element={<ErrorBoundary><PageWrapper><QueueScheduler /></PageWrapper></ErrorBoundary>} />
                <Route path="/knowledge" element={<ErrorBoundary><PageWrapper><KnowledgeBase /></PageWrapper></ErrorBoundary>} />
              </Routes>
            </AnimatePresence>
          </main>
        </div>

        <AICompanion isOpen={isCompanionOpen} onClose={() => setCompanionOpen(false)} />
      </div>
    </ToastProvider>
  );
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
