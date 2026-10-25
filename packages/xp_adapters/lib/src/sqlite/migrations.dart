import 'package:xp_adapters/src/sqlite/migration.dart';

/// Every schema change of the engine database, oldest first.
///
/// A released migration is never edited: a later change is a new migration.
/// Each one needs a golden file in `test/src/sqlite/snapshots`.
const engineMigrations = <Migration>[
  Migration(version: 1, sql: _v1),
  Migration(version: 2, sql: _v2),
  Migration(version: 3, sql: _v3),
  Migration(version: 4, sql: _v4),
  Migration(version: 5, sql: _v5),
  Migration(version: 6, sql: _v6),
  Migration(version: 7, sql: _v7),
  Migration(version: 8, sql: _v8),
  Migration(version: 9, sql: _v9),
  Migration(version: 10, sql: _v10),
  Migration(version: 11, sql: _v11),
  Migration(version: 12, sql: _v12),
  Migration(version: 13, sql: _v13),
  Migration(version: 14, sql: _v14, notes: _v14Notes),
  Migration(version: 15, sql: _v15),
  Migration(version: 16, sql: _v16, foreignKeysOff: true),
  Migration(version: 17, sql: _v17),
  Migration(version: 18, sql: _v18),
  Migration(version: 19, sql: _v19),
];

// Timestamps are integer microseconds since the Unix epoch (UTC), so that
// they sort and compare as numbers. Booleans are 0 or 1. JSON columns are
// text that must be valid JSON. Rows that belong to a parent are deleted with
// it; history (releases, jobs) is never deleted by cascade from its app.
const _v1 = '''
CREATE TABLE device_token (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('app', 'cli', 'mcp', 'runner')),
  hash TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  revoked_at INTEGER
) STRICT;

CREATE TABLE project (
  id TEXT PRIMARY KEY,
  github_repo_id INTEGER NOT NULL UNIQUE,
  remote TEXT NOT NULL,
  default_base_branch TEXT NOT NULL,
  release_model TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(release_model)),
  gates TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(gates))
) STRICT;

CREATE TABLE app (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES project (id) ON DELETE CASCADE,
  path TEXT NOT NULL,
  framework TEXT NOT NULL,
  store_country TEXT NOT NULL,
  build_counter INTEGER NOT NULL DEFAULT 0 CHECK (build_counter >= 0),
  UNIQUE (project_id, path)
) STRICT;

CREATE TABLE flavor (
  id TEXT PRIMARY KEY,
  app_id TEXT NOT NULL REFERENCES app (id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  entrypoint TEXT NOT NULL,
  ios_bundle_id TEXT,
  android_app_id TEXT,
  shorebird INTEGER NOT NULL DEFAULT 0 CHECK (shorebird IN (0, 1)),
  prod INTEGER NOT NULL DEFAULT 0 CHECK (prod IN (0, 1)),
  version_files TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(version_files)),
  UNIQUE (app_id, name)
) STRICT;

CREATE TABLE credential_ref (
  id TEXT PRIMARY KEY,
  flavor_id TEXT NOT NULL REFERENCES flavor (id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN (
    'asc_key', 'apple_id', 'play_sa', 'firebase_sa', 'keystore', 'shorebird',
    'github', 'slack'
  )),
  secret_key TEXT NOT NULL,
  verified_at INTEGER
) STRICT;
CREATE INDEX idx_credential_ref_flavor ON credential_ref (flavor_id);

CREATE TABLE workflow (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES project (id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  builtin INTEGER NOT NULL DEFAULT 0 CHECK (builtin IN (0, 1)),
  UNIQUE (project_id, name)
) STRICT;

CREATE TABLE workflow_version (
  id TEXT PRIMARY KEY,
  workflow_id TEXT NOT NULL REFERENCES workflow (id) ON DELETE CASCADE,
  version INTEGER NOT NULL CHECK (version > 0),
  yaml TEXT NOT NULL,
  UNIQUE (workflow_id, version)
) STRICT;

CREATE TABLE release (
  id TEXT PRIMARY KEY,
  app_id TEXT NOT NULL REFERENCES app (id),
  version TEXT NOT NULL,
  build INTEGER NOT NULL,
  state TEXT NOT NULL,
  tag TEXT,
  pr_url TEXT,
  store_status TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(store_status))
) STRICT;
CREATE INDEX idx_release_app ON release (app_id, state);

CREATE TABLE runner (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  capabilities TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(capabilities)),
  slots INTEGER NOT NULL DEFAULT 1 CHECK (slots > 0),
  last_heartbeat INTEGER
) STRICT;

CREATE TABLE job (
  id TEXT PRIMARY KEY,
  workflow_version_id TEXT NOT NULL REFERENCES workflow_version (id),
  project_id TEXT NOT NULL REFERENCES project (id),
  release_id TEXT REFERENCES release (id),
  sha TEXT,
  state TEXT NOT NULL,
  runner_id TEXT REFERENCES runner (id) ON DELETE SET NULL,
  lease_until INTEGER
) STRICT;
CREATE INDEX idx_job_project ON job (project_id, state);
CREATE INDEX idx_job_state ON job (state, lease_until);
CREATE INDEX idx_job_release ON job (release_id);
CREATE INDEX idx_job_workflow_version ON job (workflow_version_id);
CREATE INDEX idx_job_runner ON job (runner_id);

CREATE TABLE job_step (
  id TEXT PRIMARY KEY,
  job_id TEXT NOT NULL REFERENCES job (id) ON DELETE CASCADE,
  ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
  kind TEXT NOT NULL,
  state TEXT NOT NULL,
  side_effect INTEGER NOT NULL DEFAULT 0 CHECK (side_effect IN (0, 1)),
  result TEXT CHECK (result IS NULL OR json_valid(result)),
  log_path TEXT,
  UNIQUE (job_id, ordinal)
) STRICT;

CREATE TABLE artifact (
  id TEXT PRIMARY KEY,
  job_id TEXT NOT NULL REFERENCES job (id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN (
    'ipa', 'aab', 'apk', 'mapping', 'dsym', 'manifest', 'shorebird_symbols'
  )),
  path TEXT NOT NULL,
  size INTEGER NOT NULL CHECK (size >= 0),
  sha256 TEXT NOT NULL,
  pinned INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0, 1))
) STRICT;
CREATE INDEX idx_artifact_job ON artifact (job_id);
CREATE INDEX idx_artifact_sha256 ON artifact (sha256);

CREATE TABLE approval (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES project (id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  sha TEXT,
  version TEXT,
  state TEXT NOT NULL,
  decided_by TEXT,
  expires_at INTEGER
) STRICT;
CREATE INDEX idx_approval_project ON approval (project_id, state);

CREATE TABLE test_run (
  id TEXT PRIMARY KEY,
  job_id TEXT NOT NULL UNIQUE REFERENCES job (id) ON DELETE CASCADE,
  branch TEXT NOT NULL,
  baseline INTEGER NOT NULL DEFAULT 0 CHECK (baseline IN (0, 1)),
  results TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(results))
) STRICT;

CREATE TABLE event (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL,
  payload TEXT NOT NULL CHECK (json_valid(payload)),
  at INTEGER NOT NULL
) STRICT;
CREATE INDEX idx_event_at ON event (at);
''';

