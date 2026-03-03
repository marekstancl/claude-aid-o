/**
 * Build a rich system prompt with project context for the AI Companion.
 *
 * Reads project metadata, CLAUDE.md, current EPIC, pipeline state, queue,
 * recent decisions, and workspace structure to give the model full awareness.
 */

import { join } from 'node:path';
import { FsReader } from '../services/fs-reader.js';
import type { Project } from '../services/project-registry.js';

export async function buildProjectContext(
  project: Project,
  fs: FsReader,
): Promise<string> {
  const sections: string[] = [];

  // -- Header
  sections.push(`You are the AI Companion for project **${project.name}** (id: \`${project.id}\`).
Project root: \`${project.path}\`
AID workspace: \`${project.aidoPath}\`

You have full knowledge of this project. Answer questions about its structure, EPICs, plans, pipeline state, and architecture. Be concise and helpful. Speak the user's language (if they write in Czech, respond in Czech).`);

  // -- CLAUDE.md (project instructions)
  const claudeMd = await fs.readText(join(project.path, 'CLAUDE.md'));
  if (claudeMd) {
    sections.push(`## Project Instructions (CLAUDE.md)\n\n${claudeMd.slice(0, 6000)}`);
  }

  // -- Package.json summary
  const pkg = await fs.readJson<any>(join(project.path, 'package.json'));
  if (pkg) {
    sections.push(`## Package
- Name: ${pkg.name ?? '?'}
- Version: ${pkg.version ?? '?'}
- Description: ${pkg.description ?? 'N/A'}`);
  }

  // -- Current pipeline state
  const autoState = await fs.readYaml<any>(join(fs.aidoPath, 'work', 'auto-mode-state.yaml'));
  if (autoState?.session) {
    const s = autoState.session;
    const agg = s.aggregate ?? {};
    sections.push(`## Pipeline State
- Current FSM State: **${s.progress?.current_state ?? 'IDLE'}**
- Current EPIC: ${s.progress?.current_epic_id ?? 'none'}
- Current Step: ${s.progress?.current_step_id ?? 'none'}
- Mode: ${s.mode ?? 'N/A'}
- Session: ${s.session_id ?? 'N/A'}
- Epics Completed: ${agg.epics_completed ?? 0}, Failed: ${agg.epics_failed ?? 0}
- Total Steps Executed: ${agg.total_steps_executed ?? 0}
- Gate Runs: ${agg.total_gate_runs ?? 0}, Retries: ${agg.total_gate_retries ?? 0}
- Escalations: ${agg.total_escalations ?? 0} (budget: ${s.escalation?.budget ?? 0})`);
  }

  // -- EPIC queue
  const queue = await fs.readYaml<any>(join(fs.aidoPath, 'config', 'queue.yaml'));
  if (queue?.queue?.length) {
    const items = queue.queue.slice(0, 10).map((e: any) =>
      `  - ${e.epic_id}: ${e.status} (priority: ${e.priority ?? 'N/A'})`,
    ).join('\n');
    sections.push(`## EPIC Queue (${queue.queue.length} items)\n${items}`);
  }

  // -- Active EPICs (from tasks/)
  const epicFiles = await fs.listDir(join(fs.aidoPath, 'tasks'));
  const activeEpics = epicFiles.filter((f) => f.endsWith('.md') && !f.startsWith('archive'));
  if (activeEpics.length > 0) {
    const epicSummaries: string[] = [];
    for (const file of activeEpics.slice(0, 5)) {
      const content = await fs.readText(join(fs.aidoPath, 'tasks', file));
      if (content) {
        // Extract first 500 chars as summary
        const summary = content.slice(0, 500).replace(/\n/g, ' ').trim();
        epicSummaries.push(`  - **${file}**: ${summary}...`);
      }
    }
    if (epicSummaries.length) {
      sections.push(`## Active EPICs\n${epicSummaries.join('\n')}`);
    }
  }

  // -- Plans (from plans/)
  const planFiles = await fs.listDir(join(fs.aidoPath, 'plans'));
  const activePlans = planFiles.filter((f) => f.endsWith('.md'));
  if (activePlans.length > 0) {
    sections.push(`## Plans\n${activePlans.map((f) => `  - ${f}`).join('\n')}`);
  }

  // -- Recent decisions
  const decisionsDir = join(fs.aidoPath, 'work', 'decisions');
  const decisionFiles = await fs.listDir(decisionsDir);
  if (decisionFiles.length > 0) {
    const recentDecisions = decisionFiles.slice(-5);
    const decisionSummaries: string[] = [];
    for (const file of recentDecisions) {
      const d = await fs.readYaml<any>(join(decisionsDir, file));
      if (d) {
        decisionSummaries.push(`  - [${d.status ?? '?'}] ${d.title ?? file}: ${d.summary ?? d.description ?? ''}`);
      }
    }
    if (decisionSummaries.length) {
      sections.push(`## Recent Decisions\n${decisionSummaries.join('\n')}`);
    }
  }

  // -- Ideas backlog
  const ideas = await fs.readYaml<any>(join(fs.aidoPath, 'work', 'ideas.yaml'));
  if (ideas?.ideas?.length) {
    const ideaList = ideas.ideas.slice(0, 8).map((i: any) =>
      `  - [${i.status ?? '?'}] ${i.title ?? 'Untitled'}`,
    ).join('\n');
    sections.push(`## Ideas Backlog (${ideas.ideas.length} total)\n${ideaList}`);
  }

  // -- Workspace structure summary
  const topLevelDirs = await fs.listDir(project.path);
  const relevantDirs = topLevelDirs.filter((d) =>
    !d.startsWith('.') && !['node_modules', 'dist', 'build', 'coverage'].includes(d),
  );
  if (relevantDirs.length) {
    sections.push(`## Project Structure\nTop-level: ${relevantDirs.join(', ')}`);
  }

  // -- Config summary
  const gatesConfig = await fs.readYaml<any>(join(fs.aidoPath, 'config', 'gates.yaml'));
  if (gatesConfig) {
    const gateNames = Object.keys(gatesConfig.gates ?? gatesConfig).slice(0, 10);
    sections.push(`## Quality Gates\nConfigured: ${gateNames.join(', ')}`);
  }

  return sections.join('\n\n---\n\n');
}
