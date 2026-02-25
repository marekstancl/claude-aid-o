/**
 * Markdown parser for `.aid-o/` files.
 *
 * Handles: EPIC spec files (`.aid-o/02-epics/{epic_id}.md`), plan files,
 * audit reports in Markdown format, and IDEAS.md.
 *
 * Uses `gray-matter` for frontmatter extraction. Section parsing is done
 * with custom heading-level splitting.
 *
 * snake_case keys in YAML frontmatter are converted to camelCase in the output.
 */

import matter from 'gray-matter';
import type {
  ParseResult,
  ParseWarning,
  EpicSpec,
  AcceptanceCriterion,
  EpicStep,
} from '../types.ts';
import { snakeToCamel } from './utils.ts';

// ---------------------------------------------------------------------------
// Generic Markdown + Frontmatter parser
// ---------------------------------------------------------------------------

/**
 * Parse a Markdown string with optional YAML frontmatter.
 *
 * @param content - Raw Markdown string (may include --- fenced frontmatter).
 * @param source  - Source file path (used for diagnostics).
 * @returns ParseResult with frontmatter (camelCase) and body text.
 */
export function parseMarkdownWithFrontmatter<T>(
  content: string,
  source: string,
): ParseResult<{ frontmatter: T | null; body: string }> {
  const warnings: ParseWarning[] = [];

  // Handle empty / whitespace-only content.
  if (!content || content.trim().length === 0) {
    warnings.push({
      message: 'Markdown content is empty',
      severity: 'warning',
    });
    return {
      data: { frontmatter: null, body: '' },
      warnings,
      source,
    };
  }

  try {
    const parsed = matter(content);

    let frontmatter: T | null = null;
    if (parsed.data && Object.keys(parsed.data).length > 0) {
      frontmatter = snakeToCamel<T>(parsed.data);
    } else {
      warnings.push({
        message: 'No frontmatter found in Markdown file',
        severity: 'info',
      });
    }

    return {
      data: { frontmatter, body: parsed.content },
      warnings,
      source,
    };
  } catch (err: unknown) {
    const message =
      err instanceof Error ? err.message : 'Unknown frontmatter parse error';
    warnings.push({
      message: `Failed to parse Markdown frontmatter: ${message}`,
      severity: 'error',
    });
    return {
      data: { frontmatter: null, body: content },
      warnings,
      source,
    };
  }
}

// ---------------------------------------------------------------------------
// EPIC Spec parser
// ---------------------------------------------------------------------------

/**
 * Parse a full EPIC specification from Markdown.
 *
 * Extracts:
 * - YAML frontmatter (status, plan_ref, etc.)
 * - Title from the H1 heading
 * - Structured sections: Context, Goal, Scope, Artifacts, Constraints,
 *   DoD Gates, Acceptance Criteria, Dependencies, Steps, Hints
 *
 * @param content - Raw Markdown string of an EPIC spec file.
 * @param source  - Source file path (used for diagnostics and epicId derivation).
 * @returns ParseResult with the fully parsed EpicSpec.
 */
