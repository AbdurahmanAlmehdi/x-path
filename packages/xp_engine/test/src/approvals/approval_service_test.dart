import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/approval_harness.dart';

void main() {
  late ApprovalHarness h;
  final app = tokenOf(DeviceTokenKind.app, name: 'Mac mini');
  final cli = tokenOf(DeviceTokenKind.cli, name: 'laptop');
  final mcp = tokenOf(DeviceTokenKind.mcp);
  final runner = tokenOf(DeviceTokenKind.runner);

  setUp(() async => h = await ApprovalHarness.create());

  Future<String> ask([GateRequest? request]) async {
    final decision = await h.service.check(request ?? gateRequest());
    return (decision as GatePending).approvalId!;
  }

  group('check', () {
    test('creates a pending request and announces it', () async {
      final decision = await h.service.check(gateRequest());

      expect(decision, isA<GatePending>());
      final id = (decision as GatePending).approvalId!;
      final approval = await h.service.get(id);
      expect(approval.state, ApprovalState.pending);
      expect(approval.projectId, 'prj_1');
      expect(approval.action, 'prod_release');
      expect(approval.sha, approvalSha);
      expect(approval.version, '1.2.3+45');
      expect(approval.jobId, 'job_1');
      expect(approval.createdAt, h.clock.now());
      expect(approval.expiresAt, h.clock.now().add(approvalLifetime));
      expect(await h.logged(), [
        ApprovalRequested(
          approvalId: id,
          projectId: 'prj_1',
          action: 'prod_release',
          sha: approvalSha,
          version: '1.2.3+45',
          expiresAt: approval.expiresAt,
        ),
      ]);
    });

    test('is the same question when asked again', () async {
      final first = await ask();
      h.clock.advance(const Duration(hours: 3));

      final second = await ask();

      expect(second, first);
      expect(await h.service.list(), hasLength(1));
      expect(await h.logged(), hasLength(1));
      expect((await h.service.get(first)).expiresAt, isNot(h.clock.now()));
    });

    test('shares the request between the jobs of a run', () async {
      final first = await ask(gateRequest());
      final second = await ask(gateRequest(jobId: 'job_2'));

      expect(second, first);
      expect((await h.service.get(first)).jobId, 'job_1');
    });

    test('is a new request for another commit, version or action', () async {
      final base = await ask();

      expect(await ask(gateRequest(sha: 'b' * 40)), isNot(base));
      expect(await ask(gateRequest(version: '1.2.3+46')), isNot(base));
      expect(await ask(gateRequest(version: null)), isNot(base));
      expect(await ask(gateRequest(action: GateAction.push)), isNot(base));
      expect(await ask(gateRequest(projectId: 'prj_2')), isNot(base));
      expect(await h.service.list(), hasLength(6));
    });

    test('is a new request for a new run', () async {
      await h.jobs.create(_job('job_1', runId: 'run_1'), const []);
      await h.jobs.create(_job('job_2', runId: 'run_2'), const []);
      final first = await ask(gateRequest());
      final sameRun = await ask(gateRequest());
      final second = await ask(gateRequest(jobId: 'job_2'));

      expect(sameRun, first);
      expect(second, isNot(first));
      expect((await h.service.get(first)).runId, 'run_1');
      expect((await h.service.get(second)).runId, 'run_2');
    });

    test('approves at once where the project turned the gate off', () async {
      await h.service.setGates(
        'prj_1',
        const ProjectGates({'prod_release': false}),
        by: app,
      );

      expect(await h.service.check(gateRequest()), isA<GateApproved>());
      expect(await h.service.list(), isEmpty);
      expect(
        await h.service.check(gateRequest(action: GateAction.push)),
        isA<GatePending>(),
      );
    });

    test('approves once the owner approved', () async {
      final id = await ask();

      await h.service.decide(id, approve: true, by: app);

      expect(await h.service.check(gateRequest()), isA<GateApproved>());
      expect(await h.service.list(), hasLength(1));
    });

    test('denies, with who and why, once the owner denied', () async {
      final id = await ask();

      await h.service.decide(id, approve: false, by: cli, reason: 'not today');
      final decision = await h.service.check(gateRequest());

      expect(
        decision,
        isA<GateDenied>().having(
          (denied) => denied.reason,
          'reason',
          'denied by laptop (cli): not today.',
        ),
      );
    });

    test('denies without a reason when the owner gave none', () async {
      final id = await ask();
      await h.service.decide(id, approve: false, by: app);

      expect(
        (await h.service.check(gateRequest()) as GateDenied).reason,
        'denied by Mac mini (app).',
      );
    });

    test('keeps a denial: asking again does not ask the owner again', () async {
      final id = await ask();
      await h.service.decide(id, approve: false, by: app);

      await h.service.check(gateRequest());
      await h.service.check(gateRequest());

      expect(await h.service.list(), hasLength(1));
      expect(await h.logged(), hasLength(2));
    });

    test('denies once 24 hours passed, and says so', () async {
      final id = await ask();
      h.clock.advance(approvalLifetime);

      final decision = await h.service.check(gateRequest());

      expect(
        decision,
        isA<GateDenied>().having(
          (denied) => denied.reason,
          'reason',
          allOf(contains('24 hours'), contains(id), contains('expired')),
        ),
      );
      expect((await h.service.get(id)).state, ApprovalState.expired);
    });

    test('does not resume the job that asks when it finds an expiry', () async {
      await ask();
      h.clock.advance(approvalLifetime);

      await h.service.check(gateRequest());

      expect(h.resumed, isEmpty);
    });

    test('announces an expiry it found, once', () async {
      final id = await ask();
      h.clock.advance(approvalLifetime);

      await h.service.check(gateRequest());
      await h.service.check(gateRequest());

      final expired = (await h.logged()).whereType<ApprovalExpired>();
      expect(expired, [
        ApprovalExpired(
          approvalId: id,
          projectId: 'prj_1',
          action: 'prod_release',
        ),
      ]);
    });

    test('is just short of an expiry a second before the time is up', () async {
      await ask();
      h.clock.advance(approvalLifetime - const Duration(seconds: 1));

      expect(await h.service.check(gateRequest()), isA<GatePending>());
    });
  });

  group('decide', () {
    test('approves, announces, and resumes the waiting jobs', () async {
      final id = await ask();
      h.clock.advance(const Duration(minutes: 5));

      final approval = await h.service.decide(
        id,
        approve: true,
        by: app,
        reason: '  looks right  ',
      );

      expect(approval.state, ApprovalState.approved);
      expect(approval.decidedAt, h.clock.now());
      expect(approval.reason, 'looks right');
      expect(
        approval.decidedBy,
        const DecidedBy(
          tokenId: 'tok_app',
          name: 'Mac mini',
          kind: DeviceTokenKind.app,
        ),
      );
      expect(await h.service.get(id), approval);
      expect(
        (await h.logged()).last,
        ApprovalDecided(
          approvalId: id,
          projectId: 'prj_1',
          action: 'prod_release',
          state: ApprovalState.approved,
          decidedBy: approval.decidedBy!,
        ),
      );
      expect(h.resumed, ['prj_1']);
    });

    test('denies as a cli token', () async {
      final id = await ask();

      final approval = await h.service.decide(id, approve: false, by: cli);

      expect(approval.state, ApprovalState.denied);
      expect(approval.decidedBy!.kind, DeviceTokenKind.cli);
      expect(approval.reason, isNull);
      expect(h.resumed, ['prj_1']);
    });

    test('drops a blank reason', () async {
      final id = await ask();

      final approval = await h.service.decide(
        id,
        approve: true,
        by: app,
        reason: '   ',
      );

      expect(approval.reason, isNull);
    });

    for (final token in [mcp, runner]) {
      test('is forbidden to a ${token.kind.name} token', () async {
        final id = await ask();

        await expectLater(
          h.service.decide(id, approve: true, by: token),
          throwsA(
            isA<ApprovalForbiddenException>().having(
              (error) => error.message,
              'message',
              allOf(contains(token.kind.name), contains('cannot approve')),
            ),
          ),
        );
        await expectLater(
          h.service.decide(id, approve: false, by: token),
          throwsA(
            isA<ApprovalForbiddenException>().having(
              (error) => error.message,
              'message',
              contains('cannot deny'),
            ),
          ),
        );
        expect((await h.service.get(id)).state, ApprovalState.pending);
        expect(h.resumed, isEmpty);
      });
    }

    test('is forbidden to an mcp token even for an approval that is gone', () {
      expect(
        h.service.decide('apr_x', approve: true, by: mcp),
        throwsA(isA<ApprovalForbiddenException>()),
      );
    });

    test('is not found for an approval that does not exist', () {
      expect(
        h.service.decide('apr_x', approve: true, by: app),
        throwsA(isA<ApprovalNotFoundException>()),
      );
    });

    test('lets the first decision win and tells the rest who did', () async {
      final id = await ask();
      await h.service.decide(
        id,
        approve: false,
        by: cli,
        reason: 'wrong build',
      );

      await expectLater(
        h.service.decide(id, approve: true, by: app),
        throwsA(
          isA<ApprovalAlreadyDecidedException>()
              .having(
                (error) => error.approval.state,
                'state',
                ApprovalState.denied,
              )
              .having(
                (error) => error.approval.decidedBy!.name,
                'decided by',
                'laptop',
              )
              .having((error) => error.message, 'message', contains('denied')),
        ),
      );
      expect((await h.service.get(id)).state, ApprovalState.denied);
      expect(h.resumed, ['prj_1']);
    });

    test('lets exactly one of two concurrent decisions win', () async {
      final id = await ask();

      final results = await Future.wait([
        h.service
            .decide(id, approve: true, by: app)
            .then<Object>((approval) => approval, onError: (Object e) => e),
        h.service
            .decide(id, approve: false, by: cli)
            .then<Object>((approval) => approval, onError: (Object e) => e),
      ]);

      final winners = results.whereType<Approval>().toList();
      final losers = results.whereType<ApprovalAlreadyDecidedException>();
      expect(winners, hasLength(1));
      expect(losers, hasLength(1));
      expect(losers.single.approval, winners.single);
      expect(await h.service.get(id), winners.single);
      expect((await h.logged()).whereType<ApprovalDecided>(), hasLength(1));
    });

    test(
      'reports the winner when the write is lost to another decision',
      () async {
        final repository = _RacingRepository();
        final racing = await ApprovalHarness.create(approvals: repository);
        final id = (await racing.service.check(
          gateRequest(),
        ) as GatePending).approvalId!;
        repository.beforeDecide = () => repository.inner.decide(
          id,
          state: ApprovalState.denied,
          by: const DecidedBy(
            tokenId: 'tok_cli',
            name: 'laptop',
            kind: DeviceTokenKind.cli,
          ),
          at: racing.clock.now(),
        );

        await expectLater(
          racing.service.decide(id, approve: true, by: app),
          throwsA(
            isA<ApprovalAlreadyDecidedException>().having(
              (error) => error.approval.state,
              'state',
              ApprovalState.denied,
            ),
          ),
        );
        expect(racing.resumed, isEmpty);
      },
    );

    test('cannot approve what expired', () async {
      final id = await ask();
      h.clock.advance(approvalLifetime);

      await expectLater(
        h.service.decide(id, approve: true, by: app),
        throwsA(
          isA<ApprovalAlreadyDecidedException>()
              .having(
                (error) => error.approval.state,
                'state',
                ApprovalState.expired,
              )
              .having(
                (error) => error.message,
                'message',
                contains('counts as denied'),
              ),
        ),
      );
      expect(await h.logged(), contains(isA<ApprovalExpired>()));
    });
  });

  group('get and list', () {
    test('get is not found for an unknown id', () {
      expect(h.service.get('apr_x'), throwsA(isA<ApprovalNotFoundException>()));
    });

    test(
      'get expires a request whose time is up and resumes its jobs',
      () async {
        final id = await ask();
        h.clock.advance(approvalLifetime);

        final approval = await h.service.get(id);

        expect(approval.state, ApprovalState.expired);
        expect(approval.decidedAt, h.clock.now());
        expect(approval.decidedBy, isNull);
        expect(approval.reason, contains('24 hours'));
        expect(h.resumed, ['prj_1']);
      },
    );

    test('list filters by project and state, newest first', () async {
      final first = await ask();
      h.clock.advance(const Duration(minutes: 1));
      final second = await ask(gateRequest(action: GateAction.push));
      final other = await ask(gateRequest(projectId: 'prj_2'));
      await h.service.decide(second, approve: true, by: app);

      expect(
        [for (final a in await h.service.list()) a.id],
        [other, second, first],
      );
      expect(
        [for (final a in await h.service.list(projectId: 'prj_1')) a.id],
        [second, first],
      );
      expect(
        [
          for (final a in await h.service.list(state: ApprovalState.pending))
            a.id,
        ],
        [other, first],
      );
    });

    test('list expires what is due first', () async {
      await ask();
      h.clock.advance(approvalLifetime);

      final approvals = await h.service.list();

      expect(approvals.single.state, ApprovalState.expired);
      expect(await h.service.list(state: ApprovalState.pending), isEmpty);
    });
  });

  group('sweep', () {
    test(
      'expires what is due, announces each and resumes each project',
      () async {
        final a = await ask();
        final b = await ask(gateRequest(action: GateAction.push));
        final c = await ask(gateRequest(projectId: 'prj_2'));
        h.clock.advance(const Duration(hours: 1));
        final later = await ask(gateRequest(sha: 'c' * 40));
        h.clock.advance(approvalLifetime - const Duration(hours: 1));

        final expired = await h.service.sweep();

        expect(expired, 3);
        expect(
          (await h.logged()).whereType<ApprovalExpired>().map(
            (e) => e.approvalId,
          ),
          [a, b, c],
        );
        expect(h.resumed, ['prj_1', 'prj_2']);
        expect((await h.service.get(later)).state, ApprovalState.pending);
      },
    );

    test('has nothing to do when nothing is due', () async {
      await ask();

      expect(await h.service.sweep(), 0);
      expect(h.resumed, isEmpty);
    });
  });

  group('gates', () {
    test('are all on for a project that never set them', () async {
      final gates = await h.service.gates('prj_1');

      expect(gates.gates.keys, GateAction.values.map((a) => a.wire));
      expect(gates.gates.values, everyElement(isTrue));
    });

    test('gates is not found for an unknown project', () {
      expect(
        h.service.gates('prj_9'),
        throwsA(isA<ProjectNotFoundException>()),
      );
    });

    test('an app token loosens them, announced and resuming jobs', () async {
      final gates = await h.service.setGates(
        'prj_1',
        const ProjectGates({'push': false, 'merge': false}),
        by: app,
      );

      expect(gates.gates['push'], isFalse);
      expect(gates.gates['merge'], isFalse);
      expect(gates.gates['prod_release'], isTrue);
      expect(await h.service.gates('prj_1'), gates);
      expect(await h.logged(), [
        ProjectGatesChanged(
          projectId: 'prj_1',
          gates: gates.gates,
          changedBy: DeviceTokenKind.app,
        ),
      ]);
      expect(h.resumed, ['prj_1']);
    });

    test('an app token tightens them without resuming jobs', () async {
      await h.service.setGates(
        'prj_1',
        const ProjectGates({'push': false}),
        by: app,
      );
      h.resumed.clear();

      final gates = await h.service.setGates(
        'prj_1',
        const ProjectGates({'push': true}),
        by: app,
      );

      expect(gates.gates['push'], isTrue);
      expect(h.resumed, isEmpty);
    });

    test('a cli token tightens them', () async {
      await h.service.setGates(
        'prj_1',
        const ProjectGates({'push': false}),
        by: app,
      );

      final gates = await h.service.setGates(
        'prj_1',
        const ProjectGates({'push': true}),
        by: cli,
      );

      expect(gates.gates['push'], isTrue);
      expect(
        (await h.logged()).whereType<ProjectGatesChanged>().last.changedBy,
        DeviceTokenKind.cli,
      );
    });

    test('a cli token may not loosen them, and says what to do', () async {
      await expectLater(
        h.service.setGates(
          'prj_1',
          const ProjectGates({'push': false, 'delete': false}),
          by: cli,
        ),
        throwsA(
          isA<ApprovalForbiddenException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('cli token can turn gates on but not off'),
              contains('push, delete'),
              contains('in the app'),
            ),
          ),
        ),
      );
      expect((await h.service.gates('prj_1')).gates['push'], isTrue);
      expect(await h.logged(), isEmpty);
      expect(h.resumed, isEmpty);
    });

    test('a cli token may keep a gate off that is off', () async {
      await h.service.setGates(
        'prj_1',
        const ProjectGates({'push': false}),
        by: app,
      );

      final gates = await h.service.setGates(
        'prj_1',
        const ProjectGates({'push': false, 'merge': true}),
        by: cli,
      );

      expect(gates.gates['push'], isFalse);
    });

    for (final token in [mcp, runner]) {
      test('a ${token.kind.name} token never changes them', () async {
        for (final desired in [
          const ProjectGates({'push': false}),
          const ProjectGates({'push': true}),
          const ProjectGates({}),
        ]) {
          await expectLater(
            h.service.setGates('prj_1', desired, by: token),
            throwsA(
              isA<ApprovalForbiddenException>().having(
                (error) => error.message,
                'message',
                contains('cannot change gates'),
              ),
            ),
          );
        }
        expect(await h.logged(), isEmpty);
      });
    }

    test('refuses an action that is not a gate', () {
      expect(
        h.service.setGates(
          'prj_1',
          const ProjectGates({'launch_rocket': false}),
          by: app,
        ),
        throwsA(isA<ApprovalRequestException>()),
      );
    });

    test('setGates is not found for an unknown project', () {
      expect(
        h.service.setGates('prj_9', const ProjectGates({}), by: app),
        throwsA(isA<ProjectNotFoundException>()),
      );
    });

    test('changing nothing announces nothing', () async {
      final gates = await h.service.setGates(
        'prj_1',
        const ProjectGates({'push': true}),
        by: app,
      );

      expect(gates.gates.values, everyElement(isTrue));
      expect(await h.logged(), isEmpty);
      expect(h.resumed, isEmpty);
    });
  });
}

