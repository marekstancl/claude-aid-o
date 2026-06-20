<!--
  Fixture for parseScope (EPIC E-047-2_7, Step 2).
  Scope section derived from .aid-o/tasks/archive/E-047-1_7-aid-cockpit-mvp1.md
  "### Allowed files/paths" list, plus the §9.1 "Distribution boundary"
  forbidden entry from that EPIC's Constraints, re-homed under "### Forbidden
  zones" so the parser exercises a real forbidden bucket. Inline (annotations)
  on two allowed paths exercise the annotation-strip path.
-->

## Scope

### Allowed files/paths
- `/opt/eco/projects/aid-orchestrator/packages/aid-server/src/parsers/markdown.ts`
- `/opt/eco/projects/aid-orchestrator/packages/aid-server/src/parsers/index.ts`
- `/opt/eco/projects/aid-orchestrator/packages/aid-contract/package.json` (lines 1-21)
- `/opt/eco/projects/aid-orchestrator/packages/aid-contract/src/view.ts` (read-only reference)
- `/opt/eco/projects/aid-orchestrator/tsconfig.base.json`

### Forbidden zones
- `.claude-plugin/marketplace.json` (Distribution boundary — G-009 / §9.1)
- `plugins/aid-orchestrator/.claude-plugin/plugin.json`
- `plugins/aid-orchestrator/CHANGELOG.md` (8 version files / plugin CHANGELOG)
- `plugins/aid-orchestrator/defaults/`
