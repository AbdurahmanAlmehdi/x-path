import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_desktop/app/bloc/engine_connection_bloc.dart';
import 'package:xp_desktop/approvals/bloc/pending_approvals_bloc.dart';
import 'package:xp_desktop/approvals/widgets/needs_you_alerts_listener.dart';
import 'package:xp_desktop/engines/view/engines_page.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/local_engine/local_engine.dart';
import 'package:xp_desktop/onboarding/view/onboarding_page.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/runners/bloc/runners_bloc.dart';
import 'package:xp_desktop/shell/bloc/command_palette_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/view/app_shell.dart';
import 'package:xp_desktop/shell/widgets/engine_staleness.dart';
import 'package:xp_desktop/storage/bloc/storage_bloc.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/toast/cubit/toast_cubit.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// The app: the [services] it reaches outside Flutter, the
/// `EngineConnectionBloc` that owns the active engine, the
/// `LocalEngineBloc` that keeps the engine on this Mac running, and the
/// `ToastCubit` whose toasts outlive a change of engine.
class App extends StatelessWidget {
  const new({required this.services, super.key});

  final AppServices services;

  @override
  Widget build(BuildContext context) => RepositoryProvider.value(
    value: services,
    child: MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => EngineConnectionBloc(
            engines: services.engines,
            openSession: services.openSession,
          )..add(const EngineConnectionStarted()),
        ),
        BlocProvider(
          create: (_) => LocalEngineBloc(
            agent: services.agent,
            localEngine: services.localEngine,
            engines: services.engines,
          ),
        ),
        BlocProvider(create: (_) => ToastCubit()),
      ],
      child: const XpClock(child: AppView()),
    ),
  );
}

class AppView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'XPath',
    debugShowCheckedModeBanner: false,
    theme: appTheme(Brightness.light),
    darkTheme: appTheme(Brightness.dark),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => XpToastHost(child: child!),
    home: const LocalEngineListener(child: AppHome()),
  );
}

/// Onboarding until the app knows an engine, then the shell of the active
/// engine.
class AppHome extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<EngineConnectionBloc, EngineConnectionState>(
        buildWhen: (previous, current) =>
            previous.loaded != current.loaded ||
            previous.engines.isEmpty != current.engines.isEmpty ||
            previous.session != current.session ||
            previous.active != current.active,
        builder: (context, state) {
          if (!state.loaded) {
            return ColoredBox(color: context.xpColors.surfaceWindow);
          }
          if (state.engines.isEmpty) {
            return const OnboardingPage(firstRun: true);
          }
          final session = state.session;
          if (session == null) return const EngineMissingTokenPage();
          return EngineScope(session: session, child: const AppShell());
        },
      );
}

/// The repositories and the blocs of one engine session.
///
/// It is keyed on the session: when the active engine changes, Flutter
/// throws the whole subtree away and builds it again, so every bloc below
/// subscribes to the new engine's streams (the old ones were ended by
/// `EngineSession.close`).
class EngineScope extends StatelessWidget {
  const new({required this.session, required this.child, super.key});

  final EngineSession session;
  final Widget child;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: ObjectKey(session),
    child: MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => ProjectsRepository(session)),
        RepositoryProvider(create: (_) => CredentialsRepository(session)),
        RepositoryProvider(create: (_) => JobsRepository(session)),
        RepositoryProvider(create: (_) => ReleasesRepository(session)),
        RepositoryProvider(create: (_) => ApprovalsRepository(session)),
        RepositoryProvider(create: (_) => RunnersRepository(session)),
        RepositoryProvider(create: (_) => WorkflowsRepository(session)),
        RepositoryProvider(create: (_) => TestsRepository(session)),
        RepositoryProvider(create: (_) => StorageRepository(session)),
        RepositoryProvider(create: (_) => SettingsRepository(session)),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => ShellCubit()),
          BlocProvider(
            create: (context) => CommandPaletteBloc(
              projects: context.read<ProjectsRepository>(),
              releases: context.read<ReleasesRepository>(),
              jobs: context.read<JobsRepository>(),
              workflows: context.read<WorkflowsRepository>(),
              approvals: context.read<ApprovalsRepository>(),
            ),
          ),
          BlocProvider(
            create: (context) =>
                ProjectsBloc(projects: context.read<ProjectsRepository>())
                  ..add(const ProjectsSubscriptionRequested()),
          ),
          BlocProvider(
            create: (context) => PendingApprovalsBloc(
              approvals: context.read<ApprovalsRepository>(),
            )..add(const PendingApprovalsSubscriptionRequested()),
          ),
          BlocProvider(
            create: (context) =>
                RunnersBloc(runners: context.read<RunnersRepository>())
                  ..add(const RunnersSubscriptionRequested()),
          ),
          BlocProvider(
            create: (context) =>
                StorageBloc(storage: context.read<StorageRepository>())
                  ..add(const StorageSubscriptionRequested()),
          ),
        ],
        child: NeedsYouAlertsListener(child: EngineStaleness(child: child)),
      ),
    ),
  );
}

/// The active engine has no token in the Keychain (or it cannot be read).
class EngineMissingTokenPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final state = context.watch<EngineConnectionBloc>().state;
    final bloc = context.read<EngineConnectionBloc>();
    final active = state.active!;
    return Material(
      color: colors.surfaceWindow,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIconsRegular.key,
                size: context.xpSizes.iconXl,
                color: colors.textTertiary,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.engineNoTokenTitle(active.name),
                style: context.xpType.headline.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.engineNoTokenBody,
                textAlign: TextAlign.center,
                style: context.xpType.body.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  XpButton(
                    label: l10n.engineNoTokenRetry,
                    kind: XpButtonKind.primary,
                    onPressed: () => bloc.add(const EnginesChanged()),
                  ),
                  XpButton(
                    label: l10n.enginesRemove,
                    onPressed: () => removeEngine(context, active),
                  ),
                  for (final engine in state.engines)
                    if (engine.id != active.id)
                      XpButton(
                        label: '${l10n.enginesUse} ${engine.name}',
                        onPressed: () => bloc.add(EngineSelected(engine.id)),
                      ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