JobRecord _job(String id, {String? runId}) => JobRecord(
  id: id,
  workflowVersionId: 'wfv_1',
  projectId: 'prj_1',
  state: JobState.queued,
  createdAt: DateTime.utc(2026),
  runId: runId,
);

/// A repository that lets a test slip a decision in between the service's
/// read and its write.
class _RacingRepository implements ApprovalRepository {
  final inner = InMemoryApprovalRepository();

  Future<Object?> Function()? beforeDecide;

  @override
  Future<ApprovalRecord?> get(String id) => inner.get(id);

  @override
  Future<List<ApprovalRecord>> list({
    String? projectId,
    ApprovalState? state,
  }) => inner.list(projectId: projectId, state: state);

  @override
  Future<({ApprovalRecord record, bool created})> findOrCreate(
    ApprovalRecord candidate,
  ) => inner.findOrCreate(candidate);

  @override
  Future<ApprovalRecord?> decide(
    String id, {
    required ApprovalState state,
    required DecidedBy by,
    required DateTime at,
    String? reason,
  }) async {
    final before = beforeDecide;
    beforeDecide = null;
    if (before != null) await before();
    return await inner.decide(id, state: state, by: by, at: at, reason: reason);
  }

  @override
  Future<List<ApprovalRecord>> expireDue(
    DateTime now, {
    required String reason,
    String? id,
  }) => inner.expireDue(now, reason: reason, id: id);
}
