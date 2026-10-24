import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  group('diffLines', () {
    test('keeps what both have and marks what changed', () {
      expect(diffLines('a\nb\nc\n', 'a\nx\nc\nd\n'), const [
        DiffLine(DiffKind.same, 'a'),
        DiffLine(DiffKind.removed, 'b'),
        DiffLine(DiffKind.added, 'x'),
        DiffLine(DiffKind.same, 'c'),
        DiffLine(DiffKind.added, 'd'),
      ]);
    });

    test('reads a text without a last line break, and an empty one', () {
      expect(diffLines('a', 'a\n'), const [DiffLine(DiffKind.same, 'a')]);
      expect(diffLines('', 'a'), const [DiffLine(DiffKind.added, 'a')]);
      expect(diffLines('a\nb', ''), const [
        DiffLine(DiffKind.removed, 'a'),
        DiffLine(DiffKind.removed, 'b'),
      ]);
      expect(diffLines('', ''), isEmpty);
    });

    test('prints a line as a diff does', () {
      expect(const DiffLine(DiffKind.same, 'a').toString(), ' a');
      expect(const DiffLine(DiffKind.added, 'a').toString(), '+a');
      expect(const DiffLine(DiffKind.removed, 'a').toString(), '-a');
    });
  });

  group('unifiedDiff', () {
    test('is empty for the same lines', () {
      expect(unifiedDiff('a\nb\n', 'a\nb'), isEmpty);
    });

    test('shows each change with its context under a hunk header', () {
      final before = [for (var i = 1; i <= 20; i++) 'line $i'].join('\n');
      final after = before
          .replaceFirst('line 2\n', 'line two\n')
          .replaceFirst('line 18\n', '');

      expect(
        unifiedDiff(before, after, context: 1),
        '@@ -1,3 +1,3 @@\n'
        ' line 1\n'
        '-line 2\n'
        '+line two\n'
        ' line 3\n'
        '@@ -17,3 +17,2 @@\n'
        ' line 17\n'
        '-line 18\n'
        ' line 19\n',
      );
    });

    test('joins changes whose context meets', () {
      expect(
        unifiedDiff('a\nb\nc\nd\n', 'x\nb\nc\ny\n', context: 1),
        '@@ -1,4 +1,4 @@\n'
        '-a\n'
        '+x\n'
        ' b\n'
        ' c\n'
        '-d\n'
        '+y\n',
      );
    });
  });
}
