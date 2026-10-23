import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('SqliteApprovalRepository', () {
    late SqliteDatabase database;
    Future<ApprovalRepository> create() async =>
        SqliteApprovalRepository(database);

    late ApprovalRepository repository;
    final created = DateTime.utc(2026, 10, 13, 9);
    const app = DecidedBy(
      tokenId: 'tok_app',
      name: 'Mac mini',
      kind: DeviceTokenKind.app,
    );
    const cli = DecidedBy(
      tokenId: 'tok_cli',
      name: 'laptop',
      kind: DeviceTokenKind.cli,
    );

    ApprovalRecord record(
      String id, {
      String projectId = 'prj_1',
      GateAction action = GateAction.prodRelease,
      String sha = 'aaaa',
      String? version = '1.0.0+1',
      String? runId = 'run_1',
      DateTime? at,
    }) => ApprovalRecord(
      id: id,
      projectId: projectId,
      action: action,
      sha: sha,
      version: version,
      runId: runId,
      jobId: 'job_1',
      createdAt: at ?? created,
      expiresAt: (at ?? created).add(approvalLifetime),
    );

    setUp(() async {
      database = SqliteDatabase.openInMemory();
      addTearDown(database.close);
      database.connection.execute(
        'INSERT INTO project (id, host, source_key, github_repo_id, remote, '
        'default_base_branch) '
        "VALUES ('prj_1', 'github.com', '1', 1, 'a', 'main'), ('prj_2', "
        "'github.com', '2', 2, 'b', 'main')",
      );
      repository = await create();
    });

    group('findOrCreate', () {
      test('stores a new binding', () async {
        final result = await repository.findOrCreate(record('apr_1'));

        expect(result.created, isTrue);
        expect(result.record, record('apr_1'));
        expect(await repository.get('apr_1'), record('apr_1'));
        expect(await repository.get('apr_x'), isNull);
      });

      test('returns the record that holds the binding', () async {
        await repository.findOrCreate(record('apr_1'));

        final again = await repository.findOrCreate(record('apr_2'));

        expect(again.created, isFalse);
        expect(again.record.id, 'apr_1');
        expect(await repository.get('apr_2'), isNull);
      });

      test('keeps a settled binding settled', () async {
        await repository.findOrCreate(record('apr_1'));
        await repository.decide(
          'apr_1',
          state: ApprovalState.denied,
          by: app,
          at: created,
        );

        final again = await repository.findOrCreate(record('apr_2'));

        expect(again.created, isFalse);
        expect(again.record.state, ApprovalState.denied);
      });

      test('treats a different binding as a new request', () async {
        await repository.findOrCreate(record('apr_1'));

        for (final (index, other) in [
          record('apr_a', projectId: 'prj_2'),
          record('apr_b', action: GateAction.push),
          record('apr_c', sha: 'bbbb'),
          record('apr_d', version: '1.0.0+2'),
          record('apr_e', version: null),
          record('apr_f', runId: 'run_2'),
          record('apr_g', runId: null),
        ].indexed) {
          final result = await repository.findOrCreate(other);

          expect(result.created, isTrue, reason: '$index');
        }
        expect(await repository.list(), hasLength(8));
      });

      test('finds a binding that has no version and no run', () async {
        await repository.findOrCreate(
          record('apr_1', version: null, runId: null),
        );

        final again = await repository.findOrCreate(
          record('apr_2', version: null, runId: null),
        );

        expect(again.created, isFalse);
        expect(again.record.id, 'apr_1');
      });
    });

    group('list', () {
      setUp(() async {
        await repository.findOrCreate(record('apr_1'));
        await repository.findOrCreate(record('apr_2', sha: 'bbbb'));
        await repository.findOrCreate(
          record('apr_3', projectId: 'prj_2', sha: 'cccc'),
        );
        await repository.decide(
          'apr_2',
          state: ApprovalState.approved,
          by: app,
          at: created,
        );
      });

      test('lists the newest first', () async {
        final all = await repository.list();

        expect([for (final r in all) r.id], ['apr_3', 'apr_2', 'apr_1']);
      });

      test('filters by project and by state', () async {
        expect(
          [for (final r in await repository.list(projectId: 'prj_1')) r.id],
          ['apr_2', 'apr_1'],
        );
        expect(
          [
            for (final r in await repository.list(state: ApprovalState.pending))
              r.id,
          ],
          ['apr_3', 'apr_1'],
        );
        expect(
          [
            for (final r in await repository.list(
              projectId: 'prj_1',
              state: ApprovalState.approved,
            ))
              r.id,
          ],
          ['apr_2'],
        );
        expect(await repository.list(projectId: 'prj_9'), isEmpty);
      });
    });

    group('decide', () {
      setUp(() => repository.findOrCreate(record('apr_1')));

      test('settles a pending approval with who and when', () async {
        final at = created.add(const Duration(hours: 2));

        final decided = await repository.decide(
          'apr_1',
          state: ApprovalState.approved,
          by: app,
          at: at,
          reason: 'ship it',
        );

        expect(decided!.state, ApprovalState.approved);
        expect(decided.decidedBy, app);
        expect(decided.decidedAt, at);
        expect(decided.reason, 'ship it');
        expect(await repository.get('apr_1'), decided);
      });

      test('lets exactly one of two decisions win', () async {
        final results = await Future.wait([
          repository.decide(
            'apr_1',
            state: ApprovalState.approved,
            by: app,
            at: created,
          ),
          repository.decide(
            'apr_1',
            state: ApprovalState.denied,
            by: cli,
            at: created,
          ),
        ]);

        expect(results.where((r) => r != null), hasLength(1));
        final winner = results.firstWhere((r) => r != null)!;
        expect((await repository.get('apr_1'))!.state, winner.state);
        expect((await repository.get('apr_1'))!.decidedBy, winner.decidedBy);
      });

      test('does not decide twice', () async {
        await repository.decide(
          'apr_1',
          state: ApprovalState.denied,
          by: cli,
          at: created,
        );

        final second = await repository.decide(
          'apr_1',
          state: ApprovalState.approved,
          by: app,
          at: created,
        );

        expect(second, isNull);
        expect((await repository.get('apr_1'))!.state, ApprovalState.denied);
        expect((await repository.get('apr_1'))!.decidedBy, cli);
      });

      test('does not decide an approval whose time is up', () async {
        final late = created.add(approvalLifetime);

        final decided = await repository.decide(
          'apr_1',
          state: ApprovalState.approved,
          by: app,
          at: late,
        );

        expect(decided, isNull);
        expect((await repository.get('apr_1'))!.state, ApprovalState.pending);
      });

      test('knows no approval that does not exist', () async {
        expect(
          await repository.decide(
            'apr_x',
            state: ApprovalState.approved,
            by: app,
            at: created,
          ),
          isNull,
        );
      });
    });

    group('expireDue', () {
      setUp(() async {
        await repository.findOrCreate(record('apr_1'));
        await repository.findOrCreate(
          record(
            'apr_2',
            sha: 'bbbb',
            at: created.add(const Duration(hours: 5)),
          ),
        );
        await repository.findOrCreate(record('apr_3', sha: 'cccc'));
        await repository.decide(
          'apr_3',
          state: ApprovalState.approved,
          by: app,
          at: created,
        );
      });

      test('expires the pending approvals whose time is up', () async {
        final now = created.add(approvalLifetime);

        final expired = await repository.expireDue(now, reason: 'too late');

        expect([for (final r in expired) r.id], ['apr_1']);
        final record1 = (await repository.get('apr_1'))!;
        expect(record1.state, ApprovalState.expired);
        expect(record1.decidedAt, now);
        expect(record1.decidedBy, isNull);
        expect(record1.reason, 'too late');
        expect((await repository.get('apr_2'))!.state, ApprovalState.pending);
        expect((await repository.get('apr_3'))!.state, ApprovalState.approved);
      });

      test('expires each approval once', () async {
        final now = created.add(approvalLifetime);
        await repository.expireDue(now, reason: 'r');

        expect(await repository.expireDue(now, reason: 'r'), isEmpty);
      });

      test('expires only the approval asked for', () async {
        final now = created.add(const Duration(days: 3));

        final expired = await repository.expireDue(
          now,
          reason: 'r',
          id: 'apr_2',
        );

        expect([for (final r in expired) r.id], ['apr_2']);
        expect((await repository.get('apr_1'))!.state, ApprovalState.pending);
      });

      test('leaves approvals whose time is not up', () async {
        expect(
          await repository.expireDue(
            created.add(const Duration(hours: 1)),
            reason: 'r',
          ),
          isEmpty,
        );
      });

      test('is not decided afterwards', () async {
        await repository.expireDue(created.add(approvalLifetime), reason: 'r');

        expect(
          await repository.decide(
            'apr_1',
            state: ApprovalState.approved,
            by: app,
            at: created.add(approvalLifetime),
          ),
          isNull,
        );
      });
    });

    group('in the database', () {
      Future<void> addAndDecide() async {
        await repository.findOrCreate(record('apr_1'));
        await repository.decide(
          'apr_1',
          state: ApprovalState.approved,
          by: app,
          at: created.add(const Duration(minutes: 7, microseconds: 123)),
          reason: 'ok',
        );
      }

      test('keeps times to the microsecond and the decider', () async {
        await addAndDecide();

        final read = (await repository.get('apr_1'))!;

        expect(
          read.decidedAt,
          created.add(const Duration(minutes: 7, microseconds: 123)),
        );
        expect(read.decidedAt!.isUtc, isTrue);
        expect(read.createdAt, created);
        expect(read.expiresAt, created.add(approvalLifetime));
        expect(read.decidedBy, app);
        expect(read.runId, 'run_1');
        expect(read.jobId, 'job_1');
      });

      test('stores the decision in the columns of the data model', () async {
        await addAndDecide();

        final row = database.connection
            .select(
              'SELECT action, state, decided_by, decided_by_name, '
              'decided_by_kind FROM approval',
            )
            .single;

        expect(row.values, [
          'prod_release',
          'approved',
          'tok_app',
          'Mac mini',
          'app',
        ]);
      });

      test('allows one row per binding', () async {
        await repository.findOrCreate(
          record('apr_1', version: null, runId: null),
        );

        expect(
          () => database.connection.execute(
            'INSERT INTO approval (id, project_id, action, sha, state) '
            "VALUES ('apr_2', 'prj_1', 'prod_release', 'aaaa', 'pending')",
          ),
          throwsA(isA<SqliteException>()),
          reason: 'a null version and run are the empty string in the index',
        );
      });

      test('only an app or a cli token can have decided', () async {
        await repository.findOrCreate(record('apr_1'));

        expect(
          () => database.connection.execute(
            "UPDATE approval SET decided_by_kind = 'mcp'",
          ),
          throwsA(isA<SqliteException>()),
        );
      });

      test('goes with its project', () async {
        await repository.findOrCreate(record('apr_1'));

        database.connection.execute("DELETE FROM project WHERE id = 'prj_1'");

        expect(await repository.get('apr_1'), isNull);
      });

      test('is not found by a project that does not exist', () {
        expect(
          () => repository.findOrCreate(record('apr_1', projectId: 'prj_9')),
          throwsA(isA<SqliteException>()),
        );
      });
    });
  });
}
