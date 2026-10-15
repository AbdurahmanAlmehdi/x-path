import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide StepState;
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/job/job.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';

import '../helpers/job_fixtures.dart';
import '../helpers/pump_app.dart';

void main() {
  late AppLocalizations l10n;

  Future<void> setUpL10n(WidgetTester tester) async {
    await tester.pumpApp(const SizedBox());
    l10n = tester.element(find.byType(SizedBox)).l10n;
  }

  group('job labels', () {
    testWidgets('name every state, step kind and gate', (tester) async {
      await setUpL10n(tester);
      for (final state in JobState.values) {
        expect(l10n.jobState(state), isNotEmpty);
        expect(jobStatus(state), isA<XpStatus>());
      }
      for (final state in StepState.values) {
        expect(l10n.stepState(state), isNotEmpty);
        expect(stepStatus(state), isA<XpStatus>());
      }
      const kinds = [
        'git.checkout',
        'guard',
        'version.bump',
        'build.android',
        'build.ios',
        'build.verifyCompiledConfig',
        'ios.stripAndReexport',
        'shorebird.release',
        'shorebird.patch',
        'symbols.archive',
        'test',
        'analyze',
        'upload.appStore',
        'upload.play',
        'upload.firebase',
        'git.tag',
        'git.push',
        'git.releaseBranch',
        'github.createPr',
        'github.mergePr',
        'record.manifest',
        'gate',
        'command',
      ];
      expect({for (final kind in kinds) l10n.stepKind(kind)}, hasLength(23));
      expect(l10n.stepKind('custom.step'), 'custom.step');
      for (final action in [
        'prod_release',
        'prod_patch',
        'store_submission',
        'push',
        'merge',
        'delete',
      ]) {
        expect(l10n.gateAction(action), isNotEmpty);
      }
      expect(l10n.gateAction('store_submission'), 'store submission');
      expect(l10n.gateAction('other'), 'other');
    });

    test('resumes from the step picked, at most the first unfinished', () {
      final job = interruptedRun().jobs[1];
      expect(resumeFrom(job, null), 2);
      expect(resumeFrom(job, 1), 1);
      expect(resumeFrom(job, 3), 2);
      expect(resumeFrom(runningRun().jobs[0], 0), 0);
      expect(isResumable(JobState.failed), isTrue);
      expect(isResumable(JobState.running), isFalse);
    });
  });

  group('PipelineGraph', () {
    testWidgets('numbers stages the workflow does not name', (tester) async {
      await setUpL10n(tester);
      final run = runningRun();
      final stages = pipelineStages(
        runJobs: run,
        l10n: l10n,
        now: testNow,
        engineName: 'This Mac',
      );
      expect(stages.map((stage) => stage.label), [
        'Stage 1',
        'Stage 2',
        'Stage 3',
        'Stage 4',
      ]);
      expect(stages.first.done, isTrue);
      expect(stages[1].nodes[1].runner, linuxBuilder);
    });

    testWidgets('flags a stage that waits for an approval', (tester) async {
      String? tapped;
      await tester.pumpApp(
        PipelineGraph(
          stages: const [
            PipelineStage(
              label: 'upload',
              needsYou: true,
              nodes: [
                PipelineNode(
                  id: 'job_upload',
                  name: 'Upload',
                  status: XpStatus.jobWaitingApproval,
                ),
              ],
            ),
          ],
          onNodeTap: (id) => tapped = id,
        ),
      );
      expect(find.text('UPLOAD · NEEDS YOU'), findsOneWidget);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(find.text('Upload')));
      await tester.pump();
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      await tester.tap(find.text('Upload'));
      expect(tapped, 'job_upload');
    });
  });
}
