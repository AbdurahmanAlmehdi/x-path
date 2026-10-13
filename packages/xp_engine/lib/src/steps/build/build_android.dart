import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/steps/build/build_outputs.dart';
import 'package:xp_engine/src/steps/build/build_settings.dart';
import 'package:xp_engine/src/steps/build/flutter_build_step.dart';

/// What to build for Android.
class BuildAndroidInput extends Equatable {
  /// Creates the input. [artifact] is [ArtifactKind.apk] or
  /// [ArtifactKind.aab].
  const new({required this.settings, this.artifact = ArtifactKind.apk})
    : assert(
        artifact == ArtifactKind.apk || artifact == ArtifactKind.aab,
        'Android builds an apk or an aab.',
      );

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if [json] is not a valid input.
  factory fromJson(Map<String, dynamic> json) {
    final artifact = optionalString(json, 'artifact') ?? 'apk';
    if (artifact != 'apk' && artifact != 'aab') {
      throw FormatException(
        '"artifact" must be "apk" or "aab", not $artifact.',
      );
    }
    return BuildAndroidInput(
      settings: BuildSettings.fromJson(json),
      artifact: artifact == 'apk' ? ArtifactKind.apk : ArtifactKind.aab,
    );
  }

  /// Where and what to build.
  final BuildSettings settings;

  /// The package to build: an APK for direct installs and Firebase App
  /// Distribution, or an AAB for Google Play.
  final ArtifactKind artifact;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    ...settings.toJson(),
    'artifact': artifact.wire,
  };

  @override
  List<Object?> get props => [settings, artifact];
}

/// Builds the release APK or AAB of a flavor (`build.android`, C:621-668,
/// O:455-496).
///
/// Runs `flutter build apk|appbundle --release` with the flavor, the target,
/// the build name and number, and the signing secrets in environment variables
/// or files. The file it produced is copied into the artifact store.
class BuildAndroidStep extends FlutterBuildStep<BuildAndroidInput> {
  /// Creates the step.
  const new({
    required super.toolchain,
    required super.files,
    required super.recorder,
    required super.repository,
    required super.store,
  });

  @override
  String get kind => 'build.android';

  @override
  String get platform => 'android';

  @override
  BuildAndroidInput decodeInput(Map<String, dynamic> json) =>
      BuildAndroidInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(BuildAndroidInput input) => input.toJson();

  @override
  BuildSettings settingsOf(BuildAndroidInput input) => input.settings;

  @override
  ArtifactKind artifactKindOf(BuildAndroidInput input) => input.artifact;

  @override
  String subcommandOf(BuildAndroidInput input) =>
      input.artifact == ArtifactKind.aab ? 'appbundle' : 'apk';

  @override
  List<String> platformArguments(BuildAndroidInput input) => const [];

  /// The Android SDK and the JDK are found through these.
  @override
  List<String> get environmentNames => const [
    'ANDROID_HOME',
    'ANDROID_SDK_ROOT',
    'ANDROID_USER_HOME',
    'JAVA_HOME',
    'GRADLE_USER_HOME',
    'GRADLE_OPTS',
    'PUB_CACHE',
    'PUB_HOSTED_URL',
    'FLUTTER_STORAGE_BASE_URL',
  ];

  @override
  Future<BuiltFile> locate(
    BuildAndroidInput input,
    String appDirectory, {
    required DateTime since,
  }) => BuildOutputs(files).android(
    appDirectory,
    kind: input.artifact,
    flavor: input.settings.flavor,
    since: since,
  );
}
