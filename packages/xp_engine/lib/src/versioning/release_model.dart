import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/versioning/app_version.dart';

/// Which app and flavor a tag belongs to, for tag patterns that name them
/// (`{app}/{flavor}/v{version}+{build}`).
class TagScope extends Equatable {
  /// Creates a scope.
  const new({this.app, this.flavor});

  /// The app, as the tag spells it.
  final String? app;

  /// The flavor, as the tag spells it.
  final String? flavor;

  @override
  List<Object?> get props => [app, flavor];
}

/// A tag of the release model, taken apart.
class ReleaseTag extends Equatable {
  /// Creates a release tag record.
  const new({
    required this.name,
    required this.version,
    required this.build,
    this.patch,
  });

  /// The tag name.
  final String name;

  /// The marketing version.
  final VersionName version;

  /// The build number the tag records.
  final int build;

  /// The number of the OTA patch, or `null` for a store release.
  final int? patch;

  /// Whether the tag records an OTA patch rather than a store release.
  bool get isPatch => patch != null;

  @override
  List<Object?> get props => [name, version, build, patch];
}

final _placeholder = RegExp(r'\{([^{}]*)\}');

// What git refuses in a ref name, and what would make a pattern ambiguous.
final _unsafeRef = RegExp(r'[\s~^:?*\[\\\x00-\x1f\x7f]|\.\.|//');

/// How an app names its release branches and tags (D-11).
///
/// A pattern is a ref name with placeholders: `{version}` (`5.4.1`),
/// `{build}` (`3283`), `{n}` (the number of an OTA patch), `{app}` and
/// `{flavor}`. The defaults are the model of `docs/RELEASING.md`: a line per
/// version on `release/<x.y.z>`, store builds on `v<x.y.z>+<build>` and OTA
/// patches on `v<x.y.z>+<build>-p<n>`. The base branch is the project's.
///
/// The model is stored as JSON in `project.release_model`. Read untrusted
/// JSON with `ReleaseModel.fromJson`, which validates; a model made in code is
/// trusted.
class ReleaseModel extends Equatable {
  /// Creates a model; leave a pattern out for its default.
  const new({
    this.branchPattern = defaultBranchPattern,
    this.tagPattern = defaultTagPattern,
    this.patchTagPattern = defaultPatchTagPattern,
  });

  /// Reads a model from its stored form; keys that are missing take the
  /// default.
  ///
  /// Throws a [FormatException] if a key is unknown or not a string, or if a
  /// pattern is not valid; the message lists every problem.
  factory fromJson(Map<String, dynamic> json) {
    const keys = {'branchPattern', 'tagPattern', 'patchTagPattern'};
    final problems = [
      for (final key in json.keys)
        if (!keys.contains(key)) 'Unknown release model key "$key".',
      for (final key in keys)
        if (json[key] != null && json[key] is! String)
          '"$key" must be a string.',
    ];
    if (problems.isNotEmpty) throw FormatException(problems.join(' '));
    final model = ReleaseModel(
      branchPattern: json['branchPattern'] as String? ?? defaultBranchPattern,
      tagPattern: json['tagPattern'] as String? ?? defaultTagPattern,
      patchTagPattern:
          json['patchTagPattern'] as String? ?? defaultPatchTagPattern,
    );
    final invalid = model.problems;
    if (invalid.isNotEmpty) throw FormatException(invalid.join(' '));
    return model;
  }

  /// `release/{version}`.
  static const defaultBranchPattern = 'release/{version}';

  /// `v{version}+{build}`.
  static const defaultTagPattern = 'v{version}+{build}';

  /// `v{version}+{build}-p{n}`.
  static const defaultPatchTagPattern = 'v{version}+{build}-p{n}';

  /// The name of a release branch. Needs `{version}`.
  final String branchPattern;

  /// The name of the tag of a store build. Needs `{version}` and `{build}`.
  final String tagPattern;

  /// The name of the tag of an OTA patch. Needs `{version}`, `{build}` and
  /// `{n}`.
  final String patchTagPattern;

