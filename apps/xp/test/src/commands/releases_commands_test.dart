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

  group('list', () {
    test('prints a table', () async {
      when(() => env.client.listReleases())
          .thenAnswer((_) async => [sample.release()]);

      await env.runOk(['releases', 'list']);

      expect(env.logger.out, contains('rel_1  in_review  1.2.3+45  prod'));
    });

    test('says when there are none', () async {
      when(() => env.client.listReleases()).thenAnswer((_) async => []);

      await env.runOk(['releases', 'list']);

      expect(env.logger.out, 'No releases.');
    });

    test('narrows by project, app and state', () async {
      when(
        () => env.client.listReleases(
          projectId: 'prj_1',
          app: '.',
          state: ReleaseState.live,
        ),
      ).thenAnswer((_) async => []);

      await env.runOk([
        'releases',
        'list',
        '--project',
        'prj_1',
        '--app',
        '.',
        '--state',
        'live',
      ]);

      verify(
        () => env.client.listReleases(
          projectId: 'prj_1',
          app: '.',
          state: ReleaseState.live,
        ),
      ).called(1);
    });
  });

  group('show, refresh, abandon', () {
    test('show prints the release and the state in each store', () async {
      when(() => env.client.getRelease('rel_1'))
          .thenAnswer((_) async => sample.release());

      await env.runOk(['releases', 'show', 'rel_1']);

      expect(env.logger.out, contains('rel_1  in_review  1.2.3+45  prod'));
      expect(env.logger.out, contains('tag: v1.2.3+45'));
      expect(env.logger.out, contains('branch: release/1.2.3'));
      expect(env.logger.out, contains('merge enabled: no'));
      expect(env.logger.out, contains('message: Waiting'));
      expect(env.logger.out, contains('apple  in_review  api'));
    });

    test('show leaves out what a release has not got', () async {
      when(() => env.client.getRelease('rel_1')).thenAnswer(
        (_) async => Release(
          id: 'rel_1',
          projectId: 'prj_1',
          app: '.',
          flavor: 'prod',
          version: '1.0.0',
          build: 1,
          state: ReleaseState.draft,
          stores: const [],
          builds: const [],
          mergeEnabled: false,
          createdAt: sample.at,
          updatedAt: sample.at,
        ),
      );

      await env.runOk(['releases', 'show', 'rel_1']);

      expect(env.logger.out, isNot(contains('tag:')));
      expect(env.logger.out, isNot(contains('pull request')));
    });

    test('show with --json prints the release', () async {
      when(() => env.client.getRelease('rel_1'))
          .thenAnswer((_) async => sample.release());

      await env.runOk(['--json', 'releases', 'show', 'rel_1']);

      expect((jsonDecode(env.logger.infos.single) as Map)['id'], 'rel_1');
    });

    test('refresh asks the stores', () async {
      when(() => env.client.refreshRelease('rel_1'))
          .thenAnswer((_) async => sample.release());

      await env.runOk(['releases', 'refresh', 'rel_1']);

      verify(() => env.client.refreshRelease('rel_1')).called(1);
    });

    test('abandon gives it a reason', () async {
      when(
        () => env.client.abandonRelease('rel_1', reason: 'too many rejections'),
      ).thenAnswer((_) async => sample.release());

      await env.runOk([
        'releases',
        'abandon',
        'rel_1',
        '--reason',
        'too many rejections',
      ]);

      verify(
        () => env.client.abandonRelease('rel_1', reason: 'too many rejections'),
      ).called(1);
    });
  });

  group('status', () {
    test('says by hand what a store did', () async {
      when(
        () => env.client.setReleaseStoreStatus(
          'rel_1',
          ReleaseStore.play,
          StoreState.live,
        ),
      ).thenAnswer((_) async => sample.release());

      await env.runOk(['releases', 'status', 'rel_1', 'play', 'live']);

      verify(
        () => env.client.setReleaseStoreStatus(
          'rel_1',
          ReleaseStore.play,
          StoreState.live,
        ),
      ).called(1);
    });

    test('refuses a store or a state it does not know', () async {
      expect(
        await env.run(['releases', 'status', 'rel_1', 'moon', 'live']),
        64,
      );
      expect(env.logger.errors.last, contains('apple or play'));
      expect(
        await env.run(['releases', 'status', 'rel_1', 'play', 'maybe']),
        64,
      );
      expect(env.logger.errors.last, contains('in_review'));
    });
  });

  group('build and merge', () {
    test('build starts a new build of the same version', () async {
      when(() => env.client.startReleaseBuild('rel_1'))
          .thenAnswer((_) async => sample.run(state: RunState.queued));

      await env.runOk(['releases', 'build', 'rel_1']);

      expect(env.logger.out, contains('Started run_1.'));
    });

    test('merge asks for the merge', () async {
      when(() => env.client.mergeRelease('rel_1'))
          .thenAnswer((_) async => sample.run(state: RunState.queued));

      await env.runOk(['releases', 'merge', 'rel_1']);

      expect(env.logger.out, contains('Started run_1.'));
    });

    test('merge is refused until both stores are live', () async {
      when(() => env.client.mergeRelease('rel_1')).thenThrow(
        const ApiException(
          'The release is not live.',
          statusCode: 409,
          code: ApiErrorCode.conflict,
        ),
      );

      expect(await env.run(['releases', 'merge', 'rel_1']), 73);
    });

    test('rollout asks for a change of the rollout', () async {
      when(() => env.client.requestRollout('rel_1', any()))
          .thenAnswer((_) async => sample.run(state: RunState.queued));

      await env.runOk([
        'releases',
        'rollout',
        'rel_1',
        '--store',
        'play',
        '--percent',
        '50',
      ]);
      await env.runOk([
        'releases',
        'rollout',
        'rel_1',
        '--store',
        'apple',
        '--pause',
      ]);

      expect(env.logger.out, contains('Started run_1.'));
      expect(
        verify(() => env.client.requestRollout('rel_1', captureAny())).captured,
        const [
          RolloutRequest(
            store: ReleaseStore.play,
            action: RolloutAction.fraction,
            userFraction: 0.5,
          ),
          RolloutRequest(
            store: ReleaseStore.apple,
            action: RolloutAction.pause,
          ),
        ],
      );
    });

    test('rollout takes a store and one change', () async {
      for (final args in [
        ['--pause'],
        ['--store', 'apple'],
        ['--store', 'apple', '--pause', '--complete'],
        ['--store', 'play', '--percent', 'half'],
      ]) {
        expect(
          await env.run(['releases', 'rollout', 'rel_1', ...args]),
          64,
          reason: '$args',
        );
      }
      verifyNever(() => env.client.requestRollout(any(), any()));
    });
  });

  group('notes', () {
    const notes = ReleaseNotes(
      releaseId: 'rel_1',
      version: '1.2.3',
      build: 45,
      to: 'v1.2.3+45',
      commits: 1,
      groups: [],
      slack: '*1.2.3* for Slack',
      whatsapp: '1.2.3 for WhatsApp',
    );

    test('prints the Slack text by default', () async {
      when(() => env.client.getReleaseNotes('rel_1'))
          .thenAnswer((_) async => notes);

      await env.runOk(['releases', 'notes', 'rel_1']);

      expect(env.logger.infos, ['*1.2.3* for Slack']);
    });

    test('prints the WhatsApp text on request', () async {
      when(() => env.client.getReleaseNotes('rel_1'))
          .thenAnswer((_) async => notes);

      await env.runOk(['releases', 'notes', 'rel_1', '--format', 'whatsapp']);

      expect(env.logger.infos, ['1.2.3 for WhatsApp']);
    });
  });
}
