# ADR 0017: People and roles decide who may do what

- **Status:** Accepted
- **Date:** 2026-11-13
- **Phase:** Phase 1 of the web dashboard plan (amends the 1.0 non-goal on multi-user accounts and D-13)
- **Approved by:** the owner, 2026-11-13 (the decisions of the web dashboard plan, kept in
  [ADR 0018](0018-web-dashboard.md#decisions))

## Context

Until now a device token was the only identity: it had a kind (`app`, `cli`, `mcp`, `runner`) and
a name. Each service decided who may act by the kind alone, so any `cli` token could approve a
production release, and an approval recorded a device ("Mac mini"), not a person. The web dashboard
and the CI triggers that follow need to tell people apart and give them different rights. The 1.0
plan listed multi-user accounts and roles as a non-goal, and D-13 said that only the app and `xp`
decide approvals.

## Decision

**People.** A person has a name and a role: `viewer` < `developer` < `releaser` < `admin`. Every
device token belongs to a person, except a runner token, which belongs to no one (a runner is a
machine, so removing a person never breaks a runner). Migration v23 makes the admin `Owner`, on an
upgraded database and on a new one, and gives Owner every token there is but runners'.
`xpd token create` issues for the admin who has been one the longest. Two active people never share
a name, ignoring case.

**One policy.** `AccessPolicy` in `xp_engine` (`access/`) is the one place that reads a token's kind
and role. Each mutating action needs a permission, and each permission a minimum role:

| Permission | Min role | What |
|---|---|---|
| `develop` | developer | dispatch, run again, cancel, resume, adding and editing projects, scan, tests, workflows, pins, the gated release requests (store refresh, new build, merge, rollout, patch moves) |
| `decideApproval` | releaser | approve or deny a gate |
| `release` | releaser | abandoning a release, release texts, store status, turning a gate on |
| `administer` | admin | turning a gate off, removing projects, credentials, certificates, the GitHub token, runners, storage, the public URL, people, others' tokens |

Adding and editing a project and the gated release requests need only `develop`, so an agent
keeps doing what it does today; a gated request still waits for a releaser's approval.

The kind rules apply on top of the role:

- a `runner` token has no permission (its routes stay scoped by ADR 0011);
- an `mcp` token may `develop` and nothing else, so an agent never decides or changes gates;
- only `app` and `web` tokens turn gates off or make tokens.

Every role reads what a token can read today. The role is read with the token on every request,
so a change applies to the next one. The approval, release, housekeeping, runner, GitHub token and
credential services ask the policy instead of checking kinds; their own `…ForbiddenException`
still becomes `403`.

**Approvals** record the person who decided (`decidedBy.personId`, `decidedBy.personName`) next to
the token. Approvals decided before v23 have no person.

**Removal** is soft (`removed_at`): the person's tokens are revoked, a token of a removed person no
longer authenticates, and approvals keep the name. The last active admin cannot be demoted or
removed (`PersonConflictException`, `409` once the routes exist).

## Consequences

- **Amends the 1.0 non-goal** "multi-user accounts and roles": XPath now has people and roles,
  still on one self-hosted engine with no hosted accounts.
- **Amends D-13's kind rule**: a decision is no longer the app's or `xp`'s by kind. It needs the
  releaser role, with an `app`, `cli` or `web` token. `mcp` and `runner` tokens still never decide
  or change gates, and turning a gate off still needs an interactive token (`app`, and now `web`).
- What the owner could do before is unchanged: Owner is an admin, and every token they had keeps
  its kind. A viewer's `cli` token now gets `403` on approve.
- `device_token` and `approval` were rebuilt (SQLite cannot change a CHECK) to take `web` tokens,
  the person of a token and the person who decided.
- The routes for people, `/me` and the permission middleware come in the next phase; this ADR
  covers the model and the policy they use.
