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
XpGroup projectsCommand(XpContext context) =>
    XpGroup(context, 'projects', 'List, add, scan, show and remove projects.', [
      ProjectsListCommand(context),
      ProjectsShowCommand(context),
      ProjectsAddCommand(context),
      ProjectsScanCommand(context),
      ProjectsRemoveCommand(context),
    ]);

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
  return '  flavor ${flavor.name}${flavor.prod ? ' (prod)' : ''}'
      '${android == null ? '' : '  android $android'}'
      '${ios == null ? '' : '  ios $ios'}';
}

/// `xp projects add <folder or repository>`.
class ProjectsAddCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser.addOption(
      'ssh-url',
      help:
          'For a folder whose origin is an HTTPS URL on a host other than '
          'GitHub: the SSH URL to fetch from, as the engine offered it.',
      valueHelp: 'url',
    );
  }

  @override
  String get name => 'add';

  @override
  String get description =>
      'Add a project from a clone on the engine machine, from GitHub, or '
      'from any git host over SSH (git@host:path, ssh:// or file://).';

  @override
  String get invocation =>
      'xp projects add <folder | owner/name | URL> [--ssh-url <url>]';

  @override
  Future<int> execute(XpClient client) async {
    final [source] = positionals(['folder or repository']);
    final sshUrl = argResults!.option('ssh-url');
    final directory = Directory(source);
    // An SSH or file:// URL is a repository, whatever folder has its name.
    final isFolder = GitRemote.parse(source) == null && directory.existsSync();
    if (!isFolder && sshUrl != null) {
      usageException(
        '--ssh-url goes with a folder; give the SSH URL as the repository.',
      );
    }
    final request = isFolder
        ? AddProjectRequest(
            path: p.canonicalize(directory.path),
            sshUrl: sshUrl,
          )
        : AddProjectRequest(remote: source);
    final Project project;
    try {
      project = await client.addProject(request);
    } on ApiException catch (error) {
      if (error case ApiException(
        code: ApiErrorCode.sshUrlRequired,
        sshUrl: final offered?,
      )) {
        logger
          ..err(error.message)
          ..info(
            isFolder
                ? 'Run: xp projects add ${request.path} --ssh-url $offered'
                : 'Run: xp projects add $offered',
          );
        return XpExit.forApi(error);
      }
      rethrow;
    }
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
