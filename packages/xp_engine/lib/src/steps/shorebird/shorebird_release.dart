import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/artifacts/artifact_recorder.dart';
import 'package:xp_engine/src/artifacts/artifact_repository.dart';
import 'package:xp_engine/src/artifacts/artifact_store.dart';
import 'package:xp_engine/src/artifacts/artifact_summary.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/process/process_supervisor.dart';
import 'package:xp_engine/src/steps/build/build_files.dart';
import 'package:xp_engine/src/steps/build/build_outputs.dart';
import 'package:xp_engine/src/steps/build/build_settings.dart';
import 'package:xp_engine/src/steps/build/build_toolchain.dart';
import 'package:xp_engine/src/steps/build/stored_artifacts.dart';
import 'package:xp_engine/src/steps/guard/guard_ports.dart';
import 'package:xp_engine/src/steps/shorebird/shorebird_arguments.dart';
import 'package:xp_engine/src/steps/shorebird/shorebird_release_record.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/toolchain/flutter_resolver.dart';

/// What to release with Shorebird.
class ShorebirdReleaseInput extends Equatable {
  /// Creates the input. [artifact] is [ArtifactKind.apk] or
  /// [ArtifactKind.aab] and only matters on Android; iOS needs
  /// [exportOptionsPlist].
  const new({
    required this.settings,
    required this.platform,
    required this.shorebirdAppId,
    this.artifact = ArtifactKind.aab,
    this.exportOptionsPlist,
    this.tokenSecret,
  }) : assert(
         artifact == ArtifactKind.apk || artifact == ArtifactKind.aab,
         'Android builds an apk or an aab.',
       );

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if [json] is not a valid input.
  factory fromJson(Map<String, dynamic> json) {
    final wire = requiredString(json, 'platform');
    final platform = ShorebirdPlatform.fromWire(wire);
    if (platform == null) {
      throw FormatException(
        '"platform" must be "android" or "ios", not $wire.',
      );
    }
    final artifact = optionalString(json, 'artifact') ?? 'aab';
    if (artifact != 'apk' && artifact != 'aab') {
      throw FormatException(
        '"artifact" must be "apk" or "aab", not $artifact.',
      );
    }
    final exportOptionsPlist = json['exportOptionsPlist'] == null
        ? null
        : requiredRelative(json, 'exportOptionsPlist');
    final problem = exportOptionsProblem(platform, exportOptionsPlist);
    if (problem != null) throw FormatException(problem);
    return ShorebirdReleaseInput(
      settings: BuildSettings.fromJson(json),
      platform: platform,
      shorebirdAppId: requiredString(json, 'shorebirdAppId'),
      artifact: artifact == 'apk' ? ArtifactKind.apk : ArtifactKind.aab,
      exportOptionsPlist: exportOptionsPlist,
      tokenSecret: optionalString(json, 'tokenSecret'),
    );
  }

  /// Where and what to build. Its Flutter pin is the version the release is
  /// made with.
  final BuildSettings settings;

  /// The platform to release.
  final ShorebirdPlatform platform;

  /// The Shorebird app id of the flavor (`app_id` in `shorebird.yaml`).
  final String shorebirdAppId;

  /// The Android package that is the release's main file. An APK release also
  /// stores the AAB that Shorebird builds with it, which is the only AAB that
  /// can receive a patch (C:621-668).
  final ArtifactKind artifact;

  /// The export options of the iOS archive, relative to the app.
  final String? exportOptionsPlist;

  /// The key in the secret store of the Shorebird API key, passed to the CLI
  /// as `SHOREBIRD_TOKEN`; `null` uses the login of the machine.
  final String? tokenSecret;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    ...settings.toJson(),
    'platform': platform.wire,
    'shorebirdAppId': shorebirdAppId,
    'artifact': artifact.wire,
    'exportOptionsPlist': ?exportOptionsPlist,
    'tokenSecret': ?tokenSecret,
  };

  @override
  List<Object?> get props => [
    settings,
    platform,
    shorebirdAppId,
    artifact,
    exportOptionsPlist,
    tokenSecret,
  ];
}

/// What `shorebird.release` made.
class ShorebirdReleaseResult extends Equatable {
  /// Creates the result.
  const new({
    required this.artifacts,
    this.flutter,
    this.dart,
    this.debugInfoDirectory,
    this.alreadyReleased = false,
  });

  /// The files of the release in the artifact store. Empty for a release
  /// that was made earlier and whose files are no longer there.
  final List<ArtifactSummary> artifacts;

  /// The Flutter version the release was built with. A patch uses it.
  final String? flutter;

  /// The Dart version of that Flutter.
  final String? dart;

