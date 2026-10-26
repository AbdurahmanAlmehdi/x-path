# Quickstart

From nothing to a green build in a few minutes. Pick the Mac app, or the command line on a Mac,
Linux or Docker; both end with a project and a run of the built-in `test` workflow. The command-line
path is also a script, `tool/e2e/quickstart_cli.sh`, so this page cannot drift from what works.

## With the Mac app

1. Install the app:

   ```sh
   brew trust abdurahmanalmehdi/tap
   brew install --cask abdurahmanalmehdi/tap/xpath
   ```

   Or download the DMG from [Releases](https://github.com/AbdurahmanAlmehdi/x-path/releases).
2. Open **XPath**. The setup window starts the engine (a login item), links the `xp` command and
   checks the tools: Xcode, git, fvm, gh and Shorebird.
3. Connect GitHub when it asks, or skip it for a project on another git host.
4. **Add project** and pick the folder of your Flutter app. XPath scans it: its flavors, bundle
   and application ids, and what is missing for a release.
5. The project's setup checklist offers a **first build**: the `smoke-build` workflow builds a
   debug-signed APK with no credential at all. Run it, or run `test` from the project page.

The checklist then walks you through credentials, store ids and runners. [Try it
locally](try-it-locally.md) is the same path in more detail.

## With the command line

The engine (`xpd`) and the CLI (`xp`) come with the Mac app, with `install.sh` on Linux and in the
Docker image ([Install](install.md)).

1. Start the engine. On Linux, `install.sh` installs it as a user service; on a Mac the app runs
   it. To run one by hand:

   ```sh
   xpd serve
   ```

   It listens on `http://127.0.0.1:7480`.
2. Make a `cli` token for `xp` on the engine machine (the app does the same in Settings, CLI and
   agents, **New xp token**). It is printed once:

   ```sh
   xpd token create --name laptop --kind cli
   ```

3. Connect `xp` to the engine. It asks for the token, so the token stays out of your shell
   history, and saves it in the OS secret store, never in a file:

   ```sh
   xp connect http://127.0.0.1:7480
   xp status
   xp doctor
   ```

   `xp status` says which engine and version you reach; `xp doctor` checks the engine's tools,
   secrets and runners and says what to fix.
4. Add your app. A folder on the engine machine, `owner/name` on GitHub, or any git URL over SSH
   or `file://`:

   ```sh
   xp projects add ~/code/my_app
   ```

5. Run the tests and follow the log. `--follow` exits 0 only when the run succeeded:

   ```sh
   xp dispatch my_app test --follow
   ```

Then `xp dispatch my_app smoke-build --follow` builds a debug-signed APK, still with no
credential. [Credentials](credentials.md) sets up signing and the stores.

## With Docker

The image `ghcr.io/abdurahmanalmehdi/xpath` runs the engine with its data in a volume. It has no
Flutter of its own, so builds go to [runners](runners.md).

```sh
docker run -d --name xpath -p 127.0.0.1:7480:7480 -v xpath-data:/data ghcr.io/abdurahmanalmehdi/xpath
docker exec xpath xpd token create --name laptop --kind cli
xp connect http://127.0.0.1:7480
```

Then add a project from GitHub or a git URL (a folder must be inside the container) and pair a
runner, as [Runners](runners.md) says.

## Next

- [Projects](projects.md): flavors, store ids and the project settings.
- [Credentials](credentials.md): signing keys and store accounts.
- [Workflows](workflows.md): the built-in workflows and your own.
- [Releases](releases.md): a production release from build to merge.
- [Troubleshooting](troubleshooting.md): when something does not work.
