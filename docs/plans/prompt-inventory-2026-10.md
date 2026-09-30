# Prompt inventory — what each reviewer receives and which part its findings cite

Generated 2026-09-30 by `aid-prompt-inventory.sh /opt/eco/projects/aid-orchestrator/.aid-o/work/evidence /opt/eco/projects/agents/.aid-o/work/evidence /opt/eco/projects/acta/.aid-o/work/evidence /opt/eco/projects/wan/.aid-o/work/evidence`. Lines per section are the mean over the role's prompts (median total). `repository (outside the prompt)` counts citations of files the reviewer opened itself; `never cited` lists sections no finding of the role ever cited. Rounds before 2.98.0 appended the plan without a  heading, so their plan sections appear under their own names (Goal, Scope, Step N …) and their  citations count towards . This report measures; it recommends nothing.

## cp1

| project | role | prompts | lines (median) | lines by section | findings | citations by section | never cited |
|---|---|---|---|---|---|---|---|
| agents | behaviour_edges | 13 | 1210 | (before the first heading) 8, Deterministic plan check 12, Output 19, Role 19, Rules 24, Severity 7, Standards 7, This is a confirmation round 567, Your role 1, plan.md 995 | 91 | plan.md 228, repository (outside the prompt) 87 | (before the first heading), Deterministic plan check, Output, Role, Rules, Severity, Standards, This is a confirmation round, Your role |
| agents | enforcement_tests | 13 | 1208 | (before the first heading) 8, Deterministic plan check 12, Output 19, Role 17, Rules 24, Severity 7, Standards 7, This is a confirmation round 567, Your role 1, plan.md 995 | 86 | plan.md 250, repository (outside the prompt) 91 | (before the first heading), Deterministic plan check, Output, Role, Rules, Severity, Standards, This is a confirmation round, Your role |
| agents | feasibility_deps | 13 | 1209 | (before the first heading) 8, Deterministic plan check 12, Output 19, Role 20, Rules 24, Severity 7, Standards 7, This is a confirmation round 567, Your role 1, plan.md 995 | 85 | plan.md 179, repository (outside the prompt) 118 | (before the first heading), Deterministic plan check, Output, Role, Rules, Severity, Standards, This is a confirmation round, Your role |
| agents | generalist_a | 13 | 1209 | (before the first heading) 8, Deterministic plan check 12, Output 19, Role 18, Rules 24, Severity 7, Standards 7, This is a confirmation round 567, Your role 1, plan.md 995 | 89 | plan.md 279, repository (outside the prompt) 71 | (before the first heading), Deterministic plan check, Output, Role, Rules, Severity, Standards, This is a confirmation round, Your role |
| agents | generalist_b | 9 | 1165 | (before the first heading) 9, Deterministic plan check 9, Output 20, Role 17, Rules 24, Severity 8, Standards 6, This is a confirmation round 612, Your role 1, plan.md 890 | 45 | plan.md 79, repository (outside the prompt) 57 | (before the first heading), Deterministic plan check, Output, Role, Rules, Severity, Standards, This is a confirmation round, Your role |
| agents | reuse | 13 | 1209 | (before the first heading) 8, Deterministic plan check 12, Output 19, Role 18, Rules 24, Severity 7, Standards 7, This is a confirmation round 567, Your role 1, plan.md 995 | 53 | plan.md 103, repository (outside the prompt) 115 | (before the first heading), Deterministic plan check, Output, Role, Rules, Severity, Standards, This is a confirmation round, Your role |
| aid-orchestrator | behaviour_edges | 27 | 912 | (before the first heading) 62, Approach 10, Architecture 56, Constraints 8, Context 9, Data Model 51, Deterministic plan check 5, Goal 3, Implementation Steps 594, Next Steps 7, Output 19, Resources Verification 9, Risks 11, Role 19, Rules 23, Scope 25, Severity 8, Standards 8, Success Criteria 9, Testing Strategy 22, This is a confirmation round 503, Your role 1, plan.md 580 | 179 | other 2, plan.md 431, repository (outside the prompt) 177 | (before the first heading), Approach, Architecture, Constraints, Context, Data Model, Deterministic plan check, Goal, Implementation Steps, Next Steps, Output, Resources Verification, Risks, Role, Rules, Scope, Severity, Standards, Success Criteria, Testing Strategy, This is a confirmation round, Your role |
| aid-orchestrator | enforcement_tests | 27 | 910 | (before the first heading) 62, Approach 10, Architecture 56, Constraints 8, Context 9, Data Model 51, Deterministic plan check 5, Goal 3, Implementation Steps 594, Next Steps 7, Output 19, Resources Verification 9, Risks 11, Role 17, Rules 23, Scope 25, Severity 8, Standards 8, Success Criteria 9, Testing Strategy 22, This is a confirmation round 503, Your role 1, plan.md 580 | 197 | other 6, plan.md 468, repository (outside the prompt) 262 | (before the first heading), Approach, Architecture, Constraints, Context, Data Model, Deterministic plan check, Goal, Implementation Steps, Next Steps, Output, Resources Verification, Risks, Role, Rules, Scope, Severity, Standards, Success Criteria, Testing Strategy, This is a confirmation round, Your role |
| aid-orchestrator | feasibility_deps | 27 | 911 | (before the first heading) 63, Approach 10, Architecture 56, Constraints 8, Context 9, Data Model 51, Deterministic plan check 5, Goal 3, Implementation Steps 594, Next Steps 7, Output 19, Resources Verification 9, Risks 11, Role 20, Rules 23, Scope 25, Severity 8, Standards 8, Success Criteria 9, Testing Strategy 22, This is a confirmation round 503, Your role 1, plan.md 580 | 208 | other 8, plan.md 377, repository (outside the prompt) 379 | (before the first heading), Approach, Architecture, Constraints, Context, Data Model, Deterministic plan check, Goal, Implementation Steps, Next Steps, Output, Resources Verification, Risks, Role, Rules, Scope, Severity, Standards, Success Criteria, Testing Strategy, This is a confirmation round, Your role |
| aid-orchestrator | generalist_a | 26 | 874.5 | (before the first heading) 48, Approach 10, Architecture 52, Constraints 8, Context 9, Data Model 50, Deterministic plan check 5, Goal 3, Implementation Steps 588, Next Steps 7, Output 19, Resources Verification 9, Risks 11, Role 18, Rules 23, Scope 25, Severity 8, Standards 8, Success Criteria 9, Testing Strategy 21, This is a confirmation round 503, Your role 1, plan.md 580 | 204 | other 9, plan.md 509, repository (outside the prompt) 231 | (before the first heading), Approach, Architecture, Constraints, Context, Data Model, Deterministic plan check, Goal, Implementation Steps, Next Steps, Output, Resources Verification, Risks, Role, Rules, Scope, Severity, Standards, Success Criteria, Testing Strategy, This is a confirmation round, Your role |
| aid-orchestrator | generalist_b | 26 | 873.5 | (before the first heading) 48, Approach 10, Architecture 52, Constraints 8, Context 9, Data Model 50, Deterministic plan check 5, Goal 3, Implementation Steps 588, Next Steps 7, Output 19, Resources Verification 9, Risks 11, Role 17, Rules 23, Scope 25, Severity 8, Standards 8, Success Criteria 9, Testing Strategy 21, This is a confirmation round 503, Your role 1, plan.md 580 | 130 | other 2, plan.md 275, repository (outside the prompt) 147 | (before the first heading), Approach, Architecture, Constraints, Context, Data Model, Deterministic plan check, Goal, Implementation Steps, Next Steps, Output, Resources Verification, Risks, Role, Rules, Scope, Severity, Standards, Success Criteria, Testing Strategy, This is a confirmation round, Your role |
| aid-orchestrator | generalist_b.orig | 1 | 655 | (before the first heading) 8, Deterministic plan check 1, Output 18, Role 17, Rules 24, Severity 6, Standards 8, Your role 1, plan.md 564 | 0 |  | (before the first heading), Deterministic plan check, Output, Role, Rules, Severity, Standards, Your role, plan.md |
| aid-orchestrator | reuse | 26 | 874.5 | (before the first heading) 48, Approach 10, Architecture 52, Constraints 8, Context 9, Data Model 50, Deterministic plan check 5, Goal 3, Implementation Steps 588, Next Steps 7, Output 19, Resources Verification 9, Risks 11, Role 18, Rules 23, Scope 25, Severity 8, Standards 8, Success Criteria 9, Testing Strategy 21, This is a confirmation round 503, Your role 1, plan.md 580 | 137 | other 2, plan.md 258, repository (outside the prompt) 297 | (before the first heading), Approach, Architecture, Constraints, Context, Data Model, Deterministic plan check, Goal, Implementation Steps, Next Steps, Output, Resources Verification, Risks, Role, Rules, Scope, Severity, Standards, Success Criteria, Testing Strategy, This is a confirmation round, Your role |