// Phase 6: what a scan found. `scan` is the raw result and `edits` the owner's
// corrections on top of it; the app and flavor rows are rewritten from the two
// each time (they carry the ids and counters that later phases refer to).
const _v2 = '''
ALTER TABLE project ADD COLUMN full_name TEXT NOT NULL DEFAULT '';
ALTER TABLE project ADD COLUMN local_path TEXT;
ALTER TABLE project ADD COLUMN github_default_branch TEXT NOT NULL DEFAULT '';
ALTER TABLE project ADD COLUMN scan TEXT NOT NULL DEFAULT '{}'
  CHECK (json_valid(scan));
ALTER TABLE project ADD COLUMN findings TEXT NOT NULL DEFAULT '[]'
  CHECK (json_valid(findings));
ALTER TABLE project ADD COLUMN scanned_at INTEGER NOT NULL DEFAULT 0;
ALTER TABLE project ADD COLUMN edits TEXT NOT NULL DEFAULT '{}'
  CHECK (json_valid(edits));
''';

// Phase 7: what the job runner records. A job keeps when it was created,
// started and finished, and why it ended. A step keeps its input (so that a
// job survives a restart), how often it was started, why it failed, the
// process group it runs in (so that a restarted engine can stop it) and when
// it ran.
const _v3 = '''
ALTER TABLE job ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0;
ALTER TABLE job ADD COLUMN started_at INTEGER;
ALTER TABLE job ADD COLUMN finished_at INTEGER;
ALTER TABLE job ADD COLUMN message TEXT;
ALTER TABLE job_step ADD COLUMN input TEXT NOT NULL DEFAULT '{}'
  CHECK (json_valid(input));
ALTER TABLE job_step ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0
  CHECK (attempts >= 0);
ALTER TABLE job_step ADD COLUMN message TEXT;
ALTER TABLE job_step ADD COLUMN pgid INTEGER;
ALTER TABLE job_step ADD COLUMN started_at INTEGER;
ALTER TABLE job_step ADD COLUMN finished_at INTEGER;
''';

