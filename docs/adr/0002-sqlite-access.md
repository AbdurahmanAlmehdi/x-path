# ADR 0002: SQLite access

- **Status:** Accepted
- **Date:** 2026-10-13
- **Phase:** 0 (decides Phase 3)

## Context

The engine stores projects, jobs, releases, approvals and events in one SQLite file. The two
candidates were drift (typed queries, code generation) and the raw `sqlite3` 3.x package with
hand-written SQL. Both had to work inside a `dart build cli` AOT bundle.

## Decision

Use **raw `sqlite3` 3.x** in `xp_adapters/sqlite.dart`, without drift.

- Migrations are an ordered list of SQL scripts. `PRAGMA user_version` records the applied
  version; each migration runs in a transaction.
- The snapshot test for each version dumps `sqlite_schema` after migrating and compares it with
  a checked-in golden file, from empty and from every earlier snapshot.
- Connection setup: `journal_mode=WAL`, `busy_timeout`, `foreign_keys=ON`. All writes go
  through one connection (single writer); the API is synchronous, which keeps the writer simple.
- Repositories in `xp_adapters` map rows to `xp_api`/`xp_engine` models by hand.

Why not drift: it works in the bundle (proof below), but it adds `build_runner` and
`drift_dev` code generation (24 s per build here) and generated files to the adapter package,
while the schema is about a dozen tables with simple queries. Raw SQL keeps the adapter small
and the migration snapshots plain SQL. This choice does not touch any D-xx decision.

## Proof

```sh
# drift 2.35.2 + drift_dev 2.35.1 + sqlite3 3.7.0, NativeDatabase, one generated table
dart run build_runner build      # Built with build_runner/aot in 24s; wrote 6 outputs.
dart build cli -o out && out/bundle/bin/main     # drift rows: [git@x]   (5.9 MB executable)

# raw sqlite3 (ADR 0001 spike): sqlite3.openInMemory() + select sqlite_version()
dart build cli -t bin/eng.dart -o out-host && out-host/bundle/bin/eng   # sqlite 3.53.4
```

Both run in an AOT bundle; the decision is on simplicity, not feasibility.

## Consequences

- No code generation in `xp_adapters` for persistence.
- Every query is covered by adapter tests against a temporary database file.
