@Tags(['golden'])
library;

import 'package:flutter/widgets.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/workflow_builder/workflow_builder.dart';

import '../helpers/load_fonts.dart';
import 'workflow_builder_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a job of the builder, in light', (tester) async {
    await pumpBuilder(tester);
    await tester.tap(find.text('build').last);
    await tester.pump();
    await tester.tap(find.text('upload.play'));
    await settle(tester);
    await expectLater(
      find.byType(WorkflowBuilderPage),
      matchesGoldenFile('goldens/workflow_builder_light.png'),
    );
  });

  testWidgets('issues with their lines, in dark', (tester) async {
    final repository = workflowsRepository();
    when(() => repository.validate('prj_1', any())).thenAnswer(
      (_) async => const ValidateWorkflowResponse(
        valid: false,
        issues: [
          WorkflowIssue(
            line: 22,
            column: 9,
            message: 'Unknown variable "flavor". Known here: app, build, ...',
          ),
          WorkflowIssue(
            line: 31,
            column: 19,
            message: 'Unknown gate. Allowed: prod_release, push.',
          ),
        ],
      ),
    );
    await pumpBuilder(
      tester,
      repository: repository,
      brightness: Brightness.dark,
    );
    await expectLater(
      find.byType(WorkflowBuilderPage),
      matchesGoldenFile('goldens/workflow_builder_dark.png'),
    );
  });
}