// Phase 9a: the versions of the tools a job ran with (Flutter, Dart,
// Shorebird, gh, Xcode), as JSON, once they are known.
const _v4 = '''
ALTER TABLE job ADD COLUMN tools TEXT
  CHECK (tools IS NULL OR json_valid(tools));
''';

// Phase 9b: when an artifact was stored, and one file per path for a job, so
// that a step that runs again replaces its artifact instead of adding another.
// `path` is relative to the artifact store: `<job id>/<file name>`.
const _v5 = '''
ALTER TABLE artifact ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0;
CREATE UNIQUE INDEX idx_artifact_job_path ON artifact (job_id, path);
''';

// Phase 9c: the Flutter version each Shorebird release was built with, which
// every patch of it must use (D-20). A release is one app id, version and
// platform; `job_id` is the job that made it (no foreign key: the record
// outlives the job's housekeeping).
const _v6 = '''
CREATE TABLE shorebird_release (
  app_id TEXT NOT NULL,
  version TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
  flutter_version TEXT NOT NULL,
  job_id TEXT NOT NULL,
  recorded_at INTEGER NOT NULL,
  PRIMARY KEY (app_id, version, platform)
) STRICT;
''';

// Phase 9d: what a test run needs to be a baseline. A run keeps its project
// and app (the baseline is per project, app and branch, and the project is
// copied from the job so that the baseline does not depend on a join), when it
// ended, and the diff against the baseline it was compared with inside
// `results`. The partial index serves the baseline lookup.
const _v7 = '''
ALTER TABLE test_run ADD COLUMN project_id TEXT NOT NULL DEFAULT '';
ALTER TABLE test_run ADD COLUMN app_path TEXT NOT NULL DEFAULT '.';
ALTER TABLE test_run ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0;
CREATE INDEX idx_test_run_baseline
  ON test_run (project_id, app_path, branch, created_at) WHERE baseline = 1;
''';

// Phase 10c: what the checks of a credential found. `account` is who the
// credential belongs to when that is not secret (the Apple ID, the key id, the
// service account email, the keystore alias); `status` and `checked_at` are
// the result of the last check, `message` and `fix` what it said when it did
// not accept the credential. A flavor has one credential of each kind.
const _v8 = '''
ALTER TABLE credential_ref ADD COLUMN account TEXT;
ALTER TABLE credential_ref ADD COLUMN status TEXT NOT NULL DEFAULT 'unverified'
  CHECK (status IN ('unverified', 'verified', 'rejected', 'unreachable'));
ALTER TABLE credential_ref ADD COLUMN checked_at INTEGER;
ALTER TABLE credential_ref ADD COLUMN message TEXT;
ALTER TABLE credential_ref ADD COLUMN fix TEXT;
CREATE UNIQUE INDEX idx_credential_ref_flavor_kind
  ON credential_ref (flavor_id, kind);
''';

// Phase 11: runs and what the scheduler needs to know of a job. A run is one
// dispatch of a workflow version; its jobs name it, their stage (a stage
// starts when the stages before it succeeded), what the workflow calls them
// and the capabilities a runner needs for them. `workflow_version` gets the
// time it was saved.
const _v9 = '''
CREATE TABLE run (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES project (id),
  workflow_id TEXT NOT NULL,
  workflow_version_id TEXT NOT NULL REFERENCES workflow_version (id),
  sha TEXT NOT NULL,
  ref TEXT,
  locks_project INTEGER NOT NULL DEFAULT 0 CHECK (locks_project IN (0, 1)),
  lock_held INTEGER NOT NULL DEFAULT 0 CHECK (lock_held IN (0, 1)),
  version TEXT,
  build INTEGER,
  request TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(request)),
  created_at INTEGER NOT NULL
) STRICT;
CREATE INDEX idx_run_project ON run (project_id, created_at);
CREATE INDEX idx_run_workflow_version ON run (workflow_version_id);
ALTER TABLE job ADD COLUMN run_id TEXT REFERENCES run (id);
ALTER TABLE job ADD COLUMN stage INTEGER NOT NULL DEFAULT 0;
ALTER TABLE job ADD COLUMN name TEXT;
ALTER TABLE job ADD COLUMN capabilities TEXT NOT NULL DEFAULT '[]'
  CHECK (json_valid(capabilities));
CREATE INDEX idx_job_run ON job (run_id, stage);
ALTER TABLE workflow_version ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0;
''';

