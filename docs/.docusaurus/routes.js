import React from 'react';
import ComponentCreator from '@docusaurus/ComponentCreator';

export default [
  {
    path: '/ai-orchestrator/cs/',
    component: ComponentCreator('/ai-orchestrator/cs/', '855'),
    routes: [
      {
        path: '/ai-orchestrator/cs/',
        component: ComponentCreator('/ai-orchestrator/cs/', '7ff'),
        routes: [
          {
            path: '/ai-orchestrator/cs/',
            component: ComponentCreator('/ai-orchestrator/cs/', 'cf3'),
            routes: [
              {
                path: '/ai-orchestrator/cs/agents',
                component: ComponentCreator('/ai-orchestrator/cs/agents', '7fb'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/agents/architect',
                component: ComponentCreator('/ai-orchestrator/cs/agents/architect', '0a9'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/agents/auditor',
                component: ComponentCreator('/ai-orchestrator/cs/agents/auditor', '95b'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/agents/backend',
                component: ComponentCreator('/ai-orchestrator/cs/agents/backend', 'f63'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/agents/code-reviewer',
                component: ComponentCreator('/ai-orchestrator/cs/agents/code-reviewer', 'd02'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/agents/curator',
                component: ComponentCreator('/ai-orchestrator/cs/agents/curator', '82d'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/agents/docs-reviewer',
                component: ComponentCreator('/ai-orchestrator/cs/agents/docs-reviewer', 'dea'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/agents/docs-writer',
                component: ComponentCreator('/ai-orchestrator/cs/agents/docs-writer', '387'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/agents/domain',
                component: ComponentCreator('/ai-orchestrator/cs/agents/domain', '122'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/agents/frontend',
                component: ComponentCreator('/ai-orchestrator/cs/agents/frontend', '0a5'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/agents/gate-fixer',
                component: ComponentCreator('/ai-orchestrator/cs/agents/gate-fixer', '782'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/agents/lessons-extractor',
                component: ComponentCreator('/ai-orchestrator/cs/agents/lessons-extractor', 'c4f'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/agents/observability',
                component: ComponentCreator('/ai-orchestrator/cs/agents/observability', '3a2'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/agents/overview',
                component: ComponentCreator('/ai-orchestrator/cs/agents/overview', 'f80'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/agents/project-scanner',
                component: ComponentCreator('/ai-orchestrator/cs/agents/project-scanner', 'fb5'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/agents/qa',
                component: ComponentCreator('/ai-orchestrator/cs/agents/qa', 'a0a'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/agents/quality-gates-runner',
                component: ComponentCreator('/ai-orchestrator/cs/agents/quality-gates-runner', 'f86'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/agents/release',
                component: ComponentCreator('/ai-orchestrator/cs/agents/release', '69a'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/agents/run-validator',
                component: ComponentCreator('/ai-orchestrator/cs/agents/run-validator', 'b29'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/agents/security',
                component: ComponentCreator('/ai-orchestrator/cs/agents/security', '67a'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/commands',
                component: ComponentCreator('/ai-orchestrator/cs/commands', 'f19'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/commands/aid-analytics',
                component: ComponentCreator('/ai-orchestrator/cs/commands/aid-analytics', '7a4'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/commands/aid-audit',
                component: ComponentCreator('/ai-orchestrator/cs/commands/aid-audit', 'f51'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/commands/aid-brainstorm',
                component: ComponentCreator('/ai-orchestrator/cs/commands/aid-brainstorm', '2af'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/commands/aid-epic-queue',
                component: ComponentCreator('/ai-orchestrator/cs/commands/aid-epic-queue', 'ba2'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/commands/aid-epic-status',
                component: ComponentCreator('/ai-orchestrator/cs/commands/aid-epic-status', '776'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/commands/aid-first-aid',
                component: ComponentCreator('/ai-orchestrator/cs/commands/aid-first-aid', 'c89'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/commands/aid-help',
                component: ComponentCreator('/ai-orchestrator/cs/commands/aid-help', 'b3d'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/commands/aid-init',
                component: ComponentCreator('/ai-orchestrator/cs/commands/aid-init', '51e'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/commands/aid-plan-epic',
                component: ComponentCreator('/ai-orchestrator/cs/commands/aid-plan-epic', 'ce8'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/commands/aid-research',
                component: ComponentCreator('/ai-orchestrator/cs/commands/aid-research', '718'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/commands/aid-run-epic',
                component: ComponentCreator('/ai-orchestrator/cs/commands/aid-run-epic', '178'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/commands/aid-setup',
                component: ComponentCreator('/ai-orchestrator/cs/commands/aid-setup', 'b64'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/commands/aid-stop',
                component: ComponentCreator('/ai-orchestrator/cs/commands/aid-stop', '76f'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/getting-started',
                component: ComponentCreator('/ai-orchestrator/cs/getting-started', 'a7d'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/getting-started/configuration',
                component: ComponentCreator('/ai-orchestrator/cs/getting-started/configuration', '69e'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/getting-started/installation',
                component: ComponentCreator('/ai-orchestrator/cs/getting-started/installation', 'a2c'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/getting-started/quick-start',
                component: ComponentCreator('/ai-orchestrator/cs/getting-started/quick-start', 'ae8'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills',
                component: ComponentCreator('/ai-orchestrator/cs/skills', 'c36'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/agent-core',
                component: ComponentCreator('/ai-orchestrator/cs/skills/agent-core', '9ea'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/analysis-merge',
                component: ComponentCreator('/ai-orchestrator/cs/skills/analysis-merge', '2b3'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/analytics',
                component: ComponentCreator('/ai-orchestrator/cs/skills/analytics', '9a4'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/auto-done-state',
                component: ComponentCreator('/ai-orchestrator/cs/skills/auto-done-state', '9e7'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/auto-escalation',
                component: ComponentCreator('/ai-orchestrator/cs/skills/auto-escalation', '06b'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/brainstorming',
                component: ComponentCreator('/ai-orchestrator/cs/skills/brainstorming', 'f5b'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/cost-optimization',
                component: ComponentCreator('/ai-orchestrator/cs/skills/cost-optimization', '8d9'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/epic-orchestration',
                component: ComponentCreator('/ai-orchestrator/cs/skills/epic-orchestration', 'e0a'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/epic-queue',
                component: ComponentCreator('/ai-orchestrator/cs/skills/epic-queue', '5df'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/gates-engine',
                component: ComponentCreator('/ai-orchestrator/cs/skills/gates-engine', '4a6'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/improvement-proposals',
                component: ComponentCreator('/ai-orchestrator/cs/skills/improvement-proposals', '96e'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/knowledge-acquisition',
                component: ComponentCreator('/ai-orchestrator/cs/skills/knowledge-acquisition', 'e6c'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/memory-mcp',
                component: ComponentCreator('/ai-orchestrator/cs/skills/memory-mcp', 'c6f'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/overview',
                component: ComponentCreator('/ai-orchestrator/cs/skills/overview', '886'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/parallel-dispatch',
                component: ComponentCreator('/ai-orchestrator/cs/skills/parallel-dispatch', '622'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/permission-sandwich',
                component: ComponentCreator('/ai-orchestrator/cs/skills/permission-sandwich', '6bf'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/planner',
                component: ComponentCreator('/ai-orchestrator/cs/skills/planner', 'b03'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/quality-gates',
                component: ComponentCreator('/ai-orchestrator/cs/skills/quality-gates', '8d8'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/retry-engine',
                component: ComponentCreator('/ai-orchestrator/cs/skills/retry-engine', '215'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/run-management',
                component: ComponentCreator('/ai-orchestrator/cs/skills/run-management', '7c4'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/slack-mcp',
                component: ComponentCreator('/ai-orchestrator/cs/skills/slack-mcp', '642'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/skills/workflow-intelligence',
                component: ComponentCreator('/ai-orchestrator/cs/skills/workflow-intelligence', '2ce'),
                exact: true,
                sidebar: "docsSidebar"
              },
              {
                path: '/ai-orchestrator/cs/',
                component: ComponentCreator('/ai-orchestrator/cs/', 'dba'),
                exact: true,
                sidebar: "docsSidebar"
              }
            ]
          }
        ]
      }
    ]
  },
  {
    path: '*',
    component: ComponentCreator('*'),
  },
];
