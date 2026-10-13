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
, created_at INTEGER NOT NULL DEFAULT 0) STRICT;

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

CREATE TABLE device_token (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('app', 'cli', 'mcp', 'runner')),
  hash TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  revoked_at INTEGER
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
  version_files TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(version_files)),
  UNIQUE (app_id, name)
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
  CHECK (tools IS NULL OR json_valid(tools))) STRICT;

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

CREATE TABLE project (
  id TEXT PRIMARY KEY,
  github_repo_id INTEGER NOT NULL UNIQUE,
  remote TEXT NOT NULL,
  default_base_branch TEXT NOT NULL,
  release_model TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(release_model)),
  gates TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(gates))
, full_name TEXT NOT NULL DEFAULT '', local_path TEXT, github_default_branch TEXT NOT NULL DEFAULT '', scan TEXT NOT NULL DEFAULT '{}'
  CHECK (json_valid(scan)), findings TEXT NOT NULL DEFAULT '[]'
  CHECK (json_valid(findings)), scanned_at INTEGER NOT NULL DEFAULT 0, edits TEXT NOT NULL DEFAULT '{}'
  CHECK (json_valid(edits))) STRICT;

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

CREATE TABLE runner (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  capabilities TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(capabilities)),
  slots INTEGER NOT NULL DEFAULT 1 CHECK (slots > 0),
  last_heartbeat INTEGER
) STRICT;

CREATE TABLE test_run (
  id TEXT PRIMARY KEY,
  job_id TEXT NOT NULL UNIQUE REFERENCES job (id) ON DELETE CASCADE,
  branch TEXT NOT NULL,
  baseline INTEGER NOT NULL DEFAULT 0 CHECK (baseline IN (0, 1)),
  results TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(results))
) STRICT;

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

CREATE INDEX idx_approval_project ON approval (project_id, state);

CREATE INDEX idx_artifact_job ON artifact (job_id);

CREATE UNIQUE INDEX idx_artifact_job_path ON artifact (job_id, path);

CREATE INDEX idx_artifact_sha256 ON artifact (sha256);

CREATE INDEX idx_credential_ref_flavor ON credential_ref (flavor_id);

CREATE INDEX idx_event_at ON event (at);

CREATE INDEX idx_job_project ON job (project_id, state);

CREATE INDEX idx_job_release ON job (release_id);

CREATE INDEX idx_job_runner ON job (runner_id);

CREATE INDEX idx_job_state ON job (state, lease_until);

CREATE INDEX idx_job_workflow_version ON job (workflow_version_id);

CREATE INDEX idx_release_app ON release (app_id, state);
