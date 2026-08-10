---
id: P005-B
type: plan
status: done
created: 2026-02-24
author: PM + AI
parent: P005
depends_on: P005-A
---

# Plan: AID GUI Dashboard — Frontend & UX — "Orchestration Cinema"

## Context

This plan defines the visual experience, interaction design, and frontend implementation for the AID GUI Dashboard. It depends on the backend API from P005-A.

The core thesis: **this is not a dashboard — it is a cinematic experience of AI orchestration.** The user doesn't just monitor what AID does; they *experience* it. Every state transition, every agent dispatch, every gate pass/fail is a visual moment. The aesthetic must be unique, timeless, and unmistakably different from the sea of generic AI dashboards.

The name for this design language is **"Orchestration Cinema"**.

## Goal

Build a web frontend that transforms raw AID pipeline data into a visually stunning, emotionally engaging experience — where watching AI build software feels like watching a film. The interface must be so distinctive that a single screenshot identifies it as AID. It must be keyboard-first, zero-config, real-time, and deeply satisfying to use.

## Scope

**In scope:**
- Custom design system ("Orchestration Cinema") — no generic UI kits
- 9 core screens: Command Center, Pipeline Theater, Activity Stream, Decision Hub, Evidence Vault, Health Observatory, Ideas to Execution, Knowledge Base, Queue Scheduler
- AI Companion — omnipresent intelligent search/help with voice input and presets
- Real-time WebSocket-driven updates with animations
- Run replay — animated playback of completed pipeline runs
- Micro-animations, page transitions, sound feedback
- Dark theme with depth and glow aesthetics
- Keyboard-first navigation with Cmd+K command palette
- React + Vite + TypeScript + Framer Motion + custom SVG pipeline

**Out of scope:**
- EPIC editor with drag & drop (deferred — EPICs are written once, not daily)
- Config editor (read-only config viewer is sufficient for MVP; YAML editing is better in IDE)
- Mobile responsive design (desktop-first)
- Light theme in MVP (dark only; light theme is a future enhancement)

---

## Visual Identity — "Orchestration Cinema" Design Language

### Philosophy

Forget typical dashboards. No white grids with cards. No shadcn/ui generic aesthetics. This is a **dark canvas with depth** — elements float on layers, active components glow, and the entire interface breathes with the rhythm of the pipeline.

The design draws inspiration from:
- **Mission control centers** — the feeling of commanding something powerful
- **Cinema color grading** — deliberate, mood-driven color palettes
- **Musical instruments** — interfaces that feel good to touch, where every interaction has feedback
- **Deep space UIs** — depth, glow, floating elements, subtle particle effects

### Color System — FSM State-Driven

The entire UI color scheme derives from the 12 FSM states. Every state has a signature color that permeates the interface — the topbar subtly shifts, backgrounds breathe, shadows change hue. The user *feels* what state the pipeline is in without reading a label.

```
FSM State Color Palette:
─────────────────────────────────────────────────────────
IDLE            #3a3f5c → Muted blue-gray       (calm, resting)
PLAN_REVIEW     #c9943e → Warm amber/gold       (contemplation, waiting for PM)
PLAN_READY      #4a8f7a → Sage green            (prepared, about to begin)
EXECUTING       #00b4d8 → Vivid cyan/teal       (active, energy, motion)
PHASE_CHECK     #7c5cbf → Deep purple           (reflection, review)
PHASE_RETRY     #d4663a → Burnt orange          (retry, attention needed)
GATES           #2d9a4f → Gates green            (testing, validation)
GATES_RETRY     #c94040 → Danger red             (failure, needs fix)
PM_APPROVAL     #e8a832 → Pulsing bright amber   (action required!)
CURATOR_RESOLVE #8b6fc0 → Soft lavender          (curation, refinement)
DONE            #22c55e → Radiant green          (success, celebration)
ERROR           #ef4444 → Alert red              (error state)
─────────────────────────────────────────────────────────
```

**Implementation:** CSS custom properties (`--state-color`, `--state-glow`, `--state-bg`) updated on every FSM state change. All components reference these variables. State change = entire UI subtly shifts mood.

### Background & Depth

- **Base color:** `#08080f` — near-black with a hint of deep blue
- **Surface layers:** glass morphism with `backdrop-filter: blur()` — but subtle, not frosted-glass-overdone
  - Layer 0 (base): `#08080f`
  - Layer 1 (cards): `rgba(15, 15, 25, 0.7)` with 1px border `rgba(255,255,255,0.06)`
  - Layer 2 (modals, overlays): `rgba(20, 20, 35, 0.85)` with stronger blur
  - Layer 3 (active/focused): subtle glow of current FSM state color as box-shadow
- **Depth cues:** active elements have a faint glow (state-colored `box-shadow: 0 0 20px`), inactive elements recede into the background
- **Grain texture:** very subtle film grain overlay (CSS noise pattern at 2% opacity) — adds analog warmth to digital UI

### Typography

```
Hierarchy:
─────────────────────────────────────────────────────────
Data & Code      JetBrains Mono        — monospace, sharp, technical
UI Labels        Inter                  — clean sans-serif, excellent readability
Large Metrics    Inter (condensed wt)   — oversized numbers with gradient fill
Page Titles      Inter (medium wt)      — 24px, letter-spacing: -0.02em
Section Headers  Inter (medium wt)      — 16px, uppercase, letter-spacing: 0.05em, muted color
Timestamps       JetBrains Mono         — 12px, muted, relative ("2m ago")
─────────────────────────────────────────────────────────
```

- Large metric numbers (health score, step count, duration) use **gradient text fill** from the current FSM state color to white
- All text defaults to `rgba(255,255,255,0.87)` — not pure white, which is too harsh on dark backgrounds
- Muted text: `rgba(255,255,255,0.45)`

### Micro-Animations (Framer Motion)

Every interaction has feedback. Nothing is static. But nothing is gratuitous — each animation serves a purpose:

