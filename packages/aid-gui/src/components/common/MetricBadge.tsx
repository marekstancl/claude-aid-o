import { cn } from '../../lib/utils';

interface MetricBadgeProps {
  /** The metric value; `null` means "not measured", rendered as the null label (never 0). */
  value: number | string | null;
  /** Optional unit suffix appended to a non-null value (e.g. "s", "%"). */
  unit?: string;
  /** Label shown when `value == null` (defaults to "N/A"). */
  nullLabel?: string;
  className?: string;
}

/**
 * §8.5 metric chip with tabular figures so columns line up. A `null` value is
 * an explicit "N/A" (never silently coerced to 0); a present value renders in
 * tabular-nums with its optional unit.
 */
export function MetricBadge({ value, unit, nullLabel, className }: MetricBadgeProps) {
  if (value == null) {
    return (
      <span data-metric className={cn('text-slate-400', className)}>
        {nullLabel ?? 'N/A'}
      </span>
    );
  }
  return (
    <span data-metric className={cn('tabular-nums', className)}>
      {value}
      {unit}
    </span>
  );
}