  /// Why the patterns are not valid; empty if they are.
  List<String> get problems => [
    ..._problemsOf(
      'branchPattern',
      branchPattern,
      {'version'},
      {'app', 'flavor'},
    ),
    ..._problemsOf(
      'tagPattern',
      tagPattern,
      {'version', 'build'},
      {'app', 'flavor'},
    ),
    ..._problemsOf(
      'patchTagPattern',
      patchTagPattern,
      {'version', 'build', 'n'},
      {'app', 'flavor'},
    ),
  ];

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'branchPattern': branchPattern,
    'tagPattern': tagPattern,
    'patchTagPattern': patchTagPattern,
  };

  /// The release branch of [version], for example `release/5.4.1`.
  String branchName(VersionName version, {TagScope scope = const TagScope()}) =>
      _fill(branchPattern, scope, {'version': '$version'});

  /// The tag of the store build [version]+[build], for example `v5.4.1+3283`.
  String tagName(
    VersionName version,
    int build, {
    TagScope scope = const TagScope(),
  }) => _fill(tagPattern, scope, {'version': '$version', 'build': '$build'});

  /// The tag of OTA patch [n] against [version]+[build], for example
  /// `v5.4.1+3283-p2`.
  String patchTagName(
    VersionName version,
    int build,
    int n, {
    TagScope scope = const TagScope(),
  }) => _fill(patchTagPattern, scope, {
    'version': '$version',
    'build': '$build',
    'n': '$n',
  });

  /// Takes the tag [name] apart, or returns `null` if it is not a release or
  /// patch tag of this model (and [scope]).
  ///
  /// A placeholder `{app}` or `{flavor}` that [scope] leaves out matches any
  /// name.
  ReleaseTag? parseTag(String name, {TagScope scope = const TagScope()}) {
    for (final pattern in [patchTagPattern, tagPattern]) {
      final match = _regex(pattern, scope).firstMatch(name);
      if (match == null) continue;
      return ReleaseTag(
        name: name,
        version: VersionName.parse(match.namedGroup('version')!),
        build: int.parse(match.namedGroup('build')!),
        patch: pattern == patchTagPattern
            ? int.parse(match.namedGroup('n')!)
            : null,
      );
    }
    return null;
  }

  @override
  List<Object?> get props => [branchPattern, tagPattern, patchTagPattern];

  static List<String> _problemsOf(
    String field,
    String pattern,
    Set<String> needed,
    Set<String> optional,
  ) {
    final names = [for (final m in _placeholder.allMatches(pattern)) m[1]!];
    final problems = <String>[
      for (final name in names.toSet())
        if (!needed.contains(name) && !optional.contains(name))
          '$field has an unknown placeholder {$name}.',
      for (final name in needed)
        if (!names.contains(name)) '$field needs {$name}.',
      for (final name in names.toSet())
        if (names.where((other) => other == name).length > 1)
          '$field uses {$name} more than once.',
    ];
    final stripped = pattern.replaceAll(_placeholder, '');
    if (stripped.contains('{') || stripped.contains('}')) {
      problems.add('$field has a stray brace.');
    }
    final sample = pattern.replaceAllMapped(_placeholder, (match) => 'x');
    if (_unsafeRef.hasMatch(sample) ||
        sample.startsWith('/') ||
        sample.startsWith('-') ||
        sample.endsWith('/') ||
        sample.endsWith('.') ||
        sample.endsWith('.lock')) {
      problems.add('$field is not a valid git ref name.');
    }
    return problems;
  }

  static String _fill(
    String pattern,
    TagScope scope,
    Map<String, String> values,
  ) => pattern.replaceAllMapped(_placeholder, (match) {
    final name = match[1]!;
    final value = switch (name) {
      'app' => scope.app,
      'flavor' => scope.flavor,
      _ => values[name],
    };
    if (value == null) {
      throw ArgumentError.value(scope, 'scope', 'needs a value for {$name}');
    }
    return value;
  });

  static RegExp _regex(String pattern, TagScope scope) {
    final buffer = StringBuffer('^');
    var end = 0;
    for (final match in _placeholder.allMatches(pattern)) {
      buffer.write(RegExp.escape(pattern.substring(end, match.start)));
      end = match.end;
      buffer.write(switch (match[1]!) {
        'version' => r'(?<version>\d+\.\d+\.\d+)',
        'build' => r'(?<build>\d+)',
        'n' => r'(?<n>\d+)',
        'app' => scope.app == null ? '[^/]+' : RegExp.escape(scope.app!),
        _ => scope.flavor == null ? '[^/]+' : RegExp.escape(scope.flavor!),
      });
    }
    buffer
      ..write(RegExp.escape(pattern.substring(end)))
      ..write(r'$');
    return RegExp(buffer.toString());
  }
}
