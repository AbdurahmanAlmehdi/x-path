import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/scan/ios_files.dart';
import 'package:xp_engine/src/versioning/app_version.dart';
import 'package:xp_engine/src/versioning/versioning_exceptions.dart';
import 'package:xp_engine/src/versioning/workspace.dart';

const _shortVersionKey = 'CFBundleShortVersionString';
const _buildKey = 'CFBundleVersion';

// `version: 5.4.1+3283`, optionally followed by a comment. Only at the start
// of a line: a nested `version:` is a dependency's.
final _pubspecVersion = RegExp(
  r'^(version:[ \t]*)([^\s#]+)([ \t]*(?:#.*)?)$',
  multiLine: true,
);

RegExp _plistKey(String key) =>
    RegExp('(<key>${RegExp.escape(key)}</key>\\s*<string>)([^<]*)(</string>)');

/// The version as the version files of an app say it.
class VersionFilesState extends Equatable {
  /// Creates a state.
  const new({
    required this.pubspecPath,
    required this.pubspec,
    this.plists = const [],
  });

  /// The pubspec, relative to the repository root.
  final String pubspecPath;

  /// Its `version`.
  final AppVersion pubspec;

  /// The version keys of each listed plist, as written.
  final List<PlistVersion> plists;

  /// The plists with a literal version that differs from [version]. A key
  /// that holds `$(FLUTTER_BUILD_NAME)` or `$(FLUTTER_BUILD_NUMBER)` follows
  /// the build and is not compared.
  List<PlistVersion> plistsOutOfSync(AppVersion version) => [
    for (final plist in plists)
      if (_differs(plist.shortVersion, version.name.toString()) ||
          _differs(plist.buildNumber, version.build?.toString() ?? ''))
        plist,
  ];

  /// Whether every version file says [version].
  bool matches(AppVersion version) =>
      pubspec == version && plistsOutOfSync(version).isEmpty;

  static bool _differs(String? value, String expected) =>
      value != null && !isBuildVariable(value) && value != expected;

  @override
  List<Object?> get props => [pubspecPath, pubspec, plists];
}

/// Reads and writes the version of an app in its pubspec and in the plists
/// that carry literal versions (D-11).
///
/// Text matching on purpose: parsing a plist and writing it back reorders
/// keys and drops comments, which turns a version bump into an unreadable
/// diff. A file must hold exactly one of each key; zero or several is an
/// error, never a guess.
class VersionFiles {
  /// Creates the reader and writer over the workspace.
  const new(this._workspace);

  final Workspace _workspace;

  /// Reads the version files [files]: exactly one `pubspec.yaml` and any
  /// number of plists, as listed in the flavor's `versionFiles`.
  ///
  /// Throws a [VersionFileException] for a file that is missing, is of another
  /// kind, or lacks a version.
  Future<VersionFilesState> read(List<String> files) async {
    final (pubspec, plists) = _classify(files);
    final texts = await _load(files);
    return VersionFilesState(
      pubspecPath: pubspec,
      pubspec: _readPubspec(pubspec, texts[pubspec]!),
      plists: [for (final plist in plists) _readPlist(plist, texts[plist]!)],
    );
  }

  /// Writes [version] into [files] and returns the files that changed.
  ///
  /// Nothing is written unless every file can take the version. A plist key
  /// that holds a build variable is left alone.
  ///
  /// Throws a [VersionFileException] like [read] does, and an [ArgumentError]
  /// if [version] has no build number.
  Future<List<String>> write(List<String> files, AppVersion version) async {
    final build = version.build;
    if (build == null) {
      throw ArgumentError.value(version, 'version', 'has no build number');
    }
    final (pubspec, plists) = _classify(files);
    final texts = await _load(files);
    final updated = <String, String>{
      pubspec: _replace(
        pubspec,
        texts[pubspec]!,
        _pubspecVersion,
        'the `version:` line',
        '$version',
      ),
      for (final plist in plists)
        plist: _replacePlist(plist, texts[plist]!, version.name, build),
    };
    final changed = [
      for (final path in [pubspec, ...plists])
        if (updated[path] != texts[path]) path,
    ];
    for (final path in changed) {
      await _workspace.write(path, updated[path]!);
    }
    return changed;
  }

  (String, List<String>) _classify(List<String> files) {
    final pubspecs = [
      for (final file in files)
        if (file == 'pubspec.yaml' || file.endsWith('/pubspec.yaml')) file,
    ];
    final plists = [
      for (final file in files)
        if (file.endsWith('.plist')) file,
    ];
    for (final file in files) {
      if (!pubspecs.contains(file) && !plists.contains(file)) {
        throw VersionFileException(
          file,
          'is neither a pubspec.yaml nor a plist, so XPath does not know how '
          'to write a version into it.',
        );
      }
    }
    if (pubspecs.length != 1) {
      throw VersionFileException(
        pubspecs.isEmpty ? 'pubspec.yaml' : pubspecs.join(', '),
        'The version files must list exactly one pubspec.yaml, found '
        '${pubspecs.length}.',
      );
    }
    return (pubspecs.single, plists);
  }

  Future<Map<String, String>> _load(List<String> files) async => {
    for (final file in files)
      file:
          await _workspace.read(file) ??
          (throw VersionFileException(
            file,
            'does not exist or is unreadable.',
          )),
  };

  AppVersion _readPubspec(String path, String text) {
    final match = _single(
      path,
      _pubspecVersion.allMatches(text),
      'the `version:` line',
    );
    try {
      return AppVersion.parse(match[2]!);
    } on FormatException catch (error) {
      throw VersionFileException(path, error.message);
    }
  }

  PlistVersion _readPlist(String path, String text) {
    final short = _single(
      path,
      _plistKey(_shortVersionKey).allMatches(text),
      _shortVersionKey,
    )[2]!;
    final build = _single(
      path,
      _plistKey(_buildKey).allMatches(text),
      _buildKey,
    )[2]!;
    return PlistVersion(
      path: path,
      shortVersion: short,
      buildNumber: build,
      literal: !isBuildVariable(short) || !isBuildVariable(build),
    );
  }

  String _replacePlist(String path, String text, VersionName name, int build) {
    var result = text;
    for (final (key, value) in [
      (_shortVersionKey, '$name'),
      (_buildKey, '$build'),
    ]) {
      final pattern = _plistKey(key);
      final current = _single(path, pattern.allMatches(result), key)[2]!;
      if (!isBuildVariable(current)) {
        result = _replace(path, result, pattern, key, value);
      }
    }
    return result;
  }

  /// [text] with the second group of the only match of [pattern] replaced.
  String _replace(
    String path,
    String text,
    RegExp pattern,
    String what,
    String value,
  ) {
    final match = _single(path, pattern.allMatches(text), what);
    return text.replaceRange(
      match.start,
      match.end,
      '${match[1]}$value${match[3]}',
    );
  }

  RegExpMatch _single(String path, Iterable<RegExpMatch> matches, String what) {
    final list = matches.toList();
    if (list.length != 1) {
      throw VersionFileException(
        path,
        'has ${list.length} matches for $what; expected exactly one.',
      );
    }
    return list.single;
  }
}
