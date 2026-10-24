import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp/src/commands/xp_command.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/output/format.dart';
import 'package:xp/src/resolve.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

/// `xp projects`: the repositories XPath releases.
XpGroup projectsCommand(XpContext context) => XpGroup(
  context,
  'projects',
  'List, add, scan, show, edit and remove projects.',
  [
    ProjectsListCommand(context),
    ProjectsShowCommand(context),
    ProjectsAddCommand(context),
    ProjectsScanCommand(context),
    ProjectsSetCommand(context),
    ProjectsRemoveCommand(context),
  ],
);

/// `xp projects list`.
class ProjectsListCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'list';

  @override
  String get description => 'List the projects.';

  @override
  Future<int> execute(XpClient client) async {
    final projects = await client.listProjects();
    emit([for (final project in projects) project.toJson()], () {
      if (projects.isEmpty) {
        return 'No projects. Add one: xp projects add <owner/name>';
      }
      return renderTable(
        ['ID', 'REPOSITORY', 'BRANCH', 'APPS', 'SCANNED'],
        [
          for (final project in projects)
            [
              project.id,
              project.fullName,
              project.defaultBaseBranch,
              '${project.profile.apps.length}',
              formatTime(project.scannedAt),
            ],
        ],
      );
    });
    return XpExit.ok;
  }
}

/// `xp projects show <project>`.
class ProjectsShowCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'show';

  @override
  String get description => 'Show a project, its apps and what the scan found.';

  @override
  String get invocation => 'xp projects show <project>';

  @override
  Future<int> execute(XpClient client) async {
    final [reference] = positionals(['project']);
    final project = await client.getProject(
      await resolveProject(client, reference),
    );
    emit(project.toJson(), () => describeProject(project));
    return XpExit.ok;
  }
}

/// The lines `xp projects show` prints.
String describeProject(Project project) {
  final lines = [
    '${project.fullName} (${project.id})',
    'remote:   ${project.remote}',
    'branch:   ${project.defaultBaseBranch}',
    'scanned:  ${formatTime(project.scannedAt)}',
    for (final app in project.profile.apps) ...[
      '',
      _describeApp(app),
      for (final flavor in app.flavors) _describeFlavor(flavor),
    ],
    if (project.findings.isNotEmpty) ...[
      '',
      'findings:',
      for (final finding in project.findings)
        '  ${finding.severity.name}: ${finding.message}  (fix: ${finding.fix})',
    ],
  ];
  return lines.join('\n');
}

String _describeApp(AppProfile app) {
  final version = app.version;
  return 'app ${app.name} (${app.path}), ${app.framework}'
      '${version == null ? '' : ' $version'}';
}

String _describeFlavor(FlavorProfile flavor) {
  final android = flavor.androidAppId;
  final ios = flavor.iosBundleId;
  final firebase = flavor.firebaseAppId ?? const {};
  final apple = flavor.appleAppId;
  final head =
      '  flavor ${flavor.name}${flavor.prod ? ' (prod)' : ''}'
      '${android == null ? '' : '  android $android'}'
      '${ios == null ? '' : '  ios $ios'}';
  return [
    head,
    for (final MapEntry(key: platform, value: id) in firebase.entries)
      '    firebase $platform: $id',
    if (apple != null) '    app store: $apple',
  ].join('\n');
}

/// A remote, whatever host: `git@host:path`, or a `ssh://`, `file://`,
/// `http://` or `https://` URL. These are never taken for a folder.
final _remote = RegExp(r'^([\w.-]+@[\w.-]+:|(ssh|file|https?)://)');

/// A folder, not `owner/name`: it starts with `/`, `.` or `~`.
final _pathLike = RegExp('^[/.~]');

