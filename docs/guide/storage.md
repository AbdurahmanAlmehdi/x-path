# Storage

The engine keeps builds, logs, worktrees, repository mirrors and Flutter SDKs in its data directory.
Old logs go by themselves; everything else is deleted only when you free space. This page says where
things are, what housekeeping keeps, and how to free space from the app or with `xp storage`.

## Where the engine keeps its data

The data directory is `~/Library/Application Support/XPath` on macOS, `~/.local/share/xpath`
(`$XDG_DATA_HOME/xpath`) on Linux and `/data` in the Docker image. `xpd serve --data-dir` or
`$XPATH_DATA_DIR` sets another. Among other things it holds:

| Path | What it is |
|---|---|
| `xpath.db` | The database: projects, workflows, runs, jobs, releases, credentials without their secrets. Copied to `xpath.db.bak-v<N>` before a migration. |
| `secrets.enc`, `master.key` | Secrets too large for the Keychain (macOS), or all secrets and their key (Linux). |
| `artifacts/<job id>/` | The files each job built. |
| `logs/<job id>/` | The log of each job. |
| `worktrees/` | The working copies jobs ran in. |
| `mirrors/` | The engine's bare copy of each repository. |
| `toolchains/flutter/<version>` | Flutter SDKs the engine fetched when fvm was not there. |
| `service-logs/` | The engine's own log. |

A runner keeps its own copies, caches and SDKs in its data directory on the runner machine,
`~/.local/share/xpath/runner` by default.

## Artifacts

A build is stored as `artifacts/<job id>/<flavor>-<version>.<ext>`, for example `dev-1.2.3+45.apk`,
with its size and SHA-256. What a runner builds is uploaded to the same store. Each build also
records a `manifest.json`: the version, the commit, the tool versions and every file with its
SHA-256.

```sh
xp artifacts list <job id>
xp artifacts download <artifact id> -o ~/Downloads
```

`download` checks the SHA-256 the engine sends. A pinned artifact is never freed; pin one with
`POST /artifacts/{id}/pin` in the API.

## Logs

`xp logs <job>` prints the log of a job, and `xp logs -f <job>` follows it until the job ends. The
engine deletes the logs and records of jobs that finished more than 90 days ago. It does this when
it starts, if the last pass was a day ago or more, and then every 24 hours.

## What housekeeping keeps

Freeing space works in five categories. Each keeps what a release or a running job still needs.

| Category | What goes | What stays |
|---|---|---|
| `artifacts` | Builds past the newest 5 of each flavor | Pinned artifacts, those of a release that is not over, and those of unfinished jobs |
| `logs` | Logs of jobs that finished more than 90 days ago | Jobs a release that is not over needs, a current test baseline, or a job that still has an artifact |
| `worktrees` | Worktrees of jobs that succeeded or were cancelled, and of failed jobs after 7 days | Worktrees of unfinished jobs, of failed jobs for a week (so you can resume them), and of failed jobs of a release that is not over |
| `mirrors` | Mirrors of repositories that are no longer projects | Mirrors of projects |
| `flutter` | SDKs no app pins in `.fvmrc`, no Shorebird release was built with and no unfinished job uses | The others |

A release is over once its pull request is merged or it is abandoned; until then all of its builds
stay.
Removing a project leaves its mirror on disk until you free `mirrors`.

## See what is used

Open **Storage** in the sidebar, which also shows how much can be freed. The page shows how much is
reclaimable, **What the engine keeps** by category, and **Artifacts by app and flavor**. **Measure
again** measures now. From a terminal:

```sh
xp storage report
```

It prints the size used and the size that can be freed in each category, the total, and the
retention.

## Free up space

In the app, press **Free up space…**, pick the categories and press **Free** with the size. It
cannot be undone. With `xp`, `free` is a dry run unless you pass `--apply`:

```sh
xp storage free                                 # what would be freed
xp storage free --apply                         # free it
xp storage free --apply --category worktrees --category flutter
```

Artifacts are freed first. `free --apply` prints what it freed; when it could not free something, it
says what and exits 1. Only `app` and `cli` tokens may delete; an agent with an `mcp` token can read the
report and do a dry run, nothing more.

## Change the retention

The retention says how many builds of each flavor to keep (5 unless you change it) and how many days
of logs (90). In the app, the **Retention** section of the Storage page has **Builds kept per
flavor** and **Days of logs**; press **Save**. Each needs a whole number of at least 1. With `xp`:

```sh
xp storage retention                        # show it
xp storage retention --keep 10 --log-days 30
```

Logs past their days go every day; artifacts past the retention go only when you free space.
