import type { ActivityEvent, Explanation } from '@aid/contract';
import { cn } from '../../lib/utils';
import { StatusDot } from './StatusDot';

interface EventRowProps {
  event: ActivityEvent;
  /** Resolved §8.4 explanation for this event (drives the Czech sentence + status colour). */
  explanation: Explanation;
  /** ISO 8601 timestamp of the event, rendered as a Czech relative time. */
  at: string;
  className?: string;
}

/** Render an ISO timestamp as a short Czech relative phrase (e.g. "před 3 min"). */
function relativeCzech(iso: string, now: number = Date.now()): string {
  const then = Date.parse(iso);
  if (Number.isNaN(then)) return iso;
  const diffS = Math.max(0, Math.round((now - then) / 1000));
  if (diffS < 60) return 'právě teď';
  const diffMin = Math.round(diffS / 60);
  if (diffMin < 60) return `před ${diffMin} min`;
  const diffH = Math.round(diffMin / 60);
  if (diffH < 24) return `před ${diffH} h`;
  const diffD = Math.round(diffH / 24);
  return `před ${diffD} d`;
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
