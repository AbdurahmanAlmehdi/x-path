// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_edits.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FlavorEdit _$FlavorEditFromJson(Map<String, dynamic> json) =>
    $checkedCreate('FlavorEdit', json, ($checkedConvert) {
      final val = FlavorEdit(
        name: $checkedConvert('name', (v) => v as String),
        prod: $checkedConvert('prod', (v) => v as bool?),
        shorebird: $checkedConvert('shorebird', (v) => v as bool?),
        entrypoint: $checkedConvert('entrypoint', (v) => v as String?),
        iosBundleId: $checkedConvert('iosBundleId', (v) => v as String?),
        androidAppId: $checkedConvert('androidAppId', (v) => v as String?),
        versionFiles: $checkedConvert(
          'versionFiles',
          (v) => (v as List<dynamic>?)?.map((e) => e as String).toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$FlavorEditToJson(FlavorEdit instance) =>
    <String, dynamic>{
      'name': instance.name,
      'prod': ?instance.prod,
      'shorebird': ?instance.shorebird,
      'entrypoint': ?instance.entrypoint,
      'iosBundleId': ?instance.iosBundleId,
      'androidAppId': ?instance.androidAppId,
      'versionFiles': ?instance.versionFiles,
    };

AppEdit _$AppEditFromJson(Map<String, dynamic> json) =>
    $checkedCreate('AppEdit', json, ($checkedConvert) {
      final val = AppEdit(
        path: $checkedConvert('path', (v) => v as String),
        storeCountry: $checkedConvert('storeCountry', (v) => v as String?),
        flavors: $checkedConvert(
          'flavors',
          (v) =>
              (v as List<dynamic>?)
                  ?.map((e) => FlavorEdit.fromJson(e as Map<String, dynamic>))
                  .toList() ??
              const [],
        ),
      );
      return val;
    });

Map<String, dynamic> _$AppEditToJson(AppEdit instance) => <String, dynamic>{
  'path': instance.path,
  'storeCountry': ?instance.storeCountry,
  'flavors': instance.flavors.map((e) => e.toJson()).toList(),
};

ProfileEdits _$ProfileEditsFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ProfileEdits', json, ($checkedConvert) {
      final val = ProfileEdits(
        defaultBaseBranch: $checkedConvert(
          'defaultBaseBranch',
          (v) => v as String?,
        ),
        apps: $checkedConvert(
          'apps',
          (v) =>
              (v as List<dynamic>?)
                  ?.map((e) => AppEdit.fromJson(e as Map<String, dynamic>))
                  .toList() ??
              const [],
        ),
      );
      return val;
    });

Map<String, dynamic> _$ProfileEditsToJson(ProfileEdits instance) =>
    <String, dynamic>{
      'defaultBaseBranch': ?instance.defaultBaseBranch,
      'apps': instance.apps.map((e) => e.toJson()).toList(),
    };
