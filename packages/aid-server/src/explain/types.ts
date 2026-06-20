/**
 * Explainer module types (EPIC E-047-3_7, Step 9) — spec §6.4.
 *
 * `DictionaryEntry` (static content) and `Explanation` (runtime resolution) are
 * the canonical contract types (§7.5) and are re-exported here so the explain/
 * module is the single import surface for consumers. `ExplainInput` is the
 * explainer's own call shape (§6.4) — it is NOT part of the wire contract, so it
 * lives here rather than in @aid/contract.
 */

import type { DictionaryEntry } from '@aid/contract';

// Re-export the canonical contract types so callers can import everything from
// the explain module barrel (§6.4: "types re-exported from aid-contract §7.5").
export type { DictionaryEntry, Explanation } from '@aid/contract';

/**
 * The `kind` discriminator (§6.4 ExplainInput.kind). Sourced from the canonical
 * `DictionaryEntry['kind']` so a new dictionary kind cannot drift from the input
 * union — they are the same type by construction.
 */
export type ExplainKind = DictionaryEntry['kind'];

/**
 * Input to {@link explain}. A signal arrives as (kind, id, context); the
 * explainer resolves the most-specific dictionary key, interpolates `context`
 * vars into the Czech templates, and returns an {@link Explanation} (§6.4).
 */
export interface ExplainInput {
  kind: ExplainKind;
  /** e.g. "fsm_precondition_fail", "READY", "CP3". */
  id: string;
  /** {step, total_steps, reason, from, to, focus, count, ...} — interpolated into templates. */
  context?: Record<string, unknown>;
}
