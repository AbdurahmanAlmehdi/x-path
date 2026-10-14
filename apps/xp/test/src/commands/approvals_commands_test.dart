import 'dart:convert';

import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

import '../../helpers/samples.dart' as sample;
import '../../helpers/test_env.dart';

void main() {
  late TestEnv env;

  setUpAll(registerFallbacks);
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  group('approvals list', () {
    test('prints a table', () async {
      when(() => env.client.listApprovals()).thenAnswer(
        (_) async => [sample.approval(), sample.approval(version: null)],
      );

      await env.runOk(['approvals', 'list']);

      expect(env.logger.out, contains('apr_1  pending  prod_release'));
      expect(env.logger.out, contains('1.2.3+4'));
    });

    test('says when there are none', () async {
      when(() => env.client.listApprovals()).thenAnswer((_) async => []);

      await env.runOk(['approvals', 'list']);

      expect(env.logger.out, 'No approvals.');
    });

    test('narrows by project and state', () async {
      when(
        () => env.client.listApprovals(
          projectId: 'prj_1',
          state: ApprovalState.pending,
        ),
      ).thenAnswer((_) async => [sample.approval()]);

      await env.runOk([
        'approvals',
        'list',
        '--project',
        'prj_1',
        '--state',
        'pending',
      ]);

      verify(
        () => env.client.listApprovals(
          projectId: 'prj_1',
          state: ApprovalState.pending,
        ),
      ).called(1);
    });

    test('refuses a state it does not know', () async {
      expect(await env.run(['approvals', 'list', '--state', 'maybe']), 64);
    });

    test('with --json prints the approvals', () async {
      when(() => env.client.listApprovals())
          .thenAnswer((_) async => [sample.approval()]);

      await env.runOk(['--json', 'approvals', 'list']);

      expect(
        jsonDecode(env.logger.infos.single) as List<dynamic>,
        hasLength(1),
      );
    });
  });

  group('approvals show', () {
    test('prints a pending approval', () async {
      when(() => env.client.getApproval('apr_1'))
          .thenAnswer((_) async => sample.approval());

      await env.runOk(['approvals', 'show', 'apr_1']);

      expect(env.logger.out, contains('apr_1  pending  prod_release'));
      expect(env.logger.out, contains('version: 1.2.3+4'));
      expect(env.logger.out, isNot(contains('decided by')));
    });

    test('prints who decided and why', () async {
      when(() => env.client.getApproval('apr_1')).thenAnswer(
        (_) async => sample.approval(
          state: ApprovalState.approved,
          decided: true,
          reason: 'Ship it',
          version: null,
        ),
      );

      await env.runOk(['approvals', 'show', 'apr_1']);

      expect(env.logger.out, contains('decided by My Mac (app)'));
      expect(env.logger.out, contains('reason: Ship it'));
      expect(env.logger.out, isNot(contains('version:')));
    });
  });

  group('approve and deny', () {
    test('approve decides with the CLI token', () async {
      when(() => env.client.approve('apr_1', reason: 'ok')).thenAnswer(
        (_) async =>
            sample.approval(state: ApprovalState.approved, decided: true),
      );

      await env.runOk(['approvals', 'approve', 'apr_1', '--reason', 'ok']);

      expect(env.logger.out, contains('apr_1  approved'));
      expect(env.connections.single.token, 'cli-token');
    });

    test('approve without a reason sends none', () async {
      when(
        () => env.client.approve('apr_1'),
      ).thenAnswer((_) async => sample.approval(state: ApprovalState.approved));

      await env.runOk(['approvals', 'approve', 'apr_1']);

      verify(() => env.client.approve('apr_1')).called(1);
    });

    test('deny denies', () async {
      when(
        () => env.client.deny('apr_1', reason: 'wrong build'),
      ).thenAnswer((_) async => sample.approval(state: ApprovalState.denied));

      await env.runOk([
        'approvals',
        'deny',
        'apr_1',
        '--reason',
        'wrong build',
      ]);

      expect(env.logger.out, contains('apr_1  denied'));
    });

    test('the first decision wins: a late one is shown the outcome', () async {
      when(() => env.client.approve('apr_1')).thenThrow(
        ApiException(
          'Decided already.',
          statusCode: 409,
          code: ApiErrorCode.alreadyDecided,
          approval: sample.approval(state: ApprovalState.denied, decided: true),
        ),
      );

      expect(await env.run(['approvals', 'approve', 'apr_1']), 73);

      expect(env.logger.errors.single, 'Decided already.');
      expect(env.logger.out, contains('apr_1  denied'));
    });

    test('an MCP token is refused by the engine', () async {
      when(() => env.client.approve('apr_1')).thenThrow(
        const ApiException(
          'mcp tokens cannot approve.',
          statusCode: 403,
          code: ApiErrorCode.forbidden,
        ),
      );

      expect(await env.run(['approvals', 'approve', 'apr_1']), 77);
    });

    test('another failure is passed on', () async {
      when(() => env.client.approve('apr_1')).thenThrow(
        const ApiException('No.', statusCode: 404, code: ApiErrorCode.notFound),
      );

      expect(await env.run(['approvals', 'approve', 'apr_1']), 66);
    });
  });

  group('gates', () {
    test('show lists the actions', () async {
      when(() => env.client.getGates('prj_1')).thenAnswer(
        (_) async => const ProjectGates({'prod_release': true, 'push': false}),
      );

      await env.runOk(['gates', 'show', 'prj_1']);

      expect(env.logger.out, contains('prod_release  yes'));
      expect(env.logger.out, contains('push          no'));
    });

    test('tighten turns the named gates on and keeps the rest', () async {
      when(() => env.client.getGates('prj_1')).thenAnswer(
        (_) async => const ProjectGates({'prod_release': true, 'push': false}),
      );
      when(() => env.client.setGates('prj_1', any())).thenAnswer(
        (_) async => const ProjectGates({'prod_release': true, 'push': true}),
      );

      await env.runOk(['gates', 'tighten', 'prj_1', 'push', 'merge']);

      final gates =
          verify(() => env.client.setGates('prj_1', captureAny()))
                  .captured
                  .single
              as ProjectGates;
      expect(gates.gates, {'prod_release': true, 'push': true, 'merge': true});
      expect(env.logger.out, contains('push'));
    });

    test('tighten needs an action', () async {
      expect(await env.run(['gates', 'tighten', 'prj_1']), 64);
      expect(await env.run(['gates', 'tighten']), 64);
    });
  });
}
