import { useState } from 'react';
import { Outlet } from 'react-router-dom';
import { Sidebar } from './components/shell/Sidebar';
import { BottomTabBar } from './components/shell/BottomTabBar';
import { Breadcrumb } from './components/shell/Breadcrumb';
import { MoreSheet } from './components/shell/MoreSheet';
import { ToastProvider } from './components/shell/Toast';
import { ProjectsProvider } from './components/shell/ProjectsContext';
import { useIsMobile } from './components/shell/useIsMobile';
import { cn } from './lib/utils';

/**
 * Responsive read-only application shell.
 *
 * Desktop: collapsible left sidebar (rail order from spec §8.1) + breadcrumb.
 * Mobile: bottom tab bar (Rev 3 five-tab set) + a "Více" sheet; the rail is
 * reused as a slide-in drawer behind the hamburger.
 *
 * Salvaged from the orphaned App.tsx: the MOBILE_BREAKPOINT mobile-detection
 * via matchMedia (now in useIsMobile), the <ToastProvider> wrap and the
 * collapse mechanics. Dropped: PipelineToasts (medical strings), AICompanion,
 * the Cmd-K CommandPalette, the motion/react PageWrapper and the dark-glass
 * --state-glow-color styling.
 */
export default function App() {
  const isMobile = useIsMobile();
  const [isSidebarCollapsed, setIsSidebarCollapsed] = useState(true);
  const [moreOpen, setMoreOpen] = useState(false);

  return (
    <ProjectsProvider>
      <ToastProvider>
        <div className="flex min-h-screen bg-slate-50 text-slate-900">
          {/* Single Sidebar instance: desktop collapsible rail, and on mobile a
              slide-in drawer (hamburger + backdrop + -translate-x-full) — all
              handled internally by the component based on isMobile/isCollapsed. */}
          <Sidebar
            isCollapsed={isSidebarCollapsed}
            onToggle={() => setIsSidebarCollapsed((v) => !v)}
            isMobile={isMobile}
          />

          <div
            className={cn(
              'flex flex-1 flex-col transition-all duration-300',
              isMobile ? 'ml-0 pb-14' : isSidebarCollapsed ? 'ml-16' : 'ml-60',
            )}
          >
            {!isMobile && <Breadcrumb />}
            <main className="flex-1 overflow-y-auto">
              <Outlet />
            </main>
          </div>

          {isMobile && <BottomTabBar onMoreClick={() => setMoreOpen(true)} />}
          <MoreSheet open={moreOpen} onOpenChange={setMoreOpen} />
        </div>
      </ToastProvider>
    </ProjectsProvider>
  );
}
