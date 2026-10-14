import 'dart:async';

import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

import '../helpers/collector.dart';
import '../helpers/fake_web_socket.dart';
import '../helpers/scripted_connector.dart';

SequencedEvent _opened(int seq) => SequencedEvent(
  seq: seq,
  at: DateTime.utc(2026),
  event: const StreamOpened(),
);

SequencedEvent _removed(int seq, [String project = 'prj_1']) => SequencedEvent(
  seq: seq,
  at: DateTime.utc(2026),
  event: ProjectRemoved(projectId: project),
);

void main() {
  late ScriptedConnector connector;
  late List<Duration> delays;
  late XpClient client;

  setUp(() {
    connector = ScriptedConnector();
    delays = [];
    client = XpClient(
      baseUrl: Uri.parse('http://engine:7480'),
      token: 't',
      connector: connector.call,
      delay: (duration) async => delays.add(duration),
    );
  });

  EventReceived received(SequencedEvent event) => EventReceived(event);

  test('a resync notice equals another one', () {
    expect(
      const EventsResyncRequired().hashCode,
      const EventsResyncRequired().hashCode,
    );
  });

  group('watchEvents', () {
    Collector<EventStreamItem> watch([int? after]) {
      final collector = Collector(client.watchEvents(after: after));
      addTearDown(collector.cancel);
      return collector;
    }

    test('connects to /events as WebSocket', () async {
      connector.socket();
      watch();
      await pumpEventQueue();

      expect(connector.uris.single.toString(), 'ws://engine:7480/events');
    });

    test('uses wss for an https engine', () async {
      connector.socket();
      final secure = XpClient(
        baseUrl: Uri.parse('https://engine'),
        token: 't',
        connector: connector.call,
      );
      final collector = Collector(secure.watchEvents());
      addTearDown(collector.cancel);
      await pumpEventQueue();

      expect(connector.uris.single.scheme, 'wss');
    });

    test('passes on the events in order, the opening first', () async {
      final socket = connector.socket();
      final events = watch();

      socket
        ..sendEvent(_opened(5))
        ..sendEvent(_removed(6))
        ..sendEvent(_removed(7));
      await pumpEventQueue();

      expect(events.items, [
        received(_opened(5)),
        received(_removed(6)),
        received(_removed(7)),
      ]);
    });

    test('resumes after the last event when the connection drops', () async {
      final first = connector.socket();
      final second = connector.socket();
      final events = watch();

      first
        ..sendEvent(_opened(5))
        ..sendEvent(_removed(6));
      await pumpEventQueue();
      await first.dropWith();
      await pumpEventQueue();
      second
        ..sendEvent(_opened(9))
        ..sendEvent(_removed(6))
        ..sendEvent(_removed(7))
        ..sendEvent(_removed(8));
      await pumpEventQueue();

      expect(events.items, [
        received(_opened(5)),
        received(_removed(6)),
        received(_opened(9)),
        received(_removed(7)),
        received(_removed(8)),
      ]);
      expect(connector.afters, [null, '6']);
    });

    test('a stream without a cursor starts from the head of the log', () async {
      final first = connector.socket();
      connector.socket();
      watch();

      first.sendEvent(_opened(5));
      await pumpEventQueue();
      await first.dropWith();
      await pumpEventQueue();

      expect(connector.afters, [null, '5']);
    });

    test('resumes after the cursor it was given', () async {
      final first = connector.socket();
      connector.socket();
      watch(3);

      // The opening carries the head of the log (10), not an event handled.
      first.sendEvent(_opened(10));
      await pumpEventQueue();
      await first.dropWith();
      await pumpEventQueue();

      expect(connector.afters, ['3', '3']);
    });

    test('reconnects with a growing delay while the engine is away', () async {
      connector
        ..fail(const ConnectionException('down'))
        ..fail(const ConnectionException('down'))
        ..fail(const ConnectionException('down'))
        ..socket();
      watch();
      await pumpEventQueue();

      expect(delays, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
      ]);
      expect(connector.uris, hasLength(4));
    });

    test('never waits longer than the longest delay', () async {
      for (var i = 0; i < 8; i++) {
        connector.fail(const ConnectionException('down'));
      }
      watch();
      await pumpEventQueue();

      expect(delays.map((d) => d.inSeconds), [1, 2, 4, 8, 16, 30, 30, 30]);
    });

    test('starts the delay over after a connection that worked', () async {
      final first = connector.socket();
      connector
        ..fail(const ConnectionException('down'))
        ..fail(const ConnectionException('down'));
      watch();

      first.sendEvent(_opened(1));
      await pumpEventQueue();
      await first.dropWith();
      await pumpEventQueue();

      // The drop of a working connection waits the first delay again.
      expect(delays.map((d) => d.inSeconds), [1, 2, 4]);
    });

    test('retries a 5xx from the engine', () async {
      connector
        ..fail(const ApiException('Oops', statusCode: 503))
        ..socket();
      watch();
      await pumpEventQueue();

      expect(connector.uris, hasLength(2));
      expect(delays, hasLength(1));
    });

    test('ends with the error when the engine refuses the token', () async {
      connector.fail(
        const ApiException(
          'No',
          statusCode: 401,
          code: ApiErrorCode.unauthorized,
        ),
      );
      final events = watch();
      await pumpEventQueue();

      expect(events.errors.single, isA<ApiException>());
      expect(events.isDone, isTrue);
      expect(connector.uris, hasLength(1));
    });

    test(
      'a 409 resync_required says so and reconnects without a cursor',
      () async {
        connector
          ..fail(
            const ApiException(
              'Reload',
              statusCode: 409,
              code: ApiErrorCode.resyncRequired,
            ),
          )
          ..socket();
        final events = watch(3);
        await pumpEventQueue();

        expect(events.items, [const EventsResyncRequired()]);
        expect(connector.afters, ['3', null]);
        expect(delays, isEmpty);
      },
    );

    test(
      'the close code 4409 says so and reconnects without a cursor',
      () async {
        final first = connector.socket();
        connector.socket();
        final events = watch(3);
        await pumpEventQueue();

        await first.dropWith(eventStreamResyncCloseCode);
        await pumpEventQueue();

        expect(events.items, [const EventsResyncRequired()]);
        expect(connector.afters, ['3', null]);
        expect(delays, isEmpty);
      },
    );

    test('an engine that shuts down is waited for', () async {
      final first = connector.socket();
      connector.socket();
      watch(3);
      await pumpEventQueue();

      await first.dropWith(1000);
      await pumpEventQueue();

      expect(delays, hasLength(1));
      expect(connector.afters, ['3', '3']);
    });

    test('a broken connection is retried', () async {
      final first = connector.socket();
      connector.socket();
      watch(3);
      await pumpEventQueue();

      first.fail(const FormatException('reset'));
      await pumpEventQueue();

      expect(connector.afters, ['3', '3']);
    });

    test('skips frames it cannot read', () async {
      final socket = connector.socket();
      final events = watch();

      socket
        ..send('not json')
        ..send('[1, 2]')
        ..send(const {'seq': 1})
        ..sendEvent(_opened(5))
        ..sendEvent(_removed(6));
      await pumpEventQueue();

      expect(events.items, [received(_opened(5)), received(_removed(6))]);
    });

    test('passes on an event type it does not know', () async {
      final socket = connector.socket();
      final events = watch();

      socket
        ..sendEvent(_opened(5))
        ..send(const {
          'seq': 6,
          'at': '2026-01-01T00:00:00.000Z',
          'type': 'future.thing',
          'payload': {'x': 1},
        });
      await pumpEventQueue();

      final unknown = events.items.last as EventReceived;
      expect(unknown.event.event, isA<UnknownEvent>());
      expect(unknown.event.seq, 6);
    });

    test('closes the socket when the listener cancels', () async {
      final socket = connector.socket();
      final events = watch();
      socket.sendEvent(_opened(5));
      await pumpEventQueue();

      await events.cancel();
      await pumpEventQueue();

      expect(socket.closedByClient, isTrue);
    });

    test(
      'a listener that cancels while connecting closes the socket it gets',
      () async {
        final gate = Completer<WebSocketChannel>();
        connector.hold(gate);
        final events = watch();
        await pumpEventQueue();
        await events.cancel();

        final socket = FakeWebSocket();
        gate.complete(socket);
        await pumpEventQueue();

        expect(socket.closedByClient, isTrue);
        expect(connector.uris, hasLength(1));
      },
    );

    test(
      'a listener that cancels while waiting to reconnect stops it',
      () async {
        final gate = Completer<void>();
        final patient = XpClient(
          baseUrl: Uri.parse('http://engine:7480'),
          token: 't',
          connector: connector.call,
          delay: (_) => gate.future,
        );
        connector
          ..fail(const ConnectionException('down'))
          ..socket();
        final collector = Collector(patient.watchEvents());
        await pumpEventQueue();
        await collector.cancel();

        gate.complete();
        await pumpEventQueue();

        expect(connector.uris, hasLength(1));
      },
    );
  });
}
