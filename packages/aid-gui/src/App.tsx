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
import { sounds } from './lib/sounds';

export default function App() {
  const [isSidebarCollapsed, setIsSidebarCollapsed] = useState(false);
  const [isCompanionOpen, setIsCompanionOpen] = useState(false);
  const { setProject, fsmState } = useStore();
  const navigate = useNavigate();

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        setIsCompanionOpen(prev => !prev);
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
  }, [isCompanionOpen, navigate]);

  useEffect(() => {
    // Initial data fetch
    fetch('/api/projects')
      .then(res => res.json())
      .then(data => {
        if (data.length > 0) setProject(data[0]);
      });

    fetch('/api/pipeline/status')
      .then(res => res.json())
      .then(data => {
        useStore.getState().updatePipeline({
          fsmState: data.state,
          progress: data.progress,
          activeStep: data.activeStep,
          epic: data.epic,
          duration: data.duration
        });
      });
      
    // Mock state changes for sound demo
    const interval = setInterval(() => {
      const state = useStore.getState();
      if (state.fsmState === 'EXECUTING') {
        sounds.stepComplete();
      }
    }, 15000);
    
    return () => clearInterval(interval);
  }, [setProject]);

  return (
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
      />
      
      <div className={`flex-1 flex flex-col transition-all duration-300 ${isSidebarCollapsed ? 'ml-16' : 'ml-60'}`}>
        <Topbar onSearchClick={() => setIsCompanionOpen(true)} />
        
        <main className="flex-1 mt-14 relative overflow-hidden">
          <AnimatePresence mode="wait">
            <Routes>
              <Route path="/" element={<PageWrapper><CommandCenter /></PageWrapper>} />
              <Route path="/pipeline" element={<PageWrapper><PipelineTheater /></PageWrapper>} />
              <Route path="/activity" element={<PageWrapper><ActivityStream /></PageWrapper>} />
              <Route path="/decisions" element={<PageWrapper><DecisionHub /></PageWrapper>} />
              <Route path="/evidence" element={<PageWrapper><EvidenceVault /></PageWrapper>} />
              <Route path="/health" element={<PageWrapper><HealthObservatory /></PageWrapper>} />
              <Route path="/ideas" element={<PageWrapper><IdeasToExecution /></PageWrapper>} />
              <Route path="/queue" element={<PageWrapper><QueueScheduler /></PageWrapper>} />
              <Route path="/knowledge" element={<PageWrapper><KnowledgeBase /></PageWrapper>} />
            </Routes>
          </AnimatePresence>
        </main>
      </div>

      <AICompanion isOpen={isCompanionOpen} onClose={() => setIsCompanionOpen(false)} />
    </div>
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
