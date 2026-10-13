import 'package:equatable/equatable.dart';

/// A `productFlavors` entry of a Gradle build script.
class GradleFlavor extends Equatable {
  /// Creates a flavor called [name].
  const new(
    this.name, {
    this.dimension,
    this.applicationId,
    this.applicationIdSuffix,
  });

  /// The flavor name.
  final String name;

  /// Its `dimension`.
  final String? dimension;

  /// Its own `applicationId`, if it sets one.
  final String? applicationId;

  /// Its `applicationIdSuffix`, if it sets one.
  final String? applicationIdSuffix;

  /// Fills what this flavor leaves unset from [other].
  GradleFlavor withFallback(GradleFlavor other) => GradleFlavor(
    name,
    dimension: dimension ?? other.dimension,
    applicationId: applicationId ?? other.applicationId,
    applicationIdSuffix: applicationIdSuffix ?? other.applicationIdSuffix,
  );

  @override
  List<Object?> get props => [
    name,
    dimension,
    applicationId,
    applicationIdSuffix,
  ];
}

/// What the scanner reads from the Gradle scripts of one Android app.
class GradleInfo extends Equatable {
  /// Creates the result of parsing build scripts.
  const new({
    this.flavors = const [],
    this.defaultApplicationId,
    this.keyPropertiesReference,
    this.mentionsProductFlavors = false,
  });

  /// The product flavors, in the order they were declared.
  final List<GradleFlavor> flavors;

  /// The `applicationId` of `defaultConfig`.
  final String? defaultApplicationId;

  /// The path of the keystore properties file as the script spells it, for
  /// example `key.properties`, when the script reads one.
  final String? keyPropertiesReference;

  /// Whether the script has a `productFlavors` block, even if no flavor in it
  /// could be read.
  final bool mentionsProductFlavors;

  /// The application id that [flavor] ends up with: its own id, or the default
  /// id, followed by its suffix.
  String? applicationIdOf(GradleFlavor flavor) {
    final base = flavor.applicationId ?? defaultApplicationId;
    if (base == null) return null;
    return '$base${flavor.applicationIdSuffix ?? ''}';
  }

  /// The distinct flavor dimensions in use.
  Set<String> get dimensions => {
    for (final flavor in flavors)
      if (flavor.dimension != null) flavor.dimension!,
  };

  /// These results together with [other]'s: flavors are joined by name, and
  /// what one leaves unset is taken from the other.
  GradleInfo merge(GradleInfo other) {
    final byName = {for (final flavor in flavors) flavor.name: flavor};
    for (final flavor in other.flavors) {
      final existing = byName[flavor.name];
      byName[flavor.name] = existing == null
          ? flavor
          : existing.withFallback(flavor);
    }
    return GradleInfo(
      flavors: byName.values.toList(),
      defaultApplicationId: defaultApplicationId ?? other.defaultApplicationId,
      keyPropertiesReference:
          keyPropertiesReference ?? other.keyPropertiesReference,
      mentionsProductFlavors:
          mentionsProductFlavors || other.mentionsProductFlavors,
    );
  }

  @override
  List<Object?> get props => [
    flavors,
    defaultApplicationId,
    keyPropertiesReference,
    mentionsProductFlavors,
  ];
}

/// Reads product flavors, the default application id and the keystore
/// properties reference out of a Groovy or Kotlin Gradle script.
///
/// This is text matching, not a Gradle parser: it understands the shapes that
/// `flutter_flavorizr` and the Flutter templates write, and gives up
/// quietly on anything cleverer.
GradleInfo parseGradle(String script) {
  final text = withoutGradleComments(script);
  final flavorsBody = _blockAfter(text, RegExp(r'\bproductFlavors\s*\{'));
  final defaultConfig = _blockAfter(text, RegExp(r'\bdefaultConfig\s*\{'));
  return GradleInfo(
    flavors: [
      if (flavorsBody != null)
        for (final block in _topLevelBlocks(flavorsBody))
          ?_flavorOf(block.header, block.body),
    ],
    defaultApplicationId: defaultConfig == null
        ? null
        : _string(defaultConfig, 'applicationId'),
    keyPropertiesReference: RegExp(r'''["']([^"']*key\.properties)["']''')
        .firstMatch(text)
        ?.group(1),
    mentionsProductFlavors: flavorsBody != null,
  );
}

