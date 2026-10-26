# XPath

XPath is an open source (Apache-2.0), self-hosted release tool for Flutter apps.

A headless engine, `xpd`, owns projects, secrets, jobs and store status. Four clients talk to it
over HTTP/JSON plus one WebSocket:

- a Flutter macOS app (`apps/xp_desktop`),
- the `xp` command-line client (`apps/xp`),
- `xp mcp`, an MCP server for agents,
- `xp runner`, remote runners on other Macs and Linux machines.

You point it at a repo, it scans the app, and from then on it builds, tests, signs, uploads, tags
and tracks releases to App Store Connect, Google Play, Firebase App Distribution and Shorebird.
It writes nothing to the repo except release-model git changes.

> **Status:** 1.0. The engine, the `xp` CLI, `xp mcp`, remote runners and the macOS app are
> released together. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## Install

On a Mac, the notarized app (it brings the engine and `xp`):

```sh
brew trust abdurahmanalmehdi/tap
brew install --cask abdurahmanalmehdi/tap/xpath
```

On Linux, the engine and `xp` as a user service, or a runner:

```sh
curl -fsSL https://xpath.abdurahman.ly/install | sh
curl -fsSL https://xpath.abdurahman.ly/install | sh -s -- --runner --with-android
```

With Docker, `ghcr.io/abdurahmanalmehdi/xpath` for the engine and
`ghcr.io/abdurahmanalmehdi/xpath-runner` for a runner. The DMG and the Linux bundles are on
[Releases](https://github.com/AbdurahmanAlmehdi/x-path/releases). [Install](docs/guide/install.md)
has the details and which versions work together.

## Quickstart

[docs/guide/quickstart.md](docs/guide/quickstart.md) goes from nothing to a green build, with the
app or the command line:

```sh
xpd token create --name laptop --kind cli
xp connect http://127.0.0.1:7480   # asks for the token
xp projects add ~/code/my_app
xp dispatch my_app test --follow
```

## Guide

| Page | What it covers |
|---|---|
| [Quickstart](docs/guide/quickstart.md) | The first project and the first green run, with the app or `xp`. |
| [Try it locally](docs/guide/try-it-locally.md) | The Mac app path step by step, up to a dev build. |
| [Install](docs/guide/install.md) | Every way to install, where the data lives, which versions work together. |
| [Projects](docs/guide/projects.md) | Adding a project from any git host, the scan, flavors and store ids. |
| [Credentials](docs/guide/credentials.md) | Signing keys and store accounts, and how they reach a build. |
| [Workflows](docs/guide/workflows.md) | The built-in workflows, your own, inputs, expressions and gates. |
| [Runners](docs/guide/runners.md) | Other Macs and Linux machines that run jobs, and how they reach the engine. |
| [Approvals](docs/guide/approvals.md) | Gated actions and who may approve them. |
| [Releases](docs/guide/releases.md) | A production release from build to store to merge, rollouts and patches. |
| [MCP](docs/guide/mcp.md) | `xp mcp` and the agent skills. |
| [Storage](docs/guide/storage.md) | The data directory, artifacts, logs and freeing space. |
| [Troubleshooting](docs/guide/troubleshooting.md) | What to do when something does not work. |
| [Uninstall](docs/guide/uninstall.md) | Removing XPath and its data. |

## Reference

How XPath works inside, for operators and contributors:

| Page | What it covers |
|---|---|
| [Running the engine](docs/reference/engine.md) | `xpd` as a process and as a service. |
| [Releases and installation](docs/reference/installation.md) | How XPath is released and installed. |
| [Projects, jobs and builds](docs/reference/builds.md) | Scans, jobs, versions and guards, the toolchain, builds, Shorebird, tests. |
| [Stores and credentials](docs/reference/stores.md) | App Store Connect, Google Play, Firebase, the Shorebird CLI, credentials. |
| [Workflows and the scheduler](docs/reference/workflows.md) | The workflow document, the built-ins, dispatch and scheduling. |
| [Runners](docs/reference/runners.md) | Pairing, the connection, leases, the agent and its updates. |
| [Releases and notifications](docs/reference/releases.md) | The release state machine, its endpoints, notifications and housekeeping. |
| [Clients](docs/reference/clients.md) | The `xp` command line, `xp mcp`, the client library and the desktop app. |
| [Developing XPath](docs/reference/development.md) | The repository layout, setup, tests, CI and the website. |

The API is [`packages/xp_api/openapi.yaml`](packages/xp_api/openapi.yaml); the decisions are in
[docs/adr](docs/adr).

## Agent skills

`skills/` holds [Agent Skills](https://agentskills.io) that teach a coding agent (Claude Code,
Cursor, Codex and others) how to work with XPath:

| Skill | For |
|---|---|
| `xpath-release` | Operating XPath through `xp` and `xp mcp`: dispatching builds and releases, following logs, reading store status. It never approves a gate. |
| `xpath-workflows` | Writing and validating workflow YAML. |
| `xpath-setup` | Installing XPath, tokens, credentials, runners and troubleshooting. It never asks for a secret in chat. |
| `xpath-contributing` | Changing XPath itself. |

Install them with the [`skills`](https://www.npmjs.com/package/skills) CLI, from the repository of
the app the agent will release (skills install into the current project):

```sh
npx skills add AbdurahmanAlmehdi/x-path                                   # pick skills and agents
npx skills add AbdurahmanAlmehdi/x-path --list                            # list them
npx skills add AbdurahmanAlmehdi/x-path --skill xpath-release -a claude-code -y
npx skills add AbdurahmanAlmehdi/x-path --skill '*' -a claude-code -g -y  # all, for every project
```

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [Developing XPath](docs/reference/development.md):
the repository layout, the dependency direction between packages, the Melos scripts and the test
policy. Bugs and ideas go to [issues](https://github.com/AbdurahmanAlmehdi/x-path/issues).

## License

Apache-2.0. See [LICENSE](LICENSE).
