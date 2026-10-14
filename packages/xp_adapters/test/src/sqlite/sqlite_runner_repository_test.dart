import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

final _created = DateTime.utc(2026, 10, 14, 9, 30, 15, 123, 456);

RunnerRecord _runner(
  String id, {
  String? name,
  Set<Capability> capabilities = const {},
  DateTime? revokedAt,
}) => RunnerRecord(
  id: id,
  name: name ?? 'runner $id',
  tokenId: 'tok_$id',
  createdAt: _created,
  capabilities: capabilities,
  revokedAt: revokedAt,
);

void main() {
  late SqliteDatabase database;
  late SqliteRunnerRepository repository;

  Future<void> addToken(String id) => SqliteDeviceTokenRepository(database).add(
    DeviceToken(
      id: 'tok_$id',
      name: id,
      kind: DeviceTokenKind.runner,
      hash: 'hash-$id',
      createdAt: _created,
    ),
  );

  setUp(() async {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    repository = SqliteRunnerRepository(database);
    await addToken('a');
    await addToken('b');
  });

  test('starts empty', () async {
    expect(await repository.list(), isEmpty);
    expect(await repository.get('a'), isNull);
    expect(await repository.findByName('x'), isNull);
    expect(await repository.findByToken('tok_a'), isNull);
  });

  test('stores a runner with every field', () async {
    final runner = _runner('a').copyWith(
      capabilities: {Capability.iosSign, Capability.flutter},
      slots: 3,
      os: 'macos',
      arch: 'arm64',
      version: '1.0.0',
      cores: 12,
      lastHeartbeat: _created.add(const Duration(minutes: 1)),
      revokedAt: _created.add(const Duration(days: 1)),
    );

    await repository.add(runner);

    expect(await repository.get('a'), runner);
    expect(await repository.findByName('runner a'), runner);
    expect(await repository.findByToken('tok_a'), runner);
  });

  test('stores a runner that was never probed or heard from', () async {
    await repository.add(_runner('a'));

    final stored = (await repository.get('a'))!;
    expect(stored.capabilities, isEmpty);
    expect(stored.slots, 1);
    expect(stored.os, isNull);
    expect(stored.cores, isNull);
    expect(stored.lastHeartbeat, isNull);
    expect(stored.revokedAt, isNull);
  });

  test('lists the runners in the order they were paired', () async {
    await repository.add(_runner('b'));
    await repository.add(_runner('a'));

    expect((await repository.list()).map((r) => r.id), ['b', 'a']);
  });

  test('keeps the capabilities as a JSON array of wire names', () async {
    await repository.add(
      _runner('a', capabilities: {Capability.swiftLinux, Capability.android}),
    );

    final stored = database.connection
        .select("SELECT capabilities FROM runner WHERE id = 'a'")
        .single['capabilities'];
    expect(stored, '["android","swift-linux"]');
  });

  test('reads what an older row or a newer engine wrote', () async {
    await repository.add(_runner('a'));
    await repository.add(_runner('b'));
    database.connection
      ..execute("UPDATE runner SET capabilities = '{}' WHERE id = 'a'")
      ..execute(
        "UPDATE runner SET capabilities = '[\"flutter\",\"lasers\",7]' "
        "WHERE id = 'b'",
      );

    expect((await repository.get('a'))!.capabilities, isEmpty);
    expect((await repository.get('b'))!.capabilities, {Capability.flutter});
  });

  test('updates a runner', () async {
    await repository.add(_runner('a'));

    await repository.update(
      _runner('a').copyWith(
        capabilities: {Capability.flutter},
        slots: 2,
        os: 'linux',
        lastHeartbeat: _created,
        revokedAt: _created,
      ),
    );

    final stored = (await repository.get('a'))!;
    expect(stored.capabilities, {Capability.flutter});
    expect(stored.slots, 2);
    expect(stored.os, 'linux');
    expect(stored.lastHeartbeat, _created);
    expect(stored.isRevoked, isTrue);
    expect(await repository.list(), hasLength(1));
  });

  test('cannot update a runner it does not have', () async {
    await expectLater(repository.update(_runner('a')), throwsStateError);
  });

  test('refuses a second runner with the same name or credential', () async {
    await repository.add(_runner('a', name: 'mini'));

    expect(
      () => repository.add(_runner('b', name: 'mini')),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => repository.add(
        RunnerRecord(
          id: 'c',
          name: 'other',
          tokenId: 'tok_a',
          createdAt: _created,
        ),
      ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('refuses a credential that is not a device token', () async {
    expect(
      () => repository.add(
        RunnerRecord(
          id: 'c',
          name: 'other',
          tokenId: 'tok_nobody',
          createdAt: _created,
        ),
      ),
      throwsA(isA<SqliteException>()),
    );
  });
}
