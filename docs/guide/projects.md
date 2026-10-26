# Projects

A project is a git repository that XPath builds and releases. When you add one, the engine scans it
for apps, flavors and store ids, and keeps its own mirror of the repository to build from, so your
clone is never written to. This page covers adding a project, reading its scan, its settings and a
first green build.

## Add a project

A project on GitHub needs the engine's GitHub token first: **Settings** ▸ **GitHub** in the app, or
`xpd secrets import-gh` on the engine machine (see [The GitHub token](credentials.md#the-github-token)).
A project on another git host needs none.

In the app, choose **Add project…** in the sidebar, then **Choose folder…** and pick a clone of the
repository, and press **Add and scan**. The folder has to be on the machine the engine runs on; for
a remote engine, type its path. With `xp`:

```sh
xp projects add acme/app                         # a GitHub repository, or its URL
xp projects add ~/src/app                        # a clone on the engine machine
xp projects add git@bitbucket.org:acme/app.git   # another git host, over SSH
xp projects list
```

A folder only names the repository (through its `origin`) and seeds the first scan. XPath reads it
and never writes to it. Commands name a project by its id (`prj_...`), `owner/name` or `name`.

## Add a project from another git host

Bitbucket, GitLab, any SSH server and `file://` repositories are added by an SSH URL (`git@host:path`
or `ssh://`) or a `file://` URL (ADR 0015).

- The engine reads the repository with its own SSH key: `~/.ssh/id_ed25519.pub` of the user it runs
  as, with no passphrase, because the service has no terminal. Add that key as a deploy key of the
  repository (an access key on Bitbucket). Adding checks access with `git ls-remote` and, when it
  fails, says where to add the key.
- The first connection records the host key; a key that changes later fails.
- A folder whose `origin` is an HTTPS URL on another host is refused with the SSH URL of the same
  repository. The app offers **Use the SSH URL**; `xp` prints the command, such as
  `xp projects add ~/src/app --ssh-url git@bitbucket.org:acme/app.git`. Your clone is not changed.
- Only workflows without a `github.*` or `git.push` step run on such a project, such as `dev-build`,
  `smoke-build` and `test`. The others are refused at dispatch with the reason.
- Runners fetch with their own key, so add each runner's key too ([Runners](runners.md)).
- `xp doctor` checks, among other things, that the engine reaches other git hosts over SSH.

Upgrade the app, `xp` and `xp mcp` along with the engine before you add such a project
([Which versions work together](install.md#which-versions-work-together)).

## Read the scan

The scan is read-only. It finds the apps (one at the root, or the Flutter members of a pub workspace
or Melos monorepo), their flavors and, for each flavor, the Android application id, the iOS bundle id
and signing team, the Shorebird app id and the entrypoint. It also reads the `.fvmrc` Flutter pin,
`shorebird.yaml` and the keystore reference in `key.properties`, never its passwords.

What looks wrong becomes a finding with a severity (`error`, `warning` or `info`), a message and a
fix: for example `bundle_id_platform_mismatch` when Android and iOS ids differ, `fvmrc_missing` or
`keystore_properties_missing`. Fix errors in the repository and scan again; warnings and notes can
wait.

After **Add and scan** the app shows the review of the scan. Press **Done** to keep the project, or
**Remove project**. Later, **Scan** on the project overview scans again. With `xp`:

```sh
xp projects show acme/app    # apps, flavors, ids and findings
xp projects scan acme/app
```

A new scan reads the folder the project was added from if it still exists, else a fresh copy from
the mirror. It follows a GitHub rename or a new default branch.

## Flavors

The scan reads flavors from Gradle `productFlavors`, `flavorizr.yaml`, Xcode schemes that archive
with `Release-<flavor>` and `lib/main_<flavor>.dart`. An app without flavors gets one flavor,
`default`. A flavor is its app's path and its name (`.` is the root app), and `xp projects show`
marks the production flavor `(prod)`.

Credentials and store ids belong to a flavor: each flavor uses at most one credential of each kind
([Credentials](credentials.md)).

## Set the store ids

The built-in workflows upload a build to the Firebase app id or App Store Connect app id of its
flavor, unless the dispatch gives `firebaseAppIds` or `appleAppIds`. The scan fills in the Firebase
app ids that `google-services.json`, `GoogleService-Info.plist` or `firebase_options.dart` name. You
set the App Store Connect app id.

In the app, open **Project settings** ▸ **Store ids** and press **Set ids…** next to a flavor. With
`xp`:

```sh
xp projects set acme/app --flavor prod --apple-app-id 1234567890
xp projects set acme/app --flavor dev --firebase-app-id android=1:123456789012:android:abcdef
```

Add `--app <path>` when the project has more than one app. An empty id removes it. Your edits are
kept apart from the scan, so a new scan never undoes them.

## Change the project settings

**Project settings** in the sidebar, under the project, has:

- **Git host**: where the repository lives (GitHub, another host such as `bitbucket.org`, or
  "local repository" for a `file://` remote) and its remote URL.
- **Base branch**: the branch releases are based on. Press **Save** after you change it.
- **Gates**: the actions that wait for your approval. Only the app turns a gate off; `xp gates
  tighten <project> <action>` turns one on, and agents can never turn one off. See
  [Approvals](approvals.md).
- **Store ids**: **Set ids…** for each flavor, as above.
- **Remove the project**: **Remove…** makes the engine forget the project. The repository, the
  stores and the credentials stay, and the mirror stays on disk until you free it
  ([Storage](storage.md)). `xp projects remove acme/app` does the same. Once a project has jobs or
  releases, the engine refuses to remove it.

## Run a first green build

The built-in `smoke-build` workflow checks out the project and builds an Android APK of each flavor,
signed with the debug key instead of the flavor's keystore. It needs no credential and no store id,
uploads nothing and takes no build number. It shows that the project builds before you set up
signing.

After the first scan, the app's **Get to a first build** checklist offers **Try an unsigned build**.
With `xp`:

```sh
xp dispatch acme/app smoke-build --flavor dev --follow
xp artifacts list <job id>
xp artifacts download <artifact id> -o app-dev.apk
```

`--dry-run` prints what would run and where, and starts nothing. The build needs the Android SDK on
the engine's machine or a runner that offers `android`. A job that waits with "No runner can do
android." has nowhere to run: install the SDK there or [pair a runner](runners.md#pair-a-runner).

Next, add [credentials](credentials.md) and run a signed build with `dev-build`
([Workflows](workflows.md)).
