import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/process/process_supervisor.dart';
import 'package:xp_engine/src/steps/build/build_files.dart';
import 'package:xp_engine/src/steps/build/build_settings.dart';
import 'package:xp_engine/src/steps/build/build_toolchain.dart';
import 'package:xp_engine/src/steps/guard/guard_ports.dart';
import 'package:xp_engine/src/steps/shorebird/shorebird_arguments.dart';
import 'package:xp_engine/src/steps/shorebird/shorebird_release_record.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/toolchain/flutter_resolver.dart';

/// What to patch with Shorebird.
class ShorebirdPatchInput extends Equatable {
  /// Creates the input. iOS needs [exportOptionsPlist].
  const new({
    required this.settings,
    required this.platform,
    required this.shorebirdAppId,
    this.exportOptionsPlist,
    this.allowNativeDiffs = false,
    this.tokenSecret,
    this.patchNumber,
  });

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
    final exportOptionsPlist = json['exportOptionsPlist'] == null
        ? null
        : requiredRelative(json, 'exportOptionsPlist');
    final problem = exportOptionsProblem(platform, exportOptionsPlist);
    if (problem != null) throw FormatException(problem);
    final number = json['patchNumber'];
    if (number != null && number is! int) {
      throw const FormatException('"patchNumber" must be a number.');
    }
    return ShorebirdPatchInput(
      settings: BuildSettings.fromJson(json),
      platform: platform,
      shorebirdAppId: requiredString(json, 'shorebirdAppId'),
      exportOptionsPlist: exportOptionsPlist,
      allowNativeDiffs: optionalFlag(json, 'allowNativeDiffs'),
      tokenSecret: optionalString(json, 'tokenSecret'),
      patchNumber: number as int?,
    );
  }

  /// Where and what to patch. Its `version` is the release being patched,
  /// build number included (a patch names an exact release, D-11); its
  /// Flutter pin is not used, the release's version is.
  final BuildSettings settings;

  /// The platform to patch.
  final ShorebirdPlatform platform;

  /// The Shorebird app id of the flavor.
  final String shorebirdAppId;

  /// The export options of the iOS archive, relative to the app.
  final String? exportOptionsPlist;

  /// Whether to publish even if Shorebird reports native changes
  /// (`--allow-native-diffs`, C:791-828). Not recommended.
  final bool allowNativeDiffs;

  /// The key in the secret store of the Shorebird API key, passed to the CLI
  /// as `SHOREBIRD_TOKEN`; `null` uses the login of the machine.
  final String? tokenSecret;

  /// The number XPath gives the patch (its tag is `-p<n>`), for the history
  /// of the release (U7b).
  final int? patchNumber;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    ...settings.toJson(),
    'platform': platform.wire,
    'shorebirdAppId': shorebirdAppId,
    'exportOptionsPlist': ?exportOptionsPlist,
    'allowNativeDiffs': allowNativeDiffs,
    'tokenSecret': ?tokenSecret,
    'patchNumber': ?patchNumber,
  };

  @override
  List<Object?> get props => [
    settings,
    platform,
    shorebirdAppId,
    exportOptionsPlist,
    allowNativeDiffs,
    tokenSecret,
    patchNumber,
  ];
}

/// What `shorebird.patch` published.
class ShorebirdPatchResult extends Equatable {
  /// Creates the result.
  const new({
    required this.releaseVersion,
    required this.flutter,
    required this.fromShorebird,
    this.dart,
  });

  /// The release that was patched, `x.y.z+build`.
  final String releaseVersion;

  /// The Flutter version of the release, which the patch was built with.
  final String flutter;

  /// The Dart version of that Flutter.
  final String? dart;

  /// Whether the Flutter version came from Shorebird's release data because
  /// XPath had no record of the release.
  final bool fromShorebird;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'releaseVersion': releaseVersion,
    'flutter': flutter,
    'dart': ?dart,
    'fromShorebird': fromShorebird,
  };

  @override
  List<Object?> get props => [releaseVersion, flutter, dart, fromShorebird];
}

