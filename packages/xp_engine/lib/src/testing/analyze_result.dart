import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/testing/analyze_output.dart';

/// What the `analyze` step reports in the job.
class AnalyzeResult extends Equatable {
  /// Creates the result.
  const new({
    required this.errors,
    required this.warnings,
    required this.infos,
    required this.issues,
  });

  /// The result for [report].
  factory of(AnalyzeReport report) {
    final ordered = [
      for (final severity in AnalyzeSeverity.values)
        ...report.issues.where((issue) => issue.severity == severity),
    ];
    return AnalyzeResult(
      errors: report.count(AnalyzeSeverity.error),
      warnings: report.count(AnalyzeSeverity.warning),
      infos: report.count(AnalyzeSeverity.info),
      issues: ordered.take(maxStoredIssues).toList(),
    );
  }

  /// How many issues have severity error.
  final int errors;

  /// How many have severity warning.
  final int warnings;

  /// How many have severity info.
  final int infos;

  /// The issues, the most serious first, and at most [maxStoredIssues] of
  /// them.
  final List<AnalyzeIssue> issues;

  /// The most issues kept in a result, so that a project with thousands of
  /// lints does not make a large job.
  static const maxStoredIssues = 200;

  /// Whether more issues were reported than [issues] holds.
  bool get truncated => issues.length < errors + warnings + infos;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'errors': errors,
    'warnings': warnings,
    'infos': infos,
    'truncated': truncated,
    'issues': [for (final issue in issues) issue.toJson()],
  };

  @override
  List<Object?> get props => [errors, warnings, infos, issues];
}
