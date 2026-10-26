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
  'List, show, validate, create, edit, copy, rename, archive and delete '
      'workflows, compare their versions, and see what they may name.',
  [
    WorkflowsListCommand(context),
    WorkflowsShowCommand(context),
    WorkflowsSchemaCommand(context),
    WorkflowsValidateCommand(context),
    WorkflowsCreateCommand(context),
    WorkflowsEditCommand(context),
    WorkflowsCopyCommand(context),
    WorkflowsRenameCommand(context),
    WorkflowsArchiveCommand(context),
    WorkflowsDeleteCommand(context),
    WorkflowsVersionsCommand(context),
    WorkflowsDiffCommand(context),
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
    final [reference] = await projectPositionals(client, ['project']);
    final workflows = await client.listWorkflows(
      await resolveProject(client, reference),
    );
    emit([for (final workflow in workflows) workflow.toJson()], () {
      return renderTable(
        ['ID', 'NAME', 'VERSION', 'BUILT-IN', 'ARCHIVED'],
        [
          for (final workflow in workflows)
            [
              workflow.id,
              workflow.name,
              '${workflow.version.version}',
              if (workflow.builtin) 'yes' else 'no',
              if (workflow.archived) 'yes' else 'no',
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
    final [projectReference, workflowReference] = await projectPositionals(
      client,
      ['project', 'workflow'],
    );
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

/// `xp workflows schema [--kind <kind>]`.
class WorkflowsSchemaCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser.addOption(
      'kind',
      help: 'One step type, with its keys.',
      valueHelp: 'kind',
    );
  }

  @override
  String get name => 'schema';

  @override
  String get description =>
      'Show what a workflow document may name: the step types and their '
      'keys, the gates and the variables.';

  @override
  String get invocation => 'xp workflows schema [--kind <kind>]';

  @override
  Future<int> execute(XpClient client) async {
    positionals(const []);
    final schema = await client.getWorkflowSchema();
    final kind = argResults!.option('kind');
    if (kind == null) {
      emit(schema.toJson(), () => describeSchema(schema));
      return XpExit.ok;
    }
    final type = schema.steps.where((step) => step.kind == kind).firstOrNull;
    if (type == null) {
      usageException(
        'No step type "$kind". Run xp workflows schema for the list.',
      );
    }
    emit(type.toJson(), () => describeStepType(type));
    return XpExit.ok;
  }
}

/// The step types of [schema] by group, then its gates and variables.
String describeSchema(WorkflowSchema schema) {
  final groups = <String, List<StepType>>{};
  for (final step in schema.steps) {
    (groups[step.group.isEmpty ? 'Other' : step.group] ??= []).add(step);
  }
  return [
    for (final MapEntry(key: group, value: steps) in groups.entries) ...[
      group,
      renderTable(
        const ['KIND', 'TITLE'],
        [
          for (final step in steps) [step.kind, step.title],
        ],
      ).split('\n').skip(1).map((line) => '  $line').join('\n'),
      '',
    ],
    'Gates',
    for (final gate in schema.gates)
      '  $gate${switch (schema.gateLabels[gate]) {
        final label? => '  $label',
        null => '',
      }}',
    '',
    'Variables',
    '  ${schema.variables.join(', ')}',
  ].join('\n');
}

/// [type] with what it does, what runs it and its keys.
String describeStepType(StepType type) => [
  '${type.kind}${type.title.isEmpty ? '' : ': ${type.title}'}',
  if (type.description.isNotEmpty) type.description,
  if (type.capabilities.isNotEmpty) 'Needs ${_runners(type.capabilities)}.',
  if (type.keys.isEmpty)
    'It takes nothing under "with".'
  else ...[
    '',
    renderTable(
      const ['KEY', 'TYPE', 'DESCRIPTION'],
      [
        for (final key in type.keys)
          [
            key.name,
            [
              key.type.name,
              if (key.required) 'required',
              if (key.options case final options?) options.join('|'),
              if (key.defaultValue case final value?) 'default $value',
            ].join(', '),
            key.description,
          ],
      ],
    ),
  ],
].join('\n');

String _runners(List<List<String>> sets) =>
    sets.map((set) => set.join(' and ')).join(', or ');

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
    final [reference, workflowName] = await projectPositionals(client, [
      'project',
      'name',
    ]);
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
    final [projectReference, workflowReference] = await projectPositionals(
      client,
      ['project', 'workflow'],
    );
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

/// The ids of the project and the workflow that [projectReference] and
/// [workflowReference] name.
Future<(String, String)> _projectAndWorkflow(
  XpClient client,
  String projectReference,
  String workflowReference,
) async {
  final projectId = await resolveProject(client, projectReference);
  return (
    projectId,
    await resolveWorkflow(client, projectId, workflowReference),
  );
}

/// `xp workflows copy <project> <workflow> <name>`.
class WorkflowsCopyCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'copy';

  @override
  String get description =>
      'Save the newest version of a workflow, a built-in too, as a new '
      'workflow of your own. A copy of a built-in remembers it, so the app '
      'can compare when the built-in changes.';

  @override
  String get invocation => 'xp workflows copy <project> <workflow> <name>';

  @override
  Future<int> execute(XpClient client) async {
    final [projectReference, workflowReference, newName] =
        await projectPositionals(client, ['project', 'workflow', 'name']);
    final (projectId, workflowId) = await _projectAndWorkflow(
      client,
      projectReference,
      workflowReference,
    );
    final source = await client.getWorkflow(projectId, workflowId);
    final copy = await client.createWorkflow(
      projectId,
      CreateWorkflowRequest(
        name: newName,
        yaml: source.yaml,
        basedOn: source.builtin
            ? WorkflowBasedOn(
                builtin: source.name,
                version: source.version.version,
              )
            : source.basedOn,
      ),
    );
    emit(
      copy.toJson(),
      () => 'Copied ${source.name} to ${copy.name} (${copy.id}).',
    );
    return XpExit.ok;
  }
}

/// `xp workflows rename <project> <workflow> <name>`.
class WorkflowsRenameCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'rename';

  @override
  String get description =>
      'Rename a workflow of your own. Its versions and runs stay.';

  @override
  String get invocation => 'xp workflows rename <project> <workflow> <name>';

  @override
  Future<int> execute(XpClient client) async {
    final [projectReference, workflowReference, newName] =
        await projectPositionals(client, ['project', 'workflow', 'name']);
    final (projectId, workflowId) = await _projectAndWorkflow(
      client,
      projectReference,
      workflowReference,
    );
    final workflow = await client.updateWorkflow(
      projectId,
      workflowId,
      UpdateWorkflowRequest(name: newName),
    );
    emit(workflow.toJson(), () => 'Renamed to ${workflow.name}.');
    return XpExit.ok;
  }
}

