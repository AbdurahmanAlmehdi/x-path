import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/src/session/engine_session.dart';

/// What the settings show of the engine of an [EngineSession]: its version
/// and its GitHub token (one, shared by every project, which adding a
/// project needs).
class SettingsRepository {
  /// Creates the repository.
  const new(this._session);

  final EngineSession _session;

  /// The engine's version and API version (`GET /version`).
  Future<VersionResponse> engineVersion() =>
      _session.call((client) => client.version());

  /// Whether the engine has its GitHub token, and who GitHub says it
  /// belongs to.
  Future<GitHubTokenStatus> gitHubToken() =>
      _session.call((client) => client.getGitHubToken());

  /// Checks [token] with GitHub, then stores it on the engine.
  Future<GitHubTokenStatus> setGitHubToken(String token) =>
      _session.call((client) => client.setGitHubToken(token));

  /// Takes the token of the GitHub CLI of the engine machine.
  Future<GitHubTokenStatus> importGitHubToken() =>
      _session.call((client) => client.importGitHubToken());

  /// Forgets the engine's GitHub token.
  Future<void> clearGitHubToken() =>
      _session.call((client) => client.deleteGitHubToken());
}
