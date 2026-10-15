import 'package:flutter/widgets.dart' show Brightness, Scrollable;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/tests/tests.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/engine_fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

TestRunResponse _withDiff(TestRunDiff diff, {int total = 0}) => TestRunResponse(
  run: TestRun(
    id: 'tst_9',
    jobId: 'job_x',
    branch: 'feature/cart',
    appPath: 'apps/captain',
    baseline: false,
    createdAt: devRun.run.createdAt,
    counts: devRun.run.counts,
    diff: diff,
  ),
  total: total,
  offset: 0,
  tests: const [],
);

/// The repositories behind the tests of `mataa`.
class TestsHarness {
  new({List<TestBaseline>? baselines}) {
    when(() => tests.watchBaselines('prj_1')).thenAnswer(
      (_) =>
          Stream.value(Snapshot(baselines ?? [mainBaseline, releaseBaseline])),
    );
    when(() => tests.completedRuns('prj_1'))
        .thenAnswer((_) => const Stream.empty());
    when(() => tests.watchRun('job_dev'))
        .thenAnswer((_) => Stream.value(Snapshot(devRun)));
    when(() => tests.watchRun('job_base'))
        .thenAnswer((_) => Stream.value(Snapshot(baselineRun)));
    when(() => jobs.watchJob(any())).thenAnswer((_) => const Stream.empty());
    when(() => jobs.watchJob('job_dev'))
        .thenAnswer((_) => Stream.value(Snapshot(devJob)));
  }

  final tests = MockTestsRepository();
  final jobs = MockJobsRepository();

  Future<void> pump(
    WidgetTester tester, {
    String? jobId = 'job_dev',
    ShellCubit? shell,
    String projectId = 'prj_1',
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpApp(
      TestsPage(projectId: projectId, jobId: jobId),
      shell: shell,
      brightness: brightness,
      testsRepository: tests,
      jobsRepository: jobs,
      projects: projectsIn(
        const ProjectsState(loaded: true, projects: [mataa]),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }
}

void main() {
  group('TestsPage', () {
    testWidgets('shows a run against its baseline, new failures first', (
      tester,
    ) async {
      final shell = ShellCubit();
      await TestsHarness().pump(tester, shell: shell);
      expect(find.text('1 new failure'), findsOneWidget);
      expect(find.text('mataa_new_app · dev'), findsOneWidget);
      expect(
        find.textContaining('Compared with the baseline of main'),
        findsOne,
      );
      expect(find.text('2m 41s'), findsOneWidget);
      expect(find.text('1,284'), findsWidgets);
      expect(find.text('NEW FAILURES'), findsOneWidget);
      expect(find.text('cart totals include the delivery fee'), findsOneWidget);
      expect(find.text('Expected: <12.5>\n  Actual: <10.0>'), findsOneWidget);
      expect(find.text('FAILING IN THE BASELINE TOO'), findsOneWidget);
      expect(find.text('Errored'), findsOneWidget);
      expect(find.text('FIXED SINCE THE BASELINE'), findsOneWidget);
      expect(find.text('Fixed'), findsNWidgets(3));
      expect(find.text('Not reported'), findsOneWidget);

      await tester.tap(find.text('Open job'));
      expect(
        shell.state,
        const JobDestination('run_tests', jobId: 'job_dev', projectId: 'prj_1'),
      );
      await tester.scrollUntilVisible(
        find.text('release/5.4.1'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('BASELINES'), findsOneWidget);
    });

    testWidgets('switches to a baseline run', (tester) async {
      await TestsHarness().pump(tester);
      await tester.scrollUntilVisible(
        find.text('release/5.4.1'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Show').first);
      await tester.pump();
      await tester.pump();
      expect(find.text('No new failures'), findsOneWidget);
      expect(find.textContaining('This run is the baseline of main'), findsOne);
      expect(
        find.text(
          'Every test passed and nothing changed against the baseline.',
        ),
        findsOneWidget,
      );
      expect(find.text('Open job'), findsNothing);

      await tester.tap(find.textContaining('main · '));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('dev · ').last);
      await tester.pumpAndSettle();
      expect(find.text('1 new failure'), findsOneWidget);
    });

    testWidgets('says what it compared with and when it lists only some', (
      tester,
    ) async {
      final harness = TestsHarness();
      when(() => harness.tests.watchRun('job_x')).thenAnswer(
        (_) => Stream.value(
          Snapshot(
            _withDiff(
              const TestRunDiff(
                comparedTo: 'job_gone',
                newFailures: [],
                fixed: [],
                missing: [],
                stillFailing: 0,
              ),
              total: 1200,
            ),
          ),
        ),
      );
      await harness.pump(tester, jobId: 'job_x');
      expect(
        find.text('mataa_new_app · apps/captain · feature/cart'),
        findsOne,
      );
      expect(
        find.textContaining('Compared with the baseline run of job_gone'),
        findsOneWidget,
      );
      expect(find.text('Showing 0 of 1,200 failing tests.'), findsOneWidget);
    });

    testWidgets('says when there was no baseline', (tester) async {
      final harness = TestsHarness(baselines: const []);
      when(() => harness.tests.watchRun('job_x')).thenAnswer(
        (_) => Stream.value(
          Snapshot(
            _withDiff(
              const TestRunDiff(
                newFailures: [TestRef(suite: 's', name: 'n')],
                fixed: [],
                missing: [],
                stillFailing: 0,
              ),
            ),
          ),
        ),
      );
      await harness.pump(tester, jobId: 'job_x');
      expect(find.textContaining('No baseline yet'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('BASELINES'), findsNothing);
    });

    testWidgets('offers the runs that end while it watches', (tester) async {
      final harness = TestsHarness();
      when(() => harness.tests.completedRuns('prj_1')).thenAnswer(
        (_) => Stream.value(
          const TestRunCompleted(
            jobId: 'job_new',
            projectId: 'prj_1',
            branch: 'main',
            baseline: false,
            failures: 0,
            newFailures: 0,
          ),
        ),
      );
      await harness.pump(tester);
      await tester.tap(find.textContaining('dev · '));
      await tester.pumpAndSettle();
      expect(find.text('main · just ended'), findsOneWidget);
    });

    testWidgets('says why the baselines cannot be read', (tester) async {
      final harness = TestsHarness();
      when(() => harness.tests.watchBaselines('prj_1')).thenAnswer(
        (_) => Stream.error(const ApiException('Locked.', statusCode: 500)),
      );
      await harness.pump(tester);
      expect(find.text('Locked.'), findsOneWidget);
    });

    testWidgets('says when there is no run yet', (tester) async {
      await TestsHarness(baselines: const []).pump(tester, jobId: null);
      expect(find.text('No test runs yet'), findsOneWidget);
    });

    testWidgets('says when the project is gone', (tester) async {
      await TestsHarness().pump(tester, projectId: 'prj_9');
      expect(
        find.text('This project is no longer on the engine.'),
        findsOneWidget,
      );
    });
  });
}
