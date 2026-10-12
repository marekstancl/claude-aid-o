---
zadani: P<NNN>
verze: 1
datum: YYYY-MM-DD
autor: PM + AI
roadmapa: <optional — where this brief sits in a larger line of releases>
---

# P<NNN> - <short name of what is being built>

<!-- The brief is the PM's specification as a FILE. The plan binds to it by sha
     (`zadani:` / `zadani_sha256:` in the plan's frontmatter) and carries every
     point of section 6 verbatim in its ## Acceptance Criteria. A point changes
     only through a new version of this file (verze +1), which restarts the plan
     review. Check the shape with: aid-plan-lint.sh --zadani <this file>
     The six headings below, their numbers and their order are the contract. -->

## 1. Co PM chce

<!-- The PM's words, verbatim, with the date. Then one paragraph on how you
     understood them. Then the stakes paragraph below — the critic reads it,
     and the lint refuses a brief without it. -->

> „<the PM's words, verbatim>“

**Co je v sázce:** <who pays what, and how much, when this goes wrong — in one paragraph>

## 2. Změřený výchozí stav

<!-- What is true today, each claim measured (file:line, a command and its
     output, a figure with its source). Nothing from memory. This is what
     the plan reviewers check the plan against. -->

- <a measured fact, with file:line or the command that shows it>

## 3. Co udělat

<!-- What to build, as numbered items, with their dependencies. End with
     "Co do tohohle zadání nepatří" — the explicit out-of-scope list. -->

**(1) <item>.** <what changes, and where>

**Co do tohohle zadání nepatří:** <what this brief does not ask for>

## 4. Kde co je

<!-- A table: what → where (path, function, line). The plan's grounding
     starts here. -->

| Co | Kde |
|---|---|
| <thing> | `<path>` (`<function>` ř. <n>) |

## 5. Pravidla práce

<!-- The rules that bind this work: the project's CLAUDE.md and CONTRIBUTING,
     how tests run, what may and may not be touched, who merges. -->

- <rule>

## 6. Hotovo, když

<!-- Every point: `- [ ] AC<n>: <text>` (AC1, AC2, … without gaps), and within
     5 lines a ```yaml block whose first key is verification_pattern
     (skills/plan-writing.md #20): type cmd (cmd, expected_exit),
     must_not_exist (file) or must_contain (file, regex); no <…> or {…}
     placeholders. Commands run from the project root. -->

- [ ] AC1: <what is true when this is done, said so it can be checked>
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "bats tests/test-example.bats"
    expected_exit: 0
  ```
