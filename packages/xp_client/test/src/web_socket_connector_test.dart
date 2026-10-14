import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

import '../helpers/fake_engine.dart';
import '../helpers/samples.dart' as sample;

void main() {
  late FakeEngine engine;

  setUp(() async => engine = await FakeEngine.start());
  tearDown(() => engine.close());

  Uri wsUrl(String path) => engine.url.replace(scheme: 'ws', path: path);

  group('connectWebSocket', () {
    test('upgrades and exchanges text frames with the token', () async {
      engine.on('GET', '/events', (request, call) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket
          ..add('hello')
          ..listen((message) => socket.add('echo $message'));
      });

      final channel = await connectWebSocket(wsUrl('/events'), {
        'Authorization': 'Bearer xp_secret',
      });
      final messages = StreamIterator(channel.stream);
      await messages.moveNext();
      expect(messages.current, 'hello');
      channel.sink.add('ping');
      await messages.moveNext();
      expect(messages.current, 'echo ping');
      await channel.sink.close();

      expect(engine.last.headers['authorization'], 'Bearer xp_secret');
    });

    test('keeps the query', () async {
      engine.on('GET', '/events', (request, call) async {
        final socket = await WebSocketTransformer.upgrade(request);
        await socket.close();
      });

      final channel = await connectWebSocket(
        wsUrl('/events').replace(queryParameters: {'after': '7'}),
        const {},
      );
      await channel.sink.close();

      expect(engine.last.query, {'after': '7'});
    });

    test('a refusal with an error envelope is an ApiException', () async {
      engine.error('GET', '/events', ApiErrorCode.resyncRequired, 'Reload.');

      await expectLater(
        connectWebSocket(wsUrl('/events'), const {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isResyncRequired, 'isResyncRequired', isTrue)
              .having((e) => e.message, 'message', 'Reload.'),
        ),
      );
    });

    test('a refusal without an envelope is an ApiException', () async {
      engine.on('GET', '/events', (request, call) {
        request.response
          ..statusCode = 502
          ..write('<html>');
        return request.response.close();
      });

      await expectLater(
        connectWebSocket(wsUrl('/events'), const {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 502)
              .having((e) => e.code, 'code', isNull),
        ),
      );
    });

    test('a handshake with the wrong key is a ConnectionException', () async {
      engine.on('GET', '/events', (request, call) async {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.write(
          'HTTP/1.1 101 Switching Protocols\r\n'
          'Connection: Upgrade\r\nUpgrade: websocket\r\n'
          'Sec-WebSocket-Accept: wrong\r\n\r\n',
        );
        await socket.flush();
        await socket.close();
      });

      await expectLater(
        connectWebSocket(wsUrl('/events'), const {}),
        throwsA(
          isA<ConnectionException>().having(
            (e) => e.message,
            'message',
            contains('handshake'),
          ),
        ),
      );
    });

    test('an engine that is not there is a ConnectionException', () async {
      final url = wsUrl('/events');
      await engine.close();

      await expectLater(
        connectWebSocket(url, const {}),
        throwsA(isA<ConnectionException>()),
      );
    });

    test('maps wss to a TLS connection', () async {
      final url = engine.url.replace(scheme: 'wss', path: '/events');

      // The fake engine does not speak TLS, so the handshake fails; what
      // counts is that it is tried as TLS and fails as a connection error.
      await expectLater(
        connectWebSocket(url, const {}),
        throwsA(isA<ConnectionException>()),
      );
    });
  });

  group('XpClient with the real connector', () {
    test('watchEvents reads events from a real WebSocket', () async {
      engine.on('GET', '/events', (request, call) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.add(
          jsonEncode(
            SequencedEvent(
              seq: 1,
              at: sample.at,
              event: const StreamOpened(),
            ).toJson(),
          ),
        );
      });
      final client = XpClient(baseUrl: engine.url, token: 'xp_secret');
      addTearDown(client.close);

      final first = await client.watchEvents().first;

      expect(
        first,
        isA<EventReceived>().having(
          (item) => item.event.event,
          'event',
          const StreamOpened(),
        ),
      );
      expect(engine.last.headers['authorization'], 'Bearer xp_secret');
    });

    test('followJobLogs reads a log to its end', () async {
      engine.on('GET', '/jobs/job_1/logs', (request, call) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket
          ..add(
            jsonEncode(
              LogLineFrame(
                seq: 1,
                step: 0,
                at: sample.at,
                stream: LogStream.stderr,
                text: 'boom',
              ).toJson(),
            ),
          )
          ..add(jsonEncode(const LogEndFrame(state: JobState.failed).toJson()));
      });
      final client = XpClient(baseUrl: engine.url, token: 'xp_secret');
      addTearDown(client.close);

      final frames = await client.followJobLogs('job_1').toList();

      expect(frames, hasLength(2));
      expect(frames.last, const LogEndFrame(state: JobState.failed));
      expect(engine.last.query, {'after': '0'});
    });

    test('watchEvents reports a revoked token', () async {
      engine.error('GET', '/events', ApiErrorCode.unauthorized, 'Revoked.');
      final client = XpClient(baseUrl: engine.url, token: 'xp_secret');
      addTearDown(client.close);

      await expectLater(client.watchEvents(), emitsError(isA<ApiException>()));
    });
  });

  test('WebSocketChannel is what the connector returns', () async {
    engine.on('GET', '/events', (request, call) async {
      final socket = await WebSocketTransformer.upgrade(request);
      await socket.close();
    });

    final channel = await connectWebSocket(wsUrl('/events'), const {});

    expect(channel, isA<WebSocketChannel>());
    await channel.sink.close();
  });
}
