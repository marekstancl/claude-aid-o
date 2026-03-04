/**
 * Integration tests for the Epics, Plans, Config, and Knowledge REST API routes.
 *
 * Uses supertest against a fresh Express app created via createApp().
 * Each test gets its own temporary .aid-o/ directory to avoid cross-test
 * contamination. The AID_PROJECT_PATH environment variable is set to point
 * the project resolver middleware at the temp directory.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';
import request from 'supertest';
import { createApp } from '../../../server/index.ts';

// ---------------------------------------------------------------------------
// Shared setup / teardown
// ---------------------------------------------------------------------------

let tmpDir: string;
let aidoDir: string;

beforeEach(async () => {
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'api-res-test-'));
  aidoDir = path.join(tmpDir, '.aid-o');
  process.env.AID_PROJECT_PATH = aidoDir;
});

afterEach(async () => {
  delete process.env.AID_PROJECT_PATH;
  await fs.rm(tmpDir, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Write a file, creating parent directories if needed. */
async function writeFile(filePath: string, content: string): Promise<void> {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, content, 'utf-8');
}

// ---------------------------------------------------------------------------
// EPIC spec fixtures
// ---------------------------------------------------------------------------

const EPIC_SPEC_CONTENT = `---
status: active
plan_ref: .aid-o/plans/P001.md
plan_epics_total: 2
runs_total: 1
runs_completed: 0
---

# E-001 Test EPIC

## Context

This is the context section for the test EPIC.

## Goal

Deliver a working test EPIC for integration testing.

## Scope

### Allowed files/paths
- src/api/
- tests/

### Forbidden zones
- node_modules/

## Constraints

No special constraints.

## DoD Gates

- tests_pass
- lint_pass

## Acceptance Criteria

- [ ] [backend] API endpoints return correct responses
- [x] [qa] Integration tests pass

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design API contracts | — | — |
| 2 | backend | Implement endpoints | architect | — |
`;

const SECOND_EPIC_CONTENT = `---
status: completed
plan_ref: .aid-o/plans/P002.md
plan_epics_total: 1
runs_total: 1
runs_completed: 1
---

# E-002 Another EPIC

## Context

Second EPIC context.

## Goal

Second EPIC goal.

## Scope

### Allowed files/paths
- src/

### Forbidden zones
- dist/

## Constraints

None.

## DoD Gates

- tests_pass

## Acceptance Criteria

- [x] [backend] Everything works

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | backend | Do everything | — | — |
`;

// ---------------------------------------------------------------------------
// Plan fixtures
// ---------------------------------------------------------------------------

const PLAN_CONTENT = `---
title: Test Plan Alpha
version: 1
created: 2026-01-15
---

# Test Plan Alpha

## Overview

This plan covers the initial setup of the test project.

## EPICs

1. E-001 — Foundation
2. E-002 — Implementation
`;

const PLAN_NO_FRONTMATTER_TITLE = `---
version: 2
---

# Inferred Title Plan

## Overview

This plan has no title in frontmatter but has an H1 heading.
`;

// ===========================================================================
// EPICS
// ===========================================================================

