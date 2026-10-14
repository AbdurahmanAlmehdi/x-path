import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/approval_harness.dart';
import '../../helpers/release_harness.dart';

/// The release events as `type detail`, oldest first.
List<String> _summary(List<EngineEvent> events) => [
  for (final event in events)
    switch (event) {
      ReleaseCreated(:final version, :final build, :final flavor) =>
        'created $flavor $version+$build',
      ReleaseStateChanged(:final from, :final to) =>
        'state ${from.wire}->${to.wire}',
      ReleaseStoreChanged(:final store, :final state, :final source) =>
        'store ${store.wire} ${state.wire} ${source.wire}',
      _ => event.type,
    },
];

Matcher _throws<T extends ReleaseException>(String text) =>
    throwsA(isA<T>().having((e) => e.message, 'message', contains(text)));

/// A repository whose list of open releases is a snapshot, as one that was
/// read before another action changed a release.
class _StaleRepository implements ReleaseRepository {
  new(this.inner);

  final InMemoryReleaseRepository inner;

  /// What `list` answers for a state filter, when set.
  List<ReleaseRecord>? frozen;

  @override
  Future<ReleaseRecord?> get(String id) => inner.get(id);

  @override
  Future<List<ReleaseRecord>> list({
    String? projectId,
    String? appPath,
    Set<ReleaseState>? states,
  }) async => states != null && frozen != null
      ? frozen!
      : await inner.list(
          projectId: projectId,
          appPath: appPath,
          states: states,
        );

  @override
  Future<void> create(ReleaseRecord release) => inner.create(release);

  @override
  Future<void> update(ReleaseRecord release) => inner.update(release);
}

