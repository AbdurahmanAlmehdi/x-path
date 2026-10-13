// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project_profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BranchLayout _$BranchLayoutFromJson(Map<String, dynamic> json) => BranchLayout(
  defaultBranch: json['defaultBranch'] as String?,
  releaseBranches:
      (json['releaseBranches'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
);

Map<String, dynamic> _$BranchLayoutToJson(BranchLayout instance) =>
    <String, dynamic>{
      'defaultBranch': ?instance.defaultBranch,
      'releaseBranches': instance.releaseBranches,
    };

RepoWorkflow _$RepoWorkflowFromJson(Map<String, dynamic> json) => RepoWorkflow(
  path: json['path'] as String,
  provider: json['provider'] as String,
  names:
      (json['names'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
);

Map<String, dynamic> _$RepoWorkflowToJson(RepoWorkflow instance) =>
    <String, dynamic>{
      'path': instance.path,
      'provider': instance.provider,
      'names': instance.names,
    };

PlistVersion _$PlistVersionFromJson(Map<String, dynamic> json) => PlistVersion(
  path: json['path'] as String,
  literal: json['literal'] as bool,
  shortVersion: json['shortVersion'] as String?,
  buildNumber: json['buildNumber'] as String?,
);

Map<String, dynamic> _$PlistVersionToJson(PlistVersion instance) =>
    <String, dynamic>{
      'path': instance.path,
      'shortVersion': ?instance.shortVersion,
      'buildNumber': ?instance.buildNumber,
      'literal': instance.literal,
    };

KeystoreProfile _$KeystoreProfileFromJson(Map<String, dynamic> json) =>
    KeystoreProfile(
      propertiesPath: json['propertiesPath'] as String,
      propertiesPresent: json['propertiesPresent'] as bool,
      storeFile: json['storeFile'] as String?,
    );

Map<String, dynamic> _$KeystoreProfileToJson(KeystoreProfile instance) =>
    <String, dynamic>{
      'propertiesPath': instance.propertiesPath,
      'propertiesPresent': instance.propertiesPresent,
      'storeFile': ?instance.storeFile,
    };

ShorebirdProfile _$ShorebirdProfileFromJson(Map<String, dynamic> json) =>
    ShorebirdProfile(
      appId: json['appId'] as String?,
      flavorAppIds:
          (json['flavorAppIds'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, e as String),
          ) ??
          const {},
    );

Map<String, dynamic> _$ShorebirdProfileToJson(ShorebirdProfile instance) =>
    <String, dynamic>{
      'appId': ?instance.appId,
      'flavorAppIds': instance.flavorAppIds,
    };

FlavorProfile _$FlavorProfileFromJson(Map<String, dynamic> json) =>
    FlavorProfile(
      name: json['name'] as String,
      entrypoint: json['entrypoint'] as String,
      implicit: json['implicit'] as bool? ?? false,
      iosBundleId: json['iosBundleId'] as String?,
      androidAppId: json['androidAppId'] as String?,
      iosTeam: json['iosTeam'] as String?,
      iosScheme: json['iosScheme'] as String?,
      infoPlist: json['infoPlist'] as String?,
      shorebird: json['shorebird'] as bool? ?? false,
      shorebirdAppId: json['shorebirdAppId'] as String?,
      prod: json['prod'] as bool? ?? false,
      versionFiles:
          (json['versionFiles'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      sources:
          (json['sources'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );

Map<String, dynamic> _$FlavorProfileToJson(FlavorProfile instance) =>
    <String, dynamic>{
      'name': instance.name,
      'implicit': instance.implicit,
      'entrypoint': instance.entrypoint,
      'iosBundleId': ?instance.iosBundleId,
      'androidAppId': ?instance.androidAppId,
      'iosTeam': ?instance.iosTeam,
      'iosScheme': ?instance.iosScheme,
      'infoPlist': ?instance.infoPlist,
      'shorebird': instance.shorebird,
      'shorebirdAppId': ?instance.shorebirdAppId,
      'prod': instance.prod,
      'versionFiles': instance.versionFiles,
      'sources': instance.sources,
    };

AppProfile _$AppProfileFromJson(Map<String, dynamic> json) => AppProfile(
  name: json['name'] as String,
  path: json['path'] as String,
  framework: json['framework'] as String? ?? 'flutter',
  version: json['version'] as String?,
  storeCountry: json['storeCountry'] as String? ?? 'us',
  flutterVersion: json['flutterVersion'] as String?,
  flutterVersionSource: json['flutterVersionSource'] as String?,
  hasIos: json['hasIos'] as bool? ?? false,
  hasAndroid: json['hasAndroid'] as bool? ?? false,
  iosPackageManager:
      $enumDecodeNullable(
        _$IosPackageManagerEnumMap,
        json['iosPackageManager'],
      ) ??
      IosPackageManager.none,
  flavors:
      (json['flavors'] as List<dynamic>?)
          ?.map((e) => FlavorProfile.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  plists:
      (json['plists'] as List<dynamic>?)
          ?.map((e) => PlistVersion.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  keystore: json['keystore'] == null
      ? null
      : KeystoreProfile.fromJson(json['keystore'] as Map<String, dynamic>),
  shorebird: json['shorebird'] == null
      ? null
      : ShorebirdProfile.fromJson(json['shorebird'] as Map<String, dynamic>),
);

Map<String, dynamic> _$AppProfileToJson(
  AppProfile instance,
) => <String, dynamic>{
  'name': instance.name,
  'path': instance.path,
  'framework': instance.framework,
  'version': ?instance.version,
  'storeCountry': instance.storeCountry,
  'flutterVersion': ?instance.flutterVersion,
  'flutterVersionSource': ?instance.flutterVersionSource,
  'hasIos': instance.hasIos,
  'hasAndroid': instance.hasAndroid,
  'iosPackageManager': _$IosPackageManagerEnumMap[instance.iosPackageManager]!,
  'flavors': instance.flavors.map((e) => e.toJson()).toList(),
  'plists': instance.plists.map((e) => e.toJson()).toList(),
  'keystore': ?instance.keystore?.toJson(),
  'shorebird': ?instance.shorebird?.toJson(),
};

const _$IosPackageManagerEnumMap = {
  IosPackageManager.cocoapods: 'cocoapods',
  IosPackageManager.spm: 'spm',
  IosPackageManager.both: 'both',
  IosPackageManager.none: 'none',
};

ProjectProfile _$ProjectProfileFromJson(Map<String, dynamic> json) =>
    ProjectProfile(
      layout:
          $enumDecodeNullable(_$ProjectLayoutEnumMap, json['layout']) ??
          ProjectLayout.single,
      apps:
          (json['apps'] as List<dynamic>?)
              ?.map((e) => AppProfile.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      branches: json['branches'] == null
          ? const BranchLayout()
          : BranchLayout.fromJson(json['branches'] as Map<String, dynamic>),
      workflows:
          (json['workflows'] as List<dynamic>?)
              ?.map((e) => RepoWorkflow.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$ProjectProfileToJson(ProjectProfile instance) =>
    <String, dynamic>{
      'layout': _$ProjectLayoutEnumMap[instance.layout]!,
      'apps': instance.apps.map((e) => e.toJson()).toList(),
      'branches': instance.branches.toJson(),
      'workflows': instance.workflows.map((e) => e.toJson()).toList(),
    };

const _$ProjectLayoutEnumMap = {
  ProjectLayout.single: 'single',
  ProjectLayout.melos: 'melos',
};
