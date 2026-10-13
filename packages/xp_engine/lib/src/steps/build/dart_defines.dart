import 'dart:convert';

/// Reads the file `--dart-define-from-file` takes: a JSON object, or lines of
/// `KEY=value` (`.env`).
///
/// Throws a [FormatException] if a JSON file is not an object of scalars.
Map<String, String> parseDartDefines(String text) {
  if (text.trimLeft().startsWith('{')) {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic> ||
        json.values.any((value) => value is Map || value is List)) {
      throw const FormatException('The define file must hold a flat object.');
    }
    return {for (final entry in json.entries) entry.key: '${entry.value}'};
  }
  final defines = <String, String>{};
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    final equals = line.indexOf('=');
    if (line.startsWith('#') || equals <= 0) continue;
    // The first definition of a key wins, like `grep -m1` in K:430-462.
    defines.putIfAbsent(
      line.substring(0, equals).trim(),
      () => line.substring(equals + 1).replaceAll(RegExp('["\'\\s]'), ''),
    );
  }
  return defines;
}

/// What of a define value ends up as a plain string in the compiled code and
/// is distinctive: for a URL its host (K:430-462 strips the scheme and the
/// path), for anything else the value itself.
String compiledNeedle(String value) => value
    .replaceFirst(RegExp('^https?://'), '')
    .replaceFirst(RegExp('/.*'), '');
