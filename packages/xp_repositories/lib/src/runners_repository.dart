import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/src/session/engine_session.dart';
import 'package:xp_repositories/src/snapshot.dart';

/// The runners of the engine of an [EngineSession].
class RunnersRepository {
  /// Creates the repository.
  const new(this._session);

  final EngineSession _session;

  /// Every runner, oldest first, kept up to date by the runner events and by
  /// jobs starting and ending (which change what a runner is busy with).
  Stream<Snapshot<List<Runner>>> watchRunners() => _session.watch(
    key: 'runners',
    fetch: (client) => client.listRunners(),
    encode: (runners) => [for (final runner in runners) runner.toJson()],
    decode: (json) => [
      for (final runner in json! as List<dynamic>)
        Runner.fromJson(runner as Map<String, dynamic>),
    ],
    refreshOn: (event) =>
        event is RunnerPaired ||
        event is RunnerConnected ||
        event is RunnerDisconnected ||
        event is RunnerRevoked ||
        event is RunnerCapabilitiesChanged ||
        event is RunnerLeaseLost ||
        event is JobStateChanged,
  );

  /// Makes a single-use pairing token for a runner called [name].
  Future<PairingToken> createPairingToken(String name) =>
      _session.call((client) => client.createPairingToken(name));

  /// The address runners reach the engine at.
  Future<RunnerUrl> runnerUrl() =>
      _session.call((client) => client.runnerUrl());

  /// Sets the runner URL to [url], or clears it for `null`.
  Future<RunnerUrl> setRunnerUrl(String? url) =>
      _session.call((client) => client.setRunnerUrl(url));

  /// Revokes [id].
  Future<Runner> revoke(String id) =>
      _session.call((client) => client.revokeRunner(id));
}
