import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/steps/build/build_files.dart';

/// Where omarchy-apple-dev's `flutter/ship.sh` leaves the signed IPA of a
/// Linux build, relative to the app (ADR 0014).
const iosLinuxIpaPath = 'build/ios-linux/Runner-store.ipa';

/// Where `flutter/build.sh` leaves the dSYMs of a Linux build, one per image,
/// relative to the app.
const iosLinuxDsymsPath = 'build/ios-linux/dSYMs';

/// What the search for the file a build produced found.
sealed class BuiltFile {
  const new();
}

/// The file this build produced.
final class Fresh extends BuiltFile {
  /// Creates the finding.
  const new(this.file);

  /// The file.
  final BuildFile file;
}

/// A file is there, but it is older than the build: a leftover of an earlier
/// one (R:196, `assert_fresh`).
final class Stale extends BuiltFile {
  /// Creates the finding.
  const new(this.file);

  /// The leftover.
  final BuildFile file;
}

/// There is no such file.
final class Missing extends BuiltFile {
  /// Creates the finding.
  const new();
}

/// Finds what `flutter build` left in `build/` and keeps what only this build
/// can have made.
///
/// `build/` is not cleaned between runs, so a failed build can leave the
/// artifact of an earlier one where the new one belongs. Every candidate is
/// compared with the freshness marker: a file written before the build started
/// is never taken.
class BuildOutputs {
  /// Creates the finder over [_files].
  const new(this._files);

  final BuildFiles _files;

  /// The APK or AAB of [flavor] in the app at [appDirectory], written after
  /// [since].
  ///
  /// The name is pinned to the flavor on purpose: a loose `*.apk` would return
  /// the dev artifact for a prod build (C:586-605, L:543-573).
  Future<BuiltFile> android(
    String appDirectory, {
    required ArtifactKind kind,
    required String? flavor,
    required DateTime since,
  }) async {
    final extension = kind.wire;
    final name = flavor == null
        ? 'app-release.$extension'
        : 'app-$flavor-release.$extension';
    final outputs = '$appDirectory/build/app/outputs';
    final candidates = [
      for (final directory in _androidDirectories(kind, flavor))
        '$outputs/$directory/$name',
    ];
    final existing = <BuildFile>[];
    for (final candidate in candidates) {
      final file = await _files.stat(candidate);
      if (file != null) existing.add(file);
    }
    // A Gradle or Flutter upgrade may move the output: fall back to the same
    // file name anywhere below the outputs.
    if (existing.isEmpty) {
      existing.addAll(await _files.find(outputs, name: name));
    }
    return _freshest(existing, since);
  }

  /// The IPA that `flutter build ipa` exported into `build/ios/ipa` of the app
  /// at [appDirectory], written after [since].
  Future<BuiltFile> ios(String appDirectory, {required DateTime since}) async =>
      _freshest(
        await _files.list('$appDirectory/build/ios/ipa', extension: '.ipa'),
        since,
      );

  /// The IPA that omarchy-apple-dev's `flutter/ship.sh` signed for a Linux
  /// build of the app at [appDirectory], written after [since].
  Future<BuiltFile> iosLinux(
    String appDirectory, {
    required DateTime since,
  }) async {
    final file = await _files.stat('$appDirectory/$iosLinuxIpaPath');
    return _freshest([?file], since);
  }

  static List<String> _androidDirectories(ArtifactKind kind, String? flavor) =>
      switch (kind) {
        ArtifactKind.aab => [
          if (flavor == null) 'bundle/release' else 'bundle/${flavor}Release',
        ],
        _ => [
          'flutter-apk',
          if (flavor == null) 'apk/release' else 'apk/$flavor/release',
        ],
      };

  static BuiltFile _freshest(List<BuildFile> files, DateTime since) {
    if (files.isEmpty) return const Missing();
    final fresh = files.where((file) => file.modified.isAfter(since)).toList()
      ..sort((a, b) => b.modified.compareTo(a.modified));
    return fresh.isEmpty ? Stale(files.first) : Fresh(fresh.first);
  }
}
