import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/test_engine.dart';

/// A log whose subscriptions fail the way a lost resume window does.
class _LosingLog implements EventLog {
  new(this._inner);

  final EventLog _inner;

  @override
  int get head => _inner.head;

  @override
  bool canResume(int after) => true;

  @override
  SequencedEvent append(EngineEvent event) => _inner.append(event);

  @override
  Stream<SequencedEvent> subscribe({int? after}) =>
      Stream.error(EventGapException(after ?? 0, head));

  @override
  Future<void> close() => _inner.close();
}

void main() {
  late TestEngine engine;

  setUp(() async => engine = await TestEngine.start());
  tearDown(() => engine.close());

  group('XpdServer', () {
    test('listens on loopback', () {
      expect(engine.uri.host, '127.0.0.1');
      expect(engine.uri.port, greaterThan(0));
    });

    test('serves /health and /version without a token', () async {
      final health = await engine.request('/health', token: '');
      final version = await engine.request('/version', token: '');

      expect(health.statusCode, 200);
      expect(health.json, {'status': 'ok'});
      expect(version.statusCode, 200);
      expect(version.json, {'version': '9.9.9', 'apiVersion': '1'});
    });

    test('answers an unknown route with 404 and the error envelope', () async {
      final response = await engine.request('/nope');

      expect(response.statusCode, 404);
      expect(response.json['error'], {
        'code': 'not_found',
        'message': 'No route for GET /nope.',
      });
    });

    test('hides unknown routes from callers without a token', () async {
      final response = await engine.request('/nope', token: '');

      expect(response.statusCode, 401);
    });

    test('turns a failure into a 500 that reveals nothing', () async {
      final broken = await TestEngine.start(
        repository: ThrowingDeviceTokenRepository(),
      );
      addTearDown(broken.close);

      final response = await broken.request('/events', token: 'xpt_whatever');

      expect(response.statusCode, 500);
      expect(response.json['error'], {
        'code': 'internal',
        'message': 'The engine failed to handle the request.',
      });
      expect(response.body, isNot(contains('disk on fire')));
      expect(broken.errors, [isA<StateError>()]);
    });

    test('stops serving and closes event streams on close', () async {
      final stream = await engine.connect();
      await stream.next();

      await engine.close();

      expect(await stream.closeCode(), 1000);
      // Refused, or reset when the freed port was already taken by another
      // test file's server running in parallel: either way nothing serves.
      // On macOS a reset while connecting reaches the client as a bare
      // OSError, not a SocketException.
      await expectLater(
        engine.request('/health'),
        throwsA(
          anyOf(isA<SocketException>(), isA<HttpException>(), isA<OSError>()),
        ),
      );
    });
  });

  group('GET /events', () {
    test('refuses a missing, malformed, unknown or wrong token', () async {
      for (final token in ['', 'nope', 'xpt_${'A' * 43}']) {
        final response = await engine.handshake('/events', token: token);

        expect(response.statusCode, 401, reason: 'token "$token"');
        expect(response.json['error'], {
          'code': 'unauthorized',
          'message': 'Missing, unknown or revoked bearer token.',
        });
      }
      await expectLater(
        engine.connect(token: 'xpt_${'A' * 43}'),
        throwsA(
          isA<WebSocketException>().having(
            (e) => e.toString(),
            'text',
            contains('HTTP status code: 401'),
          ),
        ),
      );
    });

    test('accepts the scheme in any case and refuses other schemes', () async {
      final lower = await engine.request(
        '/events',
        token: '',
        headers: {'authorization': 'bearer ${engine.secret}'},
      );
      final basic = await engine.request(
        '/events',
        token: '',
        headers: {'authorization': 'Basic ${engine.secret}'},
      );

      expect(lower.statusCode, 426);
      expect(basic.statusCode, 401);
    });

    test('answers 426 to a request that is not a WebSocket upgrade', () async {
      final response = await engine.request('/events');

      expect(response.statusCode, 426);
      expect(response.json['error'], containsPair('code', 'upgrade_required'));
    });

    test('rejects an after that is not a non-negative integer', () async {
      for (final after in ['abc', '-1', '1.5', '']) {
        final response = await engine.handshake('/events?after=$after');

        expect(response.statusCode, 400, reason: 'after "$after"');
        expect(response.json['error'], containsPair('code', 'invalid_request'));
      }
    });

    test('opens with the log head, then streams live events', () async {
      final stream = await engine.connect();
      addTearDown(stream.close);

      final opened = await stream.next();
      expect(opened.event, isA<StreamOpened>());
      expect(opened.seq, 1); // engine.started is already logged

      engine.events.append(
        const EngineStarted(version: 'live', apiVersion: '1'),
      );
      final live = await stream.next();

      expect(live.seq, 2);
      expect(live.event, const EngineStarted(version: 'live', apiVersion: '1'));
      expect(live.at, engine.clock.now());
    });

    test('logs engine.started when the server starts', () async {
      final stream = await engine.connect(after: 0);
      addTearDown(stream.close);

      final frames = await stream.take(2);

      expect(frames.first.event, isA<StreamOpened>());
      expect(
        frames.last.event,
        const EngineStarted(version: '9.9.9', apiVersion: '1'),
      );
      expect(frames.last.seq, 1);
    });

    test(
      'resumes after a disconnect without losing or repeating events',
      () async {
        EngineEvent event(int n) =>
            EngineStarted(version: '$n', apiVersion: '1');

        var stream = await engine.connect();
        await stream.next(); // stream.opened
        engine.events
          ..append(event(2))
          ..append(event(3));
        final seen = await stream.take(2);
        expect(seen.map((e) => e.seq), [2, 3]);
        await stream.close();

        // Events logged while nobody listens.
        engine.events
          ..append(event(4))
          ..append(event(5));

        stream = await engine.connect(after: seen.last.seq);
        addTearDown(stream.close);
        engine.events.append(event(6));

        final frames = await stream.take(4);

        expect(frames.first.event, isA<StreamOpened>());
        expect(frames.first.seq, 5);
        expect(frames.skip(1).map((e) => e.seq), [4, 5, 6]);
      },
    );

    test('answers 409 when the cursor has left the resume window', () async {
      final small = await TestEngine.start(eventCapacity: 2);
      addTearDown(small.close);
      small.events
        ..append(const EngineStarted(version: 'a', apiVersion: '1'))
        ..append(const EngineStarted(version: 'b', apiVersion: '1'));

      final response = await small.handshake('/events?after=0');

      expect(response.statusCode, 409);
      expect(response.json['error'], containsPair('code', 'resync_required'));
    });

    test('answers 409 when the cursor is ahead of the log', () async {
      final response = await engine.handshake('/events?after=99');

      expect(response.statusCode, 409);
    });

    test('closes with 4409 if the window is lost after the upgrade', () async {
      final losing = await TestEngine.start(wrapLog: _LosingLog.new);
      addTearDown(losing.close);

      final stream = await losing.connect(after: 0);
      await stream.next(); // stream.opened

      expect(await stream.closeCode(), eventStreamResyncCloseCode);
    });

    test('refuses a browser origin', () async {
      final response = await engine.request(
        '/events',
        headers: {
          'connection': 'Upgrade',
          'upgrade': 'websocket',
          'sec-websocket-version': '13',
          'sec-websocket-key': 'AQEBAQEBAQEBAQEBAQEBAQ==',
          'origin': 'http://evil.example',
        },
      );

      expect(response.statusCode, 403);
    });

    test('ignores what clients send', () async {
      final stream = await engine.connect();
      addTearDown(stream.close);
      await stream.next();

      stream.socket.add('hello');
      engine.events.append(
        const EngineStarted(version: 'after', apiVersion: '1'),
      );

      expect((await stream.next()).seq, 2);
    });

    test('survives a client that breaks the protocol', () async {
      final socket = await Socket.connect('127.0.0.1', engine.uri.port);
      addTearDown(socket.destroy);
      final upgraded = Completer<void>();
      var received = '';
      socket
        ..listen((bytes) {
          received += latin1.decode(bytes);
          if (received.contains('\r\n\r\n') && !upgraded.isCompleted) {
            upgraded.complete();
          }
        }, onError: (Object _) {})
        ..write(
          'GET /events HTTP/1.1\r\n'
          'host: localhost\r\n'
          'authorization: Bearer ${engine.secret}\r\n'
          'connection: Upgrade\r\n'
          'upgrade: websocket\r\n'
          'sec-websocket-version: 13\r\n'
          'sec-websocket-key: AQEBAQEBAQEBAQEBAQEBAQ==\r\n\r\n',
        );
      await upgraded.future;
      expect(received, startsWith('HTTP/1.1 101'));

      // A masked frame with a reserved opcode.
      socket.add([0x8F, 0x80, 0, 0, 0, 0]);
      await socket.flush();

      expect((await engine.request('/health')).statusCode, 200);
      expect(engine.errors, isEmpty);
    });

    test('keeps other clients going when one leaves', () async {
      final leaving = await engine.connect();
      final staying = await engine.connect();
      addTearDown(staying.close);
      await leaving.next();
      await staying.next();

      await leaving.close();
      engine.events.append(
        const EngineStarted(version: 'after', apiVersion: '1'),
      );

      expect((await staying.next()).event, isA<EngineStarted>());
    });
  });
}
