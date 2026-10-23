import 'dart:async';

import 'package:json_annotation/json_annotation.dart';
import 'package:xp/src/mcp/mcp_tool.dart';
import 'package:xp/src/output/error_json.dart';
import 'package:xp/src/resolve.dart';
import 'package:xp/src/run_approvals.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

/// What `xp mcp` tells the agent about itself when it connects.
const mcpInstructions = '''
XPath releases Flutter apps. These tools read projects, workflows, runs, jobs, logs, releases, approvals, test runs, storage, credentials (never a secret) and runners; create and edit projects and workflows (a workflow is checked first and its errors come back with their lines); and dispatch workflows.

Gated actions (a production release, a production OTA patch, a store submission, a push, a merge, a delete) wait for the owner's approval. This server can never approve or deny: when a dispatched run reaches a gate, get_run shows it as waiting_for_approval with the pending approval ids; tell the owner, who approves in the XPath app or with `xp approvals approve <id>`, and poll get_approval until its state is no longer pending. Expired counts as denied.

Projects can be named by id (prj_...), owner/name or just name. Workflows by id (wf_...) or name.''';

/// The tools of `xp mcp`, over [client].
///
/// There is no tool to approve, deny, loosen a gate, merge, abandon or delete:
/// MCP tokens can never approve or loosen gates (D-13), and the engine answers
/// `403` if one tries, but an agent should not even be offered the call.
/// [tailIdle] is how long a log read waits for another line.
List<McpTool> buildXpTools(
  XpClient client, {
  Duration tailIdle = const Duration(seconds: 1),
}) {
  McpTool tool(
    String name,
    String description,
    Map<String, Object?> properties,
    Future<Object?> Function(McpArgs args) body, {
    List<String> required = const [],
    bool readOnly = false,
    bool Function(Object? result)? failed,
  }) => McpTool(
    name: name,
    description: description,
    readOnly: readOnly,
    inputSchema: {
      'type': 'object',
      'properties': properties,
      'required': required,
    },
    handler: (arguments) => _guard(() async {
      final result = await body(McpArgs(arguments));
      return McpToolResult.json(result, isError: failed?.call(result) ?? false);
    }),
  );

  Map<String, Object?> text(String description, {List<String>? values}) => {
    'type': 'string',
    'description': description,
    'enum': ?values,
  };
  Map<String, Object?> integer(String description) => {
    'type': 'integer',
    'description': description,
  };
  Map<String, Object?> strings(String description) => {
    'type': 'array',
    'items': {'type': 'string'},
    'description': description,
  };
  final project = text('The project: id (prj_...), owner/name or name.');
  final workflow = text('The workflow: id (wf_...) or name.');

  Future<String> projectId(McpArgs args) =>
      resolveProject(client, args.string('project'));
  final dispatchArgs = <String, Object?>{
    'project': project,
    'workflow': workflow,
    'ref': text('Branch, tag or commit; the base branch by default.'),
    'app': text('The app by path ("." for the root).'),
    'flavors': strings('The flavors to run for.'),
    'platforms': strings('"android" and/or "ios".'),
    'bump': text(
      'How to bump the version.',
      values: [for (final bump in VersionBump.values) bump.wire],
    ),
    'version': text('The version x.y.z to release, instead of bump.'),
    'releaseVersion': text('The release x.y.z+build a patch applies to.'),
    'inputs': {
      'type': 'object',
      'description':
          'The inputs the workflow declares, by name. get_workflow lists '
          'them with their type: string (text), boolean (true or false), '
          'choice (one of its options), json (any JSON value) or release '
          '(x.y.z+build; the releaseVersion when it gives none). An input '
          'without a type takes any value.',
    },
  };
  DispatchRequest dispatchRequestOf(McpArgs args) {
    final bump = args.optionalString('bump');
    return DispatchRequest(
      ref: args.optionalString('ref'),
      app: args.optionalString('app'),
      flavors: args.optionalStrings('flavors'),
      platforms: args.optionalStrings('platforms'),
      bump: bump == null
          ? null
          : VersionBump.values.firstWhere((value) => value.wire == bump),
      version: args.optionalString('version'),
      releaseVersion: args.optionalString('releaseVersion'),
      inputs: args.optionalObject('inputs') ?? const {},
    );
  }

  return [
    tool(
      'list_projects',
      'List the projects, each with its apps, flavors and the findings of the '
          'last scan.',
      {},
      (args) async => [
        for (final project in await client.listProjects()) project.toJson(),
      ],
      readOnly: true,
    ),
    tool(
      'get_project',
      'Show one project with its profile and findings.',
      {'project': project},
      (args) async => (await client.getProject(await projectId(args))).toJson(),
      required: ['project'],
      readOnly: true,
    ),
    tool(
      'add_project',
      'Add a GitHub repository as a project and scan it. Give a folder on the '
          "engine's machine, or a repository as owner/name or URL.",
      {
        'path': text('An absolute folder on the engine machine with a clone.'),
        'remote': text('owner/name, or an https or ssh URL.'),
      },
      (args) async {
        final path = args.optionalString('path');
        final remote = args.optionalString('remote');
        if ((path == null) == (remote == null)) {
          throw const McpArgumentError('Give exactly one of "path", "remote".');
        }
        return (await client.addProject(
          AddProjectRequest(path: path, remote: remote),
        )).toJson();
      },
    ),
    tool(
      'scan_project',
      'Scan a project again (read-only; the repository is never changed).',
      {'project': project},
      (args) async =>
          (await client.scanProject(await projectId(args))).toJson(),
      required: ['project'],
    ),
    tool(
      'update_project',
      "Edit the project's profile: the base branch, and per app the store "
          'country and per flavor prod, shorebird, entrypoint, iosBundleId, '
          'androidAppId, versionFiles, firebaseAppId ({"android": "1:..."}; '
          'an empty id removes it) and appleAppId, which the built-in '
          'workflows upload to when no input gives one. Edits survive '
          'rescans.',
      {
        'project': project,
        'edits': {
          'type': 'object',
          'description':
              'ProfileEdits: {"defaultBaseBranch": "main", "apps": [{"path": '
              '".", "storeCountry": "us", "flavors": [{"name": "prod", '
              '"prod": true}]}]}',
        },
      },
      (args) async {
        final edits = args.optionalObject('edits');
        if (edits == null) throw const McpArgumentError('"edits" is required.');
        return (await client.updateProject(
          await projectId(args),
          ProfileEdits.fromJson(edits),
        )).toJson();
      },
      required: ['project', 'edits'],
    ),
    tool(
      'list_workflows',
      'List the workflows of a project: the built-in ones (dev-build, '
          'prod-release, shorebird-patch, test) and its own.',
      {'project': project},
      (args) async => [
        for (final workflow in await client.listWorkflows(
          await projectId(args),
        ))
          workflow.toJson(),
      ],
      required: ['project'],
      readOnly: true,
    ),
    tool(
      'get_workflow',
      'Show a workflow with its YAML, at a version or the newest.',
      {
        'project': project,
        'workflow': workflow,
        'version': integer('A version number; the newest by default.'),
      },
      (args) async {
        final id = await projectId(args);
        return (await client.getWorkflow(
          id,
          await resolveWorkflow(client, id, args.string('workflow')),
          version: args.optionalInt('version'),
        )).toJson();
      },
      required: ['project', 'workflow'],
      readOnly: true,
    ),
    tool(
      'validate_workflow',
      'Check a workflow document without saving it. Returns the issues with '
          'their line and column.',
      {'project': project, 'yaml': text('The workflow document.')},
      (args) async => _validation(
        await client.validateWorkflow(
          await projectId(args),
          args.string('yaml'),
        ),
        saved: false,
      ),
      required: ['project', 'yaml'],
      readOnly: true,
    ),
    tool(
      'create_workflow',
      'Create a workflow. The document is checked first; with issues nothing '
          'is saved and the issues come back with their lines.',
      {
        'project': project,
        'name': text('Letters, digits, ".", "_" and "-".'),
        'yaml': text('The workflow document.'),
      },
      (args) async {
        final id = await projectId(args);
        final yaml = args.string('yaml');
        final check = await client.validateWorkflow(id, yaml);
        if (!check.valid) return _validation(check, saved: false);
        return (await client.createWorkflow(
          id,
          CreateWorkflowRequest(name: args.string('name'), yaml: yaml),
        )).toJson();
      },
      required: ['project', 'name', 'yaml'],
      failed: _isInvalid,
    ),
    tool(
      'update_workflow',
      "Save a new version of a workflow of the project's own (not a built-in "
          'one). The document is checked first; with issues nothing is saved '
          'and the issues come back with their lines.',
      {
        'project': project,
        'workflow': workflow,
        'yaml': text('The new workflow document.'),
      },
      (args) async {
        final id = await projectId(args);
        final yaml = args.string('yaml');
        final check = await client.validateWorkflow(id, yaml);
        if (!check.valid) return _validation(check, saved: false);
        return (await client.saveWorkflow(
          id,
          await resolveWorkflow(client, id, args.string('workflow')),
          yaml,
        )).toJson();
      },
      required: ['project', 'workflow', 'yaml'],
      failed: _isInvalid,
    ),
    tool(
      'dispatch_workflow',
      'Run a workflow. Returns the run. A workflow that reaches a gated '
          'action (a production release, for one) stops there: the run '
          'becomes waiting_for_approval and an approval is pending. Poll '
          'get_run for the approval ids, then get_approval; only the owner '
          'can approve.',
      dispatchArgs,
      (args) async {
        final id = await projectId(args);
        final run = await client.dispatchWorkflow(
          id,
          await resolveWorkflow(client, id, args.string('workflow')),
          dispatchRequestOf(args),
        );
        return await _runWithApprovals(client, run);
      },
      required: ['project', 'workflow'],
    ),
    tool(
      'plan_dispatch',
      'What dispatch_workflow would start, planned by the engine; nothing '
          'starts and no build number is taken. Lists the jobs of each stage '
          'and where each would run (or why it would wait), the jobs it '
          'leaves out and why (skipped), the gates, and the version and '
          'build number. A skipped job that blocks means dispatch_workflow '
          'would be refused; fix what its reason says first.',
      dispatchArgs,
      (args) async {
        final id = await projectId(args);
        return (await client.planDispatch(
          id,
          await resolveWorkflow(client, id, args.string('workflow')),
          dispatchRequestOf(args),
        )).toJson();
      },
      required: ['project', 'workflow'],
      readOnly: true,
    ),
    tool(
      'get_run',
      'Show a run and its jobs. While it waits for the owner, '
          'pendingApprovals lists the approvals to poll.',
      {'run': text('The run id (run_...).')},
      (args) async => await _runWithApprovals(
        client,
        await client.getRun(args.string('run')),
      ),
      required: ['run'],
      readOnly: true,
    ),
    tool(
      'get_job',
      'Show a job with its steps and their results.',
      {'job': text('The job id (job_...).')},
      (args) async => (await client.getJob(args.string('job'))).toJson(),
      required: ['job'],
      readOnly: true,
    ),
    tool(
      'get_job_log_tail',
      'The last lines of the log of a job (masked: secrets read ***).',
      {
        'job': text('The job id (job_...).'),
        'lines': integer('How many lines at most; 100 by default.'),
      },
      (args) async => await _tail(
        client,
        args.string('job'),
        args.optionalInt('lines') ?? 100,
        tailIdle,
      ),
      required: ['job'],
      readOnly: true,
    ),
    tool(
      'list_artifacts',
      'List the files a job produced (builds, manifests, symbols).',
      {'job': text('The job id (job_...).')},
      (args) async => [
        for (final artifact in await client.listJobArtifacts(
          args.string('job'),
        ))
          artifact.toJson(),
      ],
      required: ['job'],
      readOnly: true,
    ),
    tool(
      'get_job_tests',
      'The test run of a job with what changed against the baseline. By '
          'default only the failures are listed.',
      {
        'job': text('The job id (job_...).'),
        'statuses': strings('passed, failed, errored, skipped.'),
        'limit': integer('How many tests at most (1 to 1000).'),
        'offset': integer('How many tests to skip.'),
      },
      (args) async {
        final statuses = args.optionalStrings('statuses');
        return (await client.getJobTests(
          args.string('job'),
          statuses: statuses == null
              ? null
              : {
                  for (final wire in statuses)
                    TestStatus.values.firstWhere(
                      (status) => status.wire == wire,
                      orElse: () =>
                          throw McpArgumentError('Unknown status "$wire".'),
                    ),
                },
          limit: args.optionalInt('limit'),
          offset: args.optionalInt('offset'),
        )).toJson();
      },
      required: ['job'],
      readOnly: true,
    ),
    tool(
      'get_test_baselines',
      'The test runs that new runs of a project are compared with.',
      {'project': project},
      (args) async => [
        for (final baseline in await client.getTestBaselines(
          await projectId(args),
        ))
          baseline.toJson(),
      ],
      required: ['project'],
      readOnly: true,
    ),
    tool(
      'list_releases',
      'List the releases, newest first.',
      {
        'project': project,
        'app': text('Only this app path.'),
        'state': text(
          'Only this state.',
          values: [for (final state in ReleaseState.values) state.wire],
        ),
      },
      (args) async {
        final reference = args.optionalString('project');
        final state = args.optionalString('state');
        return [
          for (final release in await client.listReleases(
            projectId: reference == null
                ? null
                : await resolveProject(client, reference),
            app: args.optionalString('app'),
            state: state == null
                ? null
                : ReleaseState.values.firstWhere((s) => s.wire == state),
          ))
            release.toJson(),
        ];
      },
      readOnly: true,
    ),
    tool(
      'get_release',
      'Show a release with its state in each store.',
      {'release': text('The release id (rel_...).')},
      (args) async =>
          (await client.getRelease(args.string('release'))).toJson(),
      required: ['release'],
      readOnly: true,
    ),
    tool(
      'get_release_notes',
      'What changed in a release, ready to paste (Slack and WhatsApp text).',
      {'release': text('The release id (rel_...).')},
      (args) async =>
          (await client.getReleaseNotes(args.string('release'))).toJson(),
      required: ['release'],
      readOnly: true,
    ),
    tool(
      'list_approvals',
      'List the approvals, newest first.',
      {
        'project': project,
        'state': text(
          'Only this state.',
          values: [for (final state in ApprovalState.values) state.wire],
        ),
        'run': text('Only the approvals a run asked for.'),
      },
      (args) async {
        final reference = args.optionalString('project');
        final state = args.optionalString('state');
        final run = args.optionalString('run');
        return [
          for (final approval in await client.listApprovals(
            projectId: reference == null
                ? null
                : await resolveProject(client, reference),
            state: state == null
                ? null
                : ApprovalState.values.firstWhere((s) => s.wire == state),
          ))
            if (run == null || approval.runId == run) approval.toJson(),
        ];
      },
      readOnly: true,
    ),
    tool(
      'get_approval',
      'Poll an approval by id. The state is pending until the owner decides; '
          'approved, denied or expired (which counts as denied) end it.',
      {'approval': text('The approval id (apr_...).')},
      (args) async =>
          (await client.getApproval(args.string('approval'))).toJson(),
      required: ['approval'],
      readOnly: true,
    ),
    tool(
      'get_gates',
      "Which actions of a project wait for the owner's approval. Read-only: "
          'gates cannot be changed from here.',
      {'project': project},
      (args) async => (await client.getGates(await projectId(args))).toJson(),
      required: ['project'],
      readOnly: true,
    ),
    tool(
      'list_runners',
      'List the runners: name, id, status (online, draining, offline, '
          'revoked), when the engine last heard from each, what it can do '
          '(capabilities), what it cannot and why (missing, while it is '
          'connected), its slots and the jobs it runs. A job that waits with '
          '"No runner can do ..." needs a runner that offers that capability. '
          'Read-only: the owner pairs and revokes runners.',
      {},
      (args) async => [
        for (final runner in await client.listRunners()) runner.toJson(),
      ],
      readOnly: true,
    ),
    tool(
      'list_credentials',
      'List the named credentials of the engine, never a secret: name, kind, '
          'account, the status of their own check, and usedBy (the project, '
          'app and flavor that use each, with the status of that assignment '
          'and a message and fix when a check refused it). Read-only: the '
          'owner adds, assigns and removes credentials in the XPath app or '
          'with `xp credentials`.',
      {
        'project': text(
          'Only the credentials this project uses, and only its flavors: id '
          '(prj_...), owner/name or name.',
        ),
      },
      (args) async {
        final reference = args.optionalString('project');
        final credentials = await client.listNamedCredentials();
        if (reference == null) {
          return [for (final credential in credentials) credential.toJson()];
        }
        final id = await resolveProject(client, reference);
        return [
          for (final credential in credentials)
            if (credential.usedBy.any((usage) => usage.projectId == id))
              {
                ...credential.toJson(),
                'usedBy': [
                  for (final usage in credential.usedBy)
                    if (usage.projectId == id) usage.toJson(),
                ],
              },
        ];
      },
      readOnly: true,
    ),
    tool(
      'get_storage_report',
      'What the engine keeps on disk and what could be freed.',
      {},
      (args) async => (await client.getStorage()).toJson(),
      readOnly: true,
    ),
  ];
}

