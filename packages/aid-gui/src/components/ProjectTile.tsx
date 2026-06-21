import { Link } from 'react-router-dom';
import type { Explanation, FsmState, Project, RunDetail, StatusKey } from '@aid/contract';
import { cn } from '../lib/utils';
import { StatusDot } from './common/StatusDot';
import { MetricBadge } from './common/MetricBadge';
import { ExplanationLine } from './common/ExplanationLine';
import { CheckpointStrip } from './CheckpointStrip';

/** §6.2 token for an FSM state (drives the header dot colour). */
const FSM_STATUS: Record<FsmState, StatusKey> = {
  READY: 'ceka',
  EXECUTE: 'bezi',
  GATES: 'bezi',
  ESCALATION: 'eskalace',
  DONE: 'proslo',
  ERROR: 'selhalo',
};

/** Czech word per FSM state (fallback when no dictionary explanation is supplied). */
const FSM_WORD: Record<FsmState, string> = {
  READY: 'připraveno',
  EXECUTE: 'běží krok',
  GATES: 'kontroly',
  ESCALATION: 'eskalace',
  DONE: 'hotovo',
  ERROR: 'chyba',
};

/** Short Czech relative phrase for an ISO timestamp (e.g. "před 3 h"). */
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

/** Elapsed seconds since an ISO start, or null when unparseable/absent. */
function elapsedS(iso: string | null | undefined, now: number = Date.now()): number | null {
  if (!iso) return null;
  const then = Date.parse(iso);
  if (Number.isNaN(then)) return null;
  return Math.max(0, Math.round((now - then) / 1000));
}

interface ProjectTileProps {
  project: Project;
  /**
   * Detail for the active run, when the data layer has loaded it — enables the
   * full §8.2 anatomy (progress, checkpoints, elapsed). Absent → the tile still
   * renders from `Project` alone (active header + violation badge), never crashes.
   */
  activeRunDetail?: RunDetail | null;
  /** Resolved §6.4 FSM explanation; falls back to a plain Czech word when absent. */
  fsmExplanation?: Explanation | null;
  className?: string;
}

/**
 * §8.2 project tile (Screen A card / Screen G embed). Two variants:
 *
 *  - ACTIVE (`project.activeRun != null`): name + StatusDot, active EPIC id,
 *    a progress bar (currentStep/totalSteps), FSM state + Czech word, a
 *    CheckpointStrip mini, elapsed, and a violation badge.
 *  - IDLE (`project.activeRun == null`): name + idle dot, last-run-ago and the
 *    lifetime run count.
 *
 * The tile NEVER crashes on `activeRun:null` — the idle branch is taken before
 * any active field is read. Clicking the tile deep-links to Screen B.
 */
export function ProjectTile({ project, activeRunDetail, fsmExplanation, className }: ProjectTileProps) {
  const active = project.activeRun;
  const openViolations = project.health.openViolations;

  return (
    <Link
      to={`/p/${project.id}`}
      data-project-tile={project.id}
      data-variant={active ? 'active' : 'idle'}
      className={cn(
        'flex flex-col gap-2 rounded-lg border border-slate-200 bg-white p-4 no-underline transition hover:border-slate-300 hover:shadow-sm',
        className,
      )}
    >
      {/* Header: name + status dot + (optional) violation badge. */}
      <div className="flex items-start justify-between gap-2">
        <span className="flex items-center gap-2">
          <StatusDot status={active ? FSM_STATUS[active.state] : 'necinne'} />
          <span className="text-sm font-semibold text-slate-800">{project.name}</span>
        </span>
        {openViolations > 0 && (
          <span
            data-violations
            className="rounded-full border border-amber-300 bg-amber-50 px-2 py-0.5 text-xs font-medium text-amber-700"
            title={`${openViolations} otevřených porušení`}
          >
            ⚠ {openViolations}
          </span>
        )}
      </div>

      {active ? (
        <ActiveBody
          activeRun={active}
          detail={activeRunDetail}
          fsmExplanation={fsmExplanation}
        />
      ) : (
        <IdleBody project={project} />
      )}
    </Link>
  );
}

function ActiveBody({
  activeRun,
  detail,
  fsmExplanation,
}: {
  activeRun: NonNullable<Project['activeRun']>;
  detail?: RunDetail | null;
  fsmExplanation?: Explanation | null;
}) {
  const total = detail?.totalSteps ?? 0;
  const current = detail?.currentStep ?? 0;
  const pct = total > 0 ? Math.min(100, Math.max(0, (current / total) * 100)) : 0;
  const elapsed = elapsedS(detail?.startedAt);

  return (
    <>
      <div className="text-xs font-medium tabular-nums text-slate-500">{activeRun.epicId}</div>

      {/* Progress bar (currentStep / totalSteps). Unknown total → indeterminate hatched. */}
      {total > 0 ? (
        <div
          role="progressbar"
          aria-valuenow={current}
          aria-valuemin={0}
          aria-valuemax={total}
          className="h-1.5 w-full overflow-hidden rounded-full bg-slate-100"
        >
          <div
            className="h-full rounded-full"
            style={{ width: `${pct}%`, backgroundColor: 'var(--status-running)' }}
          />
        </div>
      ) : (
        <div
          role="img"
          aria-label="postup neznámý"
          className="h-1.5 w-full overflow-hidden rounded-full"
          style={{
            backgroundImage: 'repeating-linear-gradient(45deg, #e2e8f0 0 4px, #f1f5f9 4px 8px)',
          }}
        />
      )}

      <div className="flex items-center justify-between gap-2 text-xs text-slate-500">
        <span className="tabular-nums">
          {total > 0 ? `krok ${current}/${total}` : 'krok ?/?'}
        </span>
        <span className="flex items-center gap-1">
          <span className="font-medium">{activeRun.state}</span>
          <MetricBadge value={elapsed} unit="s" nullLabel="—" className="text-xs" />
        </span>
      </div>

      {/* FSM state + human word. */}
      {fsmExplanation ? (
        <ExplanationLine explanation={fsmExplanation} className="text-xs" />
      ) : (
        <p className="text-xs text-slate-500">{FSM_WORD[activeRun.state]}</p>
      )}

      {/* Checkpoint mini strip — empty array degrades to grey placeholders (never crash). */}
      <CheckpointStrip checkpoints={detail?.checkpoints ?? []} />
    </>
  );
}

function IdleBody({ project }: { project: Project }) {
  const lastAgo = project.lastActivityAt ? relativeCzech(project.lastActivityAt) : 'nikdy';
  return (
    <div className="flex flex-col gap-1 text-xs text-slate-500">
      <p>nečinné</p>
      <div className="flex items-center justify-between gap-2">
        <span>
          poslední běh: <span className="tabular-nums">{lastAgo}</span>
        </span>
        <span className="tabular-nums">
          {project.runsTotal} {runWord(project.runsTotal)}
        </span>
      </div>
    </div>
  );
}

/** Czech plural for "run" (1 běh, 2-4 běhy, 5+ běhů). */
function runWord(n: number): string {
  if (n === 1) return 'běh';
  if (n >= 2 && n <= 4) return 'běhy';
  return 'běhů';
}
