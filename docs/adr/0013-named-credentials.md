# ADR 0013: Named credentials shared across flavors

- **Status:** Accepted
- **Date:** 2026-10-18
- **Phase:** Follow-up to Phase 10c (credentials) and Phase 16b (the credentials editor)
- **Approved by:** the owner, 2026-10-18

## Context

Since Phase 10c a credential was a `credential_ref` row of one flavor: one per flavor and kind,
created with `PUT /projects/{id}/credentials`, with no name. Using it showed three problems:

- The same App Store Connect key had to be added again for every flavor (dev and prod), and again
  for every project of the same team; each copy was checked, stored and replaced on its own.
- A credential had no name, so two Shorebird keys, or the keys of two Apple teams, could not be told
  apart.
- The `xp` CLI could not add a credential at all.

## Decision

**Credentials are the engine's and have names.** A credential (the `credential` table) has an id
(`crd_...`), a name that is unique regardless of case, a kind, its secret (in the secret store
under `credential.<id>`, as before), the `account` it belongs to when that is not secret, and the
result of its own check. Renaming it or giving it a new secret keeps the id and every assignment.

**Flavors point to credentials.** A flavor of any project and app uses at most one credential of
each kind (`credential_assignment`, primary key flavor and kind, foreign key to the credential and
its kind). Deleting a flavor or a credential deletes its assignments.

**Nothing changes silently.** Assigning from a flavor offers "this flavor" or "every flavor of this
app"; a flavor that already has a credential of the kind keeps it unless "replace" is asked for,
and the answer lists those that kept theirs. The flavor the user assigns from always gets the
credential. Deleting a credential that flavors use answers `409 credential_in_use` with the flavors
and needs `force=true`, which unassigns it first. Identical secrets under two names are never
merged.

**Two checks.** The credential is checked on its own (does it authenticate) and each assignment is
checked with the flavor's identifiers (can it reach the flavor's app): an ASC key must see the app
with the flavor's bundle id, a Play service account must read the internal track of the flavor's
package. A kind whose check does not look at the flavor gives each assignment the credential's
status. Assignments are checked when they are made, when the secret is replaced, on request and by
the daily health check. An assignment that its check refuses is kept, with the reason; the
`credentials` guard check fails a job when the credential or its assignment to the job's flavor
was refused, so preflight still stops the release before any build.

**The GitHub token stays one.** It is not a named credential: the engine has one GitHub token
(`/github-token`, `github.token`). Every per-flavor `github` row named that very secret (the
credential endpoints saved a `github` credential under `github.token` since Phase 10c), so the
migration folds them into the engine token by dropping the rows: if there was no engine token
before, the secret they saved is the engine token now; if there was one, it is the same secret.
`xpd` logs how many it dropped. The deprecated `PUT /projects/{id}/credentials` with a `github`
token sets the engine token.

**Slack is like the others.** A `slack` webhook is named and assigned per flavor; a notice of a
project goes to the first webhook a flavor of the project uses and no check refused, as before.

**Who may change them.** Only `app` and `cli` tokens create, rename, replace, verify, delete,
assign and unassign; an `mcp` token reads (`403` otherwise; the MCP server has a read-only
`list_credentials` tool and no tool that changes a credential); a `runner` token reaches none of
these routes (ADR 0011). What a runner may be given is unchanged (D-09, ADR 0012): the keystore
and the Shorebird key of a credential assigned to a flavor of the job's project.

**The API.** `GET/POST /credentials`, `GET/PATCH/PUT/DELETE /credentials/{id}`,
`POST /credentials/{id}/verify`; `GET /projects/{id}/credentials` lists what each flavor uses with
both checks; `PUT/DELETE /projects/{id}/flavors/{flavor}/credentials/{kind}` (`?app=` for an app
below the root, since an app path can hold `/` and `.`) assigns with `allFlavors` and `replace`.
The routes of before stay, deprecated, so this is not a breaking change:
`PUT /projects/{id}/credentials` creates a named credential and its assignment (or gives the new
secret to a credential only that flavor uses), and the project's verify and delete work on the
credentials its flavors use.

**The migration** (schema version 14, with its snapshot golden, ADR 0002) turns every
`credential_ref` row into a credential with the same id, secret key, account and check, named
"<kind> · <project> [<app> ]<flavor>" (cut to 80 characters; a name two rows would share gets the
id after it), and an assignment with the same check, then drops `credential_ref`. Secrets are
neither read nor touched. `Migration.notes` lets a migration say what it did to the data that was
there; `xpd` writes it to stderr.

## Consequences

- One Apple key serves every flavor and project of its team, and is replaced in one place.
- An assignment check costs one more cheap read for the ASC and Play kinds; the daily health check
  does one per assignment.
- After the migration the owner sees one credential per old row, with a generated name: identical
  secrets are merged by hand (rename one, assign it, delete the others).
- Clients of the old per-flavor routes keep working; new clients use the named routes. The old
  routes can go in a later major version of the API.
