import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  final at = DateTime.utc(2026, 10, 13, 9, 30);

  group('LogFrame', () {
    test('serializes a line', () {
      final frame = LogLineFrame(
        seq: 7,
        step: 2,
        at: at,
        stream: LogStream.stderr,
        text: 'boom',
      );

      expect(frame.toJson(), {
        'type': 'line',
        'seq': 7,
        'step': 2,
        'at': '2026-10-13T09:30:00.000Z',
        'stream': 'stderr',
        'text': 'boom',
      });
    });

    test('serializes a gap', () {
      expect(const LogGapFrame(fromSeq: 3, toSeq: 9, count: 7).toJson(), {
        'type': 'gap',
        'fromSeq': 3,
        'toSeq': 9,
        'count': 7,
      });
    });

    test('serializes the end with the wire name of the state', () {
      expect(const LogEndFrame(state: JobState.waitingForResume).toJson(), {
        'type': 'end',
        'state': 'waiting_for_resume',
      });
    });

    test('round-trips every kind of frame', () {
      for (final frame in <LogFrame>[
        LogLineFrame(
          seq: 1,
          step: 0,
          at: at,
          stream: LogStream.stdout,
          text: 'hello',
        ),
        const LogGapFrame(fromSeq: 1, toSeq: 2, count: 2),
        const LogEndFrame(state: JobState.failed),
      ]) {
        expect(LogFrame.fromJson(frame.toJson()), frame);
        expect(frame.type, frame.toJson()['type']);
      }
    });

    test('rejects a frame of an unknown type', () {
      expect(
        () => LogFrame.fromJson(const {'type': 'nope'}),
        throwsFormatException,
      );
    });
  });
}
