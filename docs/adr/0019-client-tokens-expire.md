# ADR 0019: Tokens of `xp` and `xp mcp` expire after 90 days without use

- **Status:** Accepted
- **Date:** 2026-11-16
- **Phase:** Follow-up to [D17 of ADR 0018](0018-web-dashboard.md#decisions)
- **Approved by:** the owner, 2026-11-16

## Context

Since ADR 0017 every person can make `cli` and `mcp` tokens from the app or the web dashboard
(D17), and an admin can make them with `xpd token create`. Until now these tokens worked until
someone revoked them. A token left on an old laptop, in a shell history or in an agent's config
kept working for good. Only `web` tokens expired (8 hours, D11, ADR 0018), through
`device_token.expires_at` (migration v25). D17 left an expiry for the other person tokens as a
follow-up.

`xp` cannot sign in on its own: it has no browser flow, so a token comes from a person in the app,
the web dashboard or `xpd token create`, and `xp connect` saves it. A rule that makes people make
new tokens often would be a burden. A token that nobody uses is the one that should stop working.

## Decision

**Sliding expiry.** A `cli` or `mcp` token expires 90 days after it was last used
(`TokenService.clientTokenLifetime`). `TokenService.issue` gives it `expires_at` 90 days after it
is issued. Each request it authenticates moves `expires_at` to 90 days after that request. The
engine writes the new expiry only when it moves by a day or more
(`clientTokenRenewalStep`), so a busy client causes about one write a day, not one per request.
So `xp` and `xp mcp` keep working while someone uses them, and a forgotten token stops. `xp` has
nothing to renew and no new secret to save. `mcp` tokens follow the same rule: an agent's config is
as easy to forget as a laptop.

`app` and `runner` tokens still work until revoked. The Mac app holds its `app` token in the
Keychain and makes a new one when the engine refuses the old one. A runner's token is revoked with
the runner. `web` tokens keep their fixed 8 hours with no sliding renewal (D11).

**Existing tokens.** Migration v26 rebuilds `device_token`, because SQLite cannot change a CHECK.
`expires_at` is then allowed for `cli`, `mcp` and `web`. Each valid `cli` and `mcp` token gets an
expiry 90 days after the upgrade. A client in use renews it, and nothing breaks on the day of the
upgrade.

**Saying so.** A request with an expired token gets `401 unauthorized`, with `details.reason`
`token_expired` and `details.expiredAt`. An unknown or revoked token still gets the plain `401`.
The token's holder has the secret, so telling them that it expired gives nothing away. `xp` adds
how to make a new token and `xp connect` it. `xp mcp` says the same in its tool error. `TokenInfo`
(`GET /tokens`, `POST /tokens`, `GET /status`) carries `expiresAt`, and `xp status` prints it.

**Housekeeping.** The daily housekeeping (`TokenService.purgeEndedTokens`) deletes `web` tokens one
day after they ended, as before. It deletes `cli` and `mcp` tokens 30 days after they expired or
were revoked (`endedClientTokenGrace`). Until then, a client that comes back after a long break
learns that its token expired, not that the token is unknown.

## Consequences

- A token that no client uses for 90 days stops working on its own. To use the client again, the
  person makes a new token and runs `xp connect` again.
- An open event or log socket closes with code 4401 when the token's expiry, as it was when the
  socket opened, passes (the 60-second sweep of D12). Only a socket that stays open for 90 days with
  no other request from that token can meet this. The client reconnects, and that request renews the
  token.
- Expiry is checked against the engine's clock. Each request now reads the token and writes it at
  most once a day.
- The lifetime, step and grace are constants in `TokenService`, not settings. Making them settings
  is a separate decision.
