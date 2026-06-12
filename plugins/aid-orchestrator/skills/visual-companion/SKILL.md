---
name: visual-companion
description: Browser-based visual brainstorming companion — interactive mockups, per-question visual/text decision, P027 integration. Invokable directly via /visual-companion for standalone testing/demo, or auto-loaded by /aid-plan brainstorm when topic is UI-visual.
user_invocable: true
---

# Visual Companion Guide

Browser-based visual brainstorming companion for showing mockups, diagrams, and options.

## Standalone Invocation (`/visual-companion`)

When PM invokes this skill directly (outside `/aid-plan brainstorm`), treat it as
a demo / smoke-test session:

1. **Resolve plugin path** — read `.aid-o/config/plugin.yaml` → `plugin_path`. If
   the file does not exist, fall back to `~/.claude/plugins/marketplaces/claude-aid-o/plugins/aid-orchestrator`.
2. **First-run check** — if `{plugin_path}/lib/brainstorm-server/node_modules/`
   is missing, run `cd {plugin_path}/lib/brainstorm-server && npm install` once.
   Report stdout/stderr if it fails — do NOT silently fall back to terminal.
3. **Determine network reachability — MANDATORY before starting server.**
   Default `start-server.sh` binds to `127.0.0.1`, which is unreachable from
   PM's browser if the agent is running on a remote dev server (SSH, VPN,
   container). Choose binding based on context:

   **3a. Detect remote session:**
   - Check `$SSH_CONNECTION` / `$SSH_CLIENT` env vars — set means remote
   - Run `hostname -I 2>/dev/null | awk '{print $1}'` — non-127.x.x.x = remote
   - Or just ASK PM: "Spouštím server tady. Jsi přímo na téhle mašině, nebo
     se připojuješ z jiného zařízení (VPN/SSH)?"

   **3b. Pick command:**
   - **Local (agent runs on PM's machine):** `start-server.sh --project-dir {project_root}` — defaults to `127.0.0.1`, URL `http://localhost:<port>`.
   - **Remote (agent on dev server, PM on laptop/phone via VPN/SSH):**
     `start-server.sh --project-dir {project_root} --host 0.0.0.0 --url-host <reachable-ip>` where `<reachable-ip>` is the VPN/LAN address PM uses to reach the host (e.g. `10.20.20.22`). Without `--host 0.0.0.0` the server binds loopback only and PM's browser gets connection refused. Without `--url-host <IP>` the returned URL still says `localhost` and PM can't paste it.

4. **Tell PM the URL** explicitly (full `http://<host>:<port>`) and write one
   demo screen (e.g. `demo.html` with 2-3 clickable options) so PM can verify
   the round-trip end-to-end.
5. **Wait for PM** — when PM responds in terminal, read `$SCREEN_DIR/.events`
   to confirm click capture works.
6. **Stop on PM signal** — when PM says "stop"/"done"/"kill server", run
   `{plugin_path}/lib/brainstorm-server/stop-server.sh $SCREEN_DIR`.

Standalone mode skips the per-question gate from brainstorming (everything is
visual by definition during a demo).

## Refactoring or Redesigning Existing UI — Read the Code First

Before drawing ANY mockup of a component, page, or row that **already exists
in some codebase**, PAUSE and ask PM:

> "Tohle vypadá jako redesign [komponenty / stránky / řádku]. Mám si nejdřív
> načíst aktuální implementaci, abych věděl co tam reálně je za data a možné
> hodnoty, a teprve potom navrhoval? (Y/N)"

This is mandatory when ANY of these trigger:
- PM uses words like **"redesign", "překresli", "navrhni nový vzhled",
  "refaktoring vizuálu", "udělejme to jinak"**
- PM shows a **screenshot of existing UI**
- PM references an **existing page or component** by name ("zpracování",
  "klient stránka", "list X", "row Y")
- PM is in a project that contains the target component (check via `git
  ls-files` / `find` before assuming greenfield)

**Why this rule exists:** drawing mockups against guessed data shapes wastes
tokens and time. Real components encode constraints (which fields exist,
what enum values they accept, what overlays/badges fire under which
conditions) that mockups must respect. Discovering those after 3 iterations
forces a full rewrite. Read first, draw second.

**If PM accepts:**
1. Find the file — `grep -rln "<distinctive-czech-string-from-screenshot>" --include="*.tsx" --include="*.vue" --include="*.svelte" --include="*.html"` typically finds it in 1–2 hops
2. Read the component itself + its data type (TypeScript interface, prop types, Pydantic model)
3. **Write a structured inventory in chat** before any mockup:
   - Which fields the component reads from data
   - All possible enum values per field
   - Conditional rendering rules (e.g. "X renders only when Y AND status ∈ Z")
   - Visual variants (responsive, size, theme)
   - List anything PM wants to add that **isn't in the data shape today** —
     this needs backend decision before drawing
4. Get PM confirmation that the inventory matches their mental model
5. **MANDATORY — show current state first:** Before drawing any proposed changes,
   render the component/page **as it currently looks** (from the real code/data shapes
   you read in step 2). This is the baseline. Every subsequent mockup MUST be structured
   as "current → proposed" — either side-by-side (`.split` layout) or a single mockup
   that clearly shows the existing UI with the requested changes layered in.
   **Never show only the new design in isolation.** A mockup that omits the current state
   gives zero context for what is actually changing and forces the PM to mentally reconstruct
   the delta. Always: current look + changes applied within it.
6. Only THEN start companion mockups with the above baseline included

**If PM declines** (e.g. "kresli, je to jen brainstorm"): proceed with
mockups but explicitly state that data shapes are placeholders and mockups
won't survive contact with the real component.

## When to Use (within `/aid-plan brainstorm`)

Decide per-question, not per-session. The test: **would the user understand this better by seeing it than reading it?**

**Use the browser** when the content itself is visual:

- **UI mockups** — wireframes, layouts, navigation structures, component designs
- **Architecture diagrams** — system components, data flow, relationship maps
- **Side-by-side visual comparisons** — comparing two layouts, two color schemes, two design directions
- **Design polish** — when the question is about look and feel, spacing, visual hierarchy
- **Spatial relationships** — state machines, flowcharts, entity relationships rendered as diagrams

**Use the terminal** when the content is text or tabular:

- **Requirements and scope questions** — "what does X mean?", "which features are in scope?"
- **Conceptual A/B/C choices** — picking between approaches described in words
- **Tradeoff lists** — pros/cons, comparison tables
- **Technical decisions** — API design, data modeling, architectural approach selection
- **Clarifying questions** — anything where the answer is words, not a visual preference

A question *about* a UI topic is not automatically a visual question. "What kind of wizard do you want?" is conceptual — use the terminal. "Which of these wizard layouts feels right?" is visual — use the browser.

## How It Works

The server watches a directory for HTML files and serves the newest one to the browser. You write HTML content, the user sees it in their browser and can click to select options. Selections are recorded to a `.events` file that you read on your next turn.

**Content fragments vs full documents:** If your HTML file starts with `<!DOCTYPE` or `<html`, the server serves it as-is (just injects the helper script). Otherwise, the server automatically wraps your content in the frame template — adding the header, CSS theme, selection indicator, and all interactive infrastructure. **Write content fragments by default.** Only write full documents when you need complete control over the page.

## Starting a Session

```bash
# Start server with persistence (mockups saved to project)
{plugin_path}/lib/brainstorm-server/start-server.sh --project-dir /path/to/project

# Returns: {"type":"server-started","port":52341,"url":"http://localhost:52341",
#           "screen_dir":"/path/to/project/.aid-o/work/companion/12345-1706000000"}
```

Save `screen_dir` from the response. Tell user to open the URL.

**Note:** Pass the project root as `--project-dir` so mockups persist in `.aid-o/work/companion/` and survive server restarts. Without it, files go to `/tmp` and get cleaned up. The `.aid-o/work/` directory is already gitignored by AID — no extra `.gitignore` entry needed.

**`{plugin_path}`** comes from `.aid-o/config/plugin.yaml`. Run `cd {plugin_path}/lib/brainstorm-server && npm install` on first use if `node_modules` is missing.

**Codex behavior:** In Codex (`CODEX_CI=1`), `start-server.sh` auto-switches to foreground mode by default because background jobs may be reaped. Use `--background` only if your environment reliably preserves detached processes.

**If background processes are reaped in your environment:** run in foreground from a persistent terminal session:

```bash
{plugin_path}/lib/brainstorm-server/start-server.sh --project-dir /path/to/project --foreground
```

In `--foreground` mode, the command stays attached and serves until interrupted.

If the URL is unreachable from your browser (common in remote/containerized setups), bind a non-loopback host:

```bash
{plugin_path}/lib/brainstorm-server/start-server.sh \
  --project-dir /path/to/project \
  --host 0.0.0.0 \
  --url-host localhost
```

Use `--url-host` to control what hostname is printed in the returned URL JSON.

## The Loop

1. **Write HTML** to a new file in `screen_dir`:
   - Use semantic filenames: `platform.html`, `visual-style.html`, `layout.html`
   - **Never reuse filenames** — each screen gets a fresh file
   - Use Write tool — **never use cat/heredoc** (dumps noise into terminal)
   - Server automatically serves the newest file

2. **Tell user what to expect and end your turn:**
   - Remind them of the URL (every step, not just first)
   - Give a brief text summary of what's on screen (e.g., "Showing 3 layout options for the homepage")
   - Ask them to respond in the terminal: "Take a look and let me know what you think. Click to select an option if you'd like."

3. **On your next turn** — after the user responds in the terminal:
   - Read `$SCREEN_DIR/.events` if it exists — this contains the user's browser interactions (clicks, selections) as JSON lines
   - Merge with the user's terminal text to get the full picture
   - The terminal message is the primary feedback; `.events` provides structured interaction data

4. **Iterate or advance** — if feedback changes current screen, write a new file (e.g., `layout-v2.html`). Only move to the next question when the current step is validated.

5. **Unload when returning to terminal** — when the next step doesn't need the browser (e.g., a clarifying question, a tradeoff discussion), push a waiting screen to clear the stale content:

   ```html
   <!-- filename: waiting.html (or waiting-2.html, etc.) -->
   <div style="display:flex;align-items:center;justify-content:center;min-height:60vh">
     <p class="subtitle">Continuing in terminal...</p>
   </div>
   ```

   This prevents the user from staring at a resolved choice while the conversation has moved on. When the next visual question comes up, push a new content file as usual.

6. Repeat until done.

## Writing Content Fragments

Write just the content that goes inside the page. The server wraps it in the frame template automatically (header, theme CSS, selection indicator, and all interactive infrastructure).

**Minimal example:**

```html
<h2>Which layout works better?</h2>
<p class="subtitle">Consider readability and visual hierarchy</p>

<div class="options">
  <div class="option" data-choice="a" onclick="toggleSelect(this)">
    <div class="letter">A</div>
    <div class="content">
      <h3>Single Column</h3>
      <p>Clean, focused reading experience</p>
    </div>
  </div>
  <div class="option" data-choice="b" onclick="toggleSelect(this)">
    <div class="letter">B</div>
    <div class="content">
      <h3>Two Column</h3>
      <p>Sidebar navigation with main content</p>
    </div>
  </div>
</div>
```

That's it. No `<html>`, no CSS, no `<script>` tags needed. The server provides all of that.

## CSS Classes Available

The frame template provides these CSS classes for your content:

### Options (A/B/C choices)

```html
<div class="options">
  <div class="option" data-choice="a" onclick="toggleSelect(this)">
    <div class="letter">A</div>
    <div class="content">
      <h3>Title</h3>
      <p>Description</p>
    </div>
  </div>
</div>
```

**Multi-select:** Add `data-multiselect` to the container to let users select multiple options. Each click toggles the item. The indicator bar shows the count.

```html
<div class="options" data-multiselect>
  <!-- same option markup — users can select/deselect multiple -->
</div>
```

### Cards (visual designs)

```html
<div class="cards">
  <div class="card" data-choice="design1" onclick="toggleSelect(this)">
    <div class="card-image"><!-- mockup content --></div>
    <div class="card-body">
      <h3>Name</h3>
      <p>Description</p>
    </div>
  </div>
</div>
```

### Mockup container

```html
<div class="mockup">
  <div class="mockup-header">Preview: Dashboard Layout</div>
  <div class="mockup-body"><!-- your mockup HTML --></div>
</div>
```

### Split view (side-by-side)

```html
<div class="split">
  <div class="mockup"><!-- left --></div>
  <div class="mockup"><!-- right --></div>
</div>
```

### Pros/Cons

```html
<div class="pros-cons">
  <div class="pros"><h4>Pros</h4><ul><li>Benefit</li></ul></div>
  <div class="cons"><h4>Cons</h4><ul><li>Drawback</li></ul></div>
</div>
```

### Mock elements (wireframe building blocks)

```html
<div class="mock-nav">Logo | Home | About | Contact</div>
<div style="display: flex;">
  <div class="mock-sidebar">Navigation</div>
  <div class="mock-content">Main content area</div>
</div>
<button class="mock-button">Action Button</button>
<input class="mock-input" placeholder="Input field">
<div class="placeholder">Placeholder area</div>
```

### Typography and sections

- `h2` — page title
- `h3` — section heading
- `.subtitle` — secondary text below title
- `.section` — content block with bottom margin
- `.label` — small uppercase label text

## Browser Events Format

When the user clicks options in the browser, their interactions are recorded to `$SCREEN_DIR/.events` (one JSON object per line). The file is cleared automatically when you push a new screen.

```jsonl
{"type":"click","choice":"a","text":"Option A - Simple Layout","timestamp":1706000101}
{"type":"click","choice":"c","text":"Option C - Complex Grid","timestamp":1706000108}
{"type":"click","choice":"b","text":"Option B - Hybrid","timestamp":1706000115}
```

The full event stream shows the user's exploration path — they may click multiple options before settling. The last `choice` event is typically the final selection, but the pattern of clicks can reveal hesitation or preferences worth asking about.

If `.events` doesn't exist, the user didn't interact with the browser — use only their terminal text.

## Design Tips

- **Scale fidelity to the question** — wireframes for layout, polish for polish questions
- **Explain the question on each page** — "Which layout feels more professional?" not just "Pick one"
- **Iterate before advancing** — if feedback changes current screen, write a new version
- **2-4 options max** per screen
- **Use real content when it matters** — for a photography portfolio, use actual images (Unsplash). Placeholder content obscures design issues.
- **Keep mockups simple** — focus on layout and structure, not pixel-perfect design
- **Always show current + proposed for existing UI** — never a new design in isolation; see the mandatory baseline rule (step 5) in "Refactoring or Redesigning Existing UI" above.

## File Naming

- Use semantic names: `platform.html`, `visual-style.html`, `layout.html`
- Never reuse filenames — each screen must be a new file
- For iterations: append version suffix like `layout-v2.html`, `layout-v3.html`
- Server serves newest file by modification time

## Cleaning Up

```bash
{plugin_path}/lib/brainstorm-server/stop-server.sh $SCREEN_DIR
```

Mockup files persist in `.aid-o/work/companion/` for later reference — this directory is already gitignored by AID. Only `/tmp` sessions get deleted on stop.

## AID Integration (P027 Visual Assets Pipeline)

Visual Companion output integrates with the P027 Visual Assets Pipeline as the 4th input type:

- HTML files saved during brainstorming become mockup source (`source_type: companion`)
- On session end (Step 8 of brainstorming), approved screens are copied to `plans/{plan_id}/mockups/`
- plan-writing generates `visual-spec.yaml` from companion HTML (extracting CSS classes, layout structure, color values)
- Agents receive companion HTML as source code during dispatch — same treatment as GitHub TSX/CSS source

**Priority order for visual context (highest to lowest):**
1. Mockup source code (GitHub repo, companion HTML)
2. Design tokens (visual-spec.yaml)
3. PNG/JPG images
4. Text description (forbidden in plans — use source or images)

## Reference

- Frame template (CSS reference): `{plugin_path}/lib/brainstorm-server/frame-template.html`
- Helper script (client-side): `{plugin_path}/lib/brainstorm-server/helper.js`

**Last Updated:** 2026-06-12
