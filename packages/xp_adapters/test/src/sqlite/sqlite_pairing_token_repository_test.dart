import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

final _created = DateTime.utc(2026, 10, 14, 9, 30, 15, 123, 456);

PairingTokenRecord _token(String id, {DateTime? usedAt}) => PairingTokenRecord(
  id: id,
  hash: 'hash-$id',
  name: 'runner $id',
  createdBy: 'tok_owner',
  createdAt: _created,
  expiresAt: _created.add(const Duration(minutes: 15)),
  usedAt: usedAt,
);

void main() {
  late SqliteDatabase database;
  late SqlitePairingTokenRepository repository;

  setUp(() {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    repository = SqlitePairingTokenRepository(database);
  });

  test('finds a token by the hash of its secret, with every field', () async {
    await repository.add(_token('a'));
    await repository.add(_token('b', usedAt: _created));

    expect(await repository.findByHash('hash-a'), _token('a'));
    expect(
      await repository.findByHash('hash-b'),
      _token('b', usedAt: _created),
    );
    expect(await repository.findByHash('hash-c'), isNull);
  });

  test('stores no secret', () async {
    await repository.add(_token('a'));

    final columns = database.connection
        .select('SELECT * FROM pairing_token')
        .single
        .keys;
    expect(columns, [
      'id',
      'hash',
      'name',
      'created_by',
      'created_at',
      'expires_at',
      'used_at',
    ]);
  });

  test(
    'consume works for the first caller, while the token is valid',
    () async {
      await repository.add(_token('a'));
      await repository.add(_token('late'));
      final now = _created.add(const Duration(minutes: 1));

      expect(await repository.consume('a', at: now), isTrue);
      expect(await repository.consume('a', at: now), isFalse);
      expect((await repository.findByHash('hash-a'))!.usedAt, now);
      expect(await repository.consume('nope', at: now), isFalse);
      expect(
        await repository.consume(
          'late',
          at: _created.add(const Duration(minutes: 15)),
        ),
        isFalse,
      );
      expect(
        await repository.consume(
          'late',
          at: _created.add(const Duration(minutes: 14, seconds: 59)),
        ),
        isTrue,
      );
    },
  );

  test('prune forgets the expired and the used', () async {
    await repository.add(_token('expired'));
    await repository.add(_token('used', usedAt: _created));
    final later = _created.add(const Duration(hours: 1));
    await repository.add(
      PairingTokenRecord(
        id: 'fresh',
        hash: 'hash-fresh',
        name: 'fresh',
        createdBy: 'tok_owner',
        createdAt: later,
        expiresAt: later.add(const Duration(minutes: 15)),
      ),
    );

    await repository.prune(before: later);

    expect(await repository.findByHash('hash-expired'), isNull);
    expect(await repository.findByHash('hash-used'), isNull);
    expect(await repository.findByHash('hash-fresh'), isNotNull);
  });

  test('refuses a second token with the same hash', () async {
    await repository.add(_token('a'));

    expect(
      () => repository.add(
        PairingTokenRecord(
          id: 'other',
          hash: 'hash-a',
          name: 'x',
          createdBy: 'tok_owner',
          createdAt: _created,
          expiresAt: _created,
        ),
      ),
      throwsA(anything),
    );
  });
}
