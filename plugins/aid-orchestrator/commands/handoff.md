Create a handoff block for the next AI session.

Read `skills/session-management.md` and follow the Handoff protocol.

The handoff must be **self-contained** — next AI shouldn't need to ask questions.

Required sections:
1. **Completed** — tasks done with commit hashes and files
2. **Now Working On** — current task, progress %, files in progress, next immediate step
3. **Next Steps** — ordered list of remaining actions
4. **Important Context** — decisions made, known issues/gotchas, dependencies
5. **Key Locations** — config, tests, docs, logs paths
6. **How to Test** — commands to verify current state
7. **Branch** — branch name + last commit hash

Write handoff to:
1. Session file (Handoff Notes section)
2. `.aid-o/04-engine/memory/active-work.md` (Context for Next AI section)
3. Epic file (if epic session) + plan file (if exists)
