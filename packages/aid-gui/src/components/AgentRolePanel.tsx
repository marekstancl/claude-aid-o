import { useMemo } from 'react';
import type { ActivityEvent } from '@aid/contract';
import { cn } from '../lib/utils';
import { explainEvent, type Dictionary } from '../lib/explain';
import { StatusBadge } from './common/StatusBadge';
import { ExplanationLine } from './common/ExplanationLine';
import { ExplanationCard } from './common/ExplanationCard';

/** §6.3-D agent roles that emit a verdict. */
export type AgentRole = 'auditor' | 'curator' | 'reporter' | 'simplifier';

/** Czech display name per role (lidská řeč, not the raw machine word). */
const ROLE_LABEL: Record<AgentRole, string> = {
  auditor: 'Auditor',
  curator: 'Kurátor',
  reporter: 'Reportér',
  simplifier: 'Zjednodušovač',
};

interface AgentRolePanelProps {
  role: AgentRole;
  /**
   * The role's verdict (e.g. "blocking" / "clean" for auditor, a disposition for
   * simplifier). `null` = the role hasn't produced a verdict yet → resolves via
   * the dictionary's generic `role:<role>` key (graceful, never crashes).
   */
  verdict: string | null;
  /** The §6.3 dictionary served by `/api/explanations` (caller owns fetch/cache). */
  dictionary: Dictionary;
  /** Optional ISO timestamp of the role run. */
  at?: string | null;
  className?: string;
}

/**
 * §6.3-D role verdict panel. Builds a synthetic `role` {@link ActivityEvent} and
 * resolves it through {@link explainEvent} (lookup key `role:<role>:<verdict>`),
 * so the auditor/curator/reporter/simplifier verdict is shown as a §6.2
 * StatusBadge + Czech explanation, with the deep gloss behind an
 * {@link ExplanationCard}. A null verdict degrades to the generic role key —
 * never a crash, never a blank.
 */
export function AgentRolePanel({ role, verdict, dictionary, at, className }: AgentRolePanelProps) {
  const explanation = useMemo(() => {
    const event: ActivityEvent = {
      projectId: '',
      ts: at ?? '',
      event: role, // role events carry their role name as the event
      role,
      result: undefined,
      raw: verdict != null ? { verdict } : {},
    };
    return explainEvent(event, dictionary);
  }, [role, verdict, dictionary, at]);

  return (
    <section
      data-role-panel={role}
      className={cn('flex flex-col gap-2 rounded-lg border border-slate-200 bg-white p-3', className)}
    >
      <header className="flex items-center justify-between gap-2">
        <span className="text-sm font-semibold text-slate-700">{ROLE_LABEL[role]}</span>
        <div className="flex items-center gap-1">
          <StatusBadge status={explanation.status} />
          <ExplanationCard explanation={explanation} />
        </div>
      </header>
      <ExplanationLine explanation={explanation} />
      {at && (
        <time dateTime={at} title={at} className="text-xs tabular-nums text-slate-400">
          {at}
        </time>
      )}
    </section>
  );
}
