import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// The engine's built-in `dev-build` (packages/xp_engine), as the engine
/// ships it: folded text, placeholders, conditions and `with` values.
const _devBuild = r'''
schema: 1
name: Dev build
description: >-
  Builds the dev flavors and sends them to testers: Android to Firebase App
  Distribution, iOS to TestFlight.
inputs:
  firebaseAppIds:
    description: >-
      Firebase app ids by flavor and platform, for example
      {dev: {android: "1:123456789012:android:abcdef"}}. A build without one
      is not uploaded.
  testerGroups:
    description: Firebase tester group aliases.
    default: []
  notes:
    description: Release notes for the testers.
    default: ""
stages:
  - name: check
    jobs:
      check:
        name: Check ${{ flavor.name }} for ${{ platform }}
        matrix:
          platform: ${{ platforms }}
          flavor: ${{ flavors }}
        steps:
          - kind: git.checkout
          - kind: guard
            with:
              checks: [source, credentials]
  - name: upload
    jobs:
      upload:
        name: Upload ${{ flavor.name }} for ${{ platform }}
        matrix:
          platform: ${{ platforms }}
          flavor: ${{ flavors }}
        if: >-
          (platform == 'android' && inputs.firebaseAppIds[flavor.name].android)
          || (platform == 'ios' && inputs.appleAppIds[flavor.name])
        steps:
          - kind: upload.firebase
            if: platform == 'android' && inputs.firebaseAppIds[flavor.name].android
            with:
              artifactsFrom: build
              groupAliases: ${{ inputs.testerGroups }}
''';

const _rich = WorkflowDocument(
  name: 'Dev build',
  description: 'Line one\nline two\n',
  locksProject: true,
  inputs: [
    WorkflowInput(name: 'notes', description: 'Notes', defaultValue: ''),
    WorkflowInput(name: 'plain'),
    WorkflowInput(name: 'need', required: true),
  ],
  stages: [
    WorkflowStage(
      name: 'build',
      jobs: [
        WorkflowJob(
          id: 'build',
          name: r'Build ${{ flavor.name }} for ${{ platform }}',
          matrix: [
            WorkflowMatrixAxis.placeholder('platform', r'${{ platforms }}'),
            WorkflowMatrixAxis.list('flavor', ['prod', 'dev']),
          ],
          condition: "platform == 'android'",
          capabilities: ['flutter'],
          steps: [
            WorkflowStep(kind: 'git.checkout'),
            WorkflowStep(
              kind: 'command',
              condition: '!flavor.prod',
              gate: 'push',
              withValues: {
                'run': 'echo a\necho b',
                'n': 1,
                'ratio': 0.5,
                'on': false,
                'nothing': null,
                'yes': 'true',
                'list': ['a,b', r'${{ x }}', 3],
                'maps': [
                  {
                    'a': 1,
                    'b': {'c': 'd'},
                  },
                  [1, 2],
                  'x\ny',
                  <Object?>[],
                ],
                'empty': <String, Object?>{},
                '1': 'key: value',
                'odd': '\n  indented',
                'carriage': 'a\rb',
                'trailing': 'a\n\n',
                'line\nkey': 1,
                'long': [
                  'aaaaaaaaaaaaaaaaaaaa',
                  'bbbbbbbbbbbbbbbbbbbb',
                  'cccccccccccccccccccc',
                  'dddddddddddddddddddd',
                ],
              },
            ),
          ],
        ),
      ],
    ),
    WorkflowStage(name: ''),
  ],
);

