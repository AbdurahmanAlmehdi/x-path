# Credentials

Credentials are the keys XPath signs and uploads with: App Store Connect and Google Play keys, the
Android keystore, Shorebird and the rest. They belong to the engine and have names, so you add one
once and assign it to every flavor that uses it, of any project. The secrets stay on the engine
machine.

## Keep secrets out of chat, arguments and logs

- `xp` never takes a secret as an argument. At a terminal it asks without showing what you type;
  otherwise it reads standard input with the kind's `--*-stdin` flag. Key files are read by path.
- Do not paste a secret into a chat with an agent. `xp mcp` can only list credentials; an agent
  tells you where to enter one, and you enter it in the app or in your own terminal.
- The engine stores secrets in the login Keychain on macOS (services starting with
  `ly.abdurahman.xpath`, large ones such as keystores in `secrets.enc` in the data directory) and
  in an encrypted `secrets.enc` on Linux.
- No API answer, event or log carries a secret. The engine replaces known secret values with `***`
  in job logs, and passwords reach the tools it runs through the environment, never the arguments.

## The credential kinds

| Kind | In the app | What you need | Where to get it |
|---|---|---|---|
| `asc_key` | App Store Connect API key | Key ID, Issuer ID, the `.p8` file | App Store Connect ▸ Users and Access ▸ Integrations ▸ App Store Connect API. App Manager access is enough. |
| `apple_id` | Apple ID | Apple ID, app-specific password | Only to upload with `altool` instead of a key: account.apple.com ▸ Sign-In and Security ▸ App-Specific Passwords. |
| `play_sa` | Google Play service account | The JSON key file | Google Cloud console: enable the Google Play Android Developer API, make the service account and a key, then invite it in Play Console with release rights. |
| `firebase_sa` | Firebase service account | The JSON key file | A service account with the Firebase App Distribution Admin role in the app's Firebase project. |
| `keystore` | Android keystore | The `.jks` or `.keystore`, store password, key alias, key password | Your release keystore, of any size. The key password is the store password unless you give one. |
| `dart_defines` | Dart define file | The file you pass to `--dart-define-from-file`: a flat JSON object or `KEY=value` lines | Your own file, for apps that keep it outside git. One per flavor. The engine checks only that Flutter can read it. |
| `shorebird` | Shorebird API key | A key that starts with `sb_api_` | `shorebird login:ci` prints one. Only for flavors with Shorebird on. |
| `slack` | Slack webhook | The webhook URL | A Slack incoming webhook for the channel that should hear about releases. |

## Add a credential in the app

Open **Credentials** in the sidebar and press **Add credential…**. Give it a **Name** you will
recognise, such as "Personal Apple Dev Account", pick the **Kind**, fill in the fields and press
**Check and save**. A `.p8` key, a service account, a keystore or a dart-define file can be read from a file. The engine
checks the credential with the service it is for and stores nothing if the check fails.

Each row has **Rename…**, **Replace secret…** (the name and the flavors that use it stay), **Check
now** and **Delete…**. Deleting a credential that flavors use lists them and asks first.

## Assign credentials to flavors

A flavor uses at most one credential of each kind, and one credential can serve many flavors. Under
**Flavors** on the Credentials page, press **Manage…** on a flavor, or click a flavor's credentials
on the project overview. For each kind, **Assign…** picks an existing credential, or **Add new…**
makes one. **Use for** chooses **This flavor** or **Every flavor of** the app; flavors that already
have a credential of that kind keep it unless you tick **Replace existing**.

## Use xp credentials

