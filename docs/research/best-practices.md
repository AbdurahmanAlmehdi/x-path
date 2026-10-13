# Best practices (research, 2026-10-13)

[?] = unverified, spike before committing. [memory] = not sourced this session.

1. Monorepo: Dart pub workspaces (root `workspace:`, members `resolution: workspace`; globs need
   Dart 3.11+) + Melos 8 for scripts/versioning. Packages: apps/{xp_desktop,xpd,xp,xp_mcp,
   xp_runner}, packages/{xp_api,xp_client,xp_core,xp_secrets}. Flutter SDK pins may break a
   shared resolution [?]; fallback = desktop app in its own workspace using path deps.
   API models Dart-first in `xp_api` (json_serializable or dart_mappable, sealed event types).
   Hand-maintained `openapi.yaml` + contract test (Dart OpenAPI generators immature).
   https://dart.dev/tools/pub/workspaces https://pub.dev/packages/melos
2. HTTP: shelf + shelf_router + shelf_web_socket (stable). Relic 1.2 / 2.0-rc is attractive but
   moving; dart_frog poor fit. Keep handlers behind a thin layer. Loopback by default, hashed
   device tokens, monotonic event sequence for resume.
3. SQLite: `sqlite3` 3.x bundles SQLite via build hooks (Dart 3.10+). `dart compile exe` does
   NOT run hooks; use `dart build cli` (output is a bundle dir: bin/ + lib/). Cross-compile to
   Linux via `--target-os/--target-arch` [?] (sdk issue #63953); fallback build on Linux CI.
   drift 2.35 on sqlite3 ^3.4, pure-Dart use [?]; alternative raw sqlite3 + `user_version`
   migrations. WAL, busy_timeout, foreign_keys, single writer.
   https://dart.dev/tools/dart-build https://pub.dev/packages/sqlite3
4. Processes [memory]: Process.start, line-decoded streams with seq + timestamp, bounded
   fan-out buffers. Process.kill hits only the PID: need a process group (sh `set -m` trick [?],
   or FFI setpgid/kill(-pgid)); SIGTERM, 10s grace, SIGKILL; reap orphans on start. Typed step
   result. Allowlisted env per child. package:process / test_process.
5. Secrets: `cryptography` 2.9 (XChaCha20-Poly1305, HKDF, Argon2id). Master key: systemd
   `LoadCredentialEncrypted=` > 0600 key file; never in env or DB. macOS: avoid `security -w`
   (argv visible); FFI to Security.framework or stdin [?]. No age/libsodium in v1.
   https://systemd.io/CREDENTIALS/
6. Runners (GitHub, Buildkite, Woodpecker): outbound only; job lease + heartbeat as the single
   source of truth; idempotent ids and seq-numbered log chunks; advertised capabilities plus
   server-enforced rules; one-time pairing token exchanged for per-runner credential (hash
   stored); max parallel jobs, one-shot mode, graceful drain, health endpoint; artifacts
   uploaded to engine, engine keeps metadata + sha256.
7. Desktop app: VGV layers (data = xp_client, repositories expose streams, blocs use
   emit.forEach, sealed events/states, blocs never know each other). One EventStreamClient
   owns the socket (reconnect, resume cursor, replay-then-live). go_router [?]. Material 3 +
   thin wrapper and native menus over macos_ui (stale, bus factor). very_good_analysis everywhere.
8. Testing: 100% coverage on pure logic packages (`very_good test --coverage --min-coverage
   100`); ignore-file only for entrypoints/FFI with a reason, covered by integration tests.
   In-process engine on port 0 with temp SQLite, fake clock and fake process runner, a few
   real-process tests for group kill, OpenAPI contract test, migration tests per schema
   version, macOS + Linux CI, AOT smoke test. mocktail, bloc_test, goldens later.

Spikes: dart build cli cross-compile with sqlite hook; Flutter in the workspace; process
groups on macOS; drift in AOT bundle; Keychain from Dart without argv exposure.
