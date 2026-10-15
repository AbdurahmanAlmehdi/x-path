import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/src/workflows/workflow_expression.dart';
import 'package:xp_repositories/src/workflows/workflow_outline.dart';

/// What a dispatch would start, worked out by the app before it asks the
/// engine: the jobs of each stage, where each would run, and the gates it
/// would stop at (the Dispatch sheet).
///
/// It reads the same workflow, project, runners, gates and credentials the
/// engine reads, but it is a preview: the engine plans the run when it is
/// dispatched, and places each job when its stage starts.
class DispatchPreview extends Equatable {
  /// Creates a preview.
  const new({
    required this.flavors,
    required this.platforms,
    required this.stages,
    this.currentVersion,
    this.version,
  });

  /// Works out what dispatching [workflow] with [request] would start in
  /// [project]: the flavors and platforms the engine would take by default,
  /// each stage's jobs (their matrix expanded, their `if` read the way the
  /// engine reads it), where each job would run among [runners], and which of
  /// the gates the workflow names are on in [gates].
  ///
  /// An `if` the app cannot read counts as true, so the preview shows rather
  /// than hides what may run.
  factory plan({
    required Project project,
    required WorkflowOutline workflow,
    required DispatchRequest request,
    required List<Runner> runners,
    required ProjectGates gates,
    required List<Credential> credentials,
  }) {
    final apps = project.profile.apps;
    final app =
        apps.where((app) => app.path == request.app).firstOrNull ??
        apps.firstOrNull;
    if (app == null) {
      return const DispatchPreview(flavors: [], platforms: [], stages: []);
    }
    final flavors = _flavors(app, request.flavors, workflow.locksProject);
    final platforms =
        request.platforms ??
        [if (app.hasAndroid) 'android', if (app.hasIos) 'ios'];
    final version = request.version ?? bumpVersion(app.version, request.bump);
    final scope = <String, Object?>{
      'app': {
        'name': app.name,
        'path': app.path,
        'hasIos': app.hasIos,
        'hasAndroid': app.hasAndroid,
        'version': app.version,
      },
      'project': {
        'id': project.id,
        'fullName': project.fullName,
        'baseBranch': project.defaultBaseBranch,
      },
      'ref': request.ref ?? project.defaultBaseBranch,
      'release': request.release,
      'version': version,
      'bump': (request.bump ?? VersionBump.keep).wire,
      'releaseVersion': request.releaseVersion,
      'platforms': platforms,
      'flavors': [for (final flavor in flavors) flavor.name],
      'inputs': {...workflow.inputDefaults, ...request.inputs},
    };
    final placer = _Placer(runners);
    final stages = <PreviewStage>[];
    for (final stage in workflow.stages) {
      placer.nextStage();
      final jobs = <PreviewJob>[];
      final gated = <String>{};
      for (final job in stage.jobs) {
        for (final cell in _cells(job, scope)) {
          final flavor = app.flavors
              .where((flavor) => flavor.name == cell['flavor'])
              .firstOrNull;
          final jobScope = {
            ...scope,
            'platform': ?cell['platform'],
            if (flavor != null)
              'flavor': _flavorScope(flavor, app, credentials),
          };
          if (!_holds(job.condition, jobScope)) continue;
          final steps = [
            for (final step in job.steps)
              if (_holds(step.condition, jobScope)) step,
          ];
          final capabilities = {
            ...job.capabilities,
            for (final step in steps)
              ..._capabilitiesOf(step.kind, cell['platform']),
          }.toList()..sort();
          final engineOnly = steps.any(
            (step) => step.gate != null || _isEngineOnly(step.kind),
          );
          for (final step in steps) {
            if (step.gate case final gate? when gates.gates[gate] ?? true) {
              gated.add(gate);
            }
          }
          final (runner, slot) = engineOnly
              ? (null, null)
              : placer.place(capabilities);
          jobs.add(
            PreviewJob(
              name: _name(job, cell, jobScope),
              flavor: cell['flavor'],
              platform: cell['platform'],
              capabilities: capabilities,
              engineOnly: engineOnly,
              runner: runner,
              slot: slot,
            ),
          );
        }
      }
      if (jobs.isNotEmpty) {
        stages.add(
          PreviewStage(name: stage.name, jobs: jobs, gates: gated.toList()),
        );
      }
    }
    return DispatchPreview(
      flavors: [for (final flavor in flavors) flavor.name],
      platforms: platforms,
      currentVersion: app.version,
      version: version,
      stages: stages,
    );
  }

