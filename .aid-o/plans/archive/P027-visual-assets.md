---
id: P027
type: plan
status: done
created: 2026-03-16
author: PM + AI
---

# Plan: Visual Assets Pipeline — Mockup-Driven Agent Dispatch

## Context

AID agents repeatedly ignore visual specifications from plans. Root cause: agents receive text descriptions ("purple gradient banner") but never see actual mockups. In P011 (VL Process Flow), all structural components were correct but visual quality was zero — agents wrote their own CSS instead of matching the design.

P011 post-mortem proved that **mockup source code** (exact TSX/CSS) produces dramatically better results than text descriptions or even PNG images. When agents received exact Tailwind classes from mockup source, the output matched perfectly.

v2.7.0 added step verification enforcement (`increment-step` requires `step-{N}-verify.md` with `## Result: PASS`), but without visual assets in the pipeline, there's nothing to verify against.

## Goal

Enable visual assets (mockup source code, images, or AI Studio links) to flow through the entire AID pipeline as a **unified format** — regardless of input type, agents always receive the same structured output.

## Scope

**In scope:**
- 3 input types → 1 unified output format (visual-spec.yaml + source code if available)
- Mockup storage convention in `.aid-o/plans/{plan_id}/mockups/`
- `visual_refs` field in plan steps and `plan.schema.json` (+ `additionalProperties` fix)
- `visual-spec.yaml` generation: from source code (exact) or PNG (approximate + PM validation)
- Visual spec generation in Controller dispatch flow (pipeline.md §4)
- Visual anchoring requirement for frontend agents (role-cards.md)
- Post-step visual verification protocol (Playwright screenshot comparison)
- Brainstorming integration (detect and associate mockups from any source)
- Plan-writing integration (generate visual spec section, assign visual_refs per step)
- Forbidden phrase: text-only UI descriptions ("purple gradient") in plan-writing.md

**Out of scope:**
- Automated pixel-diff tooling (LLM-based semantic comparison is sufficient)
- Git LFS integration (not needed until repos exceed ~50MB of images)
- Figma/design tool native integrations

## Approach

### Option A: Multi-Source Pipeline with Unified Output (Recommended)
3 input types (GitHub repo, AI Studio URL via Playwright, PNG images) → normalized to 1 output format (`visual-spec.yaml` + source files). Source code is Tier 1 authority; design tokens from PNG are Tier 2 fallback.

**Pros:**
- Covers entire pipeline end-to-end
- Source code (TSX/CSS) gives agents exact classes to copy — proven in P011 fix
- PNG fallback with PM validation handles cases without source
- Mechanical enforcement via existing `step-verify.md`

**Cons:**
- Touches 7+ files
- Normalization logic adds complexity to brainstorming/plan-writing

### Option B: Source Code Only
Only support mockup source code from GitHub repos. No PNG support, no Playwright.

**Pros:**
- Simplest — agent reads TSX files directly
- No approximation — exact values always

**Cons:**
- Not all mockups have source code (quick sketches, client-provided PNGs)
- Limits PM workflow

### Decision

**Chosen:** Option A
**Rationale:** Option B is too restrictive. PM needs flexibility — sometimes mockup is a GitHub repo, sometimes a screenshot, sometimes an AI Studio link. The unified output format (visual-spec.yaml) ensures agents always get the same dispatch format regardless of source.

## Architecture

### 3 Inputs → 1 Output

| Input | How orchestrator processes | Priority |
|-------|--------------------------|----------|
| **GitHub repo** (TSX/CSS source) | Read files directly via Read tool | **Tier 1** — exact values |
| **Google AI Studio URL** | Playwright navigates → downloads source code | **Tier 1** — exact values |
| **PNG/JPG image** | LLM reads → generates visual-spec.yaml, PM validates | **Tier 2** — approximate |

Text-only descriptions ("purple gradient banner") are **forbidden** — plan-writing.md rejects them.

### Mockup Storage (unified output)

```
.aid-o/plans/{plan_id}/mockups/
  visual-spec.yaml              # ALWAYS present — unified spec
  CompanyDashboard.tsx          # Source code (Tier 1 — from GitHub/AI Studio)
  Sidebar.tsx                   # Source code (Tier 1)
  dashboard-mockup.png          # Screenshot (Tier 2 — when no source available)
```

