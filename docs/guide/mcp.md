# Use XPath from an agent

`xp mcp` is an MCP server for coding agents such as Claude Code and Cursor. It lets an agent read
your projects, write workflows and dispatch builds and releases, but never approve one: gated
actions still wait for you. The agent skills teach the agent how to use it.

## Make an agent token

`xp mcp` uses its own `mcp` device token, never the token of the CLI. An `mcp` token may read,
create and edit projects and workflows, and dispatch. It can never approve or deny a gate.

In the app, open **Settings** ▸ **CLI and agents** and press **New agent token**. The app shows
the token once, inside an MCP config you can copy. Or make one on the engine machine:

```sh
xpd token create --name "Claude" --kind mcp
```

With the macOS app, `xpd` is `/Applications/XPath.app/Contents/Helpers/xpd/bin/xpd`. The token is
printed once; keep it out of chats and files you share.

## Connect it

Save the token with `xp connect`. It checks the engine and the token before it saves anything,
and keeps the token in the login Keychain (macOS) or the encrypted client store (Linux):

```sh
xp connect http://127.0.0.1:7480 --mcp-token <mcp token>
```

`--token <cli token>` can go in the same command. When `xp` is already connected, the URL may be
left out. `xp disconnect` forgets the saved URL and tokens; the tokens keep working on the engine.

Instead of saving it, an agent's config can pass the token in the environment: `XP_ENGINE_URL`
and `XP_MCP_TOKEN` override what was saved.

## Add it to your agent

`xp mcp` speaks MCP over standard input and output. Standard output carries only MCP messages.

### Claude Code

With the token saved by `xp connect`:

```sh
claude mcp add xpath -- xp mcp
```

### Cursor and other agents

Agents that read an `mcpServers` config take the one the app shows under **Settings** ▸ **CLI
and agents**. For Cursor, put it in `.cursor/mcp.json` in the project, or `~/.cursor/mcp.json` for
every project:

```json
{
  "mcpServers": {
    "xpath": {
      "command": "xp",
      "args": ["mcp"],
      "env": {
        "XP_ENGINE_URL": "http://127.0.0.1:7480",
        "XP_MCP_TOKEN": "<mcp token>"
      }
    }
  }
}
```

That file then holds the token. If you saved it with `xp connect`, leave out `env`.

## What the tools do

Every tool answers with JSON. A project is named by its id (`prj_...`), `owner/name` or `name`; a
workflow by its id (`wf_...`) or its name.

- **Read.** `list_projects`, `get_project`, `list_workflows`, `get_workflow` (with its inputs),
  `list_runs`, `get_run`, `get_job`, `get_job_log_tail` (masked: secrets read `***`),
  `list_artifacts`, `get_job_tests`, `get_test_baselines`, `list_releases`, `get_release`,
  `get_release_notes`, `list_approvals`, `get_approval`, `get_gates`, `list_runners`,
  `list_credentials` (names, kinds and checks, never a secret) and `get_storage_report`.
- **Create and edit.** `add_project`, `scan_project`, `update_project`, `validate_workflow`,
  `create_workflow`, `update_workflow`, `archive_workflow` and `get_workflow_schema`. A workflow
  is validated first: with issues nothing is saved, and the issues come back with their line and
  column.
- **Dispatch.** `dispatch_workflow` starts a run with the same choices as `xp dispatch`: ref, app,
  flavors, platforms, bump or version, and inputs. `plan_dispatch` says what a dispatch would
  start and what it would leave out, without starting anything.
- **Ask for a rollout change.** `request_rollout` asks to pause, resume or complete Apple's phased
  release, or to set the percent of, halt or complete Google Play's staged rollout. It returns a
  run that waits at the `rollout` gate for you.
- **Wait.** `wait_for_run` waits for a run to end or reach a gate, and `wait_for_approval` for an
  approval to be decided or to expire. Each call waits 60 seconds by default, 300 at most, and
  returns `timedOut` when nothing changed: the agent calls it again.

There is no tool to approve, deny, merge, abandon, delete, cancel or resume, to change a gate, or
to add or assign a credential. You do those in the app or with `xp`.

## When a run waits for you

Production releases, Shorebird patches, store submissions, pushes, merges, rollout changes and
deletes wait for your approval. When a run the agent dispatched reaches one of these gates:

1. `get_run` shows the run as `waiting_for_approval`, with the ids of the pending approvals.
2. The agent tells you the approval id, what it covers and the run.
3. You approve or deny it in the app (**Approvals**) or with `xp approvals approve <id>` on your
   own machine.
4. The agent calls `wait_for_approval` (or polls `get_approval`) until the state is no longer
   `pending`, then follows the run again.

An approval nobody decides within 24 hours expires, which counts as denied. If an agent tries to
approve anyway, the engine answers `403 forbidden` to its `mcp` token. [Approvals](approvals.md)
covers gates and approvals.

## Errors the tools return

An error is `{"code", "message", "hint"}` with `isError` set. `code` is the engine's (such as
`not_found`, `workflow_invalid` or `secrets_locked`), or `unreachable` when the engine did not
answer. `hint` names the tool to call next, when there is one.

- `unauthorized`: the engine rejected the `mcp` token. Make a new one and connect again.
- `forbidden`: the token kind may not do this. Only you can.
- `ambiguous`: a bare `name` matches more than one project. Use `owner/name` or the id.

[Troubleshooting](troubleshooting.md) has the fixes.

## Agent skills

The XPath repository has four [Agent Skills](https://agentskills.io) that teach an agent how to
work with XPath:

| Skill | For |
|---|---|
| `xpath-release` | Operating XPath through `xp` and `xp mcp`: dispatching builds and releases, following logs, reading store status. It never approves a gate. |
| `xpath-workflows` | Writing and validating workflow YAML. |
| `xpath-setup` | Installing XPath, tokens, credentials, runners and troubleshooting. It never asks for a secret in chat. |
| `xpath-contributing` | Changing XPath itself. |

Install them with the [`skills`](https://www.npmjs.com/package/skills) CLI, from the repository of
the app the agent will release. Skills install into the current project; `-g` installs them for
every project:

```sh
npx skills add AbdurahmanAlmehdi/x-path                                   # pick skills and agents
npx skills add AbdurahmanAlmehdi/x-path --list                            # list them
npx skills add AbdurahmanAlmehdi/x-path --skill xpath-release -a claude-code -y
npx skills add AbdurahmanAlmehdi/x-path --skill '*' -a claude-code -g -y  # all, for every project
```

The reference for `xp mcp` is [Clients](../reference/clients.md).
