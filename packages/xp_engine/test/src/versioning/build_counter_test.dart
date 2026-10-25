import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late InMemoryBuildCounterRepository counters;

  setUp(
    () => counters = InMemoryBuildCounterRepository(
      [('prj_1', '.'), ('prj_1', 'apps/b')],
      counters: {('prj_1', 'apps/b'): 40},
    ),
  );

  test('counts up from the counter when the seed is lower', () async {
    expect(
      await counters.allocate(projectId: 'prj_1', appPath: 'apps/b', seed: 10),
      41,
    );
    expect(
      await counters.allocate(projectId: 'prj_1', appPath: 'apps/b', seed: 0),
      42,
    );
    expect(counters.counterOf('prj_1', 'apps/b'), 42);
  });

  test('jumps over the seed when it is higher than the counter', () async {
    expect(
      await counters.allocate(projectId: 'prj_1', appPath: '.', seed: 3283),
      3284,
    );
    expect(counters.counterOf('prj_1', '.'), 3284);
  });

  test('keeps one counter per app', () async {
    await counters.allocate(projectId: 'prj_1', appPath: '.', seed: 0);

    expect(counters.counterOf('prj_1', 'apps/b'), 40);
  });

  test('refuses an unknown app and a negative seed', () {
    expect(
      counters.allocate(projectId: 'prj_1', appPath: 'nope', seed: 0),
      throwsA(
        isA<UnknownAppException>()
            .having((e) => e.projectId, 'projectId', 'prj_1')
            .having((e) => e.appPath, 'appPath', 'nope')
            .having((e) => '$e', 'text', contains('no app at nope')),
      ),
    );
    expect(
      counters.allocate(projectId: 'prj_1', appPath: '.', seed: -1),
      throwsRangeError,
    );
    expect(
      () => counters.counterOf('x', 'y'),
      throwsA(isA<UnknownAppException>()),
    );
  });

  test('peeks at the next number without taking it (a dry run)', () async {
    expect(
      await counters.peek(projectId: 'prj_1', appPath: 'apps/b', seed: 10),
      41,
    );
    expect(
      await counters.peek(projectId: 'prj_1', appPath: 'apps/b', seed: 50),
      51,
    );
    expect(counters.counterOf('prj_1', 'apps/b'), 40);
    expect(
      () => counters.peek(projectId: 'prj_1', appPath: 'apps/b', seed: -1),
      throwsRangeError,
    );
  });
}
