import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_desktop/app/bloc/engine_connection_bloc.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/local_engine/bloc/local_engine_bloc.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// Ties the engine on this Mac to the connection: when it is the active
/// engine and turns unreachable (at launch or later), asks
/// [LocalEngineBloc] to start it on its own; when it answers again, ends
/// the episode; and once a start worked, has the connection check again
/// (or open a new session, when the app had to make a new token).
class LocalEngineListener extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  /// The name of an app token made for the engine on this Mac.
  static String tokenName(BuildContext context) => context.l10n
      .onboardingAppTokenName(context.read<AppServices>().deviceName);

  @override
  Widget build(BuildContext context) => MultiBlocListener(
    listeners: [
      BlocListener<EngineConnectionBloc, EngineConnectionState>(
        listenWhen: (previous, current) =>
            previous.status != current.status ||
            previous.active != current.active,
        listener: (context, state) {
          if (state.active?.isLocal != true) return;
          final local = context.read<LocalEngineBloc>();
          switch (state.status) {
            case EngineStatus.connected || EngineStatus.secretsLocked:
              local.add(const LocalEngineReachable());
            case EngineStatus.unreachable:
              local.add(
                LocalEngineStartRequested(
                  tokenName: tokenName(context),
                  automatic: true,
                ),
              );
            case EngineStatus.connecting ||
                EngineStatus.reconnecting ||
                EngineStatus.rejected:
              break;
          }
        },
      ),
      BlocListener<LocalEngineBloc, LocalEngineState>(
        listenWhen: (previous, current) =>
            previous.progress != current.progress &&
            current.progress == LocalEngineProgress.started,
        listener: (context, state) {
          final connection = context.read<EngineConnectionBloc>();
          if (connection.state.active?.isLocal != true) return;
          connection.add(
            state.tokenRenewed
                ? const EnginesChanged()
                : const EngineCheckRequested(),
          );
        },
      ),
    ],
    child: child,
  );
}
