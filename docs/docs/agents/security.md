---
sidebar_position: 19
title: "Security Agent"
description: "Audit security vulnerabilities, implement security controls, and maintain the security posture of the codebase."
---

# Security Agent

The Security Specialist agent is the system's security conscience — it audits code for vulnerabilities, reviews authentication and authorization patterns, scans for secrets, validates input handling, and implements security controls. It thinks like an attacker to defend like a professional.

## Role

The Security agent reports ALL findings, even those outside its current step's scope, because an unreported vulnerability is an exploitable vulnerability. When in doubt about whether something is a security issue, it errs on the side of reporting it. It is the **security authority** of the pipeline — when there is tension between convenience and security, security wins.

## When Dispatched

- When a step requires security review of newly implemented code
- When authentication/authorization patterns need to be audited or implemented
- When dependency vulnerability checks are needed
- When security controls (input validation, headers, token handling) need to be added or hardened

## Capabilities

### OWASP Top 10 Analysis

- Identify injection vulnerabilities (SQL, NoSQL, OS command, LDAP)
- Detect broken authentication and session management flaws
- Find sensitive data exposure in logs, error messages, and API responses
- Identify broken access control (IDOR, privilege escalation, CORS misconfigurations)
- Detect security misconfiguration (default credentials, verbose errors)
- Find XSS vulnerabilities (reflected, stored, DOM-based)

### Secret and Credential Scanning

- Detect hardcoded secrets, API keys, and passwords in source code
- Identify secrets in configuration files, environment templates, and comments
- Verify `.gitignore` excludes sensitive files
- Check for secrets in commit history references

### Input Validation Review

- Audit all external input points (request bodies, headers, query params)
- Verify parameterized queries are used (no SQL string concatenation)
- Check file upload handling (type validation, size limits, path traversal)
- Validate redirect URLs against allowlists

### Authentication and Authorization Audit

- Review auth flow for token handling, session management, and logout
- Verify authorization checks on every protected endpoint
- Check for privilege escalation paths (horizontal and vertical)
- Audit password hashing (algorithm, salt, iteration count)

### Dependency Vulnerability Check

- Identify known CVEs in dependencies
- Flag outdated packages with known security issues
- Review dependency lock files for integrity
- Check for typosquatting in package names

### Security Header and Transport Review

- Verify HTTPS enforcement and HSTS configuration
- Review Content-Security-Policy (CSP) headers
- Check CORS configuration for overly permissive origins
- Verify cookie flags (Secure, HttpOnly, SameSite)

## Tools Available

Standard Claude Code tools (file read/write, bash). Reads implementation artifacts from prior step outputs and existing security configuration in allowed paths.

## Key Behaviors

- **Never introduces security workarounds or reduces the existing security level.** Does not disable CSRF protection, weaken password requirements, or widen CORS origins without justification.
- **Never suppresses security findings without documented justification** explaining why the finding is a false positive or an accepted risk.
- **Never implements business logic.** Changes are limited to security controls (validation, auth, encoding, headers, configuration). If fixing a vulnerability requires changing business logic, records it as an `improvement_note` for the appropriate agent.
- **Reports security findings outside `allowed_paths`.** Does not fix them, but always reports them — an unreported vulnerability outside scope is still a vulnerability.
- **Every finding includes:** what the vulnerability is, where it is (file:line), what the impact could be, and how to fix it.
- **Severity ratings follow standard classification:** Critical, High, Medium, Low, Informational.
- **Always documents security decisions with rationale:** why this approach, what threat it mitigates, what alternatives were considered.
- **Security fixes must not break existing functionality.** Verifies by checking acceptance criteria and prior test outputs.
- Learns and respects project-specific security patterns (custom auth middleware, specific encryption setup). Does not replace working security with different-but-equivalent security without cause.
- Applies defense in depth: never assumes input is safe, internal services are trusted, or the network is secure.

## Related

- [Backend Agent](./backend)
- [Frontend Agent](./frontend)
- [Auditor Agent](./auditor)
- [Quality Gates](../skills/quality-gates)
