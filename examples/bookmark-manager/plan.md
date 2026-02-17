# Plan: Bookmark Manager — Full-Stack Web App

**ID:** P-20260217-bm01
**Status:** Approved → EPIC created
**Date:** 2026-02-17

---

## 1. Problem Statement

We need a self-contained demo app that showcases AID orchestration end-to-end.
The app should be useful on its own (not just a toy), produce a visible web UI,
and require zero external dependencies (no database server, no auth, no third-party APIs).

## 2. Options Considered

### Option A: Todo App
- **Pros:** Simple, well-understood, fast to build
- **Cons:** Boring, doesn't showcase enough agent variety, overdone

### Option B: Bookmark Manager ← SELECTED
- **Pros:** Useful, full-stack (API + DB + UI), rich enough to exercise all roles (search, tags, CRUD, favicon fetching). Zero external deps with SQLite.
- **Cons:** Slightly more complex than a todo app
- **Why chosen:** Best balance of usefulness, visual appeal, and orchestration coverage

### Option C: Pomodoro Timer + Task Tracker
- **Pros:** Visual, interactive
- **Cons:** Timer logic is frontend-heavy, less backend work, doesn't showcase security agent well

## 3. Design Decisions

### Storage: SQLite
- Zero config — file-based, auto-created on startup
- Good enough for single-user app
- No migrations needed — CREATE IF NOT EXISTS

### Tech Stack
- **Backend:** FastAPI + SQLite (via `sqlite3` stdlib)
- **Frontend:** React + TypeScript + CSS modules
- **No auth** — single-user, no login

### API Design
- REST, prefix `/api/v1/bookmarks`
- Standard CRUD + search (`?q=`) + tag filter (`?tag=`)
- Pagination with `page` + `per_page` params
- Auto-fetch URL title with 3s timeout

### Component Architecture
```
App
├── Layout
│   ├── TagSidebar (tag list with counts)
│   └── Main
│       ├── SearchBar
│       ├── BookmarkForm (add/edit modal)
│       └── BookmarkGrid
│           └── BookmarkCard × N (title, URL, favicon, tags)
```

### Data Model
```
bookmarks:        id, url, title, description, favicon_url, created_at, updated_at
tags:             id, name
bookmark_tags:    bookmark_id, tag_id (junction table)
```

## 4. Agent Coverage

| Agent | What it does in this EPIC |
|-------|--------------------------|
| Architect | OpenAPI spec, SQLite schema, component tree, ADR |
| Backend | FastAPI endpoints, SQLite setup, URL fetcher |
| Frontend | React components, API client, layout |
| QA | Pytest for API, edge cases, URL fetcher mocking |
| Security | SQL injection review, SSRF check on URL fetcher |
| Docs | API documentation, CHANGELOG |

## 5. Out of Scope

- User authentication (single-user app)
- Import/export (bookmarks from browser)
- Browser extension
- Full-text search (basic LIKE query is enough)
- Deployment (runs locally only)

## 6. Success Criteria

After `/run-epic` completes:
1. Backend starts with `uvicorn backend.app.main:app`
2. Frontend starts with `npm run dev`
3. User can add, search, tag, edit, and delete bookmarks
4. Quality gates pass (tests, lint, docs)

---

**Next step:** Create EPIC from this plan → `EPIC.md`
