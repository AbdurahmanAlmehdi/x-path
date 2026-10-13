import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/steps/build/build_outputs.dart';
import 'package:xp_engine/src/steps/build/build_settings.dart';
import 'package:xp_engine/src/steps/build/flutter_build_step.dart';

/// What to build for iOS.
class BuildIosInput extends Equatable {
  /// Creates the input.
  const new({required this.settings, required this.exportOptionsPlist});

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if [json] is not a valid input.
  factory fromJson(Map<String, dynamic> json) => BuildIosInput(
    settings: BuildSettings.fromJson(json),
    exportOptionsPlist: requiredRelative(json, 'exportOptionsPlist'),
  );

  /// Where and what to build.
  final BuildSettings settings;

  /// The export options (`--export-options-plist`), relative to the app. It
  /// names the signing team and the provisioning profiles of the flavor.
  final String exportOptionsPlist;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    ...settings.toJson(),
    'exportOptionsPlist': exportOptionsPlist,
  };

  @override
  List<Object?> get props => [settings, exportOptionsPlist];
}

/// Builds the release IPA of a flavor (`build.ios`, C:670-712, O:500-540).
///
/// Runs `flutter build ipa --release --export-options-plist`. Only a Mac can
/// do it: the step fails on any other machine, which is what the `ios-sign`
/// capability of a runner is for (D-19).
class BuildIosStep extends FlutterBuildStep<BuildIosInput> {
  /// Creates the step. [isMacOS] tells whether this machine runs macOS.
  const new({
    required super.toolchain,
    required super.files,
    required super.recorder,
    required super.repository,
    required super.store,
    required this.isMacOS,
  });

  /// Whether this machine runs macOS.
  final bool isMacOS;

  @override
  String get kind => 'build.ios';

  @override
  String get platform => 'ios';

  @override
  String? get unsupportedReason => isMacOS
      ? null
      : 'build.ios needs macOS (ios-sign): this machine cannot run Xcode. Run '
            'the job on a Mac.';

  @override
  BuildIosInput decodeInput(Map<String, dynamic> json) =>
      BuildIosInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(BuildIosInput input) => input.toJson();

  @override
  BuildSettings settingsOf(BuildIosInput input) => input.settings;

  @override
  ArtifactKind artifactKindOf(BuildIosInput input) => ArtifactKind.ipa;

  @override
  String subcommandOf(BuildIosInput input) => 'ipa';

  @override
  List<String> platformArguments(BuildIosInput input) => [
    '--export-options-plist=${input.exportOptionsPlist}',
  ];

  /// Xcode is found through `DEVELOPER_DIR`.
  @override
  List<String> get environmentNames => const [
    'DEVELOPER_DIR',
    'PUB_CACHE',
    'PUB_HOSTED_URL',
    'FLUTTER_STORAGE_BASE_URL',
  ];

  /// Clears the folder the IPA is exported to. The IPA is named after the
  /// app, not the flavor, so an earlier build leaves its own beside the new
  /// one, and nothing downstream can tell them apart (C:670-712).
  @override
  Future<void> prepareOutputs(String appDirectory) =>
      files.deleteAll('$appDirectory/build/ios/ipa', extension: '.ipa');

  @override
  Future<BuiltFile> locate(
    BuildIosInput input,
    String appDirectory, {
    required DateTime since,
  }) => BuildOutputs(files).ios(appDirectory, since: since);
}
