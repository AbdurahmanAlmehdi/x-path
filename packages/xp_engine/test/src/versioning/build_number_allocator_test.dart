import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/stub_git.dart';

void main() {
  const mirror = GitMirror(githubRepoId: 1, path: '/m.git');
  late StubGit git;
  late FakeStoreBuildNumbers store;
  late InMemoryBuildCounterRepository counters;
  late BuildNumberAllocator allocator;
  late ManualClock clock;

  setUp(() {
    clock = ManualClock(DateTime.utc(2026, 10, 24, 9));
    git = StubGit();
    store = FakeStoreBuildNumbers(const StoreBuilds({}));
    counters = InMemoryBuildCounterRepository([('prj_1', '.')]);
    allocator = BuildNumberAllocator(
      counters: counters,
      stores: store,
      git: git,
      clock: clock,
    );
  });

  Future<int> allocate({
    ReleaseModel model = const ReleaseModel(),
    TagScope scope = const TagScope(),
  }) => allocator.allocate(
    projectId: 'prj_1',
    appPath: '.',
    mirror: mirror,
    model: model,
    scope: scope,
    iosBundleId: 'com.mataa.app',
    androidAppId: 'com.mataa.app',
  );

  test('starts at 1 for an app that was never released', () async {
    expect(await allocate(), 1);
  });

  test('continues after the highest store build', () async {
    store.builds = const StoreBuilds({3279, 3282});

    expect(await allocate(), 3283);
    expect(store.lookups, ['com.mataa.app com.mataa.app']);
  });

  test('continues after the highest tagged build, patches included', () async {
    git.tags.addAll(const [
      GitTagInfo(name: 'v5.4.0+3282', commit: 'a'),
      GitTagInfo(name: 'v5.4.0+3290-p1', commit: 'b'),
      GitTagInfo(name: 'archive/old', commit: 'c'),
      GitTagInfo(name: 'v5.3.0+100', commit: 'd'),
    ]);

    expect(await allocate(), 3291);
  });

  test('counts only the tags of the app and flavor', () async {
    const model = ReleaseModel(tagPattern: '{app}/v{version}+{build}');
    git.tags.addAll(const [
      GitTagInfo(name: 'mobile/v1.0.0+7', commit: 'a'),
      GitTagInfo(name: 'web/v1.0.0+900', commit: 'b'),
    ]);

    expect(
      await allocate(
        model: model,
        scope: const TagScope(app: 'mobile'),
      ),
      8,
    );
  });

  test('continues after the counter when it is the highest', () async {
    await counters.allocate(projectId: 'prj_1', appPath: '.', seed: 5000);
    store.builds = const StoreBuilds({3282});
    git.tags.add(const GitTagInfo(name: 'v5.4.0+3282', commit: 'a'));

    expect(await allocate(), 5002);
  });

  test('never hands out the same number twice', () async {
    final first = await allocate();
    final second = await allocate();

    expect(second, greaterThan(first));
  });

  test(
    'goes on with tags and counter when the stores cannot be asked',
    () async {
      store.builds = null;
      git.tags.add(const GitTagInfo(name: 'v5.4.0+3282', commit: 'a'));

      expect(await allocate(), 3283);
    },
  );

  test('peeks at the number it would allocate without taking it', () async {
    store.builds = const StoreBuilds({3282});

    final peeked = await allocator.peek(
      projectId: 'prj_1',
      appPath: '.',
      mirror: mirror,
      iosBundleId: 'com.mataa.app',
    );

    expect(peeked, 3283);
    expect(counters.counterOf('prj_1', '.'), 0);
    expect(await allocate(), 3283);
  });

  test('a peek asks the stores again only after a minute', () async {
    Future<int> peek() => allocator.peek(
      projectId: 'prj_1',
      appPath: '.',
      mirror: mirror,
      iosBundleId: 'com.mataa.app',
    );
    store.builds = const StoreBuilds({10});

    expect(await peek(), 11);
    store.builds = const StoreBuilds({20});
    expect(await peek(), 11, reason: 'what the stores said a moment ago');
    expect(store.lookups, hasLength(1));

    clock.advance(BuildNumberAllocator.storeAnswerKept);
    expect(await peek(), 21);
    expect(store.lookups, hasLength(2));
  });

  test('an allocation always asks the stores', () async {
    store.builds = const StoreBuilds({10});
    await allocator.peek(
      projectId: 'prj_1',
      appPath: '.',
      mirror: mirror,
      iosBundleId: 'com.mataa.app',
      androidAppId: 'com.mataa.app',
    );
    store.builds = const StoreBuilds({20});

    expect(await allocate(), 21);
    expect(store.lookups, hasLength(2));
  });
}