// Phase 12a: what an approval needs beyond the binding of version 1. The
// binding is (project, action, commit, version) plus the run that asked, so
// that a denial or an expiry of one dispatch does not stop the next; there is
// one row per binding for good (a null counts as the empty string in the
// unique index), and a decision is a compare-and-set on `state = 'pending'`.
// `job_id` and `run_id` are plain text (the record outlives the housekeeping
// of jobs). Who decided is copied from the device token, so that the record
// reads the same after the token is revoked.
const _v10 = '''
ALTER TABLE approval ADD COLUMN run_id TEXT;
ALTER TABLE approval ADD COLUMN job_id TEXT;
ALTER TABLE approval ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0;
ALTER TABLE approval ADD COLUMN decided_at INTEGER;
ALTER TABLE approval ADD COLUMN decided_by_name TEXT;
ALTER TABLE approval ADD COLUMN decided_by_kind TEXT
  CHECK (decided_by_kind IS NULL OR decided_by_kind IN ('app', 'cli'));
ALTER TABLE approval ADD COLUMN reason TEXT;
CREATE UNIQUE INDEX idx_approval_binding ON approval (
  project_id, action, COALESCE(sha, ''), COALESCE(version, ''),
  COALESCE(run_id, '')
);
CREATE INDEX idx_approval_due ON approval (expires_at) WHERE state = 'pending';
''';

// Phase 12b: what a release needs beyond the version 1 table. A release is one
// flavor of an app at one version (a new build of the same version after a
// rejection stays in it, `builds` lists them all as JSON), with its release
// branch, the commit its tag names, its pull request, the run that merges it
// and the merge commit. `store_status` holds the status in each store (JSON,
// by store). The project of a release is the project of its app.
const _v11 = '''
ALTER TABLE release ADD COLUMN flavor TEXT NOT NULL DEFAULT '';
ALTER TABLE release ADD COLUMN base_branch TEXT NOT NULL DEFAULT '';
ALTER TABLE release ADD COLUMN branch TEXT;
ALTER TABLE release ADD COLUMN head_sha TEXT;
ALTER TABLE release ADD COLUMN pr_number INTEGER;
ALTER TABLE release ADD COLUMN merge_sha TEXT;
ALTER TABLE release ADD COLUMN merge_run_id TEXT;
ALTER TABLE release ADD COLUMN message TEXT;
ALTER TABLE release ADD COLUMN builds TEXT NOT NULL DEFAULT '[]'
  CHECK (json_valid(builds));
ALTER TABLE release ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0;
ALTER TABLE release ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0;
''';

// Phase 12c: what housekeeping remembers between runs. `housekeeping_setting`
// is a small key to JSON table: the retention the owner set (`retention`) and
// when the logs were last pruned (`last_log_prune`, microseconds since the
// epoch).
const _v12 = '''
CREATE TABLE housekeeping_setting (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL CHECK (json_valid(value))
) STRICT;
''';

// Phase 14a: runners (D-08). A runner keeps the device token that is its
// credential (`token_id`), what it reported about itself and when it was
// revoked; `capabilities` is a JSON array of the wire names the engine found
// with its probe. A pairing token is single use and valid for 15 minutes; only
// the hash of its secret is kept, and `used_at` is set by one compare-and-set.
// A job that runs on a runner holds a lease: `job.runner_id` and
// `job.lease_until` already exist.
const _v13 = '''
ALTER TABLE runner ADD COLUMN token_id TEXT REFERENCES device_token (id);
ALTER TABLE runner ADD COLUMN os TEXT;
ALTER TABLE runner ADD COLUMN arch TEXT;
ALTER TABLE runner ADD COLUMN version TEXT;
ALTER TABLE runner ADD COLUMN cores INTEGER CHECK (cores IS NULL OR cores > 0);
ALTER TABLE runner ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0;
ALTER TABLE runner ADD COLUMN revoked_at INTEGER;
CREATE UNIQUE INDEX idx_runner_token ON runner (token_id);

CREATE TABLE pairing_token (
  id TEXT PRIMARY KEY,
  hash TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  created_by TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  used_at INTEGER
) STRICT;
CREATE INDEX idx_pairing_token_expires ON pairing_token (expires_at);
''';

