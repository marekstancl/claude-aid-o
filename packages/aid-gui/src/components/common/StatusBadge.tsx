import {
  Circle,
  CircleDashed,
  CheckCircle2,
  XCircle,
  Square,
  AlertTriangle,
  type LucideIcon,
} from 'lucide-react';
import { STATUS, type StatusKey } from '@aid/contract';
import { cn } from '../../lib/utils';

/**
 * §8.5 status → lucide glyph map. Eight keys, one per §6.2 token.
 * The plan's symbolic names (circle/half-circle/check/cross/square/warn/ring)
 * resolve to the nearest lucide glyph so colour is never the only signal.
 */
export const STATUS_ICON: Record<StatusKey, LucideIcon> = {
  bezi: Circle, // circle
  ceka: CircleDashed, // half-circle (dashed ring)
  proslo: CheckCircle2, // check
  selhalo: XCircle, // cross
  zablokovano: Square, // square
  eskalace: AlertTriangle, // warn
  pozor: AlertTriangle, // warn
  necinne: CircleDashed, // ring
};

/** §6.2 fallback when an unexpected value slips past the type system. */
const FALLBACK: StatusKey = 'necinne';

/**
 * Coerce an (untyped at runtime) status to a known §6.2 key, defaulting to
 * `necinne` (grey) with a console.warn — colour is NEVER undefined.
 */
function safeStatus(status: StatusKey): StatusKey {
  if (status in STATUS) return status;
  // eslint-disable-next-line no-console
  console.warn(`StatusBadge: unknown status "${String(status)}", defaulting to "${FALLBACK}".`);
  return FALLBACK;
}

interface StatusBadgeProps {
  status: StatusKey;
  /** Override the §6.2 Czech word (defaults to STATUS[status].label). */
  label?: string;
  className?: string;
}

/**
 * §6.2/§8.5 status badge: Czech word + lucide icon + the canonical STATUS
 * colour, on a neutral light surface. Colour is always paired with both a word
 * and an icon, so the badge is colorblind-safe (red selhalo vs green prošlo are
 * distinguishable by word + glyph alone).
 */
export function StatusBadge({ status, label, className }: StatusBadgeProps) {
  const key = safeStatus(status);
  const Icon = STATUS_ICON[key];
  const color = STATUS[key].color;
  return (
    <span
      data-status={key}
      style={{ borderColor: color, color }}
      className={cn(
        'inline-flex items-center gap-1.5 rounded-full border bg-white px-2.5 py-0.5 text-xs font-medium',
        className,
      )}
    >
      <Icon aria-hidden className="h-3.5 w-3.5" />
      {label ?? STATUS[key].label}
    </span>
  );
}
