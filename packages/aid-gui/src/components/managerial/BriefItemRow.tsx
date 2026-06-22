import { useState } from 'react';
import { Link } from 'react-router-dom';
import type { BriefItem, ItemLifecycle } from '@aid/contract';
import { cn, czechPlural } from '../../lib/utils';
import { StatusDot } from '../common/StatusDot';

interface BriefItemRowProps {
  item: BriefItem;
  className?: string;
}

/** Lifecycle → small Czech badge (only when it adds information). */
const LIFECYCLE_BADGE: Partial<Record<ItemLifecycle, { label: string; cls: string }>> = {
  stale: { label: 'déle bez pohybu', cls: 'bg-amber-100 text-amber-800' },
  unknown: { label: 'stav nejasný', cls: 'bg-slate-200 text-slate-600' },
  historical: { label: 'historické', cls: 'bg-slate-100 text-slate-500' },
  resolved: { label: 'vyřešené', cls: 'bg-emerald-100 text-emerald-700' },
};

const NEXT_ACTOR_LABEL: Record<string, string> = {
  pm: 'ty (PM)',
  aid: 'AID',
  agent: 'agent',
  none: '—',
};

/**
 * One {@link BriefItem} as a MANAGERIAL CARD (E-047-6 REOPEN productization):
 * human title first, then plain-language impact, what it blocks, and the
 * recommended action + next actor. Grouping (occurrenceCount / affectedEpics) and
 * lifecycle are shown as chips. Raw identifiers (signal, rootCauseKey, evidence
 * refs, flags) live behind a "technický detail" expander — NEVER as the headline.
 */
export function BriefItemRow({ item, className }: BriefItemRowProps) {
  const [open, setOpen] = useState(false);
  const primary = item.evidenceRefs[0];
  const epicCount = item.affectedEpics.length;

  return (
    <div
      data-brief-item={item.id}
      data-severity={item.severity}
      data-lifecycle={item.lifecycle}
      className={cn('rounded-lg border border-slate-200 bg-white px-3 py-2.5', className)}
    >
      <div className="flex items-start gap-2">
        <StatusDot status={item.explanation.status} className="mt-1" />
        <div className="min-w-0 flex-1">
          {/* Human title + chips */}
          <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
            {primary ? (
              <Link
                to={primary.href}
                data-brief-link
                className="text-sm font-semibold text-slate-800 no-underline hover:underline"
              >
                {item.humanTitle}
              </Link>
            ) : (
              <span className="text-sm font-semibold text-slate-800">{item.humanTitle}</span>
            )}
            {item.occurrenceCount > 1 && (
              <span
                data-occurrence
                className="rounded-full bg-slate-100 px-2 py-0.5 text-xs text-slate-600 tabular-nums"
              >
                {item.occurrenceCount} {czechPlural(item.occurrenceCount, 'běh', 'běhy', 'běhů')}
                {epicCount > 1 ? ` · ${epicCount} EPIC` : ''}
              </span>
            )}
            {LIFECYCLE_BADGE[item.lifecycle] && (
              <span
                data-lifecycle-badge
                className={cn('rounded-full px-2 py-0.5 text-xs', LIFECYCLE_BADGE[item.lifecycle]!.cls)}
              >
                {LIFECYCLE_BADGE[item.lifecycle]!.label}
              </span>
            )}
          </div>

          {/* Impact / why it matters */}
          <p className="mt-1 text-xs text-slate-600">{item.whyItMatters}</p>

          {/* What it blocks */}
          {item.whatBlocks && (
            <p className="mt-1 text-xs text-slate-500">
              <span className="font-medium text-slate-600">Blokuje:</span> {item.whatBlocks}
            </p>
          )}

          {/* Recommended action + next actor */}
          {item.recommendedAction && (
            <p className="mt-1 text-xs text-slate-700">
              <span className="font-medium">Doporučení:</span> {item.recommendedAction}
              {item.nextActor !== 'none' && (
                <span className="text-slate-400"> · čeká na: {NEXT_ACTOR_LABEL[item.nextActor]}</span>
              )}
            </p>
          )}

          {/* Technical detail (raw identifiers) — expandable, never the headline */}
          <button
            type="button"
            data-tech-toggle
            onClick={() => setOpen((v) => !v)}
            className="mt-1.5 text-xs text-slate-400 hover:text-slate-600"
          >
            {open ? '▾ skrýt technický detail' : '▸ technický detail'}
          </button>
          {open && (
            <div data-tech-detail className="mt-1 space-y-1 rounded bg-slate-50 px-2 py-1.5 text-xs text-slate-500">
              <div>
                <span className="text-slate-400">signál:</span>{' '}
                <code className="text-slate-600">{item.signal}</code>
              </div>
              <div>
                <span className="text-slate-400">root cause:</span>{' '}
                <code className="text-slate-600">{item.rootCauseKey}</code>
              </div>
              {item.affectedEpics.length > 0 && (
                <div>
                  <span className="text-slate-400">EPICy:</span> {item.affectedEpics.join(', ')}
                </div>
              )}
              {item.inconsistencyFlags.length > 0 && (
                <div className="text-amber-600">⚠ {item.inconsistencyFlags.join(', ')}</div>
              )}
              {item.evidenceRefs.length > 0 && (
                <div className="flex flex-wrap gap-2 pt-0.5">
                  {item.evidenceRefs.map((e) => (
                    <Link key={e.href} to={e.href} className="text-sky-600 hover:underline">
                      {e.label}
                    </Link>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

/** Severity sort weight: blocking first, then warn, then info. */
const SEVERITY_WEIGHT: Record<BriefItem['severity'], number> = { blocking: 0, warn: 1, info: 2 };
const LIFECYCLE_WEIGHT: Record<ItemLifecycle, number> = {
  active: 0,
  stale: 1,
  unknown: 2,
  resolved: 3,
  historical: 4,
};

/**
 * Sort BriefItems for display: active first, then severity, then most-recent
 * `lastSeen`. The server already returns them sorted; this keeps client renders
 * stable when items are merged/filtered locally. Pure; returns a new array.
 */
export function sortBriefItems(items: BriefItem[]): BriefItem[] {
  return [...items].sort((a, b) => {
    const lc = LIFECYCLE_WEIGHT[a.lifecycle] - LIFECYCLE_WEIGHT[b.lifecycle];
    if (lc !== 0) return lc;
    const s = SEVERITY_WEIGHT[a.severity] - SEVERITY_WEIGHT[b.severity];
    if (s !== 0) return s;
    return (b.lastSeen ?? '').localeCompare(a.lastSeen ?? '');
  });
}
