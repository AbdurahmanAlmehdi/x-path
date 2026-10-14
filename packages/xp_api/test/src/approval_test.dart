import 'package:json_annotation/json_annotation.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  final created = DateTime.utc(2026, 10, 13, 9);
  final expires = created.add(const Duration(hours: 24));
  const decider = DecidedBy(
    tokenId: 'tok_1',
    name: 'Mac mini',
    kind: DeviceTokenKind.app,
  );

  group('ApprovalState', () {
    test('uses lower case on the wire', () {
      expect(ApprovalState.pending.wire, 'pending');
      expect(ApprovalState.approved.wire, 'approved');
      expect(ApprovalState.denied.wire, 'denied');
      expect(ApprovalState.expired.wire, 'expired');
    });

    test('is settled once it is not pending', () {
      expect(ApprovalState.pending.isSettled, isFalse);
      for (final state in [
        ApprovalState.approved,
        ApprovalState.denied,
        ApprovalState.expired,
      ]) {
        expect(state.isSettled, isTrue, reason: state.wire);
      }
    });
  });

  group('DecidedBy', () {
    test('round-trips through JSON', () {
      expect(decider.toJson(), {
        'tokenId': 'tok_1',
        'name': 'Mac mini',
        'kind': 'app',
      });
      expect(DecidedBy.fromJson(decider.toJson()), decider);
    });
  });

  group('Approval', () {
    final pending = Approval(
      id: 'apr_1',
      projectId: 'prj_1',
      action: 'prod_release',
      sha: 'a' * 40,
      state: ApprovalState.pending,
      createdAt: created,
      expiresAt: expires,
    );

    test('leaves out what it lacks', () {
      expect(pending.toJson().keys, {
        'id',
        'projectId',
        'action',
        'sha',
        'state',
        'createdAt',
        'expiresAt',
      });
      expect(Approval.fromJson(pending.toJson()), pending);
    });

    test('round-trips a decided approval with everything', () {
      final decided = Approval(
        id: 'apr_1',
        projectId: 'prj_1',
        action: 'prod_release',
        sha: 'a' * 40,
        version: '1.2.3+45',
        runId: 'run_1',
        jobId: 'job_1',
        state: ApprovalState.approved,
        createdAt: created,
        expiresAt: expires,
        decidedAt: created.add(const Duration(minutes: 5)),
        decidedBy: decider,
        reason: 'looks right',
      );

      final json = decided.toJson();

      expect(json['decidedBy'], decider.toJson());
      expect(json['state'], 'approved');
      expect(Approval.fromJson(json), decided);
    });
  });

  group('ApprovalsResponse', () {
    test('round-trips through JSON', () {
      final response = ApprovalsResponse([
        Approval(
          id: 'apr_1',
          projectId: 'prj_1',
          action: 'push',
          sha: 'b' * 40,
          state: ApprovalState.expired,
          createdAt: created,
          expiresAt: expires,
        ),
      ]);

      expect(ApprovalsResponse.fromJson(response.toJson()), response);
    });
  });

  group('DecisionRequest', () {
    test('has an optional reason', () {
      expect(DecisionRequest.fromJson(const {}).reason, isNull);
      expect(const DecisionRequest().toJson(), isEmpty);
      expect(
        DecisionRequest.fromJson(const {'reason': 'ok'}),
        const DecisionRequest(reason: 'ok'),
      );
    });

    test('rejects a reason that is not text', () {
      expect(
        () => DecisionRequest.fromJson(const {'reason': 1}),
        throwsA(isA<CheckedFromJsonException>()),
      );
    });
  });

  group('ProjectGates', () {
    test('round-trips through JSON', () {
      const gates = ProjectGates({'prod_release': true, 'push': false});

      expect(gates.toJson(), {
        'gates': {'prod_release': true, 'push': false},
      });
      expect(ProjectGates.fromJson(gates.toJson()), gates);
    });

    test('rejects gates that are not a map of booleans', () {
      for (final json in <Map<String, dynamic>>[
        {},
        {'gates': 5},
        {
          'gates': {'push': 'yes'},
        },
      ]) {
        expect(
          () => ProjectGates.fromJson(json),
          throwsA(isA<CheckedFromJsonException>()),
          reason: '$json',
        );
      }
    });
  });
}
