/**
 * FSM state display constants — shared between ProjectTile and PlanPhaseTimeline.
 *
 * §6.2 tokens for FSM states used in status glyphs, and Czech phase words
 * displayed as fallback labels when no dictionary explanation is supplied.
 */

import type { FsmState, StatusKey } from '@aid/contract';

/** §6.2 token for an FSM state (drives the header dot colour). */
export const FSM_STATUS: Record<FsmState, StatusKey> = {
  READY: 'ceka',
  EXECUTE: 'bezi',
  GATES: 'bezi',
  ESCALATION: 'eskalace',
  DONE: 'proslo',
  ERROR: 'selhalo',
};

/** Czech word per FSM state (fallback when no dictionary explanation is supplied). */
export const FSM_WORD: Record<FsmState, string> = {
  READY: 'připraveno',
  EXECUTE: 'běží',
  GATES: 'kontroly',
  ESCALATION: 'eskalace',
  DONE: 'hotovo',
  ERROR: 'chyba',
};