| Element | Animation | Purpose |
|---------|-----------|---------|
| Active step node | Gentle pulse (scale 1.0→1.03→1.0, 2s loop) | Shows which step is currently executing |
| Step completion | Brief "sparkle" particle burst (0.5s) + glow intensify | Celebrates progress, draws attention |
| Gate pass | Gate icon "opens" (SVG path animation, 0.4s) + green flash | Visceral pass/fail feedback |
| Gate fail | Gate icon "slams shut" + red shake (0.3s) | Immediate negative feedback |
| New stage_log entry | Fade-in from top with slight blur-to-sharp (0.3s) | Data "materializing" from the pipeline |
| Page transition | Shared layout animation (framer-motion layoutId) | Spatial continuity between views |
| FSM state change | Background color shift (1.5s ease), topbar glow transition | Ambient mood change |
| PM notification | Badge pulse (scale + opacity, 1s loop) + optional audio | Demands attention without being aggressive |
| Card hover | Subtle lift (translateY -2px) + border glow intensify | Affordance — "this is interactive" |
| Sidebar collapse | Smooth width animation (0.3s spring) | Spatial rearrangement |
| Data loading | Skeleton with shimmer (gradient sweep, not spinner) | Perceived performance |
| WebSocket reconnect | Topbar subtle "breathing" animation | System health indicator |

### Sound Design (Web Audio API)

Optional, user-configurable. Disabled by default — enabled via preferences. Sounds are short (< 0.5s), subtle, non-intrusive:

| Event | Sound | Character |
|-------|-------|-----------|
| Step complete | Soft chime (C5 → E5, sine wave, 0.3s decay) | Positive, minimal |
| Gate pass | Two-tone ascending (C5 → G5, 0.2s) | Confirmation |
| Gate fail | Low tone (C3, triangle wave, 0.4s decay) | Warning, not alarming |
| PM decision needed | Gentle bell (A4, 0.5s with reverb) | Attention-getting |
| Pipeline complete | Three-note ascending arpeggio (C5→E5→G5, 0.5s total) | Celebration |
| Error | Single low thud (A2, 0.2s) | Alert |

**Implementation:** Pre-generated AudioBuffer instances, triggered via AudioContext. Volume controlled by global preference slider. No external audio files — synthesized in browser.

---

## Core Screens

### A. Command Center (Home)

**Not a dashboard with cards.** This is a mission control view that tells you the state of your world at a glance.

**Layout:**
```
┌──────────────────────────────────────────────────────────────┐
│  [AI Companion search bar]                    [notifications]│
├──────┬───────────────────────────────────────────────────────┤
│      │                                                       │
│  S   │         ╭─────────────────╮                           │
│  I   │         │   FSM STATE     │  ← Large radial element   │
│  D   │         │   EXECUTING     │    color = state color     │
│  E   │         │   ●●●○○○○○     │    animated ring           │
│  B   │         ╰─────────────────╯                           │
│  A   │                                                       │
│  R   │  ┌─ Timeline Strip ──────────────────────────────┐   │
│      │  │ ○──●──●──●──◐──○──○──○──○──○──○──○            │   │
│      │  │ start              now                    end  │   │
│      │  └────────────────────────────────────────────────┘   │
│      │                                                       │
│      │  ┌─ Satellites ──────────────────────────────────┐   │
│      │  │  [Queue: 3]    [Health: 87]    [Decisions: 1] │   │
│      │  │  [Active EPIC]  [Last Run: 2h ago]            │   │
│      │  └────────────────────────────────────────────────┘   │
│      │                                                       │
└──────┴───────────────────────────────────────────────────────┘
```

**Central element:** Large circular/radial visualization showing the current FSM state. Animated ring that fills as the pipeline progresses. State name in large typography, state color as dominant glow. When executing, the ring segments correspond to pipeline steps — completed segments glow, current segment pulses.

**Timeline strip:** Horizontal bar showing the current run's journey from first event to now. Each dot = a stage_log event. Color-coded by FSM state. Hovering a dot shows event details in a tooltip. Clicking navigates to that moment in the Activity Stream.

**Satellite metrics:** Small, elegant cards around the central element:
- Queue count (links to Ideas to Execution)
- Health score (links to Health Observatory)
- Pending decisions (links to Decision Hub) — pulsing if count > 0
- Active EPIC name + progress %
- Last completed run (relative time)

**Idle state:** When nothing is running, the central element shows a calm, meditative state — muted colors, slow breathing animation. Text: "No active pipeline. Your codebase rests." The timeline strip is empty. Satellites show last known values.

### B. Pipeline Theater

**The main show.** Full-screen visualization of the EPIC pipeline execution.

**Design: "River Flow" — not a traditional DAG**

Instead of a box-and-arrow diagram, the pipeline flows like a river from left to right:
- Steps are "islands" in the river, connected by flowing water (animated gradient lines)
- When the river reaches a parallel group, it splits into tributaries (swim lanes) that flow side by side, then merge back
- Each island/step shows:
  - Role icon (architect, backend, frontend, qa, security, docs — custom SVG icons per role)
  - Step label (truncated, full on hover)
  - Status: pending (translucent, outline only), active (pulsing glow, particle effects flowing into it), completed (solid, full glow), failed (red outline, shake), skipped (dashed outline)
  - Duration badge (when completed)
- The "water" between steps is animated — subtle gradient flow that shows direction and represents data/artifacts flowing between agents
- Active step has particle effects: small dots flowing from the previous completed step toward it, representing work in progress

**Implementation:** Custom SVG with Framer Motion for animations. No React Flow — too generic, too heavy. Custom layout algorithm for river topology (linear chain with parallel fan-out/fan-in). `requestAnimationFrame` for particle effects (lightweight canvas overlay on SVG).

**Step Detail Panel (right slide-in):**
Click any step island → panel slides in from right (framer-motion, 0.3s):
- Agent output (rendered Markdown with syntax highlighting)
- Diff patch (syntax-highlighted, collapsible hunks, side-by-side or unified toggle)
- Timing (start → end, duration bar)
- Review cycles (if retries occurred — numbered attempts with status)
- Acceptance criteria checklist (from plan.json)
- "View in Evidence Vault" link

**Gates visualization:**
After all steps complete, a "gate" element appears at the river's end:
- Visual: tall gate icon with two doors
- Pass: doors swing open (SVG animation), green glow, step-through effect
- Fail: doors slam shut, red glow, shake effect
- Each individual gate (tests_pass, lint_pass, etc.) shown as smaller icons within the gate structure

**Progress bar:**
Bottom of the screen — thin, elegant bar showing overall pipeline progress (steps completed / total). Segmented by parallel groups. Estimated time remaining (based on historical average from past runs, if available).

