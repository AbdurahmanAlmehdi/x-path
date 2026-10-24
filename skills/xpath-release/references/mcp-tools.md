# `xp mcp` tools

The tools of `xp mcp`, from `apps/xp/lib/src/mcp/xp_tools.dart`. Every tool answers with JSON
text, or with `isError` and the error as JSON: `{"code", "message", "hint"}`. `project` is an id (`prj_...`), `owner/name` or `name`;
`workflow` is an id (`wf_...`) or a name.

There is no tool to approve, deny, merge, abandon, delete, change a gate, cancel or resume, nor to
add, assign or remove a credential (the owner does that in the app or with `xp credentials`). The
server tells the agent so when it connects.

## Read

| Tool | Arguments (required in bold) | Returns |
|---|---|---|
| `list_projects` | none | Every project with its apps, flavors and the findings of the last scan. |
| `get_project` | **`project`** | One project with its profile and findings. |
| `list_workflows` | **`project`** | The built-in workflows and the project's own. |
| `get_workflow` | **`project`**, **`workflow`**, `version` (integer; newest by default) | The workflow with its YAML, versions and `inputs`: each with its `type` (`string`, `boolean`, `choice` with `options`, `json`, `release`, or none for any value), `default` and `required`. |
| `get_run` | **`run`** (`run_...`) | `{run, pendingApprovals, note?}`: the run with its jobs, and the approvals it waits for. |
| `get_job` | **`job`** (`job_...`) | The job with its steps and their results. |
| `get_job_log_tail` | **`job`**, `lines` (100 by default) | `{lines, jobEnded, jobState?}`: the last lines, masked. |
| `list_artifacts` | **`job`** | The files the job produced (builds, manifests, symbols). |
| `get_job_tests` | **`job`**, `statuses` (`passed`, `failed`, `errored`, `skipped`), `limit` (1 to 1000), `offset` | The test run with its diff against the baseline; failures only by default. |
| `get_test_baselines` | **`project`** | The test runs new runs are compared with. |
| `list_releases` | `project`, `app` (path), `state` (`draft`, `building`, `uploaded`, `in_review`, `rejected`, `approved`, `live`, `merged`, `abandoned`) | Releases, newest first. |
| `get_release` | **`release`** (`rel_...`) | A release with its state in each store. |
| `get_release_notes` | **`release`** | What changed, as Slack and WhatsApp text. |
| `list_approvals` | `project`, `state` (`pending`, `approved`, `denied`, `expired`), `run` | Approvals, newest first. |
| `get_approval` | **`approval`** (`apr_...`) | One approval. Poll it while it is `pending`. |
| `get_gates` | **`project`** | Which actions of the project wait for an approval. Read-only. |
| `get_storage_report` | none | What the engine keeps on disk and what could be freed. |
| `list_runners` | none | Every runner: `name`, `id`, `status`, `lastHeartbeat`, `capabilities`, `missing` (each with `capability`, `reason` and `fix`, while the runner is connected), `slots`, `jobIds`. A job that waits with "No runner can do ..." needs a runner that offers it. Read-only. |
| `list_credentials` | `project` (only the credentials it uses, and only its flavors) | The named credentials, never a secret: `id`, `name`, `kind`, `account`, `status` (`unverified`, `verified`, `rejected`, `unreachable`), `message`, `fix`, and `usedBy` (`projectId`, `project`, `app`, `flavor`, and the `status`, `message` and `fix` of that assignment). Read-only. |

## Create and edit

| Tool | Arguments (required in bold) | Notes |
|---|---|---|
| `add_project` | exactly one of `path` (an absolute folder with a clone, on the engine's machine) or `remote` (`owner/name`, or an https or ssh URL) | Adds the GitHub repository and scans it. Needs the engine's GitHub token. |
| `scan_project` | **`project`** | Scans again. Read-only: the repository is never changed. |
| `update_project` | **`project`**, **`edits`** | `edits` is a `ProfileEdits` object, for example `{"defaultBaseBranch": "main", "apps": [{"path": ".", "storeCountry": "us", "flavors": [{"name": "prod", "prod": true}]}]}`. Per flavor: `prod`, `shorebird`, `entrypoint`, `iosBundleId`, `androidAppId`, `versionFiles`, `firebaseAppId` (by platform; an empty id removes it), `appleAppId`. The built-ins upload to the store ids when no input gives one. Edits survive rescans. |
| `validate_workflow` | **`project`**, **`yaml`** | `{valid, saved: false, issues: [{line, column, message}]}`. Saves nothing. |
| `create_workflow` | **`project`**, **`name`** (letters, digits, `.`, `_`, `-`), **`yaml`** | Validates first; with issues nothing is saved and the issues come back (`isError`). |
| `update_workflow` | **`project`**, **`workflow`**, **`yaml`** | A new version of a workflow of the project's own; built-ins cannot be edited. Validates first. |

## Run

| Tool | Arguments (required in bold) | Notes |
|---|---|---|
| `dispatch_workflow` | **`project`**, **`workflow`**, `ref`, `app`, `flavors` (list), `platforms` (list of `android`, `ios`), `bump` (`major`, `minor`, `patch`, `keep`), `version` (`x.y.z`, instead of `bump`), `releaseVersion` (`x.y.z+build`, for a patch), `inputs` (object) | Returns `{run, pendingApprovals, note?}`. A gated run becomes `waiting_for_approval`. |
| `plan_dispatch` | the arguments of `dispatch_workflow` | What it would start, planned by the engine; nothing starts and no build number is taken. `stages` (each job with `local`, `runner`, `waitReason`), `skipped` (each with its `reason`; `blocks: true` means `dispatch_workflow` would be refused), `version`, `build`. Read-only. |

## Errors the tools return

An error is `{"code", "message", "hint"}`. `code` is the engine's (`not_found`,
`workflow_invalid`, ...; see [failures.md](failures.md)), or one of `unreachable`, `ambiguous`,
`invalid_request` and `internal` when the engine never answered. `hint` names the tool to call
next, or is empty.

- `forbidden`: "The engine refused: ... This MCP token reads, creates and edits projects and
  workflows and dispatches; it can never approve or loosen a gate."
- `unauthorized`: "The engine rejected the MCP token." The owner makes a new one with
  `xpd token create --name <name> --kind mcp` and saves it with `xp connect --mcp-token <token>`.
- `unreachable`: the engine is not reachable at the saved URL (or `XP_ENGINE_URL`).
- `not_found` with the hint `See: list_projects` (or `list_workflows`): a name that matches no
  project or workflow. `ambiguous`: a bare `name` that is more than one project (use
  `owner/name` or the id).
- Any other API error comes back with the engine's code and message.

## A typical session

1. `list_projects`, then `list_workflows` for the project.
2. `get_workflow` to read the inputs of the workflow you will run.
3. `dispatch_workflow`; keep the run id.
4. `get_run` until it is `succeeded`, `failed`, `cancelled` or `waiting_for_approval`;
   `get_job_log_tail` for a job that runs or failed.
5. On `waiting_for_approval`: report the approval to the owner (see the main skill), then poll
   `get_approval`.
6. For a release: `list_releases` (state `in_review`, say) and `get_release` for the store lanes.