void main() {
  group('WorkflowDocument', () {
    test('writes the layout of the built-in workflows', () {
      expect(_rich.toYaml(), r'''
schema: 1
name: Dev build
description: |
  Line one
  line two
lock: project
inputs:
  notes:
    description: Notes
    default: ''
  plain: {}
  need:
    required: true
stages:
  - name: build
    jobs:
      build:
        name: Build ${{ flavor.name }} for ${{ platform }}
        matrix:
          platform: ${{ platforms }}
          flavor: [prod, dev]
        if: platform == 'android'
        capabilities: [flutter]
        steps:
          - kind: git.checkout
          - kind: command
            if: '!flavor.prod'
            gate: push
            with:
              run: |-
                echo a
                echo b
              n: 1
              ratio: 0.5
              on: false
              nothing: null
              yes: 'true'
              list: ['a,b', '${{ x }}', 3]
              maps:
                - a: 1
                  b:
                    c: d
                - [1, 2]
                - |-
                  x
                  y
                - []
              empty: {}
              '1': 'key: value'
              odd: "\n  indented"
              carriage: "a\rb"
              trailing: "a\n\n"
              "line\nkey": 1
              long:
                - aaaaaaaaaaaaaaaaaaaa
                - bbbbbbbbbbbbbbbbbbbb
                - cccccccccccccccccccc
                - dddddddddddddddddddd
  - name: ''
    jobs: {}
''');
    });

    test('reads back what it writes', () {
      expect(WorkflowDocument.parse(_rich.toYaml()), _rich);
      const bare = WorkflowDocument(schema: null);
      expect(bare.toYaml(), 'stages: []\n');
      expect(WorkflowDocument.parse(bare.toYaml()), bare);
    });

    test('reads a built-in workflow and writes it back', () {
      final document = WorkflowDocument.parse(_devBuild);

      expect(document.name, 'Dev build');
      expect(
        document.description,
        'Builds the dev flavors and sends them to testers: Android to '
        'Firebase App Distribution, iOS to TestFlight.',
      );
      expect(
        document.inputs[1],
        const WorkflowInput(
          name: 'testerGroups',
          description: 'Firebase tester group aliases.',
          defaultValue: <Object?>[],
        ),
      );
      final upload = document.stages[1].jobs.single;
      expect(upload.matrix, const [
        WorkflowMatrixAxis.placeholder('platform', r'${{ platforms }}'),
        WorkflowMatrixAxis.placeholder('flavor', r'${{ flavors }}'),
      ]);
      expect(upload.condition, startsWith("(platform == 'android'"));
      expect(upload.steps.single.withValues, {
        'artifactsFrom': 'build',
        'groupAliases': r'${{ inputs.testerGroups }}',
      });
      expect(document.stages.first.jobs.single.steps.last.withValues, {
        'checks': ['source', 'credentials'],
      });
      expect(WorkflowDocument.parse(document.toYaml()), document);
    });

    test('reads an input without fields', () {
      expect(
        WorkflowDocument.parse('inputs:\n  notes:\nstages: []\n').inputs,
        const [WorkflowInput(name: 'notes')],
      );
    });

    test('reads empty containers as nothing', () {
      expect(
        WorkflowDocument.parse('''
name:
inputs:
stages:
  - name: a
    jobs:
      j:
        matrix:
        capabilities:
        steps:
          - kind: x
            with:
'''),
        const WorkflowDocument(
          schema: null,
          stages: [
            WorkflowStage(
              name: 'a',
              jobs: [
                WorkflowJob(
                  id: 'j',
                  steps: [WorkflowStep(kind: 'x')],
                ),
              ],
            ),
          ],
        ),
      );
    });

    test('copies with fields replaced or cleared', () {
      const document = WorkflowDocument(name: 'a', description: 'b');
      expect(document.copyWith(), document);
      expect(
        document.copyWith(
          name: () => null,
          description: () => 'c',
          locksProject: true,
          inputs: const [WorkflowInput(name: 'i')],
          stages: const [WorkflowStage(name: 's')],
        ),
        const WorkflowDocument(
          description: 'c',
          locksProject: true,
          inputs: [WorkflowInput(name: 'i')],
          stages: [WorkflowStage(name: 's')],
        ),
      );
      const stage = WorkflowStage(name: 's');
      expect(stage.copyWith(), stage);
      expect(
        stage.copyWith(
          name: 't',
          jobs: const [WorkflowJob(id: 'j')],
        ),
        const WorkflowStage(
          name: 't',
          jobs: [WorkflowJob(id: 'j')],
        ),
      );
      const job = WorkflowJob(id: 'j', name: 'n', condition: 'c');
      expect(job.copyWith(), job);
      expect(
        job.copyWith(
          id: 'k',
          name: () => null,
          condition: () => null,
          matrix: const [
            WorkflowMatrixAxis.list('platform', ['ios']),
          ],
          capabilities: const ['flutter'],
          steps: const [WorkflowStep(kind: 'test')],
        ),
        const WorkflowJob(
          id: 'k',
          matrix: [
            WorkflowMatrixAxis.list('platform', ['ios']),
          ],
          capabilities: ['flutter'],
          steps: [WorkflowStep(kind: 'test')],
        ),
      );
      const step = WorkflowStep(kind: 'a', condition: 'c', gate: 'push');
      expect(step.copyWith(), step);
      expect(
        step.copyWith(
          kind: 'b',
          condition: () => null,
          gate: () => null,
          withValues: const {'x': 1},
        ),
        const WorkflowStep(kind: 'b', withValues: {'x': 1}),
      );
    });
  });

  group('WorkflowDocument.parse refuses what it cannot hold', () {
    List<WorkflowIssue> issues(String yaml) {
      try {
        WorkflowDocument.parse(yaml);
      } on WorkflowDocumentException catch (error) {
        return error.issues;
      }
      fail('parsed');
    }

    test('YAML that does not parse', () {
      expect(issues('stages: [a'), [
        isA<WorkflowIssue>()
            .having((issue) => issue.line, 'line', 1)
            .having(
              (issue) => issue.message,
              'message',
              startsWith('The document is not valid YAML'),
            ),
      ]);
    });

    test('a document that is not a mapping', () {
      expect(issues('- a'), const [
        WorkflowIssue(
          line: 1,
          column: 1,
          message: 'A workflow is a mapping with "schema" and "stages".',
        ),
      ]);
      expect(issues('').single.line, 1);
    });

    test('unknown keys, wrong types and empty conditions, with lines', () {
      expect(
        issues('''
schema: one
lock: always
extra: 1
name: [x]
inputs:
  a: x
  b:
    required: maybe
    color: red
stages:
  - x
  - name: s
    jobs: []
  - name: t
    jobs:
      j: x
      k:
        matrix:
          platform: 3
          flavor: [prod, 4]
        capabilities: x
        if: !x
        steps:
          - x
          - with: {a: 1}
          - kind: y
            gate: [push]
'''),
        const [
          WorkflowIssue(
            line: 3,
            column: 1,
            message:
                'Unknown key "extra" in the workflow. Allowed: description, '
                'inputs, lock, name, schema, stages.',
          ),
          WorkflowIssue(line: 1, column: 9, message: '"schema" is a number.'),
          WorkflowIssue(
            line: 2,
            column: 7,
            message: '"lock" can only be "project".',
          ),
          WorkflowIssue(line: 4, column: 7, message: '"name" is text.'),
          WorkflowIssue(
            line: 6,
            column: 6,
            message: 'An input is a mapping, or empty.',
          ),
          WorkflowIssue(
            line: 9,
            column: 5,
            message:
                'Unknown key "color" in input "b". Allowed: default, '
                'description, required.',
          ),
          WorkflowIssue(
            line: 8,
            column: 15,
            message: '"required" is true or false.',
          ),
          WorkflowIssue(
            line: 11,
            column: 5,
            message: 'A stage is a mapping with "name" and "jobs".',
          ),
          WorkflowIssue(line: 13, column: 11, message: '"jobs" is a mapping.'),
          WorkflowIssue(
            line: 16,
            column: 10,
            message: 'A job is a mapping with "steps".',
          ),
          WorkflowIssue(
            line: 19,
            column: 21,
            message:
                'A matrix axis is a list of values or a placeholder such as '
                r'${{ platforms }}.',
          ),
          WorkflowIssue(line: 20, column: 26, message: 'A value here is text.'),
          WorkflowIssue(
            line: 22,
            column: 13,
            message:
                '"if" is empty. Quote an expression that starts with "!", as '
                'in "!flavor.prod".',
          ),
          WorkflowIssue(
            line: 21,
            column: 23,
            message: '"capabilities" is a list.',
          ),
          WorkflowIssue(
            line: 24,
            column: 13,
            message: 'A step is a mapping with a "kind".',
          ),
          WorkflowIssue(
            line: 25,
            column: 13,
            message: 'Add "kind" to the step.',
          ),
          WorkflowIssue(line: 27, column: 19, message: '"gate" is text.'),
        ],
      );
    });

    test('says where in its message', () {
      const error = WorkflowDocumentException([
        WorkflowIssue(line: 2, column: 3, message: 'Bad.'),
      ]);
      expect(error.toString(), 'WorkflowDocumentException: 2:3: Bad.');
    });
  });

  group('YAML values', () {
    test('format on one line and parse back', () {
      for (final value in <Object?>[
        'apk',
        r'${{ inputs.notes }}',
        'true',
        '',
        "it's",
        '[a',
        3,
        1.5,
        true,
        null,
        ['a', 'b,c'],
        {'en-US': r'${{ inputs.notes }}'},
        'two\nlines',
      ]) {
        final text = formatYamlValue(value);
        expect(text, isNot(contains('\n')), reason: '$value');
        expect(value == '' ? '' : parseYamlValue(text), value, reason: text);
      }
      expect(formatYamlValue(r'${{ inputs.notes }}'), r'${{ inputs.notes }}');
      expect(formatYamlValue(['a', 'b,c']), "[a, 'b,c']");
      expect(formatYamlValue({'k,1': "it's"}), "{'k,1': it's}");
    });

    test('read blank text as empty and broken YAML as text', () {
      expect(parseYamlValue('  '), '');
      expect(parseYamlValue('[a'), '[a');
      expect(parseYamlValue('{a: 1}'), {'a': 1});
    });
  });
}
