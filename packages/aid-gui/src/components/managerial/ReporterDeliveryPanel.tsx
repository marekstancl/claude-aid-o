import { useCallback } from 'react';
import { Link } from 'react-router-dom';
import type { ReporterDelivery, DeliveryOutcome, StatusKey } from '@aid/contract';
import { Card } from './Card';
import { StatusBadge } from '../common/StatusBadge';
import { StatusDot } from '../common/StatusDot';
import { RawMarkdownDialog } from './RawMarkdownDialog';
import { getRunFile, ApiError } from '../../lib/api';

/** §6.2 token + Czech word per Reporter delivery outcome. */
const OUTCOME: Record<NonNullable<DeliveryOutcome>, { status: StatusKey; label: string }> = {
  pass: { status: 'proslo', label: 'dodáno' },
  fail: { status: 'selhalo', label: 'selhalo' },
  partial: { status: 'pozor', label: 'částečně' },
};

interface ReporterDeliveryPanelProps {
  delivery: ReporterDelivery;
  /**
   * Run-scope coordinates for fetching testEvidence artifacts via the hardened
   * /file endpoint. If omitted, evidence links are disabled.
   */
  projectId?: string;
  epicId?: string;
  runId?: string;
  className?: string;
}

/**
 * MF6 plan-boundary Reporter delivery report (§4.3). Read-only.
 *
 * Honesty contract:
 *  - `present:false` → "Reporter zatím neběžel".
 *  - each `testEvidence[]` row carries an `exists`-driven StatusDot: `exists:false`
 *    is flagged "chybí na disku" (pozor) and NEVER dropped — a missing/fabricated
 *    artifact must stay visible.
 *  - the raw `.md` opens lazily in a drawer; a fetch failure degrades there.
 *  - testEvidence rows are `reporter/*` files (allow-listed) and link through
 *    the hardened `/file` endpoint. When run coords are absent, evidence links
 *    are disabled.
 *  - the delivery report's OWN raw .md is NOT allow-listed (future server follow-up).
 */
export function ReporterDeliveryPanel({
  delivery,
  projectId,
  epicId,
  runId,
  className,
}: ReporterDeliveryPanelProps) {
  // Build a link to a reporter/* evidence file via the hardened endpoint.
  const evidenceHref = useCallback(
    (name: string) => {
      if (!projectId || !epicId || !runId) {
        // No run context — link disabled. In the UI, exists:false rows won't
        // have a link anyway, and exists:true rows won't be wrapped in <Link>.
        return '#';
      }
      // The name is expected to be a reporter/* artifact name (e.g. "reporter/foo.txt").
      return `/api/epics/${encodeURIComponent(projectId)}/${encodeURIComponent(epicId)}/runs/${encodeURIComponent(runId)}/file?name=${encodeURIComponent(name)}`;
    },
    [projectId, epicId, runId],
  );
  if (!delivery.present) {
    return (
      <Card title="Dodávka (Reporter)" className={className}>
        <p data-reporter-absent className="text-sm text-slate-500">
          Reporter zatím neběžel
        </p>
      </Card>
    );
  }

  const outcome = delivery.outcome ? OUTCOME[delivery.outcome] : null;

  return (
    <Card
      title="Dodávka (Reporter)"
      // Note: the delivery report's rawRelPath is NOT allow-listed by the server
      // (future follow-up). The testEvidence rows are the fetchable artifacts.
      className={className}
    >
      <div className="space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          {outcome ? (
            <StatusBadge status={outcome.status} label={outcome.label} />
          ) : (
            <span className="text-sm text-slate-400">výsledek nezjištěn</span>
          )}
          {delivery.generatedAt && (
            <time dateTime={delivery.generatedAt} className="text-xs tabular-nums text-slate-400">
              {delivery.generatedAt}
            </time>
          )}
        </div>

        {delivery.summaryCs && <p className="text-sm text-slate-600">{delivery.summaryCs}</p>}

        {/* Test evidence — exists:false flagged "chybí na disku", never dropped. */}
        <div data-reporter-evidence>
          <h4 className="mb-1 text-xs font-semibold uppercase tracking-wide text-slate-400">
            Důkazy ({delivery.testEvidence.length})
          </h4>
          {delivery.testEvidence.length === 0 ? (
            <p className="text-sm text-slate-400">žádné doložené důkazy</p>
          ) : (
            <ul className="space-y-1">
              {delivery.testEvidence.map((ev, i) => (
                <li
                  key={ev.relPath || `${ev.name}-${i}`}
                  data-evidence-exists={ev.exists ? 'true' : 'false'}
                  className="flex items-center gap-2 text-sm"
                >
                  <StatusDot
                    status={ev.exists ? 'proslo' : 'pozor'}
                    title={ev.exists ? 'na disku' : 'chybí na disku'}
                  />
                  {ev.exists && projectId && epicId && runId ? (
                    <a
                      href={evidenceHref(ev.relPath)}
                      className="truncate text-sky-700 hover:underline"
                    >
                      {ev.name}
                    </a>
                  ) : (
                    <span className="truncate text-slate-700">
                      {ev.name}
                      {!ev.exists && <span className="text-amber-700"> — chybí na disku</span>}
                    </span>
                  )}
                </li>
              ))}
            </ul>
          )}
        </div>

        {delivery.warnings.length > 0 && (
          <ul className="space-y-0.5 border-t border-slate-100 pt-2">
            {delivery.warnings.map((w, i) => (
              <li key={i} className="text-xs text-amber-700">
                {w}
              </li>
            ))}
          </ul>
        )}
      </div>
    </Card>
  );
}
