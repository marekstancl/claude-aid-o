---
name: setup-project-scan
description: Re-detect project stack and update config/project.yaml
---

# Setup Module: Project Scan

Re-detect project tech stack and update project.yaml.

## Input

Called by `/aid-setup` router or `/aid-setup scan`.

## Flow

1. Read current `.aid-o/config/project.yaml`
2. Scan project root for stack indicators:

| File | Detected | Fields |
|------|----------|--------|
| `package.json` | Node.js/TypeScript | languages, test_cmd, lint_cmd, build_cmd |
| `tsconfig.json` | TypeScript | languages += TypeScript |
| `pyproject.toml` | Python | languages, test_cmd, lint_cmd |
| `requirements.txt` | Python | languages |
| `Cargo.toml` | Rust | languages, test_cmd, build_cmd |
| `go.mod` | Go | languages, test_cmd, lint_cmd, build_cmd |
| `pom.xml` | Java/Kotlin | languages, test_cmd, build_cmd |
| `docker-compose.yml` | Docker | note in project.yaml |
| `.github/workflows/` | CI/CD | note in project.yaml |
| `Makefile` | Make | detect targets for test/lint/build |
| `docusaurus.config.*` | Documentation site | `documentation.docusaurus` — the content root |
| a help route/page (`help`, `napoveda`) | In-app help | `documentation.in_app_help` — its path |
| `lib/ui-fidelity/ui-capture.mjs` (or the project's own) | Screenshot tool | `documentation.screenshot_tool` — the command that runs it |
| a UI (component dirs, a frontend framework, CSS) | Responsive UI | `ui.responsive` — `true` unless the PM says the app is desktop-only (P087) |

**The three `documentation.*` facts are defined here, once** — `/aid-init` and
`skills/plan-writing.md` point at this section rather than restating it:

```yaml
documentation:
  in_app_help: src/app/napoveda     # dir/file of the in-app help, omit if none
  docusaurus: docs/docs/myproject   # the docs site's content root, omit if none
  screenshot_tool: "node lib/ui-fidelity/ui-capture.mjs <url> <out.png>"
```

They exist so a plan does not rediscover them every time it is written: a plan
that changes behaviour a user meets must name the help file and the docs page
it changes, and `aid-plan-lint.sh` checks that against these values — **every**
surface listed here, not just one of them.

```yaml
ui:
  responsive: true                  # default; false only for a deliberately desktop-only app
```

`ui.responsive` is read by `scripts/lib/aid-ui-proposal.sh`: `true` (or absent) means every
UI proposal and every UI check covers desktop AND mobile; `false` means desktop alone. It is
asked only of a project that has a UI; confirm a `false` with the PM — it is a decision about
the product, not a detection.

**Omit a key the project does not have** — absent means the obligation does not
apply, while an empty string looks like a path that failed to match. Any key
under `documentation:` other than `screenshot_tool` counts as a surface, so a
project with a wiki or a second help route adds one line rather than patching
the plugin. Confirm a detected help path with the PM rather than guessing one
into the file.

3. Compare detected values with existing project.yaml
4. Show diff to PM:
   ```
   Project scan results:
     languages: [TypeScript, Python] → [TypeScript, Python, Go]  (CHANGED)
     test_cmd:  "npm test"                                        (unchanged)
     lint_cmd:  "npm run lint"                                    (unchanged)
     build_cmd: null → "go build ./..."                           (NEW)

   Apply changes? (Y/n)
   ```
5. On approval → merge changes into existing `config/project.yaml` (preserve custom fields)
6. Update `scanned_at` timestamp

## Important

- Never overwrite custom fields the user added to project.yaml
- Merge detected values, don't replace the entire file
- If multiple build systems detected (e.g. package.json + Makefile), list all commands

## Output

```
Project scan complete:
  {N} fields updated, {M} unchanged
Written to: .aid-o/config/project.yaml
```


**Last Updated:** 2026-08-25
