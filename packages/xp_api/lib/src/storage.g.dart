// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'storage.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RetentionSettings _$RetentionSettingsFromJson(Map<String, dynamic> json) =>
    $checkedCreate('RetentionSettings', json, ($checkedConvert) {
      final val = RetentionSettings(
        keepPerFlavor: $checkedConvert(
          'keepPerFlavor',
          (v) => (v as num?)?.toInt() ?? 5,
        ),
        logDays: $checkedConvert('logDays', (v) => (v as num?)?.toInt() ?? 90),
      );
      return val;
    });

Map<String, dynamic> _$RetentionSettingsToJson(RetentionSettings instance) =>
    <String, dynamic>{
      'keepPerFlavor': instance.keepPerFlavor,
      'logDays': instance.logDays,
    };

CategoryUsage _$CategoryUsageFromJson(Map<String, dynamic> json) =>
    CategoryUsage(
      category: $enumDecode(_$StorageCategoryEnumMap, json['category']),
      usedBytes: (json['usedBytes'] as num).toInt(),
      reclaimableBytes: (json['reclaimableBytes'] as num).toInt(),
      items: (json['items'] as num).toInt(),
    );

Map<String, dynamic> _$CategoryUsageToJson(CategoryUsage instance) =>
    <String, dynamic>{
      'category': _$StorageCategoryEnumMap[instance.category]!,
      'usedBytes': instance.usedBytes,
      'reclaimableBytes': instance.reclaimableBytes,
      'items': instance.items,
    };

const _$StorageCategoryEnumMap = {
  StorageCategory.artifacts: 'artifacts',
  StorageCategory.logs: 'logs',
  StorageCategory.worktrees: 'worktrees',
  StorageCategory.mirrors: 'mirrors',
  StorageCategory.flutter: 'flutter',
};

FlavorUsage _$FlavorUsageFromJson(Map<String, dynamic> json) => FlavorUsage(
  projectId: json['projectId'] as String,
  app: json['app'] as String,
  flavor: json['flavor'] as String,
  builds: (json['builds'] as num).toInt(),
  artifacts: (json['artifacts'] as num).toInt(),
  usedBytes: (json['usedBytes'] as num).toInt(),
  reclaimableBytes: (json['reclaimableBytes'] as num).toInt(),
);

Map<String, dynamic> _$FlavorUsageToJson(FlavorUsage instance) =>
    <String, dynamic>{
      'projectId': instance.projectId,
      'app': instance.app,
      'flavor': instance.flavor,
      'builds': instance.builds,
      'artifacts': instance.artifacts,
      'usedBytes': instance.usedBytes,
      'reclaimableBytes': instance.reclaimableBytes,
    };

StorageReport _$StorageReportFromJson(Map<String, dynamic> json) =>
    StorageReport(
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      categories: (json['categories'] as List<dynamic>)
          .map((e) => CategoryUsage.fromJson(e as Map<String, dynamic>))
          .toList(),
      flavors: (json['flavors'] as List<dynamic>)
          .map((e) => FlavorUsage.fromJson(e as Map<String, dynamic>))
          .toList(),
      retention: RetentionSettings.fromJson(
        json['retention'] as Map<String, dynamic>,
      ),
    );

Map<String, dynamic> _$StorageReportToJson(StorageReport instance) =>
    <String, dynamic>{
      'generatedAt': instance.generatedAt.toIso8601String(),
      'categories': instance.categories.map((e) => e.toJson()).toList(),
      'flavors': instance.flavors.map((e) => e.toJson()).toList(),
      'retention': instance.retention.toJson(),
    };

FreeSpaceRequest _$FreeSpaceRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('FreeSpaceRequest', json, ($checkedConvert) {
      final val = FreeSpaceRequest(
        dryRun: $checkedConvert('dryRun', (v) => v as bool? ?? true),
        categories: $checkedConvert(
          'categories',
          (v) => (v as List<dynamic>?)
              ?.map((e) => $enumDecode(_$StorageCategoryEnumMap, e))
              .toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$FreeSpaceRequestToJson(FreeSpaceRequest instance) =>
    <String, dynamic>{
      'dryRun': instance.dryRun,
      'categories': ?instance.categories
          ?.map((e) => _$StorageCategoryEnumMap[e]!)
          .toList(),
    };

FreedCategory _$FreedCategoryFromJson(Map<String, dynamic> json) =>
    FreedCategory(
      category: $enumDecode(_$StorageCategoryEnumMap, json['category']),
      bytes: (json['bytes'] as num).toInt(),
      items: (json['items'] as num).toInt(),
    );

Map<String, dynamic> _$FreedCategoryToJson(FreedCategory instance) =>
    <String, dynamic>{
      'category': _$StorageCategoryEnumMap[instance.category]!,
      'bytes': instance.bytes,
      'items': instance.items,
    };

FreeSpaceResult _$FreeSpaceResultFromJson(Map<String, dynamic> json) =>
    FreeSpaceResult(
      dryRun: json['dryRun'] as bool,
      categories: (json['categories'] as List<dynamic>)
          .map((e) => FreedCategory.fromJson(e as Map<String, dynamic>))
          .toList(),
      failures:
          (json['failures'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );

Map<String, dynamic> _$FreeSpaceResultToJson(FreeSpaceResult instance) =>
    <String, dynamic>{
      'dryRun': instance.dryRun,
      'categories': instance.categories.map((e) => e.toJson()).toList(),
      'failures': instance.failures,
    };
