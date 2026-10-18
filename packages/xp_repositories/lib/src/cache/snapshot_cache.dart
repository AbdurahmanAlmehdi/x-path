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
/// leaves half a file. A file that is not JSON reads as missing. Writes to
/// one file run one after another, each through its own temporary file, so
/// two views saving the same key at once never trip over each other and the
/// last write wins.
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

  /// The last write still running for each file, by path.
  static final _writes = <String, Future<void>>{};

  /// Makes every temporary file name of this process different.
  static var _sequence = 0;

  @override
  Future<void> write(String key, Object? value) {
    final file = _file(key);
    final text = jsonEncode(value);
    final before = _writes[file.path] ?? Future<void>.value();
    final next = before
        .then<void>((_) {}, onError: (Object _) {})
        .then((_) => _replace(file, text));
    _writes[file.path] = next;
    return next.whenComplete(() {
      if (identical(_writes[file.path], next)) {
        _writes.removeWhere((path, _) => path == file.path);
      }
    });
  }

  Future<void> _replace(File file, String text) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.$pid.${_sequence++}.tmp');
    try {
      await temporary.writeAsString(text);
      await temporary.rename(file.path);
    } on FileSystemException {
      if (temporary.existsSync()) await temporary.delete();
      rethrow;
    }
  }
}
