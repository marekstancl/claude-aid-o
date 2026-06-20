/**
 * Unit tests for the standard response-envelope helpers.
 *
 * A minimal Express `Response` stub captures the status code and the JSON
 * payload so each helper's wire shape can be asserted directly.
 */

import { describe, it, expect } from "vitest";
import type { Response } from "express";
import { sendOk, sendError, send404, send400 } from "./middleware.js";

interface CapturedResponse {
  res: Response;
  statusCalls: number[];
  jsonPayloads: unknown[];
}

function makeRes(): CapturedResponse {
  const statusCalls: number[] = [];
  const jsonPayloads: unknown[] = [];
  const res = {
    status(code: number) {
      statusCalls.push(code);
      return res;
    },
    json(payload: unknown) {
      jsonPayloads.push(payload);
      return res;
    },
  } as unknown as Response;
  return { res, statusCalls, jsonPayloads };
}

describe("sendOk", () => {
  it("produces the success envelope with cross-project meta (AC1)", () => {
    const { res, jsonPayloads } = makeRes();
    sendOk(res, [], {
      scannedAt: "2026-06-20T00:00:00.000Z",
      partialProjects: [],
    });

    expect(jsonPayloads).toHaveLength(1);
    expect(jsonPayloads[0]).toEqual({
      ok: true,
      data: [],
      meta: { scannedAt: "2026-06-20T00:00:00.000Z", partialProjects: [] },
    });
  });

  it("omits meta entirely when not provided", () => {
    const { res, jsonPayloads } = makeRes();
    sendOk(res, { id: "P-1" });

    expect(jsonPayloads[0]).toEqual({ ok: true, data: { id: "P-1" } });
    expect(jsonPayloads[0]).not.toHaveProperty("meta");
  });

  it("carries the extended cross-project meta roll-up fields", () => {
    const { res, jsonPayloads } = makeRes();
    sendOk(res, ["a", "b"], {
      scannedAt: "2026-06-20T12:00:00.000Z",
      partialProjects: ["proj-x"],
      total: 2,
      warnings: ["stale cache"],
      openCount: 1,
      closedCount: 1,
    });

    expect(jsonPayloads[0]).toEqual({
      ok: true,
      data: ["a", "b"],
      meta: {
        scannedAt: "2026-06-20T12:00:00.000Z",
        partialProjects: ["proj-x"],
        total: 2,
        warnings: ["stale cache"],
        openCount: 1,
        closedCount: 1,
      },
    });
  });
});

describe("sendError", () => {
  it("sets the status code and error envelope", () => {
    const { res, statusCalls, jsonPayloads } = makeRes();
    sendError(res, 409, "CONFLICT", "already exists");

    expect(statusCalls).toEqual([409]);
    expect(jsonPayloads[0]).toEqual({
      ok: false,
      error: { code: "CONFLICT", message: "already exists" },
    });
  });

  it("includes details only when provided", () => {
    const { res, jsonPayloads } = makeRes();
    sendError(res, 422, "VALIDATION", "bad input", { field: "epicId" });

    expect(jsonPayloads[0]).toEqual({
      ok: false,
      error: {
        code: "VALIDATION",
        message: "bad input",
        details: { field: "epicId" },
      },
    });
  });

  it("omits details when undefined", () => {
    const { res, jsonPayloads } = makeRes();
    sendError(res, 500, "INTERNAL", "boom");

    const payload = jsonPayloads[0] as ApiErrorShape;
    expect(payload.error).not.toHaveProperty("details");
  });
});

describe("send404", () => {
  it("produces a 404 NOT_FOUND envelope naming the resource", () => {
    const { res, statusCalls, jsonPayloads } = makeRes();
    send404(res, "Epic");

    expect(statusCalls).toEqual([404]);
    expect(jsonPayloads[0]).toEqual({
      ok: false,
      error: { code: "NOT_FOUND", message: "Epic not found" },
    });
  });
});

describe("send400", () => {
  it("produces a 400 BAD_REQUEST envelope with the given message", () => {
    const { res, statusCalls, jsonPayloads } = makeRes();
    send400(res, "Invalid epicId");

    expect(statusCalls).toEqual([400]);
    expect(jsonPayloads[0]).toEqual({
      ok: false,
      error: { code: "BAD_REQUEST", message: "Invalid epicId" },
    });
  });
});

interface ApiErrorShape {
  ok: false;
  error: { code: string; message: string; details?: unknown };
}
