import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/scan/app_scanner.dart';
import 'package:xp_engine/src/scan/scan_context.dart';
import 'package:xp_engine/src/scan/scan_source.dart';
import 'package:yaml/yaml.dart';

/// What a scan produced.
class ScanResult extends Equatable {
  /// Creates a result.
  const new({required this.profile, required this.findings});

  /// The repository's apps, flavors and identifiers.
  final ProjectProfile profile;

  /// What the scan noticed, most severe first.
  final List<Finding> findings;

  @override
  List<Object?> get props => [profile, findings];
}

/// Reads a Flutter repository and describes it (D-04: read-only).
///
/// It finds the apps (one at the root, or the members of a pub workspace or
/// Melos monorepo), their flavors from Gradle, `flutter_flavorizr`, Xcode
/// schemes and `lib/main_*.dart`, the bundle and application id of every
/// flavor, how versions are written, Shorebird ids, the iOS package manager,
/// signing teams, the keystore reference, the `.fvmrc` pin, the branch layout
/// and the workflow files of the repository. What it cannot make sense of
/// becomes a [Finding] with a fix, not an exception.
class ProjectScanner {
  /// Creates a scanner.
  const new();

  /// Scans the repository that [source] shows.
  Future<ScanResult> scan(ScanSource source) async {
    final context = ScanContext(source);
    final rootPubspec = await context.yaml(
      'pubspec.yaml',
      invalid: (error) => context.add(
        FindingSeverity.error,
        'pubspec_invalid',
        'pubspec.yaml is not valid YAML: $error',
        'Fix the syntax error in pubspec.yaml.',
        path: 'pubspec.yaml',
      ),
    );
    final melosConfig =
        _map(rootPubspec?['melos']) ?? await context.yaml('melos.yaml');
    final members = [
      ..._strings(rootPubspec?['workspace']),
      ..._strings(melosConfig?['packages']),
    ];

    final directories = <String>{'', ...await _expand(source, members)};
    final apps = <AppProfile>[];
    for (final dir in directories) {
      final pubspec = dir.isEmpty
          ? rootPubspec
          : await context.yaml(
              joinScanPath(dir, 'pubspec.yaml'),
              invalid: (error) => context.add(
                FindingSeverity.warning,
                'pubspec_invalid',
                '${joinScanPath(dir, 'pubspec.yaml')} is not valid YAML: '
                    '$error',
                'Fix the syntax error in the pubspec.',
                path: joinScanPath(dir, 'pubspec.yaml'),
              ),
            );
      final app = await scanApp(context, dir, pubspec);
      if (app != null) apps.add(app);
    }
    if (apps.isEmpty) {
      context.add(
        FindingSeverity.error,
        'no_flutter_app',
        'No Flutter app was found: nothing with a Flutter dependency and an '
            'android/ or ios/ project.',
        'Point XPath at the root of a Flutter app or of a workspace that '
            'contains one, or fill the profile in by hand.',
      );
    }

    final profile = ProjectProfile(
      layout: rootPubspec?['workspace'] != null || melosConfig != null
          ? ProjectLayout.melos
          : ProjectLayout.single,
      apps: apps,
      branches: await _branches(source),
      workflows: await _workflows(context),
    );
    const order = FindingSeverity.values;
    final findings = [...context.findings]
      ..sort((a, b) => order.indexOf(a.severity) - order.indexOf(b.severity));
    return ScanResult(profile: profile, findings: findings);
  }
}

YamlMap? _map(Object? value) => value is YamlMap ? value : null;

List<String> _strings(Object? value) => [
  if (value is YamlList)
    for (final entry in value)
      if (entry is String) entry,
];

/// The directories that the workspace members and Melos package globs name,
/// minus those that `!` patterns exclude. Only `dir`, `dir/*` and `dir/**` are
/// understood.
Future<List<String>> _expand(ScanSource source, List<String> patterns) async {
  Future<List<String>> directoriesOf(String pattern) async {
    final cleaned = normalizeScanPath(pattern.replaceAll(RegExp(r'/+$'), ''));
    if (cleaned.endsWith('/*') || cleaned.endsWith('/**')) {
      final base = cleaned.substring(0, cleaned.indexOf('/*'));
      return [
        for (final entry in await source.list(base))
          if (entry.isDirectory) joinScanPath(base, entry.name),
      ];
    }
    return [if (cleaned.isNotEmpty) cleaned];
  }

  final included = <String>[];
  final excluded = <String>{};
  for (final pattern in patterns) {
    if (pattern.startsWith('!')) {
      excluded.addAll(await directoriesOf(pattern.substring(1)));
    } else {
      included.addAll(await directoriesOf(pattern));
    }
  }
  return included.where((directory) => !excluded.contains(directory)).toList();
}

