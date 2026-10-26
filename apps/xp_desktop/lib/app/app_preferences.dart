import 'dart:convert';
import 'dart:io';

/// What the app remembers between launches on this Mac (U6b): whether
/// closing the window keeps it running, compact rows, the notices the owner
/// turned off, and the page last shown of each engine. A small JSON object.
class AppPreferences {
  /// Preferences kept in memory only, starting as [values].
  new([Map<String, Object?> values = const {}]) : _file = null {
    _values.addAll(values);
  }

  new _file(this._file);

  /// The preferences kept in the JSON file at [path]; a file that is missing
  /// or not a JSON object reads as no preference.
  static Future<AppPreferences> load(String path) async {
    final preferences = AppPreferences._file(File(path));
    try {
      final values = jsonDecode(await File(path).readAsString());
      if (values is Map<String, dynamic>) preferences._values.addAll(values);
    } on IOException {
      // No file yet.
    } on FormatException {
      // A broken file is rewritten at the next change.
    }
    return preferences;
  }

  final File? _file;
  final _values = <String, Object?>{};

  static const _keepRunning = 'keepRunning';
  static const _compact = 'compactRows';
  static const _muted = 'mutedNotices';
  static const _destinations = 'lastDestinations';

  /// Whether closing the window keeps XPath in the menu bar (UX-07); on by
  /// default.
  bool get keepRunning => _values[_keepRunning] as bool? ?? true;

  /// Whether rows are compact (⌃⌘=, U6c); off by default.
  bool get compactRows => _values[_compact] as bool? ?? false;

  /// The notices the owner turned off, by name.
  Set<String> get mutedNotices => {
    for (final name in _values[_muted] as List? ?? const []) '$name',
  };

  /// The page last shown of the engine [engineId], encoded.
  String? lastDestination(String engineId) =>
      (_values[_destinations] as Map?)?[engineId] as String?;

  Future<void> setKeepRunning({required bool keep}) =>
      _write(_keepRunning, keep);

  Future<void> setCompactRows({required bool compact}) =>
      _write(_compact, compact);

  Future<void> setMutedNotices(Set<String> names) =>
      _write(_muted, [...names]..sort());

  Future<void> setLastDestination(String engineId, String? destination) =>
      _write(_destinations, {
        ...?(_values[_destinations] as Map?)?.cast<String, Object?>(),
        engineId: destination,
      });

  Future<void> _write(String key, Object? value) async {
    _values[key] = value;
    final file = _file;
    if (file == null) return;
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(_values));
    await temporary.rename(file.path);
  }
}