  /// The flavors the run is for.
  final List<String> flavors;

  /// The platforms the run is for.
  final List<String> platforms;

  /// The pubspec version of the app at its last scan, `x.y.z+build`.
  final String? currentVersion;

  /// The version the run would release, `x.y.z`, when the app has one.
  final String? version;

  /// The stages that would make at least one job, in order.
  final List<PreviewStage> stages;

  /// How many jobs the dispatch would start.
  int get jobCount =>
      stages.fold(0, (count, stage) => count + stage.jobs.length);

  /// Every gated action the run would stop at for an approval.
  List<String> get gates =>
      {for (final stage in stages) ...stage.gates}.toList();

  @override
  List<Object?> get props => [
    flavors,
    platforms,
    currentVersion,
    version,
    stages,
  ];
}

/// One stage of a [DispatchPreview].
class PreviewStage extends Equatable {
  /// Creates a stage.
  const new({required this.name, required this.jobs, this.gates = const []});

  /// The stage's name in the workflow.
  final String name;

  /// The jobs it would make.
  final List<PreviewJob> jobs;

  /// The gated actions (`prod_release`, `push`, ...) its jobs would stop at
  /// for an approval.
  final List<String> gates;

  @override
  List<Object?> get props => [name, jobs, gates];
}

/// One job of a [PreviewStage] and where it would run.
class PreviewJob extends Equatable {
  /// Creates a job.
  const new({
    required this.name,
    required this.capabilities,
    required this.engineOnly,
    this.flavor,
    this.platform,
    this.runner,
    this.slot,
  });

  /// The job's name, as the engine would name it.
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

  /// The runner it would go to when the engine has no slot for it: the least
  /// loaded online runner that can run it. `null` when it runs on the engine.
  final Runner? runner;

  /// The slot of [runner] it would take, from 1.
  final int? slot;

  @override
  List<Object?> get props => [
    name,
    flavor,
    platform,
    capabilities,
    engineOnly,
    runner,
    slot,
  ];
}

/// The version `x.y.z` that [bump] makes of the pubspec version [current]
/// (`x.y.z+build`), or `null` when [current] is not one.
String? bumpVersion(String? current, VersionBump? bump) {
  final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(current ?? '');
  if (match == null) return null;
  final [major, minor, patch] = [
    for (var group = 1; group <= 3; group++) int.parse(match.group(group)!),
  ];
  return switch (bump ?? VersionBump.keep) {
    VersionBump.major => '${major + 1}.0.0',
    VersionBump.minor => '$major.${minor + 1}.0',
    VersionBump.patch => '$major.$minor.${patch + 1}',
    VersionBump.keep => '$major.$minor.$patch',
  };
}

List<FlavorProfile> _flavors(
  AppProfile app,
  List<String>? asked,
  bool locksProject,
) {
  if (asked != null) {
    return [
      for (final name in asked)
        ...app.flavors.where((flavor) => flavor.name == name),
    ];
  }
  if (app.flavors.length == 1) return app.flavors;
  return [
    for (final flavor in app.flavors)
      if (flavor.prod == locksProject) flavor,
  ];
}

