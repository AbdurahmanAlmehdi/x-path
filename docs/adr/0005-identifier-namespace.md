# ADR 0005: Identifier namespace

- **Status:** Accepted
- **Date:** 2026-10-13
- **Phase:** Follow-up to Phases 4 and 15 (supersedes the identifier prefix in ADR 0004)

## Context

Phases 0 to 8 used a placeholder reverse-DNS prefix for bundle, service and channel
identifiers. The owner owns the domain `abdurahman.ly`, so every identifier XPath registers
with macOS, launchd or the Keychain, and every public URL, should live under it.

## Decision

The reverse-DNS prefix is `ly.abdurahman.xpath`; public URLs live under
`https://xpath.abdurahman.ly`.

| Identifier | Value |
| --- | --- |
| macOS app bundle ID (`PRODUCT_BUNDLE_IDENTIFIER`) | `ly.abdurahman.xpath` |
| Test bundle ID (`RunnerTests`) | `ly.abdurahman.xpath.RunnerTests` |
| Engine LaunchAgent label and plist | `ly.abdurahman.xpath.xpd` (`ly.abdurahman.xpath.xpd.plist`) |
| Runner LaunchAgent label and plist | `ly.abdurahman.xpath.runner` (`ly.abdurahman.xpath.runner.plist`) |
| Keychain service prefix | `ly.abdurahman.xpath`, so the service is `ly.abdurahman.xpath.<scope>` (default `ly.abdurahman.xpath.credentials`) |
| `xp_macos_services` method channel | `ly.abdurahman.xpath/macos_services` |
| Sparkle appcast | `https://xpath.abdurahman.ly/appcast.xml` (Phase 18c) |
| Install script | `https://xpath.abdurahman.ly/install` (Phase 18a) |

## Consequences

- ADR 0004's placeholder service name is replaced by `ly.abdurahman.xpath.<scope>`; the rest of
  ADR 0004 stands.
- No XPath release has shipped, so there is nothing to migrate: items stored under the
  placeholder service by development builds are simply not found and must be entered again.
- The domain must serve `/appcast.xml` and `/install` before Phases 18a and 18c are accepted.
- Later phases use this prefix for any new launchd label, bundle ID, Keychain service,
  channel or notification identifier.