**Run Replay Mode:**
For completed runs: a play/pause/scrub control appears at the bottom. Clicking "play" animates the entire pipeline execution from start to finish, using stage_log.jsonl timestamps to pace the animation. Steps light up, events appear, gates open — like watching a movie of the orchestration. Playback speed: 1x, 2x, 5x, 10x. Scrub bar for jumping to specific moments.

### C. Activity Stream

**Vertical chronological feed of everything happening in the pipeline.** Like a Twitter timeline of orchestration events.

**Layout:** Full-height scrollable feed, newest events at top.

**Event cards:**
```
┌──────────────────────────────────────────┐
│  ⏱ 2m ago  │  EXECUTING  │  step_2       │
│                                          │
│  Agent dispatched: backend               │
│  Objective: Implement REST API endpoints │
│                                          │
│  → View step details                     │
└──────────────────────────────────────────┘
```

Each card contains:
- Relative timestamp ("2m ago", "just now")
- FSM state badge (colored pill)
- Step reference (if applicable)
- Event type icon (dispatch, transition, gate, decision, etc.)
- Detail text
- Clickable → navigates to relevant view (step detail, gate report, decision)

**New events:** Slide in from top with blur-to-sharp animation. Stack pushes existing events down.

**Filters:** Toggle buttons at top — filter by FSM state, by step, by event type (dispatch, gate, decision, transition). Active filters glow with state color.

**Live indicator:** Green dot + "Live" label when pipeline is running and WebSocket is connected. Gray dot when idle or disconnected.

### D. Decision Hub

**When PM needs to decide, this becomes the most important screen.**

**Not a modal** — a full-screen overlay with dramatic presence:

```
┌──────────────────────────────────────────────────────────┐
│                                                          │
│              DECISION REQUIRED                           │
│              ─────────────────                           │
│                                                          │
│   Pipeline E-005-1_1 has completed all gates.            │
│   Requesting approval to merge changes.                  │
│                                                          │
│   ┌─ Context ─────────────────────────────────┐         │
│   │  Steps completed: 12/12                    │         │
│   │  Gates: 6/6 passed                         │         │
│   │  Changes: 47 files, +2,341 / -156 lines    │         │
│   │  Duration: 1h 23m                          │         │
│   │                                            │         │
│   │  [View Pipeline] [View Evidence] [View Diff]│        │
│   └────────────────────────────────────────────┘         │
│                                                          │
│   ┌──────────────┐  ┌──────────────┐                    │
│   │   APPROVE     │  │   REJECT     │                    │
│   │   ✓ Merge     │  │   ✗ Decline  │                    │
│   └──────────────┘  └──────────────┘                    │
│                                                          │
│   [Optional feedback: ___________________________]       │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

**Design:**
- Background: dimmed, blurred version of current page (depth overlay)
- Decision card: centered, floating, with state-colored border glow (amber for PM_APPROVAL)
- Context section: structured summary of what happened (not raw data)
- Action buttons: large, clearly labeled, colored (green for approve, red for reject)
- Links to relevant views (pipeline, evidence, diff) open in background
- Feedback text field: optional, for PM notes

**Decision types** (each with appropriate context layout):
- Plan approval (PLAN_REVIEW state)
- Merge approval (PM_APPROVAL state)
- Escalation response (from auto-escalation)
- Curator proposal review
- Release decision (defer/now)

**Notification:** When a decision is pending, the topbar shows a pulsing amber badge with count. Optional audio notification (configurable). The Command Center satellite for decisions also pulses.

**Decision history:** Accessible via the Decision Hub — timeline of past decisions with context, choice, timestamp, and latency.

### E. Evidence Vault

**Browsing execution evidence — not a file tree, but a vault.**

**Left panel — Volumes:**
- EPICs as "volumes" (book-like visual metaphor)
- Under each EPIC: runs as "chapters" (chronological)
- Active/latest run highlighted
- Search/filter within evidence

**Right panel — Content viewer:**
Tabbed content area with smart rendering:

| Format | Renderer |
|--------|----------|
| Markdown (.md) | Rendered HTML with pleasant typography, syntax-highlighted code blocks |
| YAML (.yaml) | Syntax highlighted with collapsible sections, key-value alignment |
| JSON (.json) | Syntax highlighted, collapsible, with path breadcrumb |
| JSONL (.jsonl) | Timeline view — each line as a card (not raw text) |
| Diff (.patch) | Side-by-side or unified diff with line numbers, hunk navigation, syntax highlighting of changed code |
| Text (.txt) | Monospace with line numbers |

**Metadata badge** on each file: type icon, size, last modified, step reference.

**Stage log timeline:** When viewing a run's stage_log.jsonl, render it as a visual timeline (not raw JSONL). Events as cards on a vertical timeline, color-coded by FSM state, with expandable details.

### F. Health Observatory

**Audit and project health visualization.**

**Central gauge:** Large circular gauge (0-100) showing overall health score. The gauge fill color transitions from red (0-40) through amber (40-70) to green (70-100). Number in center with gradient text. Animated on load.

**Category breakdown:** Below the gauge — radar chart or horizontal bar chart showing score per category (code quality, documentation, security, architecture, testing). Each bar has a gradient fill from category color.

**Findings list:** Expandable cards, sorted by severity:
- Critical: red left border
- Warning: amber left border
- Info: blue left border
Each card: title, description, affected file, suggested fix. Clickable file paths open in Evidence Vault.

**Trend sparkline:** If multiple audit reports exist (audit history), show a sparkline chart of health score over time. Small, elegant, in the top-right corner of the gauge area.

**Curator proposals:** If curator has pending improvement proposals, show them as a separate section with "implement" / "defer" actions (linked to Decision Hub flow).

### G. Ideas to Execution

**The "creation pipeline" — from napkin sketch to running code.**

**Layout: Kanban board with a visual brainstorming area**

```
┌──────────────────────────────────────────────────────────────┐
│  [+ Quick Capture]              [View: Board | Brainstorm]   │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  IDEAS        PLANNED       QUEUED        RUNNING    DONE    │
│  ────────     ────────      ────────      ────────   ─────   │
│  ┌──────┐    ┌──────┐      ┌──────┐      ┌──────┐          │
│  │Idea 1│    │Plan 1│ ──── │EPIC 1│ ──── │Run 1 │  ✓ Done  │
│  │      │    │P005-B│      │E-005 │      │      │          │
│  │#ui   │    │      │      │      │      │      │          │
│  └──────┘    └──────┘      └──────┘      └──────┘          │
│  ┌──────┐    ┌──────┐                                       │
│  │Idea 2│    │Plan 2│                                       │
│  └──────┘    └──────┘                                       │
│  ┌──────┐                                                    │
│  │Idea 3│                                                    │
│  └──────┘                                                    │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**Kanban Board view:**
- 5 columns: Ideas → Planned → Queued → Running → Done
- Cards show: title, tags (colored pills), priority badge, linked plan/EPIC
- Drag & drop between columns (dnd-kit)
- Moving from "Queued" → automatic: the card's linked EPIC gets added to the FIRST AID queue
- "Running" column pulls from active pipeline state — shows what's currently executing
- "Done" column pulls from archived EPICs — auto-populated
- Lines connecting related cards across columns (idea → plan → EPIC → run)

