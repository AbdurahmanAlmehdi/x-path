// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'profile_edits.g.dart';

/// The owner's corrections to one flavor of a scanned profile. A `null` field
/// keeps what the scan found.
@JsonSerializable(includeIfNull: false, checked: true)
class FlavorEdit extends Equatable {
  /// Creates an edit of the flavor called [name].
  const new({
    required this.name,
    this.prod,
    this.shorebird,
    this.entrypoint,
    this.iosBundleId,
    this.androidAppId,
    this.versionFiles,
    this.firebaseAppId,
    this.appleAppId,
  });

  /// Reads a flavor edit from its JSON form.
  factory FlavorEdit.fromJson(Map<String, dynamic> json) =>
      _$FlavorEditFromJson(json);

  /// The flavor to change.
  final String name;

  /// Whether it is the production flavor.
  final bool? prod;

  /// Whether it can receive Shorebird patches.
  final bool? shorebird;

  /// The Dart entrypoint.
  final String? entrypoint;

  /// The iOS bundle id.
  final String? iosBundleId;

  /// The Android application id.
  final String? androidAppId;

  /// The files a version bump writes.
  final List<String>? versionFiles;

  /// The Firebase app id by platform (`android`, `ios`). An empty id removes
  /// the one the flavor had.
  final Map<String, String>? firebaseAppId;

  /// The App Store Connect app id. Empty removes it.
  final String? appleAppId;

  /// This edit with [newer] on top: where [newer] sets a field it wins, and
  /// the Firebase app ids of the platforms it names.
  FlavorEdit merge(FlavorEdit newer) => FlavorEdit(
    name: name,
    prod: newer.prod ?? prod,
    shorebird: newer.shorebird ?? shorebird,
    entrypoint: newer.entrypoint ?? entrypoint,
    iosBundleId: newer.iosBundleId ?? iosBundleId,
    androidAppId: newer.androidAppId ?? androidAppId,
    versionFiles: newer.versionFiles ?? versionFiles,
    firebaseAppId: firebaseAppId == null && newer.firebaseAppId == null
        ? null
        : {...?firebaseAppId, ...?newer.firebaseAppId},
    appleAppId: newer.appleAppId ?? appleAppId,
  );

  /// The JSON form.
  Map<String, dynamic> toJson() => _$FlavorEditToJson(this);

  @override
  List<Object?> get props => [
    name,
    prod,
    shorebird,
    entrypoint,
    iosBundleId,
    androidAppId,
    versionFiles,
    firebaseAppId,
    appleAppId,
  ];
}

/// The owner's corrections to one app of a scanned profile.
@JsonSerializable(explicitToJson: true, includeIfNull: false, checked: true)
class AppEdit extends Equatable {
  /// Creates an edit of the app at [path].
  const new({
    required this.path,
    this.storeCountry,
    this.iosLinux,
    this.flavors = const [],
  });

  /// Reads an app edit from its JSON form.
  factory AppEdit.fromJson(Map<String, dynamic> json) =>
      _$AppEditFromJson(json);

  /// The app to change, as in `AppProfile.path`.
  final String path;

  /// The two-letter App Store storefront.
  final String? storeCountry;

  /// Whether Linux runners may build the iOS app; `false` sends every iOS
  /// job of the app to a Mac (ADR 0014).
  final bool? iosLinux;

  /// Flavor corrections.
  final List<FlavorEdit> flavors;

  /// This edit with [newer] on top.
  AppEdit merge(AppEdit newer) => AppEdit(
    path: path,
    storeCountry: newer.storeCountry ?? storeCountry,
    iosLinux: newer.iosLinux ?? iosLinux,
    flavors: ProfileEdits.mergeFlavors(flavors, newer.flavors),
  );

  /// The JSON form.
  Map<String, dynamic> toJson() => _$AppEditToJson(this);

  @override
  List<Object?> get props => [path, storeCountry, iosLinux, flavors];
}

/// The owner's corrections to a scanned profile: the body of
/// `PATCH /projects/{id}`.
///
/// Reading edits from JSON fails with a `CheckedFromJsonException` for a field
/// of the wrong type, so that a bad request body is told apart from a bug.
///
/// XPath keeps them apart from the scan result and applies them again after
/// every scan, so a rescan never undoes an edit.
@JsonSerializable(explicitToJson: true, includeIfNull: false, checked: true)
class ProfileEdits extends Equatable {
  /// Creates a set of edits.
  const new({this.defaultBaseBranch, this.apps = const []});

  /// Reads edits from their JSON form.
  factory ProfileEdits.fromJson(Map<String, dynamic> json) =>
      _$ProfileEditsFromJson(json);

  /// The branch releases are based on (M6), when it is not the repository's
  /// default branch.
  final String? defaultBaseBranch;

  /// App corrections.
  final List<AppEdit> apps;

  /// Whether the edits change nothing.
  bool get isEmpty => defaultBaseBranch == null && apps.isEmpty;

  /// These edits with [newer] on top: edits to the same app or flavor are
  /// merged field by field, and where both set a field [newer] wins.
  ProfileEdits merge(ProfileEdits newer) {
    final byPath = {for (final app in apps) app.path: app};
    for (final app in newer.apps) {
      final existing = byPath[app.path];
      byPath[app.path] = existing == null ? app : existing.merge(app);
    }
    return ProfileEdits(
      defaultBaseBranch: newer.defaultBaseBranch ?? defaultBaseBranch,
      apps: byPath.values.toList(),
    );
  }

  /// Merges two lists of flavor edits by flavor name.
  static List<FlavorEdit> mergeFlavors(
    List<FlavorEdit> older,
    List<FlavorEdit> newer,
  ) {
    final byName = {for (final flavor in older) flavor.name: flavor};
    for (final flavor in newer) {
      final existing = byName[flavor.name];
      byName[flavor.name] = existing == null ? flavor : existing.merge(flavor);
    }
    return byName.values.toList();
  }

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ProfileEditsToJson(this);

  @override
  List<Object?> get props => [defaultBaseBranch, apps];
}
