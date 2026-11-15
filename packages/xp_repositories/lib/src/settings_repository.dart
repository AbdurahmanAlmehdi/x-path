import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/src/session/engine_session.dart';

/// What the settings show of the engine of an [EngineSession]: its version,
/// its GitHub token (one, shared by every project, which adding a project
/// needs), the tokens it makes for `xp` and agents, and the way into its
/// web dashboard.
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

  /// Makes a token called [name] for `xp` or `xp mcp` ([kind]), with its
  /// secret, shown this once.
  Future<CreatedToken> createToken({
    required String name,
    required DeviceTokenKind kind,
  }) => _session.call((client) => client.createToken(name: name, kind: kind));

  /// The page that signs this app's own person in to the engine's web
  /// dashboard, with a new one-time sign-in code in it (D9).
  Future<Uri> dashboardSignInUrl() =>
      _session.call((client) => client.dashboardSignInUrl());
}
