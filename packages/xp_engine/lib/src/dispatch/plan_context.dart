import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_record.dart';
import 'package:xp_engine/src/git/git_models.dart';
import 'package:xp_engine/src/projects/project_record.dart';
import 'package:xp_engine/src/versioning/app_version.dart';
import 'package:xp_engine/src/versioning/release_model.dart';
import 'package:xp_engine/src/versioning/release_worktree.dart';
import 'package:xp_engine/src/workflows/workflow_definition.dart';
import 'package:xp_engine/src/workflows/workflow_exceptions.dart';

/// The directory `GitService.createWorktree` gives the worktree [name] of
/// [mirror]. The steps of a job need it before the worktree exists, so the
/// engine says where it will be, and `git.checkout` checks it.
typedef WorktreeLocator = String Function(GitMirror mirror, String name);

/// What a dispatch decided, the same for every job of the run.
class RunContext {
  /// Creates the context.
  const new({
    required this.runId,
    required this.project,
    required this.app,
    required this.flavors,
    required this.platforms,
    required this.ref,
    required this.sha,
    required this.mirror,
    required this.model,
    required this.worktreeAt,
    required this.inputs,
    required this.bump,
    this.version,
    this.build,
    this.current,
    this.releaseVersion,
    this.patch,
    this.release,
  });

  /// The run.
  final String runId;

  /// The project.
  final ProjectRecord project;

  /// The app being run.
  final AppProfile app;

  /// The flavors selected for the run, in the order of the profile.
  final List<FlavorProfile> flavors;

  /// `android` and `ios`.
  final List<String> platforms;

  /// The ref that was asked for.
  final String ref;

  /// The commit it resolved to, in full.
  final String sha;

  /// The mirror the commit is in.
  final GitMirror mirror;

  /// The branch and tag names of the project.
  final ReleaseModel model;

  /// Where the worktree of a job will be.
  final WorktreeLocator worktreeAt;

  /// The inputs of the workflow: the defaults, then what the dispatch set.
  final Map<String, Object?> inputs;

  /// How the version is bumped: `major`, `minor`, `patch` or `keep`.
  final String bump;

  /// The version this run releases: the version of the app bumped, or the
  /// version asked for, with the build number allocated at dispatch (D-11).
  /// `null` when the workflow does not bump.
  final AppVersion? version;

  /// The build number allocated at dispatch.
  final int? build;

  /// The version the app has at [sha], as its pubspec says.
  final AppVersion? current;

  /// For a patch, the release it applies to.
  final AppVersion? releaseVersion;

  /// For a patch, its number: one more than the patches of that release.
  final int? patch;

  /// The release (`rel_...`) this run builds again or merges, when the
  /// dispatch named one. A workflow reads it as `release`.
  final String? release;

  /// The variables a workflow reads that do not depend on the job.
  Map<String, Object?> get scope => {
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
    'ref': ref,
    'sha': sha,
    'release': release,
    'version': version == null ? null : '${version!.name}',
    'build': build,
    'bump': bump,
    'releaseVersion': releaseVersion == null ? null : '$releaseVersion',
    'patch': patch,
    'platforms': platforms,
    'flavors': [for (final flavor in flavors) flavor.name],
    'inputs': inputs,
  };

  /// The `version` the steps of the run use: the one released, else the one
  /// being patched, else the one the app has.
  AppVersion? get stepVersion => releaseVersion ?? version ?? current;
}

/// What the planner of one job knows: the run, the cell of the matrix, and
/// where the job's worktree is.
class JobContext {
  /// Creates the context.
  const new({
    required this.run,
    required this.jobId,
    required this.worktree,
    required this.flavorValue,
    this.platform,
    this.flavor,
    this.credentialFlavor,
    this.credentials = const [],
    this.commitSources = const {},
  });

  /// The run.
  final RunContext run;

  /// The id the job is made with. Its worktree is named after it.
  final String jobId;

  /// The worktree of the job, as every step of it sees it.
  final ReleaseWorktree worktree;

