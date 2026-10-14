# ADR 0011: Runner tokens are scoped to the runner endpoints

- **Status:** Accepted
- **Date:** 2026-10-14
- **Phase:** Follow-up to Phase 14a, decides Phase 14b (refines D-06 and D-13)
- **Approved by:** the owner, 2026-10-14

## Context

Phase 14a gave a `runner` device token the same reads an `mcp` token has, and only kept it from
approving and from changing gates (D-13). A runner receives signing material for the jobs it
leases (D-09, ADR 0012), and it is the machine the engine trusts least. A stolen runner
credential should not show the owner's projects, jobs, credentials, releases and approvals.

## Decision

A token of kind `runner` reaches the runner endpoints and nothing else:

- `GET /runners/connect` (the WebSocket the runner dials out on), and
- `PUT /runners/jobs/{id}/artifacts/{name}` (the upload of an artifact of a job it holds).

Everything else the runner protocol needs travels over that socket. `GET /health` and
`GET /version` need no token, and `POST /runners/pair` is the pairing token's. Every other route
answers a runner token `403 forbidden` with a message that names the route and what the token may
reach. The check is one middleware in front of the router (`runnerScopeMiddleware`), so a route
added later is closed to runner tokens until someone opens it on purpose.

## Consequences

- The reads that were open to every kind of token (`GET /runners`, `/approvals`, `/storage`,
  `/releases/{id}`, `/releases/{id}/notes`, the gates, the dry run of `POST /storage/free`) now
  answer `app`, `cli` and `mcp` tokens only. The tests and the README that said every kind of
  token can read them were updated.
- The runner agent keeps working with nothing but its credential: it never lists runners or reads
  a job.
- `openapi.yaml` states the scope once, in its description, and the contract tests of the runner
  endpoints still pass.
