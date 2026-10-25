import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/approvals/bloc/pending_approvals_bloc.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/releases/view/releases_page.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/approval_fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';
import '../helpers/release_fixtures.dart';
import '../project_overview/overview_harness.dart';

/// The repositories behind the releases of `mataa`, with the releases the
/// test gives.
class ReleasesHarness {
  new({
    List<Release>? releases,
    List<Credential> credentials = const [verifiedKey, playAccount],
    List<Approval>? approvals,
  }) {
    when(() => releasesRepository.watchReleases(projectId: 'prj_1')).thenAnswer(
      (_) => Stream.value(Snapshot(releases ?? [reviewRelease(), liveRelease])),
    );
    when(() => releasesRepository.notes(any()))
        .thenAnswer((_) async => reviewNotes);
    when(() => projects.watchCredentials('prj_1'))
        .thenAnswer((_) => Stream.value(Snapshot(credentials)));
    when(
      () => approvalsRepository.watchApprovals(projectId: 'prj_1'),
    ).thenAnswer((_) => Stream.value(Snapshot(approvals ?? [pendingApproval])));
  }

  final releasesRepository = MockReleasesRepository();
  final projects = MockProjectsRepository();
  final approvalsRepository = MockApprovalsRepository();

  Future<void> pump(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    ShellCubit? shell,
    EngineConnectionBloc? connection,
    String? releaseId,
    List<Approval> pending = const [],
    Project? project,
  }) async {
    await tester.pumpApp(
      ReleasesPage(projectId: 'prj_1', releaseId: releaseId),
      brightness: brightness,
      shell: shell,
      connection: connection,
      projectsRepository: projects,
      releasesRepository: releasesRepository,
      approvalsRepository: approvalsRepository,
      pendingApprovals: pendingIn(
        PendingApprovalsState(loaded: true, approvals: pending),
      ),
      projects: projectsIn(
        ProjectsState(loaded: true, projects: [project ?? mataaWithVersion]),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }
}
