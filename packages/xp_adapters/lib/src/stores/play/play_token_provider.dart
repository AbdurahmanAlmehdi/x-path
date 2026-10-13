import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xp_adapters/src/stores/play/rs256_signer.dart';
import 'package:xp_engine/xp_engine.dart';

/// The OAuth2 scope of the Google Play Developer API.
const playScope = 'https://www.googleapis.com/auth/androidpublisher';

/// The OAuth2 scope of Firebase App Distribution (and most Google Cloud APIs).
const cloudPlatformScope = 'https://www.googleapis.com/auth/cloud-platform';

/// Makes the access tokens for a Google API and keeps one until it is nearly
/// expired. Google Play uses [playScope]; Firebase App Distribution uses
/// [cloudPlatformScope].
///
/// This is the OAuth2 JWT bearer flow (RFC 7523) of a service account: an
/// assertion signed RS256 with the private key, with `iss` the service
/// account email, `scope` the Play scope, `aud` the token endpoint of the key
/// file and `iat`/`exp` at most an hour apart, is posted to that endpoint as
/// `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer`. The answer
/// carries an access token and its lifetime.
class PlayTokenProvider {
  /// Creates a provider for the service account. The assertion lives
  /// [assertionLifetime]; a token is replaced when less than [refreshMargin]
  /// of its life is left.
  new({
    required this._account,
    required this._clock,
    this.scope = playScope,
    http.Client? client,
    this.assertionLifetime = const Duration(minutes: 30),
    this.refreshMargin = const Duration(minutes: 2),
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client(),
       assert(
         assertionLifetime <= maxAssertionLifetime,
         'Google refuses an assertion that lives longer than an hour.',
       );

  /// The scope the assertion asks for.
  final String scope;

  /// The longest Google accepts: one hour.
  static const maxAssertionLifetime = Duration(hours: 1);

  /// How long the signed assertion lives.
  final Duration assertionLifetime;

  /// How close to its end a token is replaced.
  final Duration refreshMargin;

  /// How long the token endpoint has to answer.
  final Duration timeout;

  final PlayServiceAccount _account;
  final Clock _clock;
  final http.Client _client;
  late final _signer = Rs256Signer.fromPem(_account.privateKey);
  ({String token, DateTime expiresAt})? _cached;
  Future<String>? _pending;

  /// An access token that is valid now and for at least [refreshMargin].
  ///
  /// Calls that overlap share one request to the token endpoint. Throws a
  /// [PlayAuthException] if Google refuses the service account or the key is
  /// unusable, and a [PlayServerException] if the endpoint cannot be reached.
  Future<String> token() {
    final cached = _cached;
    if (cached != null &&
        _clock.now().isBefore(cached.expiresAt.subtract(refreshMargin))) {
      return Future.value(cached.token);
    }
    return _pending ??= _fetch().whenComplete(() => _pending = null);
  }

  /// Forgets the token, so that the next [token] asks for a new one. For a
  /// token that Google rejected before it expired.
  void invalidate() => _cached = null;

  Future<String> _fetch() async {
    final assertion = _assertion();
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client
            .send(
              http.Request('POST', Uri.parse(_account.tokenUri))
                ..followRedirects = false
                ..headers['Accept'] = 'application/json'
                ..bodyFields = {
                  'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                  'assertion': assertion,
                },
            )
            .timeout(timeout),
      );
    } on TimeoutException {
      throw const PlayServerException(
        0,
        'The Google token endpoint did not answer in time.',
      );
    } on http.ClientException catch (error) {
      throw PlayServerException(
        0,
        'The Google token endpoint is not reachable: $error',
      );
    }
    final Map<String, dynamic> json;
    try {
      json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on Object {
      throw PlayServerException(
        response.statusCode,
        'The Google token endpoint answered with something that is not a '
        'JSON object.',
      );
    }
    final token = json['access_token'];
    if (response.statusCode == 200 && token is String && token.isNotEmpty) {
      final seconds = json['expires_in'];
      _cached = (
        token: token,
        expiresAt: _clock.now().add(
          Duration(seconds: seconds is int ? seconds : 3600),
        ),
      );
      return token;
    }
    final error = json['error'];
    final description = json['error_description'];
    final message =
        'Google refused the service account'
        '${description is String ? ': $description' : ''}.';
    if (response.statusCode >= 500) {
      throw PlayServerException(response.statusCode, message);
    }
    throw PlayAuthException(message, reason: error is String ? error : null);
  }

  String _assertion() {
    final issuedAt = _clock.now().millisecondsSinceEpoch ~/ 1000;
    final header = {
      'alg': 'RS256',
      'typ': 'JWT',
      'kid': ?_account.privateKeyId,
    };
    final claims = {
      'iss': _account.clientEmail,
      'scope': scope,
      'aud': _account.tokenUri,
      'iat': issuedAt,
      'exp': issuedAt + assertionLifetime.inSeconds,
    };
    final signingInput = '${_encode(header)}.${_encode(claims)}';
    final List<int> signature;
    try {
      signature = _signer.sign(utf8.encode(signingInput));
    } on FormatException catch (error) {
      throw PlayAuthException(
        'The service account private key cannot be used: ${error.message}',
      );
    }
    return '$signingInput.${_base64Url(signature)}';
  }

  static String _encode(Map<String, Object> json) =>
      _base64Url(utf8.encode(jsonEncode(json)));

  static String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  /// Releases the HTTP client.
  void close() => _client.close();
}
