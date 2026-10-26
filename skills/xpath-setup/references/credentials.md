# Credential kinds

Credentials are the engine's and have names (ADR 0013). The user adds a credential once and then
assigns it to the flavors that use it, of any project: one App Store Connect key can serve `dev`
and `prod`, and two Shorebird keys are told apart by name. A flavor uses at most one credential of
each kind. Never collect these values in the chat.

**In the XPath app:** **Credentials** ▸ **Add credential…**: a **Name**, the **Kind**, the fields,
**Check and save**. A `.p8` key, a service account or a keystore can be read from a file. Then,
under **Flavors** (or by clicking a flavor's credentials on the project overview), **Manage…** a
flavor ▸ **Assign…** a credential of each kind, or **Add new…**; **Use for** **This flavor** or
**Every flavor of** the app; flavors that already have one of that kind keep it unless **Replace
existing** is ticked.

**In the user's own terminal** (`xp` never takes a secret as an argument: it asks without showing
what is typed, or reads standard input with the `--*-stdin` flag; key files are read by path):

```sh
xp credentials add --kind asc_key --name "Personal Apple Dev Account" \
  --key-id ABC123DEF4 --issuer-id <issuer id> --p8 ~/keys/AuthKey_ABC123DEF4.p8
xp credentials add --kind apple_id --name "Upload Apple ID" --apple-id dev@example.com   # asks the password
xp credentials add --kind play_sa --name "Play publisher" --service-account ~/keys/play.json
xp credentials add --kind keystore --name "Upload keystore" --keystore upload.jks --key-alias upload
printf %s "$SHOREBIRD_TOKEN" | xp credentials add --kind shorebird --name "Studio Shorebird" --token-stdin
xp credentials assign "Personal Apple Dev Account" --project acme/shop --all-flavors
xp credentials assign "Studio Shorebird" --project acme/shop --flavor prod
xp credentials list                      # names, kinds, status, used by N flavors
xp credentials show "Studio Shorebird"   # and where it is used, with each assignment's check
xp credentials rename "Studio Shorebird" "Mataa Shorebird"
xp credentials replace "Play publisher" --service-account ~/keys/play-new.json   # same name, new secret
xp credentials verify "Personal Apple Dev Account"
xp credentials unassign "Studio Shorebird" --project acme/shop --flavor prod
xp credentials remove "Upload keystore"            # refused while flavors use it; --force unassigns first
```

A credential is its id (`crd_...`) or its name in any case. Only `app` and `cli` tokens change
credentials; an MCP client can only list them (`list_credentials`).

The engine checks a credential with the place it is for before it keeps it. A refusal answers
`422 credential_rejected` with the reason and a fix, and stores nothing (a replaced secret stays).
The API is `POST /credentials`, `PATCH`/`PUT`/`DELETE /credentials/{id}`,
`POST /credentials/{id}/verify` and `PUT`/`DELETE /projects/{id}/flavors/{flavor}/credentials/{kind}`;
the schemas are `CreateCredentialRequest` and its siblings in `packages/xp_api/openapi.yaml`. The old
`PUT /projects/{id}/credentials` still works (deprecated): it creates a named credential for the
flavor.

