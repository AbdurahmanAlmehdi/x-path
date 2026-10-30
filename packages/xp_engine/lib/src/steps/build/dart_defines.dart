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
      () => _envValue(line.substring(equals + 1)),
    );
  }
  return defines;
}

final _unquotedEnvValue = RegExp(r'^([^#\s]*)\s*(?:#.*)?$');

/// The value of a `.env` line as Flutter reads it: without its wrapping
/// quotes, or without a trailing comment. Spaces inside a value stay.
String _envValue(String raw) {
  final value = raw.trim();
  for (final quote in const ['"', "'", '`']) {
    final end = value.indexOf(quote, 1);
    if (value.startsWith(quote) && end > 0) return value.substring(1, end);
  }
  return _unquotedEnvValue.firstMatch(value)?.group(1) ?? value;
}

/// Throws a [FormatException] if [text] is no define file Flutter would read,
/// or defines nothing. The message never quotes the file: its values are
/// secret.
void checkDartDefines(String text) {
  final Map<String, String> defines;
  try {
    defines = parseDartDefines(text);
  } on FormatException {
    throw const FormatException(
      'The file is not a flat JSON object of --dart-define values.',
    );
  }
  final badLine =
      !text.trimLeft().startsWith('{') &&
      const LineSplitter().convert(text).any((raw) {
        final line = raw.trim();
        return line.isNotEmpty &&
            !line.startsWith('#') &&
            line.indexOf('=') <= 0;
      });
  if (badLine) {
    throw const FormatException('A line of the file is not KEY=value.');
  }
  if (defines.isEmpty) {
    throw const FormatException('The file defines no values.');
  }
}

/// What a log could show of the define file [text]: the file, each value, and
/// each `KEY=value` as Flutter hands it to its own tools (base64).
List<String> dartDefineSecrets(String text) => [
  text,
  for (final MapEntry(:key, :value) in parseDartDefines(text).entries) ...[
    value,
    base64.encode(utf8.encode('$key=$value')),
  ],
];

/// What of a define value ends up as a plain string in the compiled code and
/// is distinctive: for a URL its host (K:430-462 strips the scheme and the
/// path), for anything else the value itself.
String compiledNeedle(String value) => value
    .replaceFirst(RegExp('^https?://'), '')
    .replaceFirst(RegExp('/.*'), '');
