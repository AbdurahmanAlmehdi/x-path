import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:xp_client/src/exceptions.dart';

/// The content of an artifact, still on the wire.
///
/// Read [content] once, or save it with [saveTo]. The engine sends the SHA-256
/// of the file with it, and [saveTo] checks what it wrote against that.
class ArtifactDownload {
  /// Creates the download of a file whose bytes arrive on [content].
  const new({
    required this.content,
    required this.sha256,
    this.length,
    this.fileName,
  });

  /// The bytes of the file.
  final Stream<List<int>> content;

  /// The SHA-256 the engine says the file has, in lowercase hexadecimal, or
  /// `null` if it did not say.
  final String? sha256;

  /// The size the engine says the file has, if it did.
  final int? length;

  /// The name from `Content-Disposition`, if the engine sent one.
  final String? fileName;

  /// Saves the file to [target], by way of `<target>.part`, and returns the
  /// SHA-256 of what it wrote.
  ///
  /// Throws a [DownloadException] (and leaves nothing behind) if the size or
  /// the SHA-256 is not what the engine announced.
  Future<String> saveTo(File target) async {
    final part = File('${target.path}.part');
    final sink = part.openWrite();
    try {
      await sink.addStream(content);
    } on Object catch (error) {
      await sink.close().catchError((Object _) {});
      await _delete(part);
      throw DownloadException('The download broke off: $error');
    }
    await sink.close();
    final size = part.lengthSync();
    final actual = (await crypto.sha256.bind(part.openRead()).first).toString();
    if ((length != null && length != size) ||
        (sha256 != null && sha256 != actual)) {
      await _delete(part);
      throw DownloadException(
        'The file is not what the engine announced (size $size, SHA-256 '
        '$actual).',
      );
    }
    await part.rename(target.path);
    return actual;
  }

  static Future<void> _delete(File file) async {
    if (file.existsSync()) await file.delete();
  }
}
