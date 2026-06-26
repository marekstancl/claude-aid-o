import { STATUS, type Checkpoint, type CheckpointId, type StatusKey, type Verdict } from '@aid/contract';
import { cn } from '../lib/utils';
import { StatusDot } from './common/StatusDot';

/** The six CP slots, in canonical order — used to render placeholders for stub runs. */
const CP_ORDER: CheckpointId[] = ['CP1', 'CP2', 'CP3', 'CP4', 'CP5', 'CP6'];

/**
 * §6.2 STATUS token for a checkpoint verdict.
 *
 * The contract `Verdict` enum is `pass | fail | skipped | unverifiable | null`.
 * A `null` verdict is "not recorded" — it MUST render as the `necinne` (idle)
 * placeholder with a "?" glyph, NEVER as `proslo` (a fabricated green pass) or 0.
 * Forward/legacy aliases (`pass_with_notes`, `pending`) are accepted defensively
 * so unexpected data degrades gracefully instead of crashing.
 */
function verdictStatus(verdict: Verdict | string | null): StatusKey {
  switch (verdict) {
    case 'pass':
      return 'proslo';
    case 'fail':
      return 'selhalo';
    case 'unverifiable':
      return 'pozor';
    case 'skipped':
      return 'ceka';
    // Defensive aliases (not in the current enum, but tolerated, never crash):
    case 'pass_with_notes':
      return 'pozor';
    case 'pending':
      return 'ceka';
    case null:
    default:
      // null / unknown verdict = "not recorded" → idle placeholder, never a pass.
      return 'necinne';
  }
}

/** Czech word shown under a dot. `null` verdict → "?" (never a fabricated pass/0). */
function verdictLabel(verdict: Verdict | string | null): string {
  if (verdict == null) return '?';
  const key = verdictStatus(verdict);
  return STATUS[key].label;
}

/**
 * "stopa: …" provenance hint. A `null` provenance is "not recorded" (never
 * "unverifiable"); an array is joined; a string is shown verbatim.
 */
function provenanceHint(provenance: string | string[] | null): string {
  if (provenance == null) return 'stopa: nezaznamenáno';
  const text = Array.isArray(provenance) ? provenance.filter(Boolean).join(', ') : provenance;
  return text.trim() ? `stopa: ${text}` : 'stopa: nezaznamenáno';
}

/**
 * Repeat-count superscript. A present count ≥ 1 renders "×N"; a `null` count is
 * "unknown" → "?", NEVER 0 (a stub/legacy run that never recorded a repeat must
 * not look like "ran zero times").
 */
function repeatSuperscript(repeatCount: number | null): string | null {
  if (repeatCount == null) return '?';
  if (repeatCount <= 1) return null; // 1 = ran once, no superscript noise
  return `×${repeatCount}`;
}

interface CheckpointStripProps {
  checkpoints: Checkpoint[];
  className?: string;
}

/**
 * §8.2 CP1–CP6 dot strip. Each checkpoint renders a {@link StatusDot} in its
 * verdict colour, the §6.2 Czech word, a "×N" repeat superscript, and a
 * provenance hint. The honesty contract:
 *
 *  - `verdict:null` → `necinne` dot + "?" (never `proslo`/green, never 0).
 *  - `provenance:null` → "stopa: nezaznamenáno" (null = not recorded).
 *  - `repeatCount:null` → "?" superscript (never 0).
 *  - an empty `checkpoints` array (stub run) → six grey `necinne` placeholders
 *    + "kontroly zatím neproběhly" gloss (never six green dots, never a crash).
 */
export function CheckpointStrip({ checkpoints, className }: CheckpointStripProps) {
  // Stub run: nothing recorded yet → six idle placeholders + honest gloss.
  if (checkpoints.length === 0) {
    return (
      <div data-checkpoint-strip data-empty className={cn('flex flex-col gap-1', className)}>
        <div className="flex items-center gap-2">
          {CP_ORDER.map((id) => (
            <span key={id} className="flex flex-col items-center gap-0.5" title={`${id} — nečinné`}>
              <StatusDot status="necinne" title={`${id} — nečinné`} />
              <span className="text-[10px] leading-none text-slate-400">{id}</span>
            </span>
          ))}
        </div>
        <p className="text-xs text-slate-400">kontroly zatím neproběhly</p>
      </div>
    );
  }

  return (
    <ul data-checkpoint-strip className={cn('flex flex-wrap items-start gap-x-3 gap-y-2', className)}>
      {checkpoints.map((cp) => {
        const status = verdictStatus(cp.verdict);
        const label = verdictLabel(cp.verdict);
        const repeat = repeatSuperscript(cp.repeatCount);
        const hint = provenanceHint(cp.provenance);
        const title = `${cp.id} ${cp.label ? `(${cp.label})` : ''} — ${label}`.trim();
        return (
          <li
            key={cp.id}
            data-cp={cp.id}
            data-verdict={cp.verdict ?? 'null'}
            data-status={status}
            className="flex flex-col items-center gap-0.5"
            title={`${title}\n${hint}`}
          >
            <span className="flex items-baseline gap-0.5">
              <StatusDot status={status} title={title} />
              {repeat != null && (
                <sup
                  data-repeat={cp.repeatCount ?? 'null'}
                  className="text-[9px] leading-none text-slate-400 tabular-nums"
                >
                  {repeat}
                </sup>
              )}
            </span>
            <span className="text-[10px] font-medium leading-none text-slate-500">{cp.id}</span>
            <span className="text-[10px] leading-none text-slate-400">{label}</span>
          </li>
        );
      })}
    </ul>
  );
}
