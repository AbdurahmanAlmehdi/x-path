// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'project_profile.g.dart';

/// How the Flutter apps of a repository are laid out.
enum ProjectLayout {
  /// One app at the repository root.
  single,

  /// A workspace or Melos monorepo with apps below the root.
  melos,
}

/// How the iOS project pulls in plugins.
enum IosPackageManager {
  /// A `Podfile`.
  cocoapods,

  /// Swift Package Manager (`FlutterGeneratedPluginSwiftPackage`).
  spm,

  /// Both are set up.
  both,

  /// Neither; there is no iOS project or it has no plugins.
  none,
}

/// The repository's branches as far as a scan could tell.
@JsonSerializable(includeIfNull: false)
class BranchLayout extends Equatable {
  /// Creates a branch layout.
  const new({this.defaultBranch, this.releaseBranches = const []});

  /// Reads a branch layout from its JSON form.
  factory BranchLayout.fromJson(Map<String, dynamic> json) =>
      _$BranchLayoutFromJson(json);

  /// The branch GitHub shows first, when known.
  final String? defaultBranch;

  /// Existing branches that match `release/*`, sorted.
  final List<String> releaseBranches;

  /// Whether the repository uses `release/*` branches.
  bool get hasReleaseBranches => releaseBranches.isNotEmpty;

  /// A copy with [defaultBranch] set.
  BranchLayout withDefaultBranch(String? branch) =>
      BranchLayout(defaultBranch: branch, releaseBranches: releaseBranches);

  /// The JSON form.
  Map<String, dynamic> toJson() => _$BranchLayoutToJson(this);

  @override
  List<Object?> get props => [defaultBranch, releaseBranches];
}

/// A workflow definition that lives in the repository, for example a GitHub
/// Actions file or `codemagic.yaml`. XPath only lists them.
@JsonSerializable(includeIfNull: false)
class RepoWorkflow extends Equatable {
  /// Creates a workflow entry.
  const new({
    required this.path,
    required this.provider,
    this.names = const [],
  });

  /// Reads a workflow entry from its JSON form.
  factory RepoWorkflow.fromJson(Map<String, dynamic> json) =>
      _$RepoWorkflowFromJson(json);

  /// The file, relative to the repository root.
  final String path;

  /// `github_actions` or `codemagic`.
  final String provider;

  /// The workflow names the file declares.
  final List<String> names;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$RepoWorkflowToJson(this);

  @override
  List<Object?> get props => [path, provider, names];
}

/// The version keys of one `Info.plist`.
@JsonSerializable(includeIfNull: false)
class PlistVersion extends Equatable {
  /// Creates the version keys of the plist at [path].
  const new({
    required this.path,
    required this.literal,
    this.shortVersion,
    this.buildNumber,
  });

  /// Reads plist versions from their JSON form.
  factory PlistVersion.fromJson(Map<String, dynamic> json) =>
      _$PlistVersionFromJson(json);

  /// The plist, relative to the repository root.
  final String path;

  /// `CFBundleShortVersionString` as written, for example `5.5.0` or
  /// `$(FLUTTER_BUILD_NAME)`.
  final String? shortVersion;

  /// `CFBundleVersion` as written.
  final String? buildNumber;

  /// Whether either key holds a literal version rather than a build variable.
  /// Flutter's `--build-name` and `--build-number` do not reach such a plist.
  final bool literal;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$PlistVersionToJson(this);

  @override
  List<Object?> get props => [path, shortVersion, buildNumber, literal];
}

/// How an Android app finds its release keystore.
@JsonSerializable(includeIfNull: false)
class KeystoreProfile extends Equatable {
  /// Creates a keystore reference.
  const new({
    required this.propertiesPath,
    required this.propertiesPresent,
    this.storeFile,
  });

  /// Reads a keystore reference from its JSON form.
  factory KeystoreProfile.fromJson(Map<String, dynamic> json) =>
      _$KeystoreProfileFromJson(json);

  /// The `key.properties` file Gradle reads, relative to the repository root.
  final String propertiesPath;

  /// Whether that file exists in the scanned folder. It is normally ignored
  /// by git, so a scan of a fresh checkout reports `false`.
  final bool propertiesPresent;

  /// The `storeFile` entry of the properties file, when it could be read.
  /// Passwords are never read.
  final String? storeFile;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$KeystoreProfileToJson(this);

