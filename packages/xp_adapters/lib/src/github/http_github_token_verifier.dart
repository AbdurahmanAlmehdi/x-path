import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// Checks a GitHub token by asking who it belongs to: `GET /user`.
///
/// A `401` is a token that was revoked or expired. A `403` is not a refusal
/// of the token when it is the rate limit. The token is sent to the host of
/// the base URL only (redirects are not followed).
class HttpGitHubTokenVerifier implements CredentialVerifier {
  /// Creates the verifier. The base URL is `https://api.github.com` unless a
  /// test or an Enterprise server says otherwise.
  new({
    http.Client? client,
    Uri? baseUrl,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? Uri.parse('https://api.github.com');

  /// How long GitHub has to answer.
  final Duration timeout;

  final http.Client _client;
  final Uri _baseUrl;

  /// Releases the HTTP client.
  void close() => _client.close();

  @override
  CredentialKind get kind => CredentialKind.github;

  @override
  bool get checksTarget => false;

  @override
  Future<VerificationResult> verify(
    CredentialMaterial material,
    CredentialTarget target,
  ) async {
    final token = (material as TokenMaterial).token;
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client
            .send(
              http.Request('GET', _baseUrl.replace(path: '/user'))
                ..followRedirects = false
                ..headers.addAll({
                  'Accept': 'application/vnd.github+json',
                  'Authorization': 'Bearer $token',
                  'User-Agent': 'xpath',
                  'X-GitHub-Api-Version': '2022-11-28',
                }),
            )
            .timeout(timeout),
      );
    } on TimeoutException {
      return const VerificationResult.unreachable(
        'GitHub did not answer in time.',
        fix: 'Try again later.',
      );
    } on http.ClientException catch (error) {
      return VerificationResult.unreachable(
        'GitHub is not reachable: ${error.message}',
        fix: 'Check the network connection and try again.',
      );
    }
    final status = response.statusCode;
    if (status == 200) {
      return VerificationResult.verified(account: _login(response));
    }
    if (status == 401) {
      return const VerificationResult.rejected(
        'GitHub refused the token.',
        fix:
            'The token was revoked or has expired. Run `gh auth login` and '
            '`xpd secrets import-gh`, or save a new token (a personal access '
            'token with the repo scope).',
      );
    }
    if (status == 403 && response.headers['x-ratelimit-remaining'] != '0') {
      return const VerificationResult.rejected(
        'GitHub forbids this token.',
        fix:
            'The token may lack access, or the organization requires SSO '
            'authorization for it. Authorize the token or create another.',
      );
    }
    return VerificationResult.unreachable(
      'GitHub could not check the token (HTTP $status).',
      fix: 'Try again later.',
    );
  }

  String? _login(http.Response response) {
    final body = response.body;
    final match = RegExp(r'"login"\s*:\s*"([^"]+)"').firstMatch(body);
    return match?[1];
  }
}
