// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'dispatch_plan.g.dart';

/// What a dispatch would start, as the engine plans it without starting it
/// (`POST .../dispatch?dryRun=true`): the jobs of each stage and
/// where each would run, the jobs it leaves out and why, the gates, and the
/// version and build number it would allocate. Nothing is allocated.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class DispatchPlan extends Equatable {
  /// Creates a plan.
  const new({
    required this.flavors,
    required this.platforms,
    this.stages = const [],
    this.skipped = const [],
    this.currentVersion,
    this.version,
    this.build,
    this.releaseVersion,
  });

  /// Reads a plan from its JSON form.
  factory DispatchPlan.fromJson(Map<String, dynamic> json) =>
      _$DispatchPlanFromJson(json);

  /// The flavors the run is for.
  final List<String> flavors;

  /// The platforms the run is for.
  final List<String> platforms;

  /// The stages that would make at least one job, in order.
  final List<PlannedStage> stages;

  /// The jobs the run would leave out, and the ones it cannot plan.
  final List<SkippedJob> skipped;

  /// The version of the pubspec at the commit, `x.y.z+build`, when the
  /// workflow reads it.
  final String? currentVersion;

  /// The version the run would release, `x.y.z`.
  final String? version;

  /// The build number the run would take: the next one, not yet taken.
  final int? build;

  /// The release a patch would apply to, `x.y.z+build`.
  final String? releaseVersion;

  /// How many jobs the dispatch would start.
  int get jobCount =>
      stages.fold(0, (count, stage) => count + stage.jobs.length);

  /// Every gated action the run would stop at for an approval.
  List<String> get gates =>
      {for (final stage in stages) ...stage.gates}.toList();

  /// Whether the engine would refuse the dispatch: a job it cannot plan.
  bool get blocked => skipped.any((job) => job.blocks);

  /// The JSON form.
  Map<String, dynamic> toJson() => _$DispatchPlanToJson(this);

  @override
  List<Object?> get props => [
    flavors,
    platforms,
    stages,
    skipped,
    currentVersion,
    version,
    build,
    releaseVersion,
  ];
}

/// One stage of a [DispatchPlan].
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PlannedStage extends Equatable {
  /// Creates a stage.
  const new({required this.name, this.jobs = const [], this.gates = const []});

  /// Reads a stage from its JSON form.
  factory PlannedStage.fromJson(Map<String, dynamic> json) =>
      _$PlannedStageFromJson(json);

  /// The stage's name in the workflow.
  final String name;

  /// The jobs it would make.
  final List<PlannedJob> jobs;

  /// The gated actions (`prod_release`, `push`, ...) its jobs would stop at
  /// for an approval: the gates the project has on.
  final List<String> gates;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$PlannedStageToJson(this);

  @override
  List<Object?> get props => [name, jobs, gates];
}

/// One job of a [PlannedStage] and where it would run.
@JsonSerializable(includeIfNull: false)
class PlannedJob extends Equatable {
  /// Creates a job.
  const new({
    required this.name,
    required this.engineOnly,
    required this.local,
    this.capabilities = const [],
    this.flavor,
    this.platform,
    this.runner,
    this.waitReason,
    this.narrowing = const [],
  });

  /// Reads a job from its JSON form.
  factory PlannedJob.fromJson(Map<String, dynamic> json) =>
      _$PlannedJobFromJson(json);

  /// Its name, as the run would name it.
  final String name;

  /// Its matrix cell's flavor.
  final String? flavor;

  /// Its matrix cell's platform.
  final String? platform;

  /// What a runner needs to run it (D-19).
  final List<String> capabilities;

  /// Whether only the engine may run it: it uploads, pushes, checks or waits
  /// for a gate (D-09).
  final bool engineOnly;

  /// Whether the engine itself can run it; it does when it has a slot.
  final bool local;

  /// The connected runner it would go to when the engine cannot run it or
  /// has no slot: the least loaded one that can.
  final String? runner;

  /// Why it would wait to start, for example "No connected runner can do
  /// ios-sign."; `null` when the engine or [runner] can run it.
  final String? waitReason;

  /// Why it needs a Mac for iOS where a Linux runner could have built it
  /// (ADR 0014): the job or the app uses something Linux iOS builds lack.
  final List<String> narrowing;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$PlannedJobToJson(this);

  @override
  List<Object?> get props => [
    name,
    flavor,
    platform,
    capabilities,
    engineOnly,
    local,
    runner,
    waitReason,
    narrowing,
  ];
}

/// A job a dispatch would leave out (its `if` is false), or one it cannot
/// plan, which the engine would refuse to dispatch ([blocks]).
@JsonSerializable(includeIfNull: false)
class SkippedJob extends Equatable {
  /// Creates the description.
  const new({
    required this.name,
    required this.stage,
    required this.reason,
    this.flavor,
    this.platform,
    this.blocks = false,
  });

  /// Reads a skipped job from its JSON form.
  factory SkippedJob.fromJson(Map<String, dynamic> json) =>
      _$SkippedJobFromJson(json);

  /// Its name, as the run would name it.
  final String name;

  /// The name of its stage.
  final String stage;

  /// Its matrix cell's flavor.
  final String? flavor;

  /// Its matrix cell's platform.
  final String? platform;

  /// Why it is left out, for example "no Firebase app id for dev", or why it
  /// cannot be planned.
  final String reason;

  /// Whether the engine would refuse the dispatch because of it.
  final bool blocks;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$SkippedJobToJson(this);

  @override
  List<Object?> get props => [name, stage, flavor, platform, reason, blocks];
}
