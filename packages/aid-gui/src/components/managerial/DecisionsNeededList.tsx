import type { BriefItem } from '@aid/contract';
import { Card } from './Card';
import { BriefItemRow, sortBriefItems } from './BriefItemRow';

interface DecisionsNeededListProps {
  /** Brief.decisionsNeeded — runs awaiting a PM decision, escalations, blocking findings. */
  items: BriefItem[];
  /** Embedded variant drops the Card chrome (e.g. inside BriefPanel). */
  embedded?: boolean;
  className?: string;
}

/**
 * §13.1 "jaká rozhodnutí jsou potřeba" — the BriefItems that need a human.
 * Sorted blocking → warn → info then recency. An empty list collapses to a calm
 * "Nic nečeká na rozhodnutí" line (not a disappearing block), so the manager
 * sees an explicit all-clear rather than absence.
 */
export function DecisionsNeededList({ items, embedded = false, className }: DecisionsNeededListProps) {
  const sorted = sortBriefItems(items);
  const body =
    sorted.length === 0 ? (
      <p data-decisions-empty className="text-sm text-slate-400">
        Nic nečeká na rozhodnutí
      </p>
    ) : (
      <ul className="space-y-0.5" data-decisions-list>
        {sorted.map((item) => (
          <li key={item.id}>
            <BriefItemRow item={item} />
          </li>
        ))}
      </ul>
    );

  if (embedded) {
    return <div className={className}>{body}</div>;
  }

  return (
    <Card
      title="Rozhodnutí"
      action={<span className="text-xs tabular-nums text-slate-400">{items.length}</span>}
      className={className}
    >
      {body}
    </Card>
  );
}