// Named credentials (ADR 0013). A credential is the engine's, not a flavor's:
// it has a name, unique regardless of case, and the result of its own check
// (does it authenticate). A flavor uses at most one credential of each kind
// (`credential_assignment`, only of the credential's kind), and each
// assignment keeps the result of its own check (can the credential reach the
// flavor's bundle id, package or app). Deleting a flavor or a credential
// deletes its assignments.
//
// Every `credential_ref` row becomes a credential with the same id, secret
// key, account and check, named "<kind> · <project> [<app> ]<flavor>" (cut to
// 80 characters; a name that is not unique gets the id after it), and an
// assignment to its flavor with the same check. Secrets are not touched and
// identical ones are not merged. `github` rows are dropped: every one of them
// named the engine's GitHub token (`github.token`), which stays.
const _v14Notes = '''
SELECT 'Named ' || count(*) || ' credential(s) after their flavor and '
  || 'assigned each to it (ADR 0013).'
FROM credential_ref WHERE kind != 'github' HAVING count(*) > 0
UNION ALL
SELECT 'Dropped ' || count(*) || ' per-flavor GitHub credential reference(s): '
  || 'each named the engine''s GitHub token (github.token), which stays the '
  || 'one GitHub token of the engine.'
FROM credential_ref WHERE kind = 'github' HAVING count(*) > 0
''';

const _v14 = '''
CREATE TABLE credential (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
  kind TEXT NOT NULL CHECK (kind IN (
    'asc_key', 'apple_id', 'play_sa', 'firebase_sa', 'keystore', 'shorebird',
    'slack'
  )),
  secret_key TEXT NOT NULL,
  account TEXT,
  status TEXT NOT NULL DEFAULT 'unverified'
    CHECK (status IN ('unverified', 'verified', 'rejected', 'unreachable')),
  verified_at INTEGER,
  checked_at INTEGER,
  message TEXT,
  fix TEXT,
  UNIQUE (id, kind)
) STRICT;
CREATE UNIQUE INDEX idx_credential_name ON credential (name COLLATE NOCASE);

CREATE TABLE credential_assignment (
  flavor_id TEXT NOT NULL REFERENCES flavor (id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  credential_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'unverified'
    CHECK (status IN ('unverified', 'verified', 'rejected', 'unreachable')),
  verified_at INTEGER,
  checked_at INTEGER,
  message TEXT,
  fix TEXT,
  PRIMARY KEY (flavor_id, kind),
  FOREIGN KEY (credential_id, kind) REFERENCES credential (id, kind)
    ON DELETE CASCADE
) STRICT;
CREATE INDEX idx_credential_assignment_credential
  ON credential_assignment (credential_id, kind);

WITH named AS (
  SELECT ref.rowid AS position, ref.id, ref.kind, ref.secret_key, ref.account,
    ref.status, ref.verified_at, ref.checked_at, ref.message, ref.fix,
    rtrim(substr(
      CASE ref.kind
        WHEN 'asc_key' THEN 'App Store Connect API key'
        WHEN 'apple_id' THEN 'Apple ID'
        WHEN 'play_sa' THEN 'Google Play service account'
        WHEN 'firebase_sa' THEN 'Firebase service account'
        WHEN 'keystore' THEN 'Android keystore'
        WHEN 'shorebird' THEN 'Shorebird API key'
        WHEN 'slack' THEN 'Slack webhook'
      END
      || ' · ' || CASE project.full_name WHEN '' THEN project.id
        ELSE project.full_name END
      || CASE app.path WHEN '.' THEN '' ELSE ' ' || app.path END
      || ' ' || flavor.name,
      1, 80
    )) AS base
  FROM credential_ref AS ref
  JOIN flavor ON flavor.id = ref.flavor_id
  JOIN app ON app.id = flavor.app_id
  JOIN project ON project.id = app.project_id
  WHERE ref.kind != 'github'
), numbered AS (
  SELECT *, count(*) OVER (PARTITION BY lower(base)) AS sharing FROM named
)
INSERT INTO credential (id, name, kind, secret_key, account, status,
  verified_at, checked_at, message, fix)
SELECT id,
  CASE WHEN sharing = 1 THEN base
    ELSE rtrim(substr(base, 1, 77 - length(id))) || ' (' || id || ')' END,
  kind, secret_key, account, status, verified_at, checked_at, message, fix
FROM numbered ORDER BY position;

INSERT INTO credential_assignment (flavor_id, kind, credential_id, status,
  verified_at, checked_at)
SELECT flavor_id, kind, id, status, verified_at, checked_at
FROM credential_ref WHERE kind != 'github' ORDER BY rowid;

DROP INDEX idx_credential_ref_flavor_kind;
DROP INDEX idx_credential_ref_flavor;
DROP TABLE credential_ref;
''';