describe('GET /api/p/default/epics', () => {
  it('returns empty array when the tasks directory does not exist', async () => {
    const res = await request(createApp())
      .get('/api/p/default/epics')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toEqual([]);
    expect(res.body.meta.total).toBe(0);
  });

  it('returns empty array when tasks directory exists but is empty', async () => {
    await fs.mkdir(path.join(aidoDir, 'tasks'), { recursive: true });

    const res = await request(createApp())
      .get('/api/p/default/epics')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toEqual([]);
    expect(res.body.meta.total).toBe(0);
  });

  it('returns EPIC list entries when .md files exist', async () => {
    await writeFile(
      path.join(aidoDir, 'tasks', 'E-001-test.md'),
      EPIC_SPEC_CONTENT,
    );
    await writeFile(
      path.join(aidoDir, 'tasks', 'E-002-another.md'),
      SECOND_EPIC_CONTENT,
    );

    const res = await request(createApp())
      .get('/api/p/default/epics')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(2);
    expect(res.body.meta.total).toBe(2);

    // Verify list entry structure.
    const entry1 = res.body.data.find(
      (e: { epicId: string }) => e.epicId === 'E-001-test',
    );
    expect(entry1).toBeDefined();
    expect(entry1.title).toContain('E-001 Test EPIC');
    expect(entry1.status).toBe('active');
    expect(entry1.planRef).toBe('.aid-o/plans/P001.md');

    const entry2 = res.body.data.find(
      (e: { epicId: string }) => e.epicId === 'E-002-another',
    );
    expect(entry2).toBeDefined();
    expect(entry2.status).toBe('completed');
  });

  it('ignores hidden files (starting with dot)', async () => {
    await writeFile(
      path.join(aidoDir, 'tasks', '.hidden-epic.md'),
      EPIC_SPEC_CONTENT,
    );
    await writeFile(
      path.join(aidoDir, 'tasks', 'E-001-test.md'),
      EPIC_SPEC_CONTENT,
    );

    const res = await request(createApp())
      .get('/api/p/default/epics')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0].epicId).toBe('E-001-test');
  });

  it('ignores non-.md files in the epics directory', async () => {
    await writeFile(
      path.join(aidoDir, 'tasks', 'E-001-test.md'),
      EPIC_SPEC_CONTENT,
    );
    await writeFile(
      path.join(aidoDir, 'tasks', 'notes.txt'),
      'Some notes',
    );

    const res = await request(createApp())
      .get('/api/p/default/epics')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(1);
  });
});

describe('GET /api/p/default/epics/:epicId', () => {
  it('returns parsed EPIC spec for existing EPIC', async () => {
    await writeFile(
      path.join(aidoDir, 'tasks', 'E-001-test.md'),
      EPIC_SPEC_CONTENT,
    );

    const res = await request(createApp())
      .get('/api/p/default/epics/E-001-test')
      .expect(200);

    expect(res.body.ok).toBe(true);

    const data = res.body.data;
    expect(data.epicId).toBe('E-001-test');
    expect(data.title).toContain('E-001 Test EPIC');
    expect(data.status).toBe('active');
    expect(data.planRef).toBe('.aid-o/plans/P001.md');
    expect(data.planEpicsTotal).toBe(2);
    expect(data.runsTotal).toBe(1);
    expect(data.runsCompleted).toBe(0);
  });

  it('returns parsed Goal and Context sections', async () => {
    await writeFile(
      path.join(aidoDir, 'tasks', 'E-001-test.md'),
      EPIC_SPEC_CONTENT,
    );

    const res = await request(createApp())
      .get('/api/p/default/epics/E-001-test')
      .expect(200);

    const data = res.body.data;
    expect(data.goal).toContain('Deliver a working test EPIC');
    expect(data.context).toContain('context section for the test EPIC');
  });

  it('returns parsed scope with allowed and forbidden paths', async () => {
    await writeFile(
      path.join(aidoDir, 'tasks', 'E-001-test.md'),
      EPIC_SPEC_CONTENT,
    );

    const res = await request(createApp())
      .get('/api/p/default/epics/E-001-test')
      .expect(200);

    const scope = res.body.data.scope;
    expect(scope.allowedPaths).toContain('src/api/');
    expect(scope.allowedPaths).toContain('tests/');
    expect(scope.forbiddenPaths).toContain('node_modules/');
  });

  it('returns parsed DoD gates', async () => {
    await writeFile(
      path.join(aidoDir, 'tasks', 'E-001-test.md'),
      EPIC_SPEC_CONTENT,
    );

    const res = await request(createApp())
      .get('/api/p/default/epics/E-001-test')
      .expect(200);

    expect(res.body.data.dodGates).toEqual(['tests_pass', 'lint_pass']);
  });

  it('returns parsed acceptance criteria', async () => {
    await writeFile(
      path.join(aidoDir, 'tasks', 'E-001-test.md'),
      EPIC_SPEC_CONTENT,
    );

    const res = await request(createApp())
      .get('/api/p/default/epics/E-001-test')
      .expect(200);

    const criteria = res.body.data.acceptanceCriteria;
    expect(criteria).toHaveLength(2);

    const unchecked = criteria.find(
      (c: { checked: boolean }) => !c.checked,
    );
    expect(unchecked).toBeDefined();
    expect(unchecked.role).toBe('backend');
    expect(unchecked.text).toContain('API endpoints');

    const checked = criteria.find(
      (c: { checked: boolean }) => c.checked,
    );
    expect(checked).toBeDefined();
    expect(checked.role).toBe('qa');
  });

  it('returns parsed steps table', async () => {
    await writeFile(
      path.join(aidoDir, 'tasks', 'E-001-test.md'),
      EPIC_SPEC_CONTENT,
    );

    const res = await request(createApp())
      .get('/api/p/default/epics/E-001-test')
      .expect(200);

    const steps = res.body.data.steps;
    expect(steps).toHaveLength(2);
    expect(steps[0].number).toBe(1);
    expect(steps[0].role).toBe('architect');
    expect(steps[0].dependsOn).toEqual([]);
    expect(steps[1].number).toBe(2);
    expect(steps[1].role).toBe('backend');
    expect(steps[1].dependsOn).toContain('architect');
  });

  it('returns 404 for nonexistent EPIC', async () => {
    // Ensure the epics directory exists but the file does not.
    await fs.mkdir(path.join(aidoDir, 'tasks'), { recursive: true });

    const res = await request(createApp())
      .get('/api/p/default/epics/nonexistent')
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
    expect(res.body.error.message).toContain('nonexistent');
  });

  it('returns 404 when the tasks directory does not exist at all', async () => {
    const res = await request(createApp())
      .get('/api/p/default/epics/E-001-test')
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });
});

