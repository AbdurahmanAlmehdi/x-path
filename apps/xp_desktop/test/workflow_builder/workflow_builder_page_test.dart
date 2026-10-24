import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_desktop/dispatch/dispatch.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/toast/cubit/toast_cubit.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_desktop/workflow_builder/workflow_builder.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';
import 'workflow_builder_harness.dart';

/// The text field under the caption [label].
Finder field(String label) => find.descendant(
  of: find.widgetWithText(XpTextField, label.toUpperCase()),
  matching: find.byType(TextField),
);

final Finder yamlField = find.descendant(
  of: find.byType(YamlPane),
  matching: find.byType(TextField),
);

String yamlOf(WidgetTester tester) =>
    tester.widget<TextField>(yamlField).controller!.text;

/// Scrolls [finder] into view, taps it and lets the check run.
Future<void> press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

/// Types [text] into [finder] and lets the check run.
Future<void> type(WidgetTester tester, Finder finder, String text) async {
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await settle(tester);
}

void main() {
  late MockWorkflowsRepository repository;

  setUpAll(() => registerFallbackValue(const DispatchRequest()));
  setUp(() => repository = workflowsRepository());

  testWidgets('shows the open workflow in the pipeline and as YAML', (
    tester,
  ) async {
    await pumpBuilder(tester, repository: repository);

    expect(find.text('store-release · Version 2'), findsOneWidget);
    expect(find.text('CHECK'), findsOneWidget);
    expect(find.text('build'), findsWidgets);
    expect(find.text('3 steps · × platform · × flavor'), findsOneWidget);
    expect(find.text('Valid'), findsOneWidget);
    expect(yamlOf(tester), releaseYaml);
    expect(
      tester.widget<TextField>(field('Name').first).controller!.text,
      'Store release',
    );
    expect(
      tester.widget<TextField>(field('Name').last).controller!.text,
      'notes',
    );
    expect(
      find.text(
        'It also makes the production flavors the default when a dispatch '
        'names none.',
      ),
      findsOneWidget,
    );
    final save = tester.widget<XpButton>(find.widgetWithText(XpButton, 'Save'));
    expect(save.onPressed, isNull);
  });

  testWidgets('edits the workflow and saves a new version with ⌘S', (
    tester,
  ) async {
    late String saved;
    when(() => repository.saveWorkflow('prj_1', 'wf_mine', any()))
        .thenAnswer((invocation) async {
          saved = invocation.positionalArguments[2] as String;
          return Workflow(
            id: 'wf_mine',
            projectId: 'prj_1',
            name: 'store-release',
            builtin: false,
            version: versionInfo(3),
            versions: [versionInfo(3)],
            yaml: saved,
          );
        });
    await pumpBuilder(tester, repository: repository);

    await type(tester, field('Name').first, 'Nightly');
    await type(tester, field('Description').first, '');
    await press(tester, find.text('One run at a time per project'));

    expect(yamlOf(tester), startsWith('schema: 1\nname: Nightly\ninputs:'));
    expect(find.text('store-release · Version 2 · Unsaved changes'), findsOne);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await settle(tester);

    expect(saved, yamlOf(tester));
    expect(find.text('Saved store-release, version 3.'), findsOneWidget);
    expect(find.text('store-release · Version 3'), findsOneWidget);
  });

  testWidgets('adds, renames, moves and removes stages and jobs', (
    tester,
  ) async {
    await pumpBuilder(tester, repository: repository);

    await press(tester, find.text('Add stage'));
    expect(find.text('STAGE-3'), findsOneWidget);
    expect(find.text('STAGE 3 · JOB'), findsOneWidget);
    expect(
      yamlOf(tester),
      endsWith(
        '  - name: stage-3\n    jobs:\n'
        '      stage-3:\n        steps: []\n',
      ),
    );

    await press(tester, find.text('Add job').first);
    expect(find.text('check-2'), findsWidgets);
    expect(find.text('STAGE 1 · JOB'), findsOneWidget);

    await press(tester, find.byTooltip('Move earlier'));
    expect(
      WorkflowDocument.parse(yamlOf(tester)).stages[0].jobs.map((j) => j.id),
      ['check-2', 'check'],
    );
    final beforeRemoval = yamlOf(tester);
    await press(tester, find.byTooltip('Remove job'));
    expect(find.text('check-2'), findsNothing);
    expect(find.text('Removed job check-2'), findsOneWidget);
    await press(tester, find.widgetWithText(XpButton, 'Undo').last);
    expect(yamlOf(tester), beforeRemoval);
    expect(find.text('Removed job check-2'), findsNothing);
    await press(tester, find.text('check-2').first);
    await press(tester, find.byTooltip('Remove job'));
    expect(find.text('check-2'), findsNothing);

    await press(tester, find.text('CHECK'));
    await type(tester, field('Stage name'), 'verify');
    expect(find.text('VERIFY'), findsWidgets);
    await press(tester, find.byTooltip('Move later'));
    expect(WorkflowDocument.parse(yamlOf(tester)).stages.map((s) => s.name), [
      'build',
      'verify',
      'stage-3',
    ]);
    await press(tester, find.byTooltip('Remove stage'));
    expect(find.text('Removed stage verify'), findsOneWidget);
    expect(WorkflowDocument.parse(yamlOf(tester)).stages.map((s) => s.name), [
      'build',
      'stage-3',
    ]);
    // The workflow shows again: its name and its inputs.
    expect(find.text('INPUTS'), findsOneWidget);

    await press(tester, find.text('STORE RELEASE'));
    expect(find.text('INPUTS'), findsOneWidget);
  });

  testWidgets('takes its Undo toasts away when it closes', (tester) async {
    final toasts = ToastCubit();
    await pumpBuilder(tester, repository: repository, toasts: toasts);
    await press(tester, find.text('Add job').first);
    await press(tester, find.byTooltip('Remove job'));
    expect(find.text('Removed job check-2'), findsOneWidget);

    await tester.pumpApp(const SizedBox(), toasts: toasts);
    await tester.pump();

    expect(toasts.state.toasts, isEmpty);
    expect(find.text('Removed job check-2'), findsNothing);
  });

  testWidgets('edits a job: id, name, if, matrix and capabilities', (
    tester,
  ) async {
    await pumpBuilder(tester, repository: repository);
    await press(tester, find.text('build').first);

    await type(tester, field('Job id'), 'compile');
    await type(tester, field('Job name'), '');
    await type(tester, field('If'), '');
    await press(tester, find.text('Listed').first);
    await press(tester, find.text('ios'));
    await press(tester, find.text('From dispatch').last);
    await press(tester, find.text('android').last);
    await press(tester, find.text('ios-sign'));
    await press(tester, find.text('flutter'));

    var job = WorkflowDocument.parse(yamlOf(tester)).stages[1].jobs.single;
    expect(job.id, 'compile');
    expect(job.name, isNull);
    expect(job.condition, isNull);
    expect(job.matrix, const [
      WorkflowMatrixAxis.list('platform', ['android']),
      WorkflowMatrixAxis.placeholder('flavor', r'${{ flavors }}'),
    ]);
    expect(job.capabilities, ['android', 'ios-sign']);

    await press(tester, find.text('Listed').last);
    await type(tester, find.widgetWithText(TextField, 'prod, dev'), 'a, , b');
    job = WorkflowDocument.parse(yamlOf(tester)).stages[1].jobs.single;
    expect(
      job.axis('flavor'),
      const WorkflowMatrixAxis.list('flavor', ['a', 'b']),
    );
    await press(tester, find.text('None').first);
    job = WorkflowDocument.parse(yamlOf(tester)).stages[1].jobs.single;
    expect(job.axis('platform'), isNull);
  });

  testWidgets('adds a step from the engine types and edits it', (tester) async {
    await pumpBuilder(tester, repository: repository);
    await press(tester, find.text('build').first);

    await press(tester, find.text('Add step'));
    await press(tester, find.byKey(const ValueKey(('step-type', 'command'))));
    await press(tester, find.text('command'));

    await type(tester, field('If').last, "platform == 'ios'");
    await type(
      tester,
      find.widgetWithText(TextField, 'YAML value').first,
      'echo hi',
    );
    await tester.ensureVisible(find.text('No gate').last);
    await tester.tap(find.text('No gate').last);
    await tester.pumpAndSettle();
    await press(tester, find.text('push').last);
    await tester.ensureVisible(find.text('command').last);
    await tester.tap(find.text('command').last);
    await tester.pumpAndSettle();
    await press(tester, find.text('guard').last);

    var steps = WorkflowDocument.parse(yamlOf(tester))
        .stages[1]
        .jobs
        .single
        .steps;
    expect(
      steps.last,
      const WorkflowStep(
        kind: 'guard',
        condition: "platform == 'ios'",
        gate: 'push',
        withValues: {'run': 'echo hi'},
      ),
    );

    await type(
      tester,
      find.byWidgetPredicate(
        (widget) => widget is TextField && widget.controller?.text == 'echo hi',
      ),
      '',
    );
    steps = WorkflowDocument.parse(yamlOf(tester)).stages[1].jobs.single.steps;
    expect(steps.last.withValues, isEmpty);
    await type(
      tester,
      find.widgetWithText(TextField, 'YAML value').first,
      '[a, b]',
    );
    steps = WorkflowDocument.parse(yamlOf(tester)).stages[1].jobs.single.steps;
    expect(steps.last.withValues, {
      'checks': ['a', 'b'],
    });

    await press(tester, find.byTooltip('Move earlier').last);
    await press(tester, find.byTooltip('Move later').at(1));
    final beforeRemoval = yamlOf(tester);
    await press(tester, find.byTooltip('Remove step').first);
    expect(find.text('Removed step build.android'), findsOneWidget);
    steps = WorkflowDocument.parse(yamlOf(tester)).stages[1].jobs.single.steps;
    expect(steps.map((s) => s.kind), ['git.checkout', 'guard', 'upload.play']);

    // ⌘Z puts the YAML back exactly as it was; ⇧⌘Z removes the step again.
    await tester.tap(yamlField);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await settle(tester);
    expect(yamlOf(tester), beforeRemoval);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await settle(tester);
    steps = WorkflowDocument.parse(yamlOf(tester)).stages[1].jobs.single.steps;
    expect(steps.map((s) => s.kind), ['git.checkout', 'guard', 'upload.play']);
  });

  testWidgets(
    'says why no step can be added while the engine is away, and takes '
    'the type of a step as text',
    (tester) async {
      when(repository.schema).thenThrow(const ConnectionException('away'));
      await pumpBuilder(tester, repository: repository);
      await press(tester, find.text('build').first);

      final add = find.widgetWithText(XpButton, 'Add step');
      await tester.ensureVisible(add);
      expect(tester.widget<XpButton>(add).onPressed, isNull);
      expect(
        find.byTooltip(
          'The engine cannot be reached, so its step types are not known. '
          'Edit the YAML for now, or try again once it answers.',
        ),
        findsOneWidget,
      );

      await press(tester, find.text('build.android'));
      await type(tester, field('Step type'), 'shell');

      final steps = WorkflowDocument.parse(yamlOf(tester))
          .stages[1]
          .jobs
          .single
          .steps;
      expect(steps[1].kind, 'shell');
    },
  );

  testWidgets('picks a step type by group and search', (tester) async {
    await pumpBuilder(tester, repository: repository);
    await press(tester, find.text('build').first);
    await press(tester, find.text('Add step'));

    expect(find.text('Add a step'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(StepPickerDialog),
        matching: find.text('BUILD'),
      ),
      findsOneWidget,
    );
    expect(find.text('Build iOS'), findsOneWidget);
    expect(find.text('Builds and signs an IPA.'), findsOneWidget);

    await type(
      tester,
      find.descendant(
        of: find.byType(StepPickerDialog),
        matching: find.byType(TextField),
      ),
      'sign',
    );
    expect(find.byKey(const ValueKey(('step-type', 'build.ios'))), findsOne);
    expect(find.byKey(const ValueKey(('step-type', 'command'))), findsNothing);

    await type(
      tester,
      find.descendant(
        of: find.byType(StepPickerDialog),
        matching: find.byType(TextField),
      ),
      'zzz',
    );
    expect(find.text('No step type matches.'), findsOneWidget);

    await press(tester, find.text('Cancel'));
    expect(find.byType(StepPickerDialog), findsNothing);
    final steps = WorkflowDocument.parse(yamlOf(tester))
        .stages[1]
        .jobs
        .single
        .steps;
    expect(steps, hasLength(3));
  });

  testWidgets('edits with by type and marks a key the step needs (UX-02)', (
    tester,
  ) async {
    when(repository.schema).thenAnswer(
      (_) async => WorkflowSchema(
        schema: 1,
        steps: [
          for (final step in schema.steps)
            if (step.kind != 'guard') step,
          const StepType(
            kind: 'guard',
            withKeys: ['checks'],
            keys: [
              StepKeySchema(
                name: 'checks',
                type: StepKeyType.list,
                options: ['source', 'credentials', 'versionSync'],
              ),
            ],
          ),
        ],
        gates: schema.gates,
        capabilities: schema.capabilities,
        matrixAxes: schema.matrixAxes,
        platforms: schema.platforms,
      ),
    );
    await pumpBuilder(tester, repository: repository);
    await press(tester, find.text('build').first);
    List<WorkflowStep> steps() =>
        WorkflowDocument.parse(yamlOf(tester)).stages[1].jobs.single.steps;

    await press(tester, find.text('Add step'));
    await press(tester, find.byKey(const ValueKey(('step-type', 'build.ios'))));
    await press(tester, find.text('build.ios'));
    expect(find.text('Needed'), findsOneWidget);
    await type(
      tester,
      find.widgetWithText(TextField, 'The export options plist.'),
      'ios/ExportOptions.plist',
    );
    expect(find.text('Needed'), findsNothing);
    expect(steps().last.withValues, {
      'exportOptionsPlist': 'ios/ExportOptions.plist',
    });

    await press(tester, find.text('build.android'));
    await press(tester, find.text('On').first);
    expect(steps()[1].withValues, {'artifact': 'aab', 'obfuscate': true});
    await press(tester, find.text('Default (false)').first);
    expect(steps()[1].withValues, {'artifact': 'aab'});
    await press(tester, find.text('aab').first);
    await press(tester, find.text('Default (apk)').last);
    expect(steps()[1].withValues, isEmpty);

    await press(tester, find.text('Add step'));
    await press(tester, find.byKey(const ValueKey(('step-type', 'guard'))));
    await press(tester, find.text('guard').last);
    await press(tester, find.text('versionSync').last);
    expect(steps().last.withValues, {
      'checks': ['versionSync'],
    });
  });

  testWidgets('completes the variables in an if, and labels gates', (
    tester,
  ) async {
    await pumpBuilder(tester, repository: repository);
    await press(tester, find.text('build').first);
    await press(tester, find.text('upload.play'));
    expect(find.text('store submission'), findsWidgets);

    await type(tester, field('If').last, 'flavor.n');
    expect(find.text('flavor.name'), findsOneWidget);
    await press(tester, find.text('flavor.name'));

    expect(
      WorkflowDocument.parse(yamlOf(tester))
          .stages[1]
          .jobs
          .single
          .steps
          .last
          .condition,
      'flavor.name',
    );
  });

  testWidgets('typed YAML updates the pipeline, or locks it with issues', (
    tester,
  ) async {
    await pumpBuilder(tester, repository: repository);

    await type(
      tester,
      yamlField,
      releaseYaml.replaceFirst('name: check', 'name: lint'),
    );
    expect(find.text('LINT'), findsOneWidget);

    when(() => repository.validate('prj_1', 'stages:\n  - oops\n')).thenAnswer(
      (_) async => const ValidateWorkflowResponse(
        valid: false,
        issues: [
          WorkflowIssue(line: 1, column: 1, message: 'Add "schema: 1".'),
        ],
      ),
    );
    await type(tester, yamlField, 'stages:\n  - oops\n');

    expect(
      find.text(
        'The visual editor waits until the YAML reads as a workflow. '
        'Fix the issues in the YAML.',
      ),
      findsOneWidget,
    );
    expect(find.text('2 issues'), findsOneWidget);
    expect(find.text('2:5'), findsOneWidget);
    await tester.tap(find.text('A stage is a mapping with "name" and "jobs".'));
    await tester.pump();
    expect(
      tester.widget<TextField>(yamlField).controller!.selection.baseOffset,
      12,
    );
    final add = tester.widget<XpButton>(
      find.widgetWithText(XpButton, 'Add stage'),
    );
    expect(add.onPressed, isNull);

    when(() => repository.validate('prj_1', any()))
        .thenThrow(const ConnectionException('away'));
    await type(tester, yamlField, '{a: [');
    expect(find.text('Not checked · engine away'), findsNothing);
    expect(find.text('LINT'), findsOneWidget);
  });

  testWidgets('an issue shows its hint under it', (tester) async {
    await pumpBuilder(tester, repository: repository);
    final yaml = releaseYaml.replaceFirst('name: check', 'name: lint');
    when(() => repository.validate('prj_1', yaml)).thenAnswer(
      (_) async => const ValidateWorkflowResponse(
        valid: false,
        issues: [
          WorkflowIssue(
            line: 4,
            column: 3,
            message: 'The workflow has no input "notez".',
            hint: 'Did you mean "inputs.notes"?',
          ),
        ],
      ),
    );

    await type(tester, yamlField, yaml);

    expect(find.text('The workflow has no input "notez".'), findsOneWidget);
    expect(find.text('Did you mean "inputs.notes"?'), findsOneWidget);
  });

  testWidgets('starts a new workflow and saves it under a name', (
    tester,
  ) async {
    when(
      () => repository.createWorkflow(
        'prj_1',
        name: 'nightly',
        yaml: any(named: 'yaml'),
      ),
    ).thenAnswer(
      (invocation) async => Workflow(
        id: 'wf_new',
        projectId: 'prj_1',
        name: 'nightly',
        builtin: false,
        version: versionInfo(1),
        versions: [versionInfo(1)],
        yaml: invocation.namedArguments[#yaml] as String,
      ),
    );
    when(() => repository.listWorkflows('prj_1'))
        .thenAnswer((_) async => [summaryOf(releaseWorkflow)]);
    await pumpBuilder(tester, repository: repository);

    await press(tester, find.text('New'));
    expect(find.text('Start a new workflow'), findsOneWidget);
    await press(tester, find.byKey(const ValueKey(('template', 'blank'))));
    expect(find.text('Not saved yet'), findsWidgets);
    expect(yamlOf(tester), templates.first.yaml);

    await tester.tap(find.text('Save as…'));
    await tester.pumpAndSettle();
    expect(find.text('Save as a new workflow'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    verifyNever(
      () => repository.createWorkflow(
        any(),
        name: any(named: 'name'),
        yaml: any(named: 'yaml'),
      ),
    );

    await tester.tap(find.text('Save as…'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(WorkflowNameDialog),
        matching: find.byType(TextField),
      ),
      'nightly',
    );
    await tester.pump();
    await press(
      tester,
      find.descendant(
        of: find.byType(WorkflowNameDialog),
        matching: find.text('Save'),
      ),
    );

    expect(find.text('Saved nightly, version 1.'), findsOneWidget);
    expect(find.text('nightly · Version 1'), findsOneWidget);
  });

  testWidgets('starts a new workflow from a template, or not', (tester) async {
    await pumpBuilder(tester, repository: repository);

    await press(tester, find.text('New'));
    expect(find.text('Tests only'), findsOneWidget);
    expect(find.text('Runs the tests.'), findsOneWidget);
    await press(tester, find.text('Cancel'));
    expect(yamlOf(tester), releaseYaml);

    await press(tester, find.text('New'));
    await press(tester, find.byKey(const ValueKey(('template', 'tests'))));
    expect(yamlOf(tester), templates.last.yaml);
    expect(find.textContaining('tests · '), findsOneWidget);
  });

  testWidgets('starts a blank workflow when the engine has no templates', (
    tester,
  ) async {
    when(repository.templates).thenThrow(const ConnectionException('away'));
    await pumpBuilder(tester, repository: repository);

    await press(tester, find.text('New'));

    expect(find.text('Start a new workflow'), findsNothing);
    expect(yamlOf(tester), draftTemplate.toYaml());
  });

  testWidgets('edits the inputs of the workflow (UX-04)', (tester) async {
    await pumpBuilder(tester, repository: repository);
    List<WorkflowInput> inputs() =>
        WorkflowDocument.parse(yamlOf(tester)).inputs;
    expect(inputs().single.name, 'notes');

    await press(tester, find.text('Add input'));
    expect(inputs().map((input) => input.name), ['notes', 'input']);
    await type(tester, field('Name').last, 'track');
    await press(tester, find.text('Any').last);
    await press(tester, find.text('Choice').last);
    await type(tester, field('Options').last, 'internal, beta');
    await type(tester, field('Description').last, 'The Play track.');
    await press(tester, find.text('None').last);
    await press(tester, find.text('beta').last);
    expect(
      inputs().last,
      const WorkflowInput(
        name: 'track',
        type: InputType.choice,
        description: 'The Play track.',
        options: ['internal', 'beta'],
        defaultValue: 'beta',
      ),
    );

    await press(tester, find.text('Required').last);
    expect(inputs().last.required, isTrue);
    expect(inputs().last.defaultValue, isNull);
    expect(find.text('DEFAULT'), findsOneWidget, reason: 'notes only');

    await type(tester, field('Name').last, 'bad-name');
    expect(
      find.text('Letters, digits and _, starting with a letter or _.'),
      findsOneWidget,
    );
    await press(tester, find.byTooltip('Remove input').last);
    expect(find.text('Removed input bad-name'), findsOneWidget);
    expect(inputs().map((input) => input.name), ['notes']);
  });

  group('lifecycle (UX-06)', () {
    Workflow mine({DateTime? archivedAt, WorkflowBasedOn? basedOn}) => Workflow(
      id: 'wf_mine',
      projectId: 'prj_1',
      name: 'store-release',
      builtin: false,
      version: releaseWorkflow.version,
      versions: releaseWorkflow.versions,
      yaml: releaseYaml,
      archivedAt: archivedAt,
      basedOn: basedOn,
    );

    setUpAll(() => registerFallbackValue(const UpdateWorkflowRequest()));

    testWidgets('archives from the menu, with an undo', (tester) async {
      when(() => repository.updateWorkflow('prj_1', 'wf_mine', any()))
          .thenAnswer(
            (invocation) async =>
                (invocation.positionalArguments[2] as UpdateWorkflowRequest)
                        .archived ??
                    false
                ? mine(archivedAt: DateTime.utc(2026))
                : mine(),
          );
      await pumpBuilder(tester, repository: repository);

      await press(tester, find.text('More'));
      await press(tester, find.text('Archive'));

      expect(find.text('Archived store-release'), findsOneWidget);
      expect(
        find.text(
          'Archived: kept with its versions and runs, and not offered to '
          'dispatch.',
        ),
        findsOneWidget,
      );
      await press(tester, find.widgetWithText(XpButton, 'Undo').last);
      expect(
        verify(
          () => repository.updateWorkflow('prj_1', 'wf_mine', captureAny()),
        ).captured,
        const [
          UpdateWorkflowRequest(archived: true),
          UpdateWorkflowRequest(archived: false),
        ],
      );
    });

    testWidgets('renames from the menu', (tester) async {
      when(() => repository.updateWorkflow('prj_1', 'wf_mine', any()))
          .thenAnswer((_) async => mine());
      await pumpBuilder(tester, repository: repository);

      await press(tester, find.text('More'));
      await press(tester, find.text('Rename…'));
      expect(find.text('Rename the workflow'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(WorkflowNameDialog),
          matching: find.byType(TextField),
        ),
        'nightly',
      );
      await tester.pump();
      await press(
        tester,
        find.descendant(
          of: find.byType(WorkflowNameDialog),
          matching: find.text('Save'),
        ),
      );

      verify(
        () => repository.updateWorkflow(
          'prj_1',
          'wf_mine',
          const UpdateWorkflowRequest(name: 'nightly'),
        ),
      ).called(1);
    });

    testWidgets('deletes after asking', (tester) async {
      when(() => repository.deleteWorkflow('prj_1', 'wf_mine'))
          .thenAnswer((_) async {});
      await pumpBuilder(tester, repository: repository);

      await press(tester, find.text('More'));
      await press(tester, find.text('Delete…'));
      expect(find.text('Delete store-release?'), findsOneWidget);
      await press(
        tester,
        find.descendant(
          of: find.byType(XpConfirmDialog),
          matching: find.text('Delete'),
        ),
      );

      verify(() => repository.deleteWorkflow('prj_1', 'wf_mine')).called(1);
      expect(find.text('Deleted store-release.'), findsOneWidget);
    });

    testWidgets('offers only the versions of a built-in', (tester) async {
      await pumpBuilder(tester, repository: repository, workflowId: 'wf_dev');

      await press(tester, find.text('More'));

      expect(find.text('Versions…'), findsOneWidget);
      expect(find.text('Rename…'), findsNothing);
      expect(find.text('Delete…'), findsNothing);
    });

    testWidgets('compares versions and restores one', (tester) async {
      Workflow at(int version, String yaml) => Workflow(
        id: 'wf_mine',
        projectId: 'prj_1',
        name: 'store-release',
        builtin: false,
        version: versionInfo(version),
        versions: releaseWorkflow.versions,
        yaml: yaml,
      );
      when(() => repository.getWorkflow('prj_1', 'wf_mine', version: 1))
          .thenAnswer((_) async => at(1, 'schema: 1\nname: First\n'));
      when(() => repository.getWorkflow('prj_1', 'wf_mine', version: 2))
          .thenAnswer((_) async => at(2, 'schema: 1\nname: Second\n'));
      when(
        () => repository.saveWorkflow(
          'prj_1',
          'wf_mine',
          'schema: 1\nname: First\n',
        ),
      ).thenAnswer((_) async => at(3, 'schema: 1\nname: First\n'));
      await pumpBuilder(tester, repository: repository);

      await press(tester, find.text('More'));
      await press(tester, find.text('Versions…'));

      expect(find.text('Versions of store-release'), findsOneWidget);
      expect(find.text('-name: First'), findsOneWidget);
      expect(find.text('+name: Second'), findsOneWidget);
      await press(tester, find.text('Restore version 1'));

      expect(find.byType(WorkflowVersionsDialog), findsNothing);
      expect(
        find.text('Saved version 1 again as version 3 of store-release.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'a copy of dev-build offers to compare once dev-build has a newer '
      'version',
      (tester) async {
        const basedOn = WorkflowBasedOn(builtin: 'dev-build', version: 1);
        final newer = Workflow(
          id: 'wf_dev',
          projectId: 'prj_1',
          name: 'dev-build',
          builtin: true,
          version: versionInfo(2),
          versions: [versionInfo(1), versionInfo(2)],
          yaml: '${devBuild.yaml}          - kind: version.bump\n',
        );
        when(() => repository.listWorkflows('prj_1')).thenAnswer(
          (_) async => [summaryOf(newer), summaryOf(mine(basedOn: basedOn))],
        );
        when(() => repository.getWorkflow('prj_1', 'wf_mine'))
            .thenAnswer((_) async => mine(basedOn: basedOn));
        when(() => repository.getWorkflow('prj_1', 'wf_dev', version: 1))
            .thenAnswer((_) async => devBuild);
        when(() => repository.getWorkflow('prj_1', 'wf_dev'))
            .thenAnswer((_) async => newer);
        when(
          () => repository.updateWorkflow('prj_1', 'wf_mine', any()),
        ).thenAnswer(
          (_) async => mine(
            basedOn: const WorkflowBasedOn(builtin: 'dev-build', version: 2),
          ),
        );
        await pumpBuilder(tester, repository: repository);

        expect(
          find.text(
            'The built-in dev-build has a newer version (2); this copy is '
            'based on version 1.',
          ),
          findsOneWidget,
        );
        await press(tester, find.text('Compare'));
        expect(find.text('Compare with dev-build'), findsOneWidget);
        expect(
          find.text('WHAT DEV-BUILD CHANGED, VERSION 1 TO 2'),
          findsOneWidget,
        );
        expect(find.text('+          - kind: version.bump'), findsOneWidget);

        await press(tester, find.text('Mark as up to date'));
        verify(
          () => repository.updateWorkflow(
            'prj_1',
            'wf_mine',
            const UpdateWorkflowRequest(basedOnVersion: 2),
          ),
        ).called(1);
      },
    );
  });

  testWidgets('asks before dropping unsaved changes', (tester) async {
    await pumpBuilder(tester, repository: repository);
    await type(tester, field('Name').first, 'Changed');

    await tester.tap(find.text('store-release').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('dev-build').last);
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    expect(find.text('The changes to store-release are not saved.'), findsOne);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsNothing);

    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field('Name').first).controller!.text,
      'Changed',
    );

    await tester.tap(find.text('store-release').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('dev-build').last);
    await tester.pumpAndSettle();
    await press(tester, find.text('Discard'));

    expect(find.text('dev-build · Version 1 · Built-in'), findsOneWidget);
    expect(
      find.text(
        'Built-in workflows cannot be changed. Save as… keeps your edits as '
        'a workflow of your own.',
      ),
      findsOneWidget,
    );
    expect(find.text('Save as…'), findsOneWidget);
  });

  testWidgets('asks before the shell leaves with unsaved changes', (
    tester,
  ) async {
    final shell = ShellCubit(const WorkflowsDestination('prj_1'));
    await pumpBuilder(tester, repository: repository, shell: shell);

    // Nothing to lose: the shell leaves at once.
    shell.show(const ReleasesDestination('prj_1'));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsNothing);
    expect(shell.state, const ReleasesDestination('prj_1'));

    await type(tester, field('Name').first, 'Changed');
    shell.show(const TestsDestination('prj_1'));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(shell.state, const ReleasesDestination('prj_1'));
    expect(
      tester.widget<TextField>(field('Name').first).controller!.text,
      'Changed',
    );

    shell.show(const TestsDestination('prj_1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(shell.state, const TestsDestination('prj_1'));
  });

  testWidgets('saves a copy of a built-in under a free name at once', (
    tester,
  ) async {
    when(
      () => repository.createWorkflow(
        'prj_1',
        name: 'dev-build-copy',
        yaml: any(named: 'yaml'),
        basedOn: const WorkflowBasedOn(builtin: 'dev-build', version: 1),
      ),
    ).thenAnswer(
      (invocation) async => Workflow(
        id: 'wf_copy',
        projectId: 'prj_1',
        name: 'dev-build-copy',
        builtin: false,
        version: versionInfo(1),
        versions: [versionInfo(1)],
        yaml: invocation.namedArguments[#yaml] as String,
      ),
    );
    await pumpBuilder(tester, repository: repository, workflowId: 'wf_dev');

    await tester.tap(find.text('Save as…'));
    await tester.pumpAndSettle();
    final name = find.descendant(
      of: find.byType(WorkflowNameDialog),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(name).controller!.text, 'dev-build-copy');

    await tester.enterText(name, 'store-release');
    await tester.pump();
    expect(
      find.text('The project already has a workflow called store-release.'),
      findsOneWidget,
    );
    await tester.enterText(name, 'my build');
    await tester.pump();
    expect(
      find.text(
        'Start with a letter or digit; then letters, digits, dots, dashes '
        'and underscores, 64 at most.',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(WorkflowNameDialog),
        matching: find.text('Save'),
      ),
    );
    await tester.pump();
    expect(find.byType(WorkflowNameDialog), findsOneWidget);

    await tester.enterText(name, 'dev-build-copy');
    await tester.pump();
    await press(
      tester,
      find.descendant(
        of: find.byType(WorkflowNameDialog),
        matching: find.text('Save'),
      ),
    );
    expect(find.text('Saved dev-build-copy, version 1.'), findsOneWidget);
  });

  test('copyName offers the first free copy name', () {
    expect(copyName('dev-build', const {}), 'dev-build-copy');
    expect(
      copyName('dev-build', const {'dev-build-copy', 'dev-build-copy-2'}),
      'dev-build-copy-3',
    );
  });

  testWidgets('runs the open workflow from the builder', (tester) async {
    when(() => repository.lastInputs(any(), any()))
        .thenAnswer((_) async => const {});
    when(() => repository.lastWorkflow(any())).thenAnswer((_) async => null);
    when(
      () => repository.plan(any(), any(), any()),
    ).thenAnswer((_) async => const DispatchPlan(flavors: [], platforms: []));
    await pumpBuilder(tester, repository: repository);

    await tester.tap(find.text('Run…'));
    await tester.pumpAndSettle();

    expect(find.byType(DispatchSheet), findsOneWidget);
    verify(() => repository.getWorkflow('prj_1', 'wf_mine')).called(2);
  });

  testWidgets('imports and exports YAML files', (tester) async {
    final exported = <(String, String)>[];
    await pumpBuilder(
      tester,
      repository: repository,
      pickFile: () async =>
          PickedFile(name: 'nightly.yml', bytes: utf8.encode(releaseYaml)),
      saveFile: (name, contents) async {
        exported.add((name, contents));
        return '/Users/me/$name';
      },
    );

    await press(tester, find.text('Export…'));
    expect(exported, [('store-release.yaml', releaseYaml)]);
    expect(
      find.text('Exported to /Users/me/store-release.yaml.'),
      findsOneWidget,
    );

    await press(tester, find.text('Import…'));
    expect(find.text('nightly · Not saved yet'), findsOneWidget);
    expect(find.text('nightly'), findsWidgets);
  });

  testWidgets('says why the engine refused', (tester) async {
    when(() => repository.listWorkflows('prj_1'))
        .thenThrow(const ApiException('Secrets are locked.', statusCode: 503));
    await pumpBuilder(tester, repository: repository);

    expect(find.text('Secrets are locked.'), findsOneWidget);
  });

  testWidgets('says when the project is gone', (tester) async {
    await tester.pumpApp(
      const WorkflowBuilderPage(projectId: 'prj_gone'),
      projects: projectsIn(const ProjectsState(loaded: true)),
    );

    expect(find.text('Workflows'), findsOneWidget);
    expect(find.byType(WorkflowBuilderView), findsNothing);
  });
}
