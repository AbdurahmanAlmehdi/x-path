// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'storage.g.dart';

/// What the engine keeps on its disk that housekeeping can give back.
@JsonEnum(valueField: 'wire')
enum StorageCategory {
  /// The files of builds in the artifact store.
  artifacts('artifacts'),

  /// The logs of finished jobs.
  logs('logs'),

  /// The worktrees of finished jobs.
  worktrees('worktrees'),

  /// The mirrors of repositories that are no longer projects.
  mirrors('mirrors'),

  /// The Flutter SDKs in XPath's cache that no project pins.
  flutter('flutter');

  new(this.wire);

  /// The name on the wire.
  final String wire;
}

/// How long the engine keeps what it stores, and how much of it (D-22, D-24).
@JsonSerializable(checked: true)
class RetentionSettings extends Equatable {
  /// Creates the settings.
  const new({this.keepPerFlavor = 5, this.logDays = 90});

  /// Reads the settings from their JSON form.
  factory RetentionSettings.fromJson(Map<String, dynamic> json) =>
      _$RetentionSettingsFromJson(json);

  /// How many of the newest builds of each flavor keep their files. Pinned
  /// artifacts and the artifacts of releases that are not over come on top.
  /// At least 1; 5 unless the owner says otherwise.
  @JsonKey(defaultValue: 5)
  final int keepPerFlavor;

  /// How many days the logs and the records of finished jobs are kept
  /// (D-24: 90). At least 1.
  @JsonKey(defaultValue: 90)
  final int logDays;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$RetentionSettingsToJson(this);

  @override
  List<Object?> get props => [keepPerFlavor, logDays];
}

/// How much one [StorageCategory] holds and how much of it housekeeping would
/// give back.
@JsonSerializable()
class CategoryUsage extends Equatable {
  /// Creates the usage.
  const new({
    required this.category,
    required this.usedBytes,
    required this.reclaimableBytes,
    required this.items,
  });

  /// Reads the usage from its JSON form.
  factory CategoryUsage.fromJson(Map<String, dynamic> json) =>
      _$CategoryUsageFromJson(json);

  /// What it is about.
  final StorageCategory category;

  /// Everything the category holds, in bytes.
  final int usedBytes;

  /// What housekeeping would free, in bytes.
  final int reclaimableBytes;

  /// How many items that is: artifacts, job logs, worktrees, mirrors or SDK
  /// versions.
  final int items;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$CategoryUsageToJson(this);

  @override
  List<Object?> get props => [category, usedBytes, reclaimableBytes, items];
}

/// The artifacts of one flavor of an app.
@JsonSerializable()
class FlavorUsage extends Equatable {
  /// Creates the usage.
  const new({
    required this.projectId,
    required this.app,
    required this.flavor,
    required this.builds,
    required this.artifacts,
    required this.usedBytes,
    required this.reclaimableBytes,
  });

  /// Reads the usage from its JSON form.
  factory FlavorUsage.fromJson(Map<String, dynamic> json) =>
      _$FlavorUsageFromJson(json);

  /// The project.
  final String projectId;

  /// The path of the app.
  final String app;

  /// The flavor; empty for an app without flavors.
  final String flavor;

  /// How many jobs made the artifacts.
  final int builds;

  /// How many artifacts there are.
  final int artifacts;

  /// Their size in bytes.
  final int usedBytes;

  /// What housekeeping would free of it, in bytes.
  final int reclaimableBytes;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$FlavorUsageToJson(this);

  @override
  List<Object?> get props => [
    projectId,
    app,
    flavor,
    builds,
    artifacts,
    usedBytes,
    reclaimableBytes,
  ];
}

/// The body of `GET /storage`: what the engine keeps and what "free up
/// space" would give back.
@JsonSerializable(explicitToJson: true)
class StorageReport extends Equatable {
  /// Creates the report.
  const new({
    required this.generatedAt,
    required this.categories,
    required this.flavors,
    required this.retention,
  });

  /// Reads the report from its JSON form.
  factory StorageReport.fromJson(Map<String, dynamic> json) =>
      _$StorageReportFromJson(json);

  /// When the report was made, in UTC.
  final DateTime generatedAt;

  /// One entry per [StorageCategory], in the order of the enum.
  final List<CategoryUsage> categories;

  /// The artifacts by app and flavor.
  final List<FlavorUsage> flavors;

  /// The settings the report was made with.
  final RetentionSettings retention;

  /// Everything housekeeping looked at, in bytes.
  int get usedBytes => categories.fold(0, (sum, c) => sum + c.usedBytes);

  /// What it would free, in bytes.
  int get reclaimableBytes =>
      categories.fold(0, (sum, c) => sum + c.reclaimableBytes);

  /// The JSON form.
  Map<String, dynamic> toJson() => _$StorageReportToJson(this);

  @override
  List<Object?> get props => [generatedAt, categories, flavors, retention];
}

/// The body of `POST /storage/free`.
@JsonSerializable(checked: true)
class FreeSpaceRequest extends Equatable {
  /// Creates the request.
  const new({this.dryRun = true, this.categories});

  /// Reads the request from its JSON form.
  factory FreeSpaceRequest.fromJson(Map<String, dynamic> json) =>
      _$FreeSpaceRequestFromJson(json);

  /// Whether to only say what would be freed. A request without a body is a
  /// dry run; deleting needs `"dryRun": false`.
  final bool dryRun;

  /// Only these categories; all of them when absent.
  @JsonKey(includeIfNull: false)
  final List<StorageCategory>? categories;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$FreeSpaceRequestToJson(this);

  @override
  List<Object?> get props => [dryRun, categories];
}

/// What housekeeping freed, or would free, of one [StorageCategory].
@JsonSerializable()
class FreedCategory extends Equatable {
  /// Creates the entry.
  const new({required this.category, required this.bytes, required this.items});

  /// Reads the entry from its JSON form.
  factory FreedCategory.fromJson(Map<String, dynamic> json) =>
      _$FreedCategoryFromJson(json);

  /// What it is about.
  final StorageCategory category;

  /// Bytes freed.
  final int bytes;

  /// Items removed.
  final int items;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$FreedCategoryToJson(this);

  @override
  List<Object?> get props => [category, bytes, items];
}

/// The body of the answer to `POST /storage/free`.
@JsonSerializable(explicitToJson: true)
class FreeSpaceResult extends Equatable {
  /// Creates the result.
  const new({
    required this.dryRun,
    required this.categories,
    this.failures = const [],
  });

  /// Reads the result from its JSON form.
  factory FreeSpaceResult.fromJson(Map<String, dynamic> json) =>
      _$FreeSpaceResultFromJson(json);

  /// Whether nothing was deleted: the numbers are what would be freed.
  final bool dryRun;

  /// One entry per category asked for.
  final List<FreedCategory> categories;

  /// What could not be removed, one sentence each. The rest was removed.
  final List<String> failures;

  /// All the bytes.
  int get bytes => categories.fold(0, (sum, c) => sum + c.bytes);

  /// The JSON form.
  Map<String, dynamic> toJson() => _$FreeSpaceResultToJson(this);

  @override
  List<Object?> get props => [dryRun, categories, failures];
}
