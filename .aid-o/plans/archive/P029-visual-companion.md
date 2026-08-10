---
id: P029
type: plan
status: done
created: 2026-03-17
author: PM + AID
depends_on: P027
---

# Plan: Visual Companion Integration

## Context

AID brainstorming skill was refactored from Superpowers in v2.1.0 (commit `575d28a`), but the
Visual Companion — a browser-based HTML prototype viewer — was never migrated. It was neither
accepted nor rejected; it simply fell through the cracks during the redesign.

P027 (Visual Assets Pipeline) established 3 input types for mockups (GitHub repo, AI Studio URL,
PNG images) with a unified `visual-spec.yaml` output. Visual Companion becomes the **4th input
type**: when PM has no mockup, the orchestrator generates HTML prototypes during brainstorming,
PM approves visually, and the approved HTML becomes mockup source for the implementation pipeline.

## Goal

Integrate Superpowers' Visual Companion server into AID brainstorming as an opt-in feature
that generates HTML prototypes during design sections, saves them as mockup source into the
P027 pipeline, and provides per-question visual/text decision guidance.

## Scope

**In scope:**
- Copy brainstorm-server from Superpowers cache into AID plugin (`lib/brainstorm-server/`)
- New `skills/visual-companion.md` — adapted from Superpowers, AID-specific paths
- Brainstorming.md updates: opt-in offer, per-question visual decision, companion source_type
- Plan-writing.md: `source_type: companion` handling
- Pipeline.md: companion source in context assembly

**Out of scope:**
- Modifying the server code (index.js, helper.js, frame-template.html) — use as-is from Superpowers
- Codex/CI mode (not relevant for AID)
- Automated spec review loop (separate feature, not related to companion)
- Multi-select support (already in server, just document it)

## Approach

**Chosen: Copy server + adapt skill instructions**

The brainstorm-server is 602 lines of battle-tested code (Node.js + Express + WebSocket + chokidar).
No reason to rewrite. Copy the `lib/brainstorm-server/` directory, write AID-specific
`visual-companion.md` skill (adapted from Superpowers version), and wire into existing
brainstorming flow at 3 points: Step 1 (offer), Step 5 (use), Step 8 (save output).

**Rejected alternatives:**
- *Use frontend-design skill instead* — generates static HTML but no interactive browser loop
  with selection tracking. Good as fallback when companion is declined, not as replacement.
- *Write custom server* — the Superpowers server already works. Rewriting adds risk for zero benefit.
- *Use Playwright for mockup display* — wrong tool. Playwright is for automation/testing,
  not for interactive design sessions with PM.

## Decision

Copy brainstorm-server as-is. Write AID-specific visual-companion.md skill. Wire into
brainstorming Steps 1, 5, and 8. Connect output to P027 pipeline as `source_type: companion`.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| npm install fails in target project | Low | Medium | Server has 3 deps (express, ws, chokidar). Fallback: skip companion, use terminal |
| Server port conflict | Low | Low | Random port allocation (already in start-server.sh) |
| PM declines companion every time | Medium | Low | No wasted work — opt-in only. Terminal brainstorming unchanged |
| HTML prototypes saved but agents ignore them | Medium | Medium | P027 dispatch protocol already handles source files. Agent gets TSX/CSS verbatim |

## Steps

### Step 1: Copy brainstorm-server into AID plugin

**Objective:** Make the Visual Companion server available as part of the AID plugin distribution.

**Files:**
- Copy: `lib/brainstorm-server/` (index.js, helper.js, frame-template.html, start-server.sh, stop-server.sh, package.json, package-lock.json)

**Implementation Detail:**
Copy the entire `lib/brainstorm-server/` directory from Superpowers cache
(`~/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.0/lib/brainstorm-server/`)
into `plugins/aid-orchestrator/lib/brainstorm-server/`.

Modify `start-server.sh`:
- Change default `--project-dir` persistence path from `.superpowers/brainstorm/` to `.aid-o/work/companion/`
- Update gitignore reminder from `.superpowers/` to `.aid-o/work/companion/` (already gitignored by AID)

No changes to index.js, helper.js, or frame-template.html.

**AC:**
- [ ] `lib/brainstorm-server/` exists in AID plugin
- [ ] `start-server.sh` uses `.aid-o/work/companion/` as persistence path
- [ ] `npm install` in `lib/brainstorm-server/` succeeds
- [ ] Server starts and serves default page

**Effort:** S | **Role:** backend

**Dependencies:** None
**Blocks:** Steps 2, 3, 4, 5

---

### Step 2: Create visual-companion.md skill

**Objective:** AID-specific visual companion guide adapted from Superpowers.

