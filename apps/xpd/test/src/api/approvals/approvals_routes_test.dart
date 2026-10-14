import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/approval_helpers.dart';
import '../../../helpers/test_engine.dart';
import '../../../helpers/workflow_helpers.dart';

void main() {
  late ApprovalClient client;

  setUp(() async => client = await ApprovalClient.start());
  tearDown(() => client.close());

  ErrorResponse errorOf(RawResponse response) =>
      ErrorResponse.fromJson(response.json);

  group('GET /approvals', () {
    test('lists the approvals, newest first', () async {
      final first = await client.ask();
      client.engine.clock.advance(const Duration(minutes: 1));
      final second = await client.ask(action: GateAction.push);

      final response = await client.send('GET', '/approvals');

      expect(response.statusCode, 200);
      final listed = ApprovalsResponse.fromJson(response.json).approvals;
      expect([for (final a in listed) a.id], [second, first]);
      expect(listed.last.state, ApprovalState.pending);
      expect(listed.last.action, 'prod_release');
      expect(listed.last.sha, approvalSha);
      expect(listed.last.version, '1.2.3+45');
      expect(listed.last.projectId, client.projectId);
    });

    test('is empty for an engine nobody asked', () async {
      final response = await client.send('GET', '/approvals');

      expect(response.json, {'approvals': <Object?>[]});
    });

    test('filters by project and state', () async {
      final first = await client.ask();
      final second = await client.ask(action: GateAction.push);
      await client.send('POST', '/approvals/$second/approve');

      final pending = await client.send('GET', '/approvals?state=pending');
      final approved = await client.send('GET', '/approvals?state=approved');
      final mine = await client.send(
        'GET',
        '/approvals?project=${client.projectId}&state=pending',
      );
      final other = await client.send('GET', '/approvals?project=prj_other');

      expect(
        [
          for (final a in ApprovalsResponse.fromJson(pending.json).approvals)
            a.id,
        ],
        [first],
      );
      expect(
        [
          for (final a in ApprovalsResponse.fromJson(approved.json).approvals)
            a.id,
        ],
        [second],
      );
      expect(ApprovalsResponse.fromJson(mine.json).approvals, hasLength(1));
      expect(ApprovalsResponse.fromJson(other.json).approvals, isEmpty);
    });

    test('refuses a state it does not know', () async {
      final response = await client.send('GET', '/approvals?state=maybe');

      expect(response.statusCode, 400);
      expect(errorOf(response).error.code, ApiErrorCode.invalidRequest);
      expect(errorOf(response).error.message, contains('pending'));
    });

    test('expires what ran out before it lists', () async {
      await client.ask();
      client.engine.clock.advance(approvalLifetime);

      final response = await client.send('GET', '/approvals');

      expect(
        ApprovalsResponse.fromJson(response.json).approvals.single.state,
        ApprovalState.expired,
      );
    });

    test('needs a token', () async {
      final response = await client.engine.request('/approvals', token: '');

      expect(response.statusCode, 401);
    });

    test('is open to every kind of token', () async {
      await client.ask();

      for (final kind in DeviceTokenKind.values) {
        final response = await client.send('GET', '/approvals', kind: kind);

        expect(response.statusCode, 200, reason: kind.name);
      }
    });
  });

  group('GET /approvals/{id}', () {
    test('shows one approval to every kind of token, MCP polls this', () async {
      final id = await client.ask();

      for (final kind in DeviceTokenKind.values) {
        final response = await client.send('GET', '/approvals/$id', kind: kind);

        expect(response.statusCode, 200, reason: kind.name);
        expect(Approval.fromJson(response.json).state, ApprovalState.pending);
      }
    });

    test('is 404 for an approval that does not exist', () async {
      final response = await client.send('GET', '/approvals/apr_nope');

      expect(response.statusCode, 404);
      expect(errorOf(response).error.code, ApiErrorCode.notFound);
    });

    test('shows an approval that ran out as expired', () async {
      final id = await client.ask();
      client.engine.clock.advance(approvalLifetime);

      final approval = await client.read(id);

      expect(approval.state, ApprovalState.expired);
      expect(approval.decidedBy, isNull);
    });
  });

  group('POST /approvals/{id}/approve and /deny', () {
    for (final kind in [DeviceTokenKind.app, DeviceTokenKind.cli]) {
      test('a ${kind.name} token approves', () async {
        final id = await client.ask();
        client.engine.clock.advance(const Duration(minutes: 3));

        final response = await client.send(
          'POST',
          '/approvals/$id/approve',
          kind: kind,
          body: {'reason': 'checked the build'},
        );

        expect(response.statusCode, 200, reason: response.body);
        final approval = Approval.fromJson(response.json);
        expect(approval.state, ApprovalState.approved);
        expect(approval.reason, 'checked the build');
        expect(approval.decidedBy!.kind, kind);
        // The engine's own app token is called "test".
        expect(
          approval.decidedBy!.name,
          kind == DeviceTokenKind.app ? 'test' : 'cli token',
        );
        expect(approval.decidedAt, client.engine.clock.now());
        expect(await client.read(id), approval);
      });

      test('a ${kind.name} token denies', () async {
        final id = await client.ask();

        final response = await client.send(
          'POST',
          '/approvals/$id/deny',
          kind: kind,
        );

        expect(response.statusCode, 200, reason: response.body);
        final approval = Approval.fromJson(response.json);
        expect(approval.state, ApprovalState.denied);
        expect(approval.reason, isNull);
        expect(approval.decidedBy!.kind, kind);
      });
    }

    for (final kind in [DeviceTokenKind.mcp, DeviceTokenKind.runner]) {
      test('a ${kind.name} token gets 403 on approve and on deny', () async {
        final id = await client.ask();

        for (final action in ['approve', 'deny']) {
          final response = await client.send(
            'POST',
            '/approvals/$id/$action',
            kind: kind,
          );

          expect(response.statusCode, 403, reason: '$action ${kind.name}');
          expect(errorOf(response).error.code, ApiErrorCode.forbidden);
          expect(errorOf(response).error.message, contains(kind.name));
        }
        expect((await client.read(id)).state, ApprovalState.pending);
      });
    }

    test('is 404 for an approval that does not exist', () async {
      for (final action in ['approve', 'deny']) {
        final response = await client.send('POST', '/approvals/apr_x/$action');

        expect(response.statusCode, 404, reason: action);
      }
    });

    test('is 400 for a body that is not a decision', () async {
      final id = await client.ask();

      for (final body in ['nope', '[]', '{"reason": 5}']) {
        final response = await client.send(
          'POST',
          '/approvals/$id/approve',
          rawBody: body,
        );

        expect(response.statusCode, 400, reason: body);
        expect(errorOf(response).error.code, ApiErrorCode.invalidRequest);
      }
      expect((await client.read(id)).state, ApprovalState.pending);
    });

    test('answers 409 with the winning decision to the second one', () async {
      final id = await client.ask();
      await client.send(
        'POST',
        '/approvals/$id/deny',
        kind: DeviceTokenKind.cli,
        body: {'reason': 'wrong build'},
      );

      final late = await client.send('POST', '/approvals/$id/approve');

      expect(late.statusCode, 409);
      expect(late.json['error'], {
        'code': 'already_decided',
        'message': contains('denied by cli token (cli)'),
      });
      final winner = Approval.fromJson(
        late.json['approval'] as Map<String, dynamic>,
      );
      expect(winner.state, ApprovalState.denied);
      expect(winner.decidedBy!.kind, DeviceTokenKind.cli);
      expect(winner.reason, 'wrong build');
      expect(winner, await client.read(id));
    });

    test('answers 409 once the 24 hours ran out', () async {
      final id = await client.ask();
      client.engine.clock.advance(approvalLifetime);

      final response = await client.send('POST', '/approvals/$id/approve');

      expect(response.statusCode, 409);
      expect(
        Approval.fromJson(response.json['approval'] as Map<String, dynamic>)
            .state,
        ApprovalState.expired,
      );
      expect((response.json['error'] as Map)['message'], contains('denied'));
    });

    test('lets exactly one of two concurrent requests win', () async {
      final id = await client.ask();

      final responses = await Future.wait([
        client.send('POST', '/approvals/$id/approve'),
        client.send('POST', '/approvals/$id/deny', kind: DeviceTokenKind.cli),
      ]);

      final statuses = responses.map((r) => r.statusCode).toList()..sort();
      expect(statuses, [200, 409]);
      final won = responses.firstWhere((r) => r.statusCode == 200);
      final lost = responses.firstWhere((r) => r.statusCode == 409);
      final winner = Approval.fromJson(won.json);
      expect(
        Approval.fromJson(lost.json['approval'] as Map<String, dynamic>),
        winner,
      );
      expect((lost.json['error'] as Map)['code'], 'already_decided');
      expect(await client.read(id), winner);
      expect(
        (await client.logged()).whereType<ApprovalDecided>(),
        hasLength(1),
      );
    });

    test('lets exactly one of many concurrent requests win', () async {
      final id = await client.ask();

      final responses = await Future.wait([
        for (var i = 0; i < 8; i++)
          client.send(
            'POST',
            '/approvals/$id/${i.isEven ? 'approve' : 'deny'}',
            kind: i < 4 ? DeviceTokenKind.app : DeviceTokenKind.cli,
          ),
      ]);

      expect(responses.where((r) => r.statusCode == 200), hasLength(1));
      expect(responses.where((r) => r.statusCode == 409), hasLength(7));
    });
  });

  group('events', () {
    test('announce a request, a decision and an expiry', () async {
      final stream = await client.engine.connect();
      addTearDown(stream.close);
      await stream.next(); // stream.opened
      final decided = await client.ask();
      final expiring = await client.ask(action: GateAction.push);
      await client.send('POST', '/approvals/$decided/approve');
      client.engine.clock.advance(approvalLifetime);
      await client.send('GET', '/approvals');

      final events = (await stream.take(4)).map((e) => e.event).toList();

      expect(events[0], isA<ApprovalRequested>());
      expect(events[1], isA<ApprovalRequested>());
      expect(events[2], isA<ApprovalDecided>());
      expect((events[2] as ApprovalDecided).state, ApprovalState.approved);
      expect(events[3], isA<ApprovalExpired>());
      expect((events[3] as ApprovalExpired).approvalId, expiring);
    });
  });

  group('gates', () {
    String gatesPath() => '/projects/${client.projectId}/gates';

    test('are all on for a project that never set them', () async {
      final response = await client.send('GET', gatesPath());

      expect(response.statusCode, 200);
      final gates = ProjectGates.fromJson(response.json).gates;
      expect(gates.keys, GateAction.values.map((a) => a.wire));
      expect(gates.values, everyElement(isTrue));
    });

    test('every kind of token reads them', () async {
      for (final kind in DeviceTokenKind.values) {
        final response = await client.send('GET', gatesPath(), kind: kind);

        expect(response.statusCode, 200, reason: kind.name);
      }
    });

    test('are 404 for a project that does not exist', () async {
      for (final method in ['GET', 'PUT']) {
        final response = await client.send(
          method,
          '/projects/prj_nope/gates',
          body: method == 'PUT' ? {'gates': <String, bool>{}} : null,
        );

        expect(response.statusCode, 404, reason: method);
      }
    });

    test('an app token turns one off and on again', () async {
      final off = await client.send(
        'PUT',
        gatesPath(),
        body: {
          'gates': {'push': false},
        },
      );

      expect(off.statusCode, 200, reason: off.body);
      expect(ProjectGates.fromJson(off.json).gates['push'], isFalse);
      expect(ProjectGates.fromJson(off.json).gates['merge'], isTrue);
      final read = await client.send('GET', gatesPath());
      expect(ProjectGates.fromJson(read.json), ProjectGates.fromJson(off.json));

      final on = await client.send(
        'PUT',
        gatesPath(),
        body: {'gates': <String, bool>{}},
      );

      expect(ProjectGates.fromJson(on.json).gates['push'], isTrue);
    });

    test('a gate that is off approves without asking', () async {
      await client.send(
        'PUT',
        gatesPath(),
        body: {
          'gates': {'prod_release': false},
        },
      );

      final decision = await client.engine.approvals.check(
        GateRequest(
          action: GateAction.prodRelease,
          projectId: client.projectId,
          sha: approvalSha,
          jobId: 'job_x',
        ),
      );

      expect(decision, isA<GateApproved>());
    });

    test('a cli token turns gates on but not off', () async {
      await client.send(
        'PUT',
        gatesPath(),
        body: {
          'gates': {'push': false},
        },
      );

      final tighten = await client.send(
        'PUT',
        gatesPath(),
        kind: DeviceTokenKind.cli,
        body: {
          'gates': {'push': true},
        },
      );
      final loosen = await client.send(
        'PUT',
        gatesPath(),
        kind: DeviceTokenKind.cli,
        body: {
          'gates': {'merge': false},
        },
      );

      expect(tighten.statusCode, 200, reason: tighten.body);
      expect(ProjectGates.fromJson(tighten.json).gates['push'], isTrue);
      expect(loosen.statusCode, 403);
      expect(errorOf(loosen).error.code, ApiErrorCode.forbidden);
      expect(errorOf(loosen).error.message, contains('in the app'));
      final read = await client.send('GET', gatesPath());
      expect(ProjectGates.fromJson(read.json).gates['merge'], isTrue);
    });

    for (final kind in [DeviceTokenKind.mcp, DeviceTokenKind.runner]) {
      test('a ${kind.name} token gets 403 on any change', () async {
        for (final gates in [
          {'push': false},
          {'push': true},
          <String, bool>{},
        ]) {
          final response = await client.send(
            'PUT',
            gatesPath(),
            kind: kind,
            body: {'gates': gates},
          );

          expect(response.statusCode, 403, reason: '${kind.name} $gates');
          expect(errorOf(response).error.code, ApiErrorCode.forbidden);
        }
        final read = await client.send('GET', gatesPath());
        expect(
          ProjectGates.fromJson(read.json).gates.values,
          everyElement(isTrue),
        );
      });
    }

    test('refuse a body that is not gates', () async {
      for (final body in [
        'nope',
        '{}',
        '{"gates": 5}',
        '{"gates": {"push": "no"}}',
        '{"gates": {"launch_rocket": false}}',
      ]) {
        final response = await client.send('PUT', gatesPath(), rawBody: body);

        expect(response.statusCode, 400, reason: body);
        expect(errorOf(response).error.code, ApiErrorCode.invalidRequest);
      }
    });

    test('announce a change, once', () async {
      final stream = await client.engine.connect();
      addTearDown(stream.close);
      await stream.next();
      await client.send(
        'PUT',
        gatesPath(),
        body: {
          'gates': {'push': false},
        },
      );
      await client.send(
        'PUT',
        gatesPath(),
        body: {
          'gates': {'push': false},
        },
      );
      await client.send('PUT', gatesPath(), body: {'gates': <String, bool>{}});

      final events = (await stream.take(2)).map((e) => e.event).toList();

      expect(events[0], isA<ProjectGatesChanged>());
      expect((events[0] as ProjectGatesChanged).gates['push'], isFalse);
      expect((events[0] as ProjectGatesChanged).changedBy, DeviceTokenKind.app);
      expect((events[1] as ProjectGatesChanged).gates['push'], isTrue);
    });
  });

  group('a gated run', () {
    late WorkflowClient workflows;

    setUp(() => workflows = WorkflowClient(client.engine, client.projectId));

    late String shipId;

    setUp(() async => shipId = await workflows.create('ship', gatedWorkflow));

    Future<String> dispatchGated() async {
      final id = shipId;
      final run = Run.fromJson((await workflows.dispatch(id)).json);
      await workflows.until(run.id, {RunState.waitingForApproval});
      return run.id;
    }

    test('waits for an approval that an MCP token cannot give', () async {
      final runId = await dispatchGated();
      final pending = ApprovalsResponse.fromJson(
        (await client.send(
          'GET',
          '/approvals?state=pending',
          kind: DeviceTokenKind.mcp,
        )).json,
      ).approvals.single;

      final refused = await client.send(
        'POST',
        '/approvals/${pending.id}/approve',
        kind: DeviceTokenKind.mcp,
      );

      expect(pending.action, 'prod_release');
      expect(pending.runId, runId);
      expect(refused.statusCode, 403);
      final run = await workflows.until(runId, {RunState.waitingForApproval});
      expect(run.jobs.single.state, JobState.waitingForApproval);
    });

    test('goes on when an app token approves', () async {
      final runId = await dispatchGated();
      final pending = ApprovalsResponse.fromJson(
        (await client.send('GET', '/approvals?state=pending')).json,
      ).approvals.single;

      final approved = await client.send(
        'POST',
        '/approvals/${pending.id}/approve',
      );

      expect(approved.statusCode, 200);
      await workflows.until(runId, {RunState.succeeded});
    });

    test('fails when a cli token denies, with the reason', () async {
      final runId = await dispatchGated();
      final pending = ApprovalsResponse.fromJson(
        (await client.send('GET', '/approvals?state=pending')).json,
      ).approvals.single;

      await client.send(
        'POST',
        '/approvals/${pending.id}/deny',
        kind: DeviceTokenKind.cli,
        body: {'reason': 'not today'},
      );

      final failed = await workflows.until(runId, {RunState.failed});
      expect(failed.jobs.single.message, contains('not today'));
    });

    test('fails when nobody decides within 24 hours', () async {
      final runId = await dispatchGated();
      client.engine.clock.advance(approvalLifetime);

      await client.engine.approvals.sweep();

      final failed = await workflows.until(runId, {RunState.failed});
      expect(failed.jobs.single.message, contains('24 hours'));
    });

    test('goes on when an app token turns the gate off', () async {
      final runId = await dispatchGated();

      await client.send(
        'PUT',
        '/projects/${client.projectId}/gates',
        body: {
          'gates': {'prod_release': false},
        },
      );

      await workflows.until(runId, {RunState.succeeded});
    });

    test(
      'asks again for a new run, which an old denial does not stop',
      () async {
        final first = await dispatchGated();
        final pending = ApprovalsResponse.fromJson(
          (await client.send('GET', '/approvals?state=pending')).json,
        ).approvals.single;
        await client.send('POST', '/approvals/${pending.id}/deny');
        await workflows.until(first, {RunState.failed});

        final second = await dispatchGated();

        expect(second, isNot(first));
        final all = ApprovalsResponse.fromJson(
          (await client.send('GET', '/approvals')).json,
        ).approvals;
        expect(all.map((a) => a.state), [
          ApprovalState.pending,
          ApprovalState.denied,
        ]);
      },
    );
  });
}
