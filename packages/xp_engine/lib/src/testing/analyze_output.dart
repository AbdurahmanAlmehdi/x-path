import 'package:equatable/equatable.dart';

/// How serious an analyzer issue is.
enum AnalyzeSeverity {
  /// A mistake the code cannot be built with.
  error('error'),

  /// Something likely wrong.
  warning('warning'),

  /// A lint or a hint.
  info('info');

  new(this.wire);

  /// The name in the output of `flutter analyze` and in the stored form.
  final String wire;

  /// The severity named [wire], or `null`.
  static AnalyzeSeverity? named(String? wire) =>
      values.where((severity) => severity.wire == wire).firstOrNull;
}

/// One issue `flutter analyze` reported.
class AnalyzeIssue extends Equatable {
  /// Creates an issue.
  const new({
    required this.severity,
    required this.message,
    required this.path,
    required this.line,
    required this.column,
    required this.code,
  });

  /// How serious it is.
  final AnalyzeSeverity severity;

  /// What is wrong, with the analyzer's hint how to fix it.
  final String message;

  /// The file, as the analyzer prints it: relative to the app.
  final String path;

  /// The line, from 1.
  final int line;

  /// The column, from 1.
  final int column;

  /// The analyzer's name for the issue, such as `unused_import`.
  final String code;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'severity': severity.wire,
    'message': message,
    'path': path,
    'line': line,
    'column': column,
    'code': code,
  };

  /// `lib/main.dart:6:10`.
  String get location => '$path:$line:$column';

  @override
  List<Object?> get props => [severity, message, path, line, column, code];
}

/// What `flutter analyze` reported once it finished.
class AnalyzeReport extends Equatable {
  /// Creates a report.
  const new({required this.issues, required this.reported});

  /// The issues that could be read, in the order printed.
  final List<AnalyzeIssue> issues;

  /// How many issues the summary line of the analyzer announced.
  final int reported;

  /// Whether every announced issue was read. If not, the output has a format
  /// the parser does not know, and an error could be hiding in it.
  bool get complete => issues.length == reported;

  /// How many issues have [severity].
  int count(AnalyzeSeverity severity) =>
      issues.where((issue) => issue.severity == severity).length;

  @override
  List<Object?> get props => [issues, reported];
}

final _issue = RegExp(
  r'^\s*(error|warning|info) • (.+) • (.+):(\d+):(\d+) • (\S+)$',
);
final _summary = RegExp(r'^(?:No issues found!|(\d+) issues? found\.)');

/// Reads the text `flutter analyze` prints: one line per issue,
/// `severity • message • path:line:column • code`, and a summary line
/// (`4 issues found.` or `No issues found!`).
///
/// Flutter's analyzer has no machine-readable format. Issues go to standard
/// output and the summary to standard error, so feed both streams.
class AnalyzeOutputParser {
  final _issues = <AnalyzeIssue>[];
  int? _reported;

  /// Reads one line of output.
  void addLine(String line) {
    final issue = _issue.firstMatch(line);
    if (issue != null) {
      _issues.add(
        AnalyzeIssue(
          severity: AnalyzeSeverity.named(issue[1])!,
          message: issue[2]!,
          path: issue[3]!,
          line: int.parse(issue[4]!),
          column: int.parse(issue[5]!),
          code: issue[6]!,
        ),
      );
      return;
    }
    final summary = _summary.firstMatch(line.trim());
    if (summary != null) _reported = int.parse(summary[1] ?? '0');
  }

  /// The report, or `null` if the output has no summary line: the analyzer
  /// did not finish.
  AnalyzeReport? finish() {
    final reported = _reported;
    return reported == null
        ? null
        : AnalyzeReport(issues: List.of(_issues), reported: reported);
  }
}
