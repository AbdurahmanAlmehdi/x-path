import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xp_engine/xp_engine.dart';

/// The iTunes lookup over HTTP: `/lookup` on `https://itunes.apple.com`, with
/// the parameters `bundleId` and `country`.
///
/// The storefront is the app's own (`store_country` of the profile), because an
/// app can be on sale in one storefront and not in another. Apple's CDN keeps
/// an answer for hours, so every call carries a changing `_` parameter that
/// makes it a new URL. The answer is "live somewhere", not precise.
class HttpItunesLookup implements ItunesLookup {
  /// Creates a lookup. [client], [baseUrl] and the clock are for tests.
  new({
    http.Client? client,
    Uri? baseUrl,
    this._clock = const SystemClock(),
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? Uri.parse('https://itunes.apple.com');

  /// How long the lookup has to answer.
  final Duration timeout;

  final http.Client _client;
  final Uri _baseUrl;
  final Clock _clock;

  /// Releases the HTTP client.
  void close() => _client.close();

  @override
  Future<ItunesApp?> lookup({
    required String bundleId,
    required String country,
  }) async {
    final url = _baseUrl.replace(
      path: '/lookup',
      queryParameters: {
        'bundleId': bundleId,
        'country': country.toLowerCase(),
        '_': '${_clock.now().millisecondsSinceEpoch}',
      },
    );
    final http.Response response;
    try {
      response = await _client.get(url).timeout(timeout);
    } on TimeoutException {
      throw const ItunesLookupException('The iTunes lookup did not answer.');
    } on http.ClientException catch (error) {
      throw ItunesLookupException('The iTunes lookup is not reachable: $error');
    }
    if (response.statusCode != 200) {
      throw ItunesLookupException(
        'The iTunes lookup answered HTTP ${response.statusCode}.',
      );
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const ItunesLookupException(
        'The iTunes lookup did not answer with JSON.',
      );
    }
    final results = json is Map<String, dynamic> ? json['results'] : null;
    if (results is! List<dynamic>) {
      throw const ItunesLookupException(
        'The iTunes lookup answered without results.',
      );
    }
    for (final result in results) {
      if (result is Map<String, dynamic> && result['bundleId'] == bundleId) {
        return _app(result);
      }
    }
    return null;
  }

  ItunesApp _app(Map<String, dynamic> result) {
    final version = result['version'];
    final trackId = result['trackId'];
    if (version is! String || trackId is! int) {
      throw const ItunesLookupException(
        'The iTunes lookup answered without a version or an id.',
      );
    }
    final released = result['currentVersionReleaseDate'];
    return ItunesApp(
      bundleId: result['bundleId'] as String,
      trackId: '$trackId',
      version: version,
      currentVersionReleaseDate: released is String
          ? DateTime.tryParse(released)?.toUtc()
          : null,
    );
  }
}
