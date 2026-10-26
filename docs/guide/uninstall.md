# Uninstall XPath

Removing XPath means stopping its services, revoking its runners and, if you want, deleting its data
and secrets. Your repositories are never touched, and nothing changes in the stores. On a Mac the
app does most of it in one step; elsewhere you run a few commands.

## Remove the Mac app

Open **Settings** ▸ **Remove XPath…**. Confirmed, the app:

1. revokes every runner of the engine on this Mac while the engine still runs;
2. stops the engine and takes it off the login items;
3. removes the `xp` link, only where it points into this app;
4. with **Also delete engine data**, deletes `~/Library/Application Support/XPath` (the database,
   builds, logs and mirrors) and the app's own engine list and cache, once the engine has stopped;
5. with **Also delete Keychain items**, deletes every Keychain item whose service is
   `ly.abdurahman.xpath` or starts with it: the engine's secrets and credentials and the app's engine
   tokens.

A step that fails shows what macOS or the engine said, and the others still run. Then press **Move
to Trash and quit**, or **Quit XPath** and drag XPath from Applications to the Trash. If you
installed it with Homebrew, press **Quit XPath** and let Homebrew remove the app:

```sh
brew uninstall --cask xpath
```

An engine started with `--data-dir` or `$XPATH_DATA_DIR` keeps that folder; delete it yourself.

## Remove the engine without the app

On a headless Mac or on Linux, stop and remove the service that `xpd install-service` (or the Linux
installer) made:

```sh
xpd uninstall-service
```

It leaves the data directory alone. Add `--system` for a system unit on Linux, as root. On Linux,
then delete what the installer put under its prefix (`~/.local` unless you passed `--prefix`): the
folder `~/.local/lib/xpath` and the links `~/.local/bin/xpd` and `~/.local/bin/xp`.

For the Docker image, remove the container, and the volume with its data:

```sh
docker rm -f xpath
docker volume rm xpath-data
```

## Remove a runner

1. Revoke it on the engine, so its credential stops working: **Revoke…** on the Runners page of the
   app, or `xp runners revoke <runner>`. Removing the Mac app revokes every runner by itself.
2. On the runner machine, stop and remove its service:

   ```sh
   xp runner uninstall-service
   ```

   Add `--system` if it runs as a system unit, and `--data-dir` if it uses another data directory.
   The data directory is left alone.
3. Delete the runner's data directory, `~/.local/share/xpath/runner` unless you chose another. It
   holds `runner.json`, its repository caches, its Flutter SDKs and, on Linux, its credential.
4. On macOS, delete its credential from the login Keychain: the item with the service
   `ly.abdurahman.xpath.runner`.
5. Remove the runner's SSH key from the deploy keys of your repositories.

For the runner image, remove the container and its volume:

```sh
docker rm -f xpath-runner
docker volume rm xpath-runner
```

## Delete the data directory

The data directory is `~/Library/Application Support/XPath` on macOS and `~/.local/share/xpath`
(`$XDG_DATA_HOME/xpath`) on Linux. Stop the engine before you delete it. Deleting it removes every
project, run, release and credential record, all builds and logs, and on Linux the encrypted secrets
and their `master.key`.

On Linux the default runner data directory, `~/.local/share/xpath/runner`, is inside it. If the
machine is also a runner, deleting the engine's folder removes the runner's too.

To free space without removing XPath, see [Storage](storage.md) instead.

## Delete Keychain items

On macOS, XPath keeps its secrets in the login Keychain under these services:

| Service | What it holds |
|---|---|
| `ly.abdurahman.xpath.credentials` | The engine's secrets, such as credentials and the GitHub token; large ones are in `secrets.enc` |
| `ly.abdurahman.xpath.master` | The key of `secrets.enc` in the data directory |
| `ly.abdurahman.xpath.app` | The app's tokens for each engine |
| `ly.abdurahman.xpath.client` | The tokens `xp connect` saved |
| `ly.abdurahman.xpath.runner` | A paired runner's credential |

**Also delete Keychain items** in Remove XPath deletes all of them. Without the app, search for
`ly.abdurahman.xpath` in Keychain Access and delete the items it finds. Delete the `master` item
only together with `secrets.enc`: without it the file cannot be opened.

## Forget an engine in the CLI

```sh
xp disconnect
```

It forgets the engine URL and the tokens `xp connect` saved: the URL in `xp.json` in
`~/.config/xpath` (or `$XP_CONFIG_DIR`), the tokens in the Keychain on macOS or in `secrets.enc` in
that folder on Linux. The tokens keep working on the engine, and `XP_ENGINE_URL`, `XP_TOKEN` and
`XP_MCP_TOKEN` still apply when they are set. Connect to another engine with `xp connect`
([Install XPath](install.md#connect-the-cli)).
