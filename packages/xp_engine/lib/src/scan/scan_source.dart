import 'package:equatable/equatable.dart';

/// One entry of a directory listing.
class ScanEntry extends Equatable {
  /// Creates an entry called [name].
  const new(this.name, {required this.isDirectory});

  /// The file or directory name, without its parent.
  final String name;

  /// Whether the entry is a directory.
  final bool isDirectory;

  @override
  List<Object?> get props => [name, isDirectory];
}

/// A read-only view of a folder that the scanner reads (D-04).
///
/// Paths are relative to the folder, separated by `/`, and never start with
/// `/` or contain `..`; `''` is the folder itself. The scanner never writes,
/// and this interface cannot: the picked folder is only ever read.
///
/// `xp_adapters` has the `dart:io` implementation; [InMemoryScanSource] is for
/// tests.
abstract interface class ScanSource {
  /// Whether a file or directory exists at [path].
  Future<bool> exists(String path);

  /// The text of the file at [path], or `null` if there is no such file or it
  /// cannot be read as text.
  Future<String?> read(String path);

  /// The entries of the directory at [path], sorted by name; empty if there is
  /// no such directory.
  Future<List<ScanEntry>> list(String path);
}

/// A [ScanSource] over a map of file paths to their contents, for tests.
///
/// Directories exist as far as a file lies below them.
class InMemoryScanSource implements ScanSource {
  /// Creates a source holding [files], keyed by relative path.
  new(Map<String, String> files) : _files = Map.of(files);

  final Map<String, String> _files;

  @override
  Future<bool> exists(String path) async {
    final prefix = _prefix(path);
    return _files.containsKey(path) ||
        _files.keys.any((file) => file.startsWith(prefix));
  }

  @override
  Future<String?> read(String path) async => _files[path];

  @override
  Future<List<ScanEntry>> list(String path) async {
    final prefix = _prefix(path);
    final entries = <String, bool>{};
    for (final file in _files.keys) {
      if (!file.startsWith(prefix)) continue;
      final rest = file.substring(prefix.length);
      final slash = rest.indexOf('/');
      final name = slash < 0 ? rest : rest.substring(0, slash);
      entries[name] = (entries[name] ?? false) || slash >= 0;
    }
    return [
      for (final name in entries.keys.toList()..sort())
        ScanEntry(name, isDirectory: entries[name]!),
    ];
  }

  static String _prefix(String path) => path.isEmpty ? '' : '$path/';
}

/// Joins relative scan paths, leaving out empty parts and `.`.
String joinScanPath(String a, String b) {
  final parts = [a, b].where((part) => part.isNotEmpty && part != '.');
  return parts.join('/');
}

/// Resolves `..` and `.` segments of the relative [path].
String normalizeScanPath(String path) {
  final out = <String>[];
  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (out.isNotEmpty) out.removeLast();
    } else {
      out.add(part);
    }
  }
  return out.join('/');
}
