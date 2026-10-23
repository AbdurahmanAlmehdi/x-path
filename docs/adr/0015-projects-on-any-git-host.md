# ADR 0015: Projects on any git host

- **Status:** Accepted
- **Date:** 2026-10-23
- **Phase:** Follow-up to D-05 and ADR 0009, decides R10a–R10d of the
  [runner onboarding plan](../plan/2026-10-22-feat-remote-runner-onboarding-part-2-plan.md)
- **Approved by:** the owner, 2026-10-23 (Q3, Q5 and Q6 of the plan, the recommended options)

## Context

GitHub is assumed in every layer. `ProjectService.add` accepts only an origin that
`GitHubRemote.parse` reads; `project.github_repo_id INTEGER NOT NULL UNIQUE` keys the project, the
engine mirror (`mirrors/<id>.git`, D-05), the runner cache (ADR 0009), the lease protocol,
housekeeping and `ReleaseWorktree`; and the engine authenticates git only through a
`https://github.com` credential helper. The 1.0 plan lists "GitLab or Bitbucket" as a non-goal.

Teams on Bitbucket, on a self-hosted SSH server or with a local bare repository cannot add their
project at all, although `dev-build` and `test` need nothing from GitHub: they check out a commit,
build and upload to the stores.

## Decision

**A project has a host and a source key.** `host` is `github.com`, `bitbucket.org`, any SSH host,
or `local` for a `file://` origin. `source_key` is a stored opaque string that keys the engine
mirror, the runner cache and the worktrees.

- For GitHub the key is the repository id in decimal, so existing `mirrors/<id>.git` folders stay
  where they are and follow renames as before.
- For other hosts it is `h` plus 16 hex digits of the SHA-256 of the normalised remote URL, fixed
  when the project is added.
- `github_repo_id` becomes nullable; it is present only for GitHub projects. The `project` table
  is rebuilt with SQLite's 12-step procedure in a migration that runs with foreign keys off (Q5);
  the migration runner checks `PRAGMA foreign_key_check` before it commits. Negative synthetic
  GitHub ids were rejected: a fake id would reach the API and step inputs.

**Other hosts are added by SSH or `file://`.**

- An SSH URL (scp-like `git@host:path` or `ssh://`) or a `file://` URL is accepted as it is.
- Bitbucket clones are usually HTTPS. For an HTTPS origin that is not GitHub, XPath derives the
  SSH URL (`https://bitbucket.org/ws/repo.git` → `git@bitbucket.org:ws/repo.git`) and asks the
  owner to confirm it; the owner's clone is not changed. Without confirmation it refuses with
  "XPath has no credentials for <host> over HTTPS; use the SSH URL".
- **Normalisation.** The scp-like, `ssh://` and derived forms of one repository give the same
  `source_key`: the host is lower-cased, the default port and the user are dropped, and a trailing
  `.git` and `/` are removed. So one repository cannot be added twice.
- The repository's `owner/name` is its URL path; more than two segments are kept (GitLab
  subgroups).

**The engine fetches with its own SSH key.** Every git command XPath runs against a non-GitHub
remote uses

```text
GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=30 -o StrictHostKeyChecking=accept-new'
```

as the runner does (Q6). The first connection records the host key; a changed key still fails.
There is no interactive `ssh -T` step, which is awkward under a LaunchAgent or in Docker. An
explicit `xp runner trust-host` was rejected as one more thing to do. The engine machine needs a
key that can read the repository without a passphrase prompt (the LaunchAgent has no terminal).
Adding a project proves access with `git ls-remote --symref <url> HEAD`, which also reads the
default branch; when it fails, the error names the public key the engine used
(`~/.ssh/id_ed25519.pub` of the engine's user) and where to add it as an access key.

**Only workflows that need no GitHub run on other hosts (Q3).** A workflow with a `github.*` or
`git.push` step is refused at dispatch on a non-GitHub project, with an error that names the host,
the step and the workarounds: `dev-build`, `test`, or a private GitHub mirror. The engine can push
only with the GitHub token. Allowing `git.push` and `git.tag` over the engine's SSH key was
rejected for now: `prod-release` would still stop at `github.createPr`.

## Consequences

- D-05 now reads "keyed by the project's source key" and ADR 0009's runner cache and lease carry a
  `cacheKey`; for GitHub projects nothing moves on disk.
- "GitLab or Bitbucket" is no longer a 1.0 non-goal. Pull requests, merges and tags on other hosts
  remain later work, as do HTTPS credentials for hosts other than GitHub.
- An app one minor version behind cannot read a project without `githubRepoId`; the install
  guide's version section says so.
- The engine host needs `ssh` and a readable key for every non-GitHub project; the UX plan's
  `xp doctor` shows the same check.
