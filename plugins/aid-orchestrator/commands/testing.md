Load testing workflow and standards for this project.

Read `.aid-o/04-engine/memory/project-profile.yaml` for project-specific test configuration.
Read `defaults/playbooks/qa.md` for the QA agent playbook.

This covers project-specific testing standards:
- Test file naming and structure conventions
- Coverage targets (>80% for new code)
- TDD cycle: RED (write failing test) → GREEN (minimal implementation) → REFACTOR (clean up)
- Regression tests mandatory for bug fixes
- Test templates in `.aid-o/03-config/templates/`

$ARGUMENTS — optional context about what to test.
