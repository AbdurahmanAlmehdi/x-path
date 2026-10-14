import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  final at = DateTime.utc(2026, 10, 14, 9);
  final later = at.add(const Duration(minutes: 3));

  StoreEntry entry({
    ReleaseStore store = ReleaseStore.apple,
    StoreState state = StoreState.inReview,
  }) => StoreEntry(
    store: store,
    state: state,
    source: StatusSource.api,
    identity: const {'bundleId': 'ly.demo'},
    detail: 'IN_REVIEW',
    checkedAt: at,
    changedAt: at,
    note: 'a note',
    ignored: 'REJECTED',
  );

  ReleaseRecord record({ReleaseState state = ReleaseState.live}) =>
      ReleaseRecord(
        id: 'rel_1',
        projectId: 'prj_1',
        appPath: '.',
        flavor: 'prod',
        version: '1.2.0',
        build: 5,
        state: state,
        stores: {ReleaseStore.apple: entry()},
        builds: [ReleaseBuild(build: 5, runId: 'run_1', createdAt: at)],
        baseBranch: 'main',
        createdAt: at,
        updatedAt: at,
        prNumber: 7,
      );

  group('StoreEntry', () {
    test('round-trips through JSON with everything', () {
      final stored = entry().toJson();

      expect(stored, {
        'state': 'in_review',
        'source': 'api',
        'identity': {'bundleId': 'ly.demo'},
        'detail': 'IN_REVIEW',
        'checkedAt': '2026-10-14T09:00:00.000Z',
        'changedAt': '2026-10-14T09:00:00.000Z',
        'note': 'a note',
        'ignored': 'REJECTED',
      });
      expect(StoreEntry.fromJson(ReleaseStore.apple, stored), entry());
    });

    test('leaves out what it lacks', () {
      const bare = StoreEntry(
        store: ReleaseStore.play,
        state: StoreState.pending,
        source: StatusSource.upload,
      );

      expect(bare.toJson().keys, {'state', 'source', 'identity'});
      expect(StoreEntry.fromJson(ReleaseStore.play, bare.toJson()), bare);
    });

    test('replaces and clears fields', () {
      final next = entry().copyWith(
        state: StoreState.live,
        source: StatusSource.manual,
        detail: null,
        checkedAt: later,
        changedAt: null,
        note: null,
        ignored: null,
      );

      expect(next.state, StoreState.live);
      expect(next.source, StatusSource.manual);
      expect(next.detail, isNull);
      expect(next.checkedAt, later);
      expect(next.changedAt, isNull);
      expect(next.note, isNull);
      expect(next.ignored, isNull);
      expect(next.identity, entry().identity);
      expect(entry().copyWith(), entry());
      expect(entry().copyWith(detail: 'X').detail, 'X');
      expect(entry().copyWith(changedAt: later).changedAt, later);
      expect(entry().copyWith(note: 'n').note, 'n');
      expect(entry().copyWith(ignored: 'I').ignored, 'I');
    });

    test('shows the owner the status without the identity', () {
      expect(
        entry().toApi(),
        StoreStatus(
          store: ReleaseStore.apple,
          state: StoreState.inReview,
          source: StatusSource.api,
          detail: 'IN_REVIEW',
          checkedAt: at,
          changedAt: at,
          note: 'a note',
        ),
      );
    });
  });

  group('ReleaseRecord', () {
    test('replaces and clears fields', () {
      final base = record().copyWith(
        branch: 'release/1.2.0',
        tag: 'v1.2.0+5',
        headSha: 'b' * 40,
        prUrl: 'https://example/pull/7',
        mergeCommit: 'c' * 40,
        mergeRunId: 'run_2',
        message: 'hi',
      );

      expect(base.branch, 'release/1.2.0');
      expect(base.tag, 'v1.2.0+5');
      expect(base.headSha, 'b' * 40);
      expect(base.prUrl, 'https://example/pull/7');
      expect(base.mergeCommit, 'c' * 40);
      expect(base.mergeRunId, 'run_2');
      expect(base.message, 'hi');
      final cleared = base.copyWith(
        build: 6,
        state: ReleaseState.merged,
        stores: const {},
        builds: const [],
        updatedAt: later,
        branch: null,
        tag: null,
        headSha: null,
        prNumber: null,
        prUrl: null,
        mergeCommit: null,
        mergeRunId: null,
        message: null,
      );
      expect(cleared.build, 6);
      expect(cleared.state, ReleaseState.merged);
      expect(cleared.stores, isEmpty);
      expect(cleared.builds, isEmpty);
      expect(cleared.updatedAt, later);
      expect(cleared.branch, isNull);
      expect(cleared.tag, isNull);
      expect(cleared.headSha, isNull);
      expect(cleared.prNumber, isNull);
      expect(cleared.prUrl, isNull);
      expect(cleared.mergeCommit, isNull);
      expect(cleared.mergeRunId, isNull);
      expect(cleared.message, isNull);
      expect(record().copyWith(), record());
      expect(record().copyWith(prNumber: 8).prNumber, 8);
    });

    test('enables the merge of a live release with its pull request', () {
      expect(record().mergeEnabled, isTrue);
      expect(record(state: ReleaseState.approved).mergeEnabled, isFalse);
      expect(record().copyWith(prNumber: null).mergeEnabled, isFalse);
      expect(record().copyWith(mergeRunId: 'run_2').mergeEnabled, isFalse);
    });

    test('names the run of the current build', () {
      expect(record().runId, 'run_1');
      expect(
        record()
            .copyWith(
              builds: [
                ReleaseBuild(build: 5, runId: 'run_1', createdAt: at),
                ReleaseBuild(build: 6, runId: 'run_2', createdAt: later),
              ],
            )
            .runId,
        'run_2',
      );
    });

    test('stores the stores as JSON, the apple one and the play one', () {
      final stores = {
        ReleaseStore.apple: entry(),
        ReleaseStore.play: entry(store: ReleaseStore.play),
      };

      final json = record().copyWith(stores: stores).storesToJson();

      expect(json.keys, ['apple', 'play']);
      expect(ReleaseRecord.storesFromJson(json), stores);
      expect(ReleaseRecord.storesFromJson({'play': json['play']}).keys, [
        ReleaseStore.play,
      ]);
      expect(ReleaseRecord.storesFromJson(const {}), isEmpty);
    });

    test('shows the API form', () {
      final release = record()
          .copyWith(branch: 'release/1.2.0', tag: 'v1.2.0+5')
          .toApi();

      expect(release.id, 'rel_1');
      expect(release.projectId, 'prj_1');
      expect(release.app, '.');
      expect(release.flavor, 'prod');
      expect(release.version, '1.2.0');
      expect(release.build, 5);
      expect(release.state, ReleaseState.live);
      expect(release.stores.single.store, ReleaseStore.apple);
      expect(release.builds.single.runId, 'run_1');
      expect(release.mergeEnabled, isTrue);
      expect(release.branch, 'release/1.2.0');
      expect(release.baseBranch, 'main');
      expect(release.tag, 'v1.2.0+5');
      expect(release.prNumber, 7);
      expect(release.createdAt, at);
    });
  });

  group('InMemoryReleaseRepository', () {
    late InMemoryReleaseRepository repository;

    setUp(() => repository = InMemoryReleaseRepository());

    ReleaseRecord make(
      String id, {
      String project = 'prj_1',
      String app = '.',
      ReleaseState state = ReleaseState.draft,
    }) => ReleaseRecord(
      id: id,
      projectId: project,
      appPath: app,
      flavor: 'prod',
      version: '1.2.0',
      build: 5,
      state: state,
      stores: const {},
      builds: [ReleaseBuild(build: 5, runId: 'run_$id', createdAt: at)],
      baseBranch: 'main',
      createdAt: at,
      updatedAt: at,
    );

    test('stores, reads and replaces', () async {
      await repository.create(make('a'));
      expect(await repository.get('a'), make('a'));
      expect(await repository.get('nope'), isNull);

      await repository.update(make('a', state: ReleaseState.building));

      expect((await repository.get('a'))!.state, ReleaseState.building);
    });

    test(
      'refuses a second release with the same id, and an unknown update',
      () async {
        await repository.create(make('a'));

        expect(() => repository.create(make('a')), throwsStateError);
        expect(() => repository.update(make('b')), throwsStateError);
      },
    );

    test('lists newest first, and filters', () async {
      await repository.create(make('a'));
      await repository.create(make('b', project: 'prj_2'));
      await repository.create(
        make('c', app: 'packages/x', state: ReleaseState.live),
      );

      expect((await repository.list()).map((r) => r.id), ['c', 'b', 'a']);
      expect((await repository.list(projectId: 'prj_1')).map((r) => r.id), [
        'c',
        'a',
      ]);
      expect((await repository.list(appPath: 'packages/x')).map((r) => r.id), [
        'c',
      ]);
      expect(
        (await repository.list(states: {ReleaseState.live})).map((r) => r.id),
        ['c'],
      );
    });
  });
}