Mockups are co-located with the plan. When the plan is archived, mockups go with it.

### Data Flow

```
PM provides mockup:
  (A) GitHub repo URL → orchestrator clones/reads source files
  (B) AI Studio URL → Playwright downloads source code
  (C) PNG/JPG file → LLM reads image
        ↓
Brainstorming: saved to plans/{plan_id}/mockups/
        ↓
Plan-writing: orchestrator generates visual-spec.yaml:
  - From source (A/B): extract exact Tailwind classes, colors, spacing
  - From PNG (C): LLM approximates → PM validates/corrects
  Assigns visual_refs per step
        ↓
Dispatch: Controller sends agent:
  1. visual-spec.yaml (always)
  2. Source TSX/CSS verbatim in prompt (if available)
  3. File paths for agent to Read
        ↓
Agent: reads spec + source (primary), writes Visual Anchoring, implements
        ↓
Verification: Playwright screenshot → compare against mockup/source
        ↓
step-verify.md: includes visual comparison result
```

### visual-spec.yaml Format

```yaml
# Unified visual specification — always present regardless of input type
source_type: github | ai_studio | image   # how this was generated
source_accuracy: exact | approximate       # exact for source code, approximate for PNG

colors:
  primary: "#6B46C1"
  primary-gradient: "bg-gradient-to-r from-indigo-600 to-violet-600"
  background: "#F7FAFC"
  card-bg: "#FFFFFF"
  card-shadow: "shadow-lg shadow-indigo-200"
spacing:
  grid-gap: "gap-6"           # Tailwind class when from source
  card-padding: "p-6"
  section-margin: "mt-8"
typography:
  heading: "text-2xl font-bold text-slate-900"
  subheading: "text-lg font-semibold text-slate-700"
  body: "text-sm text-slate-600"
  label: "text-xs font-semibold text-slate-400 uppercase tracking-wider"
layout:
  type: "3-column"
  sidebar: "w-60"
  main: "flex-1"
  right-panel: "w-80"

components:
  - name: "stat-card"
    source_file: "CompanyDashboard.tsx"     # present only for Tier 1
    source_lines: "48-64"                    # present only for Tier 1
    classes: "bg-white border border-slate-200 rounded-2xl p-6 hover:border-indigo-300 hover:shadow-md"
  - name: "department-card"
    source_file: "CompanyDashboard.tsx"
    source_lines: "98-124"
    classes: "bg-white rounded-xl shadow-sm p-5 border border-slate-100"
```

When `source_accuracy: exact` — values are extracted from actual source code (Tailwind classes, hex values).
When `source_accuracy: approximate` — values are LLM-estimated from PNG, marked for PM validation.

## Implementation Steps

**EPIC 1: Steps 1-7 — Visual Assets Pipeline**

### Step 1: Add `visual_refs` to plan.schema.json

