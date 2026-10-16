# Credential kinds

The user enters credentials in the XPath app: select the project, **Credentials** ▸ **Add
credential…**, pick the **Flavor** and the **Kind**, fill the fields, **Check and save**. A
`.p8` key, a service account or a keystore can be read from a file. Never collect these values in
the chat.

The engine checks a credential with the place it is for before it keeps it. A refusal answers
`422 credential_rejected` with the reason and a fix, and stores nothing (the old credential
stays). The same endpoint is `PUT /projects/{id}/credentials` for scripts the user runs; the
schemas are `AscKeyCredentialRequest` and its siblings in `packages/xp_api/openapi.yaml`.

| Kind | App label | Fields (API name) | Where the user gets it | How XPath checks it |
|---|---|---|---|---|
| `asc_key` | App Store Connect API key | Key ID (`keyId`), Issuer ID (`issuerId`), Private key (`privateKey`, the `.p8` text), `keyKind` (`team` default, or `individual`) | App Store Connect ▸ Users and Access ▸ Integrations ▸ App Store Connect API. App Manager access is enough for uploads and review status. | `GET /v1/apps?limit=1` with a signed token; a `401` is an expired or revoked key |
| `apple_id` | Apple ID | Apple ID (`appleId`), App-specific password (`password`, shaped `abcd-efgh-ijkl-mnop`) | Only to upload with altool instead of an API key. account.apple.com ▸ Sign-In and Security ▸ App-Specific Passwords. Not the Apple ID's own password. | `xcrun altool --list-providers`; a password of another shape is refused unasked |
| `play_sa` | Google Play service account | Service account key (`serviceAccount`, the JSON key file) | Google Cloud console: enable the Google Play Android Developer API, create the service account and a JSON key (IAM ▸ Service accounts ▸ Keys), then invite its email in Play Console ▸ Users and permissions with release rights for the app. | token exchange, then the internal track of the flavor's application id |
| `firebase_sa` | Firebase service account | Service account key (`serviceAccount`, the JSON key file) | A service account with the Firebase App Distribution Admin role in the app's Firebase project. | token exchange with the `cloud-platform` scope |
| `keystore` | Android keystore | Keystore (`keystore`, the file; base64 over the API), Store password (`storePassword`), Key alias (`keyAlias`), Key password (`keyPassword`, the store password unless given) | The release `.jks` or `.keystore`. Any size. | `keytool -list` with the store password and the alias (the key password cannot be checked) |
| `shorebird` | Shorebird API key | Token (`token`, `sb_api_...`) | A Shorebird API key; the guide says `shorebird login:ci` prints one. Only for flavors with Shorebird on. Keys that do not start with `sb_api_` are refused (`login:ci` tokens of the old form stopped working on 2026-10-01). | `shorebird account whoami --json` |
| `github` | GitHub token | Token (`token`) | The same token as Settings ▸ GitHub; the engine has one GitHub token for every project, so it is usually set there once. | `GET /user` |
| `slack` | Slack webhook | Webhook URL (`webhookUrl`, `https://hooks.slack.com/services/T/B/X`) | A Slack incoming webhook for the channel that should hear about releases. | its shape only; no message is sent |

Every request also names `flavor` and, for an app that is not at the root, `app` (its path).

## Status

| Status | Meaning |
|---|---|
| `unverified` | never checked |
| `verified` | accepted at the last check |
| `rejected` | refused at the last check (expired, revoked, wrong password, a missing role); a job that needs it fails its `credentials` guard |
| `unreachable` | the check could not be made (no network, a missing tool); says nothing about the credential and only warns |

**Check now** in the app (or `POST /projects/{id}/credentials/{credentialId}/verify`) checks again.
The engine checks every credential every 24 hours, and at start if the last check is older than a
day.

## Which steps need which

- `upload.firebase` needs `firebase_sa`; `upload.play` needs `play_sa`; `upload.appStore` needs
  `asc_key` or `apple_id`. Without it a dispatch that plans the step is refused.
- `build.android` signs with the flavor's `keystore` when it has one.
- Shorebird steps use the `shorebird` key when there is one.
- Without a `play_sa` (or with only an `apple_id`), XPath cannot read that store's review status;
  the owner marks it approved or live in the app.
- A `slack` credential makes the engine post notifications (failed or finished production jobs,
  approvals, store results, expired credentials) to that webhook.