/// `xp projects add <folder or owner/name>`.
class ProjectsAddCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'add';

  @override
  String get description =>
      'Add a project from a clone on the engine machine or from GitHub.';

  @override
  String get invocation => 'xp projects add <folder | owner/name | URL>';

  @override
  Future<int> execute(XpClient client) async {
    final [source] = positionals(['folder or repository']);
    final request = switch (source) {
      _ when _remote.hasMatch(source) => AddProjectRequest(remote: source),
      _ when Directory(source).existsSync() => AddProjectRequest(
        path: p.canonicalize(source),
      ),
      _ when _pathLike.hasMatch(source) => usageException(
        'No folder at $source.',
      ),
      _ => AddProjectRequest(remote: source),
    };
    final project = await client.addProject(request);
    emit(
      project.toJson(),
      () =>
          'Added ${project.fullName} (${project.id}).\n\n'
          '${describeProject(project)}',
    );
    return XpExit.ok;
  }
}

/// `xp projects scan <project>`.
class ProjectsScanCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'scan';

  @override
  String get description => 'Scan a project again.';

  @override
  String get invocation => 'xp projects scan <project>';

  @override
  Future<int> execute(XpClient client) async {
    final [reference] = positionals(['project']);
    final project = await client.scanProject(
      await resolveProject(client, reference),
    );
    emit(
      project.toJson(),
      () => 'Scanned ${project.fullName}.\n\n${describeProject(project)}',
    );
    return XpExit.ok;
  }
}

/// `xp projects set <project> --flavor <name> ...`: edits a flavor of the
/// profile. Edits survive rescans.
class ProjectsSetCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser
      ..addOption('app', help: 'The app, by path (`.` for the root).')
      ..addOption('flavor', help: 'The flavor to edit.')
      ..addMultiOption(
        'firebase-app-id',
        help:
            'The Firebase app id of a platform, platform=id; an empty id '
            'removes it. Repeatable.',
        valueHelp: 'android=1:123:android:abc',
      )
      ..addOption(
        'apple-app-id',
        help: 'The App Store Connect app id; empty removes it.',
      );
  }

  @override
  String get name => 'set';

  @override
  String get description =>
      'Set the store ids of a flavor, which the built-in workflows upload to.';

  @override
  String get invocation =>
      'xp projects set <project> --flavor <name> '
      '[--firebase-app-id <platform=id>] [--apple-app-id <id>]';

  @override
  Future<int> execute(XpClient client) async {
    final [reference] = positionals(['project']);
    final results = argResults!;
    final firebase = <String, String>{};
    for (final value in results.multiOption('firebase-app-id')) {
      final split = value.indexOf('=');
      if (split < 1) {
        usageException('--firebase-app-id must be platform=id, not "$value".');
      }
      firebase[value.substring(0, split)] = value.substring(split + 1);
    }
    final flavor = results.option('flavor') ?? usageException('Give --flavor.');
    final apple = results.option('apple-app-id');
    if (firebase.isEmpty && apple == null) {
      usageException('Give --firebase-app-id, --apple-app-id or both.');
    }
    final id = await resolveProject(client, reference);
    final project = await client.updateProject(
      id,
      ProfileEdits(
        apps: [
          AppEdit(
            path: results.option('app') ?? await _onlyApp(client, id),
            flavors: [
              FlavorEdit(
                name: flavor,
                firebaseAppId: firebase.isEmpty ? null : firebase,
                appleAppId: apple,
              ),
            ],
          ),
        ],
      ),
    );
    emit(project.toJson(), () => describeProject(project));
    return XpExit.ok;
  }

  /// The path of the only app of the project; a usage error with more.
  Future<String> _onlyApp(XpClient client, String id) async {
    final apps = (await client.getProject(id)).profile.apps;
    if (apps.length == 1) return apps.single.path;
    usageException(
      'Give --app: the project has the apps '
      '${apps.map((app) => app.path).join(', ')}.',
    );
  }
}

/// `xp projects remove <project>`.
class ProjectsRemoveCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'remove';

  @override
  String get description => 'Remove a project. Its folder is never touched.';

  @override
  String get invocation => 'xp projects remove <project>';

  @override
  Future<int> execute(XpClient client) async {
    final [reference] = positionals(['project']);
    final id = await resolveProject(client, reference);
    await client.removeProject(id);
    emit({'removed': id}, () => 'Removed $id.');
    return XpExit.ok;
  }
}