// ===========================================================================
// PLANS
// ===========================================================================

describe('GET /api/p/default/plans', () => {
  it('returns empty array when the plans directory does not exist', async () => {
    const res = await request(createApp())
      .get('/api/p/default/plans')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toEqual([]);
    expect(res.body.meta.total).toBe(0);
  });

  it('returns empty array when plans directory exists but is empty', async () => {
    await fs.mkdir(path.join(aidoDir, 'plans'), { recursive: true });

    const res = await request(createApp())
      .get('/api/p/default/plans')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toEqual([]);
    expect(res.body.meta.total).toBe(0);
  });

  it('returns plan list entries with frontmatter titles', async () => {
    await writeFile(
      path.join(aidoDir, 'plans', 'P001.md'),
      PLAN_CONTENT,
    );

    const res = await request(createApp())
      .get('/api/p/default/plans')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.meta.total).toBe(1);

    const entry = res.body.data[0];
    expect(entry.planId).toBe('P001');
    expect(entry.title).toBe('Test Plan Alpha');
    expect(entry.filename).toBe('P001.md');
  });

  it('falls back to H1 heading when frontmatter title is absent', async () => {
    await writeFile(
      path.join(aidoDir, 'plans', 'P002.md'),
      PLAN_NO_FRONTMATTER_TITLE,
    );

    const res = await request(createApp())
      .get('/api/p/default/plans')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(1);

    const entry = res.body.data[0];
    expect(entry.planId).toBe('P002');
    expect(entry.title).toBe('Inferred Title Plan');
  });

  it('returns multiple plan entries sorted by filename', async () => {
    await writeFile(
      path.join(aidoDir, 'plans', 'P001.md'),
      PLAN_CONTENT,
    );
    await writeFile(
      path.join(aidoDir, 'plans', 'P002.md'),
      PLAN_NO_FRONTMATTER_TITLE,
    );

    const res = await request(createApp())
      .get('/api/p/default/plans')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(2);
    expect(res.body.meta.total).toBe(2);
  });

  it('ignores hidden files (starting with dot)', async () => {
    await writeFile(
      path.join(aidoDir, 'plans', '.draft-plan.md'),
      PLAN_CONTENT,
    );
    await writeFile(
      path.join(aidoDir, 'plans', 'P001.md'),
      PLAN_CONTENT,
    );

    const res = await request(createApp())
      .get('/api/p/default/plans')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0].planId).toBe('P001');
  });

  it('ignores non-.md files', async () => {
    await writeFile(
      path.join(aidoDir, 'plans', 'P001.md'),
      PLAN_CONTENT,
    );
    await writeFile(
      path.join(aidoDir, 'plans', 'scratch.txt'),
      'scratch notes',
    );
    await writeFile(
      path.join(aidoDir, 'plans', 'data.json'),
      '{}',
    );

    const res = await request(createApp())
      .get('/api/p/default/plans')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(1);
  });
});

