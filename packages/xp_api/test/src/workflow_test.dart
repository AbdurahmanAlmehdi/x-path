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
        'inputs': <Object?>[],
      });
    });

    test('round-trips through JSON', () {
      expect(Workflow.fromJson(workflow.toJson()), workflow);
      expect(WorkflowVersionInfo.fromJson(version.toJson()), version);
    });

    test('carries its typed inputs', () {
      final typed = Workflow(
        id: 'wf_1',
        projectId: 'prj_1',
        name: 'n',
        builtin: false,
        version: version,
        versions: [version],
        yaml: 'schema: 1',
        inputs: const [
          WorkflowInput(
            name: 'track',
            type: InputType.choice,
            description: 'Where it goes.',
            options: ['internal', 'beta'],
            defaultValue: 'internal',
          ),
          WorkflowInput(
            name: 'release',
            type: InputType.release,
            required: true,
          ),
          WorkflowInput(name: 'loose'),
        ],
      );

      expect(Workflow.fromJson(typed.toJson()), typed);
      expect(typed.toJson()['inputs'], [
        {
          'name': 'track',
          'type': 'choice',
          'description': 'Where it goes.',
          'options': ['internal', 'beta'],
          'default': 'internal',
          'required': false,
        },
        {'name': 'release', 'type': 'release', 'required': true},
        {'name': 'loose', 'required': false},
      ]);
      expect(Workflow.fromJson(workflow.toJson()..remove('inputs')), workflow);
      expect(
        [for (final type in InputType.values) type.wire],
        ['string', 'boolean', 'choice', 'json', 'release'],
      );
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
      expect(issue.toJson().containsKey('hint'), isFalse);
    });

    test('an issue can carry a hint (UX-02)', () {
      const issue = WorkflowIssue(
        line: 3,
        column: 5,
        message: 'Unknown key "stage".',
        hint: 'Did you mean "stages"?',
      );

      expect(
        issue.toString(),
        '3:5: Unknown key "stage". Did you mean "stages"?',
      );
      expect(issue.toJson()['hint'], 'Did you mean "stages"?');
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

  group('WorkflowSchema', () {
    const schema = WorkflowSchema(
      schema: 1,
      steps: [
        StepType(kind: 'build.android', withKeys: ['artifact', 'flavor']),
        StepType(kind: 'test'),
      ],
      gates: ['prod_release'],
      capabilities: ['flutter'],
      matrixAxes: ['platform', 'flavor'],
      platforms: ['android', 'ios'],
    );

    test('names the with keys of a step type "with"', () {
      expect(schema.steps.first.toJson(), {
        'kind': 'build.android',
        'with': ['artifact', 'flavor'],
        'title': '',
        'description': '',
        'group': '',
        'capabilities': <Object?>[],
        'keys': <Object?>[],
      });
      expect(StepType.fromJson(const {'kind': 'test'}), schema.steps.last);
    });

    test('a step type says what it does and types its keys (UX-02)', () {
      const type = StepType(
        kind: 'upload.play',
        withKeys: ['status'],
        title: 'Upload to Google Play',
        description: 'Uploads.',
        group: 'Upload',
        keys: [
          StepKeySchema(
            name: 'status',
            type: StepKeyType.string,
            options: ['completed', 'draft'],
            defaultValue: 'completed',
            description: 'Release now or keep a draft.',
          ),
        ],
      );

      expect(type.toJson()['keys'], [
        {
          'name': 'status',
          'type': 'string',
          'required': false,
          'default': 'completed',
          'options': ['completed', 'draft'],
          'description': 'Release now or keep a draft.',
        },
      ]);
      expect(StepType.fromJson(type.toJson()), type);
      expect(
        StepKeySchema.fromJson(const {'name': 'x'}),
        const StepKeySchema(name: 'x'),
      );
    });

    test('labels the gates and lists the variables', () {
      const labelled = WorkflowSchema(
        schema: 1,
        steps: [],
        gates: ['push'],
        gateLabels: {'push': 'Push'},
        capabilities: [],
        matrixAxes: [],
        platforms: [],
        variables: ['platform'],
      );

      expect(labelled.toJson()['gateLabels'], {'push': 'Push'});
      expect(WorkflowSchema.fromJson(labelled.toJson()), labelled);
      expect(
        WorkflowSchema.fromJson(schema.toJson()..remove('variables')),
        schema,
      );
    });

    test('round-trips through JSON', () {
      expect(WorkflowSchema.fromJson(schema.toJson()), schema);
    });
  });
}