// ------------------------------------------------------------------ branches

/// The branches that the repository's own `.git` shows: loose and packed refs
/// under `refs/heads` and `refs/remotes/origin`. A folder without `.git`, such
/// as a worktree of the engine's mirror, shows none.
Future<BranchLayout> _branches(ScanSource source) async {
  final names = <String>{};
  final packed = await source.read('.git/packed-refs');
  for (final line in (packed ?? '').split('\n')) {
    final parts = line.trim().split(' ');
    if (parts.length == 2 && !line.startsWith('^')) {
      names.addAll(_branchOf(parts[1]));
    }
  }
  for (final root in const ['heads', 'remotes/origin']) {
    for (final ref in await _walk(source, '.git/refs/$root')) {
      names.addAll(_branchOf('refs/$root/$ref'));
    }
  }
  final head = await source.read('.git/refs/remotes/origin/HEAD');
  final defaultBranch = RegExp(r'ref:\s*refs/remotes/origin/(\S+)')
      .firstMatch(head ?? '')
      ?.group(1);
  return BranchLayout(
    defaultBranch: defaultBranch,
    releaseBranches:
        (names.where((name) => name.startsWith('release/')).toList()..sort()),
  );
}

Iterable<String> _branchOf(String ref) sync* {
  for (final prefix in const ['refs/heads/', 'refs/remotes/origin/']) {
    if (ref.startsWith(prefix)) {
      final name = ref.substring(prefix.length);
      if (name != 'HEAD') yield name;
    }
  }
}

/// The files below [directory], as paths relative to it.
Future<List<String>> _walk(
  ScanSource source,
  String directory, {
  int depth = 0,
}) async {
  if (depth > 6) return const [];
  final files = <String>[];
  for (final entry in await source.list(directory)) {
    if (entry.isDirectory) {
      files.addAll([
        for (final child in await _walk(
          source,
          '$directory/${entry.name}',
          depth: depth + 1,
        ))
          '${entry.name}/$child',
      ]);
    } else {
      files.add(entry.name);
    }
  }
  return files;
}

// ----------------------------------------------------------------- workflows

Future<List<RepoWorkflow>> _workflows(ScanContext context) async {
  final workflows = <RepoWorkflow>[];
  void invalid(String path) => context.add(
    FindingSeverity.warning,
    'workflow_yaml_invalid',
    '$path is not valid YAML, so its workflows are not listed.',
    'Fix the syntax error.',
    path: path,
  );

  const directory = '.github/workflows';
  for (final entry in await context.source.list(directory)) {
    final stem = entry.name.endsWith('.yml')
        ? entry.name.substring(0, entry.name.length - 4)
        : entry.name.endsWith('.yaml')
        ? entry.name.substring(0, entry.name.length - 5)
        : null;
    if (entry.isDirectory || stem == null) continue;
    final path = '$directory/${entry.name}';
    var failed = false;
    final yaml = await context.yaml(
      path,
      invalid: (_) {
        failed = true;
        invalid(path);
      },
    );
    if (failed) continue;
    workflows.add(
      RepoWorkflow(
        path: path,
        provider: 'github_actions',
        names: ['${yaml?['name'] ?? stem}'],
      ),
    );
  }

  for (final path in const ['codemagic.yaml', 'codemagic.yml']) {
    if (!await context.source.exists(path)) continue;
    var failed = false;
    final yaml = await context.yaml(
      path,
      invalid: (_) {
        failed = true;
        invalid(path);
      },
    );
    if (failed) continue;
    final entries = _map(yaml?['workflows']);
    workflows.add(
      RepoWorkflow(
        path: path,
        provider: 'codemagic',
        names: [
          if (entries != null)
            for (final entry in entries.entries)
              '${_map(entry.value)?['name'] ?? entry.key}',
        ],
      ),
    );
  }
  return workflows;
}