export function parseEpicSpec(
  content: string,
  source: string,
): ParseResult<EpicSpec> {
  const warnings: ParseWarning[] = [];

  // Handle empty / whitespace-only content.
  if (!content || content.trim().length === 0) {
    warnings.push({
      message: 'EPIC spec content is empty',
      severity: 'error',
    });
    return { data: null, warnings, source };
  }

  // --- Frontmatter ---
  let frontmatter: Record<string, unknown> = {};
  let body = '';

  try {
    const parsed = matter(content);
    if (parsed.data && Object.keys(parsed.data).length > 0) {
      frontmatter = snakeToCamel<Record<string, unknown>>(parsed.data);
    } else {
      warnings.push({
        message: 'EPIC spec has no frontmatter',
        severity: 'warning',
      });
    }
    body = parsed.content;
  } catch (err: unknown) {
    const message =
      err instanceof Error ? err.message : 'Unknown frontmatter parse error';
    warnings.push({
      message: `Failed to parse EPIC frontmatter: ${message}`,
      severity: 'error',
    });
    body = content;
  }

  // --- Derive epicId from frontmatter or filename ---
  const epicId = deriveEpicId(frontmatter, source);

  // --- Parse sections from body ---
  const sections = splitSections(body);

  // --- Title (H1 heading) ---
  const title = extractTitle(body);
  if (!title) {
    warnings.push({
      message: 'No H1 heading found in EPIC spec',
      severity: 'warning',
    });
  }

  // --- Section extraction ---
  const context = sections['context'] ?? '';
  if (!context) {
    warnings.push({
      message: 'Missing "Context" section in EPIC spec',
      severity: 'info',
    });
  }

  const goal = sections['goal'] ?? '';
  if (!goal) {
    warnings.push({
      message: 'Missing "Goal" section in EPIC spec',
      severity: 'info',
    });
  }

  const scope = parseScope(sections['scope'] ?? '');
  const artifacts = sections['artifacts'] || undefined;
  const constraints = sections['constraints'] ?? '';
  const dodGates = parseDodGates(sections['dod gates'] ?? sections['dod'] ?? '');
  const acceptanceCriteria = parseAcceptanceCriteria(
    sections['acceptance criteria'] ?? sections['acceptance'] ?? '',
  );
  const dependencies = sections['dependencies'] || undefined;
  const steps = parseStepsTable(sections['steps'] ?? sections['steps (role pipeline)'] ?? '');
  const hints = parseHints(sections['hints'] ?? '');

  const spec: EpicSpec = {
    epicId,
    status: (frontmatter.status as string) ?? '',
    planRef: (frontmatter.planRef as string) ?? '',
    planEpicsTotal: (frontmatter.planEpicsTotal as number) ?? 0,
    runsTotal: (frontmatter.runsTotal as number) ?? 0,
    runsCompleted: (frontmatter.runsCompleted as number) ?? 0,
    title: title ?? '',
    context,
    goal,
    scope,
    artifacts,
    constraints,
    dodGates,
    acceptanceCriteria,
    dependencies,
    steps,
    hints: hints && Object.keys(hints).length > 0 ? hints : undefined,
  };

  return { data: spec, warnings, source };
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/**
 * Derive the EPIC ID from frontmatter or the source filename.
 */
function deriveEpicId(
  frontmatter: Record<string, unknown>,
  source: string,
): string {
  // Try frontmatter first (may be under "id" or "epicId").
  if (typeof frontmatter.id === 'string' && frontmatter.id) {
    return frontmatter.id;
  }
  if (typeof frontmatter.epicId === 'string' && frontmatter.epicId) {
    return frontmatter.epicId;
  }

  // Fall back to filename without extension.
  const match = source.match(/([^/\\]+?)(?:\.md)?$/);
  return match ? match[1] : 'unknown';
}

/**
 * Extract the title from the first H1 heading in the Markdown body.
 *
 * Handles formats like:
 *   # EPIC: E-005-1_4 -- Title here
 *   # Title here
 */
function extractTitle(body: string): string | null {
  const match = body.match(/^#\s+(.+)$/m);
  if (!match) return null;
  return match[1].trim();
}

/**
 * Split a Markdown body into sections keyed by their H2 heading name.
 *
 * Returns a map where the key is the lowercase heading text and the value is
 * the section body (everything between this heading and the next H2 or end of
 * file), trimmed of leading/trailing whitespace.
 */
function splitSections(body: string): Record<string, string> {
  const sections: Record<string, string> = {};
  // Match H2 headings: "## Something" possibly followed by more text.
  const headingRegex = /^##\s+(.+)$/gm;

  const headings: { name: string; index: number }[] = [];
  let match: RegExpExecArray | null;

  while ((match = headingRegex.exec(body)) !== null) {
    headings.push({
      name: match[1].trim().toLowerCase(),
      index: match.index + match[0].length,
    });
  }

  for (let i = 0; i < headings.length; i++) {
    const start = headings[i].index;
    const end = i + 1 < headings.length
      ? body.lastIndexOf('\n##', headings[i + 1].index)
      : body.length;
    const sectionBody = body.slice(start, end).trim();
    sections[headings[i].name] = sectionBody;
  }

  return sections;
}

/**
 * Parse the Scope section into allowed paths, forbidden paths, and raw markdown.
 */
function parseScope(sectionBody: string): EpicSpec['scope'] {
  const allowedPaths: string[] = [];
  const forbiddenPaths: string[] = [];

  // Look for subsections like "### Allowed files/paths" and "### Forbidden zones"
  const lines = sectionBody.split('\n');
  let currentBucket: string[] | null = null;

  for (const line of lines) {
    const trimmed = line.trim();
    const lower = trimmed.toLowerCase();

    if (lower.startsWith('### ') || lower.startsWith('**')) {
      if (lower.includes('allowed') || lower.includes('include')) {
        currentBucket = allowedPaths;
      } else if (
        lower.includes('forbidden') ||
        lower.includes('excluded') ||
        lower.includes('forbidden zones')
      ) {
        currentBucket = forbiddenPaths;
      } else {
        currentBucket = null;
      }
      continue;
    }

    if (currentBucket !== null && trimmed.startsWith('- ')) {
      const path = trimmed.slice(2).trim();
      // Strip inline comments and annotations like "(read-only reference)".
      const cleaned = path.replace(/\s*\(.*?\)\s*$/, '').trim();
      if (cleaned) {
        currentBucket.push(cleaned);
      }
    }
  }

  return {
    allowedPaths,
    forbiddenPaths,
    rawMarkdown: sectionBody,
  };
}

/**
 * Parse the DoD Gates section.
 *
 * Expects a bulleted list like:
 *   - tests_pass
 *   - lint_pass
 */
function parseDodGates(sectionBody: string): string[] {
  const gates: string[] = [];
  const lines = sectionBody.split('\n');

  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.startsWith('- ')) {
      const gate = trimmed.slice(2).trim();
      if (gate) gates.push(gate);
    }
  }

  return gates;
}