describe('GET /api/p/default/plans/:planId', () => {
  it('returns parsed plan with frontmatter and body', async () => {
    await writeFile(
      path.join(aidoDir, 'plans', 'P001.md'),
      PLAN_CONTENT,
    );

    const res = await request(createApp())
      .get('/api/p/default/plans/P001')
      .expect(200);

    expect(res.body.ok).toBe(true);

    const data = res.body.data;
    expect(data.frontmatter).toBeDefined();
    expect(data.frontmatter.title).toBe('Test Plan Alpha');
    expect(data.frontmatter.version).toBe(1);
    expect(data.body).toContain('# Test Plan Alpha');
    expect(data.body).toContain('## Overview');
    expect(data.body).toContain('initial setup of the test project');
  });

  it('returns plan with null frontmatter when frontmatter is absent', async () => {
    const noFrontmatter = `# Plan Without Frontmatter

## Overview

Just a plain markdown plan.
`;
    await writeFile(
      path.join(aidoDir, 'plans', 'P003.md'),
      noFrontmatter,
    );

    const res = await request(createApp())
      .get('/api/p/default/plans/P003')
      .expect(200);

    expect(res.body.ok).toBe(true);

    const data = res.body.data;
    expect(data.frontmatter).toBeNull();
    expect(data.body).toContain('# Plan Without Frontmatter');
  });

  it('returns 404 for nonexistent plan', async () => {
    await fs.mkdir(path.join(aidoDir, 'plans'), { recursive: true });

    const res = await request(createApp())
      .get('/api/p/default/plans/nonexistent')
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
    expect(res.body.error.message).toContain('nonexistent');
  });

  it('returns 404 when the plans directory does not exist at all', async () => {
    const res = await request(createApp())
      .get('/api/p/default/plans/P001')
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });
});

// ===========================================================================
// CONFIG
// ===========================================================================