**Objective:** Extend the plan JSON schema to support visual reference fields per step.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/templates/plan.schema.json` (lines ~36-80, step properties) — add `visual_refs` array field

**Architecture Context:**
`plan.schema.json` defines the execution plan format consumed by `aid-epic-to-json.sh` and the Controller during dispatch. Adding `visual_refs` makes mockup references a first-class field that the dispatch protocol can rely on.

**Implementation Detail:**
Add to step properties (inside the `additionalProperties: false` block at line ~140 — MUST add field there or validation breaks):
```json
"visual_refs": {
  "type": "array",
  "items": { "type": "string" },
  "description": "Relative paths to mockup files (source code or images) for this step. Controller reads these before dispatch and generates visual-spec.yaml.",
  "examples": [".aid-o/plans/P011/mockups/CompanyDashboard.tsx", ".aid-o/plans/P011/mockups/dashboard-mockup.png"]
}
```
Also add optional top-level `visual_assets` object (inside the top-level `additionalProperties: false` block at line ~248):
```json
"visual_assets": {
  "type": "object",
  "properties": {
    "mockup_dir": { "type": "string", "description": "Path to mockups directory" },
    "visual_spec": { "type": ["string", "null"], "description": "Path to visual-spec.yaml" },
    "source_type": { "type": "string", "enum": ["github", "ai_studio", "image"], "description": "How mockups were provided" }
  }
}
```

**Error Handling:**
- `visual_refs` is optional — plans without mockups work as before
- Invalid paths in `visual_refs` are caught at dispatch time (Controller reads file, gets error, logs warning)
- `additionalProperties: false` in schema requires both additions to be in the correct property blocks

**Edge Cases:**
- Plan with zero visual_refs — skip all visual dispatch logic, no design tokens
- Plan with visual_refs but mockup file deleted — Controller logs warning, dispatches without visual context, flags in step-verify.md
- Multiple mockups per step — Controller reads all, generates combined spec

**Dependencies:**
- No dependencies — can start independently
- Blocks: Steps 3, 4, 5 (they reference visual_refs field)

**Acceptance Criteria:**
- [ ] `plan.schema.json` validates with `visual_refs` array in step properties
- [ ] `plan.schema.json` validates with `visual_assets` top-level object
- [ ] Existing plans without `visual_refs` still validate (backward compatible)

**Effort:** S
**AID Role:** backend

### Step 2: Update plan-writing.md — Visual Specification section + forbidden phrases + source code priority

**Objective:** Extend plan-writing skill to handle mockups: generate visual-spec.yaml, add `## Visual Specification` conditional section, assign `visual_refs` per step, and ban text-only UI descriptions.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/plan-writing.md` (lines ~104-108, conditional sections) — add `## Visual Specification` section
- Modify: `plugins/aid-orchestrator/skills/plan-writing.md` (lines ~199-244, step template) — add `visual_refs` field

**Architecture Context:**
Plan-writing is invoked by brainstorming Step 8 (Mode A) or standalone (Mode B). It receives approved design sections and writes the exhaustive plan. Visual specification becomes a new conditional section, included only when mockups exist.

**Implementation Detail:**
1. Add to conditional sections list (line ~108):
   ```
   - `## Visual Specification` — Design tokens, mockup references, component breakdown
     (when mockups exist in `plans/{plan_id}/mockups/`)
   ```

2. Define the Visual Specification section format:
   ```markdown
   ## Visual Specification

   **Mockups:** {list of files in plans/{plan_id}/mockups/}

   **Design Tokens:** `plans/{plan_id}/mockups/design-tokens.yaml`
   {Auto-generated YAML content — colors, spacing, typography, layout, components}

   **Component Breakdown:**
   | Component | Mockup | Steps |
   |-----------|--------|-------|
   | Header bar | header-mockup.png | 3 |
   | Sidebar | sidebar-mockup.png | 4, 5 |
   | Dashboard cards | dashboard-mockup.png | 6 |
   ```

3. Add to per-step template (after AID Role line):
   ```markdown
   **Visual Refs:** `{path/to/mockup.png}` — {what part of the mockup this step implements}
   ```
   Make this field optional — only for frontend/UI steps.

4. Add generation rule: when mockups directory is non-empty, orchestrator MUST:
   - **Source code available (Tier 1):** Read TSX/CSS files, extract exact Tailwind classes, hex values, spacing → generate `visual-spec.yaml` with `source_accuracy: exact`
   - **PNG only (Tier 2):** Read images via Read tool, LLM approximates values → generate `visual-spec.yaml` with `source_accuracy: approximate` → show to PM for validation
   - Write `visual-spec.yaml` to `plans/{plan_id}/mockups/`
   - Create Visual Specification section in the plan
   - Assign `visual_refs` to relevant frontend steps

5. Add forbidden phrases to the Forbidden Phrase Detection table:
   ```
   | "purple gradient banner" (or any text-only UI description) | Vague — agent invents own design | Include exact CSS: `className="bg-gradient-to-r from-indigo-600 to-violet-600"` |
   | "styled similar to mockup" | Which mockup? What styles? | Reference visual-spec.yaml component + exact classes |
   ```

**Error Handling:**
- No mockups directory → skip Visual Specification section entirely
- Mockup image unreadable → warn PM, continue without that mockup
- Design token extraction uncertain (PNG source) → mark `source_accuracy: approximate`, PM validates

**Edge Cases:**
- Backend-only plan with no UI → no Visual Specification section, no `visual_refs` on any step
- Plan with mockups but no frontend steps → include Visual Specification for reference, no `visual_refs` assigned
- Component-level mockups vs full-page → both supported, component-level preferred for per-step assignment

**Dependencies:**
- Depends on: Step 1 — `visual_refs` field must exist in schema
- Blocks: Step 4 (dispatch protocol references visual spec)

**Acceptance Criteria:**
- [ ] Plan-writing generates `design-tokens.yaml` when mockups directory contains images
- [ ] Visual Specification section appears in plan when mockups exist
- [ ] Visual Specification section is omitted when no mockups exist
- [ ] Per-step template includes optional `Visual Refs` field
- [ ] Completeness Gate (16 checks) still passes with new section

**Effort:** M
**AID Role:** docs

### Step 3: Update brainstorming.md — Mockup detection and association

**Objective:** Extend brainstorming skill to detect mockup images provided by PM, save them to the plan's mockups directory, and reference them throughout the session.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/brainstorming.md` — add mockup detection in Step 1 (Context) and mockup association in Step 5 (Design)

