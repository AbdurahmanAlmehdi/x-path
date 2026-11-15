import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/xpd.dart';

import '../../../helpers/test_engine.dart';

/// A connection to [localPort] from [remoteAddress].
class _Connection implements HttpConnectionInfo {
  const new(this.remoteAddress, this.localPort);

  @override
  final InternetAddress remoteAddress;

  @override
  final int localPort;

  @override
  int get remotePort => 50000;
}

void main() {
  late TestEngine engine;

  setUp(() async => engine = await TestEngine.start());
  tearDown(() => engine.close());

  Future<RawResponse> signIn(
    String code, {
    Map<String, String>? headers,
    bool root = false,
    String token = '',
  }) => engine.request(
    '/session',
    method: 'POST',
    token: token,
    root: root,
    headers: headers ?? {'origin': engine.loopbackOrigin},
    body: jsonEncode({'code': code}),
  );

  Future<String> codeFor([String? personId]) async =>
      (await engine.signIn.issue(personId ?? testOwner.id)).code;

  group('POST /session', () {
    test('on loopback, sets xp_session_<port> for 8 hours and answers who '
        'signed in', () async {
      final response = await signIn(await codeFor());

      expect(response.statusCode, 200, reason: response.body);
      expect(response.headers['cache-control'], 'no-store');
      final cookie = response.headers['set-cookie']!;
      expect(
        cookie,
        matches(
          RegExp(
            '^xp_session_${engine.uri.port}=xpt_[A-Za-z0-9_-]{43}; HttpOnly; '
            r'SameSite=Strict; Path=/; Max-Age=28800$',
          ),
        ),
      );
      final me = Me.fromJson(response.json);
      expect(me.person, testOwner);
      expect(me.token.kind, DeviceTokenKind.web);
      expect(me.permissions, Permission.values);
      final secret = cookie.split(';').first.split('=').last;
      expect(response.body, isNot(contains(secret)));
    });

    test(
      'through the HTTPS public URL, sets __Host-xp_session with Secure',
      () async {
        await engine.publicUrl.set(
          'https://xpath.example.com',
          by: testOwnerToken,
        );

        final response = await signIn(
          await codeFor(),
          headers: {'origin': 'https://xpath.example.com'},
        );

        expect(response.statusCode, 200, reason: response.body);
        expect(
          response.headers['set-cookie'],
          matches(
            RegExp(
              '^__Host-xp_session=xpt_[A-Za-z0-9_-]{43}; Secure; HttpOnly; '
              r'SameSite=Strict; Path=/; Max-Age=28800$',
            ),
          ),
        );
      },
    );

    test(
      'refuses a loopback origin with a foreign Host (DNS rebinding)',
      () async {
        final code = await codeFor();

        final response = await signIn(
          code,
          headers: {
            'origin': engine.loopbackOrigin,
            'host': 'evil.example:${engine.uri.port}',
          },
        );

        expect(response.statusCode, 403);
        expect(response.error['code'], 'forbidden');
        expect(response.headers['set-cookie'], isNull);
        expect((await signIn(code)).statusCode, 200, reason: 'still unused');
      },
    );

    test(
      'refuses an origin the engine does not serve, with the reason',
      () async {
        for (final origin in [
          'http://evil.example',
          'http://127.0.0.1:1',
          'https://xpath.example.com',
        ]) {
          final response = await signIn(
            await codeFor(),
            headers: {'origin': origin},
          );

          expect(response.statusCode, 403, reason: origin);
          expect(response.error['message'], contains('HTTPS public'));
          expect(response.error['hint'], contains('public URL'));
        }
      },
    );

    test('refuses a request without an Origin as csrf', () async {
      final response = await signIn(await codeFor(), headers: {});

      expect(response.statusCode, 403);
      expect(response.error['code'], 'csrf');
    });

    test('refuses the same code twice, and an unknown one, with 401', () async {
      final code = await codeFor();
      expect((await signIn(code)).statusCode, 200);

      final again = await signIn(code);
      final unknown = await signIn('0000-0000-0000-0000');

      expect(again.statusCode, 401);
      expect(unknown.statusCode, 401);
      expect(again.error, unknown.error);
      expect(again.headers['set-cookie'], isNull);
    });

    test('answers 429 to the 21st wrong code within 10 minutes', () async {
      for (var i = 0; i < 20; i++) {
        expect((await signIn('0000-0000-0000-0000')).statusCode, 401);
      }

      final limited = await signIn(await codeFor());

      expect(limited.statusCode, 429);
      expect(limited.error['code'], 'rate_limited');
      expect(limited.headers['retry-after'], '600');
    });

    test('refuses a body without a code', () async {
      final response = await engine.request(
        '/session',
        method: 'POST',
        token: '',
        headers: {'origin': engine.loopbackOrigin},
        body: '{}',
      );

      expect(response.statusCode, 400);
    });

    test('is not served at the root alias', () async {
      final response = await signIn(
        await codeFor(),
        root: true,
        token: engine.secret,
      );

      expect(response.statusCode, 404);
      expect(response.headers['set-cookie'], isNull);
    });

    test(
      'refuses a loopback origin over a connection from another machine',
      () async {
        final code = await codeFor();
        final router = ApiRouter();
        SessionRoutes(
          signIn: engine.signIn,
          tokens: engine.tokens,
          origins: AllowedOrigins(engine.publicUrl),
        ).addTo(router);
        Request request(InternetAddress remote) => Request(
          'POST',
          Uri.parse('http://127.0.0.1:7480/api/v1/session'),
          headers: {
            'origin': 'http://127.0.0.1:7480',
            'host': '127.0.0.1:7480',
          },
          body: jsonEncode({'code': code}),
          context: {'shelf.io.connection_info': _Connection(remote, 7480)},
        ).change(path: 'api/v1');

        final remote = await router.call(
          request(InternetAddress('192.168.1.20')),
        );
        final local = await router.call(request(InternetAddress.loopbackIPv4));

        expect(remote.statusCode, 403);
        expect(await remote.readAsString(), contains('plain HTTP'));
        expect(local.statusCode, 200);
      },
    );
  });

  group('the session cookie', () {
    test('authenticates its web token under /api/v1', () async {
      final cookie = await engine.signInBrowser();

      final response = await engine.request(
        '/me',
        token: '',
        headers: {'cookie': 'other=1; $cookie'},
      );

      expect(response.statusCode, 200);
      expect(Me.fromJson(response.json).token.kind, DeviceTokenKind.web);
    });

    test('is never read at the root aliases', () async {
      final cookie = await engine.signInBrowser();

      final response = await engine.request(
        '/me',
        token: '',
        root: true,
        headers: {'cookie': cookie},
      );

      expect(response.statusCode, 404);
    });

    test('authenticates no token but a web one', () async {
      final response = await engine.request(
        '/me',
        token: '',
        headers: {'cookie': 'xp_session_${engine.uri.port}=${engine.secret}'},
      );

      expect(response.statusCode, 401);
    });

    test("is not another port's engine's session", () async {
      final cookie = await engine.signInBrowser();
      final other = await TestEngine.start();
      addTearDown(other.close);
      final secret = cookie.split('=').last;

      for (final name in ['xp_session_${other.uri.port}', 'xp_session']) {
        final response = await other.request(
          '/me',
          token: '',
          headers: {'cookie': '$name=$secret'},
        );
        expect(response.statusCode, 401, reason: name);
      }
      final own = await engine.request(
        '/me',
        token: '',
        headers: {'cookie': 'xp_session=$secret; $cookie'},
      );
      expect(own.statusCode, 200);
    });

    test('is ignored when the request has a bearer token', () async {
      final cookie = await engine.signInBrowser();
      final viewer = await engine.tokenFor(PersonRole.viewer);

      final me = await engine.request(
        '/me',
        token: viewer,
        headers: {'cookie': cookie},
      );
      final create = await engine.request(
        '/people',
        method: 'POST',
        token: viewer,
        headers: {'cookie': cookie},
        body: jsonEncode({'name': 'Kim', 'role': 'viewer'}),
      );

      expect(Me.fromJson(me.json).person.role, PersonRole.viewer);
      expect(create.statusCode, 403);
      expect(create.error['code'], 'forbidden');
    });

    test('stops working 8 hours after sign-in', () async {
      final cookie = await engine.signInBrowser();
      engine.clock.advance(TokenService.webSessionLifetime);

      final response = await engine.request(
        '/me',
        token: '',
        headers: {'cookie': cookie},
      );

      expect(response.statusCode, 401);
    });
  });

  group('DELETE /session', () {
    test('revokes the session and clears the cookie', () async {
      final cookie = await engine.signInBrowser();

      final response = await engine.request(
        '/session',
        method: 'DELETE',
        token: '',
        headers: engine.browser(cookie),
      );

      expect(response.statusCode, 204);
      expect(response.headers['cache-control'], 'no-store');
      expect(
        response.headers['set-cookie'],
        'xp_session_${engine.uri.port}=; HttpOnly; SameSite=Strict; Path=/; '
        'Max-Age=0',
      );
      final after = await engine.request(
        '/me',
        token: '',
        headers: {'cookie': cookie},
      );
      expect(after.statusCode, 401);
    });

    test('clears a __Host- cookie with Secure', () async {
      await engine.publicUrl.set(
        'https://xpath.example.com',
        by: testOwnerToken,
      );
      final code = await engine.signIn.issue(testOwner.id);
      final signedIn = await signIn(
        code.code,
        headers: {'origin': 'https://xpath.example.com'},
      );
      final cookie = signedIn.headers['set-cookie']!.split(';').first;

      final response = await engine.request(
        '/session',
        method: 'DELETE',
        token: '',
        headers: {
          'cookie': cookie,
          'origin': 'https://xpath.example.com',
          'x-xpath-csrf': '1',
        },
      );

      expect(response.statusCode, 204);
      expect(
        response.headers['set-cookie'],
        '__Host-xp_session=; Secure; HttpOnly; SameSite=Strict; Path=/; '
        'Max-Age=0',
      );
    });

    test('refuses a token that is not a browser session', () async {
      final response = await engine.request('/session', method: 'DELETE');

      expect(response.statusCode, 403);
      expect(response.error['message'], contains('DELETE /tokens'));
    });
  });

  group('POST /people/{id}/sign-in-codes', () {
    Future<RawResponse> issue(String personId, {String? token}) =>
        engine.request(
          '/people/$personId/sign-in-codes',
          method: 'POST',
          token: token,
        );

    test('an admin issues a code for anyone, which signs them in', () async {
      final viewerToken = await engine.tokenFor(PersonRole.viewer);
      final viewer = (await engine.people.get('per_viewer'))!;

      final response = await issue(viewer.id);

      expect(response.statusCode, 201);
      expect(response.headers['cache-control'], 'no-store');
      final code = SignInCode.fromJson(response.json);
      expect(code.personId, viewer.id);
      expect(
        code.expiresAt,
        engine.clock.now().add(SignInCodeService.lifetime),
      );
      final signedIn = await signIn(code.code);
      expect(Me.fromJson(signedIn.json).person, viewer);
      expect(viewerToken, isNotEmpty);
    });

    test("a person's app or cli token issues one for them alone", () async {
      final cli = await engine.tokenFor(PersonRole.developer);

      expect((await issue('per_developer', token: cli)).statusCode, 201);
      final other = await issue(testOwner.id, token: cli);
      expect(other.statusCode, 403);
      expect(other.error['message'], contains('Only an admin'));
    });

    test("an agent's token issues none, even for its own person", () async {
      final mcp = await engine.tokenFor(
        PersonRole.admin,
        kind: DeviceTokenKind.mcp,
      );

      expect((await issue('per_admin', token: mcp)).statusCode, 403);
    });

    test('answers 404 for no such active person', () async {
      expect((await issue('per_nope')).statusCode, 404);
    });
  });
}
