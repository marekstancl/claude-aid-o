import { useMemo, useState } from 'react';
import type { BacklogDelta, BacklogDeltaItem, StatusKey } from '@aid/contract';
import { cn } from '../../lib/utils';
import { Card } from './Card';
import { StatusBadge } from '../common/StatusBadge';

/** The four delta buckets, each with its §6.2 badge token + Czech label. */
type BucketKey = 'added' | 'closed' | 'priorityChanged' | 'statusChanged';

const BUCKETS: { key: BucketKey; label: string; status: StatusKey }[] = [
  { key: 'added', label: 'přidané', status: 'bezi' },
  { key: 'closed', label: 'uzavřené', status: 'proslo' },
  { key: 'priorityChanged', label: 'změna priority', status: 'pozor' },
  { key: 'statusChanged', label: 'změna stavu', status: 'pozor' },
];

interface BacklogDeltaListProps {
  delta: BacklogDelta;
  /** Embedded variant (e.g. inside ChangedSinceList) drops the outer Card chrome. */
  embedded?: boolean;
  className?: string;
}

/**
 * §13.7 client-side backlog delta. Read-only — it never mutates the backlog,
 * only shows "co se v backlogu od minule změnilo" across four buckets:
 *  - added → běží, closed → prošlo, priorityChanged / statusChanged → pozor.
 *
 * `firstVisit:true` → a calm "bez porovnání - vše jako nové" line (there is no
 * prior snapshot to diff against), NOT four empty buckets pretending nothing
 * changed. Filter chips narrow to one bucket; an empty bucket shows an honest
 * "nic" line rather than disappearing.
 */
export function BacklogDeltaList({ delta, embedded = false, className }: BacklogDeltaListProps) {
  const [active, setActive] = useState<BucketKey | 'all'>('all');

  const counts = useMemo(
    () => ({
      added: delta.added.length,
      closed: delta.closed.length,
      priorityChanged: delta.priorityChanged.length,
      statusChanged: delta.statusChanged.length,
    }),
    [delta],
  );

  const body = delta.firstVisit ? (
    <p data-backlog-firstvisit className="text-sm text-slate-500">
      bez porovnání - vše jako nové
    </p>
  ) : (
    <div className="space-y-3" data-backlog-delta>
      {/* Filter chips. */}
      <div className="flex flex-wrap gap-1.5">
        <FilterChip active={active === 'all'} onClick={() => setActive('all')}>
          vše
        </FilterChip>
        {BUCKETS.map((b) => (
          <FilterChip key={b.key} active={active === b.key} onClick={() => setActive(b.key)}>
            {b.label} ({counts[b.key]})
          </FilterChip>
        ))}
      </div>

      {BUCKETS.filter((b) => active === 'all' || active === b.key).map((bucket) => {
        const items = delta[bucket.key] as BacklogDeltaItem[];
        return (
          <div key={bucket.key} data-bucket={bucket.key}>
            <div className="mb-1 flex items-center gap-2">
              <StatusBadge status={bucket.status} label={bucket.label} />
              <span className="text-xs tabular-nums text-slate-400">{items.length}</span>
            </div>
            {items.length === 0 ? (
              <p className="pl-1 text-sm text-slate-400">nic</p>
            ) : (
              <ul className="space-y-0.5">
                {items.map((item, i) => (
                  <li
                    key={item.id ?? `${bucket.key}-${i}`}
                    className="flex items-baseline gap-2 text-sm text-slate-700"
                  >
                    <span className="shrink-0 font-mono text-xs tabular-nums text-slate-400">
                      {item.id ?? '—'}
                    </span>
                    <span className="truncate">{item.title}</span>
                  </li>
                ))}
              </ul>
            )}
          </div>
        );
      })}

      {delta.warnings.length > 0 && (
        <ul className="space-y-0.5 border-t border-slate-100 pt-2">
          {delta.warnings.map((w, i) => (
            <li key={i} className="text-xs text-amber-700">
              {w}
            </li>
          ))}
        </ul>
      )}
    </div>
  );

  if (embedded) {
    return (
      <div data-backlog-delta-embedded className={className}>
        {body}
      </div>
    );
  }

  return (
    <Card
      title="Backlog — co se změnilo"
      action={
        <span className="text-xs tabular-nums text-slate-400">
          {delta.openCount} otevřených · {delta.closedCount} uzavřených
        </span>
      }
      className={className}
    >
      {body}
    </Card>
  );
}

function FilterChip({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      data-filter-chip
      data-active={active ? '' : undefined}
      onClick={onClick}
      className={cn(
        'rounded-full border px-2.5 py-0.5 text-xs font-medium',
        active
          ? 'border-slate-400 bg-slate-100 text-slate-800'
          : 'border-slate-200 bg-white text-slate-500 hover:bg-slate-50',
      )}
    >
      {children}
    </button>
  );
}
