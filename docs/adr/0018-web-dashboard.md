# ADR 0018: A web dashboard on the engine's own origin, with the API under /api/v1

- **Status:** Accepted
- **Date:** 2026-11-14
- **Phase:** Phase 3 of the web dashboard plan (amends the rule that browsers are refused)
- **Approved by:** the owner, 2026-11-12 and 2026-11-13 (the Decisions D1 to D17 of the web dashboard plan)

## Context

The only GUI of XPath is the macOS app, so an engine on Linux (the bundle or the Docker image) can be
driven only with `xp` and `xp mcp`. The web dashboard gives those teams a GUI that `xpd` serves
itself. Until now the engine refused browsers on purpose: every WebSocket has
`allowedOrigins: const []`, the only credential is a bearer token, and `xpd` serves no files. The API
lives at the root (`/projects`, `/events`, ...), which leaves no room for the pages of an app on the
same origin.

## Decision

**Same origin.** `xpd` serves the dashboard (a Vue app, `apps/xp_web`) and the API on one origin. It
sends no CORS headers, so no other site can call the API from a browser.

**The API under `/api/v1`.** Every route moves under `/api/v1`, and the rest of the URL space belongs
to the dashboard. `xpd` dispatches a request in this order:

1. A path under `/api/v1` is the API. A path no route has gets the JSON `404`, never a page.
2. A root path is the API if and only if the request carries `Authorization`, or the path is public
   (`/health`, `/version`, `/runners/pair`). These root paths are deprecated aliases for the clients
   made before the move: an old `xp`, an old Mac app, a runner bundle that pairs and connects through
   `/runners/pair` and `/runners/connect`. An answer to one carries `Deprecation: true`, a `Sunset`
   date (2027-11-14) and `Link: </api/v1/...>; rel="successor-version"`. The aliases are removed in
   the first major release (2.0) on or after that date, as a `feat!` change.
3. Everything else is the dashboard (until it is built, a JSON `404`).

Every answer to a root path carries `Vary: Authorization`, since that header alone decides whether
it is the API. A `Location` the API answers under `/api/v1` is under `/api/v1` too. `openapi.yaml`
names `…/api/v1` as its server.

`xp_client` asks `GET /api/v1/version` once, without a token, before its first request. An engine
that answers `200` serves the API under `/api/v1`; one that answers `401` or `404` is older and
serves it at the root. Any other answer, or none, is not remembered. A Homebrew or tarball `xp` can
be newer than a remote engine, and nothing makes their versions match, so the probe stays.
`xp_repositories`, the Mac app and the runner use `xp_client`, so they follow.

**Browser sessions.** A browser signs in with a one-time code that an admin issues (or that `xp` and
the Mac app ask for their own person), and gets a `web` token that lasts 8 hours in a cookie:
`__Host-xp_session; Secure; HttpOnly; SameSite=Strict; Path=/` through the HTTPS public URL, and
`xp_session; HttpOnly; SameSite=Strict; Path=/` on a loopback origin. A cookie authenticates only
`web` tokens and only under `/api/v1`; `Authorization` wins when both are sent. `xpd` has no TLS:
sign-in works on loopback or through the configured HTTPS public URL.

**Opening the dashboard signed in** (D9). `xp dashboard` and the Mac app's Open dashboard ask for a
sign-in code for their own person and open `<origin>/sign-in#code=<code>`. They hand that link to
`open` (macOS) or `xdg-open` (Linux) as a process argument, which bends the rule that no secret goes
in process arguments. The owner accepted this exception (2026-11-15): the code works once, expires
in 10 minutes, and the browser redeems it within seconds, so a reader of the process list has
little to take. `xp dashboard --print` prints the link instead and passes no argument.

**CSRF.** A request authenticated by the cookie with a method other than `GET`, `HEAD` or `OPTIONS`
needs an `Origin` from the allowed set and the header `X-XPath-CSRF: 1`. The allowed origins are exact
strings: the public URL's origin, and the loopback origins of the bound port when `Host` is one of
them too (against DNS rebinding). `X-Forwarded-*` is never trusted.

**Sockets.** `/api/v1/events` and `/api/v1/jobs/{id}/logs` accept the cookie with an exact `Origin`
match, and close with code 4401 when their token is revoked or expires. `/runners/connect` stays
closed to browsers.

**Packaging.** CI builds the dashboard once, and every `xpd` bundle, the Docker image and the Mac
app's engine carry it as `web/` next to the engine.

## Consequences

- **Amends the rule that browsers are refused**: a browser reaches the engine on its own origin, with
  a cookie, CSRF checks and an exact `Origin` match. Every other origin is still refused.
- Bearer clients keep working at the root paths until 2.0. Removing the aliases is a breaking
  change (`feat!`), released no earlier than the `Sunset` date. A request to a root
  path without `Authorization` (other than the public ones) is no longer the API: it gets `404`
  instead of `401`.
- `xp dashboard` and the Mac app put a one-time sign-in code in the argument of `open` or `xdg-open`
  for a moment: an accepted exception to the rule that no secret goes in process arguments (see
  "Opening the dashboard signed in").
- Phase 3 of the plan builds the URL space, the aliases and the client probe. Sessions, CSRF and
  the cookie on sockets come in Phase 4, and serving and packaging the dashboard in Phase 5.
