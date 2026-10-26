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
    iosLinux: edit.iosLinux,
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
            firebaseAppId: change.firebaseAppId == null
                ? null
                : () => _firebaseIds(flavor.firebaseAppId, change),
            appleAppId: switch (change.appleAppId) {
              null => null,
              final id => () => id.isEmpty ? null : id,
            },
          )
        else
          flavor,
    ],
  );
}

/// The Firebase app ids of a flavor with [change] on top: an empty id
/// removes the platform's; `null` when none is left.
Map<String, String>? _firebaseIds(
  Map<String, String>? scanned,
  FlavorEdit change,
) {
  final ids = {...?scanned, ...?change.firebaseAppId}
    ..removeWhere((_, id) => id.isEmpty);
  return ids.isEmpty ? null : ids;
}

final _storeCountry = RegExp(r'^[A-Za-z]{2}$');

/// A Firebase app id of [platform]: `1:<project number>:<platform>:<hex>`.
bool _isFirebaseAppId(String platform, String id) =>
    RegExp('^[0-9]+:[0-9]+:$platform:[0-9a-f]+\$').hasMatch(id);

final _appleAppId = RegExp(r'^[0-9]+$');

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
    for (final MapEntry(key: platform, value: id)
        in (flavor.firebaseAppId ?? const <String, String>{}).entries) {
      if (platform != 'android' && platform != 'ios') {
        throw ProjectInvalidException(
          'firebaseAppId is by platform, android or ios, not "$platform".',
        );
      }
      if (id.isNotEmpty && !_isFirebaseAppId(platform, id)) {
        throw ProjectInvalidException(
          '"$id" is not a Firebase app id of $platform, which reads '
          '1:<project number>:$platform:<hex>.',
        );
      }
    }
    final apple = flavor.appleAppId;
    if (apple != null && apple.isNotEmpty && !_appleAppId.hasMatch(apple)) {
      throw ProjectInvalidException(
        'appleAppId is the number App Store Connect shows, not "$apple".',
      );
    }
  }
  return AppEdit(
    path: edit.path,
    storeCountry: country?.toLowerCase(),
    iosLinux: edit.iosLinux,
    flavors: edit.flavors,
  );
}

bool _isInside(String path) =>
    path.isNotEmpty && !path.startsWith('/') && !path.split('/').contains('..');