**Architecture Context:**
Brainstorming is the primary entry point where PM provides visual references. Currently, `.aid-o/inputs/` supports images (per `inputs-readme.md`), but there's no mechanism to associate them with a plan or copy them to the plan's mockups directory. This step bridges that gap.

**Implementation Detail:**
1. In Step 1 (Context), after scanning `.aid-o/inputs/`:
   - Detect image files AND source code files (TSX, CSS, HTML)
   - Present found files to PM: "Found {N} mockup files in inputs/. Associate with this plan? (Y/N)"
   - If Y: note for later copy (actual copy happens in Step 8 when plan ID is allocated)

2. During conversation, when PM provides a mockup reference, detect type:
   - **GitHub repo URL** (e.g. `github.com/user/mockup-repo`) → note as `source_type: github`, clone/read in Step 8
   - **Google AI Studio URL** → note as `source_type: ai_studio`, Playwright capture in Step 8
   - **Local file path** (PNG/JPG) → note as `source_type: image`, copy in Step 8
   - **Local file path** (TSX/CSS/HTML) → note as `source_type: github` (local source), copy in Step 8
   - Validate file/URL exists, read and describe to confirm understanding

3. In Step 5 (Design), if mockups are available:
   - Reference mockups in the architecture discussion
   - Ask PM which mockups map to which components/pages
   - Record component↔mockup mapping for plan-writing

4. In Step 8 (Document), before delegating to plan-writing:
   - Create `plans/{plan_id}/mockups/` directory
   - Process by source type:
     - **github:** Read source files, copy TSX/CSS to mockups/
     - **ai_studio:** Playwright navigates to URL, downloads source code, saves to mockups/
     - **image:** Copy PNG/JPG to mockups/
   - Pass mockup paths, source type, and component mapping to plan-writing skill

**Error Handling:**
- PM provides path to non-existent file → warn, ask to re-provide
- GitHub URL inaccessible → warn PM, ask for local files instead
- AI Studio URL requires auth → use Playwright credentials from `.aid-o/config/.env`
- Image too large (>10MB) → warn PM, suggest optimizing before including

**Edge Cases:**
- PM provides mockups mid-conversation (not in Step 1) → still capture and associate
- Mixed sources (some GitHub, some PNG) → each processed by its type, all output to same mockups/
- No mockups at all → proceed normally, no Visual Specification in plan

**Dependencies:**
- No dependencies — changes are additive to existing brainstorming flow
- Blocks: Step 2 (plan-writing expects mockups in the directory)

**Acceptance Criteria:**
- [ ] Brainstorming detects images in `.aid-o/inputs/` and offers to associate
- [ ] Mockups provided mid-conversation are captured
- [ ] Mockups are copied to `plans/{plan_id}/mockups/` in Step 8
- [ ] Component↔mockup mapping is passed to plan-writing

**Effort:** M
**AID Role:** docs

### Step 4: Update pipeline.md §4 — Visual dispatch protocol

**Objective:** Extend the EXECUTE state dispatch flow to include visual asset handling: Controller reads mockups, generates structured visual spec, and includes both in the agent prompt.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~148-161, Context assembly section) — add visual context as item 8
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~165-210, Agent Dispatch Protocol) — add visual dispatch rule