/**
 * Parse Acceptance Criteria from a Markdown section.
 *
 * Expects checkbox-style list items like:
 *   - [ ] [backend] Server starts on port 4200
 *   - [x] [frontend] Dashboard renders correctly
 */
function parseAcceptanceCriteria(sectionBody: string): AcceptanceCriterion[] {
  const criteria: AcceptanceCriterion[] = [];
  const lines = sectionBody.split('\n');

  for (const line of lines) {
    const trimmed = line.trim();
    // Match: - [ ] [role] text   or   - [x] [role] text
    const match = trimmed.match(
      /^-\s+\[([ xX])\]\s+\[([^\]]+)\]\s+(.+)$/,
    );
    if (match) {
      criteria.push({
        checked: match[1].toLowerCase() === 'x',
        role: match[2].trim(),
        text: match[3].trim(),
      });
      continue;
    }

    // Fallback: checkbox without role tag.
    const fallback = trimmed.match(/^-\s+\[([ xX])\]\s+(.+)$/);
    if (fallback) {
      criteria.push({
        checked: fallback[1].toLowerCase() === 'x',
        role: '',
        text: fallback[2].trim(),
      });
    }
  }

  return criteria;
}

/**
 * Parse the Steps table from a Markdown section.
 *
 * Expects a pipe-delimited Markdown table with headers:
 *   | # | Role | Objective | Depends On | Parallel Group |
 */
function parseStepsTable(sectionBody: string): EpicStep[] {
  const steps: EpicStep[] = [];
  const lines = sectionBody.split('\n');

  // Find the table rows (skip the header and separator lines).
  let headerFound = false;
  let separatorSkipped = false;

  for (const line of lines) {
    const trimmed = line.trim();

    // Detect table header row.
    if (!headerFound && trimmed.startsWith('|') && trimmed.includes('#')) {
      headerFound = true;
      continue;
    }

    // Skip separator row (e.g., |---|---|---|---|---|).
    if (headerFound && !separatorSkipped && /^\|[\s\-|]+\|$/.test(trimmed)) {
      separatorSkipped = true;
      continue;
    }

    // Parse data rows.
    if (headerFound && separatorSkipped && trimmed.startsWith('|')) {
      const cells = trimmed
        .split('|')
        .map((c) => c.trim())
        .filter((c) => c.length > 0);

      if (cells.length >= 3) {
        const stepNumber = parseInt(cells[0], 10);
        const role = cells[1] ?? '';
        const objective = cells[2] ?? '';
        const dependsOnRaw = cells[3] ?? '';
        const parallelGroup = cells[4] ?? '';

        const dependsOn = parseDependsOn(dependsOnRaw);

        const step: EpicStep = {
          number: isNaN(stepNumber) ? 0 : stepNumber,
          role: role.trim(),
          objective: objective.trim(),
          dependsOn,
        };

        const pg = parallelGroup.trim();
        if (pg && pg !== '\u2014' && pg !== '-' && pg !== '---' && pg !== '') {
          step.parallelGroup = pg;
        }

        steps.push(step);
      }
    }
  }

  return steps;
}

/**
 * Parse a "Depends On" cell value into an array of step IDs.
 *
 * Handles formats like:
 *   "architect"        -> ["architect"]
 *   "backend:2"        -> ["backend:2"]
 *   "frontend:3, backend:4" -> ["frontend:3", "backend:4"]
 *   "---" or "—"       -> []
 */
function parseDependsOn(raw: string): string[] {
  const trimmed = raw.trim();
  if (!trimmed || trimmed === '\u2014' || trimmed === '---' || trimmed === '-') {
    return [];
  }

  return trimmed
    .split(/[,;]/)
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

/**
 * Parse the Hints section into key-value pairs.
 *
 * Expects lines like:
 *   - expected_steps: 12
 *   - complexity: high
 *   - notes: "Some text here"
 */
function parseHints(sectionBody: string): Record<string, string | number> {
  const hints: Record<string, string | number> = {};
  const lines = sectionBody.split('\n');

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed.startsWith('- ')) continue;

    const itemText = trimmed.slice(2).trim();
    const colonIndex = itemText.indexOf(':');
    if (colonIndex === -1) continue;

    const key = itemText.slice(0, colonIndex).trim();
    let value: string = itemText.slice(colonIndex + 1).trim();

    // Strip surrounding quotes.
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    // Try to parse as number.
    const num = Number(value);
    if (!isNaN(num) && value.length > 0) {
      hints[key] = num;
    } else {
      hints[key] = value;
    }
  }

  return hints;
}
