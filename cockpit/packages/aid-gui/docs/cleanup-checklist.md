# AI Studio Cleanup Checklist

**EPIC:** E-005-1_4-gui-foundation
**Author:** Architect agent (Step 1)
**Consumer:** Backend agent (Step 2)
**Date:** 2026-02-25

---

## Purpose

This checklist guides Step 2 (backend agent) through removing all Google AI Studio
artifacts from `packages/aid-gui/` and establishing the server directory structure.
Each item should be completed in order. The project must remain functional (`npm run
dev` working) after each group of changes.

---

## Group 1: Dependency Cleanup

These changes modify `packages/aid-gui/package.json`.

- [ ] Remove `@google/genai` from dependencies
  - **Why:** Gemini API client, no longer needed. The GUI reads local `.aid-o/` files.
  - **File:** `packages/aid-gui/package.json` line ~15
  - **Verify:** `@google/genai` does not appear anywhere in `package.json`

- [ ] Remove `better-sqlite3` from dependencies
  - **Why:** SQLite binding from AI Studio prototype. The GUI has no database.
  - **File:** `packages/aid-gui/package.json` line ~23
  - **Verify:** `better-sqlite3` does not appear anywhere in `package.json`

- [ ] Remove `dotenv` from dependencies
  - **Why:** AI Studio injected env vars via dotenv. Express + Vite handle
    `process.env` natively. No `.env` loading needed.
  - **File:** `packages/aid-gui/package.json` line ~25
  - **Verify:** `dotenv` does not appear anywhere in `package.json`

- [ ] Add `js-yaml` to dependencies
  - **Why:** YAML parser for `.aid-o/` YAML files (epic-queue.yaml,
    auto-mode-state.yaml, policies, etc.)
  - **Command:** `npm install js-yaml` (from `packages/aid-gui/`)
  - **Also add:** `@types/js-yaml` to devDependencies

- [ ] Add `gray-matter` to dependencies
  - **Why:** Markdown frontmatter parser for EPIC specs, plans, IDEAS.md
  - **Command:** `npm install gray-matter` (from `packages/aid-gui/`)

- [ ] Run `npm install` from repo root and verify no errors

---

## Group 2: File Cleanup

- [ ] Delete `metadata.json`
  - **Why:** AI Studio artifact. Contains app name "AID GUI Dashboard v2 8/10"
    and `requestFramePermissions` for microphone. Not needed.
  - **File:** `packages/aid-gui/metadata.json`
  - **Command:** `rm packages/aid-gui/metadata.json`

- [ ] Remove Gemini references from `vite.config.ts`
  - **Current content (lines 11-12):**
    ```typescript
    define: {
      'process.env.GEMINI_API_KEY': JSON.stringify(env.GEMINI_API_KEY),
    },
    ```
  - **Action:** Remove the entire `define` block. Also remove the `loadEnv`
    import and `env` variable if no other uses remain. Remove the AI Studio
    HMR comment (line 19-21).
  - **Target state:** Clean vite config with only `plugins`, `resolve`, and
    `server` sections. Keep the `server.hmr` option but remove the AI Studio
    comment.
  - **File:** `packages/aid-gui/vite.config.ts`

- [ ] Update `index.html` title
  - **Current:** `<title>My Google AI Studio App</title>` (line 6)
  - **Change to:** `<title>AID Dashboard</title>`
  - **File:** `packages/aid-gui/index.html`

- [ ] Clean `.env.example`
  - **Current content:** GEMINI_API_KEY and APP_URL with AI Studio comments
  - **Replace with:**
    ```
    # AID Dashboard — Environment Variables
    #
    # AID_PROJECT_PATH: Absolute path to the project root containing .aid-o/
    # Default: two levels up from packages/aid-gui/ (i.e., the monorepo root)
    # AID_PROJECT_PATH="/path/to/your/project"
    #
    # PORT: Server port (default: 3000)
    # PORT=3000
    ```
  - **File:** `packages/aid-gui/.env.example`

