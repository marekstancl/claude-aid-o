# Example: Bookmark Manager

A complete AID orchestration example that produces a **working full-stack bookmark manager** — FastAPI backend + React frontend + SQLite storage.

## What's in this example

| File | What it is | Created by |
|------|-----------|------------|
| `plan.md` | Brainstorming output — design decisions, options, architecture | PM + AI via brainstorming |
| `EPIC.md` | Task specification — scope, steps, acceptance criteria | PM (derived from plan) |
| `plan.json` | Execution plan — dependency graph, parallel groups, gates | `/plan-epic` (auto-generated) |

## How to run this example

### 1. Create a fresh project

```bash
mkdir bookmark-manager && cd bookmark-manager
git init

# Create minimal project structure
mkdir -p backend/app/core backend/tests
mkdir -p frontend/src/components frontend/src/features
mkdir -p docs/api docs/architecture/adr

# Backend
cat > backend/app/main.py << 'EOF'
from fastapi import FastAPI
app = FastAPI(title="Bookmark Manager", version="0.1.0")

@app.get("/health")
def health():
    return {"status": "ok"}
EOF

cat > backend/requirements.txt << 'EOF'
fastapi>=0.100.0
uvicorn>=0.23.0
pytest>=7.0.0
httpx>=0.25.0
ruff>=0.1.0
EOF

# Frontend
cat > frontend/package.json << 'EOF'
{
  "name": "bookmark-manager-frontend",
  "version": "0.1.0",
  "scripts": {
    "dev": "echo 'Dev server would start here'",
    "build": "echo 'Build successful'",
    "test": "echo 'Tests passed'",
    "lint": "echo 'Lint passed'"
  }
}
EOF

cat > frontend/src/App.tsx << 'EOF'
export default function App() {
  return <div>Bookmark Manager</div>;
}
EOF

# Git
echo -e "node_modules/\n__pycache__/\n*.pyc\n.env\ndata/" > .gitignore
git add . && git commit -m "chore: initial project structure"
```

### 2. Initialize AID

```bash
# In Claude Code:
/aid-setup
```

### 3. Copy the EPIC

```bash
# Copy from this example (adjust source path)
cp /path/to/examples/bookmark-manager/EPIC.md .aid-o/02-epics/E-20260217-bm01-bookmark-manager.md
```

### 4. Generate plan and run

```bash
# In Claude Code:
/plan-epic .aid-o/02-epics/E-20260217-bm01-bookmark-manager.md
/run-epic
```

### 5. See the result

After orchestration completes:

```bash
# Start backend
cd backend && pip install -r requirements.txt && uvicorn app.main:app --reload

# Start frontend (in another terminal)
cd frontend && npm install && npm run dev
```

## What AID does with this EPIC

```
Step 1: Architect    → designs API contracts, SQLite schema, component tree
                     ↓
Step 2: Backend  ────┤ (parallel)  → implements API + database + URL fetcher
Step 3: Frontend ────┘             → builds React components + layout
                     ↓
Step 4: QA       ────┤ (parallel)  → writes pytest tests for API
Step 5: Security ────┘             → reviews SQL injection, SSRF, input validation
                     ↓
Step 6: Docs         → writes API documentation + updates CHANGELOG
                     ↓
Quality Gates        → tests_pass, lint_pass, docs_updated (auto-retry on failure)
                     ↓
PM Approval          → review and merge
```

## Expected output

A bookmark manager where you can:
- Add bookmarks with URL, title, description, and tags
- Browse bookmarks in a card grid with favicons
- Filter by tags (sidebar with counts)
- Search by title or description
- Edit and delete bookmarks
- Auto-fetched page titles when adding by URL