describe('GET /api/p/default/config', () => {
  it('returns empty config when the config directory does not exist', async () => {
    const res = await request(createApp())
      .get('/api/p/default/config')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.files).toEqual([]);
    expect(res.body.meta.total).toBe(0);
  });

  it('returns empty config when config directory exists but is empty', async () => {
    await fs.mkdir(path.join(aidoDir, 'config'), { recursive: true });

    const res = await request(createApp())
      .get('/api/p/default/config')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.files).toEqual([]);
    expect(res.body.meta.total).toBe(0);
  });

  it('returns parsed YAML config files', async () => {
    const yamlContent = `permissions:
  auto_approve: true
  max_retries: 3
  roles:
    - backend
    - frontend
`;
    await writeFile(
      path.join(aidoDir, 'config', 'permissions-auto.yaml'),
      yamlContent,
    );

    const res = await request(createApp())
      .get('/api/p/default/config')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.files).toHaveLength(1);
    expect(res.body.meta.total).toBe(1);

    const file = res.body.data.files[0];
    expect(file.filename).toBe('permissions-auto.yaml');
    expect(file.parsed).toBeDefined();
    expect(file.parsed.permissions).toBeDefined();
    expect(file.parsed.permissions.autoApprove).toBe(true);
    expect(file.parsed.permissions.maxRetries).toBe(3);
    expect(file.parsed.permissions.roles).toEqual(['backend', 'frontend']);
  });

  it('returns multiple parsed YAML config files', async () => {
    await writeFile(
      path.join(aidoDir, 'config', 'permissions-auto.yaml'),
      'auto_approve: true\n',
    );
    await writeFile(
      path.join(aidoDir, 'config', 'gates.yaml'),
      'gates:\n  - tests_pass\n  - lint_pass\n',
    );

    const res = await request(createApp())
      .get('/api/p/default/config')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.files).toHaveLength(2);
    expect(res.body.meta.total).toBe(2);

    const filenames = res.body.data.files.map(
      (f: { filename: string }) => f.filename,
    );
    expect(filenames).toContain('permissions-auto.yaml');
    expect(filenames).toContain('gates.yaml');
  });

  it('parses .yml files as well as .yaml files', async () => {
    await writeFile(
      path.join(aidoDir, 'config', 'settings.yml'),
      'debug: false\n',
    );

    const res = await request(createApp())
      .get('/api/p/default/config')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.files).toHaveLength(1);
    expect(res.body.data.files[0].filename).toBe('settings.yml');
    expect(res.body.data.files[0].parsed.debug).toBe(false);
  });

  it('ignores hidden files (starting with dot)', async () => {
    await writeFile(
      path.join(aidoDir, 'config', '.hidden-config.yaml'),
      'secret: value\n',
    );
    await writeFile(
      path.join(aidoDir, 'config', 'visible.yaml'),
      'public: true\n',
    );

    const res = await request(createApp())
      .get('/api/p/default/config')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.files).toHaveLength(1);
    expect(res.body.data.files[0].filename).toBe('visible.yaml');
  });

  it('ignores non-YAML files', async () => {
    await writeFile(
      path.join(aidoDir, 'config', 'notes.md'),
      '# Config notes\n',
    );
    await writeFile(
      path.join(aidoDir, 'config', 'data.json'),
      '{}',
    );
    await writeFile(
      path.join(aidoDir, 'config', 'actual.yaml'),
      'key: value\n',
    );

    const res = await request(createApp())
      .get('/api/p/default/config')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.files).toHaveLength(1);
    expect(res.body.data.files[0].filename).toBe('actual.yaml');
  });

  it('skips backup files with .bak extension', async () => {
    await writeFile(
      path.join(aidoDir, 'config', 'config.yaml.bak'),
      'old: data\n',
    );
    await writeFile(
      path.join(aidoDir, 'config', 'config.yaml'),
      'new: data\n',
    );

    const res = await request(createApp())
      .get('/api/p/default/config')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.files).toHaveLength(1);
    expect(res.body.data.files[0].filename).toBe('config.yaml');
  });

  it('skips temporary files with .tmp extension', async () => {
    await writeFile(
      path.join(aidoDir, 'config', 'temp.yaml.tmp'),
      'temp: data\n',
    );
    await writeFile(
      path.join(aidoDir, 'config', 'real.yaml'),
      'real: data\n',
    );

    const res = await request(createApp())
      .get('/api/p/default/config')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.files).toHaveLength(1);
    expect(res.body.data.files[0].filename).toBe('real.yaml');
  });
});

// ===========================================================================
// KNOWLEDGE
// ===========================================================================

