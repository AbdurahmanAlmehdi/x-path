# Security policy

XPath holds signing keys, store credentials and GitHub tokens for the apps it releases. We take
reports about it seriously and handle them before anything else.

## Supported versions

XPath is before 1.0, and every merge to `main` publishes a release. Only the latest release gets
security fixes; update to it before reporting.

## Reporting a vulnerability

Do not open a public issue, pull request or discussion for a security problem.

Report it privately through GitHub: on the repository page, open **Security ▸ Report a
vulnerability**. Include:

- what an attacker can do, and what they need first (network access to the engine, a device token,
  a paired runner, a malicious repository, …);
- the version (`xpd --version`, `xp --version`, or **Settings ▸ About** in the app) and the platform;
- steps to reproduce, ideally against the fake stores in `tool/e2e/fake_stores` rather than real
  accounts.

Never include real credentials, signing keys or tokens in a report. If a secret of yours was exposed,
revoke it with the service that issued it first.

You can expect an acknowledgement within 3 days and a first assessment within 7. We will keep you
updated, agree a disclosure date with you, and credit you in the release notes unless you prefer not
to be named.

## What is in scope

- The engine `xpd`, the `xp` CLI, `xp mcp`, `xp runner`, the macOS app and the install scripts and
  images in this repository.
- Ways a secret can leave the engine machine, appear in a log, a process argument or a file outside
  the data directory, or reach a runner it was not leased to.
- Ways to act without the right token: an `mcp` or `runner` token approving a gate, a runner token
  reaching non-runner routes, a stale approval being accepted after the commit, version or flavor
  changed.
- Ways a scanned repository can make the engine run commands it should not, or write to the source
  folder.

## What is out of scope

- Problems that need an attacker who already has your device token, your macOS account or root on
  the engine machine.
- Problems in the stores, GitHub, Shorebird, Flutter or the tools XPath runs, unless XPath makes them
  worse. Report those upstream.
- The engine listening on a network address you chose to expose without a reverse proxy and TLS.

## How XPath protects secrets

- Secrets live only on the engine machine: in the macOS Keychain (large ones in an encrypted file
  whose key is in the Keychain), or in an XChaCha20-Poly1305 encrypted file on Linux.
- They are never written to logs (every log line is masked), never passed on a command line, and
  never returned by the API after they are saved.
- Device tokens are stored as SHA-256 hashes. `mcp` tokens cannot approve anything, and runner tokens
  reach only the runner routes.
- Signing material goes to a runner only for the job that needs it, and is deleted when the job ends
  or the lease is lost.
