import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/process/process_runner.dart';
import 'package:xp_engine/src/process/process_supervisor.dart';
import 'package:xp_engine/src/toolchain/flutter_installer.dart';
import 'package:xp_engine/src/toolchain/flutter_version.dart';
import 'package:xp_engine/src/toolchain/version_parsers.dart';

/// Where a resolved Flutter SDK comes from.
enum FlutterSource {
  /// The cache of fvm.
  fvm,

  /// XPath's own cache, `<data-dir>/toolchains/flutter`.
  cache,
}

/// A Flutter SDK a job can build with.
class ResolvedFlutter extends Equatable {
  /// Creates a resolved SDK.
  const new({
    required this.path,
    required this.version,
    required this.source,
    this.dartVersion,
    this.wasInstalled = false,
  });

  /// The SDK folder; run `<path>/bin/flutter`.
  final String path;

  /// The Flutter version it reports, for example `3.47.6`.
  final String version;

  /// The Dart version that comes with it.
  final String? dartVersion;

  /// Whose cache it is in.
  final FlutterSource source;

  /// Whether this resolution had to download it.
  final bool wasInstalled;

  /// The Flutter executable.
  String get flutterExecutable => '$path/bin/flutter';

  @override
  List<Object?> get props => [path, version, dartVersion, source, wasInstalled];
}

/// Why a Flutter SDK could not be resolved.
enum FlutterResolutionFailure {
  /// The app has no `.fvmrc` pin.
  noPin,

  /// The pin cannot be used.
  invalidPin,

  /// The SDK could not be downloaded.
  installFailed,

  /// The SDK in XPath's cache does not work.
  brokenCache,
}

/// No Flutter SDK can be found for the pin; [fix] says what the owner can do.
class FlutterResolutionException extends ToolchainException {
  /// Creates an exception.
  const new(this.failure, String message, this.fix)
    : super('flutter', '$message $fix');

  /// What went wrong.
  final FlutterResolutionFailure failure;

  /// What to do about it.
  final String fix;
}

/// Finds the Flutter SDK for an app's pinned version (D-20).
///
/// The pin comes from `.fvmrc`. If fvm is installed it is used: the SDK it has
/// cached, or one it installs. Without fvm, or if fvm cannot install the
/// version, XPath's own cache is used, and the SDK is downloaded into it when
/// it is not there.
///
/// A Shorebird patch asks for the version that was recorded for the release
/// instead of the current pin.
class FlutterResolver {
  /// Creates a resolver.
  ///
  /// [fvmExecutable] is the fvm to use. [commandTimeout] is how long fvm and
  /// `flutter --version` have to answer; [fvmInstallTimeout] how long fvm has
  /// to install an SDK.
  const new({
    required this._runner,
    required this._installer,
    this.fvmExecutable = 'fvm',
    this.commandTimeout = const Duration(minutes: 2),
    this.fvmInstallTimeout = const Duration(minutes: 30),
  });

  /// The fvm program.
  final String fvmExecutable;

  /// How long a query has to answer.
  final Duration commandTimeout;

  /// How long `fvm install` may take.
  final Duration fvmInstallTimeout;

  final ProcessRunner _runner;
  final FlutterInstaller _installer;

  /// The SDK of [version], the pin read from [pinSource] (a path in the
  /// repository, for the messages).
  ///
  /// A `null` [version] with a [pinSource] is a pin file that could not be
  /// read; without one the app has no pin.
  ///
  /// Throws a [FlutterResolutionException].
  Future<ResolvedFlutter> resolve(String? version, {String? pinSource}) async {
    if (version == null) {
      throw pinSource == null
          ? const FlutterResolutionException(
              FlutterResolutionFailure.noPin,
              'The app does not pin a Flutter version.',
              'Add a .fvmrc with {"flutter": "x.y.z"} to the app or to the '
                  'repository root.',
            )
          : FlutterResolutionException(
              FlutterResolutionFailure.invalidPin,
              '$pinSource does not say which Flutter version to use.',
              'Write it as {"flutter": "x.y.z"}.',
            );
    }
    if (!isFlutterPinName(version)) {
      throw FlutterResolutionException(
        FlutterResolutionFailure.invalidPin,
        '"$version" is not a Flutter version.',
        'Pin an exact version such as 3.47.6 in ${pinSource ?? '.fvmrc'}.',
      );
    }
    final fromFvm = await _fromFvm(version);
    if (fromFvm != null) return fromFvm;
    if (!isExactFlutterVersion(version)) {
      throw FlutterResolutionException(
        FlutterResolutionFailure.invalidPin,
        'fvm is not available and "$version" is not an exact Flutter version, '
            'which is the only kind XPath downloads.',
        'Pin an exact version such as 3.47.6 in ${pinSource ?? '.fvmrc'}, or '
            'install fvm.',
      );
    }
    return await _fromCache(version);
  }

  Future<ResolvedFlutter?> _fromFvm(String version) async {
    // No list means no fvm, or one that does not speak `fvm api`.
    final list = await _fvmList();
    if (list == null) return null;
    var cached = _find(list, version);
    if (cached == null) {
      final installed = await _try(
        () => _runner.run(fvmExecutable, [
          'install',
          version,
        ], timeout: fvmInstallTimeout),
      );
      if (installed == null || installed.exitCode != 0) return null;
      cached = _find(await _fvmList() ?? const [], version);
      if (cached == null) return null;
    }
    return ResolvedFlutter(
      path: cached.directory,
      version: cached.flutterVersion ?? version,
      dartVersion: cached.dartVersion,
      source: FlutterSource.fvm,
    );
  }

  static FvmVersion? _find(List<FvmVersion> list, String name) =>
      list.where((entry) => entry.name == name).firstOrNull;

  Future<List<FvmVersion>?> _fvmList() async {
    final output = await _try(
      () =>
          _runner.run(fvmExecutable, ['api', 'list'], timeout: commandTimeout),
    );
    if (output == null || output.exitCode != 0) return null;
    return parseFvmList(output.stdout);
  }

  Future<ResolvedFlutter> _fromCache(String version) async {
    final path = _installer.pathFor(version);
    var installed = false;
    if (!await _installer.isInstalled(version)) {
      try {
        await _installer.install(version);
      } on FlutterInstallException catch (error) {
        throw FlutterResolutionException(
          FlutterResolutionFailure.installFailed,
          'Flutter $version could not be downloaded: ${error.message}',
          'Check the network, or install fvm and run fvm install $version.',
        );
      }
      installed = true;
    }
    final output = await _try(
      () => _runner.run('$path/bin/flutter', [
        '--version',
        '--machine',
      ], timeout: commandTimeout),
    );
    final versions = output == null || output.exitCode != 0
        ? null
        : parseFlutterMachineVersion(output.stdout);
    if (versions == null || versions.flutter != version) {
      throw FlutterResolutionException(
        FlutterResolutionFailure.brokenCache,
        'The Flutter SDK in $path does not report version $version.',
        'Delete $path and run the job again.',
      );
    }
    return ResolvedFlutter(
      path: path,
      version: versions.flutter,
      dartVersion: versions.dart,
      source: FlutterSource.cache,
      wasInstalled: installed,
    );
  }

  /// The output of [run], or `null` if the program is missing or too slow.
  Future<ProcessOutput?> _try(Future<ProcessOutput> Function() run) async {
    try {
      return await run();
    } on ProcessStartException {
      return null;
    } on TimeoutException {
      return null;
    }
  }
}
