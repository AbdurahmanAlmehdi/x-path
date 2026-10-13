import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_fake_play/xp_fake_play.dart';

final _start = DateTime.utc(2026, 10, 13, 12);

Map<String, dynamic> _part(String token, int index) => jsonDecode(
  utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[index]))),
) as Map<String, dynamic>;

void main() {
  late ManualClock clock;
  late FakePlayServer server;

  PlayServiceAccount account({
    String privateKey = fakePlayPrivateKeyPem,
    String clientEmail = fakePlayClientEmail,
    String? tokenUri,
  }) => PlayServiceAccount(
    clientEmail: clientEmail,
    privateKey: privateKey,
    privateKeyId: fakePlayPrivateKeyId,
    tokenUri: tokenUri ?? '${server.tokenUri}',
  );

  PlayTokenProvider provider({
    PlayServiceAccount? forAccount,
    http.Client? client,
    Duration timeout = const Duration(seconds: 30),
  }) {
    final created = PlayTokenProvider(
      account: forAccount ?? account(),
      clock: clock,
      client: client,
      timeout: timeout,
    );
    addTearDown(created.close);
    return created;
  }

  setUp(() async {
    clock = ManualClock(_start);
    server = await FakePlayServer.start(now: clock.now);
    addTearDown(server.close);
  });

  Future<Object?> failure(Future<Object?> future) =>
      future.then<Object?>((_) => null, onError: (Object e) => e);

  group('the assertion', () {
    test('has the header and the claims Google documents', () async {
      final bodies = <Map<String, String>>[];
      final tokens = provider(
        client: MockClient((request) async {
          bodies.add(request.bodyFields);
          return http.Response(
            jsonEncode({'access_token': 'ya29.x', 'expires_in': 3600}),
            200,
          );
        }),
      );

      await tokens.token();

      final body = bodies.single;
      expect(body['grant_type'], 'urn:ietf:params:oauth:grant-type:jwt-bearer');
      final assertion = body['assertion']!;
      expect(_part(assertion, 0), {
        'alg': 'RS256',
        'typ': 'JWT',
        'kid': fakePlayPrivateKeyId,
      });
      final seconds = _start.millisecondsSinceEpoch ~/ 1000;
      expect(_part(assertion, 1), {
        'iss': fakePlayClientEmail,
        'scope': playScope,
        'aud': '${server.tokenUri}',
        'iat': seconds,
        'exp': seconds + 1800,
      });
    });

    test('omits the key id a key file does not have', () async {
      final headers = <Map<String, dynamic>>[];
      final tokens = provider(
        forAccount: PlayServiceAccount(
          clientEmail: fakePlayClientEmail,
          privateKey: fakePlayPrivateKeyPem,
          tokenUri: '${server.tokenUri}',
        ),
        client: MockClient((request) async {
          headers.add(_part(request.bodyFields['assertion']!, 0));
          return http.Response(jsonEncode({'access_token': 't'}), 200);
        }),
      );

      await tokens.token();

      expect(headers.single.containsKey('kid'), isFalse);
    });

    test('is accepted by the fake token endpoint', () async {
      final token = await provider().token();

      expect(token, startsWith('ya29.fake-1-'));
      expect(server.tokensIssued, 1);
    });
  });

  group('the token', () {
    test('is kept until shortly before it expires', () async {
      final tokens = provider();

      final first = await tokens.token();
      clock.advance(const Duration(minutes: 57));
      final second = await tokens.token();
      clock.advance(const Duration(minutes: 2));
      final third = await tokens.token();

      expect(second, first);
      expect(third, isNot(first));
      expect(server.tokensIssued, 2);
    });

    test('is asked for once when calls overlap', () async {
      final tokens = provider();

      final all = await Future.wait([
        tokens.token(),
        tokens.token(),
        tokens.token(),
      ]);

      expect(all.toSet(), hasLength(1));
      expect(server.tokensIssued, 1);
    });

    test('is replaced after invalidate', () async {
      final tokens = provider();
      final first = await tokens.token();

      tokens.invalidate();

      expect(await tokens.token(), isNot(first));
    });

    test('lives an hour when the endpoint does not say', () async {
      var calls = 0;
      final tokens = provider(
        client: MockClient((_) async {
          calls++;
          return http.Response(jsonEncode({'access_token': 't'}), 200);
        }),
      );

      await tokens.token();
      clock.advance(const Duration(minutes: 57));
      await tokens.token();
      expect(calls, 1);
      clock.advance(const Duration(minutes: 2));
      await tokens.token();

      expect(calls, 2);
    });

    test('is asked for again after a failure', () async {
      var calls = 0;
      final tokens = provider(
        client: MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('', 503)
              : http.Response(jsonEncode({'access_token': 't'}), 200);
        }),
      );

      await expectLater(tokens.token(), throwsA(isA<PlayServerException>()));
      expect(await tokens.token(), 't');
    });
  });

  group('a refusal', () {
    test('of a key the endpoint does not know says why', () async {
      final error = await failure(
        provider(forAccount: account(privateKey: fakePlayOtherPrivateKeyPem))
            .token(),
      );

      expect(error, isA<PlayAuthException>());
      final exception = error! as PlayAuthException;
      expect(
        exception.message,
        'Google refused the service account: Invalid JWT Signature..',
      );
      expect(exception.reason, 'invalid_grant');
      expect(exception.fix, contains('service account key'));
    });

    test('of an unknown service account', () async {
      final error = await failure(
        provider(forAccount: account(clientEmail: 'nobody@x')).token(),
      );

      expect((error! as PlayAuthException).message, contains('nobody@x'));
    });

    test('of a clock that is wrong', () async {
      final tokens = PlayTokenProvider(
        account: account(),
        // The server believes it is an hour later.
        clock: ManualClock(_start.subtract(const Duration(hours: 3))),
      );
      addTearDown(tokens.close);

      final error = await failure(tokens.token());

      expect((error! as PlayAuthException).message, contains('expired'));
    });

    test('without an explanation still says it was refused', () async {
      final error = await failure(
        provider(client: MockClient((_) async => http.Response('{}', 400)))
            .token(),
      );

      expect(
        (error! as PlayAuthException).message,
        'Google refused the service account.',
      );
      expect((error as PlayAuthException).reason, isNull);
    });
  });

  group('a private key that cannot be used', () {
    test('is an auth failure that does not print the key', () async {
      final error = await failure(
        provider(forAccount: account(privateKey: 'nope')).token(),
      );

      expect(error, isA<PlayAuthException>());
      expect(
        (error! as PlayAuthException).message,
        allOf(contains('cannot be used'), isNot(contains('nope'))),
      );
      expect(server.requests, isEmpty);
    });
  });

  group('an endpoint that is not working', () {
    test('answers 5xx', () async {
      final error = await failure(
        provider(
          client: MockClient(
            (_) async =>
                http.Response(jsonEncode({'error': 'backend_error'}), 503),
          ),
        ).token(),
      );

      expect(error, isA<PlayServerException>());
      expect((error! as PlayServerException).statusCode, 503);
    });

    test('answers with something that is not JSON', () async {
      final error = await failure(
        provider(client: MockClient((_) async => http.Response('<html>', 200)))
            .token(),
      );

      expect(
        (error! as PlayServerException).message,
        contains('not a JSON object'),
      );
    });

    test('is not reachable', () async {
      final tokens = provider(
        client: MockClient((_) async => throw http.ClientException('refused')),
      );

      final error = await failure(tokens.token());

      expect(error, isA<PlayServerException>());
      expect((error! as PlayServerException).message, contains('refused'));
    });

    test('does not answer in time', () async {
      final tokens = provider(
        timeout: const Duration(milliseconds: 10),
        client: MockClient((_) => Completer<http.Response>().future),
      );

      final error = await failure(tokens.token());

      expect((error! as PlayServerException).message, contains('in time'));
    });
  });
}