**Quick Capture:** Click "+ Quick Capture" → minimal input appears at top of Ideas column. Just title + optional tags. No forms, no friction. Hit Enter → idea created.

**Brainstorm view (toggle):**
Switch from Kanban to a visual brainstorm canvas:
- Ideas as floating nodes on a dark canvas
- Drag to position, group visually
- Connect ideas with lines (relationships)
- Color-code by tag or priority
- Zoom in/out (scroll)
- Double-click node → expand to full idea details
- "Generate Plan" action on any idea → creates plan template linked to the idea

**FIRST AID integration:**
"Launch" button on any EPIC card in Queued column → triggers FIRST AID queue addition. Visual feedback: card gets a rocket icon, moves to Running column when execution starts. Status updates in real-time via WebSocket.

**Scheduled launch on cards:**
Each EPIC card in the Queued column can have a scheduled start time:
- Click clock icon on card → date/time picker appears (minimal, inline)
- Card shows countdown badge: "Starts in 2h 14m" with a subtle ticking animation
- Scheduled cards have a dim clock glow instead of the "ready" glow
- When countdown reaches zero → card automatically transitions to Running (FIRST AID picks it up)
- "Launch now" overrides any schedule

**Backlog & Lessons Learned integration:**
- Backlog items from `.aid-o/04-engine/memory/backlog.md` appear as idea cards tagged `[backlog]`
- Lessons learned from `.aid-o/04-engine/lessons-learned.md` appear in a collapsible sidebar panel — "Wisdom from past runs"
- These items can be dragged into the Ideas column to start a new cycle

### H. Queue Scheduler

**Timeline view for scheduled EPIC execution with cooldown pauses and CC limit awareness.**

The Queue Scheduler is the "mission planner" — where you line up 10 EPICs, set pauses between them to avoid burning through the Claude Code usage limit, and watch the execution unfold over hours.

**Layout: Horizontal timeline + CC limit gauge**

