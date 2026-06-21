import { Link } from 'react-router-dom';
import type { BriefItem } from '@aid/contract';
import { cn } from '../../lib/utils';
import { StatusDot } from '../common/StatusDot';
import { ExplanationLine } from '../common/ExplanationLine';

interface BriefItemRowProps {
  item: BriefItem;
  className?: string;
}

/**
 * One {@link BriefItem} as a deep-linked row: a §6.2 StatusDot (coloured by the
 * resolved explanation), the technical title, an {@link ExplanationLine} gloss,
 * and an `at` caption — all wrapped in a deep-link to the item's `href`.
 *
 * Honesty: a BriefItem whose explanation failed to resolve still renders — the
 * server's `explain()` degrades a miss to a grey `ceka` Explanation with the raw
 * label as the headline, so this row shows the raw label + grey dot rather than
 * blanking or throwing.
 */
export function BriefItemRow({ item, className }: BriefItemRowProps) {
  return (
    <Link
      to={item.href}
      data-brief-item={item.id}
      data-severity={item.severity}
      className={cn(
        'flex items-start gap-2 rounded-md px-1.5 py-1 no-underline hover:bg-slate-50',
        className,
      )}
    >
      <StatusDot status={item.explanation.status} className="mt-0.5" />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm font-medium text-slate-700">{item.title}</span>
        <ExplanationLine explanation={item.explanation} className="text-xs" />
      </span>
      {item.at && (
        <time dateTime={item.at} className="shrink-0 text-xs tabular-nums text-slate-400">
          {item.at}
        </time>
      )}
    </Link>
  );
}

/** Severity sort weight: blocking first, then warn, then info (§13.4). */
const SEVERITY_WEIGHT: Record<BriefItem['severity'], number> = {
  blocking: 0,
  warn: 1,
  info: 2,
};

/**
 * Sort BriefItems blocking → warn → info, then by `at` descending (most recent
 * first within a severity band). Pure; returns a new array.
 */
export function sortBriefItems(items: BriefItem[]): BriefItem[] {
  return [...items].sort((a, b) => {
    const s = SEVERITY_WEIGHT[a.severity] - SEVERITY_WEIGHT[b.severity];
    if (s !== 0) return s;
    return (b.at ?? '').localeCompare(a.at ?? '');
  });
}
