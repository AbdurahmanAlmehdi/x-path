import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

final _created = DateTime.utc(2026, 10, 13, 9, 30, 15, 123, 456);

JobRecord _job(
  String id, {
  JobState state = JobState.queued,
  String? message,
  DateTime? startedAt,
  DateTime? finishedAt,
}) => JobRecord(
  id: id,
  workflowVersionId: 'wfv_1',
  projectId: 'prj_1',
  sha: 'a' * 40,
  state: state,
  message: message,
  createdAt: _created,
  startedAt: startedAt,
  finishedAt: finishedAt,
);

StepRecord _step(String jobId, int ordinal, {bool sideEffect = false}) =>
    StepRecord(
      jobId: jobId,
      ordinal: ordinal,
      kind: 'command',
      sideEffect: sideEffect,
      input: {'executable': 'step$ordinal'},
    );

void main() {
  late SqliteDatabase database;
  late SqliteJobRepository repository;

  setUp(() {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    // A job refers to a project and a workflow version.
    database.connection
      ..execute(
        'INSERT INTO project (id, github_repo_id, remote, '
        "default_base_branch) VALUES ('prj_1', 1, 'r', 'main')",
      )
      ..execute(
        'INSERT INTO workflow (id, project_id, name) '
        "VALUES ('wf_1', 'prj_1', 'w')",
      )
      ..execute(
        'INSERT INTO workflow_version (id, workflow_id, version, yaml) '
        "VALUES ('wfv_1', 'wf_1', 1, '')",
      );
    repository = SqliteJobRepository(database);
  });

  group('lease', () {
    final until = _created.add(const Duration(seconds: 90));

    void addRunner(String id) => database.connection.execute(
      'INSERT INTO runner (id, name) VALUES (?, ?)',
      [id, 'runner $id'],
    );

    test('is stored with the job and read back', () async {
      addRunner('rnr_1');
      final leased = _job(
        'job_1',
        state: JobState.running,
      ).copyWith(runnerId: 'rnr_1', leaseUntil: until);

      await repository.create(leased, const []);

      expect(await repository.get('job_1'), leased);
      expect(
        (await repository.list(states: {JobState.running})).single.leaseUntil,
        until,
      );
    });

    test('is saved and cleared by updateJob', () async {
      addRunner('rnr_1');
      await repository.create(_job('job_1'), const []);

      await repository.updateJob(
        _job(
          'job_1',
          state: JobState.running,
        ).copyWith(runnerId: 'rnr_1', leaseUntil: until),
      );
      final leased = (await repository.get('job_1'))!;
      expect(leased.runnerId, 'rnr_1');
      expect(leased.leaseUntil, until);

      await repository.updateJob(
        leased.copyWith(
          state: JobState.queued,
          runnerId: null,
          leaseUntil: null,
        ),
      );
      final released = (await repository.get('job_1'))!;
      expect(released.runnerId, isNull);
      expect(released.leaseUntil, isNull);
    });

    test('renewLease moves the end of the lease and nothing else', () async {
      addRunner('rnr_1');
      await repository.create(
        _job(
          'job_1',
          state: JobState.running,
          message: 'm',
        ).copyWith(runnerId: 'rnr_1', leaseUntil: _created),
        const [],
      );

      final renewed = await repository.renewLease(
        'job_1',
        runnerId: 'rnr_1',
        until: until,
      );

      expect(renewed, isTrue);
      final stored = (await repository.get('job_1'))!;
      expect(stored.leaseUntil, until);
      expect(stored.state, JobState.running);
      expect(stored.message, 'm');
    });

    test('renewLease does nothing for another runner, state or job', () async {
      addRunner('rnr_1');
      addRunner('rnr_2');
      await repository.create(
        _job(
          'job_1',
          state: JobState.running,
        ).copyWith(runnerId: 'rnr_1', leaseUntil: _created),
        const [],
      );
      await repository.create(
        _job(
          'job_2',
          state: JobState.cancelled,
        ).copyWith(runnerId: 'rnr_1', leaseUntil: _created),
        const [],
      );

      expect(
        await repository.renewLease('job_1', runnerId: 'rnr_2', until: until),
        isFalse,
      );
      expect(
        await repository.renewLease('job_2', runnerId: 'rnr_1', until: until),
        isFalse,
      );
      expect(
        await repository.renewLease('nope', runnerId: 'rnr_1', until: until),
        isFalse,
      );
      expect((await repository.get('job_1'))!.leaseUntil, _created);
      expect((await repository.get('job_2'))!.leaseUntil, _created);
    });
  });

  test('stores a job and its steps', () async {
    await repository.create(_job('job_1'), [
      _step('job_1', 0),
      _step('job_1', 1, sideEffect: true),
    ]);

    expect(await repository.get('job_1'), _job('job_1'));
    final steps = await repository.steps('job_1');
    expect(steps.map((s) => (s.ordinal, s.sideEffect, s.state)), [
      (0, false, StepState.pending),
      (1, true, StepState.pending),
    ]);
    expect(steps.first.input, {'executable': 'step0'});
    expect(await repository.get('job_x'), isNull);
    expect(await repository.steps('job_x'), isEmpty);
  });

  test('keeps the needs of a job and why Linux was ruled out', () async {
    final job = JobRecord(
      id: 'job_ios',
      workflowVersionId: 'wfv_1',
      projectId: 'prj_1',
      state: JobState.queued,
      createdAt: _created,
      capabilities: const ['flutter', 'ios-sign|ios-linux'],
      narrowing: const ['the app uses the flavor prod'],
    );

    await repository.create(job, const []);
    await repository.updateJob(job.copyWith(message: 'Waiting.'));

    final stored = (await repository.get('job_ios'))!;
    expect(stored.capabilities, ['flutter', 'ios-sign|ios-linux']);
    expect(stored.narrowing, ['the app uses the flavor prod']);
    expect((await repository.get('job_1'))?.narrowing, isNull);
  });

  test('keeps the times to the microsecond, in UTC', () async {
    await repository.create(_job('job_1'), const []);

    final read = (await repository.get('job_1'))!;

    expect(read.createdAt, _created);
    expect(read.createdAt.isUtc, isTrue);
    expect(read.startedAt, isNull);
  });

  test('stores nothing of a job whose steps clash', () async {
    await expectLater(
      repository.create(_job('job_1'), [_step('job_1', 0), _step('job_1', 0)]),
      throwsA(isA<SqliteException>()),
    );

    expect(await repository.get('job_1'), isNull);
  });

  test('updates the state, message and times of a job', () async {
    await repository.create(_job('job_1'), const []);
    final later = _created.add(const Duration(minutes: 2));

    await repository.updateJob(
      _job(
        'job_1',
        state: JobState.waitingForResume,
        message: 'engine stopped',
        startedAt: _created,
        finishedAt: later,
      ),
    );

    final read = (await repository.get('job_1'))!;
    expect(read.state, JobState.waitingForResume);
    expect(read.message, 'engine stopped');
    expect(read.startedAt, _created);
    expect(read.finishedAt, later);
    final raw = database.connection
        .select("SELECT state FROM job WHERE id = 'job_1'")
        .single['state'];
    expect(raw, 'waiting_for_resume');
  });

  test('records the tool versions of a job, replacing earlier ones', () async {
    await repository.create(_job('job_1'), const []);
    expect(await repository.tools('job_1'), isNull);

    await repository.saveTools('job_1', const JobTools(flutter: '3.47.5'));
    await repository.saveTools(
      'job_1',
      const JobTools(
        flutter: '3.47.6',
        dart: '3.13.5',
        shorebird: '1.6.128',
        gh: '2.96.0',
        xcode: '27.1',
      ),
    );

    final tools = await repository.tools('job_1');
    expect(tools?.flutter, '3.47.6');
    expect(tools?.xcode, '27.1');
    expect(tools?.toJson(), hasLength(5));
    expect(await repository.get('job_1'), _job('job_1'));
  });

  test('stores tools as JSON and leaves out what is missing', () async {
    await repository.create(_job('job_1'), const []);

    await repository.saveTools('job_1', const JobTools(flutter: '3.47.6'));

    expect(
      database.connection.select('SELECT tools FROM job').single['tools'],
      '{"flutter":"3.47.6"}',
    );
  });

  test('has no tools for a job that is not there', () async {
    expect(await repository.tools('job_x'), isNull);
    await expectLater(
      repository.saveTools('job_x', const JobTools()),
      throwsStateError,
    );
  });

  test('cannot update a job that is not there', () async {
    await expectLater(repository.updateJob(_job('nope')), throwsStateError);
  });

  test('updates a step with everything the runner records', () async {
    await repository.create(_job('job_1'), [_step('job_1', 0)]);
    final later = _created.add(const Duration(seconds: 9));

    await repository.updateStep(
      _step('job_1', 0).copyWith(
        state: StepState.succeeded,
        attempts: 2,
        result: {
          'exitCode': 0,
          'nested': [1, 2],
        },
        message: 'fine',
        pgid: 4242,
        logPath: '/logs/job_1/0-command.log',
        startedAt: _created,
        finishedAt: later,
      ),
    );

    final read = (await repository.steps('job_1')).single;
    expect(read.state, StepState.succeeded);
    expect(read.attempts, 2);
    expect(read.result, {
      'exitCode': 0,
      'nested': [1, 2],
    });
    expect(read.message, 'fine');
    expect(read.pgid, 4242);
    expect(read.logPath, '/logs/job_1/0-command.log');
    expect(read.startedAt, _created);
    expect(read.finishedAt, later);
    expect(read.input, {'executable': 'step0'});
  });

  test('clears the result and the process group', () async {
    await repository.create(_job('job_1'), [_step('job_1', 0)]);
    await repository.updateStep(
      _step('job_1', 0).copyWith(result: {'a': 1}, pgid: 7),
    );

    await repository.updateStep(
      _step('job_1', 0).copyWith(result: null, pgid: null),
    );

    final read = (await repository.steps('job_1')).single;
    expect(read.result, isNull);
    expect(read.pgid, isNull);
  });

  test('cannot update a step that is not there', () async {
    await repository.create(_job('job_1'), [_step('job_1', 0)]);

    await expectLater(
      repository.updateStep(_step('job_1', 5)),
      throwsStateError,
    );
  });

  test('lists the jobs in the states asked for, oldest first', () async {
    await repository.create(_job('job_a', state: JobState.running), const []);
    await repository.create(_job('job_b', state: JobState.failed), const []);
    await repository.create(_job('job_c', state: JobState.running), const []);
    await repository.create(
      _job('job_d', state: JobState.waitingForResume),
      const [],
    );

    expect(
      (await repository.list(states: {JobState.running})).map((j) => j.id),
      ['job_a', 'job_c'],
    );
    expect(
      (await repository.list(
        states: {JobState.waitingForResume, JobState.failed},
      )).map((j) => j.id),
      ['job_b', 'job_d'],
    );
    expect(await repository.list(states: const {}), isEmpty);
  });

  test('deletes the steps with their job', () async {
    await repository.create(_job('job_1'), [_step('job_1', 0)]);

    database.connection.execute("DELETE FROM job WHERE id = 'job_1'");

    expect(await repository.steps('job_1'), isEmpty);
  });

  test('deletes a job with its steps, artifacts and test run', () async {
    await repository.create(_job('job_1'), [_step('job_1', 0)]);
    await repository.create(_job('job_2'), [_step('job_2', 0)]);
    database.connection
      ..execute(
        'INSERT INTO artifact (id, job_id, kind, path, size, sha256) '
        "VALUES ('art_1', 'job_1', 'apk', 'job_1/a.apk', 1, 'x')",
      )
      ..execute(
        'INSERT INTO test_run (id, job_id, branch) '
        "VALUES ('tst_1', 'job_1', 'main')",
      );

    expect(await repository.delete('job_1'), isTrue);

    expect(await repository.get('job_1'), isNull);
    expect(await repository.steps('job_1'), isEmpty);
    expect(database.connection.select('SELECT * FROM artifact'), isEmpty);
    expect(database.connection.select('SELECT * FROM test_run'), isEmpty);
    expect(await repository.get('job_2'), isNotNull);
    expect(await repository.steps('job_2'), hasLength(1));
  });

  test('deleting a job it does not have answers false', () async {
    expect(await repository.delete('job_9'), isFalse);
  });
}
