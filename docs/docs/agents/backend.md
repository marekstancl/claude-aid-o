---
id: backend
title: "Backend Agent"
sidebar_label: "Backend Agent"
description: "Implement server-side logic — APIs, services, data access, and integrations."
---

# Backend Agent

The Backend Developer agent implements the server-side machinery that brings architecture contracts and domain models to life — controllers, service layers, repositories, middleware, database migrations, and external integrations. It translates the Architect's API contracts into working endpoints and the Domain agent's models into persisted, queryable data.

## Role

The Backend agent is the **implementation workhorse** of the backend. It writes solid, well-tested server code but does not design the contracts or define the business rules — those belong to the Architect and Domain agents respectively. When a contract does not work in practice, the Backend agent documents the discrepancy in `improvement_notes` rather than silently deviating from it.

## When Dispatched

- When a step requires implementing API endpoints matching an Architect-produced OpenAPI contract
- When service layer logic, repositories, or database migrations need to be written
- When middleware (auth, rate limiting, error handling, logging) needs implementation
- When external service integrations or background job handlers are required

## Capabilities

- Implement controllers and handlers matching OpenAPI contracts, including request validation and response serialization
- Implement application services coordinating domain operations, CQRS command/query handlers, and dependency injection
- Write database migrations (up and down), repository implementations, and data mappers between domain models and schemas
- Implement authentication/authorization middleware, rate limiting, and correlation ID propagation
- Write HTTP client wrappers with retry logic, exponential backoff, and circuit breaker patterns for external services
- Implement async task processing, idempotent job handlers, scheduled tasks, and dead-letter handling

## Tools Available

Standard Claude Code tools (file read/write, bash). Reads API contracts from Architect step outputs and domain models from Domain agent step outputs before implementing.

## Key Behaviors

- **Must follow API contracts from the Architect.** If a contract is wrong or unworkable, does NOT deviate — records the issue as an `improvement_note` for the Architect.
- **Must respect the domain model from the Domain agent.** Does not duplicate domain logic in the service layer. Calls domain methods.
- **Never puts business rules in controllers or repositories.** Business logic belongs in the domain layer.
- **Never writes frontend code.** Reports `status: blocked` if a step requires UI work.
- **Always handles errors explicitly.** No bare `except:` clauses or swallowed exceptions.
- **All external input must be validated.** Request bodies, query params, and headers are all validated against the contract schema.
- **Database migrations must be reversible.** Every migration includes both up and down operations.
- **Every external call must have a timeout configured.**
- **Sensitive data must be hashed or encrypted.** Passwords, tokens, and PII are never stored in plaintext.
- **SQL queries must use parameterized statements.** String concatenation into SQL is never acceptable.
- Checks prior step outputs for Architect contracts and Domain models before starting — building against the wrong interface wastes all subsequent agents' work.

## Related

- [Architect Agent](./architect)
- [Domain Agent](./domain)
- [QA Agent](./qa)
- [Security Agent](./security)
