Start a new tracked session.

Read `.claude/skills/session-management/instructions.md` and follow the Initialization protocol.

Steps:
1. Read `workspace/active-work.md` for context
2. Determine session type based on $ARGUMENTS or task description:
   - `bug-fix` → use `templates/session-bug-fix.md`
   - `new-feature` → use `templates/session-new-feature.md`
   - `refactoring` → use `templates/session-refactoring.md`
   - `exploration` → use `templates/session-exploration.md`
3. Create session file: `workspace/sessions/active/YYYY-MM-DD-{type}-{topic}.md`
4. Fill in objective and initial analysis
5. Create Think-First plan
6. Ask PM for approval before implementation

Templates: `{project.paths.templates}`
