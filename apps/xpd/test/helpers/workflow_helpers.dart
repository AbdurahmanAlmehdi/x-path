import 'dart:async';
import 'dart:convert';

import 'package:xp_api/xp_api.dart';

import 'test_engine.dart';

/// A workflow of one job that checks out the commit and runs `echo`.
const echoWorkflow = '''
schema: 1
stages:
  - name: run
    jobs:
      job:
        name: Echo
        steps:
          - kind: git.checkout
          - kind: command
            with:
              executable: echo
''';

/// Like [echoWorkflow], and it holds the project: a production release.
const lockingWorkflow = '''
schema: 1
lock: project
stages:
  - name: run
    jobs:
      job:
        name: Release
        steps:
          - kind: git.checkout
          - kind: command
            with:
              executable: echo
''';

/// A workflow whose command waits for the owner before it runs.
const gatedWorkflow = '''
schema: 1
lock: project
stages:
  - name: run
    jobs:
      job:
        name: Ship
        steps:
          - kind: git.checkout
          - kind: command
            gate: prod_release
            with:
              executable: echo
''';

/// Requests to the workflow endpoints of one project.
class WorkflowClient {
  new(this.engine, this.projectId);

  final TestEngine engine;
  final String projectId;

  /// Adds a project from a folder and returns a client for it.
  static Future<WorkflowClient> add(TestEngine engine) async {
    engine.folders['/work/app'] = projectFiles;
    final response = await engine.request(
      '/projects',
      method: 'POST',
      body: jsonEncode({'path': '/work/app'}),
    );
    return WorkflowClient(engine, response.json['id']! as String);
  }

  String get base => '/projects/$projectId/workflows';

  Future<RawResponse> send(String method, String path, [Object? json]) =>
      engine.request(
        path,
        method: method,
        body: json == null ? null : jsonEncode(json),
      );

  /// The id of the built-in workflow [name].
  Future<String> builtin(String name) async {
    final response = await send('GET', base);
    return (response.json['workflows']! as List)
            .cast<Map<String, dynamic>>()
            .firstWhere((w) => w['name'] == name)['id']!
        as String;
  }

  /// Creates a workflow of the owner and returns its id.
  Future<String> create(String name, String yaml) async {
    final response = await send('POST', base, {'name': name, 'yaml': yaml});
    return response.json['id']! as String;
  }

  /// Dispatches a workflow.
  Future<RawResponse> dispatch(String workflowId, [Object? json]) =>
      send('POST', '$base/$workflowId/dispatch', json);

  /// Waits until the run is in one of [states].
  Future<Run> until(String runId, Set<RunState> states) async {
    for (var i = 0; i < 2000; i++) {
      final run = Run.fromJson((await send('GET', '/runs/$runId')).json);
      if (states.contains(run.state)) return run;
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    throw StateError('Run $runId never reached $states.');
  }
}
