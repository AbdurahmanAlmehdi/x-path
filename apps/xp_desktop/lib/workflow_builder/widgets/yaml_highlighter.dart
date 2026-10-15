import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/theme/theme.dart';

/// What a run of YAML text is, for its colour.
enum YamlToken { text, key, string, number, keyword, comment }

/// The runs of one line of YAML, in order; their texts join to the line.
typedef YamlRun = (String text, YamlToken token);

final _keyLine = RegExp(
  r'''^(\s*(?:-\s+)*)((?:"(?:[^"\\]|\\.)*"|'(?:[^']|'')*'|[^\s#'"\-?][^#]*?|-[^\s#][^#]*?))(:)(?=\s|$)''',
);
final _listItem = RegExp(r'^(\s*(?:-\s+)+|\s*-$)');
final _number = RegExp(r'^[-+]?(\d[\d_]*(\.\d*)?|\.\d+)([eE][-+]?\d+)?$');
const _keywords = {'true', 'false', 'null', '~', 'True', 'False', 'Null'};
final _blockHeader = RegExp(r'^[|>][-+0-9]*$');

/// Splits [source] into lines of runs: keys, quoted strings, numbers,
/// booleans and null, comments, and the text of block scalars as strings.
List<List<YamlRun>> highlightYaml(String source) {
  final lines = <List<YamlRun>>[];
  int? blockIndent;
  for (final line in source.split('\n')) {
    final indent = line.length - line.trimLeft().length;
    if (blockIndent != null) {
      if (line.trim().isEmpty || indent > blockIndent) {
        lines.add([if (line.isNotEmpty) (line, YamlToken.string)]);
        continue;
      }
      blockIndent = null;
    }
    final runs = <YamlRun>[];
    var rest = line;
    if (rest.trimLeft().startsWith('#')) {
      lines.add([(rest, YamlToken.comment)]);
      continue;
    }
    if (_keyLine.firstMatch(rest) case final match?) {
      final lead = match.group(1)!;
      if (lead.isNotEmpty) runs.add((lead, YamlToken.text));
      runs
        ..add((match.group(2)!, YamlToken.key))
        ..add((match.group(3)!, YamlToken.text));
      rest = rest.substring(match.end);
    } else if (_listItem.firstMatch(rest) case final match?) {
      runs.add((match.group(0)!, YamlToken.text));
      rest = rest.substring(match.end);
    }
    final value = _value(rest);
    runs.addAll(value);
    if (value.any((run) => _blockHeader.hasMatch(run.$1.trim()))) {
      blockIndent = indent;
    }
    lines.add(runs);
  }
  return lines;
}

/// The runs of the value part of a line: leading space, the value, a
/// trailing comment.
List<YamlRun> _value(String text) {
  if (text.isEmpty) return const [];
  final runs = <YamlRun>[];
  final trimmed = text.trimLeft();
  final space = text.substring(0, text.length - trimmed.length);
  if (space.isNotEmpty) runs.add((space, YamlToken.text));
  if (trimmed.isEmpty) return runs;
  if (trimmed.startsWith('#')) return [...runs, (trimmed, YamlToken.comment)];
  final comment = _commentStart(trimmed);
  final body = comment == null ? trimmed : trimmed.substring(0, comment);
  final core = body.trimRight();
  final token = switch (core) {
    _ when core.startsWith('"') || core.startsWith("'") => YamlToken.string,
    _ when _keywords.contains(core) || _blockHeader.hasMatch(core) =>
      YamlToken.keyword,
    _ when _number.hasMatch(core) => YamlToken.number,
    _ => YamlToken.text,
  };
  runs.add((body, token));
  if (comment != null) {
    runs.add((trimmed.substring(comment), YamlToken.comment));
  }
  return runs;
}

/// Where a ` #` comment starts in [text], outside quotes.
int? _commentStart(String text) {
  String? quote;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quote != null) {
      if (char == quote) quote = null;
    } else if (char == '"' || char == "'") {
      if (i == 0) quote = char;
    } else if (char == '#' && i > 0 && text[i - 1] == ' ') {
      return i;
    }
  }
  return null;
}

/// A text controller that paints its YAML in the `color.code.*` tokens and
/// underlines, wavy in `color.code.error`, each line with an issue from the
/// issue's column on.
class YamlEditingController extends TextEditingController {
  new({super.text});

  List<WorkflowIssue> _issues = const [];

  /// The issues to underline.
  List<WorkflowIssue> get issues => _issues;
  set issues(List<WorkflowIssue> value) {
    if (value == _issues) return;
    _issues = value;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    required bool withComposing,
    TextStyle? style,
  }) {
    final colors = context.xpColors;
    TextStyle styleOf(YamlToken token) => (style ?? const TextStyle()).copyWith(
      color: switch (token) {
        YamlToken.text => colors.codeText,
        YamlToken.key => colors.codeKey,
        YamlToken.string => colors.codeString,
        YamlToken.number => colors.codeNumber,
        YamlToken.keyword => colors.codeKeyword,
        YamlToken.comment => colors.codeComment,
      },
    );
    final underline = TextStyle(
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.wavy,
      decorationColor: colors.codeError,
    );
    final errorColumns = <int, int>{};
    for (final issue in _issues) {
      final column = issue.column - 1;
      errorColumns.update(
        issue.line - 1,
        (existing) => existing < column ? existing : column,
        ifAbsent: () => column,
      );
    }
    final lines = highlightYaml(text);
    final children = <InlineSpan>[];
    for (final (index, runs) in lines.indexed) {
      if (index > 0) children.add(TextSpan(text: '\n', style: style));
      final from = errorColumns[index];
      var offset = 0;
      for (final (text, token) in runs) {
        final base = styleOf(token);
        if (from == null || offset + text.length <= from) {
          children.add(TextSpan(text: text, style: base));
        } else if (offset >= from) {
          children.add(TextSpan(text: text, style: base.merge(underline)));
        } else {
          final split = from - offset;
          children
            ..add(TextSpan(text: text.substring(0, split), style: base))
            ..add(
              TextSpan(
                text: text.substring(split),
                style: base.merge(underline),
              ),
            );
        }
        offset += text.length;
      }
    }
    return TextSpan(style: style, children: children);
  }
}
