import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/schema_dump.dart';

DeviceToken _token(String id, {DeviceTokenKind? kind, DateTime? revokedAt}) =>
    DeviceToken(
      id: id,
      name: 'device $id',
      kind: kind ?? DeviceTokenKind.app,
      hash: 'hash-$id',
      createdAt: DateTime.utc(2026, 10, 13, 8, 30, 15, 123, 456),
      revokedAt: revokedAt,
    );

void main() {
  late SqliteDatabase database;
  late SqliteDeviceTokenRepository repository;

  setUp(() {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    repository = SqliteDeviceTokenRepository(database);
  });

  test('starts empty', () async {
    expect(await repository.list(), isEmpty);
  });

  test('lists tokens in the order they were added, with every field', () async {
    final revoked = _token(
      'b',
      kind: DeviceTokenKind.runner,
      revokedAt: DateTime.utc(2026, 10, 14, 1, 2, 3, 4, 5),
    );
    await repository.add(_token('a'));
    await repository.add(revoked);
    await repository.add(_token('c', kind: DeviceTokenKind.mcp));

    final tokens = await repository.list();

    expect(tokens.map((t) => t.id), ['a', 'b', 'c']);
    expect(tokens[1], revoked);
    expect(tokens[1].isRevoked, isTrue);
    expect(tokens[0].isRevoked, isFalse);
    expect(tokens[2].kind, DeviceTokenKind.mcp);
    expect(tokens[0].createdAt.isUtc, isTrue);
  });

  test('stores each kind', () async {
    for (final kind in DeviceTokenKind.values) {
      await repository.add(_token(kind.name, kind: kind));
    }

    expect(
      (await repository.list()).map((t) => t.kind),
      DeviceTokenKind.values,
    );
  });

  test('revokes a valid token, once', () async {
    await repository.add(_token('a', kind: DeviceTokenKind.runner));
    await repository.add(_token('b'));
    final at = DateTime.utc(2026, 10, 14, 1, 2, 3, 4, 5);

    expect(await repository.revoke('a', at: at), isTrue);
    expect(
      await repository.revoke('a', at: at.add(const Duration(days: 1))),
      isFalse,
    );
    expect(await repository.revoke('nope', at: at), isFalse);

    final tokens = {for (final t in await repository.list()) t.id: t};
    expect(tokens['a']!.revokedAt, at);
    expect(tokens['a']!.kind, DeviceTokenKind.runner);
    expect(tokens['b']!.revokedAt, isNull);
  });

  test('refuses a second token with the same id or hash', () async {
    await repository.add(_token('a'));

    await expectLater(
      repository.add(_token('a')),
      throwsA(isA<SqliteException>()),
    );
    await expectLater(
      repository.add(
        DeviceToken(
          id: 'other',
          name: 'n',
          kind: DeviceTokenKind.cli,
          hash: 'hash-a',
          createdAt: DateTime.utc(2026),
        ),
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(await repository.list(), hasLength(1));
  });

  test('another process sees a token at once', () async {
    final path = '${tempDirectory().path}/xpath.db';
    final reader = SqliteDatabase.open(path);
    addTearDown(reader.close);
    final writer = SqliteDatabase.open(path);
    addTearDown(writer.close);

    expect(await SqliteDeviceTokenRepository(reader).list(), isEmpty);
    await SqliteDeviceTokenRepository(writer).add(_token('late'));

    expect(await SqliteDeviceTokenRepository(reader).list(), [_token('late')]);
  });

  test('works with the token service', () async {
    final service = TokenService(
      tokens: repository,
      clock: ManualClock(DateTime.utc(2026, 10, 13)),
    );

    final issued = await service.issue(
      name: 'Mac mini',
      kind: DeviceTokenKind.cli,
    );

    expect((await service.authenticate(issued.secret))?.id, issued.token.id);
    expect(await service.authenticate('xpt_wrong'), isNull);
  });
}
