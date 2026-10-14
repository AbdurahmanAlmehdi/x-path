# ADR 0009: Runner source access

- **Status:** Accepted
- **Date:** 2026-10-14
- **Phase:** Follow-up to Phase 14a, decides Phase 14b (refines D-05 for remote runners)
- **Approved by:** the owner, 2026-10-14

## Context

D-05 says the engine keeps its own bare mirror per repository and cuts a fresh worktree from it
for every job. A job that runs on a remote runner (D-08) cannot use the engine's mirror: the
runner is another machine. Sending it the source through the engine (a bundle over the socket, or
a download) would make the engine a file server for source code, and handing it a GitHub token
would break D-07: the GitHub token never leaves the engine.

## Decision

A remote runner gets the source of a job with its own SSH access to GitHub. The SSH key is one
on the runner machine: a deploy key of the repository, or the key of a user who can read it.

- **The offer names the source and nothing else.** The `lease_offer` carries `repository` (the
  SSH URL of the repository and its GitHub repository id) and `sha`, the exact commit. It never
  carries a credential. `sha` is the dispatched commit, or, for a job that starts from the
  version commit of an earlier job of its run (`commitFrom`), that commit.
- **The runner keeps its own bare cache per repository, keyed by the GitHub repository id**
  (`<data dir>/source/mirrors/<id>.git`), as the engine does.
- **The runner fetches the exact commit over SSH.** `git fetch origin <sha>` runs with
  `GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=30'`, so SSH never asks for a
  password, passphrase or host-key confirmation. The runner's `git` ignores the global and system
  git configuration, as the engine's does.
- **Every job gets a fresh worktree at that commit**, cut from the cache. The runner verifies
  that `HEAD` is the commit before the job runs anything. A worktree that is not the commit the
  engine named is a failed job, never a job on other source.
- **Any access failure fails the job with a clear fix.** A key that cannot read the repository:
  "add this runner's SSH key as a deploy key on `<owner/repo>`". A host key SSH does not trust
  yet: run `ssh -T git@github.com` once as the user of the runner and accept the key. A commit
  GitHub does not have (it was never pushed): push it.
- **The step is `git.checkout` as before.** On a runner it is a different implementation of the
  same step kind (`RemoteCheckoutStep`); the engine-side `git.checkout` stays as it is for local
  jobs. This contrasts with D-05 only for remote runners.
- **Test hook.** `XP_RUNNER_TEST_SOURCE_URL` replaces the URL of every lease. The end-to-end test
  (`tool/e2e/runner_loss_e2e.sh`) uses it to fetch from a local bare repository. A real runner
  never sets it.

## Consequences

- The runner machine needs `git`, `ssh` and read access to every repository it builds. The
  engine needs nothing from the runner side.
- The engine's `project.remote` must be reachable by the SSH URL it derives
  (`git@github.com:owner/name.git`). A remote that is not on GitHub is sent as it is, without any
  user information in the URL.
- A commit that exists only in the engine's mirror cannot reach a runner. The built-in
  `prod-release` pushes the release branch right after it cuts it, so that the build jobs can be
  leased (ADR 0010).
- `git worktree` on the runner means the runner's cache holds a ref `refs/xpath/<sha>` per
  fetched commit, so a cleanup of the cache keeps what a job needs.
