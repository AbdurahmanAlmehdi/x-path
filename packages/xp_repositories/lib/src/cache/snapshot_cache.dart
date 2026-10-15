import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Where the repositories keep the last answer of the engine, so the app can
/// show it read-only while the engine cannot be reached.
///
/// A value is the JSON form of what the engine answered, under a key such as
/// `projects` or `job.<id>`. One cache belongs to one engine.
abstract interface class SnapshotCache {
  /// The value saved under [key], or `null` if there is none (or it cannot be
  /// read).
  Future<Object?> read(String key);

  /// Saves [value] under [key], replacing what was there.
  Future<void> write(String key, Object? value);
}

/// A [SnapshotCache] that keeps nothing beyond the life of the process.
///
/// Values go through JSON text as they would in a file, so what is read
/// back is plain maps and lists.
class MemorySnapshotCache implements SnapshotCache {
  final _values = <String, String>{};

  @override
  Future<Object?> read(String key) async {
    final text = _values[key];
    return text == null ? null : jsonDecode(text);
  }

  @override
  Future<void> write(String key, Object? value) async =>
      _values[key] = jsonEncode(value);
}

/// A [SnapshotCache] that keeps one JSON file per key in [directory].
///
/// A file is written next to its final name and renamed, so a crash never
/// leaves half a file. A file that is not JSON reads as missing.
class FileSnapshotCache implements SnapshotCache {
  /// Creates a cache in [directory], which is created when it is first
  /// written.
  const new(this.directory);

  /// The folder of the files.
  final String directory;

  File _file(String key) => File(
    p.join(directory, '${key.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_')}.json'),
  );

  @override
  Future<Object?> read(String key) async {
    final file = _file(key);
    if (!file.existsSync()) return null;
    try {
      return jsonDecode(await file.readAsString());
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(String key, Object? value) async {
    final file = _file(key);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value));
    await temporary.rename(file.path);
  }
}