## cp2

| project | role | prompts | lines (median) | lines by section | findings | citations by section | never cited |
|---|---|---|---|---|---|---|---|
| agents | step_generalist | 55 | 688 | (before the first heading) 9, Acceptance criteria 5, Declared scope 10, Definition of Done 2, Deterministic step check 8, Output 22, Role 19, Rules 24, Severity 9, This is a confirmation round 175, Your role 1, diff.patch 595 | 33 | diff.patch 58, repository (outside the prompt) 20 | (before the first heading), Acceptance criteria, Declared scope, Definition of Done, Deterministic step check, Output, Role, Rules, Severity, This is a confirmation round, Your role |
| agents | step_security | 25 | 975 | (before the first heading) 9, Acceptance criteria 6, Declared scope 11, Definition of Done 2, Deterministic step check 8, Output 22, Role 19, Rules 24, Severity 9, This is a confirmation round 146, Your role 1, diff.patch 859 | 13 | diff.patch 32, repository (outside the prompt) 3 | (before the first heading), Acceptance criteria, Declared scope, Definition of Done, Deterministic step check, Output, Role, Rules, Severity, This is a confirmation round, Your role |
| aid-orchestrator | step_generalist | 45 | 453 | (before the first heading) 8, Acceptance criteria 5, Declared scope 10, Definition of Done 2, Deterministic step check 8, Output 22, Role 19, Rules 24, Severity 7, This is a confirmation round 91, Your role 1, diff.patch 635 | 21 | diff.patch 21, repository (outside the prompt) 15 | (before the first heading), Acceptance criteria, Declared scope, Definition of Done, Deterministic step check, Output, Role, Rules, Severity, This is a confirmation round, Your role |
| aid-orchestrator | step_security | 18 | 883 | (before the first heading) 9, Acceptance criteria 5, Declared scope 12, Definition of Done 2, Deterministic step check 8, Output 22, Role 19, Rules 24, Severity 10, This is a confirmation round 183, Your role 1, diff.patch 787 | 15 | diff.patch 30, repository (outside the prompt) 1 | (before the first heading), Acceptance criteria, Declared scope, Definition of Done, Deterministic step check, Output, Role, Rules, Severity, This is a confirmation round, Your role |

