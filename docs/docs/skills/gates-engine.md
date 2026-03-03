---
sidebar_position: 99
title: "Gates Engine (Removed)"
---

# Gates Engine -- Removed in v2.0.0

This skill was consolidated into [Quality Gates](./quality-gates) and [Pipeline](./pipeline) in v2.0.0.

Gate execution is now handled by `aid-run-gates.sh` (bash script). Configuration lives in `execution.yaml`. The Pipeline skill's GATES state section defines FSM transitions on gate pass/fail.
