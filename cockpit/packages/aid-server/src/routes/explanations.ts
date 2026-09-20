/**
 * Explanations (dictionary) route for the cross-project aid-server
 * (EPIC E-047-4_7, Step 1) — spec §7.4, §13.10.
 *
 * Serves the static Czech dictionary that powers UI tooltips and Help. The wire
 * payload is the un-interpolated SOURCE — `Record<string, DictionaryEntry>` —
 * so the live UI and Help resolve each entry to a runtime Explanation
 * themselves (§6.4 "shared with frontend"). The dictionary is the single source
 * of truth in `explain/dictionary.cs.ts`, surfaced via `getDictionary()`.
 *
 * Mounted at `/api` by the bootstrap, so `GET /api/explanations?lang=cs`
 * resolves to this router's `GET /explanations`.
 *
 * Graceful language fallback: only `cs` exists in MVP1 (the `lang` param
 * documents the future `.en` seam — §6.4). An unknown `lang` is NOT a 404; the
 * route returns the `cs` map with a `meta.warnings` note so a client requesting
 * an unsupported language still gets usable content.
 *
 * Module: src/routes/explanations.ts
 */

import { Router } from 'express';
import { sendOk } from '../api/middleware.js';
import { getDictionary } from '../explain/index.js';

/** The only language shipped in MVP1; default + fallback target. */
const DEFAULT_LANG = 'cs' as const;

/**
 * Build the explanations router. `GET /explanations?lang=cs` →
 * `{ ok: true, data: Record<string, DictionaryEntry> }`. An unknown `lang`
 * still returns the `cs` map, with a `meta.warnings` note (graceful, NOT 404).
 */
export function explanationsRoutes(): Router {
  const router = Router();

  router.get('/explanations', (req, res) => {
    // `req.query.lang` is `string | undefined` for a scalar, or an array/object
    // for a repeated/structured param; normalise to a single string for the
    // supported-language check. Absent → treated as the default (cs).
    const rawLang = req.query.lang;
    const lang = typeof rawLang === 'string' ? rawLang : undefined;

    // MVP1 ships only `cs`; everything else falls back to `cs` with a warning.
    const dictionary = getDictionary(DEFAULT_LANG);

    if (lang !== undefined && lang !== DEFAULT_LANG) {
      sendOk(res, dictionary, {
        scannedAt: new Date().toISOString(),
        partialProjects: [],
        warnings: [
          `Unsupported language "${lang}"; serving "${DEFAULT_LANG}" dictionary (only "${DEFAULT_LANG}" available in MVP1).`,
        ],
      });
      return;
    }

    sendOk(res, dictionary);
  });

  return router;
}
