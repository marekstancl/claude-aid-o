import { Tabs } from '@base-ui/react/tabs';

/**
 * A reusable tab trigger styled as an underline tab (active = slate underline).
 * Used by ScreenB, ScreenC, and ScreenPlan.
 */
export function TabButton({ value, children }: { value: string; children: React.ReactNode }) {
  return (
    <Tabs.Tab
      value={value}
      className="min-h-[40px] shrink-0 border-b-2 border-transparent px-3 text-sm font-medium text-slate-500 data-[active]:border-slate-900 data-[active]:text-slate-900"
    >
      {children}
    </Tabs.Tab>
  );
}
