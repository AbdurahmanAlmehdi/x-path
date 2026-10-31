/// Which steps may run on a remote runner (D-09, D-05, D-07, D-13).
///
/// A job is leased to a runner as a whole, so a job with one step that only
/// the engine may run runs on the engine. The engine-only steps are the ones
/// that need a secret that stays on the engine machine or change something
/// outside it:
///
/// - `upload.*` (`upload.appStore`, `upload.play`, `upload.firebase`): store
///   uploads always run on the engine (D-09).
/// - `git.push`, `git.tag`, `git.releaseBranch`, `github.*`: they push to the
///   origin and talk to GitHub with the GitHub token, which never leaves the
///   engine (D-05, D-07).
/// - `gate`: approvals are the engine's state (D-13).
/// - `guard`: its checks read the credentials and ask the stores.
/// - `test`: it judges the run against the baseline and stores the run, both
///   in the engine's database (D-21); a runner has neither.
///
/// `shorebird.release` and `shorebird.patch` may run on a runner (ADR 0012):
/// the Shorebird `sb_api_*` key reaches it for the one job, like signing
/// material (`RunnerSecretGrants`).
///
/// What a runner may be handed is signing material, the Shorebird key and the
/// flavor's dart-define file (ADR 0016), and only for the one job it leases.
///
/// The built-in workflows keep the engine-only steps in jobs of their own
/// (ADR 0010), so their build jobs can go to a runner.
abstract final class RemoteStepPolicy {
  /// The step kinds that only the engine runs, besides every `upload.*` and
  /// `github.*` step.
  static const engineOnlyKinds = {
    'store.rollout',
    'shorebird.track',
    'git.push',
    'git.tag',
    'git.releaseBranch',
    'gate',
    'guard',
    'test',
  };

  /// The prefixes of the step kinds that only the engine runs.
  static const engineOnlyPrefixes = ['upload.', 'github.'];

  /// Whether only the engine may run a step of [kind].
  static bool isEngineOnly(String kind) =>
      engineOnlyKinds.contains(kind) || engineOnlyPrefixes.any(kind.startsWith);

  /// The kinds among [kinds] that only the engine runs, sorted, once each.
  static List<String> engineOnlyIn(Iterable<String> kinds) =>
      ({...kinds.where(isEngineOnly)}).toList()..sort();

  /// Whether a job made of steps of [kinds] may run on a remote runner.
  static bool canRunRemotely(Iterable<String> kinds) =>
      !kinds.any(isEngineOnly);
}
