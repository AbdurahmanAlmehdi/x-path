import 'package:test/test.dart';
import 'package:xp/src/output/format.dart';

void main() {
  group('renderTable', () {
    test('aligns the columns and leaves no trailing blanks', () {
      expect(
        renderTable(
          ['ID', 'NAME'],
          [
            ['a', 'long name'],
            ['bbb', 'x'],
          ],
        ),
        'ID   NAME\n'
        'a    long name\n'
        'bbb  x',
      );
    });

    test('with no rows is the header', () {
      expect(renderTable(['A', 'B'], []), 'A  B');
    });
  });

  test('formatTime prints UTC to the minute', () {
    expect(formatTime(DateTime.utc(2026, 1, 2, 3, 4, 5)), '2026-01-02 03:04');
    expect(formatTime(null), '-');
  });

  test('formatBytes picks the unit', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1023), '1023 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(3 * 1024 * 1024), '3.0 MB');
    expect(formatBytes(5 * 1024 * 1024 * 1024 * 1024 * 1024), '5120.0 TB');
  });

  test('prettyJson indents', () {
    expect(prettyJson({'a': 1}), '{\n  "a": 1\n}');
  });
}
