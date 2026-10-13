import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/projects/project_exceptions.dart';

/// [profile] with the owner's [edits] on top.
///
/// Edits to an app or flavor that the profile does not have are ignored: a
/// rescan may no longer find what was once edited, and the edit applies again
/// if it comes back.
ProjectProfile applyEdits(ProjectProfile profile, ProfileEdits edits) {
  if (edits.apps.isEmpty) return profile;
  final byPath = {for (final app in edits.apps) app.path: app};
  return profile.copyWith(
    apps: [
      for (final app in profile.apps)
        if (byPath[app.path] case final edit?) _applyToApp(app, edit) else app,
    ],
  );
}

AppProfile _applyToApp(AppProfile app, AppEdit edit) {
  final byName = {for (final flavor in edit.flavors) flavor.name: flavor};
  return app.copyWith(
    storeCountry: edit.storeCountry,
    flavors: [
      for (final flavor in app.flavors)
        if (byName[flavor.name] case final change?)
          flavor.copyWith(
            entrypoint: change.entrypoint,
            iosBundleId: change.iosBundleId,
            androidAppId: change.androidAppId,
            shorebird: change.shorebird,
            prod: change.prod,
            versionFiles: change.versionFiles,
          )
        else
          flavor,
    ],
  );
}

final _storeCountry = RegExp(r'^[A-Za-z]{2}$');

/// Checks [edits] against what [profile] has and returns them with the store
/// countries in lower case.
///
/// Throws a [ProjectInvalidException] for an app or flavor that does not
/// exist, a blank branch, a store country that is not two letters, or a path
/// that is absolute or leaves the app.
ProfileEdits validateEdits(ProjectProfile profile, ProfileEdits edits) {
  final branch = edits.defaultBaseBranch;
  if (branch != null && branch.trim().isEmpty) {
    throw const ProjectInvalidException('defaultBaseBranch is blank.');
  }
  return ProfileEdits(
    defaultBaseBranch: branch?.trim(),
    apps: [
      for (final edit in edits.apps)
        _validateApp(
          edit,
          profile.apps.where((app) => app.path == edit.path).firstOrNull,
        ),
    ],
  );
}

AppEdit _validateApp(AppEdit edit, AppProfile? app) {
  if (app == null) {
    throw ProjectInvalidException('There is no app at ${edit.path}.');
  }
  final country = edit.storeCountry;
  if (country != null && !_storeCountry.hasMatch(country)) {
    throw ProjectInvalidException(
      'storeCountry must be two letters, not "$country".',
    );
  }
  for (final flavor in edit.flavors) {
    if (!app.flavors.any((existing) => existing.name == flavor.name)) {
      throw ProjectInvalidException(
        'App ${edit.path} has no flavor ${flavor.name}.',
      );
    }
    for (final path in [?flavor.entrypoint, ...?flavor.versionFiles]) {
      if (!_isInside(path)) {
        throw ProjectInvalidException(
          '"$path" must be a path inside the repository.',
        );
      }
    }
  }
  return AppEdit(
    path: edit.path,
    storeCountry: country?.toLowerCase(),
    flavors: edit.flavors,
  );
}

bool _isInside(String path) =>
    path.isNotEmpty && !path.startsWith('/') && !path.split('/').contains('..');
