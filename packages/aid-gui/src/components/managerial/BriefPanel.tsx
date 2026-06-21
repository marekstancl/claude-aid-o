import type { Brief, Project, RunDetail, Explanation, BacklogDelta } from '@aid/contract';
import { cn } from '../../lib/utils';
import { Card } from './Card';
import { BriefItemRow, sortBriefItems } from './BriefItemRow';
import { RiskBadge } from './RiskBadge';
import { DecisionsNeededList } from './DecisionsNeededList';
import { ChangedSinceList } from './ChangedSinceList';
import { ProjectTileGrid } from '../ProjectTileGrid';

interface BriefPanelProps {
  brief: Brief;
  /** Render scope. Drives which blocks show (infra-only embeds Přehled projektů). */
  scope: 'infra' | 'project' | 'plan';
  /** Infra-scope embedded Přehled projektů tiles (ignored at other scopes). */
  projects?: Project[];
  activeRunDetails?: Record<string, RunDetail | null | undefined>;
  fsmExplanations?: Record<string, Explanation | null | undefined>;
  /** Optional backlog delta for the "Co se změnilo" block's backlog slice. */
  backlogDelta?: BacklogDelta | null;
  className?: string;
}

/**
 * THE managerial Brief panel (§8.2) — one Brief, three scopes via the `scope`
 * prop. Renders the seven §8.2 blocks in §13.4 priority order:
 *
 *   1. Rozhodnutí (decisionsNeeded)   — most urgent: needs a human
 *   2. Co blokuje (blockers)
 *   3. Riziko (risk + success-probability placeholder)
 *   4. Na co pozor (watchOuts)
 *   5. Co se změnilo (sinceLastSeen + backlog delta)
 *   6. Co bude dál (nextUp)
 *   7. Přehled projektů (infra scope ONLY)
 *
 * Each BriefItem reuses {@link BriefItemRow} (ExplanationLine + StatusDot +
 * deep-link). Items sort blocking → warn → info then `at` desc. Empty blocks
 * collapse to a calm "Nic …" line (they never disappear). On mobile each block
 * is a collapsible Card.
 *
 * The success-probability slot ALWAYS renders the `concept:success_probability_mvp2`
 * placeholder ("přesnější odhad přijde s agentem (MVP2)", grey) — never a number.
 * Per the MVP1 contract invariant `Brief.successProbability` is `{value:null,
 * source:null}`; this component does not read `.value` as a number.
 */
export function BriefPanel({
  brief,
  scope,
  projects = [],
  activeRunDetails,
  fsmExplanations,
  backlogDelta,
  className,
}: BriefPanelProps) {
  return (
    <div data-brief-panel data-scope={scope} className={cn('space-y-4', className)}>
      {/* 1. Rozhodnutí. */}
      <Card title="Rozhodnutí" collapsibleOnMobile>
        <DecisionsNeededList items={brief.decisionsNeeded} embedded />
      </Card>

      {/* 2. Co blokuje. */}
      <BriefBlock title="Co blokuje" emptyLabel="Nic neblokuje" items={brief.blockers} block="blockers" />

      {/* 3. Riziko + success-probability placeholder. */}
      <Card title="Riziko" collapsibleOnMobile>
        <div className="space-y-2" data-risk-block>
          <RiskBadge risk={brief.risk} />
          {/* The success-probability slot ALWAYS renders the MVP2 placeholder. */}
          <p data-success-probability className="text-sm text-slate-400">
            Přesnější odhad úspěchu přijde s agentem (MVP2).
          </p>
        </div>
      </Card>

      {/* 4. Na co pozor. */}
      <BriefBlock
        title="Na co si dát pozor"
        emptyLabel="Nic, na co bys teď musel dávat pozor"
        items={brief.watchOuts}
        block="watchOuts"
      />

      {/* 5. Co se změnilo. */}
      <Card title="Co se změnilo od minule" collapsibleOnMobile>
        <ChangedSinceList sinceLastSeen={brief.sinceLastSeen} backlogDelta={backlogDelta} embedded />
      </Card>

      {/* 6. Co bude dál. */}
      <BriefBlock title="Co bude dál" emptyLabel="Ve frontě nic nečeká" items={brief.nextUp} block="nextUp" />

      {/* 7. Přehled projektů — infra scope ONLY. */}
      {scope === 'infra' && (
        <Card title="Přehled projektů" collapsibleOnMobile>
          <ProjectTileGrid
            projects={projects}
            activeRunDetails={activeRunDetails}
            fsmExplanations={fsmExplanations}
          />
        </Card>
      )}
    </div>
  );
}

/** A BriefItem block: sorted rows, or a calm "Nic …" line when empty. */
function BriefBlock({
  title,
  emptyLabel,
  items,
  block,
}: {
  title: string;
  emptyLabel: string;
  items: import('@aid/contract').BriefItem[];
  block: string;
}) {
  const sorted = sortBriefItems(items);
  return (
    <Card
      title={title}
      collapsibleOnMobile
      action={<span className="text-xs tabular-nums text-slate-400">{items.length}</span>}
    >
      {sorted.length === 0 ? (
        <p data-block-empty className="text-sm text-slate-400">
          {emptyLabel}
        </p>
      ) : (
        <ul className="space-y-0.5" data-block-list={block}>
          {sorted.map((item) => (
            <li key={item.id}>
              <BriefItemRow item={item} />
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}
