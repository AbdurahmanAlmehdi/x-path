import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/project_overview/view/project_overview_page.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/job_fixtures.dart';
import '../helpers/pump_app.dart';
import '../helpers/release_fixtures.dart';

/// `mataa` with the pubspec version of `Main.dc.html`.
final mataaWithVersion = Project(
  id: mataa.id,
  host: 'github.com',
  sourceKey: '${mataa.githubRepoId}',
  githubRepoId: mataa.githubRepoId,
  fullName: mataa.fullName,
  remote: mataa.remote,
  defaultBaseBranch: mataa.defaultBaseBranch,
  findings: mataa.findings,
  profile: ProjectProfile(
    apps: [
      for (final app in mataa.profile.apps)
        AppProfile(
          name: app.name,
          path: app.path,
          version: '5.5.0+3284',
          flutterVersion: app.flutterVersion,
          storeCountry: app.storeCountry,
          hasIos: app.hasIos,
          hasAndroid: app.hasAndroid,
          flavors: app.flavors,
        ),
    ],
  ),
);

/// The repositories behind an overview, with the releases the test gives.
class OverviewHarness {
  new({
    List<Release>? releases,
    List<Credential> credentials = const [verifiedKey],
    RunJobs? run,
  }) {
    when(() => releasesRepository.watchReleases(projectId: 'prj_1')).thenAnswer(
      (_) => Stream.value(Snapshot(releases ?? [buildingRelease, liveRelease])),
    );
    when(() => projects.watchCredentials('prj_1'))
        .thenAnswer((_) => Stream.value(Snapshot(credentials)));
    when(runners.watchRunners)
        .thenAnswer((_) => Stream.value(Snapshot([linuxRunner])));
    when(() => jobs.watchRunJobs('run_1'))
        .thenAnswer((_) => Stream.value(Snapshot(run ?? runningRun())));
    when(() => jobs.followLogs(any(), after: any(named: 'after')))
        .thenAnswer((_) {
          final controller = StreamController<LogFrame>();
          iosLog.forEach(controller.add);
          return controller.stream;
        });
    when(() => workflows.workflowOf(any()))
        .thenAnswer((_) async => prodWorkflow);
  }

  final releasesRepository = MockReleasesRepository();
  final projects = MockProjectsRepository();
  final jobs = MockJobsRepository();
  final workflows = MockWorkflowsRepository();
  final runners = MockRunnersRepository();

  Future<void> pump(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    ShellCubit? shell,
    ProjectsBloc? projectsBloc,
    EngineConnectionBloc? connection,
    Project? project,
  }) async {
    await tester.pumpApp(
      const ProjectOverviewPage('prj_1'),
      brightness: brightness,
      shell: shell,
      connection: connection,
      projectsRepository: projects,
      releasesRepository: releasesRepository,
      jobsRepository: jobs,
      workflowsRepository: workflows,
      runnersRepository: runners,
      projects:
          projectsBloc ??
          projectsIn(
            ProjectsState(
              loaded: true,
              projects: [project ?? mataaWithVersion],
            ),
          ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }
}
