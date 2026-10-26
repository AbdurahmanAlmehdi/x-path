import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/approval_harness.dart';
import '../../helpers/release_harness.dart';

Matcher _throws<T extends ReleaseException>(String text) =>
    throwsA(isA<T>().having((e) => e.message, 'message', contains(text)));

/// The kinds of [history], with the store, detail, device and patch of each
/// when it has one.
List<String> _lines(ReleaseHistory history) => [
  for (final event in history.events)
    [
      event.kind.wire,
      ?event.store?.wire,
      ?event.detail,
      ?event.by,
      ?event.runId,
      if (event.patchNumber case final number?) 'p$number',
    ].join(' '),
];

void main() {
  late ReleaseHarness h;
  late String id;

  setUp(() async => h = await ReleaseHarness.create());

  /// A release both stores have live.
  Future<void> live() async {
    id = await h.open();
    await h.finishBuild(id);
    await h.service.sync(id);
    for (final store in ReleaseStore.values) {
      await h.service.setStoreStatus(id, store, StoreState.live, by: owner());
    }
  }

  group('the history of a release', () {
    test('records its dispatch, stores, merge and who acted', () async {
      await live();
      await h.service.requestMerge(id);
      h.clock.advance(const Duration(minutes: 5));
      await h.addJob(
        id,
        [
          (
            'github.mergePr',
            StepState.succeeded,
            {'number': 7, 'sha': 'c' * 40, 'alreadyMerged': false},
          ),
        ],
        runId: 'run_2',
        state: JobState.succeeded,
      );
      await h.service.sync(id);

      expect(_lines(await h.service.history(id)), [
        'created 1.2.0+5 run_1',
        'store apple uploaded',
        'store play uploaded',
        'store apple live app device',
        'store play live app device',
        'merge_requested run_2',
        'merged ${'c' * 40} run_2',
      ]);
    });

    test('records a new build and an abandon, with its reason', () async {
      id = await h.open();
      await h.finishBuild(id);
      await h.service.sync(id);
      h.apple.reading = const StoreReading(
        state: StoreState.rejected,
        source: StatusSource.api,
        detail: 'REJECTED',
      );
      await h.service.refresh(id);
      await h.service.newBuild(id);
      await h.service.abandon(id, by: owner(), reason: 'Wrong icon.');

      final lines = _lines(await h.service.history(id));
      expect(lines, contains('store apple rejected'));
      expect(lines, contains('build 6 run_2'));
      expect(lines.last, 'abandoned Wrong icon. app device');
    });

    test('is read only for a release there is', () async {
      await expectLater(
        h.service.history('rel_nope'),
        throwsA(isA<ReleaseNotFoundException>()),
      );
    });
  });

  group('the outcome of a job', () {
    test('records a rollout, a patch and its promotion once each', () async {
      await live();
      await h.service.requestRollout(
        id,
        const RolloutRequest(
          store: ReleaseStore.play,
          action: RolloutAction.fraction,
          userFraction: 0.5,
        ),
      );
      final finished = h.clock.now().add(const Duration(minutes: 1));
      final rollout = await h.addJob(
        id,
        [
          ('gate', StepState.succeeded, {}),
          (
            'store.rollout',
            StepState.succeeded,
            {'store': 'play', 'state': 'inProgress', 'userFraction': 0.5},
          ),
        ],
        runId: 'run_2',
        state: JobState.succeeded,
        finishedAt: finished,
      );
      final patch = await h.addJob(
        id,
        [('shorebird.patch', StepState.succeeded, {})],
        runId: 'run_3',
        state: JobState.succeeded,
        inputs: [
          {'platform': 'android', 'patchNumber': 1},
        ],
      );
      final track = await h.addJob(
        id,
        [
          ('shorebird.track', StepState.succeeded, {}),
          ('shorebird.track', StepState.failed, null),
        ],
        runId: 'run_4',
        state: JobState.succeeded,
        inputs: [
          {'action': 'rollback', 'patchNumber': 1},
        ],
      );
      final running = await h.addJob(id, [
        ('shorebird.patch', StepState.succeeded, {}),
      ], runId: 'run_5');

      for (final job in [rollout, patch, track, rollout, running, 'nope']) {
        await h.service.syncJob(job);
      }

      final history = await h.service.history(id);
      expect(_lines(history).skip(5), [
        'rollout_requested run_2',
        'patch android run_3 p1',
        'patch_rolled_back run_4 p1',
        'rollout play inProgress · 50 % run_2',
      ], reason: 'oldest first: the rollout finished last');
      expect(history.events.last.at, finished);
    });

    test(
      'records a promotion and an Apple change without a fraction',
      () async {
        await live();
        await h.addJob(
          id,
          [
            (
              'store.rollout',
              StepState.succeeded,
              {'store': 'apple', 'state': 'PAUSED'},
            ),
            ('shorebird.track', StepState.succeeded, {}),
            ('command', StepState.succeeded, {}),
          ],
          runId: 'run_2',
          state: JobState.succeeded,
          inputs: [
            {},
            {'action': 'promote', 'patchNumber': 2},
          ],
        );

        await h.service.syncJob('job_5');

        expect(_lines(await h.service.history(id)).skip(5), [
          'rollout apple PAUSED run_2',
          'patch_promoted run_2 p2',
        ]);
      },
    );
  });

  group('the texts', () {
    test('are kept on the release, trimmed, and recorded', () async {
      id = await h.open();

      final release = await h.service.setTexts(
        id,
        const ReleaseTexts(whatsNew: '  Faster checkout. ', whatToTest: ' '),
        by: owner(),
      );
      await h.service.setTexts(
        id,
        const ReleaseTexts(whatsNew: 'Faster checkout.'),
        by: owner(),
      );

      expect(release.whatsNew, 'Faster checkout.');
      expect(release.whatToTest, isNull);
      expect((await h.record(id)).whatsNew, 'Faster checkout.');
      expect(_lines(await h.service.history(id)).last, 'texts app device');
      expect(
        (await h.service.history(id)).events
            .where((event) => event.kind == ReleaseEventKind.texts),
        hasLength(1),
        reason: 'the same texts again change nothing',
      );
    });

    test('are for the app and xp, on a release not abandoned', () async {
      id = await h.open();

      await expectLater(
        h.service.setTexts(
          id,
          const ReleaseTexts(whatsNew: 'x'),
          by: tokenOf(DeviceTokenKind.mcp),
        ),
        throwsA(isA<ReleaseForbiddenException>()),
      );
      await h.service.abandon(id, by: owner());
      await expectLater(
        h.service.setTexts(id, const ReleaseTexts(whatsNew: 'x'), by: owner()),
        _throws<ReleaseStateException>('abandoned'),
      );
    });
  });

  group('a patch', () {
    Future<void> patched() async {
      await live();
      await h.addJob(
        id,
        [('shorebird.patch', StepState.succeeded, {})],
        runId: 'run_9',
        state: JobState.succeeded,
        inputs: [
          {'platform': 'ios', 'patchNumber': 2},
        ],
      );
      await h.service.syncJob('job_5');
    }

    test('is promoted through the shorebird-track workflow', () async {
      await patched();

      final run = await h.service.requestPatch(id, 2, PatchAction.promote);

      final call = h.dispatched.single;
      final workflow = (await h.workflows.list('prj_1'))
          .firstWhere((w) => w.name == 'shorebird-track');
      expect(call.workflow, workflow.id);
      expect(call.request.releaseVersion, '1.2.0+5');
      expect(call.request.release, id);
      expect(call.request.inputs, {'patchNumber': 2, 'action': 'promote'});
      expect(
        _lines(await h.service.history(id)).last,
        'patch_requested promote ${run.id} p2',
      );
    });

    test('must be one XPath published, of a release out', () async {
      await expectLater(
        h.service.requestPatch(
          await h.open(runId: 'run_0', version: '2.0.0'),
          1,
          PatchAction.rollback,
        ),
        _throws<ReleaseStateException>('cannot change: it is draft'),
      );
      await patched();
      await expectLater(
        h.service.requestPatch(id, 3, PatchAction.rollback),
        _throws<ReleaseRequestException>('no patch 3'),
      );
    });

    test('of a version applies to the release the stores approved', () async {
      await live();
      Future<String?> find(String flavor, String version) =>
          h.service.patchable(
            projectId: 'prj_1',
            appPath: '.',
            flavor: flavor,
            version: AppVersion.parse(version),
          );

      expect(await find('prod', '1.2.0+5'), id);
      expect(await find('prod', '1.2.0+6'), isNull);
      expect(await find('prod', '1.3.0+5'), isNull);
      expect(await find('dev', '1.2.0+5'), isNull);
    });

    test('run attaches only to a release the stores approved', () async {
      id = await h.open();

      await expectLater(
        h.service.attach(
          releaseId: id,
          projectId: 'prj_1',
          kind: ReleaseRunKind.patch,
          runId: 'run_9',
        ),
        _throws<ReleaseStateException>('once the stores approved'),
      );
    });
  });
}