- [ ] Rename package in `package.json`
  - **Current:** `"name": "react-example"` (line 2)
  - **Change to:** `"name": "aid-gui"`
  - **File:** `packages/aid-gui/package.json`

---

## Group 3: Server Directory Structure

- [ ] Create `server/` directory structure
  - **Commands:**
    ```bash
    mkdir -p packages/aid-gui/server/parsers
    mkdir -p packages/aid-gui/server/watchers
    mkdir -p packages/aid-gui/server/ws
    mkdir -p packages/aid-gui/server/api
    ```
  - **Note:** `watchers/`, `ws/`, and `api/` will be empty placeholders — add a
    `.gitkeep` in each to preserve them in git.

- [ ] Create `tests/` directory structure
  - **Commands:**
    ```bash
    mkdir -p packages/aid-gui/tests/server/parsers
    mkdir -p packages/aid-gui/tests/fixtures
    ```

- [ ] Move and refactor `server.ts` into `server/index.ts`
  - **Source:** `packages/aid-gui/server.ts`
  - **Target:** `packages/aid-gui/server/index.ts`
  - **Refactoring required:**
    1. Remove all mock API endpoints (`/api/health`, `/api/projects`,
       `/api/pipeline/status`, `/api/pipeline/steps`, `/api/activity`)
    2. Keep the Express + Vite bootstrap structure
    3. Add a placeholder comment where real API routes will be mounted (EPIC 3)
    4. Keep the `__dirname` resolution but adjust paths for the new location
       (now one level deeper: `path.join(__dirname, '..')` for project root)
    5. Update production static file serving path accordingly
    6. Keep the PORT constant and 0.0.0.0 binding
  - **After move:** Delete the original `packages/aid-gui/server.ts`

- [ ] Update `package.json` scripts
  - **Change `dev` script:** `"dev": "tsx server/index.ts"`
    (was: `"dev": "tsx server.ts"`)
  - **Change `start` script:** `"start": "node server/index.ts"`
    (was: `"start": "node server.ts"`)

---

## Group 4: Verification

- [ ] Run `npm install` from repo root — no errors
- [ ] Run `npm run dev` from `packages/aid-gui/` — server starts on port 3000
- [ ] Verify frontend loads at `http://localhost:3000` (React app renders, even
  though API endpoints return 404 now since mock data was removed)
- [ ] Run `npx tsc --noEmit` from `packages/aid-gui/` — no type errors
  (or document any pre-existing type errors from the frontend code)

---

## Files Summary

| Action | File | Reason |
|--------|------|--------|
| DELETE | `packages/aid-gui/metadata.json` | AI Studio artifact |
| DELETE | `packages/aid-gui/server.ts` | Moved to `server/index.ts` |
| MODIFY | `packages/aid-gui/package.json` | Rename, remove/add deps, update scripts |
| MODIFY | `packages/aid-gui/vite.config.ts` | Remove Gemini references |
| MODIFY | `packages/aid-gui/index.html` | Update title |
| MODIFY | `packages/aid-gui/.env.example` | Replace AI Studio env vars |
| CREATE | `packages/aid-gui/server/index.ts` | Refactored Express bootstrap |
| CREATE | `packages/aid-gui/server/parsers/` | Directory for parsers (Step 4) |
| CREATE | `packages/aid-gui/server/watchers/.gitkeep` | Placeholder (EPIC 2) |
| CREATE | `packages/aid-gui/server/ws/.gitkeep` | Placeholder (EPIC 2) |
| CREATE | `packages/aid-gui/server/api/.gitkeep` | Placeholder (EPIC 3) |
| CREATE | `packages/aid-gui/tests/server/parsers/` | Test directory (Step 5) |
| CREATE | `packages/aid-gui/tests/fixtures/` | Test fixtures (Step 5) |
