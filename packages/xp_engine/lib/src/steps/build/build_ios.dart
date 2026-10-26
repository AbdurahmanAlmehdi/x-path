import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/process/process_supervisor.dart';
import 'package:xp_engine/src/steps/build/build_outputs.dart';
import 'package:xp_engine/src/steps/build/build_result.dart';
import 'package:xp_engine/src/steps/build/build_settings.dart';
import 'package:xp_engine/src/steps/build/build_toolchain.dart';
import 'package:xp_engine/src/steps/build/dart_defines.dart';
import 'package:xp_engine/src/steps/build/flutter_build_step.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/toolchain/flutter_resolver.dart';
import 'package:xp_engine/src/toolchain/ios_linux_toolchain.dart';

/// What to build for iOS.
class BuildIosInput extends Equatable {
  /// Creates the input.
  const new({
    required this.settings,
    required this.exportOptionsPlist,
    this.linuxSigning = const {},
  });

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if [json] is not a valid input.
  factory fromJson(Map<String, dynamic> json) => BuildIosInput(
    settings: BuildSettings.fromJson(json),
    exportOptionsPlist: requiredRelative(json, 'exportOptionsPlist'),
    linuxSigning: stringMap(json, 'linuxSigning'),
  );

  /// Where and what to build.
  final BuildSettings settings;

  /// The export options (`--export-options-plist`), relative to the app. It
  /// names the signing team and the provisioning profiles of the flavor.
  final String exportOptionsPlist;

  /// What a Linux runner signs with, by the variable omarchy-apple-dev reads:
  /// the secret keys of the Apple Distribution identity, its certificate and
  /// the App Store profile the engine makes (ADR 0014). Empty when the
  /// flavor cannot sign on Linux; a Mac signs with its keychain either way.
  final Map<String, String> linuxSigning;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    ...settings.toJson(),
    'exportOptionsPlist': exportOptionsPlist,
    if (linuxSigning.isNotEmpty) 'linuxSigning': linuxSigning,
  };

  @override
  List<Object?> get props => [settings, exportOptionsPlist, linuxSigning];
}

/// What `build.ios` builds with on a Linux runner (ADR 0014).
class IosLinuxBuilds {
  /// Creates the pair.
  const new({required this.toolchain, required this.checkout});

  /// Resolves the Flutter installs dedicated to Linux iOS builds (under
  /// [IosLinuxToolchain.installs]) and records the job's tools.
  final BuildToolchain toolchain;

  /// The omarchy-apple-dev checkout and what the installs are ready for.
  final IosLinuxToolchain checkout;
}

/// Builds the release IPA of a flavor (`build.ios`, C:670-712, O:500-540).
///
/// The backend depends on the host (ADR 0014, amending D-20):
///
/// - **macOS** runs `flutter build ipa --release --export-options-plist`.
/// - **Linux, with [linux]** runs omarchy-apple-dev: `flutter/setup.sh` once
///   per Flutter version in an install of its own, `flutter/build.sh`, then
///   `flutter/ship.sh` without `--upload`, which signs with the Apple
///   Distribution identity and the App Store profile in `linuxSigning`. The
///   build name and number, the dart defines (as `KEY=VALUE` arguments),
///   obfuscation, the export options and `ios/Runner/Runner.entitlements` are
///   mapped onto that interface. The IPA is
///   `build/ios-linux/Runner-store.ipa`.
///
/// Any other machine fails the step, which is what the `ios-sign` and
/// `ios-linux` capabilities of a runner are for (D-19).
class BuildIosStep extends FlutterBuildStep<BuildIosInput> {
  /// Creates the step. [isMacOS] tells whether this machine runs macOS;
  /// [linux] is set on a Linux runner set up for iOS builds.
  const new({
    required super.toolchain,
    required super.files,
    required super.recorder,
    required super.repository,
    required super.store,
    required this.isMacOS,
    this.linux,
  });

  /// Whether this machine runs macOS.
  final bool isMacOS;

  /// How this Linux machine builds iOS apps, if it can.
  final IosLinuxBuilds? linux;

  /// The entitlements `flutter/ship.sh` requests, when the app has them.
  static const _entitlements = 'ios/Runner/Runner.entitlements';

  @override
  String get kind => 'build.ios';

  @override
  String get platform => 'ios';

  @override
  String? get unsupportedReason => isMacOS || linux != null
      ? null
      : 'build.ios needs macOS (ios-sign), or a Linux runner set up for iOS '
            'builds (ios-linux): this machine is neither. Run the job on a '
            'Mac.';

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

  @override
  Future<StepOutcome<BuildResult>> run(
    BuildIosInput input,
    StepContext context,
  ) {
    final linux = this.linux;
    return isMacOS || linux == null
        ? super.run(input, context)
        : _runOnLinux(input, context, linux);
  }

