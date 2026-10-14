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
/// - `shorebird.release`, `shorebird.patch`: they publish with the Shorebird
///   API key, which is not signing material, so it stays on the engine too
///   (D-07, D-09).
///
/// What a runner may be handed is signing material only, and only for the
/// one job it leases (`SigningSecretGrants`).
///
/// The built-in workflows put a `guard` or an upload in the same job as the
/// build, so those jobs run on the engine. A workflow that builds on a runner
/// splits the engine-only steps into a job of their own.
abstract final class RemoteStepPolicy {
  /// The step kinds that only the engine runs, besides every `upload.*` and
  /// `github.*` step.
  static const engineOnlyKinds = {
    'git.push',
    'git.tag',
    'git.releaseBranch',
    'gate',
    'guard',
    'shorebird.release',
    'shorebird.patch',
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
