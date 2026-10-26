import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/artifacts/artifact_recorder.dart';
import 'package:xp_engine/src/artifacts/artifact_repository.dart';
import 'package:xp_engine/src/artifacts/artifact_store.dart';
import 'package:xp_engine/src/artifacts/artifact_summary.dart';
import 'package:xp_engine/src/artifacts/digest.dart';
import 'package:xp_engine/src/process/process_supervisor.dart';
import 'package:xp_engine/src/steps/build/build_files.dart';
import 'package:xp_engine/src/steps/build/build_outputs.dart';
import 'package:xp_engine/src/steps/build/build_result.dart';
import 'package:xp_engine/src/steps/build/build_settings.dart';
import 'package:xp_engine/src/steps/build/build_toolchain.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/toolchain/flutter_resolver.dart';

/// A step that runs `flutter build` of the job's pinned Flutter SDK in the
/// job's worktree and stores what it produced as an artifact (`build.android`
/// and `build.ios`).
///
/// The step is the same for both platforms but for the subcommand, where the
/// output is and whether the machine can do it.
abstract class FlutterBuildStep<I> extends Step<I, BuildResult> {
  /// Creates a step.
  const new({
    required this.toolchain,
    required this.files,
    required this.recorder,
    required this.repository,
    required this.store,
  });

  /// Resolves Flutter and records the tool versions.
  final BuildToolchain toolchain;

  /// The build output on disk.
  final BuildFiles files;

  /// Stores the produced file.
  final ArtifactRecorder recorder;

  /// The records of the stored artifacts.
  final ArtifactRepository repository;

  /// The artifact store, to check a file that was stored before.
  final ArtifactStore store;

  /// The settings inside [input].
  BuildSettings settingsOf(I input);

  /// The platform folder name: `android` or `ios`.
  String get platform;

  /// The `flutter build` subcommand: `apk`, `appbundle` or `ipa`.
  String subcommandOf(I input);

  /// The flags of `flutter build` that are specific to the platform.
  List<String> platformArguments(I input);

  /// What the build produces.
  ArtifactKind artifactKindOf(I input);

  /// The environment variables, besides the allowed ones, that a build on this
  /// platform reads from the engine's environment.
  List<String> get environmentNames;

  /// Why this machine cannot run the build, or `null` if it can.
  String? get unsupportedReason => null;

  /// Gets the output folder ready for the build.
  Future<void> prepareOutputs(String appDirectory) async {}

  /// Looks for what the build produced.
  Future<BuiltFile> locate(
    I input,
    String appDirectory, {
    required DateTime since,
  });

  @override
  bool sideEffectOf(I input) => false;

  @override
  Map<String, dynamic> encodeResult(BuildResult result) => result.toJson();

  /// The file name of the artifact in the store, such as `dev-1.2.3+45.apk`.
  String fileNameOf(I input) =>
      '${settingsOf(input).label}.${artifactKindOf(input).wire}';

  /// Done when the store holds the artifact of this name for the job and the
  /// file still has the SHA-256 recorded for it.
  @override
  Future<BuildResult?> alreadyDone(I input, StepContext context) async {
    final path = ArtifactRecorder.pathOf(context.jobId, fileNameOf(input));
    final record = await repository.findByPath(context.jobId, path);
    if (record == null ||
        record.kind != artifactKindOf(input) ||
        !await store.exists(path) ||
        await sha256OfStream(store.read(path)) != record.sha256) {
      return null;
    }
    final tools = await toolchain.recorded(context.jobId);
    return BuildResult(
      artifact: ArtifactSummary.of(record),
      flutter: tools?.flutter,
      dart: tools?.dart,
      debugInfoDirectory: debugInfoOf(settingsOf(input)),
    );
  }

  @override
  Future<StepOutcome<BuildResult>> run(I input, StepContext context) async {
    final unsupported = unsupportedReason;
    if (unsupported != null) return StepFailed(unsupported);
    final settings = settingsOf(input);
    final ResolvedFlutter flutter;
    try {
      flutter = await toolchain.prepare(context.jobId, settings.flutterVersion);
    } on ToolchainException catch (error) {
      return StepFailed(error.message);
    }
    final appDirectory = settings.appDirectory;
    await prepareOutputs(appDirectory);
    final since = await files.markBuildStart();

    final subcommand = subcommandOf(input);
    final exit = await context.run(
      ProcessCommand(
        flutter.flutterExecutable,
        arguments: [
          'build',
          subcommand,
          ...platformArguments(input),
          ...settings.flutterArguments(
            debugInfoDirectory: debugInfoOf(settings),
          ),
        ],
        workingDirectory: appDirectory,
        environment: const {'CI': 'true'},
        passThroughEnvironment: [
          ...environmentNames,
          ...settings.passThroughEnvironment,
        ],
        secretEnvironment: settings.secretEnvironment,
        secretFiles: settings.secretFiles,
      ),
    );
    if (exit.cancelled) return const StepFailed('The build was cancelled.');
    if (!exit.succeeded) {
      return StepFailed(
        'flutter build $subcommand exited with code ${exit.exitCode}. '
        'The step log has its output.',
      );
    }
    return await keep(
      input,
      context,
      found: await locate(input, appDirectory, since: since),
      flutter: flutter,
      missing:
          'flutter build succeeded but no .${artifactKindOf(input).wire} '
          'was found under $appDirectory/build.',
    );
  }

  /// Stores the file the build left, [found], as the job's artifact, with
  /// the versions of [flutter]. [missing] says what is wrong when there is
  /// none.
  Future<StepOutcome<BuildResult>> keep(
    I input,
    StepContext context, {
    required BuiltFile found,
    required ResolvedFlutter flutter,
    required String missing,
  }) async {
    final BuildFile file;
    switch (found) {
      case Fresh(file: final fresh):
        file = fresh;
      case Stale(file: final leftover):
        return StepFailed(
          '${leftover.path} is older than this build, so it is a leftover of '
          'an earlier one and is not taken. Delete it, or run flutter clean in '
          'the app, and build again.',
        );
      case Missing():
        return StepFailed(missing);
    }
    final record = await recorder.record(
      jobId: context.jobId,
      kind: artifactKindOf(input),
      name: fileNameOf(input),
      content: files.open(file.path),
    );
    return StepSucceeded(
      BuildResult(
        artifact: ArtifactSummary.of(record),
        flutter: flutter.version,
        dart: flutter.dartVersion,
        debugInfoDirectory: debugInfoOf(settingsOf(input)),
      ),
    );
  }

  /// Where an obfuscated build leaves its Dart debug info, relative to the
  /// app; `null` when it is not obfuscated.
  String? debugInfoOf(BuildSettings settings) =>
      settings.obfuscate ? 'build/xpath/debug-info/$platform' : null;
}