/// The cells of [job]'s matrix, in the order of its axes and values.
List<Map<String, String>> _cells(JobOutline job, Map<String, Object?> scope) {
  var cells = <Map<String, String>>[{}];
  for (final MapEntry(key: axis, :value) in job.matrix.entries) {
    final values = switch (value) {
      final String template => _evaluate(() => renderTemplate(template, scope)),
      _ => value,
    };
    final items = values is List ? values.whereType<String>() : <String>[];
    cells = [
      for (final cell in cells)
        for (final item in items) {...cell, axis: item},
    ];
  }
  return cells;
}

Object? _evaluate(Object? Function() read) {
  try {
    return read();
  } on FormatException {
    return null;
  }
}

bool _holds(String? condition, Map<String, Object?> scope) {
  if (condition == null) return true;
  try {
    return isTruthy(evaluateExpression(condition, scope));
  } on FormatException {
    return true;
  }
}

String _name(
  JobOutline job,
  Map<String, String> cell,
  Map<String, Object?> scope,
) {
  final name = job.name == null
      ? null
      : _evaluate(() => renderTemplate(job.name!, scope));
  if (name is String && name.isNotEmpty) return name;
  return cell.isEmpty ? job.id : '${job.id} (${cell.values.join(', ')})';
}

Map<String, Object?> _flavorScope(
  FlavorProfile flavor,
  AppProfile app,
  List<Credential> credentials,
) => {
  'name': flavor.name,
  'implicit': flavor.implicit,
  'prod': flavor.prod,
  'shorebird': flavor.shorebird,
  'entrypoint': flavor.entrypoint,
  'iosBundleId': flavor.iosBundleId,
  'androidAppId': flavor.androidAppId,
  'shorebirdAppId': flavor.shorebirdAppId,
  'credentials': {
    for (final credential in credentials)
      if (credential.app == app.path && credential.flavor == flavor.name)
        credential.kind.wire: true,
  },
};

/// The step kinds only the engine runs, besides `upload.*` and `github.*`
/// (the engine's `RemoteStepPolicy`).
const _engineOnlyKinds = {
  'git.push',
  'git.tag',
  'git.releaseBranch',
  'gate',
  'guard',
  'test',
};

bool _isEngineOnly(String kind) =>
    _engineOnlyKinds.contains(kind) ||
    kind.startsWith('upload.') ||
    kind.startsWith('github.');

/// What a step of [kind] needs of a runner (the engine's step planners).
Set<String> _capabilitiesOf(String kind, String? platform) => switch (kind) {
  'build.android' => {'android', 'flutter'},
  'build.ios' => {'ios-sign', 'flutter'},
  'ios.stripAndReexport' || 'upload.appStore' => {'ios-sign'},
  'shorebird.release' || 'shorebird.patch' => {
    'flutter',
    if (platform == 'ios') 'ios-sign' else 'android',
  },
  'test' || 'analyze' => {'flutter'},
  _ => const {},
};

/// Picks runners the way the engine's scheduler picks a remote one: the
/// least loaded online runner (running jobs per slot) that can do what the
/// job needs and has a free slot, the oldest first on a tie. The jobs of one
/// stage start together, so each takes a slot.
class _Placer {
  new(List<Runner> runners)
    : _runners = [
        for (final runner in runners)
          if (runner.status == RunnerStatus.online && runner.slots > 0) runner,
      ];

  final List<Runner> _runners;
  final _taken = <String, int>{};

  void nextStage() => _taken.clear();

  (Runner?, int?) place(List<String> capabilities) {
    Runner? best;
    var bestLoad = 0.0;
    for (final runner in _runners) {
      if (!capabilities.every(runner.capabilities.contains)) continue;
      final running = runner.jobIds.length + (_taken[runner.id] ?? 0);
      if (running >= runner.slots) continue;
      final load = running / runner.slots;
      if (best == null || load < bestLoad) {
        best = runner;
        bestLoad = load;
      }
    }
    if (best == null) return (null, null);
    final slot = best.jobIds.length + (_taken[best.id] ?? 0) + 1;
    _taken[best.id] = (_taken[best.id] ?? 0) + 1;
    return (best, slot);
  }
}
