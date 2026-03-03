import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  docsSidebar: [
    'intro',
    {
      type: 'category',
      label: 'Getting Started',
      items: [
        'getting-started/installation',
        'getting-started/quick-start',
        'getting-started/configuration',
      ],
    },
    {
      type: 'category',
      label: 'Architecture',
      items: [
        'architecture/overview',
        'architecture/orchestration-flow',
        'architecture/quality-gates',
        'architecture/memory-system',
        'architecture/diagrams',
        'architecture/fsm',
        'architecture/execution-modes',
        'architecture/first-aid-mode',
        'architecture/gui-integration',
      ],
    },
    {
      type: 'category',
      label: 'Commands',
      items: [
        'commands/aid-do',
        'commands/aid-plan',
        'commands/aid-run',
        'commands/aid-status',
        'commands/aid-init',
        'commands/aid-audit',
        'commands/aid-stop',
        'commands/aid-help',
      ],
    },
    {
      type: 'category',
      label: 'Agents',
      items: [
        'agents/overview',
        'agents/implementer',
        'agents/verifier',
        'agents/gate-fixer',
        'agents/curator',
        'agents/auditor',
        'agents/project-scanner',
        'agents/run-validator',
      ],
    },
    {
      type: 'category',
      label: 'Skills',
      items: [
        'skills/overview',
        'skills/pipeline',
        'skills/agent-protocol',
        'skills/role-cards',
        'skills/brainstorming',
        'skills/planner',
        'skills/quality-gates',
        'skills/run-management',
        'skills/memory',
      ],
    },
    {
      type: 'category',
      label: 'Configuration',
      items: [
        'configuration/execution-yaml',
        'configuration/orchestration-yaml',
        'configuration/integrations-yaml',
      ],
    },
    {
      type: 'category',
      label: 'Contributing',
      items: [
        'contributing/how-to-contribute',
        'contributing/plugin-structure',
        'contributing/adding-commands',
        'contributing/adding-agents',
        'contributing/code-style',
      ],
    },
    {
      type: 'category',
      label: 'Troubleshooting',
      items: [
        'troubleshooting/common-issues',
        'troubleshooting/faq',
      ],
    },
  ],
};

export default sidebars;