void main() {
  late ReleaseHarness h;

  setUp(() async => h = await ReleaseHarness.create());

  group('open', () {
    test(
      'makes a draft release per flavor, with the stores it targets',
      () async {
        final id = await h.open();

        final release = await h.record(id);
        expect(id, startsWith('rel_'));
        expect(release.state, ReleaseState.draft);
        expect(release.version, '1.2.0');
        expect(release.build, 5);
        expect(release.baseBranch, 'main');
        expect(release.runId, 'run_1');
        expect(release.builds.single.build, 5);
        expect(release.stores.keys, [ReleaseStore.apple, ReleaseStore.play]);
        final apple = release.stores[ReleaseStore.apple]!;
        expect(apple.state, StoreState.pending);
        expect(apple.source, StatusSource.upload);
        expect(apple.identity, {
          'bundleId': 'ly.demo',
          'appleAppId': '1234567890',
          'country': 'us',
        });
        expect(release.stores[ReleaseStore.play]!.identity, {
          'packageName': 'ly.demo',
          'track': 'internal',
        });
        expect(_summary(await h.releaseEvents()), ['created prod 1.2.0+5']);
      },
    );

    test('targets only the stores the flavor uploads to', () async {
      final id = await h.open(steps: [uploadPlans().last]);

      expect((await h.record(id)).stores.keys, [ReleaseStore.play]);
    });

    test('leaves the stores empty for a flavor that uploads nowhere', () async {
      final id = await h.open(
        steps: const [StepPlan(kind: 'guard', input: {}, sideEffect: false)],
      );

      expect((await h.record(id)).stores, isEmpty);
    });

    test('makes one release per flavor', () async {
      await h.runs.create(
        RunRecord(
          id: 'run_9',
          projectId: 'prj_1',
          workflowId: 'wf',
          workflowVersionId: 'wfv',
          sha: 'a' * 40,
          locksProject: true,
          createdAt: h.clock.now(),
        ),
      );

      final ids = await h.service.open(
        ReleaseOpening(
          projectId: 'prj_1',
          appPath: '.',
          runId: 'run_9',
          version: '2.0.0',
          build: 9,
          baseBranch: 'main',
          storeCountry: 'sa',
          flavors: [
            FlavorSteps(flavor: 'prod', steps: uploadPlans()),
            FlavorSteps(flavor: 'beta', steps: uploadPlans()),
          ],
        ),
      );

      expect(ids.keys, ['prod', 'beta']);
      expect(ids.values.toSet(), hasLength(2));
      final beta = await h.record(ids['beta']!);
      expect(beta.stores[ReleaseStore.apple]!.identity['country'], 'sa');
    });

    test(
      'abandons a release of the same version that never reached a store',
      () async {
        final first = await h.open();

        final second = await h.open(runId: 'run_2');

        expect(second, isNot(first));
        final replaced = await h.record(first);
        expect(replaced.state, ReleaseState.abandoned);
        expect(replaced.message, 'Replaced by a new release of 1.2.0.');
        expect(
          _summary(await h.releaseEvents()),
          contains('state draft->abandoned'),
        );
      },
    );

    test(
      'keeps a release that has been uploaded, and other versions',
      () async {
        final uploaded = await h.open();
        await h.finishBuild(uploaded);
        await h.service.sync(uploaded);
        final other = await h.open(runId: 'run_2', version: '1.3.0', build: 6);

        final third = await h.open(runId: 'run_3', build: 7);

        expect((await h.record(uploaded)).state, ReleaseState.uploaded);
        expect((await h.record(other)).state, ReleaseState.draft);
        expect(third, isNot(uploaded));
      },
    );

    test('does not abandon a release that moved on while it looked', () async {
      final inner = InMemoryReleaseRepository();
      final stale = _StaleRepository(inner);
      h = await ReleaseHarness.create(repository: stale);
      final first = await h.open();
      // The list will show it as the draft it was ...
      stale.frozen = [(await inner.get(first))!];
      // ... but an upload moved it on before it was abandoned.
      await h.finishBuild(first);
      await h.service.sync(first);

      await h.open(runId: 'run_2');

      expect((await h.record(first)).state, ReleaseState.uploaded);
    });
  });

  group('sync', () {
    test('keeps a draft with no progress as it is', () async {
      final id = await h.open();
      await h.addJob(id, [
        ('git.checkout', StepState.succeeded, null),
        ('build.ios', StepState.pending, null),
      ], state: JobState.waitingForApproval);

      final release = await h.service.get(id);

      expect(release.state, ReleaseState.draft);
      expect(release.updatedAt, h.clock.now());
    });

    test('is building once a build step started', () async {
      final id = await h.open();
      await h.addJob(id, [('build.android', StepState.running, null)]);

      final release = await h.service.get(id);

      expect(release.state, ReleaseState.building);
      expect(_summary(await h.releaseEvents()), [
        'created prod 1.2.0+5',
        'state draft->building',
      ]);
    });

    test('is uploaded once every store has its upload', () async {
      final id = await h.open();
      final ios = await h.addJob(id, [
        ('build.ios', StepState.succeeded, null),
        ('upload.appStore', StepState.succeeded, {}),
      ]);
      await h.addJob(id, [
        ('build.android', StepState.succeeded, null),
        ('upload.play', StepState.running, null),
      ]);

      var release = await h.service.get(id);

      expect(release.state, ReleaseState.building);
      expect(release.stores.map((s) => s.state), [
        StoreState.uploaded,
        StoreState.pending,
      ]);
      await h.setStep(ios, 1, StepState.succeeded);
      final play = (await h.jobs.forRun('run_1')).last;
      await h.setStep(play.id, 1, StepState.succeeded, result: {});

      release = await h.service.get(id);

      expect(release.state, ReleaseState.uploaded);
      expect(release.stores.map((s) => s.state), [
        StoreState.uploaded,
        StoreState.uploaded,
      ]);
      expect(_summary(await h.releaseEvents()), [
        'created prod 1.2.0+5',
        'store apple uploaded upload',
        'state draft->building',
        'store play uploaded upload',
        'state building->uploaded',
      ]);
    });

    test('records the branch, the tag and the pull request', () async {
      final id = await h.open();
      await h.finishBuild(id);

      final release = await h.service.get(id);

      expect(release.state, ReleaseState.uploaded);
      expect(release.branch, 'release/1.2.0');
      expect(release.tag, 'v1.2.0+5');
      expect(release.headSha, 'b' * 40);
      expect(release.prNumber, 7);
      expect(release.prUrl, 'https://github.com/octo/demo/pull/7');
      expect(release.baseBranch, 'main');
    });

    test(
      'says what stopped the build, and clears it when the job goes on',
      () async {
        final id = await h.open();
        final job = await h.addJob(
          id,
          [('build.android', StepState.failed, null)],
          state: JobState.failed,
          message: 'Step 0 (build.android) failed: Gradle',
        );

        var release = await h.service.get(id);

        expect(release.state, ReleaseState.building);
        expect(
          release.message,
          'Job $job failed: Step 0 (build.android) failed: Gradle',
        );
        await h.jobs.updateJob(
          (await h.jobs.get(job))!
              .copyWith(state: JobState.running, message: null),
        );
        await h.setStep(job, 0, StepState.running);

        release = await h.service.get(id);

        expect(release.message, isNull);
      },
    );

    test('names a stopped job without a message', () async {
      final id = await h.open();
      final job = await h.addJob(id, [
        ('build.android', StepState.cancelled, null),
      ], state: JobState.cancelled);

      final release = await h.service.get(id);

      expect(release.message, 'Job $job cancelled');
    });

    test('leaves a release that is over as it is', () async {
      final id = await h.open();
      await h.service.abandon(id, by: owner());
      await h.addJob(id, [('build.android', StepState.running, null)]);

      final release = await h.service.get(id);

      expect(release.state, ReleaseState.abandoned);
    });

    test('says when there is no such release', () async {
      await expectLater(
        h.service.get('rel_nope'),
        _throws<ReleaseNotFoundException>('There is no release rel_nope.'),
      );
    });

    test('syncs the release of a job, and only that', () async {
      final id = await h.open();
      final job = await h.addJob(id, [
        ('build.android', StepState.running, null),
      ]);
      final loose = await h.addJob(id, const []);
      await h.jobs.create(
        JobRecord(
          id: 'job_loose',
          workflowVersionId: 'wfv_1',
          projectId: 'prj_1',
          state: JobState.running,
          createdAt: h.clock.now(),
        ),
        const [],
      );

      await h.service.syncJob('job_loose');
      expect((await h.record(id)).state, ReleaseState.draft);
      await h.service.syncJob('job_nope');
      expect((await h.record(id)).state, ReleaseState.draft);
      await h.service.syncJob(job);

      expect((await h.record(id)).state, ReleaseState.building);
      expect(loose, isNotEmpty);
    });

    test('concurrent syncs move a release once', () async {
      final id = await h.open();
      await h.finishBuild(id);

      await Future.wait([h.service.sync(id), h.service.sync(id)]);

      expect(
        _summary(await h.releaseEvents()).where((e) => e.startsWith('state')),
        ['state draft->building', 'state building->uploaded'],
      );
    });
  });

  group('the stores', () {
    late String id;

    Future<void> uploaded() async {
      id = await h.open();
      await h.finishBuild(id);
      await h.service.sync(id);
    }

    StoreReading reading(
      StoreState? state, {
      String detail = 'DETAIL',
      StatusSource source = StatusSource.api,
    }) => StoreReading(state: state, source: source, detail: detail);

    Future<Release> refresh() => h.service.refresh(id);

    Map<ReleaseStore, StoreState> states(Release release) => {
      for (final status in release.stores) status.store: status.state,
    };

    test('a review moves the release to in_review', () async {
      await uploaded();
      h.apple.reading = reading(StoreState.inReview, detail: 'IN_REVIEW');
      h.play.reading = reading(StoreState.inReview);

      final release = await refresh();

      expect(release.state, ReleaseState.inReview);
      final apple = release.stores.first;
      expect(apple.state, StoreState.inReview);
      expect(apple.detail, 'IN_REVIEW');
      expect(apple.source, StatusSource.api);
      expect(apple.checkedAt, h.clock.now());
      expect(apple.changedAt, h.clock.now());
      expect(
        _summary(await h.releaseEvents()),
        containsAllInOrder([
          'store apple in_review api',
          'store play in_review api',
          'state uploaded->in_review',
        ]),
      );
    });

    test('stays in_review while either store reviews', () async {
      await uploaded();
      h.apple.reading = reading(StoreState.approved);
      h.play.reading = reading(StoreState.inReview);

      expect((await refresh()).state, ReleaseState.inReview);
    });

    test('is approved when each store is, or is live', () async {
      await uploaded();
      h.apple.reading = reading(StoreState.approved);
      h.play.reading = reading(StoreState.live);

      final release = await refresh();

      expect(release.state, ReleaseState.approved);
      expect(states(release), {
        ReleaseStore.apple: StoreState.approved,
        ReleaseStore.play: StoreState.live,
      });
    });

    test(
      'is live only when every store is, and then enables the merge',
      () async {
        await uploaded();
        h.apple.reading = reading(StoreState.live);
        h.play.reading = reading(StoreState.live);

        final release = await refresh();

        expect(release.state, ReleaseState.live);
        expect(release.mergeEnabled, isTrue);
        expect(_summary(await h.releaseEvents()).last, 'state uploaded->live');
      },
    );

    test('is rejected as soon as a store rejects', () async {
      await uploaded();
      h.apple.reading = reading(StoreState.rejected, detail: 'REJECTED');
      h.play.reading = reading(StoreState.live);

      final release = await refresh();

      expect(release.state, ReleaseState.rejected);
      expect(release.mergeEnabled, isFalse);
    });

    test(
      'keeps the status of a reading that says nothing, and its detail',
      () async {
        await uploaded();
        h.apple.reading = reading(null, detail: 'READY_FOR_REVIEW');
        h.play.reading = reading(null, detail: 'RELEASE_LIFECYCLE_STATE_DRAFT');

        final release = await refresh();

        expect(release.state, ReleaseState.uploaded);
        expect(release.stores.first.detail, 'READY_FOR_REVIEW');
        expect(release.stores.first.checkedAt, h.clock.now());
      },
    );

    test('never moves a status back', () async {
      await uploaded();
      h.apple.reading = reading(StoreState.live);
      h.play.reading = reading(StoreState.inReview);
      await refresh();
      h.apple.reading = reading(StoreState.inReview);
      h.play.reading = reading(StoreState.uploaded);

      final release = await refresh();

      expect(states(release), {
        ReleaseStore.apple: StoreState.live,
        ReleaseStore.play: StoreState.inReview,
      });
    });

    test('does not reject what was approved', () async {
      await uploaded();
      h.apple.reading = reading(StoreState.approved);
      h.play.reading = reading(StoreState.inReview);
      await refresh();
      h.apple.reading = reading(StoreState.rejected);

      final release = await refresh();

      expect(states(release)[ReleaseStore.apple], StoreState.approved);
    });

    test('does not ask about a release that was rejected', () async {
      await uploaded();
      h.apple.reading = reading(StoreState.rejected, detail: 'REJECTED');
      h.play.reading = reading(StoreState.inReview);
      await refresh();

      final release = await refresh();

      expect(release.state, ReleaseState.rejected);
      expect(h.apple.reads, hasLength(1), reason: 'it waits for a new build');
    });

    test('says why a store could not be read, and keeps the status', () async {
      await uploaded();
      h.apple.reading = null;
      h.play.failure = const PlayException(500, 'Backend error');

      final release = await refresh();

      expect(release.state, ReleaseState.uploaded);
      expect(release.stores.first.note, contains('Apple approved'));
      expect(release.stores.last.note, 'Google Play: Backend error');
      expect(release.stores.last.checkedAt, h.clock.now());
    });

    test('clears the note once the store answers', () async {
      await uploaded();
      h.apple.reading = null;
      await refresh();
      h.apple.reading = reading(null, detail: 'WAITING');

      final release = await refresh();

      expect(release.stores.first.note, isNull);
    });

    test(
      'asks at most every ten minutes, and the refresh asks at once',
      () async {
        await uploaded();
        h.apple.reading = reading(StoreState.inReview);
        h.play.reading = reading(StoreState.inReview);

        expect(await h.service.pollDue(), 2);
        expect(await h.service.pollDue(), 0);
        h.clock.advance(const Duration(minutes: 9, seconds: 59));
        expect(await h.service.pollDue(), 0);
        await refresh();
        expect(h.apple.reads, hasLength(2));
        h.clock.advance(const Duration(minutes: 10));
        expect(await h.service.pollDue(), 2);
        expect(h.apple.reads, hasLength(3));
      },
    );

    test('polls only the releases that wait for a store', () async {
      await uploaded();
      final building = await h.open(runId: 'run_2', version: '2.0.0');
      await h.addJob(building, [
        ('build.android', StepState.running, null),
      ], runId: 'run_2');
      h.apple.reading = reading(StoreState.live);
      h.play.reading = reading(StoreState.live);
      expect(await h.service.pollDue(), 2);

      expect(await h.service.pollDue(), 0);
      expect((await h.service.refresh(id)).state, ReleaseState.live);
      expect(h.apple.reads.map((r) => r.split(' ').first).toSet(), {id});
    });

    test('a refresh of a release that does not wait asks nothing', () async {
      final building = await h.open();

      final release = await h.service.refresh(building);

      expect(release.state, ReleaseState.draft);
      expect(h.apple.reads, isEmpty);
    });

    test(
      'ignores the rejection a store keeps reporting after a new build',
      () async {
        await uploaded();
        h.apple.reading = reading(StoreState.rejected, detail: 'REJECTED');
        h.play.reading = reading(StoreState.live);
        await refresh();
        await h.service.newBuild(id);
        await h.addJob(id, [
          ('build.ios', StepState.succeeded, null),
          ('upload.appStore', StepState.succeeded, {}),
        ], runId: 'run_2');
        await h.addJob(id, [
          ('upload.play', StepState.succeeded, {}),
        ], runId: 'run_2');
        await h.service.sync(id);
        expect((await h.record(id)).state, ReleaseState.uploaded);

        var release = await refresh();
        expect(states(release)[ReleaseStore.apple], StoreState.uploaded);
        expect(release.state, ReleaseState.uploaded);
        h.apple.reading = reading(StoreState.inReview, detail: 'IN_REVIEW');
        h.play.reading = reading(StoreState.inReview);
        release = await refresh();

        expect(states(release)[ReleaseStore.apple], StoreState.inReview);
        expect(
          (await h.record(id)).stores[ReleaseStore.apple]!.ignored,
          isNull,
        );
      },
    );
  });

  group('by hand', () {
    late String id;

    setUp(() async {
      id = await h.open();
      await h.finishBuild(id);
      await h.service.sync(id);
    });

    test(
      'Apple approved, Play live, Apple live walk the release to live',
      () async {
        var release = await h.service.setStoreStatus(
          id,
          ReleaseStore.apple,
          StoreState.approved,
          by: owner(),
        );
        expect(release.state, ReleaseState.uploaded);
        expect(release.stores.first.source, StatusSource.manual);
        expect(release.stores.first.detail, 'manual');

        release = await h.service.setStoreStatus(
          id,
          ReleaseStore.play,
          StoreState.live,
          by: tokenOf(DeviceTokenKind.cli),
        );
        expect(release.state, ReleaseState.approved);

        release = await h.service.setStoreStatus(
          id,
          ReleaseStore.apple,
          StoreState.live,
          by: owner(),
        );
        expect(release.state, ReleaseState.live);
        expect(
          _summary(await h.releaseEvents()),
          containsAllInOrder([
            'store apple approved manual',
            'store play live manual',
            'state uploaded->approved',
            'store apple live manual',
            'state approved->live',
          ]),
        );
      },
    );

    test('is for app and cli tokens only', () async {
      for (final kind in [DeviceTokenKind.mcp, DeviceTokenKind.runner]) {
        await expectLater(
          h.service.setStoreStatus(
            id,
            ReleaseStore.play,
            StoreState.live,
            by: tokenOf(kind),
          ),
          _throws<ReleaseForbiddenException>(
            'cannot set the status of a store',
          ),
          reason: kind.name,
        );
      }
    });

    test('takes the statuses the buttons offer', () async {
      await expectLater(
        h.service.setStoreStatus(
          id,
          ReleaseStore.apple,
          StoreState.inReview,
          by: owner(),
        ),
        _throws<ReleaseRequestException>('approved or live'),
      );
      await expectLater(
        h.service.setStoreStatus(
          id,
          ReleaseStore.play,
          StoreState.approved,
          by: owner(),
        ),
        _throws<ReleaseRequestException>('can be set to live by hand'),
      );
    });

    test('needs a store the release goes to', () async {
      final playOnly = await h.open(
        runId: 'run_2',
        version: '2.0.0',
        steps: [uploadPlans().last],
      );

      await expectLater(
        h.service.setStoreStatus(
          playOnly,
          ReleaseStore.apple,
          StoreState.live,
          by: owner(),
        ),
        _throws<ReleaseRequestException>('does not go to apple'),
      );
    });

    test(
      'needs the build to be in the store, and the status to be ahead',
      () async {
        final fresh = await h.open(runId: 'run_2', version: '2.0.0');
        await expectLater(
          h.service.setStoreStatus(
            fresh,
            ReleaseStore.play,
            StoreState.live,
            by: owner(),
          ),
          _throws<ReleaseStateException>('play is pending'),
        );
        await h.service.setStoreStatus(
          id,
          ReleaseStore.play,
          StoreState.live,
          by: owner(),
        );
        await expectLater(
          h.service.setStoreStatus(
            id,
            ReleaseStore.play,
            StoreState.live,
            by: owner(),
          ),
          _throws<ReleaseStateException>('play is live'),
        );
      },
    );

    test('says when there is no such release', () async {
      await expectLater(
        h.service.setStoreStatus(
          'rel_nope',
          ReleaseStore.play,
          StoreState.live,
          by: owner(),
        ),
        _throws<ReleaseNotFoundException>('rel_nope'),
      );
    });
  });

  group('a new build of the same version', () {
    late String id;

    Future<void> rejected() async {
      id = await h.open();
      await h.finishBuild(id);
      await h.service.sync(id);
      h.apple.reading = const StoreReading(
        state: StoreState.rejected,
        source: StatusSource.api,
        detail: 'REJECTED',
      );
      h.play.reading = const StoreReading(
        state: StoreState.inReview,
        source: StatusSource.api,
        detail: 'IN_REVIEW',
      );
      await h.service.refresh(id);
    }

    test('dispatches the workflow again on the release branch', () async {
      await rejected();

      final run = await h.service.newBuild(id);

      expect(run.id, 'run_2');
      final call = h.dispatched.single;
      expect(call.project, 'prj_1');
      expect(call.workflow, 'wf_release');
      expect(call.request.release, id);
      expect(call.request.ref, 'release/1.2.0');
      expect(call.request.version, '1.2.0');
      expect(call.request.bump, isNull);
      expect(call.request.flavors, ['prod']);
      expect(call.request.platforms, ['android', 'ios']);
      expect(call.request.inputs, {'notes': 'hello'});
    });

    test('takes the release back to building with the new number', () async {
      await rejected();

      await h.service.newBuild(id);

      final release = await h.record(id);
      expect(release.state, ReleaseState.building);
      expect(release.build, 6);
      expect(release.builds.map((b) => (b.build, b.runId)), [
        (5, 'run_1'),
        (6, 'run_2'),
      ]);
      expect(release.tag, isNull);
      expect(release.headSha, isNull);
      expect(release.prNumber, 7, reason: 'the pull request stays');
      expect(release.branch, 'release/1.2.0');
      expect(release.stores.values.map((e) => e.state), [
        StoreState.pending,
        StoreState.pending,
      ]);
      expect(release.stores[ReleaseStore.apple]!.ignored, 'REJECTED');
      expect(release.stores[ReleaseStore.play]!.ignored, isNull);
      expect(release.stores[ReleaseStore.apple]!.checkedAt, isNull);
      expect(
        _summary(await h.releaseEvents()),
        containsAllInOrder([
          'state uploaded->rejected',
          'state rejected->building',
          'store apple pending upload',
          'store play pending upload',
        ]),
      );
    });

    test('is offered to a rejected release only', () async {
      final fresh = await h.open(runId: 'run_8', version: '9.9.9');

      await expectLater(
        h.service.newBuild(fresh),
        _throws<ReleaseStateException>('Only a rejected release'),
      );
      await rejected();
      await h.service.newBuild(id);
      await expectLater(
        h.service.newBuild(id),
        _throws<ReleaseStateException>('building'),
      );
    });

    test('needs the release branch', () async {
      id = await h.open();
      await h.addJob(id, [
        ('upload.appStore', StepState.succeeded, {}),
        ('upload.play', StepState.succeeded, {}),
      ]);
      await h.service.sync(id);
      h.apple.reading = const StoreReading(
        state: StoreState.rejected,
        source: StatusSource.api,
        detail: 'REJECTED',
      );
      h.play.reading = const StoreReading(
        state: StoreState.live,
        source: StatusSource.api,
        detail: 'PUBLISHED',
      );
      await h.service.refresh(id);

      await expectLater(
        h.service.newBuild(id),
        _throws<ReleaseStateException>('Only a rejected release'),
      );
    });
  });

  group('attach', () {
    test('says when the project has no such release', () async {
      final id = await h.open();

      for (final (release, project) in [
        ('rel_nope', 'prj_1'),
        (id, 'prj_other'),
      ]) {
        await expectLater(
          h.service.attach(
            releaseId: release,
            projectId: project,
            kind: ReleaseRunKind.merge,
            runId: 'run_9',
          ),
          _throws<ReleaseNotFoundException>(release),
        );
      }
    });

    test('refuses a new build of a release that was not rejected', () async {
      final id = await h.open();

      await expectLater(
        h.service.attach(
          releaseId: id,
          projectId: 'prj_1',
          kind: ReleaseRunKind.build,
          runId: 'run_9',
          build: 6,
        ),
        _throws<ReleaseStateException>('Only a rejected release'),
      );
    });

    test('refuses a merge before the release is live', () async {
      final id = await h.open();

      await expectLater(
        h.service.attach(
          releaseId: id,
          projectId: 'prj_1',
          kind: ReleaseRunKind.merge,
          runId: 'run_9',
        ),
        _throws<ReleaseStateException>('release is draft'),
      );
    });
  });

  group('the merge', () {
    late String id;

    Future<void> live() async {
      id = await h.open();
      await h.finishBuild(id);
      await h.service.sync(id);
      for (final store in ReleaseStore.values) {
        await h.service.setStoreStatus(id, store, StoreState.live, by: owner());
      }
    }

    test('is requested through the release-merge workflow', () async {
      await live();

      final run = await h.service.requestMerge(id);

      expect(run.id, 'run_2');
      final call = h.dispatched.single;
      final mergeWorkflow = (await h.workflows.list('prj_1'))
          .firstWhere((w) => w.name == 'release-merge');
      expect(call.workflow, mergeWorkflow.id);
      expect(call.request.ref, 'release/1.2.0');
      expect(call.request.app, '.');
      expect(call.request.flavors, ['prod']);
      expect(call.request.releaseVersion, '1.2.0+5');
      expect(call.request.release, id);
      final release = await h.record(id);
      expect(release.mergeRunId, 'run_2');
      expect(release.mergeEnabled, isFalse);
    });

    test('asked again, answers with the run that is under way', () async {
      await live();
      final first = await h.service.requestMerge(id);

      final second = await h.service.requestMerge(id);

      expect(second.id, first.id);
      expect(h.dispatched, hasLength(1));
    });

    test(
      'waits until every store is live and the pull request is open',
      () async {
        id = await h.open();
        await expectLater(
          h.service.requestMerge(id),
          _throws<ReleaseStateException>('is draft and has no pull request'),
        );
        await h.finishBuild(id);
        await h.service.sync(id);
        await expectLater(
          h.service.requestMerge(id),
          _throws<ReleaseStateException>('is uploaded'),
        );
      },
    );

    test('needs the pull request', () async {
      id = await h.open();
      await h.addJob(id, [
        ('upload.appStore', StepState.succeeded, {}),
        ('upload.play', StepState.succeeded, {}),
      ]);
      await h.service.sync(id);
      for (final store in ReleaseStore.values) {
        await h.service.setStoreStatus(id, store, StoreState.live, by: owner());
      }

      await expectLater(
        h.service.requestMerge(id),
        _throws<ReleaseStateException>('has no pull request'),
      );
    });

    test('makes the release merged once the merge step succeeded', () async {
      await live();
      await h.service.requestMerge(id);
      final job = await h.addJob(
        id,
        [
          ('gate', StepState.succeeded, {}),
          (
            'github.mergePr',
            StepState.succeeded,
            {'number': 7, 'sha': 'c' * 40, 'alreadyMerged': false},
          ),
        ],
        runId: 'run_2',
        state: JobState.succeeded,
      );

      final release = await h.service.get(id);

      expect(release.state, ReleaseState.merged);
      expect(release.mergeCommit, 'c' * 40);
      expect(release.mergeEnabled, isFalse);
      expect(job, isNotEmpty);
      expect(_summary(await h.releaseEvents()).last, 'state live->merged');
    });

    test('lets the merge be requested again when its run ended', () async {
      await live();
      await h.service.requestMerge(id);
      await h.addJob(
        id,
        [('gate', StepState.failed, null)],
        runId: 'run_2',
        state: JobState.failed,
        message: 'Step 0 (gate) failed: denied',
      );

      final release = await h.service.get(id);

      expect(release.state, ReleaseState.live);
      expect(release.mergeRunId, isNull);
      expect(release.mergeEnabled, isTrue);
      expect(
        release.message,
        'The merge run run_2 ended: Step 0 (gate) failed: denied',
      );
    });

    test('keeps waiting while the merge run waits for the owner', () async {
      await live();
      await h.service.requestMerge(id);
      await h.addJob(
        id,
        [('gate', StepState.waitingForApproval, null)],
        runId: 'run_2',
        state: JobState.waitingForApproval,
      );

      final release = await h.service.get(id);

      expect(release.mergeRunId, 'run_2');
      expect(release.state, ReleaseState.live);
    });
  });

  group('abandon', () {
    test('gives a release up and stops the run that builds it', () async {
      final id = await h.open();
      final job = await h.addJob(id, [
        ('build.android', StepState.running, null),
      ]);

      final release = await h.service.abandon(
        id,
        by: owner(),
        reason: '  wrong build ',
      );

      expect(release.state, ReleaseState.abandoned);
      expect(release.message, 'wrong build');
      expect(h.control.cancelled, [job]);
      expect(
        _summary(await h.releaseEvents()).last,
        'state building->abandoned',
      );
    });

    test('has a default reason', () async {
      final id = await h.open();

      expect((await h.service.abandon(id, by: owner())).message, 'Abandoned.');
      final other = await h.open(runId: 'run_2', version: '2.0.0');
      expect(
        (await h.service.abandon(other, by: owner(), reason: ' ')).message,
        'Abandoned.',
      );
    });

    test('works on a live release, whose run ended already', () async {
      final id = await h.open();
      await h.finishBuild(id);
      await h.service.sync(id);
      for (final store in ReleaseStore.values) {
        await h.service.setStoreStatus(id, store, StoreState.live, by: owner());
      }

      final release = await h.service.abandon(
        id,
        by: tokenOf(DeviceTokenKind.cli),
      );

      expect(release.state, ReleaseState.abandoned);
      expect(h.control.cancelled, isEmpty);
    });

    test('does not need the run of the release to still exist', () async {
      final ids = await h.service.open(
        ReleaseOpening(
          projectId: 'prj_1',
          appPath: '.',
          runId: 'run_gone',
          version: '3.0.0',
          build: 9,
          baseBranch: 'main',
          storeCountry: 'us',
          flavors: [FlavorSteps(flavor: 'prod', steps: uploadPlans())],
        ),
      );

      final release = await h.service.abandon(ids['prod']!, by: owner());

      expect(release.state, ReleaseState.abandoned);
    });

    test('is for app and cli tokens only', () async {
      final id = await h.open();

      await expectLater(
        h.service.abandon(id, by: tokenOf(DeviceTokenKind.mcp)),
        _throws<ReleaseForbiddenException>(
          'mcp token cannot abandon a release',
        ),
      );
    });

    test('is not for a release that is over', () async {
      final id = await h.open();
      await h.service.abandon(id, by: owner());

      await expectLater(
        h.service.abandon(id, by: owner()),
        _throws<ReleaseStateException>('abandoned'),
      );
    });
  });

  group('list', () {
    test('lists the releases newest first, with filters', () async {
      final first = await h.open();
      final second = await h.open(runId: 'run_2', version: '1.3.0');
      await h.service.abandon(first, by: owner());

      expect((await h.service.list()).map((r) => r.id), [second, first]);
      expect(
        (await h.service.list(projectId: 'prj_other')).map((r) => r.id),
        isEmpty,
      );
      expect(
        (await h.service.list(appPath: 'packages/other')).map((r) => r.id),
        isEmpty,
      );
      expect(
        (await h.service.list(state: ReleaseState.abandoned)).map((r) => r.id),
        [first],
      );
      expect(
        (await h.service.list(projectId: 'prj_1', appPath: '.')).length,
        2,
      );
    });

    test('brings each release up to date first', () async {
      final id = await h.open();
      await h.addJob(id, [('build.ios', StepState.running, null)]);

      final listed = await h.service.list(state: ReleaseState.building);

      expect(listed.single.id, id);
    });
  });
}