// Runner onboarding R4: settings of the engine itself, one text value per
// key. The first is `runner_url`, the address runners reach the engine at,
// which pairing tokens carry. `housekeeping_setting` has the same shape but
// its JSON values belong to housekeeping.
const _v15 = '''
CREATE TABLE engine_setting (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
) STRICT;
''';

// Projects on any git host (ADR 0015). A project has a `host` and a
// `source_key` that keys its mirror, the runner cache and its worktrees;
// `github_repo_id` is only there for GitHub projects. SQLite cannot drop a NOT
// NULL constraint, so `project` is rebuilt (SQLite's 12-step procedure) with
// foreign keys off: the rows that refer to it keep their ids. Every existing
// project is on GitHub, and its key is its repository id, so its mirror stays
// where it is.
const _v16 = '''
CREATE TABLE new_project (
  id TEXT PRIMARY KEY,
  host TEXT NOT NULL CHECK (length(host) > 0),
  source_key TEXT NOT NULL UNIQUE CHECK (length(source_key) > 0),
  github_repo_id INTEGER UNIQUE,
  remote TEXT NOT NULL,
  default_base_branch TEXT NOT NULL,
  release_model TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(release_model)),
  gates TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(gates)),
  full_name TEXT NOT NULL DEFAULT '',
  local_path TEXT,
  github_default_branch TEXT NOT NULL DEFAULT '',
  scan TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(scan)),
  findings TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(findings)),
  scanned_at INTEGER NOT NULL DEFAULT 0,
  edits TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(edits)),
  CHECK ((host = 'github.com') = (github_repo_id IS NOT NULL))
) STRICT;

INSERT INTO new_project (id, host, source_key, github_repo_id, remote,
  default_base_branch, release_model, gates, full_name, local_path,
  github_default_branch, scan, findings, scanned_at, edits)
SELECT id, 'github.com', CAST(github_repo_id AS TEXT), github_repo_id, remote,
  default_base_branch, release_model, gates, full_name, local_path,
  github_default_branch, scan, findings, scanned_at, edits
FROM project ORDER BY rowid;

DROP TABLE project;
ALTER TABLE new_project RENAME TO project;
''';

// iOS on Linux 3a (ADR 0014): why the planner ruled out an iOS build on Linux
// for a job, so that it needs ios-sign. A JSON list of reasons, which the
// queue message of the job repeats.
const _v17 = '''
ALTER TABLE job ADD COLUMN narrowing TEXT NOT NULL DEFAULT '[]'
  CHECK (json_valid(narrowing));
''';

// UX U2a: the store ids of a flavor, from its profile like its bundle
// and application ids: the Firebase app id of each platform and the App Store
// Connect app id. The built-in workflows upload to them when no input gives
// one.
const _v18 = '''
ALTER TABLE flavor ADD COLUMN firebase_app_id_android TEXT;
ALTER TABLE flavor ADD COLUMN firebase_app_id_ios TEXT;
ALTER TABLE flavor ADD COLUMN apple_app_id TEXT;
''';

// UX U3d: a workflow copied from a built-in remembers which one and the
// version it started from, so the app can offer to compare when the
// built-in changes; and a workflow can be archived: kept with its
// versions and runs, and not dispatched.
const _v19 = '''
ALTER TABLE workflow ADD COLUMN based_on_builtin TEXT;
ALTER TABLE workflow ADD COLUMN based_on_version INTEGER
  CHECK (based_on_version IS NULL OR based_on_version > 0);
ALTER TABLE workflow ADD COLUMN archived_at INTEGER;
''';
