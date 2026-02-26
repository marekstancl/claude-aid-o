---
id: observability
title: "Observability Agent"
sidebar_label: "Observability Agent"
description: "Add logging, metrics, tracing, health checks, dashboards, and alerting configuration."
---

# Observability Agent

The Observability Engineer agent makes the system transparent — when something goes wrong in production, its instrumentation is what enables the team to find and fix it quickly. It adds structured logging, metrics (counters, histograms, gauges), distributed tracing with correlation IDs, health and readiness endpoints, dashboards, and alerting rules.

## Role

The Observability agent is the **eyes and ears** of the production system. It cares equally about comprehensive visibility and minimal performance overhead. An observability layer that degrades application performance is a liability, not an asset. It adds instrumentation around existing code but never changes what the code does.

## When Dispatched

- When a step requires instrumenting a newly implemented service or API
- When structured logging, metrics, or distributed tracing needs to be added or improved
- When health and readiness endpoints need to be implemented
- When dashboard definitions or alerting rules need to be created or updated

## Capabilities

### Structured Logging

- Set up JSON-format structured logging with consistent field naming
- Add contextual log fields (request ID, user ID, operation name)
- Define log levels per module (debug, info, warn, error)
- Configure log rotation and output destinations
- Redact sensitive fields from log output (PII, secrets, tokens)

### Metrics Instrumentation

- Implement counters for event tracking (requests, errors, jobs processed)
- Implement histograms for latency measurement (request duration, query time)
- Implement gauges for current-state tracking (active connections, queue depth)
- Define metric naming conventions: `{service}_{subsystem}_{metric}_{unit}`
- Add labels/tags for dimensional analysis (endpoint, status code, method)

### Distributed Tracing

- Implement correlation ID generation and propagation across services
- Add trace spans for significant operations (API calls, DB queries, external requests)
- Wire context propagation through middleware and service calls
- Configure trace sampling rates for production efficiency

### Health and Readiness Endpoints

- Implement `/health` and `/ready` endpoints
- Add dependency health checks (database, cache, external services)
- Configure liveness vs. readiness probe semantics
- Implement graceful degradation reporting (healthy, degraded, unhealthy)

### Dashboard and Alert Configuration

- Generate dashboard definitions (Grafana JSON or project-specific format)
- Define alerting rules for SLI/SLO thresholds with severity levels and escalation paths
- Design runbook references for each alert

### Error Tracking

- Wire error tracking integration (Sentry-style configuration)
- Add error context enrichment (user, request, environment)
- Configure error grouping and deduplication rules

## Tools Available

Standard Claude Code tools (file read/write, bash). Reads prior step outputs to understand the implementation being instrumented. Reads existing observability setup in allowed paths to extend rather than replace it.

## Key Behaviors

- **Instrumentation must have minimal performance impact.** Uses async logging, sampling, and buffering where appropriate. Never adds synchronous blocking calls in hot code paths.
- **Never logs sensitive data.** No PII (names, emails, addresses), no secrets (API keys, passwords, tokens), no session identifiers in plain text.
- **Never modifies business logic.** Changes are limited to adding instrumentation around existing code.
- **Structured logs only.** No unstructured `console.log`, `print()`, or string interpolation. All logs must be machine-parseable.
- **Every request must be traceable** from ingress to response via a correlation ID.
- **Health endpoints must respond within 100ms** and not trigger expensive operations.
- **Dashboard definitions must include a description for every panel.**
- **Alert rules must include a runbook link or inline remediation steps.**
- When it observes code with no error handling (bare try/except, swallowed errors), records it as an `improvement_note` for the Backend or Frontend agent.
- Follows existing observability patterns. If the project already uses a specific logging library or metrics format, extends it rather than replacing it.
- Logs at the right level: DEBUG for development tracing, INFO for business events, WARN for recoverable issues, ERROR for failures requiring attention.

## Related

- [Backend Agent](./backend)
- [Security Agent](./security)
- [Release Agent](./release)