```
┌──────────────────────────────────────────────────────────────────┐
│  QUEUE SCHEDULER                          [CC Limit ████████░░] │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─ Timeline ──────────────────────────────────────────────┐    │
│  │                                                          │    │
│  │  14:00    15:00    16:00    17:00    18:00    19:00      │    │
│  │  ├────────┤        ├────────┤        ├────────┤          │    │
│  │  │ EPIC 1 │ 30min  │ EPIC 2 │ 1h     │ EPIC 3 │         │    │
│  │  │ auth   │ pause  │ API    │ pause  │ UI     │ ...     │    │
│  │  │████████│ ░░░░░  │████░░░░│        │░░░░░░░░│         │    │
│  │  │ done ✓ │        │ 40%    │        │ queued │         │    │
│  │  ├────────┤        ├────────┤        ├────────┤          │    │
│  │                                                          │    │
│  │  ◄ now                                                   │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─ Queue Settings ────────────────────────────────────────┐    │
│  │  Cooldown between EPICs: [30 min ▾]                      │    │
│  │  Max concurrent:         [1 ▾]                           │    │
│  │  Auto-pause at CC limit: [●] enabled                     │    │
│  │  Start time:             [Now ▾] or [Schedule...]        │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─ CC Usage (token-based, estimated) ────────────────────┐    │
│  │                                                          │    │
│  │  ╭──────────╮  Today: ~42k / 100k tokens                 │    │
│  │  │          │  ████████████████░░░░░░░░  (42%)           │    │
│  │  │   42k    │                                            │    │
│  │  │  /100k   │  Estimated remaining: ~7 EPICs             │    │
│  │  │          │  Avg tokens per EPIC: ~8k                  │    │
│  │  ╰──────────╯                                            │    │
│  │                                                          │    │
│  │  ┌─ History ─────────────────────────┐                   │    │
│  │  │  ╱╲    ╱╲                         │                   │    │
│  │  │ ╱  ╲  ╱  ╲  ╱╲                   │  ← 7-day trend    │    │
│  │  │╱    ╲╱    ╲╱  ╲___                │                   │    │
│  │  │ Mon  Tue  Wed  Thu  Fri  Sat  Sun │                   │    │
│  │  └───────────────────────────────────┘                   │    │
│  │  ⚠ Token counts are estimated from stage_log data        │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

**Timeline bar:**
- Horizontal time axis (scrollable, zoomable)
- EPICs as colored blocks — width proportional to estimated duration (from historical avg or plan step count)
- Pause/cooldown gaps shown as dimmed spacers between blocks with duration label
- Currently running EPIC has animated progress fill (left-to-right gradient)
- Completed EPICs are solid with checkmark
- Queued EPICs are outlined/translucent
- Drag EPIC blocks to reorder on timeline
- Drag cooldown spacers to adjust pause duration
- "Now" indicator: vertical line with current time, pulsing dot
- Past (left of "now"): solid, committed history
- Future (right of "now"): projected schedule, slightly dimmer

**Queue settings panel:**
- Cooldown between EPICs: dropdown (15min, 30min, 1h, 2h, custom)
- Max concurrent EPICs: (1 = sequential, 2+ = parallel if independent)
- Auto-pause at CC limit: toggle — automatically pauses queue when approaching CC usage limit
- Start time: "Now" or schedule picker for delayed start of the entire queue
- "Launch Queue" button — starts FIRST AID with the configured schedule

**CC Usage gauge (token-based, always visible in topbar + detail on Queue Scheduler):**
- **Topbar mini-gauge:** compact badge showing `42k / 100k` with color indicator (green/amber/red)
- **Queue Scheduler detail:** expanded view with circular gauge, percentage bar, trend
- Token count: estimated from stage_log.jsonl entries (sum of tokens across today's runs)
- Limit: user-configured token budget (set in Queue Settings — not from Anthropic API)
- "Estimated remaining EPICs" — calculated from average tokens per EPIC in recent runs
- Warning states:
  - 70%: gauge turns amber, label "Approaching limit"
  - 90%: gauge turns red, pulsing, label "Near limit — queue will auto-pause"
  - 100%: gauge filled, queue paused, notification sent
- Mini sparkline: 7-day usage trend (one dot per day)
- Tokens per EPIC breakdown: hover to see individual EPIC token usage from recent runs
- **Accuracy disclaimer:** Token counts are estimated. Show "~" prefix on all numbers to indicate approximation. Actual Anthropic billing may differ.

**Real-time updates:**
- As pipeline runs, the timeline fills in real-time
- Cooldown timer counts down between EPICs
- CC gauge updates after each EPIC completes (or per-step if data is available)
- If queue auto-pauses due to limit → visual: all queued blocks dim, "PAUSED — limit reached" overlay on timeline

**Visual design:**
- Timeline uses the "Orchestration Cinema" aesthetic — dark background, EPIC blocks glow with state colors
- Active EPIC block has particle flow animation (like Pipeline Theater)
- Cooldown gaps have a subtle "breathing" animation (opacity 0.3 → 0.5 → 0.3)
- CC gauge uses the same gradient-fill technique as the Health Observatory gauge
- Completed EPICs in timeline match their final state color (green for success, red for failed)

### I. Knowledge Base

**Interactive visual browser of AID's architecture — commands, agents, skills as connected nodes.**

**Layout: Node graph + detail panel**

```
┌──────────────────────────────────────────────────────────────┐
│  [Filter: Commands | Agents | Skills | All]    [Search...]   │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│         ┌─────────┐                                          │
│         │/aid-run  │────────┐                                │
│         │ -epic    │        │                                │
│         └─────────┘        │                                │
│              │         ┌───▼─────┐     ┌──────────┐         │
│              │         │architect│─────│permission│         │
│              │         │  agent  │     │-sandwich │         │
│         ┌────▼────┐    └─────────┘     └──────────┘         │
│         │epic-    │                                          │
│         │orchestr.│    ┌──────────┐     ┌──────────┐        │
│         │ skill   │────│ parallel │─────│  gates   │        │
│         └─────────┘    │-dispatch │     │ -engine  │        │
│                        └──────────┘     └──────────┘        │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│  DETAIL: /aid-run-epic                                       │
│  ─────────────────────                                       │
│  Main orchestration command. Executes EPIC pipeline with     │
│  12-state FSM, dispatches agents, runs quality gates...      │
│  [Read full documentation →]                                 │
└──────────────────────────────────────────────────────────────┘
```

**Node graph:**
- Three node types with distinct shapes:
  - Commands: rounded rectangles (blue-tinted)
  - Agents: circles (green-tinted)
  - Skills: hexagons (purple-tinted)
- Edges show relationships (command uses skill, skill dispatches agent, agent uses skill)
- Interactive: drag nodes, zoom, pan
- Click node → detail panel shows description, key parameters, related nodes
- Hover → highlight connected nodes and edges
- Filter by type or search to reduce complexity

**Detail panel (bottom or right):**
- Rendered Markdown documentation for the selected node
- "Related" section — other commands/agents/skills that interact with this one
- Links to Evidence Vault for examples of this agent's output

**Data source:** Parsed from `plugins/aid-orchestrator/commands/`, `agents/`, `skills/` — the backend reads these markdown files and extracts frontmatter + first paragraph for summaries.

### I. AI Companion

**Not a search bar. An omnipresent AI assistant embedded in the dashboard.**

**Visual presence:**
- Always visible in the topbar — a subtle glowing input field with a magic/sparkle icon
- Placeholder text rotates through contextual suggestions: "Ask about dispatch strategy...", "What happened in the last run?", "How does the gates engine work?"
- Click or `Cmd+K` → the field expands into a command-palette-style overlay

**Expanded view (command palette style):**
```
┌──────────────────────────────────────────────────────────────┐
│  🔮  Ask anything...                               [🎤 mic] │
├──────────────────────────────────────────────────────────────┤
│  PRESETS                                                     │
│  ────────                                                    │
│  📊 What's the status of my pipeline?                        │
│  🔍 Show me lessons from the last 3 runs                     │
│  ⚡ What should I work on next?                              │
│  📝 Summarize recent decisions                               │
│  🏥 Run a health check                                       │
│  ────────                                                    │
│  RECENT                                                      │
│  ────────                                                    │
│  "Why did gate lint_pass fail yesterday?"                    │
│  "Compare run performance this week"                         │
└──────────────────────────────────────────────────────────────┘
```

**Preset suggestions:** Dynamic, context-aware. If pipeline is running → "What step is currently executing?". If decision pending → "Show me what needs approval". If idle → "What's in the queue?". Presets come from the backend's `/api/companion/presets` endpoint.

**Voice input:** Microphone button uses Web Speech API (browser-native speech-to-text). Click to start, click to stop. Transcribed text goes into the search field. No external API needed.

**Results:** Displayed inline below the input, styled as cards:
- Knowledge results (from Qdrant): relevance score bar, source type badge, text excerpt
- Project context results: structured data from active-work.md, backlog.md, lessons-learned.md
- Navigation results: "Go to Pipeline", "Open Evidence Vault" — clickable actions
- If Qdrant is unavailable: show project context results only with "Memory offline" badge

**AI Companion is the help system.** Instead of navigating to a help page, users can ask: "How does the dispatch strategy work?" and get an answer that combines AID documentation + their project's specific configuration. Context-aware help.

---

## Layout & Navigation

### Shell Structure

```
┌─────────────────────────────────────────────────────────────┐
│  TOPBAR: [Project Switcher] [AI Companion ──────] [Badges]  │
├──────┬──────────────────────────────────────────────────────┤
│      │                                                      │
│  S   │                                                      │
│  I   │               MAIN CONTENT AREA                      │
│  D   │                                                      │
│  E   │          (renders active screen)                      │
│  B   │                                                      │
│  A   │                                                      │
│  R   │                                                      │
│      │                                                      │
└──────┴──────────────────────────────────────────────────────┘
```

**Topbar (56px):**
- Left: Project switcher dropdown (project name + colored dot for health)
- Center: AI Companion input (expands on focus)
- Right: Notification badges (decisions, errors), preferences gear icon

**Sidebar (64px collapsed, 240px expanded):**
- Icon-only when collapsed, icon + label when expanded
- Toggle: click hamburger or `[` key
- Items (top to bottom):
  1. Command Center (home icon)
  2. Pipeline Theater (flow icon)
  3. Activity Stream (list icon)
  4. Decision Hub (gavel icon) — badge if pending
  5. Evidence Vault (archive icon)
  6. Health Observatory (heart-pulse icon)
  7. Ideas to Execution (lightbulb icon)
  8. Queue Scheduler (calendar-clock icon)
  9. Knowledge Base (book icon)
- Bottom: Preferences, keyboard shortcuts help

**Keyboard navigation:**
- `Cmd+K` / `Ctrl+K` → AI Companion
- `1-9` → navigate to screen (when no input focused)
- `[` → toggle sidebar
- `Space` → play/pause (in Pipeline Theater replay)
- `Esc` → close overlay / go back
- `?` → show keyboard shortcuts overlay

### Page Transitions

Framer Motion `AnimatePresence` + `layoutId` for shared elements:
- Clicking a metric on Command Center → morphs into the full page view
- Going from Pipeline overview to step detail → step node animates to panel position
- Navigating between screens → crossfade with slight y-axis movement (20px up, 0.2s)

---

## Technical Stack

| Category | Choice | Rationale |
|----------|--------|-----------|
| Framework | React 19 + Vite | Fast dev server, TypeScript, tree-shaking |
| Styling | Tailwind CSS + CSS custom properties | Utility-first + dynamic theming via CSS vars |
| Animation | Framer Motion | Layout animations, gestures, AnimatePresence, spring physics |
| Pipeline SVG | Custom SVG + Canvas overlay | Full control over river-flow design, lightweight particles |
| Charts | Recharts (lightweight) | Health gauge, trend sparklines, radar chart |
| Drag & Drop | dnd-kit | Kanban board, queue management |
| Markdown | marked + highlight.js | Evidence rendering, help content |
| Diff viewer | diff2html | Patch file rendering with syntax highlighting |
| Icons | Custom SVG icon set | Role icons, FSM state icons — unique to AID |
| Sound | Web Audio API (native) | No external deps, synthesized in-browser |
| Voice | Web Speech API (native) | Browser speech-to-text, no API key needed |
| State | Zustand | Minimal, performant, WebSocket-friendly |
| Routing | React Router v7 | 9 routes, shallow hierarchy |
| WebSocket | Native WebSocket + reconnect logic | No library needed, custom hook with auto-reconnect |

**NOT using:** shadcn/ui (too generic), React Flow (too heavy for our use case), Material UI / Ant Design (wrong aesthetic), Next.js (SSR unnecessary for localhost).

**Custom design system:** Build from Radix UI primitives (headless, accessible) + Tailwind styling. Components: Button, Card, Badge, Modal, Tooltip, Dropdown, Input, Toggle, Slider. All themed via CSS custom properties that respond to FSM state.

## High-Level Steps

| # | Task | Description | Effort |
|---|------|-------------|--------|
| 1 | Design system foundation | CSS custom properties (colors, spacing, typography), Tailwind config, Radix UI primitives setup, base components (Button, Card, Badge, Modal, Tooltip, Input), FSM state color system, dark theme tokens, grain texture overlay | M |
| 2 | Layout shell | Topbar + collapsible sidebar + main content area, React Router (9 routes), project switcher component (reads from API), notification badge system, keyboard navigation (Cmd+K, 1-9, [, Esc), CC limit mini-gauge in topbar | M |
| 3 | WebSocket hook + state | Custom `useWebSocket` hook with auto-reconnect, topic subscription, Zustand store for pipeline state / decisions / evidence, connection status indicator | S |
| 4 | Command Center | Central FSM state radial element (SVG + Framer Motion), timeline strip (stage_log events as dots), satellite metrics (queue, health, decisions, active EPIC), idle state animation | M |
| 5 | Pipeline Theater — static | River-flow layout algorithm, step island components (role icons, status, labels), parallel group fan-out/fan-in topology, connection lines with gradient, step detail slide-in panel (output, diff, timing) | L |
| 6 | Pipeline Theater — real-time | WebSocket-driven step status updates, active step pulse animation, step completion sparkle effect, gate open/close animation, progress bar, particle effects (canvas overlay) | M |
| 7 | Pipeline Theater — replay | Play/pause/scrub controls, stage_log timestamp-based animation pacing, playback speed (1x/2x/5x/10x), scrub bar, state reconstruction from events | M |
| 8 | Activity Stream | Event card component, real-time WebSocket feed, new-event animation (slide-in + blur-to-sharp), filter toggles (state, step, type), live indicator, auto-scroll with manual override | M |
| 9 | Decision Hub | Full-screen overlay component, context renderer (per decision type: plan approval, merge, escalation, curator, release), action buttons, feedback field, POST to decisions API, decision history timeline | M |
| 10 | Evidence Vault | Volume/chapter navigation (EPIC → runs), content viewer with format-specific renderers (MD, YAML, JSON, JSONL-as-timeline, diff, text), metadata badges, search within evidence | M |
| 11 | Health Observatory | Circular gauge component (SVG, animated fill), category breakdown (bar chart or radar), findings list (expandable cards, severity badges), trend sparkline, curator proposals section | M |
| 12 | Ideas to Execution — Kanban | 5-column kanban board (dnd-kit), idea card component, quick capture input, drag & drop between columns, FIRST AID launch button, backlog/lessons-learned sidebar, real-time status from pipeline | L |
| 13 | Ideas to Execution — Brainstorm | Visual canvas for idea nodes, drag positioning, connecting lines, zoom/pan, color-coding, "Generate Plan" action, toggle between Kanban and Brainstorm views | M |
| 14 | Queue Scheduler — Timeline | Horizontal timeline component (scrollable, zoomable), EPIC blocks with estimated duration, cooldown gap spacers, drag-to-reorder, drag-to-resize cooldowns, "now" indicator, real-time progress fill, schedule picker (delayed start, per-EPIC scheduling) | L |
| 15 | Queue Scheduler — CC Limit | CC usage gauge component (circular + linear bar), current spend vs plan limit, estimated remaining EPICs calculation, 7-day usage trend sparkline, cost-per-EPIC breakdown, warning states (70%/90%/100%), auto-pause integration, mini-gauge for topbar | M |
| 16 | Knowledge Base | Node graph component (custom SVG), commands/agents/skills as typed nodes, relationship edges, click-to-detail panel, filter by type, search, rendered Markdown documentation viewer | M |
| 17 | AI Companion | Topbar search input with expand-to-palette animation, preset suggestions (dynamic from API), voice input (Web Speech API), result cards (knowledge, context, navigation), Cmd+K trigger, recent queries | M |
| 18 | Sound system | Web Audio API synthesizer, 6 sound effects (step complete, gate pass/fail, PM notification, pipeline complete, error), global volume control, enable/disable toggle in preferences | S |
| 19 | Micro-animations & polish | All animations from the animation table, page transitions (AnimatePresence), loading skeletons, error boundaries with recovery, empty states with illustrations | M |
| 20 | Custom icon set | SVG icons for: 18 agent roles, 12 FSM states, event types, navigation items, status badges. Consistent style — thin line, 24x24 grid, state-colorable via currentColor | S |

## Constraints

- Depends on P005-A backend API being available
- Dark theme only in MVP (light theme deferred)
- Desktop-first, minimum 1280px viewport
- No external font CDN — bundle JetBrains Mono + Inter as woff2
- No external API calls from frontend (all via backend proxy)
- Animations must be performant: 60fps, GPU-accelerated (transform + opacity only), reduced-motion media query support
- Accessibility: Radix primitives provide ARIA, keyboard navigation on all interactive elements
- Bundle size target: < 500KB gzipped (excluding fonts)

## GUI Capabilities & Limitations (Claude Code Integration Reality)

This section documents what the GUI can and cannot realistically do when connected to Claude Code and the AID orchestrator. This is critical for setting correct expectations and avoiding building features that can't actually work.

### What GUI CAN do (read/write to filesystem + process control):

| Capability | Mechanism | Notes |
|------------|-----------|-------|
| **Display pipeline state in real-time** | Read + watch `stage_log.jsonl` via chokidar | Core feature — read-only, safe, reliable |
| **Read all .aid-o/ files** | Filesystem read: plans, EPICs, evidence, audit reports, active-work.md, lessons-learned.md, backlog.md | Straightforward file reading |
| **Display health score** | Parse `audit_report.yaml` | Read-only |
| **Manage Ideas (CRUD)** | Read/write `ideas.json` in .aid-o/ | Only metadata — no CC invocation needed |
| **Approve/Reject decisions** | Write decision response to a file that AID pipeline reads at PM_APPROVAL checkpoint | Works because AID polls for decision file |
| **Launch EPIC execution** | Spawn `claude -p "invoke skill aid-run-epic..."` as child process | GUI starts the process, then monitors via stage_log |
| **Queue sequential EPICs** | Orchestrate: start EPIC → wait for completion (watch stage_log) → cooldown timer → start next | Bash-level orchestration over `claude` CLI |
| **Track token usage (estimated)** | Parse stage_log.jsonl entries for token counts if available, or estimate from step count/duration | Approximation — not exact billing data |
| **Search knowledge (Qdrant)** | Proxy to Qdrant MCP server via backend | Requires Qdrant MCP to be running |
| **Voice input** | Web Speech API (browser-native) | No external API — works offline in supported browsers |
| **Browse Knowledge Base** | Parse command/agent/skill markdown files from plugin directory | Static data, read at server startup |

### What GUI CANNOT do (hard limitations):

| Limitation | Reason | Workaround |
|------------|--------|------------|
| **Stop a running EPIC gracefully** | Claude Code has no graceful stop API. Process can be killed but leaves incomplete state | Kill process + manual cleanup. Consider adding a "poison pill" file that AID checks between steps |
| **Send messages to a running agent** | Agents run as autonomous Claude sessions — no bidirectional communication during execution | PM_APPROVAL is the only built-in checkpoint. Design around planned checkpoints, not ad-hoc interruption |
| **Get exact CC billing/spend in dollars** | Anthropic has no billing API accessible from CLI. Claude Code doesn't expose current spend | Track token counts from stage_log (if available) and estimate cost using known per-token pricing. Show as "~estimated" not exact |
| **Run truly concurrent EPICs** | Each Claude Code invocation is an independent process with its own session | Can run 2+ processes in parallel, but each consumes from the same CC plan limit. Not recommended without explicit user control |
| **Modify running pipeline configuration** | Once an EPIC is executing, plan.json and pipeline config are locked | Queue changes apply to next EPIC only |
| **Access Anthropic dashboard data** | No API for usage/billing dashboard | Token estimation only |

### CC Usage Tracking — Realistic Approach:

The CC Usage gauge in the topbar (currently showing `42k / 100k` tokens) works as follows:

- **Source:** Sum token counts from `stage_log.jsonl` entries across all runs today
- **Limit:** User-configured token budget (not from Anthropic API — user sets their own limit)
- **Accuracy:** Approximate — depends on what stage_log records. If token counts aren't in stage_log, estimate from step count × average tokens per step
- **Auto-pause:** When estimated usage approaches user-set limit → pause queue, show warning. This prevents overshoot but is not exact billing protection
- **Display:** Token-based (`42k / 100k`) not dollar-based — tokens are what we can measure

### Key Architectural Insight:

> **The GUI is 90% visualization (read-only monitoring) and 10% control (launching EPICs, approving decisions, managing queue).** It is a "mission observation deck with a launch button" — not a full remote control. This is by design: Claude Code agents are autonomous; the PM's role is to observe, decide at checkpoints, and schedule — not to micromanage running agents.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Custom design system takes too long | High | High | Start with minimal component set (8 core components), iterate visually after functionality works |
| Pipeline SVG animation performance | Medium | Medium | Canvas overlay for particles (GPU-composited), limit particle count, use requestAnimationFrame efficiently |
| Run replay timing accuracy | Low | Low | Use stage_log timestamps for pacing, accept approximate timing (not frame-perfect) |
| Web Speech API browser support | Medium | Low | Feature-detect, hide mic button if unavailable, text input always works |
| Design vision vs implementation gap | High | High | Write detailed design specs (this document), use Storybook for component development, iterate in isolation before integration |

## Success Criteria

- Single screenshot of Pipeline Theater is immediately recognizable as AID — not generic
- FSM state change visually transforms the entire UI mood (colors, glow, animation tempo)
- Pipeline run replay plays smoothly at 60fps with correct event timing
- Kanban board allows drag-and-drop from idea to queued EPIC with one gesture
- AI Companion answers project-specific questions using Qdrant + local context
- Knowledge Base node graph correctly maps all 13 commands, 18 agents, 22 skills with relationships
- Sound effects are subtle, non-annoying, and enhance the experience
- Zero-config: `npx aid-gui` → browser opens → content appears without any setup
- Queue Scheduler timeline allows scheduling 10+ EPICs with configurable cooldowns via drag & drop
- CC limit gauge accurately reflects current usage and warns before hitting plan limits
- Auto-pause activates when CC usage approaches limit, preventing unexpected charges

---

## Appendix: UI Agent Proposal

### Purpose

A specialized AI agent designed to generate detailed, evocative, and technically precise UI/UX descriptions from high-level feature specifications. This agent bridges the gap between "what it should do" and "how it should look and feel" — producing output that serves as a complete brief for frontend implementation or AI-powered UI generators.

### Agent Name: `ui-visionary`

### Role Definition

```markdown
You are a UI/UX visionary agent. Your task is to transform functional
specifications into rich, detailed visual and interaction design
descriptions that capture not just layout but emotion, motion, and
aesthetic identity.

You do NOT produce code. You produce design specifications so vivid
and precise that any frontend developer or AI code generator can
implement them without ambiguity.
```

### Input

The agent receives:
1. **Feature specification** — what the screen/component should do (functional requirements)
2. **Design language reference** — the project's established visual identity (colors, typography, animation principles, component library)
3. **Context** — what screens exist already, how this feature connects to them, user flows
4. **Constraints** — technical limitations (bundle size, performance targets, browser support)

### Output Structure

The agent produces a structured design document with these sections:

1. **Screen Purpose** (2-3 sentences) — what this screen exists to do, what emotion it should evoke
2. **Layout Diagram** (ASCII art) — spatial arrangement of elements, responsive breakpoints
3. **Component Inventory** — every visual element on the screen, with:
   - Element name and type (card, button, chart, input, etc.)
   - Visual description (colors, borders, shadows, typography)
   - Content source (which API endpoint / data field)
   - Interactive behavior (hover, click, drag, focus states)
4. **Animation Choreography** — every animation on the screen:
   - Trigger (on load, on data change, on hover, on click)
   - Motion description (what moves, from where to where)
   - Timing (duration, easing, delay)
   - Purpose (why this animation exists — what does it communicate?)
5. **State Variations** — how the screen looks in different states:
   - Loading (skeleton / shimmer)
   - Empty (no data — illustration + message)
   - Error (error boundary — recovery action)
   - Active (data flowing, animations running)
   - Idle (calm, muted, resting)
6. **Interaction Flow** — step-by-step user journey through the screen:
   - What draws attention first (visual hierarchy)
   - Primary action path (1-2 clicks to main goal)
   - Secondary explorations (hover-to-discover, expand-to-detail)
   - Keyboard shortcuts specific to this screen
7. **Sound Cues** (if applicable) — what sounds play and when
8. **Accessibility Notes** — ARIA roles, focus order, screen reader announcements
9. **Design Tokens** — specific CSS values for this screen:
   - Colors (hex values with semantic names)
   - Spacing (px/rem values)
   - Border radii, shadows, blur values
   - Font sizes, weights, line heights

### Agent Behavioral Rules

1. **Be specific, not vague.** Never write "nice animation" — write "translateY from 20px to 0px over 0.3s with ease-out, opacity from 0 to 1."
2. **Be opinionated.** Don't present options — make design decisions and justify them.
3. **Think in motion.** Static mockups are not enough. Every screen has states, transitions, and real-time data flow. Describe the movie, not the poster.
4. **Respect the design language.** All decisions must align with the established visual identity. Reference color tokens, typography scale, animation principles by name.
5. **Think about empty states.** What does this screen look like with zero data? This is often the first thing a user sees. Make it welcoming, not broken.
6. **Think about overload.** What happens when there are 100 items? 1000 events? Design for realistic data volumes.
7. **Consider the periphery.** How does this screen affect the sidebar, topbar, notifications? Does the FSM state color influence this screen's mood?
8. **Write for implementers.** The developer reading this should be able to build it without asking a single clarifying question. Every measurement, every color, every timing value should be specified.

### Integration with AID

This agent would be added to `plugins/aid-orchestrator/agents/` as `ui-visionary.md` and dispatched during frontend EPIC steps. When a frontend step's objective is "Implement {screen name}", the architect step would first dispatch `ui-visionary` to generate the design spec, which then becomes the input for the `frontend` agent.

**Pipeline integration:**
```
architect → ui-visionary → frontend → qa
    ↓              ↓             ↓        ↓
  API spec    Design spec    React code   Tests
```

The `ui-visionary` agent's output is saved as evidence (`design-spec.md`) alongside the step's code output, creating a traceable link from visual intent to implementation.

### Example Dispatch

```yaml
step: step_5_ui_visionary
role: ui-visionary
objective: "Design the Pipeline Theater screen for the AID GUI Dashboard"
inputs:
  - P005-B plan (Pipeline Theater section)
  - Design language reference (Orchestration Cinema)
  - API contract (GET /api/p/:projectId/pipeline)
  - Existing layout shell (topbar, sidebar)
outputs:
  - design-spec-pipeline-theater.md
constraints:
  - Must align with Orchestration Cinema design language
  - 60fps animation budget
  - Custom SVG, no React Flow
  - Dark theme only
```

---

**Last Updated:** 2026-02-24
