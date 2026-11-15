import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/test_engine.dart';

void main() {
  late TestEngine engine;

  setUp(
    () async => engine = await TestEngine.start(
      socketSweep: const Duration(milliseconds: 20),
    ),
  );
  tearDown(() => engine.close());

  Future<EventStream> browserSocket(String cookie) => engine.connect(
    token: '',
    headers: {'cookie': cookie, 'origin': engine.loopbackOrigin},
  );

  group('GET /events from a browser', () {
    test('opens with the session cookie and an Origin of the engine', () async {
      final stream = await browserSocket(await engine.signInBrowser());
      addTearDown(stream.close);

      expect((await stream.next()).event, const StreamOpened());
    });

    test('closes with 4401 when an admin revokes its token', () async {
      final cookie = await engine.signInBrowser();
      final stream = await browserSocket(cookie);
      await stream.next();
      final web = (await engine.tokens.listFor(
        (await engine.tokens.authenticate(engine.secret))!,
      )).singleWhere((token) => token.kind == DeviceTokenKind.web);

      final revoked = await engine.request(
        '/tokens/${web.id}',
        method: 'DELETE',
      );

      expect(revoked.statusCode, 204);
      expect(await stream.closeCode(), sessionEndedCloseCode);
    });

    test('closes with 4401 when the browser signs out', () async {
      final cookie = await engine.signInBrowser();
      final stream = await browserSocket(cookie);
      await stream.next();

      await engine.request(
        '/session',
        method: 'DELETE',
        token: '',
        headers: engine.browser(cookie),
      );

      expect(await stream.closeCode(), sessionEndedCloseCode);
    });

    test('closes with 4401 once its session expires', () async {
      final stream = await browserSocket(await engine.signInBrowser());
      await stream.next();

      engine.clock.advance(TokenService.webSessionLifetime);

      expect(await stream.closeCode(), sessionEndedCloseCode);
    });

    test('refuses a foreign Origin, and a cookie without one', () async {
      final cookie = await engine.signInBrowser();

      final foreign = await engine.handshake(
        '/events',
        token: '',
        headers: {'cookie': cookie, 'origin': 'http://evil.example'},
      );
      final rebound = await engine.handshake(
        '/events',
        token: '',
        headers: {
          'cookie': cookie,
          'origin': engine.loopbackOrigin,
          'host': 'evil.example:${engine.uri.port}',
        },
      );
      final absent = await engine.handshake(
        '/events',
        token: '',
        headers: {'cookie': cookie},
      );

      for (final response in [foreign, rebound, absent]) {
        expect(response.statusCode, 403);
        expect(response.error['message'], contains('Origin'));
      }
    });
  });

  group('GET /events with a bearer token', () {
    test('closes with 4401 when the token is revoked', () async {
      final cli = await engine.tokenFor(PersonRole.developer);
      final stream = await engine.connect(token: cli);
      await stream.next();
      final token = (await engine.tokens.authenticate(cli))!;

      await engine.tokens.revoke(token.id);

      expect(await stream.closeCode(), sessionEndedCloseCode);
    });

    test('closes with 4401 when its person is removed', () async {
      final cli = await engine.tokenFor(PersonRole.developer);
      final stream = await engine.connect(token: cli);
      await stream.next();

      final removed = await engine.request(
        '/people/per_developer',
        method: 'DELETE',
      );

      expect(removed.statusCode, 204);
      expect(await stream.closeCode(), sessionEndedCloseCode);
    });

    test('keeps the other sockets open', () async {
      final cli = await engine.tokenFor(PersonRole.developer);
      final kept = await engine.connect();
      final closed = await engine.connect(token: cli);
      await kept.next();
      await closed.next();

      await engine.tokens.revoke((await engine.tokens.authenticate(cli))!.id);
      expect(await closed.closeCode(), sessionEndedCloseCode);
      engine.events.append(const EngineStarted(version: 'v', apiVersion: '1'));

      expect((await kept.next()).event, isA<EngineStarted>());
      await kept.close();
    });
  });

  group('GET /jobs/{id}/logs from a browser', () {
    test('follows a job with the session cookie, and closes on '
        'revocation', () async {
      final proceed = Completer<void>();
      engine.supervisor.handler = (process) async {
        await process.emit('one');
        await proceed.future;
        return 0;
      };
      addTearDown(proceed.complete);
      final job = await engine.startJob(['x']);
      final cookie = await engine.signInBrowser();
      final logs = await engine.connectLogs(
        job.id,
        token: '',
        headers: {'cookie': cookie, 'origin': engine.loopbackOrigin},
      );
      await logs.next();

      await engine.request(
        '/session',
        method: 'DELETE',
        token: '',
        headers: engine.browser(cookie),
      );

      await logs.all();
      expect(logs.closeCode, sessionEndedCloseCode);
    });

    test('refuses a foreign Origin', () async {
      final job = await engine.createJob(['true']);

      final response = await engine.handshake(
        '/jobs/${job.id}/logs',
        headers: {'origin': 'http://evil.example'},
      );

      expect(response.statusCode, 403);
    });
  });
}
