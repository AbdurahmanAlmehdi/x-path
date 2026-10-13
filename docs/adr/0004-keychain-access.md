# ADR 0004: Keychain access

- **Status:** Accepted
- **Date:** 2026-10-13
- **Phase:** 0 (decides Phase 4)

## Context

D-07 stores secrets in the macOS Keychain through `security -i` over stdin, because
`security add-generic-password -w <secret>` puts the secret in `argv`, visible to `ps`. This
spike checks that the interactive mode round-trips arbitrary values and never exposes them.

## Decision

The Keychain store runs one `security -i` process per operation (behind the process-runner
interface) and writes a single command line to its stdin:

- write: `add-generic-password -U -a <account> -s <service> -w <value> [keychain]`
- read: `find-generic-password -a <account> -s <service> -w [keychain]` (value on stdout)
- delete: `delete-generic-password -a <account> -s <service> [keychain]`

Every argument is double-quoted, with `\` escaped as `\\` and `"` as `\"`. The service name is
`dev.xpath.<scope>`. Tests use a temporary keychain created with `security create-keychain` so
they never touch the login keychain. The engine never passes a value through argv or the
environment of `security`.

Identifier prefix superseded by ADR 0005.

## Proof

Temporary keychain, value generated at run time so no other process could contain it:
`S3c "q" \ <random> $HOME'` (quotes, backslash, spaces, `$`).

```sh
security create-keychain -p spikepw "$KC" && security unlock-keychain -p spikepw "$KC"
dart run bin/main.dart "$KC"
# security alive, secret in ps: false        (ps -axww -o args= while security -i was running)
# exit=0                                      (add-generic-password -U)
# roundtrip equal: true                       (find-generic-password -w)
# exit=0 err=password has been deleted.       (delete-generic-password)
security delete-keychain "$KC"
```

## Consequences

- Phase 4 implements this quoting in one place and unit-tests it with a fake process runner;
  the real-Keychain test is tagged `macos`.
- A locked keychain makes `security` fail without prompting the daemon; the store maps that
  failure to the "secrets locked" state (D-10).
