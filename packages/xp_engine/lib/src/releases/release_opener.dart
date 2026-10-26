import 'package:xp_engine/src/steps/step.dart';

/// The planned steps of one flavor of a run that makes a release.
class FlavorSteps {
  /// Creates the description.
  const new({required this.flavor, required this.steps});

  /// The flavor.
  final String flavor;

  /// Every step of every job of the run for the flavor, as planned. The
  /// uploads among them say which stores the release goes to.
  final List<StepPlan> steps;
}

/// A dispatch that makes releases: one per flavor.
class ReleaseOpening {
  /// Creates the description.
  const new({
    required this.projectId,
    required this.appPath,
    required this.runId,
    required this.version,
    required this.build,
    required this.baseBranch,
    required this.storeCountry,
    required this.flavors,
  });

  /// The project.
  final String projectId;

  /// The path of the app.
  final String appPath;

  /// The run that builds them.
  final String runId;

  /// The marketing version, `x.y.z`.
  final String version;

  /// The build number allocated for the run (D-11).
  final int build;

  /// The branch the release pull requests merge into.
  final String baseBranch;

  /// The App Store storefront of the app.
  final String storeCountry;

  /// The flavors of the run.
  final List<FlavorSteps> flavors;
}

/// What a run of an existing release does.
enum ReleaseRunKind {
  /// It builds and uploads a new build of the version (after a rejection).
  build,

  /// It merges the pull request.
  merge,

  /// It changes the rollout in a store (U7a).
  rollout,
}

/// What a dispatch tells the releases. `ReleaseService` implements it; the
/// `WorkflowDispatcher` calls it.
abstract interface class ReleaseOpener {
  /// Creates a draft release for each flavor of [opening] and returns the
  /// ids by flavor. A release of the same flavor and version that never got
  /// as far as a store is abandoned: this one replaces it.
  Future<Map<String, String>> open(ReleaseOpening opening);

  /// Records that the run [runId] works on the release [releaseId] of the
  /// project: a new [ReleaseRunKind.build] (with its [build] number, which
  /// takes a rejected release back to `building`) or the
  /// [ReleaseRunKind.merge] of its pull request.
  ///
  /// Throws a `ReleaseNotFoundException` if the project has no such release
  /// and a `ReleaseStateException` if it is not in the state the run needs.
  Future<void> attach({
    required String releaseId,
    required String projectId,
    required ReleaseRunKind kind,
    required String runId,
    int? build,
  });
}
