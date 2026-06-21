import type { ReactNode } from 'react';

/**
 * Placeholder screen shell used by every Phase 5 screen stub. The real screens
 * are authored in Phase 6 (EPIC 6); this renders only the title + a "TODO Step N"
 * marker so the shell, routes and navigation can be exercised end-to-end now.
 */
export function ScreenStub({
  title,
  todoStep,
  children,
}: {
  title: string;
  todoStep: string;
  children?: ReactNode;
}) {
  return (
    <section className="p-6" aria-label={title}>
      <h1 className="text-2xl font-semibold text-slate-900">{title}</h1>
      <p className="mt-2 text-sm text-slate-500">TODO {todoStep}</p>
      {children}
    </section>
  );
}
