import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

const _catalog = MapStepCatalog({
  'build.android': {'artifact', 'dartDefineFile'},
  'git.checkout': {'commitFrom'},
  'upload.play': {'artifactsFrom'},
  'guard': {'checks'},
  'version.bump': {},
});

const _valid = r'''
schema: 1
name: Dev build
description: Builds dev.
lock: project
inputs:
  notes:
    description: Release notes.
    default: ""
  groups:
    default: [qa]
  needed:
    required: true
  bare:
stages:
  - name: prepare
    jobs:
      prepare:
        steps:
          - kind: version.bump
  - name: build
    jobs:
      build:
        name: Build ${{ flavor.name }} for ${{ platform }}
        matrix:
          platform: ${{ platforms }}
          flavor: [dev, prod]
        if: platform == 'android' && flavor.prod
        capabilities: [flutter, android]
        steps:
          - kind: git.checkout
            with:
              commitFrom: prepare
          - kind: guard
            with:
              checks: [source]
          - kind: build.android
            if: "!flavor.shorebird"
            gate: prod_release
            with:
              artifact: apk
              dartDefineFile: ${{ inputs.notes }}
''';

void main() {
  const parser = WorkflowParser(_catalog);

  List<String> issues(String source) => [
    for (final issue in parser.parse(source).issues)
      '${issue.line}:${issue.column} ${issue.message}',
  ];

  group('a valid document', () {
    late WorkflowDefinition definition;

    setUp(() {
      final result = parser.parse(_valid);
      expect(result.issues, isEmpty);
      expect(result.isValid, isTrue);
      definition = result.definition!;
    });

    test('has its header', () {
      expect(definition.name, 'Dev build');
      expect(definition.description, 'Builds dev.');
      expect(definition.locksProject, isTrue);
    });

    test('has its inputs', () {
      expect(definition.inputs.map((input) => input.name), [
        'notes',
        'groups',
        'needed',
        'bare',
      ]);
      expect(definition.inputs.map((input) => input.defaultValue), [
        '',
        ['qa'],
        null,
        null,
      ]);
      expect(definition.inputs.map((input) => input.required), [
        false,
        false,
        true,
        false,
      ]);
      expect(definition.inputs.first.description, 'Release notes.');
      expect(definition.inputs.first.position, const SourcePosition(6, 3));
    });

    test('has its stages and jobs', () {
      expect(definition.stages.map((stage) => stage.name), [
        'prepare',
        'build',
      ]);
      expect(definition.jobs.map((job) => job.id), ['prepare', 'build']);
      expect(definition.stages.first.position, const SourcePosition(15, 5));
    });

    test('has the matrix of a job', () {
      final job = definition.jobs.last;

      expect(job.matrix.map((axis) => axis.name), ['platform', 'flavor']);
      expect(job.matrix.first.values, isNull);
      expect(job.matrix.first.reference, isNotNull);
      expect(job.matrix.last.values, ['dev', 'prod']);
      expect(job.capabilities, [Capability.flutter, Capability.android]);
      expect(job.name!.hasPlaceholders, isTrue);
      expect(job.condition, isNotNull);
    });

    test('has the steps of a job', () {
      final steps = definition.jobs.last.steps;

      expect(
        [for (final step in steps) step.kind],
        ['git.checkout', 'guard', 'build.android'],
      );
      expect(steps.first.withValues, {'commitFrom': 'prepare'});
      expect(steps[1].withValues, {
        'checks': ['source'],
      });
      expect(steps.last.conditionText, '!flavor.shorebird');
      expect(steps.last.gate, GateAction.prodRelease);
      expect(steps.last.withValues['artifact'], 'apk');
      expect(steps.last.position, const SourcePosition(36, 13));
    });

    test('is not locking by default', () {
      final result = parser.parse('''
schema: 1
stages:
  - name: a
    jobs:
      j:
        steps:
          - kind: version.bump
''');

      expect(result.definition!.locksProject, isFalse);
      expect(result.definition!.name, isNull);
      expect(result.definition!.inputs, isEmpty);
    });
  });

  group('the definition', () {
    test('compares inputs and matrix axes by value', () {
      final first = parser.parse(_valid).definition!;
      final second = parser.parse(_valid).definition!;

      expect(first.inputs, second.inputs);
      expect(first.jobs.last.matrix, second.jobs.last.matrix);
      expect(first.inputs.first, isNot(first.inputs.last));
      expect(first.jobs.last.matrix.first, isNot(first.jobs.last.matrix.last));
    });
  });

  group('SourcePosition', () {
    test('prints line and column', () {
      expect(const SourcePosition(3, 4).toString(), '3:4');
    });
  });

  group('the document', () {
    test('must be YAML, with the place of the error', () {
      final found = parser.parse('schema: 1\nstages: [a\n');

      expect(found.isValid, isFalse);
      expect(found.definition, isNull);
      expect(found.issues.single.line, greaterThan(1));
      expect(found.issues.single.message, startsWith('The document is not'));
    });

    test('must not repeat a key', () {
      expect(
        issues('schema: 1\nschema: 1\n').single,
        contains('not valid YAML'),
      );
    });

    test('must not be empty or a list', () {
      expect(issues(''), ['1:1 The workflow is empty.']);
      expect(issues('- a'), [
        '1:1 A workflow is a mapping with "schema" and "stages".',
      ]);
      expect(issues('just text'), [
        '1:1 A workflow is a mapping with "schema" and "stages".',
      ]);
    });

    test('must say its schema and stages', () {
      expect(issues('name: x'), [
        '1:1 Add "schema: 1".',
        '1:1 Add "stages", a list of stages that run in order.',
      ]);
    });

    test('must have schema 1', () {
      expect(issues('schema: 2\nstages: []'), [
        '1:9 "schema" must be 1.',
        '2:9 "stages" is a list with at least one stage.',
      ]);
      expect(
        issues('schema: one\nstages: []').first,
        '1:9 "schema" must be 1.',
      );
    });

    test('must not have an unknown key', () {
      const unknown =
          '2:1 Unknown key "stage" in the workflow. Allowed: description, '
          'inputs, lock, name, schema, stages.';

      expect(issues('schema: 1\nstage: []\nstages: []\n'), [
        unknown,
        '3:9 "stages" is a list with at least one stage.',
      ]);
    });

    test('must have text for its name and description', () {
      expect(issues('schema: 1\nname: 3\ndescription: ""\nstages: []'), [
        '2:7 "name" must be a non-empty string.',
        '3:14 "description" must be a non-empty string.',
        '4:9 "stages" is a list with at least one stage.',
      ]);
    });

    test('can only lock the project', () {
      expect(
        issues('schema: 1\nlock: all\nstages: []').first,
        '2:7 "lock" can '
        'only be "project".',
      );
    });
  });

  group('inputs', () {
    String document(String inputs) =>
        'schema: 1\ninputs:\n$inputs\nstages: []\n';

    test('are a mapping', () {
      expect(issues(document('  - a')).first, startsWith('3:3 "inputs" is a'));
    });

    test('have a name made of letters, digits and underscores', () {
      expect(
        issues(document('  bad-name: {}')).first,
        '3:3 "bad-name" is not an input name: letters, digits and _.',
      );
    });

    test('are a mapping or empty', () {
      expect(
        issues(document('  a: 3')).first,
        '3:6 An input is a mapping, '
        'or empty.',
      );
    });

    test('know their keys', () {
      expect(
        issues(document('  a: {color: red}')).first,
        '3:7 Unknown key "color" in input "a". Allowed: default, '
        'description, required.',
      );
    });

    test('are required with true or false, and without a default', () {
      expect(
        issues(document('  a: {required: maybe}')).first,
        '3:17 "required" must be true or false.',
      );
      expect(
        issues(document('  a: {required: true, default: 1}')).first,
        '3:6 An input with a default cannot be required.',
      );
    });
  });

  group('stages and jobs', () {
    String stages(String body) => 'schema: 1\nstages:\n$body\n';

    test('are mappings with a name and jobs', () {
      expect(
        issues(stages('  - a')).first,
        '3:5 A stage is a mapping with '
        '"name" and "jobs".',
      );
      expect(
        issues(stages('  - name: a')).first,
        '3:5 Add "jobs" to the '
        'stage.',
      );
      expect(
        issues(stages('  - jobs: {}')).first,
        startsWith('3:5 Add "name"'),
      );
      expect(
        issues(stages('  - {name: a, jobs: []}')).first,
        '3:21 "jobs" is a mapping from a job id to its job.',
      );
      expect(
        issues(stages('  - {name: a, jobs: {}}')).first,
        '3:21 "jobs" is a mapping from a job id to its job.',
      );
      expect(
        issues(stages('  - {name: a, jobs: {j: 3}}')).first,
        '3:25 A job is a mapping with "steps".',
      );
    });

    test('have an id of letters, digits, - and _', () {
      expect(
        issues(
          stages(
            '  - name: a\n    jobs:\n      "1x": {steps: [{kind: guard}]}',
          ),
        ).first,
        startsWith('5:7 "1x" is not a job id'),
      );
    });

    test('have an id that is used once in the workflow', () {
      final problems = issues(
        stages('''
  - name: a
    jobs:
      j:
        steps: [{kind: guard}]
  - name: b
    jobs:
      j:
        steps: [{kind: guard}]'''),
      );

      expect(problems, ['9:7 The job id "j" is used at 5:7 already.']);
    });

    test('know their keys and need steps', () {
      const unknown =
          '6:9 Unknown key "step" in job "j". Allowed: capabilities, if, '
          'matrix, name, steps.';

      expect(
        issues(stages('  - name: a\n    jobs:\n      j:\n        step: []')),
        [unknown, '6:9 Add "steps" to job "j".'],
      );
      expect(
        issues(stages('  - name: a\n    jobs:\n      j:\n        steps: []')),
        ['6:16 "steps" is a list with at least one step.'],
      );
    });

    test('have a name that is text', () {
      expect(
        issues(
          stages(
            '  - name: a\n    jobs:\n      j:\n        name: 3\n'
            '        steps: [{kind: guard}]',
          ),
        ),
        ['6:15 "name" must be a non-empty string.'],
      );
    });

    test('have a name whose placeholders are valid', () {
      expect(
        issues(
          stages(
            '  - name: a\n    jobs:\n      j:\n'
            '        name: "Build \${{ nope }}"\n'
            '        steps: [{kind: guard}]',
          ),
        ).single,
        startsWith(
          '6:15 Unknown variable "nope". Known here: app, build, bump,',
        ),
      );
      expect(
        issues(
          stages(
            '  - name: a\n    jobs:\n      j:\n'
            '        name: "Build \${{ a == }}"\n'
            '        steps: [{kind: guard}]',
          ),
        ).single,
        startsWith('6:'),
      );
    });

    test('have capabilities from the known ones', () {
      const unknown =
          '6:33 Unknown capability. Allowed: ios-sign, android, flutter, '
          'swift-linux, ios-linux.';

      expect(
        issues(
          stages(
            '  - name: a\n    jobs:\n      j:\n'
            '        capabilities: [flutter, lasers]\n'
            '        steps: [{kind: guard}]',
          ),
        ),
        [unknown],
      );
      expect(
        issues(
          stages(
            '  - name: a\n    jobs:\n      j:\n'
            '        capabilities: flutter\n'
            '        steps: [{kind: guard}]',
          ),
        ),
        ['6:23 "capabilities" is a list.'],
      );
    });

    test('say so when an expression starting with ! was not quoted', () {
      expect(
        issues(
          stages(
            '  - name: a\n    jobs:\n      j:\n'
            '        if: !flavor.prod\n'
            '        steps: [{kind: guard}]',
          ),
        ).single,
        '6:13 "if" is empty. Quote an expression that starts with "!", as in '
        '"!flavor.prod".',
      );
    });

    test('have a condition that is a valid expression', () {
      expect(
        issues(
          stages(
            '  - name: a\n    jobs:\n      j:\n'
            '        if: platform ==\n'
            '        steps: [{kind: guard}]',
          ),
        ).single,
        '6:24 Expected a value, not the end of the expression.',
      );
      expect(
        issues(
          stages(
            '  - name: a\n    jobs:\n      j:\n'
            '        if: "inputs =="\n'
            '        steps: [{kind: guard}]',
          ),
        ).single,
        '6:23 Expected a value, not the end of the expression.',
      );
      expect(
        issues(
          stages(
            '  - name: a\n    jobs:\n      j:\n'
            '        if: 3\n'
            '        steps: [{kind: guard}]',
          ),
        ).single,
        '6:13 "if" must be a non-empty string.',
      );
    });
  });

  group('matrices', () {
    String job(String matrix) =>
        'schema: 1\nstages:\n  - name: a\n    jobs:\n      j:\n'
        '        matrix:\n$matrix\n        steps: [{kind: guard}]';

    test('have platform and flavor axes only', () {
      expect(
        issues(job('          color: [red]')).single,
        '7:11 Unknown '
        'matrix axis "color". Allowed: platform, flavor.',
      );
      expect(
        issues(job('          - a')).single,
        '7:11 "matrix" is a mapping '
        'from "platform" or "flavor".',
      );
      expect(issues(job('          {}')).single, startsWith('7:11 "matrix"'));
    });

    test('take platforms android and ios', () {
      expect(
        issues(job('          platform: [android, windows]')).single,
        '7:31 Unknown platform "windows". Allowed: android, ios.',
      );
    });

    test('take strings', () {
      expect(
        issues(job('          flavor: [dev, 3]')).single,
        '7:25 A matrix value is a string.',
      );
    });

    test('take a placeholder of the dispatch, and nothing else', () {
      expect(issues(job(r'          flavor: ${{ flavors }}')), isEmpty);
      expect(
        issues(job(r'          flavor: ${{ flavor }}')).single,
        startsWith('7:19 Unknown variable "flavor"'),
      );
      expect(
        issues(job(r'          flavor: a ${{ flavors }}')).single,
        r'7:19 Use one placeholder, such as ${{ platforms }}.',
      );
      expect(
        issues(job(r'          flavor: ${{ flavors ==}}')).single,
        startsWith('7:'),
      );
      expect(
        issues(job('          flavor: 3')).single,
        '7:19 A matrix axis is a list of values or a placeholder such as '
        r'${{ platforms }}.',
      );
    });
  });

  group('steps', () {
    String step(String body) =>
        'schema: 1\nstages:\n  - name: a\n    jobs:\n      j:\n'
        '        steps:\n$body';

    test('are mappings with a kind', () {
      expect(
        issues(step('          - x')).single,
        '7:13 A step is a mapping '
        'with a "kind".',
      );
      expect(
        issues(step('          - with: {}')).single,
        '7:13 Add "kind" to '
        'a step.',
      );
      expect(
        issues(step('          - kind: guard\n            color: 1')).single,
        '8:13 Unknown key "color" in a step. Allowed: gate, if, kind, with.',
      );
    });

    test('name a step type the engine has', () {
      expect(
        issues(step('          - kind: nope')).single,
        '7:19 Unknown step type "nope". Known: build.android, git.checkout, '
        'guard, upload.play, version.bump.',
      );
    });

    test('give the step type its keys under with', () {
      expect(
        issues(
          step(
            '          - kind: guard\n            with:\n              x: 1',
          ),
        ).single,
        '9:15 "guard" does not take "x". It takes: checks.',
      );
      expect(
        issues(step('          - kind: guard\n            with: [a]')).single,
        '8:19 "with" is a mapping.',
      );
    });

    test('check the placeholders in the values of with', () {
      expect(
        issues(
          step(
            '          - kind: guard\n            with:\n'
            r'              checks: ["${{ nope }}", ["${{ inputs }}"]]'
            '\n              ',
          ),
        ).single,
        startsWith('9:24 Unknown variable "nope"'),
      );
      expect(
        issues(
          step(
            '          - kind: build.android\n            with:\n'
            r'              artifact: {a: "${{ nope }}"}',
          ),
        ).single,
        startsWith('9:29 Unknown variable "nope"'),
      );
    });

    test('have a condition and a gate that are valid', () {
      expect(
        issues(step('          - kind: guard\n            gate: ship')).single,
        '8:19 Unknown gate. Allowed: prod_release, prod_patch, '
        'store_submission, push, merge, delete.',
      );
      expect(
        issues(step('          - kind: guard\n            gate: 3')).single,
        startsWith('8:19 Unknown gate.'),
      );
      expect(
        issues(step('          - kind: guard\n            if: a ==')).single,
        '8:21 Expected a value, not the end of the expression.',
      );
    });

    test('say commitFrom a job of an earlier stage', () {
      final problems = issues(r'''
schema: 1
stages:
  - name: a
    jobs:
      first:
        steps:
          - kind: git.checkout
            with:
              commitFrom: second
  - name: b
    jobs:
      second:
        steps:
          - kind: git.checkout
            with:
              commitFrom: first
          - kind: git.checkout
            with:
              commitFrom: ${{ inputs.job }}
''');

      expect(problems, [
        '7:13 "commitFrom" must name a job of an earlier stage, not "second".',
      ]);
    });

    test('say artifactsFrom a job of an earlier stage', () {
      final problems = issues('''
schema: 1
stages:
  - name: a
    jobs:
      build:
        steps:
          - kind: upload.play
            with:
              artifactsFrom: upload
  - name: b
    jobs:
      upload:
        steps:
          - kind: upload.play
            with:
              artifactsFrom: build
''');

      expect(problems.single, contains('"artifactsFrom" must name a job of'));
      expect(problems.single, startsWith('7:13 '));
    });

    test('report every problem of a document at once', () {
      final problems = issues('''
schema: 1
name: 3
stages:
  - name: a
    jobs:
      j:
        steps:
          - kind: nope
          - kind: guard
            gate: ship
''');

      expect(problems.length, 3);
    });
  });
}
