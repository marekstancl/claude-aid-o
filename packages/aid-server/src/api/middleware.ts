/**
 * Standard API response-envelope helpers for the cross-project aid-server.
 *
 * Every HTTP handler returns one of two envelope shapes:
 *
 *   - Success: `{ ok: true, data, meta? }`  — see {@link ApiResponse}
 *   - Error:   `{ ok: false, error }`       — see {@link ApiError}
 *
 * The `meta` block carries cross-project scan metadata so a client can tell
 * which projects were scanned, when, and which ones returned partial data.
 *
 * This module is deliberately stateless: it does NOT resolve a single project
 * to an `.aid-o/` path, nor does it locate an "active run". That single-project
 * resolver machinery does not belong in the cross-project server (it scanned a
 * lone workspace per request). Path safety lives in
 * `routes/path-validation.ts`; project enumeration lives in the scanner layer.
 */

import type { Response } from "express";

// ---------------------------------------------------------------------------
// Envelope types
// ---------------------------------------------------------------------------

/**
 * Standard API success response envelope.
 *
 * `meta` is optional and carries cross-project scan metadata. `scannedAt` and
 * `partialProjects` are the cross-project core; the remaining fields are
 * endpoint-specific roll-ups (counts, warnings) that a handler may attach.
 */
export interface ApiResponse<T> {
  ok: true;
  data: T;
  meta?: {
    /** ISO 8601 timestamp marking when the cross-project scan ran. */
    scannedAt: string;
    /** Project IDs that returned partial/degraded data during the scan. */
    partialProjects: string[];
    /** Total item count when the payload is a paginated/filtered list. */
    total?: number;
    /** Non-fatal warnings surfaced to the client. */
    warnings?: string[];
    /** Count of open items (e.g. open decisions / backlog entries). */
    openCount?: number;
    /** Count of closed items. */
    closedCount?: number;
  };
}

/**
 * Standard API error response envelope.
 */
export interface ApiError {
  ok: false;
  error: {
    /** Stable machine-readable error code (e.g. `NOT_FOUND`). */
    code: string;
    /** Human-readable error message. */
    message: string;
    /** Optional structured detail (validation errors, etc.). */
    details?: unknown;
  };
}

// ---------------------------------------------------------------------------
// Response helpers
// ---------------------------------------------------------------------------

/**
 * Send a success envelope. Attaches `meta` only when provided so the wire
 * shape stays minimal for endpoints that have no cross-project metadata.
 */
export function sendOk<T>(
  res: Response,
  data: T,
  meta?: ApiResponse<T>["meta"],
): void {
  const response: ApiResponse<T> = { ok: true, data };
  if (meta) response.meta = meta;
  res.json(response);
}

/**
 * Send an error envelope with an explicit HTTP status code. `details` is
 * included only when defined, keeping the shape minimal for simple errors.
 */
export function sendError(
  res: Response,
  status: number,
  code: string,
  message: string,
  details?: unknown,
): void {
  const response: ApiError = {
    ok: false,
    error: { code, message, ...(details !== undefined && { details }) },
  };
  res.status(status).json(response);
}

/** Send a 404 Not Found error envelope for a named resource. */
export function send404(res: Response, resource: string): void {
  sendError(res, 404, "NOT_FOUND", `${resource} not found`);
}

/** Send a 400 Bad Request error envelope with a custom message. */
export function send400(res: Response, message: string): void {
  sendError(res, 400, "BAD_REQUEST", message);
}
