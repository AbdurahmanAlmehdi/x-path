import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('NoMasking', () {
    test('passes text through and ignores secrets', () {
      final masker = const NoMasking()..add('hunter2-secret');
      final stream = masker.newStream();

      expect(stream.add('hunter2-secret'), 'hunter2-secret');
      expect(stream.flush(), isEmpty);
    });
  });

  test('OutputLine compares by value', () {
    final at = DateTime.utc(2026);
    final line = OutputLine(
      seq: 1,
      timestamp: at,
      stream: LogStream.stdout,
      text: 'x',
    );

    expect(
      line,
      OutputLine(seq: 1, timestamp: at, stream: LogStream.stdout, text: 'x'),
    );
    expect(
      line,
      isNot(
        OutputLine(seq: 2, timestamp: at, stream: LogStream.stdout, text: 'x'),
      ),
    );
  });
}