bool _isInvalid(Object? result) =>
    result is Map<String, Object?> && result['valid'] == false;

Map<String, Object?> _validation(
  ValidateWorkflowResponse response, {
  required bool saved,
}) => {
  'valid': response.valid,
  'saved': saved,
  'issues': [
    for (final issue in response.issues)
      {'line': issue.line, 'column': issue.column, 'message': issue.message},
  ],
};

Future<Map<String, Object?>> _runWithApprovals(XpClient client, Run run) async {
  final approvals = await pendingApprovalsOf(client, run);
  return {
    'run': run.toJson(),
    'pendingApprovals': [for (final approval in approvals) approval.toJson()],
    if (approvals.isNotEmpty)
      'note':
          'The run waits for the owner. Only the owner can approve, in the '
          'XPath app or with `xp approvals approve <id>`. Poll get_approval.',
  };
}

Future<Map<String, Object?>> _tail(
  XpClient client,
  String jobId,
  int lines,
  Duration idle,
) async {
  final kept = <String>[];
  JobState? ended;
  final frames = StreamIterator(client.followJobLogs(jobId));
  try {
    while (await frames.moveNext().timeout(idle, onTimeout: () => false)) {
      switch (frames.current) {
        case LogLineFrame(:final text):
          kept.add(text);
          if (kept.length > lines) kept.removeAt(0);
        case LogEndFrame(:final state):
          ended = state;
        case LogGapFrame():
          break;
      }
    }
  } finally {
    await frames.cancel();
  }
  return {'lines': kept, 'jobEnded': ended != null, 'jobState': ?ended?.wire};
}

