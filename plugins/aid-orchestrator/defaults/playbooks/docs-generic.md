# Generic Markdown Documentation Playbook

> Loaded when `project.docs.platform == generic-markdown` or no specific platform detected.
> Contains minimal rules for plain Markdown documentation projects.

## File Format

- Format: `.md` (standard Markdown)
- Documentation root: `{project.docs.path}` (default: `docs/`)

## Frontmatter

No specific frontmatter is required for generic Markdown projects. If the project has its own conventions, follow them.

Optional recommended frontmatter:
```yaml
---
title: "Page Title"
last_updated: "YYYY-MM-DD"
---
```

## Formatting Rules

- Use standard CommonMark Markdown
- No framework-specific syntax required
- Code blocks with language identifier: ` ```python `
- Internal links as relative paths: `[text](./other-doc.md)`

## Build Verification

No build step required for generic Markdown projects. If the project has a static site generator configured separately, check `project.docs.build_command` in `project-profile.yaml`.

## Quality Checklist

- [ ] Markdown renders correctly (no broken syntax)
- [ ] No broken internal links
- [ ] Code examples are accurate and up to date
- [ ] `last_updated` date set on modified files (if frontmatter is used)
