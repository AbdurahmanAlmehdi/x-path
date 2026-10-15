import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp_engine/xp_engine.dart';

final _version = RegExp(r'^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$');

/// Whether [version] is fit to be the name of a folder: the engine sends it,
/// so it is never trusted as a path.
bool isVersionName(String version) => _version.hasMatch(version);

/// The bundles of `xp` a runner has installed: one folder per version in
/// `versions/`, and `current`, the symlink the service starts through (D-24).
///
/// An update unpacks the new bundle beside the running one and then moves the
/// link in one step, so the service always starts a complete bundle, and the
/// version before stays for a rollback.
class RunnerVersions {
  /// Creates the view of the versions under [_paths].
  const new(this._paths);

  final RunnerPaths _paths;

  /// The version `current` points at, or `null` when there is no link (a
  /// runner started from a bundle that is not installed here).
  String? currentVersion() {
    final link = Link(_paths.currentLink);
    if (!link.existsSync()) return null;
    return p.basename(link.targetSync());
  }

  /// Whether the bundle of [version] is installed.
  bool has(String version) =>
      isVersionName(version) &&
      File(p.join(_paths.versionDirectory(version), 'bin', 'xp')).existsSync();

  /// Copies the bundle at [bundle] (a folder with `bin/xp` and `lib/`) to
  /// `versions/<version>`, by way of a temporary folder: a copy that breaks
  /// off is never taken for an installed version.
  Future<void> adopt({
    required String bundle,
    required String version,
    required ProcessRunner runner,
  }) async {
    final target = _paths.versionDirectory(version);
    final partial = '$target.partial';
    _delete(partial);
    Directory(partial).createSync(recursive: true);
    final copy = await runner.run('cp', [
      '-R',
      '$bundle${p.separator}.',
      partial,
    ]);
    if (copy.exitCode != 0) {
      _delete(partial);
      throw FileSystemException(
        'Cannot copy the bundle $bundle: ${copy.stderr.trim()}',
        target,
      );
    }
    _delete(target);
    Directory(partial).renameSync(target);
  }

  /// Moves the unpacked bundle in [unpacked] to `versions/<version>`,
  /// replacing the folder of that version.
  void install(String unpacked, String version) {
    final target = _paths.versionDirectory(version);
    Directory(_paths.versions).createSync(recursive: true);
    _delete(target);
    Directory(unpacked).renameSync(target);
  }

  /// Points `current` at the folder of [version]. The link is made beside it
  /// and renamed over it, so there is no moment without a `current`.
  void switchTo(String version) {
    final next = Link('${_paths.currentLink}.next');
    if (FileSystemEntity.typeSync(next.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      next.deleteSync();
    }
    // Relative, so that the data directory can be moved.
    next
      ..createSync(p.join('versions', version))
      ..renameSync(_paths.currentLink);
  }

  /// Deletes every installed version but those in [keep], and what an update
  /// left half done.
  void prune(Set<String> keep) {
    final directory = Directory(_paths.versions);
    if (!directory.existsSync()) return;
    for (final entry in directory.listSync(followLinks: false)) {
      if (!keep.contains(p.basename(entry.path))) {
        entry.deleteSync(recursive: true);
      }
    }
  }

  static void _delete(String path) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type == FileSystemEntityType.directory) {
      Directory(path).deleteSync(recursive: true);
    } else {
      File(path).deleteSync();
    }
  }
}
