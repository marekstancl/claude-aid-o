---
sidebar_position: 99
title: "Quality Gates Runner (Removed)"
---

# Quality Gates Runner -- Removed in v2.0.0

This agent was removed in v2.0.0. Quality gates are now executed by `aid-run-gates.sh` (bash script) during the GATES FSM state, not by an LLM agent.

See [Quality Gates Skill](../skills/quality-gates) for the gate configuration and execution reference.
See [Gate Fixer Agent](./gate-fixer) for the agent that fixes gate failures.
