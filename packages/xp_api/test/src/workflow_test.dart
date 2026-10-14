import 'package:json_annotation/json_annotation.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  final created = DateTime.utc(2026, 10, 13, 9);
  final version = WorkflowVersionInfo(
    id: 'wfv_1',
    version: 2,
    createdAt: created,
  );

  group('Workflow', () {
    final workflow = Workflow(
      id: 'wf_1',
      projectId: 'prj_1',
      name: 'dev-build',
      builtin: true,
      version: version,
      versions: [version],
      yaml: 'schema: 1',
    );

    test('serializes its versions inline', () {
      expect(workflow.toJson(), {
        'id': 'wf_1',
        'projectId': 'prj_1',
        'name': 'dev-build',
        'builtin': true,
        'version': {
          'id': 'wfv_1',
          'version': 2,
          'createdAt': '2026-10-13T09:00:00.000Z',
        },
        'versions': [
          {
            'id': 'wfv_1',
            'version': 2,
            'createdAt': '2026-10-13T09:00:00.000Z',
          },
        ],
        'yaml': 'schema: 1',
      });
    });

    test('round-trips through JSON', () {
      expect(Workflow.fromJson(workflow.toJson()), workflow);
      expect(WorkflowVersionInfo.fromJson(version.toJson()), version);
    });
  });

  group('WorkflowSummary and WorkflowsResponse', () {
    test('round-trip through JSON', () {
      final summary = WorkflowSummary(
        id: 'wf_1',
        projectId: 'prj_1',
        name: 'test',
        builtin: false,
        version: version,
      );
      final response = WorkflowsResponse([summary]);

      expect(WorkflowSummary.fromJson(summary.toJson()), summary);
      expect(WorkflowsResponse.fromJson(response.toJson()), response);
    });
  });

  group('requests', () {
    test('read their fields', () {
      expect(
        CreateWorkflowRequest.fromJson(const {'name': 'a', 'yaml': 'y'}),
        const CreateWorkflowRequest(name: 'a', yaml: 'y'),
      );
      expect(WorkflowYamlRequest.fromJson(const {'yaml': 'y'}).toJson(), {
        'yaml': 'y',
      });
      expect(
        const WorkflowYamlRequest(yaml: 'y'),
        WorkflowYamlRequest.fromJson(const {'yaml': 'y'}),
      );
      expect(const CreateWorkflowRequest(name: 'a', yaml: 'y').toJson(), {
        'name': 'a',
        'yaml': 'y',
      });
    });

    test('reject a missing yaml', () {
      expect(
        () => WorkflowYamlRequest.fromJson(const {}),
        throwsA(isA<CheckedFromJsonException>()),
      );
    });
  });

  group('validation', () {
    test('an issue prints where it is', () {
      const issue = WorkflowIssue(line: 3, column: 5, message: 'Unknown key.');

      expect(issue.toString(), '3:5: Unknown key.');
      expect(WorkflowIssue.fromJson(issue.toJson()), issue);
    });

    test('a response round-trips through JSON', () {
      const response = ValidateWorkflowResponse(
        valid: false,
        issues: [WorkflowIssue(line: 1, column: 1, message: 'm')],
      );

      expect(ValidateWorkflowResponse.fromJson(response.toJson()), response);
      expect(const ValidateWorkflowResponse(valid: true).issues, isEmpty);
    });
  });
}
