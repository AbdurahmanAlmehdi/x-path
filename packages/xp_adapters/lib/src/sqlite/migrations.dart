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