**Architecture Context:**
Pipeline §4 defines the EXECUTE state dispatch flow. Context assembly (7 items currently) determines what goes into the agent prompt. Visual context becomes item 8. The Agent Dispatch Protocol (5 rules) gets a 6th rule for visual dispatch.

**Implementation Detail:**
1. Add item 8 to Context assembly list:
   ```
   8. `VISUAL CONTEXT` — loaded when step has `visual_refs` in plan.json:
      a. Read `visual-spec.yaml` from mockup dir — include VERBATIM in prompt
      b. If source files exist (TSX/CSS): read relevant source file + lines
         from visual-spec.yaml component entries → paste VERBATIM in prompt
      c. If only PNG: include file paths for agent to Read as confirmation
      d. Priority: source code > visual-spec.yaml > PNG
   ```

2. Add visual spec format for dispatch prompt:
   ```
   ## Visual Specification

   **Source:** visual-spec.yaml (source_accuracy: exact|approximate)

   {visual-spec.yaml content — VERBATIM}

   **Mockup Source Code (adapt to our data layer, DO NOT invent your own design):**
   ```tsx
   // From CompanyDashboard.tsx lines 48-64:
   <div className="bg-gradient-to-r from-indigo-600 to-violet-600 rounded-2xl p-6 text-white shadow-lg shadow-indigo-200">
     ...exact JSX from mockup...
   </div>
   ```

   IMPORTANT: Use the EXACT classes from the source code above.
   Write a "Visual Anchoring" section in your output BEFORE writing any code.
   ```

3. Add rule 6 to Agent Dispatch Protocol:
   ```
   6. **Visual context for UI steps** — when step has `visual_refs`:
      Controller reads visual-spec.yaml + source code (if available) and
      pastes VERBATIM into prompt. Agent receives exact Tailwind classes
      and JSX structure — adapts to our data layer, does NOT invent design.
      Agent MUST write Visual Anchoring section before implementation code.
   ```

**Error Handling:**
- Mockup file not found at dispatch time → log warning, dispatch without visual context, note missing visual in step output
- design-tokens.yaml missing → Controller generates inline spec from mockup reading

**Edge Cases:**
- Step with visual_refs but role != frontend → still include visual context (architect may need it for layout decisions)
- Multiple visual_refs per step → Controller reads all, generates combined spec
- Step with no visual_refs → skip visual context entirely (no overhead)

**Dependencies:**
- Depends on: Step 1 (visual_refs field in schema), Step 2 (design-tokens.yaml generation)
- Blocks: Step 5 (role card references visual anchoring)

**Acceptance Criteria:**
- [ ] Pipeline Context assembly includes item 8 (VISUAL CONTEXT)
- [ ] Agent Dispatch Protocol has rule 6 (visual context for UI steps)
- [ ] Visual spec format is documented with concrete example
- [ ] Non-visual steps are unaffected (no overhead)

**Effort:** M
**AID Role:** docs

### Step 5: Update role-cards.md — Visual Anchoring requirement

**Objective:** Add Visual Anchoring requirement to the frontend role card so agents must produce a structured visual description before writing any implementation code.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/role-cards.md` — frontend role card section, add Visual Anchoring capability/constraint

**Architecture Context:**
Role cards define agent identity, capabilities, and constraints. The frontend role card currently doesn't mention visual references. Adding Visual Anchoring as a constraint ensures every frontend agent converts the mockup into a concrete spec before coding — preventing the "visual impression fades" problem.

**Implementation Detail:**
Add to frontend role card Constraints section:
```markdown
- **Visual Anchoring (when visual_refs provided):** Before writing ANY
  implementation code, produce a `## Visual Anchoring` section that converts
  the mockup into concrete specifications:
  ```
  ## Visual Anchoring
  - Layout: {grid type, column count, widths}
  - Colors: {hex values for primary, secondary, bg, text, borders}
  - Typography: {font-family, sizes per heading level, weights}
  - Spacing: {padding, margin, gap values in px}
  - Components: {list each visible component with position and style}
  ```
  This section serves as your implementation spec. Reference it while coding.
  If no visual_refs: skip this section.