**Files:**
- Create: `plugins/aid-orchestrator/skills/visual-companion.md`

**Implementation Detail:**
Adapt Superpowers' `visual-companion.md` (259 lines) for AID context:

1. **When to Use** — keep the per-question decision taxonomy (browser vs. terminal) verbatim.
   This is the most valuable part — when to show visual vs. text.

2. **Starting a Session** — adapt paths:
   - `${CLAUDE_PLUGIN_ROOT}` → `{plugin_path}` (from `.aid-o/config/plugin.yaml`)
   - `.superpowers/brainstorm/` → `.aid-o/work/companion/`
   - Add: "Run `npm install` in `{plugin_path}/lib/brainstorm-server/` on first use"

3. **The Loop** — keep as-is (write HTML → end turn → user responds → read .events → iterate)

4. **CSS Classes** — keep entire reference (options, cards, mockup, split, pros-cons, mock elements)

5. **Browser Events Format** — keep .events documentation

6. **Design Tips** — keep all tips

7. **AID Integration** (new section):
   ```
   ## AID Integration

   Visual Companion output integrates with P027 Visual Assets Pipeline:
   - HTML files saved during brainstorming become mockup source (`source_type: companion`)
   - On session end, approved screens are copied to `plans/{plan_id}/mockups/`
   - plan-writing generates visual-spec.yaml from companion HTML (extracting CSS classes,
     layout structure, color values)
   - Agents receive companion HTML as source code during dispatch (same as GitHub source)
   ```

8. **Cleanup** — adapt stop-server.sh path, note that `.aid-o/work/companion/` is gitignored

Add YAML frontmatter: `name: visual-companion`, `description: Browser-based visual brainstorming companion`, `user_invocable: false`

**AC:**
- [ ] `skills/visual-companion.md` exists with AID-specific paths
- [ ] Per-question decision taxonomy preserved (browser vs. terminal)
- [ ] CSS class reference preserved
- [ ] AID Integration section connects to P027

**Effort:** S | **Role:** docs

**Dependencies:** Step 1
**Blocks:** Step 3

---

### Step 3: Update brainstorming.md — opt-in offer + per-question decision + companion source_type

**Objective:** Wire Visual Companion into brainstorming flow at Steps 1, 5, and 8.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/brainstorming.md`

**Implementation Detail:**

**3a. After Analysis Protocol (after RULE 8, before mockup detection):**

Add Visual Companion offer:
```
**Visual Companion offer:** After analysis, if the topic involves UI, visual design,
or layout decisions, offer the browser companion:
"This topic involves visual decisions. Want to use the Visual Companion?
It shows interactive mockups in your browser during design.
  (Y) Yes — start companion server (requires Node.js)
  (N) No — text-only brainstorming (default)"

If PM accepts:
1. Start server: `bash {plugin_path}/lib/brainstorm-server/start-server.sh --project-dir {project_root}`
2. Run `npm install` in server dir if node_modules missing (first use only)
3. Save screen_dir from server response
4. Note: `visual_companion: active` in interim document

If PM declines or topic is non-visual: skip. No re-asking.

Fallback: If server fails to start → log warning, continue with text-only brainstorming.
Offer `frontend-design` skill as alternative for generating static mockups.
```

**3b. Add per-question visual decision guidance (new section before Design Validation Protocol):**

```
### Visual Delivery Decision (when companion is active)

For each question/presentation in Steps 3-6, decide: browser or terminal?

**Use browser:**
- UI mockups, wireframes, layouts, component designs
- Architecture diagrams, data flow, relationship maps
- Side-by-side visual comparisons (two layouts, two color schemes)
- Design polish questions (look and feel, spacing, visual hierarchy)
- Spatial relationships (state machines, flowcharts as diagrams)

**Use terminal:**
- Requirements and scope questions
- Conceptual A/B/C choices (approaches described in words)
- Tradeoff lists, comparison tables
- Technical decisions (API design, data modeling)
- Clarifying questions (answer is words, not visual preference)

Rule: A question *about* a UI topic is not automatically visual.
"What kind of wizard?" = terminal. "Which wizard layout?" = browser.

When returning to terminal after visual question, push waiting screen:
```html
<div style="display:flex;align-items:center;justify-content:center;min-height:60vh">
  <p class="subtitle">Continuing in terminal...</p>
</div>
```
```

**3c. Update mockup detection to include companion source_type:**

After existing 3 source types, add:
```
- **Visual Companion** → HTML files from active companion session. Note as `source_type: companion`.
  On session end, copy approved screens from `.aid-o/work/companion/{session}/` to `plans/{plan_id}/mockups/`.
