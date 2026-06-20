/**
 * Unit tests for the CWE-22 evidence-path guard.
 *
 * Covers the two defense layers of `validateEvidencePath` (component rejection
 * + bounds checking) plus the standalone `isValidPathComponent` /
 * `isWithinDirectory` primitives.
 */

import { describe, it, expect } from "vitest";
import * as path from "node:path";
import {
  validateEvidencePath,
  isValidPathComponent,
  isWithinDirectory,
} from "./path-validation.js";

const BASE = "/project/.aid-o/work/evidence";

describe("validateEvidencePath (CWE-22 guard) — AC2", () => {
  it('rejects a ".." traversal component', () => {
    const result = validateEvidencePath(BASE, "..", "secret");
    expect(result.ok).toBe(false);
  });

  it("rejects an absolute path component", () => {
    const result = validateEvidencePath(BASE, "/etc/passwd");
    expect(result.ok).toBe(false);
  });

  it("rejects a Windows separator component", () => {
    const result = validateEvidencePath(BASE, "a\\..\\b");
    expect(result.ok).toBe(false);
  });

  it("accepts a clean two-component evidence path resolving inside the base", () => {
    const result = validateEvidencePath(BASE, "E-047-3_7", "R-E047-3_7-1");
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.resolvedPath).toBe(
        path.resolve(BASE, "E-047-3_7", "R-E047-3_7-1"),
      );
    }
  });
});

describe("isValidPathComponent", () => {
  it('rejects "..", "a/b", and "a\\b" (constraint)', () => {
    expect(isValidPathComponent("..")).toBe(false);
    expect(isValidPathComponent("a/b")).toBe(false);
    expect(isValidPathComponent("a\\b")).toBe(false);
  });

  it('rejects "." and the empty string', () => {
    expect(isValidPathComponent(".")).toBe(false);
    expect(isValidPathComponent("")).toBe(false);
  });

  it("accepts a clean identifier (constraint)", () => {
    expect(isValidPathComponent("R-E007-3")).toBe(true);
  });
});

describe("isWithinDirectory", () => {
  it("accepts a path inside the parent", () => {
    expect(isWithinDirectory(path.join(BASE, "epic"), BASE)).toBe(true);
  });

  it("accepts a path equal to the parent", () => {
    expect(isWithinDirectory(BASE, BASE)).toBe(true);
  });

  it("rejects a sibling whose name is a prefix of the parent", () => {
    expect(isWithinDirectory("/project/.aid-o/work/evidenceX", BASE)).toBe(
      false,
    );
  });

  it("rejects a path outside the parent", () => {
    expect(isWithinDirectory("/etc/passwd", BASE)).toBe(false);
  });
});
