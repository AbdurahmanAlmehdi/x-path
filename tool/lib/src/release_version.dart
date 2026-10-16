import 'dart:io';

import 'package:path/path.dart' as p;

/// How far a release moves the version.
enum Bump {
  /// 0.4.2 → 0.4.3.
  patch,

  /// 0.4.2 → 0.5.0.
  minor,

  /// 1.4.2 → 2.0.0.
  major,
}

/// A plain release version, `major.minor.patch`, without a pre-release or
/// build part.
final class ReleaseVersion implements Comparable<ReleaseVersion> {
  /// Creates `major.minor.patch`.
  const new(this.major, this.minor, this.patch);

  /// Parses `1.2.3` or `v1.2.3`. Returns null for anything else, a
  /// pre-release (`1.0.0-rc.1`) or a build (`1.2.3+4`) included.
  static ReleaseVersion? tryParse(String text) {
    final match = _plain.firstMatch(text.trim());
    if (match == null) return null;
    return .new(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  static final _plain = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$');

  /// The major version; 0 before 1.0.
  final int major;

  /// The minor version.
  final int minor;

  /// The patch version.
  final int patch;

  /// The version after this one for [bump].
  ReleaseVersion bumped(Bump bump) => switch (bump) {
    Bump.major => .new(major + 1, 0, 0),
    Bump.minor => .new(major, minor + 1, 0),
    Bump.patch => .new(major, minor, patch + 1),
  };

  @override
  int compareTo(ReleaseVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

final _mergeTitle = RegExp(
  r'^Merge (?:pull request|branch|remote-tracking branch)\b',
);
final _header = RegExp(r'^([A-Za-z]+)(?:\([^)]*\))?(!)?:\s');
final _breakingFooter = RegExp('^BREAKING[ -]CHANGE:', multiLine: true);

/// The title of a commit [message] that names the change: its first line,
/// or for a merge commit ("Merge pull request #12 from ...") the first
/// non-empty line of its body, where GitHub puts the pull request title.
String titleOf(String message) {
  final lines = message.trim().split('\n').map((line) => line.trim());
  final first = lines.first;
  if (!_mergeTitle.hasMatch(first)) return first;
  return lines
      .skip(1)
      .firstWhere((line) => line.isNotEmpty, orElse: () => first);
}

/// The bump a commit [message] asks for by Conventional Commits, from
/// [base]: a breaking change (`feat!:`, `fix(api)!:` or a `BREAKING CHANGE:`
/// footer) is minor before 1.0 and major after, `feat:` is minor, and
/// everything else (`fix:`, `perf:`, `docs:`, `ci:`, a title that is not
/// conventional, ...) is patch.
Bump bumpOf(String message, ReleaseVersion base) {
  final header = _header.firstMatch(titleOf(message));
  final breaking =
      header?.group(2) != null || _breakingFooter.hasMatch(message);
  if (breaking) return base.major == 0 ? Bump.minor : Bump.major;
  if (header?.group(1)!.toLowerCase() == 'feat') return Bump.minor;
  return Bump.patch;
}

/// The release a build makes: its version, tag and build number.
final class ReleasePlan {
  /// Creates the plan for [version] (no leading `v`) with [build].
  const new({required this.version, required this.build, required this.reason});

  /// The version, `0.5.0` or `1.0.0-rc.1`.
  final String version;

  /// The build number (`CFBundleVersion`, the `+build` of the app): the
  /// number of commits up to the released one, so it only grows on `main`.
  final int build;

  /// Why this version, for the log.
  final String reason;

  /// The git tag, `v<version>`.
  String get tag => 'v$version';

  /// Whether GitHub marks the release a pre-release: every version before
  /// 1.0 and every version with a pre-release part (`1.0.0-rc.1`).
  bool get prerelease => version.startsWith('0.') || version.contains('-');

  /// The plan as `key=value` lines, the format of `$GITHUB_OUTPUT`.
  String toOutput() =>
      'version=$version\n'
      'tag=$tag\n'
      'build=$build\n'
      'prerelease=$prerelease\n';
}

/// The git queries [planRelease] needs.
abstract interface class ReleaseHistory {
  /// The tags that point at `HEAD`.
  List<String> tagsAtHead();

  /// The tags reachable from `HEAD`.
  List<String> mergedTags();

  /// The full messages of the first-parent commits after [tag] up to
  /// `HEAD`, newest first.
  List<String> messagesSince(String tag);

  /// The full message of `HEAD`.
  String headMessage();

  /// The number of commits reachable from `HEAD`.
  int commitCount();
}

final _tagPattern = RegExp(r'^v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$');

/// Decides the release of `HEAD`.
///
/// - With [tag] (a tag pushed by hand, or a version asked for), that tag.
/// - When a plain `vX.Y.Z` tag points at `HEAD` already (a run again), that
///   version.
/// - Otherwise the highest plain `vX.Y.Z` tag reachable from `HEAD`, bumped
///   by the largest bump of the first-parent commits since it (one squash
///   commit per merge; more when a run was skipped). Without such a tag the
///   base is [pubspecVersion] and only `HEAD` decides.
///
/// Pre-release tags (`v1.0.0-rc.1`) are never a base. Throws a
/// [FormatException] when [tag] is not `v<major>.<minor>.<patch>[-<pre>]`.
ReleasePlan planRelease({
  required ReleaseHistory history,
  required ReleaseVersion pubspecVersion,
  String? tag,
}) {
  final build = history.commitCount();
  if (tag != null) {
    if (!_tagPattern.hasMatch(tag)) {
      throw FormatException(
        'the tag must be v<major>.<minor>.<patch>[-<pre-release>]',
        tag,
      );
    }
    return .new(version: tag.substring(1), build: build, reason: 'tag $tag');
  }

  final atHead = _highest(history.tagsAtHead());
  if (atHead != null) {
    return .new(
      version: '${atHead.version}',
      build: build,
      reason: '${atHead.tag} already points at HEAD',
    );
  }

  final previous = _highest(history.mergedTags());
  final base = previous?.version ?? pubspecVersion;
  final messages = previous == null
      ? [history.headMessage()]
      : history.messagesSince(previous.tag);
  final bump = messages
      .map((message) => bumpOf(message, base))
      .fold(Bump.patch, (a, b) => a.index >= b.index ? a : b);
  final from = previous == null
      ? 'no release tag yet, base $base from apps/xpd/pubspec.yaml'
      : 'after ${previous.tag}';
  final count = messages.length == 1
      ? '1 commit'
      : '${messages.length} commits';
  return .new(
    version: '${base.bumped(bump)}',
    build: build,
    reason: '$from; $count; ${bump.name} bump',
  );
}

({String tag, ReleaseVersion version})? _highest(List<String> tags) {
  ({String tag, ReleaseVersion version})? best;
  for (final tag in tags) {
    if (!tag.startsWith('v')) continue;
    final version = ReleaseVersion.tryParse(tag);
    if (version == null) continue;
    if (best == null || version.compareTo(best.version) > 0) {
      best = (tag: tag, version: version);
    }
  }
  return best;
}

/// [ReleaseHistory] read with `git` in [root].
final class GitReleaseHistory implements ReleaseHistory {
  /// Reads the repository at [root].
  const new(this.root);

  /// The repository's working tree.
  final String root;

  String _git(List<String> arguments) {
    final result = Process.runSync('git', arguments, workingDirectory: root);
    if (result.exitCode != 0) {
      throw ProcessException(
        'git',
        arguments,
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
    return '${result.stdout}';
  }

  List<String> _lines(String text) =>
      text.split('\n').where((line) => line.isNotEmpty).toList();

  @override
  List<String> tagsAtHead() =>
      _lines(_git(['tag', '--points-at', 'HEAD', '--list', 'v*']));

  @override
  List<String> mergedTags() =>
      _lines(_git(['tag', '--merged', 'HEAD', '--list', 'v*']));

  @override
  List<String> messagesSince(String tag) =>
      _git(['log', '--first-parent', '--format=%B%x00', '$tag..HEAD'])
          .split('\x00')
          .map((m) => m.trim())
          .where((m) => m.isNotEmpty)
          .toList();

  @override
  String headMessage() => _git(['log', '-1', '--format=%B']).trim();

  @override
  int commitCount() {
    if (_git(['rev-parse', '--is-shallow-repository']).trim() == 'true') {
      throw const ProcessException(
        'git',
        ['rev-list', '--count', 'HEAD'],
        'a shallow clone has no build number; fetch the whole history '
            '(actions/checkout with fetch-depth: 0)',
      );
    }
    return int.parse(_git(['rev-list', '--count', 'HEAD']).trim());
  }
}

/// The lines a release build writes its version into, by file relative to
/// the repository root; each file must hold its line exactly once.
///
/// The `xpd` and `xp` executables print `packageVersion`, and the app's
/// `CFBundleShortVersionString` and `CFBundleVersion` come from the
/// `version` of its pubspec (`<version>+<build>`).
Map<String, ({RegExp line, String value})> _versionLines(
  String version,
  int build,
) {
  final pubspecLine = RegExp(r'^version: .*$', multiLine: true);
  final constantLine = RegExp(
    r"^const packageVersion = '[^']*';$",
    multiLine: true,
  );
  return {
    for (final app in ['xpd', 'xp']) ...{
      'apps/$app/pubspec.yaml': (line: pubspecLine, value: 'version: $version'),
      'apps/$app/lib/src/version.dart': (
        line: constantLine,
        value: "const packageVersion = '$version';",
      ),
    },
    'apps/xp_desktop/pubspec.yaml': (
      line: pubspecLine,
      value: 'version: $version+$build',
    ),
  };
}

/// Writes [version] and [build] into the version files of the checkout at
/// [root] (a build checkout: the change is never committed). Returns the
/// files written, relative to [root].
///
/// Throws a [FormatException] for a version that is not a tag's, or when a
/// file does not hold its version line exactly once (nothing is written).
List<String> applyVersion(Directory root, String version, int build) {
  if (!_tagPattern.hasMatch('v$version')) {
    throw FormatException(
      'the version must be <major>.<minor>.<patch>[-<pre-release>]',
      version,
    );
  }
  if (build < 1) throw FormatException('the build must be 1 or more', build);
  final lines = _versionLines(version, build);
  final updated = <String, String>{};
  lines.forEach((path, spec) {
    final file = File(p.join(root.path, path));
    final text = file.readAsStringSync();
    final matches = spec.line.allMatches(text).length;
    if (matches != 1) {
      throw FormatException(
        '$path holds its version line $matches times, not once '
        '(${spec.line.pattern})',
      );
    }
    updated[path] = text.replaceFirst(spec.line, spec.value);
  });
  updated.forEach((path, text) {
    File(p.join(root.path, path)).writeAsStringSync(text);
  });
  return lines.keys.toList();
}

/// Runs `tool/release_version.dart` with [arguments] in the repository at
/// [root] and returns the exit code.
///
///     next [--tag v<version>]   prints the plan as key=value lines
///     apply <version> <build>   writes the version into the checkout
///
/// The plan goes to [out]; the reason, errors and usage go to [err].
int runReleaseVersion(
  List<String> arguments, {
  required Directory root,
  required StringSink out,
  required StringSink err,
  ReleaseHistory? history,
}) {
  try {
    switch (arguments) {
      case ['next']:
      case ['next', '--tag', _]:
        final pubspec = File(p.join(root.path, 'apps/xpd/pubspec.yaml'))
            .readAsStringSync();
        final declared = RegExp(
          r'^version: *(\S+)',
          multiLine: true,
        ).firstMatch(pubspec)?.group(1);
        final pubspecVersion = ReleaseVersion.tryParse(declared ?? '');
        if (pubspecVersion == null) {
          throw FormatException(
            'apps/xpd/pubspec.yaml has no plain version',
            declared,
          );
        }
        final plan = planRelease(
          history: history ?? GitReleaseHistory(root.path),
          pubspecVersion: pubspecVersion,
          tag: arguments.length == 3 ? arguments[2] : null,
        );
        err.writeln(
          'Release ${plan.tag} (build ${plan.build}): ${plan.reason}',
        );
        out.write(plan.toOutput());
        return 0;
      case ['apply', final version, final build]
          when int.tryParse(build) != null:
        final written = applyVersion(root, version, int.parse(build));
        out.writeln('Version $version+$build written to ${written.join(', ')}');
        return 0;
      default:
        err
          ..writeln(
            'Usage: dart run tool/release_version.dart next [--tag v<version>]',
          )
          ..writeln(
            '       dart run tool/release_version.dart apply <version> <build>',
          );
        return 64;
    }
  } on FormatException catch (error) {
    final source = error.source == null ? '' : ' (${error.source})';
    err.writeln('release_version: ${error.message}$source');
    return 1;
  } on Exception catch (error) {
    err.writeln('release_version: $error');
    return 1;
  }
}