```

Also add to Capabilities:
```markdown
- Visual specification extraction from mockup images
- CSS value derivation from design tokens
```

**Error Handling:**
- Agent doesn't produce Visual Anchoring despite visual_refs → Controller catches this in output verification (visual check section in step-verify.md)

**Edge Cases:**
- Component-level mockup → Visual Anchoring covers only that component
- Multiple mockups → one Visual Anchoring section covering all
- No visual_refs → no Visual Anchoring required

**Dependencies:**
- Depends on: Step 4 (dispatch protocol sends visual context)
- Blocks: Step 6 (verification checks for Visual Anchoring in output)

**Acceptance Criteria:**
- [ ] Frontend role card includes Visual Anchoring constraint
- [ ] Visual Anchoring section format is documented with example
- [ ] Constraint is conditional on visual_refs presence

**Effort:** S
**AID Role:** docs

### Step 6: Update agent-protocol.md — visual_refs in input format

**Objective:** Extend the agent protocol input format to include `visual_refs` field so agents know which visual references apply to their task.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/agent-protocol.md` — input format YAML template, add `visual_refs` field

**Architecture Context:**
Agent protocol defines the universal input format all AID agents receive. Adding `visual_refs` here ensures every agent (not just frontend) is aware of visual context when relevant. The protocol already defines `context_files` — `visual_refs` follows the same pattern.

**Implementation Detail:**
Add to the YAML task input format (after `context_scope`):
```yaml
visual_refs:           # optional — mockup images for this step
  - path: ".aid-o/plans/P011/mockups/dashboard-mockup.png"
    description: "Target dashboard layout — header, cards, sidebar"
  - path: ".aid-o/plans/P011/mockups/design-tokens.yaml"
    description: "Extracted design tokens — colors, spacing, typography"
```

Add to reading order (after "context_files"):
```
5. visual_refs — Read each image file for visual context (frontend/UI steps)
```

**Error Handling:**
- visual_refs field missing → no visual context (backward compatible)
- File path in visual_refs not found → log warning, continue

**Edge Cases:**
- Non-frontend agent with visual_refs → agent reads them for context but doesn't produce Visual Anchoring
- Agent can't read image (tool permission denied) → proceed without, note in output

**Dependencies:**
- Depends on: Step 1 (visual_refs field in schema)
- Blocks: Step 7 (verification expects visual check)

**Acceptance Criteria:**
- [ ] Agent protocol input format includes `visual_refs` field
- [ ] Reading order updated to include visual_refs
- [ ] Backward compatible — agents without visual_refs work as before

**Effort:** S
**AID Role:** docs

### Step 7: Formalize visual verification in pipeline.md — screenshot comparison protocol

**Objective:** Formalize the post-step visual verification protocol: Playwright screenshot capture, Controller semantic comparison against mockup, structured result in step-verify.md.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~215-240, Output verification section) — expand Visual Check section with concrete protocol

**Architecture Context:**
Pipeline §4 Output verification already has a placeholder for visual checks in step-verify.md (`## Visual Check` section). This step formalizes the protocol: when to screenshot, how to compare, what constitutes MATCH/PARTIAL/MISMATCH, and how results feed into the fix loop.

**Implementation Detail:**
Expand the Visual Check section in Output verification:
```markdown
**Visual verification protocol (frontend steps with visual_refs):**

1. **Screenshot capture:**
   - Start dev server if not running
   - Playwright navigates to the page affected by this step
   - Screenshot at 1280x720 viewport (default)
   - Save to `evidence/{epic_id}/{run_id}/screenshots/step_{N}_actual.png`

2. **Semantic comparison:**
   Controller reads both images:
   - Mockup: path from step `visual_refs`
   - Actual: screenshot from step 1
   Produces structured comparison:
   ```
   ## Visual Check
   Mockup: {mockup_path}
   Screenshot: {screenshot_path}

   | Aspect | Match | Notes |
   |--------|-------|-------|
   | Layout (grid, columns, placement) | YES/NO | {details} |
   | Colors (primary, bg, text, borders) | YES/NO | {details} |
   | Typography (sizes, weights, fonts) | YES/NO | {details} |
   | Spacing (padding, margins, gaps) | YES/NO | {details} |
   | Components (presence, completeness) | YES/NO | {details} |

   Verdict: MATCH / PARTIAL / MISMATCH
   ```

3. **Thresholds:**
   - **MATCH** — all aspects YES → PASS
   - **PARTIAL** — layout YES, 1-2 minor color/spacing diffs → PASS_WITH_NOTES
   - **MISMATCH** — layout NO or 3+ aspects NO → FAIL → resume agent with failures

4. **FAIL handling:**
   - Resume agent with specific visual failures (table from comparison)
   - Include mockup path for agent to re-read
   - Max 2 visual fix attempts → ESCALATION
```