  /// Where an obfuscated build left its debug info, relative to the app.
  final String? debugInfoDirectory;

  /// Whether Shorebird had the release before this run.
  final bool alreadyReleased;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'artifacts': [for (final artifact in artifacts) artifact.toJson()],
    'flutter': ?flutter,
    'dart': ?dart,
    'debugInfoDirectory': ?debugInfoDirectory,
    'alreadyReleased': alreadyReleased,
  };

  @override
  List<Object?> get props => [
    artifacts,
    flutter,
    dart,
    debugInfoDirectory,
    alreadyReleased,
  ];
}

/// Makes a Shorebird release (`shorebird.release`, C:621-712, O:455-540).
///
/// Runs `shorebird release android|ios` with the flavor, the target, the
/// build name and number and the Flutter version the app pins, stores the
/// APK, AAB or IPA it built, and records the Flutter version of the release,
/// which every patch of it must use (D-20). Shorebird takes the app's own
/// flags after `--`.
///
/// The step has a side effect: Shorebird registers the version, and it cannot
/// be released twice. `alreadyDone` asks Shorebird whether the release exists.
class ShorebirdReleaseStep
    extends Step<ShorebirdReleaseInput, ShorebirdReleaseResult> {
  /// Creates the step. [isMacOS] tells whether this machine runs macOS.
  const new({
    required this.toolchain,
    required this.files,
    required this.recorder,
    required this.repository,
    required this.store,
    required this.releases,
    required this.records,
    required this.clock,
    required this.isMacOS,
    this.shorebirdExecutable = 'shorebird',
  });

  /// Resolves Flutter and records the tool versions.
  final BuildToolchain toolchain;

  /// The build output on disk.
  final BuildFiles files;

  /// Stores the produced files.
  final ArtifactRecorder recorder;

  /// The records of the stored artifacts.
  final ArtifactRepository repository;

  /// The artifact store, to check a file that was stored before.
  final ArtifactStore store;

  /// What Shorebird knows about the releases of the app.
  final ShorebirdReleases releases;

  /// Where the Flutter version of each release is kept.
  final ShorebirdReleaseRepository records;

  /// Time, for the record.
  final Clock clock;

  /// Whether this machine runs macOS.
  final bool isMacOS;

  /// The Shorebird CLI.
  final String shorebirdExecutable;

  @override
  String get kind => 'shorebird.release';

  @override
  bool sideEffectOf(ShorebirdReleaseInput input) => true;

  @override
  ShorebirdReleaseInput decodeInput(Map<String, dynamic> json) =>
      ShorebirdReleaseInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(ShorebirdReleaseInput input) =>
      input.toJson();

  @override
  Map<String, dynamic> encodeResult(ShorebirdReleaseResult result) =>
      result.toJson();

  /// The files a release of [input] stores, main file first.
  List<(ArtifactKind, String)> _expected(ShorebirdReleaseInput input) {
    final label = input.settings.label;
    return switch (input.platform) {
      ShorebirdPlatform.ios => [(ArtifactKind.ipa, '$label.ipa')],
      ShorebirdPlatform.android => [
        (input.artifact, '$label.${input.artifact.wire}'),
        if (input.artifact == ArtifactKind.apk)
          (ArtifactKind.aab, '$label.aab'),
      ],
    };
  }

  /// Done when Shorebird has the release for the platform.
  @override
  Future<ShorebirdReleaseResult?> alreadyDone(
    ShorebirdReleaseInput input,
    StepContext context,
  ) async {
    final settings = input.settings;
    final listed = await releases.releases(
      input.shorebirdAppId,
      tokenSecret: input.tokenSecret,
    );
    final release = listed
        ?.where(
          (release) =>
              release.version == settings.version &&
              release.activePlatforms.contains(input.platform.wire),
        )
        .firstOrNull;
    if (release == null) return null;

    final flutter = release.flutterVersion;
    if (flutter != null &&
        await records.find(
              input.shorebirdAppId,
              settings.version,
              input.platform,
            ) ==
            null) {
      await _record(input, context, flutter);
    }
    final tools = await toolchain.recorded(context.jobId);
    final stored = <ArtifactSummary>[];
    for (final (kind, name) in _expected(input)) {
      final record = await intactArtifact(
        repository: repository,
        store: store,
        jobId: context.jobId,
        name: name,
        kind: kind,
      );
      if (record != null) stored.add(ArtifactSummary.of(record));
    }
    return ShorebirdReleaseResult(
      artifacts: stored,
      flutter: flutter ?? tools?.flutter,
      dart: tools?.dart,
      debugInfoDirectory: _debugInfoOf(input),
      alreadyReleased: true,
    );
  }

  @override
  Future<StepOutcome<ShorebirdReleaseResult>> run(
    ShorebirdReleaseInput input,
    StepContext context,
  ) async {
    final platform = input.platform;
    if (platform == ShorebirdPlatform.ios && !isMacOS) {
      return const StepFailed(
        'shorebird.release for iOS needs macOS (ios-sign): this machine '
        'cannot run Xcode. Run the job on a Mac.',
      );
    }
    final settings = input.settings;
    final ResolvedFlutter flutter;
    try {
      flutter = await toolchain.prepare(context.jobId, settings.flutterVersion);
    } on ToolchainException catch (error) {
      return StepFailed(error.message);
    }
    final appDirectory = settings.appDirectory;
    // shorebird release refuses to pick between two IPAs (C:670-712).
    if (platform == ShorebirdPlatform.ios) {
      await files.deleteAll('$appDirectory/build/ios/ipa', extension: '.ipa');
    }
    final since = await files.markBuildStart();

    final exit = await context.run(
      shorebirdCommand(
        shorebirdExecutable,
        withForwarded(
          _arguments(input, flutter.version),
          forwardedArguments(settings),
        ),
        settings: settings,
        platform: platform,
        tokenSecret: input.tokenSecret,
      ),
    );
    if (exit.cancelled) {
      return const StepFailed('The Shorebird release was cancelled.');
    }
    if (!exit.succeeded) {
      return StepFailed(
        'shorebird release ${platform.wire} exited with code '
        '${exit.exitCode}. The step log has its output.',
      );
    }
    // Shorebird has the release now; patches depend on this record.
    await _record(input, context, flutter.version);

    final summaries = <ArtifactSummary>[];
    for (final (index, (kind, name)) in _expected(input).indexed) {
      final found = await _locate(input, kind, appDirectory, since);
      switch (found) {
        case Fresh(:final file):
          final record = await recorder.record(
            jobId: context.jobId,
            kind: kind,
            name: name,
            content: files.open(file.path),
          );
          summaries.add(ArtifactSummary.of(record));
        case Stale(:final file) when index == 0:
          return StepFailed(
            '${file.path} is older than this release, so it is a '
            'leftover of an earlier build and is not taken. Shorebird has '
            'registered ${settings.version} already: delete the file, bump '
            'the build number and release again.',
          );
        case Missing() when index == 0:
          return StepFailed(
            'shorebird release succeeded but no .${kind.wire} was found '
            'under $appDirectory/build. Shorebird has registered '
            '${settings.version} already: bump the build number before '
            'releasing again.',
          );
        // The AAB beside an APK is a bonus: a release without one still
        // works, but cannot be patched on Play (C:621-668).
        case Stale() || Missing():
          break;
      }
    }
    return StepSucceeded(
      ShorebirdReleaseResult(
        artifacts: summaries,
        flutter: flutter.version,
        dart: flutter.dartVersion,
        debugInfoDirectory: _debugInfoOf(input),
      ),
    );
  }

  List<String> _arguments(ShorebirdReleaseInput input, String flutterVersion) {
    final settings = input.settings;
    return [
      'release',
      input.platform.wire,
      if (input.platform == ShorebirdPlatform.android) ...[
        '--artifact',
        input.artifact.wire,
      ],
      '--flutter-version=$flutterVersion',
      if (settings.flavor != null) ...['--flavor', settings.flavor!],
      if (settings.target != null) ...['--target', settings.target!],
      if (input.exportOptionsPlist != null)
        '--export-options-plist=${input.exportOptionsPlist}',
      if (settings.obfuscate)
        '--split-debug-info=${shorebirdDebugInfoDirectory(input.platform)}',
      '--build-name=${settings.version.name}',
      '--build-number=${settings.build}',
    ];
  }

  Future<BuiltFile> _locate(
    ShorebirdReleaseInput input,
    ArtifactKind kind,
    String appDirectory,
    DateTime since,
  ) {
    final outputs = BuildOutputs(files);
    return input.platform == ShorebirdPlatform.ios
        ? outputs.ios(appDirectory, since: since)
        : outputs.android(
            appDirectory,
            kind: kind,
            flavor: input.settings.flavor,
            since: since,
          );
  }

  Future<void> _record(
    ShorebirdReleaseInput input,
    StepContext context,
    String flutterVersion,
  ) => records.save(
    ShorebirdReleaseRecord(
      appId: input.shorebirdAppId,
      version: input.settings.version,
      platform: input.platform,
      flutterVersion: flutterVersion,
      jobId: context.jobId,
      recordedAt: clock.now(),
    ),
  );

  String? _debugInfoOf(ShorebirdReleaseInput input) => input.settings.obfuscate
      ? shorebirdDebugInfoDirectory(input.platform)
      : null;
}
