import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class DashboardEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Opens the engine's web dashboard in the browser, signed in.
final class DashboardOpenRequested extends DashboardEvent {
  const new();
}

class DashboardState extends Equatable {
  const new({this.opening = false, this.error});

  /// Whether the dashboard is being opened.
  final bool opening;

  /// What the engine said when it could not be opened.
  final String? error;

  @override
  List<Object?> get props => [opening, error];
}

/// Settings ▸ Web dashboard (D9): asks the engine for a one-time sign-in
/// code for this app's own person and opens the dashboard's sign-in page
/// with it in the browser. The link, which holds the code, is never kept in
/// the state.
class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  new({required this._settings, required this._openUrl})
    : super(const DashboardState()) {
    on<DashboardOpenRequested>(_onOpenRequested, transformer: droppable());
  }

  final SettingsRepository _settings;
  final Future<void> Function(Uri url) _openUrl;

  Future<void> _onOpenRequested(
    DashboardOpenRequested event,
    Emitter<DashboardState> emit,
  ) async {
    emit(const DashboardState(opening: true));
    try {
      await _openUrl(await _settings.dashboardSignInUrl());
      emit(const DashboardState());
    } on Exception catch (error) {
      emit(DashboardState(error: errorMessage(error)));
    }
  }
}
