import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_engine/xp_engine.dart';

/// A Linux runner's omarchy-apple-dev checkout and its dedicated Flutter
/// installs, on disk (ADR 0014).
///
/// An install is ready when its iOS `gen_snapshot` is an ELF file, which is
/// what `flutter/setup.sh` leaves. Each job that builds with an install
/// writes the time into `.xpath-last-used` in it; installs no job used for
/// [keepFor] are deleted then, since each holds a whole Flutter SDK.
class DirectoryIosLinuxToolchain implements IosLinuxToolchain {
  /// Creates the toolchain of the checkout [directory], with its installs
  /// under [installs].
  const new({
    required this.directory,
    required this.installs,
    required this._runner,
    required this._clock,
    this.keepFor = const Duration(days: 30),
  });

  @override
  final String directory;

  @override
  final String installs;

  /// How long an install no job used is kept.
  final Duration keepFor;

  final ProcessRunner _runner;
  final Clock _clock;

  static const _lastUsed = '.xpath-last-used';

  /// Where `flutter/setup.sh` puts the Linux-hosted `gen_snapshot`.
  static const genSnapshot =
      'bin/cache/artifacts/engine/ios-release/gen_snapshot_arm64';

  @override
  Future<String?> commit() async {
    try {
      final output = await _runner.run('git', [
        '-C',
        directory,
        'rev-parse',
        'HEAD',
      ]);
      final sha = output.stdout.trim();
      return output.exitCode == 0 && sha.isNotEmpty ? sha : null;
    } on ProcessStartException {
      return null;
    }
  }

  @override
  Future<bool> isPrepared(String flutterRoot) async {
    final file = File(p.join(flutterRoot, genSnapshot));
    if (!file.existsSync()) return false;
    final handle = file.openSync();
    try {
      return _isElf(handle.readSync(4));
    } finally {
      handle.closeSync();
    }
  }

  static bool _isElf(List<int> head) =>
      head.length == 4 &&
      head[0] == 0x7f &&
      head[1] == 0x45 &&
      head[2] == 0x4c &&
      head[3] == 0x46;

  @override
  Future<void> markUsed(String flutterRoot) async {
    final now = _clock.now();
    File(p.join(flutterRoot, _lastUsed))
        .writeAsStringSync(now.toIso8601String());
    final root = Directory(installs);
    if (!root.existsSync()) return;
    for (final install in root.listSync().whereType<Directory>()) {
      final name = p.basename(install.path);
      if (name.startsWith('.') || p.equals(install.path, flutterRoot)) {
        continue;
      }
      final marker = File(p.join(install.path, _lastUsed));
      final used = marker.existsSync()
          ? DateTime.tryParse(marker.readAsStringSync().trim())
          : null;
      if (now.difference(used ?? install.statSync().modified) > keepFor) {
        await install.delete(recursive: true);
      }
    }
  }
}
