import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/artifacts/artifact_record.dart';
import 'package:xp_engine/src/artifacts/artifact_repository.dart';
import 'package:xp_engine/src/artifacts/artifact_store.dart';
import 'package:xp_engine/src/process/process_runner.dart';
import 'package:xp_engine/src/process/process_supervisor.dart';
import 'package:xp_engine/src/secrets/secret_store.dart';
import 'package:xp_engine/src/steps/build/stored_artifacts.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/steps/upload/upload_app_store_input.dart';
import 'package:xp_engine/src/stores/apple/altool_output.dart';
import 'package:xp_engine/src/stores/apple/app_store_connect.dart';
import 'package:xp_engine/src/stores/apple/asc_exceptions.dart';
import 'package:xp_engine/src/stores/apple/asc_key.dart';
import 'package:xp_engine/src/stores/apple/asc_models.dart';

/// The variable that carries the app-specific password to altool
/// (`-p @env:XPATH_ASC_APP_PASSWORD`), so that it is never in `ps`.
const ascAppPasswordVariable = 'XPATH_ASC_APP_PASSWORD';

/// Uploads the IPA of the job to App Store Connect (`upload.appStore`,
/// C:752-785, K:559-581; D-14 as amended by ADR 0014, D-09).
///
/// With an API key the IPA goes through the build-upload API, on any engine:
/// the parts App Store Connect asks for are sent, then the upload is polled
/// every [pollInterval] until App Store Connect accepts or refuses it, for at
/// most [processingTimeout]. Its errors are reported the way altool's are
/// (`AltoolOutput`).
///
/// With an Apple ID and an app-specific password it runs `xcrun altool
/// --upload-package` on macOS: the REST API takes API keys only. altool can
/// exit 0 after Apple rejected the build, so its output decides, not its exit
/// code.
///
/// The step has a side effect. `alreadyDone` asks App Store Connect whether it
/// has the build: the REST API for an API key, `altool --build-status` for an
/// Apple ID.
class UploadAppStoreStep
    extends Step<UploadAppStoreInput, UploadAppStoreResult> {
  /// Creates the step. [isMacOS] tells whether this machine runs macOS, where
  /// altool is. [connect] makes the REST client for an API key. [sleep] waits
  /// between two polls (`Future.delayed` by default; tests replace it).
  const new({
    required this.repository,
    required this.store,
    required this.secrets,
    required this.connect,
    required this.isMacOS,
    this.executable = 'xcrun',
    this.pollInterval = const Duration(seconds: 15),
    this.processingTimeout = const Duration(minutes: 30),
    this.sleep = Future.delayed,
  });

  /// The records of the stored artifacts.
  final ArtifactRepository repository;

  /// The artifact store, whose IPA is sent to App Store Connect, or read from
  /// disk by altool.
  final LocalArtifactStore store;

  /// Where the API key and the app-specific password are read from.
  final SecretStore secrets;

  /// Makes the App Store Connect client of an API key.
  final AppStoreConnectFactory connect;

  /// Whether this machine runs macOS.
  final bool isMacOS;

  /// The program that runs altool.
  final String executable;

  /// How long to wait between two polls of a build upload.
  final Duration pollInterval;

  /// How long App Store Connect may take to accept or refuse a build upload
  /// before the step gives up on it.
  final Duration processingTimeout;

  /// Waits for a [Duration].
  final Future<void> Function(Duration) sleep;

  @override
  String get kind => 'upload.appStore';

  @override
  bool sideEffectOf(UploadAppStoreInput input) => true;

  @override
  UploadAppStoreInput decodeInput(Map<String, dynamic> json) =>
      UploadAppStoreInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(UploadAppStoreInput input) => input.toJson();

  @override
  Map<String, dynamic> encodeResult(UploadAppStoreResult result) =>
      result.toJson();

  /// Done when App Store Connect has the build. If it cannot be asked, the
  /// step runs, and Apple refuses a build number it has seen.
  @override
  Future<UploadAppStoreResult?> alreadyDone(
    UploadAppStoreInput input,
    StepContext context,
  ) => switch (input.auth) {
    ApiKeyUploadAuth(:final keySecret) => _inRestApi(input, keySecret),
    AppleIdUploadAuth() => _inBuildStatus(input, context),
  };

  Future<UploadAppStoreResult?> _inRestApi(
    UploadAppStoreInput input,
    String keySecret,
  ) async {
    final AscKey? key;
    try {
      key = await _readKey(keySecret);
    } on Object {
      return null;
    }
    if (key == null) return null;
    final List<AscBuild> builds;
    try {
      builds = await connect(key).builds(
        input.appleAppId,
        version: '${input.version.name}',
        buildNumber: input.build,
      );
    } on AppStoreConnectException {
      return null;
    }
    final build = builds.firstOrNull;
    if (build == null) return null;
    return UploadAppStoreResult(
      alreadyUploaded: true,
      confirmed: true,
      buildId: build.id,
      processingState: build.processingState.wire,
    );
  }

  Future<UploadAppStoreResult?> _inBuildStatus(
    UploadAppStoreInput input,
    StepContext context,
  ) async {
    if (!isMacOS) return null;
    final lines = <String>[];
    final ProcessExit exit;
    try {
      exit = await context.run(
        _appleIdCommand(input, [
          '--build-status',
          '--apple-id',
          input.appleAppId,
          '--bundle-version',
          input.build,
          '--bundle-short-version-string',
          '${input.version.name}',
          '--platform',
          'ios',
        ]),
        onLine: (line) => lines.add(line.text),
      );
    } on ProcessStartException {
      return null;
    }
    // Only an answer that names the build counts: when in doubt the step
    // uploads, and Apple refuses a build number it has already.
    final names = RegExp('(?<!\\d)${input.build}(?!\\d)');
    if (!exit.succeeded ||
        AltoolOutput.parse(lines).rejected ||
        !lines.any(names.hasMatch)) {
      return null;
    }
    return const UploadAppStoreResult(alreadyUploaded: true, confirmed: true);
  }

  @override
  Future<StepOutcome<UploadAppStoreResult>> run(
    UploadAppStoreInput input,
    StepContext context,
  ) async {
    if (input.auth is AppleIdUploadAuth && !isMacOS) {
      return const StepFailed(
        'upload.appStore with an Apple ID needs macOS (xcrun altool): this '
        'machine cannot upload with it. Assign an App Store Connect API key '
        'to the flavor, which uploads from any engine, or run the upload on '
        'the Mac that runs the engine.',
      );
    }
    final ipa = await intactArtifact(
      repository: repository,
      store: store,
      jobId: input.artifactJob ?? context.jobId,
      name: input.artifactName,
      kind: ArtifactKind.ipa,
    );
    if (ipa == null) {
      return StepFailed(
        '${input.sourceOfArtifact} has no intact IPA named '
        '${input.artifactName}. Build the '
        'iOS app first; a changed or missing file is not uploaded.',
      );
    }
    return await switch (input.auth) {
      ApiKeyUploadAuth(:final keySecret) => _uploadThroughApi(
        input,
        ipa,
        keySecret,
        context,
      ),
      AppleIdUploadAuth() => _uploadWithAltool(
        input,
        store.localPath(ipa.path),
        context,
      ),
    };
  }

  Future<StepOutcome<UploadAppStoreResult>> _uploadThroughApi(
    UploadAppStoreInput input,
    ArtifactRecord ipa,
    String keySecret,
    StepContext context,
  ) async {
    final (:key, :problem) = await _usableKey(keySecret);
    if (key == null) return StepFailed(problem!);
    final client = connect(key);
    try {
      final upload = await client.uploadBuild(
        input.appleAppId,
        version: '${input.version.name}',
        buildNumber: input.build,
        fileName: input.artifactName,
        length: ipa.size,
        content: () => store.read(ipa.path),
      );
      return await _awaitVerdict(client, upload, input, context);
    } on AppStoreConnectException catch (error) {
      final hint =
          AltoolOutput.ofUploadErrors([error.message]).hint ?? error.fix;
      return StepFailed(
        'App Store Connect refused the upload: ${error.message}'
        '${hint == null ? '' : ' $hint'} ${_kept(input)}',
      );
    }
  }

  /// Polls [started] until App Store Connect accepts or refuses it, for at
  /// most [processingTimeout].
  Future<StepOutcome<UploadAppStoreResult>> _awaitVerdict(
    AppStoreConnect client,
    AscBuildUpload started,
    UploadAppStoreInput input,
    StepContext context,
  ) async {
    var upload = started;
    final maxPolls =
        processingTimeout.inMilliseconds ~/ pollInterval.inMilliseconds;
    for (var polls = 0; !upload.state.isFinal; polls++) {
      if (context.isStopping) {
        return const StepFailed(
          'The upload to App Store Connect was cancelled.',
        );
      }
      if (polls >= maxPolls) {
        return StepFailed(
          'App Store Connect did not accept or refuse the upload '
          '(${upload.id}) of build ${input.build} in '
          '${processingTimeout.inMinutes} minutes. Resume the step later: it '
          'finds the build if App Store Connect made it. ${_kept(input)}',
        );
      }
      await sleep(pollInterval);
      upload = await client.buildUpload(upload.id);
    }
    if (upload.state == AscBuildUploadState.failed) {
      final output = AltoolOutput.ofUploadErrors([
        for (final error in upload.errors) '$error',
      ]);
      final what = output.rejected ? ': ${output.describe()}' : '.';
      final hint = output.hint;
      return StepFailed(
        'App Store Connect rejected the build$what'
        '${hint == null ? '' : ' $hint'} ${_kept(input)}',
      );
    }
    return StepSucceeded(
      UploadAppStoreResult(confirmed: true, buildId: upload.buildId),
    );
  }

  static String _kept(UploadAppStoreInput input) =>
      'The IPA is still ${input.artifactName} in the artifact store.';

  Future<StepOutcome<UploadAppStoreResult>> _uploadWithAltool(
    UploadAppStoreInput input,
    String path,
    StepContext context,
  ) async {
    final lines = <String>[];
    final ProcessExit exit;
    try {
      exit = await context.run(
        _appleIdCommand(input, _uploadArguments(input, path)),
        onLine: (line) => lines.add(line.text),
      );
    } on ProcessStartException catch (error) {
      return StepFailed(
        '${error.executable} could not be started: ${error.message}. '
        'Install Xcode and select it with xcode-select.',
      );
    }
    if (exit.cancelled) {
      return const StepFailed('The upload to App Store Connect was cancelled.');
    }
    final output = AltoolOutput.parse(lines);
    if (!exit.succeeded || output.rejected) {
      final how = exit.succeeded
          ? 'altool exited 0 but reported errors'
          : 'altool exited with code ${exit.exitCode}';
      final what = output.rejected ? ': ${output.describe()}' : '.';
      final hint = output.hint;
      return StepFailed(
        '$how$what${hint == null ? '' : ' $hint'} The step log has the '
        'output. The IPA is still ${input.artifactName} in the artifact store.',
      );
    }
    return StepSucceeded(
      UploadAppStoreResult(
        confirmed: output.confirmed,
        deliveryId: output.deliveryId,
      ),
    );
  }

  List<String> _uploadArguments(UploadAppStoreInput input, String path) => [
    '--upload-package',
    path,
    '--type',
    'ios',
    '--apple-id',
    input.appleAppId,
    '--bundle-id',
    input.bundleId,
    '--bundle-version',
    input.build,
    '--bundle-short-version-string',
    '${input.version.name}',
  ];

  /// The command for an Apple ID: the password is read from the environment
  /// by altool (`@env:`), which the engine fills from the secret store.
  ProcessCommand _appleIdCommand(
    UploadAppStoreInput input,
    List<String> arguments,
  ) {
    final auth = input.auth as AppleIdUploadAuth;
    return ProcessCommand(
      executable,
      arguments: [
        'altool',
        ...arguments,
        '-u',
        auth.appleId,
        '-p',
        '@env:$ascAppPasswordVariable',
      ],
      passThroughEnvironment: const ['DEVELOPER_DIR'],
      secretEnvironment: {ascAppPasswordVariable: auth.passwordSecret},
    );
  }

  /// The key under [secret], or `null` if there is none.
  Future<AscKey?> _readKey(String secret) async {
    final json = await secrets.read(secret);
    return json == null ? null : AscKey.fromSecret(json);
  }

  /// The key under [secret], or the reason it cannot be used.
  Future<({AscKey? key, String? problem})> _usableKey(String secret) async {
    try {
      final key = await _readKey(secret);
      return (
        key: key,
        problem: key == null
            ? 'There is no ASC key under "$secret" in the secret store.'
            : null,
      );
    } on FormatException catch (error) {
      return (
        key: null,
        problem:
            'The secret "$secret" is not a usable ASC key: ${error.message}',
      );
    }
  }
}
