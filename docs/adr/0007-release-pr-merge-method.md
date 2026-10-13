# ADR 0007: Release PR merge method

- **Status:** Accepted
- **Date:** 2026-10-13
- **Phase:** Follow-up to Phase 5, decides Phase 12b
- **Approved by:** the owner, 2026-10-13

## Context

A release runs on a `release/*` branch: version commits and the release tag are made there
(D-04, D-17). The release PR is merged once both stores are live. Squash and rebase merges
create new commits on the base branch, so the tag and the version commits on the release
branch stop being reachable from the base branch, and `git describe` and the tag history of
the base lose the release.

## Decision

Release PRs are merged with a merge commit (`GitHubMergeMethod.merge`, the default of
`GitHubClient.mergePullRequest`). The release commits and their tags stay reachable from the
base branch, and the tag matches the SHA that shipped.

`GitHubMergeMethod.squash` and `GitHubMergeMethod.rebase` stay available in the client
interface, but release PRs do not use them. The merge is a gated action (D-13).

## Consequences

- The release flow of Phase 12b calls `mergePullRequest` without a method argument, and its
  test asserts that the method sent to GitHub is `merge`.
- A project whose base branch forbids merge commits cannot merge its release PR through XPath;
  the engine reports the GitHub error instead of falling back to another method.
