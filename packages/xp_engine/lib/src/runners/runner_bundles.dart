import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/runners/runner_exceptions.dart';

final _part = RegExp(r'^[a-z0-9_]{1,32}$');

/// The machine a runner bundle is for: the operating system and the processor
/// architecture the runner reports in its `hello`, for example `linux` and
/// `arm64`.
///
/// Both are plain lower case words, so a target is safe to use as a folder
/// name (`linux-arm64`).
class RunnerBundleTarget extends Equatable {
  const new _(this.os, this.arch);

  /// Reads the target from the [os] and [arch] a runner asked for.
  ///
  /// Throws a [RunnerInvalidException] for a missing or odd value.
  factory parse(String? os, String? arch) {
    if (os == null || arch == null) {
      throw const RunnerInvalidException(
        'Give the os and the arch of the runner, for example '
        '?os=linux&arch=arm64.',
      );
    }
    if (!_part.hasMatch(os) || !_part.hasMatch(arch)) {
      throw const RunnerInvalidException(
        'os and arch are lower case words of letters, digits and '
        'underscores, for example macos and arm64.',
      );
    }
    return RunnerBundleTarget._(os, arch);
  }

  /// The operating system, for example `macos` or `linux`.
  final String os;

  /// The processor architecture, for example `arm64` or `x86_64`.
  final String arch;

  /// The name of the folder that holds the bundle of this target.
  String get folderName => '$os-$arch';

  @override
  List<Object?> get props => [os, arch];

  @override
  String toString() => folderName;
}

/// A runner bundle the engine can send: the `xp` bundle of the engine's own
/// version for one [RunnerBundleTarget], as one `.tar.gz`.
class RunnerBundle {
  /// Creates the bundle.
  const new({required this.sha256, required this.size, required this.open});

  /// The SHA-256 of the file, in lowercase hexadecimal.
  final String sha256;

  /// The size of the file in bytes.
  final int size;

  /// Opens the file for reading; each call starts at the first byte.
  final Stream<List<int>> Function() open;
}

/// The engine has no runner bundle for the target asked for.
class RunnerBundleMissingException extends RunnerException {
  /// Creates an exception with [message], which says where the bundle goes.
  const new(super.message);

  @override
  String toString() => 'RunnerBundleMissingException: $message';
}

/// Where the engine finds the runner bundles it hands to runners that have to
/// update (D-24). The bundles are those of the engine's own version: a runner
/// updates to the version of the engine it works for.
abstract interface class RunnerBundles {
  /// The bundle for [target].
  ///
  /// Throws a [RunnerBundleMissingException] if there is none.
  Future<RunnerBundle> find(RunnerBundleTarget target);
}

/// [RunnerBundles] over files held in memory, for tests.
class InMemoryRunnerBundles implements RunnerBundles {
  /// The bundles' bytes, by [RunnerBundleTarget.folderName].
  final files = <String, List<int>>{};

  @override
  Future<RunnerBundle> find(RunnerBundleTarget target) async {
    final bytes = files[target.folderName];
    if (bytes == null) {
      throw RunnerBundleMissingException(
        'There is no runner bundle for ${target.folderName}.',
      );
    }
    return RunnerBundle(
      sha256: sha256.convert(bytes).toString(),
      size: bytes.length,
      open: () => Stream.value(bytes),
    );
  }
}
