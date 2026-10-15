import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/storage/storage.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/engine_fixtures.dart';
import '../helpers/fakes.dart';

void main() {
  late MockStorageRepository storage;

  const freed = FreeSpaceResult(
    dryRun: false,
    categories: [
      FreedCategory(category: StorageCategory.logs, bytes: 600, items: 3),
    ],
  );
  const settings = RetentionSettings(keepPerFlavor: 3, logDays: 30);

  setUp(() {
    storage = MockStorageRepository();
    when(storage.watchStorage)
        .thenAnswer((_) => Stream.value(Snapshot(storageReport)));
  });

  test('events compare by value', () {
    expect(const StorageSubscriptionRequested().props, isEmpty);
    expect(const StorageFreeRequested([StorageCategory.logs]).props, [
      [StorageCategory.logs],
    ]);
    expect(const StorageRetentionChanged(settings).props, [settings]);
  });

  blocTest<StorageBloc, StorageState>(
    'reads the report, and says why it could not',
    setUp: () => when(storage.watchStorage).thenAnswer(
      (_) => Stream.error(const ApiException('Disk gone.', statusCode: 500)),
    ),
    build: () => StorageBloc(storage: storage),
    act: (bloc) => bloc.add(const StorageSubscriptionRequested()),
    expect: () => const [StorageState(loaded: true, error: 'Disk gone.')],
  );

  blocTest<StorageBloc, StorageState>(
    'frees space, then reads the report again',
    setUp: () =>
        when(() => storage.freeSpace([StorageCategory.logs]))
            .thenAnswer((_) async => freed),
    build: () => StorageBloc(storage: storage),
    act: (bloc) => bloc.add(const StorageFreeRequested([StorageCategory.logs])),
    expect: () => [
      const StorageState(command: StorageCommand.freeing),
      const StorageState(command: StorageCommand.freeing, freed: freed),
      const StorageState(freed: freed),
      StorageState(loaded: true, report: storageReport, freed: freed),
    ],
  );

  blocTest<StorageBloc, StorageState>(
    'saves the retention, and says why it could not',
    setUp: () => when(() => storage.setRetention(settings))
        .thenThrow(const ApiException('Only the app may.', statusCode: 403)),
    build: () => StorageBloc(storage: storage),
    act: (bloc) => bloc.add(const StorageRetentionChanged(settings)),
    expect: () => const [
      StorageState(command: StorageCommand.saving),
      StorageState(error: 'Only the app may.'),
    ],
  );

  blocTest<StorageBloc, StorageState>(
    'saves the retention, then reads the report again',
    setUp: () =>
        when(() => storage.setRetention(settings))
            .thenAnswer((_) async => settings),
    build: () => StorageBloc(storage: storage),
    act: (bloc) => bloc.add(const StorageRetentionChanged(settings)),
    expect: () => [
      const StorageState(command: StorageCommand.saving),
      const StorageState(),
      StorageState(loaded: true, report: storageReport),
    ],
  );
}