/// `xp workflows archive <project> <workflow> [--undo]`.
class WorkflowsArchiveCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser.addFlag(
      'undo',
      negatable: false,
      help: 'Unarchive it: offer it to dispatch again.',
    );
  }

  @override
  String get name => 'archive';

  @override
  String get description =>
      'Archive a workflow of your own: it keeps its versions and runs and is '
      'no longer dispatched. --undo brings it back.';

  @override
  String get invocation => 'xp workflows archive <project> <workflow> [--undo]';

  @override
  Future<int> execute(XpClient client) async {
    final [projectReference, workflowReference] = await projectPositionals(
      client,
      ['project', 'workflow'],
    );
    final (projectId, workflowId) = await _projectAndWorkflow(
      client,
      projectReference,
      workflowReference,
    );
    final undo = argResults!.flag('undo');
    final workflow = await client.updateWorkflow(
      projectId,
      workflowId,
      UpdateWorkflowRequest(archived: !undo),
    );
    emit(
      workflow.toJson(),
      () => undo
          ? 'Unarchived ${workflow.name}.'
          : 'Archived ${workflow.name}. Undo with: xp workflows archive '
                '$projectReference ${workflow.name} --undo',
    );
    return XpExit.ok;
  }
}

/// `xp workflows delete <project> <workflow>`.
class WorkflowsDeleteCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'delete';

  @override
  String get description =>
      'Delete a workflow of your own that never ran. One that ran keeps its '
      'versions for its runs: archive it instead.';

  @override
  String get invocation => 'xp workflows delete <project> <workflow>';

  @override
  Future<int> execute(XpClient client) async {
    final [projectReference, workflowReference] = await projectPositionals(
      client,
      ['project', 'workflow'],
    );
    final (projectId, workflowId) = await _projectAndWorkflow(
      client,
      projectReference,
      workflowReference,
    );
    await client.deleteWorkflow(projectId, workflowId);
    emit({'deleted': workflowId}, () => 'Deleted $workflowReference.');
    return XpExit.ok;
  }
}

/// `xp workflows versions <project> <workflow>`.
class WorkflowsVersionsCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'versions';

  @override
  String get description => 'List the versions of a workflow, newest last.';

  @override
  String get invocation => 'xp workflows versions <project> <workflow>';

  @override
  Future<int> execute(XpClient client) async {
    final [projectReference, workflowReference] = await projectPositionals(
      client,
      ['project', 'workflow'],
    );
    final (projectId, workflowId) = await _projectAndWorkflow(
      client,
      projectReference,
      workflowReference,
    );
    final workflow = await client.getWorkflow(projectId, workflowId);
    emit(
      [for (final version in workflow.versions) version.toJson()],
      () => renderTable(
        ['VERSION', 'SAVED', 'ID'],
        [
          for (final version in workflow.versions)
            ['${version.version}', formatTime(version.createdAt), version.id],
        ],
      ),
    );
    return XpExit.ok;
  }
}

/// `xp workflows diff <project> <workflow> <from> [<to>]`.
class WorkflowsDiffCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'diff';

  @override
  String get description =>
      'Show what changed between two versions of a workflow, as a unified '
      'diff; <to> is the newest by default.';

  @override
  String get invocation =>
      'xp workflows diff <project> <workflow> <from> [<to>]';

  @override
  Future<int> execute(XpClient client) async {
    final rest = argResults!.rest;
    if (rest.length != 3) positionals(['project', 'workflow', 'from', 'to']);
    final [projectReference, workflowReference, fromText, ...more] = rest;
    int version(String text) =>
        int.tryParse(text) ?? usageException('"$text" is not a version.');
    final from = version(fromText);
    final to = more.isEmpty ? null : version(more.single);
    final (projectId, workflowId) = await _projectAndWorkflow(
      client,
      projectReference,
      workflowReference,
    );
    final before = await client.getWorkflow(
      projectId,
      workflowId,
      version: from,
    );
    final after = await client.getWorkflow(projectId, workflowId, version: to);
    final diff = unifiedDiff(before.yaml, after.yaml);
    emit(
      {
        'from': before.version.version,
        'to': after.version.version,
        'diff': diff,
      },
      () => diff.isEmpty
          ? 'Versions ${before.version.version} and '
                '${after.version.version} are the same.'
          : '--- version ${before.version.version}\n'
                '+++ version ${after.version.version}\n'
                '${diff.trimRight()}',
    );
    return XpExit.ok;
  }
}