## cp3

| project | role | prompts | lines (median) | lines by section | findings | citations by section | never cited |
|---|---|---|---|---|---|---|---|
| agents | epic_behaviour | 19 | 1236 | (before the first heading) 9, Declared scope 30, Definition of Done 4, Deterministic step check 8, Output 21, Role 17, Rules 24, Severity 9, Step 0 5, Step 1 6, Step 2 5, Step 3 6, Step 4 5, Step 5 5, Step 6 4, This is a confirmation round 496, Your role 1, diff.patch 975 | 13 | diff.patch 37, repository (outside the prompt) 1 | (before the first heading), Declared scope, Definition of Done, Deterministic step check, Output, Role, Rules, Severity, Step 0, Step 1, Step 2, Step 3, Step 4, Step 5, Step 6, This is a confirmation round, Your role |
| agents | epic_generalist | 17 | 1237 | (before the first heading) 9, Declared scope 26, Definition of Done 4, Deterministic step check 8, Output 21, Role 18, Rules 24, Severity 8, Step 0 5, Step 1 5, Step 2 5, Step 3 6, Step 4 5, Step 5 5, Step 6 4, This is a confirmation round 525, Your role 1, diff.patch 975 | 14 | diff.patch 36, repository (outside the prompt) 8 | (before the first heading), Declared scope, Definition of Done, Deterministic step check, Output, Role, Rules, Severity, Step 0, Step 1, Step 2, Step 3, Step 4, Step 5, Step 6, This is a confirmation round, Your role |
| agents | epic_security | 21 | 1241 | (before the first heading) 9, Declared scope 28, Definition of Done 4, Deterministic step check 8, Output 22, Role 18, Rules 24, Severity 9, Step 0 5, Step 1 5, Step 2 5, Step 3 6, Step 4 5, Step 5 5, Step 6 4, This is a confirmation round 445, Your role 1, diff.patch 1093 | 17 | diff.patch 57 | (before the first heading), Declared scope, Definition of Done, Deterministic step check, Output, Role, Rules, Severity, Step 0, Step 1, Step 2, Step 3, Step 4, Step 5, Step 6, This is a confirmation round, Your role |
| aid-orchestrator | epic_behaviour | 18 | 1298.5 | (before the first heading) 9, Declared scope 29, Definition of Done 4, Deterministic step check 8, Output 22, Role 17, Rules 24, Severity 8, Step 0 4, Step 1 4, Step 2 4, Step 3 5, Step 4 6, Step 5 6, Step 6 4, Step 7 5, This is a confirmation round 297, Your role 1, diff.patch 1091 | 16 | diff.patch 23, repository (outside the prompt) 9 | (before the first heading), Declared scope, Definition of Done, Deterministic step check, Output, Role, Rules, Severity, Step 0, Step 1, Step 2, Step 3, Step 4, Step 5, Step 6, Step 7, This is a confirmation round, Your role |
| aid-orchestrator | epic_generalist | 17 | 691 | (before the first heading) 9, Declared scope 29, Definition of Done 4, Deterministic step check 8, Output 22, Role 18, Rules 24, Severity 9, Step 0 4, Step 1 4, Step 2 5, Step 3 5, Step 4 6, Step 5 7, Step 6 4, Step 7 5, This is a confirmation round 285, Your role 1, diff.patch 862 | 11 | diff.patch 28, repository (outside the prompt) 11 | (before the first heading), Declared scope, Definition of Done, Deterministic step check, Output, Role, Rules, Severity, Step 0, Step 1, Step 2, Step 3, Step 4, Step 5, Step 6, Step 7, This is a confirmation round, Your role |
| aid-orchestrator | epic_security | 26 | 1299.5 | (before the first heading) 9, Declared scope 28, Definition of Done 4, Deterministic step check 8, Output 22, Role 18, Rules 24, Severity 8, Step 0 4, Step 1 4, Step 2 4, Step 3 4, Step 4 6, Step 5 6, Step 6 4, Step 7 5, This is a confirmation round 248, Your role 1, diff.patch 1044 | 41 | diff.patch 106, repository (outside the prompt) 17 | (before the first heading), Declared scope, Definition of Done, Deterministic step check, Output, Role, Rules, Severity, Step 0, Step 1, Step 2, Step 3, Step 4, Step 5, Step 6, Step 7, This is a confirmation round, Your role |

## Sections no finding cited in any project

- (before the first heading) (23 role rows)
- Acceptance criteria (4 role rows)
- Approach (6 role rows)
- Architecture (6 role rows)
- Constraints (6 role rows)
- Context (6 role rows)
- Data Model (6 role rows)
- Declared scope (10 role rows)
- Definition of Done (10 role rows)
- Deterministic plan check (13 role rows)
- Deterministic step check (10 role rows)
- Goal (6 role rows)
- Implementation Steps (6 role rows)
- Next Steps (6 role rows)
- Output (23 role rows)
- Resources Verification (6 role rows)
- Risks (6 role rows)
- Role (23 role rows)
- Rules (23 role rows)
- Scope (6 role rows)
- Severity (23 role rows)
- Standards (13 role rows)
- Step 0 (6 role rows)
- Step 1 (6 role rows)
- Step 2 (6 role rows)
- Step 3 (6 role rows)
- Step 4 (6 role rows)
- Step 5 (6 role rows)
- Step 6 (6 role rows)
- Step 7 (3 role rows)
- Success Criteria (6 role rows)
- Testing Strategy (6 role rows)
- This is a confirmation round (22 role rows)
- Your role (23 role rows)
- plan.md (1 role rows)
