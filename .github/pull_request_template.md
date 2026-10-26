## What and why

<!-- What changes and why. The pull request title is a Conventional Commit (feat:, fix:, docs:, ...): it becomes the commit message and decides the version. -->

## How it was checked

<!-- The tests you added or ran, and anything you checked by hand. -->

## Checklist

- [ ] Tests cover the change (see the coverage policy in docs/reference/development.md).
- [ ] `openapi.yaml` and its contract tests changed with any API change.
- [ ] A schema change is a new migration with its snapshot golden.
- [ ] Docs in `docs/guide` and the skills match the change.
- [ ] No secret in code, tests, logs or this description.
