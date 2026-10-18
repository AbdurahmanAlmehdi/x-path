# Try XPath locally

This guide gets XPath running on your own Mac, connects your own accounts and runs a first dev
build of `mataa_new_app`. It uses the local build of the app: signed with your Apple Development
certificate, not notarized, no auto-update. Everything stays on this Mac; nothing in the repository
of your app is written except the release tags and commits a prod release makes.

You need macOS 13 or later, Xcode, git, and the Flutter toolchain your app uses (fvm if the app pins
Flutter with `.fvmrc`). Shorebird is only needed for over-the-air patches.

## 1. Build and install the app

From the XPath repository, with the repository's Flutter first on PATH:

```bash
export PATH="$PWD/.fvm/flutter_sdk/bin:$HOME/.pub-cache/bin:$PATH"
```

```bash
tool/release/build_mac.sh --install
```

It builds the `xpd` engine and the `xp` CLI, builds `XPath.app` in release mode, puts both tools
inside the app (`Contents/Helpers/xpd` and `Contents/Helpers/xp`), signs everything with your Apple
Development identity (Hardened Runtime, team AFBD5TBR5U) and replaces `/Applications/XPath.app`.
Another identity can be named with `XPATH_SIGN_IDENTITY`; `--reuse-bundles` skips rebuilding the
tools when only the app changed.

When you install over a running engine, restart it so it picks up the new `xpd`:

```bash
launchctl kickstart -k gui/$(id -u)/ly.abdurahman.xpath.xpd
```

## 2. Open XPath and finish setup

Open **XPath** from `/Applications` (or Spotlight). The first window is **Set up XPath on this Mac**:

1. **Start the engine.** XPath registers its engine (`ly.abdurahman.xpath.xpd`) as a login item, so
   it runs now and at every login. macOS shows a "Background Items Added" notice; that is expected.
   If the step asks you to, allow XPath in **System Settings ▸ General ▸ Login Items** and press
   **Start engine** again.
2. **Add xp to your PATH.** **Link xp** links the `xp` command inside the app to `/usr/local/bin/xp`
   (or `~/.local/bin/xp` if `/usr/local/bin` is not writable). Open a new terminal and check:

   ```bash
   xp --version
   ```

3. **Check the tools.** Shows whether Xcode, git, fvm, gh and Shorebird are found.

Then **Open XPath**. The engine listens on `http://127.0.0.1:7480`; check it with:

```bash
curl -s http://127.0.0.1:7480/health
```

If the setup window doesn't appear (an engine was already set up), **Settings ▸ Command line tool**
links `xp`, and **Settings ▸ About** shows whether the engine runs at login.

The engine keeps its database and large secrets in `~/Library/Application Support/XPath`, its log
in `service-logs/xpd.log` there, and its secrets in your login Keychain under services starting
with `ly.abdurahman.xpath`. It finds Flutter, fvm, Shorebird and Homebrew tools in their usual home
and Homebrew folders even though launchd starts it with a short PATH.

## 3. Connect GitHub

A project is a GitHub repository, so the engine needs a GitHub token before you can add one.

Open **Settings** (⌘,) ▸ **GitHub** and either press **Import from GitHub CLI** (runs
`gh auth token` on this Mac; log in first with `gh auth login`) or paste a token (`ghp_…` or
`github_pat_…`) and press **Check and save**. XPath checks it with GitHub before keeping it and
then shows the GitHub login it belongs to. The token needs read access to the repositories you
add, and write access (contents and pull requests) for the release PR merge. If you try to add a
project first, **Add project** offers **Connect GitHub…**, which opens this section.

From a terminal the same import is:

```bash
/Applications/XPath.app/Contents/Helpers/xpd/bin/xpd secrets import-gh
```

## 4. Add mataa_new_app

1. In the sidebar choose **Add project…**.
2. **Choose folder…** and pick your clone of `mataa_new_app`, then **Add and scan**. XPath reads the
   folder and never writes to it; builds run from the engine's own copy of the repository.
3. **Review the scan.** It lists the apps, flavors, iOS bundle IDs, Android application IDs and
   Shorebird. Errors must be fixed in the repository and scanned again; warnings can wait. Press
   **Done**.

## 5. Add your credentials

Credentials have names and are shared: add each one once, then give it to the flavors that use it.
One App Store Connect key can serve both `dev` and `prod`, and two Shorebird keys are told apart by
their names. The secrets stay on this Mac.