GradleFlavor? _flavorOf(String header, String body) {
  final name = _flavorName(header);
  if (name == null) return null;
  // Nested blocks (`manifestPlaceholders`, `buildConfigField`) are not ours.
  final own = _withoutNestedBlocks(body);
  return GradleFlavor(
    name,
    dimension: _string(own, 'dimension'),
    applicationId: _string(own, 'applicationId'),
    applicationIdSuffix: _string(own, 'applicationIdSuffix'),
  );
}

final _createCall = RegExp(
  r'''(?:create|register|maybeCreate|getByName)\s*\(\s*["']([^"']+)["']\s*\)''',
);
final _bareName = RegExp(r'''^["']?([A-Za-z_][\w-]*)["']?$''');

String? _flavorName(String header) {
  final trimmed = header.trim();
  return _createCall.firstMatch(trimmed)?.group(1) ??
      _bareName.firstMatch(trimmed)?.group(1);
}

/// The quoted value of the assignment or call `key "value"`, `key = "value"`
/// or `key("value")`.
String? _string(String text, String key) =>
    RegExp('''\\b$key(?![A-Za-z0-9_])\\s*[=(]?\\s*["']([^"']*)["']''')
        .firstMatch(text)
        ?.group(1);

/// The text between the braces of the first block that starts with [opening],
/// whose last character must be `{`.
String? _blockAfter(String text, RegExp opening) {
  final match = opening.firstMatch(text);
  if (match == null) return null;
  return _braceBody(text, match.end);
}

/// The text from [start] up to the `}` that closes the block opened just
/// before it. Unbalanced text runs to the end.
String _braceBody(String text, int start) {
  var depth = 1;
  for (var i = start; i < text.length; i++) {
    final char = text[i];
    if (char == '{') depth++;
    if (char == '}' && --depth == 0) return text.substring(start, i);
  }
  return text.substring(start);
}

class _Block {
  const new(this.header, this.body);

  final String header;
  final String body;
}

/// The `header { body }` blocks directly inside [text].
List<_Block> _topLevelBlocks(String text) {
  final blocks = <_Block>[];
  var statementStart = 0;
  var i = 0;
  while (i < text.length) {
    final char = text[i];
    if (char == '{') {
      final body = _braceBody(text, i + 1);
      blocks.add(_Block(text.substring(statementStart, i), body));
      i += body.length + 2;
      statementStart = i;
      continue;
    }
    if (char == '\n' || char == ';') statementStart = i + 1;
    i++;
  }
  return blocks;
}

String _withoutNestedBlocks(String text) {
  final out = StringBuffer();
  var depth = 0;
  for (final char in text.split('')) {
    if (char == '{') depth++;
    if (depth == 0) out.write(char);
    if (char == '}' && depth > 0) depth--;
  }
  return out.toString();
}

/// [script] with `//` and `/* */` comments blanked out, leaving strings alone.
String withoutGradleComments(String script) {
  final out = StringBuffer();
  String? quote;
  var i = 0;
  while (i < script.length) {
    final char = script[i];
    final next = i + 1 < script.length ? script[i + 1] : '';
    if (quote != null) {
      out.write(char);
      if (char == r'\' && next.isNotEmpty) {
        out.write(next);
        i += 2;
        continue;
      }
      if (char == quote) quote = null;
    } else if (char == '"' || char == "'") {
      quote = char;
      out.write(char);
    } else if (char == '/' && next == '/') {
      while (i < script.length && script[i] != '\n') {
        i++;
      }
      continue;
    } else if (char == '/' && next == '*') {
      final end = script.indexOf('*/', i + 2);
      i = end < 0 ? script.length : end + 2;
      out.write(' ');
      continue;
    } else {
      out.write(char);
    }
    i++;
  }
  return out.toString();
}
