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

/// The token may not do this with tokens (D17): make one of that kind, or
/// list and revoke tokens. The message says who may.
class TokenForbiddenException implements Exception {
  /// Creates the exception with a [message].
  const new(this.message);

  /// What went wrong, for the owner.
  final String message;

  @override
  String toString() => 'TokenForbiddenException: $message';
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

  /// How long a browser session's token is kept once it expired or was
  /// revoked, before housekeeping deletes it ([purgeEndedTokens]).
  static const endedWebTokenGrace = Duration(days: 1);

  /// How long a token of `xp` or `xp mcp` works after it was last used
  /// (ADR 0019): each use moves its expiry to this long after, so a client
  /// in use keeps working and a forgotten one stops.
  static const clientTokenLifetime = Duration(days: 90);

  /// How far a use must move a client token's expiry before it is written:
  /// a token is written at most about once a day, not on every request.
  static const clientTokenRenewalStep = Duration(days: 1);

  /// How long a token of `xp` or `xp mcp` is kept once it expired or was
  /// revoked, before housekeeping deletes it ([purgeEndedTokens]): until
  /// then, a client that uses it hears that it expired.
  static const endedClientTokenGrace = Duration(days: 30);

  /// The kinds of the tokens of `xp` and `xp mcp`, which expire when they
  /// are not used for [clientTokenLifetime] (ADR 0019).
  static const Set<DeviceTokenKind> clientKinds = {
    DeviceTokenKind.cli,
    DeviceTokenKind.mcp,
  };

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
  /// longest: what `xpd token create` makes. A token of [clientKinds]
  /// expires [clientTokenLifetime] from now unless it is used.
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
    final hasPerson = AccessPolicy.hasPerson(kind);
    if (!hasPerson && personId != null) {
      throw ArgumentError.value(personId, 'personId', 'a runner has no person');
    }
    final person = hasPerson ? await _ownerOf(personId) : null;
    return await _store(
      name: trimmed,
      kind: kind,
      person: person,
      expiresAt: clientKinds.contains(kind)
          ? _clock.now().add(clientTokenLifetime)
          : null,
    );
  }

  /// Creates and stores a [kind] token called [name] for the person of
  /// [creator], who makes it from the app or the web dashboard (D17).
  ///
  /// Throws a [TokenForbiddenException] unless [creator] may make a [kind]
  /// token ([AccessPolicy.mayCreateToken]), and an [ArgumentError] as
  /// [issue] does.
  Future<IssuedToken> issueFor(
    DeviceToken creator, {
    required String name,
    required DeviceTokenKind kind,
  }) async {
    if (!AccessPolicy.mayCreateToken(creator, kind)) {
      throw TokenForbiddenException(
        'Only the app and the web dashboard make tokens, and only cli and '
        'mcp ones: ${AccessPolicy.aTokenOf(creator.kind)} may not make '
        '${AccessPolicy.aTokenOf(kind).toLowerCase()}.',
      );
    }
    return await issue(name: name, kind: kind, personId: creator.personId);
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
  /// valid. A token of [clientKinds] is renewed: it then expires
  /// [clientTokenLifetime] from now.
  ///
  /// The token is looked up by the SHA-256 of [secret], an indexed column:
  /// a lookup's timing could at most tell how much of a hash a guess shares
  /// with a stored one, which says nothing about a secret of 256 random
  /// bits.
  Future<DeviceToken?> authenticate(String? secret) async {
    final now = _clock.now();
    final found = await _find(secret);
    final match = found != null && found.isValidAt(now) ? found : null;
    final personId = match?.personId;
    if (match == null || personId == null) return match;
    final person = await _people.get(personId);
    if (person == null || person.isRemoved) return null;
    return (await _renew(match, now)).withPerson(person);
  }

  /// When the token that [secret] belongs to expired, or `null` unless it is
  /// one that expired and was not revoked: it lets a refusal say that the
  /// token expired ([ErrorReason.tokenExpired]), which is no secret to the
  /// one who holds [secret].
  Future<DateTime?> expiredAt(String? secret) async {
    final found = await _find(secret);
    return found != null && !found.isRevoked && found.isExpiredAt(_clock.now())
        ? found.expiresAt
        : null;
  }

  Future<DeviceToken?> _find(String? secret) async =>
      secret == null || !secret.startsWith(secretPrefix)
      ? null
      : await _tokens.findByHash(hashToken(secret));

  /// [token], used at [now]: a token of [clientKinds] then expires
  /// [clientTokenLifetime] from [now], written once that moves its expiry by
  /// [clientTokenRenewalStep] or more.
  Future<DeviceToken> _renew(DeviceToken token, DateTime now) async {
    if (!clientKinds.contains(token.kind)) return token;
    final expiresAt = now.add(clientTokenLifetime);
    final current = token.expiresAt;
    if (current != null &&
        expiresAt.difference(current) < clientTokenRenewalStep) {
      return token;
    }
    await _tokens.renew(token.id, expiresAt: expiresAt);
    return token.renewed(expiresAt);
  }

  /// The valid tokens [asker] may see, in the order they were stored (D17):
  /// those of its own person, or every person's for a token that may
  /// [Permission.administer]. Runner tokens are never among them: a runner's
  /// token is revoked with the runner.
  ///
  /// Throws a [TokenForbiddenException] unless [asker] may manage tokens
  /// ([AccessPolicy.mayManageTokens]): an agent's `mcp` token may not.
  Future<List<DeviceToken>> listFor(DeviceToken asker) async {
    if (!AccessPolicy.mayManageTokens(asker)) {
      throw TokenForbiddenException(
        '${AccessPolicy.aTokenOf(asker.kind)} cannot list or revoke tokens: '
        'only the app, `xp` or the web dashboard do.',
      );
    }
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
  /// one that is not valid, and a [TokenForbiddenException] as [listFor]
  /// does.
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
    if (revoked) _announce(id);
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
    owned.forEach(_announce);
    return count;
  }

  /// Deletes the tokens that will never work again: the `web` tokens that
  /// expired or were revoked more than [endedWebTokenGrace] ago (every
  /// browser sign-in adds one), and those of [clientKinds] more than
  /// [endedClientTokenGrace] ago. Returns how many went. Housekeeping runs
  /// it daily.
  Future<int> purgeEndedTokens() async {
    final now = _clock.now();
    final web = await _tokens.deleteEnded(
      kinds: const {DeviceTokenKind.web},
      before: now.subtract(endedWebTokenGrace),
    );
    final clients = await _tokens.deleteEnded(
      kinds: clientKinds,
      before: now.subtract(endedClientTokenGrace),
    );
    return web + clients;
  }

  /// Stops telling [revocations]: the engine is shutting down.
  Future<void> close() => _revocations.close();

  void _announce(String id) {
    if (!_revocations.isClosed) _revocations.add(id);
  }

  List<int> _bytes(int length) =>
      List.generate(length, (_) => _random.nextInt(256));

  String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
