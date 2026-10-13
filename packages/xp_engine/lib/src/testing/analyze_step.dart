import 'package:xp_engine/src/process/process_supervisor.dart';
import 'package:xp_engine/src/steps/build/build_toolchain.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/testing/analyze_input.dart';
import 'package:xp_engine/src/testing/analyze_output.dart';
import 'package:xp_engine/src/testing/analyze_result.dart';
import 'package:xp_engine/src/toolchain/flutter_resolver.dart';

/// How many issues the failure message of the step names.
const _namedIssues = 5;

/// Runs `flutter analyze` over the app (`analyze`, D-21).
///
/// The step fails when the analyzer reports an issue of the input's `failOn`
/// severity or worse: errors by default. There is no baseline for the
/// analyzer: an error is never something a project lives with, and warnings
/// and lints are recorded in the result without failing the step unless the
/// workflow asks for it.
///
/// It resolves packages with `flutter pub get` first, because the analyzer is
/// run with `--no-pub` and, in a fresh worktree, reports every import of a
/// package as missing without them. A run whose output has no summary, or
/// fewer issues than the summary announces, fails: it says nothing about the
/// code.
class AnalyzeStep extends Step<AnalyzeInput, AnalyzeResult> {
  /// Creates the step.
  const new({required this.toolchain});

  /// Resolves Flutter and records the tool versions.
  final BuildToolchain toolchain;

  /// The variables of the engine's environment that Flutter reads on top of
  /// the allowed ones.
  static const environmentNames = [
    'PUB_CACHE',
    'PUB_HOSTED_URL',
    'FLUTTER_STORAGE_BASE_URL',
  ];

  @override
  String get kind => 'analyze';

  @override
  bool sideEffectOf(AnalyzeInput input) => false;

  @override
  AnalyzeInput decodeInput(Map<String, dynamic> json) =>
      AnalyzeInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(AnalyzeInput input) => input.toJson();

  @override
  Map<String, dynamic> encodeResult(AnalyzeResult result) => result.toJson();

  @override
  Future<StepOutcome<AnalyzeResult>> run(
    AnalyzeInput input,
    StepContext context,
  ) async {
    final ResolvedFlutter flutter;
    try {
      flutter = await toolchain.prepare(context.jobId, input.flutterVersion);
    } on ToolchainException catch (error) {
      return StepFailed(error.message);
    }

    ProcessCommand flutterCommand(List<String> arguments) => ProcessCommand(
      flutter.flutterExecutable,
      arguments: arguments,
      workingDirectory: input.appDirectory,
      environment: const {'CI': 'true'},
      passThroughEnvironment: environmentNames,
    );

    final pub = await context.run(flutterCommand(const ['pub', 'get']));
    if (pub.cancelled) return const StepFailed('The analysis was cancelled.');
    if (!pub.succeeded) {
      return StepFailed(
        'flutter pub get exited with code ${pub.exitCode}. The step log has '
        'its output.',
      );
    }

    final parser = AnalyzeOutputParser();
    // The warnings and lints do not make the analyzer exit with an error
    // here: the step decides what fails, from what it reads.
    final exit = await context.run(
      flutterCommand(const [
        'analyze',
        '--no-pub',
        '--no-fatal-infos',
        '--no-fatal-warnings',
      ]),
      onLine: (line) => parser.addLine(line.text),
    );
    if (exit.cancelled) return const StepFailed('The analysis was cancelled.');
    final report = parser.finish();
    if (report == null) {
      return StepFailed(
        'flutter analyze did not finish (exit code ${exit.exitCode}). The '
        'step log has its output.',
      );
    }
    if (!report.complete) {
      return StepFailed(
        'flutter analyze announced ${report.reported} issues but '
        '${report.issues.length} could be read, so an error could be hiding '
        'in output this step does not understand. The step log has it.',
      );
    }

    final result = AnalyzeResult.of(report);
    final failing = [
      for (final issue in report.issues)
        if (issue.severity.index <= input.failOn.index) issue,
    ];
    if (failing.isEmpty) return StepSucceeded(result);
    final named = [
      for (final issue in failing.take(_namedIssues))
        '${issue.location}: ${issue.message} (${issue.code})',
    ];
    final more = failing.length - named.length;
    final headline =
        'flutter analyze found ${failing.length} ${_describe(input.failOn)}:';
    return StepFailed(
      [headline, ...named, if (more > 0) 'and $more more.'].join('\n'),
    );
  }

  String _describe(AnalyzeSeverity failOn) => switch (failOn) {
    AnalyzeSeverity.error => 'errors',
    AnalyzeSeverity.warning => 'errors or warnings',
    AnalyzeSeverity.info => 'issues',
  };
}
