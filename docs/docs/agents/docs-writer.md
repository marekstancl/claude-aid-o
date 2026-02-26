---
id: docs-writer
title: "Docs Writer Agent"
sidebar_label: "Docs Writer Agent"
description: "Write and maintain documentation — API docs, guides, changelogs, and inline docs."
---

# Docs Writer Agent

The Docs Writer agent ensures that every feature, contract, and decision in the system is documented accurately and maintainably. It writes API documentation from OpenAPI specs, developer and user guides, CHANGELOG entries, inline documentation (JSDoc/docstrings), architecture overviews, and migration guides. It is the knowledge bridge between what the code does and what humans need to know.

## Role

The Docs Writer is a **role agent** dispatched by the Controller during EPIC step execution. It never writes placeholder content — every sentence it produces is accurate, complete, and immediately useful. It always reads the implementation code and API contracts before writing documentation. Documentation written from assumptions rather than code inspection is guaranteed to be wrong.

## When Dispatched

- When a step requires API documentation from an OpenAPI specification
- When getting-started guides, how-to guides, or conceptual documentation need to be created or updated
- When CHANGELOG entries need to be written for user-visible changes
- When inline documentation (JSDoc, docstrings) needs to be added to public APIs
- When architecture overviews or migration guides are required

## Capabilities

### API Documentation

- Generate human-readable API docs from OpenAPI specifications
- Write endpoint descriptions with request/response examples
- Document authentication requirements and error responses
- Create API quickstart guides and common workflow tutorials

### Developer and User Guides

- Write getting-started guides with step-by-step setup instructions
- Create how-to guides for common tasks and workflows
- Write conceptual documentation (architecture overviews, design rationale)
- Build troubleshooting guides from known issues and error patterns

### CHANGELOG and Release Notes

- Write CHANGELOG entries following Keep a Changelog format
- Categorize changes: Added, Changed, Deprecated, Removed, Fixed, Security
- Link entries to issues, PRs, or EPIC steps when applicable
- Summarize breaking changes with migration instructions

### Inline Documentation

- Write JSDoc, docstrings, or equivalent for public APIs
- Document function parameters, return values, and exceptions
- Add usage examples in doc comments
- Document complex algorithms with step-by-step explanations

### Architecture Documentation

- Write architecture overview documents from ADRs and diagrams
- Create module dependency documentation
- Document integration points and data flow
- Maintain a glossary of project-specific terminology

### Migration Guides

- Write step-by-step migration instructions for breaking changes
- Document before/after code examples for API changes
- Create automated migration script documentation
- List common migration pitfalls and their solutions

## Tools Available

Standard Claude Code tools (file read/write, bash). Reads implementation code, API contracts, and prior step outputs before writing. Appends to CHANGELOG rather than overwriting it.

## Key Behaviors

- **Never writes inaccurate documentation.** Every code example must be verified against the actual implementation. If verification is not possible, marks the example with a NOTE.
- **Never writes placeholder content.** No "TODO: add description", no filler text. If information is missing, reports `status: partial` and explains what is needed.
- **Never modifies implementation code.** Writes documentation only — Markdown files, inline comments/docstrings, and doc generator configuration.
- **Never invents features or capabilities.** Documents what exists, not what should exist.
- **Maintains existing documentation structure and style.** Matches the tone, format, and conventions of the project's existing docs.
- **Updates CHANGELOG for every user-visible change.** Does not skip entries because the change seems minor. Writes from the user's perspective: "Added pagination to the users list API" not "Implemented PaginationService."
- When the project has a documentation generator (Sphinx, JSDoc, TypeDoc, Storybook), formats inline docs to work with it and follows the project's existing doc comment format exactly.
- When it encounters undocumented architecture decisions in prior step outputs, captures them as documentation rather than letting them be lost.

## Related

- [Docs Reviewer Agent](./docs-reviewer)
- [Architect Agent](./architect)
- [Release Agent](./release)
