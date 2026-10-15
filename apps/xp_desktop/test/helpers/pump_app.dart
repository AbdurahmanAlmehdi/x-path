import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

import 'fakes.dart';

/// The time the widget tests see: 14:08:55 on this Mac, six minutes into
/// the sample run.
final testNow = DateTime(2026, 10, 13, 14, 8, 55);

class MockEngineConnectionBloc
    extends MockBloc<EngineConnectionEvent, EngineConnectionState>
    implements EngineConnectionBloc;

class MockProjectsBloc extends MockBloc<ProjectsEvent, ProjectsState>
    implements ProjectsBloc;

class MockShellCubit extends MockCubit<ShellDestination> implements ShellCubit;

/// A connection bloc that stays in [state].
MockEngineConnectionBloc connectionIn(EngineConnectionState state) {
  final bloc = MockEngineConnectionBloc();
  whenListen(
    bloc,
    const Stream<EngineConnectionState>.empty(),
    initialState: state,
  );
  return bloc;
}

/// A connection to the local engine with [status].
EngineConnectionState connectedTo({
  EngineStatus status = EngineStatus.connected,
  EngineProfile? active,
  List<EngineProfile>? engines,
}) => EngineConnectionState(
  loaded: true,
  engines: engines ?? [localEngine, macMini],
  active: active ?? localEngine,
  status: status,
);

/// A projects bloc that stays in [state].
MockProjectsBloc projectsIn(ProjectsState state) {
  final bloc = MockProjectsBloc();
  whenListen(bloc, const Stream<ProjectsState>.empty(), initialState: state);
  return bloc;
}

/// Turns animations off, as macOS Reduce Motion does, so running arcs stand
/// still and `pumpAndSettle` settles; and sizes the window like the
/// design's reference (1440 × 900).
void desktopWindow(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  tester.view
    ..physicalSize = const Size(1440, 900)
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    tester.view.reset();
  });
}

/// The app's theme and localizations around [home].
Widget themed(Widget home, {Brightness brightness = Brightness.light}) =>
    XpClock(
      clock: () => testNow,
      ticking: false,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme(brightness),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

extension PumpApp on WidgetTester {
  /// Pumps [widget] inside the app's theme, localizations and providers,
  /// with fakes for whatever is not given.
  Future<void> pumpApp(
    Widget widget, {
    AppServices? services,
    EngineConnectionBloc? connection,
    ShellCubit? shell,
    ProjectsBloc? projects,
    ProjectsRepository? projectsRepository,
    JobsRepository? jobsRepository,
    ReleasesRepository? releasesRepository,
    RunnersRepository? runnersRepository,
    WorkflowsRepository? workflowsRepository,
    Brightness brightness = Brightness.light,
  }) async {
    desktopWindow(this);
    await pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AppServices>.value(
            value: services ?? testServices(),
          ),
          RepositoryProvider<ProjectsRepository>.value(
            value: projectsRepository ?? quietProjects(),
          ),
          RepositoryProvider<JobsRepository>.value(
            value: jobsRepository ?? quietJobs(),
          ),
          RepositoryProvider<ReleasesRepository>.value(
            value: releasesRepository ?? quietReleases(),
          ),
          RepositoryProvider<RunnersRepository>.value(
            value: runnersRepository ?? quietRunners(),
          ),
          RepositoryProvider<WorkflowsRepository>.value(
            value: workflowsRepository ?? MockWorkflowsRepository(),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<EngineConnectionBloc>.value(
              value: connection ?? connectionIn(connectedTo()),
            ),
            BlocProvider<ShellCubit>.value(value: shell ?? ShellCubit()),
            BlocProvider<ProjectsBloc>.value(
              value: projects ?? projectsIn(const ProjectsState(loaded: true)),
            ),
          ],
          child: themed(Material(child: widget), brightness: brightness),
        ),
      ),
    );
  }
}
