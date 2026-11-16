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

  test('keeps the expiry of a web, cli or mcp token, and refuses one on '
      'others', () async {
    final expiresAt = DateTime.utc(2026, 10, 13, 16, 30, 15, 123, 456);
    final expiring = [
      for (final kind in TokenService.clientKinds.union({DeviceTokenKind.web}))
        DeviceToken(
          id: kind.name,
          name: 'n',
          kind: kind,
          hash: 'hash-${kind.name}',
          createdAt: DateTime.utc(2026, 10, 13, 8, 30, 15, 123, 456),
          expiresAt: expiresAt,
          personId: _ownerId,
        ),
    ];
    for (final token in expiring) {
      await repository.add(token);
    }

    expect(await repository.list(), expiring);
    await expectLater(
      repository.add(
        DeviceToken(
          id: 'a',
          name: 'n',
          kind: DeviceTokenKind.app,
          hash: 'h',
          createdAt: DateTime.utc(2026),
          expiresAt: expiresAt,
          personId: _ownerId,
        ),
      ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('finds a token by its hash, revoked or not', () async {
    final revoked = _token('b', revokedAt: DateTime.utc(2026, 10, 14));
    await repository.add(_token('a'));
    await repository.add(revoked);

    expect(await repository.findByHash('hash-a'), _token('a'));
    expect(await repository.findByHash('hash-b'), revoked);
    expect(await repository.findByHash('hash-nope'), isNull);
  });

  test('deletes the tokens of some kinds that ended before a time, and no '
      'other token', () async {
    final before = DateTime.utc(2026, 10, 14);
    DeviceToken ending(
      String id, {
      DeviceTokenKind kind = DeviceTokenKind.web,
      DateTime? expiresAt,
      DateTime? revokedAt,
    }) => DeviceToken(
      id: id,
      name: 'n',
      kind: kind,
      hash: 'hash-$id',
      createdAt: DateTime.utc(2026, 10, 13),
      expiresAt: expiresAt ?? DateTime.utc(2026, 10, 15),
      revokedAt: revokedAt,
      personId: _ownerId,
    );
    await repository.add(
      ending('expired', expiresAt: DateTime.utc(2026, 10, 13)),
    );
    await repository.add(
      ending('revoked', revokedAt: DateTime.utc(2026, 10, 13)),
    );
    await repository.add(
      ending('late', revokedAt: DateTime.utc(2026, 10, 14, 1)),
    );
    await repository.add(ending('valid'));
    await repository.add(
      ending(
        'cli',
        kind: DeviceTokenKind.cli,
        expiresAt: DateTime.utc(2026, 10, 13),
      ),
    );
    await repository.add(
      _token('mcp', kind: DeviceTokenKind.mcp, revokedAt: DateTime.utc(2026)),
    );
    await repository.add(_token('app', revokedAt: DateTime.utc(2026, 10)));

    expect(
      await repository.deleteEnded(
        kinds: {DeviceTokenKind.web},
        before: before,
      ),
      2,
    );
    expect(await repository.deleteEnded(kinds: {}, before: before), 0);
    expect(
      await repository.deleteEnded(
        kinds: TokenService.clientKinds,
        before: before,
      ),
      2,
      reason: 'a revoked token without an expiry ended too',
    );

    expect((await repository.list()).map((t) => t.id), [
      'late',
      'valid',
      'app',
    ]);
  });

  test('renews the expiry of a valid token only', () async {
    final renewed = DateTime.utc(2027, 1, 1, 8, 30, 15, 123, 456);
    final valid = _token('a', kind: DeviceTokenKind.cli);
    final revoked = _token(
      'b',
      kind: DeviceTokenKind.cli,
      revokedAt: DateTime.utc(2026, 10, 14),
    );
    await repository.add(valid);
    await repository.add(revoked);

    await repository.renew('a', expiresAt: renewed);
    await repository.renew('b', expiresAt: renewed);
    await repository.renew('nope', expiresAt: renewed);

    expect(await repository.list(), [valid.renewed(renewed), revoked]);
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
