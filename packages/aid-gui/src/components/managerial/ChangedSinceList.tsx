import type { Brief, BacklogDelta } from '@aid/contract';
import { Card } from './Card';
import { BriefItemRow, sortBriefItems } from './BriefItemRow';
import { BacklogDeltaList } from './BacklogDeltaList';

interface ChangedSinceListProps {
  /** The Brief's `sinceLastSeen` slice (§13.3). */
  sinceLastSeen: Brief['sinceLastSeen'];
  /** Optional backlog delta to embed for the backlog slice (§13.7). */
  backlogDelta?: BacklogDelta | null;
  /** Embedded variant drops the Card chrome (e.g. inside BriefPanel). */
  embedded?: boolean;
  className?: string;
}

/**
 * §13.3 "co se změnilo od poslední návštěvy". Renders the `sinceLastSeen.items`
 * (sorted blocking → warn → info then recency) under a header counts pill, and
 * embeds {@link BacklogDeltaList} for the backlog slice when supplied.
 *
 * `since === null` is the first visit → a calm "První návštěva - zatím není co
 * porovnat" line, never an empty/misleading "nothing changed". An empty item
 * list with a prior `since` shows "Od minule nic nového".
 */
export function ChangedSinceList({
  sinceLastSeen,
  backlogDelta,
  embedded = false,
  className,
}: ChangedSinceListProps) {
  const sorted = sortBriefItems(sinceLastSeen.items);
  const c = sinceLastSeen.counts;

  const pill = (
    <span className="text-xs tabular-nums text-slate-400">
      {c.newRuns} běhů · {c.newGateFails} bran · {c.newViolations} porušení · {c.newBacklog} backlog ·{' '}
      {c.stateTransitions} přechodů
    </span>
  );

  const inner = (
    <div className="space-y-3">
      {sinceLastSeen.since === null ? (
        <p data-since-firstvisit className="text-sm text-slate-400">
          První návštěva - zatím není co porovnat
        </p>
      ) : sorted.length === 0 ? (
        <p data-since-empty className="text-sm text-slate-400">
          Od minule nic nového
        </p>
      ) : (
        <ul className="space-y-0.5" data-since-list>
          {sorted.map((item) => (
            <li key={item.id}>
              <BriefItemRow item={item} />
            </li>
          ))}
        </ul>
      )}

      {backlogDelta && <BacklogDeltaList delta={backlogDelta} embedded />}
    </div>
  );

  if (embedded) {
    return (
      <div className={className}>
        <div className="mb-1">{pill}</div>
        {inner}
      </div>
    );
  }

  return (
    <Card title="Co se změnilo od minule" action={pill} className={className}>
      {inner}
    </Card>
  );
}
