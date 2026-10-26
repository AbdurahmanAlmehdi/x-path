CREATE TABLE app (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES project (id) ON DELETE CASCADE,
  path TEXT NOT NULL,
  framework TEXT NOT NULL,
  store_country TEXT NOT NULL,
  build_counter INTEGER NOT NULL DEFAULT 0 CHECK (build_counter >= 0),
  UNIQUE (project_id, path)
) STRICT;

CREATE TABLE approval (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES project (id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  sha TEXT,
  version TEXT,
  state TEXT NOT NULL,
  decided_by TEXT,
  expires_at INTEGER
, run_id TEXT, job_id TEXT, created_at INTEGER NOT NULL DEFAULT 0, decided_at INTEGER, decided_by_name TEXT, decided_by_kind TEXT
  CHECK (decided_by_kind IS NULL OR decided_by_kind IN ('app', 'cli')), reason TEXT) STRICT;

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
, created_at INTEGER NOT NULL DEFAULT 0) STRICT;

CREATE TABLE "credential" (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
  kind TEXT NOT NULL CHECK (kind IN (
    'asc_key', 'apple_id', 'apple_distribution', 'play_sa', 'firebase_sa',
    'keystore', 'shorebird', 'slack'
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

CREATE TABLE device_token (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('app', 'cli', 'mcp', 'runner')),
  hash TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  revoked_at INTEGER
) STRICT;

CREATE TABLE engine_setting (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
) STRICT;

CREATE TABLE event (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL,
  payload TEXT NOT NULL CHECK (json_valid(payload)),
  at INTEGER NOT NULL
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
  version_files TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(version_files)), firebase_app_id_android TEXT, firebase_app_id_ios TEXT, apple_app_id TEXT,
  UNIQUE (app_id, name)
) STRICT;

CREATE TABLE housekeeping_setting (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL CHECK (json_valid(value))
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
, created_at INTEGER NOT NULL DEFAULT 0, started_at INTEGER, finished_at INTEGER, message TEXT, tools TEXT
  CHECK (tools IS NULL OR json_valid(tools)), run_id TEXT REFERENCES run (id), stage INTEGER NOT NULL DEFAULT 0, name TEXT, capabilities TEXT NOT NULL DEFAULT '[]'
  CHECK (json_valid(capabilities)), narrowing TEXT NOT NULL DEFAULT '[]'
  CHECK (json_valid(narrowing))) STRICT;

CREATE TABLE job_step (
  id TEXT PRIMARY KEY,
  job_id TEXT NOT NULL REFERENCES job (id) ON DELETE CASCADE,
  ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
  kind TEXT NOT NULL,
  state TEXT NOT NULL,
  side_effect INTEGER NOT NULL DEFAULT 0 CHECK (side_effect IN (0, 1)),
  result TEXT CHECK (result IS NULL OR json_valid(result)),
  log_path TEXT, input TEXT NOT NULL DEFAULT '{}'
  CHECK (json_valid(input)), attempts INTEGER NOT NULL DEFAULT 0
  CHECK (attempts >= 0), message TEXT, pgid INTEGER, started_at INTEGER, finished_at INTEGER,
  UNIQUE (job_id, ordinal)
) STRICT;

CREATE TABLE pairing_token (
  id TEXT PRIMARY KEY,
  hash TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  created_by TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  used_at INTEGER
) STRICT;

CREATE TABLE "project" (
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

CREATE TABLE release (
  id TEXT PRIMARY KEY,
  app_id TEXT NOT NULL REFERENCES app (id),
  version TEXT NOT NULL,
  build INTEGER NOT NULL,
  state TEXT NOT NULL,
  tag TEXT,
  pr_url TEXT,
  store_status TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(store_status))
, flavor TEXT NOT NULL DEFAULT '', base_branch TEXT NOT NULL DEFAULT '', branch TEXT, head_sha TEXT, pr_number INTEGER, merge_sha TEXT, merge_run_id TEXT, message TEXT, builds TEXT NOT NULL DEFAULT '[]'
  CHECK (json_valid(builds)), created_at INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL DEFAULT 0) STRICT;

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

CREATE TABLE runner (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  capabilities TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(capabilities)),
  slots INTEGER NOT NULL DEFAULT 1 CHECK (slots > 0),
  last_heartbeat INTEGER
, token_id TEXT REFERENCES device_token (id), os TEXT, arch TEXT, version TEXT, cores INTEGER CHECK (cores IS NULL OR cores > 0), created_at INTEGER NOT NULL DEFAULT 0, revoked_at INTEGER) STRICT;

