import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// Takes the AOT snapshot out of an APK, AAB or IPA by unzipping it.
class ZipSnapshotReader implements SnapshotReader {
  /// Creates the reader.
  const new();

  static final Map<ArtifactKind, RegExp> _entries = {
    ArtifactKind.apk: RegExp(r'^lib/[^/]+/libapp\.so$'),
    ArtifactKind.aab: RegExp(r'^base/lib/[^/]+/libapp\.so$'),
    ArtifactKind.ipa: RegExp(
      r'^Payload/[^/]+\.app/Frameworks/App\.framework/App$',
    ),
  };

  /// Writes the package to a temporary file, because a ZIP archive is read
  /// from its end, then reads the one entry from it. The snapshot itself is
  /// held in memory, which is tens of megabytes.
  @override
  Future<Stream<List<int>>?> snapshotOf(
    ArtifactKind kind,
    Stream<List<int>> package,
  ) async {
    final pattern = _entries[kind];
    if (pattern == null) return null;
    final scratch = Directory.systemTemp.createTempSync('xpath-package-');
    try {
      final file = File('${scratch.path}/package.zip');
      final sink = file.openWrite();
      await sink.addStream(package);
      await sink.close();

      final input = InputFileStream(file.path);
      try {
        final archive = ZipDecoder().decodeStream(input);
        // Bytes that are not a ZIP archive decode to an archive without
        // entries, and a package always has some.
        if (archive.files.isEmpty) {
          throw const FormatException('The package is not a ZIP archive.');
        }
        final entry = archive.files
            .where((entry) => entry.isFile && pattern.hasMatch(entry.name))
            .firstOrNull;
        return entry == null ? null : Stream.value(entry.content);
      } on ArchiveException catch (error) {
        throw FormatException('The package is not a ZIP archive: $error');
      } finally {
        await input.close();
      }
    } finally {
      scratch.deleteSync(recursive: true);
    }
  }
}
