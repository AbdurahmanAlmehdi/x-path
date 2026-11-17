# ADR 0018: A web dashboard on the engine's own origin, with the API under /api/v1

- **Status:** Accepted
- **Date:** 2026-11-14
- **Amends:** the rule that browsers are refused
- **Approved by:** the owner, 2026-11-12 to 2026-11-15 (the [Decisions](#decisions) D1 to D17 below)

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
`xp_session_<port>; HttpOnly; SameSite=Strict; Path=/` on a loopback origin, the port being the one the engine serves on. A cookie authenticates only
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

## Decisions

The detailed decisions behind this ADR. Code comments cite them by number, for example `(D9)` or
`(ADR 0018, D15)`. The people and roles they rely on are ADR 0017's.

| # | Question | Decision |
|---|---|---|
| D1 | URL space | The API moves to `/api/v1`. Root paths stay as **bearer-only** aliases with `Deprecation` and `Sunset` headers, removed in the first major release (2.0) on or after 2027-11-14, as a `feat!` change. Everything else is the SPA. |
| D2 | Live updates | The existing WebSockets, authenticated by the session cookie plus an exact `Origin` match. No ticket, no SSE. |
| D3 | TLS | No TLS in `xpd`. Browser sign-in works only on loopback or through the configured HTTPS public URL. Plain HTTP from another machine gets `403` with the reason. |
| D3a | Cookie attributes | Chosen by the scheme of the origin that is signing in, never by request headers. Through the HTTPS `public_url`: `__Host-xp_session; Secure; HttpOnly; SameSite=Strict; Path=/`. On a loopback origin: `xp_session_<port>; HttpOnly; SameSite=Strict; Path=/`, the port being the one the engine serves on, so two engines on one machine keep separate sessions. Safari still refuses `Secure` cookies on `http://localhost` (WebKit bug 232088), and a loopback cookie never leaves the machine. |
| D4 | Packaging | `npm run build` runs once in CI, and `bundles.sh` copies `dist/` into every `xpd` bundle as `xpd/web/`. |
| D5 | TS coverage | 100% lines for `src/api/**` and every Pinia store, 90% for the rest. This mirrors the repo's 100% client and bloc, 90% glue tiers. |
| D6 | Runner tokens | They belong to no person (`person_id` NULL is allowed only for `kind = 'runner'`). A runner is a machine, so removing a person never breaks a runner. |
| D7 | Upgrade | Migration creates the person `Owner` (admin), who owns every non-runner token. It can be renamed later. |
| D8 | First admin, headless | `xpd person create --name <n> --role admin` prints a sign-in code. `xpd person code <name>` issues a new one. Both write to the database directly, like `xpd token create`. |
| D9 | Mac or CLI owner opening the dashboard | `xp dashboard` and a Settings button in the Mac app ask for a sign-in code for **their own** person and open `<origin>/sign-in#code=…`. A fragment never reaches a server log. They pass that link to `open`/`xdg-open` as a process argument: an **accepted exception** to the rule that no secret goes in process arguments, since the code is single-use, expires in 10 minutes and the browser redeems it within seconds; `xp dashboard --print` avoids it. |
| D10 | Sign-in code | 16 Crockford base32 characters (80 bits), shown as `XXXX-XXXX-XXXX-XXXX`. It lasts 10 minutes and works once. Issuing a code deletes the person's unused codes. Only the SHA-256 is stored, and it is the primary key. 20 failures per connection address (never `X-Forwarded-*`) and 200 in total per 10 minutes, then `429`; behind a same-host proxy every client shares the proxy's address. Unknown, used and expired codes all get the same `401`. It is used up atomically (`UPDATE … WHERE hash = ? AND used_at IS NULL AND expires_at > ?`, then the row count is checked). |
| D11 | Session lifetime | A `web` token expires 8 hours after sign-in, with no sliding renewal. Signing out revokes the token on the server and clears the cookie (`Max-Age=0`). Responses under `/api/v1/session` and `/api/v1/me` are `no-store`. |
| D12 | Revocation while signed in | The role is read with the token on every request, so a role change applies to the next request. Revoking a token, signing out, removing the person or expiry closes the affected sockets with code 4401: a push on revocation, plus a sweep every 60 s for expiry. The next REST call answers `401`, and the SPA goes to `/sign-in?next=<path>`. Every tab holds its own socket, so each tab learns on its own. |
| D13 | People removal | Soft removal (`removed_at`) that revokes all their tokens. Approvals and run origins keep the name. The last active admin cannot be demoted or removed (`409`). |
| D14 | CSRF | Any request authenticated by cookie with a method other than GET/HEAD/OPTIONS needs both of these:<br>- an `Origin` in the D15 set (an absent `Origin` is refused);<br>- the header `X-XPath-CSRF: 1`. `xpd` sends no CORS headers, so a cross-site page cannot add it without a preflight that fails.<br>Together with `SameSite=Strict`, that makes three independent layers. `POST /session` checks `Origin`, which covers login CSRF. A request with `Authorization` is bearer: the cookie is ignored and CSRF does not apply. `xpd` never sends CORS headers. GET never changes anything. |
| D15 | Allowed origins | Exact string matches only:<br>- the configured `public_url` origin;<br>- the loopback origins of the bound port (`http://127.0.0.1:<p>`, `http://localhost:<p>`, `http://[::1]:<p>`), but only when the `Host` header is one of those too, which blocks DNS rebinding.<br>`X-Forwarded-*` is never trusted. |
| D16 | Role-aware UI | `GET /api/v1/me` returns the person and their `permissions` (the four of ADR 0017). The SPA hides actions it may not take and never reimplements the rules. |
| D17 | Tokens per person | Any person lists, creates (`cli`, `mcp`) and revokes their own tokens. Admins see and revoke everyone's. Creating a token needs an interactive token (`app` or `web`). `cli` and `mcp` tokens had no expiry at first; since ADR 0019 (2026-11-16) they expire 90 days after their last use. |
