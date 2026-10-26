import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_desktop/app/app_preferences.dart';
import 'package:xp_desktop/app/bloc/engine_notices_bloc.dart';
import 'package:xp_macos_services/xp_macos_services.dart';

class NoticeSettingsState extends Equatable {
  const new({required this.keepRunning, this.muted = const {}});

  /// Whether closing the window keeps XPath in the menu bar (UX-07).
  final bool keepRunning;

  /// The notices turned off.
  final Set<NoticeKind> muted;

  /// Whether notices of [kind] are shown.
  bool shows(NoticeKind kind) => !muted.contains(kind);

  @override
  List<Object?> get props => [keepRunning, muted];
}

/// Settings ▸ Notifications (U6b): whether XPath keeps running in the menu
/// bar once its window is closed, and which notices it shows.
class NoticeSettingsCubit extends Cubit<NoticeSettingsState> {
  new({required this._preferences, required this._app})
    : super(
        NoticeSettingsState(
          keepRunning: _preferences.keepRunning,
          muted: {
            for (final kind in NoticeKind.values)
              if (_preferences.mutedNotices.contains(kind.name)) kind,
          },
        ),
      );

  final AppPreferences _preferences;
  final RunningApp _app;

  Future<void> setKeepRunning({required bool keep}) async {
    emit(NoticeSettingsState(keepRunning: keep, muted: state.muted));
    await _preferences.setKeepRunning(keep: keep);
    await _app.setKeepRunning(keep: keep);
  }

  Future<void> show(NoticeKind kind, {required bool shown}) async {
    final muted = {...state.muted};
    shown ? muted.remove(kind) : muted.add(kind);
    emit(NoticeSettingsState(keepRunning: state.keepRunning, muted: muted));
    await _preferences.setMutedNotices({for (final kind in muted) kind.name});
  }
}