**Error Handling:**
- Dev server not running → warn, skip visual verification, note in step-verify.md
- Playwright screenshot fails → warn, skip visual verification
- No visual_refs on step → skip visual verification entirely

**Edge Cases:**
- Step modifies component not visible on default page → Controller navigates to specific route (from step metadata or AC)
- Step modifies responsive behavior → take screenshots at multiple viewports (add 768px mobile)
- Multiple mockups per step → compare each mockup against relevant page section

**Dependencies:**
- Depends on: Step 4 (dispatch includes visual context), Step 6 (agent protocol)
- No blocks — this is the final step

**Acceptance Criteria:**
- [ ] Visual verification protocol documented with concrete steps
- [ ] Comparison table format defined with 5 aspects
- [ ] MATCH/PARTIAL/MISMATCH thresholds documented
- [ ] FAIL handling connects to fix loop (resume agent, max 2 attempts)
- [ ] Skip conditions documented (no visual_refs, no dev server)

**Effort:** M
**AID Role:** docs

## Testing Strategy

All changes are documentation/schema changes in the plugin. Testing approach:

1. **Schema validation** — validate `plan.schema.json` with a test plan containing `visual_refs`
2. **Backward compatibility** — validate existing plans (without `visual_refs`) still pass schema
3. **End-to-end dry run** — create a test plan with mockups, simulate dispatch flow mentally, verify all documents reference each other correctly
4. **Plugin validation** — `/plugin validate .` from repo root

## Constraints

- All changes are in `plugins/aid-orchestrator/` — no changes to target project structure
- Backward compatible — plans without mockups must work exactly as before
- No new bash scripts — all logic is instruction-level (orchestrator LLM follows the protocol)
- Design token generation quality depends on LLM vision capabilities — approximate is acceptable

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| LLM generates inaccurate visual-spec from PNG | Medium | Medium | `source_accuracy: approximate` + PM validation; source code (Tier 1) avoids this entirely |
| Agents skip Visual Anchoring despite role card constraint | Medium | High | Step-verify.md visual check catches it post-hoc; increment-step blocks without PASS |
| Mockup source/images bloat git repo | Low | Low | Optimize images before adding; source files are small (<100KB) |
| Frontend agent has source code but still implements differently | Low | Medium | Source code gives exact classes — much less room for interpretation than PNG |
| AI Studio Playwright capture fails (auth, timeout) | Medium | Low | Fallback: PM downloads source manually and provides as local file |

## Success Criteria

- [ ] A frontend step with visual_refs receives: visual-spec.yaml + source code verbatim (if available) + mockup paths in dispatch prompt
- [ ] Frontend agent produces Visual Anchoring section before implementation code
- [ ] Post-step visual verification produces MATCH/PARTIAL/MISMATCH verdict
- [ ] Plans without mockups are completely unaffected (zero overhead)
- [ ] 3 input types (GitHub, AI Studio, PNG) all produce the same unified output format
- [ ] Text-only UI descriptions are rejected by plan-writing forbidden phrase detection
- [ ] All 7 files modified, plugin validates, CHANGELOGs updated
- [ ] End-to-end: plan with mockups → dispatched agent receives visual-spec + source in prompt

## Next Steps

- [ ] Create EPIC from this plan: `/aid-plan epic P027-visual-assets.md`
- [ ] Implement (single EPIC, 7 steps, all docs/schema changes)
- [ ] Test with a real project — create a plan with mockups and run through the pipeline
- [ ] Tier 2 planning: URL-based mockup capture via Playwright (separate plan)

---

**Last Updated:** 2026-03-16
