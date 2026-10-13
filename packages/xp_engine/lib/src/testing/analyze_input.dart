import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/testing/analyze_output.dart';
import 'package:xp_engine/src/versioning/release_worktree.dart';

/// What the `analyze` step checks.
class AnalyzeInput extends Equatable {
  /// Creates the input.
  const new({
    required this.worktree,
    this.flutterVersion,
    this.failOn = AnalyzeSeverity.error,
  });

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type.
  factory fromJson(Map<String, dynamic> json) {
    final failOn = optionalString(json, 'failOn');
    return AnalyzeInput(
      worktree: ReleaseWorktree.fromJson(requiredObject(json, 'worktree')),
      flutterVersion: optionalString(json, 'flutterVersion'),
      failOn: failOn == null
          ? AnalyzeSeverity.error
          : AnalyzeSeverity.named(failOn) ??
                (throw FormatException(
                  '"failOn" must be "error", "warning" or "info", not '
                  '$failOn.',
                )),
    );
  }

  /// The worktree of the job and the app in it.
  final ReleaseWorktree worktree;

  /// The Flutter version the app pins in `.fvmrc`, as the scan read it.
  final String? flutterVersion;

  /// The least serious issue that fails the step: `error` fails on errors
  /// only, `warning` on warnings too, `info` on any issue.
  final AnalyzeSeverity failOn;

  /// The app's directory.
  String get appDirectory => worktree.appPath == '.'
      ? worktree.path
      : '${worktree.path}/${worktree.appPath}';

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'worktree': worktree.toJson(),
    'flutterVersion': ?flutterVersion,
    'failOn': failOn.wire,
  };

  @override
  List<Object?> get props => [worktree, flutterVersion, failOn];
}
