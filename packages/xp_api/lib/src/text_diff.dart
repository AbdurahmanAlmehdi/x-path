import 'package:equatable/equatable.dart';

/// What a line of a diff is: in both texts, only in the new one, or only in
/// the old one.
enum DiffKind {
  /// In both texts.
  same,

  /// Only in the new text.
  added,

  /// Only in the old text.
  removed,
}

/// One line of a diff of two texts.
class DiffLine extends Equatable {
  /// Creates a line.
  const new(this.kind, this.text);

  /// Where the line is.
  final DiffKind kind;

  /// The line, without its line break.
  final String text;

  @override
  String toString() =>
      '${switch (kind) {
        DiffKind.same => ' ',
        DiffKind.added => '+',
        DiffKind.removed => '-',
      }}$text';

  @override
  List<Object?> get props => [kind, text];
}

/// The lines of [before] and [after], each once: what both have, what
/// [after] added and what it removed, in order (a longest common
/// subsequence of the lines, removals before additions).
List<DiffLine> diffLines(String before, String after) {
  List<String> lines(String text) {
    final all = text.split('\n');
    return text.endsWith('\n') ? all.sublist(0, all.length - 1) : all;
  }

  final a = before.isEmpty ? const <String>[] : lines(before);
  final b = after.isEmpty ? const <String>[] : lines(after);
  // common[i][j]: the longest common subsequence of a[i..] and b[j..].
  final common = List.generate(
    a.length + 1,
    (_) => List.filled(b.length + 1, 0),
  );
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      common[i][j] = a[i] == b[j]
          ? common[i + 1][j + 1] + 1
          : (common[i + 1][j] >= common[i][j + 1]
                ? common[i + 1][j]
                : common[i][j + 1]);
    }
  }
  final out = <DiffLine>[];
  var i = 0;
  var j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] == b[j]) {
      out.add(DiffLine(DiffKind.same, a[i]));
      i++;
      j++;
    } else if (j == b.length ||
        (i < a.length && common[i + 1][j] >= common[i][j + 1])) {
      out.add(DiffLine(DiffKind.removed, a[i++]));
    } else {
      out.add(DiffLine(DiffKind.added, b[j++]));
    }
  }
  return out;
}

/// [diffLines] of [before] and [after] as a unified diff: each change with
/// [context] lines around it, hunks apart with `@@ -a,n +b,m @@` headers.
/// Empty when the texts have the same lines.
String unifiedDiff(String before, String after, {int context = 3}) {
  final lines = diffLines(before, after);
  final changed = [
    for (final (index, line) in lines.indexed)
      if (line.kind != DiffKind.same) index,
  ];
  if (changed.isEmpty) return '';
  // Hunks: runs of lines within [context] of a change.
  final hunks = <(int, int)>[];
  for (final index in changed) {
    final start = (index - context).clamp(0, lines.length);
    final end = (index + context + 1).clamp(0, lines.length);
    if (hunks.isNotEmpty && start <= hunks.last.$2) {
      hunks.last = (hunks.last.$1, end);
    } else {
      hunks.add((start, end));
    }
  }
  final out = StringBuffer();
  for (final (start, end) in hunks) {
    var oldLine = 1;
    var newLine = 1;
    for (final line in lines.take(start)) {
      if (line.kind != DiffKind.added) oldLine++;
      if (line.kind != DiffKind.removed) newLine++;
    }
    final hunk = lines.sublist(start, end);
    final oldCount = hunk.where((l) => l.kind != DiffKind.added).length;
    final newCount = hunk.where((l) => l.kind != DiffKind.removed).length;
    out.writeln('@@ -$oldLine,$oldCount +$newLine,$newCount @@');
    hunk.forEach(out.writeln);
  }
  return out.toString();
}