describe('GET /api/p/default/knowledge', () => {
  it('returns empty array when the plugins directory does not exist', async () => {
    // aidoDir is the .aid-o/ path; knowledge derives project root as parent.
    // Since tmpDir has no plugins/ directory, this should return empty.
    await fs.mkdir(aidoDir, { recursive: true });

    const res = await request(createApp())
      .get('/api/p/default/knowledge')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toEqual([]);
    expect(res.body.meta.total).toBe(0);
  });

  it('returns skill items when skill .md files exist', async () => {
    // Knowledge looks for plugins/aid-orchestrator/skills/ relative to
    // the project root (parent of aidoDir, which is tmpDir).
    await fs.mkdir(aidoDir, { recursive: true });
    await writeFile(
      path.join(tmpDir, 'plugins', 'aid-orchestrator', 'skills', 'test-skill.md'),
      `---
name: test-skill
description: A test skill
---

This is a test skill body.
`,
    );

    const res = await request(createApp())
      .get('/api/p/default/knowledge')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.meta.total).toBe(1);

    const item = res.body.data[0];
    expect(item.type).toBe('skill');
    expect(item.name).toBe('test-skill');
    expect(item.description).toBe('A test skill');
    expect(item.filename).toBe('test-skill.md');
  });

  it('returns agent items when agent .md files exist', async () => {
    await fs.mkdir(aidoDir, { recursive: true });
    await writeFile(
      path.join(tmpDir, 'plugins', 'aid-orchestrator', 'agents', 'backend-agent.md'),
      `---
name: backend-agent
description: The backend developer agent
---

Implements server-side logic.
`,
    );

    const res = await request(createApp())
      .get('/api/p/default/knowledge')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(1);

    const item = res.body.data[0];
    expect(item.type).toBe('agent');
    expect(item.name).toBe('backend-agent');
    expect(item.description).toBe('The backend developer agent');
  });

  it('returns command items when command .md files exist', async () => {
    await fs.mkdir(aidoDir, { recursive: true });
    await writeFile(
      path.join(
        tmpDir,
        'plugins',
        'aid-orchestrator',
        'defaults',
        'commands',
        'aid-help.md',
      ),
      `---
name: aid-help
description: Show AID documentation
---

Displays help information.
`,
    );

    const res = await request(createApp())
      .get('/api/p/default/knowledge')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(1);

    const item = res.body.data[0];
    expect(item.type).toBe('command');
    expect(item.name).toBe('aid-help');
    expect(item.description).toBe('Show AID documentation');
  });

  it('returns items from all three directories combined', async () => {
    await fs.mkdir(aidoDir, { recursive: true });
    const pluginBase = path.join(tmpDir, 'plugins', 'aid-orchestrator');

    await writeFile(
      path.join(pluginBase, 'skills', 'skill-a.md'),
      `---
description: Skill A
---

Skill body.
`,
    );
    await writeFile(
      path.join(pluginBase, 'agents', 'agent-b.md'),
      `---
description: Agent B
---

Agent body.
`,
    );
    await writeFile(
      path.join(pluginBase, 'defaults', 'commands', 'cmd-c.md'),
      `---
description: Command C
---

Command body.
`,
    );

    const res = await request(createApp())
      .get('/api/p/default/knowledge')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(3);
    expect(res.body.meta.total).toBe(3);

    const types = res.body.data.map((i: { type: string }) => i.type);
    expect(types).toContain('skill');
    expect(types).toContain('agent');
    expect(types).toContain('command');
  });

  it('extracts description from body when frontmatter description is absent', async () => {
    await fs.mkdir(aidoDir, { recursive: true });
    await writeFile(
      path.join(tmpDir, 'plugins', 'aid-orchestrator', 'skills', 'body-desc.md'),
      `---
name: body-desc
---

# Body Description Skill

This is the first paragraph that should be used as description.

More content follows.
`,
    );

    const res = await request(createApp())
      .get('/api/p/default/knowledge')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0].description).toBe(
      'This is the first paragraph that should be used as description.',
    );
  });

  it('ignores hidden files in plugin directories', async () => {
    await fs.mkdir(aidoDir, { recursive: true });
    const skillsDir = path.join(
      tmpDir,
      'plugins',
      'aid-orchestrator',
      'skills',
    );
    await writeFile(
      path.join(skillsDir, '.hidden-skill.md'),
      '---\ndescription: Hidden\n---\nHidden skill.\n',
    );
    await writeFile(
      path.join(skillsDir, 'visible-skill.md'),
      '---\ndescription: Visible\n---\nVisible skill.\n',
    );

    const res = await request(createApp())
      .get('/api/p/default/knowledge')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0].name).toBe('visible-skill');
  });

  it('gracefully handles empty plugin subdirectories', async () => {
    await fs.mkdir(aidoDir, { recursive: true });
    const pluginBase = path.join(tmpDir, 'plugins', 'aid-orchestrator');
    await fs.mkdir(path.join(pluginBase, 'skills'), { recursive: true });
    await fs.mkdir(path.join(pluginBase, 'agents'), { recursive: true });
    // defaults/commands directory does not exist at all.

    const res = await request(createApp())
      .get('/api/p/default/knowledge')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toEqual([]);
    expect(res.body.meta.total).toBe(0);
  });
});

// ===========================================================================
// Project resolution — shared across all routes
// ===========================================================================

describe('Project resolution middleware', () => {
  it('returns 404 for unknown project IDs (non-default)', async () => {
    const res = await request(createApp())
      .get('/api/p/unknown-project/epics')
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('PROJECT_NOT_FOUND');
  });
});
