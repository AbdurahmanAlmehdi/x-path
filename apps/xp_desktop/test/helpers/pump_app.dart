import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/app/bloc/engine_notices_bloc.dart';
import 'package:xp_desktop/approvals/bloc/pending_approvals_bloc.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/local_engine/local_engine.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/runners/bloc/runners_bloc.dart';
import 'package:xp_desktop/shell/bloc/command_palette_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/engine_staleness.dart';
import 'package:xp_desktop/storage/bloc/storage_bloc.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/toast/cubit/toast_cubit.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

import 'fakes.dart';

/// The time the widget tests see: 14:08:55 on this Mac, six minutes into
/// the sample run.
final testNow = DateTime(2026, 10, 13, 14, 8, 55);

class MockEngineConnectionBloc
    extends MockBloc<EngineConnectionEvent, EngineConnectionState>
    implements EngineConnectionBloc;

class MockLocalEngineBloc extends MockBloc<LocalEngineEvent, LocalEngineState>
    implements LocalEngineBloc;

/// A local-engine bloc that stays in [state].
MockLocalEngineBloc localEngineIn(LocalEngineState state) {
  final bloc = MockLocalEngineBloc();
  whenListen(bloc, const Stream<LocalEngineState>.empty(), initialState: state);
  return bloc;
}

class MockProjectsBloc extends MockBloc<ProjectsEvent, ProjectsState>
    implements ProjectsBloc;

class MockShellCubit extends MockCubit<ShellDestination> implements ShellCubit;

class MockRunnersBloc extends MockBloc<RunnersEvent, RunnersState>
    implements RunnersBloc;

class MockStorageBloc extends MockBloc<StorageEvent, StorageState>
    implements StorageBloc;

class MockEngineNoticesBloc
    extends MockBloc<EngineNoticesEvent, EngineNoticesState>
    implements EngineNoticesBloc;

/// An engine-notices bloc that stays in [state].
MockEngineNoticesBloc noticesIn(EngineNoticesState state) {
  final bloc = MockEngineNoticesBloc();
  whenListen(
    bloc,
    const Stream<EngineNoticesState>.empty(),
    initialState: state,
  );
  return bloc;
}

/// A runners bloc that stays in [state].
MockRunnersBloc runnersIn(RunnersState state) {
  final bloc = MockRunnersBloc();
  whenListen(bloc, const Stream<RunnersState>.empty(), initialState: state);
  return bloc;
}

/// A storage bloc that stays in [state].
MockStorageBloc storageIn(StorageState state) {
  final bloc = MockStorageBloc();
  whenListen(bloc, const Stream<StorageState>.empty(), initialState: state);
  return bloc;
}

class MockPendingApprovalsBloc
    extends MockBloc<PendingApprovalsEvent, PendingApprovalsState>
    implements PendingApprovalsBloc;

/// A pending-approvals bloc that stays in [state].
MockPendingApprovalsBloc pendingIn(PendingApprovalsState state) {
  final bloc = MockPendingApprovalsBloc();
  whenListen(
    bloc,
    const Stream<PendingApprovalsState>.empty(),
    initialState: state,
  );
  return bloc;
}

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
    LocalEngineBloc? localEngine,
    ShellCubit? shell,
    ProjectsBloc? projects,
    ProjectsRepository? projectsRepository,
    CredentialsRepository? credentialsRepository,
    JobsRepository? jobsRepository,
    ReleasesRepository? releasesRepository,
    RunnersRepository? runnersRepository,
    WorkflowsRepository? workflowsRepository,
    ApprovalsRepository? approvalsRepository,
    TestsRepository? testsRepository,
    StorageRepository? storageRepository,
    SettingsRepository? settingsRepository,
    PendingApprovalsBloc? pendingApprovals,
    RunnersBloc? runners,
    StorageBloc? storage,
    ToastCubit? toasts,
    EngineNoticesBloc? notices,
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
          RepositoryProvider<CredentialsRepository>.value(
            value: credentialsRepository ?? quietCredentials(),
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
            value: workflowsRepository ?? quietWorkflows(),
          ),
          RepositoryProvider<ApprovalsRepository>.value(
            value: approvalsRepository ?? quietApprovals(),
          ),
          RepositoryProvider<TestsRepository>.value(
            value: testsRepository ?? quietTests(),
          ),
          RepositoryProvider<StorageRepository>.value(
            value: storageRepository ?? quietStorage(),
          ),
          RepositoryProvider<SettingsRepository>.value(
            value: settingsRepository ?? quietSettings(),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<EngineConnectionBloc>.value(
              value: connection ?? connectionIn(connectedTo()),
            ),
            BlocProvider<LocalEngineBloc>.value(
              value: localEngine ?? localEngineIn(const LocalEngineState()),
            ),
            BlocProvider<ShellCubit>.value(value: shell ?? ShellCubit()),
            BlocProvider<ProjectsBloc>.value(
              value: projects ?? projectsIn(const ProjectsState(loaded: true)),
            ),
            BlocProvider<PendingApprovalsBloc>.value(
              value:
                  pendingApprovals ??
                  pendingIn(const PendingApprovalsState(loaded: true)),
            ),
            BlocProvider<RunnersBloc>.value(
              value: runners ?? runnersIn(const RunnersState(loaded: true)),
            ),
            BlocProvider<StorageBloc>.value(
              value: storage ?? storageIn(const StorageState()),
            ),
            BlocProvider<ToastCubit>(create: (_) => toasts ?? ToastCubit()),
            BlocProvider<DensityCubit>(
              create: (_) => DensityCubit(AppPreferences()),
            ),
            BlocProvider<EngineNoticesBloc>.value(
              value: notices ?? noticesIn(const EngineNoticesState()),
            ),
            BlocProvider<CommandPaletteBloc>(
              create: (context) => CommandPaletteBloc(
                projects: context.read<ProjectsRepository>(),
                releases: context.read<ReleasesRepository>(),
                jobs: context.read<JobsRepository>(),
                workflows: context.read<WorkflowsRepository>(),
                approvals: context.read<ApprovalsRepository>(),
              ),
            ),
          ],
          child: themed(
            Material(
              child: EngineStaleness(child: XpToastHost(child: widget)),
            ),
            brightness: brightness,
          ),
        ),
      ),
    );
  }
}
