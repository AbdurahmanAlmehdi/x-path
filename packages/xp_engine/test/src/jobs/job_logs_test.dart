import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

OutputLine _line(int seq, String text, {LogStream? stream}) => OutputLine(
  seq: seq,
  timestamp: DateTime.utc(2026, 10, 13, 9, 0, seq),
  stream: stream ?? LogStream.stdout,
  text: text,
);

String _describe(FanOutEvent<LogLineFrame> event) => switch (event) {
  FanOutItem(:final value) => '${value.seq}:${value.step}:${value.text}',
  FanOutGap(:final fromSeq, :final toSeq, :final count) =>
    'gap $fromSeq-$toSeq ($count)',
};

Future<List<String>> _collect(Stream<FanOutEvent<LogLineFrame>> stream) async =>
    [await for (final event in stream) _describe(event)];

/// Listens to a followed log and notes when it ends.
class _Reader {
  new(Stream<FanOutEvent<LogLineFrame>> stream) {
    subscription = stream.listen(
      (event) => received.add(_describe(event)),
      onDone: finished.complete,
    );
  }

  final received = <String>[];
  final finished = Completer<void>();
  late final StreamSubscription<FanOutEvent<LogLineFrame>> subscription;

  void pause() => subscription.pause();

  void resume() => subscription.resume();
}

/// A store whose `read` looks at the lines a little late, and can hide the
/// newest ones.
class _LateStore extends InMemoryJobLogStore {
  int replayLimit = 1 << 30;

  @override
  Stream<LogLineFrame> read(String jobId, {int after = 0}) async* {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await for (final line in super.read(jobId, after: after)) {
      if (line.seq <= replayLimit) yield line;
    }
  }
}