```sh
xp credentials add --kind asc_key --name "Personal Apple Dev Account" \
  --key-id ABC123DEF4 --issuer-id <issuer id> --p8 ~/keys/AuthKey_ABC123DEF4.p8
xp credentials add --kind apple_id --name "Upload Apple ID" --apple-id dev@example.com
xp credentials add --kind play_sa --name "Play publisher" --service-account ~/keys/play.json
xp credentials add --kind keystore --name "Upload keystore" --keystore upload.jks --key-alias upload
xp credentials add --kind dart_defines --name "Mataa prod defines" --dart-defines env/prod.json
printf %s "$SHOREBIRD_TOKEN" | xp credentials add --kind shorebird --name "Studio Shorebird" --token-stdin
xp credentials assign "Personal Apple Dev Account" --project acme/app --all-flavors
xp credentials assign "Studio Shorebird" --project acme/app --flavor prod
xp credentials list
xp credentials show "Studio Shorebird"
```

- `firebase_sa` takes `--service-account` like `play_sa`; `asc_key` also takes `--key-kind team` or
  `individual`. `apple_id`, `keystore` and `slack` ask for their secrets, or read them with
  `--password-stdin`, `--store-password-stdin`, `--key-password-stdin` or `--webhook-url-stdin`, one
  per command.
- A credential is its id (`crd_...`) or its name in any case.
- `assign --all-flavors` keeps a flavor's other credential of the kind unless you add `--replace`.
  Add `--app <path>` for an app below the root.
- `rename <c> <new name>`, `replace <c>` with the options of its kind, `unassign <c> --project <p>
  --flavor <f>` and `remove <c>` do the rest. `remove` refuses a credential that flavors use; `--force`
  unassigns it first.
- Only `app` and `cli` tokens change credentials.

## The GitHub token

The GitHub token is not a named credential: the engine has one for every GitHub project, and
`--kind github` is refused. Set it in **Settings** ▸ **GitHub**: **Import from GitHub CLI** runs
`gh auth token` on the engine machine (log in with `gh auth login` first), or paste a token and press
**Check and save**. From a terminal on the engine machine:

```sh
xpd secrets import-gh
```

It prints only `Imported the GitHub token.` The token needs read access to your repositories, and
write access to contents and pull requests for the release branch, tag and pull request merge.

## Checks

| Status | Meaning |
|---|---|
| `verified` | Accepted at the last check. The app shows **Verified**. |
| `rejected` | Refused: expired, revoked, a wrong password, a missing role, or an app the key cannot see. The app shows **Rejected**. |
| `unverified` | Never checked. The app shows **Not checked**. |
| `unreachable` | The check could not be made (no network, a missing tool). It says nothing about the credential and only warns. |

A credential has its own status (does it authenticate), and each assignment has one (can it reach
that flavor's app: an App Store Connect key must see the bundle id, a Play service account the
package). The engine checks every credential and assignment every 24 hours, at start when the last
check is older than a day, and before each build. Only a rejected credential or assignment stops a
job, at its `credentials` guard, before anything is built. **Check now**, or `xp credentials verify
<c>`, checks again; `verify` exits 1 when a check refuses it.

## Which steps need which

- `upload.firebase` needs `firebase_sa`, `upload.play` needs `play_sa`, and `upload.appStore` needs
  `asc_key` or `apple_id`, assigned to the flavor. Without it a dispatch that plans the step is
  refused.
- `build.android` signs with the flavor's `keystore` when it has one. Shorebird steps use the
  flavor's `shorebird` key.
- `build.android`, `build.ios`, `shorebird.release` and `shorebird.patch` use the flavor's
  `dart_defines` file when the workflow names no `dartDefineFile`; a file the workflow names wins.
  The file is written with mode 0600 to the job's secret folder, on the engine or on the runner that
  has the job, and deleted when the job ends. `record.manifest` records its SHA-256 and
  `build.verifyCompiledConfig` reads its `keys` from it.
- Every value of a `dart_defines` file of 6 characters or more is hidden in all job output, wherever
  it appears. A value like `MODE=release` hides that word too, so keep such settings out of the file.
- Without a `play_sa`, or with only an `apple_id`, XPath cannot read that store's review status; you
  mark it approved or live in the app ([Releases](releases.md)).
- A `slack` webhook assigned to a flavor makes the engine post the project's notifications there:
  failed or finished production jobs, approvals, store results and expired credentials.
