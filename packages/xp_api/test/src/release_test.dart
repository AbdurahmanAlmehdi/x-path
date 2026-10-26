import 'package:json_annotation/json_annotation.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  final at = DateTime.utc(2026, 10, 14, 9);

  group('ReleaseState', () {
    test('uses snake_case on the wire', () {
      expect(ReleaseState.inReview.wire, 'in_review');
      expect(ReleaseState.values.map((s) => s.wire), [
        'draft',
        'building',
        'uploaded',
        'in_review',
        'rejected',
        'approved',
        'live',
        'merged',
        'abandoned',
      ]);
    });

    test('ends at merged and abandoned', () {
      expect(ReleaseState.values.where((state) => state.isTerminal), [
        ReleaseState.merged,
        ReleaseState.abandoned,
      ]);
    });
  });

  group('the store enums', () {
    test('use their names on the wire', () {
      expect(ReleaseStore.apple.wire, 'apple');
      expect(ReleaseStore.play.wire, 'play');
      expect(StoreState.inReview.wire, 'in_review');
      expect(StoreState.pending.wire, 'pending');
      expect(StatusSource.lookup.wire, 'lookup');
      expect(StatusSource.manual.wire, 'manual');
    });
  });

  group('StoreStatus', () {
    test('leaves out what it lacks', () {
      const status = StoreStatus(
        store: ReleaseStore.apple,
        state: StoreState.uploaded,
        source: StatusSource.upload,
      );

      expect(status.toJson(), {
        'store': 'apple',
        'state': 'uploaded',
        'source': 'upload',
      });
      expect(StoreStatus.fromJson(status.toJson()), status);
    });

    test('round-trips with everything', () {
      final status = StoreStatus(
        store: ReleaseStore.play,
        state: StoreState.inReview,
        source: StatusSource.api,
        detail: 'RELEASE_LIFECYCLE_STATE_IN_REVIEW',
        checkedAt: at,
        changedAt: at,
        note: 'n',
      );

      expect(StoreStatus.fromJson(status.toJson()), status);
      expect(status.toJson()['checkedAt'], '2026-10-14T09:00:00.000Z');
    });
  });

  group('ReleaseBuild', () {
    test('round-trips', () {
      final build = ReleaseBuild(build: 45, runId: 'run_1', createdAt: at);

      expect(ReleaseBuild.fromJson(build.toJson()), build);
    });
  });

  group('Release', () {
    final minimal = Release(
      id: 'rel_1',
      projectId: 'prj_1',
      app: '.',
      flavor: 'prod',
      version: '1.2.0',
      build: 45,
      state: ReleaseState.draft,
      stores: const [],
      builds: [ReleaseBuild(build: 45, runId: 'run_1', createdAt: at)],
      mergeEnabled: false,
      createdAt: at,
      updatedAt: at,
    );

    test('leaves out what it lacks', () {
      expect(minimal.toJson().keys, {
        'id',
        'projectId',
        'app',
        'flavor',
        'version',
        'build',
        'state',
        'stores',
        'builds',
        'mergeEnabled',
        'createdAt',
        'updatedAt',
      });
      expect(Release.fromJson(minimal.toJson()), minimal);
    });

    test('round-trips a merged release with everything', () {
      final merged = Release(
        id: 'rel_1',
        projectId: 'prj_1',
        app: '.',
        flavor: 'prod',
        version: '1.2.0',
        build: 45,
        state: ReleaseState.merged,
        stores: const [
          StoreStatus(
            store: ReleaseStore.apple,
            state: StoreState.live,
            source: StatusSource.lookup,
          ),
        ],
        builds: [ReleaseBuild(build: 45, runId: 'run_1', createdAt: at)],
        mergeEnabled: false,
        branch: 'release/1.2.0',
        baseBranch: 'main',
        tag: 'v1.2.0+45',
        headSha: 'a' * 40,
        prNumber: 7,
        prUrl: 'https://github.com/o/r/pull/7',
        mergeCommit: 'b' * 40,
        mergeRunId: 'run_2',
        message: 'm',
        createdAt: at,
        updatedAt: at,
      );

      expect(Release.fromJson(merged.toJson()), merged);
      expect(
        ReleasesResponse.fromJson(ReleasesResponse([merged]).toJson()),
        ReleasesResponse([merged]),
      );
    });

    test('rejects a state it does not know', () {
      expect(
        () => Release.fromJson({...minimal.toJson(), 'state': 'flying'}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('StoreStatusRequest', () {
    test('reads the state', () {
      expect(
        StoreStatusRequest.fromJson(const {'state': 'live'}).state,
        StoreState.live,
      );
      expect(
        StoreStatusRequest.fromJson(
          const StoreStatusRequest(state: StoreState.approved).toJson(),
        ),
        const StoreStatusRequest(state: StoreState.approved),
      );
    });

    test('needs a state it knows', () {
      expect(
        () => StoreStatusRequest.fromJson(const {}),
        throwsA(isA<CheckedFromJsonException>()),
      );
      expect(
        () => StoreStatusRequest.fromJson(const {'state': 'soon'}),
        throwsA(isA<CheckedFromJsonException>()),
      );
    });
  });

  group('AbandonRequest', () {
    test('has an optional reason', () {
      expect(AbandonRequest.fromJson(const {}).reason, isNull);
      expect(const AbandonRequest().toJson(), isEmpty);
      expect(
        AbandonRequest.fromJson(const {'reason': 'wrong build'}).reason,
        'wrong build',
      );
      expect(
        AbandonRequest.fromJson(const AbandonRequest(reason: 'r').toJson()),
        const AbandonRequest(reason: 'r'),
      );
    });

    test('rejects a reason that is not text', () {
      expect(
        () => AbandonRequest.fromJson(const {'reason': 1}),
        throwsA(isA<CheckedFromJsonException>()),
      );
    });
  });

  group('RolloutRequest', () {
    test('round-trips through JSON', () {
      const request = RolloutRequest(
        store: ReleaseStore.play,
        action: RolloutAction.fraction,
        userFraction: 0.5,
      );

      expect(request.toJson(), {
        'store': 'play',
        'action': 'fraction',
        'userFraction': 0.5,
      });
      expect(RolloutRequest.fromJson(request.toJson()), request);
    });

    test('says what a store cannot do', () {
      String? problem(
        ReleaseStore store,
        RolloutAction action, [
        double? fraction,
      ]) => RolloutRequest(
        store: store,
        action: action,
        userFraction: fraction,
      ).problem;

      for (final action in [
        RolloutAction.pause,
        RolloutAction.resume,
        RolloutAction.complete,
      ]) {
        expect(problem(ReleaseStore.apple, action), isNull);
      }
      expect(problem(ReleaseStore.apple, RolloutAction.halt), isNotNull);
      expect(problem(ReleaseStore.play, RolloutAction.pause), isNotNull);
      expect(problem(ReleaseStore.play, RolloutAction.halt), isNull);
      expect(problem(ReleaseStore.play, RolloutAction.fraction, 0.1), isNull);
      expect(problem(ReleaseStore.play, RolloutAction.fraction, 1), isNull);
      expect(problem(ReleaseStore.play, RolloutAction.fraction), isNotNull);
      expect(problem(ReleaseStore.play, RolloutAction.fraction, 0), isNotNull);
      expect(
        problem(ReleaseStore.play, RolloutAction.fraction, 1.5),
        isNotNull,
      );
    });
  });
}
