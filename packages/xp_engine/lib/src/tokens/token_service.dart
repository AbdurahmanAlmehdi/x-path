import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/tokens/device_token.dart';
import 'package:xp_engine/src/tokens/device_token_repository.dart';

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

/// Issues device tokens and tells which token a bearer secret belongs to.
class TokenService {
  /// Creates a service over a token repository.
  ///
  /// `random` is for tests; it must be cryptographically secure otherwise.
  new({required this._tokens, required this._clock, Random? random})
    : _random = random ?? Random.secure();

  /// Marks a string as an XPath token, so that secret scanners can find it.
  static const secretPrefix = 'xpt_';

  final DeviceTokenRepository _tokens;
  final Clock _clock;
  final Random _random;

  /// Creates and stores a token called [name] for [kind].
  ///
  /// Throws an [ArgumentError] if [name] is blank.
  Future<IssuedToken> issue({
    required String name,
    required DeviceTokenKind kind,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name', 'is blank');
    final secret = secretPrefix + _base64Url(_bytes(32));
    final token = DeviceToken(
      id: 'tok_${_hex(_bytes(8))}',
      name: trimmed,
      kind: kind,
      hash: hashToken(secret),
      createdAt: _clock.now(),
    );
    await _tokens.add(token);
    return IssuedToken(token: token, secret: secret);
  }

  /// The valid token that [secret] belongs to, or `null`.
  ///
  /// Every stored hash is compared, in constant time, so the time taken does
  /// not reveal how much of a guess was right.
  Future<DeviceToken?> authenticate(String? secret) async {
    if (secret == null || !secret.startsWith(secretPrefix)) return null;
    final hash = hashToken(secret);
    DeviceToken? match;
    for (final token in await _tokens.list()) {
      final same = _constantTimeEquals(token.hash, hash);
      if (same && !token.isRevoked) match = token;
    }
    return match;
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
