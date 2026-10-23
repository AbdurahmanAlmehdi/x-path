import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// Where saving the store ids of a flavor is.
enum StoreIdsStatus { idle, saving, saved, failed }

class StoreIdsState extends Equatable {
  const new({this.status = StoreIdsStatus.idle, this.error});

  final StoreIdsStatus status;

  /// Why the last save failed.
  final String? error;

  @override
  List<Object?> get props => [status, error];
}

/// Saves the store ids of a flavor of [_projectId] (UX-03): its Firebase app
/// id per platform and its App Store Connect app id, which the built-in
/// workflows upload to when a dispatch gives none. An empty id removes it.
class StoreIdsCubit extends Cubit<StoreIdsState> {
  new({required this._projects, required this._projectId})
    : super(const StoreIdsState());

  final ProjectsRepository _projects;
  final String _projectId;

  Future<void> save({
    required String app,
    required String flavor,
    required String firebaseAndroid,
    required String firebaseIos,
    required String appleAppId,
  }) async {
    emit(const StoreIdsState(status: StoreIdsStatus.saving));
    try {
      await _projects.editProject(
        _projectId,
        ProfileEdits(
          apps: [
            AppEdit(
              path: app,
              flavors: [
                FlavorEdit(
                  name: flavor,
                  firebaseAppId: {
                    'android': firebaseAndroid.trim(),
                    'ios': firebaseIos.trim(),
                  },
                  appleAppId: appleAppId.trim(),
                ),
              ],
            ),
          ],
        ),
      );
      emit(const StoreIdsState(status: StoreIdsStatus.saved));
    } on Exception catch (error) {
      emit(
        StoreIdsState(
          status: StoreIdsStatus.failed,
          error: errorMessage(error),
        ),
      );
    }
  }
}