```

**3d. Update Document Generation Protocol RULE 2 to include companion:**

Add to mockup processing:
```
- **companion:** Copy approved HTML screens from companion session dir to mockups/.
  Stop companion server: `bash {plugin_path}/lib/brainstorm-server/stop-server.sh {screen_dir}`
```

**AC:**
- [ ] Companion offered after analysis for UI/visual topics
- [ ] Per-question visual decision taxonomy present
- [ ] `source_type: companion` in mockup detection
- [ ] Document generation copies companion HTML and stops server
- [ ] Fallback to text-only if server fails
- [ ] `frontend-design` skill offered as alternative when companion declined

**Effort:** M | **Role:** docs

**Dependencies:** Steps 1, 2
**Blocks:** Steps 4, 5

---

### Step 4: Update plan-writing.md — companion source handling

**Objective:** Plan-writing recognizes companion HTML as mockup source and generates visual-spec.yaml from it.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/plan-writing.md`

**Implementation Detail:**

In the Visual Specification conditional section (added by P027), add companion handling:

```
**source_type: companion** — HTML files from Visual Companion session.
Extract from HTML:
- CSS classes (Tailwind or custom) → design-tokens.yaml
- Layout structure (grid, flex, columns) → layout description
- Color values from inline styles or CSS variables → color palette
- Component structure (options, cards, mockup, split) → component list

The companion HTML IS the mockup source code. Agents receive it verbatim,
same as GitHub TSX/CSS source. No PNG intermediary needed.
```

**AC:**
- [ ] Companion source type documented in Visual Specification section
- [ ] Extraction guidance for CSS/layout/colors from companion HTML

**Effort:** S | **Role:** docs

**Dependencies:** Step 3
**Blocks:** Step 5

---

### Step 5: Update pipeline.md — companion in context assembly + CHANGELOG

**Objective:** Pipeline dispatch handles companion source same as GitHub source. Update CHANGELOG.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/pipeline.md`
- Modify: `CHANGELOG.md` (both root and plugin)

**Implementation Detail:**

**5a. Pipeline.md §4 VISUAL CONTEXT section:**

Update the source type table to include companion:
```
| Source Type | Context Assembly |
|-------------|----------------|
| `github` | Read TSX/CSS files → include verbatim in prompt |
| `ai_studio` | Read downloaded source → include verbatim in prompt |
| `image` | Read PNG → include in prompt + design-tokens.yaml |
| `companion` | Read HTML files → include verbatim in prompt + design-tokens.yaml |
```

**5b. CHANGELOG entry under v2.7.0 (or bump to v2.8.0):**

```
### Added
- **Visual Companion** — browser-based HTML prototype viewer for brainstorming
  (opt-in, Node.js server from Superpowers). Generates interactive mockups during
  design sections, saves approved HTML as 4th input type for P027 visual assets pipeline
```

**AC:**
- [ ] Companion source type in context assembly table
- [ ] CHANGELOG updated
- [ ] Pipeline dispatch treats companion same as github source (verbatim)

**Effort:** S | **Role:** docs

**Dependencies:** Steps 3, 4
**Blocks:** None

## Testing Strategy

1. **Server lifecycle:** Start server → verify URL accessible → push HTML → verify display → stop server
2. **Brainstorming flow:** Run `/aid-plan brainstorm "design a dashboard"` → verify companion offered → accept → verify HTML generation in Step 5 → verify save in Step 8
3. **P027 integration:** Verify companion HTML appears in `plans/{plan_id}/mockups/` with correct `source_type: companion` → verify pipeline dispatch includes it
4. **Fallback:** Decline companion → verify text-only brainstorming unchanged
5. **Server failure:** Kill server mid-session → verify graceful fallback message

## Summary

| Step | What | Files | Effort | Deps |
|------|------|-------|--------|------|
| 1 | Copy brainstorm-server | `lib/brainstorm-server/` (copy) | S | — |
| 2 | visual-companion.md skill | `skills/visual-companion.md` (new) | S | 1 |
| 3 | brainstorming.md updates | `skills/brainstorming.md` (modify) | M | 1, 2 |
| 4 | plan-writing.md companion | `skills/plan-writing.md` (modify) | S | 3 |
| 5 | pipeline.md + CHANGELOG | `skills/pipeline.md`, `CHANGELOG.md` (modify) | S | 3, 4 |

**Total: 5 steps, ~1 new file + 1 copy + 3 modifications. Effort: M overall.**

**Critical path:** Step 1 → Step 2 → Step 3 → Step 4 → Step 5
**Parallel opportunities:** Steps 1 and 2 can run in parallel (no file overlap).
