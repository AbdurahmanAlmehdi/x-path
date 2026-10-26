import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/credential_harness.dart';
import '../../../helpers/notify_harness.dart';
import '../../../helpers/step_context.dart';

const _key = AscKey(keyId: 'K', issuerId: 'I', privateKey: 'p');

StoreRolloutInput _input(
  ReleaseStore store,
  RolloutAction action, [
  double? fraction,
]) => StoreRolloutInput(
  releaseId: 'rel_1',
  request: RolloutRequest(store: store, action: action, userFraction: fraction),
);

void main() {
  late InMemoryReleaseRepository releases;
  late FakeAppStoreConnect apple;
  late FakeGooglePlay play;
  late FakeAscCredentialSource ascKeys;
  late FakePlayCredentialSource playAccounts;
  late StoreRolloutStep step;
  final context = NoProcessContext();

  setUp(() async {
    releases = InMemoryReleaseRepository();
    apple = FakeAppStoreConnect();
    play = FakeGooglePlay();
    ascKeys = FakeAscCredentialSource({'ly.demo': _key});
    playAccounts = FakePlayCredentialSource({'ly.demo': testServiceAccount});
    step = StoreRolloutStep(
      releases: releases,
      ascCredentials: ascKeys,
      appStoreConnect: (_) => apple,
      playCredentials: playAccounts,
      googlePlay: (_) => play,
    );
    await releases.create(
      releaseRecord(
        stores: {
          ReleaseStore.apple: const StoreEntry(
            store: ReleaseStore.apple,
            state: StoreState.live,
            source: StatusSource.api,
            identity: {
              'bundleId': 'ly.demo',
              'appleAppId': '1',
              'country': 'ly',
            },
          ),
          ReleaseStore.play: const StoreEntry(
            store: ReleaseStore.play,
            state: StoreState.live,
            source: StatusSource.api,
            identity: {'packageName': 'ly.demo', 'track': 'production'},
          ),
        },
      ),
    );
    apple.apps['ly.demo'] = const AscApp(id: 'app_1', bundleId: 'ly.demo');
    apple.versionsOf['app_1'] = [
      const AscAppStoreVersion(
        id: 'ver_1',
        versionString: '1.2.0',
        platform: 'IOS',
        state: AppVersionState.readyForDistribution,
      ),
    ];
    apple.phasedReleases['ver_1'] = const AscPhasedRelease(
      id: 'phr_1',
      state: PhasedReleaseState.active,
    );
    play.tracksOf['production'] = const PlayTrack(
      name: 'production',
      releases: [
        PlayRelease(versionCodes: [4], status: PlayReleaseStatus.completed),
        PlayRelease(
          versionCodes: [5],
          status: PlayReleaseStatus.inProgress,
          userFraction: 0.1,
          name: '1.2.0',
        ),
      ],
    );
  });

  test('the input and the result keep their stored form', () {
    final input = _input(ReleaseStore.play, RolloutAction.fraction, 0.5);

    expect(step.decodeInput(step.encodeInput(input)), input);
    expect(input.props, ['rel_1', input.request]);
    expect(step.kind, 'store.rollout');
    expect(step.sideEffectOf(input), isTrue);
    expect(
      step.encodeResult(
        const StoreRolloutResult(
          store: ReleaseStore.play,
          state: 'halted',
          userFraction: 0.1,
        ),
      ),
      {
        'store': 'play',
        'state': 'halted',
        'userFraction': 0.1,
        'alreadyDone': false,
      },
    );
    expect(
      const StoreRolloutResult(
        store: ReleaseStore.apple,
        state: 'PAUSED',
      ).props,
      [ReleaseStore.apple, 'PAUSED', null, false],
    );
  });

  group('Apple', () {
    test('pauses, resumes and completes the phased release', () async {
      for (final (action, state) in [
        (RolloutAction.pause, PhasedReleaseState.paused),
        (RolloutAction.resume, PhasedReleaseState.active),
        (RolloutAction.complete, PhasedReleaseState.complete),
      ]) {
        final outcome = await step.run(
          _input(ReleaseStore.apple, action),
          context,
        );

        expect(
          (outcome as StepSucceeded<StoreRolloutResult>).result,
          StoreRolloutResult(store: ReleaseStore.apple, state: state.wire),
        );
        expect(apple.phasedReleases['ver_1']!.state, state);
      }
    });

    test('is done already when the phased release is there', () async {
      final input = _input(ReleaseStore.apple, RolloutAction.resume);

      expect(
        await step.alreadyDone(input, context),
        const StoreRolloutResult(
          store: ReleaseStore.apple,
          state: 'ACTIVE',
          alreadyDone: true,
        ),
      );
      expect(
        await step.alreadyDone(
          _input(ReleaseStore.apple, RolloutAction.pause),
          context,
        ),
        isNull,
      );
    });

    test('says why there is nothing to change', () async {
      Future<String> failure() async => ((await step.run(
        _input(ReleaseStore.apple, RolloutAction.pause),
        context,
      )) as StepFailed).message;

      apple.phasedReleases.clear();
      expect(await failure(), contains('no phased release'));
      apple.versionsOf['app_1'] = [];
      expect(await failure(), contains('no version 1.2.0'));
      apple.apps.clear();
      expect(await failure(), contains('no version 1.2.0'));
      ascKeys.keys.clear();
      expect(await failure(), contains('No App Store Connect API key'));
    });

    test('says what App Store Connect said', () async {
      apple.phasedReleases['ver_1'] = const AscPhasedRelease(
        id: 'phr_1',
        state: PhasedReleaseState.active,
      );
      final outcome = await step.run(
        _input(ReleaseStore.apple, RolloutAction.pause),
        context,
      );
      expect(outcome, isA<StepSucceeded<StoreRolloutResult>>());

      apple.failure = const AppStoreConnectException(403, 'Forbidden.');
      final failed = await step.run(
        _input(ReleaseStore.apple, RolloutAction.pause),
        context,
      );
      expect((failed as StepFailed).message, 'App Store Connect: Forbidden.');
      apple.failure = const AppStoreConnectException(500, 'Down.');
      expect(
        await step.alreadyDone(
          _input(ReleaseStore.apple, RolloutAction.pause),
          context,
        ),
        isNull,
      );
    });
  });

  group('Google Play', () {
    test(
      'raises the fraction, halts and completes the staged rollout',
      () async {
        for (final (action, fraction, status, expected) in [
          (RolloutAction.fraction, 0.5, PlayReleaseStatus.inProgress, 0.5),
          (RolloutAction.halt, null, PlayReleaseStatus.halted, 0.5),
          (RolloutAction.fraction, 1.0, PlayReleaseStatus.completed, null),
          (RolloutAction.complete, null, PlayReleaseStatus.completed, null),
        ]) {
          final outcome = await step.run(
            _input(ReleaseStore.play, action, fraction),
            context,
          );

          expect(
            (outcome as StepSucceeded<StoreRolloutResult>).result,
            StoreRolloutResult(
              store: ReleaseStore.play,
              state: status.wire,
              userFraction: expected,
            ),
            reason: '$action',
          );
          final releases = play.updatedTracks.last.releases;
          expect(releases.first.versionCodes, [4], reason: 'others stay');
          expect(releases.last.status, status);
          expect(releases.last.userFraction, expected);
          expect(releases.last.name, '1.2.0');
        }
        expect(play.committed, hasLength(4));
      },
    );

    test('is done already when the rollout is there', () async {
      expect(
        await step.alreadyDone(
          _input(ReleaseStore.play, RolloutAction.fraction, 0.1),
          context,
        ),
        const StoreRolloutResult(
          store: ReleaseStore.play,
          state: 'inProgress',
          userFraction: 0.1,
          alreadyDone: true,
        ),
      );
      expect(
        await step.alreadyDone(
          _input(ReleaseStore.play, RolloutAction.halt),
          context,
        ),
        isNull,
      );
      play.tracksOf.clear();
      expect(
        await step.alreadyDone(
          _input(ReleaseStore.play, RolloutAction.halt),
          context,
        ),
        isNull,
      );
      expect(play.deleted, hasLength(3), reason: 'reading edits are deleted');
    });

    test('says why there is nothing to change, and drops the edit', () async {
      play.tracksOf.clear();
      final missing = await step.run(
        _input(ReleaseStore.play, RolloutAction.halt),
        context,
      );
      expect((missing as StepFailed).message, contains('version code 5'));
      expect(play.deleted, ['edit-1']);

      play.tracksOf['production'] = const PlayTrack(
        name: 'production',
        releases: [
          PlayRelease(versionCodes: [5], status: PlayReleaseStatus.inProgress),
        ],
      );
      play.failures['commitEdit'] = const PlayException(409, 'In review.');
      final failed = await step.run(
        _input(ReleaseStore.play, RolloutAction.complete),
        context,
      );
      expect((failed as StepFailed).message, 'Google Play: In review.');
      expect(play.deleted, ['edit-1', 'edit-2']);

      playAccounts.accounts.clear();
      final noAccount = await step.run(
        _input(ReleaseStore.play, RolloutAction.complete),
        context,
      );
      expect(
        (noAccount as StepFailed).message,
        contains('No Google Play service account'),
      );
    });
  });

  test('says when the release is gone or did not go to the store', () async {
    expect(
      ((await step.run(
        const StoreRolloutInput(
          releaseId: 'rel_9',
          request: RolloutRequest(
            store: ReleaseStore.apple,
            action: RolloutAction.pause,
          ),
        ),
        context,
      )) as StepFailed).message,
      'There is no release rel_9.',
    );
    await releases.update(releaseRecord());
    expect(
      ((await step.run(
        _input(ReleaseStore.apple, RolloutAction.pause),
        context,
      )) as StepFailed).message,
      contains('did not go to apple'),
    );
    expect(
      await step.alreadyDone(
        _input(ReleaseStore.apple, RolloutAction.pause),
        context,
      ),
      isNull,
    );
  });
}