1. Open **Credentials** in the sidebar and press **Add credential…** once per credential. Give it a
   **Name** you will recognise (for example "Personal Apple Dev Account"), pick the **Kind**, fill
   the fields and press **Check and save**. The engine checks it with the service it is for and
   stores nothing if the check fails.
2. Under **Flavors**, pick **mataa_new_app** and press **Manage…** on a flavor (or click the
   credentials of a flavor on the project overview). For each kind, **Assign…** picks an existing
   credential or **Add new…**. **Use for** says whether it is for **This flavor** or **Every flavor
   of** the app; flavors that already have a credential of that kind keep it unless **Replace
   existing** is ticked.

| Kind | Fields | Where to get it |
|---|---|---|
| App Store Connect API key | Key ID, Issuer ID, Private key (.p8) | App Store Connect ▸ Users and Access ▸ Integrations ▸ App Store Connect API. App Manager access is enough for uploads and review status. |
| Apple ID | Apple ID, App-specific password | Only if you upload with `altool` instead of an API key. Make the password at account.apple.com ▸ Sign-In and Security ▸ App-Specific Passwords. |
| Google Play service account | Service account key (JSON) | Google Cloud console ▸ IAM ▸ Service accounts ▸ Keys, then invite the account in Play Console ▸ Users and permissions with release rights for the app. |
| Firebase service account | Service account key (JSON) | A service account with the Firebase App Distribution Admin role in the app's Firebase project. |
| Android keystore | Keystore, Store password, Key alias, Key password | Your release `.jks`/`.keystore`. Keystores of any size are fine. |
| Shorebird API key | Token | `shorebird login:ci` prints one (`sb_api_…`). Only for flavors with Shorebird on. |
| Slack webhook | Webhook URL | A Slack incoming webhook for the channel that should hear about releases. |

The GitHub token is not on this list: the engine has one, set in step 3.

Each credential shows **Verified**, **Rejected** or **Not checked**, and how many flavors use it.
Each flavor also shows whether its credentials reach its app (an App Store Connect key must see the
flavor's bundle ID, a Play service account its package). **Check now** checks again; the engine also
checks every day and before each build. Deleting a credential that flavors use lists them and asks
first.

From a terminal, `xp credentials` does the same, without ever taking a secret as an argument:

```sh
xp credentials add --kind asc_key --name "Personal Apple Dev Account" \
  --key-id ABC123DEF4 --issuer-id <issuer id> --p8 ~/keys/AuthKey_ABC123DEF4.p8
xp credentials assign "Personal Apple Dev Account" --project mataa_new_app --all-flavors
xp credentials list
```

## 6. Run a dev build

1. Select **mataa_new_app** in the sidebar. The overview shows each flavor's local, testing and live
   versions.
2. Press **Dispatch…** (⌘N), pick the **Dev build** workflow, the dev flavor and the platforms, and
   check **Will run**: it lists every job, where it runs and which approvals it waits for.
3. Press **Dispatch N jobs** with ⌘↩ (Return does not dispatch). The job view opens: the pipeline
   graph, the steps and the live log.

The built-in Dev build uploads only when it knows where to: Android goes to Firebase App
Distribution when `firebaseAppIds` names the flavor's Firebase app, iOS goes to TestFlight when
`appleAppIds` names the App Store Connect app. Without them it builds and keeps the artifacts.
To upload, either:

- dispatch from a terminal with the inputs:

  ```bash
  xp dispatch <project> dev-build --flavor dev --platform android \
    --input 'firebaseAppIds={"dev": {"android": "1:…:android:…"}}'
  ```

  (`xp` needs a CLI token once: `xpd token create --name "My Mac" --kind cli` with the `xpd` inside
  the app, then `xp connect http://127.0.0.1:7480 --token <token>`), or
- open **Workflows**, pick **Dev build**, **Save as…** a copy, set the default of
  `firebaseAppIds` / `appleAppIds` in the YAML and dispatch that copy from the app.

## Remove XPath

**Settings ▸ Remove XPath…** revokes the paired runners, stops and unregisters the engine, and
removes the `xp` link if it points into the app. Tick **Also delete engine data** and **Also delete
Keychain items** to remove everything (your repositories are never touched), then press **Move to
Trash and quit**.

## Not in this build

Developer ID signing, notarization, the DMG, Sparkle updates and the Homebrew cask are not part of
the local build. To update, pull the repository and run `tool/release/build_mac.sh --install`
again; the engine and your data are kept.
