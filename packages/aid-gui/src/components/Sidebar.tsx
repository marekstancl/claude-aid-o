import React, { useEffect, useRef, useState } from 'react';
import { NavLink } from 'react-router';
import {
  LayoutDashboard,
  Activity,
  GitBranch,
  Gavel,
  Archive,
  HeartPulse,
  Lightbulb,
  BookOpen,
  ChevronLeft,
  ChevronRight,
  ListOrdered,
  Menu,
  Layers,
} from 'lucide-react';
import { cn } from '../lib/utils';
import { useStore } from '../store';

interface SidebarProps {
  isCollapsed: boolean;
  onToggle: () => void;
  isMobile: boolean;
}

const navItems = [
  { icon: LayoutDashboard, label: 'Command Center', path: '/' },
  { icon: GitBranch, label: 'Pipeline Theater', path: '/pipeline' },
  { icon: Activity, label: 'Activity Stream', path: '/activity' },
  { icon: Gavel, label: 'Decision Hub', path: '/decisions' },
  { icon: Layers, label: 'EPIC Lifecycle', path: '/epics' },
  { icon: Archive, label: 'Evidence Vault', path: '/evidence' },
  { icon: HeartPulse, label: 'Health Observatory', path: '/health' },
  { icon: Lightbulb, label: 'Ideas to Execution', path: '/ideas' },
  { icon: ListOrdered, label: 'Queue Scheduler', path: '/queue' },
  { icon: BookOpen, label: 'Knowledge Base', path: '/knowledge' },
];

export const Sidebar: React.FC<SidebarProps> = ({ isCollapsed, onToggle, isMobile }) => {
  const pendingDecisions = useStore((s) => s.pendingDecisions);
  const [isPulsing, setIsPulsing] = useState(false);
  const prevCountRef = useRef(pendingDecisions);

  // Trigger pulse animation when pending count increases
  useEffect(() => {
    if (pendingDecisions > prevCountRef.current && pendingDecisions > 0) {
      setIsPulsing(true);
      const timer = setTimeout(() => setIsPulsing(false), 2000);
      return () => clearTimeout(timer);
    }
    prevCountRef.current = pendingDecisions;
  }, [pendingDecisions]);

  // Also update prevCountRef when count decreases (no pulse needed)
  useEffect(() => {
    prevCountRef.current = pendingDecisions;
  }, [pendingDecisions]);

  const handleNavClick = () => {
    if (isMobile && !isCollapsed) {
      onToggle();
    }
  };

  return (
    <>
      {/* Hamburger button — visible only on mobile when sidebar is collapsed */}
      {isMobile && isCollapsed && (
        <button
          onClick={onToggle}
          className="fixed top-3 left-3 z-50 p-2 rounded-lg bg-surface-1/80 backdrop-blur-sm border border-white/10 text-white/60 hover:text-white hover:bg-white/10 transition-colors"
          aria-label="Open navigation menu"
        >
          <Menu size={20} />
        </button>
      )}

      {/* Backdrop overlay — visible on mobile when sidebar is expanded */}
      {isMobile && !isCollapsed && (
        <div
          className="fixed inset-0 bg-black/50 z-30 transition-opacity duration-300"
          onClick={onToggle}
          aria-label="Close navigation menu"
        />
      )}

      <aside
        className={cn(
          "fixed left-0 top-0 h-full bg-surface-1/50 backdrop-blur-xl border-r border-white/5 transition-all duration-300 z-40 flex flex-col",
          isCollapsed ? "w-16" : "w-60",
          isMobile && isCollapsed && "-translate-x-full"
        )}
      >
        <div className="h-14 flex items-center justify-between px-4 border-b border-white/5">
          {!isCollapsed && <span className="font-bold tracking-tighter text-xl bg-gradient-to-r from-white to-white/40 bg-clip-text text-transparent">AID</span>}
          <button
            onClick={onToggle}
            className="p-1.5 rounded-lg hover:bg-white/5 text-white/40 hover:text-white transition-colors"
          >
            {isCollapsed ? <ChevronRight size={18} /> : <ChevronLeft size={18} />}
          </button>
        </div>

        <nav className="flex-1 py-4 px-2 space-y-1 overflow-y-auto">
          {navItems.map((item) => {
            const isDecisionHub = item.path === '/decisions';
            const showBadge = isDecisionHub && pendingDecisions > 0;

            return (
              <NavLink
                key={item.path}
                to={item.path}
                onClick={handleNavClick}
                className={({ isActive }) => cn(
                  "flex items-center gap-3 px-3 py-2.5 rounded-xl transition-all group relative",
                  isActive
                    ? "bg-white/10 text-white"
                    : "text-white/40 hover:text-white hover:bg-white/5"
                )}
              >
                <div className="relative shrink-0">
                  <item.icon size={20} />
                  {showBadge && isCollapsed && (
                    <span
                      className={cn(
                        "absolute -top-1.5 -right-1.5 min-w-[18px] h-[18px] flex items-center justify-center rounded-full bg-state-error text-white text-[9px] font-bold px-1 leading-none",
                        isPulsing && "animate-pulse"
                      )}
                    >
                      {pendingDecisions > 99 ? '99+' : pendingDecisions}
                    </span>
                  )}
                </div>
                {!isCollapsed && (
                  <span className="text-sm font-medium flex-1">{item.label}</span>
                )}
                {!isCollapsed && showBadge && (
                  <span
                    className={cn(
                      "min-w-[20px] h-[20px] flex items-center justify-center rounded-full bg-state-error text-white text-[10px] font-bold px-1.5 leading-none",
                      isPulsing && "animate-pulse"
                    )}
                  >
                    {pendingDecisions > 99 ? '99+' : pendingDecisions}
                  </span>
                )}
                {isCollapsed && (
                  <div className="absolute left-full ml-2 px-2 py-1 bg-surface-2 border border-white/10 rounded text-xs whitespace-nowrap opacity-0 group-hover:opacity-100 pointer-events-none transition-opacity flex items-center gap-2">
                    {item.label}
                    {showBadge && (
                      <span className="min-w-[16px] h-[16px] flex items-center justify-center rounded-full bg-state-error text-white text-[9px] font-bold px-1 leading-none">
                        {pendingDecisions > 99 ? '99+' : pendingDecisions}
                      </span>
                    )}
                  </div>
                )}
              </NavLink>
            );
          })}
        </nav>

        <div className="p-4 border-t border-white/5">
          <div className={cn("flex items-center gap-3", isCollapsed ? "justify-center" : "")}>
            <div className="w-8 h-8 rounded-full bg-gradient-to-br from-state-executing to-state-phase-check shrink-0" />
            {!isCollapsed && (
              <div className="flex flex-col min-w-0">
                <span className="text-xs font-medium truncate">Admin User</span>
                <span className="text-[10px] text-white/40 truncate">v1.4.0</span>
              </div>
            )}
          </div>
        </div>
      </aside>
    </>
  );
};
