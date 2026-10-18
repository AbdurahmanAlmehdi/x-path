import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_exceptions.dart';
import 'package:xp_engine/src/credentials/credential_material.dart';
import 'package:xp_engine/src/credentials/credential_verifier.dart';
import 'package:xp_engine/src/git/github_client.dart';
import 'package:xp_engine/src/process/output_masker.dart';
import 'package:xp_engine/src/secrets/secret_store.dart';
import 'package:xp_engine/src/tokens/device_token.dart';

/// The token of the GitHub CLI (`gh auth token`) on the engine machine.
abstract interface class GitHubCliToken {
  /// Reads it, without storing it anywhere.
  ///
  /// Throws a [GitHubCliTokenException] when `gh` is missing, not logged in
  /// or prints no token.
  Future<String> read();
}

/// `gh` gave no token. The message never contains one.
class GitHubCliTokenException implements Exception {
  /// Creates the exception.
  const new(this.message, {this.fix});

  /// What went wrong.
  final String message;

  /// What to do about it.
  final String? fix;

  @override
  String toString() => 'GitHubCliTokenException: $message';
}

/// A device token that may not change the GitHub token tried to.
class GitHubTokenForbiddenException implements Exception {
  /// Creates the exception.
  const new(this.message);

  /// What the token's kind may not do.
  final String message;

  @override
  String toString() => 'GitHubTokenForbiddenException: $message';
}

/// The GitHub token of the engine: one, shared by every project, under
/// [githubTokenSecretKey] (where `xpd secrets import-gh` and the deprecated
/// per-flavor save of a `github` token put it too). It is not a named
/// credential (ADR 0013).
///
/// A token is checked with GitHub before it is stored, as every credential
/// is; nothing here returns or logs it, and the [OutputMasker] learns it as
/// soon as the engine sees it. Only the app and `xp` may change it (an MCP
/// client may not hand the engine another identity, D-13).
class GitHubTokenService {
  /// Creates the service. `verifier` checks `github` credentials.
  const new({
    required this._secrets,
    required this._verifier,
    required this._cli,
    required this._masker,
  });

  final SecretStore _secrets;
  final CredentialVerifier _verifier;
  final GitHubCliToken _cli;
  final OutputMasker _masker;

  /// Whether there is a token and what GitHub says of it now.
  ///
  /// Throws a `SecretsLockedException` when the secrets cannot be read.
  Future<GitHubTokenStatus> status() async {
    final token = await _secrets.read(githubTokenSecretKey);
    if (token == null || token.isEmpty) {
      return const GitHubTokenStatus(stored: false);
    }
    _masker.add(token);
    final result = await _check(token);
    return GitHubTokenStatus(
      stored: true,
      status: result.status,
      login: result.account,
      message: result.message,
      fix: result.fix,
    );
  }

  /// Checks [token] with GitHub and stores it when GitHub accepts it.
  ///
  /// Throws a [GitHubTokenForbiddenException] for a token kind [by] that may
  /// not, a [CredentialRejectedException] when GitHub refused [token] and a
  /// [CredentialUnreachableException] when it could not be checked; nothing
  /// is stored then.
  Future<GitHubTokenStatus> save(
    String token, {
    required DeviceToken by,
  }) async {
    _requireOwner(by, 'set the GitHub token');
    return await _store(token.trim());
  }

  /// Takes the token of the GitHub CLI, then stores it as [save] does.
  ///
  /// Throws a [CredentialRejectedException] when `gh` gave no token, besides
  /// what [save] throws.
  Future<GitHubTokenStatus> importFromCli({required DeviceToken by}) async {
    _requireOwner(by, 'import the GitHub token');
    final String token;
    try {
      token = await _cli.read();
    } on GitHubCliTokenException catch (error) {
      throw CredentialRejectedException(error.message, fix: error.fix);
    }
    return await _store(token);
  }

  /// Forgets the token. Projects cannot be added or pushed to afterwards.
  Future<void> clear({required DeviceToken by}) async {
    _requireOwner(by, 'remove the GitHub token');
    await _secrets.delete(githubTokenSecretKey);
  }

  Future<GitHubTokenStatus> _store(String token) async {
    if (token.isEmpty) {
      throw const CredentialRejectedException(
        'The GitHub token is empty.',
        fix: 'Paste a personal access token with the repo scope.',
      );
    }
    _masker.add(token);
    final result = await _check(token);
    switch (result.status) {
      case CredentialStatus.verified:
        await _secrets.write(githubTokenSecretKey, token);
        return GitHubTokenStatus(
          stored: true,
          status: CredentialStatus.verified,
          login: result.account,
        );
      case CredentialStatus.rejected:
        throw CredentialRejectedException(result.message!, fix: result.fix);
      case CredentialStatus.unverified:
      case CredentialStatus.unreachable:
        throw CredentialUnreachableException(
          result.message ?? 'The GitHub token could not be checked.',
          fix: result.fix,
        );
    }
  }

  Future<VerificationResult> _check(String token) => _verifier.verify(
    TokenMaterial(CredentialKind.github, token),
    const CredentialTarget(),
  );

  static void _requireOwner(DeviceToken by, String what) {
    if (by.kind != DeviceTokenKind.app && by.kind != DeviceTokenKind.cli) {
      throw GitHubTokenForbiddenException(
        'A ${by.kind.name} token cannot $what: only the app or `xp` do.',
      );
    }
  }
}

/// A [GitHubCliToken] that answers [token], or throws [error].
class FakeGitHubCliToken implements GitHubCliToken {
  /// Creates the fake.
  new({this.token = 'gho_cli', this.error});

  /// What [read] answers.
  String token;

  /// What [read] throws, if anything.
  GitHubCliTokenException? error;

  /// How often [read] was called.
  int reads = 0;

  @override
  Future<String> read() async {
    reads++;
    if (error case final error?) throw error;
    return token;
  }
}