/// Publishes an over-the-air patch of a Shorebird release (`shorebird.patch`,
/// C:791-828, O:621-704).
///
/// A patch must be built with the Flutter version of the release it patches
/// (D-20). The step looks it up in the record `shorebird.release` saved and,
/// for a release XPath did not make, in Shorebird's release data; it resolves
/// that exact SDK, records it as the Flutter version of the job, and runs
/// `shorebird patch --release-version`. The Shorebird CLI builds with the
/// Flutter revision of the release by itself and has no `--flutter-version`
/// option on `patch`, so none is passed. Without a known version the step
/// fails with a hint instead of building with whatever Flutter the app pins
/// today.
///
/// `shorebird patch ios` also builds an IPA, which carries the release's
/// build number; the step deletes it so nothing downstream uploads it
/// (C:806-815).
class ShorebirdPatchStep
    extends Step<ShorebirdPatchInput, ShorebirdPatchResult> {
  /// Creates the step. [isMacOS] tells whether this machine runs macOS.
  const new({
    required this.toolchain,
    required this.files,
    required this.releases,
    required this.records,
    required this.isMacOS,
    this.shorebirdExecutable = 'shorebird',
  });

  /// Resolves Flutter and records the tool versions.
  final BuildToolchain toolchain;

  /// The build output on disk.
  final BuildFiles files;

  /// What Shorebird knows about the releases of the app.
  final ShorebirdReleases releases;

  /// Where the Flutter version of each release is kept.
  final ShorebirdReleaseRepository records;

  /// Whether this machine runs macOS.
  final bool isMacOS;

  /// The Shorebird CLI.
  final String shorebirdExecutable;

  @override
  String get kind => 'shorebird.patch';

  @override
  bool sideEffectOf(ShorebirdPatchInput input) => true;

  @override
  ShorebirdPatchInput decodeInput(Map<String, dynamic> json) =>
      ShorebirdPatchInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(ShorebirdPatchInput input) => input.toJson();

  @override
  Map<String, dynamic> encodeResult(ShorebirdPatchResult result) =>
      result.toJson();

  @override
  Future<StepOutcome<ShorebirdPatchResult>> run(
    ShorebirdPatchInput input,
    StepContext context,
  ) async {
    final platform = input.platform;
    if (platform == ShorebirdPlatform.ios && !isMacOS) {
      return const StepFailed(
        'shorebird.patch for iOS needs macOS (ios-sign): this machine cannot '
        'run Xcode. Run the job on a Mac.',
      );
    }
    final settings = input.settings;
    final release = settings.version;
    final known = await _flutterVersionOf(input);
    if (known == null) {
      return StepFailed(
        'The Flutter version of release $release is not known: XPath has no '
        'record of it and Shorebird lists none. A patch must be built with the '
        'version of its release. Fix: check that $release exists for '
        '${input.shorebirdAppId} (shorebird releases list), or run the release '
        'through XPath.',
      );
    }
    final ResolvedFlutter flutter;
    try {
      flutter = await toolchain.prepare(context.jobId, known.version);
    } on ToolchainException catch (error) {
      return StepFailed(error.message);
    }

    final exit = await context.run(
      shorebirdCommand(
        shorebirdExecutable,
        withForwarded(_arguments(input), forwardedArguments(settings)),
        settings: settings,
        platform: platform,
        tokenSecret: input.tokenSecret,
      ),
    );
    if (platform == ShorebirdPlatform.ios) {
      await files.deleteAll(
        '${settings.appDirectory}/build/ios/ipa',
        extension: '.ipa',
      );
    }
    if (exit.cancelled) {
      return const StepFailed('The Shorebird patch was cancelled.');
    }
    if (!exit.succeeded) {
      return StepFailed(
        'shorebird patch ${platform.wire} exited with code ${exit.exitCode}. '
        'The step log has its output.',
      );
    }
    return StepSucceeded(
      ShorebirdPatchResult(
        releaseVersion: '$release',
        flutter: flutter.version,
        dart: flutter.dartVersion,
        fromShorebird: known.fromShorebird,
      ),
    );
  }

  List<String> _arguments(ShorebirdPatchInput input) {
    final settings = input.settings;
    return [
      'patch',
      input.platform.wire,
      '--release-version=${settings.version}',
      if (settings.flavor != null) ...['--flavor', settings.flavor!],
      if (settings.target != null) ...['--target', settings.target!],
      if (input.exportOptionsPlist != null)
        '--export-options-plist=${input.exportOptionsPlist}',
      if (settings.obfuscate)
        '--split-debug-info=${shorebirdDebugInfoDirectory(input.platform)}',
      if (input.allowNativeDiffs) '--allow-native-diffs',
    ];
  }

  /// The Flutter version of the release: XPath's record, else Shorebird's
  /// data.
  Future<({String version, bool fromShorebird})?> _flutterVersionOf(
    ShorebirdPatchInput input,
  ) async {
    final release = input.settings.version;
    final record = await records.find(
      input.shorebirdAppId,
      release,
      input.platform,
    );
    if (record != null) {
      return (version: record.flutterVersion, fromShorebird: false);
    }
    final listed = await releases.releases(
      input.shorebirdAppId,
      tokenSecret: input.tokenSecret,
    );
    final flutter = listed
        ?.where((candidate) => candidate.version == release)
        .firstOrNull
        ?.flutterVersion;
    return flutter == null ? null : (version: flutter, fromShorebird: true);
  }
}
