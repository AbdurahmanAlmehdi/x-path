# Approvals

Some actions change what your users get or what is on GitHub, so XPath waits for you before it does
them. A step behind a gate stops its job until you approve or deny it in the app or with `xp`.
Agents can ask for these actions, but never approve them.

## What waits for approval

A workflow puts a gate in front of a step with `gate: <action>`. The built-in workflows use these:

| Gate | Where | If you approve |
|---|---|---|
| `prod_release` | `prod-release`, before the release branch is cut | The release is built and uploaded to the stores. |
| `push` | `prod-release`, `shorebird-patch` | The release branch is pushed; the same approval covers the tag push at the end of the run. |
| `prod_patch` | `shorebird-patch`, `shorebird-track` | A Shorebird patch is published, promoted or rolled back. |
| `merge` | `release-merge` | The release pull request is merged with a merge commit. |
| `rollout` | `release-rollout` | A store's phased or staged rollout changes. |

Two more gates, `store_submission` and `delete`, are there for your own workflows. A dev build or a
test run has no gate, so it never waits.

While a job waits it is in `waiting_for_approval`. It holds no slot and no runner, but a run of a
workflow with `lock: project` keeps the project, so the next release or patch queues behind it.

## Who can approve

Only `app` and `cli` tokens decide: the Mac app and the `xp` command line. An `mcp` token, the one
`xp mcp` uses, and a runner's token get `403` when they try, and no MCP tool approves or denies. So
an agent that dispatches a production release stops at the gate and tells you; see
[Use XPath from an agent](mcp.md).

The same rule covers actions that move a release on without a gate step: marking a store status by
hand, abandoning a release, setting its store texts, and deleting files to free disk space. Only an
`app` or `cli` token may do them.

## Approve in the app

- **The needs-you bar** of a project shows the approval that expires first, with "Review…" (⇧⌘A)
  and "Deny…".
- **Approvals** in the sidebar is the inbox, with the count of what waits: Pending, Decided and
  Expired.
- **A macOS notification** and the menu bar extra appear when an approval starts to wait. Neither
  decides; "Review…" opens the confirmation sheet.

The confirmation sheet is the only place the app decides. It shows what the approval is bound to
(project, flavor, version, commit, job) and what happens if you approve. Approve takes ⌘↩ or a
click once a one-second delay is over; Return never approves. Deny takes an optional reason.

## Approve with xp

```sh
xp approvals list --state pending              # --project <p> for one project
xp approvals show apr_...                      # action, project, commit, version, expiry
xp approvals approve apr_... --reason "Checked the build on a device"
xp approvals deny apr_... --reason "Wrong commit"
```

`xp runs show <run>` also names the approval a waiting run needs. The `xp` you approve with must be
connected with a `cli` token (see [Install XPath](install.md)). An `xp` exit code of 77 means the
token may not decide; 73 means the approval was decided already.

## What an approval covers

An approval binds to one project, action, commit, version and run. If the commit or the version
changes, or you dispatch again, the engine asks anew. Every job of the run that waits at the same
gate, such as each platform of a release, goes on with the one approval.

- **The first decision wins.** When two devices decide at once, one wins and the other is told who
  decided it.
- **Approved:** the jobs that wait go on.
- **Denied:** the gate step fails with your reason, and the run fails.

## When an approval expires

An approval nobody decides within 24 hours turns `expired`, which counts as denied: the job that
waited fails. A decided or expired approval is final for its run. To try again, dispatch the
workflow again; the new run asks for a new approval.

## Set the gates of a project

Every gate is on for a new project. You can turn a gate off for one project, and then that action
goes ahead without asking. Turning a gate off also lets the jobs that wait at it go on.

- **In the app:** Project settings, Gates. Tick or untick each action.
- **With xp:** read the gates, or turn gates on. The CLI cannot turn a gate off; only the app can.

```sh
xp gates show acme/app
xp gates tighten acme/app push merge
```

An `mcp` token can read the gates (the MCP tool `get_gates`) but never change them.

More: [The `xp` command line](../reference/clients.md) and [Releases](releases.md).