/// Runs a tool and turns its failure into an error result: [errorJson],
/// with the engine's code and a hint that names MCP tools, not commands.
Future<McpToolResult> _guard(Future<McpToolResult> Function() body) async {
  McpToolResult fail(String code, String message, [String? hint]) =>
      McpToolResult.json(errorJson(code, message, hint), isError: true);
  try {
    return await body();
  } on ApiException catch (error) {
    return error.isForbidden
        ? fail(
            apiCodeOf(error),
            'The engine refused: ${error.message} This MCP token reads, '
            'creates and edits projects and workflows and dispatches; it can '
            'never approve or loosen a gate.',
          )
        : error.isUnauthorized
        ? fail(
            apiCodeOf(error),
            'The engine rejected the MCP token.',
            'Ask the owner to create one with `xpd token create --kind mcp` '
                'and save it with `xp connect --mcp-token <token>`.',
          )
        : fail(apiCodeOf(error), error.message);
  } on ConnectionException catch (error) {
    return fail('unreachable', error.message);
  } on ReferenceException catch (error) {
    return fail(
      error.notFound ? 'not_found' : 'ambiguous',
      error.message,
      error.mcpHint,
    );
  } on McpArgumentError catch (error) {
    return fail('invalid_request', error.message);
  } on CheckedFromJsonException catch (error) {
    // A malformed object argument (`edits`) fails as it is read.
    return fail('invalid_request', 'Invalid arguments: ${error.message}');
  } on FormatException catch (error) {
    return fail('invalid_request', 'Invalid arguments: ${error.message}');
  } on Exception catch (error) {
    return fail('internal', '$error');
  }
}
