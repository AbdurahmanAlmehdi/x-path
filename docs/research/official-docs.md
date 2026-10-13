# Official docs fact sheet (verified 2026-10-13)

## App Store Connect API
- JWT ES256, header `{alg, kid, typ:JWT}`; team key payload `iss, iat, exp<=20min,
  aud:"appstoreconnect-v1"`; individual key uses `sub:"user"` instead of `iss`.
  https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests
- Rate limit per key per rolling hour, header `X-Rate-Limit`, 429 `RATE_LIMIT_EXCEEDED`.
- Builds: `GET /v1/builds` filters app/version/preReleaseVersion.version/processingState;
  `processingState` PROCESSING|FAILED|INVALID|VALID.
- Versions: `GET /v1/apps/{id}/appStoreVersions`; use `appVersionState` (`appStoreState`
  deprecated since 3.7). Values incl. WAITING_FOR_REVIEW, IN_REVIEW, PENDING_DEVELOPER_RELEASE,
  READY_FOR_DISTRIBUTION, REJECTED, METADATA_REJECTED, INVALID_BINARY, DEVELOPER_REJECTED.
  `reviewSubmissions.state` READY_FOR_REVIEW..COMPLETE, UNRESOLVED_ISSUES.
- Phased release: `appStoreVersionPhasedRelease.phasedReleaseState` INACTIVE|ACTIVE|PAUSED|COMPLETE.
- Build upload API (ASC 4.1): buildUploads -> buildUploadFiles (uploadOperations) -> PUT chunks ->
  PATCH uploaded; poll `apps/{id}/buildUploads` state AWAITING_UPLOAD|PROCESSING|FAILED|COMPLETE.
  Body schema not yet verified.
- altool not deprecated; `--upload-app` deprecated for `--upload-package` (needs --apple-id,
  --bundle-id, --bundle-short-version-string, --bundle-version). Auth `-u -p @env:` or
  `--apiKey --apiIssuer`. altool 27.0.5 ships in Xcode 27.1.
- Webhooks (4.0) need a public HTTPS receiver: poll instead.
- Apple ID + app-specific password cannot use the REST API. `altool --build-status` accepts it
  (unverified output).

## iTunes lookup
`itunes.apple.com/lookup?bundleId=&country=` -> version, currentVersionReleaseDate; CDN cached
~9h (max-age=32170 observed). "Live somewhere", not precise.

## Google Play androidpublisher v3
- Edits: insert -> bundles.upload -> tracks.update (versionCodes, status, userFraction,
  releaseNotes) -> validate -> commit. One open edit per user; console changes invalidate.
- `TrackRelease.status` draft|inProgress|halted|completed.
- Review state: `GET applications/{pkg}/tracks/{track}/releases` ->
  `releaseLifecycleState` DRAFT, NOT_SENT_FOR_REVIEW, IN_REVIEW, APPROVED_NOT_PUBLISHED,
  NOT_APPROVED, PUBLISHED (max 20, no edit). Check Dart googleapis client includes it.
- Commit `changesInReviewBehavior=ERROR_IF_IN_REVIEW` to avoid cancelling a review.
- Quota 3000 qpm. Service account: enable API, create SA + key, invite email in Play Console
  with view + release permissions.

## MCP
- Spec 2026-07-28 (stateless, no initialize, `server/discover`); clients may still speak
  2025-11-25. Transports stdio and Streamable HTTP.
- `dart_mcp` (Dart team, labs): 0.5.2 stdio only, specs up to 2025-11-25; `main` 0.6.0-wip adds
  Streamable HTTP + 2026-07-28, unreleased. `mcp_dart` 2.4.2 (third party) has Streamable HTTP.

## macOS
- SMAppService.agent: plist in `Contents/Library/LaunchAgents/` with `BundleProgram`; user
  toggle in Login Items; statuses notRegistered/enabled/requiresApproval/notFound. Flutter: copy
  files build phase + MethodChannel to Swift. LaunchAgent can reach the login Keychain;
  LaunchDaemon cannot.
- Notarize: `notarytool submit --wait`, `stapler staple`; Hardened Runtime, timestamp, sign
  inner binaries -> app -> DMG with Developer ID Application.
- Sparkle 2.10.0 (macOS 12+). `auto_updater` effectively unmaintained: embed Sparkle via a thin
  native channel.
- Homebrew 5: tap repo `homebrew-<name>`; sign and notarize regardless.

## Keychain from pure Dart
`/usr/bin/security` via `security -i` over stdin (keeps secrets out of argv); run in user
session. `keyring_native` 1.0.0 too new. FFI to Security.framework is the robust later option.

## Shorebird
- `login:ci` tokens stopped working 2026-10-01; use `sb_api_*` API keys as `SHOREBIRD_TOKEN`
  (1-year default expiry).
- Non-interactive with `--json`, no TTY, or `CI` set. Always pass `--release-version` on patch.
  `--track` replaces `--staging`.
- `releases list|info`, `patches list|...` support `--json` -> `{status,data,meta}`.
- REST `https://api.shorebird.dev/api/v1` (no compat guarantee).

## Firebase App Distribution
- CLI recommends ADC (`GOOGLE_APPLICATION_CREDENTIALS`); `FIREBASE_TOKEN` is legacy.
- REST v1: `releases:upload` (raw body) -> LRO poll -> `:distribute` -> PATCH notes. Dart via
  `googleapis_auth` + `http`, no Node needed.
