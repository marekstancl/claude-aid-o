import type { Explanation, StatusKey } from '@aid/contract';
import { cn } from '../lib/utils';
import { StatusDot } from './common/StatusDot';
import { ExplanationLine } from './common/ExplanationLine';

/**
 * One node in a generic state walk. Authored deliberately free of FSM-specific
 * fields so Step 40's `PlanPhaseTimeline` can reuse this same component for plan
 * phases — a node is just a labelled, status-coloured, explained point in time.
 */
export interface TimelineNode {
  /** Stable react key + machine label (e.g. an FSM state "EXECUTE"). */
  key: string;
  /** Short display label shown next to the dot (e.g. "EXECUTE"). */
  label: string;
  /** §6.2 token driving the node colour. */
  status: StatusKey;
  /** Resolved §6.4 explanation (Czech gloss under the label). */
  explanation: Explanation;
  /** Optional ISO timestamp for this transition (rendered as a muted caption). */
  at?: string | null;
  /** Marks the node the run currently sits in (emphasised ring). */
  current?: boolean;
}

interface FsmTimelineProps {
  nodes: TimelineNode[];
  /** `false` (default) → horizontal (desktop). `true` → vertical (mobile). */
  vertical?: boolean;
  className?: string;
  /** Honest empty-state line when there are no nodes (never a blank box). */
  emptyLabel?: string;
}

/**
 * §6.2 state-walk: a horizontal (desktop) or vertical (mobile) row of nodes,
 * each a {@link StatusDot} + label + {@link ExplanationLine}, joined by a
 * connector. Node colour comes from each node's §6.2 status token. Generic by
 * design — FSM states feed it now, plan phases feed it in Step 40.
 */
export function FsmTimeline({ nodes, vertical = false, className, emptyLabel = 'žádné přechody' }: FsmTimelineProps) {
  if (nodes.length === 0) {
    return (
      <p data-fsm-timeline data-empty className={cn('text-sm text-slate-400', className)}>
        {emptyLabel}
      </p>
    );
  }

  return (
    <ol
      data-fsm-timeline
      data-orientation={vertical ? 'vertical' : 'horizontal'}
      className={cn(
        vertical ? 'flex flex-col gap-0' : 'flex flex-row items-start gap-0 overflow-x-auto',
        className,
      )}
    >
      {nodes.map((node, i) => {
        const isLast = i === nodes.length - 1;
        return (
          <li
            key={node.key}
            data-node={node.key}
            data-current={node.current ? '' : undefined}
            className={cn(
              'relative',
              vertical ? 'flex gap-3 pb-4 last:pb-0' : 'flex flex-1 flex-col items-start pr-4 last:pr-0',
            )}
          >
            {/* Connector to the next node. */}
            {!isLast && (
              <span
                aria-hidden
                className={cn(
                  'bg-slate-200',
                  vertical
                    ? 'absolute left-[6px] top-5 h-full w-px'
                    : 'absolute left-5 top-[6px] h-px w-full',
                )}
              />
            )}
            <div className={cn('flex items-center gap-2', vertical ? 'shrink-0' : '')}>
              <StatusDot
                status={node.status}
                title={node.label}
                className={cn('z-10 bg-white', node.current && 'ring-2 ring-offset-1 rounded-full')}
              />
              <span className="text-sm font-medium tabular-nums text-slate-700">{node.label}</span>
            </div>
            <div className={cn(vertical ? 'pl-5 pt-0.5' : 'pt-1')}>
              <ExplanationLine explanation={node.explanation} />
              {node.at && (
                <time dateTime={node.at} title={node.at} className="text-xs tabular-nums text-slate-400">
                  {node.at}
                </time>
              )}
            </div>
          </li>
        );
      })}
    </ol>
  );
}
