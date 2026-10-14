import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

import '../helpers/collector.dart';
import '../helpers/scripted_connector.dart';

LogLineFrame _line(int seq) => LogLineFrame(
  seq: seq,
  step: 0,
  at: DateTime.utc(2026),
  stream: LogStream.stdout,
  text: 'line $seq',
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

  Collector<LogFrame> follow({int after = 0}) {
    final collector = Collector(client.followJobLogs('job_1', after: after));
    addTearDown(collector.cancel);
    return collector;
  }

  group('followJobLogs', () {
    test('opens /jobs/{id}/logs from the line it is asked for', () async {
      connector.socket();
      follow(after: 7);
      await pumpEventQueue();

      expect(connector.uris.single.path, '/jobs/job_1/logs');
      expect(connector.afters, ['7']);
    });

    test('passes on the lines in order and ends with the end frame', () async {
      final socket = connector.socket();
      final logs = follow();

      socket
        ..send(_line(1).toJson())
        ..send(_line(2).toJson())
        ..send(const LogEndFrame(state: JobState.succeeded).toJson());
      await pumpEventQueue();

      expect(logs.items, [
        _line(1),
        _line(2),
        const LogEndFrame(state: JobState.succeeded),
      ]);
      expect(logs.isDone, isTrue);
      expect(socket.closedByClient, isTrue);
    });

    test('reconnects after the last line when the connection drops', () async {
      final first = connector.socket();
      final second = connector.socket();
      final logs = follow();

      first
        ..send(_line(1).toJson())
        ..send(_line(2).toJson());
      await pumpEventQueue();
      await first.dropWith(1006);
      await pumpEventQueue();
      second
        ..send(_line(2).toJson())
        ..send(_line(3).toJson())
        ..send(const LogEndFrame(state: JobState.failed).toJson());
      await pumpEventQueue();

      expect(logs.items, [
        _line(1),
        _line(2),
        _line(3),
        const LogEndFrame(state: JobState.failed),
      ]);
      expect(connector.afters, ['0', '2']);
      expect(delays, hasLength(1));
    });

    test('reads again the lines a gap says it missed', () async {
      final first = connector.socket();
      final second = connector.socket();
      final logs = follow();

      first
        ..send(_line(1).toJson())
        ..send(const LogGapFrame(fromSeq: 2, toSeq: 4, count: 3).toJson())
        // Whatever follows the gap on this connection is left to the next one.
        ..send(_line(5).toJson());
      await pumpEventQueue();
      second
        ..send(_line(2).toJson())
        ..send(_line(3).toJson())
        ..send(_line(4).toJson())
        ..send(_line(5).toJson())
        ..send(const LogEndFrame(state: JobState.succeeded).toJson());
      await pumpEventQueue();

      expect(logs.items.whereType<LogLineFrame>().map((l) => l.seq), [
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(connector.afters, ['0', '1']);
      expect(first.closedByClient, isTrue);
      expect(delays, isEmpty);
    });

    test('fails with the error when the engine refuses', () async {
      connector.fail(
        const ApiException(
          'Beyond the log',
          statusCode: 409,
          code: ApiErrorCode.resyncRequired,
        ),
      );
      final logs = follow(after: 99);
      await pumpEventQueue();

      expect(logs.errors.single, isA<ApiException>());
      expect(logs.isDone, isTrue);
    });

    test('skips a frame type it does not know', () async {
      final socket = connector.socket();
      final logs = follow();

      socket
        ..send(const {'type': 'future'})
        ..send(_line(1).toJson());
      await pumpEventQueue();

      expect(logs.items, [_line(1)]);
    });

    test('stops when the listener cancels', () async {
      final socket = connector.socket();
      final logs = follow();
      socket.send(_line(1).toJson());
      await pumpEventQueue();

      await logs.cancel();
      await pumpEventQueue();

      expect(socket.closedByClient, isTrue);
    });
  });
}
