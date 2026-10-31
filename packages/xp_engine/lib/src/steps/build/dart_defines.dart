import 'dart:convert';

// The `.env` grammar of Flutter (`DotEnvRegex` of flutter_tools): what Linux
// builds, the masker and the compiled config check read must be what `flutter
// build` compiles.
final _envMultiLine = RegExp(r'^\s*[a-zA-Z_]+[a-zA-Z0-9_]*\s*=\s*"""');
final _envKeyValue = RegExp(r'^\s*([a-zA-Z_]+[a-zA-Z0-9_]*)\s*=\s*(.*)?$');
final _envValues = [
  RegExp(r'^"(.*)"\s*(\#\s*.*)?$'),
  RegExp(r"^'(.*)'\s*(\#\s*.*)?$"),
  RegExp(r'^`(.*)`\s*(\#\s*.*)?$'),
  RegExp(r'^([^#\n\s]*)\s*(?:\s*#\s*(.*))?$'),
];

/// Reads the file `--dart-define-from-file` takes as Flutter does: a JSON
/// object, or lines of `KEY=value` (`.env`) where the last definition of a key
/// wins.
///
/// Throws a [FormatException] if Flutter would refuse the file. The exception
/// never quotes the file: its values may be secret.
Map<String, String> parseDartDefines(String text) {
  if (text.trimLeft().startsWith('{')) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const FormatException('The define file is not valid JSON.');
    }
    if (json is! Map<String, dynamic> ||
        json.values.any((value) => value is Map || value is List)) {
      throw const FormatException('The define file must hold a flat object.');
    }
    return {for (final entry in json.entries) entry.key: '${entry.value}'};
  }
  final defines = <String, String>{};
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final match = _envKeyValue.firstMatch(line);
    if (match == null || _envMultiLine.hasMatch(line)) {
      throw const FormatException(
        'A line of the define file is not KEY=value.',
      );
    }
    final value = match.group(2) ?? '';
    defines[match.group(1)!] = _envValues
        .map((pattern) => pattern.firstMatch(value)?.group(1))
        .firstWhere((found) => found != null, orElse: () => value)!;
  }
  return defines;
}

/// Throws a [FormatException] if Flutter could not read [text], or it defines
/// nothing.
void checkDartDefines(String text) {
  if (parseDartDefines(text).isEmpty) {
    throw const FormatException('The define file defines no values.');
  }
}

/// What a log could show of the define file [text]: the file, each value, and
/// each `KEY=value` as Flutter hands it to its own tools (base64). Of a file
/// that cannot be read, its lines.
List<String> dartDefineSecrets(String text) {
  final Map<String, String> defines;
  try {
    defines = parseDartDefines(text);
  } on FormatException {
    return [text];
  }
  return [
    text,
    for (final MapEntry(:key, :value) in defines.entries) ...[
      value,
      base64.encode(utf8.encode('$key=$value')),
    ],
  ];
}

/// What of a define value ends up as a plain string in the compiled code and
/// is distinctive: for a URL its host (K:430-462 strips the scheme and the
/// path), for anything else the value itself.
String compiledNeedle(String value) => value
    .replaceFirst(RegExp('^https?://'), '')
    .replaceFirst(RegExp('/.*'), '');
