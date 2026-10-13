import 'dart:convert';

import 'package:xp_adapters/src/stores/apple/es256_signer.dart';
import 'package:xp_engine/xp_engine.dart';

/// Makes the bearer tokens for the App Store Connect REST API and keeps one
/// until it is nearly expired.
///
/// A token is a JWT signed ES256 with the `.p8` key. The header is `alg`, `kid`
/// and `typ`; the claims are `iat`, `exp` (at most 20 minutes later) and
/// `aud: appstoreconnect-v1`, plus `iss` (the issuer id) for a team key or
/// `sub: user` for an individual key (Apple's "Generating tokens for API
/// requests").
class AscTokenProvider {
  /// Creates a provider for the API key. Tokens live [lifetime] and are
  /// replaced when less than [refreshMargin] of that is left.
  new({
    required this._key,
    required this._clock,
    this.lifetime = const Duration(minutes: 15),
    this.refreshMargin = const Duration(minutes: 2),
  }) : assert(
         lifetime <= maxLifetime,
         'Apple refuses a token that lives longer than 20 minutes.',
       ),
       assert(refreshMargin < lifetime, 'The margin must be shorter.');

  /// The longest Apple accepts: 20 minutes.
  static const maxLifetime = Duration(minutes: 20);

  /// The `aud` claim.
  static const audience = 'appstoreconnect-v1';

  /// How long a token lives.
  final Duration lifetime;

  /// How close to its end a token is replaced.
  final Duration refreshMargin;

  final AscKey _key;
  final Clock _clock;
  late final _signer = Es256Signer.fromPem(_key.privateKey);
  ({String token, DateTime expiresAt})? _cached;

  /// A token that is valid now and for at least [refreshMargin].
  ///
  /// Throws a [FormatException] if the key is not a usable `.p8`.
  String token() {
    final now = _clock.now();
    final cached = _cached;
    if (cached != null &&
        now.isBefore(cached.expiresAt.subtract(refreshMargin))) {
      return cached.token;
    }
    final issuedAt = now.millisecondsSinceEpoch ~/ 1000;
    final expires = issuedAt + lifetime.inSeconds;
    final header = {'alg': 'ES256', 'kid': _key.keyId, 'typ': 'JWT'};
    final claims = {
      if (_key.kind == AscKeyKind.team) 'iss': _key.issuerId else 'sub': 'user',
      'iat': issuedAt,
      'exp': expires,
      'aud': audience,
    };
    final signingInput = '${_encode(header)}.${_encode(claims)}';
    final signature = _signer.sign(utf8.encode(signingInput));
    final token = '$signingInput.${_base64Url(signature)}';
    _cached = (
      token: token,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expires * 1000,
        isUtc: true,
      ),
    );
    return token;
  }

  static String _encode(Map<String, Object> json) =>
      _base64Url(utf8.encode(jsonEncode(json)));

  static String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}
