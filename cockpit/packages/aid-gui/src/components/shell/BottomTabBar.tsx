import type { FC } from 'react';
import { NavLink } from 'react-router-dom';
import {
  ClipboardCheck,
  LayoutGrid,
  Activity,
  ShieldCheck,
  MoreHorizontal,
  type LucideIcon,
} from 'lucide-react';
import { cn } from '../../lib/utils';

interface TabItem {
  icon: LucideIcon;
  label: string;
  path?: string;
}

/**
 * Rev 3 five-tab set, exact Czech labels. The first four are routes; "Více"
 * opens the MoreSheet (handled by onMoreClick). Reused order:
 * Co řešit · Přehled · Dění · Compliance · Více.
 */
export const tabs: TabItem[] = [
  { icon: ClipboardCheck, label: 'Co řešit', path: '/' },
  { icon: LayoutGrid, label: 'Přehled', path: '/prehled' },
  { icon: Activity, label: 'Dění', path: '/activity' },
  { icon: ShieldCheck, label: 'Compliance', path: '/compliance' },
  { icon: MoreHorizontal, label: 'Více' },
];

interface BottomTabBarProps {
  onMoreClick: () => void;
}

// Each touch target is ≥44px (min-h/min-w) per WCAG; bar itself is 56px tall
// with safe-area-inset padding. On ≤320px the labels truncate but icons +
// targets stay ≥44px, and "Více" absorbs overflow.
const tabClasses =
  'flex min-h-[44px] min-w-[44px] flex-1 flex-col items-center justify-center gap-0.5 px-1';
const labelClasses = 'max-w-full truncate text-[10px] font-medium leading-none';

export const BottomTabBar: FC<BottomTabBarProps> = ({ onMoreClick }) => {
  return (
    <nav
      aria-label="Hlavní navigace"
      className="fixed inset-x-0 bottom-0 z-40 flex h-14 items-stretch border-t border-slate-200 bg-white pb-[env(safe-area-inset-bottom)]"
    >
      {tabs.map((tab) => {
        if (tab.path) {
          return (
            <NavLink
              key={tab.label}
              to={tab.path}
              end={tab.path === '/'}
              className={({ isActive }) =>
                cn(tabClasses, isActive ? 'text-sky-700' : 'text-slate-500')
              }
            >
              <tab.icon size={22} aria-hidden="true" />
              <span className={labelClasses}>{tab.label}</span>
            </NavLink>
          );
        }
        return (
          <button
            key={tab.label}
            type="button"
            onClick={onMoreClick}
            className={cn(tabClasses, 'text-slate-500')}
          >
            <tab.icon size={22} aria-hidden="true" />
            <span className={labelClasses}>{tab.label}</span>
          </button>
        );
      })}
    </nav>
  );
};
