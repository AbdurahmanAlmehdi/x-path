import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/access/access_policy.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/people/person_repository.dart';
import 'package:xp_engine/src/repositories/device_token_repository.dart';
import 'package:xp_engine/src/tokens/device_token.dart';

/// The hex SHA-256 of a token [secret]: what the engine stores.
///
/// A plain hash is enough because secrets are 256 random bits, so there is
/// nothing to brute-force.
String hashToken(String secret) =>
    sha256.convert(utf8.encode(secret)).toString();

/// A freshly issued token. [secret] exists only here: show it once.
class IssuedToken extends Equatable {
  /// Creates the result of issuing [token].
  const new({required this.token, required this.secret});

  /// The stored record.
  final DeviceToken token;

  /// The bearer secret, `xpt_` followed by 43 URL-safe characters.
  final String secret;

  @override
  List<Object?> get props => [token, secret];
}

/// There is no valid token [id] that the asker may see.
class TokenNotFoundException implements Exception {
  /// Creates the exception for [id].
  const new(this.id);

  /// The id that was asked for.
  final String id;

  /// What went wrong, for the owner.
  String get message => 'There is no token $id.';

  @override
  String toString() => 'TokenNotFoundException: $message';
}

/// Issues device tokens and tells which token a bearer secret belongs to.
///
/// Every token but a runner's belongs to a person (ADR 0017), whom
/// [authenticate] reads with the token, so a change of role applies to the
/// next request and a removed person's tokens stop working.
class TokenService {
  /// Creates a service over a token repository and the people the tokens
  /// belong to.
  ///
  /// `random` is for tests; it must be cryptographically secure otherwise.
  new({
    required this._tokens,
    required this._people,
    required this._clock,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// Marks a string as an XPath token, so that secret scanners can find it.
  static const secretPrefix = 'xpt_';

  /// How long a browser session's token works (D11): there is no sliding
  /// renewal, so a browser signs in again after it.
  static const webSessionLifetime = Duration(hours: 8);

  final DeviceTokenRepository _tokens;
  final PersonRepository _people;
  final Clock _clock;
  final Random _random;
  final _revocations = StreamController<String>.broadcast(sync: true);

  /// The id of every token revoked through this service, as it is revoked:
  /// the sockets it opened close (D12).
  Stream<String> get revocations => _revocations.stream;

  /// Creates and stores a token called [name] for [kind], which belongs to
  /// the person [personId]. A runner token belongs to no person. Without a
  /// [personId], any other token belongs to the admin who has been one the
  /// longest: what `xpd token create` makes.
  ///
  /// Throws an [ArgumentError] if [name] is blank, if a runner token is
  /// given a person, or if there is no such active person.
  Future<IssuedToken> issue({
    required String name,
    required DeviceTokenKind kind,
    String? personId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name', 'is blank');
    final runner = kind == DeviceTokenKind.runner;
    if (runner && personId != null) {
      throw ArgumentError.value(personId, 'personId', 'a runner has no person');
    }
    final person = runner ? null : await _ownerOf(personId);
    return await _store(name: trimmed, kind: kind, person: person);
  }

  /// Creates and stores the token of a browser that signed in as the person
  /// [personId] (ADR 0018): a `web` token that expires after
  /// [webSessionLifetime].
  ///
  /// Throws an [ArgumentError] if there is no such active person.
  Future<IssuedToken> issueWeb({required String personId}) async {
    final person = await _ownerOf(personId);
    return await _store(
      name: 'Browser',
      kind: DeviceTokenKind.web,
      person: person,
      expiresAt: _clock.now().add(webSessionLifetime),
    );
  }

  Future<IssuedToken> _store({
    required String name,
    required DeviceTokenKind kind,
    required Person? person,
    DateTime? expiresAt,
  }) async {
    final secret = secretPrefix + _base64Url(_bytes(32));
    final token = DeviceToken(
      id: 'tok_${_hex(_bytes(8))}',
      name: name,
      kind: kind,
      hash: hashToken(secret),
      createdAt: _clock.now(),
      expiresAt: expiresAt,
      personId: person?.id,
      person: person,
    );
    await _tokens.add(token);
    return IssuedToken(token: token, secret: secret);
  }

  Future<Person> _ownerOf(String? personId) async {
    final active = (await _people.list()).where((p) => !p.isRemoved);
    final owner = personId == null
        ? active.where((p) => p.role == PersonRole.admin).firstOrNull
        : active.where((p) => p.id == personId).firstOrNull;
    return owner ??
        (throw ArgumentError.value(
          personId,
          'personId',
          personId == null ? 'there is no admin' : 'is no active person',
        ));
  }

  /// The valid token that [secret] belongs to, with its person read, or
  /// `null`. A token that expired, or whose person was removed, is not
  /// valid.
  ///
  /// Every stored hash is compared, in constant time, so the time taken does
  /// not reveal how much of a guess was right.
  Future<DeviceToken?> authenticate(String? secret) async {
    if (secret == null || !secret.startsWith(secretPrefix)) return null;
    final hash = hashToken(secret);
    final now = _clock.now();
    DeviceToken? match;
    for (final token in await _tokens.list()) {
      final same = _constantTimeEquals(token.hash, hash);
      if (same && token.isValidAt(now)) match = token;
    }
    final personId = match?.personId;
    if (match == null || personId == null) return match;
    final person = await _people.get(personId);
    if (person == null || person.isRemoved) return null;
    return match.withPerson(person);
  }

  /// The valid tokens [asker] may see, in the order they were stored (D17):
  /// those of its own person, or every person's for a token that may
  /// [Permission.administer]. Runner tokens are never among them: a runner's
  /// token is revoked with the runner.
  Future<List<DeviceToken>> listFor(DeviceToken asker) async {
    final everyone = AccessPolicy.allows(asker, Permission.administer);
    final now = _clock.now();
    return [
      for (final token in await _tokens.list())
        if (token.isValidAt(now) &&
            token.personId != null &&
            (everyone || token.personId == asker.personId))
          token,
    ];
  }

  /// Revokes the token [id] for [asker], who may revoke the tokens it may
  /// see ([listFor]).
  ///
  /// Throws a [TokenNotFoundException] for a token [asker] may not see, or
  /// one that is not valid.
  Future<void> revokeFor(DeviceToken asker, String id) async {
    final visible = await listFor(asker);
    if (!visible.any((token) => token.id == id)) {
      throw TokenNotFoundException(id);
    }
    await revoke(id);
  }

  /// Revokes the token [id]: it no longer authenticates, and its sockets
  /// close ([revocations]). Returns whether it was valid until now.
  Future<bool> revoke(String id) async {
    final revoked = await _tokens.revoke(id, at: _clock.now());
    if (revoked) _revocations.add(id);
    return revoked;
  }

  /// Revokes every valid token of the person [personId], and closes their
  /// sockets ([revocations]). Returns how many there were.
  Future<int> revokeAllOf(String personId) async {
    final owned = [
      for (final token in await _tokens.list())
        if (token.personId == personId && !token.isRevoked) token.id,
    ];
    final count = await _tokens.revokeOwnedBy(personId, at: _clock.now());
    owned.forEach(_revocations.add);
    return count;
  }

  List<int> _bytes(int length) =>
      List.generate(length, (_) => _random.nextInt(256));

  String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }
}
