/**
 * Client-side explanation resolver (§6.4).
 *
 * The §6.3/§13.10 dictionary itself is served by `GET /api/explanations`
 * (see {@link getExplanations}) and cached under the react-query key
 * `['explanations']` as a `Record<string, DictionaryEntry>`. This module is the
 * thin, pure runtime layer over that dictionary:
 *
 *   - {@link resolveExplanation} turns ONE `DictionaryEntry` + interpolation
 *     vars into a runtime {@link Explanation} (headline/detail interpolated,
 *     colour resolved from the §6.2 `STATUS` table).
 *   - {@link explainEvent} maps a live {@link ActivityEvent} onto a dictionary
 *     KEY (e.g. `event:fsm_transition:GATES_to_DONE`, `role:auditor:blocking`),
 *     looks it up, and resolves it — falling back to a graceful generic
 *     `ceka` explanation when the key is unknown (never throws, never blanks).
 *
 * Both functions take the resolved dictionary as an argument; fetching/caching
 * is the caller's concern (react-query `['explanations']`), keeping this module
 * pure and unit-testable.
 */

import type { ActivityEvent, DictionaryEntry, Explanation, StatusKey } from '@aid/contract';
import { STATUS } from '@aid/contract';

/** A resolved dictionary as served by `/api/explanations` and cached in react-query. */
export type Dictionary = Record<string, DictionaryEntry>;

/** Interpolation variables for {@link resolveExplanation} headline/detail templates. */
export type ExplainVars = Record<string, string | number | undefined>;

/** §6.2 fallback token when an entry's status is missing/unknown — grey "čeká". */
const FALLBACK_STATUS: StatusKey = 'ceka';

/**
 * Resolve a §6.2 `STATUS` colour for a (possibly malformed) status token.
 * Colour is NEVER undefined: an unknown/absent token degrades to `ceka` (grey).
 */
function statusColor(status: StatusKey | undefined): { status: StatusKey; color: string } {
  const key: StatusKey = status && status in STATUS ? status : FALLBACK_STATUS;
  return { status: key, color: STATUS[key].color };
}

/**
 * Interpolate `{var}` placeholders in a template with the supplied vars.
 * Unmatched placeholders are left verbatim (visible, never silently blanked).
 */
function interpolate(template: string, vars?: ExplainVars): string {
  if (!vars) return template;
  return template.replace(/\{(\w+)\}/g, (match, name: string) => {
    const value = vars[name];
    return value === undefined ? match : String(value);
  });
}

/**
 * Turn one `DictionaryEntry` into a runtime `Explanation`.
 *
 * - `headline`/`detail` come from the entry's templates with `{step}`/`{total}`/
 *   `{count}`/`{staleDays}` (etc.) interpolated from `vars`.
 * - `status` + `color` come from the §6.2 `STATUS` table keyed by `entry.status`,
 *   falling back to `ceka` (grey) when the entry's status token is absent/unknown
 *   — colour is never undefined.
 */
export function resolveExplanation(entry: DictionaryEntry, vars?: ExplainVars): Explanation {
  const { status, color } = statusColor(entry.status);
  return {
    headline: interpolate(entry.headlineTemplate, vars),
    detail: interpolate(entry.detailTemplate, vars),
    status,
    color,
  };
}

/**
 * Build the dictionary lookup KEY for a live `ActivityEvent`.
 *
 * Discriminators (most specific first):
 *   - `fsm_transition` → `event:fsm_transition:<FROM>_to_<TO>` when both ends
 *     are known (e.g. `event:fsm_transition:GATES_to_DONE`), else bare
 *     `event:fsm_transition`.
 *   - role events (auditor/curator/reporter/simplifier) → `role:<role>:<result>`
 *     where the qualifier comes from `result` / explicit `role` verdict.
 *   - a pass/fail-bearing event → `event:<event>:<result>`.
 *   - everything else → `event:<event>`.
 */
export function eventKey(event: ActivityEvent): string {
  const name = event.event;

  if (name === 'fsm_transition') {
    if (event.from && event.to) return `event:fsm_transition:${event.from}_to_${event.to}`;
    return 'event:fsm_transition';
  }

  // Role verdict events carry a `role` (auditor/curator/reporter/simplifier).
  if (event.role) {
    const qualifier = event.result ?? readRaw(event, 'verdict') ?? readRaw(event, 'disposition');
    return qualifier ? `role:${event.role}:${qualifier}` : `role:${event.role}`;
  }

  if (event.result) return `event:${name}:${event.result}`;
  return `event:${name}`;
}

/** Best-effort read of a string field off the event's `raw` bag. */
function readRaw(event: ActivityEvent, field: string): string | undefined {
  const v = event.raw?.[field];
  return typeof v === 'string' ? v : undefined;
}

/**
 * Resolve a live `ActivityEvent` into an `Explanation` via the dictionary.
 *
 * Lookup order: the specific {@link eventKey} first, then a generic
 * `event:<name>` fallback key. If neither resolves, returns a graceful generic
 * `Explanation` with `status:'ceka'` (grey), the raw event label as the headline
 * and a warning gloss as the detail — it NEVER throws or returns a blank.
 */
export function explainEvent(event: ActivityEvent, dict: Dictionary): Explanation {
  const vars: ExplainVars = {
    from: event.from,
    to: event.to,
    step: event.step,
    gate: event.gate,
    role: event.role,
    ...flattenRaw(event.raw),
  };

  const specificKey = eventKey(event);
  const specificEntry = dict[specificKey];
  if (specificEntry) return resolveExplanation(specificEntry, vars);

  // Fall back to the generic, un-qualified key (e.g. `event:fsm_transition`).
  const genericKey = `event:${event.event}`;
  if (genericKey !== specificKey) {
    const genericEntry = dict[genericKey];
    if (genericEntry) return resolveExplanation(genericEntry, vars);
  }

  // Unresolved — graceful generic explanation (never throw, never blank).
  const { status, color } = statusColor(FALLBACK_STATUS);
  return {
    headline: event.event,
    detail: `Pro tuto událost ("${specificKey}") zatím není vysvětlení ve slovníku.`,
    status,
    color,
  };
}

/** Copy primitive string/number fields out of `raw` for use as interpolation vars. */
function flattenRaw(raw: Record<string, unknown> | undefined): ExplainVars {
  const out: ExplainVars = {};
  if (!raw) return out;
  for (const [key, value] of Object.entries(raw)) {
    if (typeof value === 'string' || typeof value === 'number') out[key] = value;
  }
  return out;
}