  /// The matrix cell's platform.
  final String? platform;

  /// The matrix cell's flavor.
  final FlavorProfile? flavor;

  /// `flavor` as workflows read it.
  final Map<String, Object?>? flavorValue;

  /// The flavor as the credentials know it.
  final CredentialFlavor? credentialFlavor;

  /// The credentials the flavor has.
  final List<AssignedCredential> credentials;

  /// The job (its id as planned) that `commitFrom` names, by the id the
  /// workflow gives it.
  final Map<String, String> commitSources;

  /// The variables a workflow reads in this job.
  Map<String, Object?> get scope => {
    ...run.scope,
    'platform': ?platform,
    'flavor': ?flavorValue,
  };

  /// The credential of [kind], if the flavor has one.
  AssignedCredential? credential(CredentialKind kind) =>
      credentials.where((record) => record.kind == kind).firstOrNull;
}

/// The flavor as a workflow reads it (`flavor.name`, `flavor.prod`,
/// `flavor.firebaseAppId.android`, `flavor.credentials.play_sa`, ...).
Map<String, Object?> flavorScope(
  FlavorProfile flavor,
  Iterable<AssignedCredential> credentials,
) => {
  'name': flavor.name,
  'implicit': flavor.implicit,
  'prod': flavor.prod,
  'shorebird': flavor.shorebird,
  'entrypoint': flavor.entrypoint,
  'iosBundleId': flavor.iosBundleId,
  'androidAppId': flavor.androidAppId,
  'shorebirdAppId': flavor.shorebirdAppId,
  'firebaseAppId': {...?flavor.firebaseAppId},
  'appleAppId': flavor.appleAppId,
  'credentials': {
    for (final credential in credentials) credential.kind.wire: true,
  },
};

/// A step of a job, with the values it was given, as its planner reads them.
class StepPlanning {
  /// Creates the view.
  const new({
    required this.kind,
    required this.job,
    required this.values,
    required this.position,
  });

  /// The step type.
  final String kind;

  /// The job the step is in.
  final JobContext job;

  /// The values of `with`, with their placeholders resolved.
  final Map<String, Object?> values;

  /// Where the step starts in the document.
  final SourcePosition position;

  /// Stops the dispatch: this step cannot be planned. [hint] says what to do
  /// about it, and [details] what a client can act on.
  Never fail(String message, {String? hint, Map<String, Object?>? details}) =>
      throw DispatchException(
        'Line ${position.line}, $kind: $message',
        hint: hint,
        details: details,
      );

  /// The string at [key], or `null` if the step was not given it.
  String? text(String key) {
    final value = values[key];
    if (value == null) return null;
    if (value is String) return value;
    return fail('"$key" must be a string.');
  }

  /// The string at [key].
  String requireText(String key) =>
      text(key) ?? fail('"$key" is needed: give it under "with".');

  /// The boolean at [key], or [otherwise] if the step was not given it.
  bool flag(String key, {bool otherwise = false}) {
    final value = values[key];
    if (value == null) return otherwise;
    if (value is bool) return value;
    return fail('"$key" must be true or false.');
  }

  /// The list of strings at [key]; empty if the step was not given it.
  List<String> list(String key) {
    final value = values[key];
    if (value == null) return const [];
    if (value is List && value.every((item) => item is String)) {
      return value.cast<String>();
    }
    return fail('"$key" must be a list of strings.');
  }

  /// The number at [key], or `null`.
  num? number(String key) {
    final value = values[key];
    if (value == null) return null;
    if (value is num) return value;
    return fail('"$key" must be a number.');
  }

  /// The map of strings to strings at [key]; empty if not given.
  Map<String, String> strings(String key) {
    final value = values[key];
    if (value == null) return const {};
    if (value is Map && value.values.every((item) => item is String)) {
      return value.cast<String, String>();
    }
    return fail('"$key" must be a mapping of strings.');
  }

  /// The value at [key] as it is.
  Object? raw(String key) => values[key];
}
