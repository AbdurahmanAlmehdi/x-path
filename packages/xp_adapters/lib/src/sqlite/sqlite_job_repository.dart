import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_adapters/src/sqlite/timestamps.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// Jobs and their steps in the `job` and `job_step` tables.
///
/// Job states are stored as their wire names (`waiting_for_resume`), step
/// states as their names. The `job_step` id is `<jobId>/<ordinal>`.
class SqliteJobRepository implements JobRepository {
  /// Creates a repository over a database.
  const new(this._database);

  final SqliteDatabase _database;

  Database get _db => _database.connection;

  static const _jobColumns =
      'id, workflow_version_id, project_id, release_id, sha, state, '
      'runner_id, run_id, stage, name, capabilities, message, created_at, '
      'started_at, finished_at';

  static const _stepColumns =
      'job_id, ordinal, kind, state, side_effect, input, attempts, result, '
      'message, pgid, log_path, started_at, finished_at';

  @override
  Future<void> create(JobRecord job, List<StepRecord> steps) async {
    _database.transaction(() {
      _db.execute(
        'INSERT INTO job ($_jobColumns) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          job.id,
          job.workflowVersionId,
          job.projectId,
          job.releaseId,
          job.sha,
          job.state.wire,
          job.runnerId,
          job.runId,
          job.stage,
          job.name,
          jsonEncode(job.capabilities),
          job.message,
          toDatabaseTime(job.createdAt),
          _time(job.startedAt),
          _time(job.finishedAt),
        ],
      );
      for (final step in steps) {
        _db.execute(
          'INSERT INTO job_step (id, $_stepColumns) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          ['${job.id}/${step.ordinal}', ..._stepValues(step)],
        );
      }
    });
  }

  @override
  Future<JobRecord?> get(String id) async {
    final rows = _db.select('SELECT $_jobColumns FROM job WHERE id = ?', [id]);
    return rows.isEmpty ? null : _jobFromRow(rows.single);
  }

  @override
  Future<List<StepRecord>> steps(String jobId) async => [
    for (final row in _db.select(
      'SELECT $_stepColumns FROM job_step WHERE job_id = ? ORDER BY ordinal',
      [jobId],
    ))
      _stepFromRow(row),
  ];

  @override
  Future<List<JobRecord>> list({required Set<JobState> states}) async => [
    for (final row in _db.select(
      'SELECT $_jobColumns FROM job '
      'WHERE state IN (${List.filled(states.length, '?').join(', ')}) '
      'ORDER BY rowid',
      [for (final state in states) state.wire],
    ))
      _jobFromRow(row),
  ];

  @override
  Future<List<JobRecord>> forRun(String runId) async => [
    for (final row in _db.select(
      'SELECT $_jobColumns FROM job WHERE run_id = ? ORDER BY stage, rowid',
      [runId],
    ))
      _jobFromRow(row),
  ];

  @override
  Future<void> updateJob(JobRecord job) async {
    _db.execute(
      'UPDATE job SET state = ?, runner_id = ?, message = ?, started_at = ?, '
      'finished_at = ? WHERE id = ?',
      [
        job.state.wire,
        job.runnerId,
        job.message,
        _time(job.startedAt),
        _time(job.finishedAt),
        job.id,
      ],
    );
    if (_db.updatedRows == 0) throw StateError('There is no job ${job.id}.');
  }

  @override
  Future<void> saveTools(String jobId, JobTools tools) async {
    _db.execute('UPDATE job SET tools = ? WHERE id = ?', [
      jsonEncode(tools.toJson()),
      jobId,
    ]);
    if (_db.updatedRows == 0) throw StateError('There is no job $jobId.');
  }

  @override
  Future<JobTools?> tools(String jobId) async {
    final rows = _db.select('SELECT tools FROM job WHERE id = ?', [jobId]);
    final json = rows.isEmpty ? null : rows.single['tools'] as String?;
    return json == null
        ? null
        : JobTools.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  @override
  Future<void> updateStep(StepRecord step) async {
    _db.execute(
      'UPDATE job_step SET state = ?, attempts = ?, result = ?, message = ?, '
      'pgid = ?, log_path = ?, started_at = ?, finished_at = ? '
      'WHERE job_id = ? AND ordinal = ?',
      [
        step.state.name,
        step.attempts,
        _json(step.result),
        step.message,
        step.pgid,
        step.logPath,
        _time(step.startedAt),
        _time(step.finishedAt),
        step.jobId,
        step.ordinal,
      ],
    );
    if (_db.updatedRows == 0) {
      throw StateError(
        'There is no step ${step.ordinal} in job ${step.jobId}.',
      );
    }
  }

  static int _flag(bool value) => value ? 1 : 0;

  static String? _json(Object? value) =>
      value == null ? null : jsonEncode(value);

  static int? _time(DateTime? time) =>
      time == null ? null : toDatabaseTime(time);

  static DateTime? _fromTime(Object? value) =>
      value == null ? null : fromDatabaseTime(value as int);

  /// The values of a step in the order of [_stepColumns].
  static List<Object?> _stepValues(StepRecord step) => [
    step.jobId,
    step.ordinal,
    step.kind,
    step.state.name,
    _flag(step.sideEffect),
    jsonEncode(step.input),
    step.attempts,
    _json(step.result),
    step.message,
    step.pgid,
    step.logPath,
    _time(step.startedAt),
    _time(step.finishedAt),
  ];

  static JobRecord _jobFromRow(Row row) => JobRecord(
    id: row['id'] as String,
    workflowVersionId: row['workflow_version_id'] as String,
    projectId: row['project_id'] as String,
    releaseId: row['release_id'] as String?,
    sha: row['sha'] as String?,
    state: JobState.values.firstWhere((s) => s.wire == row['state']),
    runnerId: row['runner_id'] as String?,
    runId: row['run_id'] as String?,
    stage: row['stage'] as int,
    name: row['name'] as String?,
    capabilities: (jsonDecode(row['capabilities'] as String) as List<dynamic>)
        .cast<String>(),
    message: row['message'] as String?,
    createdAt: fromDatabaseTime(row['created_at'] as int),
    startedAt: _fromTime(row['started_at']),
    finishedAt: _fromTime(row['finished_at']),
  );

  static StepRecord _stepFromRow(Row row) => StepRecord(
    jobId: row['job_id'] as String,
    ordinal: row['ordinal'] as int,
    kind: row['kind'] as String,
    state: StepState.values.byName(row['state'] as String),
    sideEffect: row['side_effect'] == 1,
    input: jsonDecode(row['input'] as String) as Map<String, dynamic>,
    attempts: row['attempts'] as int,
    result: row['result'] == null
        ? null
        : jsonDecode(row['result'] as String) as Map<String, dynamic>,
    message: row['message'] as String?,
    pgid: row['pgid'] as int?,
    logPath: row['log_path'] as String?,
    startedAt: _fromTime(row['started_at']),
    finishedAt: _fromTime(row['finished_at']),
  );
}
