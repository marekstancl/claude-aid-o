import { cn } from '../../lib/utils';

interface DurationBarProps {
  /** Duration in seconds; `null` means "not measured" (hatched track, not 0%). */
  durationS: number | null;
  /** Full-scale reference in seconds — the bar fills `durationS / maxS`. */
  maxS: number;
  className?: string;
}

/**
 * §8.5 horizontal CSS duration bar. A real measurement fills proportionally to
 * `maxS` in the §6.2 "running" colour; a `null` duration renders a hatched
 * "neměřeno" track (NEVER an empty/zero bar, so absence of data is visibly
 * distinct from a zero-length step).
 */
export function DurationBar({ durationS, maxS, className }: DurationBarProps) {
  if (durationS == null) {
    return (
      <div
        role="img"
        aria-label="neměřeno"
        title="neměřeno"
        className={cn('h-2 w-full overflow-hidden rounded-full', className)}
        style={{
          backgroundImage:
            'repeating-linear-gradient(45deg, #e2e8f0 0 4px, #f1f5f9 4px 8px)',
        }}
      />
    );
  }

  const pct = maxS > 0 ? Math.min(100, Math.max(0, (durationS / maxS) * 100)) : 0;
  return (
    <div
      role="progressbar"
      aria-valuenow={durationS}
      aria-valuemin={0}
      aria-valuemax={maxS}
      className={cn('h-2 w-full overflow-hidden rounded-full bg-slate-100', className)}
    >
      <div
        className="h-full rounded-full"
        style={{ width: `${pct}%`, backgroundColor: 'var(--status-running)' }}
      />
    </div>
  );
}