  Future<StepOutcome<BuildResult>> _runOnLinux(
    BuildIosInput input,
    StepContext context,
    IosLinuxBuilds linux,
  ) async {
    final settings = input.settings;
    if (input.linuxSigning.isEmpty) {
      return const StepFailed(
        'The flavor has no Apple Distribution identity with an App Store '
        'Connect API key, so a Linux runner cannot sign the build.',
      );
    }
    final commit = await linux.checkout.commit();
    final ResolvedFlutter flutter;
    final List<String> defines;
    try {
      flutter = await linux.toolchain.prepare(
        context.jobId,
        settings.flutterVersion,
        iosLinux:
            'Linux, omarchy-apple-dev ${commit ?? 'at an unknown commit'}',
      );
      defines = await _defines(settings);
    } on ToolchainException catch (error) {
      return StepFailed(error.message);
    } on FormatException catch (error) {
      return StepFailed(error.message);
    }
    final scripts = _Scripts(context, linux.checkout.directory, settings, {
      'CI': 'true',
      'FLUTTER': flutter.flutterExecutable,
    });
    if (!await linux.checkout.isPrepared(flutter.path)) {
      if (await scripts.run('setup.sh') case final failed?) return failed;
      if (!await linux.checkout.isPrepared(flutter.path)) {
        return StepFailed(
          'flutter/setup.sh finished, but the iOS gen_snapshot of '
          '${flutter.path} is still not the Linux build.',
        );
      }
    }
    await linux.checkout.markUsed(flutter.path);

    final app = settings.appDirectory;
    final debugInfo = debugInfoOf(settings);
    final since = await files.markBuildStart();
    final built = await scripts.run(
      'build.sh',
      arguments: [app, ...defines],
      environment: {
        'BUILD_NAME': '${settings.version.name}',
        'BUILD_NUMBER': '${settings.build}',
        if (debugInfo != null) ...{
          'SPLIT_DEBUG_INFO': debugInfo,
          'DART_OBFUSCATION': 'true',
        },
      },
    );
    if (built != null) return built;
    final shipped = await scripts.run(
      'ship.sh',
      arguments: [app],
      environment: {
        'BUILD_NUMBER': '${settings.build}',
        'ASC_EXPORT_OPTIONS': '$app/${input.exportOptionsPlist}',
        if (await files.stat('$app/$_entitlements') != null)
          'ASC_ENTITLEMENTS_PATH': '$app/$_entitlements',
      },
      secretFiles: input.linuxSigning,
    );
    if (shipped != null) return shipped;
    return await keep(
      input,
      context,
      found: await BuildOutputs(files).iosLinux(app, since: since),
      flutter: flutter,
      missing: 'flutter/ship.sh succeeded but left no $iosLinuxIpaPath.',
    );
  }

  /// The dart defines of the build as `flutter/build.sh` takes them:
  /// `KEY=VALUE` arguments.
  ///
  /// Throws a [FormatException] if the define file is missing or not one.
  Future<List<String>> _defines(BuildSettings settings) async {
    final name = settings.dartDefineFile;
    if (name == null) return const [];
    final path = '${settings.appDirectory}/$name';
    if (await files.stat(path) == null) {
      throw FormatException('There is no define file $name in the app.');
    }
    final text = await utf8.decodeStream(files.open(path));
    return [
      for (final MapEntry(:key, :value) in parseDartDefines(text).entries)
        '$key=$value',
    ];
  }
}

/// omarchy-apple-dev's Flutter scripts in the checkout [directory], run in
/// the app being built with the variables of the runner they read.
class _Scripts {
  const new(this._context, this.directory, this._settings, this._environment);

  /// Variables of the runner's environment omarchy-apple-dev reads, besides
  /// the ones every step gets.
  static const _passThrough = [
    'XDG_CONFIG_HOME',
    'DARWIN_SDK_BUNDLE',
    'FLUTTER_IOS_WORK',
    'PUB_CACHE',
    'PUB_HOSTED_URL',
    'FLUTTER_STORAGE_BASE_URL',
  ];

  final StepContext _context;
  final String directory;
  final BuildSettings _settings;
  final Map<String, String> _environment;

  /// Runs `flutter/[name]`; `null` if it succeeded, else why the step fails.
  Future<StepFailed?> run(
    String name, {
    List<String> arguments = const [],
    Map<String, String> environment = const {},
    Map<String, String> secretFiles = const {},
  }) async {
    final exit = await _context.run(
      ProcessCommand(
        '$directory/flutter/$name',
        arguments: arguments,
        workingDirectory: _settings.appDirectory,
        environment: {..._environment, ...environment},
        passThroughEnvironment: [
          ..._passThrough,
          ..._settings.passThroughEnvironment,
        ],
        secretFiles: secretFiles,
      ),
    );
    if (exit.cancelled) return const StepFailed('The build was cancelled.');
    return exit.succeeded
        ? null
        : StepFailed(
            "omarchy-apple-dev's flutter/$name exited with code "
            '${exit.exitCode}. The step log has its output.',
          );
  }
}