  @override
  List<Object?> get props => [propertiesPath, propertiesPresent, storeFile];
}

/// What `shorebird.yaml` declares.
@JsonSerializable(includeIfNull: false)
class ShorebirdProfile extends Equatable {
  /// Creates a Shorebird profile.
  const new({this.appId, this.flavorAppIds = const {}});

  /// Reads a Shorebird profile from its JSON form.
  factory ShorebirdProfile.fromJson(Map<String, dynamic> json) =>
      _$ShorebirdProfileFromJson(json);

  /// The `app_id`.
  final String? appId;

  /// The `flavors:` map, flavor name to app id.
  final Map<String, String> flavorAppIds;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ShorebirdProfileToJson(this);

  @override
  List<Object?> get props => [appId, flavorAppIds];
}

/// One build variant of an app: a Flutter flavor, or the plain build when the
/// app has none.
@JsonSerializable(includeIfNull: false)
class FlavorProfile extends Equatable {
  /// Creates a flavor.
  const new({
    required this.name,
    required this.entrypoint,
    this.implicit = false,
    this.iosBundleId,
    this.androidAppId,
    this.iosTeam,
    this.iosScheme,
    this.infoPlist,
    this.shorebird = false,
    this.shorebirdAppId,
    this.prod = false,
    this.versionFiles = const [],
    this.sources = const [],
  });

  /// Reads a flavor from its JSON form.
  factory FlavorProfile.fromJson(Map<String, dynamic> json) =>
      _$FlavorProfileFromJson(json);

  /// The flavor name, as passed to `flutter build --flavor`. `default` for an
  /// [implicit] flavor.
  final String name;

  /// Whether the app has no flavors and this entry stands for its only build.
  /// Build it without `--flavor`.
  final bool implicit;

  /// The Dart entrypoint, relative to the app, for example
  /// `lib/main_dev.dart`.
  final String entrypoint;

  /// `PRODUCT_BUNDLE_IDENTIFIER` that Xcode builds for the flavor.
  final String? iosBundleId;

  /// The Android application id of the flavor.
  final String? androidAppId;

  /// `DEVELOPMENT_TEAM` that Xcode builds the flavor with.
  final String? iosTeam;

  /// The shared Xcode scheme of the flavor.
  final String? iosScheme;

  /// The `Info.plist` the flavor's Xcode configuration reads, relative to the
  /// repository root.
  final String? infoPlist;

  /// Whether the flavor can receive Shorebird patches.
  final bool shorebird;

  /// Its Shorebird app id, when `shorebird.yaml` names one.
  final String? shorebirdAppId;

  /// Whether it is the production flavor. A guess from the name until the
  /// owner edits it.
  final bool prod;

  /// The files a version bump writes (D-11), relative to the repository root:
  /// the pubspec and every plist with a literal version.
  final List<String> versionFiles;

  /// Which files told the scan about the flavor: any of `gradle`,
  /// `flavorizr`, `xcscheme`, `entrypoint`.
  final List<String> sources;

  /// A copy with the editable fields replaced where given.
  FlavorProfile copyWith({
    String? entrypoint,
    String? iosBundleId,
    String? androidAppId,
    bool? shorebird,
    bool? prod,
    List<String>? versionFiles,
  }) => FlavorProfile(
    name: name,
    implicit: implicit,
    entrypoint: entrypoint ?? this.entrypoint,
    iosBundleId: iosBundleId ?? this.iosBundleId,
    androidAppId: androidAppId ?? this.androidAppId,
    iosTeam: iosTeam,
    iosScheme: iosScheme,
    infoPlist: infoPlist,
    shorebird: shorebird ?? this.shorebird,
    shorebirdAppId: shorebirdAppId,
    prod: prod ?? this.prod,
    versionFiles: versionFiles ?? this.versionFiles,
    sources: sources,
  );

  /// The JSON form.
  Map<String, dynamic> toJson() => _$FlavorProfileToJson(this);

  @override
  List<Object?> get props => [
    name,
    implicit,
    entrypoint,
    iosBundleId,
    androidAppId,
    iosTeam,
    iosScheme,
    infoPlist,
    shorebird,
    shorebirdAppId,
    prod,
    versionFiles,
    sources,
  ];
}

