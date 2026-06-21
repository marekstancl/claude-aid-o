import { useState } from 'react';
import { Outlet } from 'react-router-dom';
import { Sidebar } from './components/shell/Sidebar';
import { BottomTabBar } from './components/shell/BottomTabBar';
import { Breadcrumb } from './components/shell/Breadcrumb';
import { MoreSheet } from './components/shell/MoreSheet';
import { ToastProvider } from './components/shell/Toast';
import { ProjectsProvider } from './components/shell/ProjectsContext';
import { useIsMobile } from './components/shell/useIsMobile';
import { useAidSocket } from './hooks/useAidSocket';
import { usePollingFallback } from './hooks/usePollingFallback';
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

  // Live monitoring: subscribe to ALL topics + ALL projects (empty = all, per the
  // server filter). When the socket is not OPEN, usePollingFallback polls
  // /api/activity + the active keys every 5s and raises the offline banner — so
  // the dashboard never goes dark (§7.3 / §9.5 / risk #5).
  const { status: socketStatus } = useAidSocket({ topics: [], projects: [] });
  const { polling } = usePollingFallback(socketStatus, [['projects'], ['activity']]);

  return (
    <ProjectsProvider>
      <ToastProvider>
        <div className="flex min-h-screen bg-slate-50 text-slate-900">
          {polling && (
            <div
              role="status"
              aria-live="polite"
              className="fixed inset-x-0 top-0 z-50 bg-amber-50 px-4 py-1.5 text-center text-sm text-amber-800 shadow-sm"
            >
              živé spojení nejede - aktualizuji po 5 s
            </div>
          )}
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
