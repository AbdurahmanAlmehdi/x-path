import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/job/view/job_page.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/job_fixtures.dart';
import '../helpers/pump_app.dart';

/// The repositories behind a job view, with the run and log the test gives.
class JobHarness {
  new({RunJobs? run, List<LogFrame>? log}) {
    when(() => jobs.watchRunJobs('run_1')).thenAnswer((_) => runs.stream);
    when(() => jobs.followLogs(any(), after: any(named: 'after')))
        .thenAnswer((invocation) {
          final controller = StreamController<LogFrame>();
          logs.add(controller);
          if (invocation.positionalArguments.first == 'job_ios') {
            (log ?? iosLog).forEach(controller.add);
          }
          return controller.stream;
        });
    when(() => jobs.listArtifacts(any())).thenAnswer((_) async => iosArtifacts);
    when(() => workflows.workflowOf(any()))
        .thenAnswer((_) async => prodWorkflow);
    when(() => workflows.getWorkflow(any(), any()))
        .thenAnswer((_) async => prodWorkflow);
    when(runners.watchRunners)
        .thenAnswer((_) => Stream.value(Snapshot([linuxRunner])));
    runs.add(Snapshot(run ?? runningRun()));
  }

  final jobs = MockJobsRepository();
  final workflows = MockWorkflowsRepository();
  final runners = MockRunnersRepository();
  final runs = StreamController<Snapshot<RunJobs>>();
  final logs = <StreamController<LogFrame>>[];

  /// Pumps the job view of `run_1` and lets the run, workflow and log
  /// arrive.
  Future<void> pump(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    EngineConnectionBloc? connection,
    ShellCubit? shell,
    String? jobId,
    AppServices? services,
  }) async {
    await tester.pumpApp(
      JobPage(runId: 'run_1', jobId: jobId),
      services: services,
      brightness: brightness,
      connection: connection,
      shell: shell,
      jobsRepository: jobs,
      workflowsRepository: workflows,
      runnersRepository: runners,
      projects: projectsIn(
        const ProjectsState(loaded: true, projects: [mataa]),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }
}

void registerJobFallbacks() => registerFallbackValue(runningRun().run);
