import { STATUS, type StatusKey } from '@aid/contract';
import { cn } from '../../lib/utils';
import { STATUS_ICON } from './StatusBadge';

/** §6.2 fallback when an unexpected value slips past the type system. */
const FALLBACK: StatusKey = 'necinne';

function safeStatus(status: StatusKey): StatusKey {
  if (status in STATUS) return status;
  // eslint-disable-next-line no-console
  console.warn(`StatusDot: unknown status "${String(status)}", defaulting to "${FALLBACK}".`);
  return FALLBACK;
}

interface StatusDotProps {
  status: StatusKey;
  /** Accessible title; defaults to the §6.2 Czech word. */
  title?: string;
  className?: string;
}

/**
 * Compact §8.5 variant of {@link StatusBadge}: the same lucide glyph in the
 * canonical STATUS colour, with an aria-label so the meaning survives without
 * colour. Used where a full badge would be too heavy (dense lists, headers).
 */
export function StatusDot({ status, title, className }: StatusDotProps) {
  const key = safeStatus(status);
  const Icon = STATUS_ICON[key];
  const color = STATUS[key].color;
  const label = title ?? STATUS[key].label;
  return (
    <Icon
      data-status={key}
      role="img"
      aria-label={label}
      style={{ color }}
      className={cn('inline-block h-3.5 w-3.5 shrink-0', className)}
    />
  );
}
