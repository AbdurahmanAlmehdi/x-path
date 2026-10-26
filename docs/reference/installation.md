# Releases and installation

How XPath is released and every way to install it. The user guide is in [docs/guide](../guide/quickstart.md); this is the reference.

## Releases and installation

**Installing.** On a Mac, the notarized app from Homebrew (the tap
[AbdurahmanAlmehdi/homebrew-tap](https://github.com/AbdurahmanAlmehdi/homebrew-tap); Homebrew asks you to trust a
third-party tap once):

```sh
brew trust abdurahmanalmehdi/tap
brew install --cask abdurahmanalmehdi/tap/xpath   # --adopt takes over an XPath.app installed from the DMG
brew upgrade --cask xpath                         # later releases
```

or `XPath-<version>.dmg` from the [latest release](https://github.com/AbdurahmanAlmehdi/x-path/releases/latest). On
Linux, `curl -fsSL https://xpath.abdurahman.ly/install | sh`; or the Docker image below. The rest of this section is
how those are built.

`tool/release/bundles.sh` builds a release of XPath into `build/release` (D-23, ADR 0001):

- **Bundles.** `dart build cli` of `xpd` and `xp` for each target in `bundles/<target>/{xpd,xp}` (`bin/`, `lib/` with
  `libsqlite3`). The targets are `macos-arm64`, `macos-x64`, `linux-x64` and `linux-arm64`; by default every target
  the machine can build. `dart build cli` cross-compiles to Linux from anywhere but builds macOS only for the
  machine's own architecture, so an Apple silicon Mac builds `macos-arm64`, `linux-x64` and `linux-arm64`, and
  `macos-x64` needs an Intel Mac. The host's bundles must print the version of `apps/xpd/pubspec.yaml` (`xp` and
  `xpd` must agree); the others are checked with `file`.
- **Runner bundles.** `runners/<os>-<arch>/xp.tar.gz` (top level `bin` and `lib`), named as a runner reports itself
  (`linux-x86_64`, `linux-arm64`, `macos-arm64`), and copied into `bundles/<target>/xpd/runners/`, where the engine
  serves them to runners that update (Runner updates).
- **Assets.** `assets/xpath-<target>.tar.gz` (top folder `xpath-<version>-<target>/` with `VERSION`, `LICENSE`,
  `install.sh`, `xpd/` and `xp/`), `assets/xp-<target>.tar.gz` (the CLI alone), a `.sha256` for each and
  `install.sh`. The archives hold plain files owned by root, without macOS extended attributes.

**The release workflow** (`.github/workflows/release.yml`) publishes a release on every push to `main`, so on every
merged pull request. Nothing is committed to `main`: the version lives in the tag.

- **Version** (job `version`). `dart run tool/release_version.dart next` decides it. A `vX.Y.Z` tag already on the
  commit is reused (a run again). Otherwise the highest `vX.Y.Z` tag reachable from the commit is bumped by the
  [Conventional Commits](https://www.conventionalcommits.org) titles of the first-parent commits since it: the squash
  commit of each merge, whose title is the pull request title (for a merge commit, the pull request title in its
  body). A breaking change (`feat!:`, `fix(scope)!:` or a `BREAKING CHANGE:` footer) is minor before 1.0 and major
  after, `feat:` is minor and everything else is patch, as in the table of CONTRIBUTING.md. When merges queue up,
  GitHub runs only the newest waiting run, and the largest bump since the last tag wins. Without a tag the base is the
  version of `apps/xpd/pubspec.yaml` (0.0.1) and only the pushed commit decides. Pre-release tags (`v1.0.0-rc.1`)
  are never a base. The build number is the number of commits up to the released one (`git rev-list --count`), so
  it only grows on `main`.
- **Build** (jobs `bundles`, `arm64`, `docker`). `dart run tool/release_version.dart apply <version> <build>` writes
  the version into the build checkout only: the `version` of `apps/xpd` and `apps/xp`, `<version>+<build>` in
  `apps/xp_desktop` (the app's `CFBundleShortVersionString` and `CFBundleVersion`), and the `packageVersion`
  constants that `xpd --version` and `xp --version` print. The pubspecs in git stay at 0.0.1. Then it builds the
  Linux targets (`bundles.sh` checks that `xpd` and `xp` print the version), runs `smoke_bundle.sh` and the
  `install.sh` test, runs the arm64 bundles on an arm64 runner, builds the Docker image, tests that it answers
  `/health` and prints the version, and pushes it to `ghcr.io/abdurahmanalmehdi/xpath:<version>` for `linux/amd64`
  and `linux/arm64` (and `latest` for a release that is not a pre-release).
- **Release** (job `release`). `gh release create` tags the commit `v<version>` through the API (nothing is pushed)
  and publishes the GitHub Release with generated notes and the assets. Every version before 1.0, and every version
  with a `-`, is a pre-release. A run again for a commit that has its release replaces the assets.
- **DMG** (job `dmg`). On a public repository with the signing secrets below, a GitHub-hosted macOS runner writes the
  version the same way, runs `tool/release/build_mac.sh --developer-id --dmg --notarize --upload v<version>` and
  uploads the macOS archives (`xpath-macos-arm64.tar.gz`, `xp-macos-arm64.tar.gz` and their `.sha256`) to the same
  release. Without the secrets it skips itself with a notice; on a private repository it does not run, and the
  macOS archives come from a Mac: `dart run tool/release_version.dart apply <version> <build>`,
  `tool/release/bundles.sh --upload v<version>`, then `git checkout -- apps` to drop the version again.
- **By hand.** A tag `vX.Y.Z` pushed by hand releases that version (1.0 is tagged by hand). Actions ▸ release ▸ Run
  workflow on `main` runs again for its HEAD, optionally with the version to release. A release never comes from
  another branch.

**Signing secrets.** The `dmg` job reads five repository secrets and never prints them. It imports the certificate
into a keychain of its own in the runner's temporary folder, writes the API key there (mode 0600), and deletes the
keychain and both files at the end, also when a step failed. Set each with `gh secret set <name>`, which reads the
value from stdin, or under Settings ▸ Secrets and variables ▸ Actions:

| Secret | What it holds | How to make it |
|---|---|---|
| `MAC_DEVELOPER_ID_P12_BASE64` | The "Developer ID Application: … (AFBD5TBR5U)" certificate and its private key, a `.p12`, in base64. | Create it in Xcode ▸ Settings ▸ Accounts ▸ the team ▸ Manage Certificates… ▸ + ▸ Developer ID Application (the Account Holder only). Export it with its key from Keychain Access ▸ My Certificates as a `.p12` with a password: `base64 -i developer-id.p12 \| gh secret set MAC_DEVELOPER_ID_P12_BASE64`. Delete the `.p12` afterwards. |
| `MAC_DEVELOPER_ID_P12_PASSWORD` | The password of that `.p12`. | The one chosen on export. |
| `MAC_NOTARY_KEY_P8_BASE64` | An App Store Connect API key (`AuthKey_<key id>.p8`) in base64, for `notarytool`. | App Store Connect ▸ Users and Access ▸ Integrations ▸ App Store Connect API ▸ Team Keys ▸ +, access Developer. The `.p8` downloads once: `base64 -i AuthKey_<key id>.p8 \| gh secret set MAC_NOTARY_KEY_P8_BASE64`. |
| `MAC_NOTARY_KEY_ID` | The key ID of that key. | Shown in its row. |
| `MAC_NOTARY_ISSUER_ID` | The issuer ID of the team's keys. | Shown above the list of keys. |

**Linux install.** `tool/release/linux/install.sh` is served at `https://xpath.abdurahman.ly/install` (ADR 0005):

```sh
curl -fsSL https://xpath.abdurahman.ly/install | sh                  # engine and CLI, xpd user service
curl -fsSL https://xpath.abdurahman.ly/install | sh -s -- --runner   # a runner machine: pair it afterwards
```

It downloads `xpath-linux-<arch>.tar.gz` of the latest release (`--version` for another) from GitHub Releases and
refuses it when the SHA-256 does not match its `.sha256` (GitHub's latest release is never a pre-release, so before 1.0
it needs `--version`); `--archive` installs a local archive or unpacked folder
instead, and the `install.sh` inside an unpacked release folder installs that folder. The bundles go to
`<prefix>/lib/xpath/{xpd,xp}` (`--prefix`, default `~/.local`) and `<prefix>/bin/xpd` and `xp` link to them. They
are copied beside the old ones and must start (`--version`, so a wrong architecture or C library stops the install)
before they replace them, so running it again updates in place. With a systemd user session it then runs
`xpd install-service` (the `xpd.service` user unit of Running as a service) and restarts the service when it was
installed already; without one it says how to start the engine. The unit it writes has no master key credential, so
the engine keeps a 0600 `master.key` in its data directory (D-07); for a systemd credential run `xpd install-service
--master-key-credential <file>` yourself before the first secret is stored. `--runner` prints `xp runner pair` and
`xp runner install-service`, which writes `xp-runner.service` once the runner is paired. `--no-service` installs the
files only. Each option has an environment variable (`XPATH_VERSION`, `XPATH_PREFIX`, `XPATH_ARCHIVE`,
`XPATH_RUNNER=1`, `XPATH_NO_SERVICE=1`); `XPATH_RELEASES_URL` replaces the GitHub Releases URL.
`tool/release/linux/install_test.sh` tests it with no network against the archive of the machine in
`build/release/assets`, in a throwaway `HOME` and prefix: an install, an update from the unpacked folder, a download
from `file://` URLs with and without a version, a wrong SHA-256, a wrong version and the runner mode; on Linux also
the service step against a fake `systemctl` and `loginctl` (the unit written, `enable --now`, the restart on update)
and `--with-android` against a fake `apt-get`, `sudo`, `dpkg-query` and `sdkmanager`.

**Which versions work together** (runners follow their engine; the app and the CLI need the same API version):
[docs/guide/install.md](../guide/install.md#which-versions-work-together).

**A Linux runner, with Android.** `install.sh --runner --with-android` (Debian or Ubuntu) also installs a JDK 17, git,
ssh, curl, unzip, xz, zip and perl with `apt-get`, the Android command-line tools (pinned by version and SHA-256),
the licences, one platform and one build-tools, into `--android-sdk <dir>` (default `~/Android/Sdk`, where Flutter
looks). It ends with the next steps: `xp runner doctor`, the pairing command, `xp runner install-service`.

**Docker.** The `Dockerfile` copies the Linux bundles of `build/release/bundles` (run `bundles.sh` first; `buildx`
picks the bundle of each platform) into a `debian:trixie-slim` image with `git`, `ssh` and `curl`, but not `unzip`,
which the Flutter SDK download needs, so the engine's own runner offers no `flutter` and builds go to runners. It runs `xpd serve --host 0.0.0.0 --port 7480` as the user `xpath` (uid 10001), keeps its
data (database, `master.key`) in the volume `/data` (`XPATH_DATA_DIR`) and checks `/health` every 30 s.

```sh
tool/release/bundles.sh && docker build -t xpath .
docker run -d --name xpath -p 127.0.0.1:7480:7480 -v xpath-data:/data xpath
docker exec xpath xpd token create --name laptop --kind cli
```

**The runner image.** `Dockerfile.runner` makes `ghcr.io/abdurahmanalmehdi/xpath-runner`, a runner that offers
`android` and `flutter` out of the box (amd64 only): it is built by `install.sh --runner --with-android` from the
release archive, and the release workflow checks `xp runner doctor` in it before it pushes it. How to run it:
[docs/guide/runners.md](../guide/runners.md#the-runner-image).

**The Mac app (local install, Phase 18b).** `tool/release/build_mac.sh` builds `dist/XPath.app` (gitignored) for
this Mac: it runs `bundles.sh` for the Mac's target and the Linux runner targets (`--reuse-bundles` takes the ones in
`build/release`), `flutter build macos --release`, copies the `xpd` and `xp` bundles (`bin/`, `lib/`) into
`Contents/Helpers/xpd` and `Contents/Helpers/xp` (the LaunchAgent plist runs `Contents/Helpers/xpd/bin/xpd`, the app
links `Contents/Helpers/xp/bin/xp`) and the runner archives into `Contents/Resources/runners` (Helpers may hold only
code; the engine looks there when it runs from the app). It then signs every Mach-O inside, deepest first, then the
frameworks, then the app with `Release.entitlements`, all with the Hardened Runtime (`--options runtime`) and
`--timestamp=none`, verifies with `codesign --verify --deep --strict` and runs the signed helpers' `--version`. The
helpers are signed with `apps/xp_desktop/macos/Runner/Helpers.entitlements`: the Dart AOT runtime maps its snapshot
as executable memory, and the Hardened Runtime kills it at start (exit 137) without
`com.apple.security.cs.allow-unsigned-executable-memory`. `libsqlite3` needs nothing: it is signed by the same team,
so library validation passes. `spctl` rejects the app (Gatekeeper accepts only Developer ID outside the App Store),
which does not matter for a build that never carried a quarantine flag. The identity is `$XPATH_SIGN_IDENTITY`, by default the owner's Apple Development certificate (SHA-1
`3B9E9C2FB4D94EFC7AC367C68CF1FC077EBB799F`, team AFBD5TBR5U); a `codesign` that waits more than 60 s (a Keychain
dialog) is stopped. `--install` then quits a running XPath (SIGTERM, no Apple Event), replaces
`/Applications/XPath.app` and makes LaunchServices forget the build-folder copies
(`apps/xp_desktop/build/macos/Build/Products/*/XPath.app`, `dist/XPath.app`; `lsregister -u`) and register the
installed one (`lsregister -f`): they share the bundle id, so macOS could otherwise open a Debug build, whose
LaunchAgent points at a bundle without `xpd` (launchd `EX_CONFIG`). Nothing else: it does not open the app, register
the LaunchAgent or link `xp` (onboarding or Settings ▸ Command line tool does). A running
engine keeps the old `xpd` until it restarts (`launchctl kickstart -k gui/$(id -u)/ly.abdurahman.xpath.xpd`). The
macOS 26 `.icon` (Icon Composer) is manual; the app uses `docs/design/brand/macos/AppIcon.appiconset`.

**The Mac download (DMG).** The same script builds what the release workflow publishes. The app's version
(`CFBundleShortVersionString`) and the bundled `xpd` and `xp` must all print the version of `apps/xpd/pubspec.yaml`
(`dart run tool/release_version.dart apply <version> <build>` writes it), and the script checks that before and
after the build:

- `--developer-id` signs with a "Developer ID Application: … (AFBD5TBR5U)" identity instead (the team is
  `$XPATH_TEAM_ID`), with a secure timestamp (`--timestamp`, which needs the network) and the Hardened Runtime. It
  is the one such identity in the keychain, or the one `$XPATH_SIGN_IDENTITY` names; an Apple Distribution or Apple
  Development identity is refused. Without one it stops before building and says how to create it: Xcode ▸
  Settings ▸ Accounts ▸ the team ▸ Manage Certificates… ▸ + ▸ Developer ID Application (only the Account Holder can).
- `--dmg` builds `dist/XPath-<version>.dmg` (the app and a link to `/Applications`), signs it with the same identity,
  mounts it and checks the signed app and the link inside. Without `--developer-id` it is signed with Apple
  Development and says that it is for this Mac only, not for distribution.
- `--notarize` (needs `--developer-id`) submits the app to Apple's notary service with
  `xcrun notarytool submit --wait` and staples it, then the DMG (with `--dmg`) and staples it too, and runs
  `spctl -a -vv -t install` on the DMG, which must report "source=Notarized Developer ID". The credentials are a
  `notarytool store-credentials` keychain profile in `$XPATH_NOTARY_PROFILE`, or an App Store Connect API key:
  `$XPATH_NOTARY_KEY` (the `.p8` file), `$XPATH_NOTARY_KEY_ID` and `$XPATH_NOTARY_ISSUER`. A rejected submission
  prints its log.
- `--upload v<version>` (needs `--dmg` and `--notarize`) attaches the DMG to the existing GitHub Release
  (`gh release upload --clobber`); the tag must be `v<version>`.

```sh
tool/release/build_mac.sh --reuse-bundles --dmg                    # local DMG, Apple Development
XPATH_NOTARY_PROFILE=xpath tool/release/build_mac.sh --developer-id --dmg --notarize
```

**The engine under the app's LaunchAgent.** The plist sets `XPATH_LAUNCHD=1`. `xpd serve` then writes its output,
each line stamped with the UTC time, to `<data dir>/service-logs/xpd.log` (moved to `xpd.log.1` past 10 MB at a
start). Whoever starts it, `xpd serve` puts the tool folders that exist and are missing from its `PATH` in front of
it: `~/.shorebird/bin`, `~/.pub-cache/bin`, `~/fvm/default/bin`, `/opt/homebrew/bin`, `/usr/local/bin` (a plist
cannot name the home folder). The jobs, the tool probes and every program the engine runs get that `PATH`.
