import type { ActivityEvent, Explanation } from '@aid/contract';
import { cn, relativeCzech } from '../../lib/utils';
import { StatusDot } from './StatusDot';

interface EventRowProps {
  event: ActivityEvent;
  /** Resolved §8.4 explanation for this event (drives the Czech sentence + status colour). */
  explanation: Explanation;
  /** ISO 8601 timestamp of the event, rendered as a Czech relative time. */
  at: string;
  className?: string;
}

/**
 * §8.4 narrated timeline row: a §6.2 status glyph, the Czech explanation
 * sentence ({@link Explanation.headline}) and a relative time. One row = one
 * human-readable event; no raw JSON leaks into the UI.
 */
export function EventRow({ event, explanation, at, className }: EventRowProps) {
  return (
    <div className={cn('flex items-start gap-3 py-2', className)}>
      <StatusDot status={explanation.status} title={explanation.headline} className="mt-0.5" />
      <p className="flex-1 text-sm leading-snug text-slate-700">{explanation.headline}</p>
      <time
        dateTime={at}
        title={at}
        className="shrink-0 text-xs tabular-nums text-slate-400"
        data-event={event.event}
      >
        {relativeCzech(at)}
      </time>
    </div>
  );
}
