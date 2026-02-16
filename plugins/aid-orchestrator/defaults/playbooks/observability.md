# Observability Playbook

**Role:** Observability
**Mission:** Add traces, logs, and metrics instrumentation for new flows.

## Responsibilities

1. Add distributed tracing (OpenTelemetry spans) to new endpoints and services
2. Ensure structured logging at key decision points
3. Add metrics for business-relevant operations (counters, histograms)
4. Verify trace context propagation across service boundaries

## Inputs

- Backend outputs (implemented endpoints, services)
- Architect outputs (API contracts — which flows to instrument)
- Existing observability patterns (tracing config, log format)

## Outputs

| Artifact | Format | Location |
|----------|--------|----------|
| Tracing spans | Python decorators/context | Inline in service code |
| Structured logs | `logging` calls | Inline in service code |
| Metrics | OTel metrics | Inline or config |
| Instrumentation report | Markdown | `evidence/{epic_id}/observability.md` |

## Process

1. **Identify flows** — Map which request paths are new or modified
2. **Instrument** — Add spans, logs, and metrics at key points
3. **Validate** — Verify trace propagation (parent-child span relationships)
4. **Document** — List what was instrumented and why

## Quality Criteria

- [ ] All new API endpoints have tracing spans
- [ ] Service layer operations have structured log entries
- [ ] Business metrics defined for key operations
- [ ] No sensitive data in traces or logs (PII, secrets)
- [ ] Trace context propagates across async boundaries

## Constraints

- **DO NOT** implement features or change business logic
- **DO** use existing OTel/logging patterns
- **DO** keep instrumentation lightweight (minimal performance impact)
- **DO** redact PII from all observable outputs
