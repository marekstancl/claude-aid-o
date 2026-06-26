import { Popover } from '@base-ui/react/popover';
import type { Risk, RiskLevel, StatusKey } from '@aid/contract';
import { STATUS } from '@aid/contract';
import { cn } from '../../lib/utils';
import { STATUS_ICON } from '../common/StatusBadge';
import { StatusDot } from '../common/StatusDot';

/**
 * §13.10 `concept:risk:*` colour token per deterministic RiskLevel.
 * nízké → prošlo (green), střední → pozor (amber), vysoké → zablokováno
 * (orange/blocked), neurčeno → čeká (grey). These mirror the dictionary entries
 * `concept:risk:nizke|stredni|vysoke|neurceno` exactly.
 */
const RISK_STATUS: Record<RiskLevel, StatusKey> = {
  nizke: 'proslo',
  stredni: 'pozor',
  vysoke: 'zablokovano',
  neurceno: 'ceka',
};

/** Czech badge word per RiskLevel (the level itself, not the §6.2 status word). */
const RISK_WORD: Record<RiskLevel, string> = {
  nizke: 'nízké',
  stredni: 'střední',
  vysoke: 'vysoké',
  neurceno: 'neurčeno',
};

interface RiskBadgeProps {
  risk: Risk;
  className?: string;
}

/**
 * §13.2 deterministic risk badge: a colour-coded "Riziko <level>" chip whose
 * colour is the §13.10 `concept:risk:*` token, plus a Popover listing
 * `risk.reasons[]`. The level is ALWAYS paired with a Czech word + an icon, so
 * the badge is colorblind-safe.
 *
 * `level === 'neurceno'` is the honest "not enough data" state: the word is
 * "neurčeno" and the Popover says "málo dat" (never a fabricated low/zero risk).
 */
export function RiskBadge({ risk, className }: RiskBadgeProps) {
  const status = RISK_STATUS[risk.level] ?? 'ceka';
  const color = STATUS[status].color;
  const Icon = STATUS_ICON[status];
  const word = RISK_WORD[risk.level] ?? 'neurčeno';

  return (
    <Popover.Root>
      <Popover.Trigger
        data-risk-badge
        data-level={risk.level}
        data-status={status}
        style={{ borderColor: color, color }}
        className={cn(
          'inline-flex items-center gap-1.5 rounded-full border bg-white px-2.5 py-0.5 text-xs font-medium',
          className,
        )}
      >
        <Icon aria-hidden className="h-3.5 w-3.5" />
        Riziko {word}
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Positioner sideOffset={6} className="z-50">
          <Popover.Popup className="max-w-xs rounded-xl border border-slate-200 bg-white p-3 shadow-lg">
            <Popover.Title className="mb-1.5 text-sm font-semibold text-slate-900">
              Riziko {word}
            </Popover.Title>
            {risk.reasons.length === 0 ? (
              <p data-risk-empty className="text-sm text-slate-500">
                {risk.level === 'neurceno' ? 'málo dat' : 'žádné rizikové signály'}
              </p>
            ) : (
              <ul className="space-y-1.5">
                {risk.reasons.map((reason, i) => (
                  <li key={`${reason.signal}-${i}`} className="flex items-start gap-2 text-sm text-slate-700">
                    <StatusDot status={reason.status} className="mt-0.5" />
                    <span>
                      {reason.text}
                      {reason.value !== undefined && (
                        <span className="ml-1 tabular-nums text-slate-400">({reason.value})</span>
                      )}
                    </span>
                  </li>
                ))}
              </ul>
            )}
            {risk.confidence === 'low' && (
              <p className="mt-2 text-xs text-slate-400">nízká důvěra — některé signály chybí</p>
            )}
          </Popover.Popup>
        </Popover.Positioner>
      </Popover.Portal>
    </Popover.Root>
  );
}

export { RISK_STATUS, RISK_WORD };
