# Stores and credentials

App Store Connect, Google Play, Firebase App Distribution, the Shorebird CLI and the credentials, with the fake stores the tests use. The user guide is in [docs/guide](../guide/quickstart.md); this is the reference.

## App Store Connect and Apple

Phase 10a adds the Apple side of the stores (D-14): the App Store Connect REST client, the iTunes lookup,
`upload.appStore` and the two guard checks that ask Apple. Interfaces and the parser are in
`packages/xp_engine/lib/src/stores/apple`, the HTTP adapters in `packages/xp_adapters/lib/src/stores/apple`.
Nothing here calls Apple in a test: the adapters run against `tool/e2e/fake_stores/asc` (below) and altool is
only ever faked or read from captured output.

- **The ASC API key is one secret.** The `secret_key` of an `asc_key` credential names a secret in the
  secret store whose value is JSON (`AscKey.toSecret`):
  `{"keyId": "ABC123DEF4", "issuerId": "<uuid>", "keyKind": "team" | "individual", "privateKey": "<.p8 text>"}`.
  `keyKind` defaults to `team`. The credential endpoints (see Credentials) write it. An Apple ID flavor has an
  `apple_id` credential instead, and no REST access.
- **Tokens** (`AscTokenProvider`) are ES256 JWTs signed in pure Dart (`pointycastle`, RFC 6979 nonces, raw
  `r || s`): header `alg`, `kid`, `typ`; claims `iat`, `exp` (15 minutes, Apple's maximum is 20), `aud:
  appstoreconnect-v1`, and `iss` for a team key or `sub: user` with no `iss` for an individual key. One token is
  kept until two minutes before it expires. The signer is checked against the RFC 6979 test vector, against
  `openssl dgst -verify` (`process` tag), and the fake server verifies the tokens it receives like Apple does.
- **The REST client** (`HttpAppStoreConnect`) reads apps by bundle id, builds (by app, marketing version and build
  number, with their processing state), App Store versions with **`appVersionState`** (`appStoreState` is
  deprecated and never read), review submissions (create with the version, submit, read) and phased releases
  (read, pause, resume, complete). Lists follow `links.next`, but only to the host of the base URL: the token is
  never sent anywhere else. Errors are typed by status (`AscAuthException` 401, `AscForbiddenException` 403,
  `AscNotFoundException` 404, `AscConflictException` 409, `AscValidationException` 422,
  `AscRateLimitedException` 429, `AscServerException` otherwise), each with Apple's message and code and a fix.
  A `429` is waited out when Apple's `Retry-After` (else 1 s, 2 s, ... backoff) is at most 30 s, up to three
  attempts; a longer wait (the hourly quota is spent) is thrown at once with `retryAfter`, because a job must not
  sleep for an hour. A `5xx` on a read is retried the same way. The quota left comes from `X-Rate-Limit` after
  each answer (`rateLimit`).
- **The iTunes lookup** (`HttpItunesLookup`) asks `itunes.apple.com/lookup` for the app's own storefront
  (`store_country` of the profile) with a changing `_` parameter to get past Apple's CDN. It needs no key, so it
  is the only Apple source for an Apple ID flavor. It is "live somewhere", not precise.
- **`AppStoreTrains`** (the `appStoreTrain` guard check, ITMS-90186) takes the live version from the iTunes lookup
  and, with an API key, from `appVersionState` too; the versions that are approved and not live yet
  (`PENDING_DEVELOPER_RELEASE`, `PENDING_APPLE_RELEASE`, `PROCESSING_FOR_APP_STORE`, ...) are the closed trains.
  **`StoreBuildNumbers`** (the `buildNumberReuse` guard check) is every build number App Store Connect has for the
  app, expired builds included; it needs an API key, and answers for iOS only (Google Play's half is in the next section).
  `SqliteAscCredentialSource` finds the key through the `asc_key` credential assigned to the flavor with the bundle id.
  `xpd serve` wires all of it in `apps/xpd/lib/src/stores/apple_stores.dart`; the `appStoreTrain` check and the
  step are registered there, and `buildNumberReuse` over both stores' numbers in `store_guard_checks.dart`.
- **`upload.appStore`** (side effect, always on the engine, D-09; ADR 0014). With an API key (`asc_key`) it
  uploads through the App Store Connect build-upload API on any engine, a Linux or Docker one included:
  `POST /v1/buildUploads`, `POST /v1/buildUploadFiles`, a `PUT` of each part of the IPA to the address Apple
  names (without the token, and never quoted in an error, since the address is signed), `PATCH` the file
  uploaded with its MD5, then it polls the upload until App Store Connect accepts or refuses it, for at most
  30 minutes. A refusal is told the way altool's are (`AltoolOutput.ofUploadErrors`, with the same fixes);
  an upload still undecided fails with "resume the step later", and the resumed step finds the build if Apple
  made one. The IPA must still have the SHA-256 recorded for it. With an Apple ID it runs, on macOS only,
  `xcrun altool --upload-package <ipa> --type ios --apple-id <id> --bundle-id <id> --bundle-version <build>
  --bundle-short-version-string <version> -u <apple id> -p @env:XPATH_ASC_APP_PASSWORD`, so the app-specific
  password is in the environment of altool only, masked in the log, never in `ps`. Only that case needs
  `ios-sign`.
- **altool's output decides, not its exit code** (`AltoolOutput`, Apple ID uploads). altool can exit 0 after Apple rejected the
  build (a closed version train, for example). The step fails on any line with `ERROR:`, `ERROR ITMS-`, `*** Error:`,
  `validation failed`, `upload failed`, `VALIDATION_ERROR`, `failed to upload|validate package` or `unable to
  authenticate`, and tells the first three. Known codes get a fix: 90186 and 90062 (bump the version), 90189
  (allocate a new build number), authentication. A success line (`UPLOAD SUCCEEDED`, `No errors uploading`,
  `upload complete`) and altool's delivery UUID are recorded when present; an output with neither errors nor
  success is a success that is not `confirmed`, as in the reference scripts. The fixtures are in
  `packages/xp_engine/test/src/stores/apple/fixtures` (its README says which are captured from altool 27.0.5
  and which are reconstructed).
- **`alreadyDone`** asks whether App Store Connect has the build: the builds API for an API key (by app,
  version and build number); for an Apple ID `altool --build-status`, which counts only if its output names the
  build number. When it cannot ask, the step runs, and Apple refuses a build number it has seen.

### Fake App Store Connect

`tool/e2e/fake_stores/asc` is the workspace package `xp_fake_asc`: a `dart:io` server on a loopback port
(`FakeAscServer.start`) with apps, builds, App Store versions, review submissions, phased releases and the iTunes
lookup in memory, in JSON:API shape. It verifies every bearer token (signature with the registered public key,
`kid`, `aud`, `exp`, at most 20 minutes, `iss` or `sub` per key kind) and says what is wrong in the 401. Tests fill
it with `addApp`, `addBuild`, `addVersion`, `addPhasedRelease` and `addItunes`, make it misbehave with
`failNext` and `rateLimitNext`, and read `requests`. The test key (`fakeAscTestKey`, made with `openssl`) signs
nothing real. `release_e2e.sh` (Phases 11 and 12b) will reuse it. The layer rules let `xp_adapters` and `xpd` use it
(as a dev dependency).

## Google Play

Phase 10b adds the Google Play side of the stores (D-15): the Developer API client, `upload.play`, the Play half
of the `buildNumberReuse` guard check and the `playTargetSdk` guard check. Interfaces are in
`packages/xp_engine/lib/src/stores/play`, the HTTP adapters in `packages/xp_adapters/lib/src/stores/play`. Nothing
here calls Google in a test: the adapters run against `tool/e2e/fake_stores/play` (below).

- **The service account is one secret.** The `secret_key` of a `play_sa` credential names a secret in the
  secret store whose value is the JSON key file Google Cloud gives out, as it is (`PlayServiceAccount`): it needs
  `client_email` and `private_key`, uses `token_uri` (default `https://oauth2.googleapis.com/token`) and
  `private_key_id`, and ignores the rest. The credential endpoints (see Credentials) write it. A flavor with no
  `play_sa` credential assigned has no service account: XPath cannot upload for it, `upload.play` fails with "upload the
  bundle by hand", and the build numbers of Play are unknown (the endpoint behind "Play: live" is Phase 12b, the desktop's button Phase 16b).
  Setting up the account: enable the Google Play Android Developer API in the Cloud project, create the service
  account and a JSON key, and invite its email in the Play Console (Users and permissions) with permission to
  release the app.
- **Auth is the OAuth2 JWT bearer flow, in pure Dart** (`PlayTokenProvider`, `Rs256Signer`). The assertion is an
  RS256 JWT (header `alg`, `typ`, `kid`; claims `iss` the service account email, `scope`
  `https://www.googleapis.com/auth/androidpublisher`, `aud` the `token_uri`, `iat`, `exp` 30 minutes later; Google's
  maximum is an hour) posted as `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer`. The access token is kept
  until two minutes before it expires; calls that overlap share one request; a `401` drops the token and the call
  is tried once more with a new one. **Why `pointycastle` and not `googleapis_auth`:** `googleapis_auth` hardcodes
  the token endpoint, so the fake server could not stand in for it; the `token_uri` of the key file is the one
  address the flow needs, and the signer is 30 lines on a package already used for ES256 (Phase 10a). The signer is
  checked byte for byte against `openssl dgst -sha256 -sign`, and against `openssl dgst -verify` (`process` tag).
- **The Developer API client** (`HttpGooglePlay`, `package:http`, base URLs of the API and of the upload host
  injectable) does `edits.insert`, `edits.delete`, `edits.bundles.upload` and `list`, `edits.tracks.get` and
  `update`, `edits.commit` and `tracks.releases.list`. Bundles go up with the simple media upload
  (`uploadType=media`), **streamed from the artifact store with a known length**, never held in memory; the stream
  is opened again if the upload has to be repeated. Errors are typed, each with Google's message, reason and a fix:
  `PlayAuthException` (401, or the token endpoint), `PlayForbiddenException` (403: invite the service account),
  `PlayNotFoundException` (404), `PlayVersionCodeUsedException` (a version code seen before),
  `PlayConflictException` (409), `PlayValidationException` (other 4xx), `PlayRateLimitedException` (429),
  `PlayServerException`. A `429` is waited out when `Retry-After` (else 1 s, 2 s, ...) is at most 30 s, up to three
  attempts; a longer wait is thrown at once with `retryAfter`. A `5xx` is retried for reads, track updates and
  deletes; **not for an upload or a commit**, which may have gone through: `alreadyDone` finds out.
- **A review in progress is never cancelled.** `GooglePlay.commitEdit` has no option: it always sends
  `changesInReviewBehavior=ERROR_IF_IN_REVIEW` (`edits.commit` defaults to cancelling the review). When changes
  are in review Google answers `400 FAILED_PRECONDITION` with `CHANGES_ALREADY_IN_REVIEW`, the edit stays valid and
  the review is untouched; the client throws `PlayReviewInProgressException`. The fake server implements both
  behaviors and records the parameter and any cancelled review, so the acceptance test asserts the parameter was
  sent and the review survived (`http_google_play_test.dart`, "while a review is in progress fails without
  cancelling it").
- **`upload.play`** (side effect, always on the engine, D-09) streams the AAB of the job (it must still have the
  SHA-256 recorded for it), opens an edit, uploads, checks that the bundle's version code is the build number of
  the input, sets the release of the track and commits. Input: `artifactName`, `packageName`, `version`
  (`x.y.z+build`, the build is the version code), `serviceAccountSecret`, and optionally `track` (default
  `internal`), `status` (`completed` by default, `inProgress` with a `userFraction` above 0 and below 1, or
  `draft`), `releaseName` and `releaseNotes` (language tag to text). Whatever fails after the edit was opened, the
  edit is deleted, so nothing is left half done. A review in progress fails the step with "Play has a review in
  progress; the release was not committed and the review was not cancelled". The result carries the version code,
  the track and the `releaseLifecycleState` of the new release when Play can say.
- **`alreadyDone`** lists the releases of the track (`tracks.releases.list`: committed releases, at most 20, no edit
  needed, state `DRAFT`, `NOT_SENT_FOR_REVIEW`, `IN_REVIEW`, `APPROVED_NOT_PUBLISHED`, `NOT_APPROVED` or
  `PUBLISHED`) and is done when one holds the version code. Google's `googleapis` Dart package has no
  `tracks.releases.list`, which is one more reason the client is hand-written against the REST shapes in the
  discovery document.
- **Build numbers.** `PlayStoreBuildNumbers` reads every bundle of the app (`edits.bundles.list` in a short edit
  that is deleted again): Play refuses a version code it has seen on any track. It needs a service account and
  covers bundles only (XPath uploads bundles). `CombinedStoreBuildNumbers` asks App Store Connect for the iOS
  bundle id and Play for the Android application id, adds the numbers up and names a store it could not read in
  `StoreBuilds.unreadable`; `buildNumberReuse` then warns instead of passing, but still fails for a number the
  other store has. `xpd serve` composes it in `apps/xpd/lib/src/stores/store_guard_checks.dart`.
- **`playTargetSdk`** compares the `targetSdk` in the Gradle scripts with the level Play asks for. Google publishes
  no API for that policy value, so it is a setting (`ConfiguredPlayRequirements`): the default is **36**, what Play
  has asked of new apps and updates since 2026-08-31 (Android 16). Play raises it every August; set
  `XPD_PLAY_TARGET_SDK` for `xpd serve` (a whole number from 21 to 99; anything else stops the engine at start).

### Fake Google Play

`tool/e2e/fake_stores/play` is the workspace package `xp_fake_play`: a `dart:io` server on a loopback port
(`FakePlayServer.start`) that is both the OAuth2 token endpoint (`/token`) and the Developer API. It verifies the
signed assertion like Google does (RS256 against the public key of the registered account, `iss`, `scope`, `aud`
the token endpoint, `exp`, at most an hour) and says what is wrong in the `invalid_grant`; it issues access tokens
that expire by the fake clock and checks one on every API call. `serviceAccountJson()` makes the key file for the
test account with `token_uri` pointing at the server. It keeps apps, edits, bundles, tracks and releases in memory,
validates what Play validates (the bundle must be an AAB, a version code is used once, a release can only name
uploaded bundles, `userFraction` only with `inProgress`) and answers with Google's error bodies. A commit while a
release is `IN_REVIEW` answers `400 CHANGES_ALREADY_IN_REVIEW` with `ERROR_IF_IN_REVIEW` and cancels the review
without it; `commits` and `FakePlayApp.cancelledReviews` record which. A test AAB is any bytes that start with
`fake-aab versionCode=<n>` (`fakeAab(n)`), because the fake reads the version code from the first line where Play
reads the manifest. Tests fill it with `addApp` and `FakePlayApp.addRelease`, make it misbehave with `failNext`,
`rateLimitNext` and `revokeTokens`, and read `requests`. The test key (made with `openssl genpkey`) signs nothing
real. The layer rules let `xp_adapters` and `xpd` use it (as a dev dependency).

## Firebase, Shorebird CLI and credentials

Phase 10c adds Firebase App Distribution, the last store adapter (`upload.firebase`, D-16), consolidates the Shorebird
CLI access, and gives the engine the credentials every upload needs: saved after the place they are for accepts them,
checked every day, and checked again before a job builds. Interfaces and verifiers are in
`packages/xp_engine/lib/src/{credentials,stores/firebase}`, the HTTP and CLI adapters in
`packages/xp_adapters/lib/src/{credentials,stores/firebase,stores/shorebird,github,sqlite}`, the endpoints in
`apps/xpd/lib/src/api/credentials`. Nothing here calls Google, Apple, Shorebird or GitHub in a test.

### Firebase App Distribution

- **`upload.firebase`** (side effect, always on the engine, D-09) uploads the APK, AAB or IPA of the job (it must still
  have the SHA-256 recorded for it) with the REST API and a service account: no Node and no `firebase` CLI. Input:
  `artifactName`, `appId` (`1:684690133351:android:...`; the project number the API addresses the app by is its
  second part, so there is no separate field), `version` (`x.y.z+build`), `serviceAccountSecret`, and optionally
  `testerEmails`, `groupAliases` and `releaseNotes`. Steps: `POST
  https://firebaseappdistribution.googleapis.com/upload/v1/projects/{number}/apps/{appId}/releases:upload` with the raw
  bytes streamed from the artifact store with a known length (`X-Goog-Upload-Protocol: raw`,
  `X-Goog-Upload-File-Name`); poll the long-running operation every 3 s until it is done (at most 200 polls);
  `releases.patch` with `updateMask=releaseNotes.text`; `releases:distribute`. Firebase reads the version from the
  binary: if it is not the version of the job the step fails and names the release it made.
- **`alreadyDone`** lists the newest 300 releases (`releases.list`, `orderBy=createTime desc`, three pages of 100) and is
  done when one has the build number and version name of the input and, if the input has release notes, the same
  notes. A release with other notes was not finished (the notes and the distribution come after the upload), so the
  step runs again: the upload finds the same release (`RELEASE_UNMODIFIED` or `RELEASE_UPDATED`) and the rest is
  repeated. A failure after the upload says so and names the release. Known limit: the API shows no testers, so a
  release whose distribution failed but whose notes are set counts as done; a deterministic failure there (a group that
  does not exist) needs a new job anyway.
- **The service account** is the JSON key file, as `firebase_sa` (same convention as `play_sa`). The token is the same
  OAuth2 JWT bearer flow as Google Play (`PlayTokenProvider`, now with a `scope`; Firebase asks for
  `https://www.googleapis.com/auth/cloud-platform`), so `HttpFirebaseAppDistribution` reuses it and maps its failures to
  `FirebaseException`s with a fix (`FirebaseAuthException` 401, `FirebaseForbiddenException` 403 with the role to give,
  `FirebaseNotFoundException`, `FirebaseValidationException`, `FirebaseRateLimitedException`,
  `FirebaseServerException`, `FirebaseOperationFailedException`). Retries are as for Play: a `429` is waited out up to
  30 s; a `5xx` is retried for reads, release notes and distribution, **never for the upload**, which may have gone
  through.
- **The Firebase app id is a step input.** The scanner does not read `google-services.json` or `firebase.json` yet, so
  workflows take it as an input (`firebaseAppIds`, by flavor and platform); nothing here guesses it.

### Fake Firebase App Distribution

`tool/e2e/fake_stores/firebase` is the workspace package `xp_fake_firebase`: a `dart:io` server on a loopback port
(`FakeFirebaseServer.start`) that is both the OAuth2 token endpoint and the REST API. It is a package of its own, not
an extension of the Play fake: the two APIs share nothing but Google's token flow, so `xp_fake_firebase` depends on
`xp_fake_play` for exactly that (`AssertionVerifier`, now with a `scope`, the test account and its key) and the layer
rules allow nothing else. It checks the assertion and the access token like Google does, takes `releases:upload`
(raw protocol and file name header required) and answers with an operation that is done after `pollsBeforeDone`
polls, finds the release of the same version name and build (`RELEASE_UNMODIFIED` when the bytes are the same,
`RELEASE_UPDATED` when not), lists releases newest first in pages, patches the notes, and distributes (a group that was
not added with `addApp(groups:)` is a `400`). A test binary is any bytes that start with `fake-apk versionName=1.2.3
versionCode=45` (`fakeBinary`). Tests fill it with `addApp` and `addRelease` and make it misbehave with `failNext`,
`rateLimitNext` and `revokeTokens`.

### The Shorebird CLI

`ShorebirdCli` (`packages/xp_adapters/lib/src/stores/shorebird`) is the one place the CLI is run: always `CI=true`
(no prompts), JSON in, the API key in `SHOREBIRD_TOKEN` and never in the arguments, a time limit, and the documented
envelope `{"status": "success", "data": ...}` read into a result that is either a success or a failure that says
whether the program is missing, too slow or failed. `ShorebirdCliReleases` (`releases list`, Phase 9c) now goes through
it, and so does `ShorebirdCliVerifier`, which checks an API key with `shorebird account whoami --json`. The
documentation shows the command, not the shape of its JSON, so the verifier only needs the envelope and reads `email`
when it is there (the fixtures are reconstructed from the documentation and say so). A key that does not start with
`sb_api_` is refused without asking Shorebird, with the reason that `login:ci` tokens stopped working on 2026-10-01.

### Credentials

Credentials are the engine's, with names (ADR 0013). A **named credential** (the `credential` table) has an id
(`crd_...`, which never changes), a name that is unique regardless of case ("Personal Apple Dev Account", "Mataa Apple
Dev Account"), a kind, its secret, the `account` it belongs to when that is not secret, and the result of its own check
(does it authenticate). Any flavor of any project may use it: a flavor (an app path and a flavor name, `.` and
`default` for an app without flavors) uses **at most one credential of each kind** (`credential_assignment`, only of
the credential's kind), and each assignment keeps the result of its own check (can the credential reach this
flavor's bundle id, package or app). So one Apple key serves the dev and the prod flavor, and two Shorebird keys are
told apart by name. Renaming a credential or giving it a new secret keeps its id and every assignment. The secret is
only in the secret store, under the `secret_key` of the credential (`credential.<id>`; a secret another credential
keeps is not deleted with this one). Identical secrets under two names stay two credentials.

The GitHub token is not a named credential: the engine has one, under `github.token`, set with `PUT /github-token`
(see GitHub). A `slack` webhook is named and assigned per flavor like the others; a notice of a project goes to the
first webhook a flavor of the project uses and no check refused.

What each kind stores and how it is checked:

| Kind | Secret store | Check of the credential (cheap, changes nothing) | Check of an assignment |
|---|---|---|---|
| `asc_key` | JSON `{keyId, issuerId, keyKind, privateKey}` | `GET /v1/apps?limit=1` with a signed token; a `401` is an expired or revoked key | the key sees the app with the flavor's iOS bundle id (`GET /v1/apps?filter[bundleId]=`) |
| `apple_id` | the app-specific password; the Apple ID is the `account` | `xcrun altool --list-providers -u <id> -p @env:XPATH_ASC_APP_PASSWORD`; a password that is not shaped like `abcd-efgh-ijkl-mnop` is refused unasked | the credential's |
| `play_sa` | the JSON key file | token exchange | `tracks.releases.list` of the internal track of the flavor's application id |
| `firebase_sa` | the JSON key file | token exchange with the `cloud-platform` scope | the credential's (the app ids belong to the steps) |
| `keystore` | the bytes; `<key>.storePassword`, `<key>.keyPassword`; the alias is the `account` | `keytool -list -keystore <0600 temp file> -storepass:env XPATH_KEYSTORE_STOREPASS -alias <alias>` | the credential's |
| `shorebird` | the `sb_api_*` key | `shorebird account whoami --json` with `SHOREBIRD_TOKEN` | the credential's |
| `slack` | the webhook URL | its shape only (`https://hooks.slack.com/services/T/B/X`); no message is sent | the credential's |

A check ends `verified`, `rejected` (the place said no: expired, revoked, wrong password, a missing role, an app the
key cannot see) or `unreachable` (no network, a missing tool: it says nothing about the credential). A kind whose
check does not look at the flavor, and a credential its own check did not accept, gives each assignment the
credential's status. Only `rejected` blocks a job. The keytool check proves the store password and the alias;
`keytool` has no check for the key password. The password of an Apple ID and of a keystore reach the program through
the environment, never the arguments, and every secret value is given to the log masker as soon as it arrives.

Only `app` and `cli` tokens change credentials; an `mcp` token reads them (`403 forbidden` otherwise) and a `runner`
token reaches none of these routes (ADR 0011).

| Route | What it does |
|---|---|
| `GET /credentials` | The named credentials by name, each with `usedBy`: the flavors that use it, with the check of each assignment. No secret is ever returned. |
| `POST /credentials` | `{"name": "...", "kind": "asc_key", ...}` with the secret fields of the kind (`CreateCredentialRequest`; `packages/xp_api/openapi.yaml` has one schema per kind). Verifies, then stores the secret and the credential: `201`. No flavor uses it yet. `409 conflict` for a name that is taken in any case; `422 credential_rejected` says why and how to fix it and **stores nothing**; `502 upstream_error` when the check could not be made, also stores nothing. |
| `GET /credentials/{id}` | One credential with `usedBy`. |
| `PATCH /credentials/{id}` | `{"name": "..."}`: renames it; `409` for a name that is taken. |
| `PUT /credentials/{id}` | The secret fields of its kind: a new secret, checked first (`422`/`502` change nothing). The name and the assignments stay, and the assignments are checked again. |
| `POST /credentials/{id}/verify` | Checks the credential and each assignment now and keeps the results. A refusal is still a `200`, with `status: rejected`. |
| `DELETE /credentials/{id}` | Deletes it and its secret. A credential that flavors use answers `409 credential_in_use` with `usedBy`, and is deleted only with `?force=true`, which unassigns it first. |
| `GET /projects/{id}/credentials` | The credential each flavor of the project uses, by app, flavor and kind: `id`, `name`, `account`, `credentialStatus` (the credential's check), `assignmentStatus` (the assignment's) and `status`, `message`, `fix` as preflight sees them (a refusal of either is a refusal). `?flavor=` (and `?app=`, `.` by default) for one flavor. |
| `PUT /projects/{id}/flavors/{flavor}/credentials/{kind}` | `{"credentialId": "crd_...", "allFlavors": false, "replace": false}`, `?app=` for an app below the root. The flavor uses the credential for the kind from now on; with `allFlavors` every flavor of the app does too, except those that have another credential of the kind: they keep it (`kept` in the answer) unless `replace`. Each assignment is checked at once; a refusal does not undo it, it fails preflight until fixed. |
| `DELETE /projects/{id}/flavors/{flavor}/credentials/{kind}` | The flavor stops using its credential of the kind; the credential stays. |

**Deprecated, kept so that no client breaks:** `PUT /projects/{id}/credentials` takes the per-flavor body of before
(`{"app": ".", "flavor": "prod", "kind": "asc_key", ...}`, optionally with a `name`): the credential is checked as
`POST /credentials` checks it; if the flavor's credential of the kind is used by that flavor alone it gets the new
secret (`200`, same id), otherwise a new named credential is created (`201`) and the flavor uses it, called `name` or
"<kind> · <project> <app> <flavor>". A `github` token there becomes the engine's GitHub token.
`POST /projects/{id}/credentials/{credentialId}/verify` verifies the credential and answers as the first flavor of the
project that uses it sees it, and `DELETE /projects/{id}/credentials/{credentialId}` unassigns it from the project's
flavors and deletes it when no other flavor uses it.

Creating, replacing, renaming, checking, expiring, deleting, assigning and unassigning announce `credential.saved`,
`credential.renamed`, `credential.verified`, `credential.expired` (a credential or an assignment that was `verified`
and is `rejected` now, once), `credential.removed`, `credential.assigned` and `credential.unassigned` on `/events`; the
events carry ids, names, places and kinds, never a secret. The server logs no request, and a failure names the field
that is wrong, not its value.

**The migration** (schema version 14) turns every `credential_ref` row of before into a named credential with the
same id, secret key, account and check, called "<kind> · <project> [<app> ]<flavor>" (for example "App Store Connect
API key · acme/shop prod"; cut to 80 characters, and a name that two rows would share gets the id after it), and an
assignment to its flavor with the same check. Secrets are neither read nor touched, and identical ones are not merged:
rename them, assign one to the flavors and delete the others. The per-flavor `github` rows are dropped: each of them
named the engine's GitHub token (`github.token`, the key they were saved under), which stays the one GitHub token, so
nothing is lost. `xpd` logs what the migration did on stderr (`xpd: Named 5 credential(s) ...`, `xpd: Dropped 2
per-flavor GitHub credential reference(s) ...`), and the database before it is kept as `xpath.db.bak-v13`.

**The daily health check** (`CredentialHealthCheck`, started by `xpd serve`) checks every credential and every
assignment every 24 hours and records the results. When the engine starts it also checks at once if any of them was
last checked more than a day ago, so a Mac mini that was off catches up; this does not delay the engine, which is
listening already. Checks never overlap, and a failed run (locked secrets, say) is reported to stderr and tried again
at the next tick.

**Preflight.** The `credentials` guard check reads the recorded results of the credentials assigned to the flavor named
in the step input (`flavorId`; `credentialKinds` narrows it to what the job needs, and a kind that is listed but not
assigned fails). A credential or an assignment that is `rejected` fails the `guard` step with the reason and the fix,
so the job stops before any build step runs; an `unreachable` or never-checked one is a warning. The acceptance tests
are `credentials_preflight_test.dart` in `xp_engine` (an expired ASC key, a revoked app-specific password and a key
that cannot see the flavor's app, through `JobRunner` with the guard first and a build step that must stay `pending`)
and `credential_checks_test.dart` in `xpd` (the same against the fake ASC server, and one key shared by two flavors).