void main() {
  late InMemoryJobLogStore store;
  late JobLogs logs;

  setUp(() {
    store = InMemoryJobLogStore();
    logs = JobLogs(store: store, liveCapacity: 3);
  });

  group('recording', () {
    test('numbers lines across the steps of a job', () async {
      await logs.begin('job_1');
      final first = await logs.openStep('job_1', 0, 'command');
      await first.record(_line(1, 'a'));
      await first.record(_line(2, 'b', stream: LogStream.stderr));
      await first.close();
      final second = await logs.openStep('job_1', 1, 'command');
      await second.record(_line(1, 'c'));

      expect(
        store.lines['job_1']!.map((l) => (l.seq, l.step, l.stream, l.text)),
        [
          (1, 0, LogStream.stdout, 'a'),
          (2, 0, LogStream.stderr, 'b'),
          (3, 1, LogStream.stdout, 'c'),
        ],
      );
      expect(
        store.lines['job_1']!.first.at,
        DateTime.utc(2026, 10, 13, 9, 0, 1),
      );
      expect(first.path, '/logs/job_1/0-command.log');
      expect(second.ordinal, 1);
      expect(await logs.head('job_1'), 3);
    });

    test('continues the numbering of a job that ran before', () async {
      await logs.begin('job_1');
      await (await logs.openStep('job_1', 0, 'x')).record(_line(1, 'a'));
      await logs.end('job_1');

      await logs.begin('job_1');
      await (await logs.openStep('job_1', 1, 'x')).record(_line(1, 'b'));

      expect(store.lines['job_1']!.map((l) => l.seq), [1, 2]);
    });

    test('cannot open a step of a job that has not begun', () async {
      await expectLater(logs.openStep('job_1', 0, 'x'), throwsStateError);
    });

    test('knows which jobs are active', () async {
      expect(logs.isActive('job_1'), isFalse);

      await logs.begin('job_1');
      expect(logs.isActive('job_1'), isTrue);

      await logs.end('job_1');
      expect(logs.isActive('job_1'), isFalse);
      await logs.end('job_1');
    });

    test(
      'reports the head of a job that is not active from the store',
      () async {
        await logs.begin('job_1');
        await (await logs.openStep('job_1', 0, 'x')).record(_line(1, 'a'));
        await logs.end('job_1');

        expect(await logs.head('job_1'), 1);
        expect(await logs.head('job_2'), 0);
      },
    );
  });

  group('follow', () {
    Future<void> logLines(String jobId, int count, {int from = 1}) async {
      final log = await logs.openStep(jobId, 0, 'x');
      for (var i = from; i < from + count; i++) {
        await log.record(_line(i, 'l$i'));
      }
    }

    test(
      'replays the lines after a cursor of a job that is not active',
      () async {
        await logs.begin('job_1');
        await logLines('job_1', 4);
        await logs.end('job_1');

        expect(await _collect(logs.follow('job_1')), [
          '1:0:l1',
          '2:0:l2',
          '3:0:l3',
          '4:0:l4',
        ]);
        expect(await _collect(logs.follow('job_1', after: 2)), [
          '3:0:l3',
          '4:0:l4',
        ]);
        expect(await _collect(logs.follow('job_1', after: 4)), isEmpty);
      },
    );

    test(
      'replays, then follows the lines of a running job until it ends',
      () async {
        await logs.begin('job_1');
        await logLines('job_1', 2);
        final received = <String>[];
        final done = _collect(logs.follow('job_1')).then(received.addAll);
        await Future<void>.delayed(Duration.zero);

        final log = await logs.openStep('job_1', 1, 'y');
        await log.record(_line(1, 'live'));
        await logs.end('job_1');
        await done;

        expect(received, ['1:0:l1', '2:0:l2', '3:1:live']);
      },
    );

    test('shows a line once even if it is both replayed and live', () async {
      await logs.begin('job_1');
      await logLines('job_1', 2);
      final reader = _Reader(logs.follow('job_1'))..pause();
      await Future<void>.delayed(Duration.zero);
      // The reader is subscribed live; lines arrive while it replays.
      final log = await logs.openStep('job_1', 0, 'x');
      await log.record(_line(3, 'l3'));
      reader.resume();
      await Future<void>.delayed(Duration.zero);
      await logs.end('job_1');
      await reader.finished.future;

      expect(reader.received, ['1:0:l1', '2:0:l2', '3:0:l3']);
    });

    test('tells a reader that falls behind what it missed', () async {
      await logs.begin('job_1');
      final reader = _Reader(logs.follow('job_1'));
      await Future<void>.delayed(Duration.zero);
      reader.pause();
      await logLines('job_1', 8);
      reader.resume();
      await Future<void>.delayed(Duration.zero);
      await logs.end('job_1');
      await reader.finished.future;

      // Line 1 was already on its way to the reader when it paused.
      expect(reader.received, [
        '1:0:l1',
        'gap 2-5 (4)',
        '6:0:l6',
        '7:0:l7',
        '8:0:l8',
      ]);
    });

    test('reports lines the live reader lost and the replay lacks', () async {
      await logs.begin('job_1');
      await logLines('job_1', 2);
      final reader = _Reader(logs.follow('job_1'))..pause();
      await Future<void>.delayed(Duration.zero);
      final log = await logs.openStep('job_1', 0, 'x');
      for (var i = 3; i <= 9; i++) {
        await log.record(_line(i, 'l$i'));
      }
      reader.resume();
      await Future<void>.delayed(Duration.zero);
      await logs.end('job_1');
      await reader.finished.future;

      expect(reader.received, [
        '1:0:l1',
        '2:0:l2',
        'gap 3-6 (4)',
        '7:0:l7',
        '8:0:l8',
        '9:0:l9',
      ]);
    });

    group('when the replay reads the store late', () {
      // The reader subscribes live first; the store is read afterwards, so
      // the lines written meanwhile are both replayed and live.
      late _LateStore late;

      setUp(() {
        late = _LateStore();
        logs = JobLogs(store: late, liveCapacity: 3);
      });

      test('drops the live gap that the replay covered', () async {
        await logs.begin('job_1');
        final reader = _Reader(logs.follow('job_1'));
        await Future<void>.delayed(Duration.zero);
        final log = await logs.openStep('job_1', 0, 'x');
        for (var i = 1; i <= 8; i++) {
          await log.record(_line(i, 'l$i'));
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await logs.end('job_1');
        await reader.finished.future;

        expect(reader.received, [for (var i = 1; i <= 8; i++) '$i:0:l$i']);
      });

      test('narrows a live gap to the lines the replay lacks', () async {
        late.replayLimit = 3;
        await logs.begin('job_1');
        final reader = _Reader(logs.follow('job_1'));
        await Future<void>.delayed(Duration.zero);
        final log = await logs.openStep('job_1', 0, 'x');
        for (var i = 1; i <= 8; i++) {
          await log.record(_line(i, 'l$i'));
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await logs.end('job_1');
        await reader.finished.future;

        expect(reader.received, [
          '1:0:l1',
          '2:0:l2',
          '3:0:l3',
          'gap 4-5 (2)',
          '6:0:l6',
          '7:0:l7',
          '8:0:l8',
        ]);
      });
    });

    test('stops being a live reader when the listener cancels', () async {
      await logs.begin('job_1');
      final subscription = logs.follow('job_1').listen((_) {});
      await Future<void>.delayed(Duration.zero);

      // The cancel completes when the next line wakes the stream up.
      final cancelled = subscription.cancel();
      await logLines('job_1', 5);
      await cancelled;
      await logs.end('job_1');
    });

    test('cleans up when cancelled while it replays', () async {
      await logs.begin('job_1');
      await logLines('job_1', 3);
      final subscription = logs.follow('job_1').listen((_) {});

      await subscription.cancel();
      await logLines('job_1', 3, from: 4);
      await logs.end('job_1');
    });
  });

  group('InMemoryJobLogStore', () {
    test('reads nothing for a job without lines', () async {
      expect(await store.read('job_x').toList(), isEmpty);
      expect(await store.head('job_x'), 0);
    });
  });
}
