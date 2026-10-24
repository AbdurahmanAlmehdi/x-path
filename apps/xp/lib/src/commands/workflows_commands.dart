import 'dart:io';

import 'package:xp/src/commands/xp_command.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/output/format.dart';
import 'package:xp/src/resolve.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

/// `xp workflows`: the workflows of a project.
XpGroup workflowsCommand(XpContext context) => XpGroup(
  context,
  'workflows',
  'List, show, validate, create and edit workflows.',
  [
    WorkflowsListCommand(context),
    WorkflowsShowCommand(context),
    WorkflowsValidateCommand(context),
    WorkflowsCreateCommand(context),
    WorkflowsEditCommand(context),
  ],
);

/// `xp workflows list <project>`.
class WorkflowsListCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'list';

  @override
  String get description => 'List the workflows of a project.';

  @override
  String get invocation => 'xp workflows list <project>';

  @override
  Future<int> execute(XpClient client) async {
    final [reference] = positionals(['project']);
    final workflows = await client.listWorkflows(
      await resolveProject(client, reference),
    );
    emit([for (final workflow in workflows) workflow.toJson()], () {
      return renderTable(
        ['ID', 'NAME', 'VERSION', 'BUILT-IN'],
        [
          for (final workflow in workflows)
            [
              workflow.id,
              workflow.name,
              '${workflow.version.version}',
              if (workflow.builtin) 'yes' else 'no',
            ],
        ],
      );
    });
    return XpExit.ok;
  }
}

/// `xp workflows show <project> <workflow>`.
class WorkflowsShowCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser.addOption(
      'version',
      help: 'A version of the workflow (the newest by default).',
      valueHelp: 'number',
    );
  }

  @override
  String get name => 'show';

  @override
  String get description => 'Print the YAML of a workflow.';

  @override
  String get invocation => 'xp workflows show <project> <workflow>';

  @override
  Future<int> execute(XpClient client) async {
    final [projectReference, workflowReference] = positionals([
      'project',
      'workflow',
    ]);
    final versionText = argResults!.option('version');
    final version = versionText == null ? null : int.tryParse(versionText);
    if (versionText != null && version == null) {
      usageException('--version must be a number.');
    }
    final projectId = await resolveProject(client, projectReference);
    final workflow = await client.getWorkflow(
      projectId,
      await resolveWorkflow(client, projectId, workflowReference),
      version: version,
    );
    emit(workflow.toJson(), workflow.yaml.trimRight);
    return XpExit.ok;
  }
}

/// Reads the workflow document at `--file`.
String readWorkflowFile(XpCommand command) {
  final path = command.argResults!.option('file');
  if (path == null) command.usageException('--file is required.');
  return readWorkflowAt(command, path);
}

/// Reads the workflow document at [path].
String readWorkflowAt(XpCommand command, String path) {
  final file = File(path);
  if (!file.existsSync()) command.usageException('No such file: $path');
  return file.readAsStringSync();
}

/// `xp workflows validate <file>`.
class WorkflowsValidateCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser.addOption(
      'file',
      abbr: 'f',
      help: 'The workflow document, instead of <file>.',
      valueHelp: 'path',
    );
  }

  @override
  String get name => 'validate';

  @override
  String get description =>
      'Check a workflow document against the engine, line by line. A '
      'document is valid or not for every project alike.';

  @override
  String get invocation => 'xp workflows validate <file>';

  @override
  Future<int> execute(XpClient client) async {
    final String yaml;
    if (argResults!.option('file') != null) {
      // `xp workflows validate <project> --file <file>` still works: the
      // project changes nothing.
      if (argResults!.rest.length > 1) positionals(['project']);
      yaml = readWorkflowFile(this);
    } else {
      final [path] = positionals(['file']);
      yaml = readWorkflowAt(this, path);
    }
    final result = await client.validateWorkflow(null, yaml);
    emit(result.toJson(), () {
      return result.valid
          ? 'The workflow is valid.'
          : 'The workflow has issues:\n${describeIssues(result.issues)}';
    });
    return result.valid ? XpExit.ok : XpExit.invalid;
  }
}

/// `xp workflows create <project> <name> --file <file>`.
class WorkflowsCreateCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser.addOption(
      'file',
      abbr: 'f',
      help: 'The workflow document.',
      valueHelp: 'path',
    );
  }

  @override
  String get name => 'create';

  @override
  String get description => 'Create a workflow from a file.';

  @override
  String get invocation => 'xp workflows create <project> <name> --file <file>';

  @override
  Future<int> execute(XpClient client) async {
    final [reference, workflowName] = positionals(['project', 'name']);
    final yaml = readWorkflowFile(this);
    final workflow = await client.createWorkflow(
      await resolveProject(client, reference),
      CreateWorkflowRequest(name: workflowName, yaml: yaml),
    );
    emit(
      workflow.toJson(),
      () =>
          'Created ${workflow.name} (${workflow.id}), version '
          '${workflow.version.version}.',
    );
    return XpExit.ok;
  }
}

/// `xp workflows edit <project> <workflow> --file <file>`.
class WorkflowsEditCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser.addOption(
      'file',
      abbr: 'f',
      help: 'The new workflow document.',
      valueHelp: 'path',
    );
  }

  @override
  String get name => 'edit';

  @override
  String get description =>
      'Save a file as a new version of a workflow of your own.';

  @override
  String get invocation =>
      'xp workflows edit <project> <workflow> --file <file>';

  @override
  Future<int> execute(XpClient client) async {
    final [projectReference, workflowReference] = positionals([
      'project',
      'workflow',
    ]);
    final yaml = readWorkflowFile(this);
    final projectId = await resolveProject(client, projectReference);
    final workflowId = await resolveWorkflow(
      client,
      projectId,
      workflowReference,
    );
    final workflow = await client.saveWorkflow(projectId, workflowId, yaml);
    emit(
      workflow.toJson(),
      () => 'Saved version ${workflow.version.version} of ${workflow.name}.',
    );
    return XpExit.ok;
  }
}