/// One Flutter app of a repository.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class AppProfile extends Equatable {
  /// Creates an app.
  const new({
    required this.name,
    required this.path,
    this.framework = 'flutter',
    this.version,
    this.storeCountry = 'us',
    this.flutterVersion,
    this.flutterVersionSource,
    this.hasIos = false,
    this.hasAndroid = false,
    this.iosPackageManager = IosPackageManager.none,
    this.iosAppExtensions = const [],
    this.flavors = const [],
    this.plists = const [],
    this.keystore,
    this.shorebird,
  });

  /// Reads an app from its JSON form.
  factory AppProfile.fromJson(Map<String, dynamic> json) =>
      _$AppProfileFromJson(json);

  /// The pubspec name.
  final String name;

  /// The app directory relative to the repository root; `.` for the root.
  final String path;

  /// `flutter`.
  final String framework;

  /// The pubspec `version`, for example `1.3.6+29`.
  final String? version;

  /// The two-letter App Store storefront used for status lookups (D4).
  /// Defaults to `us` until the owner edits it.
  final String storeCountry;

  /// The Flutter version pinned by `.fvmrc` (D-20), the app's own or the
  /// repository's.
  final String? flutterVersion;

  /// The `.fvmrc` the pin came from, relative to the repository root.
  final String? flutterVersionSource;

  /// Whether the app has an Xcode project.
  final bool hasIos;

  /// Whether the app has an Android project.
  final bool hasAndroid;

  /// How iOS plugins are integrated.
  final IosPackageManager iosPackageManager;

  /// The app extension targets of the Xcode project (widgets, share,
  /// notification service).
  final List<String> iosAppExtensions;

  /// The build variants.
  final List<FlavorProfile> flavors;

  /// The version keys of the `Info.plist` files the flavors use.
  final List<PlistVersion> plists;

  /// The Android release keystore reference, when Gradle reads
  /// `key.properties`.
  final KeystoreProfile? keystore;

  /// `shorebird.yaml`, when the app has one.
  final ShorebirdProfile? shorebird;

  /// A copy with the editable fields replaced where given.
  AppProfile copyWith({String? storeCountry, List<FlavorProfile>? flavors}) =>
      AppProfile(
        name: name,
        path: path,
        framework: framework,
        version: version,
        storeCountry: storeCountry ?? this.storeCountry,
        flutterVersion: flutterVersion,
        flutterVersionSource: flutterVersionSource,
        hasIos: hasIos,
        hasAndroid: hasAndroid,
        iosPackageManager: iosPackageManager,
        iosAppExtensions: iosAppExtensions,
        flavors: flavors ?? this.flavors,
        plists: plists,
        keystore: keystore,
        shorebird: shorebird,
      );

  /// The JSON form.
  Map<String, dynamic> toJson() => _$AppProfileToJson(this);

  @override
  List<Object?> get props => [
    name,
    path,
    framework,
    version,
    storeCountry,
    flutterVersion,
    flutterVersionSource,
    hasIos,
    hasAndroid,
    iosPackageManager,
    iosAppExtensions,
    flavors,
    plists,
    keystore,
    shorebird,
  ];
}

/// What a scan learned about a repository: its apps, flavors, identifiers
/// and branches.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ProjectProfile extends Equatable {
  /// Creates a profile.
  const new({
    this.layout = ProjectLayout.single,
    this.apps = const [],
    this.branches = const BranchLayout(),
    this.workflows = const [],
  });

  /// Reads a profile from its JSON form.
  factory ProjectProfile.fromJson(Map<String, dynamic> json) =>
      _$ProjectProfileFromJson(json);

  /// How the apps are laid out.
  final ProjectLayout layout;

  /// The Flutter apps found.
  final List<AppProfile> apps;

  /// The branches.
  final BranchLayout branches;

  /// Workflow files in the repository.
  final List<RepoWorkflow> workflows;

  /// A copy with [apps] and [branches] replaced where given.
  ProjectProfile copyWith({List<AppProfile>? apps, BranchLayout? branches}) =>
      ProjectProfile(
        layout: layout,
        apps: apps ?? this.apps,
        branches: branches ?? this.branches,
        workflows: workflows,
      );

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ProjectProfileToJson(this);

  @override
  List<Object?> get props => [layout, apps, branches, workflows];
}
