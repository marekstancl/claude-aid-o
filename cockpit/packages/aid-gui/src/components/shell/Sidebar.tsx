import type { FC } from 'react';
import { NavLink } from 'react-router-dom';
import {
  ClipboardCheck,
  LayoutGrid,
  Activity,
  ShieldCheck,
  HelpCircle,
  ChevronLeft,
  ChevronRight,
  Menu,
} from 'lucide-react';
import { cn } from '../../lib/utils';

interface SidebarProps {
  isCollapsed: boolean;
  onToggle: () => void;
  isMobile: boolean;
}

/**
 * Rail order per spec §8.1 — leads with the managerial brief:
 * Co potřebuju vědět (G) · Přehled (A) · Dění (D) · Compliance (E) · Nápověda (F).
 * Project/plan switchers are NOT top-level rail items (they live in the "Více" sheet).
 */
export const navItems = [
  { icon: ClipboardCheck, label: 'Co potřebuju vědět', path: '/' },
  { icon: LayoutGrid, label: 'Přehled', path: '/prehled' },
  { icon: Activity, label: 'Dění', path: '/activity' },
  { icon: ShieldCheck, label: 'Compliance', path: '/compliance' },
  { icon: HelpCircle, label: 'Nápověda', path: '/help' },
];

/**
 * Desktop collapsible icon-rail. Mechanics salvaged from the orphaned
 * components/Sidebar.tsx (w-16/w-60 collapse, -translate-x-full mobile hide,
 * hamburger, backdrop overlay, NavLink active styling) but re-skinned to the
 * light theme. The pendingDecisions badge animation and the "Admin User /
 * v1.4.0" footer were dropped.
 */
export const Sidebar: FC<SidebarProps> = ({ isCollapsed, onToggle, isMobile }) => {
  const handleNavClick = () => {
    if (isMobile && !isCollapsed) onToggle();
  };

  return (
    <>
      {/* Hamburger — mobile only, when the rail is collapsed (hidden off-screen) */}
      {isMobile && isCollapsed && (
        <button
          onClick={onToggle}
          className="fixed left-3 top-3 z-50 rounded-lg border border-slate-200 bg-white/90 p-2 text-slate-600 backdrop-blur-sm transition-colors hover:bg-slate-100"
          aria-label="Otevřít navigaci"
        >
          <Menu size={20} />
        </button>
      )}

      {/* Backdrop overlay — mobile only, when the rail is open */}
      {isMobile && !isCollapsed && (
        <div
          className="fixed inset-0 z-30 bg-slate-900/40 transition-opacity duration-300"
          onClick={onToggle}
          aria-label="Zavřít navigaci"
        />
      )}

      <aside
        className={cn(
          'fixed left-0 top-0 z-40 flex h-full flex-col border-r border-slate-200 bg-white transition-all duration-300',
          isCollapsed ? 'w-16' : 'w-60',
          isMobile && isCollapsed && '-translate-x-full',
        )}
      >
        <div className="flex h-14 items-center justify-between border-b border-slate-200 px-4">
          {!isCollapsed && (
            <span className="text-xl font-bold tracking-tight text-slate-900">AID</span>
          )}
          <button
            onClick={onToggle}
            className="rounded-lg p-1.5 text-slate-400 transition-colors hover:bg-slate-100 hover:text-slate-700"
            aria-label={isCollapsed ? 'Rozbalit navigaci' : 'Sbalit navigaci'}
          >
            {isCollapsed ? <ChevronRight size={18} /> : <ChevronLeft size={18} />}
          </button>
        </div>

        <nav className="flex-1 space-y-1 overflow-y-auto px-2 py-4">
          {navItems.map((item) => (
            <NavLink
              key={item.path}
              to={item.path}
              end={item.path === '/'}
              onClick={handleNavClick}
              className={({ isActive }) =>
                cn(
                  'group relative flex items-center gap-3 rounded-xl px-3 py-2.5 transition-colors',
                  isActive
                    ? 'bg-sky-50 text-sky-700'
                    : 'text-slate-500 hover:bg-slate-100 hover:text-slate-900',
                )
              }
            >
              <span className="shrink-0">
                <item.icon size={20} />
              </span>
              {!isCollapsed && (
                <span className="flex-1 text-sm font-medium">{item.label}</span>
              )}
              {isCollapsed && (
                <div className="pointer-events-none absolute left-full ml-2 whitespace-nowrap rounded border border-slate-200 bg-white px-2 py-1 text-xs text-slate-700 opacity-0 shadow-sm transition-opacity group-hover:opacity-100">
                  {item.label}
                </div>
              )}
            </NavLink>
          ))}
        </nav>
      </aside>
    </>
  );
};
