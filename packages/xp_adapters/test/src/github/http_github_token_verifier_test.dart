import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late List<http.BaseRequest> seen;

  HttpGitHubTokenVerifier verifier(
    FutureOr<http.Response> Function(http.BaseRequest request) answer, {
    Duration timeout = const Duration(seconds: 30),
  }) => HttpGitHubTokenVerifier(
    baseUrl: Uri.parse('https://github.test/api'),
    timeout: timeout,
    client: MockClient.streaming((request, body) async {
      seen.add(request);
      final response = await answer(request);
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
      );
    }),
  );

  Future<VerificationResult> verify(HttpGitHubTokenVerifier verifier) =>
      verifier.verify(
        const TokenMaterial(CredentialKind.github, 'ghp_secret'),
        const CredentialTarget(),
      );

  setUp(() => seen = []);

  test('is the verifier of GitHub tokens', () {
    expect(verifier((_) => http.Response('', 200)).kind, CredentialKind.github);
  });

  test(
    'accepts a token that can read its user, and learns the login',
    () async {
      final result = await verify(
        verifier((_) => http.Response(jsonEncode({'login': 'octocat'}), 200)),
      );

      expect(result, const VerificationResult.verified(account: 'octocat'));
      final request = seen.single;
      expect(request.method, 'GET');
      expect(request.url, Uri.parse('https://github.test/user'));
      expect(request.headers['Authorization'], 'Bearer ghp_secret');
      expect(request.headers['Accept'], 'application/vnd.github+json');
    },
  );

  test('accepts a user without a login', () async {
    final result = await verify(verifier((_) => http.Response('{}', 200)));

    expect(result, const VerificationResult.verified());
  });

  test('rejects a revoked token (401) with a fix', () async {
    final result = await verify(
      verifier((_) => http.Response('{"message": "Bad credentials"}', 401)),
    );

    expect(result.status, CredentialStatus.rejected);
    expect(result.fix, contains('xpd secrets import-gh'));
  });

  test('rejects a token that is forbidden', () async {
    final result = await verify(verifier((_) => http.Response('{}', 403)));

    expect(result.status, CredentialStatus.rejected);
    expect(result.message, contains('forbids'));
  });

  test('cannot tell when GitHub is rate limiting or down', () async {
    final limited = await verify(
      verifier(
        (_) =>
            http.Response('{}', 403, headers: {'x-ratelimit-remaining': '0'}),
      ),
    );
    final down = await verify(verifier((_) => http.Response('', 503)));

    expect(limited.status, CredentialStatus.unreachable);
    expect(down.status, CredentialStatus.unreachable);
    expect(down.message, contains('HTTP 503'));
  });

  test('cannot tell when GitHub is out of reach', () async {
    final result = await verify(
      HttpGitHubTokenVerifier(
        client: MockClient((_) => throw http.ClientException('refused')),
      ),
    );

    expect(result.status, CredentialStatus.unreachable);
    expect(result.message, contains('refused'));

    final slow = await verify(
      verifier(
        (_) => Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 10),
      ),
    );
    expect(slow.message, contains('did not answer in time'));
  });

  test('does not follow redirects, so the token stays here', () async {
    await verify(verifier((_) => http.Response('', 301)));

    expect(seen.single.followRedirects, isFalse);
  });

  test('asks the real GitHub by default', () async {
    final real = HttpGitHubTokenVerifier(
      client: MockClient((request) async {
        seen.add(request);
        return http.Response('{}', 200);
      }),
    );

    await verify(real);
    real.close();

    expect(seen.single.url.host, 'api.github.com');
  });
}
