Load documentation protocol for this project.

Read `.aid-o/04-engine/memory/project-profile.yaml` to determine `project.docs.platform`.
Read the appropriate platform playbook: `defaults/playbooks/docs-{project.docs.platform}.md`.

If no docs platform detected, read `defaults/playbooks/docs-generic.md`.

Covers:
- Platform-specific formatting rules (MDX escaping for Docusaurus, RST for Sphinx, etc.)
- Navigation/sidebar configuration
- Frontmatter requirements
- Mermaid diagram syntax
- Documentation impact analysis (which code changes affect which docs)
- Common build errors and fixes

$ARGUMENTS — optional context about what documentation to create/update.
