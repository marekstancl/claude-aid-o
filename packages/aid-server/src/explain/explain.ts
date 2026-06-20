/**
 * Deterministic Czech explainer (EPIC E-047-3_7, Step 9) — spec §6.4.
 *
 * `explain()` turns a raw signal (kind, id, context) into a human-readable Czech
 * {@link Explanation}. It is a PURE function: same input → identical output, no
 * async, no LLM, no network, no randomness (§13.5). LLM narration is explicitly
 * MVP2; the static layer here stays the fallback and the terminology source.
 *
 * `explain()` MUST NEVER throw (§6.3 narrator note): an unknown id resolves to a
 * flagged "Neznámá událost" entry rather than blowing up the WS stream or a tile
 * render.
 *
 * HONESTY (§5.7): a missing / null signal never becomes a fabricated positive.
 *  - At the DICTIONARY level callers route null signals to dedicated flagged keys
 *    (`verdict:pending` = "ještě neproběhla", `concept:risk:neurceno` =
 *    "zatím nelze určit", `concept:success_probability_mvp2`).
 *  - At the INTERPOLATION level an absent / null `{var}` renders as the flagged
 *    placeholder `«neměřeno»`, never as an empty string that would read like a
 *    confident statement with the awkward gap silently closed.
 */

import { STATUS } from '@aid/contract';
import type { StatusKey } from '@aid/contract';
import { DICTIONARY_CS } from './dictionary.cs.js';
import type { DictionaryEntry, ExplainInput, Explanation } from './types.js';

/** Flagged placeholder for an absent / null interpolation variable (§5.7 honesty). */
export const MISSING_VAR_PLACEHOLDER = '«neměřeno»';

/**
 * The dictionary key the unknown-id fallback uses. Not a real §6.3 entry — it is
 * synthesized so the resolver always has a target and `explain()` never throws.
 */
const UNKNOWN_HEADLINE = 'Neznámá událost: {id}';
const UNKNOWN_DETAIL =
  'Tahle událost zatím nemá lidský popis. Surová data jsou níž.';

/**
 * Sink for unknown ids so the dictionary can grow (§6.3 narrator note). Default
 * logs to stderr; tests can swap it via {@link setUnknownIdSink}. Kept module-
 * local so the swap does not leak across the public `explain()` contract.
 */
let unknownIdSink: (key: string, input: ExplainInput) => void = (key) => {
  // eslint-disable-next-line no-console -- intentional growth signal, not app output
  console.warn(`[explain] unknown dictionary key: ${key}`);
};

/** Override the unknown-id sink (test seam). Returns the previous sink. */
export function setUnknownIdSink(
  sink: (key: string, input: ExplainInput) => void,
): (key: string, input: ExplainInput) => void {
  const prev = unknownIdSink;
  unknownIdSink = sink;
  return prev;
}

/**
 * Build the ordered list of candidate dictionary keys, most-specific first
 * (§6.4 resolveKey). The discriminator is data-driven per `kind`:
 *  - event:   `${reason}` then `${to}` then `${verdict}` then `${pass|fail}`
 *  - verdict: raw id only (the id IS the discriminator, e.g. "pass")
 *  - others:  `${verdict}` / `${reason}` if present, else bare key
 *
 * Returns bare `${kind}:${id}` last so a generic entry always backs the specific
 * ones. Discriminators that are null/undefined/empty are skipped (honesty: a
 * missing discriminator must NOT silently match a positive-coded specific key).
 */
export function resolveKeyCandidates(input: ExplainInput): string[] {
  const { kind, id, context } = input;
  const base = `${kind}:${id}`;
  const candidates: string[] = [];
  const ctx = context ?? {};

  const push = (disc: unknown): void => {
    if (disc === null || disc === undefined) return;
    const s = String(disc);
    if (s.length === 0) return;
    candidates.push(`${base}:${s}`);
  };

  switch (kind) {
    case 'event': {
      // Transition: try "from→to" composite, then wildcard "*→to" (§6.3 B).
      // Transitions are keyed ONLY by these composites — there is no bare ":to".
      if (ctx.from != null && ctx.to != null) {
        candidates.push(`${base}:${String(ctx.from)}→${String(ctx.to)}`);
        candidates.push(`${base}:*→${String(ctx.to)}`);
      }
      push(ctx.reason);
      push(ctx.verdict);
      push(ctx.result);
      // pass/fail flavour for gate_complete etc.
      if (ctx.passed === true) push('pass');
      if (ctx.passed === false) push('fail');
      break;
    }
    case 'verdict': {
      // The id itself is the discriminator; no further key needed.
      break;
    }
    case 'check': {
      // §6.3 F names the compliance overall key `compliance:overall:pass|fail`
      // (NOT `check:overall:...`) — map it here so callers can address it as the
      // natural ExplainInput {kind:'check', id:'overall', context:{overall}}.
      if (id === 'overall') {
        if (ctx.overall != null && String(ctx.overall).length > 0) {
          candidates.push(`compliance:overall:${String(ctx.overall)}`);
        }
        if (ctx.verdict != null && String(ctx.verdict).length > 0) {
          candidates.push(`compliance:overall:${String(ctx.verdict)}`);
        }
      }
      push(ctx.overall);
      push(ctx.verdict);
      push(ctx.reason);
      break;
    }
    case 'role': {
      push(ctx.outcome);
      push(ctx.verdict);
      break;
    }
    default: {
      push(ctx.verdict);
      push(ctx.reason);
      break;
    }
  }

  candidates.push(base);
  return candidates;
}

/** Resolve the most-specific matching {@link DictionaryEntry}, or null. */
export function resolveEntry(input: ExplainInput): DictionaryEntry | null {
  for (const key of resolveKeyCandidates(input)) {
    const entry = DICTIONARY_CS[key];
    if (entry) return entry;
  }
  return null;
}

/**
 * Interpolate `{var}` placeholders from `context` into a template. An absent or
 * null variable renders as {@link MISSING_VAR_PLACEHOLDER} (§5.7) — never an
 * empty string. Deterministic: no Date, no randomness.
 */
export function interpolate(
  template: string,
  context: Record<string, unknown> | undefined,
): string {
  const ctx = context ?? {};
  return template.replace(/\{(\w+)\}/g, (_match, name: string) => {
    const value = ctx[name];
    if (value === null || value === undefined || value === '') {
      return MISSING_VAR_PLACEHOLDER;
    }
    return String(value);
  });
}

/** Resolve a StatusKey to its CSS-var colour (§6.2 STATUS). */
function colorFor(status: StatusKey): string {
  return STATUS[status].color;
}

/**
 * Resolve a raw signal into a deterministic Czech {@link Explanation} (§6.4).
 * Pure, synchronous, never throws.
 */
export function explain(input: ExplainInput): Explanation {
  const entry = resolveEntry(input);

  if (!entry) {
    // Unknown id — flagged fallback, logged so the dictionary can grow (§6.3).
    const lastKey = `${input.kind}:${input.id}`;
    unknownIdSink(lastKey, input);
    const status: StatusKey = 'ceka';
    return {
      headline: interpolate(UNKNOWN_HEADLINE, { id: input.id }),
      detail: UNKNOWN_DETAIL,
      status,
      color: colorFor(status),
    };
  }

  return {
    headline: interpolate(entry.headlineTemplate, input.context),
    detail: interpolate(entry.detailTemplate, input.context),
    status: entry.status,
    color: colorFor(entry.status),
  };
}
