import type { EpicSummary, Explanation, StatusKey } from '@aid/contract';
import { FsmTimeline, type TimelineNode } from '../FsmTimeline';
import { FSM_STATUS, FSM_WORD } from '../../lib/fsmStatus';

interface PlanPhaseTimelineProps {
  /** Member EPICs in plan order (the caller supplies the order; §13.6). */
  epics: EpicSummary[];
  /** `true` → vertical (mobile). */
  vertical?: boolean;
  className?: string;
}

/**
 * §13.6 plan-phase timeline: the plan's member EPICs as a left-to-right walk,
 * each node coloured by that EPIC's latest-run FsmState. This is a thin adapter
 * over the Step 39 {@link FsmTimeline} — it introduces NO new primitive, it only
 * maps EPIC rows onto generic {@link TimelineNode}s.
 *
 * An EPIC with no latest run degrades to the grey `ceka` node ("zatím neběžel")
 * rather than disappearing. Zero member EPICs → FsmTimeline's honest empty line.
 */
export function PlanPhaseTimeline({ epics, vertical = false, className }: PlanPhaseTimelineProps) {
  const nodes: TimelineNode[] = epics.map((epic) => {
    const latest = epic.latestRun;
    const status: StatusKey = latest ? FSM_STATUS[latest.state] : 'ceka';
    const word = latest ? FSM_WORD[latest.state] : 'zatím neběžel';
    const explanation: Explanation = {
      headline: word,
      detail: '',
      status,
      color: '',
    };
    return {
      key: epic.id,
      label: epic.id,
      status,
      explanation,
      at: latest?.startedAt ?? epic.lastActivityAt ?? null,
      current: latest != null && (latest.state === 'EXECUTE' || latest.state === 'GATES'),
    };
  });

  return (
    <FsmTimeline
      nodes={nodes}
      vertical={vertical}
      className={className}
      emptyLabel="plán nemá členské EPICy"
    />
  );
}
