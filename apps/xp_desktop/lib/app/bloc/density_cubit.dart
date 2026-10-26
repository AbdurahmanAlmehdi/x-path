import 'package:bloc/bloc.dart';
import 'package:xp_desktop/app/app_preferences.dart';

/// Whether rows are compact (View ▸ Compact rows, ⌃⌘=, U6c): the app's
/// theme follows it, and the choice outlives the launch.
class DensityCubit extends Cubit<bool> {
  new(this._preferences) : super(_preferences.compactRows);

  final AppPreferences _preferences;

  /// Switches between compact and standard rows.
  Future<void> toggle() async {
    emit(!state);
    await _preferences.setCompactRows(compact: state);
  }
}