| Kind | App label | Fields (API name) | `xp credentials add` options | Where the user gets it | How XPath checks it |
|---|---|---|---|---|---|
| `asc_key` | App Store Connect API key | Key ID (`keyId`), Issuer ID (`issuerId`), Private key (`privateKey`, the `.p8` text), `keyKind` (`team` default, or `individual`) | `--key-id`, `--issuer-id`, `--p8 <file>`, `--key-kind` | App Store Connect ▸ Users and Access ▸ Integrations ▸ App Store Connect API. App Manager access is enough for uploads and review status. | `GET /v1/apps?limit=1` with a signed token (a `401` is an expired or revoked key); for each flavor, the app with its bundle id |
| `apple_id` | Apple ID | Apple ID (`appleId`), App-specific password (`password`, shaped `abcd-efgh-ijkl-mnop`) | `--apple-id`; the password asked, or `--password-stdin` | Only to upload with altool instead of an API key. account.apple.com ▸ Sign-In and Security ▸ App-Specific Passwords. Not the Apple ID's own password. | `xcrun altool --list-providers`; a password of another shape is refused unasked |
| `apple_distribution` | Apple Distribution identity | Private key (`privateKey`, PEM), Certificate (`certificate`, a `.cer` or PEM) | `--private-key <file>`, `--certificate <file>`; or `--create --project <p> --flavor <f>`, which has the engine create one with the flavor's `asc_key` and assign it | Only for iOS builds on a Linux runner (ADR 0014). `--create` needs no Mac; Apple allows a team three distribution certificates and the engine refuses at the limit, listing them. From a `.p12`: `openssl pkcs12 -in id.p12 -nodes -nocerts` (key), `-clcerts -nokeys` (certificate). | its certificate's expiry; for each flavor, that App Store Connect lists the certificate (with the flavor's `asc_key`) |
| `play_sa` | Google Play service account | Service account key (`serviceAccount`, the JSON key file) | `--service-account <file>` | Google Cloud console: enable the Google Play Android Developer API, create the service account and a JSON key (IAM ▸ Service accounts ▸ Keys), then invite its email in Play Console ▸ Users and permissions with release rights for the app. | token exchange; for each flavor, the internal track of its application id |
| `firebase_sa` | Firebase service account | Service account key (`serviceAccount`, the JSON key file) | `--service-account <file>` | A service account with the Firebase App Distribution Admin role in the app's Firebase project. | token exchange with the `cloud-platform` scope |
| `keystore` | Android keystore | Keystore (`keystore`, the file; base64 over the API), Store password (`storePassword`), Key alias (`keyAlias`), Key password (`keyPassword`, the store password unless given) | `--keystore <file>`, `--key-alias`; passwords asked, or `--store-password-stdin` / `--key-password-stdin` | The release `.jks` or `.keystore`. Any size. | `keytool -list` with the store password and the alias (the key password cannot be checked) |
| `shorebird` | Shorebird API key | Token (`token`, `sb_api_...`) | the token asked, or `--token-stdin` | A Shorebird API key; the guide says `shorebird login:ci` prints one. Only for flavors with Shorebird on. Keys that do not start with `sb_api_` are refused (`login:ci` tokens of the old form stopped working on 2026-10-01). | `shorebird account whoami --json` |
| `slack` | Slack webhook | Webhook URL (`webhookUrl`, `https://hooks.slack.com/services/T/B/X`) | the URL asked, or `--webhook-url-stdin` | A Slack incoming webhook for the channel that should hear about releases. | its shape only; no message is sent |

The GitHub token is not a named credential: the engine has one for every project, set in
**Settings** ▸ **GitHub** or with `xpd secrets import-gh`.

## Status

| Status | Meaning |
|---|---|
| `unverified` | never checked |
| `verified` | accepted at the last check |
| `rejected` | refused at the last check (expired, revoked, wrong password, a missing role, an app the key cannot see); a job that needs it fails its `credentials` guard |
| `unreachable` | the check could not be made (no network, a missing tool); says nothing about the credential and only warns |

A credential has its own status (does it authenticate) and each assignment has one (can it reach
that flavor's app); a refusal of either stops that flavor's jobs. **Check now** in the app (or
`xp credentials verify`, `POST /credentials/{id}/verify`) checks the credential and its assignments
again. The engine checks every credential and assignment every 24 hours, and at start if the last
check is older than a day.

## Which steps need which

- `upload.firebase` needs `firebase_sa`; `upload.play` needs `play_sa`; `upload.appStore` needs
  `asc_key` or `apple_id`, assigned to the flavor. Without it a dispatch that plans the step is
  refused.
- `build.android` signs with the flavor's `keystore` when it has one.
- Shorebird steps use the flavor's `shorebird` key when there is one.
- Without a `play_sa` (or with only an `apple_id`), XPath cannot read that store's review status;
  the owner marks it approved or live in the app.
- A `slack` credential assigned to a flavor of a project makes the engine post that project's
  notifications (failed or finished production jobs, approvals, store results, expired
  credentials) to that webhook.
