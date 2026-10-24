import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
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
      '${issue.line}:${issue.column} ${[issue.message, ?issue.hint].join(' ')}',
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
          '2:1 Unknown key "stage" in the workflow. Did you mean "stages"?';

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

    /// [inputs] in a workflow that is valid otherwise.
    String typed(String inputs) =>
        'schema: 1\ninputs:\n$inputs\nstages:\n  - name: s\n    jobs:\n'
        '      j:\n        steps:\n          - kind: version.bump\n';

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
        'description, options, required, type.',
      );
    });

    test('have a type and, for a choice, options (UX-04)', () {
      final inputs = parser
          .parse(
            typed(
              '  track: {type: choice, options: [internal, beta], '
              'default: beta}\n'
              '  release: {type: release}\n'
              '  flag: {type: boolean, default: false}\n'
              '  ids: {type: json, default: {dev: 1}}\n'
              '  notes: {type: string, default: ""}\n'
              '  bare:',
            ),
          )
          .definition!
          .inputs;

      expect(inputs.map((input) => input.type), [
        InputType.choice,
        InputType.release,
        InputType.boolean,
        InputType.json,
        InputType.string,
        null,
      ]);
      expect(inputs.first.options, ['internal', 'beta']);
      expect(inputs.first.toWire().options, ['internal', 'beta']);
      expect(inputs.last.toWire(), const WorkflowInput(name: 'bare'));
    });

    test('name a type the engine knows, and options that fit it', () {
      expect(
        issues(typed('  a: {type: number}')).first,
        '3:13 Unknown input type "number". Allowed: boolean, choice, json, '
        'release, string.',
      );
      expect(
        issues(typed('  a: {type: [string]}')).first,
        startsWith('3:13 Unknown input type'),
      );
      expect(
        issues(typed('  a: {type: strng}')).first,
        '3:13 Unknown input type "strng". Did you mean "string"?',
      );
      expect(
        issues(typed('  a: {type: choice}')).first,
        '3:6 A choice input needs "options".',
      );
      expect(
        issues(typed('  a: {type: choice, options: []}')).first,
        '3:30 "options" is a list of strings.',
      );
      expect(
        issues(typed('  a: {type: choice, options: [1]}')).first,
        '3:30 "options" is a list of strings.',
      );
      expect(
        issues(typed('  a: {type: string, options: [x]}')).first,
        '3:30 "options" go with "type: choice".',
      );
    });

    test('have a default of their type', () {
      for (final (input, message) in [
        ('{type: boolean, default: yes}', 'must be true or false'),
        ('{type: string, default: 3}', 'must be text'),
        ('{type: choice, options: [a], default: b}', 'must be one of a'),
        ('{type: release, default: 1.2.3}', 'must be a release, x.y.z+build'),
        ('{type: release, default: latest}', 'must be a release'),
        ('{type: release, default: 3}', 'must be a release'),
      ]) {
        expect(
          issues(typed('  a: $input')).single,
          contains('The default of "a" $message'),
          reason: input,
        );
      }
      expect(issues(typed('  a: {type: release, default: 1.2.3+4}')), isEmpty);
      expect(issues(typed('  a: {type: json, default: [1]}')), isEmpty);
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
          '6:9 Unknown key "step" in job "j". Did you mean "steps"?';

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
          '6:33 Unknown capability "lasers". Allowed: android, flutter, '
          'ios-sign, swift-linux.';

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
        'matrix axis "color". Allowed: flavor, platform.',
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
      expect(
        issues(job('          platform: [andriod]')).single,
        '7:22 Unknown platform "andriod". Did you mean "android"?',
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
        '8:19 Unknown gate "ship". Allowed: delete, merge, prod_patch, '
        'prod_release, push, store_submission.',
      );
      expect(
        issues(step('          - kind: guard\n            gate: 3')).single,
        startsWith('8:19 Unknown gate "3".'),
      );
      expect(
        issues(step('          - kind: guard\n            gate: prod_relase'))
            .single,
        '8:19 Unknown gate "prod_relase". Did you mean "prod_release"?',
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
              commitFrom: ${{ ref }}
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

  group('the paths an expression reads (UX-02)', () {
    String job(String condition, {String inputs = ''}) =>
        'schema: 1\n$inputs'
        'stages:\n  - name: a\n    jobs:\n      j:\n'
        '        matrix: {platform: [android], flavor: [dev]}\n'
        '        if: "$condition"\n'
        '        steps: [{kind: guard}]\n';

    const ids = 'inputs:\n  firebaseAppIds: {type: json}\n  notes:\n';

    test('name an input the workflow declares', () {
      expect(
        issues(job('inputs.firebaseAppId != null', inputs: ids)).single,
        '10:13 The workflow has no input "firebaseAppId". Did you mean '
        '"inputs.firebaseAppIds"?',
      );
      expect(
        issues(job('inputs.groups', inputs: ids)).single,
        '10:13 The workflow has no input "groups". Allowed: '
        'inputs.firebaseAppIds, inputs.notes.',
      );
      expect(
        issues(job('inputs.notes')).single,
        '7:13 The workflow has no input "notes". Declare it under "inputs".',
      );
      expect(
        issues(
          job(
            'inputs.firebaseAppIds[flavor.name][platform] || inputs.notes',
            inputs: ids,
          ),
        ),
        isEmpty,
      );
    });

    test('name a field of flavor, app and project', () {
      expect(
        issues(job('flavor.prd')).single,
        '7:13 "flavor" has no "prd". Did you mean "flavor.prod"?',
      );
      expect(
        issues(job('flavor.credentials.play_sx')).single,
        '7:13 "flavor.credentials" has no "play_sx". Did you mean '
        '"flavor.credentials.play_sa"?',
      );
      expect(
        issues(job('flavor.firebaseAppId.web')).single,
        '7:13 "flavor.firebaseAppId" has no "web". It has: '
        'flavor.firebaseAppId.android, flavor.firebaseAppId.ios.',
      );
      const fullName =
          '7:13 "project" has no "fullname". Did you mean "project.fullName"?';
      expect(issues(job('app.hasIOS && project.fullname')), [
        '7:13 "app" has no "hasIOS". Did you mean "app.hasIos"?',
        fullName,
      ]);
      expect(
        issues(
          job(
            'flavor.credentials.play_sa && flavor.firebaseAppId.ios && '
            "app.name == 'a' && project.baseBranch",
          ),
        ),
        isEmpty,
      );
    });

    test('read no field of a string, a number or a list', () {
      expect(issues(job('platform.name || build.next || platforms.first')), [
        '7:13 "platform" is a string; it has no "name".',
        '7:13 "build" is a number; it has no "next".',
        '7:13 "platforms" is a list; it has no "first".',
      ]);
      expect(issues(job('platforms[0] == platform')), isEmpty);
    });
  });

  group('the with of a step, by its keys (UX-02)', () {
    const typed = WorkflowParser(
      MapStepCatalog(
        {
          'build.ios': {'exportOptionsPlist', 'obfuscate', 'dartDefineFile'},
          'upload.play': {'status', 'releaseNotes'},
          'guard': {'checks'},
        },
        typed: {
          'build.ios': [
            StepKey.needed('exportOptionsPlist'),
            StepKey('obfuscate', value: StepValue.flag),
          ],
          'upload.play': [
            StepKey.choice('status', ['completed', 'draft']),
            StepKey('releaseNotes', value: StepValue.textMap),
          ],
          'guard': [
            StepKey.choice('checks', ['source'], value: StepValue.texts),
          ],
        },
      ),
    );

    List<String> typedIssues(String steps) => [
      for (final issue
          in typed
              .parse(
                'schema: 1\nstages:\n  - name: a\n    jobs:\n      j:\n'
                '        steps:\n$steps',
              )
              .issues)
        '${issue.line}:${issue.column} ${issue.message}',
    ];

    test('give the keys a step type needs', () {
      expect(typedIssues('          - kind: build.ios\n'), [
        '7:13 "build.ios" needs "exportOptionsPlist" under "with".',
      ]);
      expect(
        typedIssues(
          '          - kind: build.ios\n'
          '            with: {obfuscate: true}\n',
        ),
        ['8:19 "build.ios" needs "exportOptionsPlist" under "with".'],
      );
      expect(
        typedIssues(
          '          - kind: build.ios\n'
          r'            with: {exportOptionsPlist: "${{ inputs }}"}'
          '\n',
        ),
        isEmpty,
      );
    });

    test('give each key a value of its shape', () {
      expect(
        typedIssues(
          '          - kind: build.ios\n'
          '            with: {exportOptionsPlist: 3, obfuscate: "yes"}\n',
        ),
        [
          '8:40 "exportOptionsPlist" must be a string.',
          '8:54 "obfuscate" must be true or false.',
        ],
      );
      expect(
        typedIssues(
          '          - kind: upload.play\n'
          '            with: {status: live, releaseNotes: [a]}\n',
        ),
        [
          '8:28 "status" takes completed, draft.',
          '8:48 "releaseNotes" must be a mapping of strings.',
        ],
      );
      expect(
        typedIssues(
          '          - kind: guard\n'
          '            with: {checks: [source, nope]}\n',
        ),
        ['8:28 "checks" takes source.'],
      );
    });

    test('the step types of the engine need what their steps need', () {
      final result = WorkflowParser(StepPlanners(StepRegistry(const []))).parse(
        'schema: 1\nstages:\n  - name: a\n    jobs:\n      ios:\n'
        '        steps:\n          - kind: build.ios\n',
      );

      expect(result.issues, const [
        WorkflowIssue(
          line: 7,
          column: 13,
          message: '"build.ios" needs "exportOptionsPlist" under "with".',
        ),
      ]);
    });
  });
}
