import 'package:xp_engine/src/steps/build/build_settings.dart';
import 'package:xp_engine/src/steps/shorebird/shorebird_release_record.dart';
import 'package:xp_engine/src/steps/step_context.dart';

/// The variable the Shorebird CLI reads its API key from (`sb_api_*`, D-20).
const shorebirdTokenVariable = 'SHOREBIRD_TOKEN';

/// Where an obfuscated Shorebird build leaves its debug info, relative to the
/// app (the same place `build.android` and `build.ios` use).
String shorebirdDebugInfoDirectory(ShorebirdPlatform platform) =>
    'build/xpath/debug-info/${platform.wire}';

/// The variables of the engine's environment that Shorebird's own `flutter
/// build` needs on [platform].
List<String> shorebirdEnvironmentNames(ShorebirdPlatform platform) => [
  ...switch (platform) {
    ShorebirdPlatform.android => const [
      'ANDROID_HOME',
      'ANDROID_SDK_ROOT',
      'ANDROID_USER_HOME',
      'JAVA_HOME',
      'GRADLE_USER_HOME',
      'GRADLE_OPTS',
    ],
    ShorebirdPlatform.ios => const ['DEVELOPER_DIR'],
  },
  'PUB_CACHE',
  'PUB_HOSTED_URL',
  'FLUTTER_STORAGE_BASE_URL',
];

/// What Shorebird passes on to `flutter build`: the arguments after `--`.
///
/// The app's own flags go there, as `shorebird release --help` documents.
List<String> forwardedArguments(BuildSettings settings) => [
  if (settings.dartDefineFile != null)
    '--dart-define-from-file=${settings.dartDefineFile}',
  if (settings.obfuscate) '--obfuscate',
];

/// [arguments] followed by `--` and [forwarded], when there is anything to
/// forward.
List<String> withForwarded(List<String> arguments, List<String> forwarded) => [
  ...arguments,
  if (forwarded.isNotEmpty) ...['--', ...forwarded],
];

/// The `shorebird` command for [arguments].
///
/// The CLI runs without prompts (`CI`). The API key travels as the secret
/// [shorebirdTokenVariable], never as an argument; [tokenSecret] is its key
/// in the secret store.
ProcessCommand shorebirdCommand(
  String executable,
  List<String> arguments, {
  required BuildSettings settings,
  required ShorebirdPlatform platform,
  required String? tokenSecret,
}) => ProcessCommand(
  executable,
  arguments: arguments,
  workingDirectory: settings.appDirectory,
  environment: const {'CI': 'true'},
  passThroughEnvironment: [
    ...shorebirdEnvironmentNames(platform),
    ...settings.passThroughEnvironment,
  ],
  secretEnvironment: {
    ...settings.secretEnvironment,
    shorebirdTokenVariable: ?tokenSecret,
  },
  secretFiles: settings.secretFiles,
);

/// The first problem with the pair of [platform] and [exportOptionsPlist],
/// or `null`.
String? exportOptionsProblem(
  ShorebirdPlatform platform,
  String? exportOptionsPlist,
) => platform == ShorebirdPlatform.ios && exportOptionsPlist == null
    ? '"exportOptionsPlist" is needed to release or patch iOS.'
    : null;