CREATE TABLE shorebird_release (
  app_id TEXT NOT NULL,
  version TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
  flutter_version TEXT NOT NULL,
  job_id TEXT NOT NULL,
  recorded_at INTEGER NOT NULL,
  PRIMARY KEY (app_id, version, platform)
) STRICT;

CREATE TABLE test_run (
  id TEXT PRIMARY KEY,
  job_id TEXT NOT NULL UNIQUE REFERENCES job (id) ON DELETE CASCADE,
  branch TEXT NOT NULL,
  baseline INTEGER NOT NULL DEFAULT 0 CHECK (baseline IN (0, 1)),
  results TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(results))
, project_id TEXT NOT NULL DEFAULT '', app_path TEXT NOT NULL DEFAULT '.', created_at INTEGER NOT NULL DEFAULT 0) STRICT;

CREATE TABLE workflow (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES project (id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  builtin INTEGER NOT NULL DEFAULT 0 CHECK (builtin IN (0, 1)), based_on_builtin TEXT, based_on_version INTEGER
  CHECK (based_on_version IS NULL OR based_on_version > 0), archived_at INTEGER,
  UNIQUE (project_id, name)
) STRICT;

CREATE TABLE workflow_version (
  id TEXT PRIMARY KEY,
  workflow_id TEXT NOT NULL REFERENCES workflow (id) ON DELETE CASCADE,
  version INTEGER NOT NULL CHECK (version > 0),
  yaml TEXT NOT NULL, created_at INTEGER NOT NULL DEFAULT 0,
  UNIQUE (workflow_id, version)
) STRICT;

CREATE UNIQUE INDEX idx_approval_binding ON approval (
  project_id, action, COALESCE(sha, ''), COALESCE(version, ''),
  COALESCE(run_id, '')
);

CREATE INDEX idx_approval_due ON approval (expires_at) WHERE state = 'pending';

CREATE INDEX idx_approval_project ON approval (project_id, state);

CREATE INDEX idx_artifact_job ON artifact (job_id);

CREATE UNIQUE INDEX idx_artifact_job_path ON artifact (job_id, path);

CREATE INDEX idx_artifact_sha256 ON artifact (sha256);

CREATE INDEX idx_credential_assignment_credential
  ON credential_assignment (credential_id, kind);

CREATE UNIQUE INDEX idx_credential_name ON credential (name COLLATE NOCASE);

CREATE INDEX idx_event_at ON event (at);

CREATE INDEX idx_job_project ON job (project_id, state);

CREATE INDEX idx_job_release ON job (release_id);

CREATE INDEX idx_job_run ON job (run_id, stage);

CREATE INDEX idx_job_runner ON job (runner_id);

CREATE INDEX idx_job_state ON job (state, lease_until);

CREATE INDEX idx_job_workflow_version ON job (workflow_version_id);

CREATE INDEX idx_pairing_token_expires ON pairing_token (expires_at);

CREATE INDEX idx_release_app ON release (app_id, state);

CREATE INDEX idx_run_project ON run (project_id, created_at);

CREATE INDEX idx_run_workflow_version ON run (workflow_version_id);

CREATE UNIQUE INDEX idx_runner_token ON runner (token_id);

CREATE INDEX idx_test_run_baseline
  ON test_run (project_id, app_path, branch, created_at) WHERE baseline = 1;
