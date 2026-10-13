import 'package:xp_engine/src/git/git_service.dart';
import 'package:xp_engine/src/steps/guard/guard_check.dart';
import 'package:xp_engine/src/steps/guard/guard_input.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/versioning/workspace.dart';

/// Runs the checks a workflow lists before a build or an upload and stops the
/// job at the first sign of trouble (`guard` in the step library).
///
/// Every requested check runs, so the owner sees all problems at once. The
/// step fails if any check failed; warnings and skipped checks do not stop
/// the job. A check the engine has no implementation for fails: a guard that
/// silently does not run is worse than none.
class GuardStep extends Step<GuardInput, GuardReport> {
  /// Creates the step with the [checks] the engine can run.
  ///
  /// Throws an [ArgumentError] if two checks have the same name.
  new({
    required Iterable<GuardCheck> checks,
    required this._git,
    required this._workspaces,
  }) : _checks = {} {
    for (final check in checks) {
      if (_checks.containsKey(check.name)) {
        throw ArgumentError.value(check.name, 'checks', 'Duplicate check');
      }
      _checks[check.name] = check;
    }
  }

  final GitService _git;
  final WorkspaceOpener _workspaces;
  final Map<GuardCheckName, GuardCheck> _checks;

  @override
  String get kind => 'guard';

  @override
  bool sideEffectOf(GuardInput input) => false;

  @override
  GuardInput decodeInput(Map<String, dynamic> json) =>
      GuardInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(GuardInput input) => input.toJson();

  @override
  Map<String, dynamic> encodeResult(GuardReport result) => result.toJson();

  @override
  Future<StepOutcome<GuardReport>> run(
    GuardInput input,
    StepContext context,
  ) async {
    final request = GuardRequest(
      input: input,
      workspace: _workspaces(input.worktree.path),
      git: _git,
    );
    final results = <GuardCheckResult>[];
    for (final name in input.checks) {
      final check = _checks[name];
      results.add(
        check == null
            ? GuardCheckResult(
                name,
                GuardStatus.failed,
                'This engine cannot run the ${name.name} check yet.',
              )
            : await check.run(request),
      );
    }
    final failures = [
      for (final result in results)
        if (result.status == GuardStatus.failed) result,
    ];
    if (failures.isEmpty) return StepSucceeded(GuardReport(results));
    return StepFailed(
      [for (final failure in failures) _describe(failure)].join('\n\n'),
    );
  }

  static String _describe(GuardCheckResult failure) {
    final fix = failure.fix == null ? '' : '\nFix: ${failure.fix}';
    return '${failure.name.name}: ${failure.message}$fix';
  }
}
