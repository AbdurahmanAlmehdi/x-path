import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/schema_dump.dart';

/// The id of `Owner`, whom migration v23 makes in every database.
late String _ownerId;

DeviceToken _token(String id, {DeviceTokenKind? kind, DateTime? revokedAt}) {
  final tokenKind = kind ?? DeviceTokenKind.app;
  return DeviceToken(
    id: id,
    name: 'device $id',
    kind: tokenKind,
    hash: 'hash-$id',
    createdAt: DateTime.utc(2026, 10, 13, 8, 30, 15, 123, 456),
    revokedAt: revokedAt,
    personId: tokenKind == DeviceTokenKind.runner ? null : _ownerId,
  );
}

Future<String> _ownerOf(SqliteDatabase database) async =>
    (await SqlitePersonRepository(database).list()).single.id;

void main() {
  late SqliteDatabase database;
  late SqliteDeviceTokenRepository repository;

  setUp(() async {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    repository = SqliteDeviceTokenRepository(database);
    _ownerId = await _ownerOf(database);
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
    expect(tokens[0].personId, _ownerId);
    expect(tokens[1].personId, isNull);
  });

  test('refuses a token without a person unless it is a runner', () async {
    await expectLater(
      repository.add(
        DeviceToken(
          id: 'a',
          name: 'n',
          kind: DeviceTokenKind.cli,
          hash: 'h',
          createdAt: DateTime.utc(2026),
        ),
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(await repository.list(), isEmpty);
  });

  test('keeps the expiry of a web token, and refuses one on others', () async {
    final expiresAt = DateTime.utc(2026, 10, 13, 16, 30, 15, 123, 456);
    final web = DeviceToken(
      id: 'w',
      name: 'Browser',
      kind: DeviceTokenKind.web,
      hash: 'hash-w',
      createdAt: DateTime.utc(2026, 10, 13, 8, 30, 15, 123, 456),
      expiresAt: expiresAt,
      personId: _ownerId,
    );
    await repository.add(web);

    expect(await repository.list(), [web]);
    await expectLater(
      repository.add(
        DeviceToken(
          id: 'a',
          name: 'n',
          kind: DeviceTokenKind.cli,
          hash: 'h',
          createdAt: DateTime.utc(2026),
          expiresAt: expiresAt,
          personId: _ownerId,
        ),
      ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('revokes every valid token of a person, and no other', () async {
    final at = DateTime.utc(2026, 10, 14);
    final earlier = DateTime.utc(2026, 10);
    await repository.add(_token('a'));
    await repository.add(_token('b', kind: DeviceTokenKind.mcp));
    await repository.add(_token('c', revokedAt: earlier));
    await repository.add(_token('d', kind: DeviceTokenKind.runner));

    expect(await repository.revokeOwnedBy(_ownerId, at: at), 2);
    expect(await repository.revokeOwnedBy(_ownerId, at: at), 0);

    final tokens = {for (final t in await repository.list()) t.id: t};
    expect(tokens['a']!.revokedAt, at);
    expect(tokens['b']!.revokedAt, at);
    expect(tokens['c']!.revokedAt, earlier);
    expect(tokens['d']!.revokedAt, isNull);
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
    _ownerId = await _ownerOf(writer);

    expect(await SqliteDeviceTokenRepository(reader).list(), isEmpty);
    await SqliteDeviceTokenRepository(writer).add(_token('late'));

    expect(await SqliteDeviceTokenRepository(reader).list(), [_token('late')]);
  });

  test('works with the token service', () async {
    final service = TokenService(
      tokens: repository,
      people: SqlitePersonRepository(database),
      clock: ManualClock(DateTime.utc(2026, 10, 13)),
    );

    final issued = await service.issue(
      name: 'Mac mini',
      kind: DeviceTokenKind.cli,
    );
    final found = await service.authenticate(issued.secret);

    expect(found?.id, issued.token.id);
    expect(found?.person?.name, 'Owner');
    expect(found?.role, PersonRole.admin);
    expect(await service.authenticate('xpt_wrong'), isNull);
  });
}
