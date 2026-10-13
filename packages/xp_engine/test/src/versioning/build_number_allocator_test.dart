import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/stub_git.dart';

void main() {
  const mirror = GitMirror(githubRepoId: 1, path: '/m.git');
  late StubGit git;
  late FakeStoreBuildNumbers store;
  late InMemoryBuildCounterRepository counters;
  late BuildNumberAllocator allocator;

  setUp(() {
    git = StubGit();
    store = FakeStoreBuildNumbers(const StoreBuilds({}));
    counters = InMemoryBuildCounterRepository([('prj_1', '.')]);
    allocator = BuildNumberAllocator(
      counters: counters,
      stores: store,
      git: git,
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
}
